# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require_relative "../conferencenative"

module SpeexDSP
begin
SpeexDSP=EltenRuntimePaths.dlopen(EltenSystemHelpers.speexdsp_library_name)
rescue Exception
SpeexDSP=nil
end

Preprocess_state_init = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_preprocess_state_init'], [Fiddle::TYPE_INT, Fiddle::TYPE_INT], ELTEN_INTPTR) : EltenRubyFunction.new { |_frame, _freq| 0 }
Preprocess_ctl = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_preprocess_ctl'], [ELTEN_INTPTR, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state, _ctl, _ptr| 0 }
Preprocess_run = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_preprocess_run'], [ELTEN_INTPTR, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state, _frame| 0 }
Preprocess_state_destroy = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_preprocess_state_destroy'], [ELTEN_INTPTR], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state| 0 }

Echo_state_init = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_echo_state_init'], [Fiddle::TYPE_INT, Fiddle::TYPE_INT], ELTEN_INTPTR) : EltenRubyFunction.new { |_frame, _filter| 0 }
Echo_ctl = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_echo_ctl'], [ELTEN_INTPTR, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state, _ctl, _ptr| 0 }
Echo_cancellation = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_echo_cancellation'], [ELTEN_INTPTR, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state, input, _echo, output| output[0, input.bytesize] = input if output.respond_to?(:[]=); 0 }
Echo_capture = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_echo_capture'], [ELTEN_INTPTR, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state, input, output| output[0, input.bytesize] = input if output.respond_to?(:[]=); 0 }
Echo_playback = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_echo_playback'], [ELTEN_INTPTR, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state, input, output| output[0, input.bytesize] = input if output.respond_to?(:[]=); 0 }
Echo_state_destroy = SpeexDSP ? Fiddle::Function.new(SpeexDSP['speex_echo_state_destroy'], [ELTEN_INTPTR], Fiddle::TYPE_INT) : EltenRubyFunction.new { |_state| 0 }

SPEEX_PREPROCESS_GET_AGC=3
SPEEX_PREPROCESS_GET_AGC_DECREMENT=29
SPEEX_PREPROCESS_GET_AGC_INCREMENT=27
SPEEX_PREPROCESS_GET_AGC_LEVEL=7
SPEEX_PREPROCESS_GET_AGC_MAX_GAIN=31
SPEEX_PREPROCESS_GET_DENOISE=1
SPEEX_PREPROCESS_GET_DEREVERB=9
SPEEX_PREPROCESS_GET_DEREVERB_DECAY=13
SPEEX_PREPROCESS_GET_DEREVERB_LEVEL=11
SPEEX_PREPROCESS_GET_ECHO_STATE=25
SPEEX_PREPROCESS_GET_ECHO_SUPPRESS=21
SPEEX_PREPROCESS_GET_ECHO_SUPPRESS_ACTIVE=23
SPEEX_PREPROCESS_GET_NOISE_SUPPRESS=19 
SPEEX_PREPROCESS_GET_PROB_CONTINUE=17 
SPEEX_PREPROCESS_GET_PROB_START=15 
SPEEX_PREPROCESS_GET_VAD=5 
SPEEX_PREPROCESS_SET_AGC=2 
SPEEX_PREPROCESS_SET_AGC_DECREMENT=28 
SPEEX_PREPROCESS_SET_AGC_INCREMENT=26 
SPEEX_PREPROCESS_SET_AGC_LEVEL=6 
SPEEX_PREPROCESS_SET_AGC_MAX_GAIN=30 
SPEEX_PREPROCESS_SET_DENOISE=0 
SPEEX_PREPROCESS_SET_DEREVERB=8 
SPEEX_PREPROCESS_SET_DEREVERB_DECAY=12 
SPEEX_PREPROCESS_SET_DEREVERB_LEVEL=10 
SPEEX_PREPROCESS_SET_ECHO_STATE=24 
SPEEX_PREPROCESS_SET_ECHO_SUPPRESS=20 
SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE=22 
SPEEX_PREPROCESS_SET_NOISE_SUPPRESS=18 
SPEEX_PREPROCESS_SET_PROB_CONTINUE=16 
SPEEX_PREPROCESS_SET_PROB_START=14 
SPEEX_PREPROCESS_SET_VAD=4
SPEEX_ECHO_GET_FRAME_SIZE=3
SPEEX_ECHO_SET_SAMPLING_RATE=24
SPEEX_ECHO_GET_SAMPLING_RATE=25
SPEEX_ECHO_GET_IMPULSE_RESPONSE_SIZE=27
SPEEX_ECHO_GET_IMPULSE_RESPONSE=29

