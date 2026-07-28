# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module VorbisNative
  STRUCT_SIZE = 8192
  PACKET_SIZE = OggNative.packet_size

  class << self
    def load!
      return if @loaded
      require "fiddle"
      require_relative "../../conferencenative" unless defined?(::ELTEN_INTPTR)
      OggNative.load!
      @vorbis = EltenRuntimePaths.dlopen("libvorbis")
      cstring = defined?(Fiddle::TYPE_CONST_STRING) ? Fiddle::TYPE_CONST_STRING : Fiddle::TYPE_VOIDP
      @info_init = Fiddle::Function.new(@vorbis["vorbis_info_init"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @info_clear = Fiddle::Function.new(@vorbis["vorbis_info_clear"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @comment_init = Fiddle::Function.new(@vorbis["vorbis_comment_init"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @comment_add_tag = Fiddle::Function.new(@vorbis["vorbis_comment_add_tag"], [Fiddle::TYPE_VOIDP, cstring, cstring], Fiddle::TYPE_INT)
      @comment_clear = Fiddle::Function.new(@vorbis["vorbis_comment_clear"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @encode_init = Fiddle::Function.new(@vorbis["vorbis_encode_init"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG], Fiddle::TYPE_INT)
      @encode_init_vbr = Fiddle::Function.new(@vorbis["vorbis_encode_init_vbr"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_FLOAT], Fiddle::TYPE_INT) rescue nil
      @analysis_init = Fiddle::Function.new(@vorbis["vorbis_analysis_init"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @analysis_headerout = Fiddle::Function.new(@vorbis["vorbis_analysis_headerout"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @analysis_buffer = Fiddle::Function.new(@vorbis["vorbis_analysis_buffer"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], ELTEN_INTPTR)
      @analysis_wrote = Fiddle::Function.new(@vorbis["vorbis_analysis_wrote"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      @analysis_blockout = Fiddle::Function.new(@vorbis["vorbis_analysis_blockout"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @analysis = Fiddle::Function.new(@vorbis["vorbis_analysis"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @bitrate_addblock = Fiddle::Function.new(@vorbis["vorbis_bitrate_addblock"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @bitrate_flushpacket = Fiddle::Function.new(@vorbis["vorbis_bitrate_flushpacket"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @block_init = Fiddle::Function.new(@vorbis["vorbis_block_init"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @block_clear = Fiddle::Function.new(@vorbis["vorbis_block_clear"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @dsp_clear = Fiddle::Function.new(@vorbis["vorbis_dsp_clear"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @loaded = true
    end

    def struct_buffer(size = STRUCT_SIZE)
      pointer = Fiddle::Pointer.malloc(size)
      pointer[0, size] = "\0" * size
      pointer
    end

    def packet_buffer
      struct_buffer(PACKET_SIZE)
    end

    attr_reader :info_init, :info_clear, :comment_init, :comment_add_tag, :comment_clear, :encode_init, :encode_init_vbr,
      :analysis_init, :analysis_headerout, :analysis_buffer, :analysis_wrote, :analysis_blockout,
      :analysis, :bitrate_addblock, :bitrate_flushpacket, :block_init, :block_clear, :dsp_clear
  end
end

class VorbisAudioEncoder < AudioEncoder
  def initialize(bitrate = 64, tags: nil)
    @bitrate = bitrate.to_i * 1000
    @tags = tags
  end

  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    super(output, :frequency => frequency, :channels => [[channels.to_i, 1].max, 2].min, :source_channel => source_channel)
    @queue = "".b
    @sample_bytes = @channels * 2
    @chunk_frames = 4096
    @chunk_bytes = @chunk_frames * @sample_bytes
    VorbisNative.load!
    @vi = VorbisNative.struct_buffer
    @vc = VorbisNative.struct_buffer
    @vd = VorbisNative.struct_buffer
    @vb = VorbisNative.struct_buffer
    @packet = VorbisNative.packet_buffer
    @header = VorbisNative.packet_buffer
    @header_comment = VorbisNative.packet_buffer
    @header_code = VorbisNative.packet_buffer
    @ogg = OggStreamWriter.new(output)
    begin
      VorbisNative.info_init.call(@vi)
      @info_initialized = true
      managed_err = VorbisNative.encode_init.call(@vi, @channels, @frequency, -1, @bitrate, -1)
      err = managed_err
      vbr_quality = nil
      if err != 0 && VorbisNative.encode_init_vbr != nil
        VorbisNative.info_clear.call(@vi)
        VorbisNative.info_init.call(@vi)
        vbr_quality = [[@bitrate.to_f / 320000.0, 0.0].max, 1.0].min
        err = VorbisNative.encode_init_vbr.call(@vi, @channels, @frequency, vbr_quality)
      end
      if err != 0
        raise RuntimeError, "Vorbis encoder init failed: #{err} (managed=#{managed_err}, frequency=#{@frequency}, channels=#{@channels}, bitrate=#{@bitrate}, vbr_quality=#{vbr_quality || "n/a"})"
      end
      VorbisNative.comment_init.call(@vc)
      @comment_initialized = true
      add_comments(@tags)
      raise RuntimeError, "Vorbis analysis init failed" if VorbisNative.analysis_init.call(@vd, @vi) != 0
      @dsp_initialized = true
      raise RuntimeError, "Vorbis block init failed" if VorbisNative.block_init.call(@vd, @vb) != 0
      @block_initialized = true
      raise RuntimeError, "Vorbis header init failed" if VorbisNative.analysis_headerout.call(@vd, @vc, @header, @header_comment, @header_code) != 0
      @ogg.packetin(@header)
      @ogg.packetin(@header_comment)
      @ogg.packetin(@header_code)
      @ogg.write_pages(true)
      self
    rescue Exception
      close
      raise
    end
  end

  def feed(data)
    return 0 if data == nil || data.bytesize <= 0
    @queue << data.to_s.b
    processed = 0
    while @queue.bytesize >= @chunk_bytes
      chunk = @queue.byteslice(0, @chunk_bytes)
      @queue = @queue.byteslice(@chunk_bytes..-1) || "".b
      process_chunk(chunk)
      processed += chunk.bytesize
    end
    processed
  end

  def finish
    frames = @queue.bytesize / @sample_bytes
    process_chunk(@queue.byteslice(0, frames * @sample_bytes)) if frames > 0
    @queue = "".b
    VorbisNative.analysis_wrote.call(@vd, 0) if @vd != nil
    drain_packets
    close
  end

  def close
    return if @closed
    @closed = true
    @ogg.close if @ogg != nil
    @ogg = nil
    VorbisNative.block_clear.call(@vb) if @vb != nil && @block_initialized
    VorbisNative.dsp_clear.call(@vd) if @vd != nil && @dsp_initialized
    VorbisNative.comment_clear.call(@vc) if @vc != nil && @comment_initialized
    VorbisNative.info_clear.call(@vi) if @vi != nil && @info_initialized
    @vb = @vd = @vc = @vi = nil
  end

  def normalize_source?
    true
  end

  def source_frequency
    48000
  end

  def source_channels(channel)
    EltenRecorderRuntime.source_limited_channels(channel)
  end

  private

  def add_comments(tags)
    comments = tags || {}
    comments.each do |key, value|
      next if key == nil || value == nil
      VorbisNative.comment_add_tag.call(@vc, key.to_s.encode("UTF-8", invalid: :replace, undef: :replace), value.to_s.encode("UTF-8", invalid: :replace, undef: :replace))
    end
    VorbisNative.comment_add_tag.call(@vc, "ENCODER", "ELTEN") if comments.keys.map { |key| key.to_s.upcase }.include?("ENCODER") == false
  end

  def process_chunk(pcm)
    frames = pcm.bytesize / @sample_bytes
    return if frames <= 0
    buffer = VorbisNative.analysis_buffer.call(@vd, frames)
    pointer_table = Fiddle::Pointer.new(buffer.to_i)[0, @channels * EltenRecorderStructs::POINTER_SIZE]
    samples = pcm.unpack("s<*")
    for channel in 0...@channels
      pointer = Fiddle::Pointer.new(EltenRecorderStructs.pointer_value(pointer_table, channel * EltenRecorderStructs::POINTER_SIZE))
      values = Array.new(frames)
      index = channel
      for frame in 0...frames
        values[frame] = samples[index].to_f / 32768.0
        index += @channels
      end
      pointer[0, frames * 4] = values.pack("f*")
    end
    VorbisNative.analysis_wrote.call(@vd, frames)
    drain_packets
  end

  def drain_packets
    while VorbisNative.analysis_blockout.call(@vd, @vb) == 1
      VorbisNative.analysis.call(@vb, 0)
      VorbisNative.bitrate_addblock.call(@vb)
      while VorbisNative.bitrate_flushpacket.call(@vd, @packet) != 0
        @ogg.packetin(@packet)
        @ogg.write_pages(false)
      end
    end
  end
end
