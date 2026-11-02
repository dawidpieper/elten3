# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class Audio3DEffect < SoundEffect
  attr_reader :x, :y, :z, :bilinear, :frequency, :hrtf_profile

  DEFAULT_FREQUENCY = 48_000
  DEFAULT_FRAMESIZE = 20
  OUTPUT_CHANNELS = 2
  POSITION_MIN = -1.0
  POSITION_MAX = 1.0
  ORIGIN = [0.0, 0.0, 0.0].freeze
  FORWARD = [0.0, 0.0, -1.0].freeze
  BACK = [0.0, 0.0, 1.0].freeze
  LEFT = [-1.0, 0.0, 0.0].freeze
  RIGHT = [1.0, 0.0, 0.0].freeze
  UP = [0.0, 1.0, 0.0].freeze
  DOWN = [0.0, -1.0, 0.0].freeze

  @@engine_mutex = Mutex.new
  @@engines = {}

  class << self
    def load(frequency = DEFAULT_FREQUENCY, framesize = DEFAULT_FRAMESIZE)
      engine(frequency, framesize) != nil
    end

    def loaded?
      !@@engines.empty?
    end

    def free
      @@engine_mutex.synchronize { free_locked }
    end

    def engine(frequency = DEFAULT_FREQUENCY, framesize = DEFAULT_FRAMESIZE)
      frequency = frequency.to_i
      framesize = framesize.to_i
      frequency = DEFAULT_FREQUENCY if frequency <= 0
      framesize = DEFAULT_FRAMESIZE if framesize <= 0
      key = [frequency, framesize]
      @@engine_mutex.synchronize do
        return @@engines[key] if @@engines[key] != nil
        SteamAudio.load
        @@engines[key] = SteamAudio.new(frequency, framesize)
      end
    rescue Exception => e
      Log.error("Audio3DEffect SteamAudio load failed: #{e.class}: #{e.message}; frequency=#{frequency} framesize=#{framesize}")
      nil
    end

    def framesize
      DEFAULT_FRAMESIZE
    end

    private

    def free_locked
      @@engines.each_value { |engine| engine.free if engine != nil }
      @@engines.clear
    rescue Exception
      @@engines.clear
    end
  end

  def initialize(frequency = DEFAULT_FREQUENCY, framesize = DEFAULT_FRAMESIZE, position: nil, interpolation: :nearest, hrtf: nil, spatial_blend: 1.0)
    @frequency = frequency.to_i <= 0 ? DEFAULT_FREQUENCY : frequency.to_i
    @framesize = framesize.to_i <= 0 ? DEFAULT_FRAMESIZE : framesize.to_i
    raise ArgumentError, "Expected an Audio::HRTF profile" if hrtf != nil && !hrtf.is_a?(Audio::HRTF)
    @hrtf_profile = hrtf
    @pending = "".b
    @mutex = Mutex.new
    @x = 0.0
    @y = 0.0
    @z = 0.0
    @bilinear = false
    @effect = nil
    @hrtf = nil
    @channels = nil
    self.spatial_blend = spatial_blend
    self.position = position if position != nil
    self.interpolation = interpolation
    load_engine(@frequency)
  end

  def output_channels(channels, _frequency)
    channels.to_i == 1 ? OUTPUT_CHANNELS : channels
  end

  def output_frequency(_frequency, _channels)
    @frequency
  end

  def latency_ms
    @framesize.to_f / 2.0
  end

  def process(audio, _frequency, channels)
    audio = audio.to_s.b
    channels = [[channels.to_i, 1].max, 2].min
    frequency = @frequency
    return stereo_silence(audio, channels) if !load_engine(frequency)
    ensure_effect(channels)
    return stereo_silence(audio, channels) if @effect == nil

    samples = audio.bytesize / channels / 4
    return "".b if samples <= 0
    expected_samples = frame_samples(frequency)
    expected_bytes = expected_samples * channels * 4
    x, y, z, blend = @mutex.synchronize { [@x, @y, @z, @spatial_blend] }
    z = 0.001 if x == 0 && y == 0 && z == 0
    @pending = "".b
    output = "".b
    offset = 0
    while offset < audio.bytesize
      frame = audio.byteslice(offset, expected_bytes)
      count = frame.bytesize / channels / 4
      frame = frame.ljust(expected_bytes, "\0") if frame.bytesize < expected_bytes
      out = @hrtf.process(@effect, frame, x, y, z, spatial_blend: blend)
      output << out.byteslice(0, count * OUTPUT_CHANNELS * 4)
      @pending = out.byteslice(count * OUTPUT_CHANNELS * 4..-1).to_s.b
      offset += expected_bytes
    end
    output
  rescue Exception => e
    Log.error("Audio3DEffect error: #{e.class}: #{e.message}")
    stereo_silence(audio, channels)
  end

  def process_final(audio, frequency, channels)
    output = process(audio, frequency, channels)
    output << @pending
    @pending = "".b
    output
  end

  def reset
    @pending = "".b
    @hrtf.reset_effect(@effect) if @hrtf != nil && @effect != nil
  end

  def tail_duration
    nil
  end

  def tail
    unless @pending.empty?
      result, @pending = @pending, "".b
      return result
    end
    @hrtf != nil && @effect != nil ? @hrtf.tail(@effect) : "".b
  end

  def spatial_blend
    @mutex.synchronize { @spatial_blend }
  end

  def spatial_blend=(value)
    blend = Audio::SpatialMath.scalar(value, "Spatial blend", min: 0, max: 1)
    @mutex.synchronize { @spatial_blend = blend }
  end

  def audio_clone
    self.class.new(
      @frequency,
      @framesize,
      :position => position,
      :interpolation => interpolation,
      :hrtf => @hrtf_profile,
      :spatial_blend => spatial_blend
    )
  end

  def close
    release_effect
    if @hrtf_profile != nil
      @hrtf&.free
      @hrtf = nil
    end
  end

  def x=(value)
    @mutex.synchronize { @x = clamp_position(value) }
  end

  def y=(value)
    @mutex.synchronize { @y = clamp_position(value) }
  end

  def z=(value)
    @mutex.synchronize { @z = clamp_position(value) }
  end

  def position
    @mutex.synchronize { [@x, @y, @z] }
  end

  def position=(value)
    coordinates = Array(value)
    position = [
      clamp_position(coordinates[0]),
      clamp_position(coordinates[1]),
      clamp_position(coordinates[2])
    ]
    @mutex.synchronize { @x, @y, @z = position }
    position
  end

  def interpolation
    @mutex.synchronize { @bilinear == true ? :bilinear : :nearest }
  end

  def interpolation=(value)
    interpolation = value.respond_to?(:to_sym) ? value.to_sym : nil
    raise ArgumentError, "interpolation must be :nearest or :bilinear" if ![:nearest, :bilinear].include?(interpolation)
    self.bilinear = interpolation == :bilinear
    interpolation
  end

  def bilinear=(value)
    @mutex.synchronize { @bilinear = value == true }
    @hrtf.set_bilinear(@effect, @bilinear) if @hrtf != nil && @effect != nil
    @bilinear
  end

  private

  def load_engine(frequency)
    if @hrtf_profile != nil
      raise SteamAudio::Error, "Steam Audio is unavailable" if !SteamAudio.load
      @hrtf ||= SteamAudio.new(frequency, @framesize, hrtf: @hrtf_profile)
      return true
    end
    engine = self.class.engine(frequency, @framesize)
    return false if engine == nil
    if @hrtf != engine
      release_effect
      @hrtf = engine
    end
    true
  end

  def ensure_effect(channels)
    return if @effect != nil && @channels == channels
    release_effect
    return if @hrtf == nil
    @effect = @hrtf.add_effect(channels)
    @effect = nil if @effect.to_i < 0
    @channels = channels
    @hrtf.set_bilinear(@effect, @bilinear) if @effect != nil
  end

  def release_effect
    @hrtf.remove_effect(@effect) if @hrtf != nil && @effect != nil
    @effect = nil
    @channels = nil
    @pending = "".b
  end

  def frame_samples(frequency)
    [(frequency.to_i * @framesize / 1000.0).to_i, 1].max
  end

  def clamp_position(value)
    [[value.to_f, POSITION_MIN].max, POSITION_MAX].min
  end

  def stereo_silence(audio, channels)
    samples = audio.to_s.bytesize / [[channels.to_i, 1].max, 2].min / 4
    "\0".b * samples * OUTPUT_CHANNELS * 4
  end
end
