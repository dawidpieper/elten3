# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenRecorderStructs
  POINTER_SIZE = [nil].pack("p").bytesize
  POINTER_PACK = POINTER_SIZE == 8 ? "Q" : "L"
  LONG_SIZE = [0].pack("l!").bytesize

  class << self
    def pointer_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer.to_s.b.byteslice(offset, POINTER_SIZE) || "".b
      chunk += "\0" * (POINTER_SIZE - chunk.bytesize)
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

    def dword_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer.to_s.b.byteslice(offset, 4) || "".b
      chunk += "\0" * (4 - chunk.bytesize)
      chunk.unpack("L").first
    end

    def long_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer.to_s.b.byteslice(offset, LONG_SIZE) || "".b
      chunk += "\0" * (LONG_SIZE - chunk.bytesize)
      chunk.unpack("l!").first
    end

    def set_dword(buffer, offset, value)
      buffer[offset, 4] = [value.to_i].pack("L")
    end

    def set_long(buffer, offset, value)
      buffer[offset, LONG_SIZE] = [value.to_i].pack("l!")
    end

    def set_pointer(buffer, offset, value)
      buffer[offset, POINTER_SIZE] = [value.to_i].pack(POINTER_PACK)
    end

    def bass_channel_info_buffer
      ("\0" * (POINTER_SIZE == 8 ? 40 : 32)).b
    end

    def bass_channel_info_values(buffer)
      filename_offset = POINTER_SIZE == 8 ? 32 : 28
      values = []
      for i in 0...7
        values.push(dword_value(buffer, i * 4))
      end
      values.push(pointer_value(buffer, filename_offset))
      values
    end
  end
end

