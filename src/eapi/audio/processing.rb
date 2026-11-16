# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module Audio
  class GainSource < Source
    attr_reader :source, :format, :value, :envelope

    def initialize(source, value: nil, envelope: nil)
      @source = source.format.sample_type == :float32le ? source : SampleFormatSource.new(source, :sample_type => :float32le)
      @format = @source.format
      @envelope = normalize_envelope(envelope)
      @value = value == nil ? 1.0 : Float(value)
      raise ArgumentError, "Audio volume must be finite" if !@value.finite?
    end

    def duration
      @source.duration
    end

    def metadata
      @source.metadata
    end

    def each_full_buffer(chunk_frames: DEFAULT_CHUNK_FRAMES)
      return enum_for(__method__, :chunk_frames => chunk_frames) if !block_given?
      frame_offset = 0
      channels = @format.channels
      @source.each_buffer(:chunk_frames => chunk_frames) do |buffer|
        samples = PCM.decode(buffer.data, buffer.format)
        for frame in 0...buffer.frame_count
          gain = @envelope == nil ? @value : @envelope.value_at(@format.seconds_for_frames(frame_offset + frame))
          for channel in 0...channels
            index = frame * channels + channel
            samples[index] *= gain
          end
        end
        frame_offset += buffer.frame_count
        yield Buffer.new(:data => PCM.encode(samples, @format), :format => @format, :metadata => buffer.metadata)
      end
      self
    end

    private

    def normalize_envelope(envelope)
      return nil if envelope == nil
      return envelope if envelope.is_a?(Envelope)
      Envelope.new(envelope)
    end
  end

  class PanSource < Source
    attr_reader :source, :format, :value, :envelope

    def initialize(source, value: nil, envelope: nil)
      @source = source.format.sample_type == :float32le ? source : SampleFormatSource.new(source, :sample_type => :float32le)
      @format = @source.format
      @envelope = envelope == nil || envelope.is_a?(Envelope) ? envelope : Envelope.new(envelope)
      @value = value == nil ? 0.0 : Float(value)
      raise ArgumentError, "Audio pan must be finite" if !@value.finite?
    end

    def duration
      @source.duration
    end

    def metadata
      @source.metadata
    end

    def each_full_buffer(chunk_frames: DEFAULT_CHUNK_FRAMES)
      return enum_for(__method__, :chunk_frames => chunk_frames) if !block_given?
      return @source.each_buffer(:chunk_frames => chunk_frames) { |buffer| yield buffer } if @format.channels < 2
      frame_offset = 0
      channels = @format.channels
      @source.each_buffer(:chunk_frames => chunk_frames) do |buffer|
        samples = PCM.decode(buffer.data, buffer.format)
        for frame in 0...buffer.frame_count
          pan = (@envelope == nil ? @value : @envelope.value_at(@format.seconds_for_frames(frame_offset + frame))).clamp(-1.0, 1.0)
          left_gain = pan > 0.0 ? 1.0 - pan : 1.0
          right_gain = pan < 0.0 ? 1.0 + pan : 1.0
          samples[frame * channels] *= left_gain
          samples[frame * channels + 1] *= right_gain
        end
        frame_offset += buffer.frame_count
        yield Buffer.new(:data => PCM.encode(samples, @format), :format => @format, :metadata => buffer.metadata)
      end
      self
    end
  end

  class BassPushSource < Source
    attr_reader :source, :format

    def initialize(source)
      @source = source.format.sample_type == :float32le ? source : SampleFormatSource.new(source, :sample_type => :float32le)
      @format = @source.format
    end

    def duration
      @source.duration
    end

    def metadata
      @source.metadata
    end

    def each_full_buffer(chunk_frames: DEFAULT_CHUNK_FRAMES)
      return enum_for(__method__, :chunk_frames => chunk_frames) if !block_given?
      source_channel = Bass::BASS_StreamCreate.call(
        @source.format.sample_rate,
        @source.format.channels,
        Bass::BASS_SAMPLE_FLOAT | Bass::BASS_STREAM_DECODE,
        Bass::STREAMPROC_PUSH,
        nil
      ).to_i
      raise UnsupportedOperation, "Cannot create an offline BASS audio stream: #{Bass.error_name}" if source_channel == 0
      output_channel = build_output_channel(source_channel)
      raise UnsupportedOperation, "Cannot create an offline BASS processor: #{Bass.error_name}" if output_channel.to_i == 0
      output_buffer = "\0".b * @format.bytes_for_frames(Integer(chunk_frames))
      @source.each_buffer(:chunk_frames => chunk_frames) do |buffer|
        written = Bass::BASS_StreamPutData.call(source_channel, buffer.data, buffer.data.bytesize).to_i
        raise Error, "Cannot feed offline BASS processor: #{Bass.error_name}" if written < 0
        drain_available(output_channel, output_buffer) { |result| yield result }
      end
      Bass::BASS_StreamPutData.call(source_channel, nil, Bass::BASS_STREAMPROC_END)
      drain_to_end(output_channel, output_buffer) { |result| yield result }
      self
    ensure
      begin
        close_output_channel
      rescue Exception
      end
      begin
        Bass.free_stream(output_channel) if output_channel != nil && output_channel.to_i != 0 && output_channel != source_channel
      rescue Exception
      end
      begin
        Bass.free_stream(source_channel) if source_channel != nil && source_channel.to_i != 0
      rescue Exception
      end
    end

    private

    def build_output_channel(source_channel)
      source_channel
    end

    def close_output_channel
    end

    def drain_available(channel, buffer)
      loop do
        available = Bass::BASS_ChannelGetData.call(channel, nil, 0).to_i
        break if available <= 0
        bytes = [available, buffer.bytesize].min
        bytes -= bytes % @format.bytes_per_frame
        break if bytes <= 0
        read = Bass::BASS_ChannelGetData.call(channel, buffer, bytes).to_i
        break if read <= 0
        read -= read % @format.bytes_per_frame
        yield Buffer.new(:data => buffer.byteslice(0, read), :format => @format, :metadata => metadata) if read > 0
      end
    end

    def drain_to_end(channel, buffer)
      loop do
        read = Bass::BASS_ChannelGetData.call(channel, buffer, buffer.bytesize).to_i
        break if read <= 0
        read -= read % @format.bytes_per_frame
        yield Buffer.new(:data => buffer.byteslice(0, read), :format => @format, :metadata => metadata) if read > 0
      end
    end
  end

  class BassTempoSource < BassPushSource
    def initialize(source, attribute:, value:)
      super(source)
      @attribute = Integer(attribute)
      @value = Float(value)
      raise ArgumentError, "Audio tempo attribute must be finite" if !@value.finite?
      validate_value
    end

    def duration
      value = @source.duration
      return nil if value == nil
      case @attribute
      when Bass::BASS_ATTRIB_TEMPO
        value / (1.0 + @value / 100.0)
      when Bass::BASS_ATTRIB_TEMPO_FREQ
        value * @source.format.sample_rate / @value
      else
        value
      end
    end

    private

    def build_output_channel(source_channel)
      function = Bass.optional_fiddle(Bass::BASSFX, "BASS_FX_TempoCreate", [Bass::F_UINT, Bass::F_UINT], Bass::F_UINT)
      channel = function.call(source_channel, Bass::BASS_STREAM_DECODE | Bass::BASS_SAMPLE_FLOAT).to_i
      raise UnsupportedOperation, "BASS_FX tempo processing is unavailable" if channel == 0
      if Bass::BASS_ChannelSetAttribute.call(channel, @attribute, @value).to_i == 0
        Bass.free_stream(channel)
        raise UnsupportedOperation, "Cannot set offline audio attribute: #{Bass.error_name}"
      end
      channel
    end

    def validate_value
      if @attribute == Bass::BASS_ATTRIB_TEMPO && 1.0 + @value / 100.0 <= 0.0
        raise ArgumentError, "Audio tempo must be greater than -100%"
      end
      if @attribute == Bass::BASS_ATTRIB_TEMPO_FREQ && @value <= 0.0
        raise ArgumentError, "Audio tempo frequency must be positive"
      end
    end
  end

  class NativeEffectSource < BassPushSource
    def initialize(source, effect)
      super(source)
      @effect_definition = effect
      @effect_instance = nil
    end

    private

    def build_output_channel(source_channel)
      @effect_instance = clone_effect(@effect_definition)
      if !@effect_instance.__send__(:bind, source_channel)
        raise UnsupportedOperation, "Cannot attach native audio effect"
      end
      source_channel
    end

    def close_output_channel
      @effect_instance.close if @effect_instance != nil && @effect_instance.respond_to?(:close)
      @effect_instance = nil
    end

    def clone_effect(effect)
      effect.respond_to?(:audio_clone) ? effect.audio_clone : effect.dup
    end
  end

  class EffectSource < Source
    attr_reader :source, :effect, :format

    def initialize(source, effect)
      raise ArgumentError, "Audio effect must respond to #process" if !effect.respond_to?(:process)
      @effect = effect
      if native_effect?(effect)
        @delegate = NativeEffectSource.new(source, effect)
        @source = source
        @format = @delegate.format
      else
        source = source.format.sample_type == :float32le ? source : SampleFormatSource.new(source, :sample_type => :float32le)
        target_frequency = effect.respond_to?(:output_frequency) ? effect.output_frequency(source.format.sample_rate, source.format.channels) : source.format.sample_rate
        target_frequency = source.format.sample_rate if target_frequency == nil || target_frequency.to_i <= 0
        source = source.resample(:to => target_frequency.to_i) if source.format.sample_rate != target_frequency.to_i
        output_channels = effect.respond_to?(:output_channels) ? effect.output_channels(source.format.channels, source.format.sample_rate) : source.format.channels
        @source = source
        @format = source.format.with(:channels => output_channels.to_i, :sample_type => :float32le)
        @delegate = nil
      end
    end

    def duration
      return @delegate.duration if @delegate != nil
      tail = @effect.respond_to?(:tail_duration) ? @effect.tail_duration : 0.0
      @source.duration != nil && tail != nil ? @source.duration + tail : nil
    end

    def metadata
      @source.metadata
    end

    def each_full_buffer(chunk_frames: DEFAULT_CHUNK_FRAMES)
      return enum_for(__method__, :chunk_frames => chunk_frames) if !block_given?
      if @delegate != nil
        @delegate.each_buffer(:chunk_frames => chunk_frames) { |buffer| yield buffer }
        return self
      end
      instance = @effect.respond_to?(:audio_clone) ? @effect.audio_clone : @effect.dup
      instance.reset if instance.respond_to?(:reset)
      processing_frames = [(@source.format.sample_rate * 0.02).round, 1].max
      @source.each_buffer(:chunk_frames => processing_frames) do |buffer|
        data = SoundEffect.process_frame(instance, buffer.data, @source.format.sample_rate, @source.format.channels)
        @format.frames_for_bytes(data.bytesize)
        yield Buffer.new(:data => data, :format => @format, :metadata => buffer.metadata)
      end
      SoundEffect.each_tail([instance], @source.format.sample_rate, @source.format.channels) do |data|
        yield Buffer.new(:data => data, :format => @format, :metadata => metadata)
      end
      self
    ensure
      begin
        instance.close if instance != nil && instance.respond_to?(:close)
      rescue Exception
      end
    end

    private

    def native_effect?(effect)
      effect.respond_to?(:native?) && effect.native? == true
    end
  end
end
