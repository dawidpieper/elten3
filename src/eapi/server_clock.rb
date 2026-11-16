module EltenAPI
  module ServerClock
    REFRESH_AFTER = 300.0
    RETRY_AFTER = 60.0
    TIMEOUT = 5.0
    Sample = Struct.new(:time, :age, :rtt, :uncertainty, keyword_init: true)
    Request = Struct.new(:key, :started_at, :cancellation)
    private_constant :REFRESH_AFTER, :RETRY_AFTER, :TIMEOUT, :Request

    @mutex = Mutex.new
    @enabled = false

    class << self
      def now
        @mutex.synchronize do
          Time.at(@anchor[0] + monotonic_time - @anchor[1]) if available?
        end
      end

      def synchronized?
        @mutex.synchronize { available? }
      end

      def sample
        @mutex.synchronize do
          return nil unless available?
          tick = monotonic_time
          Sample.new(time: Time.at(@anchor[0] + tick - @anchor[1]).freeze,
            age: tick - @anchor[2], rtt: @anchor[3], uncertainty: @anchor[3] / 2.0 + 1.0).freeze
        end
      end

      private

      def available?
        @anchor != nil && @key == session_key
      end

      def session_key
        return nil unless defined?(Session) && Session.logged?
        [Session.name.to_s, Session.token.to_s]
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def start
        @mutex.synchronize { @enabled = true }
      end

      def stop
        cancellation = @mutex.synchronize do
          @enabled = false
          @key = @anchor = nil
          current = @request
          @request = nil
          @next_attempt_at = 0.0
          current&.cancellation
        end
        cancellation&.cancel
      end

      def update(key)
        cancellation = nil
        request = @mutex.synchronize do
          return unless @enabled
          tick = monotonic_time
          if @key != key
            cancellation = @request&.cancellation
            @key = key&.map { |value| value.to_s.dup.freeze }&.freeze
            @anchor = @request = nil
            @next_attempt_at = 0.0
          end
          if @request != nil && tick - @request.started_at >= TIMEOUT
            cancellation = @request.cancellation
            @request = nil
            @next_attempt_at = tick + RETRY_AFTER
          end
          if @key != nil && @request == nil && tick >= @next_attempt_at.to_f
            @request = Request.new(@key, tick, Tasks::CancellationToken.new)
          end
        end
        cancellation&.cancel
        request_sample(request) if request != nil
      end

      def request_sample(request)
        return if request.cancellation.cancelled?
        path = EltenLink::Client.append_query("/api/v1/system/time",
          {"name" => request.key[0], "token" => request.key[1]})
        EltenLink::Client.new.e_json_request("GET", path, {}, cancellation_token: request.cancellation) do |answer, _data|
          received_at = monotonic_time
          time = begin
            response = JSON.parse(answer) if answer.is_a?(String)
            if response.is_a?(Hash) && EltenLink::Client.truthy?(response["success"])
              EltenLink::System.__send__(:server_time_from_data, response["data"])
            end
          rescue JSON::ParserError, EltenLink::Error
            nil
          end
          complete(request, time, received_at)
        end
      rescue StandardError
        complete(request, nil, monotonic_time)
        raise
      end

      def complete(request, time, received_at)
        @mutex.synchronize do
          return unless @enabled && @request.equal?(request) && @key == session_key
          @request = nil
          rtt = received_at - request.started_at
          if time != nil && rtt >= 0 && rtt < TIMEOUT
            @anchor = [time.to_f, request.started_at + rtt / 2.0, received_at, rtt].freeze
            @next_attempt_at = received_at + REFRESH_AFTER
          else
            @next_attempt_at = received_at + RETRY_AFTER
          end
        end
      end
    end
  end
end
