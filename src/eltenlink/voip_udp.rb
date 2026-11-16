require "ipaddr"
require "securerandom"
require_relative "voip_datagram"

module EltenLink
  class VoIP
    class UDPTransport
      PATH_TIMEOUT = 3.0
      STATE_TIMEOUT = 3.0
      Peer = Struct.new(:id, :cipher, :addresses, :selected, :last_pong, :next_probe, :nonces, :cursor)
      attr_reader :server

      def initialize(owner, registration, host, port)
        @owner = owner
        @server = [Addrinfo.getaddrinfo(host, port, Socket::AF_INET, Socket::SOCK_DGRAM).first.ip_address, port]
        @control = Datagram.new(registration.fetch("id"),
          Base64.strict_decode64(registration.fetch("secret")), role: :client)
        @mutex = Mutex.new
        @peers, @pairs, @users = {}, {}, {}
        @media = nil
        @active = false
        @channel = @stamp = 0
        @valid_until = @next_registration = @last_ack = 0.0
      end

      def update_params
        {
          "p2p_enabled" => allowed?,
          "p2p_candidates" => allowed? ? local_candidates : [],
          "udp_relay" => server_ready?
        }
      end

      def configure(response, requested_at)
        return unless response.is_a?(Hash)
        @mutex.synchronize do
          state = response["state"]
          if state
            bits = state.fetch("key_len")
            media = state.fetch("media")
            if !@media || @media.id != media["id"]
              @media = Datagram.new(media.fetch("id"), Base64.strict_decode64(media.fetch("secret")),
                role: :client, bits: bits)
            end
            @channel, @stamp = state.fetch("channel"), state.fetch("stamp")
            @active = state["active"] == true
            @users = state.fetch("users").to_h { |row| [row.fetch("id"), row] }
            peers = {}
            state.fetch("peers").each do |row|
              old = @peers[row["id"]]
              addresses = row.fetch("addresses")
              if old && old.cipher.id == row["pair_id"]
                if old.addresses != addresses
                  old.selected = nil
                  old.nonces.clear
                  old.addresses = addresses
                end
                peers[old.id] = old
              else
                role = @owner.uid < row["id"] ? :client : :server
                cipher = Datagram.new(row.fetch("pair_id"), Base64.strict_decode64(row.fetch("secret")),
                  role: role, bits: bits)
                peers[row["id"]] = Peer.new(row["id"], cipher, addresses, nil, 0.0, 0.0, {}, 0)
              end
            end
            @peers = peers
            @pairs = peers.values.to_h { |peer| [peer.cipher.id, peer] }
          end
          @valid_until = requested_at + [response.fetch("lease").to_f, STATE_TIMEOUT].min if @media
        end
      end

      def server_ready?
        !@owner.tcp_requested && monotonic - @last_ack < 6
      end

      def send(data)
        packets = Datagram.unpack(data)
        return false unless packets && !packets.empty?
        outgoing = @mutex.synchronize do
          next nil unless @media
          groups = packets.group_by { |packet| direct_targets(packet) }
          groups.filter_map do |ids, items|
            payload = Datagram.bundle(items)
            direct = []
            if payload.bytesize + 1 + @media.overhead <= packet_limit
              ids.each do |id|
                peer = @peers[id]
                if send_udp(peer.cipher.encode("D".b + payload), peer.selected)
                  direct << id
                else
                  peer.selected = nil
                end
              end
            end
            needed = items.any? { |item| server_packet?(item) || (targets(item) - direct).any? }
            next unless needed
            envelope = if direct.empty?
                         "D".b + payload
                       else
                         "F".b + [direct.length].pack("v") + direct.pack("v*") + payload
                       end
            @media.encode(envelope)
          end
        end
        return false unless outgoing
        outgoing.map { |packet| @owner.__send__(:send_relay_packet, packet) }.all?
      end

      def receive(data, address = nil)
        id = Datagram.id(data)
        return false unless id
        source = false
        packets = @mutex.synchronize do
          if id == @control.id
            next [] unless address == @server
            clear = @control.decode(data)
            next [] unless clear
            if clear.bytesize == 25 && clear.getbyte(0) == 67 &&
                @registration_nonce && clear.byteslice(1, 8) == @registration_nonce[0] &&
                monotonic - @registration_nonce[1] < 5
              send_udp(@control.encode("V".b + clear.byteslice(9, 16)), @server)
            elsif clear == "A".b
              @last_ack = monotonic
              source = :server
            end
            next []
          end
          if @media && id == @media.id
            next [] if address && address != @server
            clear = @media.decode(data)
            next [] unless clear && clear.getbyte(0) == 68
            source = :server
            next (Datagram.unpack(clear.byteslice(1..-1)) || []).select { |item| relay_allowed?(item) }
          end
          peer = @pairs[id]
          next [] unless peer && enabled?
          clear = peer.cipher.decode(data)
          next [] unless clear
          case clear.getbyte(0)
          when 80
            send_udp(peer.cipher.encode("Q".b + clear.byteslice(1, 8)), address) if clear.bytesize == 9 && address
          when 81
            pending = peer.nonces.delete(clear.byteslice(1, 8)) if clear.bytesize == 9
            if pending && pending[1] == address && monotonic - pending[0] <= PATH_TIMEOUT
              peer.selected = address
              peer.last_pong = monotonic
            end
          when 68
            items = Datagram.unpack(clear.byteslice(1..-1))
            next [] unless items && items.all? { |item| direct_allowed?(item, peer.id) }
            next items.reject { |item| muted?(item) }
          end
          []
        end
        packets.each { |packet| @owner.__send__(:receive, packet) }
        source
      end

      def tick
        @mutex.synchronize do
          now = monotonic
          unless @owner.tcp_requested
            if now >= @next_registration
              nonce = SecureRandom.random_bytes(8)
              @registration_nonce = [nonce, now]
              send_udp(@control.encode("R".b + nonce), @server)
              @next_registration = now + 2
            end
          end
          return unless enabled?
          @peers.each_value do |peer|
            next if now < peer.next_probe
            addresses = ready?(peer) ? [peer.selected] : peer.addresses.rotate(peer.cursor).first(2)
            peer.cursor = (peer.cursor + 2) % [peer.addresses.length, 1].max
            addresses.each do |endpoint|
              nonce = SecureRandom.random_bytes(8)
              peer.nonces[nonce] = [now, endpoint] if send_udp(peer.cipher.encode("P".b + nonce), endpoint)
            end
            peer.nonces.delete_if { |_nonce, value| now - value[0] > PATH_TIMEOUT }
            peer.next_probe = now + 0.75
          end
        end
      end

      def status
        @mutex.synchronize do
          {
            "channel_id" => @channel,
            "local_enabled" => allowed?,
            "recipients" => @peers.count { |_id, peer| ready?(peer) },
            "total_recipients" => @users.count { |id, _user| id != @owner.uid }
          }
        end
      end

      def reserve
        @mutex.synchronize { (@media ? @media.overhead : 44) + 3 + @peers.length * 2 }
      end

      private

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def allowed?
        @owner.p2p_allowed? && !@owner.tcp_requested
      end

      def enabled?
        @active && allowed? && monotonic < @valid_until
      end

      def ready?(peer)
        enabled? && peer && peer.selected && monotonic - peer.last_pong <= PATH_TIMEOUT
      end

      def packet_limit
        [($udpmaxpacketsize || 1400).to_i, 1400].min
      end

      def send_udp(packet, endpoint)
        return false unless endpoint
        @owner.__send__(:send_udp_packet, packet, endpoint)
      end

      def local_candidates
        return @candidates if @candidates && monotonic < @next_candidates
        port = @owner.__send__(:udp_port)
        @candidates = Socket.ip_address_list.filter_map do |address|
          next unless address.ipv4? && !address.ipv4_loopback?
          ip = IPAddr.new(address.ip_address)
          next if ip.to_i.zero? || IPAddr.new("224.0.0.0/3").include?(ip)
          [address.ip_address, port]
        end.uniq.first(8)
        @next_candidates = monotonic + 10
        @candidates
      rescue IOError, SystemCallError
        []
      end

      def sender(packet)
        packet.byteslice(0, 2).unpack1("v")
      end

      def destination(packet)
        packet.byteslice(8, 2).unpack1("v")
      end

      def current?(packet)
        stamp = packet.getbyte(2) | (packet.getbyte(3) << 8) | (packet.getbyte(4) << 16)
        @channel != 0 && stamp == @stamp
      end

      def permitted?(packet, id)
        return false unless current?(packet) && sender(packet) == id
        user = @users[id]
        return false unless user
        case packet.getbyte(7)
        when 1 then user["audio"] == true
        when 2, 31 then true
        when 3, 4 then @users.key?(destination(packet))
        when 21 then user["streams"].include?(destination(packet))
        else false
        end
      end

      def direct_allowed?(packet, id)
        return false unless permitted?(packet, id)
        return false if [3, 4].include?(packet.getbyte(7)) && destination(packet) != @owner.uid
        true
      end

      def relay_allowed?(packet)
        packet.getbyte(7) >= 200 || !muted?(packet)
      end

      def muted?(packet)
        user = @users[sender(packet)]
        return true unless user
        @owner.__send__(:packet_muted?, user["name"], packet.getbyte(7), destination(packet))
      end

      def targets(packet)
        return [destination(packet)] if [3, 4].include?(packet.getbyte(7))
        ids = @users.keys
        ids -= [@owner.uid] if sender(packet) == @owner.uid && muted?(packet)
        ids
      end

      def server_packet?(packet)
        !enabled? || !permitted?(packet, @owner.uid)
      end

      def direct_targets(packet)
        return [] if server_packet?(packet)
        targets(packet).select { |id| ready?(@peers[id]) }
      end
    end
  end
end