module EltenRecorderRuntime
  class InputRecording
    def initialize(session_factory, read_buffer_bytes = 384000, record_flags = 0)
      session = nil
      begin
        @paused = false
        @stopping = false
        @mutex = Mutex.new
        @pending_pcm = "".b
        @read_buffer_bytes = [read_buffer_bytes.to_i, 4096].max
        Bass.record_prepare
        @channel = Bass::BASS_RecordStart.call(48000, 2, record_flags.to_i, 0, 0)
        raise RuntimeError, "Cannot start recording: BASS error #{Bass::BASS_ErrorGetCode.call}" if @channel == 0
        notify_recording(true)
        @thread = Thread.new { reader_thread }
        session = session_factory.call
        @mutex.synchronize do
          @session = session
          session = nil
          flush_pending_locked
        end
      rescue Exception
        @stopping = true
        Bass::BASS_ChannelStop.call(@channel) if @channel != nil && @channel != 0
        @thread.join(1) if @thread != nil
        session.close if session != nil
        @session.close if @session != nil
        notify_recording(false)
        raise
      end
    end

    def stop
      return if @stopping
      notify_recording(false)
      @stopping = true
      Bass::BASS_ChannelStop.call(@channel) if @channel != nil && @channel != 0
      @thread.join(1) if @thread != nil
      @mutex.synchronize do
        flush_pending_locked
        @session.finish if @session != nil
      end
      @session = nil
    end

    def pause
      notify_recording(false)
      @paused = true
      Bass::BASS_ChannelPause.call(@channel) if @channel != nil && @channel != 0
    end

    def resume
      notify_recording(true)
      @paused = false
      Bass::BASS_ChannelPlay.call(@channel, 0) if @channel != nil && @channel != 0
    end

    def paused
      @paused == true
    end

    private

    def reader_thread
      buffer = "\0" * @read_buffer_bytes
      until @stopping
        if @paused
          sleep(0.02)
          next
        end
        size = Bass::BASS_ChannelGetData.call(@channel, buffer, buffer.bytesize)
        if size != nil && size > 0
          data = buffer.byteslice(0, size)
          @mutex.synchronize do
            if @session != nil && !@stopping
              flush_pending_locked
              @session.process_pcm(data)
            else
              @pending_pcm << data
            end
          end
        else
          sleep(0.01)
        end
      end
    rescue Exception
      Log.error("Recorder reader error: #{$!.class}: #{$!.message} #{$@}")
    end

    def notify_recording(recording)
      $recording = recording == true
    rescue Exception
    end

    def flush_pending_locked
      return if @session == nil || @pending_pcm == nil || @pending_pcm.bytesize == 0
      data = @pending_pcm
      @pending_pcm = "".b
      @session.process_pcm(data)
    end
  end

  class << self
    def source_stream(file, flags)
      if source_url?(file)
        Bass.create_url_stream(file, 0, flags, 0, 0)
      else
        Bass.create_file_stream_from_path(file, 0, flags)
      end
    end

    def memory_source_stream(data, flags)
      data = data.to_s.b
      Bass.create_file_stream_from_memory(data, flags)
    end

    def source_url?(file)
      file.to_s[0..4] == "http:" || file.to_s[0..5] == "https:"
    end

    def source_channels(channel)
      info_buffer = EltenRecorderStructs.bass_channel_info_buffer
      Bass::BASS_ChannelGetInfo.call(channel, info_buffer)
      info = EltenRecorderStructs.bass_channel_info_values(info_buffer)
      [info[1].to_i, 1].max
    rescue Exception
      2
    end

    def source_limited_channels(channel)
      [[source_channels(channel), 1].max, 2].min
    end

    def source_frequency(channel)
      freq = [0.0].pack("f")
      Bass::BASS_ChannelGetAttribute.call(channel, 1, freq)
      value = freq.unpack("f").first.to_i
      value > 0 ? value : 48000
    rescue Exception
      48000
    end

    def source_tags(channel)
      tags = {}
      ai = AudioInfo.new(channel)
      chapters = ai.chapters
      for i in 0...chapters.size
        chapter = chapters[i]
        key = sprintf("CHAPTER%03d", i)
        time = chapter.time.to_f
        tags[key] = sprintf("%02d:%02d:%02d.%03d", time / 3600, (time / 60) % 60, time % 60, ((time - time.to_i) * 1000).round)
        tags["#{key}NAME"] = chapter.name
      end
      tags["TITLE"] = ai.title if ai.title != nil && ai.title != ""
      tags["ARTIST"] = ai.artist if ai.artist != nil && ai.artist != ""
      tags["ALBUM"] = ai.album if ai.album != nil && ai.album != ""
      tags["TRACKNUMBER"] = ai.track_number if ai.track_number != nil && ai.track_number != ""
      tags
    rescue Exception
      {}
    end

    def pump_source(file, session_factory, normalize: false, frequency: 48000, channels: nil, buffer_size: 2097152)
      url = source_url?(file)
      channel = source_stream(file, 0x200000 | 131072)
      raise RuntimeError, "Cannot open audio source: BASS error #{Bass::BASS_ErrorGetCode.call}" if channel == 0
      if normalize
        pump_normalized_source(channel, url, session_factory, frequency, channels, buffer_size)
      else
        session = session_factory.call(channel, source_frequency(channel), source_channels(channel))
        pump_channel(channel, url, session, buffer_size)
      end
    ensure
      session.finish if session != nil
      Bass::BASS_StreamFree.call(channel) if channel != nil && channel != 0
    end

    def pump_memory_source(data, session_factory, normalize: false, frequency: 48000, channels: nil, buffer_size: 2097152, interactive: true)
      data = data.to_s.b
      channel = memory_source_stream(data, 0x200000 | 131072)
      raise RuntimeError, "Cannot open memory audio source: BASS error #{Bass::BASS_ErrorGetCode.call}" if channel == 0
      if normalize
        pump_normalized_source(channel, false, session_factory, frequency, channels, buffer_size, :interactive => interactive)
      else
        session = session_factory.call(channel, source_frequency(channel), source_channels(channel))
        pump_channel(channel, false, session, buffer_size, :interactive => interactive)
      end
    ensure
      session.finish if session != nil
      Bass::BASS_StreamFree.call(channel) if channel != nil && channel != 0
    end

    private

    def pump_normalized_source(channel, url, session_factory, frequency, channels, buffer_size, interactive: true)
      target_frequency = frequency.to_i > 0 ? frequency.to_i : 48000
      target_channels = channels || source_limited_channels(channel)
      target_channels = [[target_channels.to_i, 1].max, 2].min
      mixer = Bass::BASS_Mixer_StreamCreate.call(target_frequency, target_channels, 0x200000 | 0x10000)
      raise RuntimeError, "Cannot create recording mixer: BASS error #{Bass::BASS_ErrorGetCode.call}" if mixer == 0
      if Bass::BASS_Mixer_StreamAddChannel.call(mixer, channel, 0x10000 | 0x4000 | 0x800000) == 0
        raise RuntimeError, "Cannot add source to recording mixer: BASS error #{Bass::BASS_ErrorGetCode.call}"
      end
      session = session_factory.call(channel, target_frequency, target_channels)
      pump_channel(mixer, url, session, buffer_size, :source_channel => channel, :interactive => interactive)
    ensure
      session.finish if session != nil
      Bass::BASS_StreamFree.call(mixer) if mixer != nil && mixer != 0
    end

    def pump_channel(channel, url, session, buffer_size, source_channel: channel, interactive: true)
      buffer = "\0" * buffer_size
      total = 0
      while (size = Bass::BASS_ChannelGetData.call(channel, buffer, buffer_size)) > 0 || (url && Bass::BASS_StreamGetFilePosition.call(source_channel, 4) == 1)
        loop_update if interactive
        if size != nil && size > 0
          session.process_pcm(buffer.byteslice(0, size))
          total += size
        else
          sleep(0.01)
        end
        if interactive && key_pressed?(:key_escape)
          play_sound("cancel")
          break
        end
      end
      total
    end
  end
