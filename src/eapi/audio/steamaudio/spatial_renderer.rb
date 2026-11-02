# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class SteamAudio
  class SpatialRenderer
    def initialize(simulation)
      @settings = simulation.settings
      @frames = @settings[:frequency] / 50
      @resources = []
      @audio = SteamAudio.audio_settings(@settings[:frequency], @frames)
      @hrtf = simulation.hrtf.hrtf_handle
      @mono = buffer(1)
      @filtered = buffer(1)
      @output = buffer(2)
      @direct = effect(:DirectEffect, [1].pack("i"))
      @binaural = effect(:BinauralEffect, SteamAudio.pointer_buffer(@hrtf))
      @direct_params = Native.build(Native::DirectParams)
      @direct_params.attenuation = @direct_params.directivity = @direct_params.occlusion = 1
      @direct_params.air = [1, 1, 1]
      @direct_params.transmission_type = 1
      @binaural_params = Native.build(Native::BinauralParams)
      @binaural_params.hrtf = @hrtf
      if @settings[:reflections]
        config = Native.build(Native::ReflectionSettings)
        config.samples = (@settings[:duration] * @settings[:frequency]).ceil
        config.channels = (@settings[:order] + 1)**2
        @reflections = effect(:ReflectionEffect, config)
        @ambisonics = buffer(config.channels)
        @reverb = buffer(2)
        decode = Native.build(Native::DecodeSettings)
        decode.layout.type = 1
        decode.hrtf = @hrtf
        decode.order = @settings[:order]
        @decode = effect(:AmbisonicsDecodeEffect, decode)
        @reflection_params = Native.build(Native::ReflectionParams)
        @decode_params = Native.build(Native::DecodeParams)
        @decode_params.order = @settings[:order]
        @decode_params.hrtf = @hrtf
        @decode_params.binaural = 1
      end
      @simulation_direct = @direct_params.to_ptr[0, Native::DirectParams.size].freeze
      @simulation_reflections = nil
      @pending = "".b
      @processed = false
    rescue Exception
      close
      raise
    end

    def publish(outputs, reflections:)
      if reflections
        @simulation_reflections = outputs.reflections.to_ptr[0, Native::ReflectionParams.size].freeze
      else
        @simulation_direct = outputs.direct.to_ptr[0, Native::DirectParams.size].freeze
      end
    end

    def direct_state
      params = Native::DirectParams.new(Fiddle::Pointer[@simulation_direct])
      {distance_attenuation: params.attenuation, air_absorption: params.air.to_a.freeze, directivity: params.directivity, occlusion: params.occlusion, transmission: params.transmission.to_a.freeze}.freeze
    end

    def process(audio, channels, options, pose, listener, final: false)
      raise ArgumentError, "Spatial audio requires one or two channels" if ![1, 2].include?(channels)
      raise ArgumentError, "Incomplete spatial audio sample" if audio.bytesize % (channels * 4) != 0
      frames = audio.bytesize / (channels * 4)
      return "".b if frames == 0
      raise ArgumentError, "Spatial audio frames must not exceed 20 ms" if frames > @frames
      @pending = "".b
      padded = frames == @frames ? audio : audio.ljust(@frames * channels * 4, "\0")
      if channels == 1
        @mono.read(padded)
      else
        @stereo ||= buffer(2)
        @stereo.read(padded)
        Native.call(:AudioBufferDownmix, SteamAudio.context, @stereo.storage, @mono.storage)
      end
      enable_reflections(options[:reflections])
      update_params(options, pose, listener)
      Native.call(:DirectEffectApply, @direct, @direct_params, @mono.storage, @filtered.storage)
      Native.call(:BinauralEffectApply, @binaural, @binaural_params, @filtered.storage, @output.storage)
      if @reflections != nil && options[:reflections] && @simulation_reflections != nil
        @reflection_params.to_ptr[0, Native::ReflectionParams.size] = @simulation_reflections
        if @reflection_params.ir.to_i != 0
          Native.call(:ReflectionEffectApply, @reflections, @reflection_params, @mono.storage, @ambisonics.storage, 0)
          decode_reflections
        end
      end
      @processed = true
      result = @output.write
      return result.dup if final
      @pending = result.byteslice(frames * 8, (@frames - frames) * 8) if frames < @frames
      result.byteslice(0, frames * 8)
    end

    def tail(listener, reflections: true)
      enable_reflections(reflections)
      unless @pending.empty?
        result, @pending = @pending, "".b
        return result
      end
      return "".b if !@processed
      @output.clear
      length = 0
      if tail_size(@direct) > 0
        Native.call(:DirectEffectGetTail, @direct, @filtered.storage)
        Native.call(:BinauralEffectApply, @binaural, @binaural_params, @filtered.storage, @output.storage)
        length = @frames
      elsif (count = tail_size(@binaural)) > 0
        Native.call(:BinauralEffectGetTail, @binaural, @output.storage)
        length = [count, @frames].min
      end
      if @reflections != nil
        Native.coordinates(@decode_params.listener, listener)
        if tail_size(@reflections) > 0
          Native.call(:ReflectionEffectGetTail, @reflections, @ambisonics.storage, 0)
          decode_reflections
          length = @frames
        elsif (count = tail_size(@decode)) > 0
          Native.call(:AmbisonicsDecodeEffectGetTail, @decode, @reverb.storage)
          Native.call(:AudioBufferMix, SteamAudio.context, @reverb.storage, @output.storage)
          length = [length, [count, @frames].min].max
        end
      end
      @processed = false if length == 0
      @output.write.byteslice(0, length * 8)
    end

    def reset
      [@direct, @binaural, @reflections, @decode].compact.each { |handle| Native.call(:"#{handle.type}Reset", handle) }
      @pending = "".b
      @processed = false
    end

    def close
      @resources&.reverse_each(&:close)
      @resources&.clear
    end

    private

    def enable_reflections(enabled)
      if !enabled && @reflecting && @reflections != nil
        Native.call(:ReflectionEffectReset, @reflections)
        Native.call(:AmbisonicsDecodeEffectReset, @decode)
      end
      @reflecting = enabled
    end

    def buffer(channels)
      resource = Native::Buffer.new(channels, @frames)
      @resources << resource
      resource
    end

    def effect(type, config)
      resource = Native.create(type, SteamAudio.context, @audio, config)
      @resources << resource
      resource
    end

    def tail_size(handle)
      Native.call(:"#{handle.type}GetTailSize", handle)
    end

    def update_params(options, pose, listener)
      @direct_params.to_ptr[0, Native::DirectParams.size] = @simulation_direct
      flags = 4
      flags |= 1 if options[:distance_attenuation]
      flags |= 2 if options[:air_absorption] != false
      flags |= 8 if options[:occlusion] != false
      flags |= 16 if options[:transmission] != false
      @direct_params.flags = flags
      @direct_params.transmission_type = 1
      @direct_params.air = options[:air_absorption] if options[:air_absorption].is_a?(Array)
      @direct_params.occlusion = options[:occlusion] if options[:occlusion].is_a?(Numeric)
      @direct_params.transmission = options[:transmission] if options[:transmission].is_a?(Array)
      @binaural_params.direction = Audio::SpatialMath.direction(pose[:position], listener)
      @binaural_params.interpolation = options[:interpolation] == :bilinear ? 1 : 0
      @binaural_params.blend = options[:spatial_blend]
      Native.coordinates(@decode_params.listener, listener) if @decode != nil
    end

    def decode_reflections
      Native.call(:AmbisonicsDecodeEffectApply, @decode, @decode_params, @ambisonics.storage, @reverb.storage)
      Native.call(:AudioBufferMix, SteamAudio.context, @reverb.storage, @output.storage)
    end
  end
end
