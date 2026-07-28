# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class OpusOggWriter
  def initialize(output, channels, preskip, tags = nil)
    @output = output
    @channels = channels.to_i
    @ogg = OggNative.stream_state_buffer
    @packetno = 0
    @granulepos = 0
    @lastpacket = nil
    @lastpacket_data = nil
    @lastpacket_data_pointer = nil
    OggNative.load!
    OggNative.stream_init.call(@ogg, rand(2**32) - 2**31)
    write_headers(preskip.to_i, tags)
  end

  def write_packet(data, samples)
    @granulepos += samples.to_i
    add_packet(data)
  end

  def close
    return if @ogg == nil
    add_packet("") if @lastpacket == nil
    OggNative.packet_set_eos(@lastpacket, 1)
    add_packet(nil)
    OggNative.stream_clear.call(@ogg)
    @ogg = nil
  end

  private

  def write_headers(preskip, tags)
    head = "OpusHead".b
    head += [1].pack("C")
    head += [@channels].pack("C")
    head += [preskip].pack("S")
    head += [48000].pack("I")
    head += [0].pack("S")
    head += [0].pack("C")
    add_packet(head, true, false)
    add_packet(opus_tags(tags), false, false, false)
  end

  def opus_tags(tags)
    vendor = Opus.version.b
    comments = []
    (tags || {}).each do |key, value|
      next if key == nil || value == nil
      comments << utf8_comment("#{key}=#{value}")
    end
    comments << utf8_comment("ENCODER=ELTEN") if comments.none? { |comment| comment.upcase.start_with?("ENCODER=") }
    data = "OpusTags".b
    data += [vendor.bytesize].pack("I")
    data += vendor
    data += [comments.size].pack("I")
    comments.each do |comment|
      data += [comment.bytesize].pack("I")
      data += comment
    end
    data
  end

  def utf8_comment(text)
    text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).b
  end

  def add_packet(data, b_o_s = false, e_o_s = false, writepages = true)
    if @lastpacket != nil
      OggNative.stream_packetin.call(@ogg, @lastpacket)
      if writepages
        page = OggNative.page_buffer
        while OggNative.stream_pageout.call(@ogg, page) != 0
          values = OggNative.page_values(page)
          @output.write(OggNative.page_part(values[0], values[1], 282))
          @output.write(OggNative.page_part(values[2], values[3], 65_025))
        end
      end
    end
    if data != nil
      @packetno += 1
      @lastpacket_data = data.b
      @lastpacket_data_pointer = OggNative.packet_data_pointer(@lastpacket_data)
      @lastpacket = OggNative.packet(@lastpacket_data_pointer, @lastpacket_data.bytesize, b_o_s ? 1 : 0, e_o_s ? 1 : 0, @granulepos, @packetno)
    end
  end
end

class OpusAudioEncoder < AudioEncoder
  def initialize(bitrate = 64, framesize = 60, application = 2048, usevbr = 1, tags: nil, denoise: false)
    @bitrate = bitrate.to_i
    @framesize = framesize.to_f
    @framesize = 20.0 if @framesize <= 0
    @framesize = [@framesize, 60.0].min
    @application = application.to_i
    @usevbr = usevbr.to_i
    @tags = tags
    @denoise = denoise == true
  end

  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    super(output, :frequency => 48000, :channels => [[channels.to_i, 1].max, 2].min, :source_channel => source_channel)
    require_relative "../opus" unless defined?(::Opus)
    require_relative "../speexdsp" unless defined?(::SpeexDSP)
    @frame_samples = (48000 * @framesize / 1000).to_i
    @frame_bytes = @frame_samples * @channels * 2
    @queue = "".b
    @encoder = Opus::Encoder.new(48000, @channels, @application == 2049 ? :audio : :voip)
    handle = @encoder.instance_variable_get(:@encoder)
    raise RuntimeError, "Opus encoder is unavailable" if handle == nil || handle.to_i == 0
    @encoder.bitrate = @bitrate * 1000
    @encoder.vbr = @usevbr
    @speex = nil
    if @denoise && defined?(::SpeexDSP)
      @speex = SpeexDSP::Processor.new(48000, @channels, @framesize)
      @speex.noise_reduction = true
    end
    tags = @tags
    tags = EltenRecorderRuntime.source_tags(source_channel) if tags == nil && source_channel != nil
    @writer = OpusOggWriter.new(output, @channels, @encoder.preskip, tags)
    self
  rescue Exception
    close
    raise
  end

  def feed(data)
    return 0 if data == nil || data.bytesize <= 0
    @queue << data.to_s.b
    processed = 0
    while @queue.bytesize >= @frame_bytes
      frame = @queue.byteslice(0, @frame_bytes)
      @queue = @queue.byteslice(@frame_bytes..-1) || "".b
      process_frame(frame)
      processed += frame.bytesize
    end
    processed
  end

  def finish
    if @queue != nil && @queue.bytesize > 0
      frame = @queue + ("\0" * (@frame_bytes - @queue.bytesize)).b
      @queue = "".b
      process_frame(frame)
    end
    close
  end

  def close
    @writer.close if @writer != nil
    @writer = nil
    @speex.free if @speex != nil
    @speex = nil
    @encoder.free if @encoder != nil && !@encoder.closed?
    @encoder = nil
  end

  def normalize_source?
    true
  end

  def source_frequency
    48000
  end

  def source_channels(channel)
    EltenRecorderRuntime.source_limited_channels(channel)
  end

  def recording_buffer_bytes
    [@frame_samples.to_i * 2 * 2 * 8, 384000].max
  end

  private

  def process_frame(frame)
    frame = @speex.process(frame) if @speex != nil
    return if frame == nil || frame.bytesize < @frame_bytes
    frame = frame.byteslice(0, @frame_bytes)
    packet = @encoder.encode(frame, @frame_samples)
    @writer.write_packet(packet, @frame_samples) if packet != nil && packet.bytesize > 0
  end
end
