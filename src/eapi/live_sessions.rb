# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# frozen_string_literal: true

require "json"
require "securerandom"
require "thread"

module EltenAPI
  module LiveSessions
    CONTROL_INTERVAL = 5.0
    CONTROL_TIMEOUT = 5.0
    CONTROL_RETRY_INTERVAL = 1.0
    ACK_INTERVAL = 0.1
    MAX_QUEUE_ITEMS = 4_096
    MAX_QUEUE_BYTES = 8 * 1024 * 1024
    MAX_PENDING_INVITATIONS = 128
    DEFAULT_STACK_ENTRY_BYTES = 256
    DEFAULT_STACK_ENTRIES = 0
    DEFAULT_POOL_COUNT = 0
    LEGACY_STACK_ENTRIES = 1024
    LEGACY_POOL_COUNT = 1
    STACK_MESSAGE_PAGE_SIZE = 128

    class Error < StandardError; end
    class TimeoutError < Error; end
    class SessionClosed < Error; end
    class NotOwner < Error; end
    class OwnershipTransferUnsupported < Error; end
    class QueueOverflow < Error; end
    class StackPacketTooLarge < Error; end
    class StackFull < Error; end
    class StackUnsupported < Error; end
    class StackDisabled < Error; end
    class PoolsDisabled < Error; end
    class DiscoveryUnsupported < Error; end
    class PoolUnsupported < Error; end
    class PoolLimit < Error; end
    class PoolExhausted < Error; end
    class PoolPacketTooLarge < Error; end
    class RandomUnsupported < Error; end
    class RandomPacketTooLarge < Error; end
    class PrivateMessagesUnsupported < Error; end
    class PrivateMessagesDisabled < Error; end
    class MessagePacketTooLarge < Error; end

    Message = Struct.new(:id, :sequence, :sender, :packet, keyword_init: true) do
      attr_accessor :metadata

      def regular?
        metadata&.regular? == true
      end
    end

    class MessageMetadata
      attr_reader :id, :sequence, :origin, :created_at, :min, :max, :count, :draw_number, :kind, :operation, :pool_id, :visibility, :recipient_user

      def initialize(envelope)
        @id = envelope["message_id"].to_s.dup.freeze
        @sequence = envelope["seq"].to_i
        @created_at = envelope["created_at"]
        @origin = :participant
        @kind = :message
        @visibility = envelope["visibility"] == "private" ? :private : :public
        if private?
          recipient = envelope["recipient_user"]
          unless recipient.is_a?(String) && !recipient.strip.empty? && recipient.bytesize <= 64
            raise EltenLink::Error.new("Invalid private message recipient", code: "invalid_json")
          end
          @recipient_user = recipient.dup.freeze
        end
        if envelope["origin"] == "server"
          random = envelope["random"]
          values = envelope["packet"].is_a?(Hash) && envelope["packet"]["values"]
          valid = random.is_a?(Hash) && random.values_at("min", "max", "count").all? { |value| value.is_a?(Integer) }
          valid &&= random["min"] <= random["max"] && random["count"].positive? &&
            values.is_a?(Array) && values.length == random["count"] &&
            values.all? { |value| value.is_a?(Integer) && value.between?(random["min"], random["max"]) }
          raise EltenLink::Error.new("Invalid server random message", code: "invalid_json") unless valid
          @origin = :server
          @kind = :random
          @min, @max, @count = random.values_at("min", "max", "count")
          @draw_number = random["draw_number"]
        elsif envelope["origin"] == "server_pool"
          pool, packet = envelope.values_at("pool", "packet")
          valid = pool.is_a?(Hash) && packet.is_a?(Hash) && pool["id"].is_a?(String) &&
            pool["id"] == packet["pool_id"] && %w[create take reveal delete].include?(pool["operation"])
          raise EltenLink::Error.new("Invalid server pool message", code: "invalid_json") unless valid
          @origin, @kind = :server, :pool
          @operation = pool["operation"].to_sym
          @pool_id = pool["id"].dup.freeze
        end
        @regular = @origin == :participant && @kind == :message &&
          [nil, "participant"].include?(envelope["origin"]) && [nil, "public"].include?(envelope["visibility"]) &&
          [nil, "message"].include?(envelope["kind"]) && [nil, "message"].include?(envelope["type"])
        freeze
      end

      def regular?
        @regular
      end

      def private?
        @visibility == :private
      end

      def server_random?
        @origin == :server && @kind == :random
      end

      def server_pool?
        @origin == :server && @kind == :pool
      end
    end

    class EventQueue
      def initialize(limit: MAX_QUEUE_ITEMS, max_bytes: MAX_QUEUE_BYTES)
        @items = []
        @bytes = 0
        @limit, @max_bytes = limit, max_bytes
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @closed = nil
      end

      def push(item, bytes: 1)
        @mutex.synchronize do
          raise @closed if @closed
          raise QueueOverflow, "Live session queue is full" if @items.length >= @limit || @bytes + bytes > @max_bytes
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
              item, bytes = @items.shift
              @bytes -= bytes
              return item
            end
            raise @closed if @closed
            remaining = deadline.nil? ? nil : deadline - monotonic
            return nil if remaining && remaining <= 0
            @condition.wait(@mutex, [remaining || 0.05, 0.05].min) unless pump
          end
          pump.call if pump
        end
      end

      def close(error = SessionClosed.new("Live session is closed"))
        @mutex.synchronize { @closed ||= error; @condition.broadcast }
      end

      def clear
        @mutex.synchronize { @items.clear; @bytes = 0 }
      end

      def delete_if
        @mutex.synchronize do
          @items.delete_if do |item, bytes|
            remove = yield(item)
            @bytes -= bytes if remove
            remove
          end
        end
      end

      def size
        @mutex.synchronize { @items.length }
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class Participant
      attr_reader :id, :user, :metadata, :joined_at

      def initialize(data)
        update(data)
      end

      def update(data)
        @id = data["id"].to_s
        @user = data["user"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        @joined_at = data["joined_at"].to_i
        self
      end
    end

    def self.immutable_copy(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[immutable_copy(key)] = immutable_copy(item) }.freeze
      when Array
        value.map { |item| immutable_copy(item) }.freeze
      when String
        value.dup.freeze
      else
        value
      end
    end

    class PoolDraw
      attr_reader :id, :pool_id, :values, :visibility, :context, :created_at, :revealed_values, :user, :participant_id

      def initialize(pool, data)
        @pool = pool
        value = LiveSessions.immutable_copy(data)
        @id, @pool_id, @values, @context, @created_at, @revealed_values, @user, @participant_id =
          value.values_at("id", "pool_id", "values", "context", "created_at", "revealed_values", "user", "participant_id")
        @visibility = value["visibility"].to_s.to_sym
        freeze
      end

      def reveal(**options)
        @pool.reveal(@id, **options)
      end
    end

    class PoolDrawPage
      include Enumerable
      attr_reader :items, :next_cursor

      def initialize(pool, data)
        @items = data.fetch("draws").map { |draw| PoolDraw.new(pool, draw) }.freeze
        @next_cursor = data["next_cursor"]
        freeze
      end

      def each(&block)
        @items.each(&block)
      end
    end

    class Pool
      attr_reader :id

      def initialize(session, id)
        raise ArgumentError, "Invalid pool_id" unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9_-]{16,64}\z/)
        @session, @id = session, id.dup.freeze
      end

      def state(timeout: 45, cancellation_token: nil)
        @session.pool_request(:state, {}, pool_id: @id, timeout: timeout, cancellation_token: cancellation_token).fetch("pool")
      end

      def take(count: 1, visibility: :public, context: nil, delivery: :message, message_id: nil, retries: 2, timeout: 45, cancellation_token: nil)
        params = { "count" => count, "visibility" => visibility.to_s, "context" => context, "delivery" => delivery.to_s,
          "message_id" => @session.pool_message_id(message_id) }
        validate_take!(params)
        snapshot = state(timeout: timeout, cancellation_token: cancellation_token)
        validator = ->(first = true) { validate_take!(params, snapshot, capacity: message_id.nil? && first) }
        validator.call
        data = @session.pool_request(:take, params, pool_id: @id, retries: retries, timeout: timeout,
          cancellation_token: cancellation_token, validator: validator)
        PoolDraw.new(self, data.fetch("draw"))
      end

      def draw(draw_id, timeout: 45, cancellation_token: nil)
        raise ArgumentError, "Invalid draw_id" unless draw_id.is_a?(String)
        draw_id = @session.pool_message_id(draw_id)
        data = @session.pool_request(:draw, {}, pool_id: @id, draw_id: draw_id, timeout: timeout, cancellation_token: cancellation_token)
        PoolDraw.new(self, data.fetch("draw"))
      end

      def my_draws(after: 0, limit: 100, timeout: 45, cancellation_token: nil)
        unless after.is_a?(Integer) && after >= 0 && limit.is_a?(Integer) && limit.between?(1, 100)
          raise ArgumentError, "Invalid pool draw page"
        end
        data = @session.pool_request(:draws, { "after" => after, "limit" => limit }, pool_id: @id, timeout: timeout, cancellation_token: cancellation_token)
        PoolDrawPage.new(self, data)
      end

      def reveal(draw_id, values: nil, context: nil, delivery: :message, message_id: nil, retries: 2, timeout: 45, cancellation_token: nil)
        raise ArgumentError, "Invalid draw_id" unless draw_id.is_a?(String)
        draw_id = @session.pool_message_id(draw_id)
        identity = @session.pool_message_id(message_id)
        unless values.nil? || (values.is_a?(Array) && !values.empty? && values.length <= @session.limits.fetch("max_pool_take_count", 100) &&
          values.uniq.length == values.length && values.all? { |value| value.is_a?(Integer) })
          raise ArgumentError, "Invalid reveal values"
        end
        @session.validate_pool_context!(context)
        raise ArgumentError, "Invalid pool delivery" unless %w[message stack].include?(delivery.to_s)
        @session.ensure_stack! if delivery.to_s == "stack"
        taken = draw(draw_id, timeout: timeout, cancellation_token: cancellation_token)
        raise ArgumentError, "Values do not belong to this draw" if values && !(values - taken.values).empty?
        chosen = values || (taken.values - taken.revealed_values)
        packet = { "pool_id" => @id, "draw_id" => draw_id, "values" => chosen }
        packet["draw_context"] = taken.context unless taken.context.nil?
        packet["context"] = context unless context.nil?
        validator = ->(first = true) { @session.validate_pool_publication!(packet, delivery.to_s, capacity: first && message_id.nil? && !(chosen - taken.revealed_values).empty?) }
        validator.call
        @session.pool_request(:reveal, { "values" => values, "context" => context, "delivery" => delivery.to_s, "message_id" => identity },
          pool_id: @id, draw_id: draw_id, retries: retries, timeout: timeout, cancellation_token: cancellation_token, validator: validator)
      end

      def delete(timeout: 45, cancellation_token: nil)
        raise NotOwner, "Only the live session owner can delete pools" unless @session.owner?
        @session.pool_request(:delete, {}, pool_id: @id, timeout: timeout, cancellation_token: cancellation_token)
        true
      end

      private

      def validate_take!(params, snapshot = nil, capacity: true)
        maximum = @session.limits.fetch("max_pool_take_count", 100)
        count = params["count"]
        raise ArgumentError, "Invalid pool draw count" unless count.is_a?(Integer) && count.between?(1, maximum)
        raise ArgumentError, "Invalid pool visibility" unless %w[public private].include?(params["visibility"])
        raise ArgumentError, "Invalid pool delivery" unless %w[message stack].include?(params["delivery"])
        @session.validate_pool_context!(params["context"])
        @session.ensure_stack! if params["delivery"] == "stack"
        return unless snapshot
        raise ArgumentError, "This pool only permits public draws" if params["visibility"] == "private" && !snapshot["private_draws"]
        raise PoolExhausted, "Not enough pool items" if capacity && count > snapshot["remaining"]
        packet = { "pool_id" => @id, "draw_id" => params["message_id"], "count" => count,
          "remaining" => [snapshot["remaining"] - count, 0].max, "visibility" => params["visibility"] }
        packet["context"] = params["context"] unless params["context"].nil?
        if params["visibility"] == "public"
          widest = snapshot.values_at("min", "max").max_by { |value| value.to_s.bytesize }
          packet["values"] = Array.new(count, widest)
        end
        @session.validate_pool_publication!(packet, params["delivery"], capacity: capacity)
      end
    end

    class DiscoveryPage
      include Enumerable
      attr_reader :items, :next_cursor, :limits

      def initialize(endpoint, data)
        @items = Array(data["items"]).map { |entry| DiscoveredSession.new(endpoint, entry) }.freeze
        @next_cursor = data["next_cursor"]
        @limits = LiveSessions.immutable_copy(data["limits"] || {})
      end

      def each(&block)
        @items.each(&block)
      end
    end

    class DiscoveredSession
      attr_reader :id, :visibility, :discovery_metadata, :created_at, :state, :capacity, :participant_count,
        :available_slots, :can_join, :join_reason, :invitation, :discovery_context, :discovery_token_expires_at, :limits, :hide_participants, :participants
      alias can_join? can_join
      alias hide_participants? hide_participants

      def initialize(endpoint, data)
        @endpoint = endpoint
        apply_snapshot(data)
      end

      def refresh(timeout: 45, cancellation_token: nil)
        raise DiscoveryUnsupported, "Server does not support refreshing discovered sessions" unless @limits["discovery_refresh"] == true
        data = @endpoint.refresh_discovered_session(@id, @discovery_token, timeout: timeout, cancellation_token: cancellation_token)
        apply_snapshot(data)
        self
      end

      def join(participant_metadata: {}, timeout: 45, cancellation_token: nil)
        @endpoint.join_discovered_session(@id, @discovery_token, participant_metadata,
          timeout: timeout, cancellation_token: cancellation_token)
      end

      def inspect
        "#<#{self.class} id=#{@id.inspect} visibility=#{@visibility.inspect}>"
      end

      private

      def apply_snapshot(data)
        @id = data["id"].to_s
        @visibility = data["visibility"].to_s.to_sym
        @state = data["state"].to_s.to_sym
        @hide_participants = data["hide_participants"] == true
        @participants = data["participants"].is_a?(Array) ? LiveSessions.immutable_copy(data["participants"]) : nil
        @discovery_metadata = LiveSessions.immutable_copy(data["discovery_metadata"] || {})
        @created_at, @capacity = data["created_at"].to_i, data["capacity"].to_i
        @participant_count, @available_slots = data["participant_count"].to_i, data["available_slots"].to_i
        @can_join = data["can_join"] == true
        @join_reason = data["join_reason"]&.to_sym
        @invitation = LiveSessions.immutable_copy(data["invitation"])
        @discovery_context = LiveSessions.immutable_copy(data["discovery_context"] || {})
        @discovery_token = data["discovery_token"].to_s
        @discovery_token_expires_at = data["discovery_token_expires_at"].to_i
        @limits = LiveSessions.immutable_copy(data["limits"] || {})
      end
    end

    class Invitation
      attr_reader :id, :metadata, :invitation_metadata, :inviter, :capacity, :expires_at, :invitation_id, :generation, :discovery_context

      def initialize(endpoint, data)
        @endpoint = endpoint
        @id = data["session_id"].to_s
        @metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
        @invitation_metadata = data["invitation_metadata"].is_a?(Hash) ? data["invitation_metadata"] : {}
        @inviter = Participant.new(data["invited_by"].is_a?(Hash) ? data["invited_by"] : {})
        @capacity = data["capacity"].to_i
        @expires_at = data["expires_at"].to_i
        @state = :pending
        @invitation_id = data["invitation_id"]
        @generation = data["generation"].to_i
        @discovery_context = LiveSessions.immutable_copy(data["discovery_context"] || { "via" => "invitation", "sources" => ["invited"] })
      end

      def accept(participant_metadata: {})
        raise Error, "Invitation is no longer pending" unless pending?
        session = @endpoint.accept_invitation(self, participant_metadata)
        @state = :accepted
        session
      end

      def reject
        return false unless pending?
        @endpoint.reject_invitation(self)
        @state = :rejected
        true
      end

      def supersede
        @state = :superseded
      end

      def superseded?
        @state == :superseded
      end

      def pending?
        @state == :pending && !expired?
      end

      def expired?
        @expires_at.positive? && Time.now.to_i >= @expires_at
      end
    end

    class Session
      MISSING_PACKET = Object.new.freeze
      private_constant :MISSING_PACKET

      attr_reader :id, :metadata, :capacity, :owner_id, :participant_id, :state, :limits,
        :visibility, :join_code, :discovery_metadata, :discovery_context, :join_context, :hide_participants
      alias hide_participants? hide_participants

      def initialize(endpoint, data)
        @endpoint = endpoint
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @messages = EventQueue.new
        @delivery_mutex = Mutex.new
        @receive_requested = false
        @snapshot_revision = -1
        @participants = {}
        @ack = 0
        @state = :open
        @stack_state = { "revision" => -1, "last_seq" => 0, "trimmed_through" => 0, "count" => 0, "first_seq" => nil }
        @stack_notice = false
        @stack_cursor = 0
        @stack_read_request = @stack_page = @stack_delivery = @stack_through = nil
        @stack_started = @stack_callback_pending = @stack_reader_failed = false
        @stack_read_failures = 0
        @stack_retry_at = 0.0
        apply_snapshot(data)
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

      def owner?
        @participant_id == @owner_id
      end

      def closed?
        @mutex.synchronize { @state == :closed }
      end

      def ownership_transfer?
        @mutex.synchronize { @limits["ownership_transfer"] == true }
      end

      # Requires the server contract in docs/live-session-ownership.md.
      # With leave: true, assignment and departure are one server transaction.
      def transfer_ownership(participant, leave: false, timeout: 45, cancellation_token: nil)
        raise ArgumentError, "leave must be boolean" unless leave == true || leave == false
        validate_ownership_transfer!(participant)
        data = @endpoint.transfer_ownership(self, participant, leave: leave,
          timeout: timeout, cancellation_token: cancellation_token)
        @delivery_mutex.synchronize do
          apply_snapshot(data)
          close_local(:left, confirmed: true) if leave
        end
        true
      end

      def validate_ownership_transfer!(participant)
        @mutex.synchronize do
          raise SessionClosed, "Live session is closed" if @state == :closed
          raise NotOwner, "Only the live session owner can transfer ownership" unless @participant_id == @owner_id
          unless @limits["ownership_transfer"] == true
            raise OwnershipTransferUnsupported, "Server does not support live session ownership transfer"
          end
          unless participant.is_a?(Participant) && @participants[participant.id].equal?(participant) && participant.id != @participant_id
            raise ArgumentError, "successor must be another current participant of this session"
          end
        end
        true
      end

      def invite(user, metadata: {})
        ensure_open!
        @endpoint.invite(self, user, metadata)
      end

      def update_discovery_metadata(metadata, timeout: 45, cancellation_token: nil)
        ensure_open!
        raise NotOwner, "Only the session owner can update discovery metadata" unless owner?
        raise DiscoveryUnsupported, "Server does not support updating discovery metadata" unless @limits["discovery_metadata_updates"] == true
        raise ArgumentError, "discovery_metadata must be a Hash" unless metadata.is_a?(Hash)
        encoded = JSON.generate(metadata)
        maximum = @limits.fetch("max_discovery_metadata_bytes", 1024).to_i
        raise ArgumentError, "Discovery metadata exceeds #{maximum} bytes" if encoded.bytesize > maximum
        data = @endpoint.update_discovery_metadata(self, JSON.parse(encoded), timeout: timeout, cancellation_token: cancellation_token)
        apply_snapshot(data)
        @discovery_metadata
      end

      def invite_all(users, metadata: {})
        Array(users).map { |user| invite(user, metadata: metadata) }
      end

      def send(packet = MISSING_PACKET, message_id: nil, retries: 2, cancellation_token: nil, **packet_fields)
        # Preserve send("type" => "move") and send(type: "move") on Ruby 3+
        # while accepting explicit delivery options with a positional packet.
        if packet.equal?(MISSING_PACKET) && !packet_fields.empty?
          packet = packet_fields
        elsif packet.equal?(MISSING_PACKET) || !packet_fields.empty?
          raise ArgumentError, "exactly one packet is required"
        end
        ensure_open!
        validate_json!(packet)
        @endpoint.send_packet(self, packet, message_id: message_id, retries: retries, cancellation_token: cancellation_token)
      end

      def private_messages?
        @mutex.synchronize { @private_messages == true }
      end

      def send_private(recipient_user, packet = MISSING_PACKET, message_id: nil, retries: 2, timeout: 45, cancellation_token: nil, **packet_fields)
        if packet.equal?(MISSING_PACKET) && !packet_fields.empty?
          packet = packet_fields
        elsif packet.equal?(MISSING_PACKET) || !packet_fields.empty?
          raise ArgumentError, "exactly one packet is required"
        end
        unless recipient_user.is_a?(String) && !recipient_user.strip.empty? && recipient_user.strip.bytesize <= 64
          raise ArgumentError, "Invalid recipient_user"
        end
        identity = message_id || SecureRandom.uuid
        raise ArgumentError, "Invalid message_id" unless identity.is_a?(String) && identity.match?(/\A[A-Za-z0-9_-]{16,64}\z/)
        encoded = JSON.generate(packet)
        validate_private_message!(encoded.bytesize)
        @endpoint.private_request(self, {
          "recipient_user" => recipient_user.strip, "packet" => JSON.parse(encoded), "message_id" => identity
        }, retries: retries, timeout: timeout, cancellation_token: cancellation_token)
      end

      def validate_private_message!(bytes)
        ensure_open!
        raise PrivateMessagesUnsupported, "Server does not support private live session messages" unless @limits["private_messages"] == true
        raise PrivateMessagesDisabled, "Private messages are disabled for this session" unless private_messages?
        if bytes > @limits.fetch("max_message_bytes", 16 * 1024)
          raise MessagePacketTooLarge, "Private message exceeds the session message limit"
        end
      end

      def stack_state
        ensure_stack!(allow_closed: true)
        @mutex.synchronize { @stack_state.dup }
      end

      def stack_push(packet = MISSING_PACKET, message_id: nil, retries: 2, timeout: 45, cancellation_token: nil, **packet_fields)
        if packet.equal?(MISSING_PACKET) && !packet_fields.empty?
          packet = packet_fields
        elsif packet.equal?(MISSING_PACKET) || !packet_fields.empty?
          raise ArgumentError, "exactly one packet is required"
        end
        identity = message_id || SecureRandom.uuid
        raise ArgumentError, "Invalid message_id" unless identity.is_a?(String) && identity.match?(/\A[A-Za-z0-9_-]{16,64}\z/)
        encoded = JSON.generate(packet)
        validate_stack_push!(encoded.bytesize, capacity: message_id.nil?)
        @endpoint.stack_request(self, :push, { "packet" => JSON.parse(encoded), "message_id" => identity },
          retries: retries, timeout: timeout, cancellation_token: cancellation_token, check_capacity: message_id.nil?)
      end

      def create_pool(min: nil, max: nil, values: nil, private_draws: true, message_id: nil, retries: 2, timeout: 45, cancellation_token: nil)
        ensure_pools!
        raise NotOwner, "Only the live session owner can create pools" unless owner?
        identity = pool_message_id(message_id)
        maximum = @limits.fetch("max_pool_items", 32_768)
        lower = @limits.fetch("min_random_value", -9_007_199_254_740_991)
        upper = @limits.fetch("max_random_value", 9_007_199_254_740_991)
        if values.nil?
          unless min.is_a?(Integer) && max.is_a?(Integer) && min.between?(lower, upper) && max.between?(min, upper) && max - min + 1 <= maximum
            raise ArgumentError, "Invalid pool range"
          end
        elsif !min.nil? || !max.nil? || !values.is_a?(Array) || !values.length.between?(1, maximum) ||
          values.uniq.length != values.length || !values.all? { |value| value.is_a?(Integer) && value.between?(lower, upper) }
          raise ArgumentError, "Invalid pool values"
        end
        raise ArgumentError, "private_draws must be boolean" unless private_draws == true || private_draws == false
        if message_id.nil? && pools(timeout: timeout, cancellation_token: cancellation_token).length >= @limits.fetch("max_pools", 1)
          raise PoolLimit, "Live session pool limit reached"
        end
        data = pool_request(:create, { "min" => min, "max" => max, "values" => values, "private_draws" => private_draws, "message_id" => identity },
          retries: retries, timeout: timeout, cancellation_token: cancellation_token)
        Pool.new(self, data.fetch("pool").fetch("id"))
      end

      def pools(timeout: 45, cancellation_token: nil)
        data = pool_request(:list, {}, timeout: timeout, cancellation_token: cancellation_token)
        data.fetch("pools").map { |pool| Pool.new(self, pool.fetch("id")) }
      end

      def pool(id)
        ensure_pools!
        Pool.new(self, id)
      end

      def stack_enabled?
        @mutex.synchronize { @limits["stack"] == true && @limits.fetch("max_stack_entries", LEGACY_STACK_ENTRIES).to_i.positive? }
      end

      def pools_enabled?
        @mutex.synchronize { @limits["pools"] == true && @limits.fetch("max_pools", LEGACY_POOL_COUNT).to_i.positive? }
      end

      def ensure_stack!(allow_closed: false)
        ensure_open! unless allow_closed
        raise StackUnsupported, "Server does not support live session stacks" unless @limits["stack"] == true
        raise StackDisabled, "Live session stack is disabled" unless stack_enabled?
      end

      def ensure_pools!
        ensure_open!
        raise PoolUnsupported, "Server does not support live session pools" unless @limits["pools"] == true
        raise PoolsDisabled, "Live session pools are disabled" unless pools_enabled?
      end

      def pool_message_id(value)
        value ||= SecureRandom.uuid
        raise ArgumentError, "Invalid message_id" unless value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]{16,64}\z/)
        value
      end

      def validate_pool_context!(context)
        ensure_pools!
        maximum = @limits.fetch("max_pool_context_bytes", 256)
        raise PoolPacketTooLarge, "Pool context exceeds #{maximum} bytes" if JSON.generate(context).bytesize > maximum
      end

      def validate_pool_publication!(packet, delivery, capacity: true)
        ensure_pools!
        bytes = JSON.generate(packet).bytesize
        if delivery == "stack"
          validate_stack_push!(bytes, capacity: capacity)
        elsif bytes > @limits.fetch("max_message_bytes", 16 * 1024)
          raise PoolPacketTooLarge, "Pool message exceeds the session message limit"
        end
      end

      def pool_request(operation, params, pool_id: nil, draw_id: nil, retries: 2, timeout: 45, cancellation_token: nil, validator: nil)
        ensure_pools!
        @endpoint.pool_request(self, operation, params, pool_id: pool_id, draw_id: draw_id, retries: retries, timeout: timeout,
          cancellation_token: cancellation_token, validator: validator)
      end

      def send_random(min:, max:, count: 1, context: nil, message_id: nil, draw_number: nil, retries: 2, timeout: 45, cancellation_token: nil)
        request_random(:random, min, max, count, context, message_id, draw_number, retries, timeout, cancellation_token)
      end

      def stack_push_random(min:, max:, count: 1, context: nil, message_id: nil, draw_number: nil, retries: 2, timeout: 45, cancellation_token: nil)
        request_random(:stack_random, min, max, count, context, message_id, draw_number, retries, timeout, cancellation_token)
      end

      def validate_random_request!(operation, params, capacity: true)
        ensure_open!
        raise RandomUnsupported, "Server does not support live session random messages" unless @limits["random"] == true
        maximum_count = @limits.fetch("max_random_count", 100)
        lower = @limits.fetch("min_random_value", -9_007_199_254_740_991)
        upper = @limits.fetch("max_random_value", 9_007_199_254_740_991)
        min, max, count = params.values_at("min", "max", "count")
        unless min.is_a?(Integer) && max.is_a?(Integer) && min.between?(lower, upper) && max.between?(min, upper)
          raise ArgumentError, "Invalid random range"
        end
        raise ArgumentError, "count must be between 1 and #{maximum_count}" unless count.is_a?(Integer) && count.between?(1, maximum_count)
        number = params["draw_number"]
        raise ArgumentError, "Invalid draw_number" unless number.nil? || (number.is_a?(Integer) && number.between?(1, 9_007_199_254_740_991))
        widest = [min, max].max_by { |value| value.to_s.bytesize }
        packet = { "values" => Array.new(count, widest) }
        packet["context"] = params["context"] unless params["context"].nil?
        bytes = JSON.generate(packet).bytesize
        if operation == :stack_random
          validate_stack_push!(bytes, capacity: capacity)
        elsif bytes > @limits.fetch("max_message_bytes", 16 * 1024)
          raise RandomPacketTooLarge, "Random packet exceeds the session message limit"
        end
        true
      end

      def stack_read(after: 0, limit: nil, through: nil, timeout: 120, cancellation_token: nil)
        ensure_stack!
        params = { "after" => stack_integer(after, "after") }
        params["limit"] = stack_integer(limit, "limit", minimum: 1) unless limit.nil?
        params["through"] = stack_integer(through, "through") unless through.nil?
        @endpoint.stack_request(self, :read, params, timeout: timeout, cancellation_token: cancellation_token)
      end

      def stack_trim(through:, timeout: 45, cancellation_token: nil)
        ensure_stack!
        raise NotOwner, "Only the live session owner can trim it" unless owner?
        @endpoint.stack_request(self, :trim, { "through" => stack_integer(through, "through") }, timeout: timeout, cancellation_token: cancellation_token)
      end

      def stack_clear(timeout: 120, cancellation_token: nil)
        ensure_stack!
        raise NotOwner, "Only the live session owner can clear it" unless owner?
        state = stack_read(limit: 1, timeout: timeout, cancellation_token: cancellation_token)
        stack_trim(through: state.fetch("through"), timeout: timeout, cancellation_token: cancellation_token)
      end

      def on_stack_changed(&block)
        ensure_stack!
        register_callback(:stack_changed, &block)
        notify_stack_changed
        self
      end

      def on_stack_message(with_metadata: false, &block)
        raise ArgumentError, "callback is required" unless block
        ensure_stack!
        register_message_callback(:stack_message, with_metadata, &block)
      end

      def on_stack_gap(&block)
        ensure_stack!
        register_callback(:stack_gap, &block)
      end

      def tick_stack_messages(now)
        return unless stack_enabled?
        request = @mutex.synchronize { @stack_read_request }
        if request
          begin
            value, error = request[:result].pop(true)
          rescue ThreadError
            return
          end
          @endpoint.cancel_stack_request(request)
          @mutex.synchronize { @stack_read_request = nil if @stack_read_request.equal?(request) }
          return if closed?
          raise error if error
          validate_stack_page!(value, request[:params])
          @mutex.synchronize do
            return if @state == :closed
            @stack_page = value
            @stack_read_failures = 0
            @stack_retry_at = 0.0
          end
        end
        queue_stack_callback
        params = @mutex.synchronize do
          next if @state == :closed || @callbacks[:stack_message].empty? || @stack_reader_failed
          next if @stack_read_request || @stack_page || @stack_delivery || now < @stack_retry_at
          next if @stack_started && @stack_through.nil? && @stack_cursor >= @stack_state["last_seq"].to_i
          values = { "after" => @stack_cursor, "limit" => STACK_MESSAGE_PAGE_SIZE }
          values["through"] = @stack_through unless @stack_through.nil?
          values
        end
        return unless params
        request = @endpoint.queue_stack_request(self, :read, params, retries: 0, timeout: 15)
        accepted = @mutex.synchronize do
          next false if @state == :closed
          @stack_read_request = request
          true
        end
        @endpoint.cancel_stack_request(request) unless accepted
      rescue StandardError => error
        stack_read_failed(error, now) unless closed?
      end

      def validate_stack_push!(bytes, capacity: true)
        ensure_stack!
        @mutex.synchronize do
          maximum = @limits.fetch("max_stack_entry_bytes", DEFAULT_STACK_ENTRY_BYTES).to_i
          raise StackPacketTooLarge, "Stack packet exceeds #{maximum} bytes" if bytes > maximum
          if capacity && @stack_state["count"].to_i >= @limits.fetch("max_stack_entries", LEGACY_STACK_ENTRIES).to_i
            raise StackFull, "Live session stack is full"
          end
        end
      end

      def apply_stack_state(data, limits = nil)
        changed = @mutex.synchronize do
          next false if @state == :closed
          @limits = limits.dup if limits.is_a?(Hash)
          next false unless data.is_a?(Hash) && data["revision"].to_i > @stack_state["revision"].to_i
          @stack_state = data.dup
          true
        end
        notify_stack_changed if changed
        changed
      end

      def receive(timeout: nil, cancellation_token: nil)
        @mutex.synchronize { @receive_requested = true }
        @messages.pop(timeout: timeout, cancellation_token: cancellation_token, pump: -> { @endpoint.wait_step(cancellation_token: cancellation_token) })
      end

      def leave
        return false if closed?
        confirmed = false
        begin
          @endpoint.leave_session(self)
          confirmed = true
        ensure
          close_local(:left, confirmed: confirmed)
        end
        true
      end

      def close
        ensure_open!
        raise NotOwner, "Only the live session owner can close it" unless owner?
        confirmed = false
        begin
          @endpoint.close_session(self)
          confirmed = true
        ensure
          close_local(:closed, confirmed: confirmed, operation: :close)
        end
        true
      end

      def on_message(with_metadata: false, &block); register_message_callback(:message, with_metadata, &block); end
      def on_participant_joined(&block); register_callback(:participant_joined, &block); end
      def on_participant_left(&block); register_callback(:participant_left, &block); end
      def on_owner_changed(&block); register_callback(:owner_changed, &block); end
      def on_discovery_metadata_changed(&block); register_callback(:discovery_metadata_changed, &block); end
      def on_gap(&block); register_callback(:gap, &block); end
      def on_closed(&block); register_callback(:closed, &block); end

      def wait_for_participant(user = nil, timeout: 10, cancellation_token: nil)
        deadline = monotonic + timeout.to_f
        loop do
          found = @mutex.synchronize do
            raise SessionClosed, "Live session is closed" if @state == :closed
            @participants.values.find { |entry| entry.id != @participant_id && (user.nil? || entry.user.casecmp?(user.to_s)) }
          end
          return found if found
          raise TimeoutError, "Participant did not join in time" if monotonic >= deadline
          @endpoint.wait_step(cancellation_token: cancellation_token)
        end
      end

      def control_entry
        @mutex.synchronize do
          {
            "id" => @id,
            "participant_id" => @participant_id,
            "ack" => @ack, "stack_revision" => @stack_state["revision"].to_i
          }
        end
      end

      def apply_envelope(data)
        @delivery_mutex.synchronize do
          return false if closed?
          # Snapshots and event cursors have different jobs: a stale snapshot may
          # accompany an event page we still need, so only the snapshot is ignored.
          apply_snapshot(data)
          seen = @mutex.synchronize { @ack }
          Array(data["events"]).sort_by { |event| event["seq"].to_i }.each do |event|
            sequence = event["seq"].to_i
            next if sequence <= seen
            apply_event(event)
            seen = sequence
          end
          cursor = data["cursor"].to_i
          @mutex.synchronize { @ack = [@ack, cursor].max }
          data["has_more"] == true
        end
      rescue QueueOverflow => error
        @endpoint.record_error(error)
        close_local(:queue_overflow)
        false
      end

      def close_local(reason, confirmed: false, operation: :leave)
        stack_request = nil
        changed = @mutex.synchronize do
          next false if @state == :closed
          @state = :closed
          stack_request = @stack_read_request
          @stack_read_request = @stack_page = @stack_delivery = nil
          @stack_callback_pending = false
          @condition.broadcast
          true
        end
        if changed
          @endpoint.cancel_stack_request(stack_request) if stack_request
          @messages.close
          @endpoint.session_closed(self, confirmed: confirmed, operation: operation)
          emit(:closed, reason.to_sym)
        end
        changed
      end

      private

      def stack_integer(value, name, minimum: 0)
        raise ArgumentError, "#{name} must be an integer >= #{minimum}" unless value.is_a?(Integer) && value >= minimum
        value
      end

      def validate_stack_page!(page, params)
        valid = page.is_a?(Hash) && page["session_id"] == @id && page["entries"].is_a?(Array) &&
          page["entries"].length <= STACK_MESSAGE_PAGE_SIZE && page["cursor"].is_a?(Integer) &&
          page["through"].is_a?(Integer) && page["through"] >= params["after"] &&
          (!params.key?("through") || page["through"] == params["through"])
        cursor = params["after"]
        if valid && page["gap"]
          gap = page["gap"]
          valid = gap.is_a?(Hash) && gap["from"] == cursor + 1 && gap["to"].is_a?(Integer) &&
            gap["to"] >= gap["from"] && gap["to"] <= page["through"]
          cursor = gap["to"] if valid
        end
        if valid
          page["entries"].each do |entry|
            unless entry.is_a?(Hash) && entry["seq"].is_a?(Integer) && entry["seq"] == cursor + 1 && entry.key?("packet")
              valid = false
              break
            end
            cursor = entry["seq"]
          end
          valid &&= page["cursor"] == cursor && cursor <= page["through"] &&
            page["has_more"] == (cursor < page["through"]) &&
            (cursor > params["after"] || page["has_more"] == false)
        end
        raise EltenLink::Error.new("Invalid live session stack page", code: "invalid_json") unless valid
      end

      def stack_read_failed(error, now)
        retryable = @endpoint.stack_request_retryable?(error)
        @mutex.synchronize do
          return if @state == :closed
          @stack_read_failures += 1
          advertised = error.respond_to?(:retry_after) ? error.retry_after.to_f : 0
          @stack_retry_at = now + [advertised, [2**[@stack_read_failures - 1, 5].min, 30].min].max
          @stack_reader_failed = !retryable
        end
        @endpoint.record_error(error)
        if error.is_a?(EltenLink::Error) && %w[apps.live_sessions.closed apps.live_sessions.not_found apps.live_sessions.membership_required].include?(error.code)
          close_local(:expired, confirmed: error.code != "apps.live_sessions.closed")
        end
      end

      def queue_stack_callback
        queued = @mutex.synchronize do
          next false if @state == :closed || @stack_callback_pending || !@stack_page
          unless @stack_delivery
            gap = @stack_page.delete("gap")
            if gap
              @stack_delivery = { sequence: gap["to"], callbacks: @callbacks[:stack_gap].dup, arguments: [gap], index: 0 }
              if @stack_delivery[:callbacks].empty?
                @stack_cursor = gap["to"]
                @stack_delivery = nil
              end
            end
            unless @stack_delivery
              entry = @stack_page["entries"].shift
              if entry
                sender_data = entry["sender"].is_a?(Hash) ? entry["sender"] : {}
                sender = @participants[entry["sender_id"].to_s] || Participant.new(sender_data)
                info = MessageMetadata.new(entry)
                packet = info.origin == :server ? LiveSessions.immutable_copy(entry["packet"]) : entry["packet"]
                @stack_delivery = { sequence: entry["seq"], callbacks: @callbacks[:stack_message].dup,
                  arguments: [sender, packet, info], index: 0 }
              else
                @stack_cursor = @stack_page["cursor"]
                @stack_through = @stack_page["has_more"] ? @stack_page["through"] : nil
                @stack_started = true
                @stack_page = nil
                next false
              end
            end
          end
          @stack_callback_pending = true
        end
        return unless queued
        accepted = @endpoint.enqueue_callback(-> { dispatch_stack_callback })
        @mutex.synchronize { @stack_callback_pending = false } unless accepted
      end

      def dispatch_stack_callback
        delivery = @mutex.synchronize { @stack_delivery unless @state == :closed }
        return unless delivery
        begin
          delivery[:callbacks][delivery[:index]].call(*delivery[:arguments])
        ensure
          @mutex.synchronize do
            if @stack_delivery.equal?(delivery)
              delivery[:index] += 1
              if delivery[:index] >= delivery[:callbacks].length
                @stack_cursor = delivery[:sequence]
                @stack_delivery = nil
              end
            end
            @stack_callback_pending = false
          end
          queue_stack_callback
        end
      end

      def notify_stack_changed
        enqueue = @mutex.synchronize do
          next false if @state == :closed || @stack_notice || @callbacks[:stack_changed].empty?
          @stack_notice = true
        end
        return unless enqueue
        accepted = @endpoint.enqueue_callback(lambda do
          callbacks, snapshot = @mutex.synchronize do
            @stack_notice = false
            [@callbacks[:stack_changed].dup, @stack_state.dup]
          end
          callbacks.each do |callback|
            begin
              callback.call(snapshot.dup)
            rescue Exception => error
              Log.warning("Live session stack callback failed: #{error.class}: #{error.message}") if defined?(Log)
            end
          end
        end)
        @mutex.synchronize { @stack_notice = false } unless accepted
      end

      def apply_snapshot(data)
        stack = nil
        @mutex.synchronize do
          revision = data["revision"]
          return if !revision.nil? && revision.to_i < @snapshot_revision
          @snapshot_revision = revision.to_i unless revision.nil?
          @limits = data["limits"].dup if data["limits"].is_a?(Hash)
          stack = data["stack"]
          @limits = { "max_stack_entry_bytes" => DEFAULT_STACK_ENTRY_BYTES, "max_stack_entries" => LEGACY_STACK_ENTRIES }.merge(@limits || {})
          @id = (data["id"] || data["session_id"] || @id).to_s
          @metadata = data["metadata"] if data["metadata"].is_a?(Hash)
          @metadata ||= {}
          @visibility = (data["visibility"] || @visibility || :private).to_sym
          @private_messages = data["private_messages"] == true if data.key?("private_messages")
          @hide_participants = data["hide_participants"] == true if data.key?("hide_participants") || @hide_participants.nil?
          @join_code = data["join_code"] if data.key?("join_code")
          @discovery_metadata = LiveSessions.immutable_copy(data["discovery_metadata"]) if data["discovery_metadata"].is_a?(Hash)
          @discovery_metadata ||= {}.freeze
          @discovery_context ||= LiveSessions.immutable_copy(data["discovery_context"]) if data["discovery_context"].is_a?(Hash)
          @join_context ||= LiveSessions.immutable_copy(data["join_context"]) if data["join_context"].is_a?(Hash)
          @capacity = data["capacity"].to_i if data.key?("capacity")
          @owner_id = data["owner_id"].to_s unless data["owner_id"].to_s.empty?
          @participant_id = data["participant_id"].to_s unless data["participant_id"].to_s.empty?
          if data["participants"].is_a?(Array)
            current = {}
            data["participants"].each do |row|
              next unless row.is_a?(Hash)
              id = row["id"].to_s
              next if id.empty?
              current[id] = @participants[id]&.update(row) || Participant.new(row)
            end
            @participants = current
            @condition.broadcast
          end
        end
        apply_stack_state(stack) if stack
      end

      def apply_event(event)
        case event["type"].to_s
        when "message"
          sender_data = event["sender"].is_a?(Hash) ? event["sender"] : {}
          sender = participant(event["sender_id"]) || Participant.new(sender_data)
          info = MessageMetadata.new(event)
          packet = info.origin == :server ? LiveSessions.immutable_copy(event["packet"]) : event["packet"]
          message = Message.new(
            id: event["message_id"].to_s,
            sequence: event["seq"].to_i,
            sender: sender,
            packet: packet
          )
          message.metadata = info
          pull = @mutex.synchronize { @receive_requested || @callbacks[:message].empty? }
          @messages.push(message, bytes: JSON.generate(message.packet).bytesize + 256) if pull
          emit(:message, sender, message.packet, info)
        when "participant_joined"
          row = event["participant"]
          if row.is_a?(Hash)
            item = @mutex.synchronize do
              id = row["id"].to_s
              @participants[id] || Participant.new(row)
            end
            emit(:participant_joined, item)
          end
        when "participant_left"
          row = event["participant"].is_a?(Hash) ? event["participant"] : {}
          item = @mutex.synchronize do
            removed = @participants[row["id"].to_s]
            @condition.broadcast
            removed || Participant.new(row)
          end
          emit(:participant_left, item, event["reason"].to_s.to_sym)
        when "discovery_metadata_changed"
          emit(:discovery_metadata_changed, LiveSessions.immutable_copy(event["discovery_metadata"])) if event["discovery_metadata"].is_a?(Hash)
        when "owner_changed"
          row = event["owner"]
          unless row.is_a?(Hash) && row["id"].is_a?(String) && !row["id"].empty? && row["id"] == event["owner_id"]
            raise EltenLink::Error.new("Invalid live session owner event", code: "invalid_json")
          end
          # Like participant events, this describes a historical change. The
          # envelope's revision-checked snapshot remains the current authority.
          emit(:owner_changed, Participant.new(LiveSessions.immutable_copy(row)).freeze)
        when "gap"
          emit(:gap, event["from"].to_i, event["to"].to_i)
        when "closed"
          close_local(event["reason"].to_s.empty? ? :closed : event["reason"])
        end
      end

      def request_random(operation, min, max, count, context, message_id, draw_number, retries, timeout, cancellation_token)
        identity = message_id || SecureRandom.uuid
        raise ArgumentError, "Invalid message_id" unless identity.is_a?(String) && identity.match?(/\A[A-Za-z0-9_-]{16,64}\z/)
        params = { "min" => min, "max" => max, "count" => count, "context" => context, "message_id" => identity, "draw_number" => draw_number }
        validate_random_request!(operation, params, capacity: message_id.nil?)
        params = JSON.parse(JSON.generate(params))
        @endpoint.random_request(self, operation, params, retries: retries, timeout: timeout,
          cancellation_token: cancellation_token, check_capacity: message_id.nil?)
      end

      def register_message_callback(kind, with_metadata, &block)
        raise ArgumentError, "callback is required" unless block
        raise ArgumentError, "with_metadata must be boolean" unless with_metadata == true || with_metadata == false
        register_callback(kind) do |sender, packet, info|
          with_metadata ? block.call(sender, packet, info) : block.call(sender, packet)
        end
      end

      def register_callback(kind, &block)
        raise ArgumentError, "callback is required" if block == nil
        @mutex.synchronize do
          @callbacks[kind] << block
          @messages.clear if kind == :message && !@receive_requested
        end
        self
      end

      def emit(kind, *arguments)
        callbacks = @mutex.synchronize { @callbacks[kind].dup }
        callbacks.each { |callback| @endpoint.enqueue_callback(callback, *arguments) }
      end

      def ensure_open!
        raise SessionClosed, "Live session is closed" if closed?
      end

      def validate_json!(value)
        JSON.generate(value)
      rescue JSON::GeneratorError
        raise ArgumentError, "packet must be JSON-convertible"
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class Endpoint
      attr_reader :app_id, :instance_id, :user, :last_error, :limits

      def initialize(app_id:, client:, user: nil, token: nil)
        @app_id = app_id.to_s.downcase
        @client = client
        @user = (user || session_value(:name)).to_s
        @token = (token || session_value(:token)).to_s
        unless @app_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
          raise ArgumentError, "A valid app_id is required"
        end
        raise Error, "Elten user is not logged in" if @user.empty? || @token.empty?
        @instance_id = SecureRandom.uuid
        @mutex = Mutex.new
        @sessions = {}
        @lease_deadlines = {}
        @departures = {}
        @departure_pending = nil
        @departure_responses = Queue.new
        @departure_serial = 0
        @invitations = {}
        @resolved_invitations = {}
        @pending_envelopes = Hash.new { |hash, key| hash[key] = [] }
        @pending_envelope_bytes = 0
        @callback_bytes = 0
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @callback_queue = SizedQueue.new(MAX_QUEUE_ITEMS)
        @invitation_queue = EventQueue.new
        @control_responses = Queue.new
        @stack_requests = []
        @stack_pending = nil
        @stack_responses = Queue.new
        @control_pending = nil
        @control_serial = 0
        @control_failures = 0
        @retry_not_before = 0.0
        @control_rotation = 0
        @protocol_mutex = Mutex.new
        @limits = {}
        @last_error = nil
        @overflow = false
        @next_control_at = monotonic
        @closed = false
        LiveSessions.register(self)
      end

      def create(metadata: {}, participant_metadata: {}, capacity: 2, visibility: :private, join_code: nil, discovery_metadata: {}, hide_participants: false, timeout: 45, cancellation_token: nil, stack_entry_bytes: DEFAULT_STACK_ENTRY_BYTES, stack_entries: DEFAULT_STACK_ENTRIES, pool_count: DEFAULT_POOL_COUNT, private_messages: false)
        ensure_open!
        raise ArgumentError, "private_messages must be boolean" unless private_messages == true || private_messages == false
        raise ArgumentError, "hide_participants must be boolean" unless hide_participants == true || hide_participants == false
        raise ArgumentError, "stack_entry_bytes must be a positive integer" unless stack_entry_bytes.is_a?(Integer) && stack_entry_bytes.positive?
        [stack_entries, pool_count].each do |value|
          raise ArgumentError, "Stack and pool capacities must be non-negative integers" unless value.is_a?(Integer) && value >= 0
        end
        visibility = visibility.to_s
        raise ArgumentError, "Invalid session visibility" unless %w[private public].include?(visibility)
        join_code = normalize_join_code(join_code) unless join_code.nil?
        raise ArgumentError, "discovery_metadata must be a Hash" unless discovery_metadata.is_a?(Hash)
        maximum = @limits.fetch("max_discovery_metadata_bytes", 1024).to_i
        raise ArgumentError, "Discovery metadata exceeds #{maximum} bytes" if JSON.generate(discovery_metadata).bytesize > maximum
        if hide_participants && @limits["hide_participants"] != true
          discover_sessions(sources: [:created], limit: 1, timeout: timeout, cancellation_token: cancellation_token)
          raise DiscoveryUnsupported, "Server does not support hiding live session participants" unless @limits["hide_participants"] == true
        end
        data = discovery_request(:create,
          { "metadata" => metadata, "participant_metadata" => participant_metadata, "capacity" => capacity,
            "visibility" => visibility, "join_code" => join_code, "discovery_metadata" => discovery_metadata, "hide_participants" => hide_participants,
            "stack_entry_bytes" => stack_entry_bytes, "stack_entries" => stack_entries, "pool_count" => pool_count, "private_messages" => private_messages },
          timeout: timeout, cancellation_token: cancellation_token, retries: 0)
        session = store_session(data)
        if hide_participants && !session.hide_participants?
          session.close_local(:unsupported, operation: :close)
          raise DiscoveryUnsupported, "Server did not hide live session participants"
        end
        if private_messages && (session.limits["private_messages"] != true || !session.private_messages?)
          session.close_local(:unsupported)
          raise PrivateMessagesUnsupported, "Server did not enable private live session messages"
        end
        if stack_entries.positive? != session.stack_enabled?
          session.close_local(:unsupported)
          raise StackUnsupported, "Server did not apply the requested stack configuration"
        end
        if pool_count.positive? != session.pools_enabled?
          session.close_local(:unsupported)
          raise PoolUnsupported, "Server did not apply the requested pool configuration"
        end
        if (visibility != "private" || join_code || !discovery_metadata.empty?) && session.limits["discovery"] != true
          session.close_local(:unsupported)
          raise DiscoveryUnsupported, "Server does not support live session discovery"
        end
        session
      end

      def connect(user, metadata: {}, participant_metadata: {}, capacity: 2, timeout: 10, stack_entry_bytes: DEFAULT_STACK_ENTRY_BYTES, stack_entries: DEFAULT_STACK_ENTRIES, visibility: :private, join_code: nil, discovery_metadata: {}, hide_participants: false, pool_count: DEFAULT_POOL_COUNT, private_messages: false)
        session = create(metadata: metadata, participant_metadata: participant_metadata, capacity: capacity,
          stack_entry_bytes: stack_entry_bytes, stack_entries: stack_entries, visibility: visibility, join_code: join_code, discovery_metadata: discovery_metadata, hide_participants: hide_participants, pool_count: pool_count, private_messages: private_messages)
        session.invite(user)
        session.wait_for_participant(user, timeout: timeout)
        session
      rescue Exception
        session&.close rescue nil
        raise
      end

      def discover_sessions(sources: [:created, :invited, :public], limit: 50, cursor: nil, timeout: 45, cancellation_token: nil)
        sources = Array(sources).map(&:to_s).uniq
        raise ArgumentError, "Invalid discovery sources" if sources.empty? || !(sources - %w[created invited public]).empty?
        raise ArgumentError, "limit must be a positive integer" unless limit.is_a?(Integer) && limit.positive?
        unless cursor.nil? || (cursor.is_a?(String) && cursor.match?(/\A[A-Za-z0-9_-]{16,64}\z/))
          raise ArgumentError, "Invalid discovery cursor"
        end
        limit = [limit, @limits["max_discovery_page_size"].to_i].min if @limits["max_discovery_page_size"].to_i.positive?
        params = { "sources" => sources.join(","), "limit" => limit }
        params["cursor"] = cursor unless cursor.nil?
        data = discovery_request(:discover_sessions, params, timeout: timeout, cancellation_token: cancellation_token)
        DiscoveryPage.new(self, data)
      end

      def find_by_code(code, timeout: 45, cancellation_token: nil)
        data = discovery_request(:find_by_code, { "code" => normalize_join_code(code) }, timeout: timeout, cancellation_token: cancellation_token)
        DiscoveredSession.new(self, data)
      end

      def refresh_discovered_session(id, discovery_token, timeout: 45, cancellation_token: nil)
        discovery_request(:refresh, { "discovery_token" => discovery_token }, session_id: id, timeout: timeout, cancellation_token: cancellation_token)
      end

      def join_discovered_session(id, discovery_token, participant_metadata, timeout: 45, cancellation_token: nil)
        data = discovery_request(:join, { "discovery_token" => discovery_token, "participant_metadata" => participant_metadata },
          session_id: id, timeout: timeout, cancellation_token: cancellation_token)
        if data.dig("join_context", "method") == "invitation"
          resolve_invitation(id, invitation_id: data.dig("join_context", "invitation_id"),
            generation: data.dig("join_context", "invitation_generation"))
        end
        store_session(data)
      end

      def sessions
        @mutex.synchronize { @sessions.values.reject(&:closed?) }
      end

      def on_invitation(&block)
        register_callback(:invitation, &block)
      end

      def next_invitation(timeout: nil, cancellation_token: nil)
        deadline = timeout.nil? ? nil : monotonic + [timeout.to_f, 0].max
        loop do
          remaining = deadline.nil? ? nil : [deadline - monotonic, 0].max
          invitation = @invitation_queue.pop(timeout: remaining, cancellation_token: cancellation_token, pump: -> { wait_step(cancellation_token: cancellation_token) })
          return invitation if invitation.nil? || invitation.pending?
        end
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      def close
        current = @mutex.synchronize do
          return false if @closed
          @closed = true
          @sessions.values.reject(&:closed?)
        end
        cancel_control
        @invitation_queue.close
        current.each { |session| session.close_local(:endpoint_closed) }
        @invitation_queue.clear
        @mutex.synchronize do
          @callbacks.clear
          @callback_queue.clear
          @callback_bytes = 0
          @invitations.clear
          @resolved_invitations.clear
          @pending_envelopes.clear
          @pending_envelope_bytes = 0
        end
        true
      end

      def invite(session, user, metadata)
        ensure_session!(session)
        EltenLink::Apps.invite_live_session(
          @client,
          session_id: session.id,
          participant_id: session.participant_id,
          user: user.to_s,
          metadata: metadata
        )
      end

      def accept_invitation(invitation, participant_metadata)
        ensure_open!
        data = discovery_request(:accept, { "participant_metadata" => participant_metadata, "invitation_id" => invitation.invitation_id }, session_id: invitation.id)
        resolve_invitation(invitation.id, invitation_id: invitation.invitation_id, generation: invitation.generation)
        store_session(data)
      end

      def reject_invitation(invitation)
        ensure_open!
        discovery_request(:reject, { "invitation_id" => invitation.invitation_id }, session_id: invitation.id)
        resolve_invitation(invitation.id, invitation_id: invitation.invitation_id, generation: invitation.generation)
        true
      end

      def send_packet(session, packet, message_id: nil, retries: 2, cancellation_token: nil)
        ensure_session!(session)
        message_id ||= SecureRandom.uuid
        packet = JSON.parse(JSON.generate(packet))
        deadline = monotonic + 45.0
        attempts = 0
        begin
          cancellation_token&.raise_if_cancelled!
          attempts += 1
          result = EltenLink::Apps.send_live_session(
            @client, session_id: session.id, participant_id: session.participant_id,
            packet: packet, message_id: message_id,
            timeout: [15.0, deadline - monotonic].min, cancellation_token: cancellation_token
          )
          @last_error = nil
          renew_local_lease(session.id)
          result
        rescue EltenLink::Error => error
          @last_error = error
          if %w[apps.live_sessions.closed apps.live_sessions.not_found apps.live_sessions.membership_required].include?(error.code)
            session.close_local(:expired, confirmed: error.code != "apps.live_sessions.closed")
          end
          retryable = %w[network_error timeout invalid_json rate_limits.exceeded rate_limits.unavailable apps.live_sessions.rate_limited apps.live_sessions.busy apps.live_sessions.unavailable].include?(error.code) || [500, 502, 503, 504].include?(error.status.to_i)
          delay = [error.retry_after.to_f, [2**(attempts - 1), 5].min].max
          if retryable && attempts <= [[retries.to_i, 0].max, 2].min && monotonic + delay < deadline && !session.closed?
            retry_at = monotonic + delay
            wait_step(cancellation_token: cancellation_token) while monotonic < retry_at
            retry
          end
          record_error(error)
          raise
        end
      end

      def leave_session(session)
        ensure_session!(session)
        EltenLink::Apps.leave_live_session(
          @client,
          session_id: session.id,
          participant_id: session.participant_id,
          timeout: CONTROL_TIMEOUT
        )
      end

      def close_session(session)
        ensure_session!(session)
        EltenLink::Apps.close_live_session(
          @client,
          session_id: session.id,
          participant_id: session.participant_id,
          timeout: CONTROL_TIMEOUT
        )
      end

      def transfer_ownership(session, participant, leave:, timeout: 45, cancellation_token: nil)
        ensure_session!(session)
        params = { "new_owner_id" => participant.id.dup, "leave" => leave, "request_id" => SecureRandom.uuid }
        http = EltenLink::Apps.live_session_ownership_request(session.id, session.participant_id, params)
        check = ->(_first) { session.validate_ownership_transfer!(participant) }
        # A timeout can mean the transfer committed but its reply was lost.
        # Do not retry a change of authority or schedule a fallback departure.
        request = queue_live_request(session, :transfer_ownership, params, retries: 0,
          timeout: timeout, http: http, validator: check)
        data = await_live_request(request, cancellation_token: cancellation_token)
        members = data["participants"]
        valid = data["id"] == session.id && data["participant_id"] == session.participant_id &&
          data["owner_id"] == params["new_owner_id"] && data["previous_owner_id"] == session.participant_id &&
          data["request_id"] == params["request_id"] && data["left"] == leave &&
          data["revision"].is_a?(Integer) && data["revision"] >= 0 && members.is_a?(Array) &&
          members.all? { |row| row.is_a?(Hash) && row["id"].is_a?(String) && !row["id"].empty? }
        if valid
          ids = members.map { |row| row["id"] }
          valid = ids.uniq == ids && ids.include?(params["new_owner_id"]) && ids.include?(session.participant_id) == !leave
        end
        raise EltenLink::Error.new("Invalid ownership transfer confirmation", code: "invalid_json") unless valid
        data
      end

      def update_discovery_metadata(session, metadata, timeout: 45, cancellation_token: nil)
        ensure_session!(session)
        params = { "discovery_metadata" => metadata, "participant_id" => session.participant_id }
        http = EltenLink::Apps.live_session_discovery_request(:update_metadata, params, session_id: session.id)
        request = queue_live_request(session, :update_metadata, params, retries: 0, timeout: timeout, http: http)
        await_live_request(request, cancellation_token: cancellation_token)
      end

      def private_request(session, params, retries: 2, timeout: 45, cancellation_token: nil)
        params = JSON.parse(JSON.generate(params))
        bytes = JSON.generate(params["packet"]).bytesize
        http = EltenLink::Apps.live_session_private_request(session.id, session.participant_id, params)
        check = ->(_first) { session.validate_private_message!(bytes) }
        request = queue_live_request(session, :private_message, params, retries: retries, timeout: timeout, http: http, validator: check)
        await_live_request(request, cancellation_token: cancellation_token)
      end

      def pool_request(session, operation, params, pool_id: nil, draw_id: nil, retries: 2, timeout: 45, cancellation_token: nil, validator: nil)
        params = JSON.parse(JSON.generate(params))
        http = EltenLink::Apps.live_session_pool_request(session.id, session.participant_id, operation, params, pool_id: pool_id, draw_id: draw_id)
        check = ->(first) { session.ensure_pools!; validator.call(first) if validator }
        request = queue_live_request(session, :pool, params, retries: retries, timeout: timeout, http: http, validator: check)
        await_live_request(request, cancellation_token: cancellation_token)
      end

      def random_request(session, operation, params, retries: 2, timeout: 45, cancellation_token: nil, check_capacity: false)
        http = EltenLink::Apps.live_session_random_request(session.id, session.participant_id, operation, params)
        request = queue_live_request(session, operation, params, retries: retries, timeout: timeout, check_capacity: check_capacity, http: http)
        await_live_request(request, cancellation_token: cancellation_token)
      end

      def stack_request(session, operation, params, retries: 2, timeout: 120, cancellation_token: nil, check_capacity: false)
        request = queue_stack_request(session, operation, params, retries: retries, timeout: timeout, check_capacity: check_capacity)
        await_live_request(request, cancellation_token: cancellation_token)
      end

      def queue_stack_request(session, operation, params, retries: 2, timeout: 120, check_capacity: false)
        ensure_session!(session)
        session.ensure_stack!
        check = ->(_first) { session.ensure_stack! }
        queue_live_request(session, operation, params, retries: retries, timeout: timeout, check_capacity: check_capacity, validator: check)
      end

      def cancel_stack_request(request)
        request[:abandoned] = true
        request[:raw]&.close
        request[:cancellation]&.cancel
        @mutex.synchronize { @stack_requests.delete(request) }
      end

      def stack_request_retryable?(error)
        return true if error.is_a?(TimeoutError) || error.is_a?(QueueOverflow)
        error.is_a?(EltenLink::Error) && (%w[network_error timeout invalid_json rate_limits.exceeded rate_limits.unavailable apps.live_sessions.rate_limited apps.live_sessions.busy apps.live_sessions.unavailable].include?(error.code) || [500, 502, 503, 504].include?(error.status.to_i))
      end

      def session_closed(session, confirmed: false, operation: :leave)
        @mutex.synchronize do
          @sessions.delete(session.id)
          @lease_deadlines.delete(session.id)
          unless confirmed
            @departures[session.id] ||= { id: session.id, participant_id: session.participant_id, operation: operation, attempts: 0, next_at: monotonic }
          end
          removed = @pending_envelopes.delete(session.id) || []
          @pending_envelope_bytes -= removed.sum { |item| item[1] }
        end
        true
      end

      # Called only while a public blocking operation is waiting. Scheduling still
      # enters through the application's loop_update; no timer/worker loop is started.
      def wait_step(cancellation_token: nil)
        cancellation_token&.raise_if_cancelled!
        context = @client.context if @client.respond_to?(:context)
        owner = $currentthread if defined?($currentthread)
        owner ||= $mainthread if defined?($mainthread)
        if context && context.respond_to?(:loop_update, true) && (owner.nil? || owner == Thread.current)
          context.__send__(:loop_update, false)
        else
          sleep 0.01
        end
        cancellation_token&.raise_if_cancelled!
      end

      def diagnostics
        @mutex.synchronize do
          {
            instance_id: @instance_id,
            sessions: @sessions.values.map(&:control_entry),
            callback_count: @callback_queue.length,
            callback_bytes: @callback_bytes,
            pending_envelope_bytes: @pending_envelope_bytes,
            control_pending: !@control_pending.nil?,
            pending_departures: @departures.length, stack_requests: @stack_requests.length, stack_pending: !@stack_pending.nil?,
            unresponsive_sessions: @lease_deadlines.select { |_id, deadline| monotonic >= deadline }.keys,
            control_failures: @control_failures,
            last_error_code: @last_error.respond_to?(:code) ? @last_error.code : @last_error&.class&.name
          }
        end
      end

      def on_error(&block)
        register_callback(:error, &block)
      end

      def record_error(error)
        @last_error = error
        Log.warning("Live session error: #{error.class}: #{error.message}") if defined?(Log)
        emit(:error, error)
      end

      def enqueue_callback(callback, *arguments)
        bytes = JSON.generate(arguments).bytesize + 64
        @mutex.synchronize do
          return false if @closed
          if @callback_bytes + bytes > MAX_QUEUE_BYTES
            @overflow = true
            return false
          end
          @callback_queue.push([callback, arguments, bytes], true)
          @callback_bytes += bytes
        end
        true
      rescue ThreadError
        @overflow = true
        false
      end

      def enqueue_envelope(envelope)
        return false if closed?
        kind = envelope["kind"].to_s
        if kind == "events" && envelope["instance_id"].to_s != @instance_id
          return false
        end
        if kind == "invitation"
          receive_invitation(envelope)
        elsif kind == "events"
          receive_events(envelope)
        end
        true
      end

      def tick
        protocol_tick
        dispatch_events
      end

      # Bounded work, invoked by LiveSessions.tick from loop_update before callbacks.
      def protocol_tick
        return false unless @protocol_mutex.try_lock
        begin
          drain_control_responses
          tick_stack_requests
          sessions.each { |session| session.tick_stack_messages(monotonic) }
          expire_invitations
          now = monotonic
          drain_departure_responses
          if @departure_pending && now >= @departure_pending[:deadline]
            pending = @departure_pending
            @departure_pending = nil
            pending[:cancellation]&.cancel
            retry_departure(pending[:departure], TimeoutError.new("Live session departure timed out"))
          end
          if @control_pending && now >= @control_pending[:deadline]
            cancel_control
            control_failed(TimeoutError.new("Live session control timed out"))
          end
          if @overflow
            @overflow = false
            @mutex.synchronize { @callback_queue.clear; @callback_bytes = 0 }
            record_error(QueueOverflow.new("Live session callback queue is full"))
            sessions.each { |session| session.close_local(:queue_overflow) }
          end
          start_control(now) if now >= @next_control_at.to_f && now >= @retry_not_before
          start_departure(now)
          finished = @mutex.synchronize { @closed && @departures.empty? }
          LiveSessions.unregister(self) if finished && @departure_pending.nil? && @stack_pending.nil?
          true
        ensure
          @protocol_mutex.unlock
        end
      end

      def dispatch_events(limit = 100)
        return 0 if closed? || @dispatching
        @dispatching = true
        count = 0
        started = monotonic
        begin
          while count < limit && monotonic - started < 0.01
            callback, arguments, _bytes = @mutex.synchronize do
              entry = @callback_queue.pop(true)
              @callback_bytes -= entry[2]
              entry
            end
            begin
              callback.call(*arguments)
            rescue Exception => error
              Log.warning("Live session callback failed: #{error.class}: #{error.message}") if defined?(Log)
            end
            count += 1
          end
        rescue ThreadError
          nil
        ensure
          @dispatching = false
        end
        count
      end

      private

      def normalize_join_code(code)
        value = code.is_a?(String) ? code.strip.upcase : ""
        minimum = @limits.fetch("min_join_code_length", 6).to_i
        maximum = @limits.fetch("max_join_code_length", 32).to_i
        unless value.match?(/\A[A-Z0-9-]+\z/) && value.bytesize.between?(minimum, maximum)
          raise ArgumentError, "Session code must contain #{minimum} to #{maximum} ASCII letters, digits or hyphens"
        end
        value
      end

      def discovery_request(operation, params, session_id: nil, timeout: 45, cancellation_token: nil, retries: 2)
        ensure_open!
        params = JSON.parse(JSON.generate(params.merge("appid" => @app_id, "instance_id" => @instance_id)))
        http = EltenLink::Apps.live_session_discovery_request(operation, params, session_id: session_id)
        request = queue_live_request(nil, operation, params, timeout: timeout, retries: retries, http: http)
        result = await_live_request(request, cancellation_token: cancellation_token)
        @limits = result["limits"] if result["limits"].is_a?(Hash)
        result
      end

      def queue_live_request(session, operation, params, retries:, timeout:, check_capacity: false, http: nil, validator: nil)
        ensure_open!
        timeout = Float(timeout)
        raise ArgumentError, "timeout must be positive and finite" unless timeout.finite? && timeout.positive?
        token = EltenAPI::Tasks::CancellationToken.new if defined?(EltenAPI::Tasks::CancellationToken)
        request = { session: session, operation: operation, params: params, http: http, attempts: 0, retries: [[retries.to_i, 0].max, 2].min,
          deadline: monotonic + timeout, next_at: monotonic, result: Queue.new, cancellation: token, check_capacity: check_capacity, validator: validator }
        @mutex.synchronize do
          raise SessionClosed, "Live session endpoint is closed" if @closed
          raise QueueOverflow, "Too many pending live session requests" if @stack_requests.length >= MAX_QUEUE_ITEMS
          @stack_requests << request
        end
        request
      end

      def await_live_request(request, cancellation_token: nil)
        loop do
          cancellation_token&.raise_if_cancelled!
          begin
            value, error = request[:result].pop(true)
            raise error if error
            return value
          rescue ThreadError
            raise TimeoutError, "Live session request timed out" if monotonic >= request[:deadline]
            wait_step(cancellation_token: cancellation_token)
          end
        end
      ensure
        cancel_stack_request(request)
      end

      def stack_request_closed?(request)
        @closed || request[:session]&.closed?
      end

      def receive_invitation(data)
        invitation = nil
        @mutex.synchronize do
          id = data["session_id"].to_s
          return if id.empty?
          identity = data["invitation_id"]
          generation = data["generation"].to_i
          resolved = @resolved_invitations[id]
          return if resolved && (identity.nil? || identity == resolved[:id] || generation <= resolved[:generation])
          previous = @invitations[id]
          return if previous && (identity.nil? || identity == previous.invitation_id || generation <= previous.generation)
          previous&.supersede
          invitation = Invitation.new(self, data)
          @invitations[id] = invitation
        end
        @invitation_queue.delete_if { |entry| entry.superseded? || entry.expired? }
        @invitation_queue << invitation unless invitation.superseded?
        callbacks = @mutex.synchronize { @callbacks[:invitation].dup }
        callbacks.each do |callback|
          enqueue_callback(->(entry) { callback.call(entry) unless entry.superseded? }, invitation)
        end
      end

      def receive_events(data)
        session = @mutex.synchronize { @sessions[data["session_id"].to_s] }
        if session.nil?
          bytes = JSON.generate(data).bytesize
          @mutex.synchronize do
            queue = @pending_envelopes[data["session_id"].to_s]
            queue << [data, bytes]
            @pending_envelope_bytes += bytes
            @pending_envelope_bytes -= queue.shift[1] while queue.length > 32
            while @pending_envelopes.length > MAX_PENDING_INVITATIONS || @pending_envelope_bytes > MAX_QUEUE_BYTES
              _, removed = @pending_envelopes.shift
              @pending_envelope_bytes -= removed.sum { |item| item[1] }
            end
          end
          return
        end
        return if !data["participant_id"].to_s.empty? && data["participant_id"].to_s != session.participant_id
        before = session.control_entry["ack"]
        more = session.apply_envelope(data)
        request_control(more ? 0 : ACK_INTERVAL) if more || session.control_entry["ack"] > before
      end

      def store_session(data)
        session = Session.new(self, data)
        pending = @mutex.synchronize do
          existing = @sessions[session.id]
          if existing.nil?
            @sessions[session.id] = session unless @closed
          else
            session = existing
          end
          @next_control_at = monotonic
          removed = @pending_envelopes.delete(session.id) || []
          @pending_envelope_bytes -= removed.sum { |item| item[1] }
          removed.map(&:first)
        end
        if closed?
          session.close_local(:endpoint_closed)
          LiveSessions.register(self)
          raise SessionClosed, "Live session endpoint is closed"
        end
        pending.each { |envelope| receive_events(envelope) }
        @limits = data["limits"] if data["limits"].is_a?(Hash)
        renew_local_lease(session.id)
        session
      end

      def resolve_invitation(id, invitation_id: nil, generation: nil)
        @mutex.synchronize do
          current = @invitations[id.to_s]
          if current && (invitation_id.nil? || invitation_id == current.invitation_id)
            generation ||= current.generation
            @invitations.delete(id.to_s)
          end
          previous = @resolved_invitations[id.to_s]
          if previous.nil? || previous[:generation] <= generation.to_i
            @resolved_invitations[id.to_s] = { at: Time.now.to_i, id: invitation_id, generation: generation.to_i }
          end
          @resolved_invitations.shift while @resolved_invitations.length > MAX_PENDING_INVITATIONS
        end
        discard_resolved_invitation(id, invitation_id)
      end

      def discard_resolved_invitation(id, invitation_id)
        @invitation_queue.delete_if { |entry| entry.id == id.to_s && (invitation_id.nil? || entry.invitation_id == invitation_id) }
      end

      def expire_invitations
        now = Time.now.to_i
        @mutex.synchronize do
          @invitations.delete_if { |_id, invitation| invitation.expires_at.positive? && invitation.expires_at <= now }
          @resolved_invitations.delete_if { |_id, entry| entry[:at] < now - 300 }
        end
      end

      def start_control(now)
        return if @control_pending
        current = sessions
        return if current.empty? || closed?
        maximum = [@limits.fetch("max_sessions_per_user", 16).to_i, 1].max
        entries = current.rotate(@control_rotation % current.length).first(maximum).map(&:control_entry)
        @control_rotation += current.length > maximum ? entries.length : 1
        @control_serial += 1
        serial = @control_serial
        cancellation = EltenAPI::Tasks::CancellationToken.new if defined?(EltenAPI::Tasks::CancellationToken)
        @control_pending = { serial: serial, started_at: now, deadline: now + CONTROL_TIMEOUT, cancellation: cancellation }
        @next_control_at = now + (current.length > maximum ? ACK_INTERVAL : CONTROL_INTERVAL)
        path = EltenLink::Client.append_query(
          "/api/v1/apps/live-sessions/control", { "name" => @user, "token" => @token }
        )
        @client.e_json_request(
          "POST", path,
          { "appid" => @app_id, "instance_id" => @instance_id, "sessions" => entries, "recover" => true },
          cancellation_token: cancellation
        ) do |answer, _data|
          # Network callbacks never schedule the next request.
          @control_responses << [serial, answer]
        end
      rescue Exception => error
        cancel_control
        control_failed(error)
      end

      def drain_control_responses
        loop do
          serial, answer = @control_responses.pop(true)
          next unless @control_pending && @control_pending[:serial] == serial
          started_at = @control_pending[:started_at]
          @control_pending = nil
          begin
            payload = answer.is_a?(String) ? JSON.parse(answer) : nil
            data = payload.is_a?(Hash) && payload["success"] == true ? payload["data"] : nil
            unless data.is_a?(Hash) && data["accepted"] == true
              error = EltenLink::Error.new(
                payload.is_a?(Hash) ? payload.dig("error", "message") : "Live session control failed",
                code: payload.is_a?(Hash) ? payload.dig("error", "code") : "network_error", response: payload
              )
              control_failed(error)
              next
            end
            @control_failures = 0
            @retry_not_before = 0.0
            @last_error = nil
            @limits = data["limits"] if data["limits"].is_a?(Hash)
            lease = data["lease_seconds"].to_f
            interval = lease.positive? ? [[lease / 3.0, 2.0].max, CONTROL_INTERVAL].min : CONTROL_INTERVAL
            @mutex.synchronize { @next_control_at = [@next_control_at.to_f, monotonic + interval].min }
            retry_after = 0
            Array(data["sessions"]).each do |status|
              next unless status.is_a?(Hash)
              if status["accepted"] == true
                seconds = status["lease_until"] ? status["lease_until"].to_f - data["time"].to_f : lease
                renew_local_lease(status["id"].to_s, seconds: seconds, started_at: started_at)
                session = @mutex.synchronize { @sessions[status["id"].to_s] }
                session&.apply_stack_state(status["stack"], status["limits"])
                next
              end
              if status["retryable"] == true
                retry_after = [retry_after, status["retry_after"].to_f, 1].max
                next
              end
              session = @mutex.synchronize { @sessions[status["id"].to_s] }
              session&.close_local((status["reason"] || "expired").to_sym, confirmed: true)
            end
            Array(data["envelopes"]).each { |envelope| enqueue_envelope(envelope) }
            request_control if data["has_more"] == true
            if retry_after.positive?
              control_failed(Error.new("Live session control temporarily unavailable"), retry_after: retry_after)
            end
          rescue JSON::ParserError, TypeError => error
            control_failed(error)
          end
        end
      rescue ThreadError
        nil
      end

      def tick_stack_requests
        loop do
          request, attempt, value, error = @stack_responses.pop(true)
          next unless @stack_pending.equal?(request) && request[:attempts] == attempt
          @stack_pending = nil
          request[:raw].close
          next if request[:abandoned]
          if error
            retryable = stack_request_retryable?(error)
            delay = [error.respond_to?(:retry_after) ? error.retry_after.to_f : 0, 2**[attempt - 1, 2].min].max
            if retryable && attempt <= request[:retries] && monotonic + delay < request[:deadline] && !stack_request_closed?(request)
              request[:next_at] = monotonic + delay
              @mutex.synchronize { @stack_requests << request }
            else
              request[:result] << [nil, error]
            end
          else
            if request[:session]
              request[:session].apply_stack_state(value["stack"], value["limits"])
              renew_local_lease(request[:session].id)
            end
            request[:result] << [value, nil]
          end
        end
      rescue ThreadError
        now = monotonic
        if @stack_pending && (@stack_pending[:abandoned] || stack_request_closed?(@stack_pending) || now >= @stack_pending[:deadline])
          request = @stack_pending
          @stack_pending = nil
          request[:abandoned] = true
          request[:raw].close
          request[:cancellation]&.cancel
          error = stack_request_closed?(request) ? SessionClosed.new("Live session is closed") : TimeoutError.new("Live session stack request timed out")
          request[:result] << [nil, error]
        end
        if @stack_pending && now >= @stack_pending[:attempt_deadline] && !@stack_pending[:timed_out]
          request = @stack_pending
          request[:timed_out] = true
          request[:raw].close
          request[:cancellation]&.cancel
          @stack_responses << [request, request[:attempts], nil, EltenLink::Error.timeout]
        end
        @mutex.synchronize do
          @stack_requests.delete_if do |request|
            invalid = request[:abandoned] || stack_request_closed?(request) || now >= request[:deadline]
            request[:result] << [nil, stack_request_closed?(request) ? SessionClosed.new("Live session is closed") : TimeoutError.new("Live session stack request timed out")] if invalid && !request[:abandoned]
            invalid
          end
        end
        start_stack_request(now) unless @stack_pending
      end

      def start_stack_request(now)
        request = @mutex.synchronize do
          index = @stack_requests.index { |entry| entry[:next_at] <= now }
          index && @stack_requests.delete_at(index)
        end
        return unless request
        request[:validator]&.call(request[:attempts].zero?)
        if [:random, :stack_random].include?(request[:operation])
          request[:session].validate_random_request!(request[:operation], request[:params], capacity: request[:check_capacity] && request[:attempts].zero?)
        elsif request[:operation] == :push
          request[:session].validate_stack_push!(JSON.generate(request[:params]["packet"]).bytesize, capacity: request[:check_capacity] && request[:attempts].zero?)
        end
        @stack_pending = request
        request[:timed_out] = false
        request[:attempt_deadline] = request[:operation] == :read ? request[:deadline] : [now + 15, request[:deadline]].min
        request[:cancellation] = EltenAPI::Tasks::CancellationToken.new if defined?(EltenAPI::Tasks::CancellationToken)
        request[:attempts] += 1
        attempt = request[:attempts]
        raw = request[:raw] = Queue.new
        cancellation = request[:cancellation]
        method, path, params = request[:http] || EltenLink::Apps.live_session_stack_request(request[:session].id, request[:session].participant_id, request[:operation], request[:params])
        auth = { "name" => @user, "token" => @token }
        if method == "GET" || method == "DELETE"
          path = EltenLink::Client.append_query(path, params.merge(auth))
          params = {}
        else
          path = EltenLink::Client.append_query(path, auth)
        end
        Thread.new do
          begin
            @client.e_json_request(method, path, params, cancellation_token: cancellation) do |answer, _data|
              raw << answer unless raw.closed?
            rescue ClosedQueueError
              nil
            end
            answer = raw.pop
            next if request[:abandoned] || answer.nil?
            payload = answer.is_a?(String) ? JSON.parse(answer) : nil
            unless payload.is_a?(Hash) && payload["success"] == true && payload["data"].is_a?(Hash)
              raise EltenLink::Error.new(payload.is_a?(Hash) ? payload.dig("error", "message") : "Live session stack request failed",
                code: payload.is_a?(Hash) ? payload.dig("error", "code") : "network_error", response: payload)
            end
            @stack_responses << [request, attempt, payload["data"], nil] unless request[:abandoned]
          rescue JSON::ParserError => error
            @stack_responses << [request, attempt, nil, EltenLink::Error.new(error.message, code: "invalid_json")] unless request[:abandoned]
          rescue Exception => error
            @stack_responses << [request, attempt, nil, error] unless request[:abandoned]
          end
        end
      rescue StandardError => error
        @stack_pending = nil
        request[:result] << [nil, error] if request
      end

      def start_departure(now)
        return if @departure_pending
        departure = @mutex.synchronize { @departures.values.find { |entry| entry[:next_at] <= now } }
        return unless departure
        @departure_serial += 1
        serial = @departure_serial
        departure[:attempts] += 1
        cancellation = EltenAPI::Tasks::CancellationToken.new if defined?(EltenAPI::Tasks::CancellationToken)
        @departure_pending = { serial: serial, departure: departure, deadline: now + CONTROL_TIMEOUT, cancellation: cancellation }
        path = EltenLink::Client.append_query(
          "#{EltenLink::Apps.live_session_path(departure[:id])}/#{departure[:operation]}",
          { "name" => @user, "token" => @token }
        )
        @client.e_json_request("POST", path, { "participant_id" => departure[:participant_id] }, cancellation_token: cancellation) do |answer, _data|
          @departure_responses << [serial, answer]
        end
      rescue StandardError => error
        @departure_pending = nil
        cancellation&.cancel
        retry_departure(departure, error) if departure
      end

      def drain_departure_responses
        loop do
          serial, answer = @departure_responses.pop(true)
          next unless @departure_pending && @departure_pending[:serial] == serial
          departure = @departure_pending[:departure]
          @departure_pending = nil
          begin
            payload = answer.is_a?(String) ? JSON.parse(answer) : nil
            code = payload.is_a?(Hash) ? payload.dig("error", "code").to_s : "network_error"
            if payload.is_a?(Hash) && (payload["success"] == true || %w[apps.live_sessions.not_found apps.live_sessions.membership_required auth.unauthorized].include?(code))
              @mutex.synchronize { @departures.delete(departure[:id]) }
            elsif code == "apps.live_sessions.owner_required" || code == "apps.live_sessions.closed"
              departure[:operation] = :leave
              departure[:next_at] = monotonic
            else
              error = EltenLink::Error.new(
                payload.is_a?(Hash) ? payload.dig("error", "message") : "Live session departure failed",
                code: code, response: payload
              )
              retry_departure(departure, error)
            end
          rescue JSON::ParserError, TypeError => error
            retry_departure(departure, error)
          end
        end
      rescue ThreadError
        nil
      end

      def retry_departure(departure, error)
        advertised = error.respond_to?(:retry_after) ? error.retry_after.to_f : 0
        departure[:next_at] = monotonic + [[2**[departure[:attempts] - 1, 5].min, 30].min, advertised].max
        record_error(error)
      end

      def renew_local_lease(id, seconds: nil, started_at: nil)
        seconds ||= @limits.fetch("member_lease_seconds", 30).to_f
        @mutex.synchronize do
          @lease_deadlines[id] = [@lease_deadlines[id].to_f, (started_at || monotonic) + seconds].max if @sessions.key?(id)
        end
      end

      def cancel_control
        pending = @control_pending
        @control_pending = nil
        pending[:cancellation]&.cancel if pending
      end

      def control_failed(error, retry_after: nil)
        @control_failures += 1
        advertised = retry_after || (error.retry_after if error.respond_to?(:retry_after))
        delay = [[2**[@control_failures - 1, 3].min, 5].min, advertised.to_f].max
        @retry_not_before = monotonic + delay
        @mutex.synchronize { @next_control_at = @retry_not_before }
        record_error(error)
      end

      def request_control(delay = 0)
        @mutex.synchronize { @next_control_at = [@next_control_at.to_f, monotonic + delay.to_f].min }
      end

      def ensure_session!(session)
        ensure_open!
        known = @mutex.synchronize { @sessions[session.id].equal?(session) }
        raise ArgumentError, "session does not belong to this endpoint" unless known
        raise SessionClosed, "Live session is closed" if session.closed?
        true
      end

      def ensure_open!
        raise SessionClosed, "Live session endpoint is closed" if closed?
      end

      def register_callback(kind, &block)
        raise ArgumentError, "callback is required" if block == nil
        @mutex.synchronize { @callbacks[kind] << block }
        self
      end

      def emit(kind, *arguments)
        callbacks = @mutex.synchronize { @callbacks[kind].dup }
        callbacks.each { |callback| enqueue_callback(callback, *arguments) }
      end

      def session_value(name)
        session = if defined?(EltenAPI::Structs::Session)
                    EltenAPI::Structs::Session
                  elsif Object.const_defined?(:Session)
                    Object.const_get(:Session)
                  end
        session.respond_to?(name) ? session.public_send(name) : nil
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class << self
      def register(endpoint)
        mutex.synchronize do
          endpoints << endpoint
          pending_for(endpoint.app_id).each { |envelope| endpoint.enqueue_envelope(envelope) }
        end
        true
      end

      def unregister(endpoint)
        mutex.synchronize { endpoints.delete(endpoint) }
        true
      end

      def receive(rows)
        Array(rows).each do |row|
          next unless row.is_a?(Hash)
          appid = row["appid"].to_s.downcase
          selected = mutex.synchronize do
            found = endpoints.select { |endpoint| endpoint.app_id == appid && !endpoint.closed? }
            remember_pending(appid, row) if found.empty? && row["kind"].to_s == "invitation"
            found
          end
          selected.each { |endpoint| endpoint.enqueue_envelope(row) }
        end
        true
      end

      def tick(dispatch: true)
        current = mutex.synchronize do
          cleanup_pending
          endpoints.dup
        end
        current.each do |endpoint|
          begin
            endpoint.protocol_tick
          rescue StandardError => error
            endpoint.record_error(error)
          end
        end
        if dispatch && !@dispatching
          @dispatching = true
          begin
            current.each(&:dispatch_events)
          ensure
            @dispatching = false
          end
        end
        true
      end

      def reconnect
        current = mutex.synchronize { endpoints.dup }
        current.each { |endpoint| endpoint.__send__(:request_control) }
        true
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end

      def endpoints
        @endpoints ||= []
      end

      def pending
        @pending ||= Hash.new { |hash, key| hash[key] = {} }
      end

      def pending_for(appid)
        pending[appid.to_s.downcase].values
      end

      def remember_pending(appid, row)
        bucket = pending[appid]
        previous = bucket[row["session_id"].to_s]
        return if previous && previous["generation"].to_i > row["generation"].to_i
        bucket[row["session_id"].to_s] = row
        bucket.shift while bucket.length > MAX_PENDING_INVITATIONS
      end

      def cleanup_pending
        now = Time.now.to_i
        pending.delete_if do |_appid, bucket|
          bucket.delete_if { |_id, row| row["expires_at"].to_i.positive? && row["expires_at"].to_i <= now }
          bucket.empty?
        end
      end
    end
  end
end
