# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  TICK_MS = 10
  TICK_SECONDS = TICK_MS / 1000.0
  PERIODIC_FAST_SECONDS = 0.25
  PERIODIC_MEDIUM_SECONDS = 0.5
  PERIODIC_SLOW_SECONDS = 1.0

  module TimeSource
    class << self
      def current_time
        tm = nil
        tm = NotificationService.server_time
        tm = $wnlasttime if tm == nil && $wnlasttime != nil
        synctime = Configuration.synctime.to_i
        tm = Time.now.to_i if synctime == 0 || tm == nil
        Time.at(tm)
      rescue Exception
        Time.now
      end
    end
  end

  module Alarms
    class << self
      def load(force=false)
        current_path = path
        if force || @alarms == nil || @path != current_path
          @path = current_path
          @alarms = read_file(current_path)
        end
        @alarms
      end

      def replace(alarms, save_file=true)
        @path = path
        @alarms = normalize(alarms)
        save if save_file
        @alarms
      end

      def save
        write_file(path, load)
        true
      rescue Exception => e
        Log.error("Alarm save: #{e.class}: #{e.message}")
        false
      end

      def migrate_legacy_file
        old_path = legacy_path
        new_path = path
        return false if !FileTest.exist?(old_path) || FileTest.exist?(new_path)
        alarms = normalize(File.open(old_path, "rb") { |f| Marshal.load(f) })
        return false if !write_file(new_path, alarms)
        File.delete(old_path)
        @path = new_path
        @alarms = alarms
        Log.info("Migrated alarms.dat to alarms.json")
        true
      rescue Exception => e
        Log.error("Alarm migration: #{e.class}: #{e.message}")
        false
      end

      def update(now=nil)
        now ||= TimeSource.current_time
        minute = now.hour * 60 + now.min
        return if @last_checked_minute == minute
        @last_checked_minute = minute
        alarms = load
        due_index = nil
        alarms.each_with_index do |alarm, index|
          due_index = index if alarm[0].to_i == now.hour && alarm[1].to_i == now.min
        end
        return if due_index == nil
        alarm = alarms[due_index]
        if alarm[2].to_i == 0
          alarms.delete_at(due_index)
          save
        end
        Log.info("Alarm#{alarm[3].nil? ? "" : alarm[3]}")
        $agalarm = true
        $agalarmdescription = alarm[3]
      rescue Exception => e
        Log.error("Alarm update: #{e.class}: #{e.message}")
      end

      private

      def path
        EltenPath.join(Dirs.eltendata, "alarms.json")
      end

      def legacy_path
        EltenPath.join(Dirs.eltendata, "alarms.dat")
      end

      def read_file(file)
        return [] if !FileTest.exist?(file)
        data = JSON.parse(File.binread(file).to_s)
        normalize(data)
      rescue Exception => e
        Log.error("Alarm load: #{e.class}: #{e.message}")
        []
      end

      def write_file(file, alarms)
        payload = normalize(alarms).map { |alarm| alarm_to_hash(alarm) }
        tmp = "#{file}.tmp-#{$$}-#{Thread.current.object_id}"
        File.binwrite(tmp, JSON.pretty_generate(payload))
        File.delete(file) if FileTest.exist?(file)
        File.rename(tmp, file)
        true
      rescue Exception => e
        Log.error("Alarm write: #{e.class}: #{e.message}")
        false
      ensure
        File.delete(tmp) if tmp != nil && FileTest.exist?(tmp) rescue nil
      end

      def normalize(alarms)
        Array(alarms).map do |alarm|
          values = alarm_values(alarm)
          next nil if values == nil
          hour = [[values[0].to_i, 0].max, 23].min
          minute = [[values[1].to_i, 0].max, 59].min
          type = values[2].to_i == 0 ? 0 : 1
          [hour, minute, type, values[3]]
        end.compact
      end

      def alarm_values(alarm)
        if alarm.is_a?(Array) && alarm.size >= 3
          alarm
        elsif alarm.is_a?(Hash)
          repeat = alarm.key?("repeat") ? alarm["repeat"] : alarm["repeated"]
          type = alarm.key?("type") ? alarm_type(alarm["type"]) : (repeat == true ? 1 : 0)
          [
            alarm["hour"],
            alarm["minute"],
            type,
            alarm["description"] || alarm["text"]
          ]
        end
      end

      def alarm_type(value)
        text = value.to_s.downcase
        return 1 if text == "repeat" || text == "repeated" || text == "1"
        0
      end

      def alarm_to_hash(alarm)
        {
          "hour" => alarm[0].to_i,
          "minute" => alarm[1].to_i,
          "type" => alarm[2].to_i == 0 ? "once" : "repeat",
          "repeat" => alarm[2].to_i != 0,
          "description" => alarm[3] == nil ? nil : alarm[3].to_s
        }
      end

    end
  end

  module Clock
    class << self
      def update(now=nil)
        now ||= TimeSource.current_time
        minute = now.hour * 60 + now.min
        return nil if @last_announced_minute == minute
        @last_announced_minute = minute
        period = config_int(:saytimeperiod, 1)
        type = config_int(:saytimetype, 1)
        return nil if type <= 0
        m = now.min
        due = (period > 0 && m == 0) || (period > 1 && m == 30) || (period >= 2 && (m == 15 || m == 45))
        return nil if due != true || $donotdisturb == true
        [type == 1 || type == 3, (type == 1 || type == 2) ? sprintf("%02d:%02d", now.hour, now.min) : nil]
      rescue Exception => e
        Log.error("Clock update: #{e.class}: #{e.message}")
        nil
      end

      private

      def config_int(name, default)
        return default if !Configuration.respond_to?(name)
        value = Configuration.__send__(name)
        value == nil ? default : value.to_i
      rescue Exception
        default
      end
    end
  end

  module UI
    @@altdowntime=0
    private
