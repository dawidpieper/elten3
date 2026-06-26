module EltenNativeStructs
  POINTER_SIZE = [nil].pack("p").size
  POINTER_PACK = POINTER_SIZE == 8 ? "Q" : "L"
  SIGNED_POINTER_PACK = POINTER_SIZE == 8 ? "q" : "l"

  class << self
    def pointer_buffer(value = 0)
      return [value].pack("p") if value.is_a?(String)
      [value.to_i].pack(POINTER_PACK)
    end

    def pointer_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer[offset, POINTER_SIZE] || ""
      chunk += "\0" * (POINTER_SIZE - chunk.size)
      chunk.unpack(POINTER_PACK).first
    end

    def pointer_bytes(pointer, bytes)
      bytes = bytes.to_i
      return "".b if bytes <= 0
      pointer = pointer.to_i
      raise RangeError, "null native pointer with #{bytes} bytes requested" if pointer == 0
      require "fiddle"
      Fiddle::Pointer.new(pointer).to_s(bytes).b
    end

    def pointer_array(count)
      ([nil] * count.to_i).pack("p" * count.to_i)
    end

    def pointer_array_values(buffer, count)
      values = []
      (0...count.to_i).each do |i|
        values.push(pointer_value(buffer, i * POINTER_SIZE))
      end
      values
    end

    def dword_buffer(value = 0)
      [value.to_i].pack("L")
    end

    def dword_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer[offset, 4] || ""
      chunk += "\0" * (4 - chunk.size)
      chunk.unpack("L").first
    end

    def set_dword(buffer, offset, value)
      buffer[offset, 4] = dword_buffer(value)
    end

    def set_word(buffer, offset, value)
      buffer[offset, 2] = [value.to_i].pack("S")
    end

    def set_pointer(buffer, offset, value)
      buffer[offset, POINTER_SIZE] = pointer_buffer(value || 0)
    end

    def bass_device_info_buffer
      "\0" * (POINTER_SIZE == 8 ? 24 : 12)
    end

    def bass_device_info_values(buffer)
      [pointer_value(buffer, 0), pointer_value(buffer, POINTER_SIZE), dword_value(buffer, POINTER_SIZE * 2)]
    end

    def bass_channel_info_buffer
      "\0" * (POINTER_SIZE == 8 ? 40 : 32)
    end

    def bass_channel_info_values(buffer)
      filename_offset = POINTER_SIZE == 8 ? 32 : 28
      values = []
      (0...7).each do |i|
        values.push(dword_value(buffer, i * 4))
      end
      values.push(pointer_value(buffer, filename_offset))
      values
    end
  end
end
