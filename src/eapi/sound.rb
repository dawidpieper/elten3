# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class SoundStatus
  attr_reader :name, :bass_code

  def initialize(name, bass_code)
    @name = name
    @bass_code = bass_code
  end

  def stopped?
    @name == :stopped
  end

  def playing?
    @name == :playing
  end

  def stalled?
    @name == :stalled
  end

  def paused?
    @name == :paused
  end

  def to_sym
    @name
  end

  def to_s
    @name.to_s
  end

  Stopped = new(:stopped, 0)
  Playing = new(:playing, 1)
  Stalled = new(:stalled, 2)
  Paused = new(:paused, 3)
  Unknown = new(:unknown, nil)

  BY_CODE = {
    0 => Stopped,
    1 => Playing,
    2 => Stalled,
    3 => Paused
  }

  def self.from_bass(code)
    BY_CODE[code.to_i] || Unknown
  end
end

class AudioInfo
  class ID3Frame
    attr_accessor :id, :size, :encrypted, :compressed, :grouped, :group, :numvalue, :strvalue
    attr_reader :subframes

    def initialize
      @id = ""
      @size = 0
      @encrypted = false
      @compressed = false
      @grouped = false
      @group = 0
      @numvalue = 0
      @strvalue = ""
      @subframes = []
    end
  end

  class Chapter
    attr_accessor :id, :name, :time
  end

  def initialize(channel)
    @channel = channel
  end

  def tags_ogg
    return {} if @channel == nil || @channel == 0
    tags = {}
    t = Bass::BASS_ChannelGetTags.call(@channel, 2)
    if t != 0
      m = ""
      i = 0
      loop do
        byte = EltenBassStructs.pointer_bytes(t + i, 1).getbyte(0)
        if byte != 0
          m += "\0"
          m.setbyte(m.bytesize - 1, byte)
        elsif m.size > 0
          r = m.index("=") || m.size
          k = m[0...r]
          v = m[(r + 1)..-1] || ""
          tags[k] = v
          m = ""
        elsif m.size == 0
          break
        end
        i += 1
      end
    end
    tags
  end

  def tags_id3v2
    return [] if @channel == nil || @channel == 0
    tags = []
    t = Bass::BASS_ChannelGetTags.call(@channel, 1)
    if t != 0
      q = t
      header = EltenBassStructs.pointer_bytes(q, 10)
      return nil if header.getbyte(3) < 3 || header.getbyte(3) > 4
      extheader = (header.getbyte(5) & 64) > 0
      size = header.getbyte(9) + header.getbyte(8) * 128 + header.getbyte(7) * 16384 + header.getbyte(6) * 2097152
      q += 10
      if extheader
        ehsize = EltenBassStructs.pointer_bytes(q, 4)
        q += 4 + ehsize.getbyte(3) + ehsize.getbyte(2) * 256 + ehsize.getbyte(1) * 65536 + ehsize.getbyte(0) * 16777216
      end
      tags = id3_getframes(q, size, header.getbyte(3))
    end
    tags
  end

  def id3_getframes(q, size, version)
    r = []
    final = q + size
    while q < final
      header = EltenBassStructs.pointer_bytes(q, 10)
      q += 10
      if header.getbyte(0) == 0
        q += 1
        next
      end
      f = ID3Frame.new
      f.id = header[0...4]
      f.size = header.getbyte(7) + header.getbyte(6) * 256 + header.getbyte(5) * 65536 + header.getbyte(4) * 16777216
      f.size = unsynchsafe(f.size) if version == 4
      f.compressed = (header.getbyte(9) & 128) > 0
      f.encrypted = (header.getbyte(9) & 64) > 0
      f.grouped = (header.getbyte(9) & 32) > 0
      left = f.size
      if f.grouped
        t = EltenBassStructs.pointer_bytes(q, 1)
        q += 1
        f.group = t.getbyte(0)
        left -= 1
      end
      if !f.compressed && !f.encrypted
        if f.id == "CHAP"
          loop do
            t = EltenBassStructs.pointer_bytes(q, 1)
            q += 1
            left -= 1
            break if t.getbyte(0) == 0
          end
          timings = EltenBassStructs.pointer_bytes(q, 16)
          q += 16
          left -= 16
          if timings.getbyte(0) != 0xff || timings.getbyte(1) != 0xff || timings.getbyte(2) != 0xff || timings.getbyte(3) != 0xff
            f.numvalue = timings.getbyte(3) + timings.getbyte(2) * 256 + timings.getbyte(1) * 65536 + timings.getbyte(0) * 16777216
          else
            f.numvalue = timings.getbyte(7) + timings.getbyte(6) * 256 + timings.getbyte(5) * 65536 + timings.getbyte(4) * 16777216
          end
          id3_getframes(q, left, version).each { |m| f.subframes.push(m) }
        elsif f.id[0..0] == "T" && f.id[1..1] != "X"
          t = EltenBassStructs.pointer_bytes(q, 1)
          q += 1
          left -= 1
          encoding = :ASCII
          if t.getbyte(0) == 0
            encoding = :ISO_8859_1
          elsif t.getbyte(0) == 1
            u = EltenBassStructs.pointer_bytes(q, 2)
            q += 2
            left -= 2
            encoding = u.getbyte(1) == 0xff ? :UnicodeFFE : :UTF16
          elsif t.getbyte(0) == 2
            encoding = :UTF16
          elsif t.getbyte(0) == 3
            encoding = :UTF8
          end
          content = EltenBassStructs.pointer_bytes(q, left)
          case encoding
          when :UTF8
            content = content.deutf8
          when :UTF16
            content = deunicode(content)
          when :UnicodeFFE
            for i in 0...content.bytesize / 2
              s = i * 2
              c = content[s]
              content[s] = content[s + 1]
              content[s + 1] = c
            end
            content = deunicode(content)
          end
          f.strvalue = content
          q += left
          left = 0
        end
      end
      q += left
      r.push(f)
    end
    r
  rescue Exception
    []
  end

  def like_ogg
    t = tags_ogg
    return t if t != {}
    t = tags_id3v2
    if t != nil
      tgs = {}
      mapper = {"TIT2" => "TITLE", "TALB" => "ALBUM", "TPE1" => "ARTIST", "TRCK" => "TRACKNUMBER", "TCOM" => "COMPOSER", "TCOP" => "COPYRIGHT"}
      for d, o in mapper
        f = t.find { |frame| frame.id == d }
        tgs[o] = f.strvalue if f != nil
      end
      chs = t.select { |frame| frame.id == "CHAP" }
      i = 0
      for c in chs
        time = c.numvalue / 1000.0
        name = ""
        sf = c.subframes.find { |s| s.id == "TIT2" }
        name = sf.strvalue if sf != nil
        h = sprintf("CHAPTER%03d", i)
        tm = sprintf("%02d:%02d:%02d.%03d", time / 3600, (time / 60) % 60, time % 60, time - time.to_i)
        tgs[h] = tm
        tgs["#{h}NAME"] = name
        i += 1
      end
      return tgs
    end
    {}
  end

  def title
    auto_get("TITLE", "TIT2")
  end

  def album
    auto_get("ALBUM", "TALB")
  end

  def artist
    auto_get("ARTIST", "TPE1")
  end

  def track_number
    auto_get("TRACKNUMBER", "TRCK")
  end

  def copyright
    auto_get("COPYRIGHT", "TCOP")
  end

  def chapters
    return @chapters if @chapters != nil && @chapters != []
    chapters = []
    if (t = tags_ogg) != nil
      for i in 0..999
        d = sprintf("%03d", i)
        if t["CHAPTER#{d}"] != nil && t["CHAPTER#{d}NAME"] != nil
          tm = t["CHAPTER#{d}"]
          time = tm.split(":").map { |x| x.to_f }.inject(0) { |a, b| a * 60 + b }
          name = t["CHAPTER#{d}NAME"].deutf8
          ch = Chapter.new
          ch.time = time
          ch.name = name
          ch.id = i
          chapters.push(ch)
        end
      end
    end
    if (t = tags_id3v2) != nil
      for f in t
        if f.id == "CHAP" && f.subframes.size > 0
          c = Chapter.new
          c.time = f.numvalue / 1000.0
          c.name = ""
          for g in f.subframes
            c.name = g.strvalue if g.id == "TIT2"
          end
          chapters.push(c)
        end
      end
    end
    @chapters = chapters
    chapters
  end

  private

  def auto_get(ogg, id3)
    if (t = tags_ogg) != nil
      return t[ogg.upcase] if t[ogg.upcase] != nil
    end
    if (t = tags_id3v2) != nil
      for r in t
        return r.strvalue[0...r.strvalue.index("\0") || r.strvalue.size] if r.id == id3
      end
    end
    nil
  end
