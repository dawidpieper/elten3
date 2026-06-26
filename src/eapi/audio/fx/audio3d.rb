# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class Audio3DEffect < SoundEffect
  attr_reader :x, :y, :z, :bilinear, :frequency

  DEFAULT_FREQUENCY = 48_000
  DEFAULT_FRAMESIZE = 20
  OUTPUT_CHANNELS = 2

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
        require_relative "../steamaudio" unless defined?(::SteamAudio)
        return nil if !SteamAudio.load
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

  def initialize(frequency = DEFAULT_FREQUENCY, framesize = DEFAULT_FRAMESIZE)
    @frequency = frequency.to_i <= 0 ? DEFAULT_FREQUENCY : frequency.to_i
    @framesize = framesize.to_i <= 0 ? DEFAULT_FRAMESIZE : framesize.to_i
    @mutex = Mutex.new
    @x = 0.0
    @y = 0.0
    @z = 0.0
    @bilinear = false
    @effect = nil
    @hrtf = nil
    @channels = nil
    load_engine(@frequency)
  end

  def output_channels(channels, _frequency)
    channels.to_i == 1 ? OUTPUT_CHANNELS : channels
  end

  def output_frequency(_frequency, _channels)
    @frequency
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
    frame = audio.bytesize < expected_bytes ? audio + ("\0".b * (expected_bytes - audio.bytesize)) : audio.byteslice(0, expected_bytes)
    x, y, z = @mutex.synchronize { [@x, @y, @z] }
    z = 0.001 if x == 0 && y == 0 && z == 0
    out = @hrtf.process(@effect, frame, x, y, z)
    out.byteslice(0, samples * OUTPUT_CHANNELS * 4).to_s.b
  rescue Exception => e
    Log.error("Audio3DEffect error: #{e.class}: #{e.message}")
    stereo_silence(audio, channels)
  end

  def reset
  end

  def close
    @hrtf.remove_effect(@effect) if @hrtf != nil && @effect != nil
    @effect = nil
    @channels = nil
  rescue Exception
    @effect = nil
    @channels = nil
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

  def bilinear=(value)
    @mutex.synchronize { @bilinear = value == true }
    @hrtf.set_bilinear(@effect, @bilinear) if @hrtf != nil && @effect != nil
    @bilinear
  end

  private

  def load_engine(frequency)
    engine = self.class.engine(frequency, @framesize)
    return false if engine == nil
    if @hrtf != engine
      close
      @hrtf = engine
    end
    true
  end

  def ensure_effect(channels)
    return if @effect != nil && @channels == channels
    close
    return if @hrtf == nil
    @effect = @hrtf.add_effect(channels)
    @effect = nil if @effect.to_i < 0
    @channels = channels
    @hrtf.set_bilinear(@effect, @bilinear) if @effect != nil
  end

  def frame_samples(frequency)
    [(frequency.to_i * @framesize / 1000.0).to_i, 1].max
  end

  def clamp_position(value)
    [[value.to_f, -1.0].max, 1.0].min
  end

  def stereo_silence(audio, channels)
    samples = audio.to_s.bytesize / [[channels.to_i, 1].max, 2].min / 4
    "\0".b * samples * OUTPUT_CHANNELS * 4
  end
end
