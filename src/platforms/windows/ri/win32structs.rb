module EltenWin32
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

    def security_attributes(inherit_handle = true, descriptor = nil)
      if POINTER_SIZE == 8
        buffer = "\0" * 24
        set_dword(buffer, 0, 24)
        set_pointer(buffer, 8, descriptor || 0)
        set_dword(buffer, 16, inherit_handle ? 1 : 0)
      else
        buffer = "\0" * 12
        set_dword(buffer, 0, 12)
        set_pointer(buffer, 4, descriptor || 0)
        set_dword(buffer, 8, inherit_handle ? 1 : 0)
      end
      buffer
    end

    def startup_info(show_window = nil, stdin = 0, stdout = 0, stderr = 0, use_std_handles = false)
      if POINTER_SIZE == 8
        buffer = "\0" * 104
        flags_offset = 60
        show_window_offset = 64
        stdin_offset = 80
        stdout_offset = 88
        stderr_offset = 96
      else
        buffer = "\0" * 68
        flags_offset = 44
        show_window_offset = 48
        stdin_offset = 56
        stdout_offset = 60
        stderr_offset = 64
      end

      flags = 0
      flags |= 1 if show_window != nil
      flags |= 0x100 if use_std_handles

      set_dword(buffer, 0, buffer.size)
      set_dword(buffer, flags_offset, flags)
      set_word(buffer, show_window_offset, show_window || 0)
      set_pointer(buffer, stdin_offset, stdin)
      set_pointer(buffer, stdout_offset, stdout)
      set_pointer(buffer, stderr_offset, stderr)
      buffer
    end

    def process_information_buffer
      "\0" * (POINTER_SIZE == 8 ? 24 : 16)
    end

    def process_information(buffer)
      {
        :process_handle => pointer_value(buffer, 0),
        :thread_handle => pointer_value(buffer, POINTER_SIZE),
        :process_id => dword_value(buffer, POINTER_SIZE * 2),
        :thread_id => dword_value(buffer, POINTER_SIZE * 2 + 4)
      }
    end

    def data_blob(data = nil)
      data ||= ""
      if POINTER_SIZE == 8
        dword_buffer(data.bytesize) + ("\0" * 4) + [data].pack("p")
      else
        [data.bytesize, data].pack("Lp")
      end
    end

    def data_blob_values(buffer)
      pointer_offset = POINTER_SIZE == 8 ? 8 : 4
      [dword_value(buffer, 0), pointer_value(buffer, pointer_offset)]
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

    def spellcheck_result_buffer(count)
      "\0" * (count.to_i * (POINTER_SIZE == 8 ? 24 : 16))
    end

    def spellcheck_result_values(buffer, index)
      size = POINTER_SIZE == 8 ? 24 : 16
      base = index.to_i * size
      pointer_offset = POINTER_SIZE == 8 ? 16 : 12
      [
        dword_value(buffer, base),
        dword_value(buffer, base + 4),
        dword_value(buffer, base + 8),
        pointer_value(buffer, base + pointer_offset)
      ]
    end

  end
end