end

class RecorderOutput
  def write(_data)
  end

  def rewrite(_offset, _data)
  end

  def close
  end

  def data
    "".b
  end
end

class FileRecorderOutput < RecorderOutput
  def initialize(file)
    @file = File.open(file, "wb")
  end

  def write(data)
    @file.write(data.to_s.b)
  end

  def rewrite(offset, data)
    position = @file.pos
    @file.seek(offset.to_i, IO::SEEK_SET)
    @file.write(data.to_s.b)
    @file.seek(position, IO::SEEK_SET)
  end

  def close
    @file.close if @file != nil && !@file.closed?
  end
end

class MemoryRecorderOutput < RecorderOutput
  def initialize
    @data = "".b
  end

  def write(data)
    @data << data.to_s.b
  end

  def rewrite(offset, data)
    @data[offset.to_i, data.to_s.bytesize] = data.to_s.b
  end

  def data
    @data
  end
end

class AudioEncoder
  attr_reader :bytes_read

  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    @output = output
    @frequency = frequency.to_i > 0 ? frequency.to_i : 48000
    @channels = [channels.to_i, 1].max
    @bytes_read = 0
    self
  end

  def process_pcm(data)
    data = data.to_s.b
    @bytes_read += data.bytesize
    feed(data)
  end

  def feed(_data)
    0
  end

  def finish
    close
  end

  def close
  end

  def normalize_source?
    false
  end

  def source_frequency
    48000
  end

  def source_channels(channel)
    EltenRecorderRuntime.source_channels(channel)
  end

  def recording_buffer_bytes
    384000
  end
end

class OggNative
  class << self
    def load!
      require "fiddle"
      require_relative "conferencenative" unless defined?(::ELTEN_SIZE_T)
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

