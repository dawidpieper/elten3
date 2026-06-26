# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  module Common
    private
# EltenAPI common functions
    # Opens the quit menu
    #
    # @param header [String] a message to read, header of the menu
        def quit(header=p_("EAPI_Common", "Exit..."))
         dialog_open
            options = [_("Cancel")]
            options.push(p_("EAPI_Common", "Hide program in Tray")) if tray_supported?
            options.push(_("Exit"))
            sel = ListBox.new(options,header: header,index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
            sel.disable_menu
      loop do
        loop_update
        sel.update
        if key_held?(0x11) and key_pressed?(81)
sel.options=["Zabieraj mi to okno","Spadaj z mojego pulpitu","Mam ciebie dość, zamknij się","Zejdź mi z oczu"]
          sel.focus
          end
        if key_pressed?(:key_escape)
          sel.enable_menu
          dialog_close
loop_update
          break
            $exit = false
            return(false)
            end
        if key_pressed?(:key_enter)
          sel.enable_menu
          loop_update
          dialog_close
          if !tray_supported? && sel.index == options.size - 1
              $scene = nil
              break
          end
          case sel.index
          when 0
loop_update
            break
            $exit = false
            return(false)
            when 1
loop_update
              $exit = false
              tray
              return false
            when 2
              $scene = nil
              break
              $exit = true
              return(true)
                $exit = false
                return false
                when 3
                                  return quit("W zasadzie, jak mam zejść z oczu osobie niewidomej? Nie rozumiem. Proszę o doprecyzowanie.")
          end
          end
        end
      end

    class Console
      attr_reader :codes

      def initialize
        @b = binding
        @codes = []
        @hooks = []
      end

      def run(code)
        @codes.unshift(code)
        @codes.pop while @codes.size > 50
        return eval(code, @b, "Console")
      end

      def on_str(&h)
        @hooks.push(h) if h != nil
      end

      def puts(t)
        @hooks.each { |h| h.call(t.to_s) }
        return nil
      end
    end

    # Opens a console
    def console
      if !(defined?(developer_mode?) && developer_mode?)
        Log.warning("Console blocked outside developer mode")
        alert(p_("EAPI_Common", "Console is available only in developer mode.")) if respond_to?(:alert, true)
        return false
      end
      form = Form.new([
        EditBox.new(p_("EAPI_Common", "Enter the command to execute"), type: EditBox::Flags::MultiLine, text: "", quiet: true),
        EditBox.new(p_("EAPI_Common", "Output"), type: EditBox::Flags::ReadOnly, text: "", quiet: true),
        Button.new(p_("EAPI_Common", "Execute"))
      ])
      container = Console.new
      container.on_str { |str| form.fields[1].set_text(form.fields[1].text + "\r\n" + str) }
      form.bind_context { |menu|
        if LocalConfig['ConsoleAutoClearInput']==1
          s=p_("EAPI_Common", "Disable auto clear input")
        else
          s=p_("EAPI_Common", "Enable auto clear input")
        end
        menu.option(s, nil, "i") {
          if LocalConfig['ConsoleAutoClearInput']==1
            LocalConfig['ConsoleAutoClearInput']=0
            alert(p_("EAPI_Common", "Disabled"))
          else
            LocalConfig['ConsoleAutoClearInput']=1
            alert(p_("EAPI_Common", "Enabled"))
          end
        }
        if LocalConfig['ConsoleAutoClearOutput']==1
          s=p_("EAPI_Common", "Disable auto clear output")
        else
          s=p_("EAPI_Common", "Enable auto clear output")
        end
        menu.option(s, nil, "o") {
          if LocalConfig['ConsoleAutoClearOutput']==1
            LocalConfig['ConsoleAutoClearOutput']=0
            alert(p_("EAPI_Common", "Disabled"))
          else
            LocalConfig['ConsoleAutoClearOutput']=1
            alert(p_("EAPI_Common", "Enabled"))
          end
        }
        #By default, source should be copied to output.
        if LocalConfig['ConsoleDontCopySource']==1 
          s=p_("EAPI_Common", "Enable source in output")
        else
          s=p_("EAPI_Common", "Disable source in output")
        end
        menu.option(s, nil, "s") {
          if LocalConfig['ConsoleDontCopySource']==1
            LocalConfig['ConsoleDontCopySource']=0
            alert(p_("EAPI_Common", "Enabled"))
          else
            LocalConfig['ConsoleDontCopySource']=1
            alert(p_("EAPI_Common", "Disabled"))
          end
        }
        if container.codes.size > 0
          menu.option(p_("EAPI_Common", "Load last code"), nil, "l") {
            form.fields[0].set_text(container.codes[0])
            form.focus
          }
          menu.submenu(p_("EAPI_Common", "Last codes")) { |m|
            container.codes.each do |c|
              menu.option(c[0...100], c) { |c|
                form.fields[0].set_text(c)
                form.focus
              }
            end
          }
        end
      }
      loop do
        loop_update
        form.update
        if form.fields[2].pressed? or (key_held?(0x11) and key_pressed?(:key_enter))
          kom = form.fields[0].text
          if LocalConfig['ConsoleDontCopySource']==1
            outKom=""
          else
            outKom=kom
          end
          if LocalConfig['ConsoleAutoClearOutput']==1
            form.fields[1].set_text(outKom)
          else
            form.fields[1].set_text(form.fields[1].text + "\r\n\r\n" + outKom)
          end
          begin
            r = container.run(kom).inspect
          rescue Exception
            plc = ""
            if $@.is_a?(Array)
              $@.each do |e|
                if e != nil
                  plc += e + "\n" if e != nil and e[0..6] != "Section"
                end
              end
              lin = $@[0].split(":")[1].to_i
              plc += kom.delete("\r").split("\n")[lin - 1] || ""
            end
            r = $!.class.to_s + " (" + $!.to_s + ")\n" + plc
          end
          speak(r)
          form.fields[0].set_text("") if LocalConfig['ConsoleAutoClearInput']==1
          form.fields[1].set_text(form.fields[1].text + "\r\n#=> " + r, false)
          loop_update
        end
        if key_pressed?(:key_escape)
          if form.fields[0].text=="" || confirm(p_("EAPI_Common", "Are you sure you want to exit console?"))
            break
            end
          end
      end
    end

# Opens a menu of a specified user
#
# @param user name of the user whose menu you want to open
# @param submenu [Boolean] specifies if the menu is a submenu
# @return [String] returns ALT if menu was closed using an alt menu
    def usermenu(user,submenu=false, left=false)
      ui=userinfo(user, true)
      return if ui==-1
      if ui[15]==true
        alert(p_("EAPI_Common", "This account is archived"))
        return
        end
            @incontacts = ui[8].to_b if Session.name!="guest"      
@isbanned = ui[10].to_b
      @hasblog = ui[1]
    @hashonors=(ui[11]>0)
   @callable=ui[12].to_b
   @feedfollowed = ui[13].to_b
   @monitored = ui[14].to_b
    play_sound("menu_open") if submenu != true
Menu.menubg_play if submenu != true and (Configuration.bgsounds==1 && Configuration.soundthemeactivation==1)
sel = [p_("EAPI_Common", "Write a private message"),p_("EAPI_Common", "Visiting card"),p_("EAPI_Common", "Open user's blog"),p_("EAPI_Common", "badges of this user")]
if Session.name!="guest"
if @incontacts == true
  sel.push(p_("EAPI_Common", "Remove from contacts' list"))
else
  sel.push(p_("EAPI_Common", "Add to contacts' list"))
end
if @feedfollowed == true
  sel.push(p_("EAPI_Common", "Unfollow feed"))
else
  sel.push(p_("EAPI_Common", "Follow feed"))
end
else
  sel.push("")
  sel.push("")
end
ringtone=false
  begin
  ringtone_file=EltenPath.join(Dirs.eltendata, "ringtones.json")
  if FileTest.exists?(ringtone_file)
json=JSON.load(File.binread(ringtone_file))
ringtone=true if json[user].is_a?(String) && FileTest.exists?(json[user])
  end
end
if ringtone
  sel.push(p_("EAPI_Common", "Unset ringtone"))
  else
  sel.push(p_("EAPI_Common", "Set ringtone"))
  end
  sel.push(p_("EAPI_Common", "Call this user"))
  sel.push(p_("EAPI_Common", "Show feed"))
  if @monitored==false
  sel.push(p_("EAPI_Common", "Monitor when this user becomes online"))
else
  sel.push(p_("EAPI_Common", "Do not monitor this user"))
    end
  if Session.moderator > 0
  if @isbanned == false
    sel.push(p_("EAPI_Common", "Ban"))
  else
    sel.push(p_("EAPI_Common", "Unban"))
  end
else
  sel.push("")
  end
    if $usermenuextra.is_a?(Hash) and Session.name!="guest"
      $usermenuextra.keys.each do |k|
    sel.push(k)
    end
    end
  if submenu==false
    menu = ListBox.new(sel,header: "",index: 0,flags: ListBox::Flags::AnyDir)
  else
    menu = ListBox.new(sel,header: "")
    end
  menu.disable_item(2) if @hasblog == false
if Session.name=="guest"
  menu.disable_item(0)
    menu.disable_item(4)
    menu.disable_item(5)
   menu.disable_item(6)
    menu.disable_item(7)
    menu.disable_item(9)
  end
menu.disable_item(3) if @hashonors==false
menu.disable_item(7) if @callable==false
menu.disable_item(10) if Session.moderator==0
menu.focus
loop do
loop_update
if key_pressed?(:key_enter)
  play_sound("menu_close")
    Menu.menubg_close
  case menu.index
  when 0
    insert_scene(Scene_Messages_New.new(user,"","",Scene_Main.new), true)
        loop_update
    return "ALT"
    when 1
            visitingcard(user)
      loop_update
            return("ALT")
      break
            when 2
        insert_scene(Scene_Blog_List.new(user,Scene_Main.new), true)
    loop_update
        return "ALT"
        break
    when 3
        insert_scene(Scene_Honors.new(user,Scene_Main.new), true)
    loop_update
    return "ALT"
          when 4
      if @incontacts == true
        confirm(p_("EAPI_Common", "Are you sure you want to delete this contact?")) {
        insert_scene(Scene_Contacts_Delete.new(user,Scene_Main.new), true)
        }
      else
        insert_scene(Scene_Contacts_Insert.new(user,Scene_Main.new), true)
      end
    loop_update
    return "ALT"
    when 5
      if set_feed_follow(user, follow: !@feedfollowed)
        if @feedfollowed
          alert(p_("EAPI_Common", "Feed unfollowed"))
        else
          alert(p_("EAPI_Common", "Feed followed"))
        end
      end
      loop_update
    return "ALT"
    when 6
      if ringtone
        set_ringtone(user, nil)
        alert(p_("EAPI_Common", "Ringtone removed"))
      else
        if requires_premiumpackage("audiophile")
        file=get_file(p_("EAPI_Common", "Select ringtone for user %{user}")%{:user=>user}, path: EltenPath.with_separator(Dirs.documents), save: false, extensions: [".mp3",".wav",".ogg",".mod",".m4a",".flac",".wma",".opus",".aac",".aiff",".w64"])
        if file!=nil
        set_ringtone(user, file)
        alert(p_("EAPI_Common", "Ringtone changed"))
        end
        end
    end
      loop_update
    return "ALT"
        when 7
        voicecall(nil, nil, [user])
        when 8
          insert_scene(Scene_FeedViewer.new(user))
          loop_update
          return "ALT"
        when 9
if @monitored==false
  opts = [p_("EAPI_Common", "Notify me one time when this user becomes online"), p_("EAPI_Common", "Notify me whenever this user becomes online")]
  o = selector(opts, header: p_("EAPI_Common", "Online monitor"), start_index: 0, cancel_index: -1)
  if o>=0
    if add_online_monitor(user, permanent: o)
      alert(p_("EAPI_Common", "This user is now monitored"))
    end
  end
else
  if delete_online_monitor(user)
    alert(p_("EAPI_Common", "This user is no longer monitored"))
  end
  end
      loop_update
    return "ALT"
          when 10
        if @isbanned == false
          insert_scene(Scene_Ban_Ban.new(user,Scene_Main.new), true)
        else
          insert_scene(Scene_Ban_Unban.new(user,Scene_Main.new), true)
        end
    loop_update
    return "ALT"
      else
                if $usermenuextra.is_a?(Hash)
                                    a=$usermenuextra.values[menu.index-11]
                                    s=a[0].new
                                    s.userevent(user, *a[1..-1])
                      insert_scene(s, true)
                                                                 return "ALT"
                  break                  
                  end
end
break
end
if key_pressed?(:key_alt)
  if submenu != true
    break
else
  return("ALT")
  break
end
end
if key_pressed?(:key_escape)
  loop_update
  if submenu == true
        return
    break
  else
        break
    end
  end
  if ((key_pressed?(:key_up) and !left and menu.index==0) or (key_pressed?(:key_left) and left)) and submenu == true
        loop_update
    return
    break
  end
  menu.update
end
Menu.menubg_close if submenu != true
play_sound("menu_close") if submenu != true
end

# Creates a debug info
#
# @return [String] debug information which can be attached to a bug report etc.
          def createdebuginfo
            require "rbconfig"
            require "etc"
            require "digest/sha1"

            safe = proc do |fallback = "", &block|
              value = block.call
              value.nil? ? fallback : value
            rescue Exception
              fallback
            end
            add = proc do |lines, key, value|
              text = value.nil? ? "" : value.to_s
              lines << "#{key}: #{text}" if text != ""
            end
            add_section = proc do |lines, name|
              lines << ""
              lines << "[_#{name}]"
            end
            yes_no = proc do |value|
              value == true ? "yes" : value == false ? "no" : value.to_s
            end
            config = proc do |name|
              safe.call(nil) { Configuration.public_send(name) }
            end
            file_info = proc do |file|
              next "" if file.to_s == ""
              if File.file?(file)
                "#{file} (#{File.size(file)} bytes)"
              else
                "#{file} (missing)"
              end
            rescue Exception
              file.to_s
            end
            pointer_bits = ([nil].pack("p").bytesize * 8).to_i
            config_default = proc do |value, fallback|
              text = value.to_s
              text.empty? ? fallback : text
            end
            uname = safe.call({}) { Etc.uname }
            system_version = safe.call("") { EltenSystemHelpers.os_version if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:os_version) }
            current_executable = safe.call("") do
              if respond_to?(:current_executable_path, true)
                current_executable_path
              elsif Process.respond_to?(:execpath)
                File.expand_path(Process.execpath)
              else
                ""
              end
            end
            launched_by_launcher = safe.call(false) { defined?(EltenBoot) && EltenBoot.launched_by_launcher? }
            developer = safe.call(false) { developer_mode? }

            lines = []
            lines << "*ELTEN | DEBUG INFO*"
            if $! != nil
              add_section.call(lines, "LastException")
              add.call(lines, "Class", $!.class)
              add.call(lines, "Message", $!.message)
              lines << "Backtrace:"
              lines.concat(Array($@))
            end

            add_section.call(lines, "OS")
            add.call(lines, "System", system_version)
            add.call(lines, "Kernel", [uname[:sysname], uname[:release]].compact.reject(&:empty?).join(" "))
            add.call(lines, "Kernel version", uname[:version])
            add.call(lines, "Machine", uname[:machine])
            add.call(lines, "Host", "#{RbConfig::CONFIG["host_os"]} / #{RbConfig::CONFIG["host_cpu"]}")
            add.call(lines, "Target", "#{RbConfig::CONFIG["target_os"]} / #{RbConfig::CONFIG["target_cpu"]}")
            add.call(lines, "Process architecture", "#{defined?(EltenRuntimePaths) ? EltenRuntimePaths.architecture : ""} (#{pointer_bits}-bit)")
            add.call(lines, "Environment architecture", safe.call("") { EltenSystemHelpers.environment_architecture if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:environment_architecture) })

            add_section.call(lines, "Runtime")
            add.call(lines, "Ruby", RUBY_DESCRIPTION)
            add.call(lines, "Ruby engine", "#{defined?(RUBY_ENGINE) ? RUBY_ENGINE : "ruby"} #{defined?(RUBY_ENGINE_VERSION) ? RUBY_ENGINE_VERSION : RUBY_VERSION}")
            add.call(lines, "Ruby ABI", RbConfig::CONFIG["ruby_version"])
            add.call(lines, "Ruby platform", RbConfig::CONFIG["arch"])
            add.call(lines, "RubyGems", safe.call("") { defined?(Gem) && Gem.const_defined?(:VERSION, false) ? Gem.const_get(:VERSION).to_s : "not loaded" })
            add.call(lines, "Bundler", safe.call("") { defined?(Bundler) && Bundler.const_defined?(:VERSION, false) ? Bundler.const_get(:VERSION).to_s : "not loaded" })
            yjit_status = if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?)
              RubyVM::YJIT.enabled? ? "enabled" : "disabled"
            else
              "unavailable"
            end
            add.call(lines, "YJIT", yjit_status)
            if yjit_status == "enabled" && RubyVM::YJIT.respond_to?(:runtime_stats)
              stats = safe.call({}) { RubyVM::YJIT.runtime_stats }
              add.call(lines, "YJIT stats", stats.sort_by { |key, _value| key.to_s }.map { |key, value| "#{key}=#{value}" }.join(", ")) if stats.is_a?(Hash) && !stats.empty?
            end
            add.call(lines, "Default external encoding", Encoding.default_external)
            add.call(lines, "Default internal encoding", Encoding.default_internal || "nil")
            add.call(lines, "Locale charmap", safe.call("") { Encoding.locale_charmap })
            add.call(lines, "Filesystem encoding", safe.call("") { Encoding.find("filesystem") })
            add.call(lines, "Loaded features", $LOADED_FEATURES.size)
            add.call(lines, "Loaded gems", safe.call("") { defined?(Gem) && Gem.respond_to?(:loaded_specs) ? Gem.loaded_specs.size : "" })
            gc = safe.call({}) { GC.stat }
            add.call(lines, "GC count", gc[:count])
            add.call(lines, "GC heap live/free slots", [gc[:heap_live_slots], gc[:heap_free_slots]].compact.join(" / "))
            add.call(lines, "GC old objects", gc[:old_objects])
            add.call(lines, "GC total allocated objects", gc[:total_allocated_objects])
            add.call(lines, "GC malloc increase bytes", gc[:malloc_increase_bytes])

            add_section.call(lines, "Launch")
            add.call(lines, "PID", Process.pid)
            add.call(lines, "Executable", current_executable)
            add.call(lines, "Ruby executable", safe.call("") { RbConfig.ruby }) unless launched_by_launcher
            add.call(lines, "Program file", $PROGRAM_NAME)
            add.call(lines, "Working directory", Dir.pwd)
            add.call(lines, "Launched by launcher", yes_no.call(launched_by_launcher))
            add.call(lines, "Developer mode", yes_no.call(developer))
            add.call(lines, "Startup hidden", yes_no.call(safe.call(false) { defined?(EltenBoot) && EltenBoot.startup_hidden? }))
            add.call(lines, "Platform tags", safe.call("") { defined?(EltenBoot) ? EltenBoot.platform_tags.join(", ") : "" })
            add.call(lines, "Command line", $commandline) if $commandline.to_s != ""
            add.call(lines, "ARGV", ARGV.inspect)
            add.call(lines, "Threads", Thread.list.size)

            add_section.call(lines, "Elten")
            add.call(lines, "Version", safe.call("") { defined?(Elten) ? Elten.version : "" })
            add.call(lines, "Build ID", safe.call("") { defined?(Elten) ? Elten.build_id : "" })
            add.call(lines, "Build date", safe.call("") { defined?(Elten) ? Elten.build_date : "" })
            add.call(lines, "Branch", safe.call("") { defined?(Elten) ? Elten.branch : config.call(:branch) })
            add.call(lines, "API URL", safe.call("") { elten_api_base_url })
            add.call(lines, "Session", safe.call("") { Session.logged? ? "logged in" : "not logged in" })
            add.call(lines, "Session hash", safe.call("") { Digest::SHA1.hexdigest(Session.name.to_s + ":" + Session.token.to_s) })
            add.call(lines, "Start time", $start)
            add.call(lines, "Current time", Time.now.to_i)
            add.call(lines, "Uptime", ($start != nil ? Time.now.to_i - $start.to_i : 0))

            add_section.call(lines, "Paths")
            add.call(lines, "Root", safe.call("") { defined?(EltenRuntimePaths) ? EltenRuntimePaths.root : File.expand_path("../..", __dir__) })
            add.call(lines, "Runtime directory", safe.call("") { defined?(EltenRuntimePaths) ? EltenRuntimePaths.runtime_directory_name : "" })
            add.call(lines, "Runtime bin", safe.call("") { defined?(EltenRuntimePaths) ? EltenRuntimePaths.arch_bin : "" })
            add.call(lines, "Data", safe.call("") { Dirs.eltendata })
            add.call(lines, "Apps root", safe.call("") { Dirs.appsdata })
            add.call(lines, "Apps source", safe.call("") { Dirs.apps })
            add.call(lines, "Sound themes", safe.call("") { Dirs.soundthemes })
            add.call(lines, "Extras", safe.call("") { Dirs.extras })
            add.call(lines, "Temp", safe.call("") { Dirs.temp })
            add.call(lines, "Log file", safe.call("") { file_info.call(EltenPath.join(Dirs.eltendata, "elten.log")) })
            add.call(lines, "Config file", safe.call("") { file_info.call(EltenPath.join(Dirs.eltendata, "elten.ini")) })

            add_section.call(lines, "Configuration")
            add.call(lines, "Language", config.call(:language))
            add.call(lines, "Voice", config.call(:voice).to_s == "" ? "default" : config.call(:voice))
            add.call(lines, "Voice rate/volume/pitch", [config.call(:voicerate), config.call(:voicevolume), config.call(:voicepitch)].compact.join(" / "))
            add.call(lines, "Main volume", config.call(:volume))
            add.call(lines, "Sound theme", config_default.call(config.call(:soundtheme), "default"))
            add.call(lines, "Sound theme active", config.call(:soundthemeactivation))
            add.call(lines, "Background sounds", config.call(:bgsounds))
            add.call(lines, "Use pan", config.call(:usepan))
            add.call(lines, "Braille enabled", config.call(:enablebraille))
            add.call(lines, "Autoplay", config.call(:autoplay))
            add.call(lines, "Auto login", config.call(:autologin))
            add.call(lines, "HTTP/2 disabled", config.call(:disablehttp2))
            add.call(lines, "Conference TCP only", config.call(:tcpconferences))
            add.call(lines, "Conference audio buffer/cutoff", [config.call(:conferencesaudiobuffer), config.call(:conferencesaudiobuffercutoff)].compact.join(" / "))
            add.call(lines, "UDP packet size", config.call(:udppacketsize))
            add.call(lines, "Bilinear HRTF", config.call(:usebilinearhrtf))
            add.call(lines, "Audio buffering", config.call(:enableaudiobuffering))

            add_section.call(lines, "AudioSpeech")
            bass_version = safe.call("") do
              version = Bass::BASS_GetVersion.call.to_i
              format("%d.%d.%d.%d", (version >> 24) & 0xff, (version >> 16) & 0xff, (version >> 8) & 0xff, version & 0xff)
            end
            add.call(lines, "BASS", bass_version)
            output_devices = safe.call([]) { Bass.soundcards }
            input_devices = safe.call([]) { Bass.microphones }
            add.call(lines, "Output devices", output_devices.size) if output_devices.respond_to?(:size)
            add.call(lines, "Input devices", input_devices.size) if input_devices.respond_to?(:size)
            add.call(lines, "Configured output", config.call(:soundcard).to_s == "" ? "default" : config.call(:soundcard))
            add.call(lines, "Configured input", config.call(:microphone).to_s == "" ? "default" : config.call(:microphone))
            if defined?(SpeechOutput)
              current_output = safe.call(nil) { SpeechOutput.current_output }
              current_voice = safe.call(nil) { SpeechOutput.voice_for(SpeechOutput.configured_voice) || SpeechOutput.default_voice }
              outputs = safe.call([]) { SpeechOutput.list }
              add.call(lines, "Speech output", current_output == nil ? "none" : current_output.name.to_s)
              add.call(lines, "Speech voice", current_voice == nil ? "default" : "#{current_voice.name} (#{current_voice.voiceid})")
              add.call(lines, "Speech outputs", outputs.map { |output| "#{output.name}: voices=#{safe.call(0) { output.voices.size }}, stream=#{yes_no.call(safe.call(false) { output.stream_output_supported? })}" }.join("; ")) if outputs.respond_to?(:map)
            end
            add.call(lines, "Invisible interface", yes_no.call(safe.call(false) { defined?(InvisibleInterface) && InvisibleInterface.available? }))
            add.call(lines, "Tray supported", yes_no.call(safe.call(false) { tray_supported? }))

            lines.join("\r\n") + "\r\n"
          end

