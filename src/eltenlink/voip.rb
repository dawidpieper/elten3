# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require "base64"
require "fiddle"
require "json"
require "openssl"
require "socket"
require "thread"
require "zlib"

require_relative "../eapi/conferencenative"

module EltenLink

class VoIP

CommandAliases = {'update'=>1}
ResponseAliases={'success'=>0,'error'=>1}
CommandTimeout = 5.0
CommandReadChunk = 16 * 1024

class CommandTimeoutError < StandardError; end

class MessageType
Audio=1
Text=2
Whisper=3
Noop=200
Reemit=201
Ping=251
Pong=252
end

attr_reader :connected, :latency, :uid, :tcp_requested, :streams
def initialize
@closing=false
@tcp_requested=false
@reconnecting=false
@reconnect_thread = nil
@last_uuid=nil
@last_password=nil
@latency=0
@sendtimes={}
@receivetimes={}
@sendbytes=0
@receivedbytes=0
@cur_rx_packets=0
@cur_lostpackets=0
@starttime=Time.now.to_f
@key = OpenSSL::PKey::RSA.new(2048)
@tcp=nil
@udp=nil
@uid=nil
@secret=nil
@chid=0
@connected=false
@cipher_mutex=Mutex.new
@cipher=OpenSSL::Cipher::AES256.new :CTR
@channel_secrets=[]
@received={}
@pings={}
@tcp_mutex = Mutex.new
@receive_hooks=[]
@params_hooks=[]
@status_hooks=[]
@ping_hooks=[]
@mutes=[]
@chat_mutes=[]
@streams_mutes=[]
@streamid_mutes=[]
@streams=[]
@bigpackets=false
end
def connect(username, token)
@closing=false
@username=username
@token=token
@mutes=[@username]
@bigpackets=false
tcp=TCPSocket.new("conferencing.elten.link",8133)
ctx = OpenSSL::SSL::SSLContext.new()
@tcp = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
@tcp.sync_close=true
begin
@tcp.connect_nonblock
rescue IO::WaitReadable
if IO.select([@tcp], nil, nil, 2)
retry
else
    return false
end
rescue IO::WaitWritable
if IO.select(nil, [@tcp], nil, 2)
retry
  else
