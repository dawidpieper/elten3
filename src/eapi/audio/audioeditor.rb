module EltenAPI
  class AudioEditor
    def verify
      raise(RuntimeError, "Already closed") if @tempfile==nil
      end
    def initialize(type=:file, content=nil, frequency=nil, channels=nil)
          @tempfilename = EltenPath.join(Dirs.temp, "audioedit_#{rand(36**16).to_s(36)}.tmp")
          @tempfile = File.open(@tempfilename, "w+b")
                    if type==:file
                      cha=nil
                      file=content
if file[0..4]=="http:" || file[0..5]=="https:"
  cha = Bass.create_url_stream(file, 0, 0x200000|131072|256, 0, 0)
else
cha = Bass.create_file_stream_from_path(file, 0, 0x200000|131072|256)
end                      
  rinfo=EltenNativeStructs.bass_channel_info_buffer
           Bass::BASS_ChannelGetInfo.call(cha, rinfo)
           info=EltenNativeStructs.bass_channel_info_values(rinfo)
           @channels=info[1]           
@frequency=info[0]           
@tempfile.write([@frequency, @channels, 0].pack("IIQ"))
bufsize = 2097152
buf="\0"*bufsize
t=0
while (sz=Bass::BASS_ChannelGetData.call(cha, buf, bufsize))>0 || ((file[0..4]=="http:" || file[0..5]=="https:") && Bass::BASS_StreamGetFilePosition.call(cha, 4)==1)
  loop_update
    @tempfile.write(buf[0...sz])
  t+=sz
end
Bass::BASS_StreamFree.call(cha)
@tempfile.seek(8)
@tempfile.write([t].pack("Q"))
else
  @frequency=frequency
  @channels=channels
  @tempfile.write([@frequency, @channels, content.bytesize/4].pack("IIQ"))
  @tempfile.write(content)
end
@left=0
@right=size
end
def size
  verify
  @tempfile.pos=8
  @tempfile.read(8).unpack("Q").first
end
def play(from=0, to=-1)
  verify
  to=size+to if to<0
  from,to=to,from if to<from
  
end
def stop
  verify
  
end
def free
  verify
  stop
  @tempfile.close
  File.delete(@tempfilename) if File.file?(@tempfilename)
  @tempfile=nil
end

    end
  end
