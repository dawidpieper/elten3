# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module MediaEncoders
  @@encoders = []
  @@owners = {}
  @@mutex = Mutex.new

  class << self
    def register(encoder_class)
      # The legacy registry accepted any class. Keep that contract so an older
      # application cannot fail while it is being loaded; for_audio performs the
      # stricter capability check used by the new rendering API.
      return false if !encoder_class.is_a?(Class)
      owner = current_owner
      added = false
      @@mutex.synchronize do
        if !@@encoders.include?(encoder_class)
          @@encoders << encoder_class
          added = true
        end
        @@owners[encoder_class] = owner if owner != nil
      end
      log(:debug, "Registering media encoder #{encoder_class}") if added
      added
    rescue StandardError => error
      log(:error, "Cannot register media encoder #{encoder_class}: #{error.class}: #{error.message}")
      false
    end

    def unregister(encoder_class)
      removed = false
      @@mutex.synchronize do
        removed = @@encoders.delete(encoder_class) != nil
        @@owners.delete(encoder_class)
      end
      log(:debug, "Unregistering media encoder #{encoder_class}") if removed
      removed
    rescue StandardError => error
      log(:error, "Cannot unregister media encoder #{encoder_class}: #{error.class}: #{error.message}")
      false
    end

    def unregister_owner(owner)
      return 0 if owner == nil
      classes = @@mutex.synchronize { @@owners.select { |_encoder, value| value.equal?(owner) }.keys }
      classes.count { |encoder_class| unregister(encoder_class) }
    end

    def delete_all
      classes = @@mutex.synchronize { @@encoders.dup }
      classes.each { |encoder_class| unregister(encoder_class) }
      classes.size
    end

    def list
      external = @@mutex.synchronize { @@encoders.dup }
      built_in = [OpusEncoder, VorbisEncoder, WaveEncoder]
      built_in << Mp3Encoder if Mp3Encoder.available?
      (built_in + external).uniq
    end

    def for_audio
      list.filter_map do |encoder_class|
        begin
          encoder_class if encoder_class.audio_supported?
        rescue StandardError => error
          log(:error, "Ignoring incompatible media encoder #{encoder_class}: #{error.class}: #{error.message}")
          nil
        end
      end
    end

    private

    def current_owner
      return nil if !defined?(Programs) || !Programs.respond_to?(:current_runtime)
      Programs.current_runtime
    rescue StandardError
      nil
    end

    def log(level, message)
      logger = defined?(Log) ? Log : (defined?(EltenAPI::Log) ? EltenAPI::Log : nil)
      logger.__send__(level, message) if logger != nil && logger.respond_to?(level)
    rescue StandardError
    end
  end
end

class MediaEncoder
  Type = :audio
  Extension = "."
  IsBitrateSupported = true
  Name = ""
  SupportsPcmStream = false

  class UnsupportedOperation < StandardError; end

  class << self
    def identifier
      nil
    end

    def output_descriptor
      nil
    end

    def input_constraints
      nil
    end

    def available?
      true
    end

    def audio_supported?
      return false if const_get(:Type) != :audio
      return false if output_descriptor == nil || input_constraints == nil
      return false if !available?
      instance_method(:start).owner != MediaEncoder
    end

    def encode_file(_file, _output, _bitrate = nil)
      false
    end

    def audio_encoder(_bitrate = nil)
      nil
    end
  end

  def output_descriptor
    self.class.output_descriptor
  end

  def input_constraints
    self.class.input_constraints
  end

  def start(output:, input_format:, metadata: {})
    raise UnsupportedOperation, "#{self.class} does not support the Audio rendering API"
  end
end

class OpusEncoder < MediaEncoder
  Type = :audio
  Extension = ".opus"
  Name = "Opus"
  IsBitrateSupported = true
  SupportsPcmStream = true

  class << self
    def identifier
      :opus
    end

    def output_descriptor
      @output_descriptor ||= {
        :codec => :opus,
        :container => :ogg,
        :extensions => [Extension].freeze,
        :mime_type => "audio/ogg"
      }.freeze
    end

    def input_constraints
      @input_constraints ||= Audio::FormatConstraint.new(:sample_types => [:s16le], :sample_rates => [48_000], :channels => 1..2)
    end

    def encode_file(file, output, bitrate = nil)
      Recorder.encode_opus_file(file, output, bitrate || 64)
      true
    end

    def audio_encoder(bitrate = nil)
      Recorder.opus_encoder(bitrate || 64)
    end
  end

  def initialize(bitrate: 64, framesize: 60, application: :audio, vbr: true, tags: nil, denoise: false)
    @bitrate = Integer(bitrate)
    @framesize = Float(framesize)
    @application = application.to_sym == :voip ? 2048 : 2049
    @vbr = vbr == true ? 1 : 0
    @tags = tags
    @denoise = denoise == true
  end

  def start(output:, input_format:, metadata: {})
    tags = @tags == nil ? metadata : @tags
    OpusAudioEncoder.new(@bitrate, @framesize, @application, @vbr, :tags => tags, :denoise => @denoise).start(
      output,
      :frequency => input_format.sample_rate,
      :channels => input_format.channels
    )
  end
