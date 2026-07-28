# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class OggNative
  class << self
    def load!
      require "fiddle"
      require_relative "../../conferencenative" unless defined?(::ELTEN_SIZE_T)
      return if @loaded
      ogg = EltenRuntimePaths.dlopen("ogg")
      @stream_init = Fiddle::Function.new(ogg["ogg_stream_init"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      @stream_packetin = Fiddle::Function.new(ogg["ogg_stream_packetin"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @stream_pageout = Fiddle::Function.new(ogg["ogg_stream_pageout"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @stream_flush = Fiddle::Function.new(ogg["ogg_stream_flush"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @stream_clear = Fiddle::Function.new(ogg["ogg_stream_clear"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @loaded = true
    end

    attr_reader :stream_init, :stream_packetin, :stream_pageout, :stream_flush, :stream_clear

    def stream_state_buffer
      "\0" * 512
    end

    def page_buffer
      "\0" * page_size
    end

    def page_values(buffer)
      layout = page_layout
      [
        EltenRecorderStructs.pointer_value(buffer, layout[:header]),
        EltenRecorderStructs.long_value(buffer, layout[:header_len]),
        EltenRecorderStructs.pointer_value(buffer, layout[:body]),
        EltenRecorderStructs.long_value(buffer, layout[:body_len])
      ]
    end

    def page_size
      page_layout[:size]
    end

    def packet_size
      packet_layout[:size]
    end

    def packet_data_pointer(data)
      require "fiddle"
      data = data.to_s.b
      pointer = Fiddle::Pointer.malloc([data.bytesize, 1].max)
      pointer[0, data.bytesize] = data if data.bytesize > 0
      pointer
    end

    def packet(packet_data, bytes, b_o_s, e_o_s, granulepos, packetno)
      packet_pointer = packet_data.to_i
      raise RangeError, "null OGG packet data pointer with #{bytes} bytes" if packet_pointer == 0 && bytes.to_i > 0
      layout = packet_layout
      buffer = "\0" * layout[:size]
      EltenRecorderStructs.set_pointer(buffer, layout[:packet], packet_pointer)
      EltenRecorderStructs.set_long(buffer, layout[:bytes], bytes)
      EltenRecorderStructs.set_long(buffer, layout[:b_o_s], b_o_s)
      EltenRecorderStructs.set_long(buffer, layout[:e_o_s], e_o_s)
      buffer[layout[:granulepos], 8] = [granulepos.to_i].pack("q")
      buffer[layout[:packetno], 8] = [packetno.to_i].pack("q")
      buffer
    end

    def packet_set_eos(buffer, e_o_s)
      EltenRecorderStructs.set_long(buffer, packet_layout[:e_o_s], e_o_s)
    end

    def page_part(pointer, bytes, max_bytes)
      bytes = bytes.to_i
      raise RangeError, "invalid OGG page part length #{bytes}" if bytes < 0 || bytes > max_bytes
      EltenRecorderStructs.pointer_bytes(pointer, bytes)
    end

    private

    def align_offset(offset, alignment)
      alignment = alignment.to_i
      return offset if alignment <= 1
      ((offset + alignment - 1) / alignment) * alignment
    end

    def page_layout
      @page_layout ||= begin
        header = 0
        header_len = header + EltenRecorderStructs::POINTER_SIZE
        body = align_offset(header_len + EltenRecorderStructs::LONG_SIZE, EltenRecorderStructs::POINTER_SIZE)
        body_len = body + EltenRecorderStructs::POINTER_SIZE
        size = align_offset(body_len + EltenRecorderStructs::LONG_SIZE, [EltenRecorderStructs::POINTER_SIZE, EltenRecorderStructs::LONG_SIZE].max)
        { :header => header, :header_len => header_len, :body => body, :body_len => body_len, :size => size }
      end
    end

    def packet_layout
      @packet_layout ||= begin
        packet = 0
        bytes = packet + EltenRecorderStructs::POINTER_SIZE
        b_o_s = bytes + EltenRecorderStructs::LONG_SIZE
        e_o_s = b_o_s + EltenRecorderStructs::LONG_SIZE
        granulepos = align_offset(e_o_s + EltenRecorderStructs::LONG_SIZE, 8)
        packetno = granulepos + 8
        size = align_offset(packetno + 8, [EltenRecorderStructs::POINTER_SIZE, EltenRecorderStructs::LONG_SIZE, 8].max)
        { :packet => packet, :bytes => bytes, :b_o_s => b_o_s, :e_o_s => e_o_s, :granulepos => granulepos, :packetno => packetno, :size => size }
      end
    end
  end
end

class OggStreamWriter
  def initialize(output)
    OggNative.load!
    @output = output
    @ogg = OggNative.stream_state_buffer
    OggNative.stream_init.call(@ogg, rand(2**32) - 2**31)
  end

  def packetin(packet)
    OggNative.stream_packetin.call(@ogg, packet)
  end

  def write_pages(flush = false)
    page = OggNative.page_buffer
    function = flush ? OggNative.stream_flush : OggNative.stream_pageout
    while function.call(@ogg, page) != 0
      values = OggNative.page_values(page)
      @output.write(OggNative.page_part(values[0], values[1], 282))
      @output.write(OggNative.page_part(values[2], values[3], 65_025))
    end
  end

  def close
    return if @ogg == nil
    write_pages(true)
    OggNative.stream_clear.call(@ogg)
    @ogg = nil
  end
end
