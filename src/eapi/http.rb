# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "base64"
require "http/2"
require "io/wait"
require "json"
require "monitor"
require "openssl"
require "securerandom"
require "timeout"
require "time"
require "uri"

module EltenAPI
  class ERDownloadProgress
    attr_reader :downloaded, :total, :percent

    def initialize(downloaded, total)
      @downloaded = downloaded.to_i
      @total = total.to_i
      @percent = @total > 0 ? (@downloaded.to_f / @total.to_f * 100.0).floor : 0
    end
  end

  module HTTPClient
    class Connection < HTTP2::Client
      CANCELLED_STREAM_TTL = 15.0
      MAX_CANCELLED_STREAMS = 128

      class CancelledStream
        def <<(_frame)
        end
      end

      CANCELLED_STREAM = CancelledStream.new.freeze

      def initialize(settings = {})
        @cancelled_streams = {}
        super
        on(:frame_received) do |frame|
          clear_cancelled_frame
          prune_cancelled_streams
          id = frame[:stream]
          if @cancelled_streams.key?(id) && !@streams.key?(id) && frame[:type] != :push_promise
            @cancelled_frame_id = id
            @streams[id] = CANCELLED_STREAM
          end
        end
      end

      def receive(data)
        super
      ensure
        clear_cancelled_frame
      end

      private

      def activate_stream(id:, **args)
        stream = super
        stream.once(:close) do
          if stream.closed == :local_rst
            prune_cancelled_streams
            @cancelled_streams.shift while @cancelled_streams.size >= MAX_CANCELLED_STREAMS
            @cancelled_streams[id] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
        stream
      end

      def clear_cancelled_frame
        @streams.delete(@cancelled_frame_id) if @cancelled_frame_id && @streams[@cancelled_frame_id].equal?(CANCELLED_STREAM)
        @cancelled_frame_id = nil
      end

      def prune_cancelled_streams
        cutoff = Process.clock_gettime(Process::CLOCK_MONOTONIC) - CANCELLED_STREAM_TTL
        while (entry = @cancelled_streams.first) && entry[1] <= cutoff
          @cancelled_streams.shift
        end
      end
    end

    private_constant :Connection

    HOST = "api.elten.link".freeze
    PORT = 443
    HTTP2_ALPN = "h2".freeze
    CONNECT_TIMEOUT = 8
    READ_TIMEOUT = 20
    STALE_AFTER = 20
    ACTIVE_STALE_AFTER = 45
    MAX_REDIRECTS = 5
    TRANSPORT_SESSION_ALGORITHM = "AES-256-GCM-SESSION"
    REALTIME_STREAM_ALGORITHM = "AES-256-GCM-STREAM"
    TRANSPORT_SESSION_INFO = "elten transport session v1".b
    TRANSPORT_SESSION_NONCE_BYTES = 32
    TRANSPORT_SESSION_KEY_BYTES = 32
    TRANSPORT_SESSION_SECRET_BYTES = TRANSPORT_SESSION_KEY_BYTES * 3
    TRANSPORT_SESSION_CLIENT_TTL = 300

    @conn_mutex = Mutex.new
    @http_mutex = Monitor.new
    @ssl_mutex = Mutex.new
    @pending_mutex = Mutex.new
    @transport_session_mutex = Mutex.new

    class << self
      def init(force=false)
        connect_http2(force: force, reconnect_if_stale: false)
      end

      def close
        close_http2(true)
      end

      def ejrequest(method, path, params, data=nil, encrypted: nil, headers: nil, transport_session_retry: true, cancellation_token: nil, protocol: nil, &block)
        if protocol == :http1 || (protocol == nil && disable_http2?)
          return ejrequest_http1(
            method, path, params, data,
            encrypted: encrypted,
            headers: headers,
            transport_session_retry: transport_session_retry,
            cancellation_token: cancellation_token,
            &block
          )
        end
        params = {} unless params.is_a?(Hash)
        headers = headers.is_a?(Hash) ? headers : {}
        Thread.new do
          Thread.current.report_on_exception = false
          attempts = 0
          pending_token = nil
          request_generation = nil
          begin
            attempts += 1
            raise_if_cancelled!(cancellation_token, data)
            pending_token = nil
            request_generation = nil
            raise "HTTP/2 unavailable" unless ensure_http2_connection
            encrypted_request = encrypted.nil? ? encrypted_transport? : encrypted == true
            json, decrypt_context = json_request_body(params, encrypted_request)
            body = "".b
            response_headers = {}
            http_mutex.synchronize do
              stream = nil
              connection_mutex.synchronize do
                request_generation = @connection_generation
                http = @http
                ssl = @ssl
                raise "HTTP/2 connection changed" unless connection_current?(request_generation, ssl, http)

                stream = http.new_stream
                pending_token = register_pending_request(request_generation, stream, cancellation_token) do
                  safe_call(block, :error, data)
                end
              end
              if cancelled?(data, cancellation_token)
                fail_pending_request(pending_token)
                next
              end
              head = {
                ":scheme" => "https",
                ":authority" => "api.elten.link:443",
                ":path" => path,
                ":method" => method.to_s.upcase,
                "user-agent" => user_agent,
                "accept-encoding" => "zstd, identity",
                "content-type" => "application/json",
                "content-length" => json.bytesize.to_s
              }
              headers.each do |key, value|
                next if key.to_s.empty? || value == nil
                head[key.to_s.downcase] = value.to_s
              end
              stream.on(:headers) do |h|
                response_headers = h.to_h
                data["headers"] = h if data.is_a?(Hash)
              end
              stream.on(:data) { |chunk| body << chunk.to_s.b }
              stream.on(:close) do
                next unless take_pending_request(pending_token)

                begin
                  @last_response = Time.now.to_i
                  touch_connection_activity(request_generation)
                  decoded = decode_body(body, response_headers)
                  decoded = decrypt_json_response(decoded, decrypt_context) if decrypt_context != nil
                  safe_call(block, decoded, data)
                rescue Exception => e
                  if transport_session_retry && decrypt_context.is_a?(Hash) && decrypt_context[:mode] == :session
                    log_warning("Encrypted session request failed, retrying with RSA: #{format_exception(e)}")
                    clear_transport_session(decrypt_context[:session_id])
                    ejrequest(method, path, params, data, encrypted: true, headers: headers, transport_session_retry: false, cancellation_token: cancellation_token, protocol: :http2, &block)
                    next
                  end
                  log_error("JSON body error: #{format_exception(e)}")
                  safe_call(block, :error, data)
                end
              end
              stream.headers(head, end_stream: false)
              until json.empty?
                chunk = json.slice!(0...4096)
                stream.data(chunk, end_stream: json.empty?)
              end
            end
          rescue Exception => e
            if cancelled?(data, cancellation_token)
              if pending_token != nil
                fail_pending_request(pending_token)
              else
                safe_call(block, :error, data)
              end
              next
            end
            log_error("JSON request error: #{format_exception(e)}")
            close_http2(false, request_generation, reason: "request setup failed") if request_generation != nil
            if pending_token != nil
              fail_pending_request(pending_token)
            elsif attempts < 2
              retry
            else
              safe_call(block, :error, data)
            end
          end
        end
      end

      def ejrequest_http1(method, path, params, data=nil, encrypted: nil, headers: nil, transport_session_retry: true, cancellation_token: nil, &block)
        params = {} unless params.is_a?(Hash)
        headers = headers.is_a?(Hash) ? headers : {}
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            raise_if_cancelled!(cancellation_token, data)
            encrypted_request = encrypted.nil? ? encrypted_transport? : encrypted == true
            json, decrypt_context = json_request_body(params, encrypted_request)
            request_headers = {
              "Content-Type" => "application/json",
              "Accept-Encoding" => "zstd, identity"
            }.merge(headers)
            response = readurl_sync(
              "https://#{HOST}:#{PORT}#{path}",
              method,
              json,
              request_headers,
              data,
              cancellation_token: cancellation_token
            )
            body = response.is_a?(Hash) ? response[:body] : :error
            if body == :error
              safe_call(block, :error, data)
              next
            end
            data["headers"] = response[:headers] if data.is_a?(Hash)
            begin
              body = decrypt_json_response(body, decrypt_context) if decrypt_context != nil
              safe_call(block, body, data)
            rescue Exception => e
              if transport_session_retry && decrypt_context.is_a?(Hash) && decrypt_context[:mode] == :session
                log_warning("Encrypted session request failed, retrying with RSA: #{format_exception(e)}")
                clear_transport_session(decrypt_context[:session_id])
                ejrequest_http1(
                  method, path, params, data,
                  encrypted: true,
                  headers: headers,
                  transport_session_retry: false,
                  cancellation_token: cancellation_token,
                  &block
                )
                next
              end
              raise
            end
          rescue Exception => e
            log_error("HTTP/1.1 JSON request error: #{format_exception(e)}") unless cancelled?(data, cancellation_token)
            safe_call(block, :error, data)
          end
        end
      end

      def ejstream(path, params, data=nil, cancellation_token: nil, transport_session_retry: true, &block)
        params = {} unless params.is_a?(Hash)
        Thread.new do
          Thread.current.report_on_exception = false
          pending_token = nil
          generation = nil
          begin
            raise_if_cancelled!(cancellation_token, data)
            raise "HTTP/2 disabled" if disable_http2?
            raise "HTTP/2 unavailable" unless ensure_http2_connection
            json, context = json_request_body(params, true)
            unless context.is_a?(Hash) && context[:mode] == :session
              raise "Encrypted transport session unavailable" unless transport_session_retry

              ejrequest(
                "GET", "/api/v1/system/time", {}, data,
                encrypted: true, protocol: :http2, transport_session_retry: false,
                cancellation_token: cancellation_token
              ) do |_answer, _request_data|
                ejstream(
                  path, params, data, cancellation_token: cancellation_token,
                  transport_session_retry: false, &block
                )
              end
              next
            end

            buffer = +"".b
            sequence = 0
            status = 0
            response_headers = {}
            failure_reason = nil
            http_mutex.synchronize do
              stream = nil
              connection_mutex.synchronize do
                generation = @connection_generation
                http = @http
                ssl = @ssl
                raise "HTTP/2 connection changed" unless connection_current?(generation, ssl, http)

                stream = http.new_stream
                pending_token = register_pending_request(generation, stream, cancellation_token, persistent: true) do
                  reason = failure_reason || realtime_stream_http_error(status, buffer, response_headers, context, data)
                  set_realtime_stream_error(data, reason)
                  result = status.between?(200, 299) && failure_reason == nil ? :closed : :error
                  safe_call(block, result, data)
                end
              end
              if cancelled?(data, cancellation_token)
                fail_pending_request(pending_token)
                next
              end
              stream.on(:headers) do |values|
                response_headers = values.to_h
                status = (response_headers[":status"] || response_headers[:status]).to_i
              end
              stream.on(:data) do |chunk|
                buffer << chunk.to_s.b
                raise "Realtime stream frame is too large" if buffer.bytesize > 8 * 1024 * 1024
                next unless status.between?(200, 299)

                while (newline = buffer.index("\n"))
                  line = buffer.slice!(0..newline).strip
                  next if line.empty?

                  decoded, sequence = decrypt_stream_frame(line, context, sequence)
                  safe_call(block, decoded, data)
                end
              rescue Exception => e
                failure_reason = "invalid frame: #{e.message}"
                set_realtime_stream_error(data, failure_reason)
                log_error("Realtime stream frame error: #{format_exception(e)}")
                begin
                  stream.cancel unless stream.respond_to?(:closed?) && stream.closed?
                rescue Exception
                end
              end
              stream.on(:close) do |error|
                next unless take_pending_request(pending_token)

                touch_connection_activity(generation)
                if status.between?(200, 299) && failure_reason == nil
                  reason = "HTTP/2 stream ended after HTTP #{status}: #{error || :end_stream}, frames=#{sequence}"
                  set_realtime_stream_error(data, reason)
                  safe_call(block, :closed, data)
                else
                  set_realtime_stream_error(
                    data,
                    failure_reason || realtime_stream_http_error(status, buffer, response_headers, context, data)
                  )
                  safe_call(block, :error, data)
                end
              end
              head = {
                ":scheme" => "https",
                ":authority" => "api.elten.link:443",
                ":path" => path,
                ":method" => "GET",
                "user-agent" => user_agent,
                "accept" => "application/x-ndjson",
                "accept-encoding" => "identity",
                "content-type" => "application/json",
                "content-length" => json.bytesize.to_s
              }
              stream.headers(head, end_stream: false)
              until json.empty?
                chunk = json.slice!(0...4096)
                stream.data(chunk, end_stream: json.empty?)
              end
            end
          rescue Exception => e
            set_realtime_stream_error(data, "setup failed: #{e.class}: #{e.message}")
            log_error("Realtime stream error: #{format_exception(e)}") unless cancelled?(data, cancellation_token)
            close_http2(false, generation, reason: "stream setup failed") unless pending_token.nil? || generation.nil?
            pending_token.nil? ? safe_call(block, :error, data) : fail_pending_request(pending_token)
          end
        end
      end

      def downloadfile(source, destination, data=nil, redirects=0, cancellation_token: nil, &block)
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            result = downloadfile_sync(source, destination, data, redirects, cancellation_token: cancellation_token, &block)
            safe_call(block, result, data) if result.is_a?(Integer)
          rescue Exception => e
            log_error("downloadfile worker error: #{format_exception(e)}") unless cancelled?(data, cancellation_token)
            safe_call(block, :error, data)
          end
        end
      end

      def readurl(url, method="get", body="", headers={}, data=nil, redirects=0, cancellation_token: nil, &block)
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            response = readurl_sync(url, method, body, headers, data, redirects, cancellation_token: cancellation_token)
            safe_call(block, response[:body], data, response[:headers])
          rescue Exception => e
            log_error("readurl worker error: #{format_exception(e)}") unless cancelled?(data, cancellation_token)
            safe_call(block, :error, data, {})
          end
        end
      end

      def server_verify
        self.encrypted_transport_enabled = false
        return false if server_rsa == nil
        token = SecureRandom.alphanumeric(32)
        response = nil
        client_time = Time.now.to_f
        ejrequest(
          "GET",
          "/api/v1/system/time",
          { "client_time" => client_time, "challenge" => token, "seed" => SecureRandom.alphanumeric(32) },
          nil,
          encrypted: true
        ) { |resp, _data| response = resp }
        started = Time.now.to_f
        while response == nil && Time.now.to_f - started < 15
          if defined?(loop_update)
            loop_update(false)
          else
            sleep 0.01
          end
        end
        return false unless response.is_a?(String)
        begin
          json = JSON.load(response)
        rescue JSON::ParserError, TypeError
          return false
        end
        response_hash = json.is_a?(Hash) ? json : {}
        data = response_hash["data"]
        verified = response_hash["success"] == true &&
                   data.is_a?(Hash) &&
                   (data["time"].to_f - Time.now.to_f).abs <= 86_400 &&
                   (data["client_time"].to_f - client_time).abs < 0.01 &&
                   data["challenge"].to_s == token
        self.encrypted_transport_enabled = verified
        verified
      rescue Exception => e
        log_warning("Server verification error: #{format_exception(e)}")
        self.encrypted_transport_enabled = false
        false
      end

      def encrypted_transport_enabled=(enabled)
        @encrypted_transport_enabled = enabled == true
        clear_transport_session unless @encrypted_transport_enabled
      end

      def http2_enabled?
        !disable_http2?
      end

      private

      def connection_mutex
        @conn_mutex ||= Mutex.new
      end

      def http_mutex
        @http_mutex ||= Monitor.new
      end

      def ssl_mutex
        @ssl_mutex ||= Mutex.new
      end

      def pending_mutex
        @pending_mutex ||= Mutex.new
      end

      def ensure_http2_connection
        connect_http2(force: false, reconnect_if_stale: true)
      end

      def connect_http2(force:, reconnect_if_stale:)
        detached = nil
        socket = nil
        ssl = nil
        generation = nil

        connection_mutex.synchronize do
          if connected?
            return true if !force && (!reconnect_if_stale || !stale?)
          end

          reason = force ? "forced reconnect" : (connected? ? "stale connection" : "connection no longer usable")
          detached = detach_http2_locked(reason: reason)
          close_io(detached[:ssl]) if detached != nil

          socket = connect_socket(HOST, PORT)
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.alpn_protocols = [HTTP2_ALPN]
          ctx.options |= OpenSSL::SSL::OP_IGNORE_UNEXPECTED_EOF
          ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
          ssl.sync_close = true
          ssl.hostname = HOST if ssl.respond_to?(:hostname=)
          Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }

          http = Connection.new(settings_max_frame_size: 131072)
          @connection_sequence = @connection_sequence.to_i + 1
          generation = @connection_sequence
          @connection_generation = generation
          @ssl = ssl
          @http = http
          @last_response = Time.now.to_i
          @last_activity = monotonic_time
          http.on(:frame) { |bytes| write_http2_frame(bytes, generation, ssl) }
          http.on(:error) do |error|
            log_warning("HTTP/2 connection error: #{error}")
            close_http2(false, generation, reason: "protocol error: #{error}")
          end
          http.on(:goaway) do |last_stream, error|
            log_debug("HTTP/2 connection #{generation} received GOAWAY: #{error}, last_stream_id=#{last_stream}")
          end
          start_reader(generation, ssl, http)
        end

        finalize_detached_connection(detached, false)
        true
      rescue Exception => e
        finalize_detached_connection(detached, false)
        if generation != nil
          close_http2(false, generation, reason: "connection setup failed")
        else
          close_io(ssl || socket)
        end
        log_error("HTTP/2 init error: #{format_exception(e)}")
        false
      end

      def connected?
        http = @http
        http != nil &&
          @ssl != nil &&
          !@ssl.closed? &&
          (!http.respond_to?(:closed?) || !http.closed?) &&
          @reader_thread != nil &&
          @reader_thread.alive?
      end

      def stale?
        last_activity = @last_activity
        return false if last_activity == nil

        now = monotonic_time
        pending_started_at = oldest_pending_request_started_at(@connection_generation)
        return pending_started_at < now - ACTIVE_STALE_AFTER if pending_started_at != nil

        last_activity < now - STALE_AFTER
      end

      def disable_http2?
        Configuration.disablehttp2 == true
      end

      def encrypted_transport?
        @encrypted_transport_enabled == true && server_rsa != nil
      end

      def user_agent
        version = if defined?(Elten) && Elten.respond_to?(:version)
          Elten.version
        else
          "ELTEN"
        end
        version.to_s
      end

      def connect_socket(host, port)
        Socket.tcp(host, port, connect_timeout: CONNECT_TIMEOUT)
      end

      def start_reader(generation, ssl, http)
        @reader_thread = Thread.new do
          Thread.current.report_on_exception = false
          reason = "reader stopped"
          loop do
            break unless connection_current?(generation, ssl, http)
            begin
              chunk = ssl.read_nonblock(16_384)
              if chunk != nil && chunk.bytesize > 0
                break unless connection_current?(generation, ssl, http)

                touch_connection_activity(generation)
                http_mutex.synchronize { http << chunk }
              end
            rescue IO::WaitReadable
              IO.select([ssl], nil, nil, 0.5)
            rescue EOFError
              reason = "peer closed connection"
              break
            rescue IOError => e
              reason = "reader failed: #{e.class}: #{e.message}"
              break
            rescue Exception => e
              reason = "reader failed: #{e.class}: #{e.message}"
              log_error("HTTP reader error: #{format_exception(e)}")
              break
            end
          end
          close_http2(false, generation, reason: reason)
        end
      end

      def close_http2(kill_reader, generation=nil, reason: "client closed connection")
        detached = connection_mutex.synchronize do
          detach_http2_locked(generation, reason: reason)
        end
        return false if detached == nil

        finalize_detached_connection(detached, kill_reader)
        true
      rescue Exception
        false
      end

      def write_http2_frame(bytes, generation, ssl)
        ssl_mutex.synchronize do
          return unless connection_current?(generation, ssl)
          return if ssl.closed?

          ssl.write(bytes)
          ssl.flush
          touch_connection_activity(generation)
        end
      rescue Exception => e
        log_error("HTTP frame write error: #{format_exception(e)}")
        close_http2(false, generation, reason: "write failed: #{e.class}: #{e.message}")
      end

      def connection_current?(generation, ssl=nil, http=nil)
        generation != nil &&
          @connection_generation == generation &&
          (ssl == nil || @ssl.equal?(ssl)) &&
          (http == nil || @http.equal?(http))
      end

      def detach_http2_locked(expected_generation=nil, reason: "connection replaced")
        return nil if expected_generation != nil && @connection_generation != expected_generation
        return nil if @http == nil && @ssl == nil && @reader_thread == nil

        detached = {
          generation: @connection_generation,
          http: @http,
          ssl: @ssl,
          reader: @reader_thread,
          reason: reason
        }
        @connection_generation = nil
        @reader_thread = nil
        @http = nil
        @ssl = nil
        @last_activity = nil
        detached
      end

      def finalize_detached_connection(detached, kill_reader)
        return if detached == nil

        log_debug("HTTP/2 connection #{detached[:generation]} closed: #{detached[:reason]}")
        close_io(detached[:ssl])
        reader = detached[:reader]
        begin
          reader.kill if kill_reader && reader != nil && reader != Thread.current && reader.alive?
        rescue Exception
        end
        fail_pending_requests_for_generation(detached[:generation])
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue Exception
        Time.now.to_f
      end

      def touch_connection_activity(generation)
        @last_activity = monotonic_time if @connection_generation == generation
      end

      def register_pending_request(generation, stream, cancellation_token=nil, persistent: false, &failure)
        token = Object.new
        entry = {
          generation: generation,
          started_at: monotonic_time,
          failure: failure,
          stream: stream,
          persistent: persistent,
          cancellation_registration: nil
        }
        pending_mutex.synchronize do
          @pending_requests ||= {}
          @pending_requests[token] = entry
        end
        registration = register_cancellation(cancellation_token) { cancel_pending_request(token) }
        if registration != nil
          attached = pending_mutex.synchronize do
            current = @pending_requests == nil ? nil : @pending_requests[token]
            current[:cancellation_registration] = registration if current.equal?(entry)
            current.equal?(entry)
          end
          registration.unregister unless attached
        end
        token
      end

      def take_pending_request(token)
        entry = pending_mutex.synchronize do
          @pending_requests == nil ? nil : @pending_requests.delete(token)
        end
        dispose_cancellation(entry)
        entry
      end

      def fail_pending_request(token)
        entry = detach_pending_request(token)
        return false if entry == nil

        entry[:failure].call if entry[:failure] != nil
        true
      rescue Exception
        false
      end

      def fail_pending_requests_for_generation(generation)
        return if generation == nil

        entries = pending_mutex.synchronize do
          requests = @pending_requests || {}
          selected = requests.select { |_token, entry| entry[:generation] == generation }
          selected.each_key { |token| requests.delete(token) }
          selected.values
        end
        entries.each do |entry|
          dispose_cancellation(entry)
          begin
            entry[:failure].call if entry[:failure] != nil
          rescue Exception
          end
        end
      end

      def cancel_pending_request(token)
        entry = detach_pending_request(token)
        return false if entry == nil

        cancel_http2_stream(entry[:stream])
        entry[:failure].call if entry[:failure] != nil
        true
      rescue Exception
        false
      end

      def detach_pending_request(token)
        entry = pending_mutex.synchronize do
          @pending_requests == nil ? nil : @pending_requests.delete(token)
        end
        dispose_cancellation(entry)
        entry
      end

      def dispose_cancellation(entry)
        registration = entry.is_a?(Hash) ? entry[:cancellation_registration] : nil
        registration.unregister if registration != nil
      rescue Exception
      end

      def cancel_http2_stream(stream)
        return if stream == nil
        http_mutex.synchronize do
          stream.cancel unless stream.respond_to?(:closed?) && stream.closed?
        end
      rescue Exception
      end

      def oldest_pending_request_started_at(generation)
        return nil if generation == nil

        pending_mutex.synchronize do
          (@pending_requests || {}).values
            .select { |entry| entry[:generation] == generation && entry[:persistent] != true }
            .map { |entry| entry[:started_at] }
            .compact
            .min
        end
      end

      def write_http1_request(io, method, path, host, headers, body, cancellation_token=nil)
        request = "#{method} #{path} HTTP/1.1\r\nHost: #{host}\r\n".b
        headers.each { |key, value| request << "#{key}: #{value}\r\n".b }
        request << "\r\n".b
        io.write(request)
        if body.respond_to?(:read)
          body.rewind if body.respond_to?(:rewind)
          while (chunk = body.read(64 * 1024))
            break if chunk.empty?
            raise_if_cancelled!(cancellation_token)
            io.write(chunk)
          end
        elsif body != nil && !body.empty?
          io.write(body)
        end
        io.flush if io.respond_to?(:flush)
      end

      def read_http1_response(io)
        response = read_http1_head(io)
        response[:body] = read_http_body(io, response[:headers])
        response
      end

      def read_http1_head(io)
        header = "".b
        line = "".b
        until line == "\r\n"
          line = read_line(io)
          header << line
        end
        lines = header.split("\r\n")
        status_line = lines.shift.to_s
        raise "Invalid HTTP response: #{status_line}" unless status_line.start_with?("HTTP/")
        headers = {}
        lines.each do |entry|
          index = entry.index(":")
          next if index == nil
          headers[entry[0...index]] = entry[index + 1..-1].to_s.strip
        end
        { status: status_line.split(" ")[1].to_i, headers: headers }
      end

      def read_http_body(io, headers)
        transfer = header_value(headers, "Transfer-Encoding").to_s.downcase
        length = header_value(headers, "Content-Length")
        if transfer.include?("chunked")
          read_chunked_body(io)
        elsif length != nil
          read_exact_body(io, length.to_i)
        else
          read_until_eof(io)
        end
      end

      def read_chunked_body(io)
        body = "".b
        loop do
          line = read_line(io)
          size = line.split(";", 2)[0].to_i(16)
          break if size == 0
          body << read_exact_body(io, size)
          read_exact_body(io, 2)
        end
        body
      end

      def read_exact_body(io, size)
        body = "".b
        while body.bytesize < size
          chunk = read_partial(io, size - body.bytesize)
          break if chunk == nil || chunk.empty?
          body << chunk
        end
        body
      end

      def read_until_eof(io)
        body = "".b
        loop do
          chunk = read_partial(io, 16_384)
          break if chunk == nil || chunk.empty?
          body << chunk
        end
        body
      end

      def read_line(io)
        wait_readable(io)
        io.readline
      end

      def read_partial(io, size)
        wait_readable(io)
        io.readpartial([size, 16_384].min)
      rescue EOFError
        nil
      end

      def wait_readable(io)
        ready = IO.select([io], nil, nil, READ_TIMEOUT)
        raise Timeout::Error, "network read timeout" if ready == nil
      end

      def decode_body(body, headers)
        data = body.to_s.b
        encoding = header_value(headers, "content-encoding").to_s.downcase
        transfer = header_value(headers, "transfer-encoding").to_s.downcase
        if (encoding == "gzip" || transfer == "gzip") && data.getbyte(0) == 0x1f && data.getbyte(1) == 0x8b
          Zlib::GzipReader.new(StringIO.new(data)).read
        elsif transfer == "deflate" || encoding == "deflate"
          Zlib::Inflate.inflate(data)
        elsif encoding == "zstd"
          require "zstd-ruby" unless defined?(Zstd)
          Zstd.decompress(data)
        else
          data
        end
      end

      def json_request_body(params, encrypt)
        payload = JSON.generate(params).b
        return [payload, nil] unless encrypt

        if (session = current_transport_session)
          envelope = encrypted_session_request_envelope(payload, session)
          return [JSON.generate(envelope).b, { mode: :session, key: session[:server_to_client_key], session_id: session[:id] }]
        end

        envelope, key, session_open = encrypted_request_envelope(payload, open_session: transport_sessions_enabled?)
        [JSON.generate(envelope).b, { mode: :rsa, key: key, session_open: session_open }]
      end

      def encrypted_request_envelope(payload, open_session: false)
        key = OpenSSL::Random.random_bytes(32)
        iv = OpenSSL::Random.random_bytes(12)
        compressed = zstd_compress(payload)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        cipher.iv = iv
        encrypted = cipher.update(compressed) + cipher.final
        envelope = {
          "elten_encryption" => "v1",
          "alg" => "RSA-OAEP+AES-256-GCM",
          "content_encoding" => "zstd",
          "key" => Base64.strict_encode64(server_rsa.public_encrypt(key, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)),
          "iv" => Base64.strict_encode64(iv),
          "tag" => Base64.strict_encode64(cipher.auth_tag),
          "payload" => Base64.strict_encode64(encrypted)
        }
        session_open = nil
        if open_session
          client_nonce_raw = OpenSSL::Random.random_bytes(TRANSPORT_SESSION_NONCE_BYTES)
          client_nonce = Base64.strict_encode64(client_nonce_raw)
          envelope["session"] = {
            "op" => "open",
            "client_nonce" => client_nonce
          }
          session_open = {
            request_key: key,
            client_nonce_raw: client_nonce_raw,
            client_nonce: client_nonce
          }
        end
        [envelope, key, session_open]
      end

      def encrypted_session_request_envelope(payload, session)
        iv = OpenSSL::Random.random_bytes(12)
        compressed = zstd_compress(payload)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = session[:client_to_server_key]
        cipher.iv = iv
        cipher.auth_data = transport_session_auth_data(session[:id], "request", "zstd")
        encrypted = cipher.update(compressed) + cipher.final
        {
          "elten_encryption" => "v1",
          "alg" => TRANSPORT_SESSION_ALGORITHM,
          "session_id" => session[:id],
          "content_encoding" => "zstd",
          "iv" => Base64.strict_encode64(iv),
          "tag" => Base64.strict_encode64(cipher.auth_tag),
          "payload" => Base64.strict_encode64(encrypted)
        }
      end

      def decrypt_json_response(body, context)
        envelope = JSON.load(body.to_s)
        unless envelope.is_a?(Hash) && envelope["elten_encryption"].to_s == "v1"
          raise "Invalid encrypted response envelope"
        end

        key = context.is_a?(Hash) ? context[:key] : context
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = Base64.strict_decode64(envelope.fetch("iv"))
        cipher.auth_tag = Base64.strict_decode64(envelope.fetch("tag"))
        if envelope["alg"].to_s == TRANSPORT_SESSION_ALGORITHM
          cipher.auth_data = transport_session_auth_data(envelope.fetch("session_id"), "response", envelope["content_encoding"].to_s)
        end
        plaintext = cipher.update(Base64.strict_decode64(envelope.fetch("payload"))) + cipher.final
        process_transport_session_response(envelope["session"], context[:session_open]) if context.is_a?(Hash) && context[:mode] == :rsa
        decode_encrypted_payload(plaintext, envelope["content_encoding"])
      rescue JSON::ParserError, KeyError, ArgumentError, OpenSSL::Cipher::CipherError => e
        raise "Invalid encrypted response: #{e.message}"
      end

      def decrypt_stream_frame(line, context, previous_sequence)
        envelope = JSON.load(line.to_s)
        unless envelope.is_a?(Hash) && envelope["elten_encryption"] == "v1" && envelope["alg"] == REALTIME_STREAM_ALGORITHM
          raise "Invalid realtime stream envelope"
        end

        session_id = envelope.fetch("session_id").to_s
        raise "Realtime stream session mismatch" unless session_id == context[:session_id].to_s
        sequence = envelope.fetch("sequence").to_i
        raise "Invalid realtime stream sequence" unless sequence == previous_sequence.to_i + 1

        encoding = envelope["content_encoding"].to_s
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = context[:key]
        cipher.iv = Base64.strict_decode64(envelope.fetch("iv"))
        cipher.auth_tag = Base64.strict_decode64(envelope.fetch("tag"))
        cipher.auth_data = ["v1", REALTIME_STREAM_ALGORITHM, session_id, "stream", sequence, encoding].join("|").b
        plaintext = cipher.update(Base64.strict_decode64(envelope.fetch("payload"))) + cipher.final
        [decode_encrypted_payload(plaintext, encoding), sequence]
      rescue JSON::ParserError, KeyError, ArgumentError, OpenSSL::Cipher::CipherError => e
        raise "Invalid realtime stream frame: #{e.message}"
      end

      def realtime_stream_http_error(status, body, headers, context, data=nil)
        prefix = if status.to_i.between?(200, 299)
                   "HTTP/2 connection closed after HTTP #{status.to_i}"
                 elsif status.to_i.positive?
                   "HTTP #{status.to_i}"
                 else
                   "HTTP/2 connection closed before response"
                 end
        error = nil
        unless body.to_s.empty?
          begin
            decoded = decode_body(body, headers)
            payload = JSON.load(decoded.to_s)
            if payload.is_a?(Hash) && payload["elten_encryption"] == "v1"
              payload = JSON.load(decrypt_json_response(decoded, context))
            end
            error = payload["error"] if payload.is_a?(Hash)
          rescue Exception
          end
        end
        error = {} unless error.is_a?(Hash)
        details = error["details"].is_a?(Hash) ? error["details"] : {}
        retry_after = [headers["retry-after"], error["retry_after"], details["retry_after"]].map do |value|
          http_retry_after(value)
        end.max
        data["stream_retry_after"] = retry_after if data.is_a?(Hash) && retry_after > 0
        parts = [prefix, error["code"], error["message"]].map(&:to_s).reject(&:empty?)
        parts << "profile=#{details["profile"]}" if details["profile"]
        parts << "rule=#{details["rule"]}" if details["rule"]
        parts << "retry_after=#{retry_after}s" if retry_after > 0
        parts.join(": ")
      end

      def http_retry_after(value)
        text = value.to_s.strip
        return text.to_i if text.match?(/\A\d+\z/)
        return 0 if text.empty?

        [Time.httpdate(text) - Time.now, 0].max.ceil
      rescue ArgumentError
        0
      end

      def set_realtime_stream_error(data, reason)
        return unless data.is_a?(Hash)

        value = reason.to_s.gsub(/\s+/, " ").strip
        data["stream_error"] = value[0, 240] unless value.empty?
      end

      def process_transport_session_response(session_response, session_open)
        return false unless session_open.is_a?(Hash)
        return false unless session_response.is_a?(Hash)
        return false unless session_response["op"].to_s == "open"
        return false unless session_response["alg"].to_s == TRANSPORT_SESSION_ALGORITHM

        session_id = session_response["id"].to_s
        server_nonce = session_response["server_nonce"].to_s
        ttl = session_response["ttl"].to_i
        return false if session_id.empty? || server_nonce.empty? || ttl <= 0

        server_nonce_raw = Base64.strict_decode64(server_nonce)
        keys = derive_transport_session_keys(session_open[:request_key], session_open[:client_nonce_raw], server_nonce_raw)
        expected = transport_session_proof(
          keys[:proof_key],
          session_id: session_id,
          client_nonce: session_open[:client_nonce],
          server_nonce: server_nonce,
          ttl: ttl
        )
        return false unless secure_compare(expected, session_response["proof"].to_s)

        set_transport_session(
          id: session_id,
          client_to_server_key: keys[:client_to_server_key],
          server_to_client_key: keys[:server_to_client_key],
          expires_at: Time.now.to_f + [ttl, transport_session_client_ttl].min
        )
        true
      rescue Exception => e
        log_warning("Encrypted transport session open failed: #{format_exception(e)}")
        false
      end

      def derive_transport_session_keys(request_key, client_nonce_raw, server_nonce_raw)
        secret = hkdf(request_key.to_s.b, salt: client_nonce_raw.to_s.b + server_nonce_raw.to_s.b, info: TRANSPORT_SESSION_INFO, length: TRANSPORT_SESSION_SECRET_BYTES)
        {
          client_to_server_key: secret.byteslice(0, TRANSPORT_SESSION_KEY_BYTES),
          server_to_client_key: secret.byteslice(TRANSPORT_SESSION_KEY_BYTES, TRANSPORT_SESSION_KEY_BYTES),
          proof_key: secret.byteslice(TRANSPORT_SESSION_KEY_BYTES * 2, TRANSPORT_SESSION_KEY_BYTES)
        }
      end

      def hkdf(secret, salt:, info:, length:)
        salt = "\0".b * 32 if salt.to_s.empty?
        prk = OpenSSL::HMAC.digest("SHA256", salt, secret)
        output = +"".b
        previous = +"".b
        counter = 1
        while output.bytesize < length
          previous = OpenSSL::HMAC.digest("SHA256", prk, previous + info + counter.chr)
          output << previous
          counter += 1
        end
        output.byteslice(0, length)
      end

      def transport_session_proof(proof_key, session_id:, client_nonce:, server_nonce:, ttl:)
        payload = ["open", session_id, client_nonce, server_nonce, ttl.to_i, TRANSPORT_SESSION_ALGORITHM].join(":")
        Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", proof_key, payload))
      end

      def transport_session_auth_data(session_id, direction, content_encoding)
        ["v1", TRANSPORT_SESSION_ALGORITHM, session_id.to_s, direction.to_s, content_encoding.to_s].join("|").b
      end

      def secure_compare(a, b)
        a = a.to_s.b
        b = b.to_s.b
        return false unless a.bytesize == b.bytesize

        diff = 0
        a.bytes.zip(b.bytes) { |left, right| diff |= left ^ right }
        diff == 0
      end

      def transport_sessions_enabled?
        @transport_sessions_enabled != false
      end

      def transport_session_client_ttl
        value = ENV.fetch("ELTEN_TRANSPORT_SESSION_CLIENT_TTL", TRANSPORT_SESSION_CLIENT_TTL.to_s).to_i
        value.positive? ? value : TRANSPORT_SESSION_CLIENT_TTL
      end

      def transport_session_mutex
        @transport_session_mutex ||= Mutex.new
      end

      def current_transport_session
        transport_session_mutex.synchronize do
          session = @transport_session
          return nil unless session.is_a?(Hash)
          if session[:expires_at].to_f <= Time.now.to_f + 5
            @transport_session = nil
            return nil
          end

          session
        end
      end

      def set_transport_session(session)
        transport_session_mutex.synchronize { @transport_session = session }
      end

      def clear_transport_session(expected_session_id=nil)
        transport_session_mutex.synchronize do
          if expected_session_id != nil
            current_id = @transport_session.is_a?(Hash) ? @transport_session[:id].to_s : ""
            return false unless current_id == expected_session_id.to_s
          end

          @transport_session = nil
          true
        end
      end

      def decode_encrypted_payload(payload, content_encoding)
        case content_encoding.to_s.downcase
        when "", "identity"
          payload
        when "zstd"
          require "zstd-ruby" unless defined?(Zstd)
          Zstd.decompress(payload.to_s.b)
        else
          raise "Unsupported encrypted response encoding: #{content_encoding}"
        end
      end

      def zstd_compress(payload)
        require "zstd-ruby" unless defined?(Zstd)
        Zstd.compress(payload.to_s.b, level: 3)
      end

      def normalize_headers(headers)
        result = {}
        return result unless headers.is_a?(Hash)
        headers.each { |key, value| result[key.to_s] = value.to_s }
        result
      end

      def header_value(headers, name)
        return nil unless headers.is_a?(Hash)
        name = name.to_s.downcase
        headers.each { |key, value| return value if key.to_s.downcase == name }
        nil
      end

      def downloadfile_sync(source, destination, data=nil, redirects=0, cancellation_token: nil, &block)
        raise "Too many redirects" if redirects > MAX_REDIRECTS
        raise_if_cancelled!(cancellation_token)
        uri = URI.parse(source)
        socket = connect_socket(uri.host, uri.port || (uri.scheme == "https" ? 443 : 80))
        io = socket
        cancellation_registration = register_cancellation(cancellation_token) do
          close_io(io)
          close_io(socket)
        end
        raise_if_cancelled!(cancellation_token)
        if uri.scheme == "https"
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
          ssl.sync_close = true
          ssl.hostname = uri.host if ssl.respond_to?(:hostname=)
          Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
          io = ssl
        end
        write_http1_request(io, "GET", uri.request_uri, uri.host, {
          "User-Agent" => user_agent,
          "Connection" => "close",
          "Accept-Encoding" => "identity, chunked, *;q=0"
        }, nil)
        response = read_http1_head(io)
        location = header_value(response[:headers], "Location")
        return downloadfile_sync(uri.merge(location).to_s, destination, data, redirects + 1, cancellation_token: cancellation_token, &block) if location != nil
        status = response[:status].to_i
        return :error if status < 200 || status >= 300
        File.open(destination, "wb") do |file|
          stream_http_body(io, response[:headers], file, data, block, cancellation_token)
        end
      ensure
        cancellation_registration.unregister if defined?(cancellation_registration) && cancellation_registration != nil
        close_io(io) if defined?(io)
        close_io(socket) if defined?(socket)
      end

      def readurl_sync(url, method="get", body="", headers={}, data=nil, redirects=0, cancellation_token: nil)
        raise "Too many redirects" if redirects > MAX_REDIRECTS
        raise_if_cancelled!(cancellation_token)
        uri = URI.parse(url)
        body_data = if body.nil?
                      nil
                    elsif body.respond_to?(:read)
                      body.rewind if body.respond_to?(:rewind)
                      body
                    else
                      body.to_s.b
                    end
        request_headers = {
          "User-Agent" => user_agent,
          "Connection" => "close",
          "Accept-Encoding" => "identity, chunked, *;q=0"
        }.merge(normalize_headers(headers))
        if body_data != nil
          body_size = body_data.respond_to?(:size) ? body_data.size : body_data.bytesize
          request_headers["Content-Length"] = body_size.to_i.to_s
        end
        response = http1_request_uri(uri, method.to_s.upcase, body_data, request_headers, data, cancellation_token)
        if response[:redirect] != nil
          return readurl_sync(uri.merge(response[:redirect]).to_s, method, body, headers, data, redirects + 1, cancellation_token: cancellation_token)
        end
        status = response[:status].to_i
        return { body: :error, headers: response[:headers] } if status < 200 || status >= 300
        { body: decode_body(response[:body], response[:headers]), headers: response[:headers] }
      end

      def http1_request_uri(uri, method, body, headers, data=nil, cancellation_token=nil)
        raise_if_cancelled!(cancellation_token)
        socket = connect_socket(uri.host, uri.port || (uri.scheme == "https" ? 443 : 80))
        io = socket
        cancellation_registration = register_cancellation(cancellation_token) do
          close_io(io)
          close_io(socket)
        end
        raise_if_cancelled!(cancellation_token)
        if uri.scheme == "https"
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
          ssl.sync_close = true
          ssl.hostname = uri.host if ssl.respond_to?(:hostname=)
          Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
          io = ssl
        end
        write_http1_request(io, method, uri.request_uri, uri.host, headers, body, cancellation_token)
        response = read_http1_response(io)
        location = header_value(response[:headers], "Location")
        response[:redirect] = location if location != nil
        response
      ensure
        cancellation_registration.unregister if defined?(cancellation_registration) && cancellation_registration != nil
        close_io(io) if defined?(io)
        close_io(socket) if defined?(socket)
      end

      def stream_http_body(io, headers, file, data=nil, block=nil, cancellation_token=nil)
        transfer = header_value(headers, "Transfer-Encoding").to_s.downcase
        total = header_value(headers, "Content-Length").to_i
        downloaded = 0
        last_progress = Time.now.to_f
        if transfer.include?("chunked")
          loop do
            raise_if_cancelled!(cancellation_token, data)
            size = read_line(io).split(";", 2)[0].to_i(16)
            break if size == 0
            chunk = read_exact_body(io, size)
            file.write(chunk)
            downloaded += chunk.bytesize
            read_exact_body(io, 2)
            if total > 0 && Time.now.to_f - last_progress > 5
              last_progress = Time.now.to_f
              safe_call(block, ERDownloadProgress.new(downloaded, total), data)
            end
          end
        elsif total > 0
          while downloaded < total
            raise_if_cancelled!(cancellation_token, data)
            chunk = read_partial(io, [16_384, total - downloaded].min)
            break if chunk == nil || chunk.empty?
            file.write(chunk)
            downloaded += chunk.bytesize
            if Time.now.to_f - last_progress > 5
              last_progress = Time.now.to_f
              safe_call(block, ERDownloadProgress.new(downloaded, total), data)
            end
          end
        else
          loop do
            raise_if_cancelled!(cancellation_token, data)
            chunk = read_partial(io, 16_384)
            break if chunk == nil || chunk.empty?
            file.write(chunk)
            downloaded += chunk.bytesize
          end
        end
        downloaded
      end

      def cancelled?(data=nil, cancellation_token=nil)
        (data.is_a?(Hash) && data[:cancelled] == true) ||
          (cancellation_token != nil && cancellation_token.respond_to?(:cancelled?) && cancellation_token.cancelled?)
      end

      def raise_if_cancelled!(cancellation_token=nil, data=nil)
        cancellation_token.raise_if_cancelled! if cancellation_token != nil && cancellation_token.respond_to?(:raise_if_cancelled!)
        raise "cancelled" if data.is_a?(Hash) && data[:cancelled] == true
      end

      def register_cancellation(cancellation_token, &callback)
        return nil if cancellation_token == nil || !cancellation_token.respond_to?(:on_cancel)
        cancellation_token.on_cancel(&callback)
      end

      def server_rsa
        return @server_rsa if defined?(@server_rsa)
        pem = EltenAPI::Resources.read("eltenpub.pem")
        @server_rsa = pem.to_s == "" ? nil : OpenSSL::PKey::RSA.new(pem)
      rescue Exception => e
        log_error("Server key load error: #{format_exception(e)}")
        @server_rsa = nil
      end

      def safe_call(block, *args)
        block.call(*args) if block != nil
      rescue Exception => e
        log_error("HTTP callback error: #{format_exception(e)}")
      end

      def close_io(io)
        io.close if io != nil && io.respond_to?(:close) && !io.closed?
      rescue Exception
      end

      def format_exception(error)
        "#{error.class}: #{error.message} #{Array(error.backtrace).join(" ")}"
      end

      def log_error(message)
          Log.error(message)
      rescue Exception
      end

      def log_debug(message)
          Log.debug(message)
      rescue Exception
      end

      def log_warning(message)
          Log.warning(message)
      rescue Exception
      end
    end
  end

  module HTTP
    private

    def ejrequest(method, path, params, data=nil, headers: nil, cancellation_token: nil, &block)
      elten_link.e_json_request(method, path, params, data, headers: headers, cancellation_token: cancellation_token, &block)
    end

    def readurl(url, method="get", body="", headers={}, data=nil, cancellation_token: nil, &block)
      elten_link.e_read_url(url, method, body, headers, data, cancellation_token: cancellation_token, &block)
    end

    def downloadfile(source, destination, data=nil, cancellation_token: nil, &block)
      elten_link.e_download_file(source, destination, data, cancellation_token: cancellation_token, &block)
    end

    def srvverify
      elten_link.e_server_verify
    end
  end

  include HTTP
end
