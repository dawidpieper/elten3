# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 



class EltenAPI::Conference::Core
class << self
def ogg_stream_state_buffer
  if EltenNativeStructs::POINTER_SIZE == 8
    "\0" * 376
  else
    ([nil, 0, 0, 0, 0, 0, 0, 0, 0, 0]+[0]*282+[0,0,0,0,0,0,0]).pack("piiiiqiiii"+"C"*282+'iiiiiqq')
  end
end

def ogg_page_buffer
  "\0" * (EltenNativeStructs::POINTER_SIZE == 8 ? 32 : 16)
end

def ogg_page_values(buffer)
  if EltenNativeStructs::POINTER_SIZE == 8
    [EltenNativeStructs.pointer_value(buffer, 0), EltenNativeStructs.dword_value(buffer, 8), EltenNativeStructs.pointer_value(buffer, 16), EltenNativeStructs.dword_value(buffer, 24)]
  else
    [EltenNativeStructs.pointer_value(buffer, 0), EltenNativeStructs.dword_value(buffer, 4), EltenNativeStructs.pointer_value(buffer, 8), EltenNativeStructs.dword_value(buffer, 12)]
  end
end

def ogg_packet(data, bytes, b_o_s, e_o_s, granulepos, packetno)
  buffer = "\0" * (EltenNativeStructs::POINTER_SIZE == 8 ? 40 : 32)
  if EltenNativeStructs::POINTER_SIZE == 8
    EltenNativeStructs.set_pointer(buffer, 0, data)
    EltenNativeStructs.set_dword(buffer, 8, bytes)
    EltenNativeStructs.set_dword(buffer, 12, b_o_s)
    EltenNativeStructs.set_dword(buffer, 16, e_o_s)
    buffer[24, 8] = [granulepos.to_i].pack("q")
    buffer[32, 8] = [packetno.to_i].pack("q")
  else
    EltenNativeStructs.set_pointer(buffer, 0, data)
    EltenNativeStructs.set_dword(buffer, 4, bytes)
    EltenNativeStructs.set_dword(buffer, 8, b_o_s)
    EltenNativeStructs.set_dword(buffer, 12, e_o_s)
    buffer[16, 8] = [granulepos.to_i].pack("q")
    buffer[24, 8] = [packetno.to_i].pack("q")
  end
  buffer
end

def ogg_packet_set_eos(buffer, e_o_s)
  EltenNativeStructs.set_dword(buffer, EltenNativeStructs::POINTER_SIZE == 8 ? 16 : 12, e_o_s)
end
end

class ChannelPosition
attr_accessor :x, :y, :dir
attr_reader :mutex
def initialize
@x, @y = 0, 0
@dir = 0
@mutex=Mutex.new
end
end

class WaitingUser
attr_accessor :id, :name
end

class Transmitter
attr_reader :decoder, :stream
attr_reader :listener_x, :listener_y, :transmitter_x, :transmitter_y
attr_reader :username
attr_reader :losses
attr_accessor :speech_requested
attr_accessor :chat_temp
def initialize(channels, framesize, preskip, starttime, spatialization, position, username, volume=nil)
@channels=channels
@framesize=framesize
@lastframetime=starttime
@preskip=preskip
@listener_dir=0
@listener_x=-1
@listener_y=-1
@position=position
@absolute_x=0
@absolute_y=0
@transmitter_x=-1
@transmitter_y=-1
@decoder = Opus::Decoder.new(48000, channels)
@losses=[]
@vst_lastpriority = 2**31
@vsts=[]
@pvsts=[]
flags=0x200000
flags|=256 if spatialization==1 || spatialization==2
ch=@channels
ch=2 if spatialization==1 || spatialization==2
@stream = Bass::BASS_StreamCreate.call(48000, ch, flags, -1, nil)
@whisper = Bass::BASS_StreamCreate.call(48000, ch, flags, -1, nil)
@preprocessor=nil
@vst_target = @stream
@predecoder=nil
@preencoder=nil
@username=username
@hrtf=nil
@hrtf_effect=nil
@spatialization=spatialization
@speech_requested=false
@mutex = Mutex.new
setvolume(volume)
@sec=0
@fsec=0
@queue={}
@starttime=Time.now.to_f
@lasttime=Time.now.to_f
@ogg_mutex=Mutex.new
@thread=Thread.new{thread}
@chat_temp=""
end
def set_mixer(mixer, whispermixer)
return if @channel_mixer==mixer
@channel_mixer=mixer
@mutex.synchronize {
Bass::BASS_Mixer_StreamAddChannel.call(mixer, @stream, 0)
Bass::BASS_Mixer_StreamAddChannel.call(whispermixer, @whisper, 0)
}
end
def setvolume(volume)
if volume.is_a?(Array)
vol=volume[0]
@volume=vol
else
@volume=100
end
update_position
end
def move_absolute(x,y)
@absolute_x, @absolute_y = x,y
end
def move(nx, ny)
return if nx<=0||ny<=0
@transmitter_x=nx
@transmitter_y=ny
update_position
end	
def update_position
@listener_x=@position.x
@listener_y=@position.y
@listener_dir = @position.dir
if @spatialization==0 || @spatialization==1
if @listener_y>0 && @listener_x>0 && @transmitter_x>0 && @transmitter_y>0
@rx=(@transmitter_x-@listener_x)/8.0
@ry=(@transmitter_y-@listener_y)/8.0
if @position.dir!=0
sn = Math::sin(Math::PI/180*-@listener_dir)
cs = Math::cos(Math::PI/180*-@listener_dir)
px = @rx * cs - @ry * sn; 
py = @rx * sn + @ry * cs;
@rx=px
@ry=py
end
pos=@rx
pos=-1 if pos<-1
pos=1 if pos>1
vl=@volume/100.0
if @volume>100
vl=1+(@volume-100)/10.0
end
vol=(1-Math::sqrt((@ry.abs*0.5)**2+(@rx.abs*0.5)**2))*vl
vol=0 if vol<0
@mutex.synchronize {
if @spatialization==0
Bass::BASS_ChannelSetAttribute.call(@stream, 3, pos)
Bass::BASS_ChannelSetAttribute.call(@whisper, 3, pos)
end
if @spatialization==0 || @spatialization==1
Bass::BASS_ChannelSetAttribute.call(@stream, 2, vol)
Bass::BASS_ChannelSetAttribute.call(@whisper, 2, vol)
end
}
end
end
end
def set_hrtf(hrtf)
@mutex.synchronize {
@hrtf=hrtf
@hrtf_effect=nil
@hrtf_effect = @hrtf.add_effect(@channels) if @hrtf!=nil
}
end
def reset
@mutex.synchronize {
@decoder.reset
}
end
def begin_save(dir, id, savetime)
@ogg_mutex.synchronize {
msec=((Time.now.to_f-savetime)*1000).round
file=dir+"/transmitters/#{msec}_#{id}_#{@username}.opus"
@lastframetime=savetime
@ogg=EltenAPI::Conference::Core.ogg_stream_state_buffer
@ogg_file=File.open(file, "wb")
@ogg_lastpacket=nil
$ogg_stream_init.call(@ogg, rand(2**32)-2**31)
head="OpusHead".b
head+=[1].pack("C")
head+=[@channels].pack("C")
head+=[@preskip].pack("S")
head+=[48000].pack("I")
head+=[0].pack("S")
head+=[0].pack("C")
@packetno=0
@granulepos=0
ogg_addpacket(head, true, false)
tags="OpusTags".b
ver=Opus.version.to_s.b
tags+=[ver.bytesize].pack("I")
tags+=ver
tags+=[1].pack("I")
encinfo="ENCODER=ELTEN"
tags+=[encinfo.bytesize].pack("I")
tags+=encinfo
ogg_addpacket(tags, false, false, false)
}
end
def ogg_addpacket(data, b_o_s=false, e_o_s=false, writepages=true)
if @ogg_lastpacket!=nil
$ogg_stream_packetin.call(@ogg, @ogg_lastpacket);
if writepages
og=EltenAPI::Conference::Core.ogg_page_buffer
while $ogg_stream_pageout.call(@ogg, og) != 0
page=EltenAPI::Conference::Core.ogg_page_values(og)
head=EltenNativeStructs.pointer_bytes(page[0], page[1])
body=EltenNativeStructs.pointer_bytes(page[2], page[3])
@ogg_file.write(head)
@ogg_file.write(body)
end
end
end
if data!=nil
@packetno+=1
@ogg_lastpacket_data=data
@ogg_lastpacket=EltenAPI::Conference::Core.ogg_packet(@ogg_lastpacket_data, data.bytesize, (b_o_s)?(1):(0), (e_o_s)?(1):(0), @granulepos, @packetno)
end
end
def end_save
return if @ogg==nil
@ogg_mutex.synchronize {
ogg_addpacket("") if @ogg_lastpacket==nil
EltenAPI::Conference::Core.ogg_packet_set_eos(@ogg_lastpacket, 1)
ogg_addpacket(nil)
@ogg_file.close
$ogg_stream_clear.call(@ogg)
@ogg=@ogg_file=nil
}
end
def put(frame, type=1, x=-1, y=-1, frame_id=0, index=-1)
@lastindex||=0
if @thread!=nil && @thread.status!=false
n=index
n+=65535 if n<100
if @lastindex<index || index<100
@queue[n]=@lastqueue=[frame, type, x, y, index, frame_id]
@thread.wakeup
@lastindex=index
end
end
end
def free
end_save if @ogg!=nil
@mutex.synchronize {
Bass::BASS_StreamFree.call(@stream)
Bass::BASS_StreamFree.call(@whisper)
Bass::BASS_StreamFree.call(@preprocessor) if @preprocessor!=nil
@predecoder.free if @predecoder!=nil
@preencoder.free if @preencoder!=nil
@decoder.free
@stream=nil
@preprocessor = @preencoder = @predecoder = @decoder=nil
}
@thread.exit if @thread!=nil
rescue Exception
log(2, "Conference: Transmitter free error: "+$!.to_s+" "+$@.to_s)
end
def set_vst_target(target=:stream)
t=nil
if target == :preprocessor
preprocessor_init
end
if target==:stream
t=@stream
elsif target==:preprocessor && @preprocessor!=nil
t=@preprocessor
end
return if t==nil
@vst_target = t
for i in 0...@vsts.size
v=Bass::VST.new(@vsts[i].file, t, @vsts[i].priority)
v.import(:bank, @vsts[i].export(:bank))
@vsts[i].free
@vsts[i]=v
end
end
def preprocessor_init
if @preprocessor==nil
@preprocessor = Bass::BASS_StreamCreate.call(48000, @channels, 0x200000, -1, nil)
@predecoder = Opus::Decoder.new(48000, @channels)
@preencoder = Opus::Encoder.new(48000, @channels)
end
end
def preprocess(frame, bitrate=128)
preprocessor_init
dt = @predecoder.decode(frame)
@preencoder.bitrate = bitrate*1000
Bass::BASS_StreamPutData.call(@preprocessor, dt, dt.bytesize)
nd=""
while nd.bytesize<dt.bytesize
plc="\0"*(dt.bytesize-nd.bytesize)
Bass::BASS_ChannelGetData.call(@preprocessor, plc, plc.bytesize)
nd+=plc
end
nframe = @preencoder.encode(nd, dt.bytesize/2.0/@channels)
nframe
end
def vsts
@vsts
end
def vst_remove(index)
v=@vsts[index]
if v!=nil
@vsts.delete_at(index)
v.free
end
end
def vst_add(file)
return if @vst_lastpriority<8
@vst_lastpriority-=1
v=Bass::VST.new(file, @vst_target, @vst_lastpriority)
@vsts.push(v)
end
def vst_move(index, pos)
@vsts.insert(pos, @vsts.delete_at(index))
vsts_reprioritize
end
def vsts_reprioritize
@vst_lastpriority = 2**31
for i in 0...@vsts.size
@vst_lastpriority -= 1
@vsts[i].priority=@vst_lastpriority
end
end
private
def thread
last_frame_id=0
loop {
sleep(0.001)
ab=$conferencesaudiobuffer||0
ab=0 if ab<0
ab=400 if ab>400
while @queue.size>ab
key=@queue.keys.sort.first
ar = @queue[key]
frame, type, x, y, index, frame_id = ar
@queue.delete(key)
fid=frame_id
fid+=60000 if fid>0 && fid<100 && last_frame_id>59000
lostframes=0
if last_frame_id!=0
if frame_id==0
lostframes=((Time.now.to_f-@lastframetime-@framesize/1000.0)/(@framesize/1000.0)).floor
else
lostframes = fid-last_frame_id-1
@losses.push(lostframes)
@losses.delete_at(0) while @losses.size>6000
lf=lostframes
lf=3 if lf>3
lf.times {
pcm=""
if lostframes==1
pcm=@decoder.decode(nil) if @decoder!=nil
else
pcm=@decoder.decode(frame, true) if @decoder!=nil
end
out=""
if @spatialization==1 || @spatialization==2
out = pcm.unpack("s"*(pcm.bytesize/2)).map{|s|s/32768.0}.pack("f"*(pcm.bytesize/2))
suc=false
if @hrtf!=nil && ((@rx!=nil && @ry!=nil) || @spatialization==2)
suc=true
if @spatialization==1 && (@rx!=0 || @ry!=0)
rx=@rx
rz=@ry
ry=0
ry=-0.2 if @spatialization==2
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
elsif @spatialization==2
rx=@absolute_x
rz=@absolute_y
ry=0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
else
rx=@rx
rz=@ry
ry=0
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
end
else
rout = out.unpack("f"*(out.bytesize/4))
fout=[]
rout.each{|f|fout.push(f,f)}
out=fout.pack("f"*fout.size)
end
else
out=pcm
end
stream=@stream
stream=@whisper if type==3
Bass::BASS_StreamPutData.call(stream, out, out.bytesize) if stream!=nil
}
end
end
last_frame_id=frame_id
if x!=nil && y!=nil && x>0 && y>0
if @spatialization==0 || @spatialization==1
if x!=@transmitter_x || y!=@transmitter_y || @listener_x!=@position.x || @listener_y!=@position.y || @listener_dir!=@position.dir
@position.mutex.synchronize {
move(x,y)
}
end
end
end
@ogg_mutex.synchronize {
if @ogg!=nil
if lostframes>0
e=Opus::Encoder.new(48000, @channels)
fr=e.encode("\0"*@framesize*48*2*@channels, 48*@framesize)
e.free
lostframes.times {
@granulepos+=@framesize*48
ogg_addpacket(fr)
}
end
@granulepos+=@framesize*48
ogg_addpacket(frame)
end
}
@lastframetime=Time.now.to_f
@mutex.synchronize {
pcm=""
pcm=@decoder.decode(frame) if @decoder!=nil
if @sec!=Time.now.to_i
@sec=Time.now.to_i
@fsec=0
end
@fsec+=1
out=""
if @spatialization==1 || @spatialization==2
out = pcm.unpack("s"*(pcm.bytesize/2)).map{|s|s/32768.0}.pack("f"*(pcm.bytesize/2))
suc=false
if @hrtf!=nil && ((@rx!=nil && @ry!=nil) || @spatialization==2)
if @spatialization!=2
suc=true
rx=@rx
rz=@ry
ry=0
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
else
rx=@absolute_x
rz=@absolute_y
ry=0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
end
else
rout = out.unpack("f"*(out.bytesize/4))
fout=[]
rout.each{|f|fout.push(f,f)}
out=fout.pack("f"*fout.size)
end
else
out=pcm
end
stream=@stream
stream=@whisper if type==3
ps=0
ps=Bass::BASS_StreamPutData.call(stream, out, out.bytesize) if @stream!=nil
ps+=Bass::BASS_ChannelGetData.call(stream, nil, 0) if stream!=nil
fl=2
fl=4 if @spatialization==1 || @spatialization==2
ch=@channels
ch=2 if @spatialization==1 || @spatialization==2
acs = ($conferencesaudiobuffercutoff||250) / 1000.0
acs = 0.01 if acs<0.01
if ps-out.bytesize>48000*ch*fl*acs
dt="\0"*ps
Bass::BASS_ChannelGetData.call(stream, dt, dt.bytesize)
end
}
end
Thread.stop
}
rescue Exception
log(2, "Conference: Decoding error: "+$!.to_s+" "+$@.to_s)
end
end

