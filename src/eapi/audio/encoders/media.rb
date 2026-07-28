# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module MediaEncoders
  @@encoders=[]
  class <<self
    include EltenAPI
    def register(cls)
      return if !cls.is_a?(Class)
        EltenAPI::Log.debug("Registering media encoder #{cls.to_s}")
      @@encoders.push(cls)
    end
    def unregister(cls)
      Log.debug("Unregistering media encoder #{cls}")
            @@encoders.delete(cls)
    end
    def delete_all
      Log.info("Flushing media encoders")
      c=@@encoders.size
            unregister @@encoders[0] while @@encoders.size>0
            return c
      end
      def list
        return [OpusEncoder, VorbisEncoder, WaveEncoder]+@@encoders
      end
  end
  end

class MediaEncoder
  Type=:audio
  Extension="."
  IsBitrateSupported=true
  Name=""
  SupportsPcmStream=false
  def self.encode_file(file, output, bitrate=nil)
    bitrate=64 if bitrate==nil
    return false
    end
  def self.audio_encoder(bitrate=nil)
    nil
  end
  end
  
  class OpusEncoder < MediaEncoder
  Type=:audio
  Extension=".opus"
  Name="Opus"
  IsBitrateSupported=true
  SupportsPcmStream=true
  def self.encode_file(file, output, bitrate=nil)
    bitrate=64 if bitrate==nil
    Recorder.encode_opus_file(file, output, bitrate)
    return true
    end
  def self.audio_encoder(bitrate=nil)
    bitrate=64 if bitrate==nil
    Recorder.opus_encoder(bitrate)
    end
  end
  
  class VorbisEncoder < MediaEncoder
  Type=:audio
  Extension=".ogg"
  Name="Ogg Vorbis"
  IsBitrateSupported=true
  SupportsPcmStream=true
  def self.encode_file(file, output, bitrate=nil)
    bitrate=96 if bitrate==nil
    Recorder.encode_vorbis_file(file, output, bitrate)
    return true
    end
  def self.audio_encoder(bitrate=nil)
    bitrate=96 if bitrate==nil
    Recorder.vorbis_encoder(bitrate)
    end
  end
  
  class WaveEncoder < MediaEncoder
  Type=:audio
  Extension=".wav"
  Name="Wave PCM"
  IsBitrateSupported=false
  SupportsPcmStream=true
  def self.encode_file(file, output, bitrate=nil)
    Recorder.encode_wave_file(file, output)
    return true
    end
  def self.audio_encoder(bitrate=nil)
    Recorder.wave_encoder
    end
  end
