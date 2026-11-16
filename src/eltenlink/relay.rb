# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# frozen_string_literal: true

require "base64"
require "json"
require "monitor"
require "openssl"
require "securerandom"
require "socket"
require "thread"

module EltenLink
  module Relay
    DEFAULT_HOST = "relay.elten.link"
    DEFAULT_PORT = 8244
    VERSION = 1
    MAX_FRAME = 128 * 1024
    MAX_RELIABLE_DATA = 64 * 1024
    MAX_UNRELIABLE_DATA = 1200
    MAX_DATAGRAM = 1400
    MAX_PARTICIPANTS = 32
    FEATURES = %w[udp_aead payload_aead response_chunks request_dedupe session_sync p2p_v1].freeze
    DEFAULT_LIMITS = {
      max_frame: MAX_FRAME,
      max_reliable_data: MAX_RELIABLE_DATA,
      max_unreliable_data: MAX_UNRELIABLE_DATA,
      max_datagram: MAX_DATAGRAM,
      max_metadata: 8 * 1024,
      max_participants: MAX_PARTICIPANTS,
      fast_path_timeout: 12.0,
      session_timeout: 20.0,
      ping_interval: 5.0
    }.freeze
    MAGIC = "ELR1".b

    DATAGRAM_REGISTER = 1
    DATAGRAM_REGISTERED = 2
    DATAGRAM_MESSAGE = 3
    DATAGRAM_FORWARDED = 4
    DATAGRAM_PING = 5
    DATAGRAM_PONG = 6
    DATAGRAM_READY = 7

    class Error < StandardError; end
    class ConnectionError < Error; end
    class AuthenticationError < Error; end
    class TimeoutError < Error; end
    class MessageTooLarge < Error; end

    class RemoteError < Error
      attr_reader :code

      def initialize(code, message = nil)
        @code = code.to_s
        super(message.to_s.empty? ? @code.tr("_", " ") : message.to_s)
      end
    end

    class ResponseWaiter
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @done = false
      end

      def resolve(value = nil, error = nil)
        @mutex.synchronize do
          return if @done
          @done = true
          @value = value
          @error = error
          @condition.broadcast
        end
      end

      def wait(timeout, pump: nil)
        deadline = monotonic + timeout.to_f
        loop do
          @mutex.synchronize do
            if @done
              raise @error if @error
              return @value
            end
            remaining = deadline - monotonic
            raise TimeoutError, "Relay request timed out" if remaining <= 0
            @condition.wait(@mutex, [remaining, 0.05].min) unless pump
          end
          pump.call if pump
        end
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end


    class ByteBudget
      def initialize(maximum, reserve: 1024 * 1024)
        @maximum, @reserve, @bytes = maximum, reserve, 0
        @mutex = Mutex.new
      end

      def acquire(bytes, critical: false)
        @mutex.synchronize do
          return false if @bytes + bytes > (critical ? @maximum : @maximum - @reserve)
          @bytes += bytes
          true
        end
      end

      def release(bytes)
        @mutex.synchronize { @bytes -= bytes }
      end
    end

    OUTBOUND_BUDGET = ByteBudget.new(128 * 1024 * 1024, reserve: 8 * 1024 * 1024)

    class OutboundQueue
      Entry = Struct.new(:frame, :request_id, :deadline, keyword_init: true)

      def initialize(limit: 512, bytes: 8 * 1024 * 1024, reserve: 64, budget: OUTBOUND_BUDGET)
        @limit, @maximum, @reserve = limit, bytes, [reserve, limit / 4].min
        @budget = budget
        @priority, @ordered = [], []
        @bytes = 0
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @closed = false
      end

      def push(frame, priority: false, critical: false, request_id: nil, deadline: nil)
        @mutex.synchronize do
          return false if @closed
          count = @priority.length + @ordered.length
          maximum = priority || critical ? @maximum : [@maximum - 256 * 1024, @maximum / 2].max
          capacity = priority || critical ? @limit : @limit - @reserve
          return false if count >= capacity || @bytes + frame.bytesize > maximum
          return false unless @budget.acquire(frame.bytesize, critical: priority || critical)
          entry = Entry.new(frame: frame, request_id: request_id, deadline: deadline)
          (priority ? @priority : @ordered) << entry
          @bytes += frame.bytesize
          @condition.signal
          true
        end
      end

      def pop
        @mutex.synchronize do
          loop do
            return nil if @closed
            entry = @priority.shift || @ordered.shift
            if entry
              @budget.release(entry.frame.bytesize)
              @bytes -= entry.frame.bytesize
              next if entry.deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= entry.deadline
              return entry
            end
            @condition.wait(@mutex)
          end
        end
      end

      def cancel(request_id)
        @mutex.synchronize do
          removed = false
          [@priority, @ordered].each do |queue|
            queue.delete_if do |entry|
              match = entry.request_id == request_id
              if match
                @budget.release(entry.frame.bytesize)
                @bytes -= entry.frame.bytesize
                removed = true
              end
              match
            end
          end
          removed
        end
      end

      def close
        @mutex.synchronize do
          @closed = true
          @budget.release(@bytes)
          @priority.clear
          @ordered.clear
          @bytes = 0
          @condition.broadcast
        end
      end

      def length
        @mutex.synchronize { @priority.length + @ordered.length }
      end
    end

    class DatagramCipher
      MAGIC = "ELR2".b
      OVERHEAD = 44

      def initialize(client_id, secret, role:)
        raise ArgumentError, "Invalid datagram key" unless secret.bytesize == 32
        @id = [client_id].pack("H*")
        raise ArgumentError, "Invalid client ID" unless @id.bytesize == 16
        outgoing = role == :client ? "client" : "server"
        incoming = role == :client ? "server" : "client"
        @write_key = OpenSSL::HMAC.digest("SHA256", secret, "elten-relay-udp-v2-#{outgoing}")
        @read_key = OpenSSL::HMAC.digest("SHA256", secret, "elten-relay-udp-v2-#{incoming}")
        @write_mutex, @read_mutex = Mutex.new, Mutex.new
        @serial = @highest = @seen = 0
      end

      def self.client_id(packet)
        return nil unless packet.bytesize >= OVERHEAD && packet.byteslice(0, 4) == MAGIC
        packet.byteslice(4, 16).unpack1("H*")
      end

      def encode(packet)
        @write_mutex.synchronize do
          @serial += 1
          raise IOError, "Datagram sequence exhausted" if @serial > 0xffffffffffffffff
          header = MAGIC + @id + [@serial].pack("Q>")
          cipher = OpenSSL::Cipher.new("aes-256-gcm")
          cipher.encrypt
          cipher.key = @write_key
          cipher.iv = [0, @serial].pack("NQ>")
          cipher.auth_data = header
          encrypted = (packet.empty? ? "".b : cipher.update(packet)) + cipher.final
          header + cipher.auth_tag + encrypted
        end
      end

      def decode(packet)
        return nil unless self.class.client_id(packet) && packet.byteslice(4, 16) == @id
        serial = packet.byteslice(20, 8).unpack1("Q>")
        return nil if serial.zero?
        @read_mutex.synchronize do
          offset = @highest - serial
          return nil if offset >= 1024 || (offset >= 0 && (@seen & (1 << offset)) != 0)
          cipher = OpenSSL::Cipher.new("aes-256-gcm")
          cipher.decrypt
          cipher.key = @read_key
          cipher.iv = [0, serial].pack("NQ>")
          cipher.auth_tag = packet.byteslice(28, 16)
          cipher.auth_data = packet.byteslice(0, 28)
          encrypted = packet.byteslice(44..-1)
          clear = (encrypted.empty? ? "".b : cipher.update(encrypted)) + cipher.final
          if serial > @highest
            shift = serial - @highest
            @seen = shift >= 1024 ? 1 : ((@seen << shift) | 1) & ((1 << 1024) - 1)
            @highest = serial
          else
            @seen |= 1 << offset
          end
          clear
        end
      rescue OpenSSL::Cipher::CipherError, ArgumentError
        nil
      end
    end


    class Client
      STOP_WRITER = Object.new

      attr_reader :app_id, :user, :latency

      def initialize(app_id:, user:, token:, host: DEFAULT_HOST, port: DEFAULT_PORT, timeout: 5,
                     tls_context: nil, event_sink: nil)
        @app_id = app_id.to_s
        @user = user.to_s
        @token = token.to_s
        @host = host.to_s
        @port = port.to_i
        @timeout = timeout.to_f
        @tls_context = tls_context
        @event_sink = event_sink
        raise AuthenticationError, "Elten user is not logged in" if @user.empty? || @token.empty?
        raise ArgumentError, "app_id is required" if @app_id.empty? || @app_id == "0"

        @mutex = Mutex.new
        @request_mutex = Mutex.new
        @udp_mutex = Mutex.new
        @requests = {}
        @written_requests = {}
        @outgoing = OutboundQueue.new
        @request_serial = SecureRandom.random_number(1 << 30)
        @udp_pings = {}
        @latency = nil
        @last_udp_pong = 0.0
        @last_control_pong = monotonic
        @udp_registered = false
        @limits = DEFAULT_LIMITS.dup
        @features = []
        @tick_mutex = Mutex.new
        @ack_mutex = Mutex.new
        @reliable_send_mutex = Monitor.new
        @pending_acks = {}
        @response_chunks = {}
        @event_chunks = nil
        @next_ping = 0.0
        @server_clock_offset = 0.0
        @closed = false
        @closing = false
        connect_control
      rescue Exception
        close if @mutex != nil
        raise
      end

      def create_session(metadata:, participant_metadata:, capacity:, public_state:, encryption:, p2p: :off, p2p_participants_limit: 2)
        validate_p2p_options!(p2p, p2p_participants_limit)
        fields = {
          "metadata" => metadata,
          "participant_metadata" => participant_metadata,
          "capacity" => capacity,
          "public" => public_state,
          "encryption" => encryption
        }
        if supports?("p2p_v1")
          fields["p2p"] = p2p.to_s
          fields["p2p_participants_limit"] = p2p_participants_limit
        end
        result = request("create_session", fields)
        @p2p&.track(result)
        result
      end

      def public_sessions
        return Array(request("public_sessions")) unless supports?("response_chunks")
        rows = []
        cursor = nil
        loop do
          page = request("public_sessions", "page" => true, "cursor" => cursor)
          return Array(page) unless page.is_a?(Hash)
          rows.concat(Array(page["sessions"]))
          following = page["next_cursor"]
          break if following.nil? || following == cursor
          cursor = following
        end
        rows
      end

      def session_state(session_id:)
        request("session_state", "session_id" => session_id.to_s)
      end

      def supports?(feature)
        @features.include?(feature)
      end

      def join_public_session(session_id:, participant_metadata:)
        result = request(
          "join_public_session",
          "session_id" => session_id.to_s,
          "participant_metadata" => participant_metadata
        )
        @p2p&.track(result)
        result
      end

      def invite(session_id:, user:, metadata:)
        request("invite", "session_id" => session_id.to_s, "user" => user.to_s, "metadata" => metadata)
      end

      def cancel_invitation(invitation_id:)
        request("cancel_invitation", "invitation_id" => invitation_id.to_s)
      end

      def accept_invitation(invitation_id:, participant_metadata:)
        result = request(
          "accept_invitation",
          "invitation_id" => invitation_id.to_s,
          "participant_metadata" => participant_metadata
        )
        @p2p&.track(result)
        result
      end

      def reject_invitation(invitation_id:)
        request("reject_invitation", "invitation_id" => invitation_id.to_s)
      end

      def leave_session(session_id:)
        request("leave_session", "session_id" => session_id.to_s)
      end

      def close_session(session_id:)
        request("close_session", "session_id" => session_id.to_s)
      end

      def remove_participant(session_id:, participant_id:)
        request("remove_participant", "session_id" => session_id.to_s, "participant_id" => participant_id.to_s)
      end

      def transfer_ownership(session_id:, participant_id:)
        request("transfer_ownership", "session_id" => session_id.to_s, "participant_id" => participant_id.to_s)
      end

      def set_session_public(session_id:, public_state:)
        request("set_session_public", "session_id" => session_id.to_s, "public" => public_state)
      end

      def send_reliable(session_id:, epoch:, message_id:, targets:, envelope:)
        unless @p2p&.reliable?(session_id)
          return send_relay_reliable(session_id: session_id, epoch: epoch, message_id: message_id, targets: targets, envelope: envelope)
        end
        @reliable_send_mutex.synchronize do
          @p2p.send_reliable(session_id: session_id, epoch: epoch, message_id: message_id, targets: targets, envelope: envelope)
        end
      end

      def send_relay_reliable(session_id:, epoch:, message_id:, targets:, envelope:)
        request(
          "reliable",
          "session_id" => session_id.to_s,
          "epoch" => epoch.to_i,
          "message_id" => message_id.to_i,
          "targets" => targets,
          "data" => Base64.strict_encode64(envelope)
        )
      end

      def send_unreliable(session_id:, epoch:, message_id:, targets:, envelope:)
        if @p2p
          remaining = @p2p.send_unreliable(session_id: session_id, epoch: epoch, message_id: message_id, targets: targets, envelope: envelope)
          return true if remaining == []
          targets = remaining if remaining
        end
        send_relay_unreliable(session_id: session_id, epoch: epoch, message_id: message_id, targets: targets, envelope: envelope)
      end

      def send_relay_unreliable(session_id:, epoch:, message_id:, targets:, envelope:)
        if fast_path?
          begin
            packet = message_datagram(session_id, epoch, message_id, targets, envelope)
            return true if send_datagram(packet)
          rescue ArgumentError
            nil
          end
        end
        send_frame({
          "type" => "unreliable",
          "session_id" => session_id.to_s,
          "epoch" => epoch.to_i,
          "message_id" => message_id.to_i,
          "targets" => targets,
          "data" => Base64.strict_encode64(envelope)
        }, important: false)
      end

      def acknowledge(session_id:, sender_id:, message_id:, status:)
        frame = {
          "type" => "ack", "session_id" => session_id.to_s,
          "sender_id" => sender_id.to_s, "message_id" => message_id.to_i, "status" => status.to_s
        }
        return true if send_frame(frame, important: false)
        accepted = @ack_mutex.synchronize do
          key = [session_id, sender_id, message_id]
          next false if @pending_acks.length >= 4096 && !@pending_acks.key?(key)
          @pending_acks[key] = frame
          true
        end
        fail_connection(ConnectionError.new("Relay acknowledgement queue is full"), :overloaded) unless accepted
        accepted
      end

      def tick
        return false if closed? || !@tick_mutex.try_lock
        begin
          @p2p&.update_policy
          now = monotonic
          if now - @last_control_pong > limit(:session_timeout)
            fail_connection(ConnectionError.new("Relay heartbeat timed out"), :connection_lost)
            return false
          end
          @ack_mutex.synchronize do
            @pending_acks.keys.first(128).each do |key|
              break unless send_frame(@pending_acks[key], important: false)
              @pending_acks.delete(key)
            end
          end
          if now >= @next_ping
            queued = send_frame({ "type" => "ping", "nonce" => SecureRandom.hex(8) }, important: false)
            @next_ping = now + (queued ? limit(:ping_interval) : 0.1)
            probe_datagrams if queued
          end
          true
        ensure
          @tick_mutex.unlock
        end
      end

      def fast_path?
        @udp_registered && monotonic - @last_udp_pong <= limit(:fast_path_timeout)
      end

      def p2p_allowed?
        return true unless defined?(::EltenAPI::Configuration) && ::EltenAPI::Configuration.respond_to?(:allowp2p)

        ::EltenAPI::Configuration.allowp2p != false
      end

      def p2p_status(session_id)
        @p2p ? @p2p.status(session_id) : {}
      end

      def limits
        @mutex.synchronize { @limits.dup }
      end

      def limit(name)
        @mutex.synchronize { @limits.fetch(name.to_sym) }
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def close
        shutdown(ConnectionError.new("Relay client was closed"), :closed, notify: false)
      end

      private

      def connect_control
        raw = Socket.tcp(@host, @port, connect_timeout: @timeout)
        raw.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        context = @tls_context || default_tls_context
        ssl = OpenSSL::SSL::SSLSocket.new(raw, context)
        ssl.sync_close = true
        ssl.hostname = @host if ssl.respond_to?(:hostname=)
        connect_tls(ssl)
        ssl.post_connection_check(@host)
        @control = ssl
        @writer_thread = Thread.new { writer_loop }
        @reader_thread = Thread.new { reader_loop }
        p2p_enabled = p2p_allowed?
        login = request(
          "login",
          { "version" => VERSION, "user" => @user, "token" => @token, "app_id" => @app_id, "features" => FEATURES, "p2p_enabled" => p2p_enabled },
          timeout: @timeout
        )
        @client_id = login["client_id"].to_s
        @datagram_secret = Base64.strict_decode64(login["datagram_secret"].to_s)
        apply_limits(login["limits"])
        @features = Array(login["features"]) & FEATURES
        @server_clock_offset = login["time"].to_f - Time.now.to_f if login["time"]
        if supports?("p2p_v1")
          @p2p = P2PTransport.new(self, @client_id, @datagram_secret, @host, @port, enabled: p2p_enabled)
        end
        start_datagrams

      rescue RemoteError => error
        if ["authentication_failed", "not_authenticated"].include?(error.code)
          raise AuthenticationError, error.message
        end
        raise
      rescue AuthenticationError
        raise
      rescue Exception => error
        raise ConnectionError, "Cannot connect to relay service: #{error.message}"
      ensure
        if ssl == nil || @control != ssl
          begin
            ssl&.close
          rescue Exception
            nil
          end
          begin
            raw&.close
          rescue Exception
            nil
          end
        end
        @token = nil
      end

      def validate_p2p_options!(mode, limit)
        raise ArgumentError, "p2p must be :off, :partial or :full" unless %i[off partial full].include?(mode)
        raise ArgumentError, "p2p_participants_limit must be a non-negative integer" unless limit.is_a?(Integer) && limit.between?(0, 0x7fffffff)
      end

      def default_tls_context
        return ::EltenAPI::TLS.client_context if defined?(::EltenAPI::TLS)

        context = OpenSSL::SSL::SSLContext.new
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
        context
      end

      def connect_tls(socket)
        deadline = monotonic + @timeout
        loop do
          socket.connect_nonblock
          return
        rescue IO::WaitReadable, OpenSSL::SSL::SSLErrorWaitReadable
          raise TimeoutError, "TLS connection timed out" if monotonic >= deadline
          IO.select([socket], nil, nil, 0.1)
        rescue IO::WaitWritable, OpenSSL::SSL::SSLErrorWaitWritable
          raise TimeoutError, "TLS connection timed out" if monotonic >= deadline
          IO.select(nil, [socket], nil, 0.1)
        end
      end

      def writer_loop
        while (entry = @outgoing.pop)
          if entry.request_id
            active = @request_mutex.synchronize do
              next false unless @requests.key?(entry.request_id)
              next false if entry.deadline && monotonic >= entry.deadline
              @written_requests[entry.request_id] = true
            end
            next unless active
          end
          @control.write(entry.frame)
        end
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => error
        fail_connection(ConnectionError.new(error.message), :connection_lost) unless @closing
      end

      def reader_loop
        loop { handle_frame(read_frame(@control)) }
      rescue StandardError => error
        fail_connection(ConnectionError.new(error.message), :connection_lost) unless @closing
      end

      def request(type, fields = {}, timeout: 5, pump_events: true, **keywords)
        fields = fields.merge(keywords)
        waiter = ResponseWaiter.new
        request_id = nil
        deadline = monotonic + timeout.to_f
        @request_mutex.synchronize do
          raise ConnectionError, "Relay client is closed" if closed?
          raise RemoteError.new("rate_limited") if @requests.length >= 256
          @request_serial += 1
          request_id = @request_serial.to_s
          @requests[request_id] = waiter
        end
        frame = { "type" => type, "request_id" => request_id }.merge(fields)
        frame["expires_at"] = Time.now.to_f + @server_clock_offset + timeout.to_f if supports?("request_dedupe")
        send_frame(frame, request_id: request_id, deadline: deadline)
        pump = -> { @event_sink.__send__(:wait_step) } if pump_events && @event_sink && @event_sink.respond_to?(:wait_step, true)
        retryable = supports?("request_dedupe") && type != "login"
        begin
          waiter.wait(retryable ? timeout.to_f / 2 : timeout, pump: pump)
        rescue TimeoutError
          raise unless retryable && monotonic < deadline
          @outgoing.cancel(request_id)
          send_frame(frame, important: false, request_id: request_id, deadline: deadline)
          waiter.wait([deadline - monotonic, 0].max, pump: pump)
        end
      rescue TimeoutError => error
        written = @request_mutex.synchronize do
          @requests.delete(request_id)
          @written_requests[request_id]
        end
        @outgoing.cancel(request_id) if request_id
        if written && !%w[public_sessions session_state].include?(type)
          fail_connection(ConnectionError.new("Relay operation outcome is unknown"), :request_timeout)
        end
        raise error
      ensure
        if request_id
          @outgoing.cancel(request_id)
          @request_mutex.synchronize { @requests.delete(request_id); @written_requests.delete(request_id); @response_chunks.delete(request_id) }
        end
      end

      def send_frame(object, important: true, request_id: nil, deadline: nil)
        raise ConnectionError, "Relay client is closed" if closed?
        payload = JSON.generate(object).b
        raise MessageTooLarge, "Relay control frame is too large" if payload.bytesize > limit(:max_frame)
        priority = %w[ack ping pong session_state].include?(object["type"])
        critical = !%w[reliable unreliable].include?(object["type"])
        accepted = @outgoing.push([payload.bytesize].pack("N") + payload, priority: priority, critical: critical, request_id: request_id, deadline: deadline)
        raise RemoteError.new("rate_limited", "Relay send queue is full") if !accepted && important
        accepted
      end

      def read_frame(io)
        header = read_exact(io, 4)
        size = header.unpack1("N")
        raise IOError, "Invalid relay frame" if size <= 0 || size > limit(:max_frame)
        JSON.parse(read_exact(io, size), max_nesting: 24, create_additions: false)
      end

      def read_exact(io, size)
        output = +"".b
        while output.bytesize < size
          part = io.read(size - output.bytesize)
          raise EOFError if part == nil || part.empty?
          output << part
        end
        output
      end

      def handle_frame(frame)
        return unless frame.is_a?(Hash)
        if @p2p
          @p2p.event(frame)
          return if frame["type"] == "p2p_state"
        end
        case frame["type"]
        when "response" then handle_response(frame)
        when "response_chunk" then handle_response_chunk(frame)
        when "event_chunk" then handle_event_chunk(frame)
        when "ping" then send_frame({ "type" => "pong", "nonce" => frame["nonce"] }, important: false)
        when "pong" then @last_control_pong = monotonic
        else emit_event(frame)
        end
      end

      def handle_event_chunk(frame)
        index = frame["index"].to_i
        @event_chunks = [frame["event_id"], 0, "".b] if index.zero?
        chunk = @event_chunks
        raise ConnectionError, "Invalid event chunk sequence" unless chunk && chunk[0] == frame["event_id"] && chunk[1] == index
        decoded = Base64.strict_decode64(frame["data"].to_s)
        raise ConnectionError, "Relay event is too large" if chunk[2].bytesize + decoded.bytesize > 4 * 1024 * 1024
        chunk[2] << decoded
        chunk[1] += 1
        if frame["last"] == true
          @event_chunks = nil
          event = JSON.parse(chunk[2], max_nesting: 24, create_additions: false)
          @p2p&.event(event)
          emit_event(event) unless event["type"] == "p2p_state"
        end
      end

      def handle_response_chunk(frame)
        id = frame["request_id"].to_s
        complete = @request_mutex.synchronize do
          return unless @requests.key?(id)
          index = frame["index"].to_i
          @response_chunks[id] = [0, "".b] if index.zero?
          chunk = @response_chunks[id]
          raise ConnectionError, "Invalid response chunk sequence" unless chunk && chunk[0] == index
          decoded = Base64.strict_decode64(frame["data"].to_s)
          total = @response_chunks.values.sum { |row| row[1].bytesize }
          raise ConnectionError, "Relay responses are too large" if total + decoded.bytesize > 8 * 1024 * 1024 || chunk[1].bytesize + decoded.bytesize > 4 * 1024 * 1024
          chunk[1] << decoded
          chunk[0] += 1
          if frame["last"] == true
            @response_chunks.delete(id)
            JSON.parse(chunk[1], max_nesting: 24, create_additions: false)
          end
        end
        handle_response(complete) if complete
      end

      def handle_response(frame)
        waiter = @request_mutex.synchronize { @requests[frame["request_id"].to_s] }
        return if waiter == nil
        if frame["ok"] == true
          waiter.resolve(frame["result"])
        else
          waiter.resolve(nil, RemoteError.new(frame["error"], frame["message"]))
        end
      end

      def emit_event(frame)
        return if @event_sink == nil || !@event_sink.respond_to?(:relay_event, true)
        @event_sink.__send__(:relay_event, self, frame)
      end

      def start_datagrams
        return unless supports?("udp_aead")
        @datagram_cipher = DatagramCipher.new(@client_id, @datagram_secret, role: :client)
        @datagram_secret = nil
        @datagram = UDPSocket.new
        @datagram.connect(@host, @port)
        @datagram_thread = Thread.new { datagram_reader_loop }
        send_registration
      rescue IOError, SystemCallError, SocketError => error
        @datagram&.close rescue nil
        @datagram = nil
        Log.warning("Relay fast path unavailable: #{error.class}: #{error.message}") if defined?(Log)
      end

      def datagram_reader_loop
        until closed?
          packet = @datagram.recv(limit(:max_datagram) + 1)
          next if packet.bytesize > limit(:max_datagram)
          clear = @datagram_cipher.decode(packet)
          next unless clear
          parsed = parse_datagram(clear)
          next if parsed == nil
          case parsed[:type]
          when DATAGRAM_REGISTERED
            next unless parsed[:client_id] == @client_id
            next unless parsed[:challenge]
            @udp_challenge = parsed[:challenge]
            @udp_registered = true
            send_datagram_ping
          when DATAGRAM_PONG
            sent = @udp_mutex.synchronize { @udp_pings.delete(parsed[:nonce]) }
            if sent != nil
              @last_udp_pong = monotonic
              @latency = @last_udp_pong - sent
              send_datagram(MAGIC + [DATAGRAM_READY, @udp_challenge].pack("CQ>"))
            end
          when DATAGRAM_FORWARDED
            emit_event(
              "type" => "message",
              "kind" => "unreliable",
              "session_id" => parsed[:session_id],
              "sender_id" => parsed[:sender_id],
              "epoch" => parsed[:epoch],
              "message_id" => parsed[:message_id],
              "raw_data" => parsed[:envelope]
            )
          end
        end
      rescue StandardError
        @udp_registered = false
      end

      def probe_datagrams
        return if @datagram == nil
        @udp_registered = false if monotonic - @last_udp_pong > limit(:fast_path_timeout)
        send_registration unless @udp_registered
        send_datagram_ping if @udp_registered
      end

      def send_registration
        packet = MAGIC + [DATAGRAM_REGISTER].pack("C") + id_bytes(@client_id) + ("\0".b * 32)
        send_datagram(packet)
      end

      def send_datagram_ping
        nonce = SecureRandom.random_number(1 << 64)
        @udp_mutex.synchronize do
          @udp_pings[nonce] = monotonic
          @udp_pings.shift while @udp_pings.size > 8
        end
        send_datagram(MAGIC + [DATAGRAM_PING, nonce].pack("CQ>"))
      end

      def send_datagram(packet)
        return false unless @datagram && @datagram_cipher
        encoded = @datagram_cipher.encode(packet)
        return false if encoded.bytesize > limit(:max_datagram)
        @datagram.sendmsg_nonblock(encoded, 0, nil, exception: false) == encoded.bytesize
      rescue IOError, SystemCallError
        @udp_registered = false
        false
      end

      def message_datagram(session_id, epoch, message_id, targets, envelope)
        targets = Array(targets)
        raise ArgumentError, "too many targets" if targets.size > limit(:max_participants)
        packet = MAGIC + [DATAGRAM_MESSAGE].pack("C") + id_bytes(session_id)
        packet << [epoch.to_i, message_id.to_i, targets.size].pack("NQ>C")
        targets.each { |target| packet << id_bytes(target) }
        packet << envelope
        raise ArgumentError, "datagram too large" if packet.bytesize > limit(:max_datagram)
        packet
      end

      def apply_limits(values)
        return unless values.is_a?(Hash)
        parsed = DEFAULT_LIMITS.each_with_object({}) do |(name, default), output|
          value = values[name.to_s]
          next if !value.is_a?(Numeric) || value <= 0
          output[name] = default.is_a?(Float) ? value.to_f : value.to_i
        end
        @mutex.synchronize { @limits.merge!(parsed) }
      end

      def parse_datagram(packet)
        data = packet.to_s.b
        return nil if data.bytesize < 5 || data.byteslice(0, 4) != MAGIC
        type = data.getbyte(4)
        case type
        when DATAGRAM_REGISTERED
          return nil unless [21, 29].include?(data.bytesize)
          { type: type, client_id: bytes_id(data.byteslice(5, 16)), challenge: data.bytesize == 29 ? data.byteslice(21, 8).unpack1("Q>") : nil }
        when DATAGRAM_PONG
          return nil unless data.bytesize == 13
          { type: type, nonce: data.byteslice(5, 8).unpack1("Q>") }
        when DATAGRAM_FORWARDED
          return nil if data.bytesize < 69
          {
            type: type,
            session_id: bytes_id(data.byteslice(5, 16)),
            sender_id: bytes_id(data.byteslice(21, 16)),
            epoch: data.byteslice(37, 4).unpack1("N"),
            message_id: data.byteslice(41, 8).unpack1("Q>"),
            envelope: data.byteslice(49..-1)
          }
        end
      end

      def id_bytes(id)
        value = id.to_s
        raise ArgumentError, "invalid identifier" unless value.match?(/\A[0-9a-f]{32}\z/i)
        [value].pack("H*")
      end

      def bytes_id(bytes)
        bytes.unpack1("H*")
      end

      def close_transport
        @p2p&.close
        @outgoing&.close
        @control&.close rescue nil
        @datagram&.close rescue nil
      end

      def fail_connection(error, reason)
        shutdown(error, reason, notify: true)
      end

      def shutdown(error, reason, notify:)
        changed = @mutex.synchronize do
          next false if @closed
          @closing = true
          @closed = true
          true
        end
        return false unless changed
        close_transport
        waiters = @request_mutex.synchronize do
          current = @requests.values
          @requests = {}
          current
        end
        waiters.each { |waiter| waiter.resolve(nil, error) }
        if notify && @event_sink != nil && @event_sink.respond_to?(:relay_closed, true)
          @event_sink.__send__(:relay_closed, self, error, reason)
        end
        true
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