# User interface related functions
    def play_sound(voice, volume: 100, pitch: 100, pan: 50, ignore_soundtheme: false)
                              if Configuration.soundthemeactivation != 0 or FileTest.exists?(voice) or ignore_soundtheme==true
                          b=nil
                        if volume >= 0
                          volume = (volume.to_f * Configuration.volume.to_f / 100.0)
                        volume = 100 if volume > 100
                          volume = 1 if volume < 1
                                                volume = volume.to_i
                                              else
                                                volume = volume * -1
                                                volume = 100 if volume > 100
                                              end
                                                sound=nil
                                                sound=getsound(voice)
                                                if sound!=nil || FileTest.exists?(voice)
stream=nil
Bass.cleanup_memory_streams
if sound!=nil
                                                  stream=Bass.create_file_stream_from_memory(sound, Bass::BASS_STREAM_AUTOFREE)
                                                else
                                                  stream=Bass.create_file_stream_from_path(voice, 0, Bass::BASS_STREAM_AUTOFREE)
                                                  end
if stream.to_i == 0
  Log.error("Cannot play sound #{voice.inspect}: #{Bass.error_name}")
  return
end
Bass::BASS_ChannelSetAttribute.call(stream, 2, volume.to_f/100.0*0.5)
if pitch != 100
  f = [0].pack("f")
  Bass::BASS_ChannelGetAttribute.call(stream, 1, f)
  frq = f.unpack("f").first
  freq = frq * pitch / 100.0
  Bass::BASS_ChannelSetAttribute.call(stream, 1, freq.to_f)
  end
if Configuration.usepan==1
  Bass::BASS_ChannelSetAttribute.call(stream, 3, pan.to_f/50.0-1.0)
                                                  end
                                                                                                                                                                                                      Bass::BASS_ChannelPlay.call(stream, 0)
                        end
                        end
                      end
                      
                        def play_file(file, volume: 100, pitch: 100, pan: 50)
if FileTest.exists?(file)
stream=Bass.create_file_stream_from_path(file, 0, 256|Bass::BASS_STREAM_AUTOFREE)
if stream.to_i == 0
  Log.error("Cannot play file #{file.inspect}: #{Bass.error_name}")
  return
