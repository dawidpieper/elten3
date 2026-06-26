# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2025 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 



module EltenAPI
  class Conference
class Channel
      attr_accessor :id, :name, :bitrate, :framesize, :vbr_type, :codec_application, :prediction_disabled, :fec, :public, :users, :passworded, :spatialization, :channels, :lang, :creator, :width, :height, :objects, :administrators, :key_len, :groupid, :waiting_type, :banned, :permanent, :password, :uuid, :motd, :allow_guests, :room_id, :followed, :join_url, :conference_mode, :whitelist, :followers_count, :stream_bitrate, :stream_framesize
      def initialize
        @name=""
        @framesize=60
        @bitrate=64
        @vbr_type=1
        @codec_application=0
        @prediction_disabled=false
        @fec=false
        @public=true
        @users=[]
        @id=0
        @passworded=false
        @channels=2
        @spatialization=0
        @lang=""
        @creator=nil
        @width=@height=15
        @administrators=[]
        @key_len=256
        @groupid=0
        @waiting_type = 0
        @banned=[]
        @permanent=false
        @conference_mode=0
        @whitelist=[]
@followers_count=0
        end
      end
      class ChannelObject
        attr_reader :id, :resid, :name, :x, :y
        def initialize(id, resid, name, x=0, y=0)
          @id, @resid, @name, @x, @y = id, resid, name, x, y
          end
        end
    class ChannelUser
     attr_accessor :id, :name, :waiting, :supervisor, :speech_requested, :speech_allowed
     def initialize(id, name, waiting=false, supervisor=nil, speech_requested=false, speech_allowed=false)
       @id=id
       @name=name
       @waiting=waiting
       @supervisor = supervisor
       @speech_requested=speech_requested
       @speech_allowed=speech_allowed
       end
     end
     class ChannelUserVolume
       attr_accessor :user, :volume, :muted, :chat_muted, :streams_muted
       def initialize(user, volume, muted, chat_muted, streams_muted)
         @user=user
         @volume=volume
         @muted=muted
         @chat_muted=chat_muted
         @streams_muted = streams_muted
       end
       end
     class ConferenceHook
       attr_reader :hook, :block
       def initialize(hook, block)
         @hook=hook
         @block=block
         end
       end
     
       class Streams
         attr_reader :sources, :streams
         def initialize
           @sources=[]
           @streams=[]
           end
         end
       
         class Stream
           attr_reader :sources
           attr_accessor :name, :volume, :x, :y, :locally_muted
           def initialize
             @sources=[]
             @name=""
             @volume=""
             @x=0
             @y=0
             @locally_muted=false
           end
         end
         
         class Source
           attr_accessor :name, :volume, :scrollable, :toggleable
           def initialize
             @name=""
             @volume=100
             @scrollable=false
             @toggleable=false
             end
           end
         
    @@opened=false
@@userid=0
    @@volume=0
    @@input_volume=0
@@muted=false
@@stream_volume=0
    @@channels=nil
@@volumes={}
@@streamid_mutes={}
@@mystreams=Streams.new
@@streams=[]
@@channel=Channel.new
@@waiting_channel_id=0
@@created=nil
@@hooks=[]
@@status={}
@@streaming=false
@@shoutcast=false
@@cardset=false
@@texts=[]
@@saving=false
@@pushtotalk=false
@@pushtotalk_keys=[]
@@x=0
@@y=0
@@dir=0
@@vsts=nil
@@vstpreset=nil
@@vstbank=nil
@@core=nil
@@core_loaded=false
@@keyboard_thread=nil
@@configuration_signature=nil
@@configuration_tick=0

def self.load_steamaudio(file=nil)
  setup_core_runtime(false)
  require_relative "audio/steamaudio" unless defined?(::SteamAudio)
  SteamAudio.load(file)
rescue Exception
  Log.error("Conference SteamAudio load: #{$!.class}: #{$!.message}")
  false
end

def self.shutdown
  close
  @@keyboard_thread.kill if @@keyboard_thread!=nil && @@keyboard_thread.alive?
  @@keyboard_thread=nil
  SteamAudio.free if defined?(::SteamAudio)
rescue Exception
  Log.error("Conference shutdown: #{$!.class}: #{$!.message}")end

def self.setup_core_runtime(load_core=true)
  return if @@core_loaded && (load_core==false || const_defined?(:Core, false))
  require "base64"
  require "json"
  require "openssl"
  require "socket"
  require "thread"
  require "zlib"
  require "base62"
  require "io/wait"
  require "zstd-ruby"
  require_relative "conferencenative"
  begin
    require "xz"
    Object.const_set(:XZ_AVAILABLE, true) unless defined?(::XZ_AVAILABLE)
  rescue LoadError, Fiddle::DLError
    Object.const_set(:XZ_AVAILABLE, false) unless defined?(::XZ_AVAILABLE)
  end
  setup_legacy_symbols
  setup_kernel_helpers
  setup_ogg_symbols
  require_relative "audio/opus" unless defined?(::Opus)
  require_relative "audio/speexdsp" unless defined?(::SpeexDSP)
  require_relative "audio/steamaudio" unless defined?(::SteamAudio)
  require_relative "../eltenlink/voip" unless defined?(::EltenLink::VoIP)
  require_relative "conferencecore" if load_core && !const_defined?(:Core, false)
  start_keyboard_state
  @@core_loaded=true
