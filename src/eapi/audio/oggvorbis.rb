# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.

require "fiddle"

module OggVorbis
  extend self

  STRUCT_SIZE = 8192
  BUFFER_SIZE = 4096
  POINTER_SIZE = Fiddle::SIZEOF_VOIDP
  POINTER_PACK = POINTER_SIZE == 8 ? "Q" : "L!"

  def decode_to_wave(data)
    pcm, frequency, channels = decode(data, float: true)
    return nil if pcm == nil || pcm.bytesize == 0
    wave_header(pcm.bytesize, frequency, channels, 32, 3) + pcm
  rescue Exception => e
    Log.warning("Ogg Vorbis decode failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def load!
    return if @loaded == true
    require "fiddle"
    EltenRuntimePaths.configure_dll_search! if defined?(EltenRuntimePaths)
    @ogg = EltenRuntimePaths.dlopen("ogg")
    @vorbis = EltenRuntimePaths.dlopen("libvorbis")

    @ogg_sync_init = fn(@ogg, "ogg_sync_init", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @ogg_sync_clear = fn(@ogg, "ogg_sync_clear", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @ogg_sync_buffer = fn(@ogg, "ogg_sync_buffer", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP)
    @ogg_sync_wrote = fn(@ogg, "ogg_sync_wrote", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
    @ogg_sync_pageout = fn(@ogg, "ogg_sync_pageout", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @ogg_page_serialno = fn(@ogg, "ogg_page_serialno", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @ogg_stream_init = fn(@ogg, "ogg_stream_init", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
    @ogg_stream_clear = fn(@ogg, "ogg_stream_clear", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @ogg_stream_pagein = fn(@ogg, "ogg_stream_pagein", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @ogg_stream_packetout = fn(@ogg, "ogg_stream_packetout", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

    @vorbis_info_init = fn(@vorbis, "vorbis_info_init", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @vorbis_info_clear = fn(@vorbis, "vorbis_info_clear", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @vorbis_comment_init = fn(@vorbis, "vorbis_comment_init", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @vorbis_comment_clear = fn(@vorbis, "vorbis_comment_clear", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @vorbis_synthesis_headerin = fn(@vorbis, "vorbis_synthesis_headerin", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_synthesis_init = fn(@vorbis, "vorbis_synthesis_init", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_synthesis_restart = fn(@vorbis, "vorbis_synthesis_restart", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_block_init = fn(@vorbis, "vorbis_block_init", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_block_clear = fn(@vorbis, "vorbis_block_clear", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_dsp_clear = fn(@vorbis, "vorbis_dsp_clear", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @vorbis_synthesis = fn(@vorbis, "vorbis_synthesis", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_synthesis_blockin = fn(@vorbis, "vorbis_synthesis_blockin", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_synthesis_pcmout = fn(@vorbis, "vorbis_synthesis_pcmout", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @vorbis_synthesis_read = fn(@vorbis, "vorbis_synthesis_read", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)

    @loaded = true
  end

  def fn(handle, name, args, ret)
    Fiddle::Function.new(handle[name], args, ret)
  end

  def struct_buffer
    p = Fiddle::Pointer.malloc(STRUCT_SIZE)
    p[0, STRUCT_SIZE] = "\0".b * STRUCT_SIZE
    p
  end

  def pointer_buffer
    p = Fiddle::Pointer.malloc(POINTER_SIZE)
    p[0, POINTER_SIZE] = "\0".b * POINTER_SIZE
    p
  end

  def pointer_value(buffer, offset = 0)
    buffer[offset, POINTER_SIZE].unpack1(POINTER_PACK).to_i
  end

  def decode(data, float: false)
    load!
    data = data.to_s.b
    raise ArgumentError, "not an Ogg stream" if data.byteslice(0, 4) != "OggS"

    oy = struct_buffer
    os = struct_buffer
    og = struct_buffer
    op = struct_buffer
    vi = struct_buffer
    vc = struct_buffer
    vd = struct_buffer
    vb = struct_buffer
    pcm_ptr = pointer_buffer

    stream_initialized = false
    vorbis_initialized = false
    block_initialized = false
    headers = 0
    offset = 0
    output = "".b
    pcm_writer = nil
    channels = 0
    frequency = 0

    raise "ogg_sync_init failed" if @ogg_sync_init.call(oy) != 0
    @vorbis_info_init.call(vi)
    @vorbis_comment_init.call(vc)

    feed = lambda do
      if offset >= data.bytesize
        false
      else
        chunk = data.byteslice(offset, BUFFER_SIZE)
        offset += chunk.bytesize
        native = @ogg_sync_buffer.call(oy, chunk.bytesize)
        raise "ogg_sync_buffer failed" if native.to_i == 0
        Fiddle::Pointer.new(native)[0, chunk.bytesize] = chunk
        raise "ogg_sync_wrote failed" if @ogg_sync_wrote.call(oy, chunk.bytesize) != 0
        true
      end
    end

    feed.call
    loop do
      result = @ogg_sync_pageout.call(oy, og)
      if result == 0
        break unless feed.call
        next
      elsif result < 0
        next
      end

      unless stream_initialized
        serial = @ogg_page_serialno.call(og)
        raise "ogg_stream_init failed" if @ogg_stream_init.call(os, serial) != 0
        stream_initialized = true
      end

      raise "ogg_stream_pagein failed" if @ogg_stream_pagein.call(os, og) != 0

      loop do
        packet_result = @ogg_stream_packetout.call(os, op)
        break if packet_result == 0
        next if packet_result < 0

        if headers < 3
          raise "vorbis_synthesis_headerin failed" if @vorbis_synthesis_headerin.call(vi, vc, op) != 0
          headers += 1
          if headers == 3
            channels = vi[4, 4].unpack1("l<").to_i
            frequency = vi[8, 4].unpack1("l<").to_i
            raise "invalid Vorbis format" if channels <= 0 || frequency <= 0
            pcm_writer = FloatPcmWriter.new([channels, 2].min) if float
            raise "vorbis_synthesis_init failed" if @vorbis_synthesis_init.call(vd, vi) != 0
            @vorbis_synthesis_restart.call(vd)
            raise "vorbis_block_init failed" if @vorbis_block_init.call(vd, vb) != 0
            vorbis_initialized = true
            block_initialized = true
          end
          next
        end

        next if !vorbis_initialized
        if @vorbis_synthesis.call(vb, op) == 0
          @vorbis_synthesis_blockin.call(vd, vb)
        end

        loop do
          samples = @vorbis_synthesis_pcmout.call(vd, pcm_ptr)
          break if samples <= 0
          if pcm_writer != nil
            pcm_writer.write(pcm_ptr, samples)
          else
            output << interleaved_pcm(pcm_ptr, channels, samples, float)
          end
          @vorbis_synthesis_read.call(vd, samples)
        end
      end
    end

    raise "Vorbis headers not found" if headers < 3
    output = pcm_writer.finish if pcm_writer != nil
    [output, frequency, [channels, 2].min]
  ensure
    @vorbis_block_clear.call(vb) if block_initialized rescue nil
    @vorbis_dsp_clear.call(vd) if vorbis_initialized rescue nil
    @vorbis_comment_clear.call(vc) if vc != nil rescue nil
    @vorbis_info_clear.call(vi) if vi != nil rescue nil
    @ogg_stream_clear.call(os) if stream_initialized rescue nil
    @ogg_sync_clear.call(oy) if oy != nil rescue nil
  end

  def interleaved_pcm(pcm_ptr, channels, samples, float = false)
    pcm_address = pointer_value(pcm_ptr)
    raise "null Vorbis PCM pointer" if pcm_address == 0
    out_channels = [channels, 2].min
    channel_pointers = []
    out_channels.times do |channel|
      channel_address = Fiddle::Pointer.new(pcm_address + channel * POINTER_SIZE)[0, POINTER_SIZE].unpack1(POINTER_PACK).to_i
      raise "null Vorbis channel pointer" if channel_address == 0
      channel_pointers << Fiddle::Pointer.new(channel_address)
    end

    if float
      return channel_pointers[0].to_s(samples * 4).b if out_channels == 1

      left = channel_pointers[0].to_s(samples * 4).unpack("e*")
      right = channel_pointers[1].to_s(samples * 4).unpack("e*")
      interleaved = Array.new(samples * 2)
      i = 0
      j = 0
      while i < samples
        interleaved[j] = left[i]
        interleaved[j + 1] = right[i]
        i += 1
        j += 2
      end
      return interleaved.pack("e*")
    end

    channel_data = channel_pointers.map { |pointer| pointer.to_s(samples * 4).unpack("e*") }
    interleaved = Array.new(samples * out_channels)
    i = 0
    j = 0
    while i < samples
      out_channels.times do |channel|
        sample = channel_data[channel][i].to_f
        sample = -1.0 if sample < -1.0
        sample = 1.0 if sample > 1.0
        interleaved[j] = (sample * 32767.0).round
        j += 1
      end
      i += 1
    end
    interleaved.pack("s<*")
  end

  class FloatPcmWriter
    FLUSH_SAMPLES = 16_384

    def initialize(channels)
      @channels = channels
      @output = "".b
      @left = "".b
      @right = "".b
      @pending_samples = 0
    end

    def write(pcm_ptr, samples)
      pcm_address = OggVorbis.__send__(:pointer_value, pcm_ptr)
      raise "null Vorbis PCM pointer" if pcm_address == 0

      left_address = Fiddle::Pointer.new(pcm_address)[0, POINTER_SIZE].unpack1(POINTER_PACK).to_i
      raise "null Vorbis channel pointer" if left_address == 0
      left = Fiddle::Pointer.new(left_address).to_s(samples * 4).b

      if @channels == 1
        @output << left
        return
      end

      right_address = Fiddle::Pointer.new(pcm_address + POINTER_SIZE)[0, POINTER_SIZE].unpack1(POINTER_PACK).to_i
      raise "null Vorbis channel pointer" if right_address == 0

      @left << left
      @right << Fiddle::Pointer.new(right_address).to_s(samples * 4).b
      @pending_samples += samples
      flush if @pending_samples >= FLUSH_SAMPLES
    end

    def finish
      flush
      @output
    end

    private

    def flush
      return if @pending_samples <= 0

      left = @left.unpack("e*")
      right = @right.unpack("e*")
      interleaved = Array.new(@pending_samples * 2)
      i = 0
      j = 0
      while i < @pending_samples
        interleaved[j] = left[i]
        interleaved[j + 1] = right[i]
        i += 1
        j += 2
      end
      @output << interleaved.pack("e*")
      @left.clear
      @right.clear
      @pending_samples = 0
    end
  end

  def wave_header(data_size, frequency, channels, bits = 16, format = 1)
    bytes_per_sample = bits / 8
    byte_rate = frequency * channels * bytes_per_sample
    block_align = channels * bytes_per_sample
    "RIFF".b +
      [36 + data_size].pack("V") +
      "WAVEfmt ".b +
      [16].pack("V") +
      [format, channels, frequency, byte_rate, block_align, bits].pack("vvVVvv") +
      "data".b +
      [data_size].pack("V")
  end
end
