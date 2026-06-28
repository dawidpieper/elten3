# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
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
      keyboard_event_driven = EltenWindow.keyboard_event_driven?
      if keyboard_flags_driven
        flags = "\0" * 256
        EltenKeyboard.fill_flags(flags)
        events = keyboard_events_from_flags(flags)
        raw_state = EltenKeyboard.flags_state
      else
        events = EltenWindow.consume_key_events
        raw_state = if keyboard_event_driven
          EltenAPI::KeyboardState.current.state
        else
          EltenKeyboard.raw_state
        end
      end
tokeys=[]
if defined?(NVDA) && NVDA.check
  g=NVDA.getgestures
  for k in g
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
  if !keyboard_flags_driven && keyboard_event_driven && events.empty? && tokeys.empty? && !EltenAPI::KeyboardState.any_held?
    EltenAPI::KeyboardState.clear_current_frame if !EltenAPI::KeyboardState.idle?
    return
  end
  pressed_implies_held = EltenWindow.keyboard_pressed_implies_held?
  EltenAPI::KeyboardState.update(raw_state: raw_state, events: events, synthetic_keys: tokeys, pressed_implies_held: pressed_implies_held)
        end

        def keyboard_events_from_flags(flags)
          flags = flags.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
          events = []
          for key in 0...256
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
      return if $windowminimized == true
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
      if !key_held?(0x12)
        ctrl_held = key_held?(0x11)
        shift_held = key_held?(0x10)
        for i in 1..11
          k=0x6F+i
          if key_first_pressed?(k)
            l=i
            l+=12 if ctrl_held
            l*=-1 if shift_held
            for a in QuickActions.hotkey_actions(l)
              a.call
            end
          end
        end
      end
      any_key_pressed = key_any_pressed?
      if !key_held?(0x12) && any_key_pressed
        t=GlobalMenu.ctitems
        for m in t
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
end