class Stream
attr_reader :decoder, :stream
attr_reader :listener_x, :listener_y, :stream_x, :stream_y, :user_x, :user_y
attr_reader :streamid, :userid, :username
attr_accessor :name
attr_reader :losses
def initialize(channels, framesize, preskip, starttime, spatialization, position, x, y, streamid, name, userid, username, volume=nil)
@channels=channels
@framesize=framesize
@lastframetime=starttime
@preskip=preskip
@listener_dir=0
@listener_x=-1
@listener_y=-1
@position=position
@stream_x=x
@stream_y=y
@user_x=stream_x
@user_y=stream_y
@streamid=streamid
@name=name
@decoder = Opus::Decoder.new(48000, channels)
@losses=[]
@vst_lastpriority = 2**31
@vsts=[]
@pvsts=[]
	flags=0x200000
flags|=256 if spatialization==1 || spatialization==2
ch=@channels
ch=2 if spatialization==1 || spatialization==2
@stream = Bass::BASS_StreamCreate.call(48000, ch, flags, -1, nil)
@preprocessor=nil
@vst_target = @stream
@predecoder=nil
@preencoder=nil
@userid=userid
@username=username
@hrtf=nil
@hrtf_effect=nil
@spatialization=spatialization
@mutex = Mutex.new
setvolume(volume)
@sec=0
@fsec=0
@queue={}
@starttime=Time.now.to_f
@lasttime=Time.now.to_f
@ogg_mutex=Mutex.new
@thread=Thread.new{thread}
end
def set_mixer(mixer)
Bass::BASS_Mixer_StreamAddChannel.call(mixer, @stream, 0)
end
def setvolume(volume)
if volume.is_a?(Array)
vol=volume[0]
@volume=vol
else
@volume=100
end
update_position
end
def set_user_position(x,y)
@user_x, @user_y = x, y
update_position
end
def move(nx, ny)
return if nx<=0||ny<=0
@stream_x=nx
@stream_y=ny
update_position
end	
def update_position
@listener_x=@position.x
@listener_y=@position.y
@listener_dir = @position.dir
if @spatialization==0 || @spatialization==1
if @listener_y>0 && @listener_x>0
if @stream_x>0
@rx=(@stream_x-@listener_x)/8.0
@ry=(@stream_y-@listener_y)/8.0
elsif @stream_x==-1
@rx=0
@ry=0
else
@rx=(@user_x-@listener_x)/8.0
@ry=(@user_y-@listener_y)/8.0
end
if @position.dir!=0 && @rx!=0 && @ry!=0
sn = Math::sin(Math::PI/180*-@listener_dir)
cs = Math::cos(Math::PI/180*-@listener_dir)
px = @rx * cs - @ry * sn; 
py = @rx * sn + @ry * cs;
@rx=px
@ry=py
end
pos=@rx
pos=-1 if pos<-1
pos=1 if pos>1
vl=@volume/100.0
if @volume>100
vl=1+(@volume-100)/10.0
end
vol=(1-Math::sqrt((@ry.abs*0.5)**2+(@rx.abs*0.5)**2))*vl
vol=0 if vol<0
@mutex.synchronize {
if @spatialization==0
Bass::BASS_ChannelSetAttribute.call(@stream, 3, pos)
end
if @spatialization==0 || @spatialization==1
Bass::BASS_ChannelSetAttribute.call(@stream, 2, vol)
end
}
end
end
end
def set_hrtf(hrtf)
@mutex.synchronize {
@hrtf=hrtf
@hrtf_effect=nil
@hrtf_effect = @hrtf.add_effect(@channels) if @hrtf!=nil
}
end
def reset
@mutex.synchronize {
@decoder.reset
}
end
def begin_save(dir, id, savetime)
@ogg_mutex.synchronize {
msec=((Time.now.to_f-savetime)*1000).round
file=dir+"/streams/#{msec}_#{id}_#{@username}_#{@streamid}.opus"
@lastframetime=savetime
@ogg=EltenAPI::Conference::Core.ogg_stream_state_buffer
@ogg_file=File.open(file, "wb")
@ogg_lastpacket=nil
$ogg_stream_init.call(@ogg, rand(2**32)-2**31)
head="OpusHead".b
head+=[1].pack("C")
head+=[@channels].pack("C")
head+=[@preskip].pack("S")
head+=[48000].pack("I")
head+=[0].pack("S")
head+=[0].pack("C")
@packetno=0
@granulepos=0
ogg_addpacket(head, true, false)
tags="OpusTags".b
ver=Opus.version.to_s.b
tags+=[ver.bytesize].pack("I")
tags+=ver
tags+=[1].pack("I")
encinfo="ENCODER=ELTEN"
tags+=[encinfo.bytesize].pack("I")
tags+=encinfo
ogg_addpacket(tags, false, false, false)
}
end
def ogg_addpacket(data, b_o_s=false, e_o_s=false, writepages=true)
if @ogg_lastpacket!=nil
$ogg_stream_packetin.call(@ogg, @ogg_lastpacket);
if writepages
og=EltenAPI::Conference::Core.ogg_page_buffer
while $ogg_stream_pageout.call(@ogg, og) != 0
page=EltenAPI::Conference::Core.ogg_page_values(og)
head=EltenNativeStructs.pointer_bytes(page[0], page[1])
body=EltenNativeStructs.pointer_bytes(page[2], page[3])
@ogg_file.write(head)
@ogg_file.write(body)
end
end
end
if data!=nil
@packetno+=1
@ogg_lastpacket_data=data
@ogg_lastpacket=EltenAPI::Conference::Core.ogg_packet(@ogg_lastpacket_data, data.bytesize, (b_o_s)?(1):(0), (e_o_s)?(1):(0), @granulepos, @packetno)
end
end
def end_save
return if @ogg==nil
@ogg_mutex.synchronize {
ogg_addpacket("") if @ogg_lastpacket==nil
EltenAPI::Conference::Core.ogg_packet_set_eos(@ogg_lastpacket, 1)
ogg_addpacket(nil)
@ogg_file.close
$ogg_stream_clear.call(@ogg)
@ogg=@ogg_file=nil
}
end
def put(frame, frame_id=0, index=-1)
@lastindex||=0
if @thread!=nil && @thread.status!=false
n=index
n+=65535 if n<100
if @lastindex<index || index<100
@queue[n]=@lastqueue=[frame, index, frame_id]
@thread.wakeup
@lastindex=index
end
end
end
def free
end_save if @ogg!=nil
@mutex.synchronize {
Bass::BASS_StreamFree.call(@stream)
Bass::BASS_StreamFree.call(@preprocessor) if @preprocessor!=nil
@predecoder.free if @predecoder!=nil
@preencoder.free if @preencoder!=nil
@decoder.free
@stream=nil
@preprocessor = @preencoder = @predecoder = @decoder=nil
}
@thread.exit if @thread!=nil
rescue Exception
log(2, "Conference: Transmitter free error: "+$!.to_s+" "+$@.to_s)
end
def set_vst_target(target=:stream)
t=nil
if target == :preprocessor
preprocessor_init
end
if target==:stream
t=@stream
elsif target==:preprocessor && @preprocessor!=nil
t=@preprocessor
end
return if t==nil
@vst_target = t
for i in 0...@vsts.size
v=Bass::VST.new(@vsts[i].file, t, @vsts[i].priority)
v.import(:bank, @vsts[i].export(:bank))
@vsts[i].free
@vsts[i]=v
end
end
def preprocessor_init
if @preprocessor==nil
@preprocessor = Bass::BASS_StreamCreate.call(48000, @channels, 0x200000, -1, nil)
@predecoder = Opus::Decoder.new(48000, @channels)
@preencoder = Opus::Encoder.new(48000, @channels)
end
end
def preprocess(frame, bitrate=128)
preprocessor_init
dt = @predecoder.decode(frame)
@preencoder.bitrate = bitrate*1000
Bass::BASS_StreamPutData.call(@preprocessor, dt, dt.bytesize)
nd=""
while nd.bytesize<dt.bytesize
plc="\0"*(dt.bytesize-nd.bytesize)
Bass::BASS_ChannelGetData.call(@preprocessor, plc, plc.bytesize)
nd+=plc
end
nframe = @preencoder.encode(nd, dt.bytesize/2.0/@channels)
nframe
end
def vsts
@vsts
end
def vst_remove(index)
v=@vsts[index]
if v!=nil
@vsts.delete_at(index)
v.free
end
end
def vst_add(file)
return if @vst_lastpriority<8
@vst_lastpriority-=1
v=Bass::VST.new(file, @vst_target, @vst_lastpriority)
@vsts.push(v)
end
def vst_move(index, pos)
@vsts.insert(pos, @vsts.delete_at(index))
vsts_reprioritize
end
def vsts_reprioritize
@vst_lastpriority = 2**31
for i in 0...@vsts.size
@vst_lastpriority -= 1
@vsts[i].priority=@vst_lastpriority
end
end
def volume
@volume
end
private
def thread
last_frame_id=0
loop {
sleep(0.001)
ab=$conferencesaudiobuffer||0
ab=0 if ab<0
ab=400 if ab>400
while @queue.size>ab
key=@queue.keys.sort.first
ar = @queue[key]
frame, index, frame_id = ar
@queue.delete(key)
fid=frame_id
fid+=60000 if fid>0 && fid<100 && last_frame_id>59000
lostframes=0
if last_frame_id!=0
if frame_id==0
lostframes=((Time.now.to_f-@lastframetime-@framesize/1000.0)/(@framesize/1000.0)).floor
else
lostframes = fid-last_frame_id-1
@losses.push(lostframes)
@losses.delete_at(0) while @losses.size>6000
lf=lostframes
lf=3 if lf>3
lf.times {
pcm=""
if lostframes==1
pcm=@decoder.decode(nil) if @decoder!=nil
else
pcm=@decoder.decode(frame, true) if @decoder!=nil
end
out=""
if @spatialization==1 || @spatialization==2
out = pcm.unpack("s"*(pcm.bytesize/2)).map{|s|s/32768.0}.pack("f"*(pcm.bytesize/2))
suc=false
if @hrtf!=nil && @rx!=nil && @ry!=nil && @stream_x!=-1 && (@spatialization==1)
suc=true
if @spatialization==1 || (@rx!=0 || @ry!=0)
rx=@rx
rz=@ry
ry=0
ry=-0.2 if @spatialization==2
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
else
rx=@rx
rz=@ry
ry=0
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
end
elsif @channels==1
rout = out.unpack("f"*(out.bytesize/4))
fout=[]
rout.each{|f|fout.push(f,f)}
out=fout.pack("f"*fout.size)
end
else
out=pcm
end
stream=@stream
Bass::BASS_StreamPutData.call(stream, out, out.bytesize) if stream!=nil
}
end
end
last_frame_id=frame_id
update_position if @listener_x!=@position.x || @listener_y!=@position.y || @listener_dir != @position.dir
@ogg_mutex.synchronize {
if @ogg!=nil
if lostframes>0
e=Opus::Encoder.new(48000, @channels)
fr=e.encode("\0"*@framesize*48*2*@channels, 48*@framesize)
e.free
lostframes.times {
@granulepos+=@framesize*48
ogg_addpacket(fr)
}
end
@granulepos+=@framesize*48
ogg_addpacket(frame)
end
}
@lastframetime=Time.now.to_f
@mutex.synchronize {
pcm=""
pcm=@decoder.decode(frame) if @decoder!=nil
if @sec!=Time.now.to_i
@sec=Time.now.to_i
@fsec=0
end
@fsec+=1
out=""
if @spatialization==1 || @spatialization==2
out = pcm.unpack("s"*(pcm.bytesize/2)).map{|s|s/32768.0}.pack("f"*(pcm.bytesize/2))
suc=false
if @hrtf!=nil && @rx!=nil && @ry!=nil && @stream_x!=-1
suc=true
rx=@rx
rz=@ry
ry=0
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
elsif @channels==1
rout = out.unpack("f"*(out.bytesize/4))
fout=[]
rout.each{|f|fout.push(f,f)}
out=fout.pack("f"*fout.size)
end
else
out=pcm
end
stream=@stream
ps=0
ps=Bass::BASS_StreamPutData.call(stream, out, out.bytesize) if @stream!=nil
ps+=Bass::BASS_ChannelGetData.call(stream, nil, 0) if stream!=nil
fl=2
fl=4 if @spatialization==1 || @spatialization==2
ch=@channels
ch=2 if @spatialization==1 || @spatialization==2
if ps-out.bytesize>48000*ch*fl*0.25
dt="\0"*ps
Bass::BASS_ChannelGetData.call(stream, dt, dt.bytesize)
end
}
end
Thread.stop
}
rescue Exception
log(2, "Conference: Decoding error: "+$!.to_s+" "+$@.to_s)
end
end