class OpusOggWriter
  def initialize(output, channels, preskip, tags = nil)
    @output = output
    @channels = channels.to_i
    @ogg = OggNative.stream_state_buffer
    @packetno = 0
    @granulepos = 0
    @lastpacket = nil
    @lastpacket_data = nil
    @lastpacket_data_pointer = nil
    OggNative.load!
    OggNative.stream_init.call(@ogg, rand(2**32) - 2**31)
    write_headers(preskip.to_i, tags)
  end

  def write_packet(data, samples)
    @granulepos += samples.to_i
    add_packet(data)
  end

  def close
    return if @ogg == nil
    add_packet("") if @lastpacket == nil
    OggNative.packet_set_eos(@lastpacket, 1)
    add_packet(nil)
    OggNative.stream_clear.call(@ogg)
    @ogg = nil
  end

  private

  def write_headers(preskip, tags)
    head = "OpusHead".b
    head += [1].pack("C")
    head += [@channels].pack("C")
    head += [preskip].pack("S")
    head += [48000].pack("I")
    head += [0].pack("S")
    head += [0].pack("C")
    add_packet(head, true, false)
    add_packet(opus_tags(tags), false, false, false)
  end

  def opus_tags(tags)
    vendor = Opus.version.b
    comments = []
    (tags || {}).each do |key, value|
      next if key == nil || value == nil
      comments << utf8_comment("#{key}=#{value}")
    end
    comments << utf8_comment("ENCODER=ELTEN") if comments.none? { |comment| comment.upcase.start_with?("ENCODER=") }
    data = "OpusTags".b
    data += [vendor.bytesize].pack("I")
    data += vendor
    data += [comments.size].pack("I")
    comments.each do |comment|
      data += [comment.bytesize].pack("I")
      data += comment
    end
    data
  end

  def utf8_comment(text)
    text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).b
  end

  def add_packet(data, b_o_s = false, e_o_s = false, writepages = true)
    if @lastpacket != nil
      OggNative.stream_packetin.call(@ogg, @lastpacket)
      if writepages
        page = OggNative.page_buffer
        while OggNative.stream_pageout.call(@ogg, page) != 0
          values = OggNative.page_values(page)
          @output.write(OggNative.page_part(values[0], values[1], 282))
          @output.write(OggNative.page_part(values[2], values[3], 65_025))
        end
      end
    end
    if data != nil
      @packetno += 1
      @lastpacket_data = data.b
      @lastpacket_data_pointer = OggNative.packet_data_pointer(@lastpacket_data)
      @lastpacket = OggNative.packet(@lastpacket_data_pointer, @lastpacket_data.bytesize, b_o_s ? 1 : 0, e_o_s ? 1 : 0, @granulepos, @packetno)
    end
  end
end

class OpusAudioEncoder < AudioEncoder
  def initialize(bitrate = 64, framesize = 60, application = 2048, usevbr = 1, tags: nil, denoise: false)
    @bitrate = bitrate.to_i
    @framesize = framesize.to_f
    @framesize = 20.0 if @framesize <= 0
    @framesize = [@framesize, 60.0].min
    @application = application.to_i
    @usevbr = usevbr.to_i
    @tags = tags
    @denoise = denoise == true
  end

  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    super(output, :frequency => 48000, :channels => [[channels.to_i, 1].max, 2].min, :source_channel => source_channel)
    require_relative "opus" unless defined?(::Opus)
    require_relative "speexdsp" unless defined?(::SpeexDSP)
    @frame_samples = (48000 * @framesize / 1000).to_i
    @frame_bytes = @frame_samples * @channels * 2
    @queue = "".b
    @encoder = Opus::Encoder.new(48000, @channels, @application == 2049 ? :audio : :voip)
    handle = @encoder.instance_variable_get(:@encoder)
    raise RuntimeError, "Opus encoder is unavailable" if handle == nil || handle.to_i == 0
    @encoder.bitrate = @bitrate * 1000
    @encoder.vbr = @usevbr
    @speex = nil
    if @denoise && defined?(::SpeexDSP)
      @speex = SpeexDSP::Processor.new(48000, @channels, @framesize)
      @speex.noise_reduction = true
    end
    tags = @tags
    tags = EltenRecorderRuntime.source_tags(source_channel) if tags == nil && source_channel != nil
    @writer = OpusOggWriter.new(output, @channels, @encoder.preskip, tags)
    self
  rescue Exception
    close
    raise
  end

  def feed(data)
    return 0 if data == nil || data.bytesize <= 0
    @queue << data.to_s.b
    processed = 0
    while @queue.bytesize >= @frame_bytes
      frame = @queue.byteslice(0, @frame_bytes)
      @queue = @queue.byteslice(@frame_bytes..-1) || "".b
      process_frame(frame)
      processed += frame.bytesize
    end
    processed
  end

  def finish
    if @queue != nil && @queue.bytesize > 0
      frame = @queue + ("\0" * (@frame_bytes - @queue.bytesize)).b
      @queue = "".b
      process_frame(frame)
    end
    close
  end

  def close
    @writer.close if @writer != nil
    @writer = nil
    @speex.free if @speex != nil
    @speex = nil
    @encoder.free if @encoder != nil && !@encoder.closed?
    @encoder = nil
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

  def recording_buffer_bytes
    [@frame_samples.to_i * 2 * 2 * 8, 384000].max
  end

  private

  def process_frame(frame)
    frame = @speex.process(frame) if @speex != nil
    return if frame == nil || frame.bytesize < @frame_bytes
    frame = frame.byteslice(0, @frame_bytes)
    packet = @encoder.encode(frame, @frame_samples)
    @writer.write_packet(packet, @frame_samples) if packet != nil && packet.bytesize > 0
  end
