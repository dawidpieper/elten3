# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 
module EltenBassStructs
  POINTER_SIZE = [nil].pack("p").bytesize
  POINTER_PACK = POINTER_SIZE == 8 ? "Q" : "L"

  class << self
    def pointer_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer.to_s.b.byteslice(offset, POINTER_SIZE) || "".b
      chunk += "\0" * (POINTER_SIZE - chunk.bytesize)
      chunk.unpack(POINTER_PACK).first
    end

    def pointer_bytes(pointer, bytes)
      bytes = bytes.to_i
      return "".b if bytes <= 0
      pointer = pointer.to_i
      raise RangeError, "null native pointer with #{bytes} bytes requested" if pointer == 0
      require "fiddle"
      Fiddle::Pointer.new(pointer).to_s(bytes).b
    end

    def dword_value(buffer, offset = 0)
      return 0 if buffer == nil
      chunk = buffer.to_s.b.byteslice(offset, 4) || "".b
      chunk += "\0" * (4 - chunk.bytesize)
      chunk.unpack("L").first
    end

    def bass_device_info_buffer
      ("\0" * (POINTER_SIZE == 8 ? 24 : 12)).b
    end

    def bass_device_info_values(buffer)
      [pointer_value(buffer, 0), pointer_value(buffer, POINTER_SIZE), dword_value(buffer, POINTER_SIZE * 2)]
    end

    def bass_channel_info_buffer
      ("\0" * (POINTER_SIZE == 8 ? 40 : 32)).b
    end

    def bass_channel_info_values(buffer)
      filename_offset = POINTER_SIZE == 8 ? 32 : 28
      values = []
      for i in 0...7
        values.push(dword_value(buffer, i * 4))
      end
      values.push(pointer_value(buffer, filename_offset))
      values
    end
  end
end