class ChannelObject
attr_reader :stream
attr_reader :listener_x, :listener_y, :transmitter_x, :transmitter_y
attr_reader :id, :resid
def initialize(id, resid, position, transmitter_x, transmitter_y, spatialization, framesize)
@id, @resid, @framesize = id, resid, framesize
@transmitter_x, @transmitter_y, @position = transmitter_x, transmitter_y, position
@listener_x, @listener_y, @listener_dir = position.x, position.y, position.dir
@stream = Bass::BASS_StreamCreate.call(48000, 2, 0x200000|256, -1, nil)
@url=resid
@url=EltenLink::ConferenceResources.download_url(resid[1..-1]) if resid[0..0]=="$"
@source=0
@source_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x1000|0x200000|256)
@hrtf=nil
@hrtf_effect=nil
@spatialization=spatialization
@mutex = Mutex.new
update_position
@thread=Thread.new{thread}
end
def set_mixer(mixer)
Bass::BASS_Mixer_StreamAddChannel.call(mixer, @stream, 0)
end
def update_position
@listener_x, @listener_y, @listener_dir = @position.x, @position.y, @position.dir
if @listener_y>0 && @listener_x>0 && @transmitter_x>0 && @transmitter_y>0
@rx=(@transmitter_x-@listener_x)/8.0
@ry=(@transmitter_y-@listener_y)/8.0
if @position.dir!=0
sn = Math::sin(Math::PI/180*-@listener_dir)
cs = Math::cos(Math::PI/180*-@listener_dir)
px = @rx * cs - @ry * sn; 
py = @rx * sn + @ry * cs;
@rx=px
@ry=py
end
@rx=@ry=0 if @transmitter_x==0||@transmitter_y==0
pos=@rx
pos=-1 if pos<-1
pos=1 if pos>1
vol=(1-Math::sqrt((@ry.abs*0.5)**2+(@rx.abs*0.5)**2))
vol=0 if vol<0
@mutex.synchronize {
if @spatialization==0
Bass::BASS_ChannelSetAttribute.call(@stream, 3, pos)
end
if @spatialization==0 || @spatialization==1
Bass::BASS_ChannelSetAttribute.call(@stream, 2, vol)
end
}
end
end
def set_hrtf(hrtf)
@mutex.synchronize {
@hrtf=hrtf
@hrtf_effect=nil
@hrtf_effect = @hrtf.add_effect(2) if @hrtf!=nil
}
end
def free
@mutex.synchronize {
Bass::BASS_StreamFree.call(@stream)
Bass::BASS_StreamFree.call(@source) if @source!=nil && @source!=0
Bass::BASS_StreamFree.call(@source_mixer)
@stream=@source=nil
}
@thread.exit if @thread!=nil
rescue Exception
log(2, "Conference: Object free error: "+$!.to_s+" "+$@.to_s)
end
private
def thread
@source = Bass.create_url_stream(@url, 0, 0x200000|4|256, 0, 0)
Bass::BASS_Mixer_StreamAddChannel.call(@source_mixer, @source, 0)
queue="".b
fsize=48*@framesize*2*4
buf="\0"*fsize
loop {
if (sz=Bass::BASS_ChannelGetData.call(@source_mixer, buf, fsize))>0
queue += buf.byteslice(0...sz)
end
while queue.size>fsize
frame=queue.byteslice(0...fsize)
queue=queue.byteslice(fsize..-1)
update_position if @listener_x!=@position.x || @listener_y!=@position.y || @listener_dir != @position.dir
@mutex.synchronize {
out=frame
spt=false
if (@spatialization==1 || @spatialization==2) && @transmitter_x!=0 && @transmitter_y!=0
suc=false
if @hrtf!=nil && @rx!=nil && @ry!=nil
spt=true
suc=true
rx=@rx
rz=@ry
ry=0
rz=-0.075 if rz==0
@hrtf.set_bilinear(@hrtf_effect, ($usebilinearhrtf==1))
out=@hrtf.process(@hrtf_effect, out, rx, ry, rz)
end
end
ps=0
ps=Bass::BASS_StreamPutData.call(@stream, out, out.bytesize) if @stream!=nil
ps+=Bass::BASS_ChannelGetData.call(@stream, nil, 0) if @stream!=nil
t=ps/48000.0/4/2.0
sl=@framesize/1000.0-0.02
sl=0.001 if sl<=0
sleep(sl)
if t>0.1
sleep(0.02)
end
}
end
}
rescue Exception
log(2, "Conference: ChannelObject error: "+$!.to_s+" "+$@.to_s)
end
end

class ChatMessage
attr_accessor :userid, :username, :message, :time
def initialize(userid=0, username="", message="")
@userid, @username, @message = userid, username, message
@time=Time.now
end
end

class StreamSource
def initialize
raise(RuntimeError, "Abstract class")
end
def set_mixer(mixer)
if @mixer!=mixer
Bass::BASS_Mixer_StreamAddChannel.call(mixer, @stream, 0)
@mixer=mixer
end
end
def free
Bass::BASS_StreamFree.call(@stream)
end
def stream
@stream
end
def name
@name||""
end
def name=(n)
@name=n
end
def volume
vol=0
vl=[0].pack("f")
Bass::BASS_ChannelGetAttribute.call(@stream, 2, vl)
vol=(vl.unpack("f").first*100).round
return vol
end
def volume=(vol)
vol=100 if vol>100
vol=0 if vol<0
Bass::BASS_ChannelSetAttribute.call(@stream, 2, (vol/100.0))
vol
end
def frequency
@freq||=0
return @freq if @freq!=0
frq=[0].pack('f')
Bass::BASS_ChannelGetAttribute.call(@stream,1,frq)
return (@freq=frq.unpack("f")[0].to_i)
end
def position;return 0;end
def position=(ps);return 0;end
def scrollable?;false;end
def toggleable?;false;end
def toggle;end
def playing?;false;end
def play;end
def pause;end
end

class StreamSourceFile < StreamSource
attr_reader :file
def initialize(file)
@file=file
@name=File.basename(file, File.extname(file)).encode("UTF-8", invalid: :replace, undef: :replace)
@stream=Bass.create_file_stream_from_path(file, 0, 256|0x200000)
@paused=false
end
def position
bpos = Bass::BASS_ChannelGetPosition.call(@stream, 0)
pos=Bass::BASS_ChannelBytes2Seconds.call(@stream, bpos)
return pos
end
def position=(pos)
pos=0 if pos<0
bpos=Bass::BASS_ChannelSeconds2Bytes.call(@stream, pos)
Bass::BASS_ChannelSetPosition.call(@stream, bpos, 0)
return pos
end
def scrollable?;true;end
def toggleable?;true;end
def toggle
if playing?
pause
else
play
end
end
def playing?
@paused!=true
end
def play
return if @mixer==nil || @mixer==0
Bass::BASS_Mixer_StreamAddChannel.call(@mixer, @stream, 0)
@paused=false
end
def pause
Bass::BASS_Mixer_ChannelRemove.call(@stream)
@paused=true
end
end

class StreamSourceURL < StreamSourceFile
attr_reader :url
def initialize(url)
@url=url
@name=@url
@stream = Bass.create_url_stream(@url, 0, 256|0x200000, 0, 0)
@paused=false
end
end