end

module VorbisNative
  STRUCT_SIZE = 8192
  PACKET_SIZE = OggNative.packet_size

  class << self
    def load!
      return if @loaded
      require "fiddle"
      require_relative "conferencenative" unless defined?(::ELTEN_INTPTR)
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

class WaveAudioEncoder < AudioEncoder
  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    super(output, :frequency => frequency, :channels => channels, :source_channel => source_channel)
    @channels = [@channels, 1].max
    @bits = 16
    @data_size = 0
    @sample_bytes = @channels * 2
    @queue = "".b
    @output.write(header(0))
    self
  end

  def feed(data)
    return 0 if data == nil || data.bytesize <= 0
    @queue << data.to_s.b
    bytes = @queue.bytesize / @sample_bytes * @sample_bytes
    return 0 if bytes <= 0
    chunk = @queue.byteslice(0, bytes)
    @queue = @queue.byteslice(bytes..-1) || "".b
    @output.write(chunk)
    @data_size += chunk.bytesize
    chunk.bytesize
  end

  def finish
    feed("".b)
    @output.rewrite(0, header(@data_size))
    close
  end

  private

  def header(data_size)
    byte_rate = @frequency * @channels * @bits / 8
    block_align = @channels * @bits / 8
    data = "RIFF".b
    data += [36 + data_size].pack("V")
    data += "WAVEfmt ".b
    data += [16].pack("V")
    data += [1, @channels, @frequency, byte_rate, block_align, @bits].pack("vvVVvv")
    data += "data".b
    data += [data_size].pack("V")
    data
  end
end