module Bass
  EltenRuntimePaths.configure_dll_search!
  BassLib=EltenRuntimePaths.relative_library_name("bass")
  BassfxLib=EltenRuntimePaths.relative_library_name("bass_fx")
  BassmixLib=EltenRuntimePaths.relative_library_name("bassmix")
  BassvstLib=EltenRuntimePaths.relative_library_name("bass_vst")
  BassencLib=EltenRuntimePaths.relative_library_name("bassenc")
  Bassencmp3Lib=EltenRuntimePaths.relative_library_name("bassenc_mp3")
  BASS_INTPTR = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
  BASS_ABI = EltenSystemHelpers.bass_abi(EltenRuntimePaths.architecture)
  F_INT = Fiddle::TYPE_INT
  F_UINT = Fiddle::TYPE_UINT
  F_PTR = Fiddle::TYPE_VOIDP
  F_FLOAT = Fiddle::TYPE_FLOAT
  F_DOUBLE = Fiddle::TYPE_DOUBLE
  F_QWORD = Fiddle::TYPE_LONG_LONG
  BASS_UNICODE = 0x80000000
  BASS_STREAM_DECODE = 0x200000
  BASS_STREAM_AUTOFREE = 0x40000

  def self.optional_dlopen(lib)
    EltenRuntimePaths.dlopen(lib)
  rescue Exception
    nil
  end

  def self.optional_fiddle(handle, func, import, export, fallback=0)
    return lambda { |*_args| fallback } if handle == nil
    Fiddle::Function.new(handle[func], import, export, BASS_ABI)
  rescue Exception
    lambda { |*_args| fallback }
  end

  BASSDLL = EltenRuntimePaths.dlopen("bass")
  BASSMIX = EltenRuntimePaths.dlopen("bassmix")
  BASSFX = optional_dlopen("bass_fx")
  BASSENC = optional_dlopen("bassenc")
  BASSENCMP3 = optional_dlopen("bassenc_mp3")
  BASSVST = optional_dlopen("bass_vst")
  BASS_GetVersion = Fiddle::Function.new(BASSDLL["BASS_GetVersion"], [], F_INT, BASS_ABI)
  BASS_ErrorGetCode = Fiddle::Function.new(BASSDLL["BASS_ErrorGetCode"], [], F_INT, BASS_ABI)
  BASS_Init = Fiddle::Function.new(BASSDLL["BASS_Init"], [F_INT, F_INT, F_INT, F_PTR], F_INT, BASS_ABI)
  BASS_GetInfo = Fiddle::Function.new(BASSDLL["BASS_GetInfo"], [F_PTR], F_INT, BASS_ABI)
  BASS_RecordInit = Fiddle::Function.new(BASSDLL["BASS_RecordInit"], [F_INT], F_INT, BASS_ABI)
  BASS_RecordGetDevice = Fiddle::Function.new(BASSDLL["BASS_RecordGetDevice"], [], F_INT, BASS_ABI)
  BASS_RecordSetDevice = Fiddle::Function.new(BASSDLL["BASS_RecordSetDevice"], [F_INT], F_INT, BASS_ABI)
  BASS_RecordGetInput = Fiddle::Function.new(BASSDLL["BASS_RecordGetInput"], [F_INT, F_PTR], F_UINT, BASS_ABI)
  BASS_RecordSetInput = Fiddle::Function.new(BASSDLL["BASS_RecordSetInput"], [F_INT, F_UINT, F_FLOAT], F_INT, BASS_ABI)
  BASS_GetConfig = Fiddle::Function.new(BASSDLL["BASS_GetConfig"], [F_INT], F_INT, BASS_ABI)
  BASS_SetConfig = Fiddle::Function.new(BASSDLL["BASS_SetConfig"], [F_INT, F_INT], F_INT, BASS_ABI)
  BASS_SetConfigPtr = Fiddle::Function.new(BASSDLL["BASS_SetConfigPtr"], [F_INT, F_PTR], F_INT, BASS_ABI)
  BASS_GetDevice = Fiddle::Function.new(BASSDLL["BASS_GetDevice"], [], F_INT, BASS_ABI)
  BASS_SetDevice = Fiddle::Function.new(BASSDLL["BASS_SetDevice"], [F_INT], F_INT, BASS_ABI)
  BASS_GetDeviceInfo = Fiddle::Function.new(BASSDLL["BASS_GetDeviceInfo"], [F_INT, F_PTR], F_INT, BASS_ABI)
  BASS_RecordGetDeviceInfo = Fiddle::Function.new(BASSDLL["BASS_RecordGetDeviceInfo"], [F_INT, F_PTR], F_INT, BASS_ABI)
  BASS_PluginLoad = Fiddle::Function.new(BASSDLL["BASS_PluginLoad"], [F_PTR, F_UINT], F_UINT, BASS_ABI)
  BASS_Free = Fiddle::Function.new(BASSDLL["BASS_Free"], [], F_INT, BASS_ABI)
  BASS_RecordFree = Fiddle::Function.new(BASSDLL["BASS_RecordFree"], [], F_INT, BASS_ABI)
  BASS_Apply3D = Fiddle::Function.new(BASSDLL["BASS_Apply3D"], [], F_INT, BASS_ABI)
  BASS_Start = Fiddle::Function.new(BASSDLL["BASS_Start"], [], F_INT, BASS_ABI)
  BASS_Stop = Fiddle::Function.new(BASSDLL["BASS_Stop"], [], F_INT, BASS_ABI)
  BASS_Pause = Fiddle::Function.new(BASSDLL["BASS_Pause"], [], F_INT, BASS_ABI)
  BASS_SetVolume = Fiddle::Function.new(BASSDLL["BASS_SetVolume"], [F_FLOAT], F_INT, BASS_ABI)
  BASS_GetVolume = Fiddle::Function.new(BASSDLL["BASS_GetVolume"], [], F_INT, BASS_ABI)
  BASS_RecordStart = Fiddle::Function.new(BASSDLL["BASS_RecordStart"], [F_UINT, F_UINT, F_UINT, F_PTR, F_PTR], F_UINT, BASS_ABI)
  BASS_StreamCreate = Fiddle::Function.new(BASSDLL["BASS_StreamCreate"], [F_UINT, F_UINT, F_UINT, F_PTR, F_PTR], F_UINT, BASS_ABI)
  BASS_SampleLoad = Fiddle::Function.new(BASSDLL["BASS_SampleLoad"], [F_INT, F_PTR, F_QWORD, F_UINT, F_UINT, F_UINT], F_UINT, BASS_ABI)
  BASS_SampleCreate = Fiddle::Function.new(BASSDLL["BASS_SampleCreate"], [F_UINT, F_UINT, F_UINT, F_UINT, F_UINT], F_UINT, BASS_ABI)
  BASS_SampleFree = Fiddle::Function.new(BASSDLL["BASS_SampleFree"], [F_UINT], F_INT, BASS_ABI)
  BASS_SampleGetChannel = Fiddle::Function.new(BASSDLL["BASS_SampleGetChannel"], [F_UINT, F_INT], F_UINT, BASS_ABI)
  BASS_SampleStop = Fiddle::Function.new(BASSDLL["BASS_SampleStop"], [F_UINT], F_INT, BASS_ABI)
  BASS_StreamCreateFile = Fiddle::Function.new(BASSDLL["BASS_StreamCreateFile"], [F_INT, F_PTR, F_QWORD, F_QWORD, F_UINT], F_UINT, BASS_ABI)
  BASS_StreamCreateURL = Fiddle::Function.new(BASSDLL["BASS_StreamCreateURL"], [F_PTR, F_UINT, F_UINT, F_PTR, F_PTR], F_UINT, BASS_ABI)
  BASS_StreamFree = Fiddle::Function.new(BASSDLL["BASS_StreamFree"], [F_UINT], F_INT, BASS_ABI)
  BASS_ChannelFlags = Fiddle::Function.new(BASSDLL["BASS_ChannelFlags"], [F_UINT, F_UINT, F_UINT], F_UINT, BASS_ABI)
  BASS_ChannelPlay = Fiddle::Function.new(BASSDLL["BASS_ChannelPlay"], [F_UINT, F_INT], F_INT, BASS_ABI)
  BASS_ChannelStop = Fiddle::Function.new(BASSDLL["BASS_ChannelStop"], [F_UINT], F_INT, BASS_ABI)
  BASS_ChannelPause = Fiddle::Function.new(BASSDLL["BASS_ChannelPause"], [F_UINT], F_INT, BASS_ABI)
  BASS_ChannelSetDevice = Fiddle::Function.new(BASSDLL["BASS_ChannelSetDevice"], [F_UINT, F_INT], F_INT, BASS_ABI)
  BASS_StreamPutData = Fiddle::Function.new(BASSDLL["BASS_StreamPutData"], [F_UINT, F_PTR, F_UINT], F_INT, BASS_ABI)
  BASS_ChannelGetData = Fiddle::Function.new(BASSDLL["BASS_ChannelGetData"], [F_UINT, F_PTR, F_UINT], F_INT, BASS_ABI)
  BASS_ChannelGetLength = Fiddle::Function.new(BASSDLL["BASS_ChannelGetLength"], [F_UINT, F_UINT], F_QWORD, BASS_ABI)
  BASS_ChannelGetTags = Fiddle::Function.new(BASSDLL["BASS_ChannelGetTags"], [F_UINT, F_UINT], BASS_INTPTR, BASS_ABI)
  BASS_ChannelGetAttribute = Fiddle::Function.new(BASSDLL["BASS_ChannelGetAttribute"], [F_UINT, F_UINT, F_PTR], F_INT, BASS_ABI)
  BASS_ChannelSetAttribute = Fiddle::Function.new(BASSDLL["BASS_ChannelSetAttribute"], [F_UINT, F_UINT, F_FLOAT], F_INT, BASS_ABI)
  BASS_ChannelSlideAttribute = Fiddle::Function.new(BASSDLL["BASS_ChannelSlideAttribute"], [F_UINT, F_UINT, F_FLOAT, F_UINT], F_INT, BASS_ABI)
  BASS_ChannelIsSliding = Fiddle::Function.new(BASSDLL["BASS_ChannelIsSliding"], [F_UINT, F_UINT], F_INT, BASS_ABI)
  BASS_ChannelIsActive = Fiddle::Function.new(BASSDLL["BASS_ChannelIsActive"], [F_UINT], F_UINT, BASS_ABI)
  BASS_ChannelSeconds2Bytes = Fiddle::Function.new(BASSDLL["BASS_ChannelSeconds2Bytes"], [F_UINT, F_DOUBLE], F_QWORD, BASS_ABI)
  BASS_ChannelBytes2Seconds = Fiddle::Function.new(BASSDLL["BASS_ChannelBytes2Seconds"], [F_UINT, F_QWORD], F_DOUBLE, BASS_ABI)
  BASS_ChannelGetPosition = Fiddle::Function.new(BASSDLL["BASS_ChannelGetPosition"], [F_UINT, F_UINT], F_QWORD, BASS_ABI)
  BASS_ChannelGetInfo = Fiddle::Function.new(BASSDLL["BASS_ChannelGetInfo"], [F_UINT, F_PTR], F_INT, BASS_ABI)
  BASS_ChannelSetPosition = Fiddle::Function.new(BASSDLL["BASS_ChannelSetPosition"], [F_UINT, F_QWORD, F_UINT], F_INT, BASS_ABI)
  BASS_ChannelSet3DPosition = Fiddle::Function.new(BASSDLL["BASS_ChannelSet3DPosition"], [F_UINT, F_PTR, F_PTR, F_PTR], F_INT, BASS_ABI)
  BASS_StreamGetFilePosition = Fiddle::Function.new(BASSDLL["BASS_StreamGetFilePosition"], [F_UINT, F_UINT], F_QWORD, BASS_ABI)
  BASS_FXSetPriority = optional_fiddle(BASSDLL, "BASS_FXSetPriority", [F_UINT, F_INT], F_INT)
  BASS_Mixer_StreamCreate = Fiddle::Function.new(BASSMIX["BASS_Mixer_StreamCreate"], [F_UINT, F_UINT, F_UINT], F_UINT, BASS_ABI)
  BASS_Mixer_StreamAddChannel = Fiddle::Function.new(BASSMIX["BASS_Mixer_StreamAddChannel"], [F_UINT, F_UINT, F_UINT], F_INT, BASS_ABI)
  BASS_Mixer_ChannelRemove = Fiddle::Function.new(BASSMIX["BASS_Mixer_ChannelRemove"], [F_UINT], F_INT, BASS_ABI)
  BASS_Mixer_ChannelGetData = Fiddle::Function.new(BASSMIX["BASS_Mixer_ChannelGetData"], [F_UINT, F_PTR, F_UINT], F_INT, BASS_ABI)
  BASS_Split_StreamCreate = Fiddle::Function.new(BASSMIX["BASS_Split_StreamCreate"], [F_UINT, F_UINT, F_PTR], F_UINT, BASS_ABI)
  BASS_VST_ChannelSetDSP = optional_fiddle(BASSVST, "BASS_VST_ChannelSetDSP", [F_UINT, F_PTR, F_UINT, F_INT], F_UINT)
  BASS_VST_ChannelSetDSPEx = optional_fiddle(BASSVST, "BASS_VST_ChannelSetDSPEx", [F_UINT, F_PTR, F_UINT, F_INT, F_UINT, F_PTR, F_UINT], F_UINT)
  BASS_VST_ChannelRemoveDSP = optional_fiddle(BASSVST, "BASS_VST_ChannelRemoveDSP", [F_UINT, F_UINT], F_INT)
  BASS_VST_GetBypass = optional_fiddle(BASSVST, "BASS_VST_GetBypass", [F_UINT], F_INT)
  BASS_VST_SetBypass = optional_fiddle(BASSVST, "BASS_VST_SetBypass", [F_UINT, F_INT], F_INT)
  BASS_VST_GetParamCount = optional_fiddle(BASSVST, "BASS_VST_GetParamCount", [F_UINT], F_INT)
  BASS_VST_GetParam = optional_fiddle(BASSVST, "BASS_VST_GetParam", [F_UINT, F_UINT], F_FLOAT)
  BASS_VST_SetParam = optional_fiddle(BASSVST, "BASS_VST_SetParam", [F_UINT, F_UINT, F_FLOAT], F_INT)
  BASS_VST_GetParamInfo = optional_fiddle(BASSVST, "BASS_VST_GetParamInfo", [F_UINT, F_UINT, F_PTR], F_INT)
  BASS_VST_GetInfo = optional_fiddle(BASSVST, "BASS_VST_GetInfo", [F_UINT, F_PTR], F_INT)
  BASS_VST_GetProgramCount = optional_fiddle(BASSVST, "BASS_VST_GetProgramCount", [F_UINT], F_INT)
  BASS_VST_GetProgram = optional_fiddle(BASSVST, "BASS_VST_GetProgram", [F_UINT], F_INT)
  BASS_VST_SetProgram = optional_fiddle(BASSVST, "BASS_VST_SetProgram", [F_UINT, F_INT], F_INT)
  BASS_VST_GetProgramName = optional_fiddle(BASSVST, "BASS_VST_GetProgramName", [F_UINT, F_INT], BASS_INTPTR)
  BASS_VST_EmbedEditor = optional_fiddle(BASSVST, "BASS_VST_EmbedEditor", [F_UINT, BASS_INTPTR], F_INT)
  BASS_VST_GetChunk = optional_fiddle(BASSVST, "BASS_VST_GetChunk", [F_UINT, F_INT, F_PTR], BASS_INTPTR)
  BASS_VST_SetChunk = optional_fiddle(BASSVST, "BASS_VST_SetChunk", [F_UINT, F_INT, F_PTR, F_UINT], F_INT)
  BASS_Encode_Start = optional_fiddle(BASSENC, "BASS_Encode_Start", [F_UINT, F_PTR, F_UINT, F_PTR, F_PTR], F_UINT)
  BASS_Encode_Stop = optional_fiddle(BASSENC, "BASS_Encode_Stop", [F_UINT], F_INT)
  BASS_Encode_CastInit = optional_fiddle(BASSENC, "BASS_Encode_CastInit", [F_UINT, F_PTR, F_PTR, F_PTR, F_PTR, F_PTR, F_PTR, F_PTR, F_PTR, F_UINT, F_UINT], F_INT)
  BASS_Encode_Write = optional_fiddle(BASSENC, "BASS_Encode_Write", [F_UINT, F_PTR, F_UINT], F_INT)
  BASS_Encode_MP3_Start = optional_fiddle(BASSENCMP3, "BASS_Encode_MP3_Start", [F_UINT, F_PTR, F_UINT, F_PTR, F_PTR], F_UINT)

  def self.raw_create_url_stream(url, pos = 0, flags = 0, download_proc = 0, user = 0)
    flags |= BASS_UNICODE
    BASS_StreamCreateURL.call(unicode(url.to_s), pos.to_i, flags, download_proc, user)
  end

  def self.create_url_stream(url, pos = 0, flags = 0, download_proc = 0, user = 0)
    prewarm_url_loader if @init == true && @url_loader_prewarm_started != true
    raw_create_url_stream(url, pos, flags, download_proc, user)
  end

  def self.prewarm_url_loader(url = nil)
    return if @url_loader_prewarm_started == true
    return if @init != true
    @url_loader_prewarm_started = true
    warm_url = prewarm_url(url)
    @url_loader_prewarm_thread = Thread.new do
      Thread.current.report_on_exception = false
      begin
        sleep(0.2)
        channel = raw_create_url_stream(warm_url, 0, BASS_STREAM_DECODE)
        BASS_StreamFree.call(channel) if channel != 0
      rescue Exception => e
        Log.debug("Bass URL loader prewarm skipped: #{e.class}: #{e.message}")
      ensure
        @url_loader_prewarmed = true
      end
    end
  end

  def self.prewarm_url(url = nil)
    base = url
    return EltenLink::Client.absolute_api_url("/api/v1/system/build-id") if base == nil || base.to_s == ""

    base = base.to_s
    return base if base.match?(/\Ahttps?:\/\//i)

    EltenLink::Client.absolute_api_url(base)
  end
  
  Errmsg = {
    1=>"MEM",2=>"FILEOPEN",3=>"DRIVER",4=>"BUFLOST",5=>"HANDLE",6=>"FORMAT",7=>"POSITION",8=>"INIT",
    9=>"START",14=>"ALREADY",18=>"NOCHAN",19=>"ILLTYPE",20=>"ILLPARAM",21=>"NO3D",22=>"NOEAX",23=>"DEVICE",
    24=>"NOPLAY",25=>"FREQ",27=>"NOTFILE",29=>"NOHW",31=>"EMPTY",32=>"NONET",33=>"CREATE",34=>"NOFX",
    37=>"NOTAVAIL",38=>"DECODE",39=>"DX",40=>"TIMEOUT",41=>"FILEFORM",42=>"SPEAKER",43=>"VERSION",44=>"CODEC",
    45=>"ENDED",-1=>" UNKNOWN"
  }

  def self.error_name(code = nil)
    code = BASS_ErrorGetCode.call if code == nil
    "BASS_ERROR_#{Errmsg[code] || code}"
  rescue Exception
    "BASS_ERROR_UNKNOWN"
  end

  def self.remember_stream_data(channel, data, auto_free = false)
    return if channel.to_i == 0 || data == nil
    @@memory_stream_data ||= {}
    @@memory_stream_data[channel.to_i] = [data, auto_free == true]
  end

  def self.release_stream_data(channel)
    @@memory_stream_data ||= {}
    @@memory_stream_data.delete(channel.to_i)
  end

  def self.cleanup_memory_streams
    @@memory_stream_data ||= {}
    @@memory_stream_data.keys.each do |channel|
      _data, auto_free = @@memory_stream_data[channel]
      next if auto_free != true
      @@memory_stream_data.delete(channel) if BASS_ChannelIsActive.call(channel.to_i) == 0
    rescue Exception
      @@memory_stream_data.delete(channel)
    end
  end

  def self.create_file_stream_from_memory(data, flags)
    data = data.to_s.b
    source = BASS_StreamCreateFile.call(1, data, 0, data.bytesize, flags)
    if source.to_i == 0 && BASS_ErrorGetCode.call == 41 && data.byteslice(0, 4) == "OggS"
      wave = decode_ogg_vorbis_to_wave(data)
      if wave != nil
        source = BASS_StreamCreateFile.call(1, wave, 0, wave.bytesize, flags)
        remember_stream_data(source, wave, (flags.to_i & BASS_STREAM_AUTOFREE) != 0) if source.to_i != 0
      end
    end
    source
  end

  def self.create_file_stream_from_path(filename, pos = 0, flags = 0, tries = 1)
    source = 0
    tries.times do
      source = BASS_StreamCreateFile.call(0, unicode(filename), pos.to_i, 0, flags | BASS_UNICODE | 0x20000)
      break if source.to_i != 0
      sleep(0.01) if tries > 1
    end
    if source.to_i == 0 && BASS_ErrorGetCode.call == 41 && pos.to_i == 0 && File.file?(filename.to_s)
      data = File.binread(filename)
      source = create_file_stream_from_memory(data, flags)
    end
    source
  end

  def self.decode_ogg_vorbis_to_wave(data)
    require_relative "oggvorbis" unless defined?(OggVorbis)
    OggVorbis.decode_to_wave(data)
  rescue Exception => e
    Log.warning("Ogg Vorbis fallback failed: #{e.class}: #{e.message}")
    nil
  end

  class Device
    attr_accessor :name, :driver, :flags
    def initialize(name="", driver="", flags=0)
      @name=name
      @driver=driver
      @flags=flags
      end
    def enabled?
      (@flags&1)!=0
    end
    def disabled?
      !enabled?
      end
      def default?
        (@flags&2)!=0
      end
      def initialized?
        (@flags&4)!=0
      end
            def loopback?
        (@flags&8)!=0
      end
      end
  
  def self.soundcards
    BASS_SetConfig.call(36, 1)
    BASS_SetConfig.call(42, 1)
    ret=[]
    index=0
      tmp=EltenBassStructs.bass_device_info_buffer
      cds={}
      while BASS_GetDeviceInfo.call(index,tmp)>0
        a=EltenBassStructs.bass_device_info_values(tmp)
                sc=c_string(a[0])
                if sc==""
                  index+=1
                  next
                end
                name=sc
                driver=""
                flags=a[2]
                cds[name]||=0
                cds[name]+=1
                name+=" (#{cds[name]})" if cds[name]>1
                ret.push(Device.new(name, driver, flags))
        index+=1
      end
    return ret
    end

    def self.microphones
          BASS_SetConfig.call(42, 1)
      microphones=[]
        index=0
      tmp=EltenBassStructs.bass_device_info_buffer
      cds={}
      while BASS_RecordGetDeviceInfo.call(index,tmp)>0
        a=EltenBassStructs.bass_device_info_values(tmp)
                sc=c_string(a[0])
                if sc==""
                  index+=1
                  next
                end
                driver=""
                flags=a[2]
                cds[sc]||=0
                                cds[sc]+=1
                                sc+=" (#{cds[sc]})" if cds[sc]>1
                                microphones.push(Device.new(sc, driver, flags))
               index+=1
             end
                           return microphones
    end

    def self.c_string(address)
      address=address.to_i
      return "" if address==0
      if readable_memory?(address, 2)
        head=Fiddle::Pointer.new(address)[0, 2]
        return wide_c_string(address) if head!=nil && head.bytesize==2 && head.getbyte(1)==0
      end
      narrow_c_string(address)
    rescue
      ""
    end

    def self.narrow_c_string(address)
      bytes=+""
      offset=0
      while offset<4096
        break if !readable_memory?(address+offset, 1)
        byte=Fiddle::Pointer.new(address+offset)[0, 1]
        break if byte==nil || byte.bytesize==0 || byte.getbyte(0)==0
        bytes<<byte
        offset+=1
      end
      bytes.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
    rescue
      ""
    end

    def self.wide_c_string(address)
      bytes=+""
      offset=0
      while offset<4096
        break if !readable_memory?(address+offset, 2)
        chunk=Fiddle::Pointer.new(address+offset)[0, 2]
        break if chunk==nil || chunk.bytesize<2 || (chunk.getbyte(0)==0 && chunk.getbyte(1)==0)
        bytes<<chunk
        offset+=2
      end
      bytes.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    rescue
      ""
    end

    def self.readable_memory?(address, length)
      defined?(EltenSystemHelpers) && EltenSystemHelpers.readable_memory?(address, length)
    rescue
      false
    end
    
    def self.setdevice(d,hWnd=nil, samplerate=48000)
      $soundthemesounds.values.each {|g| g.close if g!=nil and !g.closed?} if $soundthemesounds!=nil
      $soundthemesounds={}
            hWnd||=$wnd||0
            @@device=d
            if @init==true
            BASS_Free.call
      BASS_Init.call(d, samplerate, 4, hWnd)
      BASS_SetDevice.call(d)
    else
      @setdeviceoninit=d
      end
    end

    def self.set_card(card, hWnd=nil, samplerate=48000)
      c=-1
      if card!=nil && card!="default"
        cards=soundcards
        c=cards.map{|dev|dev.name}.index(card)||-1
      end
      setdevice(c, hWnd, samplerate)
      c
    end

    def self.cardid
      dev=BASS_GetDevice.call
      return dev if dev.to_i>0
      @@device||-1
    rescue Exception
      @@device||-1
    end

    def self.initialized?
      @init==true
    end
    
    @@recorddevice=-1
    @@recordinit=false
    def self.setrecorddevice(i)
      @@recorddevice=i
      BASS_RecordFree.call if @@recordinit
      @@recordinit=false
      end
    
    def self.reset
      self.setdevice(@@device)
    end
    
    def self.test
      filename=EltenPath.join(ENV['WINDIR'], "Media", "tada.wav")
      h=create_file_stream_from_path(filename, 0, BASS_STREAM_DECODE)
      if h==0
        return false
      end
      begin
              bass_FX_TempoCreate ||= Bass.optional_fiddle(BASSFX, "BASS_FX_TempoCreate", [F_UINT, F_UINT], F_UINT)
                      ch = bass_FX_TempoCreate.call(h, 0)
         if ch==0
        BASS_StreamFree.call(h)
           return false
      end             
                    rescue Exception
                      BASS_StreamFree.call(h)
                      return false
                                            end
                      BASS_StreamFree.call(h)
      return true
    end
    
    def self.record_prepare
      if @@recordinit==false
              return false if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:prepare_os_microphone) && EltenSystemHelpers.prepare_os_microphone != true
              r=BASS_RecordInit.call(@@recorddevice)
              if r==0
                fl=BASS_GetConfig.call(66)
                t=0
                t=1 if fl==0
                BASS_SetConfig.call(66, t)
                Log.warning("Record fallback to Wasapi") if fl==0
                Log.warning("Record fallback to DirectSound") if fl==1
                r=BASS_RecordInit.call(@@recorddevice)
                BASS_SetConfig.call(66, fl)
              end
              if r==0
                Log.error("BASS_RecordInit failed: #{error_name(BASS_ErrorGetCode.call)}")
                return false
              end
              @@recorddevice=BASS_RecordGetDevice.call if @@recorddevice==-1
              BASS_RecordSetDevice.call(@@recorddevice)
              @@recordinit=true
              end
            return true
            rescue Exception
              Log.error($!.to_s)
              false
            end

    def self.record_resetdevice
      BASS_RecordSetDevice.call(@@recorddevice)
    end
            
            def self.version
              v=BASS_GetVersion.call
              return [v].pack("I").unpack("CCCC").map{|s|s.to_s}.reverse.join(".")
              end
    
  def self.init(hWnd, samplerate = 48000)