end

  def self.setup_legacy_symbols
    require_relative "conferencenative"
  end

  def self.setup_kernel_helpers
    return if Kernel.method_defined?(:log)
    Kernel.module_eval do
      def log(level, msg=nil)
        if msg==nil
          msg=level
          level=0
        end
        Log.add(level.to_i, msg.to_s)
      rescue Exception
      end
      private :log
    end
  end

  def self.setup_ogg_symbols
    return if $ogg_stream_init != nil
    $vorbisrecordproc ||= EltenRubyFunction.new { |_handle, _buffer, _size, _user| 0 }
    begin
      ogg=EltenRuntimePaths.dlopen("ogg")
      $ogg_stream_init=Fiddle::Function.new(ogg["ogg_stream_init"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      $ogg_stream_packetin=Fiddle::Function.new(ogg["ogg_stream_packetin"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      $ogg_stream_pageout=Fiddle::Function.new(ogg["ogg_stream_pageout"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      $ogg_stream_clear=Fiddle::Function.new(ogg["ogg_stream_clear"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    rescue Exception
      $ogg_stream_init=EltenRubyFunction.new { |_stream, _serial| 0 }
      $ogg_stream_packetin=EltenRubyFunction.new { |_stream, _packet| 0 }
      $ogg_stream_pageout=EltenRubyFunction.new { |_stream, _page| 0 }
      $ogg_stream_clear=EltenRubyFunction.new { |_stream| 0 }
    end
  end

def self.start_keyboard_state
  return if @@keyboard_thread!=nil && @@keyboard_thread.alive?
  $conference_key_state ||= Array.new(256, false)
  @@keyboard_thread=Thread.new {
    Thread.current.report_on_exception=false
    loop {
      keys = EltenKeyboard.active_pressed_keys
      $conference_key_state=keys
      sleep 0.02
    }
  }
rescue Exception
  Log.error("Conference keyboard state: #{$!.class}: #{$!.message}")end

def self.sync_core_settings
  $name=Session.name
  $token=Session.token
  $conferencestcponly=Configuration.tcpconferences.to_i
  $udpmaxpacketsize=Configuration.udppacketsize.to_i
  $conferencesaudiobuffer=Configuration.conferencesaudiobuffer.to_i
  $conferencesaudiobuffercutoff=Configuration.conferencesaudiobuffercutoff.to_i
  $usedenoising=Configuration.usedenoising.to_i
  $useechocancellation=Configuration.useechocancellation.to_i
  $usebilinearhrtf=Configuration.usebilinearhrtf.to_i
  $volume=Configuration.volume.to_i
  $disableconferencemiconrecord=Configuration.disableconferencemiconrecord.to_i
  $recording=false if $recording==nil
  $udpmaxpacketsize=1480 if $udpmaxpacketsize==nil || $udpmaxpacketsize<=0
rescue Exception
  Log.error("Conference settings sync: #{$!.class}: #{$!.message}")end

def self.configuration_signature
  {
    :soundcard => Configuration.soundcard.to_s,
    :microphone => Configuration.microphone.to_s,
    :usedenoising => Configuration.usedenoising.to_i
  }
end

def self.tick
  return if @@core==nil
  now=Time.now.to_f
  return if now-@@configuration_tick<0.5
  @@configuration_tick=now
  signature=configuration_signature
  if @@configuration_signature==nil
    @@configuration_signature=signature
    sync_core_settings
    return
  end
  return if signature==@@configuration_signature
  changed=signature.keys.select{|key| signature[key]!=@@configuration_signature[key]}
  sync_core_settings
  Log.info("Conference configuration changed: #{changed.map{|key| key.to_s}.join(", ")}")
  @@core.reset if @@core!=nil
  @@configuration_signature=signature
rescue Exception
  Log.error("Conference configuration tick: #{$!.class}: #{$!.message}")end

def self.safe(default=nil)
  sync_core_settings
  yield
rescue Exception
  Log.error("Conference: #{$!.class}: #{$!.message} - #{$@.to_s}")
  default
end

def self.core
  @@core
end

def self.ensure_open
  open if @@opened==false || @@core==nil
  @@core
end

def self.open_core(nick=nil)
  setup_core_runtime
  close_core(false)
  sync_core_settings
  @@configuration_signature=configuration_signature
  @@core=Core.new(nick)
  attach_core_callbacks(@@core)
  @@core
end

def self.refresh_open_state
  return if @@core==nil
  setopened({
    "userid"=>@@core.userid,
    "volume"=>@@core.volume,
    "input_volume"=>@@core.input_volume,
    "stream_volume"=>@@core.stream_volume,
    "muted"=>@@core.muted,
    "pushtotalk"=>@@core.pushtotalk,
    "pushtotalk_keys"=>@@core.pushtotalk_keys.map{|k|k.to_s}.join(",")
  })
end

def self.close_core(trigger_close=true)
  if @@core!=nil
    begin
      @@core.free
    rescue Exception
      Log.error("Conference close: #{$!.class}: #{$!.message}")
    end
  end
  @@core=nil
  @@configuration_signature=nil
  setclosed if trigger_close
end

def self.attach_core_callbacks(conf)
  conf.on_channel {|ch| setchannel(JSON.generate(ch))}
  conf.on_waitingchannel {|chid| setwaitingchannel(chid)}
  conf.on_status {|st| setstatus(JSON.generate(st))}
  conf.on_volumes {|vl| setvolumes(JSON.generate(vl))}
  conf.on_streammute {|id,mute| setstreamidmute(id, mute)}
  conf.on_change {|param,value| setchange(param, value)}
  conf.on_mystreams {|params| setmystreams(JSON.generate(params))}
  conf.on_streams {|streams|
    setstreams(JSON.generate(streams.values.map{|s|{"id"=>s.streamid, "name"=>s.name, "userid"=>s.userid, "username"=>s.username, "x"=>s.stream_x, "y"=>s.stream_y, "volume"=>s.volume}}))
  }
  conf.on_user {|joined, username| announce_user(joined ? "conference_userjoin" : "conference_userleave", username)}
  conf.on_waitinguser {|joined, username| announce_user(joined ? "conference_userknock" : "conference_userleave", username)}
  conf.on_speaker {|status, username, _userid| announce_speaker(status, username)}
  conf.on_text {|username, userid, message|
    settext(username, userid, message)
    announce_text(username, message, "conference_message")
  }
  conf.on_diceroll {|username, userid, value, count|
    setdiceroll(username, userid, value, count)
    announce_text(username, value.to_s, "conference_diceroll")
  }
end

def self.announce_user(sound, username)
  Thread.new {
    play_sound(sound)
    speak(username)
    wait_for_speech_interrupt
  }
end

def self.announce_speaker(status, username)
  Thread.new {
    if status==2
      play_sound("conference_speechrequest")
      speak(username)
    elsif status==1
      play_sound("conference_speechallow")
      speak(p_("Conference", "Speech allowed"))
    elsif status==0
      play_sound("conference_speechdeny")
      speak(p_("Conference", "Speech denied"))
    end
    wait_for_speech_interrupt
  }
end

def self.announce_text(username, message, sound)
  Thread.new {
    speak(username.to_s+": "+message.to_s[0...4999])
    play_sound(sound)
    wait_for_speech_interrupt
  }
end

def self.wait_for_speech_interrupt
  while speech_actived
    speech_stop if key_held?(0x11)
    sleep 0.01
  end
rescue Exception
end

def self.source_for(stream, source, may_stream=false)
  return nil if @@core==nil
  source=0 if may_stream==false && source==nil
  if !stream.is_a?(Numeric)
    s=@@core.sources.find{|src|src.is_a?(Core::StreamSourceFile)}
    return s if s!=nil
    for st in @@core.outstreams
      s=st.sources.find{|src|src.is_a?(Core::StreamSourceFile)}
      return s if s!=nil
    end
    return nil
  elsif source==nil
    return @@core.outstreams[stream]
  elsif stream==-1
    return @@core.sources[source]
  else
    st=@@core.outstreams[stream]
    return st.sources[source] if st!=nil
  end
  nil
end

def self.add_card_to_core(card, listen=false)
  cardid=-1
  Bass.microphones.each_with_index {|mic, i|
    next if i==0
    if mic.name==card || mic==card
      cardid=i
      break
    end
  }
  @@core.addg_card(cardid, listen==true) if cardid>-1 && @@core!=nil
end
def self.open(ignorePTT=false, nick=nil)
  @@opened=false
  volume=LocalConfig["ConferenceVolume", -1]
  input_volume=LocalConfig["ConferenceInputVolume", -1]
  stream_volume=LocalConfig["ConferenceStreamVolume", -1]
  pushtotalk=LocalConfig["ConferencePushToTalk", -1]
  pushtotalk_keys=LocalConfig["ConferencePushToTalkKeys", []]
  safe { 
    open_core(nick)
    @@core.volume=volume if volume!=-1
    @@core.stream_volume=stream_volume if stream_volume!=-1
    @@core.input_volume=input_volume if input_volume!=-1
    @@core.pushtotalk=(pushtotalk==1) if ignorePTT!=true && pushtotalk!=-1
    @@core.pushtotalk_keys=pushtotalk_keys.map{|k|k.to_i} if ignorePTT!=true && pushtotalk_keys!=[]
    refresh_open_state
  }
  t=Time.now.to_f
  while Time.now.to_f-t<3
    loop_update
    break if @@opened==true
  end
  delay(0.5)
end
def self.close
  close_core
  end
def self.join(id, password=nil)
  if @@opened==false
  self.open
  delay(1)
else
  return if @@channel.id==id
  end
  safe {@@core.join_channel(id, password) if @@core!=nil}
end
def self.leave
  if @@opened==false
  self.open
  delay(1)
  end
  safe {@@core.leave_channel if @@core!=nil}
end
def self.status
  @@status||{}
end
def self.pushtotalk
  @@pushtotalk
end
def self.pushtotalk=(k)
  safe {@@core.pushtotalk=(k==true) if @@core!=nil}
  @@pushtotalk=(k==true)
end
def self.pushtotalk_keys
  @@pushtotalk_keys
end
def self.pushtotalk_keys=(k)
  safe {@@core.pushtotalk_keys=k if @@core!=nil}
  @@pushtotalk_keys=k
end
def self.streaming?
  @@streaming
end
def self.shoutcast?
  @@shoutcast
  end
def self.cardset?
  @@cardset
end
def self.send_text(text)
  safe {@@core.send_text(text) if @@core!=nil}
end
def self.diceroll(cnt=6)
  safe {@@core.diceroll(cnt) if @@core!=nil}
end
def self.saving?
  @@saving==true
  end
def self.begin_save(file)
  safe {@@core.begin_save(file) if @@core!=nil && file.is_a?(String)}
  @@saving=true
end
def self.begin_fullsave(dir)
  safe {@@core.begin_fullsave(dir) if @@core!=nil && dir.is_a?(String)}
  @@saving=true
end
def self.end_save
  safe {@@core.end_save if @@core!=nil}
  @@saving=false
end
def self.set_device(dev)
  safe {@@core.set_device(dev) if @@core!=nil}
end
def self.add_card(card, listen=false)
  @@cardset=true
  safe {add_card_to_core(card, listen)}
end
def self.remove_card
  safe {@@core.remove_card if @@core!=nil}
  @@cardset=false
end
def self.object_remove(id)
  safe {@@core.object_remove(id) if @@core!=nil}
end
def self.object_add(resid, name, location)
  safe {
    x=0
    y=0
    if location==0 && @@core!=nil
      x=@@core.x
      y=@@core.y
    end
    @@core.object_add(resid, name, x, y) if @@core!=nil
  }
end
def self.stream_remove(id)
  safe {@@core.stream_remove(id) if @@core!=nil}
end
def self.removesource(stream, source)
  source_remove(stream, source)
end
def self.source_remove(stream, source)
  safe {
    if @@core!=nil
      st=@@core.outstreams[stream]
      if st!=nil
        st.remove_source(source)
      else
        @@core.remove_source(source)
      end
      @@core.streams_callback
    end
  }
end
def self.stream_add_file(file, name, x=-1, y=-1)
  safe {@@core.stream_add_file(file, name, x, y) if @@core!=nil}
end
def self.stream_add_url(url, name, x=-1, y=-1)
  safe {@@core.stream_add_url(url, name, x, y) if @@core!=nil}
end
def self.stream_add_card(cardid, name, x=-1, y=-1, mute=false)
  safe {
    stream=@@core.stream_add_card(cardid, name, x, y) if @@core!=nil
    if stream!=nil && mute==true
      stream.locally_muted=true
      @@core.streams_callback
    end
  }
end
def self.source_add_file(stream, file)
  safe {((@@core.outstreams[stream]||@@core).add_file(file); @@core.streams_callback) if @@core!=nil}
end
def self.source_add_url(stream, url)
  safe {((@@core.outstreams[stream]||@@core).add_url(url); @@core.streams_callback) if @@core!=nil}
end
def self.source_add_card(stream, cardid)
  safe {((@@core.outstreams[stream]||@@core).add_card(cardid); @@core.streams_callback) if @@core!=nil}
end
def self.set_stream(file)
  safe {@@core.set_stream(file) if @@core!=nil}
end
def self.remove_stream
  safe {@@core.remove_stream if @@core!=nil}
end
def self.scrollstream(pos_plus, stream=nil, source=nil)
  safe {
    st=source_for(stream, source)
    st.position+=pos_plus if st!=nil && st.scrollable?
  }
end
def self.togglestream(stream=nil, source=nil)
  safe {
    st=source_for(stream, source)
    st.toggle if st!=nil && st.toggleable?
  }
  delay(0.05)
end
def self.locallymutestream(stream=nil, mute=false)
  safe {
    st=@@core.outstreams[stream] if @@core!=nil
    st.locally_muted=mute if st!=nil
    @@core.streams_callback if @@core!=nil
  }
  delay(0.05)
end
def self.volumestream(volume, stream=nil, source=nil)
  safe {
    st=source_for(stream, source, true)
    st.volume=volume if st!=nil
    @@core.streams_callback if @@core!=nil
  }
  delay(0.05)
end
def self.set_shoutcast(server, pass, name=nil, pub=false, bitrate=128)
  safe {@@core.shoutcast_start(server, pass, name, pub, bitrate) if @@core!=nil}
end
def self.remove_shoutcast
  safe {@@core.shoutcast_stop if @@core!=nil}
end
def self.move(x_plus, y_plus)
  safe {
    if @@core!=nil
      dir=@@core.dir
      if dir!=0
        sn=Math::sin(Math::PI/180*dir)
        cs=Math::cos(Math::PI/180*dir)
        px=x_plus*cs-y_plus*sn
        py=x_plus*sn+y_plus*cs
        x_plus=px.round
        y_plus=py.round
      end
      @@core.x+=x_plus
      @@core.y+=y_plus
    end
  }
  delay(0.1)
end
def self.turn(dir_plus)
  safe {@@core.dir+=dir_plus if @@core!=nil}
  delay(0.1)
end
def self.goto_user(userid)
  safe {@@core.goto(userid.to_i) if @@core!=nil}
  delay(0.1)
end
def self.streamid_setvolume(id, volume, mute)
  safe {@@core.streamid_setvolume(id, volume, mute) if @@core!=nil && id.is_a?(Integer)}
  delay(0.1)
end
def self.kick(userid)
  safe {@@core.kick(userid) if @@core!=nil && userid.is_a?(Integer)}
  delay(0.1)
end
def self.accept(userid)
  safe {@@core.accept(userid) if @@core!=nil && userid.is_a?(Integer)}
  delay(0.1)
end
def self.ban(username)
  safe {@@core.ban(username) if @@core!=nil && username.is_a?(String)}
  delay(1.5)
end
def self.unban(username)
  safe {@@core.unban(username) if @@core!=nil && username.is_a?(String)}
  delay(1.5)
end
def self.admin(username)
  safe {@@core.admin(username) if @@core!=nil && username.is_a?(String)}
  delay(1.5)
end
def self.unadmin(username)
  safe {@@core.unadmin(username) if @@core!=nil && username.is_a?(String)}
  delay(1.5)
end
def self.whitelist(username)
  safe {@@core.whitelist(username) if @@core!=nil && username.is_a?(String)}
  delay(1.5)
end
def self.whiteunlist(username)
  safe {@@core.whiteunlist(username) if @@core!=nil && username.is_a?(String)}
  delay(1.5)
end
def self.supervise(userid)
  safe {@@core.supervise(userid) if @@core!=nil && userid.is_a?(Integer)}
  delay(0.1)
end
def self.unsupervise(userid)
  safe {@@core.unsupervise(userid) if @@core!=nil && userid.is_a?(Integer)}
  delay(0.1)
end
def self.follow(channel)
  safe {@@core.follow(channel) if @@core!=nil && channel.is_a?(Integer)}
  delay(0.1)
end
def self.unfollow(channel)
  safe {@@core.unfollow(channel) if @@core!=nil && channel.is_a?(Integer)}
  delay(0.1)
end
def self.speech_request
  safe {@@core.speech_request if @@core!=nil}
  delay(0.1)
end
def self.speech_refrain
  safe {@@core.speech_refrain if @@core!=nil}
  delay(0.1)
end
def self.speech_allow(userid, replace=false)
  safe {@@core.speech_allow(userid, replace) if @@core!=nil && userid!=nil}
  delay(0.1)
end
def self.speech_deny(userid)
  safe {@@core.speech_deny(userid) if @@core!=nil && userid!=nil}
  delay(0.1)
end
def self.goto(x,y)
  safe {
    if @@core!=nil && x.is_a?(Integer) && y.is_a?(Integer)
      @@core.x=x
      @@core.y=y
    end
  }
  delay(0.1)
end
def self.whisper(userid)
  safe {@@core.whisper=userid if @@core!=nil}
  end
def self.create(name="", public=true, bitrate=64, framesize=60, vbr_type=1, codec_application=0, prediction_disabled=false, fec=false, password=nil, spatialization=0, channels=2, lang='', width=15, height=15, key_len=256, waiting_type=0, permanent=false, motd="", allow_guests=false, conference_mode=0)
  if @@opened==false
  self.open
  delay(1)
  end
  @@created=nil
  params={'name'=>name, 'public'=>public, 'bitrate'=>bitrate, 'framesize'=>framesize, 'vbr_type'=>vbr_type, 'codec_application'=>codec_application, 'prediction_disabled'=>prediction_disabled, 'fec'=>fec, 'password'=>password, 'spatialization'=>spatialization, 'channels'=>channels, 'lang'=>lang, 'width'=>width, 'height'=>height, 'key_len'=>key_len, 'waiting_type'=>waiting_type, 'permanent'=>permanent, 'motd'=>motd, 'allow_guests'=>allow_guests, 'conference_mode'=>conference_mode}
  @@created=safe(nil) {@@core.create_channel(params) if @@core!=nil}
  return @@created
end
def self.edit(id, name, public, bitrate, framesize, vbr_type, codec_application, prediction_disabled, fec, password, spatialization, channels, lang, width, height, key_len, waiting_type, permanent, motd, allow_guests, conference_mode)
  if @@opened==false
  self.open
  delay(1)
end
params={'channel'=>id, 'name'=>name, 'public'=>public, 'bitrate'=>bitrate, 'framesize'=>framesize, 'vbr_type'=>vbr_type, 'codec_application'=>codec_application, 'prediction_disabled'=>prediction_disabled, 'fec'=>fec, 'password'=>password, 'spatialization'=>spatialization, 'channels'=>channels, 'lang'=>lang, 'width'=>width, 'height'=>height, 'key_len'=>key_len, 'waiting_type'=>waiting_type, 'permanent'=>permanent, 'motd'=>motd, 'allow_guests'=>allow_guests, 'conference_mode'=>conference_mode}
safe {@@core.edit_channel(id, params) if @@core!=nil && id.is_a?(Integer)}
delay(1)
end
def self.update_channels
  if @@opened==false
  self.open
  delay(1)
  end
  @@channels=nil
  @@channels=safe([]) {@@core!=nil ? @@core.list_channels.map{|ch|ch} : []}
  end
  def self.muted
    @@muted
  end
  def self.muted=(mt)
    if @@opened==false
  self.open
  delay(1)
  end
    safe {@@core.muted=(mt==true) if @@core!=nil}
    @@muted=(mt==true)
    delay(0.2)
    end
  def self.input_volume
    @@input_volume
  end
  def self.input_volume=(vol)
    if @@opened==false
  self.open
  delay(1)
  end
    vol=0 if vol<0
safe {@@core.input_volume=vol if @@core!=nil}
LocalConfig["ConferenceInputVolume"]=vol
    @@input_volume=vol
  end
  def self.output_volume
    @@volume
  end
  def self.output_volume=(vol)
    if @@opened==false
  self.open
  delay(1)
  end
    vol=0 if vol<0
    vol=100 if vol>100
safe {@@core.volume=vol if @@core!=nil}
LocalConfig["ConferenceVolume"]=vol
    @@volume=vol
  end
   def self.stream_volume
    @@stream_volume
  end
  def self.stream_volume=(vol)
    if @@opened==false
  self.open
  delay(1)
  end
    vol=0 if vol<0
    vol=100 if vol>100
safe {@@core.stream_volume=vol if @@core!=nil}
LocalConfig["ConferenceStreamVolume"]=vol
    @@stream_volume=vol
  end
def self.volume(user)
  v=self.volumes[user]
  v||=ChannelUserVolume.new(user, 100, false, false, false)
  v
  end
def self.volumes
  return {} if @@volumes==nil
  vls={}
  for u in @@volumes.keys
    vls[u] = ChannelUserVolume.new(u, @@volumes[u][0], @@volumes[u][1], @@volumes[u][2], @@volumes[u][3])
    end
  return vls
end
def self.streamid_mutes
  @@streamid_mutes
  end
def self.mystreams
  return @@mystreams
end
def self.streams
  return @@streams.dup
  end
def self.setvolume(user, volume, muted, chat_muted, streams_muted)
  if @@opened==false
  self.open
  delay(1)
  end
  safe {@@core.setvolume(user, volume, muted, chat_muted, streams_muted) if @@core!=nil}
end
def self.setvstpreset(prm)
  @@vstpreset=Base64.strict_decode64(prm)
  rescue Exception
  end
def self.setvstbank(prm)
  @@vstbank=Base64.strict_decode64(prm)
  rescue Exception
  end
  def self.texts
  return @@texts
end
def self.waiting_channel_id
  @@waiting_channel_id
  end
  def self.channels
    channels=[]
  if @@channels.is_a?(Array)
    for cha in @@channels
            ch=Channel.new
      ch.id=cha['id'].to_i
      ch.name=cha['name'].to_s
      ch.framesize=cha['framesize'].to_f
      ch.bitrate=cha['bitrate'].to_i
      ch.vbr_type = cha['vbr_type'].to_i
      ch.codec_application = cha['codec_application'].to_i
      ch.prediction_disabled = cha['prediction_disabled']==true
      ch.fec=cha['fec']==true
      ch.passworded=true if cha['passworded']==true
      ch.password=cha['password']
      ch.lang=cha['lang']
      ch.channels=cha['channels']
      ch.spatialization=cha['spatialization']
      ch.creator=cha['creator']
      ch.groupid=cha['groupid'].to_i
      for u in cha['users']
        ch.users.push(ChannelUser.new(u['id'], u['name']))
      end
      ch.administrators=cha['administrators']||[]
      ch.whitelist=cha['whitelist']||[]      
      ch.banned=cha['banned']||[]
      ch.key_len=cha['key_len']
      ch.waiting_type = cha['waiting_type']||0
      ch.width=cha['width'].to_i
      ch.height=cha['height'].to_i
      ch.permanent=(cha['permanent']==true)
      ch.uuid=cha['uuid']
      ch.motd=cha['motd']
      ch.room_id = cha['room_id']
      ch.allow_guests = cha['allow_guests']
      ch.followed=(cha['followed']==true)
      ch.join_url=cha['join_url']
      ch.conference_mode = cha['conference_mode']||0
      ch.followers_count=cha['followers_count']||0
      ch.stream_bitrate=cha['stream_bitrate'].to_i
      ch.stream_framesize=cha['stream_framesize'].to_f
      channels.push(ch)
      end
  end
  return channels
  end
                  def self.opened?
            return @@opened
          end
          def self.userid
            return @@userid
            end
          def self.channel
            return @@channel
          end
          def self.get_coordinates(userid=nil)
            @@x=0
@@y=0
@@dir=0
return [0,0,0] if !self.opened?
safe {
if @@core!=nil
if userid==nil
@@x,@@y,@@dir=@@core.x,@@core.y,@@core.dir
else
coords=@@core.coordinates(userid)
@@x,@@y,@@dir=coords[0],coords[1],0
end
end
}
return [@@x, @@y, @@dir]
end
def self.calling_play
safe {@@core.calling_play if @@core!=nil}
end
def self.calling_stop
safe {@@core.calling_stop if @@core!=nil}
end
          def self.setopened(data)
            self.setclosed
            @@input_volume = data['input_volume']
            @@stream_volume=data['stream_volume']
            @@volume = data['volume']
            @@pushtotalk=data['pushtotalk']
@@pushtotalk_keys=data['pushtotalk_keys'].split(",").map{|k|k.to_i}
@@userid=data['userid']
                        @@opened=true
          end
          def self.setclosed
            trigger(:close)
                        @@opened=false
            @@channels=nil
@@volumes={}
@@streamid_mutes={}
@@mystreams=Streams.new
@@streams=[]
@@channel=Channel.new
@@created=nil
@@volume=0
@@stream_volume=0
@@input_volume=0
@@streaming=false
@@shoutcast=false
  @@cardset=false
@@texts=[]
@@muted=false
@@saving=false
@@pushtotalk=false
@@pushtotalk_keys=[]
@@x=0
@@y=0
@@dir=0
@@waiting_channel_id=0
@@userid=0
          end
                    def self.setchannel(c)
                    params=JSON.load(c)
            if params.is_a?(Hash)
                          ch=Channel.new
            ch.id=(params['id']||0).to_i
            ch.name=params['name']
            ch.framesize=(params['framesize']||60).to_f
            ch.bitrate=(params['bitrate']||0).to_i
            ch.vbr_type = params['vbr_type'].to_i
      ch.codec_application = params['codec_application'].to_i
      ch.prediction_disabled = params['prediction_disabled']==true
      ch.fec=params['fec']==true
            ch.public=params['public']!=false
            ch.spatialization = params['spatialization']||0
            ch.password=params['password']
            ch.channels = params['channels']||2
            ch.lang=params['lang']||""
            ch.creator=params['creator']
            ch.groupid=params['groupid'].to_i
            ch.users=[]
            if params['users'].is_a?(Array)
                                          ch.users=params['users'].map{|u| ChannelUser.new(u['id'], u['name'], false, u['supervisor'], u['speech_requested'], params['speakers'].is_a?(Array) && params['speakers'].include?(u['id']))}
            end
                        if params['waiting_users'].is_a?(Array)
              ch.users+=params['waiting_users'].map{|u| ChannelUser.new(u['id'], u['name'], true)}
            end
            ch.width=params['width']
            ch.height=params['height']
            ch.objects=params['objects'].map{|o|ChannelObject.new(o['id'], o['resid'], o['name'], o['x'], o['y'])}
            ch.administrators=params['administrators']||[]
            ch.whitelist=params['whitelist']||[]      
                  ch.banned=params['banned']||[]
            ch.key_len=params['key_len']
            ch.waiting_type = params['waiting_type']||0
            ch.permanent=(params['permanent']==true)
            ch.uuid=params['uuid']
      ch.motd=params['motd']
      ch.room_id = params['room_id']
      ch.allow_guests = params['allow_guests']      
      ch.join_url=params['join_url']
      ch.conference_mode = params['conference_mode']||0
      ch.followers_count=params['followers_count']||0
      ch.stream_framesize=(params['stream_framesize']||100).to_f
            ch.stream_bitrate=(params['stream_bitrate']||0).to_i
      @@channel=ch
            self.trigger(:update)
          end
        rescue Exception
          Log.error("Conference - Update Channel: #{$!.to_s}, #{$@.to_s}")
        end
        def self.setwaitingchannel(chid)
          @@waiting_channel_id=chid
          self.trigger(:waitingchannel)
          end
                      def self.setcreated(id)
                        @@created=id
                      end
                      def self.setchannels(chs)
                                                @@channels=JSON.load(chs)
                                              rescue Exception
                                                Log.error("Conference - Update Channels list: #{$!.to_s}, #{$@.to_s}")
                        end
                        def self.setstatus(st)
                                                                          @@status=JSON.load(st)
                                                self.trigger(:status)
                                              rescue Exception
                                                Log.error("Conference - Update Status: #{$!.to_s}, #{$@.to_s}")
                        end
                        def self.setvolumes(vls)
                                                @@volumes=JSON.load(vls)
                                              rescue Exception
                                                Log.error("Conference - Update Volumes: #{$!.to_s}, #{$@.to_s}")
                                              end
                                              def self.setstreams(str)
                                                @@streams=JSON.load(str)
                                              rescue Exception
                                                Log.error("Conference - Update streams: #{$!.to_s}, #{$@.to_s}")
                                              end
                                              def self.setstreamidmute(id, mute)
                                                                                                @@streamid_mutes[id]=mute
                                                                                            end
                        def self.setmystreams(str)
                                                st=JSON.load(str)
                                                @@mystreams=Streams.new
                                                for s in st['sources']
                                                  so=Source.new
                                                  so.name=s['name']
                                                  so.volume=s['volume']
                                                  so.scrollable=s['scrollable']
                                                  so.toggleable=s['toggleable']
                                                  @@mystreams.sources.push(so)
                                                end
for s in st['streams']
  str=Stream.new
  str.name=s['name']
  str.volume=s['volume']
  str.x=s['x']
  str.y=s['y']
  str.locally_muted=s['locally_muted']
  for o in s['sources']
    so=Source.new
    so.name=o['name']
    so.volume=o['volume']
                                                      so.scrollable=o['scrollable']
                                                  so.toggleable=o['toggleable']
    str.sources.push(so)
    end
  @@mystreams.streams.push(str)
end
                                              rescue Exception
                                                Log.error("Conference - Update streams: #{$!.to_s}, #{$@.to_s}")
                                                end
                        def self.settext(username, userid, text)
                          @@texts.push([username, userid, text])
                          trigger(:text)
                        end
                        def self.setdiceroll(username, userid, value, count)
                                                    @@texts.push([username, userid, :diceroll, [value, count]])
                          trigger(:text)
                        end
                        def self.setcards(cards)
                          @@cards=JSON.load(cards)
                          rescue Exception
                          end
                          def self.setvsts(vsts)
                          @@vsts=JSON.load(vsts)
                        rescue Exception
                          end                        
                        def self.setcoordinates(x,y,dir)
                          @@x,@@y,@@dir=x.to_i,y.to_i,dir.to_i
                        end
                        def self.setchange(param, value)
                          case param
                          when "muted"
                           @@muted=value
                            when "streaming"
                              @@streaming=value
                              when "pushtotalk"
                                @@pushtotalk=value
                                when "shoutcast"
                              @@shoutcast=value
                          end
                        end
                        def self.vsts(userid=0)
  @@vsts=safe(nil) {
    if @@core!=nil
      @@core.vsts(userid).each_with_index.map {|v,i|
        {'index'=>i, 'name'=>v.name, 'uniqueid'=>v.unique_id, 'version'=>v.version, 'file'=>v.file, 'bypass'=>v.bypass, 'showneditor'=>v.editor_shown?, 'haseditor'=>v.editor?, 'program'=>v.program, 'programs'=>v.programs, 'parameters'=>v.parameters.map{|m|{'name'=>m.name, 'unit'=>m.unit, 'display'=>m.display, 'default'=>m.default, 'value'=>m.value}}}
      }
    end
  }
  @@vsts
end
def self.vst_add(file, userid=0)
safe {@@core.vst_add(file, userid) if @@core!=nil}
end
def self.vst_remove(index, userid=0)
  safe {@@core.vst_remove(index, userid) if @@core!=nil}
  end
def self.vst_setparam(index, parameter, value, userid=0)
  safe {
    vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
    param=vst.parameters[parameter.to_i] if vst!=nil
    param.value=value.to_f if param!=nil
  }
  end
  def self.vst_setbypass(index, bypass, userid=0)
    safe {
      vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
      vst.bypass=bypass if vst!=nil
    }
  end
  def self.vst_setprogram(index, program, userid=0)
    safe {
      vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
      vst.program=program if vst!=nil
    }
  end
  def self.vst_showeditor(index, userid=0)
    safe {
      vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
      vst.editor_show if vst!=nil
    }
  end
  def self.vst_hideeditor(index, userid=0)
    safe {
      vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
      vst.editor_hide if vst!=nil
    }
  end
  def self.vst_export_preset(index, userid=0)
    @@vstpreset=safe(nil) {
      vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
      vst!=nil ? vst.export(:preset) : nil
    }
@@vstpreset
end
  def self.vst_export_bank(index, userid=0)
    @@vstbank=safe(nil) {
      vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
      vst!=nil ? vst.export(:bank) : nil
    }
@@vstbank
end
  def self.vst_import_preset(index, content, userid=0)
  safe {
    vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
    vst.import(:preset, content) if vst!=nil
  }
end
  def self.vst_import_bank(index, content, userid=0)
safe {
  vst=@@core.vsts(userid)[index.to_i] if @@core!=nil
  vst.import(:bank, content) if vst!=nil
}
end
def self.vst_move(index, pos, userid=0)
  safe {@@core.vst_move(index, pos, userid) if @@core!=nil}
  end  
def self.on(hook, &block)
                          if block!=nil
                          hk=ConferenceHook.new(hook, block)
                          @@hooks.push(hk)
                          return hk
                          end
                        end
                        def self.remove_hook(hk)
                          @@hooks.delete(hk)
                          end
                        def self.trigger(hook)
                          for hk in @@hooks
                            hk.block.call if hk.hook==hook
                            end
                          end
    end
    end