return false
end
end
encodings = ['deflate', 'zstd']
encodings.push('xz') if defined?(XZ_AVAILABLE) && XZ_AVAILABLE
command("session_encodings", {'encodings'=>encodings}, reconnect: false)
command("session_aliasversion", {'version'=>1}, reconnect: false)
resp=command("login", {'login'=>username, 'token'=>token, 'publickey'=>Base64.strict_encode64(@key.public_key.to_der)}, reconnect: false)
if resp!=false
@uid=resp['id']
@secret=Base64.strict_decode64(resp['secret'])
@tcpthread.exit if @tcpthread!=nil
@tcpthread=Thread.new {
loop {
if @tcp_requested==false
sleep(0.5)
else
sleep(0.1)
end
update
}
}
connect_udp
@connected=true
else
return false
end
return true
rescue Exception
return false
end
def create_channel(params)
st=command("create", params)
if st!=false
@last_password = params['password']
log(-1, "Conference: created channel of id #{st['id']}")
return st
else
return false
end
end
def edit_channel(id, params)
prm=params.dup
st=command("edit", prm)
log(-1, "Conference: edited channel of id #{id}")
return st
end
def join_channel(id, password=nil, uuid=nil)
log(-1, "Conference: joining channel #{id}") if id!=nil
log(-1, "Conference: joining channel #{uuid}") if id==nil and uuid!=nil
r=command("join", {'channel'=>id, 'password'=>password, 'uuid'=>uuid})
update if r!=false
st=r!=false && r['status']=='success'
if st==true
@last_password=password
log(-1, "Conference: joined channel #{id}")
else
log(-1, "Conference: failed to join channel #{id}")
end
return st
end
def leave_channel
log(-1, "Conference: leaving channel")
r=command("leave", {}, reconnect: false)
update if r!=false
return r!=false && r['status']=='success'
end
def list_channels
cmd=command('list')
return {} if cmd==false
return cmd['channels']
end
def update
send(200, "")
resp=command("update")
if resp.is_a?(Hash) && resp['updated']
log(-1, "Conference: updating parameters")
@chid=resp['channel']
@stamp=resp['channel_stamp']
@last_uuid = resp['channel_uuid']
@cur_rx_packets=0
@cur_lostpackets=0
@index=1
@channel_secrets[@stamp]=Base64.strict_decode64(resp['channel_secret']) if resp['channel_secret']!=nil
@received={}
if resp['params']!=nil
@params_hooks.each{|h|Thread.new {h.call(resp['params'])}}
end
end
if resp.is_a?(Hash) && resp['packets'].is_a?(Array)
for data in resp['packets'].map{|pc|Base64.decode64(pc)}
receive(data)
end
end
end
def close_transport
if @udpthread!=nil
@udpthread.exit
@udpthread=nil
end
if @tcpthread!=nil
@tcpthread.exit
@tcpthread=nil
end
tcp=@tcp
udp=@udp
@cipher_mutex.synchronize {
@tcp_mutex.synchronize {
@tcp=nil
@udp=nil
}
}
begin
tcp.close if tcp!=nil && !tcp.closed?
rescue Exception
end
begin
udp.close if udp!=nil && udp.respond_to?(:close) && !udp.closed?
rescue Exception
end
@connected=false
end
def disconnect
log(0, "Conference: disconnecting from server")
@closing=true
executecommand("close") if @tcp!=nil
close_transport
end
def free
disconnect
@reconnect_thread.exit if @reconnect_thread!=nil
end
def reconnect
@reconnecting=true
log(0, "Conference: reconnecting with uid #{@last_uuid.to_s}")
username, token = @username, @token
uuid, password = @last_uuid, @last_password
mutes=@mutes.dup
chat_mutes=@chat_mutes.dup
streams_mutes=@streams_mutes.dup
streamid_mutes=@streamid_mutes.dup
disconnect
sleep(1)
c=false
while c==false
c=connect(username, token)
sleep(1) if c==false
end
@reconnecting=false
set_packet_method(:tcp) if @tcp_requested==true
update
join_channel(nil, @last_password, @last_uuid) if @last_uuid!=nil
update
unmute(@username) if !mutes.include?(@username)
mutes.each{|m|mute(m)}
chat_mutes.each{|m|chat_mute(m)}
streams_mutes.each{|m|streams_mute(m)}
streamid_mutes.each{|m|streamid_mute(m)}
for i in 0...@streams.size
s=@streams[i]
if s!=nil
@streams[i][:id]=command("stream_add", {'name'=>s[:name], 'channels'=>s[:channels], 'x'=>s[:x], 'y'=>s[:y]})['id']||0
end
end
update
rescue Exception
@reconnecting=false
log(2, "VoIP reconnect: #{$!.to_s} #{$@.to_s}")
end
def generate_packet(type, message, p1=0, p2=0, p3=0, p4=0, userid=nil, index=nil, ignore_stamp=false)
return nil if @chid==0 && type<200
return nil if (message=="" && type<10) || !message.is_a?(String)
message=message+""
return nil if @channel_secrets[@stamp]==nil && type<200
crc=Zlib.crc32(message)
if index==nil
index=@index
@index+=1
end
if userid==nil
userid=@uid
end
bytes=[uid%256, uid/256, @stamp%256, (@stamp/256)%256, @stamp/256/256, index%256, index/256, type, p1, p2, p3, p4, crc%256, (crc/256)%256, (crc/256/256)%256, crc/256/256/256]
data=bytes.pack("C*")
@cipher_mutex.synchronize {
if message!=""
if ignore_stamp==false && (@stamp!=0 && @channel_secrets[@stamp]!=nil && @channel_secrets[@stamp].bytesize!=0)
key=@channel_secrets[@stamp]
if @cipher.key_len!=key.bytesize
case key.bytesize
when 16
@cipher=OpenSSL::Cipher::AES128.new :CTR
when 24
@cipher=OpenSSL::Cipher::AES192.new :CTR
when 32
@cipher=OpenSSL::Cipher::AES256.new :CTR
end
end
@cipher.encrypt
@cipher.key=key
@cipher.iv=data
data+=@cipher.update(message.b).b+@cipher.final.b
else
data+=message.b
end
end
}
return data
end
def send(type, message, p1=0, p2=0, p3=0, p4=0, userid=nil, index=nil, ignore_stamp=false)
data = generate_packet(type, message, p1, p2, p3, p4, userid, index, ignore_stamp)
send_packet(data)
return true
rescue Exception
return false
end
def send_packet(data)
return false if data==nil
@sendtimes[@index-1]=Time.now.to_f
@sendbytes+=data.bytesize
if !@tcp_requested
@udp.send(data, 0, "conferencing.elten.link", 8133)
else
command("packet", {'packet'=>Base64.encode64(data)})
end
return true
rescue Exception
log(2, "Voip send: #{$!.to_s} #{$@.to_s}s")
return false
end
def send_coll(coll)
if coll.size==1
send_packet(coll[0])
elsif coll.size>1
cx=coll.map{|c|[c.bytesize].pack("I")+c}.join
send(255, cx, coll.size, 0, 0, 0, nil, nil, true)
end
end
def send_multi(packets)
return if !packets.is_a?(Array)
coll=[]
for pc in packets
if pc.size>2
m=generate_packet(pc[0], pc[1], pc[2]||0, pc[3]||0, pc[4]||0, pc[5]||0, pc[6]||nil, pc[7]||nil, pc[8]||false)
if m!=nil
if 16+coll.map{|c|c.bytesize+4}.sum+4+m.bytesize>($udpmaxpacketsize||1400) || coll.size>16
send_coll(coll)
coll.clear
end
coll.push(m)
end
end
end
send_coll(coll) if coll.size>0
rescue Exception
log(2, "Voip send_multi: #{$!.to_s} #{$@.to_s}")
end
def on_params(&block)
@params_hooks.push(block) if block!=nil
end
def on_receive(&block)
@receive_hooks.push(block) if block!=nil
end
def on_status(&block)
@status_hooks.push(block) if block!=nil
end
def on_ping(&block)
@ping_hooks.push(block) if block!=nil
end
def mute(user)
log(-1, "Conference: muting user #{user}")
command("mute", {'user'=>user})
@mutes.push(user) if !@mutes.include?(user)
end
def unmute(user)
log(-1, "Conference: unmuting user #{user}")
command("unmute", {'user'=>user})
@mutes.delete(user)
end
def chat_mute(user)
log(-1, "Conference: muting chat of user #{user}")
command("chat_mute", {'user'=>user})
@chat_mutes.push(user) if !@chat_mutes.include?(user)
end
def chat_unmute(user)
log(-1, "Conference: unmuting chat of user #{user}")
command("chat_unmute", {'user'=>user})
@chat_mutes.delete(user)
end
def streams_mute(user)
log(-1, "Conference: muting streams of user #{user}")
command("streams_mute", {'user'=>user})
@streams_mutes.push(user) if !@streams_mutes.include?(user)
end
def streams_unmute(user)
log(-1, "Conference: unmuting streams of user #{user}")
command("streams_unmute", {'user'=>user})
@streams_mutes.delete(user)
end
def streamid_mute(id)
log(-1, "Conference: muting stream #{id}")
command("streamid_mute", {'stream'=>id})
@streamid_mutes.push(id) if !@streamid_mutes.include?(id)
end
def streamid_unmute(id)
log(-1, "Conference: unmuting stream #{id}")
command("streamid_unmute", {'stream'=>id})
@streamid_mutes.delete(id)
end
def kick(userid)
log(-1, "Conference: kicking user #{userid}")
command("kick", {'userid'=>userid})
end
def accept(userid)
log(-1, "Conference: accepting user #{userid}")
command("accept", {'userid'=>userid})
end
def ban(username)
log(-1, "Conference: banning user #{username}")
command("ban", {'username'=>username})
end
def unban(username)
log(-1, "Conference: unbanning user #{username}")
command("unban", {'username'=>username})
end
def admin(username)
log(-1, "Conference: granting administration to user #{username}")
command("admin", {'username'=>username})
end
def unadmin(username)
log(-1, "Conference: denying administration to user #{username}")
command("unadmin", {'username'=>username})
end
def whitelist(username)
log(-1, "Conference: adding user #{username} to channel whitelist")
command("whitelist", {'username'=>username})
end
def whiteunlist(username)
log(-1, "Conference: removing user #{username} from channel whitelist")
command("whiteunlist", {'username'=>username})
end
def supervise(userid)
log(-1, "Conference: supervising user #{userid}")
command("supervise", {'userid'=>userid})
end
def unsupervise(userid)
log(-1, "Conference: unsupervising user #{userid}")
command("unsupervise", {'userid'=>userid})
end
def follow(channel)
log(-1, "Conference: following channel #{channel}")
command("follow", {'channel'=>channel})
end
def unfollow(channel)
log(-1, "Conference: unfollowing channel #{channel}")
command("unfollow", {'channel'=>channel})
end
def speech_request
log(-1, "Conference: requesting speech")
command("speech_request", {})
end
def speech_refrain
log(-1, "Conference: refraining speech")
command("speech_refrain", {})
end
def speech_allow(userid, replace=false)
log(-1, "Conference: allowing speech to user #{userid}")
command("speech_allow", {'userid'=>userid, 'replace'=>replace})
end
def speech_deny(userid)
log(-1, "Conference: denying speech to user #{userid}")
command("speech_deny", {'userid'=>userid})
end
def public_key(userid)
c=command("publickey", {'userid'=>userid})
return nil if c==false
return nil if c['publickey']==nil || c['publickey']==""
return OpenSSL::PKey::RSA.new(Base64.strict_decode64(c['publickey']))
rescue Exception
log("Conference: public_key error: #{$!.to_s}")
return nil
end
def object_add(resid, name, x, y)
return command("object_add", {'resid'=>resid, 'name'=>name, 'x'=>x, 'y'=>y})['id']
end
def object_remove(id)
command("object_remove", {'id'=>id})
end
def stream_add(name, channels, x, y)
id=command("stream_add", {'name'=>name, 'channels'=>channels, 'x'=>x, 'y'=>y})['id']||0
@streams.push({id: id, name: name, channels: channels, x: x, y: y})
log(-1, "VoIP: registering stream of id #{id} for #{@streams.size-1}")
return @streams.size-1
rescue Exception
return nil
end
def stream_remove(id)
log(-1, "VoIP: unregistering stream of id #{id} for #{stream_id(id)}")
command("stream_remove", {'id'=>stream_id(id)})
@streams[id]=nil
end

