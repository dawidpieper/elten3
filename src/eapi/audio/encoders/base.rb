# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class RecorderOutput
  def write(_data)
  end

  def rewrite(_offset, _data)
  end

  def close
  end

  def data
    "".b
  end
end

class FileRecorderOutput < RecorderOutput
  def initialize(file)
    @file = File.open(file, "wb")
  end

  def write(data)
    @file.write(data.to_s.b)
  end

  def rewrite(offset, data)
    position = @file.pos
    @file.seek(offset.to_i, IO::SEEK_SET)
    @file.write(data.to_s.b)
    @file.seek(position, IO::SEEK_SET)
  end

  def close
    @file.close if @file != nil && !@file.closed?
  end
end

class MemoryRecorderOutput < RecorderOutput
  def initialize
    @data = "".b
  end

  def write(data)
    @data << data.to_s.b
  end

  def rewrite(offset, data)
    @data[offset.to_i, data.to_s.bytesize] = data.to_s.b
  end

  def data
    @data
  end
end

class AudioEncoder
  attr_reader :bytes_read

  def start(output, frequency: 48000, channels: 2, source_channel: nil)
    @output = output
    @frequency = frequency.to_i > 0 ? frequency.to_i : 48000
    @channels = [channels.to_i, 1].max
    @bytes_read = 0
    self
  end

  def process_pcm(data)
    data = data.to_s.b
    @bytes_read += data.bytesize
    feed(data)
  end

  def feed(_data)
    0
  end

  def finish
    close
  end

  def close
  end

  def normalize_source?
    false
  end

  def source_frequency
    48000
  end

  def source_channels(channel)
    EltenRecorderRuntime.source_channels(channel)
  end

  def recording_buffer_bytes
    384000
  end
end