end

class VorbisEncoder < MediaEncoder
  Type = :audio
  Extension = ".ogg"
  Name = "Ogg Vorbis"
  IsBitrateSupported = true
  SupportsPcmStream = true

  class << self
    def identifier
      :vorbis
    end

    def output_descriptor
      @output_descriptor ||= {
        :codec => :vorbis,
        :container => :ogg,
        :extensions => [Extension].freeze,
        :mime_type => "audio/ogg"
      }.freeze
    end

    def input_constraints
      @input_constraints ||= Audio::FormatConstraint.new(:sample_types => [:s16le], :sample_rates => [48_000], :channels => 1..2)
    end

    def encode_file(file, output, bitrate = nil)
      Recorder.encode_vorbis_file(file, output, bitrate || 96)
      true
    end

    def audio_encoder(bitrate = nil)
      Recorder.vorbis_encoder(bitrate || 96)
    end
  end

  def initialize(bitrate: 96, tags: nil)
    @bitrate = Integer(bitrate)
    @tags = tags
  end

  def start(output:, input_format:, metadata: {})
    tags = @tags == nil ? metadata : @tags
    VorbisAudioEncoder.new(@bitrate, :tags => tags).start(
      output,
      :frequency => input_format.sample_rate,
      :channels => input_format.channels
    )
  end
end

class Mp3Encoder < MediaEncoder
  Extension = ".mp3"
  Name = "MP3"
  SupportsPcmStream = true

  class << self
    def identifier
      :mp3
    end

    def available?
      Mp3AudioEncoder.available?
    end

    def output_descriptor
      @output_descriptor ||= {
        :codec => :mp3,
        :container => :mp3,
        :extensions => [Extension].freeze,
        :mime_type => "audio/mpeg"
      }.freeze
    end

    def input_constraints
      @input_constraints ||= Audio::FormatConstraint.new(:sample_types => [:s16le],
        :sample_rates => Mp3AudioEncoder::SAMPLE_RATES, :channels => 1..2)
    end

    def encode_file(file, output, bitrate = nil)
      Audio.open(file).export(output, :encoder => new(:bitrate => bitrate || 192))
      true
    end

    def audio_encoder(bitrate = nil)
      Mp3AudioEncoder.new(bitrate || 192)
    end
  end

  def initialize(bitrate: 192)
    @bitrate = Integer(bitrate)
    raise ArgumentError, "Unsupported MP3 bitrate" if !Mp3AudioEncoder::BITRATES.include?(@bitrate)
  end

  def start(output:, input_format:, metadata: {})
    raise Audio::FormatMismatch, "Unsupported MP3 input format" if !input_constraints.allows?(input_format)
    Mp3AudioEncoder.new(@bitrate).start(output,
      :frequency => input_format.sample_rate, :channels => input_format.channels)
  end
end

class WaveEncoder < MediaEncoder
  Type = :audio
  Extension = ".wav"
  Name = "Wave PCM"
  IsBitrateSupported = false
  SupportsPcmStream = true

  class << self
    def identifier
      :wave
    end

    def output_descriptor
      @output_descriptor ||= {
        :codec => :pcm_s16le,
        :container => :wave,
        :extensions => [Extension].freeze,
        :mime_type => "audio/wav"
      }.freeze
    end

    def input_constraints
      @input_constraints ||= Audio::FormatConstraint.new(:sample_types => [:s16le], :sample_rates => 1..384_000, :channels => 1..8)
    end

    def encode_file(file, output, _bitrate = nil)
      Recorder.encode_wave_file(file, output)
      true
    end

    def audio_encoder(_bitrate = nil)
      Recorder.wave_encoder
    end
  end

  def initialize(**_options)
  end

  def start(output:, input_format:, metadata: {})
    WaveAudioEncoder.new.start(
      output,
      :frequency => input_format.sample_rate,
      :channels => input_format.channels
    )
  end
end
