# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class BassFXEffect < SoundEffect
  EFFECT_TYPE = nil

  class << self
    def inherited(subclass)
      subclass.instance_variable_set(:@parameters, parameters.transform_values(&:dup))
      super
    end

    def parameter(name, type: :float, default:, range: nil, values: nil, public: true)
      name = name.to_sym
      parameters[name] = {type: type, default: default, range: range, values: values, public: public}
      if public
        define_method(name) { @mutex.synchronize { @values[name] } }
        define_method("#{name}=") { |value| set_parameter(name, value) }
      end
    end

    def parameters
      @parameters ||= {}
    end

    def available?
      Bass::BASS_FX_GetVersion.call.to_i != 0
    rescue Exception
      false
    end
  end

  attr_reader :sound, :priority

  def initialize(priority: 0, enabled: true, **values)
    raise NotImplementedError, "BassFXEffect requires a concrete effect type" if effect_type == nil
    values = values.each_with_object({}) { |(name, value), normalized| normalized[name.to_sym] = value }
    accepted = self.class.parameters.select { |_name, definition| definition[:public] }.keys
    unknown = values.keys - accepted
    raise ArgumentError, "Unknown effect parameters: #{unknown.join(', ')}" if !unknown.empty?

    @mutex = Mutex.new
    @sound = nil
    @channel = 0
    @handle = 0
    @priority = Integer(priority)
    @enabled = enabled == true
    @values = {}
    self.class.parameters.each do |name, definition|
      value = values.key?(name) ? values[name] : definition[:default]
      @values[name] = normalize_parameter(name, value, definition)
    end
  end

  def native?
    true
  end

  def attached?
    @sound != nil
  end

  def active?
    @handle.to_i != 0
  end

  def enabled?
    @mutex.synchronize { @enabled }
  end

  def enabled=(value)
    value = value == true
    @mutex.synchronize do
      previous = @enabled
      @enabled = value
      if @handle.to_i != 0 && Bass::BASS_FXSetBypass.call(@handle, value ? 0 : 1) == 0
        @enabled = previous
        raise RuntimeError, native_error("Cannot change effect bypass")
      end
    end
    value
  end

  def priority=(value)
    value = Integer(value)
    @mutex.synchronize do
      previous = @priority
      @priority = value
      if @handle.to_i != 0 && Bass::BASS_FXSetPriority.call(@handle, value) == 0
        @priority = previous
        raise RuntimeError, native_error("Cannot change effect priority")
      end
    end
    value
  end

  def reset
    @mutex.synchronize do
      return false if @handle.to_i == 0
      Bass::BASS_FXReset.call(@handle) != 0
    end
  end

  def close
    __send__(:detach, @sound)
    nil
  end

  private

  def effect_type
    self.class::EFFECT_TYPE
  end

  def attach(sound)
    if @sound != nil && !@sound.equal?(sound)
      raise ArgumentError, "Sound effect is already attached to another sound"
    end
    @sound = sound
    self
  end

  def detach(sound)
    return self if !@sound.equal?(sound)
    unbind
    @sound = nil
    self
  end

  def bind(channel)
    channel = channel.to_i
    return false if channel == 0
    raise RuntimeError, "Native audio effects are unavailable" if !self.class.available?

    unbind
    @mutex.synchronize do
      @handle = Bass::BASS_ChannelSetFX.call(channel, effect_type, @priority).to_i
      raise RuntimeError, native_error("Cannot attach #{self.class}") if @handle == 0
      @channel = channel
      begin
        apply_parameters_locked
        if !@enabled && Bass::BASS_FXSetBypass.call(@handle, 1) == 0
          raise RuntimeError, native_error("Cannot bypass #{self.class}")
        end
      rescue Exception
        remove_native_effect_locked
        raise
      end
    end
    true
  end

  def unbind
    @mutex.synchronize { remove_native_effect_locked }
    false
  end

  def remove_native_effect_locked
    if @handle.to_i != 0
      removed = @channel.to_i != 0 && Bass::BASS_ChannelRemoveFX.call(@channel, @handle) != 0
      Bass::BASS_FXFree.call(@handle) if !removed
    end
    @channel = 0
    @handle = 0
  end

  def set_parameter(name, value)
    name = name.to_sym
    definition = self.class.parameters[name]
    raise ArgumentError, "Unknown effect parameter #{name.inspect}" if definition == nil
    value = normalize_parameter(name, value, definition)
    @mutex.synchronize do
      previous = @values[name]
      @values[name] = value
      begin
        apply_parameters_locked if @handle.to_i != 0
      rescue Exception
        @values[name] = previous
        raise
      end
    end
    value
  end

  def normalize_parameter(name, value, definition)
    normalized = case definition[:type]
    when :float
      Float(value)
    when :integer
      Integer(value)
    when :boolean
      value == true
    when :channels
      normalize_channels(value)
    when :enum
      key = value.respond_to?(:to_sym) ? value.to_sym : value
      definition[:values].fetch(key) { raise ArgumentError, "Invalid #{name}: #{value.inspect}" }
      key
    else
      raise ArgumentError, "Unknown parameter type #{definition[:type].inspect}"
    end
    if normalized.is_a?(Float) && !normalized.finite?
      raise ArgumentError, "#{name} must be finite"
    end
    range = definition[:range]
    raise ArgumentError, "#{name} is outside #{range}" if range != nil && !range.cover?(normalized)
    normalized
  rescue TypeError, ArgumentError => e
    raise e if e.message.start_with?(name.to_s) || e.message.start_with?("Invalid ")
    raise ArgumentError, "Invalid #{name}: #{value.inspect}"
  end

  def normalize_channels(value)
    return Bass::BASS_BFX_CHANALL if value == :all || value == nil
    if value.is_a?(Array)
      return value.sum do |channel|
        channel = Integer(channel)
        raise ArgumentError if channel <= 0
        1 << (channel - 1)
      end
    end
    value = Integer(value)
    raise ArgumentError if value < Bass::BASS_BFX_CHANALL
    value
  rescue TypeError, ArgumentError
    raise ArgumentError, "channels must be :all, a channel mask or an array of channel numbers"
  end

  def parameter_buffer(parameters = @values)
    format = +""
    values = []
    self.class.parameters.each do |name, definition|
      format << (definition[:type] == :float ? "f" : "l")
      value = parameters[name]
      value = value ? 1 : 0 if definition[:type] == :boolean
      value = definition[:values].fetch(value) if definition[:type] == :enum
      values << value
    end
    values.pack(format)
  end

  def apply_parameters_locked
    return false if @handle.to_i == 0
    if Bass::BASS_FXSetParameters.call(@handle, parameter_buffer) == 0
      raise RuntimeError, native_error("Cannot update #{self.class}")
    end
    true
  end

  def native_error(message)
    "#{message}: BASS error #{Bass::BASS_ErrorGetCode.call}"
  end