end
if pitch!=100
f=[0].pack("f")
Bass::BASS_ChannelGetAttribute.call(stream, 1, f)
frq=f.unpack("f").first
freq = frq*pitch/100.0
Bass::BASS_ChannelSetAttribute.call(stream, 1, freq.to_f)
end
Bass::BASS_ChannelSetAttribute.call(stream, 2, volume.to_f/100.0)
  Bass::BASS_ChannelSetAttribute.call(stream, 3, pan.to_f/50.0-1.0)
                                                                                                                                                                                                      Bass::BASS_ChannelPlay.call(stream, 0)
                        end
                      end
                        
                      # The keyboard related functions
    def key_pressed?(key, repeat: false)
      ensure_keyboard_state
      return alt_pressed? if [:key_alt, :alt].include?(key)
      return context_menu_pressed? if [:key_context_menu, :context_menu, :context_menu_key].include?(key)
      return enter_pressed? if [:key_enter, :enter].include?(key)
      code, shift = keyboard_code(key)
      return false if code == 0
      return false if shift && !key_held?(0x10)
      EltenAPI::KeyboardState.pressed?(code)
    end

    def arrow_pressed?(code, repeat=false)
      return false if key_held?(0x5B) || key_held?(0x5C)
      EltenAPI::KeyboardState.pressed?(code)
    end

    def key_held?(key)
      ensure_keyboard_state
      code, shift = keyboard_code(key)
      return false if code == 0
      return false if shift && !key_held?(0x10)
      return true if EltenWindow.keyboard_key_held?(code)
      EltenAPI::KeyboardState.held?(code)
    end

    def key_released?(key)
      ensure_keyboard_state
      code, shift = keyboard_code(key)
      return false if code == 0
      return false if shift && !EltenAPI::KeyboardState.held?(0x10)
      EltenAPI::KeyboardState.released?(code)
    end

    def key_first_pressed?(key)
      ensure_keyboard_state
      code, shift = keyboard_code(key)
      return false if code == 0
      return false if shift && !EltenAPI::KeyboardState.held?(0x10)
      EltenAPI::KeyboardState.first_pressed?(code)
    end

    def key_any_pressed?
      ensure_keyboard_state
      EltenAPI::KeyboardState.any_pressed?
    end

    def alt_pressed?
      if (@@altdowntime||0)<Time.now.to_f-1
      @@altdown||=false
      @@altdowntime=Time.now.to_f
      return false
      end
      @@altdown=true if key_first_pressed?(0x12)
      @@altdown=false if key_held?(0x11) || key_held?(0x5B) || key_held?(0x5C) || key_held?(0x10) || key_held?(0x09) || key_pressed?(0x09) || key_first_pressed?(0x09)
              l=key_released?(0x12)&&@@altdown
              @@altdowntime=0 if l
    return l
    end

    def context_menu_pressed?
      return false if key_held?(0x12) || key_released?(0x12) || key_first_pressed?(0x12)
      return false if key_held?(0x11) || key_held?(0x10) || key_held?(0x5B) || key_held?(0x5C)
      key_first_pressed?(0x5D)
    end
       
    def enter_pressed?
    return EltenAPI::KeyboardState.pressed?(0x0D)
    end

    def ensure_keyboard_state
      key_update if @keyboard_state_initialized != true
    end

    def keyboard_code(key)
      case key
      when :key_escape, :escape, :esc
        [0x1B, false]
      when :key_space, :space
        [0x20, false]
      when :key_enter, :enter, :key_return, :return
        [0x0D, false]
      when :key_left, :key_arrow_left, :arrow_left, :left
        [0x25, false]
      when :key_up, :key_arrow_up, :arrow_up, :up
        [0x26, false]
      when :key_right, :key_arrow_right, :arrow_right, :right
        [0x27, false]
      when :key_down, :key_arrow_down, :arrow_down, :down
        [0x28, false]
      when :key_shift, :shift
        [0x10, false]
      when :key_control, :control, :ctrl
        [0x11, false]
      when :key_alt, :alt
        [0x12, false]
      when :key_tab, :tab
        [0x09, false]
      when :key_delete, :delete, :del
        [0x2E, false]
      when :key_insert, :insert, :ins
        [0x2D, false]
      when Integer
        [key.to_i & 0xff, false]
      else
        keycode(key)
      end
    end
  
  # Updates the keyboard state
       def key_update
         $key_update_serial=($key_update_serial||0)+1
         @keyboard_state_initialized = true
      if !EltenWindow.keyboard_active?
        @@altdown=false
        @@altdowntime=0
        EltenAPI::KeyboardState.reset
        EltenWindow.take_character(true)
        return
      end
      if EltenWindow.activation_input_blocked?
        @@altdown=false
        @@altdowntime=0
        EltenAPI::KeyboardState.reset
        EltenWindow.take_character(true)
        return
      end
      keyboard_flags_driven = EltenWindow.keyboard_flags_driven?
      if keyboard_flags_driven
        flags = "\0" * 256
        EltenKeyboard.fill_flags(flags)
        events = keyboard_events_from_flags(flags)
        raw_state = EltenKeyboard.flags_state
      else
        events = EltenWindow.consume_key_events
        raw_state = if EltenWindow.keyboard_event_driven?
          EltenAPI::KeyboardState.current.state
        else
          EltenKeyboard.raw_state
        end
      end
tokeys=[]
if defined?(NVDA) && NVDA.check
  g=NVDA.getgestures
  g.each do |k|
        k=k.downcase
        if k=='kb(laptop):nvda+a' or k=='kb(desktop):nvda+downarrow'
          tokeys.push(0x2D,0x28)
          elsif k=='kb(laptop):nvda+l' or k=='kb(desktop):nvda+uparrow'
          tokeys.push(0x2D,0x26)
            end
  end
