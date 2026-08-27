# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "weakref"

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

class SoundDownloadStatus
  attr_reader :downloaded_bytes, :buffered_bytes, :file_size, :buffering_progress, :data_start_offset

  def initialize(downloaded_bytes:, buffered_bytes:, file_size:, connection_state:, buffering_progress:, data_start_offset:)
    @downloaded_bytes = downloaded_bytes
    @buffered_bytes = buffered_bytes
    @file_size = file_size
    @connection_state = connection_state
    @buffering_progress = buffering_progress
    @data_start_offset = data_start_offset
  end

  def connected?
    @connection_state == 1 || reconnecting?
  end

  def reconnecting?
    @connection_state == 2
  end

  def download_complete?
    return false if @downloaded_bytes == nil || @file_size == nil || @file_size <= 0
    @downloaded_bytes + @data_start_offset.to_i >= @file_size
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
            (0...content.bytesize / 2).each do |i|
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
      mapper.each do |d, o|
        f = t.find { |frame| frame.id == d }
        tgs[o] = f.strvalue if f != nil
      end
      chs = t.select { |frame| frame.id == "CHAP" }
      i = 0
      chs.each do |c|
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
      (0..999).each do |i|
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
      t.each do |f|
        if f.id == "CHAP" && f.subframes.size > 0
          c = Chapter.new
          c.time = f.numvalue / 1000.0
          c.name = ""
          f.subframes.each do |g|
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
      t.each do |r|
        return r.strvalue[0...r.strvalue.index("\0") || r.strvalue.size] if r.id == id3
      end
    end
    nil
  end
end

class SoundAttribute
  class UnsupportedOperation < StandardError; end

  NAME = nil
  ID = nil
  TARGET = :channel
  WRITABLE = true
  SLIDABLE = false

  attr_reader :sound

  def initialize
    @sound = nil
  end

  def attached?
    @sound != nil
  end

  def name
    self.class::NAME
  end

  def id
    self.class::ID
  end

  def target
    self.class::TARGET
  end

  def writable?
    self.class::WRITABLE
  end

  def slidable?
    self.class::SLIDABLE
  end

  def available?
    attached? && !value.nil?
  end

  def value
    attached_sound.__send__(:read_sound_attribute, self)
  end

  def value=(value)
    raise UnsupportedOperation, "#{self.class} is read-only" if !writable?
    prepare
    attached_sound.__send__(:write_sound_attribute, self, value)
  end

  def slide(value, duration:, logarithmic: false)
    raise UnsupportedOperation, "#{self.class} does not support slides" if !slidable?
    prepare
    attached_sound.__send__(:slide_sound_attribute, self, value, duration, logarithmic: logarithmic)
  end

  def sliding?
    return false if !slidable?
    attached_sound.__send__(:sound_attribute_sliding?, self)
  end

  def prepare
  end

  private

  def attach(sound)
    if @sound != nil && !@sound.equal?(sound)
      raise ArgumentError, "Sound attribute is already attached to another sound"
    end
    @sound = sound
    self
  end

  def detach(sound)
    @sound = nil if @sound.equal?(sound)
    self
  end

  def attached_sound
    raise RuntimeError, "Sound attribute is not attached" if @sound == nil
    @sound
  end
end

class VolumeSoundAttribute < SoundAttribute
  NAME = :volume
  ID = Bass::BASS_ATTRIB_VOL
  TARGET = :playback
  SLIDABLE = true
end

class PanSoundAttribute < SoundAttribute
  NAME = :pan
  ID = Bass::BASS_ATTRIB_PAN
  TARGET = :playback
  SLIDABLE = true
end

class FrequencySoundAttribute < SoundAttribute
  NAME = :frequency
  ID = Bass::BASS_ATTRIB_FREQ
  SLIDABLE = true
end

class TempoSoundAttribute < SoundAttribute
  NAME = :tempo
  ID = Bass::BASS_ATTRIB_TEMPO
  SLIDABLE = true

  def prepare
    attached_sound.__send__(:prepare_tempo_attribute)
  end
end

class PitchSoundAttribute < SoundAttribute
  NAME = :pitch
  ID = Bass::BASS_ATTRIB_TEMPO_PITCH
  SLIDABLE = true
end

class TempoFrequencySoundAttribute < SoundAttribute
  NAME = :tempo_frequency
  ID = Bass::BASS_ATTRIB_TEMPO_FREQ
  SLIDABLE = true
end

class SourceQualitySoundAttribute < SoundAttribute
  NAME = :source_quality
  ID = Bass::BASS_ATTRIB_SRC
  TARGET = :playback
end

class NetworkResumeSoundAttribute < SoundAttribute
  NAME = :network_resume
  ID = Bass::BASS_ATTRIB_NET_RESUME
  TARGET = :source
end

class NoRampSoundAttribute < SoundAttribute
  NAME = :no_ramp
  ID = Bass::BASS_ATTRIB_NORAMP
  TARGET = :playback
end

class BufferSoundAttribute < SoundAttribute
  NAME = :buffer
  ID = Bass::BASS_ATTRIB_BUFFER
  TARGET = :playback
end

class GranularitySoundAttribute < SoundAttribute
  NAME = :granularity
  ID = Bass::BASS_ATTRIB_GRANULE
  TARGET = :source
end

class TailSoundAttribute < SoundAttribute
  NAME = :tail
  ID = Bass::BASS_ATTRIB_TAIL
end

class DSPVolumeSoundAttribute < SoundAttribute
  NAME = :dsp_volume
  ID = Bass::BASS_ATTRIB_VOLDSP
end