end

class EchoEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_ECHO4
  parameter :dry_mix, default: 1.0, range: -2.0..2.0
  parameter :wet_mix, default: 0.5, range: -2.0..2.0
  parameter :feedback, default: 0.3, range: -1.0..1.0
  parameter :delay, default: 0.25, range: 0.001..Float::INFINITY
  parameter :stereo, type: :boolean, default: true
  parameter :channels, type: :channels, default: :all
end

class ReverbEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_FREEVERB
  parameter :dry_mix, default: 1.0, range: 0.0..1.0
  parameter :wet_mix, default: 0.5, range: 0.0..3.0
  parameter :room_size, default: 0.5, range: 0.0..1.0
  parameter :damping, default: 0.5, range: 0.0..1.0
  parameter :width, default: 1.0, range: 0.0..1.0
  parameter :freeze_mode, type: :boolean, default: false
  parameter :channels, type: :channels, default: :all
end

class ChorusEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_CHORUS
  parameter :dry_mix, default: 1.0, range: -2.0..2.0
  parameter :wet_mix, default: 0.5, range: -2.0..2.0
  parameter :feedback, default: 0.0, range: -1.0..1.0
  parameter :minimum_sweep, default: 5.0, range: 0.001..6000.0
  parameter :maximum_sweep, default: 30.0, range: 0.001..6000.0
  parameter :rate, default: 20.0, range: 0.001..1000.0
  parameter :channels, type: :channels, default: :all
end

class FlangerEffect < ChorusEffect
  def initialize(**options)
    super(**{wet_mix: 0.35, feedback: 0.35, minimum_sweep: 0.1, maximum_sweep: 5.0, rate: 5.0}.merge(options))
  end