class StreamSourceCard < StreamSource
attr_reader :cardid
def initialize(cardid)
@cardid=cardid
@name="card"
if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:prepare_os_microphone) && EltenSystemHelpers.prepare_os_microphone != true
  raise RuntimeError, "Microphone access denied"
end
r=Bass::BASS_RecordInit.call(cardid)
if r==0
fl=Bass::BASS_GetConfig.call(66)
t=0
t=1 if fl==0
Bass::BASS_SetConfig.call(66, t)
log(1, "Conference, Record fallback to Wasapi") if fl==0
log(1, "Conference, Record fallback to DirectSound") if fl==1
r=Bass::BASS_RecordInit.call(cardid)
Bass::BASS_SetConfig.call(66, fl)
end
Bass::BASS_RecordSetDevice.call(cardid)
@stream = try_record
Bass.record_resetdevice
end
def free
Bass::BASS_ChannelStop.call(@stream)
end
def try_record
r=Bass::BASS_RecordStart.call(0, 0, 256, 0, 0)
if r==0
r=Bass::BASS_RecordStart.call(0, 0, 0, 0, 0)
end
if r==0
for freq in [192000, 176400, 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 8000]
r=Bass::BASS_RecordStart.call(freq, 0, 256, 0, 0)
break if r!=0
for ch in (1..16).to_a.reverse
r=Bass::BASS_RecordStart.call(freq, ch, 256, 0, 0)
break if r!=0
r=Bass::BASS_RecordStart.call(freq, ch, 0, 0, 0)
break if r!=0
end
break if r!=0
end
end
if r==0
err=nil
case Bass::BASS_ErrorGetCode.call
when 8
err="BASS_RecordInit has not been successfully called"
when 46
err="The device is busy. An existing recording may need to be stopped before starting another one"
when 37
err="The recording device is not available. Another application may already be recording with it, or it could be a half-duplex device that is currently being used for playback"
when 6
err="The requested format is not supported."
when 1
err="There is insufficient memory"
when -1
err="Some other mystery problem!"
end
if err!=nil
log(2, "Failed to prepare audio input: #{err}")
end
end
return r
end
end

class OutStream
attr_accessor :x, :y, :frame_id, :bytes_remaining
attr_reader :name, :id, :mutex, :buf, :channels, :output, :listener, :encoder, :sources, :locally_muted, :start_time
def initialize(name, id, channels, x, y)
@name, @id, @x, @y = name.encode("UTF-8", invalid: :replace, undef: :replace), id, x, y
@buf = ""
@bytes_remaining=0
@mutex = Mutex.new
@encoder = Opus::Encoder.new(48000, channels)
@mixer = Bass::BASS_Mixer_StreamCreate.call(48000, channels, 0x1000|0x200000)
@output = Bass::BASS_Mixer_StreamCreate.call(48000, channels, 0x1000|0x200000)
@start_time=Time.now.to_f
Bass::BASS_ChannelSetAttribute.call(@mixer, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@mixer, 13, 0.1)
@channels = channels
@frame_id = 0
@out = Bass::BASS_Split_StreamCreate.call(@mixer, 0x200000, nil)
@listener = Bass::BASS_Split_StreamCreate.call(@mixer, 0x200000, nil)
Bass::BASS_Mixer_StreamAddChannel.call(@output, @out, 0)
@sources=[]
@locally_muted=false
@relvolume=1
end
def add_source(source)
source.set_mixer(@mixer)
@sources.push(source)
return source
end
def add_file(file)
s=StreamSourceFile.new(file)
add_source(s)
return s
end
def add_url(url)
s=StreamSourceURL.new(url)
add_source(s)
return s
end
def add_card(cardid)
s=StreamSourceCard.new(cardid)
add_source(s)
return s
end
def remove_source(index)
s=@sources[index]
if s!=nil
s.free
@sources.delete(s)
end
end
def set_user_position(x, y, dir)
rx=0
ry=0
if x>0 && y>0
if @x>0
rx=(@x-x)/8.0
ry=(@y-y)/8.0
elsif @x==-1
rx=0
ry=0
else
rx=0
ry=0
end
if dir!=0 && rx!=0 && ry!=0
sn = Math::sin(Math::PI/180*-dir)
cs = Math::cos(Math::PI/180*-dir)
px = rx * cs - ry * sn
py = rx * sn + ry * cs
rx=px
ry=py
end
pos=rx
pos=-1 if pos<-1
pos=1 if pos>1
@relvolume=(1-Math::sqrt((ry.abs*0.5)**2+(rx.abs*0.5)**2))
@relvolume=0 if @relvolume<0
@mutex.synchronize {
Bass::BASS_ChannelSetAttribute.call(@listener, 3, pos)
}
self.volume=volume
end
end
def volume
vol=0
@mutex.synchronize {
vl=[0].pack("f")
Bass::BASS_ChannelGetAttribute.call(@out, 2, vl)
vol=(vl.unpack("f").first*100).round
}
return vol
end
def volume=(vol)
vol=100 if vol>100
vol=0 if vol<0
@mutex.synchronize {
Bass::BASS_ChannelSetAttribute.call(@out, 2, (vol/100.0))
if !@locally_muted
Bass::BASS_ChannelSetAttribute.call(@listener, 2, (vol/100.0*@relvolume))
end
}
vol
end
def locally_muted=(mt)
if mt==true
@mutex.synchronize {
Bass::BASS_ChannelSetAttribute.call(@listener, 2, 0)
}
else
vol=volume
@mutex.synchronize {
Bass::BASS_ChannelSetAttribute.call(@listener, 2, (vol/100.0*@relvolume))
}
end
@locally_muted = (mt==true)
end
def set_mixer(mixer)
Bass::BASS_Mixer_StreamAddChannel.call(mixer, @listener, 0)
end
def free
@sources.each{|s|s.free}
@sources.clear
Bass::BASS_StreamFree.call(@mixer) if @mixer!=nil
Bass::BASS_StreamFree.call(@output) if @output!=nil
@encoder.free if @encoder!=nil
@channels=0
@mixer=@output=nil
@encoder=nil
end
end

def initialize(nick=nil)
@whisper=0
@channels=0
@position = ChannelPosition.new
@width=15
@height=15
@sltime=0.05
@input_volume=100
@stream_volume=50
@stream_lastfile=nil
@stream_lastposition=nil
@pushtotalk=false
@pushtotalk_keys=[]
@chid=0
@waiting_channel_id=0
@frame_id=0
@chat=[]
if nick==nil
@username=$name
@token = $token
else
@username="guest: #{nick}"
@token="guest"
end
Bass.record_prepare
@muteme=true
@transmitters={}
@objects={}
@streams={}
@outstreams=[]
@volumes={@username=>[100,true,false,true]}
@speakers={}
@volume=100
@muted=false
@stream_mutex = Mutex.new
@saver_mutex=Mutex.new
@lastframe_mutex=Mutex.new
@saver_file=nil
@saver_filename=nil
@waiting_users=[]
@callingplaying=true
@voip=EltenLink::VoIP.new
@voip.set_packet_method(:tcp) if $conferencestcponly==1
@starttime=Time.now.to_f
@encoder=nil
@speexdsp=nil
@speexdsp_echo=nil
@speexdsp_framesize=0
@encoder_mutex = Mutex.new
@record_mutex = Mutex.new
@lastframe=""
@voip.on_receive {|userid, type, message, p1, p2, p3, p4, index| onreceive(userid, type, message, p1, p2, p3, p4, index)}
@voip.on_status{|latency,sendbytes,receivedbytes,curlost,curpackets,time|onstatus(latency,sendbytes,receivedbytes,curlost,curpackets,time)}
@framesize=0
@bitrate=0
@stream_framesize=0
@stream_bitrate=0
@voip.on_params {|params|onparams(params)}
@voip.on_ping {|t|onping(t)}
@voip.connect(@username, @token)
snd=getsound("conference_whisper")
@whisper_sound=nil
@whisper_sound=Bass.create_file_stream_from_memory(snd, 256) if snd!=nil
@device=nil
@sources=[]
prepare_mixers
@recorder_thread = Thread.new {recorder_thread}
@output_thread = Thread.new {output_thread}
@saver_thread = Thread.new {saver_thread}
@processor_thread = Thread.new {processor_thread}
@channel_hooks=[]
@waitingchannel_hooks=[]
@volumes_hooks=[]
@streammute_hooks = []
@user_hooks=[]
@waitinguser_hooks=[]
@status_hooks=[]
@text_hooks=[]
@ping_hooks=[]
@diceroll_hooks=[]
@change_hooks=[]
@mystreams_hooks=[]
@streams_hooks=[]
@speaker_hooks=[]
end
def filestream(ind=-1)
if ind==-1
r=@sources.find{|s|s.is_a?(StreamSourceFile)}
return r if r!=nil
for s in @outstreams
r=s.sources.find{|s|s.is_a?(StreamSourceFile)}
return r if r!=nil
end
return nil
else
return nil if @outstreams[ind]==nil
@outstreams[ind].sources.find{|s|s.is_a?(StreamSourceFile)}
end
end
def cardstream(ind=-1)
if ind==-1
@sources.find{|s|s.is_a?(StreamSourceCard)}
else
return nil if @outstreams[ind]==nil
@outstreams[ind].sources.find{|s|s.is_a?(StreamSourceCard)}
end
end
def get_source(ind, sub)
return nil if @outstreams[ind]==nil
return @outstreams[ind].sources[sub]
end
def pushtotalk
return @pushtotalk
end
def pushtotalk=(v)
@pushtotalk=(v==true)
@change_hooks.each{|h|h.call("pushtotalk", v==true)}
end
def pushtotalk_keys
@pushtotalk_keys
end
def pushtotalk_keys=(v)
v=[] if !v.is_a?(Array)
@pushtotalk_keys=v
end
def saving?
return @saver_file!=nil
end
def begin_fullsave(dir)
Dir.mkdir(dir) if !FileTest.exist?(dir)
Dir.mkdir(dir+"/transmitters") if !FileTest.exist?(dir+"/transmitters")
Dir.mkdir(dir+"/streams") if !FileTest.exist?(dir+"/streams")
@fullsave_dir=dir
@fullsave_time=Time.now.to_f
@fullsave_chat = File.open(dir+"/chat.csv", "wb")
@fullsave_chat.write("time,transmitter,username,message\n")
@fullsave_chat.write("#{Time.now.strftime("%Y-%m-%d %H:%M:%S")},0,,\"Begin of save\"\n")
@fullsave_myrec=$vorbisrecorderinit.call(unicode(dir+"/myrec.ogg"), 48000, 2, 500000)
for t in @transmitters.keys
@transmitters[t].begin_save(dir, t, @fullsave_time)
end
for s in @streams.keys
@streams[s].begin_save(dir, s, @fullsave_time)
end
begin_save(dir+"/mixed.ogg")
rescue Exception
log(2, "Conference: full save error "+$!.to_s+" "+$@.to_s)
end

