# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# frozen_string_literal: true

require "base64"
require "openssl"
require "securerandom"
require "thread"
require "monitor"
require "zlib"

require_relative "../eltenlink/relay" unless defined?(::EltenLink::Relay)
require_relative "../eltenlink/relay_p2p" unless defined?(::EltenLink::Relay::P2PTransport)

module EltenAPI
  module Communication
    DEFAULT_HOST = EltenLink::Relay::DEFAULT_HOST
    DEFAULT_PORT = EltenLink::Relay::DEFAULT_PORT
    VERSION = EltenLink::Relay::VERSION
    MAX_FRAME = EltenLink::Relay::MAX_FRAME
    MAX_RELIABLE_DATA = EltenLink::Relay::MAX_RELIABLE_DATA
    MAX_UNRELIABLE_DATA = EltenLink::Relay::MAX_UNRELIABLE_DATA
    MAX_DATAGRAM = EltenLink::Relay::MAX_DATAGRAM
    MAX_PARTICIPANTS = EltenLink::Relay::MAX_PARTICIPANTS
    DEFAULT_LIMITS = EltenLink::Relay::DEFAULT_LIMITS
    MAGIC = EltenLink::Relay::MAGIC.dup

    DATAGRAM_REGISTER = EltenLink::Relay::DATAGRAM_REGISTER
    DATAGRAM_REGISTERED = EltenLink::Relay::DATAGRAM_REGISTERED
    DATAGRAM_MESSAGE = EltenLink::Relay::DATAGRAM_MESSAGE
    DATAGRAM_FORWARDED = EltenLink::Relay::DATAGRAM_FORWARDED
    DATAGRAM_PING = EltenLink::Relay::DATAGRAM_PING
    DATAGRAM_PONG = EltenLink::Relay::DATAGRAM_PONG
    DATAGRAM_READY = EltenLink::Relay::DATAGRAM_READY

    class Error < StandardError; end
    class ConnectionError < Error; end
    class AuthenticationError < Error; end
    class TimeoutError < Error; end
    class PeerUnavailable < Error; end
    class SessionClosed < Error; end
    class MessageTooLarge < Error; end
    class NotOwner < Error; end
    class StaleKey < Error; end
    class QueueOverflow < Error; end
    MAX_QUEUE_ITEMS = 4096
    MAX_QUEUE_BYTES = 8 * 1024 * 1024

    class RemoteError < Error
      attr_reader :code

      def initialize(code, message = nil)
        @code = code.to_s
        super(message.to_s.empty? ? @code.tr("_", " ") : message.to_s)
      end
    end

    class DeliveryError < Error
      attr_reader :delivery

      def initialize(delivery)
        @delivery = delivery
        super("Message was not delivered to every participant")
      end
    end

    module Crypto
      module_function

      def encrypt(data, bits, key, iv: nil, authenticated: false, aad: "")
        data = binary(data)
        bits = validate(bits, key)
        if authenticated && bits.positive?
          iv ||= SecureRandom.random_bytes(12)
          iv = OpenSSL::Digest::SHA256.digest(iv).byteslice(0, 12) if iv.bytesize == 16
          raise ArgumentError, "IV must have 12 or 16 bytes" unless iv.bytesize == 12
          cipher = OpenSSL::Cipher.new("AES-#{bits}-GCM")
          cipher.encrypt
          cipher.key = key
          cipher.iv = iv
          cipher.auth_data = aad
          encrypted = (data.empty? ? "".b : cipher.update(data)) + cipher.final
          return "ELG2".b + iv + cipher.auth_tag + encrypted
        end
        iv ||= SecureRandom.random_bytes(16)
        raise ArgumentError, "IV must have 16 bytes" unless iv.bytesize == 16
        clear = [Zlib.crc32(data)].pack("N") + data
        iv + crypt(clear, bits, key, iv, true)
      end

      def decrypt(envelope, bits, key, authenticated: false, aad: "")
        envelope = binary(envelope)
        raise Error, "Invalid encrypted message" if envelope.bytesize < 20
        bits = validate(bits, key)
        if authenticated && bits.positive?
          raise Error, "Invalid authenticated message" unless envelope.bytesize >= 32 && envelope.byteslice(0, 4) == "ELG2"
          cipher = OpenSSL::Cipher.new("AES-#{bits}-GCM")
          cipher.decrypt
          cipher.key = key
          cipher.iv = envelope.byteslice(4, 12)
          cipher.auth_tag = envelope.byteslice(16, 16)
          cipher.auth_data = aad
          encrypted = envelope.byteslice(32..-1)
          return (encrypted.empty? ? "".b : cipher.update(encrypted)) + cipher.final
        end
        iv = envelope.byteslice(0, 16)
        clear = crypt(envelope.byteslice(16..-1), bits, key, iv, false)
        checksum = clear.byteslice(0, 4).unpack1("N")
        data = clear.byteslice(4..-1).to_s.b
        raise Error, "Message checksum mismatch" unless Zlib.crc32(data) == checksum
        data
      rescue OpenSSL::Cipher::CipherError
        raise Error, "Cannot decrypt message"
      end

      def binary(data)
        raise ArgumentError, "data must be a String" unless data.is_a?(String)
        data.b
      end

      def validate(bits, key)
        bits = bits.to_i
        raise ArgumentError, "encryption must be 0, 128, 192 or 256" unless [0, 128, 192, 256].include?(bits)
        expected = bits / 8
        raise ArgumentError, "invalid session key" unless key.to_s.b.bytesize == expected
        bits
      end

      def crypt(data, bits, key, iv, encrypting)
        return data.b if bits.zero?
        cipher = OpenSSL::Cipher.new("AES-#{bits}-CTR")
        encrypting ? cipher.encrypt : cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.update(data) + cipher.final
      end
    end

    class EventQueue
      def initialize(limit: MAX_QUEUE_ITEMS, max_bytes: MAX_QUEUE_BYTES)
        @items = []
        @bytes = 0
        @limit, @maximum = limit, max_bytes
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @closed = nil
      end

      def push(item, bytes: 1, discard_if: nil)
        @mutex.synchronize do
          raise @closed if @closed
          while @items.length >= @limit || @bytes + bytes > @maximum
            index = @items.index { |entry| discard_if && discard_if.call(entry[0]) }
            raise QueueOverflow, "Communication queue is full" unless index
            @bytes -= @items.delete_at(index)[1]
          end
          @items << [item, bytes]
          @bytes += bytes
          @condition.signal
        end
        item
      end
      alias << push

      def pop(timeout: nil, cancellation_token: nil, pump: nil)
        deadline = timeout.nil? ? nil : monotonic + [timeout.to_f, 0].max
        loop do
          cancellation_token&.raise_if_cancelled!
          @mutex.synchronize do
            unless @items.empty?
              value, bytes = @items.shift
              @bytes -= bytes
              return value
            end
            raise @closed if @closed
            remaining = deadline.nil? ? nil : deadline - monotonic
            return nil if remaining && remaining <= 0
            @condition.wait(@mutex, [remaining || 0.05, 0.05].min) unless pump
          end
          pump.call if pump
        end
      end

      def close(error = SessionClosed.new("Communication is closed"))
        @mutex.synchronize { @closed ||= error; @condition.broadcast }
      end

      def clear
        @mutex.synchronize { @items.clear; @bytes = 0 }
      end

      def length
        @mutex.synchronize { @items.length }
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class Waiter
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @done = false
      end

      def resolve(value = nil, error = nil)
        @mutex.synchronize do
          return if @done
          @done = true
          @value, @error = value, error
          @condition.broadcast
        end
      end

      def wait(timeout, pump: nil, cancellation_token: nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout.to_f
        loop do
          cancellation_token&.raise_if_cancelled!
          @mutex.synchronize do
            if @done
              raise @error if @error
              return @value
            end
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise TimeoutError, "Communication request timed out" if remaining <= 0
            @condition.wait(@mutex, [remaining, 0.05].min) unless pump
          end
          pump.call if pump
        end
      end
    end

    class Participant
      attr_reader :id, :user, :metadata, :state

      def initialize(session, data)
        @session = session
        update(data)
      end

      def owner?
        @session.owner_id == @id
      end

      def update(data)
        @id = data["id"].to_s
        @user = data["user"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        @state = (data["state"] || "active").to_sym
        self
      end

      def mark(state)
        @state = state.to_sym
      end
    end

    class Message
      attr_reader :sender, :data, :id, :kind

      def initialize(sender:, data:, id:, kind:)
        @sender = sender
        @data = data.b.freeze
        @id = id.to_i
        @kind = kind.to_sym
      end

      def reliable?
        @kind == :reliable
      end

      def unreliable?
        @kind == :unreliable
      end
    end

    class Delivery
      attr_reader :message_id

      def initialize(session, message_id, statuses)
        @session = session
        @message_id = message_id.to_i
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @statuses = statuses.transform_keys(&:to_s).transform_values { |value| value.to_sym }
        @participants = {}
        @statuses.each_key { |id| @participants[id] = session.participant(id) }
      end

      def update(participant_id, status)
        @mutex.synchronize do
          @statuses[participant_id.to_s] = status.to_sym
          @participants[participant_id.to_s] ||= @session.participant(participant_id)
          @condition.broadcast
        end
        self
      end

      def fail_pending(status = :failed)
        @mutex.synchronize do
          @statuses.each_key { |id| @statuses[id] = status.to_sym if @statuses[id] == :pending }
          @condition.broadcast
        end
        self
      end

      def complete?
        @mutex.synchronize { !@statuses.value?(:pending) }
      end

      def results
        @mutex.synchronize do
          @statuses.each_with_object({}) do |(id, status), output|
            output[@participants[id] || id] = status
          end
        end
      end

      def delivered_to
        results.select { |_, status| status == :delivered }.keys
      end

      def failed_for
        results.reject { |_, status| status == :delivered }.keys
      end

      def wait(timeout: nil, cancellation_token: nil)
        deadline = timeout.nil? ? nil : monotonic + timeout.to_f
        loop do
          cancellation_token&.raise_if_cancelled!
          return self if complete?
          raise TimeoutError, "Delivery confirmation timed out" if deadline && monotonic >= deadline
          @session.wait_step(cancellation_token: cancellation_token)
        end
      end

      def wait!(timeout: nil, cancellation_token: nil)
        wait(timeout: timeout, cancellation_token: cancellation_token)
        raise DeliveryError, self unless @mutex.synchronize { @statuses.values.all? { |status| status == :delivered } }
        self
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class OutgoingInvitation
      attr_reader :id, :user, :status, :participant

      def initialize(endpoint, id, user)
        @endpoint = endpoint
        @id = id.to_s
        @user = user.to_s
        @status = :pending
        @waiter = Waiter.new
      end

      def wait_until_accepted(timeout: 30)
        result = @waiter.wait(timeout, pump: -> { @endpoint.wait_step })
        raise PeerUnavailable, "Invitation was #{@status}" unless @status == :accepted
        result
      end

      def cancel
        @endpoint.cancel_invitation(self)
      end

      def update(status, participant = nil)
        @status = status.to_sym
        @participant = participant
        @waiter.resolve(participant)
      end
    end

    class Invitation
      attr_reader :id, :sender, :metadata, :session_metadata, :participants, :status

      def initialize(endpoint, data)
        @endpoint = endpoint
        @id = data["id"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        session = data["session"].is_a?(Hash) ? data["session"] : {}
        @session_metadata = session["metadata"].is_a?(Hash) ? session["metadata"] : {}
        @participants = Array(session["participants"]).map { |item| InvitationParticipant.new(item) }
        @sender = InvitationParticipant.new(data["sender"] || {})
        @status = :pending
      end

      def accept(metadata: {})
        raise SessionClosed, "Invitation is #{@status}" unless @status == :pending
        session = @endpoint.accept_invitation(self, metadata)
        @status = :accepted
        session
      end

      def reject
        return false unless @status == :pending
        @endpoint.reject_invitation(self)
        @status = :rejected
        true
      end

      def close(status)
        @status = status.to_sym if @status == :pending
      end
    end

    class InvitationParticipant
      attr_reader :id, :user, :metadata

      def initialize(data)
        @id = data["id"].to_s
        @user = data["user"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        @owner = data["owner"] == true
      end

      def owner?
        @owner
      end
    end

    class PublicSession
      attr_reader :id, :metadata, :capacity, :encryption, :participants

      def initialize(data)
        @id = data["id"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        @capacity = data["capacity"].to_i
        @encryption = data["encryption"].to_i
        @participants = Array(data["participants"]).map { |item| InvitationParticipant.new(item) }
      end

      def full?
        @participants.size >= @capacity
      end
    end

    class Session
      attr_reader :id, :metadata, :capacity, :encryption, :owner_id, :state, :self_id, :p2p, :p2p_participants_limit

      def initialize(endpoint, data)
        @endpoint = endpoint
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @messages = EventQueue.new
        @participants = {}
        @keys = {}
        @ciphers = {}
        @snapshot_revision = -1
        @receive_requested = false
        @state = :open
        apply_snapshot(data)
      end

      def p2p_status
        @endpoint.p2p_status(@id)
      end

      def participants
        @mutex.synchronize { @participants.values.dup }
      end

      def participant(id)
        @mutex.synchronize { @participants[id.to_s] }
      end

      def owner
        participant(@owner_id)
      end

      def public?
        @mutex.synchronize { @public == true }
      end

      def public=(value)
        raise ArgumentError, "public must be true or false" unless value == true || value == false
        @endpoint.set_session_public(self, value)
        change_visibility(value)
        value
      end

      def invite(user, metadata: {})
        ensure_open!
        @endpoint.invite(self, user, metadata)
      end

      def invite_all(users, metadata: {})
        Array(users).map { |user| invite(user, metadata: metadata) }
      end

      def send_reliable(data, to: nil)
        ensure_open!
        validate_size!(data, @endpoint.limit(:max_reliable_data))
        @endpoint.send_reliable(self, data.b, target_ids(to))
      end

      def send_unreliable(data, to: nil)
        ensure_open!
        validate_size!(data, @endpoint.limit(:max_unreliable_data))
        @endpoint.send_unreliable(self, data.b, target_ids(to))
        nil
      end

      def receive(timeout: nil, cancellation_token: nil)
        @mutex.synchronize { @receive_requested = true }
        @messages.pop(timeout: timeout, cancellation_token: cancellation_token, pump: -> { wait_step(cancellation_token: cancellation_token) })
      end

      def leave
        return false if @state == :closed
        @endpoint.leave_session(self)
        close_local(:left)
        true
      end

      def close
        ensure_open!
        raise NotOwner, "Only the session owner can close it" unless owner&.id == @endpoint.member_id(@id)
        @endpoint.close_session(self)
        close_local(:closed)
        true
      end

      def remove(participant, reason: nil)
        ensure_participant!(participant)
        @endpoint.remove_participant(self, participant)
        true
      end

      def transfer_ownership(participant)
        ensure_participant!(participant)
        @endpoint.transfer_ownership(self, participant)
        true
      end

      def on_reliable(&block); register_callback(:reliable, &block); end
      def on_unreliable(&block); register_callback(:unreliable, &block); end
      def on_participant_joined(&block); register_callback(:participant_joined, &block); end
      def on_participant_left(&block); register_callback(:participant_left, &block); end
      def on_owner_changed(&block); register_callback(:owner_changed, &block); end
      def on_closed(&block); register_callback(:closed, &block); end

      def wait_for_participant(user = nil, timeout: 30, cancellation_token: nil)
        deadline = monotonic + timeout.to_f
        loop do
          found = @mutex.synchronize do
            raise SessionClosed, "Session is closed" if @state == :closed
            @participants.values.find { |entry| entry.id != @self_id && (user.nil? || entry.user.casecmp?(user.to_s)) }
          end
          return found if found
          raise TimeoutError, "Participant did not join in time" if monotonic >= deadline
          wait_step(cancellation_token: cancellation_token)
        end
      end

      def wait_step(cancellation_token: nil)
        @endpoint.wait_step(cancellation_token: cancellation_token)
      end

      def revision
        @mutex.synchronize { @snapshot_revision }
      end

      def mark_revision(value)
        @mutex.synchronize { @snapshot_revision = [@snapshot_revision, value.to_i].max }
      end

      def current_key
        encryption_state.first(2)
      end

      def encryption_state
        @mutex.synchronize { [@epoch, @keys[@epoch], @ciphers[@epoch]] }
      end

      def associated_data(kind, sender_id, message_id, epoch)
        ["elten-relay-v2", @id, kind.to_s, sender_id.to_s, message_id.to_i, epoch.to_i].join("|")
      end

      def decrypt(epoch, envelope, aad: "")
        key, cipher = @mutex.synchronize { [@keys[epoch.to_i], @ciphers[epoch.to_i]] }
        raise StaleKey, "Unknown key epoch #{epoch}" unless key
        Crypto.decrypt(envelope, @encryption, key, authenticated: cipher == "aead", aad: aad)
      end

      def apply_key(epoch, key, cipher: nil)
        Crypto.validate(@encryption, key)
        @mutex.synchronize do
          number = epoch.to_i
          @keys[number] = key.b
          @ciphers[number] = cipher || @ciphers[@epoch] || "legacy"
          @epoch = [@epoch, number].max
          while @keys.size > 32
            oldest = @keys.keys.min
            @keys.delete(oldest)
            @ciphers.delete(oldest)
          end
        end
      end

      def refresh(data)
        @mutex.synchronize { apply_snapshot(data) }
      end

      def add_participant(data)
        participant = nil
        @mutex.synchronize do
          id = data["id"].to_s
          participant = @participants[id]
          participant == nil ? @participants[id] = participant = Participant.new(self, data) : participant.update(data)
          @condition.broadcast
        end
        emit(:participant_joined, participant)
        participant
      end

      def remove_participant_local(id, reason)
        participant = @mutex.synchronize do
          item = @participants.delete(id.to_s)
          item&.mark(:left)
          @condition.broadcast
          item
        end
        emit(:participant_left, participant, reason.to_sym) if participant != nil
      end

      def change_owner(id)
        @mutex.synchronize { @owner_id = id.to_s }
        emit(:owner_changed, owner)
      end

      def change_visibility(value)
        @mutex.synchronize { @public = value == true }
      end

      def deliver(kind, message)
        @mutex.synchronize do
          discard = ->(entry) { !@receive_requested && !@callbacks[entry[0]].empty? }
          @messages.push([kind.to_sym, message], bytes: message.data.bytesize + 256, discard_if: discard)
        end
        emit(kind.to_sym, message)
        true
      rescue QueueOverflow => error
        return false if kind.to_sym == :unreliable
        @endpoint.record_error(error)
        close_local(:queue_overflow, notify_peer: true)
        false
      end

      def close_local(reason, notify_peer: false)
        changed = @mutex.synchronize do
          next false if @state == :closed
          @state = :closed
          @condition.broadcast
          true
        end
        if changed
          @messages.close
          @endpoint.session_closed(self, reason, notify_peer: notify_peer)
          emit(:closed, reason.to_sym)
        end
        changed
      end

      private

      def apply_snapshot(data)
        revision = data["revision"].to_i
        return if revision < @snapshot_revision
        @snapshot_revision = revision
        @id = data["id"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        @capacity = data["capacity"].to_i
        @p2p = %w[partial full].include?(data["p2p"]) ? data["p2p"].to_sym : :off
        @p2p_participants_limit = data.fetch("p2p_participants_limit", 2).to_i
        @public = data["public"] == true
        @encryption = data["encryption"].to_i
        @owner_id = data["owner_id"].to_s
        @epoch = [@epoch.to_i, data["epoch"].to_i].max
        key = Base64.strict_decode64(data["key"].to_s)
        Crypto.validate(@encryption, key)
        @keys[data["epoch"].to_i] = key
        @ciphers[data["epoch"].to_i] = data["cipher"] || "legacy"
        while @keys.size > 32
          oldest = @keys.keys.min
          @keys.delete(oldest)
          @ciphers.delete(oldest)
        end
        previous = @participants
        @participants = {}
        @self_id = data["self_id"] || Array(data["participants"]).find { |row| row["user"].to_s.casecmp?(@endpoint.user.to_s) }&.fetch("id", nil)
        Array(data["participants"]).each do |participant|
          item = previous[participant["id"].to_s]
          item ? item.update(participant) : item = Participant.new(self, participant)
          @participants[item.id] = item
        end
      rescue ArgumentError
        raise ConnectionError, "Server returned an invalid session key"
      end

      def target_ids(targets)
        return [] if targets == nil || targets == :all
        Array(targets).map do |participant|
          ensure_participant!(participant)
          participant.id
        end.uniq
      end

      def ensure_participant!(participant)
        raise ArgumentError, "participant does not belong to this session" unless participant.is_a?(Participant) && self.participant(participant.id).equal?(participant)
      end

      def ensure_open!
        raise SessionClosed, "Session is closed" unless @state == :open
      end

      def validate_size!(data, maximum)
        raise ArgumentError, "data must be a String" unless data.is_a?(String)
        raise MessageTooLarge, "Message exceeds #{maximum} bytes" if data.bytesize > maximum
      end

      def register_callback(kind, &block)
        raise ArgumentError, "callback is required" if block == nil
        @mutex.synchronize do
          @callbacks[kind] << block
        end
        self
      end

      def emit(kind, *arguments)
        callbacks = @mutex.synchronize { @callbacks[kind].dup }
        callbacks.each { |callback| @endpoint.enqueue_callback(callback, *arguments) }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class Endpoint
      attr_reader :app_id, :user, :last_error

      def initialize(app_id:, user: nil, token: nil, host: DEFAULT_HOST, port: DEFAULT_PORT, timeout: 5, context: nil)
        @app_id = app_id.to_s
        @user = (user || EltenAPI::Structs::Session.name).to_s
        relay_token = (token || EltenAPI::Structs::Session.token).to_s
        raise AuthenticationError, "Elten user is not logged in" if @user.empty? || relay_token.empty?
        raise ArgumentError, "app_id is required" if @app_id.empty? || @app_id == "0"

        @mutex = Mutex.new
        @callback_mutex = Mutex.new
        @delivery_mutex = Mutex.new
        @sessions = {}
        @invitations = {}
        @outgoing_invitations = {}
        @deliveries = {}
        @pending_delivery_updates = Hash.new { |hash, key| hash[key] = [] }
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @callback_queue = EventQueue.new
        @event_mutex = Monitor.new
        @protocol_mutex = Mutex.new
        @dispatch_mutex = Mutex.new
        @context = context || (Object.new.extend(EltenAPI) if defined?(EltenAPI::UI))
        @pending_events = Hash.new { |hash, key| hash[key] = [] }
        @pending_event_bytes = 0
        @early_invitations = {}
        @closed_sessions = {}
        @recover_sessions = {}
        @pending_leaves = {}
        @work_responses = Queue.new
        @work_pending = nil
        @work_serial = 0
        @next_work_at = 0.0
        @overflow = false
        @last_error = nil
        @invitation_queue = EventQueue.new
        @received = {}
        @received_reliable = {}
        @next_received_cleanup = 0.0
        @received_mutex = Mutex.new
        @message_serial = SecureRandom.random_number(1 << 48)
        @closed = false
        @close_complete = false
        @connection_waiter = Waiter.new
        @connect_options = {
          app_id: @app_id, user: @user, token: relay_token, host: host, port: port,
          timeout: timeout, tls_context: EltenAPI::TLS.client_context, event_sink: self
        }
        Communication.register(self)
        @relay = @connection_waiter.wait(timeout.to_f + 1, pump: -> { wait_step })
      rescue EltenLink::Relay::Error => error
        @closed = true
        Communication.unregister(self)
        @relay&.close
        raise translate_relay_error(error)
      rescue Exception
        @closed = true
        Communication.unregister(self)
        @relay&.close
        raise
      end

      def create_session(metadata: {}, participant_metadata: {}, capacity: 2, public: false, encryption: 192, p2p: :off, p2p_participants_limit: 2)
        result = relay_call do
          @relay.create_session(
            metadata: metadata,
            participant_metadata: participant_metadata,
            capacity: capacity,
            public_state: public,
            encryption: encryption, p2p: p2p, p2p_participants_limit: p2p_participants_limit
          )
        end
        store_session(result)
      end

      def public_sessions
        relay_call { @relay.public_sessions }.map { |data| PublicSession.new(data) }
      end

      def join(public_session, participant_metadata: {})
        session_id = public_session.respond_to?(:id) ? public_session.id : public_session.to_s
        result = relay_call do
          @relay.join_public_session(session_id: session_id, participant_metadata: participant_metadata)
        end
        store_session(result)
      end

      alias join_public_session join

      def connect(user, metadata: {}, participant_metadata: {}, encryption: 192, timeout: 10, p2p: :off, p2p_participants_limit: 2)
        session = create_session(metadata: metadata, participant_metadata: participant_metadata,
                                 capacity: 2, encryption: encryption, p2p: p2p, p2p_participants_limit: p2p_participants_limit)
        invitation = session.invite(user)
        invitation.wait_until_accepted(timeout: timeout)
        session.wait_for_participant(user, timeout: timeout)
        session
      rescue Exception
        session&.close rescue nil
        raise
      end

      def sessions
        @mutex.synchronize { @sessions.values.dup }
      end

      def on_invitation(&block)
        register_callback(:invitation, &block)
      end

      def on_closed(&block)
        register_callback(:closed, &block)
      end

      def next_invitation(timeout: nil)
        @invitation_queue.pop(timeout: timeout, pump: -> { wait_step })
      end

      def p2p_status(session_id)
        @relay.p2p_status(session_id)
      end

      def fast_path?
        @relay != nil && @relay.fast_path?
      end

      def limits
        @relay == nil ? DEFAULT_LIMITS.dup : @relay.limits
      end

      def limit(name)
        @relay == nil ? DEFAULT_LIMITS.fetch(name.to_sym) : @relay.limit(name)
      end

      def latency
        @relay&.latency
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def close
        return false if closed?
        @relay&.close
        fail_connection(ConnectionError.new("Communication endpoint was closed"), :closed)
        true
      end

      def dispatch_events(limit = 100)
        dispatch_callbacks(limit)
      end

      def callbacks_pending?
        @callback_queue.length.positive? || @mutex.synchronize { @closed && !@close_complete }
      end

      def enqueue_callback(callback, *arguments)
        bytes = arguments.sum do |value|
          if value.is_a?(Message)
            value.data.bytesize + 256
          elsif value.respond_to?(:metadata)
            JSON.generate(value.metadata).bytesize + 256
          else
            JSON.generate(value).bytesize + 64
          end
        end
        @callback_queue.push([callback, arguments], bytes: bytes)
      rescue QueueOverflow
        @overflow = true
        raise
      end

      def member_id(session_id)
        @mutex.synchronize { @sessions[session_id.to_s]&.self_id }
      end

      def wait_step(cancellation_token: nil)
        cancellation_token&.raise_if_cancelled!
        owner = $currentthread if defined?($currentthread)
        owner ||= $mainthread if defined?($mainthread)
        owner ||= Thread.main
        if @context && @context.respond_to?(:loop_update, true) && (owner.nil? || owner == Thread.current)
          @context.__send__(:loop_update, false)
        else
          sleep 0.01
        end
        cancellation_token&.raise_if_cancelled!
      end

      def on_error(&block)
        register_callback(:error, &block)
      end

      def record_error(error)
        @last_error = error
        Log.warning("Communication error: #{error.class}: #{error.message}") if defined?(Log)
        emit(:error, error)
      rescue QueueOverflow
        @overflow = true
      end

      def session_closed(session, reason, notify_peer: false)
        @mutex.synchronize do
          @sessions.delete(session.id) if @sessions[session.id].equal?(session)
          @closed_sessions[session.id] = monotonic
          @pending_leaves[session.id] = true if notify_peer && !@closed
          @recover_sessions.delete(session.id)
        end
        fail_session_operations(session.id, reason)
      end

      def protocol_tick
        return false if closed? || !@protocol_mutex.try_lock
        begin
          if @connect_options
            options = @connect_options
            @connect_options = nil
            Thread.new do
              begin
                next if closed?
                relay = EltenLink::Relay::Client.new(**options)
                if closed?
                  relay.close
                else
                  @relay = relay
                  @connection_waiter.resolve(relay)
                end
              rescue StandardError => error
                @connection_waiter.resolve(nil, error)
              end
            end
          end
          @relay&.tick
          drain_work
          now = monotonic
          @event_mutex.synchronize do
            @early_invitations.delete_if { |_id, row| now - row[0] > 60 }
            @pending_events.each_value do |events|
              while events.first && now - events.first[2] > 25
                pending, bytes = events.shift
                @pending_event_bytes -= bytes
                relay, frame = pending
                if frame["type"] == "message" && frame["kind"] == "reliable"
                  acknowledge(relay, frame["session_id"], frame["sender_id"], frame["message_id"], "failed")
                  record_error(StaleKey.new("Cannot recover the state needed to receive a reliable message"))
                  session_for(frame)&.close_local(:state_unavailable, notify_peer: true)
                end
              end
            end
            @pending_events.delete_if { |_id, events| events.empty? }
          end
          @mutex.synchronize { @closed_sessions.delete_if { |_id, time| now - time > 60 } }
          @delivery_mutex.synchronize do
            @pending_delivery_updates.delete_if { |_key, rows| rows.empty? || now - rows.first[2] > 60 }
          end
          if @overflow
            @overflow = false
            @callback_queue.clear
            record_error(QueueOverflow.new("Communication callback queue is full"))
            sessions.each { |session| session.close_local(:queue_overflow, notify_peer: true) }
          end
          if @work_pending && now >= @work_pending[:deadline]
            @work_pending[:deadline] = Float::INFINITY
            @relay.close
            fail_connection(TimeoutError.new("Communication state recovery timed out"), :connection_lost)
            @next_work_at = now + 1
            record_error(TimeoutError.new("Communication state recovery timed out"))
          end
          start_work if @relay && !@work_pending && now >= @next_work_at
          true
        ensure
          @protocol_mutex.unlock
        end
      end

      def invite(session, user, metadata)
        result = relay_call { @relay.invite(session_id: session.id, user: user, metadata: metadata) }
        @event_mutex.synchronize do
          existing = @mutex.synchronize { @outgoing_invitations[result["id"].to_s] }
          return existing.first if existing
          invitation = OutgoingInvitation.new(self, result["id"], user)
          @mutex.synchronize { @outgoing_invitations[invitation.id] = [invitation, session] }
          pending = @early_invitations.delete(invitation.id)
          handle_invitation_status(pending[1]) if pending
          invitation
        end
      end

      def cancel_invitation(invitation)
        relay_call { @relay.cancel_invitation(invitation_id: invitation.id) }
        invitation.update(:cancelled)
        @mutex.synchronize { @outgoing_invitations.delete(invitation.id) }
        true
      end

      def accept_invitation(invitation, metadata)
        result = relay_call do
          @relay.accept_invitation(invitation_id: invitation.id, participant_metadata: metadata)
        end
        @mutex.synchronize { @invitations.delete(invitation.id) }
        store_session(result)
      end

      def reject_invitation(invitation)
        relay_call { @relay.reject_invitation(invitation_id: invitation.id) }
        @mutex.synchronize { @invitations.delete(invitation.id) }
        true
      end

      def leave_session(session)
        relay_call { @relay.leave_session(session_id: session.id) }
        fail_session_operations(session.id, :left)
        @mutex.synchronize { @sessions.delete(session.id) }
      end

      def close_session(session)
        relay_call { @relay.close_session(session_id: session.id) }
        fail_session_operations(session.id, :closed)
        @mutex.synchronize { @sessions.delete(session.id) }
      end

      def remove_participant(session, participant)
        relay_call { @relay.remove_participant(session_id: session.id, participant_id: participant.id) }
      end

      def transfer_ownership(session, participant)
        relay_call { @relay.transfer_ownership(session_id: session.id, participant_id: participant.id) }
      end

      def set_session_public(session, value)
        relay_call { @relay.set_session_public(session_id: session.id, public_state: value) }
      end

      def send_reliable(session, data, targets)
        attempts = 0
        message_id = next_message_id
        begin
          attempts += 1
          epoch, key, cipher = session.encryption_state
          envelope = Crypto.encrypt(data, session.encryption, key, authenticated: cipher == "aead", aad: session.associated_data(:reliable, session.self_id, message_id, epoch))
          result = relay_call do
            @relay.send_reliable(
              session_id: session.id,
              epoch: epoch,
              message_id: message_id,
              targets: targets,
              envelope: envelope
            )
          end
          delivery = Delivery.new(session, message_id, result["statuses"] || {})
          @delivery_mutex.synchronize do
            key_id = [session.id, message_id]
            @deliveries[key_id] = delivery unless delivery.complete?
            @pending_delivery_updates.delete(key_id).to_a.each do |participant_id, status|
              delivery.update(participant_id, status)
            end
            @deliveries.delete(key_id) if delivery.complete?
          end
          delivery
        rescue StaleKey
          if attempts < 2
            request_recovery(session.id)
            until monotonic >= (until_time ||= monotonic + 5) || session.encryption_state.first > epoch || session.state == :closed
              wait_step
            end
            retry unless session.state == :closed
          end
          raise
        end
      end

      def send_unreliable(session, data, targets)
        epoch, key, cipher = session.encryption_state
        message_id = next_message_id
        envelope = Crypto.encrypt(data, session.encryption, key, authenticated: cipher == "aead", aad: session.associated_data(:unreliable, session.self_id, message_id, epoch))
        relay_call do
          @relay.send_unreliable(
            session_id: session.id,
            epoch: epoch,
            message_id: message_id,
            targets: targets,
            envelope: envelope
          )
        end
        nil
      end

      private

      def dispatch_scene_events(scene)
        return 0 unless @context.equal?(scene)
        dispatch_callbacks(32, scene)
      end

      def dispatch_callbacks(limit, scene = nil)
        return 0 unless @dispatch_mutex.try_lock
        count = 0
        begin
          started = monotonic
          while count < limit && monotonic - started < 0.01
            break if scene && (!Thread.current.equal?($currentthread) || !Thread.current.thread_variable_get(:elten_scene).equal?(scene))
            entry = @callback_queue.pop(timeout: 0)
            break unless entry
            callback, arguments = entry
            begin
              callback.call(*arguments)
            rescue Exception => error
              Log.warning("Communication callback failed: #{error.class}: #{error.message}") if defined?(Log)
            end
            count += 1
          end
        ensure
          @dispatch_mutex.unlock
        end
        count
      end

      def relay_event(relay, frame)
        return unless frame.is_a?(Hash) && !closed?
        @event_mutex.synchronize do
          id = frame["session_id"].to_s
          if !id.empty? && !session_for(frame)
            return if @mutex.synchronize { @closed_sessions.key?(id) }
            buffer_event(relay, frame)
            return
          end
          session = session_for(frame)
          if session && frame["revision"] && frame["type"] != "session_key"
            return if frame["revision"].to_i < session.revision
            session.mark_revision(frame["revision"])
          end
          dispatch_relay_event(relay, frame)
          replay_pending(id) if frame["type"] == "session_key" || frame["type"] == "participant_joined"
        end
      rescue QueueOverflow => error
        @overflow = true
        record_error(error)
      end

      def buffer_event(relay, frame)
        bytes = frame["raw_data"] ? frame["raw_data"].bytesize + 512 : JSON.generate(frame).bytesize
        id = frame["session_id"].to_s
        raise QueueOverflow, "Communication event queue is full" if @pending_event_bytes + bytes > MAX_QUEUE_BYTES || @pending_events.values.sum(&:length) >= MAX_QUEUE_ITEMS
        @pending_events[id] << [[relay, frame], bytes, monotonic]
        @pending_event_bytes += bytes
      end

      def replay_pending(id)
        rows = @pending_events.delete(id) || []
        @pending_event_bytes -= rows.sum { |row| row[1] }
        rows.each { |row| relay_event(*row[0]) }
      end

      def request_recovery(id)
        @mutex.synchronize { @recover_sessions[id] = true unless @closed || @closed_sessions.key?(id) }
      end

      def start_work
        return if closed?
        jobs = @mutex.synchronize do
          @pending_leaves.keys.first(8).map { |id| [:leave, id] } +
            (@relay.supports?("session_sync") ? @recover_sessions.keys.first(8).map { |id| [:state, id] } : [])
        end
        return if jobs.empty?
        @work_serial += 1
        serial = @work_serial
        @work_pending = { serial: serial, deadline: monotonic + jobs.length * 5 + 1 }
        Thread.new do
          results = jobs.map do |kind, id|
            begin
              data = kind == :leave ? @relay.leave_session(session_id: id) : @relay.session_state(session_id: id)
              [kind, id, data, nil]
            rescue StandardError => error
              [kind, id, nil, error]
            end
          end
          @work_responses << [serial, results]
        end
      end

      def drain_work
        loop do
          serial, results = @work_responses.pop(true)
          next unless @work_pending && @work_pending[:serial] == serial
          @work_pending = nil
          results.each do |kind, id, data, error|
            if error
              permanent = error.respond_to?(:code) && %w[not_a_participant session_not_found session_closed].include?(error.code)
              if permanent
                session_for({ "session_id" => id })&.close_local(:expired)
                @mutex.synchronize { @pending_leaves.delete(id); @recover_sessions.delete(id) }
              else
                record_error(error)
                @next_work_at = monotonic + 1
              end
            elsif kind == :leave
              @mutex.synchronize { @pending_leaves.delete(id) }
            else
              @event_mutex.synchronize do
                session_for({ "session_id" => id })&.refresh(data)
                @mutex.synchronize { @recover_sessions.delete(id) }
                replay_pending(id)
              end
            end
          end
        end
      rescue ThreadError
        nil
      end

      def dispatch_relay_event(relay, frame)
        return unless frame.is_a?(Hash)
        case frame["type"]
        when "invitation" then handle_invitation(frame)
        when "invitation_closed" then handle_invitation_closed(frame)
        when "invitation_status" then handle_invitation_status(frame)
        when "participant_joined" then session_for(frame)&.add_participant(frame["participant"] || {})
        when "participant_left" then session_for(frame)&.remove_participant_local(frame["participant_id"], frame["reason"] || "left")
        when "owner_changed" then session_for(frame)&.change_owner(frame["owner_id"])
        when "session_visibility" then session_for(frame)&.change_visibility(frame["public"])
        when "session_key" then handle_session_key(frame)
        when "session_closed" then handle_session_closed(frame)
        when "message" then handle_message(relay, frame)
        when "delivery" then handle_delivery(frame)
        when "operation_error" then record_error(RemoteError.new(frame["error"]))
        end
      end

      def relay_closed(relay, error, reason)
        @relay ||= relay
        fail_connection(translate_relay_error(error), reason)
      end

      def relay_call
        yield
      rescue EltenLink::Relay::Error => error
        raise translate_relay_error(error)
      end

      def handle_invitation(frame)
        invitation = Invitation.new(self, frame)
        @mutex.synchronize { @invitations[invitation.id] = invitation }
        @invitation_queue.push(invitation, bytes: JSON.generate(frame).bytesize, discard_if: ->(entry) { entry.status != :pending })
        emit(:invitation, invitation)
      end

      def handle_invitation_closed(frame)
        invitation = @mutex.synchronize { @invitations.delete(frame["invitation_id"].to_s) }
        invitation&.close(frame["status"] || "closed")
      end

      def handle_invitation_status(frame)
        pair = @mutex.synchronize { @outgoing_invitations.delete(frame["invitation_id"].to_s) }
        if pair.nil?
          @early_invitations[frame["invitation_id"].to_s] = [monotonic, frame]
          @early_invitations.shift while @early_invitations.length > 128
          return
        end
        invitation, session = pair
        participant_data = frame["participant"]
        participant = participant_data.is_a?(Hash) ? session.participant(participant_data["id"]) : nil
        invitation.update(frame["status"] || "closed", participant)
      end

      def handle_session_key(frame)
        session = session_for(frame)
        return if session == nil
        session.apply_key(frame["epoch"], Base64.strict_decode64(frame["key"].to_s), cipher: frame["cipher"])
      rescue ArgumentError
        fail_connection(ConnectionError.new("Server returned an invalid session key"), :protocol_error)
      end

      def handle_session_closed(frame)
        session = @mutex.synchronize { @sessions.delete(frame["session_id"].to_s) }
        fail_session_operations(frame["session_id"], :session_closed)
        session&.close_local(frame["reason"] || "closed")
      end

      def handle_message(relay, frame)
        session = session_for(frame)
        return if session == nil
        kind = (frame["kind"] || "unreliable").to_sym
        sender_id = frame["sender_id"].to_s
        message_id = frame["message_id"].to_i
        if duplicate_message?(session.id, sender_id, message_id, kind, retain_reliable: session.p2p == :full)
          acknowledge(relay, session.id, sender_id, message_id, "delivered") if kind == :reliable
          return
        end
        envelope = frame["raw_data"] || Base64.strict_decode64(frame["data"].to_s)
        sender = session.participant(sender_id) || (Participant.new(session, frame["sender"]) if frame["sender"].is_a?(Hash) && frame["sender"]["id"] == sender_id)
        if sender.nil?
          buffer_event(relay, frame)
          request_recovery(session.id)
          return
        end
        data = session.decrypt(frame["epoch"], envelope, aad: session.associated_data(kind, sender_id, message_id, frame["epoch"]))
        delivered = session.deliver(kind, Message.new(sender: sender, data: data, id: message_id, kind: kind))
        unless delivered
          acknowledge(relay, session.id, sender_id, message_id, "failed") if kind == :reliable
          return
        end
        remember_message(session.id, sender_id, message_id, kind, retain_reliable: session.p2p == :full)
        acknowledge(relay, session.id, sender_id, message_id, "delivered") if kind == :reliable
      rescue StaleKey
        buffer_event(relay, frame)
        request_recovery(session.id)
      rescue Exception => error
        acknowledge(relay, frame["session_id"], frame["sender_id"], frame["message_id"], "failed") if frame["kind"] == "reliable"
        Log.warning("Communication message rejected: #{error.class}: #{error.message}") if defined?(Log)
      end

      def handle_delivery(frame)
        key = [frame["session_id"].to_s, frame["message_id"].to_i]
        @delivery_mutex.synchronize do
          delivery = @deliveries[key]
          if delivery == nil
            return if @mutex.synchronize { @closed_sessions.key?(key[0]) }
            @pending_delivery_updates[key] << [frame["participant_id"], frame["status"], monotonic]
            @pending_delivery_updates[key].shift while @pending_delivery_updates[key].length > MAX_PARTICIPANTS
            @pending_delivery_updates.shift while @pending_delivery_updates.length > 4096
          else
            delivery.update(frame["participant_id"], frame["status"])
            @deliveries.delete(key) if delivery.complete?
          end
        end
      end

      def acknowledge(relay, session_id, sender_id, message_id, status)
        relay.acknowledge(
          session_id: session_id,
          sender_id: sender_id,
          message_id: message_id,
          status: status
        )
      end

      def store_session(data)
        @event_mutex.synchronize do
          session = Session.new(self, data)
          @mutex.synchronize do
            raise ConnectionError, "Communication endpoint is closed" if @closed
            @sessions[session.id] = session
          end
          replay_pending(session.id)
          session
        end
      end

      def session_for(frame)
        @mutex.synchronize { @sessions[frame["session_id"].to_s] }
      end

      def translate_relay_error(error)
        code = error.respond_to?(:code) ? error.code.to_s : ""
        klass = case error
                when EltenLink::Relay::AuthenticationError then AuthenticationError
                when EltenLink::Relay::ConnectionError then ConnectionError
                when EltenLink::Relay::TimeoutError then TimeoutError
                when EltenLink::Relay::MessageTooLarge then MessageTooLarge
                else
                  case code
                  when "authentication_failed", "not_authenticated" then AuthenticationError
                  when "peer_unavailable" then PeerUnavailable
                  when "session_closed", "session_not_found" then SessionClosed
                  when "message_too_large" then MessageTooLarge
                  when "not_owner" then NotOwner
                  when "stale_key" then StaleKey
                  when "request_expired" then TimeoutError
                  else RemoteError
                  end
                end
        klass == RemoteError ? klass.new(code, error.message) : klass.new(error.message)
      end

      def register_callback(kind, &block)
        raise ArgumentError, "callback is required" if block == nil
        @callback_mutex.synchronize { @callbacks[kind] << block }
        self
      end

      def emit(kind, *arguments)
        callbacks = @callback_mutex.synchronize { @callbacks[kind].dup }
        callbacks.each { |callback| enqueue_callback(callback, *arguments) }
      end

      def next_message_id
        @mutex.synchronize do
          @message_serial = (@message_serial + 1) & 0xffffffffffffffff
        end
      end

      def duplicate_message?(session_id, sender_id, message_id, kind, retain_reliable: false)
        @received_mutex.synchronize do
          key = [session_id, sender_id, message_id, kind]
          return @received.key?(key) unless kind == :reliable && retain_reliable
          now = monotonic
          if now >= @next_received_cleanup
            @received_reliable.delete_if { |_id, time| now - time > 120 }
            @next_received_cleanup = now + 1
          end
          return true if @received_reliable.key?(key)
          # Never evict a live reliable receipt under unreliable traffic: a
          # direct retransmission or relay fallback must not execute it twice.
          raise QueueOverflow, "Reliable receipt cache is full" if @received_reliable.size >= 65_536
          false
        end
      end

      def remember_message(session_id, sender_id, message_id, kind, retain_reliable: false)
        @received_mutex.synchronize do
          if kind == :reliable && retain_reliable
            @received_reliable[[session_id, sender_id, message_id, kind]] = monotonic
            return
          end
          @received[[session_id, sender_id, message_id, kind]] = monotonic
          @received.shift while @received.size > 4096
        end
      end

      def fail_session_operations(session_id, status)
        session_id = session_id.to_s
        deliveries = @delivery_mutex.synchronize do
          selected = @deliveries.select { |(id, _), _| id == session_id }
          selected.each_key { |key| @deliveries.delete(key) }
          selected.values
        end
        deliveries.each { |delivery| delivery.fail_pending(status) }
        invitations = @mutex.synchronize do
          selected = @outgoing_invitations.select { |_, (_, session)| session.id == session_id }
          selected.each_key { |key| @outgoing_invitations.delete(key) }
          selected.values.map(&:first)
        end
        invitations.each { |invitation| invitation.update(status) }
      end

      def fail_connection(error, reason)
        changed = @mutex.synchronize do
          next false if @closed
          @closed = true
          true
        end
        return unless changed
        @invitation_queue.close
        @relay&.close
        deliveries = @delivery_mutex.synchronize do
          current = @deliveries.values
          @deliveries = {}
          @pending_delivery_updates.clear
          current
        end
        deliveries.each { |delivery| delivery.fail_pending(:connection_lost) }
        outgoing = @mutex.synchronize do
          current = @outgoing_invitations.values.map(&:first)
          @outgoing_invitations = {}
          @invitations.each_value { |invitation| invitation.close(:connection_lost) }
          @invitations = {}
          current
        end
        outgoing.each { |invitation| invitation.update(:connection_lost) }
        sessions = @mutex.synchronize do
          current = @sessions.values
          @sessions = {}
          current
        end
        sessions.each do |session|
          begin
            session.close_local(reason)
          rescue QueueOverflow
            @callback_queue.clear
          end
        end
        @event_mutex.synchronize { @pending_events.clear; @pending_event_bytes = 0 }
        @last_error = error
        begin
          emit(:closed, error)
        rescue QueueOverflow
          @callback_queue.clear
          emit(:closed, error)
        end
      ensure
        @mutex.synchronize { @close_complete = true } if changed
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class << self
      def register(endpoint)
        endpoints_mutex.synchronize { endpoints << endpoint unless endpoints.include?(endpoint) }
      end

      def unregister(endpoint)
        endpoints_mutex.synchronize { endpoints.delete(endpoint) }
      end

      def tick(dispatch: true)
        current = endpoints_mutex.synchronize { endpoints.dup }
        current.each do |endpoint|
          begin
            endpoint.protocol_tick
          rescue StandardError => error
            endpoint.record_error(error)
          end
        end
        count = 0
        if dispatch && !@dispatching
          @dispatching = true
          begin
            count = current.sum(&:dispatch_events)
          ensure
            @dispatching = false
          end
        end
        current.each { |endpoint| unregister(endpoint) if endpoint.closed? && !endpoint.callbacks_pending? }
        count
      end

      private

      def dispatch_scene_events(scene)
        current = endpoints_mutex.synchronize { endpoints.dup }
        current.each { |endpoint| endpoint.__send__(:dispatch_scene_events, scene) }
      end

      def endpoints
        @endpoints ||= []
      end

      def endpoints_mutex
        @endpoints_mutex ||= Mutex.new
      end
    end
  end
end