end

class PhaserEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_PHASER
  parameter :dry_mix, default: 1.0, range: -2.0..2.0
  parameter :wet_mix, default: 0.5, range: -2.0..2.0
  parameter :feedback, default: 0.0, range: -1.0..1.0
  parameter :rate, default: 1.0, range: 0.001...10.0
  parameter :range, default: 4.0, range: 0.001...10.0
  parameter :frequency, default: 500.0, range: 0.001...1000.0
  parameter :channels, type: :channels, default: :all
end

class DistortionEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_DISTORTION
  parameter :drive, default: 1.0, range: 0.0..5.0
  parameter :dry_mix, default: 0.8, range: -5.0..5.0
  parameter :wet_mix, default: 0.2, range: -5.0..5.0
  parameter :feedback, default: 0.0, range: -1.0..1.0
  parameter :volume, default: 1.0, range: 0.0..2.0
  parameter :channels, type: :channels, default: :all
end

class CompressorEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_COMPRESSOR2
  parameter :gain, default: 0.0, range: -60.0..60.0
  parameter :threshold, default: -12.0, range: -60.0..0.0
  parameter :ratio, default: 4.0, range: 1.0..Float::INFINITY
  parameter :attack, default: 10.0, range: 0.01..1000.0
  parameter :release, default: 100.0, range: 0.01..5000.0
  parameter :channels, type: :channels, default: :all
end

class AutoWahEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_AUTOWAH
  parameter :dry_mix, default: 0.5, range: -2.0..2.0
  parameter :wet_mix, default: 0.5, range: -2.0..2.0
  parameter :feedback, default: 0.2, range: -1.0..1.0
  parameter :rate, default: 2.0, range: 0.001...10.0
  parameter :range, default: 4.0, range: 0.001...10.0
  parameter :frequency, default: 200.0, range: 0.001...1000.0
  parameter :channels, type: :channels, default: :all
end

class PeakEqualizerEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_PEAKEQ
  parameter :band, type: :integer, default: 0, range: 0..0, public: false
  parameter :bandwidth, default: 1.0, range: 0.1...10.0
  parameter :q, default: 0.0, range: 0.0..1.0
  parameter :center, default: 1000.0, range: 1.0..Float::INFINITY
  parameter :gain, default: 0.0
  parameter :channels, type: :channels, default: :all
end

class BiquadFilterEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_BQF
  FILTERS = {
    low_pass: 0,
    high_pass: 1,
    band_pass: 2,
    band_pass_q: 3,
    notch: 4,
    all_pass: 5,
    peaking_equalizer: 6,
    low_shelf: 7,
    high_shelf: 8
  }.freeze
  parameter :filter, type: :enum, default: :low_pass, values: FILTERS
  parameter :center, default: 1000.0, range: 1.0..Float::INFINITY
  parameter :gain, default: 0.0
  parameter :bandwidth, default: 0.0, range: 0.0...10.0
  parameter :q, default: 0.707, range: 0.0..1.0
  parameter :slope, default: 1.0, range: 0.0..1.0
  parameter :channels, type: :channels, default: :all

  private

  def parameter_buffer(_parameters = @values)
    parameters = @values.dup
    if [:low_shelf, :high_shelf].include?(parameters[:filter])
      parameters[:bandwidth] = 0.0
      parameters[:q] = 0.0
    else
      parameters[:slope] = 0.0
      parameters[:q] = 0.0 if parameters[:bandwidth] > 0.0
    end
    super(parameters)
  end
end

class DynamicAmplificationEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_DAMP
  parameter :target, default: 0.95, range: 0.001..1.0
  parameter :quiet, default: 0.02, range: 0.0..1.0
  parameter :rate, default: 0.5, range: 0.0..1.0
  parameter :gain, default: 1.0, range: 0.0..Float::INFINITY
  parameter :delay, default: 0.0, range: 0.0..Float::INFINITY
  parameter :channels, type: :channels, default: :all
end

class RotationEffect < BassFXEffect
  EFFECT_TYPE = Bass::BASS_FX_BFX_ROTATE
  parameter :rate, default: 0.2
  parameter :channels, type: :channels, default: :all
end