class DSPVolumePrioritySoundAttribute < SoundAttribute
  NAME = :dsp_volume_priority
  ID = Bass::BASS_ATTRIB_VOLDSP_PRIORITY
end

class CPUUsageSoundAttribute < SoundAttribute
  NAME = :cpu_usage
  ID = Bass::BASS_ATTRIB_CPU
  WRITABLE = false
end

class BitrateSoundAttribute < SoundAttribute
  NAME = :bitrate
  ID = Bass::BASS_ATTRIB_BITRATE
  TARGET = :source
  WRITABLE = false
end

class SoundEffect
  def native?
    false
  end

  def latency_ms
    0.0
  end

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
  attr_reader :file, :channel, :source_channel, :sample_handle, :kind, :basefrequency, :effects, :effect_buffer, :effect_buffer_seconds, :spatial_effect

  SAMPLE_FLOAT = 0x100
  BASS_STREAM_DECODE = 0x200000
  BASS_UNICODE = 0x80000000
  BASS_SAMPLE_LOOP = 4
  BASS_DATA_AVAILABLE = 0
  BASS_CONFIG_UPDATE_PERIOD = 1
  BASS_ACTIVE_STOPPED = 0
  BASS_ACTIVE_PLAYING = 1
  MAX_SLIDE_MILLISECONDS = 0xffffffff
  FRAME_MILLISECONDS = 20
  FLOAT_SAMPLE_BYTES = 4
  EFFECT_QUEUE_POLL_SECONDS = FRAME_MILLISECONDS / 2000.0
  INTERACTIVE_EFFECT_BUFFER_SECONDS = FRAME_MILLISECONDS / 1000.0
  PCM_FORMATS = {
    s16le: [0, 2],
    float: [Bass::BASS_SAMPLE_FLOAT, 4],
    u8: [Bass::BASS_SAMPLE_8BITS, 1]
  }.freeze
  ATTRIBUTE_CLASSES = {
    volume: VolumeSoundAttribute,
    pan: PanSoundAttribute,
    frequency: FrequencySoundAttribute,
    tempo: TempoSoundAttribute,
    pitch: PitchSoundAttribute,
    tempo_frequency: TempoFrequencySoundAttribute,
    source_quality: SourceQualitySoundAttribute,
    network_resume: NetworkResumeSoundAttribute,
    no_ramp: NoRampSoundAttribute,
    buffer: BufferSoundAttribute,
    granularity: GranularitySoundAttribute,
    tail: TailSoundAttribute,
    dsp_volume: DSPVolumeSoundAttribute,
    dsp_volume_priority: DSPVolumePrioritySoundAttribute,
    cpu_usage: CPUUsageSoundAttribute,
    bitrate: BitrateSoundAttribute
  }.freeze
  @@finalizers = {}

  def self.open_pcm(frequency:, channels:, type:, buffer:)
    sound = allocate
    sound.__send__(:initialize_pcm, frequency: frequency, channels: channels, type: type, buffer: buffer)
  end

  # :interactive selects a safe bounded buffer. Nil and :eager preserve eager buffering.
  # effect_buffer_seconds remains available for advanced callers.
  def initialize(file = nil, sample: false, loop: false, stream: nil, effect_buffer: nil, effect_buffer_seconds: nil)
    initialize_sound_state(
      file: file,
      sample: sample,
      loop: loop,
      stream: stream,
      effect_buffer: effect_buffer,
      effect_buffer_seconds: effect_buffer_seconds
    )
    open_direct
    finish_initialization
  end

  def initialize_sound_state(file:, sample:, loop:, stream:, effect_buffer:, effect_buffer_seconds:)
    @file = file
    @stream_data = stream
    @sample = sample == true
    @looper = loop == true
    @pcm_type = nil
    @pcm_sample_bytes = nil
    @pcm_frame_bytes = nil
    configure_effect_buffer(effect_buffer, effect_buffer_seconds)
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
    @sound_attributes = {}
    @slide_event_id = nil
    @slide_event_listeners = []
    @active_slides = {}
    @slide_mutex = Mutex.new
    @pipeline = false
    @processing_thread = nil
    @processing_playing = false
    @processing_paused = false
    @processing_output_started = false
    @effect_playback_mutex = Mutex.new
    @effect_output_bytes_written = 0
    @effect_output_bytes_per_second = 0.0
    @effect_playback_output_seconds = 0.0
    @effect_output_latency_seconds = 0.0
    @effect_playback_clock_at = nil
    @effect_playback_clock_running = false
    @spatial_automation_mutex = Mutex.new
    @spatial_automation = nil
  end

  def finish_initialization
    @basefrequency = frequency
    Bass::BASS_ChannelFlags.call(@channel, BASS_STREAM_DECODE, BASS_STREAM_DECODE) if @channel.to_i != 0
    Bass::BASS_ChannelFlags.call(@channel, BASS_SAMPLE_LOOP, BASS_SAMPLE_LOOP) if @looper && @channel.to_i != 0
    @finalizer_id = object_id
    update_finalizer
    ObjectSpace.define_finalizer(self, self.class.finalizer(@finalizer_id))
    self
  end

  private :initialize_sound_state, :finish_initialization

  def self.finalizer(id)
    proc do
      begin
        entry = @@finalizers.delete(id)
        next if entry == nil
        sample_handle, source_channel, channel, playback_channel, source_mixer, kind, slide_event_id = entry
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
        unregister_slide_event_sound(slide_event_id)
      rescue Exception
      end
    end
  end

  def self.free_stream_handle(handle)
    Bass.free_stream(handle)
  end

  def self.register_slide_event_sound(sound)
    slide_event_registry_mutex.synchronize do
      @slide_event_sequence = @slide_event_sequence.to_i + 1
      @slide_event_registry ||= {}
      @slide_event_registry[@slide_event_sequence] = WeakRef.new(sound)
      @slide_event_sequence
    end
  end

  def self.unregister_slide_event_sound(event_id)
    return if event_id == nil
    slide_event_registry_mutex.synchronize { (@slide_event_registry ||= {}).delete(event_id.to_i) }
    nil
  end

  def self.update_slide_events
    registry = @slide_event_registry
    return 0 if registry == nil || registry.empty?
    slide_event_sounds.sum { |sound| sound.__send__(:poll_slide_completions) }
  end

  def self.slide_event_registry_mutex
    @slide_event_registry_mutex ||= Mutex.new
  end

  def self.slide_event_sounds
    entries = slide_event_registry_mutex.synchronize { (@slide_event_registry ||= {}).to_a }
    entries.filter_map do |event_id, reference|
      reference.__getobj__
    rescue WeakRef::RefError
      unregister_slide_event_sound(event_id)
      nil
    end
  end

  def effect_buffer_seconds=(value)
    @effect_buffer = nil
    @effect_buffer_seconds = normalize_effect_buffer_seconds(value)
  end

  def effect_buffer=(value)
    @effect_buffer = normalize_effect_buffer(value)
    @effect_buffer_seconds = @effect_buffer == :interactive ? INTERACTIVE_EFFECT_BUFFER_SECONDS : nil
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
    Bass::BASS_ChannelFlags.call(@source_channel, BASS_SAMPLE_LOOP, BASS_SAMPLE_LOOP) if @looper
    self.position = position if position > 0
    @basefrequency = frequency
    @processing_frequency = pipeline_output_frequency
    @processing_channels = [[channels.to_i, 1].max, 2].min
    @processing_channel = build_effect_source_channel(@processing_frequency, @processing_channels)
    @playback_channels = pipeline_output_channels(@processing_frequency, @processing_channels)
    @playback_channel = Bass::BASS_StreamCreate.call(@processing_frequency, @playback_channels, SAMPLE_FLOAT, -1, nil)
    reset_effect_playback_state(@processing_frequency, @playback_channels)
    update_finalizer
  end

  def opened?
    @channel.to_i != 0 && !closed?
  end

  def playing?
    status.playing?
  end

  def finished?
    closed? || status.stopped?
  end

  def wait
    loop_update until finished?
    self
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

  def write_pcm(buffer)
    raise RuntimeError, "Sound is not a PCM push stream" if @kind != :pcm
    raise RuntimeError, "Cannot write PCM data to a closed sound" if !opened?
    data = pcm_buffer(buffer)
    return 0 if data.empty?
    if data.bytesize % @pcm_frame_bytes != 0
      raise ArgumentError, "PCM data must contain complete sample frames (#{@pcm_frame_bytes} bytes per frame)"
    end

    queued = Bass::BASS_StreamPutData.call(@source_channel, data, data.bytesize).to_i
    raise RuntimeError, "Cannot write PCM data: #{Bass.error_name}" if queued < 0
    data.bytesize
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

  def download_status
    return nil if closed? || @file == nil || !@file.to_s.downcase.start_with?("http://", "https://")
    source = @source_channel.to_i
    source = @channel.to_i if source == 0
    return nil if source == 0

    downloaded = stream_file_position(source, Bass::BASS_FILEPOS_DOWNLOAD)
    buffered = stream_file_position(source, Bass::BASS_FILEPOS_BUFFER)
    file_size = stream_file_position(source, Bass::BASS_FILEPOS_SIZE)
    connection_state = stream_file_position(source, Bass::BASS_FILEPOS_CONNECTED)
    buffering_remaining = stream_file_position(source, Bass::BASS_FILEPOS_BUFFERING)
    data_start_offset = stream_file_position(source, Bass::BASS_FILEPOS_START)
    return nil if [downloaded, buffered, file_size, connection_state, buffering_remaining, data_start_offset].all?(&:nil?)
    buffering_progress = buffering_remaining == nil ? nil : [[100 - buffering_remaining, 0].max, 100].min

    SoundDownloadStatus.new(
      downloaded_bytes: downloaded,
      buffered_bytes: buffered,
      file_size: file_size,
      connection_state: connection_state,
      buffering_progress: buffering_progress,
      data_start_offset: data_start_offset
    )
  rescue Exception
    nil
  end

  def play
    return if !opened?
    if @pipeline
      was_paused = @processing_paused
      @processing_playing = true
      ensure_processing_thread
      if was_paused && @processing_output_started && @playback_channel.to_i != 0
        resumed = Bass::BASS_ChannelPlay.call(@playback_channel, 0).to_i != 0
        start_effect_playback_clock if resumed
      end
      @processing_paused = false
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
      reset_effect_playback_state(@processing_frequency, @playback_channels)
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
      pause_effect_playback_clock
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
    native = native_effect?(effect)
    raise RuntimeError, "Frame effects cannot be attached to PCM push streams" if @kind == :pcm && !native
    if native && @kind == :sample
      raise RuntimeError, "Native effects cannot be attached to sample sounds"
    end
    if native && @effects_mutex.synchronize { @effects.include?(effect) }
      raise ArgumentError, "Sound effect is already attached"
    end
    effect.__send__(:attach, self) if native
    @effects_mutex.synchronize { @effects << effect }
    if native
      begin
        if !effect.__send__(:bind, native_effect_channel)
          raise RuntimeError, "Cannot attach effect to an unopened sound"
        end
      rescue Exception
        @effects_mutex.synchronize { @effects.delete(effect) }
        effect.__send__(:detach, self)
        raise
      end
    else
      rebuild_effect_pipeline
    end
    effect
  end

  def effect_remove(effect)
    removed = false
    @effects_mutex.synchronize { removed = @effects.delete(effect) != nil }
    @spatial_effect = nil if removed && @spatial_effect.equal?(effect)
    effect.close if removed && effect.respond_to?(:close)
    rebuild_effect_pipeline if removed && !native_effect?(effect)
    removed
  end

  def effects_latency_ms
    update_period = [Bass::BASS_GetConfig.call(BASS_CONFIG_UPDATE_PERIOD).to_f, 0.0].max
    effects = @effects_mutex.synchronize { @effects.dup }
    update_period + effects.sum { |effect| declared_effect_latency_ms(effect) }
  end

  def effect_playback_seconds
    return 0.0 if !@pipeline || @playback_channel.to_i == 0

    output_seconds = effect_playback_output_seconds
    [output_seconds - effect_total_latency_seconds, 0.0].max
  rescue Exception
    0.0
  end

  def effect_playback_seconds_at(time)
    seconds = effect_playback_seconds
    requested = Float(time)
    return seconds if !requested.finite?

    now = monotonic_time
    seconds += requested - now if effect_output_advancing?
    [[seconds, 0.0].max, effect_playback_max_source_seconds].min
  rescue ArgumentError, TypeError
    effect_playback_seconds
  end

  def spatialize(position: nil, interpolation: :bilinear)
    fail(RuntimeError, "Audio3DEffect is unavailable") if !defined?(::Audio3DEffect)
    position = Audio3DEffect::ORIGIN if position == nil
    if @spatial_effect == nil || !@effects.include?(@spatial_effect)
      effect = Audio3DEffect.new(position: position, interpolation: interpolation)
      effect_add(effect)
      @spatial_effect = effect
    else
      @spatial_effect.position = position
      @spatial_effect.interpolation = interpolation
    end
    self
  end

  def spatial?
    @spatial_effect != nil && @effects.include?(@spatial_effect)
  end

  def spatial_position
    spatial? ? @spatial_effect.position : nil
  end

  def spatial_position=(position)
    cancel_spatial_position_slide
    spatial? ? @spatial_effect.position = position : spatialize(position: position)
    position
  end

  def spatial_interpolation
    spatial? ? @spatial_effect.interpolation : nil
  end

  def spatial_interpolation=(interpolation)
    spatial? ? @spatial_effect.interpolation = interpolation : spatialize(interpolation: interpolation)
    interpolation
  end

  def spatial_position_slide(position, duration:, from: nil, start_at: 0.0)
    duration = Float(duration)
    start_at = Float(start_at)
    raise ArgumentError, "duration must be a positive finite number" if !duration.finite? || duration <= 0.0
    raise ArgumentError, "start_at must be a non-negative finite number" if !start_at.finite? || start_at < 0.0

    origin = from == nil ? spatial_position : from
    origin = Audio3DEffect::ORIGIN if origin == nil && defined?(::Audio3DEffect)
    origin = normalize_spatial_coordinates(origin)
    target = normalize_spatial_coordinates(position)
    spatialize(position: origin) if !spatial?
    @spatial_effect.position = origin
    @spatial_automation_mutex.synchronize do
      @spatial_automation = {
        :from => origin.freeze,
        :to => target.freeze,
        :start_at => start_at,
        :duration => duration
      }
    end
    self
  end

  def spatial_position_sliding?
    @spatial_automation_mutex.synchronize { @spatial_automation != nil }
  end

  def cancel_spatial_position_slide
    @spatial_automation_mutex.synchronize do
      active = @spatial_automation != nil
      @spatial_automation = nil
      active
    end
  end

  def despatialize
    cancel_spatial_position_slide
    effect_remove(@spatial_effect) if spatial?
    self
  end

  def close
    return if @closed
    self.class.unregister_slide_event_sound(@slide_event_id)
    @slide_event_id = nil
    @slide_mutex.synchronize do
      @active_slides.clear
      @slide_event_listeners.clear
    end
    @closed = true
    @processing_playing = false
    @processing_output_started = false
    @processing_thread.kill if @processing_thread != nil && @processing_thread.alive?
    @processing_thread = nil
    @effects_mutex.synchronize { @effects.each { |effect| effect.close if effect.respond_to?(:close) } }
    @sound_attributes.each_value { |attribute| attribute.__send__(:detach, self) }
    @sound_attributes.clear
    close_native_handles
    @sample_handle = 0
    @source_channel = 0
    @source_mixer = 0
    @channel = 0
    @playback_channel = 0
    @processing_channel = 0
    @processing_frequency = nil
    @processing_channels = 0
    @spatial_effect = nil
    @spatial_automation_mutex.synchronize { @spatial_automation = nil }
    reset_effect_playback_state
    @@finalizers.delete(@finalizer_id)
    nil
  end

  def closed?
    @closed == true
  end

  def attribute(name)
    name = name.to_sym if name.respond_to?(:to_sym)
    return @sound_attributes[name] if @sound_attributes.key?(name)
    attribute_class = ATTRIBUTE_CLASSES[name]
    raise ArgumentError, "Unknown sound attribute #{name.inspect}" if attribute_class == nil
    attribute_add(attribute_class.new)
  end

  def attribute_add(attribute)
    raise ArgumentError, "Sound attribute must inherit from SoundAttribute" if !attribute.is_a?(SoundAttribute)
    raise ArgumentError, "Sound attribute must define NAME and ID" if attribute.name == nil || attribute.id == nil

    name = attribute.name.to_sym
    previous = @sound_attributes[name]
    return attribute if previous.equal?(attribute)
    attribute.__send__(:attach, self)
    if previous != nil
      cancel_tracked_slide(sound_attribute_channel(previous), previous.id)
      previous.__send__(:detach, self)
    end
    @sound_attributes[name] = attribute
    attribute
  end

  def attribute_remove(attribute)
    name = attribute.is_a?(SoundAttribute) ? attribute.name : attribute
    name = name.to_sym if name.respond_to?(:to_sym)
    current = @sound_attributes[name]
    return false if current == nil || (attribute.is_a?(SoundAttribute) && !current.equal?(attribute))

    target = sound_attribute_channel(current)
    cancel_tracked_slide(target, current.id)
    @sound_attributes.delete(name)
    current.__send__(:detach, self)
    release_slide_event_registration_if_unused
    true
  end

  ATTRIBUTE_CLASSES.each_key do |name|
    define_method("#{name}_attribute") { attribute(name) }
  end

  def on(event, &block)
    raise ArgumentError, "Sound#on requires a block" if block == nil
    raise ArgumentError, "Unknown sound event #{event.inspect}" if event.to_sym != :slide_end

    first_listener = @slide_mutex.synchronize do
      first = @slide_event_listeners.empty?
      @slide_event_listeners << block
      first
    end
    track_active_attribute_slides if first_listener
    block
  end

  def fade_in(duration, to: 1.0, logarithmic: false, play: true)
    self.volume = 0.0
    self.play if play
    volume_attribute.slide(to.to_f, duration: duration, logarithmic: logarithmic) ? self : false
  end

  def fade_out(duration, stop: true, logarithmic: false)
    result = volume_attribute.slide(stop ? -1.0 : 0.0, duration: duration, logarithmic: logarithmic)
    result ? self : false
  end

  def frequency
    (frequency_attribute.value || 0.0).to_i
  end

  def frequency=(value)
    frequency_attribute.value = value.to_f
  end

  def pan
    (pan_attribute.value || 0.0).to_f
  end

  def pan=(value)
    pan_attribute.value = value.to_f
  end

  def tempo
    (tempo_attribute.value || 0.0).to_f
  end

  def tempo=(value)
    tempo_attribute.value = value.to_f
  end

  def pitch
    (pitch_attribute.value || 0.0).to_f
  end

  def pitch=(value)
    pitch_attribute.value = value.to_f
  end

  def volume
    (volume_attribute.value || 0.0).to_f
  end

  def volume=(value)
    volume_attribute.value = value.to_f
  end

  def new_channel
    return nil if @kind != :sample || @sample_handle.to_i == 0
    cancel_all_tracked_slides
    unbind_native_effects
    @channel = Bass::BASS_SampleGetChannel.call(@sample_handle, 0)
    Bass::BASS_ChannelFlags.call(@channel, BASS_SAMPLE_LOOP, BASS_SAMPLE_LOOP) if @looper
    bind_native_effects
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
    return @pcm_sample_bytes * 8 if @kind == :pcm
    flags = info_values[2].to_i
    return 32 if (flags & SAMPLE_FLOAT) != 0
    bits = info_values[5].to_i
    bits > 0 ? bits : 16
  end

  def type
    return @pcm_type if @kind == :pcm
    return :float if bitrate == 32 && (info_values[2].to_i & SAMPLE_FLOAT) != 0
    "s#{bitrate}le".to_sym
  end

  private

  def initialize_pcm(frequency:, channels:, type:, buffer:)
    frequency = Integer(frequency)
    channels = Integer(channels)
    raise ArgumentError, "PCM frequency must be positive" if frequency <= 0
    raise ArgumentError, "PCM channels must be between 1 and 8" if channels < 1 || channels > 8
    type = type.to_sym if type.respond_to?(:to_sym)
    format = PCM_FORMATS[type]
    raise ArgumentError, "Unsupported PCM type #{type.inspect}" if format == nil
    data = pcm_buffer(buffer)
    frame_bytes = format[1] * channels
    if data.bytesize % frame_bytes != 0
      raise ArgumentError, "PCM data must contain complete sample frames (#{frame_bytes} bytes per frame)"
    end

    initialize_sound_state(
      file: nil,
      sample: false,
      loop: false,
      stream: nil,
      effect_buffer: nil,
      effect_buffer_seconds: nil
    )
    @pcm_type = type
    @pcm_sample_bytes = format[1]
    @pcm_frame_bytes = frame_bytes
    @source_channel, @channel = Bass.create_push_stream_channel(frequency, channels, format[0])
    raise RuntimeError, "Cannot create PCM stream: #{Bass.error_name}" if @channel.to_i == 0
    @kind = :pcm
    finish_initialization
    write_pcm(data)
    self
  rescue Exception
    close if instance_variable_defined?(:@closed) && !closed?
    raise
  end

  def pcm_buffer(buffer)
    raise TypeError, "PCM buffer must be a string" if !buffer.respond_to?(:to_str)
    buffer.to_str.b
  end

  def update_finalizer
    @@finalizers[@finalizer_id] = [@sample_handle, @source_channel, @channel, @playback_channel, @source_mixer, @kind, @slide_event_id]
  end

  def playback_attribute_channel
    @pipeline && @playback_channel.to_i != 0 ? @playback_channel : @channel
  end

  def sound_attribute_channel(attribute)
    case attribute.target
    when :playback
      playback_attribute_channel
    when :source
      @source_channel.to_i != 0 ? @source_channel : @channel
    else
      @channel
    end
  end

  def info_values
    return @info_values if @info_values != nil && @info_values_channel == @channel
    buffer = EltenBassStructs.bass_channel_info_buffer
    Bass::BASS_ChannelGetInfo.call(@channel, buffer) if @channel.to_i != 0
    @info_values = EltenBassStructs.bass_channel_info_values(buffer)
    @info_values_channel = @channel
    @info_values
  end

  def stream_file_position(channel, mode)
    value = Bass::BASS_StreamGetFilePosition.call(channel, mode).to_i
    value < 0 || value == 0xffffffffffffffff ? nil : value
  end

  def read_sound_attribute(attribute)
    target = sound_attribute_channel(attribute)
    return nil if target.to_i == 0 || closed?
    buffer = [0.0].pack("f")
    return nil if Bass::BASS_ChannelGetAttribute.call(target, attribute.id, buffer) == 0
    buffer.unpack1("f").to_f
  end

  def write_sound_attribute(attribute, value)
    target = sound_attribute_channel(attribute)
    return nil if target.to_i == 0 || closed?
    result = Bass::BASS_ChannelSetAttribute.call(target, attribute.id, value.to_f)
    result == 0 ? nil : value.to_f
  end

  def slide_sound_attribute(attribute, value, duration, logarithmic: false)
    target = sound_attribute_channel(attribute)
    return false if target.to_i == 0 || closed?
    seconds = Float(duration)
    target_value = Float(value)
    raise ArgumentError, "duration must be a positive finite number" if !seconds.finite? || seconds <= 0.0
    raise ArgumentError, "duration exceeds the BASS slide limit" if seconds > MAX_SLIDE_MILLISECONDS / 1000.0
    raise ArgumentError, "slide value must be finite" if !target_value.finite?

    tracked = @slide_mutex.synchronize { !@slide_event_listeners.empty? }
    attribute_id = attribute.id
    attribute_id |= Bass::BASS_SLIDE_LOG if logarithmic
    milliseconds = [(seconds * 1000.0).round, 1].max
    raise ArgumentError, "duration exceeds the BASS slide limit" if milliseconds > MAX_SLIDE_MILLISECONDS
    result = Bass::BASS_ChannelSlideAttribute.call(target, attribute_id, target_value, milliseconds) != 0
    if result && tracked
      @slide_mutex.synchronize { @active_slides[[target, attribute.id]] = attribute }
      ensure_slide_event_registration
    elsif !result
      release_slide_event_registration_if_unused
    end
    result
  end

  def sound_attribute_sliding?(attribute)
    target = sound_attribute_channel(attribute)
    return false if target.to_i == 0 || closed?
    Bass::BASS_ChannelIsSliding.call(target, attribute.id) != 0
  end

  def prepare_tempo_attribute
    return if !opened? || @tempo_prepared_channel == @channel
    Bass::BASS_ChannelSetAttribute.call(@channel, Bass::BASS_ATTRIB_TEMPO_OPTION_SEQUENCE_MS, 60)
    Bass::BASS_ChannelSetAttribute.call(@channel, Bass::BASS_ATTRIB_TEMPO_OPTION_USE_QUICKALGO, 1)
    @tempo_prepared_channel = @channel
  end

  def ensure_slide_event_registration
    return false if closed?
    if @slide_event_id == nil
      @slide_event_id = self.class.register_slide_event_sound(self)
      update_finalizer
    end
    true
  end

  def track_active_attribute_slides
    tracked = false
    @sound_attributes.each_value do |attribute|
      next if !attribute.slidable?
      target = sound_attribute_channel(attribute)
      next if target.to_i == 0 || Bass::BASS_ChannelIsSliding.call(target, attribute.id) == 0
      @slide_mutex.synchronize { @active_slides[[target, attribute.id]] ||= attribute }
      tracked = true
    end
    ensure_slide_event_registration if tracked
    tracked
  end

  def cancel_tracked_slide(channel, attribute_id)
    @slide_mutex.synchronize { @active_slides.delete([channel.to_i, attribute_id.to_i]) }
  end

  def cancel_all_tracked_slides
    @slide_mutex.synchronize { @active_slides.clear }
    release_slide_event_registration_if_unused
  end

  def handle_slide_completion(channel, attribute_id)
    key = [channel.to_i, attribute_id.to_i]
    record = @slide_mutex.synchronize { @active_slides[key] }
    return false if record == nil
    return false if Bass::BASS_ChannelIsSliding.call(channel.to_i, attribute_id.to_i) != 0

    listeners = nil
    record = @slide_mutex.synchronize do
      current = @active_slides[key]
      if current.equal?(record)
        @active_slides.delete(key)
        listeners = @slide_event_listeners.dup
        current
      end
    end
    return false if record == nil
    listeners.each do |listener|
      begin
        listener.call(record)
      rescue Exception => e
        Log.warning("Sound slide event failed: #{e.class}: #{e.message}") if defined?(Log)
      end
    end
    release_slide_event_registration_if_unused
    true
  end

  def poll_slide_completions
    slides = @slide_mutex.synchronize { @active_slides.keys }
    slides.count { |channel, attribute_id| handle_slide_completion(channel, attribute_id) }
  end

  def release_slide_event_registration_if_unused
    needed = @slide_mutex.synchronize { !@active_slides.empty? }
    return if needed || @slide_event_id == nil
    self.class.unregister_slide_event_sound(@slide_event_id)
    @slide_event_id = nil
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
    cancel_all_tracked_slides
    unbind_native_effects
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
    @tempo_prepared_channel = nil
    @info_values = nil
    reset_effect_playback_state
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
      if frame_effects.empty?
        close_native_handles
        @pipeline = false
        open_direct
      else
        @pipeline = true
        open_effect_source(pos)
      end
      bind_native_effects
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
        next if native_effect?(effect)
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
        next if native_effect?(effect)
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
    frame_bytes = frame_samples * source_channels * FLOAT_SAMPLE_BYTES
    output_channels = @playback_channels.to_i
    output_channels = source_channels if output_channels <= 0
    output_frame_bytes = frame_samples * output_channels * FLOAT_SAMPLE_BYTES
    buffer = "\0".b * frame_bytes
    loop do
      break if closed? || !@pipeline
      if !@processing_playing || @processing_paused
        sleep(FRAME_MILLISECONDS / 1000.0)
        next
      end
      if effect_queue_full?(output_frame_bytes, freq, output_channels)
        start_effect_output if @effect_buffer_seconds != nil
        sleep(EFFECT_QUEUE_POLL_SECONDS)
        next
      end
      read = Bass::BASS_ChannelGetData.call(read_channel, buffer, frame_bytes)
      if read.to_i <= 0
        if Bass::BASS_ChannelIsActive.call(read_channel).to_i == BASS_ACTIVE_STOPPED
          start_effect_output if @effect_buffer_seconds != nil
          end_effect_output
          @processing_playing = false
        end
        sleep(FRAME_MILLISECONDS / 1000.0)
        next
      end
      audio = buffer.byteslice(0, read).to_s.b
      frame_duration = read.to_f / ([freq, 1].max * [source_channels, 1].max * FLOAT_SAMPLE_BYTES)
      apply_spatial_automation(effect_output_written_seconds, frame_duration)
      channels_now = source_channels
      @effects_mutex.synchronize do
        @effects.each do |effect|
          next if native_effect?(effect)
          audio = effect.process(audio, freq, channels_now).to_s.b
          channels_now = effect.output_channels(channels_now, freq) if effect.respond_to?(:output_channels)
        end
      end
      if audio.bytesize > 0
        written = Bass::BASS_StreamPutData.call(@playback_channel, audio, audio.bytesize)
        track_effect_output_bytes(audio.bytesize) if written.to_i >= 0
        if written.to_i > 0 && @playback_channel.to_i != 0
          if @effect_buffer_seconds == nil
            start_effect_output
          end
        end
      end
    end
  rescue Exception => e
    Log.error("Sound effect pipeline: #{e.class}: #{e.message}")
  end

  def reset_effects
    @effects_mutex.synchronize { @effects.each { |effect| effect.reset if effect.respond_to?(:reset) } }
  end

  def native_effect?(effect)
    effect.respond_to?(:native?) && effect.native? == true
  end

  def declared_effect_latency_ms(effect)
    return 0.0 if !effect.respond_to?(:latency_ms)

    latency = Float(effect.latency_ms)
    latency.finite? && latency > 0.0 ? latency : 0.0
  rescue StandardError
    0.0
  end

  def frame_effects
    @effects_mutex.synchronize { @effects.reject { |effect| native_effect?(effect) } }
  end

  def native_effects
    @effects_mutex.synchronize { @effects.select { |effect| native_effect?(effect) } }
  end

  def native_effect_channel
    @pipeline && @playback_channel.to_i != 0 ? @playback_channel : @channel
  end

  def bind_native_effects
    channel = native_effect_channel
    native_effects.each { |effect| effect.__send__(:bind, channel) }
  end

  def unbind_native_effects
    native_effects.each { |effect| effect.__send__(:unbind) }
  end

  def reset_effect_playback_state(frequency = nil, channels = nil)
    bytes_per_second = [frequency.to_i, 0].max * [channels.to_i, 0].max * FLOAT_SAMPLE_BYTES
    @effect_playback_mutex.synchronize do
      @effect_output_bytes_written = 0
      @effect_output_bytes_per_second = bytes_per_second.to_f
      @effect_playback_output_seconds = 0.0
      @effect_output_latency_seconds = 0.0
      @effect_playback_clock_at = nil
      @effect_playback_clock_running = false
    end
  end

  def track_effect_output_bytes(bytes)
    @effect_playback_mutex.synchronize { @effect_output_bytes_written += [bytes.to_i, 0].max }
  end

  def effect_output_written_seconds
    written, bytes_per_second = @effect_playback_mutex.synchronize do
      [@effect_output_bytes_written.to_i, @effect_output_bytes_per_second.to_f]
    end
    bytes_per_second > 0.0 ? written / bytes_per_second : 0.0
  end

  def effect_playback_output_seconds
    now = monotonic_time
    advancing = effect_output_advancing?
    @effect_playback_mutex.synchronize do
      update_effect_playback_clock_locked(now, advancing)
      @effect_playback_output_seconds
    end
  end

  def effect_playback_max_source_seconds
    [effect_output_written_seconds - effect_total_latency_seconds, 0.0].max
  end

  def start_effect_playback_clock
    now = monotonic_time
    output_latency = effect_device_output_latency_seconds
    @effect_playback_mutex.synchronize do
      update_effect_playback_clock_locked(now, @effect_playback_clock_running)
      @effect_output_latency_seconds = output_latency
      @effect_playback_clock_at = now
      @effect_playback_clock_running = true
    end
  end

  def pause_effect_playback_clock
    now = monotonic_time
    @effect_playback_mutex.synchronize do
      update_effect_playback_clock_locked(now, @effect_playback_clock_running)
      @effect_playback_clock_at = nil
      @effect_playback_clock_running = false
    end
  end

  def update_effect_playback_clock_locked(now, advancing)
    if advancing && @effect_playback_clock_running && @effect_playback_clock_at != nil
      elapsed = now.to_f - @effect_playback_clock_at.to_f
      @effect_playback_output_seconds += elapsed if elapsed.finite? && elapsed > 0.0
    end
    @effect_playback_clock_at = now if @effect_playback_clock_running
    bytes_per_second = @effect_output_bytes_per_second.to_f
    maximum = bytes_per_second > 0.0 ? @effect_output_bytes_written.to_i / bytes_per_second : 0.0
    @effect_playback_output_seconds = @effect_playback_output_seconds.clamp(0.0, maximum)
  end

  def effect_output_advancing?
    return false if @processing_paused || !@processing_output_started || @playback_channel.to_i == 0
    Bass::BASS_ChannelIsActive.call(@playback_channel).to_i == BASS_ACTIVE_PLAYING
  rescue Exception
    false
  end

  def effect_processing_latency_seconds
    effects = @effects_mutex.synchronize { @effects.dup }
    effects.sum { |effect| declared_effect_latency_ms(effect) } / 1000.0
  rescue Exception
    0.0
  end

  def effect_total_latency_seconds
    output_latency = @effect_playback_mutex.synchronize { @effect_output_latency_seconds.to_f }
    output_latency + effect_processing_latency_seconds
  end

  def effect_device_output_latency_seconds
    buffer = "\0".b * 56
    return 0.0 if Bass::BASS_GetInfo.call(buffer).to_i == 0

    latency = buffer.byteslice(40, 4).to_s.unpack1("L<").to_f / 1000.0
    latency.finite? && latency > 0.0 ? latency : 0.0
  rescue Exception
    0.0
  end

  def apply_spatial_automation(frame_start, frame_duration)
    automation = @spatial_automation_mutex.synchronize { @spatial_automation }
    return if automation == nil || !spatial?

    frame_time = frame_start.to_f + [frame_duration.to_f, 0.0].max / 2.0
    elapsed = frame_time - automation[:start_at]
    progress = (elapsed / automation[:duration]).clamp(0.0, 1.0)
    position = automation[:from].zip(automation[:to]).map do |origin, target|
      origin + (target - origin) * progress
    end
    @spatial_effect.position = position
    if progress >= 1.0
      @spatial_automation_mutex.synchronize do
        @spatial_automation = nil if @spatial_automation.equal?(automation)
      end
    end
  end

  def normalize_spatial_coordinates(position)
    coordinates = Array(position)
    raise ArgumentError, "position must contain three numeric coordinates" if coordinates.size < 3
    coordinates.first(3).map do |coordinate|
      value = Float(coordinate)
      raise ArgumentError, "position coordinates must be finite" if !value.finite?
      value
    end
  rescue TypeError
    raise ArgumentError, "position must contain three numeric coordinates"
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def effect_queue_full?(next_frame_bytes, frequency, channels)
    seconds = @effect_buffer_seconds
    return false if seconds == nil || @playback_channel.to_i == 0

    pending_bytes = effect_pending_bytes
    bytes_per_second = [frequency.to_i, 1].max * [channels.to_i, 1].max * FLOAT_SAMPLE_BYTES
    update_milliseconds = Bass::BASS_GetConfig.call(BASS_CONFIG_UPDATE_PERIOD).to_i
    minimum_seconds = ([update_milliseconds, 0].max + FRAME_MILLISECONDS) / 1000.0
    limit_seconds = [seconds, minimum_seconds].max
    limit_bytes = [(limit_seconds * bytes_per_second).round, next_frame_bytes.to_i].max
    pending_bytes + next_frame_bytes.to_i > limit_bytes
  rescue Exception
    false
  end

  def effect_pending_bytes
    queued = Bass::BASS_StreamPutData.call(@playback_channel, nil, 0).to_i
    buffered = Bass::BASS_ChannelGetData.call(@playback_channel, nil, BASS_DATA_AVAILABLE).to_i
    [queued, 0].max + [buffered, 0].max
  end

  def start_effect_output
    return if @playback_channel.to_i == 0
    if @processing_output_started
      active = Bass::BASS_ChannelIsActive.call(@playback_channel).to_i
      return if active != BASS_ACTIVE_STOPPED
    end
    @processing_output_started = Bass::BASS_ChannelPlay.call(@playback_channel, 0).to_i != 0
    start_effect_playback_clock if @processing_output_started
  rescue Exception
    @processing_output_started = false
  end

  def end_effect_output
    return true if @playback_channel.to_i == 0
    queued = Bass::BASS_StreamPutData.call(@playback_channel, nil, Bass::BASS_STREAMPROC_END).to_i
    return true if queued >= 0

    Log.error("Cannot end Sound effect output: #{Bass.error_name}")
    Bass::BASS_ChannelStop.call(@playback_channel)
    false
  rescue Exception => e
    Log.error("Cannot end Sound effect output: #{e.class}: #{e.message}")
    Bass::BASS_ChannelStop.call(@playback_channel) if @playback_channel.to_i != 0
    false
  end

  def normalize_effect_buffer_seconds(value)
    return nil if value == nil

    seconds = Float(value)
    raise ArgumentError if !seconds.finite? || seconds <= 0.0
    seconds
  rescue ArgumentError, TypeError
    raise ArgumentError, "effect_buffer_seconds must be nil or a positive finite number"
  end

  def normalize_effect_buffer(value)
    return nil if value == nil

    preset = value.respond_to?(:to_sym) ? value.to_sym : nil
    return preset if [:eager, :interactive].include?(preset)
    raise ArgumentError, "effect_buffer must be nil, :eager, or :interactive"
  end

  def configure_effect_buffer(preset, seconds)
    if preset != nil && seconds != nil
      raise ArgumentError, "effect_buffer and effect_buffer_seconds cannot be used together"
    end
    preset == nil ? self.effect_buffer_seconds = seconds : self.effect_buffer = preset
  end
end