end
if $setkeys.is_a?(Array)
  tokeys+=$setkeys
  $setkeys=nil
  end
  pressed_implies_held = EltenWindow.keyboard_pressed_implies_held?
  EltenAPI::KeyboardState.update(raw_state: raw_state, events: events, synthetic_keys: tokeys, pressed_implies_held: pressed_implies_held)
        end                      

        def keyboard_events_from_flags(flags)
          flags = flags.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
          events = []
          (0...256).each do |key|
            flag = flags.getbyte(key).to_i
            if (flag & 1) != 0
              events << [key, ((flag & 4) != 0 ? :repeat : true)]
            end
            if (flag & 2) != 0
              events << [key, false]
            elsif (flag & 4) != 0
              events << [key, :held]
            end
          end
          events
        rescue Exception
          []
        end
        
        def keycode(l)
          if !l.is_a?(Symbol)
          return([0, false]) if l.chrsize>1
          return([l.upcase.getbyte(0), l!=l.downcase]) if (/\w|\d/=~l)
        end
        if l.to_s.size==1
          k=l.to_s
          return([k.upcase.getbyte(0), k!=k.downcase]) if (/\w|\d/=~k)
          end
        shf=false
        if (s=l.to_s).size>5 && s[0..5].downcase=="shift_"
          l=s[6..-1].to_sym
          shf=true
          end
          mappings = {
          :esc => 0x1b,
          :space=>0x20,
          :ins=>0x2d,
          :del=>0x2e,
          :enter=>0xd,
          ";"=>0xba,
          ":"=>-0xba,
          "="=>0xbb,
          "+"=>-0xbb,
          ","=>0xbc,
          "<"=>-0xbc,
          "-"=>0xbd,
          "_"=>-0xbd,
          "."=>0xbe,
          ">"=>-0xbe,
          "/"=>0xbf,
          "?"=>-0xbf,
          "["=>0xdb,
          "{"=>-0xdb,
          "\\"=>0xdc,
          "|"=>-0xdc,
          "]"=>0xdd,
          "}"=>-0xdd,
          }
          if mappings[l]!=nil
            return([mappings[l].abs, mappings[l]<0||shf])
            end
            return ([0, false])
          end

                    def clear_keyboard_input_state
                      EltenAPI::KeyboardState.reset
                      @keyboard_state_initialized = false
                      $getkeychar_cache_serial = nil
                      $getkeychar_cache = nil
                      EltenWindow.clear_input_state
                    end

                    def run_window_action(wait=false, &block)
                      EltenWindow.post_window_action(wait, &block)
                    end

                    def alarm_sound_start
                      alarm_sound_stop
                      sound = getsound("alarm")
                      file = sound == nil ? "alarm" : nil
                      return if sound == nil && !FileTest.exists?(file)
                      $alarmplayer = Sound.new(file, loop: true, stream: sound)
                      if $alarmplayer != nil
                        $alarmplayer.volume = Configuration.volume.to_f / 100.0
                        $alarmplayer.play
                      end
                    rescue Exception => e
                      Log.error("Alarm sound: #{e.class}: #{e.message}")
                      play_sound("alarm", volume: 100, pitch: 100, pan: 50, ignore_soundtheme: true) rescue nil
                    end

                    def alarm_sound_stop
                      if $alarmplayer != nil
                        $alarmplayer.close rescue nil
                        $alarmplayer = nil
                      end
                    end
                    
    def keyprocs
                  if $windowminimized != true
                  if key_first_pressed?(0x11)
                    speech_stop(false)
                    $speech_wait = false
                  end
                  if key_held?(0x11) && key_held?(0x12) && key_held?(0x10) && key_first_pressed?(80)
                    insert_scene(Scene_Piano.new)
                    end
                  main_menu_opened = false
                  if !GlobalMenu.opened? && key_pressed?(:key_alt)
                   main_menu_opened = true
                   GlobalMenu.show
                 end
                 if !main_menu_opened && !GlobalMenu.opened? && key_pressed?(:key_context_menu)
                   GlobalMenu.show(false)
                 elsif !main_menu_opened && $opencontextmenu==true && !GlobalMenu.opened?
                   suc=false
                   ($activecontrols||[]).each{|ac|
                   suc=true if ac.hascontext
                   }
                   if suc
                                          $opencontextmenu=false
                     GlobalMenu.show(false)
                   else
                     $opencontextmenucounter+=1
                     $opencontextmenu=false if $opencontextmenucounter>=10
                   end
                 elsif !main_menu_opened && $opencontextmenu==0
                   $opencontextmenucounter=0
                    end
  if key_first_pressed?(0x7B)
    if $resetting!=true
      $resetting=true
    confirm(p_("EAPI_UI", "Do you want to restart Elten?")) {$reset=true}
    $resetting=false
    end
  end
  ac=QuickActions.get
  (1..11).each do |i|
    k=0x6F+i
    if key_first_pressed?(k) && !key_held?(0x12)
      l=i
      l+=12 if key_held?(0x11)
      l*=-1 if key_held?(0x10)
            ac.each do |a|
        a.call if a.key==l
        end
      end
    end
  end
  if !key_held?(0x12) && key_any_pressed?
    if key_any_pressed?
    t=GlobalMenu.ctitems
t.each do |m|
  l=m[3]
  k, shift = keycode(l)
  if key_first_pressed?(k) && key_held?(0x10)==shift && ((key_held?(0x11) && !l.is_a?(Symbol)) || (l.is_a?(Symbol) && !key_held?(0x11))) && m[1].is_a?(Proc)
    m[1].call(m[2])
    loop_update(false)
    end
  end
  end
  end
end

