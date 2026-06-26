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
             for f in changed_feeds
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
