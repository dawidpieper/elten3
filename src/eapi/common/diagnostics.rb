# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
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
  end
end