class CallWindow
      attr_reader :id, :caller, :channel, :password
      def initialize(id, caller, channel, password)
        @id, @caller, @channel, @password = id, caller, channel, password
        @form = Form.new([
        @st_caller = Static.new(p_("EAPI_UI", "%{user} is calling you")%{:user=>@caller}),
        @btn_answer = Button.new(p_("EAPI_UI", "Answer")),
        @btn_reject = Button.new(p_("EAPI_UI", "Reject"))
        ])
      end
      def update
        @form.update
          cancel if @btn_reject.pressed?
          if @btn_answer.pressed?
            cancel
            voicecall(@channel, @password)
            end
        end
        def cancel
          EltenAPI::EltenSRV.cancel_call(@id, self)
          end
      end
           
      class MissedCallsWindow
      def initialize(callers=[])
        @callers=callers
        @form = Form.new([
        @lst_callers = ListBox.new(@callers, header: p_("EAPI_UI", "Unanswered calls")),
        @btn_callback = Button.new(p_("EAPI_UI", "Call back")),
        @btn_close = Button.new(p_("EAPI_UI", "Close"))
        ])
@form.cancel_button = @btn_close
@btn_callback.on(:press) {
caller=@callers[@lst_callers.index]
if caller!=nil
ui=userinfo(caller)
if ui!=-1
  callable=ui[12].to_b
  if callable
    voicecall(nil, nil, [caller])
        close
      else
        alert(p_("EAPI_UI", "You cannot call this user"))
    end
  end
  end
}
@btn_close.on(:press) {close}
end
def close
  clear_callers
end
def active
  @callers.size>0
  end
def update
  @form.update
end
def add_caller(caller)
  @callers.push(caller)
  update_list
  focus if @callers.size==1
end
def clear_callers
  @callers=[]
  update_list
end
def update_list
  @lst_callers.options=@callers
end
def focus
  @form.focus
  end
      end

def update_window_tray_visibility
  return if !tray_supported?
  if $tray_restore_ignore_until != nil
    if Time.now.to_f < $tray_restore_ignore_until.to_f
      EltenWindow.consume_minimize_request
      return
    end
    $tray_restore_ignore_until = nil
  end
  minimize_requested = EltenWindow.consume_minimize_request
  return if (Configuration.hidewindow || 0).to_i != 1
  return if $trayreturn == true || $window_hidden_to_tray == true
  return if minimize_requested != true && !EltenWindow.minimized?
  Log.info("Elten window minimized")
  play_sound("minimize") rescue nil
  $totray = true
rescue Exception => e
  Log.error("Elten window auto-hide failed: #{e.class}: #{e.message}")end

def loop_update_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
rescue Exception
  Time.now.to_f
end

def loop_update_due?(key, interval, now=nil)
  now ||= loop_update_time
  $loop_update_periodic ||= {}
  last = $loop_update_periodic[key]
  return false if last != nil && now.to_f - last.to_f < interval.to_f
  $loop_update_periodic[key] = now.to_f
  true
end

def loop_update_window
  EltenWindow.update_messages
  true