return if @init==true
    @init=true
    BASS_SetConfig.call(36, 1)
    BASS_SetConfig.call(42, 1)
      devs=[]
     card=-1
     card=@setdeviceoninit if @setdeviceoninit!=nil
    @@device=card
        if BASS_Init.call(card, samplerate, 4, hWnd) == 0
      raise(error_name)
    end
    plugins = ["bassopus", "bassflac", "bassmidi", "basswebm", "basswma", "bass_aac", "bass_ac3", "bass_spx", "basshls", "bassalac"]
        for pl in plugins
              Log.debug("Loading Bass plugin #{pl}")
          plugin_path = EltenRuntimePaths.absolute_library_file(pl)
          if BASS_PluginLoad.call(plugin_path, 0) == 0
            error=BASS_ErrorGetCode.call
            Log.warning("Failed to load Bass plugin #{pl}: #{error_name(error)} (#{plugin_path})") if error!=14
          end
    end
        BASS_SetConfig.call(0, 1000)
BASS_SetConfig.call(1, 100)
BASS_SetConfig.call(11, 3000)
BASS_SetConfig.call(12, 10000)
BASS_SetConfig.call(15, 25)
BASS_SetConfigPtr.call(16, "Elten")
BASS_SetConfig.call(21, 1)
BASS_SetConfig.call(0x20000, 0)    
BASS_SetDevice.call(card) if card>0
prewarm_url_loader
        end

  def self.free
    @init=false
    if BASS_Free.call == 0 then
      raise(error_name)
    end
  end

  def self.create_stream_channel(filename, pos = 0, stream = nil, tries = 10)
    pos = pos.to_i
    flags = 256
    flags |= BASS_STREAM_DECODE if Configuration.usefx == true
    source = 0
    if filename == nil && stream != nil
      source = create_file_stream_from_memory(stream, flags)
    elsif filename != nil && filename[0, 4] == "http"
      source = Bass.create_url_stream(filename, pos, flags, 0, 0)
    else
      source = create_file_stream_from_path(filename, pos, flags, tries)
    end
    if source == 0
      Log.error("BASS stream open failed: #{error_name}, file=#{filename.inspect}, memory=#{stream&.bytesize || 0}, flags=#{flags}, runtime=#{EltenRuntimePaths.runtime_directory_name}")
      return [0, 0]
    end
    if Configuration.usefx == true
      @@BASS_FX_TempoCreate ||= Bass.optional_fiddle(BASSFX, "BASS_FX_TempoCreate", [F_UINT, F_UINT], F_UINT)
      channel = @@BASS_FX_TempoCreate.call(source, 0)
      return [source, source] if channel == 0
      [source, channel]
    else
      [source, source]
    end
  end

  def self.create_sample_channel(filename, max = 1)
    return [0, 0] if filename == nil
    handle = BASS_SampleLoad.call(0, unicode(filename), 0, 0, max, 0x20000 | BASS_UNICODE | 256)
    if handle == 0
      Log.error("BASS sample open failed: #{error_name}, file=#{filename.inspect}, runtime=#{EltenRuntimePaths.runtime_directory_name}")
      return [0, 0]
    end
    channel = BASS_SampleGetChannel.call(handle, 0)
    Log.error("BASS sample channel failed: #{error_name}, file=#{filename.inspect}, runtime=#{EltenRuntimePaths.runtime_directory_name}") if channel == 0    [handle, channel]
  end
