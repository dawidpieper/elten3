# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Object
  include EltenAPI
  end

module Elten
VERSION_STRING="ELTEN 3.0 BETA 18"
BRANCH="beta"
class <<self
  def version
  return VERSION_STRING
end
def build_id
  return nil if !const_defined?(:BuildID,false)
  return const_get(:BuildID)
end
def build_date
  return nil if !const_defined?(:BuildDate,false) || const_get(:BuildDate)==nil
  t=Time.at(const_get(:BuildDate))
  return sprintf("%04d-%02d-%02d %02d:%02d",t.year,t.month,t.day,t.hour,t.min)
rescue Exception
  nil
end
def branch
  return BRANCH
  end
end
end

def mac_quit_shortcut_request
  EltenWindow.consume_quit_shortcut_request
rescue Exception
  false
end

begin
Dirs.eltendata = EltenBoot.early_datadir if defined?(EltenBoot)
FileUtils.mkdir_p(Dirs.eltendata)
end

begin
Log.head("Starting Elten")
Log.head("Elten version: #{Elten.version.to_s}")
Log.head("Ruby version: #{RUBY_DESCRIPTION.to_s}")
    loop_update_window
        Configuration.volume=50 if Configuration.volume==nil
      $mainthread = Thread::current
      $currentthread=$mainthread
  $LOAD_PATH << "."
end
  begin
  #main
  # Make scene object (title screen)
    if $toscene != true
    $scene = Scene_Loading.new if $tomain == nil and $updating != true and $downloading != true
  $scene = Scene_Main.new if $tomain == true
  $scene = Scene_Update.new if $updating == true
  $scene = $scene if $downloading == true
end
$toscene = false
  # Call main method as long as $scene is effective
  loop do
  $scene=Scene_Loading.new if $restart==true
          if $scene != nil and $exit!=true
        $notifications_callback = nil
        Log.debug("Loading scene: #{$scene.class.to_s}")
                              $scene.main
  else
    break
    end
  end
  if $immediateexit!=true
      register_activity(wait: true, final: true)
      if defined?(Session) && Session.logged? && Session.name.to_s != "guest"
        begin
          EltenLink::System.logout_session(EltenLink.client(nil))
          Log.info("Session token invalidated on shutdown")
        rescue Exception
          Log.warning("Session token invalidation failed on shutdown: #{$!.class}: #{$!.message}") if defined?(Log)
        end
      end
      play_sound("logout")
    delay(1)
          speech_wait
              $exit = true
  if $exitupdate==true
    installer=platform_installer_path
    if $exitupdate_donotsilent!=true
    File.binwrite(EltenPath.join(Dirs.eltendata, "update.last"),Zlib::Deflate.deflate(Elten.version.to_s))
    $exit_runproc=platform_update_install_command(installer, silent: true)
  else
    $exit_runproc=platform_update_install_command(installer, silent: false)
    end
  end
  end
          rescue Hangup
  loop_update_window
  $toscene = true
  retry
rescue Reset
key_update
  $DEBUG=true if key_held?(0x10)
  play_sound("signal") if key_held?(0x10)
  retry
rescue SystemExit
  if $immediateexit!=true
  loop_update
  quit if key_held?(0x73) || mac_quit_shortcut_request
          play_sound("listbox_focus") if $exit==nil
  $toscene = true
    retry if $exit == nil
  end
rescue Exception
  Log.error($!.class.name+": "+$!.message+" - "+$@.to_s)
  Log.error("Critical exception occurred, terminating!")
  fail
            ensure
            if $immediateexit!=true
  ActivityReports.shutdown
  NVDA.join if defined?(NVDA)
  NVDA.destroy if defined?(NVDA)
    EltenAPI::InvisibleInterface.stop if defined?(EltenAPI::InvisibleInterface)
    Audio3DEffect.free if defined?(Audio3DEffect)
    EltenAPI::Conference.shutdown if defined?(EltenAPI::Conference)
    EltenLink.close if defined?(EltenLink)
    LocalConfig.save
    FileCache.get_caches.each{|a|a.save}
    Log.debug("Closing processes")
  if $procs!=nil  
  for o in $procs
terminate_process_handle(o)
    end
  end
  if $exitdonotclean!=true && Dirs.temp!=nil
  Log.info("Cleaning up temporary files")
  FileUtils.rm_rf(Dirs.temp)
  end
  Log.info("Exiting Elten")
    EltenTray.hide if defined?(EltenTray)
    if $exit_runproc!=nil
      Log.debug("Starting queued Processes")
      run($exit_runproc, false, $exit_runproc_path, false)
      exit_process(0)
      end
    end
    end;begin
  rescue Exception
  if $updating != true and $start != nil and $downloading != true
        speak("Critical error occurred: "+$!.message)
    speech_wait
    sleep(0.5)
    speak("Do you want to send the errror report?")
    speech_wait
    if selector(["No","Yes"])== 1
      sleep(0.15)
      bug
    end
sel = ListBox.new(["Copy error report to clipboard","Restart","Try again","Rescue mode","Abort"],header: "What to do?",index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
loop do
  loop_update
  sel.update
  if key_pressed?(:key_enter)
    if sel.index > 0
    break
  else
    msg = $!.to_s+"\r\n"+$@.to_s
    Clipboard.text=msg
    speak("Copied to clipboard")
    end
  end
  end
    case sel.index
    when 1
      $toscene = false
      retry
      when 2
        $toscene = true
        retry
    when 3
      speak("Rescue mode")
      speech_wait
      @sels = ["Quit", "Reinstall"]
      @sels += ["Try to open forum", "Try to open messages"] if Session.name != nil and Session.name != ""
      @sel = ListBox.new(@sels, header: "", index: 0, flags: ListBox::Flags::AnyDir, quiet: false)
      loop do
        loop_update
        @sel.update
        if key_pressed?(:key_enter)
          break
        end
      end
      case @sel.index
      when 0
              fail
        when 1
        $scene = Scene_Update.new
        $toscene = true
        retry
        when 2
          insert_scene($scene) if $scenes != nil
          $scene = Scene_Forum.new
                    $toscene = true
                    retry
          when 3
            insert_scene($scene) if $scenes != nil
            $scene = Scene_Messages.new
            $toscene = true      
            retry
      end
        when 4
    fail if $DEBUG == true
  end
  end
  if $updating == true
    retry
  end
  if $start == nil
    retry
  end
end