end

                    # Updates a window, speech api and keyboard state
                    @@call=nil
                    @@missedcalls_window=nil
     def loop_update(checkControls=true, responseCalls=true)
       if $reset==true
         if Thread::current!=$mainthread
           exit
         else
                      raise(Reset,"")
           end
       end
                     exit if $exitproc==true
              if $currentthread != nil && Thread::current != $currentthread
     l="main"
     l=($subthreads||[]).size if Thread::current!=$mainthread
          Log.info("Pausing thread #{l}")
          sc=$scene
    if Thread::current==$mainthread
      while $currentthread!=Thread::current && $exitproc!=true && $reset!=true
        EltenWindow.service_window_update
        sleep(0.005)
      end
    else
      sleep(0.1) while $currentthread!=Thread::current && $exitproc!=true && $reset!=true
    end
           exit if $exitproc==true
       if $reset==true
         if Thread::current!=$mainthread
           exit
         else
                      raise(Reset,"")
           end
       end
    Log.info("Thread resumed #{l}")
    $scene=sc
       end
       $input_frame_serial=($input_frame_serial||0)+1
       EltenAPI::Controls::ListBox.tick_audio_players if defined?(EltenAPI::Controls::ListBox)
       $getkeychar_cache_serial=nil
       $getkeychar_cache=nil
       EltenWindow.begin_input_frame
        if $exitupdate==true
       $scene=nil
       speech_stop
       end
       tr = false
       if $trayreturn==true
         source = ($trayreturn_source != nil && $trayreturn_source != "") ? $trayreturn_source : "unknown source"
         Log.info("Restored from tray: #{source}")
         tr=true
       end
       begin
         NotificationService.start
         NotificationService.drain_events.each do |d|
           if d['func']=="notif"
             if d['invisible'] != true
               $main_notifications_changed = true
               Session.notifications_update
             end
             if $notifications_callback!=nil
               $notifications_callback.call(d)
             else
               process_notification(d)
             end
           elsif d['func']=='msg'
             $notification_msg_count=d['msgs'].to_i
            elsif d['func']=='sig'
              play_sound('right')
              if $scene.class.ancestors.include?(Program) and d['appid'].to_s == $scene.class.app_uuid.to_s
                begin
                  $scene.signaled(d['sender'], JSON.parse(d['packet'].to_s))
                rescue JSON::ParserError
                  Log.warning("Invalid app signal packet for #{d['appid']} from #{d['sender']}")
                end
              end
            elsif d['func']=='call_start'
             if $bgplayer!=nil
               $bgplayer.close
               $bgplayer=nil
             end
             play_sound(d['ringtone'] || 'ringing')
             @@call = CallWindow.new(d['call_id'], d['caller'], d['channel'], d['password']) if @@call==nil || @@call.id!=d['call_id']
           elsif d['func']=='call_stop'
             if $bgplayer!=nil
               $bgplayer.close
               $bgplayer=nil
             end
             @@call=nil
             $focus=true
           elsif d['func']=='missed_call'
             if d['caller']!=nil
               @@missedcalls_window ||= MissedCallsWindow.new
               @@missedcalls_window.add_caller(d['caller'])
             end
           elsif d['func']=='premiumpackages'
             update_premiumpackages(d['premiumpackages'].to_s.split(","))
           elsif d['func']=="feeds"
             changed_feeds = d['changed'].is_a?(String) ? JSON.parse(d['changed']) : Array(d['changed'])
             changed_feeds.each do |f|
               feed = FeedMessage.new(f['id'], f['user'], f['time'], f['message'], f['response'], f['responses'], f['liked'], f['likes'])
               Session.feeds[feed.id]=feed
             end
             Session.feeds_update
           elsif d['func']=="notifications"
             $main_notifications_changed = true
             Session.notifications_update
           elsif d['func']=='auctions'
             if d['auctions']==true and Configuration.language=="pl-PL"
               Scene_Main.register_specialaction("auctions", "Uwaga! Trwa licytacja charytatywna na rzecz projektu EltenLink") {insert_scene(Scene_Auctions.new)}
             else
               Scene_Main.unregister_specialaction("auctions")
             end
           else
             Log.warning("Notification service unknown data: #{d.inspect}")
           end
         end
         rescue Exception
           Log.error("Notification service UI drain: #{$!.class}: #{$!.message}")
         end
       loop_now = loop_update_time
       if loop_update_due?(:alarms, PERIODIC_SLOW_SECONDS, loop_now)
         Alarms.update
       end
       if loop_update_due?(:clock, PERIODIC_SLOW_SECONDS, loop_now)
         if (clock_event = Clock.update) != nil
           play_sound("clock") if clock_event[0]
           speak(clock_event[1]) if clock_event[1] != nil
         end
       end
       EltenAPI::Conference.tick
       EltenAPI::InvisibleInterface.tick
       if $scene != nil && loop_update_due?(:activity_reports, PERIODIC_SLOW_SECONDS, loop_now)
         $loop_update_activity_last ||= loop_now
         activity_delta = loop_now.to_f - $loop_update_activity_last.to_f
         $loop_update_activity_last = loop_now
         ActivityReports.track($scene.class.name, activity_delta) if activity_delta > 0
       end
        loop_update_window
        sleep(TICK_SECONDS)
      update_window_tray_visibility if loop_update_due?(:window_tray_visibility, PERIODIC_FAST_SECONDS, loop_now)
      raise SystemExit if EltenWindow.consume_close_request
                              Input.update
      key_update
      EltenTray.restore_hotkey_pressed? if tray_supported? && defined?(EltenTray) && loop_update_due?(:tray_restore_hotkey, PERIODIC_FAST_SECONDS, loop_now)
      if key_held?(0x10) && key_held?(0x11)
        $errcou||=0
        $errcou+=1 if key_released?(0x2E)
      if $errcou==3
                  c=4
                  while c==4
          errors=[
          ["Error #123", "Failed to show error #123."],
          ["This computer is hungry!", "Please place the hamburger in the hard-drive slot."],
                    ["Error #404", "The error you are looking for was not found."],
          ["Matrix Breach Detected", "Neo is currently unavailable, please try again later."],
          ["Unstable Quantum State", "Elten is now both crashed and not crashed."],
          ["Unexpected Success", "The operation completed successfully.\nThis is highly suspicious."],
          ["Existential Error", "Your computer is questioning its purpose.\nPlease reassure it."],
          ["RAM Daydreaming", "Memory is temporarily imagining things. Try again later."],
          ["Parallel Universe Mismatch", "Elten ran successfully in a different universe."],
          ["Critical Tea Shortage", "Operation aborted until tea levels are restored."],
          ["Suspicious Silence", "No errors found.\nThis can't be right."],
          ["Window Open Error", "Attempt to open a window resulted in actual glass breaking."],
["Error #Ď€", "System froze at digit 3.\nIt refuses to continue irrational numbers."],
["Paradox Detected", "This error message has not been written yet.\nPlease read it when it exists."],
["Recursive Complaint", "This message is complaining about this message complaining about this message..."],
["Forbidden Knowledge Access", "You are not allowed to know what went wrong.\nStop asking."],
["Error #undefined", "Even the system has no idea what this is."],
["404: Code Not Found", "This function went out for coffee and never came back."],
["The Force Was Not With You", "Check midichlorian drivers."],
["Jedi Mind Trick Failed", "These are, unfortunately, the bugs you are looking for."],
["Entish Processing", "This operation may take a looooong time."],
["Silver Sword Required", "Process terminated due to monster interference."],
["RubberDuckNotFound", "Debugging halted.\nPlease attach a certified rubber duck."],
["KeyboardBufferOverflow", "User typed faster than humanly possible.\nSuspect: cat."],
["Thread Scheduler Panic", "Ruby threads running.\nProbably. Maybe. Hard to tell."],
["Implicit Return Confusion", "Code returned the last value.\nElten didn't mean THAT last value."],
["Bitwise Romance Error", "Elten tried to OR a bit that wanted to AND."],
["Compiler Sadness", "It compiled.\nIt ran.\nIt failed anyway."],
["Existential Error", "Program paused to ask why it should continue at all."],
["Elten PTSD", "It has seen things.\nTerrible things."],
["Coffee Overflow", "System jitter levels critical. Reduce caffeine immediately."],
["Universal Constant Modified", "Pi now equals 3. Please update mathematics."],
["Error #YOLO", "System attempted operation without considering consequences."],
["Emotional Support Required", "System is sad and needs a compliment."],
["error", "Artificial Stupidity Enabled"],
["Broken Fourth Wall", "This error knows you are reading it."],
["Philosophical Segmentation Fault", "Cogito ergo crash."],
["Boredom Overflow", "The CPU refuses to continue until something interesting happens."],
["Error #NaN", "System tried to divide by a sandwich."],
["Duck Typing Failure", "Object does not quack like a duck."],
["Procrastination Mode Enabled", "The task will start.\nEventually."],
["Error #2.71828", "The system encountered an irrational sense of growth."],
["+++ Divide By Cucumber Error +++", "Reinstall Universe And Reboot."],
]
          while errors.size>0
            r=rand(errors.size)
            error=errors[r]        
            errors.delete_at(r)
            begin
            c=EltenWindow.message_box(error[1], error[0], 5|0x10, $wnd)
          loop_update_window
          rescue Exception
          end
          break if c!=4
          end
        end
        key_update
        key_update
      end
    elsif $errcou!=nil
      $errcou=nil
          end
