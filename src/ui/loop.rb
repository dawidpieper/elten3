# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module UI
    private
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

def loop_update_tick_seconds
  foreground = true
  if defined?(EltenWindow)
    if EltenWindow.respond_to?(:active_or_child?)
      foreground = EltenWindow.active_or_child?
    elsif EltenWindow.respond_to?(:keyboard_active?)
      foreground = EltenWindow.keyboard_active?
    end
  end
  foreground ? TICK_SECONDS : TICK_BACKGROUND_SECONDS
rescue Exception
  TICK_SECONDS
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
       Programs::Extensions.tick if defined?(Programs::Extensions) && Thread::current == $mainthread
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
              call_sound_start(d['ringtone'] || 'ringing')
              @@call = CallWindow.new(d['call_id'], d['caller'], d['channel'], d['password']) if @@call==nil || @@call.id!=d['call_id']
           elsif d['func']=='call_stop'
              call_sound_stop
              missed_call = @@call if @@call != nil && @@call.id == d['call_id'] && !@@call.handled?
              @@call=nil
              if missed_call != nil && missed_call.caller != nil
                @@missedcalls_window ||= MissedCallsWindow.new
                @@missedcalls_window.add_caller(missed_call.caller)
              end
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
             for f in changed_feeds
               feed = FeedMessage.new(f['id'], f['user'], f['time'], f['message'], f['response'], f['responses'], f['liked'], f['likes'], f['audio_url'])
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
       Bass.cleanup_memory_streams if defined?(Bass) && loop_update_due?(:bass_memory_streams, PERIODIC_SLOW_SECONDS, loop_now)
       if loop_update_due?(:alarms, PERIODIC_SLOW_SECONDS, loop_now)
         Alarms.update
       end
       if loop_update_due?(:clock, PERIODIC_SLOW_SECONDS, loop_now)
         if (clock_event = Clock.update) != nil
           play_sound("clock") if clock_event[0]
           speak(clock_event[1], stop: false, break_sequence: false) if clock_event[1] != nil
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
        sleep(loop_update_tick_seconds)
      update_window_tray_visibility if loop_update_due?(:window_tray_visibility, PERIODIC_FAST_SECONDS, loop_now)
      raise SystemExit if EltenWindow.consume_close_request
      key_update
      EltenTray.restore_hotkey_pressed? if tray_supported? && defined?(EltenTray) && loop_update_due?(:tray_restore_hotkey, PERIODIC_FAST_SECONDS, loop_now)
      if raw_key_held?(:key_shift) && modifier_held?(:control)
        $errcou||=0
        $errcou+=1 if key_released?(0x2E)
      if $errcou==3
                  c=4
                  while c==4
          errors=[
            [p_("EAPI_UI", "Error #123"), p_("EAPI_UI", "Failed to show error #123.")],
            [p_("EAPI_UI", "This computer is hungry!"), p_("EAPI_UI", "Please place the hamburger in the hard-drive slot.")],
            [p_("EAPI_UI", "Error #404"), p_("EAPI_UI", "The error you are looking for was not found.")],
            [p_("EAPI_UI", "Matrix Breach Detected"), p_("EAPI_UI", "Neo is currently unavailable, please try again later.")],
            [p_("EAPI_UI", "Unstable Quantum State"), p_("EAPI_UI", "Elten is now both crashed and not crashed.")],
            [p_("EAPI_UI", "Unexpected Success"), p_("EAPI_UI", "The operation completed successfully.\nThis is highly suspicious.")],
            [p_("EAPI_UI", "Existential Error"), p_("EAPI_UI", "Your computer is questioning its purpose.\nPlease reassure it.")],
            [p_("EAPI_UI", "RAM Daydreaming"), p_("EAPI_UI", "Memory is temporarily imagining things. Try again later.")],
            [p_("EAPI_UI", "Parallel Universe Mismatch"), p_("EAPI_UI", "Elten ran successfully in a different universe.")],
            [p_("EAPI_UI", "Critical Tea Shortage"), p_("EAPI_UI", "Operation aborted until tea levels are restored.")],
            [p_("EAPI_UI", "Suspicious Silence"), p_("EAPI_UI", "No errors found.\nThis can't be right.")],
            [p_("EAPI_UI", "Window Open Error"), p_("EAPI_UI", "Attempt to open a window resulted in actual glass breaking.")],
            [p_("EAPI_UI", "Error #π"), p_("EAPI_UI", "System froze at digit 3.\nIt refuses to continue irrational numbers.")],
            [p_("EAPI_UI", "Paradox Detected"), p_("EAPI_UI", "This error message has not been written yet.\nPlease read it when it exists.")],
            [p_("EAPI_UI", "Recursive Complaint"), p_("EAPI_UI", "This message is complaining about this message complaining about this message...")],
            [p_("EAPI_UI", "Forbidden Knowledge Access"), p_("EAPI_UI", "You are not allowed to know what went wrong.\nStop asking.")],
            [p_("EAPI_UI", "Error #undefined"), p_("EAPI_UI", "Even the system has no idea what this is.")],
            [p_("EAPI_UI", "404: Code Not Found"), p_("EAPI_UI", "This function went out for coffee and never came back.")],
            [p_("EAPI_UI", "The Force Was Not With You"), p_("EAPI_UI", "Check midichlorian drivers.")],
            [p_("EAPI_UI", "Jedi Mind Trick Failed"), p_("EAPI_UI", "These are, unfortunately, the bugs you are looking for.")],
            [p_("EAPI_UI", "Entish Processing"), p_("EAPI_UI", "This operation may take a looooong time.")],
            [p_("EAPI_UI", "Silver Sword Required"), p_("EAPI_UI", "Process terminated due to monster interference.")],
            [p_("EAPI_UI", "RubberDuckNotFound"), p_("EAPI_UI", "Debugging halted.\nPlease attach a certified rubber duck.")],
            [p_("EAPI_UI", "KeyboardBufferOverflow"), p_("EAPI_UI", "User typed faster than humanly possible.\nSuspect: cat.")],
            [p_("EAPI_UI", "Thread Scheduler Panic"), p_("EAPI_UI", "Ruby threads running.\nProbably. Maybe. Hard to tell.")],
            [p_("EAPI_UI", "Implicit Return Confusion"), p_("EAPI_UI", "Code returned the last value.\nElten didn't mean THAT last value.")],
            [p_("EAPI_UI", "Bitwise Romance Error"), p_("EAPI_UI", "Elten tried to OR a bit that wanted to AND.")],
            [p_("EAPI_UI", "Compiler Sadness"), p_("EAPI_UI", "It compiled.\nIt ran.\nIt failed anyway.")],
            [p_("EAPI_UI", "Existential Error"), p_("EAPI_UI", "Program paused to ask why it should continue at all.")],
            [p_("EAPI_UI", "Elten PTSD"), p_("EAPI_UI", "It has seen things.\nTerrible things.")],
            [p_("EAPI_UI", "Coffee Overflow"), p_("EAPI_UI", "System jitter levels critical. Reduce caffeine immediately.")],
            [p_("EAPI_UI", "Universal Constant Modified"), p_("EAPI_UI", "Pi now equals 3. Please update mathematics.")],
            [p_("EAPI_UI", "Error #YOLO"), p_("EAPI_UI", "System attempted operation without considering consequences.")],
            [p_("EAPI_UI", "Emotional Support Required"), p_("EAPI_UI", "System is sad and needs a compliment.")],
            [p_("EAPI_UI", "error"), p_("EAPI_UI", "Artificial Stupidity Enabled")],
            [p_("EAPI_UI", "Broken Fourth Wall"), p_("EAPI_UI", "This error knows you are reading it.")],
            [p_("EAPI_UI", "Philosophical Segmentation Fault"), p_("EAPI_UI", "Cogito ergo crash.")],
            [p_("EAPI_UI", "Boredom Overflow"), p_("EAPI_UI", "The CPU refuses to continue until something interesting happens.")],
            [p_("EAPI_UI", "Error #NaN"), p_("EAPI_UI", "System tried to divide by a sandwich.")],
            [p_("EAPI_UI", "Duck Typing Failure"), p_("EAPI_UI", "Object does not quack like a duck.")],
            [p_("EAPI_UI", "Procrastination Mode Enabled"), p_("EAPI_UI", "The task will start.\nEventually.")],
            [p_("EAPI_UI", "Error #2.71828"), p_("EAPI_UI", "The system encountered an irrational sense of growth.")],
            [p_("EAPI_UI", "+++ Divide By Cucumber Error +++"), p_("EAPI_UI", "Reinstall Universe And Reboot.")],
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
        clear_keyboard_input_state(preserve_activation_guard: true)
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
  for c in $lastactivecontrols
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

  end
end