# Shows user agreement
#
# @param omit [Boolean] determines whether to allow user to close the window without accepting
    def license(omit=false)
    @license = licensetext
    @rules = _doc('rules')
    @privacypolicy = _doc('privacypolicy')
form = Form.new([
EditBox.new(p_("EAPI_Common", "License agreement"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::MarkDown,text: @license,quiet: true),
EditBox.new(p_("EAPI_Common", "Terms and Conditions"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::MarkDown,text: @rules,quiet: true),
EditBox.new(p_("EAPI_Common", "Privacy Policy"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::MarkDown,text: @privacypolicy,quiet: true),
Button.new(p_("EAPI_Common", "I accept Elten license agreement, Terms and Conditions and Privacy Policy")),Button.new(p_("EAPI_Common", "I do not accept, exit"))])
loop do
  loop_update
  form.update
  if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index == 4
    exit
  end
  if (key_pressed?(:key_space) or key_pressed?(:key_enter)) and form.index == 3
    break
  end
  if key_pressed?(:key_escape)
    if omit == true
      break
    else
      if form.index==0 or form.index==1
        form.index+=1
        form.focus
        else
    q = confirm(p_("EAPI_Common", "Do you accept Elten license agreement, terms and conditions and privacy policy?"))
    if q == 0
      exit
    else
      break
      end
    end
    end
    end
  end
end

# Opens an audio player
#
# @param file [String] a location or URL of a media to play
# @param label [String] player window caption
# @param wait [Boolean] close a player after audio is played
# @param control [Boolean] allow user to control the played audio, by for example scrolling it
# @param try_download [Boolean] download a file if the codec doesn't support streaming
# @param is_stream [Boolean] whether file is already a stream URL/source
def player(file, label: "", wait: false, control: true, try_download: false, is_stream: false)
  soundfont=EltenPath.join(Dirs.extras, "soundfont.sf2")
  if File.extname(file).downcase==".mid" and FileTest.exists?(soundfont) == false
    if confirm(p_("EAPI_Common", "You are trying to play a midi file. In order to play such files, Elten needs an  external base of instruments. Do you want to download the base from the server  now? It may take several minutes."))
      alert(p_("EAPI_Common", "Please wait, the soundfont is being downloaded. It may take a while."))
    download_file(soundfont_url,soundfont)
    alert(p_("EAPI_Common", "Soundfont downloaded succesfully."))
    Bass::BASS_SetConfigPtr.call(0x10403,soundfont)
  else
    return
    end
      end
    if label != ""
  dialog_open if wait==false
dialog_mute
end
snd=Player.new(file,label: label,autoplay: true,quiet: false)
delay(0.1)
    loop do
                    loop_update
                    snd.update if control
  if wait == true
    if snd.sound!=nil
  if !snd.paused?
    if snd.sound.length>0 && snd.sound.position>=snd.sound.length-0.05
                  snd.close
      return
     break
            end
          end
          end
  end
  if (key_pressed?(:key_enter) and !key_held?(0x10)) or key_pressed?(:key_escape) or snd.sound==nil
    snd.fade
    snd.close
    dialog_close if label!=""
    break
    end
  end
end

# gets a key pressed by user
#
# @param keys [Array] a keyboard state
# @param multi [Boolean] support multikeys
# @return [String] returns pressed key or keys, if nothing pressed, the return value is an empty string
# @example read the pressed keys
#  loop do
  #   speak(getkeychar)
  #   break if escape
  #  end
def getkeychar(keybd=nil,multi=false)
  default_keyboard = keybd == nil
  serial = $input_frame_serial || $key_update_serial || 0
  if default_keyboard && $getkeychar_cache_serial == serial
    return $getkeychar_cache.to_s
  end
if default_keyboard && EltenWindow.character_input_supported?
    ret = EltenWindow.take_character(multi)
    if ret != ""
      $getkeychar_cache_serial = serial
      $getkeychar_cache = ret.to_s
      $lastkeychar=[ret,Time.now.to_i*1000000+Time.now.usec.to_i]
      return ret.to_s
    end
  end
  akey = default_keyboard && defined?(EltenAPI::KeyboardState) ? EltenAPI::KeyboardState.current.pressed : nil
  akey=keybd if keybd!=nil
  keybd=EltenAPI::KeyboardState.current.state if keybd==nil && defined?(EltenAPI::KeyboardState)
  akey ||= Array.new(256, false)
  keybd ||= "\0"*256
  keybd=keybd.map{|k|((k)?(255):(0))}.pack("C*") if keybd.is_a?(Array)
  akey=akey.unpack("c*").map{|k|k<0} if !akey.is_a?(Array)
    ret=""
          (32..255).each do |i|
    if akey[i]
      re = EltenKeyboard.translate_virtual_key(i, keybd)

 if re!="" and re.getbyte(0)>=32
   ret += re
   break if multi!=true
 end
end
end
  $lastkeychar=[ret,Time.now.to_i*1000000+Time.now.usec.to_i] if ret!=""
  if default_keyboard
    $getkeychar_cache_serial = serial
    $getkeychar_cache = ret.to_s
  end
          return ret
        end
    
      # @note this function is reserved for Elten usage
                  def thr1
                                        loop do
            begin
            sleep(0.1)
              nvda = defined?(NVDA) ? NVDA : nil
              if nvda != nil && SpeechOutput.current_output != nvda
                if !nvda.check and nvda.usable?
nvda.stop
end
                      end
              rescue Exception
        fail
      end
      end
    end

# @note this function is reserved for Elten usage
  def thr2
    $subthreads=[] if $subthreads==nil
                                loop do
                              sleep(0.05)
                                    if $scenes.size > 0
                                      if $currentthread != $mainthread
                                                                                  $subthreads.push($currentthread)
                                        end
                                      $currentthread = Thread.new do
                                        stopct=false
                                        sc=$scene
                                        sleep(0.1)
                                        begin
                                          if stopct == false
                                                                                    newsc = $scenes[0]
                                          $scenes.delete_at(0)
                                          return_to_main = newsc.instance_variable_get(:@insert_scene_return_to_main) == true
                                                                $scene = newsc
                                                                  while $scene != nil and $scene.is_a?(Scene_Main) == false and $exit!=true
Log.debug("Loading parallel scene: #{$scene.class.to_s}")
$scene.main
                      end
                      $scene = return_to_main ? Scene_Main.new : sc
$scene=Scene_Main.new if $scene.is_a?(Scene_Main) or $scene == nil
$scene=nil if $exit==true
EltenAPI::KeyboardState.reset if defined?(EltenAPI::KeyboardState)
$focus = true if $scene.is_a?(Scene_Main) == false                     and $scene!=nil
Log.info("Exiting parallel scenes thread")
end
rescue Exception
      stopct=true
                                                                        $scene = sc
$scene=Scene_Main.new if $scene.is_a?(Scene_Main) or $scene == nil
loop_update
$focus = true if $scene.is_a?(Scene_Main) == false                    
Log.error("Parallel scene: #{$!.to_s} #{$@.to_s}")
  retry
end
sleep(0.1)
end
end
    if $switchthread!=nil
      cr=$switchthread
      $switchthread=nil
      cur=$currentthread
      $subthreads.push(cur) if cur!=nil
      $subthreads.delete(cr)
$currentthread=cr
      end
    if $currentthread != $mainthread
      if $currentthread.status==false or $currentthread.status==nil
        if $subthreads.size > 0
    $currentthread=$subthreads.last
    while $subthreads.last.status==false or $subthreads.last.status==nil
      $subthreads.delete_at($subthreads.size-1)
    end
      $subthreads.delete_at($subthreads.size-1)
    else
      $currentthread=$mainthread
      end
        end
                                                                                                                                                              end
         sleep(0.1)
       end
     rescue Exception
              retry
     end

  @@hrtf_loaded=false
  def load_hrtf(*)
    return true if @@hrtf_loaded==true

    require_relative "steamaudio" unless defined?(::SteamAudio)
    loaded = SteamAudio.load(steamaudio_library_path)
    @@hrtf_loaded=true if loaded
    Log.error("SteamAudio HRTF library not available") if !loaded
    loaded
  rescue Exception
    Log.error("SteamAudio HRTF load failed: #{$!.class}: #{$!.message}")
    false
  end

  def steamaudio_library_path
    defined?(EltenRuntimePaths) ? EltenRuntimePaths.absolute_library_file("phonon") : "phonon"
  end
  
  @@premiumpackages=[]
  def update_premiumpackages(packages)
    @@premiumpackages=packages if packages.is_a?(Array)
    end
  def holds_premiumpackage(package)
    return false if Session.name==""||Session.name==nil||Session.name=="guest"
    return @@premiumpackages.include?(package)
    end

    def requires_premiumpackage(package)
      return true if holds_premiumpackage(package)
      package_name=''
      case package
      when "courier"
        package_name=p_("EAPI_Common", "Courier")
when "audiophile"
        package_name=p_("EAPI_Common", "Audiophile")
        when "scribe"
        package_name=p_("EAPI_Common", "Scribe")
when "director"
        package_name=p_("EAPI_Common", "Director")
      end
      confirm(p_("EAPI_Common", "This feature requires %{package} premium package. Would you like to see the premium packages available?")%{:package=>package_name}) {insert_scene(Scene_PremiumPackages.new)
      }
      return false
      end
    
# Gets the size of a file or directory
#
# @param location [String] a location to a file or directory
# @param upd [Boolean] window refreshing
# @return [Numeric] a size in bytes
def getsize(location,upd=true)
               if File.file?(location)
    sz= File.size(location)
        sz=0 if sz<0
    return sz
    end
                      return Dir.size(location)
                    end
                    
  def getfileversioninfo(file, verinfo)
EltenSystemHelpers.file_version_info(file, verinfo)
rescue Exception
  return nil
end
  
  # @note this function is reserved for Elten usage
  def tray_supported?
    if EltenWindow.tray_supported?
      return EltenWindow.tray_supported?
    end
    if defined?(EltenTray) && EltenTray.respond_to?(:supported?)
      return EltenTray.supported?
    end
    defined?(EltenTray)
  rescue Exception
    false
  end

  def tray
    return false unless tray_supported?
    $totray=true
    true
  end

  def platform_os
    EltenSystemHelpers.platform_os
  rescue Exception
    "unknown"
  end

  def platform_target
    return EltenSystemHelpers.platform_target if EltenSystemHelpers.respond_to?(:platform_target)
    cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
    arch = cpu =~ /arm|aarch64/ ? "arm64" : (cpu.include?("64") ? "x64" : "x86")
    "#{platform_os}-#{arch}"
  rescue Exception
    platform_os
  end

  def beta_version_creation_supported?
    EltenSystemHelpers.beta_version_creation_supported?
  rescue Exception
    true
  end

  def autologin_key_encryption_supported?
    EltenSystemHelpers.autologin_key_encryption_supported?
  rescue Exception
    false
  end

  def platform_installer_path
    EltenSystemHelpers.installer_path(Dirs.eltendata)
  rescue Exception
    EltenPath.join(Dirs.eltendata, "eltenup")
  end

  def platform_update_install_command(installer = platform_installer_path, silent: true)
    EltenSystemHelpers.update_install_command(installer, silent: silent)
  rescue Exception
    command = "\"#{installer}\""
    command += " /tasks=\"\" /silent" if silent
    command
  end

  def platform_open_url(url)
    EltenSystemHelpers.open_url(url)
  rescue Exception
    false
  end
       def process_notification(notif)
         play_sound(notif['sound']) if notif['sound']!=nil
        if notif['alert']!=nil
            speak(notif['alert'], stop: false)
        end
       end
       
       def register_activity(wait: false, final: false)
                  ActivityReports.flush(wait: wait, force: final)
       end
       
       def set_ringtone(user, file)
         json={}
         ringtone_file=EltenPath.join(Dirs.eltendata, "ringtones.json")
         begin
if FileTest.exists?(ringtone_file)
  json=JSON.load(File.binread(ringtone_file))
  end
           rescue Exception
         end
         if file==nil
           json.delete(user)
         else
           json[user]=file
         end
         File.binwrite(ringtone_file, JSON.generate(json))
         end
       
       def plum
         play_sound("feed_update")
         "plum"
         end

class FeedMessage
attr_accessor :id, :user, :time, :message, :response, :responses, :liked, :likes
def initialize(id=0, user="", time=0, message="", response=0, responses=0, liked=false, likes=0)
@id, @user, @time, @message, @response, @responses, @liked, @likes = id, user, time, message, response, responses, liked, likes
@user=self.class.utf8(@user)
@message=self.class.utf8(@message)
@time=0 if !@time.is_a?(Integer) || @time<0
end
def self.utf8(value)
str=value.to_s.dup
str.force_encoding(Encoding::UTF_8) if str.encoding!=Encoding::UTF_8
str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
end
def to_h
return {'id'=>@id, 'message'=>@message, 'time'=>@time, 'user'=>@user, 'response'=>@response, 'responses'=>@responses, 'liked'=>@liked, 'likes'=>@likes}
end
end
       
       class SoundTheme
         attr_accessor :name, :stamp, :file
         attr_reader :sounds
         def initialize(name, stamp=nil, file=nil)
           @name=name
           @stamp=stamp
           @file=file
           @sounds={}
         end
         def getsound(name)
           return nil if !name.is_a?(String)
             return @sounds[name.downcase]
           end
         end

       class DirectorySoundTheme < SoundTheme
         def initialize(name, directory)
           super(name, nil, directory)
           @directory=directory
           collect_sounds
         end

         def getsound(name)
           return nil if !name.is_a?(String)
           path=@sounds[name.downcase]
           return nil if path==nil || !File.file?(path)
           File.binread(path)
         rescue Exception
           Log.warning("Cannot read directory soundtheme sound #{name}: #{$!.class}: #{$!.message}") if defined?(Log)
           nil
         end

         private

         def collect_sounds
           return if !File.directory?(@directory)
           root=File.expand_path(@directory)
           Dir.children(@directory).each do |entry|
             next if File.extname(entry).downcase!=".ogg"
             path=File.expand_path(File.join(@directory, entry))
             next if path!=root && !path.start_with?(root+File::SEPARATOR)
             next if !File.file?(path)
             @sounds[File.basename(entry, File.extname(entry)).downcase]=path
           end
         rescue Exception
           Log.warning("Cannot collect directory soundtheme sounds from #{@directory}: #{$!.class}: #{$!.message}") if defined?(Log)
         end
       end
       
       @@defaultsoundtheme=SoundTheme.new("")
         @@soundtheme=nil
       DEFAULT_SOUND_THEME_PACKAGE="data/audio.elsnd"
       DEFAULT_SOUND_THEME_DIRECTORY="audio"

       def load_soundtheme(file, loadSounds=true)
         Log.debug("Loading soundtheme: "+file)
         return nil if !FileTest.exists?(file) 
         size=File.size(file)
         return nil if size>64*1024**2 || size<36
         limit=0
         limit=32+8+1+256+4 if !loadSounds
         io=StringIO.new(limit.to_i > 0 ? File.open(file, "rb") { |f| f.read(limit.to_i) } : File.binread(file))
         magic="EltenSoundThemePackageFileCMPSMC"
         return nil if io.read(32)!=magic
         stamp=io.read(8).unpack("Q").first
         sz=io.read(1).unpack("C").first
         st=SoundTheme.new(io.read(sz), stamp, file)
         sz=io.read(4).unpack("I").first
         return nil if size!=sz+32+8+1+st.name.size+4
                                             if loadSounds
                                               zio=StringIO.new(Zlib::Inflate.inflate(io.read(sz)))
         while !zio.eof?
           sz=zio.read(1).unpack("C").first
           file=zio.read(sz)
           sz=zio.read(4).unpack("I").first
           content=zio.read(sz)
             st.sounds[file.downcase]=content
           end
           end
         return st
       rescue Exception
         Log.error("Cannot load soundtheme: "+$!.to_s+" "+$@.to_s)
         return nil
       end

       def load_directory_soundtheme(directory, name="default")
         return nil if !File.directory?(directory)
         st=DirectorySoundTheme.new(name, directory)
         return nil if st.sounds.empty?
         st
       rescue Exception
         Log.error("Cannot load directory soundtheme: "+$!.to_s+" "+$@.to_s)
         nil
       end

       def default_soundtheme_package?(file)
         normalized=file.to_s.tr("\\", "/").downcase
         normalized==DEFAULT_SOUND_THEME_PACKAGE || normalized.end_with?("/"+DEFAULT_SOUND_THEME_PACKAGE)
       end
       
       def use_soundtheme(file, default=false)
         if default==false && (file==""||file==nil)
           @@soundtheme=@@defaultsoundtheme
           return true
           end
         st=load_soundtheme(file)
         if st==nil && default==true && default_soundtheme_package?(file)
           Log.warning("Default soundtheme package #{file} unavailable; using #{DEFAULT_SOUND_THEME_DIRECTORY} directory fallback") if defined?(Log)
           st=load_directory_soundtheme(DEFAULT_SOUND_THEME_DIRECTORY)
         end
         if st!=nil
           @@soundtheme=st
         @@defaultsoundtheme=st if default
          return true
           end
         false
         end
         
       def getsound(file, default=false)
         if @@soundtheme!=nil && !default
           sound=@@soundtheme.getsound(file)
           return sound if sound!=nil
end
if @@defaultsoundtheme!=nil
           sound=@@defaultsoundtheme.getsound(file)
           return sound if sound!=nil
end
return nil
end

    
    def voicecall(channel=nil, channel_password=nil, invite=[])
      invite=[invite] if invite.is_a?(String)
      Conference.open if !Conference.opened?
      return    if Session.name=="guest"
Conference.open if !Conference.opened?
if !Conference.opened?
$scene=Scene_Main.new
return
end
if channel==nil
channel_password = rand(36**32).to_s(36)
chname="VoiceCall_"+Session.name
channel = Conference.create(chname, false, 56, 40, 1, 0, false, true, channel_password, 0, 2, nil).to_i
else
Conference.join(channel, channel_password)
end
delay(1)
tm=nil
tm=30 if invite.is_a?(Array) && invite.size==1
sc=Scene_Conference.new(tm, 1)
if invite.is_a?(Array)
invite.each{|user|sc.invite(user)}
Conference.calling_play if invite.size==1
end
insert_scene(sc)
      end

def json_load_ext(str)
          Log.debug("JSON Load Ext")
return JSON.load(str)
rescue Exception
return nil
end

def process_url(url)
  Log.debug("Opening URL #{url}")
  return if !url.is_a?(String)
  if url[0...8].downcase!="elten://"
    platform_open_url(url)
  return true
end
bu=url[8..-1]
q=bu.split("/")
case q[0]
when "forum"
  case q[1]
  when "group"
    insert_scene(Scene_Forum.new(nil, q[2].to_i))
    when "forum"
      insert_scene(Scene_Forum.new(nil, q[2]))
      when "thread"
        t=q[3].to_i
        t=nil if q[3]==nil
        insert_scene(Scene_Forum_Thread.new(q[2].to_i, -13, 0, t, nil, Scene_Main.new))
else
  return false
  end
  when "blog"
    
else
  return false
end
  end
      end
     include Common
       end
