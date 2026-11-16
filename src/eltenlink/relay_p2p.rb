# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# frozen_string_literal: true

require "ipaddr"

module EltenLink
  module Relay
    class P2PTransport
      REG_MAGIC = "ELP0".b
      PEER_MAGIC = "ELP1".b
      DATA_HEADER = 22
      MAX_BUFFER_BYTES = 8 * 1024 * 1024
      MAX_PENDING = 128
      PATH_TIMEOUT = 3.0
      Peer = Struct.new(:id, :pair_id, :cipher, :addresses, :selected, :last_pong,
                        :rtt, :next_probe, :nonces, :cursor, keyword_init: true)

      def initialize(client, client_id, secret, host, port, enabled: true)
        @client, @host, @port = client, host, port
        @allowed = @policy_applied = enabled
        @policy_pending = false
        @next_policy_update = 0.0
        registration_key = OpenSSL::HMAC.digest("SHA256", secret, "elten-p2p-registration-v1")
        @registration = DatagramCipher.new(client_id, registration_key, role: :client)
        @mutex, @start_mutex = Mutex.new, Mutex.new
        @sessions, @pairs, @pending, @assemblies = {}, {}, {}, {}
        @pending_bytes = @assembly_bytes = 0
        @tasks = Queue.new
        @sockets = {}
        @closed = @started = @failed = false
        @packet_limit = [client.limit(:max_datagram), 1200].min
        @chunk_size = @packet_limit - 48 - DATA_HEADER
        @byte_tokens, @packet_tokens, @budget_at = 256 * 1024.0, 100.0, monotonic
        @next_registration = @next_candidates = 0.0
        @last_candidates = nil
      end

      def update_policy
        queued = @mutex.synchronize { update_policy_locked }
        start if queued
      end

      def track(snapshot)
        mode = snapshot.fetch("p2p", "off")
        return if mode == "off"
        @mutex.synchronize do
          id = snapshot["id"].to_s
          old = @sessions[id]
          if !old || old[:epoch] < snapshot["epoch"].to_i
            @sessions[id] = {
              mode: mode, epoch: snapshot["epoch"].to_i, self_id: snapshot["self_id"],
              participants: Array(snapshot["participants"]).map { |row| row["id"] },
              active: snapshot.fetch("p2p_participants_limit", 2).zero? ||
                Array(snapshot["participants"]).length <= snapshot.fetch("p2p_participants_limit", 2),
              peers: {}
            }
          end
        end
        start
      end

      def event(frame)
        case frame["type"]
        when "p2p_state" then update_state(frame)
        when "delivery" then delivery(frame["session_id"], frame["message_id"], frame["participant_id"], frame["status"])
        when "session_closed" then forget(frame["session_id"])
        end
      end

      def update_state(frame)
        @mutex.synchronize do
          id, epoch = frame["session_id"].to_s, frame["epoch"].to_i
          previous = @sessions[id]
          return if previous && previous[:epoch] > epoch
          peers = {}
          Array(frame["peers"]).each do |row|
            old = previous && previous[:peers][row["id"]]
            if old && old.pair_id == row["pair_id"]
              old.addresses = Array(row["addresses"]).first(9)
              peers[row["id"]] = old
              next
            end
            secret = Base64.strict_decode64(row["secret"].to_s)
            role = frame["self_id"].to_s < row["id"].to_s ? :client : :server
            peers[row["id"]] = Peer.new(
              id: row["id"], pair_id: row["pair_id"],
              cipher: DatagramCipher.new(row["pair_id"], secret, role: role),
              addresses: Array(row["addresses"]).first(9), last_pong: 0.0,
              next_probe: 0.0, nonces: {}, cursor: 0)
          end
          @sessions[id] = {
            mode: frame["p2p"], epoch: epoch, self_id: frame["self_id"],
            participants: Array(frame["participants"]), active: frame["active"] == true, peers: peers
          }
          rebuild_pairs
          @assemblies.delete_if do |key, value|
            obsolete = !@pairs.key?(key[0])
            @assembly_bytes -= value[:bytes] if obsolete
            obsolete
          end
        end
        start if frame["p2p"] != "off"
      end

      def status(session_id)
        @mutex.synchronize do
          session = @sessions[session_id]
          next {} unless session
          session[:participants].reject { |id| id == session[:self_id] }.to_h do |id|
            peer = session[:peers][id]
            [id, { transport: session[:active] && ready?(peer) ? :p2p : :relay, latency: peer&.rtt }]
          end
        end
      end

      def reliable?(session_id)
        @mutex.synchronize do
          session = @sessions[session_id]
          @pending.keys.any? { |key| key[0] == session_id } ||
            (session && session[:mode] == "full" && session[:active] && session[:peers].values.any? { |peer| ready?(peer) })
        end
      end

      def send_reliable(session_id:, epoch:, message_id:, targets:, envelope:)
        direct = @mutex.synchronize do
          raise RemoteError.new("rate_limited", "P2P reliable queue is full") if
            @pending.length >= MAX_PENDING || @pending_bytes + envelope.bytesize > MAX_BUFFER_BYTES
          session = @sessions[session_id]
          raise ConnectionError, "P2P session is closed" unless session && !@closed
          wanted = target_ids(session, targets)
          wanted.select { |id| session[:active] && session[:epoch] == epoch && ready?(session[:peers][id]) }
        end
        result = @client.__send__(:request, "p2p_reliable", {
          "session_id" => session_id, "epoch" => epoch, "message_id" => message_id,
          "targets" => targets, "direct_targets" => direct, "bytes" => envelope.bytesize,
          "digest" => OpenSSL::Digest::SHA256.hexdigest(envelope)
        })
        @mutex.synchronize do
          raise ConnectionError, "P2P session is closed" if @closed || !@sessions.key?(session_id)
          pending = (result["statuses"] || {}).select { |_id, status| status == "pending" }
          unless pending.empty?
            @pending[[session_id, message_id]] = {
              epoch: epoch, envelope: envelope, created_at: monotonic,
              recipients: pending.to_h do |id, _|
                [id, { direct: Array(result["direct_targets"]).include?(id), offset: 0,
                       rounds: 0, next_send: 0.0, started: nil, fallback: false }]
              end
            }
            @pending_bytes += envelope.bytesize
          end
        end
        result
      end

      def send_unreliable(session_id:, epoch:, message_id:, targets:, envelope:)
        @mutex.synchronize do
          session = @sessions[session_id]
          next nil unless session && session[:active] && session[:epoch] == epoch && !@closed
          target_ids(session, targets).reject do |id|
            peer = session[:peers][id]
            next false unless ready?(peer)
            packets = fragments(peer, 0, epoch, message_id, envelope)
            packets.all? { |packet| send_packet(packet, peer.selected) }
          end
        end
      end

      def close
        sockets = @mutex.synchronize do
          return if @closed
          @closed = true
          @sessions.clear
          @pairs.clear
          @pending.clear
          @assemblies.clear
          @pending_bytes = @assembly_bytes = 0
          @tasks.clear
          @tasks.close
          @sockets.values.dup
        end
        sockets.each { |socket| socket.close rescue nil }
      end

      private

      def enabled?
        @allowed && @policy_applied == true && @client.p2p_allowed?
      end

      def update_policy_locked
        return false if @closed

        allowed = @client.p2p_allowed?
        if @allowed != allowed
          @allowed = allowed
          @policy_applied = nil
          @sessions.each_value do |session|
            session[:peers].each_value do |peer|
              peer.selected = nil
              peer.last_pong = 0.0
              peer.nonces.clear
            end
          end
          @assemblies.clear
          @assembly_bytes = 0
          @last_candidates = nil
          @next_registration = @next_candidates = @next_policy_update = 0.0
        end
        return false if @allowed == @policy_applied || @policy_pending || monotonic < @next_policy_update

        @policy_pending = true
        @tasks << [:policy, @allowed]
        true
      end

      def start
        @start_mutex.synchronize do
          return if @started || @closed
          @started = true
          [Socket::AF_INET, Socket::AF_INET6].each do |family|
            socket = nil
            begin
              socket = UDPSocket.new(family)
              socket.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_V6ONLY, 1) if family == Socket::AF_INET6
              socket.bind(family == Socket::AF_INET ? "0.0.0.0" : "::", 0)
              @mutex.synchronize do
                if @closed
                  socket.close
                else
                  @sockets[family] = socket
                end
              end
            rescue IOError, SystemCallError, SocketError
              socket&.close rescue nil
            end
          end
          return if @closed
          begin
            @host = Addrinfo.getaddrinfo(@host, @port, Socket::AF_INET, Socket::SOCK_DGRAM).first.ip_address
          rescue SocketError
            begin
              @host = Addrinfo.getaddrinfo(@host, @port, Socket::AF_INET6, Socket::SOCK_DGRAM).first.ip_address
            rescue SocketError
              @host = nil
            end
          end
          @worker = Thread.new { worker_loop }
          @thread = Thread.new { run }
        end
      end

      def forget(id)
        @mutex.synchronize do
          @sessions.delete(id)
          @pending.keys.select { |key| key[0] == id }.each { |key| remove_pending(key) }
          rebuild_pairs
          @assemblies.delete_if do |key, value|
            gone = !@pairs.key?(key[0])
            @assembly_bytes -= value[:bytes] if gone
            gone
          end
        end
      end

      def rebuild_pairs
        @pairs = {}
        @sessions.each { |id, session| session[:peers].each_value { |peer| @pairs[peer.pair_id] = [id, peer] } }
      end

      def target_ids(session, targets)
        targets = Array(targets).map(&:to_s)
        (targets.empty? ? session[:participants] : targets).uniq.reject { |id| id == session[:self_id] }
      end

      def ready?(peer)
        enabled? && !@failed && peer && peer.selected && monotonic - peer.last_pong <= PATH_TIMEOUT
      end

      def fragments(peer, kind, epoch, message_id, envelope)
        count = (envelope.bytesize.to_f / @chunk_size).ceil
        Array.new(count) do |index|
          header = [3, kind, epoch, message_id, index, count, envelope.bytesize].pack("CCNQ>nnN")
          PEER_MAGIC + peer.cipher.encode(header + envelope.byteslice(index * @chunk_size, @chunk_size))
        end
      end

      def send_packet(packet, endpoint)
        return false unless enabled? && endpoint && packet.bytesize <= @packet_limit
        now = monotonic
        elapsed = now - @budget_at
        @budget_at = now
        @byte_tokens = [256 * 1024.0, @byte_tokens + elapsed * 512 * 1024].min
        @packet_tokens = [100.0, @packet_tokens + elapsed * 500].min
        return false if @byte_tokens < packet.bytesize || @packet_tokens < 1
        socket = @sockets[endpoint[0].include?(":") ? Socket::AF_INET6 : Socket::AF_INET]
        return false unless socket
        @byte_tokens -= packet.bytesize
        @packet_tokens -= 1
        socket.sendmsg_nonblock(packet, 0, Socket.sockaddr_in(endpoint[1], endpoint[0]), exception: false) == packet.bytesize
      rescue IOError, SystemCallError, SocketError, ArgumentError
        false
      end

      def run
        loop do
          sockets = @mutex.synchronize do
            break nil if @closed
            tick_locked
            @sockets.values.dup
          end
          break unless sockets
          if sockets.empty?
            sleep(0.05)
            next
          end
          readable = IO.select(sockets, nil, nil, 0.025)&.first || []
          readable.each do |socket|
            32.times do
              begin
                packet = socket.recvfrom_nonblock(@packet_limit + 1, exception: false)
              rescue Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH
                break
              end
              break if packet == :wait_readable
              data, address = packet
              next if data.bytesize > @packet_limit
              receive(data, [address[3], address[1]])
            end
          end
        end
      rescue IOError, SystemCallError
        disable_paths
        retry unless @closed
      rescue StandardError => error
        Log.warning("P2P transport unavailable: #{error.class}: #{error.message}") if defined?(Log)
        disable_paths
        retry unless @closed
      end

      def disable_paths
        @mutex.synchronize do
          @failed = true
          @sockets.each_value { |socket| socket.close rescue nil }
          @sockets.clear
          @sessions.each_value { |session| session[:peers].each_value { |peer| peer.selected = nil } }
          @pending.each do |key, record|
            record[:recipients].each { |id, recipient| queue_fallback(key, id, recipient, record) }
          end
        end
      end

      def tick_locked
        update_policy_locked
        now = monotonic
        active = enabled? && !@failed && @sessions.values.any? { |session| session[:active] && session[:mode] != "off" }
        if active && @host && now >= @next_registration
          send_packet(REG_MAGIC + @registration.encode("R".b + SecureRandom.random_bytes(8)), [@host, @port])
          @next_registration = now + 3
        end
        if active && now >= @next_candidates
          candidates = local_candidates
          if candidates != @last_candidates
            @last_candidates = candidates
            @tasks << [:candidates, candidates]
          end
          @next_candidates = now + 10
        end
        @pairs.each_value do |_session_id, peer|
          next if !enabled? || @failed || peer.next_probe > now
          endpoints = ready?(peer) ? [peer.selected] : peer.addresses.rotate(peer.cursor).first(2)
          peer.cursor = (peer.cursor + 2) % [peer.addresses.length, 1].max
          endpoints.each do |endpoint|
            nonce = SecureRandom.random_bytes(8)
            if send_packet(PEER_MAGIC + peer.cipher.encode("P".b + nonce), endpoint)
              peer.nonces[nonce] = now
            end
          end
          peer.nonces.delete_if { |_nonce, time| now - time > PATH_TIMEOUT }
          peer.next_probe = now + (ready?(peer) ? 0.75 : 1.0)
        end
        @assemblies.delete_if do |_key, value|
          expired = now - value[:created_at] > (value[:kind] == 1 ? 5 : 1)
          @assembly_bytes -= value[:bytes] if expired
          expired
        end
        busy = {}
        packet_count = 0
        @pending.to_a.each do |key, record|
          if now - record[:created_at] > 35
            remove_pending(key)
            next
          end
          record[:recipients].each do |id, recipient|
            route = [key[0], id]
            next if busy[route]
            busy[route] = true
            next if recipient[:fallback]
            session = @sessions[key[0]]
            peer = session && session[:peers][id]
            if !recipient[:direct] || !session || !session[:active] ||
                session[:epoch] != record[:epoch] || !ready?(peer) ||
                (recipient[:started] && now - recipient[:started] > [[peer.rtt.to_f * 6, 1.0].max, 3.0].min)
              queue_fallback(key, id, recipient, record)
              next
            end
            next if now < recipient[:next_send] || packet_count >= 32
            recipient[:started] ||= now
            count = (record[:envelope].bytesize.to_f / @chunk_size).ceil
            while recipient[:offset] < count && packet_count < 32
              index = recipient[:offset]
              header = [3, 1, record[:epoch], key[1], index, count, record[:envelope].bytesize].pack("CCNQ>nnN")
              packet = PEER_MAGIC + peer.cipher.encode(header + record[:envelope].byteslice(index * @chunk_size, @chunk_size))
              break unless send_packet(packet, peer.selected)
              recipient[:offset] += 1
              packet_count += 1
            end
            if recipient[:offset] == count
              recipient[:rounds] += 1
              recipient[:offset] = 0
              recipient[:next_send] = now + (recipient[:rounds] >= 3 ? 3 : [0.2, peer.rtt.to_f * 2].max)
            end
          end
        end
      end

      def local_candidates
        Socket.ip_address_list.filter_map do |address|
          next unless address.ipv4? || address.ipv6?
          ip = IPAddr.new(address.ip_address)
          next if ip.loopback? || ip.to_i.zero? ||
            (ip.ipv6? && (IPAddr.new("fe80::/10").include?(ip) || IPAddr.new("ff00::/8").include?(ip)))
          socket = @sockets[address.afamily]
          [ip.to_s, socket.addr[1]] if socket
        end.uniq.first(8)
      rescue SocketError, SystemCallError, IPAddr::InvalidAddressError
        []
      end

      def receive(packet, endpoint)
        event = @mutex.synchronize do
          return if @closed || !enabled?
          if packet.byteslice(0, 4) == REG_MAGIC
            return unless endpoint == [@host, @port]
            clear = @registration.decode(packet.byteslice(4..-1))
            if clear && clear.bytesize == 9 && clear.getbyte(0) == 82
              send_packet(REG_MAGIC + @registration.encode("C".b + clear.byteslice(1, 8)), endpoint)
            end
            return
          end
          return unless packet.byteslice(0, 4) == PEER_MAGIC
          inner = packet.byteslice(4..-1)
          pair = @pairs[DatagramCipher.client_id(inner)]
          return unless pair
          session_id, peer = pair
          session = @sessions[session_id]
          return unless session && session[:active]
          clear = peer.cipher.decode(inner)
          return unless clear
          if clear.bytesize == 9 && clear.getbyte(0) == 80
            send_packet(PEER_MAGIC + peer.cipher.encode("Q".b + clear.byteslice(1, 8)), endpoint)
            unless peer.addresses.include?(endpoint)
              peer.addresses = (peer.addresses.first(8) + [endpoint]).uniq
              peer.next_probe = 0.0
            end
            return
          elsif clear.bytesize == 9 && clear.getbyte(0) == 81
            sent = peer.nonces.delete(clear.byteslice(1, 8))
            if sent && monotonic - sent <= PATH_TIMEOUT
              peer.selected = endpoint
              peer.last_pong = monotonic
              peer.rtt = peer.last_pong - sent
            end
            return
          end
          receive_fragment(session_id, session, peer, clear)
        end
        @client.__send__(:emit_event, event) if event
      rescue ArgumentError
        nil
      end

      def receive_fragment(session_id, session, peer, clear)
        return unless clear.bytesize > DATA_HEADER && clear.getbyte(0) == 3
        _type, kind, epoch, message_id, index, count, total = clear.unpack("CCNQ>nnN")
        return unless [0, 1].include?(kind) && epoch == session[:epoch]
        return if kind == 1 && session[:mode] != "full"
        maximum = @client.limit(kind == 1 ? :max_reliable_data : :max_unreliable_data) + 32
        return unless total.between?(20, maximum) && count == (total.to_f / @chunk_size).ceil && index < count
        data = clear.byteslice(DATA_HEADER..-1)
        expected = index == count - 1 ? total - index * @chunk_size : @chunk_size
        return unless data.bytesize == expected
        key = [peer.pair_id, kind, message_id]
        assembly = @assemblies[key]
        if !assembly
          return if @assemblies.length >= MAX_PENDING || @assembly_bytes + data.bytesize > MAX_BUFFER_BYTES
          assembly = { total: total, count: count, parts: {}, bytes: 0, created_at: monotonic, kind: kind }
          @assemblies[key] = assembly
        end
        return unless assembly[:total] == total && assembly[:count] == count
        unless assembly[:parts].key?(index)
          return if @assembly_bytes + data.bytesize > MAX_BUFFER_BYTES
          assembly[:parts][index] = data
          assembly[:bytes] += data.bytesize
          @assembly_bytes += data.bytesize
        end
        return unless assembly[:parts].length == count
        envelope = Array.new(count) { |i| assembly[:parts][i] }.join.b
        @assemblies.delete(key)
        @assembly_bytes -= assembly[:bytes]
        {
          "type" => "message", "kind" => kind == 1 ? "reliable" : "unreliable",
          "session_id" => session_id, "sender_id" => peer.id, "epoch" => epoch,
          "message_id" => message_id, "raw_data" => envelope
        }
      end

      def queue_fallback(key, id, recipient, record)
        return if recipient[:fallback] || @closed
        recipient[:fallback] = true
        @tasks << [:fallback, key, id, record[:envelope]]
      end

      def worker_loop
        while (task = @tasks.pop)
          break if @closed
          begin
            if task[0] == :policy
              @client.__send__(:request, "set_p2p_enabled", { "enabled" => task[1] }, pump_events: false)
              @mutex.synchronize do
                @policy_applied = task[1]
                @policy_pending = false
              end
            elsif task[0] == :candidates
              next unless @mutex.synchronize { enabled? }

              @client.__send__(:request, "p2p_candidates", { "candidates" => task[1] }, pump_events: false)
            else
              _, key, id, envelope = task
              active = @mutex.synchronize { @pending[key]&.dig(:recipients, id) }
              next unless active
              result = @client.__send__(:request, "p2p_fallback", {
                "session_id" => key[0], "message_id" => key[1],
                "targets" => [id], "data" => Base64.strict_encode64(envelope)
              }, pump_events: false)
              result.fetch("statuses", {}).each do |participant, status|
                next if status == "pending"
                delivery(key[0], key[1], participant, status)
                @client.__send__(:emit_event, {
                  "type" => "delivery", "session_id" => key[0], "message_id" => key[1],
                  "participant_id" => participant, "status" => status
                })
              end
            end
          rescue Error
            if task[0] == :policy
              @mutex.synchronize do
                @policy_pending = false
                @next_policy_update = monotonic + 1
              end
            elsif task[0] == :fallback
              @mutex.synchronize do
                recipient = @pending[task[1]]&.dig(:recipients, task[2])
                if recipient
                  recipient[:fallback] = false
                  recipient[:direct] = false
                end
              end
            else
              @mutex.synchronize { @last_candidates = nil }
            end
            break if @client.closed?
            sleep(0.1)
          end
        end
      end

      def delivery(session_id, message_id, participant_id, status)
        return if status == "pending"
        @mutex.synchronize do
          key = [session_id, message_id.to_i]
          record = @pending[key]
          return unless record
          record[:recipients].delete(participant_id)
          remove_pending(key) if record[:recipients].empty?
        end
      end

      def remove_pending(key)
        record = @pending.delete(key)
        @pending_bytes -= record[:envelope].bytesize if record
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