end

module Bass
class VST
  @@shown=0

  class Parameter
    attr_reader :name, :unit, :display, :default, :value

    def initialize(vst, index)
      @vst, @index = vst, index
      reload
    end

    def value=(v)
      BASS_VST_SetParam.call(@vst, @index, v.to_f)
      reload
      @value
    end

    def reload
      pc="A16A16A16f"
      n=["", "", "", 0.0].pack(pc)
      BASS_VST_GetParamInfo.call(@vst, @index, n)
      @name, @unit, @display, @default = n.unpack(pc)
      @name = @name.force_encoding("UTF-8")
      @unit = @unit.force_encoding("UTF-8")
      @display = @display.force_encoding("UTF-8")
      @value = BASS_VST_GetParam.call(@vst, @index)
    end
  end

  def initialize(file, channel, priority=0)
    @file=file
    @priority=priority
    flags=0x80000000|0x1
    @vst = BASS_VST_ChannelSetDSP.call(channel, unicode(file), flags, priority)
    @channel=channel
  end

  def priority
    @priority
  end

  def priority=(pr)
    h=info[17]
    BASS_FXSetPriority.call(h, pr)
    @priority=pr
  end

  def loaded?
    @vst!=0
  end

  def free
    BASS_VST_ChannelRemoveDSP.call(@channel, @vst)
    @channel=@vst=0
  end

  def parameters
    cnt = BASS_VST_GetParamCount.call(@vst)
    params=[]
    for i in 0...cnt
      params.push(Parameter.new(@vst, i))
    end
    params
  end

  def bypass
    BASS_VST_GetBypass.call(@vst)!=0
  end

  def bypass=(b)
    BASS_VST_SetBypass.call(@vst, b==true ? 1 : 0)
    bypass
  end

  def program
    BASS_VST_GetProgram.call(@vst)
  end

  def program=(g)
    BASS_VST_SetProgram.call(@vst, g)
    program
  end

  def name
    info[2].force_encoding("UTF-8")
  end

  def version
    info[3]
  end

  def unique_id
    info[1]
  end

  def editor?
    info[12]!=0
  end

  def editor_shown?
    @editor_shown==true
  end

  def editor_show
    editor_hide
    @@shown+=1
    @editor_shown=true
    BASS_VST_EmbedEditor.call(@vst, ($wnd||0).to_i)
  end

  def editor_hide
    return if @editor_shown!=true
    BASS_VST_EmbedEditor.call(@vst, 0)
    @@shown-=1 if @@shown>0
    @editor_shown=false
  end

  def file
    @file
  end

  def programs
    count = BASS_VST_GetProgramCount.call(@vst)
    programs=[]
    for i in 0...count
      ptr = BASS_VST_GetProgramName.call(@vst, i)
      programs[i]=Bass.c_string(ptr).force_encoding("UTF-8")
    end
    programs
  end

  def export(type=:preset)
    return nil if type!=:preset && type!=:bank
    pr = type==:bank ? 0 : 1
    pt=[0].pack("I")
    ptr=BASS_VST_GetChunk.call(@vst, pr, pt)
    len=pt.unpack("I").first
    return "".b if ptr.to_i==0 || len.to_i<=0
    Fiddle::Pointer.new(ptr.to_i).to_s(len)
  end

  def import(type=:preset, value)
    return nil if type!=:preset && type!=:bank
    pr = type==:bank ? 0 : 1
    BASS_VST_SetChunk.call(@vst, pr, value.to_s.b, value.to_s.bytesize)
  end

  private

  def info
    pc="IIA80IIIA80A80IIIIIIIIIi"
    nfo = [0, 0, "\0"*80, 0, 0, 0, "\0"*80, "\0"*80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].pack(pc)
    BASS_VST_GetInfo.call(@vst, nfo)
    nfo.unpack(pc)
  end
end
end