def begin_save(file)
end_save if @saver_file!=nil
log(-1, "Conference: beginning save to file #{file}")
case File.extname(file).downcase
when ".w64"
fp=File.open(file, "wb")
fp.write("\0"*160)
@saver_mutex.synchronize {
@saver_file=fp
@saver_filename=file
}
when ".ogg"
fp=$vorbisrecorderinit.call(unicode(file), 48000, 2, 500000)
@saver_mutex.synchronize {
@saver_file=fp
@saver_filename=file
}
end
rescue Exception
end
def end_save
log(-1, "Conference: ending save")
return if @saver_file==nil
if @fullsave_chat!=nil
@fullsave_chat.close
@fullsave_chat=nil
end
if @fullsave_dir!=nil
@fullsave_dir=nil
@fullsave_time=nil
for t in @transmitters.values
t.end_save
end
for s in @streams.values
s.end_save
end
end
case File.extname(@saver_filename).downcase
when ".w64"
guids={
"RIFF"=>["726966662E91CF11A5D628DB04C10000"].pack("H*"),
"WAVE"=>["77617665F3ACD3118CD100C04F8EDB8A"].pack("H*"),
"fmt "=>["666D7420F3ACD3118CD100C04F8EDB8A"].pack("H*"),
"fact"=>["66616374F3ACD3118CD100C04F8EDB8A"].pack("H*"),
"data"=>["64617461F3ACD3118CD100C04F8EDB8A"].pack("H*")
}
@saver_mutex.synchronize {
fp=@saver_file
ns=(fp.pos-160)/4/2
siz=fp.pos
fp.seek(0)
fp.write(guids["RIFF"])
fp.write([siz].pack("q"))
fp.write(guids["WAVE"])
fp.write(guids["fmt "])
fp.write([64].pack("q"))
fp.write([3].pack("s"))
fp.write([2].pack("s"))
fp.write([48000].pack("i"))
fp.write([48000*4*2].pack("i"))
fp.write([4*2].pack("s"))
fp.write([32].pack("s"))
fp.write([22].pack("s"))
fp.write("\0"*22)
fp.write(guids["fact"])
fp.write([32].pack("q"))
fp.write([2*ns].pack("q"))
fp.write(guids["data"])
fp.write([24+4*2*ns].pack("q"))
fp.close
@saver_file=nil
@saver_filename=nil
}
when ".ogg"
$vorbisrecorderclose.call(@saver_file)
@saver_file=nil
@saver_filename=nil
end
$vorbisrecorderclose.call(@fullsave_myrec) if @fullsave_myrec!=nil
@fullsave_myrec=nil
end
def addg_card(cardid, listen=false)
log(-1, "Conference: mixing card #{cardid}")
remove_card if cardstream!=nil
s=StreamSourceCard.new(cardid)
@sources.push(s)
if listen
s.set_mixer(@stream_mixer)
else
s.set_mixer(@output_mixer)
end
end
def remove_card
log(-1, "Conference: unmixing cards")
for s in @sources.find_all{|s|s.is_a?(StreamSourceCard)}.dup
s.free
@sources.delete(s)
end
end
def add_file(file)
s=StreamSourceFile.new(file)
s.volume=@stream_volume
@sources.push(s)
s.set_mixer(@stream_mixer)
return s
end	
def add_url(url)
s=StreamSourceURL.new(url)
s.volume=@stream_volume
@sources.push(s)
s.set_mixer(@stream_mixer)
return s
end	
def add_card(cardid)
s=StreamSourceCard.new(cardid)
s.volume=@stream_volume
@sources.push(s)
s.set_mixer(@stream_mixer)
return s
end
def remove_source(index)
s=@sources[index]
if s!=nil
s.free
@sources.delete(s)
end
end
def set_stream(file=nil, position=0)
log(-1, "Conference: setting stream from #{file}")
position=@stream_lastposition if file==nil
file=@stream_lastfile if file==nil
@stream_lastfile=file
if file!=nil
remove_stream if filestream!=nil
@stream_mutex.synchronize {
s=StreamSourceFile.new(file)
s.volume=@stream_volume
@sources.push(s)
s.set_mixer(@stream_mixer)
}
self.stream_position=position if position!=0 && position!=nil
@change_hooks.each{|h|h.call("streaming", true)}
end
end
def remove_stream(hook=true)
log(-1, "Conference: removing file stream")
@stream_mutex.synchronize {
for s in @sources.find_all{|s|s.is_a?(StreamSourceFile)}.dup
s.free
@sources.delete(s)
end
}
@change_hooks.each{|h|h.call("streaming", false)} if hook
end
def streaming?
return filestream!=nil
end
def input_volume
vl=[0].pack("f")
Bass::BASS_ChannelGetAttribute.call(@recordstream, 2, vl)
vl=vl.unpack("f").first
if vl<=1
vol=(vl*100.0).round
else
vol=(100+(vl-1)*10.0).round
end
return vol
end
def input_volume=(vol)
vol=0 if vol<0
vol=300 if vol>300
vl=vol
if vol<=100
vl=vol/100.0
else
vl=1+(vol-100)/10.0
end
Bass::BASS_ChannelSetAttribute.call(@recordstream, 2, (vl))
@input_volume=vol
vol
end
def volume
vl=[0].pack("f")
Bass::BASS_ChannelGetAttribute.call(@listen_mixer_listener, 2, vl)
return (vl.unpack("f").first*100).round
end
def volume=(vol)
vol=100 if vol>100
vol=0 if vol<0
Bass::BASS_ChannelSetAttribute.call(@listen_mixer_listener, 2, (vol/100.0))
@volume=vol
vol
end
def stream_position
return 0 if filestream==nil
pos=0
@stream_mutex.synchronize {
bpos = Bass::BASS_ChannelGetPosition.call(filestream.stream, 0)
pos=Bass::BASS_ChannelBytes2Seconds.call(filestream.stream, bpos)
}
return pos
end
def stream_position=(pos)
pos=0 if pos<0
return 0 if filestream==nil
@stream_mutex.synchronize {
bpos=Bass::BASS_ChannelSeconds2Bytes.call(filestream.stream, pos)
Bass::BASS_ChannelSetPosition.call(filestream.stream, bpos, 0)
}
return pos
end
def toggle_stream
if filestream!=nil
@stream_lastposition=stream_position
remove_stream(false)
else
set_stream
end
end
def stream_volume
return @stream_volume if filestream==nil
vol=0
@stream_mutex.synchronize {
vl=[0].pack("f")
Bass::BASS_ChannelGetAttribute.call(filestream.stream, 2, vl)
vol=(vl.unpack("f").first*100).round
}
return vol
end
def stream_volume=(vol)
return if filestream==nil
vol=100 if vol>100
vol=0 if vol<0
@stream_mutex.synchronize {
Bass::BASS_ChannelSetAttribute.call(filestream.stream, 2, (vol/100.0))
@stream_volume=vol
}
vol
end
def stream_add_empty(name="", x=0, y=0)
id=@voip.stream_add(name, 2, x, y)
return nil if id==nil
s=OutStream.new(name, id, 2, x, y)
s.volume=@stream_volume
streams_callback
return s
end
def stream_add_file(file, name="", x=0, y=0)
s=stream_add_empty(name, x, y)
return if s==nil
s.add_file(file)
s.set_mixer(@outstreams_mixer)
@outstreams.push(s)
streams_callback
return s
end
def stream_add_url(url, name="", x=0, y=0)
s=stream_add_empty(name, x, y)
return if s==nil
s.add_url(url)
s.set_mixer(@outstreams_mixer)
@outstreams.push(s)
streams_callback
return s
end
def stream_add_card(cardid, name="", x=0, y=0)
s=stream_add_empty(name, x, y)
return if s==nil
s.add_card(cardid)
s.set_mixer(@outstreams_mixer)
@outstreams.push(s)
streams_callback
return s
end
def stream_remove(ind)
if @outstreams[ind]!=nil
s=@outstreams[ind]
id=s.id
@outstreams.delete_at(ind)
s.free
@voip.stream_remove(id)
streams_callback
end
end
def muted
@muted
end
def muted=(mt)
@muted=(mt!=false)
@change_hooks.each{|h|h.call("muted", mt)}
@muted
end
def reset
@record_mutex.synchronize {
Bass::BASS_Mixer_ChannelRemove.call(@record) if @record!=nil
Bass::BASS_ChannelStop.call(@record) if @record!=nil
Bass.record_prepare
@record = try_record
Bass::BASS_ChannelSetAttribute.call(@record, 2, (@input_volume||100)/100.0)
Bass::BASS_Mixer_StreamAddChannel.call(@record_mixer, @record, 0)
Bass::BASS_ChannelPlay.call(@record, 0)
@encoder_mutex.synchronize {
@speexdsp.noise_reduction=($usedenoising||0)>0 if @speexdsp!=nil
@encoder.reset if @encoder!=nil
}
}
Bass::BASS_ChannelStop.call(@whisper_mixer)
Bass::BASS_ChannelStop.call(@listen_mixer_listener)
Bass::BASS_ChannelSetDevice.call(@whisper_mixer, Bass.cardid)
Bass::BASS_ChannelSetDevice.call(@listen_mixer_listener, current_device)
Bass::BASS_ChannelPlay.call(@whisper_mixer, 1)
Bass::BASS_ChannelPlay.call(@listen_mixer_listener, 1)
Bass::BASS_SetDevice.call(Bass.cardid)
end

def set_device(dev)
dev=dev.force_encoding("UTF-8") if dev!=nil
log(0, "Conference: changing output device to #{dev}")
@device=dev
reset
end

def current_device
return Bass.cardid if @device==nil
id=nil
soundcards=Bass.soundcards
id = soundcards.map{|c|c.name}.index(@device)
if id==nil
log(1, "Conference: cannot find device named #{@device.b}, found: #{soundcards.compact.map{|c|c.b}.join(", ")}")
id=Bass.cardid
else
Bass::BASS_Init.call(id, 48000, 4, $hwnd||0, nil)
Bass::BASS_SetDevice.call(Bass.cardid)
end
return id
end

