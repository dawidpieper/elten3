# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module Audio
  class SpatialEmitter < SoundEffect
    DEFAULTS = {
      distance_attenuation: true, min_distance: 1.0, air_absorption: true,
      directivity: [0.0, 1.0].freeze, occlusion: :raycast, radius: 0.1,
      transmission: true, reflections: true, spatial_blend: 1.0, interpolation: :bilinear
    }.freeze

    attr_reader :scene, :pose

    def initialize(scene, renderer, position: [0, 0, 0], forward: [0, 0, -1], up: [0, 1, 0], **options)
      @scene = scene
      @renderer = renderer
      @mutex = Mutex.new
      @closed = false
      @options = validate_options(DEFAULTS.merge(options))
      @pose = SpatialPose.new(position: position, forward: forward, up: up) { scene.wake }
    end

    def options
      @mutex.synchronize { @options }
    end

    def configure(**values)
      @mutex.synchronize do
        raise IOError, "Spatial emitter is closed" if @closed
        @options = validate_options(@options.merge(values))
      end
      @scene.wake(reflections: values[:reflections] == true)
      self
    end

    [:position, :forward, :up].each do |key|
      define_method(key) { @pose.public_send(key) }
      define_method("#{key}=") { |value| @pose.public_send("#{key}=", value) }
    end

    DEFAULTS.each_key do |key|
      define_method(key) { options[key] }
      define_method("#{key}=") { |value| configure(**{key => value}); value }
    end

    def output_frequency(_frequency, _channels)
      @scene.settings[:frequency]
    end

    def output_channels(_channels, _frequency)
      2
    end

    def latency_ms
      10.0
    end

    def tail_duration
      nil
    end

    def process(audio, _frequency, channels)
      @mutex.synchronize do
        return "\0".b * (audio.bytesize / channels * 2) if @closed
        @renderer.process(audio, channels, @options, @pose.snapshot, @scene.listener.snapshot)
      end
    end

    def process_final(audio, _frequency, channels)
      @mutex.synchronize do
        return "\0".b * (audio.bytesize / channels * 2) if @closed
        @renderer.process(audio, channels, @options, @pose.snapshot, @scene.listener.snapshot, final: true)
      end
    end

    def tail
      @mutex.synchronize { @closed ? "".b : @renderer.tail(@scene.listener.snapshot, reflections: @options[:reflections]) }
    end

    def reset
      @mutex.synchronize { @renderer.reset if !@closed }
      @scene.wake(reflections: true)
    end

    def direct_state
      @mutex.synchronize { @renderer.direct_state }
    end

    def publish(outputs, reflections:)
      @mutex.synchronize { @renderer.publish(outputs, reflections: reflections) if !@closed }
    end

    def audio_clone
      raise IOError, "Spatial emitter is closed" if closed?
      pose = @pose.snapshot
      emitter = @scene.create_emitter(position: pose[:position], forward: pose[:forward], up: pose[:up], **options)
      @scene.update
      emitter
    rescue Exception
      emitter&.close
      raise
    end

    def close
      @mutex.synchronize do
        return if @closed
        @closed = true
        @renderer.close
      end
      @scene.wake
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    private

    def validate_options(options)
      unknown = options.keys - DEFAULTS.keys
      raise ArgumentError, "Unknown spatial options: #{unknown.join(", ")}" if !unknown.empty?
      [:distance_attenuation, :reflections].each do |key|
        raise ArgumentError, "#{key} must be true or false" if ![true, false].include?(options[key])
      end
      options[:min_distance] = SpatialMath.scalar(options[:min_distance], "Minimum distance", min: 0.001)
      options[:radius] = SpatialMath.scalar(options[:radius], "Occlusion radius", min: 0.001)
      options[:spatial_blend] = SpatialMath.scalar(options[:spatial_blend], "Spatial blend", min: 0, max: 1)
      directivity = SpatialMath.vector(options[:directivity], "Directivity", size: 2, min: 0)
      raise ArgumentError, "Directivity weight must not exceed 1" if directivity[0] > 1
      options[:directivity] = directivity
      [:air_absorption, :transmission].each do |key|
        value = options[key]
        options[key] = SpatialMath.vector(value, key.to_s, min: 0, max: 1) if value != true && value != false
      end
      value = options[:occlusion]
      options[:occlusion] = SpatialMath.scalar(value, "Occlusion", min: 0, max: 1) if ![false, :raycast, :volumetric].include?(value)
      raise ArgumentError, "Interpolation must be :nearest or :bilinear" if ![:nearest, :bilinear].include?(options[:interpolation])
      options.freeze
    end
  end
end