class Processor
attr_reader :freq
attr_reader :ch
attr_reader :framesize
def initialize(freq=48000, ch=2, framesize=20)
@queue=""
@freq, @ch, @framesize = freq, ch, framesize
@stepsize=@ch*@framesize*2*@freq/1000
@preprocessors=[]
@echo=nil
ch.times {@preprocessors.push(Preprocess_state_init.call(@framesize*@freq/1000, @freq))}
setctl_int(SPEEX_PREPROCESS_SET_DENOISE, 0)
setctl_int(SPEEX_PREPROCESS_SET_AGC, 0)
setctl_int(SPEEX_PREPROCESS_SET_AGC_LEVEL, @freq)
setctl_int(SPEEX_PREPROCESS_SET_DEREVERB, 0)
setctl_float(SPEEX_PREPROCESS_SET_DEREVERB_DECAY, 0)
setctl_float(SPEEX_PREPROCESS_SET_DEREVERB_LEVEL, 0)
end
def noise_reduction
return getctl_int(SPEEX_PREPROCESS_GET_DENOISE)==1
end
def noise_reduction=(b)
setctl_int(SPEEX_PREPROCESS_SET_DENOISE, (b)?(1):(0))
return b
end
def set_echo(ec)
return nil if !ec.is_a?(Echo)
for i in 0...@preprocessors.size
pc=EltenNativeStructs.pointer_buffer(ec.echoes[i])
Preprocess_ctl.call(@preprocessors[i], SPEEX_PREPROCESS_SET_ECHO_STATE, pc)
end
@echo=ec
return ec
end
def free
@preprocessors.each {|pr|Preprocess_state_destroy.call(pr)}
@preprocessors=nil
end
def process(data)
audio=@queue+data
index=0
ret=""
while (audio.bytesize-index)>=@stepsize
frg=audio.byteslice(index...index+@stepsize)
channels=[]
sources=frg.unpack("s*").each_slice(@ch).to_a.transpose
for c in 0...@ch
frame=sources[c].pack("s*")
Preprocess_run.call(@preprocessors[c], frame)
channels[c]=frame.unpack("s*")
end
out=channels[0].zip(*channels[1..-1]).flatten.pack("s*")
ret+=out
index+=@stepsize
end
@queue=audio.byteslice(index..-1)
return ret
rescue Exception
log(2, $!.to_s+" "+$@.to_s)
return ""
end
private
def setctl_int(flag, value)
for pr in @preprocessors
pc=[value].pack("i")
Preprocess_ctl.call(pr, flag, pc)
end
end
def getctl_int(flag)
pc=[0].pack("i")
Preprocess_ctl.call(@preprocessors[0], flag, pc)
return pc.unpack("i").first
end
def setctl_float(flag, value)
for pr in @preprocessors
pc=[value].pack("f")
Preprocess_ctl.call(pr, flag, pc)
end
end
def getctl_float(flag)
pc=[0.0].pack("f")
Preprocess_ctl.call(@preprocessor[0], flag, pc)
return pc.unpack("f").first
end
end