def setvolume(user, volume=100, muted=false, chat_muted=false, streams_muted=false)
volume*=300 if volume>300
volume=10 if volume<10
v=[volume, muted, chat_muted, streams_muted]
@volumes[user]=v
for t in @transmitters.values
t.setvolume(v) if t.username==user
end
if muted
@voip.mute(user)
else
@voip.unmute(user)
end
if chat_muted
@voip.chat_mute(user)
else
@voip.chat_unmute(user)
end
if streams_muted
@voip.streams_mute(user)
else
@voip.streams_unmute(user)
end
if user==@username
if !muted
Bass::BASS_ChannelSetAttribute.call(@myself_mixer, 2, 0.0)
@muteme=false
else
Bass::BASS_ChannelSetAttribute.call(@myself_mixer, 2, 1.0)
@muteme=true
end
if !streams_muted
Bass::BASS_ChannelSetAttribute.call(@outstreams_mixer, 2, 0.0)
else
Bass::BASS_ChannelSetAttribute.call(@outstreams_mixer, 2, 1.0)
end
end
@volumes_hooks.each{|h|h.call(@volumes)}
end
def streamid_setvolume(id, volume, mute)
volume=100 if volume>100
volume=10 if volume<10
v=[volume]
stream=@streams[id]
stream.setvolume(v) if stream!=nil
if mute
@voip.streamid_mute(id)
else
@voip.streamid_unmute(id)
end
@streammute_hooks.each{|h|h.call(id, mute)}
end
def kick(userid)
@voip.kick(userid)
end
def accept(userid)
@voip.accept(userid)
end
def ban(username)
@voip.ban(username)
end
def unban(username)
@voip.unban(username)
end
def admin(username)
@voip.admin(username)
end
def unadmin(username)
@voip.unadmin(username)
end
def whitelist(username)
@voip.whitelist(username)
end
def whiteunlist(username)
@voip.whiteunlist(username)
end
def supervise(userid)
@voip.supervise(userid)
t=@transmitters[userid]
t.set_vst_target(:preprocessor) if t!=nil
end
def unsupervise(userid)
@voip.unsupervise(userid)
t=@transmitters[userid]
t.set_vst_target(:stream) if t!=nil
end
def follow(channel)
@voip.follow(channel)
end
def unfollow(channel)
@voip.unfollow(channel)
end
def speech_request
@voip.speech_request
end
def speech_refrain
@voip.speech_refrain
end
def speech_allow(userid, replace=false)
@voip.speech_allow(userid, replace)
end
def speech_deny(userid)
@voip.speech_deny(userid)
end
def coordinates(userid)
u=@transmitters[userid]
return [-1, -1] if u==nil
return u.transmitter_x, u.transmitter_y
end
def on_channel(&block)
@channel_hooks.push(block) if block!=nil
end
def on_waitingchannel(&block)
@waitingchannel_hooks.push(block) if block!=nil
end
def on_user(&block)
@user_hooks.push(block) if block!=nil
end
def on_waitinguser(&block)
@waitinguser_hooks.push(block) if block!=nil
end
def on_volumes(&block)
@volumes_hooks.push(block) if block!=nil
end
def on_streammute(&block)
@streammute_hooks.push(block) if block!=nil
end
def on_status(&block)
@status_hooks.push(block) if block!=nil
end
def on_text(&block)
@text_hooks.push(block) if block!=nil
end
def on_ping(&block)
@ping_hooks.push(block) if block!=nil
end
def on_diceroll(&block)
@diceroll_hooks.push(block) if block!=nil
end
def on_change(&block)
@change_hooks.push(block) if block!=nil
end
def on_mystreams(&block)
@mystreams_hooks.push(block) if block!=nil
end
def on_streams(&block)
@streams_hooks.push(block) if block!=nil
end
def on_speaker(&block)
@speaker_hooks.push(block) if block!=nil
end
def x
return @position.x
end
def y
return @position.y
end
def dir
return @position.dir
end
def goto(id)
@position.mutex.synchronize {
if id!=@voip.uid && @transmitters[id]!=nil
tx, ty = (@transmitters[id].transmitter_x), (@transmitters[id].transmitter_y)
if tx>0 && ty>0
@position.x=tx
@position.y=ty
end
elsif id==@voip.uid
@position.x=(@width+1)/2
@position.y=(@height+1)/2
end
}
position_changed
end
def x=(nx)
@position.mutex.synchronize {
nx=1 if nx<1
nx=@width if nx>@width
@position.x=nx
}
position_changed
nx
end
def y=(ny)
@position.mutex.synchronize {
ny=1 if ny<1
ny=@height if ny>@height
@position.y=ny
}
position_changed
ny
end
def dir=(d)
@position.mutex.synchronize {
@position.dir=d%360
}
d
end
def free(subs=true)
calling_stop
@output_thread.exit if @output_thread!=nil
begin
@recorder_thread.exit if @recorder_thread!=nil
if subs
for t in @transmitters.values
t.free
end
for s in @streams.values
s.free
end
for s in @sources
s.free
end
for o in @objects.keys
@objects[o].free
end
end
rescue Exception
log(2, "Conference: subs error: "+$!.to_s+" "+$@.to_s)
end
@saver_thread.exit if @saver_thread!=nil
begin
shoutcast_stop
Bass::BASS_ChannelStop.call(@record)
Bass::BASS_StreamFree.call(@record_mixer)
Bass::BASS_StreamFree.call(@recordstream)
Bass::BASS_StreamFree.call(@outstreams_mixer)
Bass::BASS_StreamFree.call(@channel_mixer)
Bass::BASS_StreamFree.call(@whisper_mixer)
for s in @outstreams
s.free
@outstreams.delete(s)
end
if subs
@encoder_mutex.synchronize {
@encoder.free if @encoder!=nil
@speexdsp.free if @speexdsp!=nil
@speexdsp_echo.free if @speexdsp_echo!=nil
@hrtf.free if @hrtf!=nil
}
end
Bass::BASS_StreamFree.call(@whisper_sound) if @whisper_sound!=nil
rescue Exception
log(2, "Conference: Free error: "+$!.to_s+" "+$@.to_s)
end
begin
Bass::BASS_StreamFree.call(@stream_mixer)
Bass::BASS_StreamFree.call(@myself_mixer)
Bass::BASS_StreamFree.call(@listen_mixer)
Bass::BASS_StreamFree.call(@processor_mixer)
Bass::BASS_StreamFree.call(@output) if @output!=0
Bass::BASS_StreamFree.call(@output_mixer)
rescue Exception
log(2, "Conference: Free error: "+$!.to_s+" "+$@.to_s)
end
@voip.free if subs
if subs
end_save if @saver_file!=nil
end
end
def list_channels
@voip.list_channels||[]
end
def join_channel(ch, password=nil)
calling_stop
@voip.join_channel(ch, password)
end
def leave_channel
calling_stop
@voip.leave_channel
end
def create_channel(params)
calling_stop
resp=@voip.create_channel(params)
if resp.is_a?(Hash)
return resp['id']
else
return nil
end
end
def edit_channel(id, params)
calling_stop
resp=@voip.edit_channel(id, params)
if resp.is_a?(Hash)
return resp['id']
else
return nil
end
end
def send_text(message)
return if message==nil||message==""
messages=[]
if message.bytesize<($udpmaxpacketsize||1400)
messages=[message]
else
buf=message+""
while buf.bytesize>($udpmaxpacketsize||1400)
lastsp=($udpmaxpacketsize||1400)
i=($udpmaxpacketsize||1400)
while i>1000 && lastsp==($udpmaxpacketsize||1400)
i-=1
lastsp=i if buf.getbyte(i)==32
end
messages.push(buf.byteslice(0..lastsp))
buf=buf.byteslice(lastsp+1..-1)
end
messages.push(buf) if buf.bytesize>0
end
for i in 0...messages.size
@voip.send(2, messages[i], (i==messages.size-1)?(0):(1))
end
end
def whisper
@whisper
end
def whisper=(w)
if w.is_a?(Integer) && w>=0 && w<256**2
log(-1, "Conference: whispering to #{w}")
@whisper_key = @voip.public_key(w)
@whisper_aes = OpenSSL::Cipher::AES128.new(:CBC)
@whisper_aes_key = @whisper_aes.random_key
@whisper=w
if w>0
play_sound("recording_start")
else
play_sound("recording_stop")
end
end
@whisper
end
def object_add(resid, name, x, y)
log(-1, "Conference: adding object #{name} at #{x}, #{y}")
@voip.object_add(resid, name, x, y)
end
def object_remove(id)
log(-1, "Conference: removing object")
@voip.object_remove(id)
end
def ping
@voip.ping
end
def diceroll(t=6)
@voip.diceroll(t)
end
def packetloss
return 0 if @framesize==0
losses=0
all=0
fs=(5000/@framesize.to_f).to_i
for t in @transmitters.values
if t.losses.size>fs
all+=fs
losses=t.losses[-fs..-1].sum
end
end
return 0 if all==0
return losses.to_f/(all.to_f+losses.to_f)*100.0
end
def transmitters
@transmitters.dup
end
def streams
@streams.dup
end
def outstreams
@outstreams.dup
end
def sources
@sources.dup
end
def volumes
@volumes.dup
end
def is_muted_user(username)
return false if !@volumes[username].is_a?(Array)
return @volumes[username][1]
end
def toggle_muted_user(username)
v=@volumes[username]
return false if v==nil
v[1]=!v[1]
setvolume(username, v[0], v[1])
return v[1]
end
def chat
@chat.dup
end
def calling_play
@callingplaying=true
play_sound("calling")
end
def calling_stop
if @callingplaying==true
if $bgplayer!=nil
$bgplayer.close
$bgplayer=nil
end
@callingplaying=false
end
end
def vsts(userid=0)
if userid==0
@vsts
elsif @transmitters[userid]!=nil
@transmitters[userid].vsts
else
[]
end
end
def vst_remove(index, userid)
if userid==0
v=@vsts[index]
if v!=nil
@vsts.delete_at(index)
v.free
end
elsif @transmitters[userid]!=nil
@transmitters[userid].vst_remove(index)
end
end
def vst_add(file, userid=0)
if userid==0
return if @vst_lastpriority<8
@vst_lastpriority-=1
v=Bass::VST.new(file, @record_mixer, @vst_lastpriority)
@vsts.push(v)
elsif @transmitters[userid]!=nil
@transmitters[userid].vst_add(file)
end
end
def vst_move(index, pos, userid=0)
if userid==0
@vsts.insert(pos, @vsts.delete_at(index))
vsts_reprioritize
elsif @transmitters[userid]!=nil
@transmitters[userid].vst_move(index, pos)
end
end
def vsts_reprioritize(userid=0)
if userid==0
@vst_lastpriority = 2**31
for i in 0...@vsts.size
@vst_lastpriority -= 1
@vsts[i].priority=@vst_lastpriority
end
elsif @transmitters[userid]!=nil
@transmitters[userid].vsts_reprioritize
end
end
def shoutcast_start(server, pass, name=nil, pub=false, bitrate=128)
log(-1, "Starting shoutcast stream to #{server}")
shoutcast_stop
@shoutcast = Bass::BASS_StreamCreate.call(48000, 2, 0x200000|256, -1, nil)
@shoutcast_enc = Bass::BASS_Encode_MP3_Start.call(@shoutcast, "-b #{bitrate}", 32, nil, nil)
s=Bass::BASS_Encode_CastInit.call(@shoutcast_enc, server, pass, "audio/mpeg", name, nil, nil, nil, nil, bitrate, (pub==true)?(1):(0))
@change_hooks.each{|h|h.call("shoutcast", true)} if s!=0
end
def shoutcast_stop
if @shoutcast!=nil
log(-1, "Stopping shoutcast stream")
Bass::BASS_Encode_Stop.call(@shoutcast)
Bass::BASS_StreamFree.call(@shoutcast)
@shoutcast=nil
@change_hooks.each{|h|h.call("shoutcast", false)}
end
end
def streams_callback
hs={streams: @outstreams.map{|s| {name: s.name.encode("UTF-8", invalid: :replace, undef: :replace), sources: sources_builder(s.sources), volume: s.volume, x: s.x, y: s.y, locally_muted: s.locally_muted}}, sources: sources_builder(@sources)}
@mystreams_hooks.each{|h|h.call(hs)}
rescue Exception
log(2, "Conference: streams callback: #{$!.message}")
end
def userid
@voip.uid
end
private
def position_changed
for s in @outstreams
s.set_user_position(@position.x, @position.y, @position.dir)
end
if is_muted
@voip.send(31, "", @position.x, @position.y)
end
end
def sources_builder(s)
return s.map{|c| {name: c.name.encode("UTF-8", invalid: :replace, undef: :replace), volume: c.volume, scrollable: c.scrollable?, toggleable: c.toggleable?}}
end
def prepare_mixers
@output_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000)
@whisper_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x1000|256)
Bass::BASS_ChannelSetAttribute.call(@whisper_mixer, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@whisper_mixer, 5, 1)
@channel_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000|256)
@channel_mixer_saver = Bass::BASS_Split_StreamCreate.call(@channel_mixer, 0x1000|0x200000, nil)
@channel_mixer_listener = Bass::BASS_Split_StreamCreate.call(@channel_mixer, 0x200000, nil)
Bass::BASS_ChannelSetAttribute.call(@channel_mixer, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@channel_mixer, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@channel_mixer_listener, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@channel_mixer_listener, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@channel_mixer_saver, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@channel_mixer_saver, 5, 1)
@myself_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000|256)
Bass::BASS_ChannelSetAttribute.call(@myself_mixer, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@myself_mixer, 5, 1)
@listen_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000|256)
@listen_mixer_listener = Bass::BASS_Split_StreamCreate.call(@listen_mixer, 0, nil)
@listen_mixer_preprocessor = Bass::BASS_Split_StreamCreate.call(@listen_mixer, 0x1000|0x200000, nil)
@processor_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000)
Bass::BASS_Mixer_StreamAddChannel.call(@processor_mixer, @listen_mixer_preprocessor, 0x4000)
Bass::BASS_ChannelSetAttribute.call(@listen_mixer, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@listen_mixer, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@listen_mixer_listener, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@listen_mixer_listener, 5, 1)
Bass::BASS_ChannelPlay.call(@listen_mixer_listener, 1)
Bass::BASS_ChannelPlay.call(@whisper_mixer, 1)
@saver = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000|256)
Bass::BASS_ChannelSetAttribute.call(@saver, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@saver, 5, 1)
Bass::BASS_Mixer_StreamAddChannel.call(@listen_mixer, @channel_mixer_listener, 0)
Bass::BASS_Mixer_StreamAddChannel.call(@listen_mixer, @myself_mixer, 0)
Bass::BASS_Mixer_StreamAddChannel.call(@saver, @channel_mixer_saver, 0)
@output = 0
@output_stream=0
@stream_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x1000|0x200000|256)
Bass::BASS_ChannelSetAttribute.call(@stream_mixer, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@stream_mixer, 13, 0.1)
@stream_mixer_listener = Bass::BASS_Split_StreamCreate.call(@stream_mixer, 0x200000, nil)
Bass::BASS_ChannelSetAttribute.call(@stream_mixer_listener, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@stream_mixer_listener, 13, 0.1)
@stream_mixer_uploader = Bass::BASS_Split_StreamCreate.call(@stream_mixer, 0x200000, nil)
Bass::BASS_ChannelSetAttribute.call(@stream_mixer_uploader, 5, 1)
Bass::BASS_ChannelSetAttribute.call(@stream_mixer_uploader, 13, 0.1)
Bass::BASS_Mixer_StreamAddChannel.call(@myself_mixer, @stream_mixer_listener, 0)
Bass::BASS_Mixer_StreamAddChannel.call(@output_mixer, @stream_mixer_uploader, 0)
@outstreams_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x200000|0x1000|256)
Bass::BASS_ChannelSetAttribute.call(@outstreams_mixer, 13, 0.1)
Bass::BASS_ChannelSetAttribute.call(@outstreams_mixer, 5, 1)
Bass::BASS_Mixer_StreamAddChannel.call(@myself_mixer, @outstreams_mixer, 0)
@record = try_record
@record_mixer = Bass::BASS_Mixer_StreamCreate.call(48000, 2, 0x1000|0x200000)
@vsts = []
@vst_lastpriority = 2**31
@shoutcast=nil
Bass::BASS_Mixer_StreamAddChannel.call(@record_mixer, @record, 0)
@recordstream = Bass::BASS_StreamCreate.call(48000, 2, 0x200000, -1, nil)
Bass::BASS_Mixer_StreamAddChannel.call(@output_mixer, @recordstream, 0x4000)
reset
end
def try_record
r=Bass::BASS_RecordStart.call(0, 0, 256, 0, 0)
if r==0
r=Bass::BASS_RecordStart.call(0, 0, 0, 0, 0)
end
if r==0
for freq in [48000, 44100, 96000, 88200, 192000, 176400, 384000, 64000, 32000, 24000, 22050, 16000, 8000]
r=Bass::BASS_RecordStart.call(freq, 0, 256, 0, 0)
break if r!=0
for ch in (1..16).to_a.reverse
r=Bass::BASS_RecordStart.call(freq, ch, 256, 0, 0)
break if r!=0
r=Bass::BASS_RecordStart.call(freq, ch, 0, 0, 0)
break if r!=0
end
break if r!=0
end
end
if r==0
err=nil
case Bass::BASS_ErrorGetCode.call
when 8
err="BASS_RecordInit has not been successfully called"
when 46
err="The device is busy. An existing recording may need to be stopped before starting another one"
when 37
err="The recording device is not available. Another application may already be recording with it, or it could be a half-duplex device that is currently being used for playback"
when 6
err="The requested format is not supported."
when 1
err="There is insufficient memory"
when -1
err="Some other mystery problem!"
end
if err!=nil
log(2, "Failed to prepare audio input: #{err}")
end
end
return r
end
def onreceive(userid, type, message, p1, p2, p3, p4, index)
if type==1
pos_x=p1
pos_y=p2
pos_x=-1 if pos_x<1||pos_x>255
pos_y=-1 if pos_y<1||pos_y>255
frame_id = p3*256+p4
for s in @streams.values
if s.userid==userid
s.set_user_position(pos_x, pos_y)
end
end
if @transmitters[userid]!=nil
@transmitters[userid].put(message, type, pos_x, pos_y, frame_id, index)
end
elsif type==2
if p1==0
cmessage=message
if @transmitters[userid]!=nil
cmessage = @transmitters[userid].chat_temp + message if @transmitters[userid].chat_temp!=nil
@transmitters[userid].chat_temp=""
end
c = ChatMessage.new(userid, @transmitters[userid].username, cmessage)
@chat.push(c)
if @transmitters[userid]!=nil
@fullsave_chat.write("#{Time.now.strftime("%Y-%m-%d %H:%M:%S")},#{userid},#{@transmitters[userid].username},\"#{cmessage.gsub("\\","\\\\").gsub("\"","\\\"")}\"\n") if @fullsave_chat!=nil
@text_hooks.each{|h|h.call(@transmitters[userid].username, userid, cmessage)}
end
elsif p1==1
if @transmitters[userid]!=nil
@transmitters[userid].chat_temp||=""
@transmitters[userid].chat_temp+=message
end
end
elsif type==3
if @whisper_sound!=nil
Bass::BASS_ChannelSetAttribute.call(@whisper_sound, 2, ($volume/100.0)) if $volume!=nil
Bass::BASS_ChannelPlay.call(@whisper_sound,0)
end
pos_x=@position.x
pos_y=@position.y
@transmitters[userid].put(message, type, pos_x, pos_y, 0, index)
elsif type==4
if @whisper_sound!=nil
Bass::BASS_ChannelSetAttribute.call(@whisper_sound, 2, ($volume/100.0)) if $volume!=nil
Bass::BASS_ChannelPlay.call(@whisper_sound,0)
end
pos_x=@position.x
pos_y=@position.y
begin
head = @voip.key.private_decrypt(message.byteslice(0...256))
keysize = head.getbyte(0)
aes=nil
case keysize
when 128
aes=OpenSSL::Cipher::AES128.new(:CBC)
when 192
aes=OpenSSL::Cipher::AES192.new(:CBC)
end
if aes!=nil
aes.decrypt
aes.key=head.byteslice(1..keysize/8)
aes.iv=head[keysize/8+1...keysize/8+1+aes.iv_len]
msg = head.byteslice(1+keysize/8+aes.iv_len..-1)
rest=message.byteslice(256..-1)
if rest!=nil && rest.bytesize>0
msg+=aes.update(rest)+aes.final
end
@transmitters[userid].put(msg, 3, pos_x, pos_y, 0, index)
end
rescue Exception
log(2, "Conference: receive encrypted whisper - #{$!.to_s}")
end
elsif type==11
if @transmitters[userid]!=nil
d = @transmitters[userid].preprocess(message, @encoder.bitrate)
@voip.send(1, d, p1, p2, p3, p4, userid, index)
end
elsif type==21
streamid=p1+p2*256
frame_id = p3*256+p4
stream=@streams[streamid]
if stream!=nil
stream.put(message, frame_id, index)
end
elsif type==31
pos_x=p1
pos_y=p2
pos_x=-1 if pos_x<1||pos_x>255
pos_y=-1 if pos_y<1||pos_y>255
for s in @streams.values
if s.userid==userid
s.set_user_position(pos_x, pos_y)
end
end
if @transmitters[userid]!=nil
@transmitters[userid].move(pos_x, pos_y)
end
elsif type==101
if @transmitters[userid]!=nil
@fullsave_chat.write("#{Time.now.strftime("%Y-%m-%d %H:%M:%S")},#{userid},#{@transmitters[userid].username},\"Dice roll: #{p2}\"\n") if @fullsave_chat!=nil
@diceroll_hooks.each{|h|h.call(@transmitters[userid].username, userid, p2, p1)}
end
end
end
def onstatus(latency,sendbytes,receivedbytes,curlost,curpackets,time)
status={}
status['latency']=latency+@framesize/1000.0
status['latency']=0 if latency==0
status['sendbytes']=sendbytes
status['receivedbytes']=receivedbytes
status['curlostpackets']=curlost
status['curpackets']=curpackets
pc=0
pc=(curlost.to_f/(curpackets+curlost).to_f)*100.0
status['curpacketloss']=packetloss
status['time']=time
@status_hooks.each{|h|h.call(status)} if @status_hooks!=nil
end
def onping(t)
@ping_hooks.each{|h|h.call(t)}
end
def onparams(params)
@position.mutex.synchronize {
@encoder_mutex.synchronize {
if params['channel'].is_a?(Hash)
if @chid!=params['channel']['id']
@chid=params['channel']['id']
@position.x=0
@position.y=0
end
@encoder.free if @encoder!=nil
app=:voip
app=:audio if params['channel']['codec_application']==1
@encoder = Opus::Encoder.new(48000, params['channel']['channels'], app)
case params['channel']['vbr_type']
when 0
@encoder.vbr=0
@encoder.cvbr=0
when 2
@encoder.vbr=1
@encoder.cvbr=1
else
@encoder.vbr=1
@encoder.cvbr=0
end
@encoder.packetloss=10
@encoder.prediction_disabled=true if params['channel']['prediction_disabled']==true
@encoder.inband_fec=true if params['channel']['fec']==true
@encoder.bitrate=params['channel']['bitrate']*1000
@sltime=params['channel']['framesize']/1000.0
@sltime=0.01 if @sltime<0.01
@sltime=0.1 if @sltime>0.1
@framesize=params['channel']['framesize']
@bitrate=params['channel']['bitrate']
@stream_framesize=params['channel']['stream_framesize']
@stream_bitrate=params['channel']['stream_bitrate']
@width=params['channel']['width']
@height=params['channel']['height']
px, py = @position.x, @position.y
@position.x=(@width+1)/2 if @position.x==0||@position.x>@width
@position.y=(@height+1)/2 if @position.y==0||@position.y>@height
position_changed if px!=@position.x || py!=@position.y
sfs=20
sfs=params['channel']['framesize'] if params['channel']['framesize']<20
if @speexdsp_framesize!=sfs
@speexdsp.free if @speexdsp!=nil
@speexdsp_echo.free if @speexdsp_echo!=nil
@speexdsp=nil
@speexdsp_echo=nil
end
if sfs>=10
if @speexdsp==nil
@speexdsp=SpeexDSP::Processor.new(48000, 2, sfs)
@speexdsp_echo=SpeexDSP::Echo.new(48000, 2, sfs)
@speexdsp.noise_reduction=($usedenoising||0)>0
@speexdsp_framesize = sfs
end
else
@speexdsp_framesize=0
end
@hrtf.free if @hrtf!=nil
@hrtf=nil
if params['channel']['spatialization']!=0
SteamAudio.load
@hrtf=SteamAudio.new(48000, @framesize)
end
if params['channel']['channels']!=@channels
Bass::BASS_StreamFree.call(@output) if @output!=0
Bass::BASS_StreamFree.call(@output_stream) if @output_stream!=0
@output = Bass::BASS_Mixer_StreamCreate.call(48000, params['channel']['channels'], 0x200000|0x1000)
@output_stream = Bass::BASS_StreamCreate.call(48000, params['channel']['channels'], 0x200000, -1, nil)
Bass::BASS_Mixer_StreamAddChannel.call(@output, @output_mixer, 0)
Bass::BASS_Mixer_StreamAddChannel.call(@saver, @output_stream, 0)
@channels=params['channel']['channels']
for t in @transmitters.keys
@transmitters[t].free
@transmitters.delete(t)
end
end
frs=@transmitters.size==0
upusers=[]
pch=false
n=params['channel']['users'].size
c = params['channel']['users'].find_index{|u|u['id']==@voip.uid}
c=0 if c==nil
da = 2.0*Math::PI/n
for i in 0...params['channel']['users'].size
u = params['channel']['users'][i]
uid=u['id']
a = ((n-c+i)%n) * da
x = 0 + 1*Math::sin(a)
y = -1*(0.5 - 0.5*Math::cos(a))
upusers.push(uid)
if @transmitters.include?(uid)
@transmitters[uid].set_hrtf(@hrtf)
if params['channel']['spatialization']==2
@transmitters[uid].move_absolute(x,y)
end
@transmitters[uid].reset
if @transmitters[uid].speech_requested==false && u['speech_requested']==true
@speaker_hooks.each{|h|h.call(2, u['name'], u['id'])} if params['channel']['administrators'].is_a?(Array) && params['channel']['administrators'].include?(@username)
end
@transmitters[uid].speech_requested=u['speech_requested']
else
if pch==false
calling_stop
position_changed
pch=true
end
@user_hooks.each{|h|h.call(true, u['name'], uid)} if frs==false
log(-1, "Conference: registering new transmitter #{uid}")
@transmitters[uid] = Transmitter.new(params['channel']['channels'], params['channel']['framesize'], @encoder.preskip, @starttime, params['channel']['spatialization'], @position, u['name'], @volumes[u['name']])
@transmitters[uid].set_hrtf(@hrtf) if params['channel']['spatialization']==1 || params['channel']['spatialization']==2
@transmitters[uid].set_mixer(@channel_mixer, @whisper_mixer)
if params['channel']['spatialization']==2
@transmitters[uid].move_absolute(x,y)
end
if @fullsave_dir!=nil
@transmitters[uid].begin_save(dir, uid, @fullsave_time)
end
end
end
@channel_hooks.each{|h|h.call(params['channel'])}
@volumes_hooks.each{|h|h.call(@volumes)}
for t in @transmitters.keys
if !upusers.include?(t)
@whisper=0 if @whisper==t
@user_hooks.each{|h|h.call(false, @transmitters[t].username, t)} if frs==false
log(-1, "Conference: unregistering transmitter #{t}")
@transmitters[t].free
@transmitters.delete(t)
end
end
upobjects=[]
for o in params['channel']['objects']
oid=o['id']
upobjects.push(oid)
if @objects.include?(oid)
@objects[oid].set_hrtf(@hrtf)
@objects[oid].set_mixer(@channel_mixer)
else
log(-1, "Conference: registering new object #{o['name']}")
@objects[oid] = ChannelObject.new(oid, o['resid'], @position, o['x'], o['y'], params['channel']['spatialization'], params['channel']['framesize'])
@objects[oid].set_hrtf(@hrtf) if params['channel']['spatialization']==1 || params['channel']['spatialization']==2
@objects[oid].set_mixer(@channel_mixer)
end
end
for o in @objects.keys
if !upobjects.include?(o)
log(-1, "Conference: unregistering object #{o}")
@objects[o].free
@objects.delete(o)
end
end
for s in @outstreams
s.set_mixer(@channel_mixer)
end
if params['channel']['streams'].is_a?(Array)
upstreams=[]
for s in params['channel']['streams']
sid=s['id']
upstreams.push(sid)
if @streams.include?(sid)
@streams[sid].set_hrtf(@hrtf)
@streams[sid].set_mixer(@channel_mixer)
else
log(-1, "Conference: registering new stream #{s['name']}")
username=""
username=@transmitters[s['user']].username if @transmitters[s['user']]!=nil
@streams[sid] = Stream.new(s['channels'], params['channel']['stream_framesize'], @encoder.preskip, @starttime, params['channel']['spatialization'], @position, s['x'], s['y'], s['id'], s['name'], s['user'], username)
@streams[sid].set_hrtf(@hrtf) if params['channel']['spatialization']==1 || params['channel']['spatialization']==2
@streams[sid].set_mixer(@channel_mixer)
@streams[sid].set_user_position(@transmitters[s['user']].transmitter_x, @transmitters[s['user']].transmitter_y) if @transmitters[s['user']]!=nil and @transmitters[s['user']].transmitter_x>0
end
end
for s in @streams.keys
if !upstreams.include?(s)
log(-1, "Conference: unregistering stream #{s}")
@voip.streamid_unmute(s)
@streammute_hooks.each{|h|h.call(s, false)}
@streams[s].free
@streams.delete(s)
end
end
@streams_hooks.each{|h|h.call(@streams)}
end
if params['channel']['speakers'].is_a?(Array)
upspeakers=[]
for userid in params['channel']['speakers']
upspeakers.push(userid)
if !@speakers.include?(userid)
username=""
username=@transmitters[userid].username if @transmitters[userid]!=nil
@speakers[userid]=[username, userid]
@speaker_hooks.each{|h|h.call(1, username, userid)} if userid==@voip.uid
end
end
for s in @speakers.keys
username,userid=@speakers[s]
if !upspeakers.include?(userid)
@speaker_hooks.each{|h|h.call(0, username, userid)} if userid==@voip.uid
@speakers.delete(s)
end
end
end
if params['channel']['waiting_users'].is_a?(Array) 
upwaiting=[]
for w in params['channel']['waiting_users']
upwaiting.push(w['id'])
if !@waiting_users.map{|u|u.id}.include?(w['id'])
wu=WaitingUser.new
wu.id=w['id']
wu.name=w['name']
@waiting_users.push(wu)
@waitinguser_hooks.each{|h|h.call(true, w['name'], w['id'])}
end
end
todel=[]
for w in @waiting_users
if !upwaiting.include?(w.id)
todel.push(w)
@waitinguser_hooks.each{|h|h.call(false, w.name, w.id)}
end
end
todel.each{|w|
@waiting_users.delete(w) if w!=nil
}
end
end
if params['waiting_channel'].is_a?(Integer)
if @waiting_channel_id!=params['waiting_channel']
@waiting_channel_id = params['waiting_channel']
@waitingchannel_hooks.each{|h|h.call(params['waiting_channel'])}
end
end
}
}
rescue Exception
log(2, "Conference: Params update: "+$!.to_s+" "+$@.to_s)
end
def is_muted
return true if @muted
return true if $disableconferencemiconrecord==1 && $recording==true
return false if @whisper!=0
if @pushtotalk==true
return true if @pushtotalk_keys.size==0
suc=true
$neededkeys = @pushtotalk_keys
for k in @pushtotalk_keys
if $conference_key_state[k]==false
suc=false
break
end
end
return !suc
end
return false
end
def recorder_thread
bufsize = 384000
buf="\0"*bufsize
queued = "".b
vorqueued="".b
loop {
sleep(@sltime)
sf=@framesize
sf=2.5 if sf==0 || sf==nil
sf=@speexdsp_framesize if @speexdsp_framesize!=nil and @speexdsp_framesize>0
sf*=48*2*2
sz=0
@record_mutex.synchronize {
if (sz=Bass::BASS_ChannelGetData.call(@record_mixer, buf, bufsize))>0
queued<<buf.byteslice(0...sz)
end
}
f=queued.bytesize/sf*sf
io = StringIO.new(queued.byteslice(0...f)).binmode
queued=queued.byteslice(f..-1)
until io.eof?
frame=io.read(sf)
@last_muted||=false
im=is_muted
if im!=@last_muted
@last_muted=im
if @pushtotalk==true
if !im
play_sound("conference_pushin")
else
play_sound("conference_pushout")
end
end
end
if !im && @chid!=0 && @chid!=nil
if $useechocancellation!=nil && $useechocancellation>0
@lastframe_mutex.synchronize {
if @lastframe!="" && @speexdsp_echo!=nil && @lastframe.bytesize>=sf
frame = @speexdsp_echo.cancellation(frame, @lastframe.byteslice(0...sf)) if $useechocancellation!=nil && $useechocancellation>0
end
}
end
frame=@speexdsp.process(frame) if @speexdsp!=nil && ($usedenoising||0)>0
vorqueued+=frame
Bass::BASS_StreamPutData.call(@recordstream, frame, frame.bytesize)
else
frame=("\0"*frame.bytesize).b
vorqueued<<frame.b
Bass::BASS_StreamPutData.call(@recordstream, frame, frame.bytesize)
end
end
if @fullsave_myrec!=nil
if vorqueued.bytesize>=48000*2*2
fr = vorqueued.unpack("s"*(vorqueued.bytesize/2)).map{|s|s/32768.0}.pack("f"*(vorqueued.bytesize/2))
$vorbisrecordproc.call(0, fr, fr.bytesize, @fullsave_myrec)
vorqueued="".b
end
else
vorqueued="".b
end
reset if sz>96000
}
end
def output_thread
bufsize = 384000
buf="\0"*bufsize
audio=""
packets=[]
loop {
sleep(0.01)#@sltime)
maxBytes=0
if @output!=nil && (sz=Bass::BASS_ChannelGetData.call(@output, buf, bufsize))>0
maxBytes=sz
@encoder_mutex.synchronize {
if @framesize>0 and @channels!=nil
fs=@framesize*48*2*@channels
au=(audio||"").b+buf.byteslice(0...sz).b
audio.clear
index=0
while au.bytesize-index>=fs
part=au.byteslice(index...index+fs)
#maxBytes+=part.bytesize
frame=nil
if @output_stream!=nil && @output_stream!=0
if @muteme && @whisper==0
Bass::BASS_StreamPutData.call(@output_stream, part, part.bytesize)
else
Bass::BASS_StreamPutData.call(@output_stream, "\0"*part.bytesize, part.bytesize)
end
end
if part.bytesize!=part.b.count("\0")
if @encoder!=nil
frame=@encoder.encode(part, fs/2/@channels)
end
if frame!=nil
if @whisper==0
@frame_id=0 if @frame_id>60000
@frame_id+=1
packets.push([1, frame, @position.x, @position.y, @frame_id/256, @frame_id%256])
else
if @whisper_key==nil || @framesize==nil || @framesize<10
packets.push([3, frame, @whisper%256, @whisper/256])
else
begin
@whisper_aes.encrypt
iv=@whisper_aes.random_iv
@whisper_aes.key = @whisper_aes_key
mat=[128].pack("C")+@whisper_aes_key+iv
sz=mat.bytesize
mat+=frame.byteslice(0...245-sz)
msg=@whisper_key.public_encrypt(mat)
rest=frame.byteslice(245-sz..-1)
if rest!=nil && rest.bytesize>0
msg+=@whisper_aes.update(rest)+@whisper_aes.final
end
packets.push([4, msg, @whisper%256, @whisper/256])
rescue Exception
log(2, "Conference: whisper error: #{$!.to_s} - #{$@.to_s}")
end
end
end
end
end
index+=fs
end
audio=au.byteslice(index..-1)
else
audio.clear
end
}
end
for s in @outstreams
if s.encoder!=nil && !s.encoder.closed? && @bitrate!=0 && @stream_bitrate!=0
mb=maxBytes
mb*=(s.channels.to_f/@channels)
mb+=s.bytes_remaining
buf="\0"*mb if mb>buf.bytesize
sz=Bass::BASS_ChannelGetData.call(s.output, buf, mb)
s.bytes_remaining=mb-sz
if s.output!=nil && s.channels>0 && sz>0
s.mutex.synchronize {
if @stream_framesize>0 and s.channels!=nil
fs=@stream_framesize*48*2*s.channels
au=(s.buf||"").b+buf.byteslice(0...sz).b
s.buf.clear
index=0
bitrate=(@stream_bitrate||0)*1000
bitrate=5000 if bitrate<5000
s.encoder.bitrate=bitrate if bitrate!=nil and bitrate>0
while au.bytesize-index>=fs
part=au.byteslice(index...index+fs)
frame=nil
if part.bytesize!=part.b.count("\0")
if s.encoder!=nil
frame=s.encoder.encode(part, fs/2/s.channels)
end
if frame!=nil
s.frame_id=0 if s.frame_id>60000
s.frame_id+=1
sid=@voip.stream_id(s.id)
packets.push([21, frame, sid%256, sid/256, s.frame_id/256, s.frame_id%256])
end
end
index+=fs
end
s.buf.replace(au.byteslice(index..-1))
else
s.buf.clear
end
}
end
end
end
if packets.size>0
@voip.send_multi(packets)
packets.clear
end
}
rescue Exception
log(2, "Conference, output error: #{$!.to_s}, #{$@.to_s}")
retry
end
def saver_thread
begin
bufsize = 2097152
buf="\0"*bufsize
loop {
sleep(1.2)
@saver_mutex.synchronize {
if @saver!=nil && (sz=Bass::BASS_ChannelGetData.call(@saver, buf, bufsize))>0
if @saver_file!=nil
if buf[0...sz].b.count("\0")!=sz
case File.extname(@saver_filename).downcase
when ".w64"
@saver_file.write(buf.byteslice(0...sz))
when ".ogg"
$vorbisrecordproc.call(0, buf.byteslice(0...sz), sz, @saver_file)
end
end
end
if @shoutcast!=nil
Bass::BASS_Encode_Write.call(@shoutcast, buf, sz)
end
end
}
}
rescue Exception
log(2, "Conference saver: "+$!.to_s+" "+$@.to_s)
retry
end
end
def processor_thread
bufsize = 2097152
buf="\0"*bufsize
audio=""
audiobuf="".b
loop {
sleep(0.01)
sf=2.5
sf=@speexdsp_framesize if @speexdsp_framesize!=nil and @speexdsp_framesize>0
sf*=48*2*2
if $useechocancellation!=nil && $useechocancellation>0
if (sz=Bass::BASS_ChannelGetData.call(@processor_mixer, buf, bufsize))>0
audiobuf<<buf.byteslice(0..sz)
audiobuf=audiobuf.byteslice(-sf..-1) if audiobuf.bytesize>sf
@lastframe_mutex.synchronize {
@lastframe=audiobuf
}
end
end
}
end
end