if (seq=current_speechsequence)!=nil
ind, indid = speech_getindex  
if seq.id==indid
  seq.execute(ind)
  end
  end
      if $totray==true
        $totray=false
  if tray_supported?
  clear_keyboard_input_state
  run_window_action(true) {
      EltenWindow.hide_to_tray
  }
  $window_hidden_to_tray = true
  clear_keyboard_input_state
  end
        end
if tr == true
  $trayreturn=false
  $trayreturn_source=nil
  $window_hidden_to_tray = false
  $tray_restore_ignore_until = Time.now.to_f + 1.0
      clear_keyboard_input_state
        delay(0.5)
        run_window_action(true) {
            EltenWindow.restore_from_tray
        }
        $tray_restore_ignore_until = Time.now.to_f + 1.0
        clear_keyboard_input_state
        play_sound("login")
  speak("ELTEN")
  end
if $agalarm==true and $alarmproc!=true
  $alarmproc=true
  alarm_sound_start
  play_sound("dialog_open")
  al=p_("EAPI_UI", "Alarm")
  al=$agalarmdescription if $agalarmdescription!=nil
  alert(al)
  t=Time.now.to_f
    until key_pressed?(:key_escape) or key_pressed?(:key_enter) or key_pressed?(:key_space)
      loop_update
      if Time.now.to_f-t>5
        speak(al)
        t=Time.now.to_f
        end
    end
          $agalarm=false
          $agalarmdescription=nil
      alarm_sound_stop
    play_sound("dialog_close")
    loop_update
    $alarmproc=false
  end
  if @@call!=nil
  @@call.update
  EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
      $focus=false
    elsif @@missedcalls_window!=nil && @@missedcalls_window.active==true
@@missedcalls_window.update
  EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
      $focus=(@@missedcalls_window.active==false)
    end
          keyprocs
  if checkControls
  $activecontrols||=[]
  $lastactivecontrols||=[]
  $lastactivecontrols.each do |c|
    c.blur if !$activecontrols.include?(c)
  end
  $lastactivecontrols=$activecontrols.dup
  $activecontrols.clear
  end
  rescue Reset=>r
    if $reset==true
    $reset=false
    fail Reset
  end
rescue Hangup
  rescue Interrupt
  end
  
  def get_tips
    tips=[]
if $activecontrols!=nil
    $activecontrols.each{|ac|
    t=ac.get_tips
    tips+=t if t.is_a?(Array)
    }
    end
    return tips
    end
  
  # Creates a simple dialog with options yes and no and returns the user's decision