def ping(material="")
r=0
r=rand(16777216) while @pings.keys.include?(r) || r==0
@pings[r]=Time.now
t=@pings[r].sec*1000+@pings[r].usec/1000
message=[r].pack("I")
message<<material if material!=""
send(251, message, t%256, t/256)
end
def pong(message)
t=Time.now.sec*1000+Time.now.usec/1000
send(252, message, t%256, t/256)
end
def diceroll(t=6)
log(-1, "Conference: rolling #{t}-sided dice")
send(101, "", t, 0)
end
def key
@key
end
def set_packet_method(method)
case method
when :tcp
command("packet_method", {'method'=>'tcp'})
@tcp_requested=true
log(-1, "VOIP: setting packet method to TCP")
when :udp
command("packet_method", {'method'=>'udp'})
@tcp_requested=false
log(-1, "VOIP: setting packet method to UDP")
end
end
def stream_id(n)
s=@streams[n]
if s!=nil
return s[:id]
else
return 0
end
end
private
def connect_udp
log(0, "Conference: connecting to server")
@udpthread.exit if @udpthread!=nil
@udp=UDPSocket.new()
@udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 16777216)
@udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, 16777216)
@sendbytes+=@secret.bytesize
@udp.send(@secret, 0, "conferencing.elten.link", 8133)
lasttime = Time.now.to_f
@udpthread = Thread.new {
loop {
begin
data, addr = @udp.recvfrom_nonblock(1500)
lasttime=Time.now.to_f
@receivedbytes+=data.bytesize
receive(data)
rescue IO::EWOULDBLOCKWaitReadable
@reconnect_thread = Thread.new{reconnect} if @reconnecting==false && (Time.now.to_f-lasttime>15 && @tcp_requested==false)
IO.select([@udp], nil, nil, 0.1)
retry
rescue IO::EWOULDBLOCKWaitWritable
@reconnect_thread = Thread.new{reconnect} if @reconnecting==false && (Time.now.to_f-lasttime>15 && @tcp_requested==false)
IO.select(nil, [@udp], nil, 0.1)
retry
rescue Exception
@reconnect_thread = Thread.new{reconnect} if @reconnecting==false && (Time.now.to_f-lasttime>15 && @tcp_requested==false)
log(2, "VoIP UDP: "+$!.to_s+" "+$@.to_s)
end
}
}
end
def extract(data)
userid=data.getbyte(0)+data.getbyte(1)*256
stamp=data.getbyte(2)+data.getbyte(3)*256+data.getbyte(4)*256**2
index=data.getbyte(5)+data.getbyte(6)*256
type=data.getbyte(7)
return [userid, stamp, index, type]
end
def receive(data)
receiveTime=Time.now
data=(data+"").b
userid, stamp, index, type = extract(data)
return if type<200 && @chid==0
@received[userid]||={}
@cur_rx_packets+=1
if index>10
cr=index-((@received[userid][type]||[]).max||0)-1
@cur_lostpackets+=cr if cr>0 && cr<5
end
@received[userid][type]||=[]
return if type<200 && (userid!=0 && (@received[userid][type]||[]).include?(index))
@received[userid][type].push(index) if userid!=0
message = ""
crc=data.getbyte(12)+data.getbyte(13)*256+data.getbyte(14)*256**2+data.getbyte(15)*256**3
p1=data.getbyte(8)
p2=data.getbyte(9)
p3=data.getbyte(10)
p4=data.getbyte(11)
if data.bytesize>16
@cipher_mutex.synchronize {
key=@channel_secrets[stamp]||@channel_secrets[@stamp]
if stamp!=0 && key!=nil && key.bytesize!=0
if @cipher.key_len!=key.bytesize
case key.bytesize
when 16
@cipher=OpenSSL::Cipher::AES128.new :CTR
when 24
@cipher=OpenSSL::Cipher::AES192.new :CTR
when 32
@cipher=OpenSSL::Cipher::AES256.new :CTR
end
end
@cipher.decrypt
@cipher.iv=data.byteslice(0...16)
@cipher.key=key
message=@cipher.update(data.byteslice(16..-1)).b+@cipher.final.b
else
message=data.byteslice(16..-1).b
end
}
end
if userid==@uid && type==1
@receivetimes[index]=Time.now.to_f
if @receivetimes.size>50
s=0
r=0
c=0
for ind in @receivetimes.keys
if @sendtimes[ind]!=nil
r+=@receivetimes[ind]
s+=@sendtimes[ind]
c+=1
end
end
@receivetimes.clear
@sendtimes.clear
@latency=(r-s)/c.to_f
end
end
if Time.now.to_f-(@statustime||0)>5
@status_hooks.each{|h| h.call(@latency, @sendbytes, @receivedbytes, @cur_lostpackets, @cur_rx_packets, Time.now.to_f-@starttime)}
@statustime=Time.now.to_f
end
if type<200
if Zlib.crc32(message)==crc || crc==0
@receive_hooks.each{|h|h.call(userid, type, message, p1, p2, p3, p4, index)}
else
log(-1, "VoIP: Wrong CRC signature for packet #{index} from #{userid}, type #{type}")
end
else
case type
when 251
pong(message)
when 252
return if message.bytesize<4
m=message.unpack("I").first
if @pings.include?(m)
lt=@pings[m]
@pings.delete(m)
rt=receiveTime
t=rt-lt
@ping_hooks.each{|h|h.call(t.to_f)}
end
@bigpackets=true if message.bytesize>1500
play_sound("signal")
end
end
rescue Exception
log(2, "VoIP Receive: "+$!.to_s+" "+$@.to_s)
end
def command_payload(cmd, params={})
json={':command'=>cmd}
if CommandAliases[cmd].is_a?(Numeric)
json[':c']=CommandAliases[cmd]
json.delete(":command")
end
for k in params.keys
json[k]=params[k]
end
for k in json.keys
if json[k].is_a?(String)
json[k]=json[k]+""
json[k].force_encoding("UTF-8")
end
end
txt=JSON.generate(json)
if txt.bytesize>64 && txt.bytesize<128
z=Zlib::Deflate.deflate(txt.b)
return (+"d".b) << z.bytesize.to_s(36).b << "\n".b << z
elsif txt.bytesize>=128
z=Zstd.compress(txt.b)
return (+"z".b) << Base62.encode(z.bytesize).b << "\n".b << z
elsif txt.bytesize>=128 && defined?(XZ_AVAILABLE) && XZ_AVAILABLE
z=XZ.compress(txt.b)
return (+"x".b) << Base62.encode(z.bytesize).b << "\n".b << z
else
return (+"".b) << txt.b << "\n".b
end
end
def command_deadline(timeout=CommandTimeout)
Time.now.to_f+timeout.to_f
end
def tcp_wait(readable, deadline)
remaining=deadline-Time.now.to_f
raise CommandTimeoutError, "timeout" if remaining<=0
ready=readable ? IO.select([@tcp], nil, nil, remaining) : IO.select(nil, [@tcp], nil, remaining)
raise CommandTimeoutError, "timeout" if ready==nil
true
end
def tcp_read_nonblock(max, deadline)
loop {
begin
data=@tcp.read_nonblock(max)
raise EOFError if data==nil || data.bytesize==0
return data
rescue IO::WaitReadable
tcp_wait(true, deadline)
rescue IO::WaitWritable
tcp_wait(false, deadline)
end
}
end
def tcp_readline(deadline)
buf=+"".b
until buf.end_with?("\n")
buf << tcp_read_nonblock(1, deadline)
end
buf
end
def tcp_read_exact(size, deadline)
size=size.to_i
buf=+"".b
while buf.bytesize<size
buf << tcp_read_nonblock([CommandReadChunk, size-buf.bytesize].min, deadline)
end
buf
end
def tcp_write_all(data, deadline)
data=data.to_s.b
offset=0
while offset<data.bytesize
begin
written=@tcp.write_nonblock(data.byteslice(offset, data.bytesize-offset))
raise IOError, "socket write returned zero bytes" if written==nil || written<=0
offset+=written
rescue IO::WaitReadable
tcp_wait(true, deadline)
rescue IO::WaitWritable
tcp_wait(false, deadline)
end
end
true
end
def executecommand(cmd, params={}, deadline: nil)
return true if @tcp==false || @tcp==nil
begin
s=command_payload(cmd, params)
deadline ||= command_deadline
@tcp_mutex.synchronize {
tcp_write_all(s, deadline)
@sendbytes+=s.bytesize
}
return false
rescue Exception
log(2, "VoIP command write: #{$!.to_s}")
return true
end
end
def handle_command_failure(reconnect)
return if @closing
if reconnect
play_sound("right")
if @reconnecting==false && (@reconnect_thread==nil || !@reconnect_thread.alive?)
@reconnect_thread = Thread.new{reconnect()}
end
else
log(0, "Conference: closing broken command connection")
@closing=true
close_transport
end
end
def decode_command_response(ans, deadline)
if ans!=nil && ans.getbyte(0)=="d".getbyte(0)
ns=ans
size=ns.byteslice(1...-1).to_i(36)
a=tcp_read_exact(size, deadline)
@receivedbytes+=size
return Zlib::Inflate.inflate(a)
elsif ans!=nil && ans.getbyte(0)=="x".getbyte(0)
ns=ans
size=Base62.decode(ns.byteslice(1...-1))
a=tcp_read_exact(size, deadline)
@receivedbytes+=size
if defined?(XZ_AVAILABLE) && XZ_AVAILABLE
return XZ.decompress(a)
else
raise "XZ encoding received but XZ is unavailable"
end
elsif ans!=nil && ans.getbyte(0)=="z".getbyte(0)
ns=ans
size=Base62.decode(ns.byteslice(1...-1))
a=tcp_read_exact(size, deadline)
@receivedbytes+=size
return Zstd.decompress(a)
end
ans
end
def command(cmd, params={}, reconnect: true)
@cmd_mutex||=Mutex.new
begin
json=nil
@cmd_mutex.synchronize {
deadline=command_deadline
raise IOError, "not connected" if @tcp==false || @tcp==nil
raise IOError, "command write failed" if executecommand(cmd, params, deadline: deadline)
ans=tcp_readline(deadline)
@receivedbytes+=ans.bytesize
ans=decode_command_response(ans, deadline)
json=JSON.load(ans)
}
json['status'] = ResponseAliases.key(json[':s']) if json.is_a?(Hash) && json[':s'].is_a?(Numeric) && ResponseAliases.key(json[':s']).is_a?(String)
return false if json['status']!='success'
return json
rescue Exception
log(2, "VoIP command #{cmd}: #{$!.to_s}")
handle_command_failure(reconnect)
return false
end
end
end
end