end

class SoundEffect
  def output_channels(channels, _frequency)
    channels
  end

  def output_frequency(frequency, _channels)
    frequency
  end

  def process(audio, _frequency, _channels)
    audio
  end

  def reset
  end

  def close
  end
end

class Sound
  attr_reader :file, :channel, :source_channel, :sample_handle, :kind, :basefrequency, :effects

  SAMPLE_FLOAT = 0x100
  BASS_STREAM_DECODE = 0x200000
  BASS_UNICODE = 0x80000000
  FRAME_MILLISECONDS = 20
  @@finalizers = {}

  def initialize(file = nil, sample: false, loop: false, stream: nil)
    @file = file
    @stream_data = stream
    @sample = sample == true
    @looper = loop == true
    @closed = false
    @sample_handle = 0
    @source_channel = 0
    @source_mixer = 0
    @channel = 0
    @playback_channel = 0
    @processing_channel = 0
    @processing_frequency = nil
    @processing_channels = 0
    @kind = :none
    @effects = []
    @effects_mutex = Mutex.new
    @pipeline_mutex = Mutex.new
    @pipeline = false
    @processing_thread = nil
    @processing_playing = false
    @processing_paused = false
    @processing_output_started = false
    open_direct
    @basefrequency = frequency
    Bass::BASS_ChannelFlags.call(@channel, BASS_STREAM_DECODE, BASS_STREAM_DECODE) if @channel.to_i != 0
    Bass::BASS_ChannelFlags.call(@channel, 4, 4) if @looper && @channel.to_i != 0
    @finalizer_id = object_id
    update_finalizer
    ObjectSpace.define_finalizer(self, self.class.finalizer(@finalizer_id))
  end

  def self.finalizer(id)
    proc do
      begin
        entry = @@finalizers.delete(id)
        next if entry == nil
        sample_handle, source_channel, channel, playback_channel, source_mixer, kind = entry
        if kind == nil
          kind = source_mixer
          source_mixer = 0
        end
        if kind == :sample
          Bass::BASS_SampleFree.call(sample_handle) if sample_handle.to_i != 0
        else
          free_stream_handle(source_mixer) if source_mixer.to_i != 0
          free_stream_handle(channel) if channel.to_i != 0 && channel != source_mixer
          free_stream_handle(source_channel) if source_channel.to_i != 0 && source_channel != channel && source_channel != source_mixer
          free_stream_handle(playback_channel) if playback_channel.to_i != 0
        end
      rescue Exception
      end
    end
  end

  def self.free_stream_handle(handle)
    Bass.release_stream_data(handle) if defined?(Bass) && Bass.respond_to?(:release_stream_data)
    Bass::BASS_StreamFree.call(handle)
  end

  def open_direct
    if @sample && @file != nil && @stream_data == nil && @file.to_s[0, 4] != "http"
      @sample_handle, @channel = Bass.create_sample_channel(@file)
      if @sample_handle != 0 && @channel != 0
        @kind = :sample
        return
      end
    end
    @source_channel, @channel = Bass.create_stream_channel(@file, 0, @stream_data)
    @kind = :stream if @channel.to_i != 0
    Log.error("Cannot play audio file: #{@file}") if @channel.to_i == 0
  rescue Exception => e
    Log.error("Cannot play audio: #{e.class}: #{e.message} #{Array(e.backtrace).join("\n")}")
  end

  def open_effect_source(position = 0.0)
    close_native_handles
    flags = SAMPLE_FLOAT | BASS_STREAM_DECODE
    if @file == nil && @stream_data != nil
      @source_channel = Bass.create_file_stream_from_memory(@stream_data, flags)
    elsif @file != nil && @file.to_s[0, 4] == "http"
      @source_channel = Bass.create_url_stream(@file, 0, flags, 0, 0)
    else
      @source_channel = Bass.create_file_stream_from_path(@file, 0, flags)
    end
    @channel = @source_channel
    @kind = :stream
    if @source_channel.to_i == 0
      Log.error("Cannot open audio effect source: #{@file}")
      update_finalizer
      return
    end
    self.position = position if position > 0
    @basefrequency = frequency
    @processing_frequency = pipeline_output_frequency
    @processing_channels = [[channels.to_i, 1].max, 2].min
    @processing_channel = build_effect_source_channel(@processing_frequency, @processing_channels)
    @playback_channels = pipeline_output_channels(@processing_frequency, @processing_channels)
    @playback_channel = Bass::BASS_StreamCreate.call(@processing_frequency, @playback_channels, SAMPLE_FLOAT, -1, nil)
    update_finalizer
  end

  def opened?
    @channel.to_i != 0 && !closed?
  end

  def playing?
    status.playing?
  end

  def channels
    info_values[1].to_i
  end

  def data(seconds = length)
    return nil if !opened?
    bytes = seconds_to_bytes(seconds)
    return "".b if bytes <= 0
    buffer = "\0".b * bytes
    read = Bass::BASS_ChannelGetData.call(@channel, buffer, bytes)
    return "".b if read.to_i <= 0
    buffer.byteslice(0, read).to_s.b
  end

  def status
    return SoundStatus::Stopped if !opened?
    if @pipeline
      return SoundStatus::Playing if @processing_playing && !@processing_paused
      return SoundStatus::Paused if @processing_paused
      output_status = SoundStatus.from_bass(Bass::BASS_ChannelIsActive.call(@playback_channel)) if @playback_channel.to_i != 0
      return output_status if output_status != nil && !output_status.stopped?
      return SoundStatus::Stopped
    end
    SoundStatus.from_bass(Bass::BASS_ChannelIsActive.call(@channel))
  end

  def play
    return if !opened?
    if @pipeline
      was_paused = @processing_paused
      @processing_playing = true
      @processing_paused = false
      ensure_processing_thread
      Bass::BASS_ChannelPlay.call(@playback_channel, 0) if was_paused && @processing_output_started && @playback_channel.to_i != 0
      return
    end
    if Bass::BASS_ChannelPlay.call(@channel, 0) == 0
      err = Bass::BASS_ErrorGetCode.call
      Bass.reset if err == 9
    end
  end

  def stop
    return if !opened?
    if @pipeline
      @processing_playing = false
      @processing_paused = false
      @processing_output_started = false
      Bass::BASS_ChannelStop.call(@playback_channel) if @playback_channel.to_i != 0
      self.position = 0
    elsif @kind == :sample
      Bass::BASS_SampleStop.call(@sample_handle)
    else
      Bass::BASS_ChannelStop.call(@channel)
    end
  end

  def pause
    return if !opened?
    if @pipeline
      @processing_paused = true
      Bass::BASS_ChannelPause.call(@playback_channel) if @playback_channel.to_i != 0
    else
      Bass::BASS_ChannelPause.call(@channel)
    end
  end

  def info
    AudioInfo.new(@channel)
  end

  def chapters
    info.chapters
  end

  def effect_add(effect)
    fail(ArgumentError, "Sound effect must respond to #process") if !effect.respond_to?(:process)
    @effects_mutex.synchronize { @effects << effect }
    rebuild_effect_pipeline
    effect
  end

  def effect_remove(effect)
    removed = false
    @effects_mutex.synchronize { removed = @effects.delete(effect) != nil }
    effect.close if removed && effect.respond_to?(:close)
    rebuild_effect_pipeline
    removed
  end

  def close
    return if @closed
    @closed = true
    @processing_playing = false
    @processing_output_started = false
    @processing_thread.kill if @processing_thread != nil && @processing_thread.alive?
    @processing_thread = nil
    @effects_mutex.synchronize { @effects.each { |effect| effect.close if effect.respond_to?(:close) } }
    close_native_handles
    @sample_handle = 0
    @source_channel = 0
    @source_mixer = 0
    @channel = 0
    @playback_channel = 0
    @processing_channel = 0
    @processing_frequency = nil
    @processing_channels = 0
    @@finalizers.delete(@finalizer_id)
    nil
  end

  def closed?
    @closed == true
  end

  def frequency
    attribute(1).to_i
  end

  def frequency=(value)
    set_attribute(1, value.to_f)
  end

  def pan
    attribute(3, playback_attribute_channel)
  end

  def pan=(value)
    set_attribute(3, value.to_f, playback_attribute_channel)
  end

  def tempo
    attribute(0x10000)
  end

  def tempo=(value)
    if @tempo == nil
      @tempo = value
      Bass::BASS_ChannelSetAttribute.call(@channel, 65555, 60) if opened?
      Bass::BASS_ChannelSetAttribute.call(@channel, 65554, 1) if opened?
    end
    set_attribute(0x10000, value.to_f)
  end

  def volume
    attribute(2, playback_attribute_channel)
  end

  def volume=(value)
    set_attribute(2, value.to_f, playback_attribute_channel)
  end

  def new_channel
    return nil if @kind != :sample || @sample_handle.to_i == 0
    @channel = Bass::BASS_SampleGetChannel.call(@sample_handle, 0)
    Bass::BASS_ChannelFlags.call(@channel, 4, 4) if @looper
    update_finalizer
    @channel
  end

  def length
    return 0.0 if !opened?
    bytes = Bass::BASS_ChannelGetLength.call(@channel, 0)
    seconds_from_bytes(bytes)
  end

  def position
    return 0.0 if !opened?
    seconds_from_bytes(Bass::BASS_ChannelGetPosition.call(@channel, 0))
  end

  def position=(value)
    return 0.0 if !opened?
    seconds = value.to_f
    seconds = 0.0 if seconds.nan? || seconds < 0
    bytes = seconds_to_bytes(seconds)
    Bass::BASS_ChannelSetPosition.call(@channel, bytes, 0)
    reset_effects
    seconds
  end

  def bitrate
    flags = info_values[2].to_i
    return 32 if (flags & SAMPLE_FLOAT) != 0
    bits = info_values[5].to_i
    bits > 0 ? bits : 16
  end

  def type
    return :float if bitrate == 32 && (info_values[2].to_i & SAMPLE_FLOAT) != 0
    "s#{bitrate}le".to_sym
  end

  private

  def update_finalizer
    @@finalizers[@finalizer_id] = [@sample_handle, @source_channel, @channel, @playback_channel, @source_mixer, @kind]
  end

  def playback_attribute_channel
    @pipeline && @playback_channel.to_i != 0 ? @playback_channel : @channel
  end

  def info_values
    return @info_values if @info_values != nil && @info_values_channel == @channel
    buffer = EltenBassStructs.bass_channel_info_buffer
    Bass::BASS_ChannelGetInfo.call(@channel, buffer) if @channel.to_i != 0
    @info_values = EltenBassStructs.bass_channel_info_values(buffer)
    @info_values_channel = @channel
    @info_values
  end

  def attribute(id, target = @channel)
    return 0.0 if target.to_i == 0 || closed?
    buffer = [0.0].pack("f")
    Bass::BASS_ChannelGetAttribute.call(target, id, buffer)
    buffer.unpack1("f").to_f
  end

  def set_attribute(id, value, target = @channel)
    return 0.0 if target.to_i == 0 || closed?
    Bass::BASS_ChannelSetAttribute.call(target, id, value.to_f)
    value.to_f
  end

  def seconds_from_bytes(bytes)
    bytes = bytes.to_i
    return 0.0 if bytes <= 0
    seconds = Bass::BASS_ChannelBytes2Seconds.call(@channel, bytes)
    return 0.0 if seconds.to_f.nan? || seconds.to_f.infinite?
    seconds.to_f
  rescue Exception
    0.0
  end

  def seconds_to_bytes(seconds)
    seconds = seconds.to_f
    return 0 if seconds <= 0 || seconds.nan? || seconds.infinite?
    Bass::BASS_ChannelSeconds2Bytes.call(@channel, seconds).to_i
  rescue Exception
    ch = channels
    ch = 1 if ch <= 0
    (seconds * [frequency, 1].max * ch * bitrate / 8).to_i
  end

  def close_native_handles
    if @kind == :sample
      Bass::BASS_SampleFree.call(@sample_handle) if @sample_handle.to_i != 0
    else
      self.class.free_stream_handle(@source_mixer) if @source_mixer.to_i != 0
      self.class.free_stream_handle(@channel) if @channel.to_i != 0 && @channel != @source_mixer
      self.class.free_stream_handle(@source_channel) if @source_channel.to_i != 0 && @source_channel != @channel && @source_channel != @source_mixer
    end
    self.class.free_stream_handle(@playback_channel) if @playback_channel.to_i != 0
    @sample_handle = 0
    @source_channel = 0
    @source_mixer = 0
    @channel = 0
    @playback_channel = 0
    @processing_channel = 0
    @processing_frequency = nil
    @processing_channels = 0
    @info_values = nil
  end

  def rebuild_effect_pipeline
    @pipeline_mutex.synchronize do
      was_playing = playing?
      pos = position
      @processing_playing = false
      @processing_output_started = false
      @processing_thread.kill if @processing_thread != nil && @processing_thread.alive?
      @processing_thread = nil
      reset_effects
      if @effects.empty?
        close_native_handles
        @pipeline = false
        open_direct
      else
        @pipeline = true
        open_effect_source(pos)
      end
      play if was_playing
    end
  end

  def pipeline_output_frequency
    freq = frequency
    freq = 1 if freq <= 0
    ch = channels
    ch = 1 if ch <= 0
    ch = 2 if ch > 2
    @effects_mutex.synchronize do
      @effects.each do |effect|
        if effect.respond_to?(:output_frequency)
          next_frequency = effect.output_frequency(freq, ch)
          freq = next_frequency.to_i if next_frequency != nil
        end
        freq = 1 if freq <= 0
        ch = effect.output_channels(ch, freq) if effect.respond_to?(:output_channels)
        ch = [[ch.to_i, 1].max, 2].min
      end
    end
    freq
  end

  def pipeline_output_channels(freq = frequency, source_channels = channels)
    ch = source_channels
    ch = 1 if ch <= 0
    @effects_mutex.synchronize do
      @effects.each do |effect|
        ch = effect.output_channels(ch, freq) if effect.respond_to?(:output_channels)
      end
    end
    [[ch.to_i, 1].max, 2].min
  end

  def build_effect_source_channel(target_frequency, target_channels)
    source_frequency = frequency
    source_frequency = 1 if source_frequency <= 0
    source_channels = channels
    source_channels = 1 if source_channels <= 0
    target_frequency = target_frequency.to_i
    target_frequency = source_frequency if target_frequency <= 0
    target_channels = [[target_channels.to_i, 1].max, 2].min
    source_limited_channels = [[source_channels.to_i, 1].max, 2].min
    if source_frequency == target_frequency && source_channels == target_channels && source_channels == source_limited_channels
      @processing_frequency = source_frequency
      @processing_channels = source_channels
      return @source_channel
    end
    @source_mixer = Bass::BASS_Mixer_StreamCreate.call(target_frequency, target_channels, BASS_STREAM_DECODE | SAMPLE_FLOAT | 0x10000)
    if @source_mixer.to_i == 0
      Log.error("Sound effect mixer create failed: BASS error #{Bass::BASS_ErrorGetCode.call}")
      @processing_frequency = source_frequency
      @processing_channels = source_limited_channels
      return @source_channel
    end
    if Bass::BASS_Mixer_StreamAddChannel.call(@source_mixer, @source_channel, 0x10000 | 0x4000 | 0x800000) == 0
      Log.error("Sound effect mixer add failed: BASS error #{Bass::BASS_ErrorGetCode.call}")
      Bass::BASS_StreamFree.call(@source_mixer)
      @source_mixer = 0
      @processing_frequency = source_frequency
      @processing_channels = source_limited_channels
      return @source_channel
    end
    @processing_frequency = target_frequency
    @processing_channels = target_channels
    @source_mixer
  end

  def ensure_processing_thread
    return if @processing_thread != nil && @processing_thread.alive?
    @processing_thread = Thread.new { processing_loop }
    @processing_thread.report_on_exception = false
  end

  def processing_loop
    read_channel = @processing_channel.to_i != 0 ? @processing_channel : @source_channel
    source_channels = @processing_channels.to_i
    source_channels = 1 if source_channels <= 0
    freq = @processing_frequency.to_i
    freq = frequency if freq <= 0
    freq = 1 if freq <= 0
    frame_samples = [(freq * FRAME_MILLISECONDS / 1000.0).to_i, 1].max
    frame_bytes = frame_samples * source_channels * 4
    buffer = "\0".b * frame_bytes
    loop do
      break if closed? || !@pipeline
      if !@processing_playing || @processing_paused
        sleep(FRAME_MILLISECONDS / 1000.0)
        next
      end
      read = Bass::BASS_ChannelGetData.call(read_channel, buffer, frame_bytes)
      if read.to_i <= 0
        @processing_playing = false if read.to_i == -1 || read.to_i == 0
        sleep(FRAME_MILLISECONDS / 1000.0)
        next
      end
      audio = buffer.byteslice(0, read).to_s.b
      channels_now = source_channels
      @effects_mutex.synchronize do
        @effects.each do |effect|
          audio = effect.process(audio, freq, channels_now).to_s.b
          channels_now = effect.output_channels(channels_now, freq) if effect.respond_to?(:output_channels)
        end
      end
      if audio.bytesize > 0
        written = Bass::BASS_StreamPutData.call(@playback_channel, audio, audio.bytesize)
        if written.to_i > 0 && @playback_channel.to_i != 0
          @processing_output_started = true
          Bass::BASS_ChannelPlay.call(@playback_channel, 0)
        end
      end
    end
  rescue Exception => e
    Log.error("Sound effect pipeline: #{e.class}: #{e.message}")
  end

  def reset_effects
    @effects_mutex.synchronize { @effects.each { |effect| effect.reset if effect.respond_to?(:reset) } }
  end
end