#
# @param text [String] a question to ask
# @return [Boolean] returns true if user selected yes, otherwise false.
def confirm(text="")
  text.gsub!("jesteĹ› pewien","jesteĹ› pewna") if Configuration.language=="pl-PL" and Session.gender==0
  dialog_open  
  sel = ListBox.new([_("No"),_("Yes")],header: text,index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
    loop do
        loop_update
        sel.update
        if key_pressed?(:key_escape)
          loop_update
          dialog_close  
          return false
    end
        if key_pressed?(:key_enter)
      loop_update
      dialog_close
      if sel.options.size==2      
        yield if sel.index==1 and block_given?
      return sel.index==1
    else
 if sel.index<=5
   return false
 elsif sel.index <= 9
   yield if block_given?
   return true
 else
   result=rand(2)==1
   yield if result && block_given?
   return result
   end
      end
      end
if key_held?(0x10) and key_held?(84) and key_held?(78)
  sel = ListBox.new(["Hmmmm, nie, podziÄ™kujÄ™","CoĹ› ty, oszalaĹ‚eĹ›?","Nie ma mowy","Nigdy w ĹĽyciu","PogiÄ™Ĺ‚o ciÄ™? Jasne, ĹĽe nie","Chyba masz jakieĹ› zwidy jeĹ›li sÄ…dzisz, ĹĽe siÄ™ zgodzÄ™","W sumie, czemu nie","HMMM, kusi, pomyĹ›lmy, no ok, zgoda","Jasne, genialny pomysĹ‚","Jestem za","A ty zdecyduj"],header: "MoĹĽesz siÄ™ szybciej decydowaÄ‡? "+text,index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
  end
      end
    end
    
    def prompt(header="",confirmation="Ok",cancellation=_("Cancel"))
      form=Form.new([EditBox.new(header,type: EditBox::Flags::MultiLine),Button.new(confirmation),Button.new(cancellation)])
      snd=form.fields[1]
      dialog_open
      loop do
loop_update
if form.fields[0].text=="" and form.fields[1]!=nil
  form.fields[1]=nil
elsif form.fields[0].text!="" and form.fields[1]==nil
  form.fields[1]=snd
  end
        form.update
        if (((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index==1) or (key_pressed?(:key_enter) and key_held?(0x11) and form.index==0)) and form.fields[0].text!=""
          dialog_close
          return legacy_line_to_text(form.fields[0].text)
          break
        end
        if ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index==2) or key_pressed?(:key_escape)
          dialog_close
          return ""
          break
          end
        end
      end
      
      @@waitingvoice=nil
      @@waitingopened=false
      
      def waiting_opened
        @@waitingopened 
        end
    
    # Opens a waiting dialog
  def waiting(&b)
    snd=getsound("waiting")
    waiting_end if @@waitingvoice!=nil
          if snd!=nil
                          @@waitingvoice = Sound.new(loop: true, stream: snd)
                          @@waitingvoice.volume = Configuration.volume.to_f/150.0
                          @@waitingvoice.play
                          end
                            @@waitingopened = true
                                                      if b!=nil
                            b.call
                            waiting_end
                            end
end

# Closes a waiting dialog
def waiting_end
    if @@waitingvoice != nil
      @@waitingvoice.close
    @@waitingvoice = nil
    end
    @@waitingopened = false
  end
  
  @@dialogvoice=nil
  @@dialogopened=false
  
  def dialog_opened
    return @@dialogopened
    end
  
  def dialog_mute
    @@dialogvoice.volume=0 if @@dialogvoice!=nil
    end

      # Opens a dialog
  def dialog_open
            play_sound("dialog_open")
            dialog_close if @@dialogvoice!=nil
        if Configuration.bgsounds==1 && Configuration.soundthemeactivation==1
          snd=getsound("dialog_background")
          if snd!=nil
                          @@dialogvoice_generation ||= 0
                          generation = (@@dialogvoice_generation += 1)
                          Thread.new do
                            Thread.current.report_on_exception = false
                            begin
                              sound = Sound.new(loop: true, stream: snd)
                              sound.volume=Configuration.volume.to_f/100.0
                              sound.position=0
                              if @@dialogvoice_generation == generation
                                @@dialogvoice = sound
                                @@dialogvoice.play
                              else
                                sound.close
                              end
                            rescue Exception => e
                              Log.warning("Dialog background sound failed: #{e.class}: #{e.message}")
                            end
                          end
                                                  end
                                                  end
  @@dialogopened = true
end

# Closes a dialog
def dialog_close
    @@dialogvoice_generation ||= 0
    @@dialogvoice_generation += 1
    if @@dialogvoice != nil
    @@dialogvoice.close
    @@dialogvoice=nil
  end
  play_sound("dialog_close")
  NVDA.braille("") if defined?(NVDA) && NVDA.check
  @@dialogopened=false
  end
   class ConfigEntry
     attr_accessor :id, :name, :value_type, :current_value
     end

     end
     include UI
end
