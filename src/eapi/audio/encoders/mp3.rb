class Mp3AudioEncoder < AudioEncoder
  BITRATES = [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 192, 224, 256, 320].freeze
  SAMPLE_RATES = [48_000, 44_100, 32_000, 24_000, 22_050, 16_000, 12_000, 11_025, 8_000].freeze

  def self.available?
    !!(defined?(Bass) && Bass::BASS_Encode_MP3_Start.is_a?(Fiddle::Function) &&
      Bass::BASS_Encode_Write.is_a?(Fiddle::Function) && Bass::BASS_Encode_Stop.is_a?(Fiddle::Function))
  end

  def initialize(bitrate = 192)
    @bitrate = Integer(bitrate)
    raise ArgumentError, "Unsupported MP3 bitrate" if !BITRATES.include?(@bitrate)
  end

  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    raise Audio::EncodingError, "MP3 encoder is unavailable" if !self.class.available?
    raise ArgumentError, "Unsupported MP3 sample rate" if !SAMPLE_RATES.include?(frequency)
    raise ArgumentError, "MP3 requires mono or stereo PCM" if ![1, 2].include?(channels)
    raise Audio::EncodingError, "MP3 encoder is already started" if @stream.to_i != 0
    started = true
    super
    @written = 0
    @write_error = nil
    @stream = Bass::BASS_StreamCreate.call(@frequency, @channels,
      Bass::BASS_STREAM_DECODE | Bass::BASS_SAMPLE_FLOAT, Bass::STREAMPROC_PUSH, nil)
    raise Audio::EncodingError, "Cannot create MP3 input: #{Bass.error_name}" if @stream == 0
    @callback = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID,
      [Bass::F_UINT, Bass::F_UINT, Bass::F_PTR, Bass::F_UINT, Bass::F_QWORD, Bass::F_PTR], Bass::BASS_ABI) do |_encoder, _channel, buffer, length, offset, _user|
      begin
        data = Fiddle::Pointer.new(buffer).to_s(length)
        offset == @written ? @output.write(data) : @output.rewrite(offset, data)
        @written = [@written, offset + length].max
      rescue StandardError => error
        @write_error ||= error
      end
    end
    @encoder = Bass::BASS_Encode_MP3_Start.call(@stream, "-b #{@bitrate}", Bass::BASS_ENCODE_PAUSE, @callback, nil)
    raise Audio::EncodingError, "Cannot start MP3 encoder: #{Bass.error_name}" if @encoder == 0
    raise @write_error if @write_error
    self
  rescue Exception
    close if started
    raise
  end

  def feed(data)
    raise Audio::EncodingError, "MP3 encoder is closed" if @encoder.to_i == 0
    data = data.to_s.b
    raise Audio::FormatMismatch, "MP3 input must contain complete PCM frames" if data.bytesize % (@channels * 2) != 0
    return 0 if data.empty?
    pcm = data.unpack("s<*").map { |sample| sample / 32768.0 }.pack("e*")
    result = Bass::BASS_Encode_Write.call(@encoder, pcm, pcm.bytesize)
    raise @write_error if @write_error
    raise Audio::EncodingError, "Cannot encode MP3: #{Bass.error_name}" if result == 0
    data.bytesize
  end

  def finish
    result = Bass::BASS_Encode_Stop.call(@encoder) if @encoder.to_i != 0
    @encoder = 0
    raise @write_error if @write_error
    raise Audio::EncodingError, "Cannot finish MP3 encoder: #{Bass.error_name}" if result == 0
  ensure
    close
  end

  def close
    Bass::BASS_Encode_Stop.call(@encoder) if @encoder.to_i != 0
  ensure
    @encoder = 0
    Bass.free_stream(@stream) if @stream.to_i != 0
    @stream = 0
    @callback = nil
  end

  def normalize_source?
    true
  end

  def source_channels(channel)
    EltenRecorderRuntime.source_limited_channels(channel)
  end
end
