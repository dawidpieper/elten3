# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class WaveAudioEncoder < AudioEncoder
  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    super(output, :frequency => frequency, :channels => channels, :source_channel => source_channel)
    @channels = [@channels, 1].max
    @bits = 16
    @data_size = 0
    @sample_bytes = @channels * 2
    @queue = "".b
    @output.write(header(0))
    self
  end

  def feed(data)
    return 0 if data == nil || data.bytesize <= 0
    @queue << data.to_s.b
    bytes = @queue.bytesize / @sample_bytes * @sample_bytes
    return 0 if bytes <= 0
    chunk = @queue.byteslice(0, bytes)
    @queue = @queue.byteslice(bytes..-1) || "".b
    @output.write(chunk)
    @data_size += chunk.bytesize
    chunk.bytesize
  end

  def finish
    feed("".b)
    @output.rewrite(0, header(@data_size))
    close
  end

  private

  def header(data_size)
    byte_rate = @frequency * @channels * @bits / 8
    block_align = @channels * @bits / 8
    data = "RIFF".b
    data += [36 + data_size].pack("V")
    data += "WAVEfmt ".b
    data += [16].pack("V")
    data += [1, @channels, @frequency, byte_rate, block_align, @bits].pack("vvVVvv")
    data += "data".b
    data += [data_size].pack("V")
    data
  end
end