class Echo
attr_reader :framesize
attr_reader :ch
attr_reader :delay
attr_reader :echoes
def initialize(freq=48000, ch=2, framesize=20, delay=100)
@playbackqueue=""
@capturequeue=""
@freq, @ch, @framesize, @delay = freq, ch, framesize, delay
@stepsize=@ch*@framesize*2*@freq/1000
@delaysize=@ch*@delay*2*@freq/1000
@echoes=[]
ch.times {@echoes.push(Echo_state_init.call(@framesize*@freq/1000, @delay*@freq/1000))}
setctl_int(SPEEX_ECHO_SET_SAMPLING_RATE, @freq)
end
def free
@echoes.each {|e|Echo_state_destroy.call(e)}
@echoes=nil
end
def cancellation(indata, outdata)
return indata if indata.bytesize>outdata.bytesize
return indata if indata.bytesize!=@stepsize
indata=indata.byteslice(0...outdata.bytesize) if indata.bytesize>outdata.bytesize
out="\0"*indata.bytesize
for c in 0...@ch
inframe=("\0"*(@stepsize/@ch)).b
outframe=("\0"*(@stepsize/@ch)).b
for i in 0...(@stepsize/@ch/2)
inframe.setbyte(i*2, indata.getbyte(2*(@ch*i+c)))
outframe.setbyte(i*2, outdata.getbyte(2*(@ch*i+c)))
inframe.setbyte(i*2+1, indata.getbyte(2*(@ch*i+c)+1))
outframe.setbyte(i*2+1, outdata.getbyte(2*(@ch*i+c)+1))
end
resframe="\0"*inframe.bytesize
Echo_cancellation.call(@echoes[c], inframe, outframe, resframe)
for i in 0...@stepsize/@ch/2
out.setbyte(2*(@ch*i+c), resframe.getbyte(i*2))
out.setbyte(2*(@ch*i+c)+1, resframe.getbyte(i*2+1))
end
end
return out
end
def capture(data)
audio=@capturequeue+data+""
index=0
ret=""
while (audio.bytesize-index)>=@stepsize
frg=audio.byteslice(index...index+@stepsize)
out=("\0"*@stepsize).b
for c in 0...@ch
frame=("\0"*(@stepsize/@ch)).b
resframe="\0"*frame.bytesize
for i in 0...(@stepsize/@ch/2)
frame.setbyte(i*2, frg.getbyte(2*(@ch*i+c)))
frame.setbyte(i*2+1, frg.getbyte(2*(@ch*i+c)+1))
end
Echo_capture.call(@echoes[c], frame, resframe)
for i in 0...@stepsize/@ch/2
out.setbyte(2*(@ch*i+c), resframe.getbyte(i*2))
out.setbyte(2*(@ch*i+c)+1, resframe.getbyte(i*2+1))
end
end
ret+=out
index+=@stepsize
end
@capturequeue=audio.byteslice(index..-1)
return ret
end
def playback(data)
audio=@playbackqueue+data+""
index=0
ret=""
while (audio.bytesize-index)>=@stepsize
frg=audio.byteslice(index...index+@stepsize)
out=("\0"*@stepsize).b
for c in 0...@ch
frame=("\0"*(@stepsize/@ch)).b
resframe="\0"*frame.bytesize
for i in 0...(@stepsize/@ch/2)
frame.setbyte(i*2, frg.getbyte(2*(@ch*i+c)))
frame.setbyte(i*2+1, frg.getbyte(2*(@ch*i+c)+1))
end
Echo_playback.call(@echoes[c], frame, resframe)
for i in 0...@stepsize/@ch/2
out.setbyte(2*(@ch*i+c), resframe.getbyte(i*2))
out.setbyte(2*(@ch*i+c)+1, resframe.getbyte(i*2+1))
end
end
ret+=out
index+=@stepsize
end
@playbackqueue=audio.byteslice(index..-1)
return ret
end
private
def setctl_int(flag, value)
for pr in @echoes
pc=[value].pack("i")
Echo_ctl.call(pr, flag, pc)
end
end
def getctl_int(flag)
pc=[0].pack("i")
Echo_ctl.call(@echoes[0], flag, pc)
return pc.unpack("i").first
end
def setctl_float(flag, value)
for pr in @echoes
pc=[value].pack("f")
Echo_ctl.call(pr, flag, pc)
end
end
def getctl_float(flag)
pc=[0.0].pack("f")
Echo_ctl.call(@echo[0], flag, pc)
return pc.unpack("f").first
end
end
end