class Recorder
  def initialize(file, encoder = nil)
    @file = file
    @encoder = encoder || WaveAudioEncoder.new
    @output = FileRecorderOutput.new(file)
    @recording = EltenRecorderRuntime::InputRecording.new(proc {
      @encoder.start(@output, :frequency => 48000, :channels => 2)
    }, @encoder.recording_buffer_bytes)
  rescue Exception
    @output.close if @output != nil
    raise
  end

  def stop
    return if @recording == nil
    @recording.stop
  ensure
    @recording = nil
    @output.close if @output != nil
    @output = nil
  end

  def pause
    @recording.pause if @recording != nil
  end

  def resume
    @recording.resume if @recording != nil
  end

  def paused
    @recording != nil && @recording.paused
  end

  class << self
    def start(file, encoder = nil)
      new(file, encoder)
    end

    def opus_recording(file, bitrate = 64, framesize = 60, application = 2048, usevbr = 1, timelimit = 0, tags: nil, denoise: nil)
      denoise = (Configuration.usedenoising == 2) if denoise == nil
      new(file, OpusAudioEncoder.new(bitrate, framesize, application, usevbr, :tags => tags, :denoise => denoise))
    end

    def vorbis_recording(file, bitrate = 64)
      new(file, VorbisAudioEncoder.new(bitrate))
    end

    def wave_recording(file)
      new(file, WaveAudioEncoder.new)
    end

    def encode_file(source, output, encoder = nil)
      sink = FileRecorderOutput.new(output)
      encode_to_output(source, sink, encoder || WaveAudioEncoder.new)
    ensure
      sink.close if sink != nil
    end

    def encode_data(source, encoder = nil)
      sink = MemoryRecorderOutput.new
      encode_to_output(source, sink, encoder || WaveAudioEncoder.new)
      sink.data
    ensure
      sink.close if sink != nil
    end

    def encode_pcm_file(pcm, output, encoder = nil, frequency: 48000, channels: 1, interactive: true)
      sink = FileRecorderOutput.new(output)
      encode_pcm_to_output(pcm, sink, encoder || WaveAudioEncoder.new, :frequency => frequency, :channels => channels, :interactive => interactive)
    ensure
      sink.close if sink != nil
    end

    def encode_pcm_data(pcm, encoder = nil, frequency: 48000, channels: 1, interactive: true)
      sink = MemoryRecorderOutput.new
      encode_pcm_to_output(pcm, sink, encoder || WaveAudioEncoder.new, :frequency => frequency, :channels => channels, :interactive => interactive)
      sink.data
    ensure
      sink.close if sink != nil
    end

    def opus_encoder(bitrate = 64, framesize = 60, application = 2048, usevbr = 1, tags: nil, denoise: false)
      OpusAudioEncoder.new(bitrate, framesize, application, usevbr, :tags => tags, :denoise => denoise)
    end

    def vorbis_encoder(bitrate = 64, tags: nil)
      VorbisAudioEncoder.new(bitrate, :tags => tags)
    end

    def wave_encoder
      WaveAudioEncoder.new
    end

    def encode_opus_file(source, output, bitrate = 64, framesize = 60, application = 2048, usevbr = 1, timelimit = 0, tags = nil)
      encode_file(source, output, opus_encoder(bitrate, framesize, application, usevbr, :tags => tags))
    end

    def copy_opus_file(source, output, tags)
      encode_opus_file(source, output, 64, 20, 2048, 0, 0, tags)
    end

    def encode_vorbis_file(source, output, bitrate = 64)
      encode_file(source, output, vorbis_encoder(bitrate))
    end

    def get_vorbis_data(source, bitrate = 64)
      encode_data(source, vorbis_encoder(bitrate))
    end

    def encode_wave_file(source, output)
      encode_file(source, output, wave_encoder)
    end

    private

    def encode_pcm_to_output(pcm, output, encoder, frequency: 48000, channels: 1, interactive: true)
      frequency = frequency.to_i > 0 ? frequency.to_i : 48000
      channels = [[channels.to_i, 1].max, 2].min
      pcm = pcm.to_s.b
      if encoder.normalize_source? && (frequency != encoder.source_frequency || channels > 2)
        return encode_memory_wave_to_output(pcm, output, encoder, :frequency => frequency, :channels => channels, :interactive => interactive)
      end
      encode_pcm_direct_to_output(pcm, output, encoder, :frequency => frequency, :channels => channels, :interactive => interactive)
    end

    def encode_pcm_direct_to_output(pcm, output, encoder, frequency: 48000, channels: 1, interactive: true)
      session = encoder.start(output, :frequency => frequency, :channels => channels)
      offset = 0
      chunk_size = 262144
      while offset < pcm.bytesize
        loop_update if interactive
        raise Interrupt if interactive && key_pressed?(:key_escape)
        chunk = pcm.byteslice(offset, chunk_size)
        session.process_pcm(chunk)
        offset += chunk.bytesize
      end
      session.finish
      session = nil
      pcm.bytesize
    ensure
      session.finish if session != nil
    end

    def encode_memory_wave_to_output(pcm, output, encoder, frequency: 48000, channels: 1, interactive: true)
      EltenRecorderRuntime.pump_memory_source(
        pcm_wave_data(pcm, frequency, channels),
        proc do |channel, source_frequency, source_channels|
          target_frequency = encoder.normalize_source? ? encoder.source_frequency : source_frequency
          target_channels = encoder.source_channels(channel)
          encoder.start(output, :frequency => target_frequency, :channels => target_channels, :source_channel => channel)
        end,
        :normalize => encoder.normalize_source?,
        :frequency => encoder.source_frequency,
        :channels => nil,
        :interactive => interactive
      )
    end

    def pcm_wave_data(pcm, frequency, channels)
      pcm = pcm.to_s.b
      channels = [[channels.to_i, 1].max, 2].min
      bits = 16
      byte_rate = frequency.to_i * channels * bits / 8
      block_align = channels * bits / 8
      data = "RIFF".b
      data += [36 + pcm.bytesize].pack("V")
      data += "WAVEfmt ".b
      data += [16].pack("V")
      data += [1, channels, frequency.to_i, byte_rate, block_align, bits].pack("vvVVvv")
      data += "data".b
      data += [pcm.bytesize].pack("V")
      data + pcm
    end

    def encode_to_output(source, output, encoder)
      session = nil
      total = EltenRecorderRuntime.pump_source(
        source,
        proc do |channel, frequency, channels|
          source_frequency = encoder.normalize_source? ? encoder.source_frequency : frequency
          source_channels = encoder.source_channels(channel)
          session = encoder.start(output, :frequency => source_frequency, :channels => source_channels, :source_channel => channel)
        end,
        :normalize => encoder.normalize_source?,
        :frequency => encoder.source_frequency,
        :channels => nil
      )
      total
    end
  end
end
