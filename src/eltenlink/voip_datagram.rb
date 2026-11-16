require "openssl"
require "thread"

module EltenLink
  class VoIP
    class Datagram
      MAGIC = "EVP1".b
      attr_reader :id, :bits

      def initialize(id, secret, role:, bits: 256)
        raise ArgumentError, "Invalid UDP key" unless secret.bytesize == 32 && [0, 128, 192, 256].include?(bits)
        raise ArgumentError, "Invalid UDP ID" unless id.match?(/\A[0-9a-f]{32}\z/)
        @id, @bits, @raw_id = id, bits, [id].pack("H*")
        outgoing, incoming = role == :client ? %w[client server] : %w[server client]
        @write_key = derive(secret, outgoing)
        @read_key = derive(secret, incoming)
        @write_mutex, @read_mutex = Mutex.new, Mutex.new
        @serial = @highest = @seen = 0
      end

      def overhead
        @bits.zero? ? 28 : 44
      end

      def self.id(packet)
        return nil unless packet.is_a?(String) && packet.bytesize >= 28 && packet.byteslice(0, 4) == MAGIC
        packet.byteslice(4, 16).unpack1("H*")
      end

      def encode(data)
        @write_mutex.synchronize do
          @serial += 1
          raise IOError, "UDP sequence exhausted" if @serial > 0xffffffffffffffff
          header = MAGIC + @raw_id + [@serial].pack("Q>")
          return header + data if @bits.zero?
          cipher = OpenSSL::Cipher.new("aes-#{@bits}-gcm")
          cipher.encrypt
          cipher.key = @write_key
          cipher.iv = [0, @serial].pack("NQ>")
          cipher.auth_data = header
          encrypted = (data.empty? ? "".b : cipher.update(data)) + cipher.final
          header + cipher.auth_tag + encrypted
        end
      end

      def decode(data)
        return nil unless self.class.id(data) == @id && data.bytesize >= overhead && data.bytesize <= 65536
        serial = data.byteslice(20, 8).unpack1("Q>")
        return nil if serial.zero?
        @read_mutex.synchronize do
          offset = @highest - serial
          return nil if offset >= 1024 || (offset >= 0 && (@seen & (1 << offset)) != 0)
          if @bits.zero?
            clear = data.byteslice(28..-1)
          else
            cipher = OpenSSL::Cipher.new("aes-#{@bits}-gcm")
            cipher.decrypt
            cipher.key = @read_key
            cipher.iv = [0, serial].pack("NQ>")
            cipher.auth_tag = data.byteslice(28, 16)
            cipher.auth_data = data.byteslice(0, 28)
            encrypted = data.byteslice(44..-1)
            clear = (encrypted.empty? ? "".b : cipher.update(encrypted)) + cipher.final
          end
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

      def self.unpack(data, depth = 0)
        return nil unless data.is_a?(String) && data.bytesize.between?(16, 32768)
        return data.bytesize <= 8192 ? [data] : nil unless data.getbyte(7) == 255
        return nil if depth >= 2
        packets, offset = [], 16
        while offset < data.bytesize
          return nil if offset + 4 > data.bytesize
          size = data.byteslice(offset, 4).unpack1("L<")
          offset += 4
          return nil if size < 16 || offset + size > data.bytesize
          inner = unpack(data.byteslice(offset, size), depth + 1)
          return nil unless inner
          packets.concat(inner)
          return nil if packets.length > 32
          offset += size
        end
        packets
      end

      def self.bundle(packets)
        return packets.first if packets.length == 1
        header = packets.first.byteslice(0, 16).dup
        header.setbyte(7, 255)
        header + packets.map { |packet| [packet.bytesize].pack("L<") + packet }.join
      end

      private

      def derive(secret, direction)
        OpenSSL::HMAC.digest("SHA256", secret, "elten-voip-udp-v1-#{@bits}-#{direction}").byteslice(0, @bits / 8)
      end
    end
  end
end
