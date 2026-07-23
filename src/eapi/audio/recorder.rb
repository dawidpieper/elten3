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
      denoise = (Configuration.usedenoising == :conferences_and_recording) if denoise == nil
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
