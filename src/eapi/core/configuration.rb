# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  private
    def load_configuration_value(group, key, values, default)
      raise ArgumentError, "Invalid default configuration value" if !values.value?(default)

      stored_default = values.key(default)
      value = readconfig(group, key, stored_default)
      return values[value] if values.key?(value)

      Log.warning("Invalid configuration value for #{group}/#{key}: #{value.inspect}; using #{stored_default.inspect}")
      writeconfig(group, key, stored_default)
      default
    end

    def load_configuration_boolean(group, key, default)
      load_configuration_value(group, key, { "false" => false, "true" => true }, default)
    end

    def load_configuration_choice(group, key, values, default)
      mapping = values.each_with_object({}) { |value, result| result[value.to_s] = value }
      load_configuration_value(group, key, mapping, default)
    end

    def load_configuration_list(group, key, values, default)
      raw = readconfig(group, key, default.join(","))
      selected = raw.to_s.split(",").map { |value| value.to_sym }
      return selected if (selected - values).empty?

      Log.warning("Invalid configuration value for #{group}/#{key}: #{raw.inspect}; using #{default.join(",").inspect}")
      writeconfig(group, key, default.join(","))
      default
    end

    def load_configuration
        Log.info("Loading configuration")
        migrate_configuration
        LocalConfig.load
        lang=Configuration.language
  Configuration.listtype = load_configuration_choice("Interface", "ListType", [:linear, :circular], :linear)
  Configuration.keyboardscheme = load_configuration_choice("Interface", "KeyboardScheme", [:default, :windows, :macos], :default)
  Configuration.macoscharacternavigation = load_configuration_choice("Interface", "MacOSCharacterNavigation", [:default, :disabled, :enabled], :default)
  Configuration.disablefeednotifications = load_configuration_boolean("Interface", "DisableFeedNotifications", false)
  Configuration.iimodifiers = load_configuration_choice("InvisibleInterface", "IIModifiers", [:automatic, :alt_ctrl_windows, :alt_shift_windows, :alt_ctrl_shift, :alt_ctrl, :alt_shift], :automatic)
  Configuration.iicards = load_configuration_list("InvisibleInterface", "Cards", [:messages, :feed, :conference], [:messages, :feed, :conference])
  Configuration.roundupforms = load_configuration_boolean("Interface", "RoundUpForms", false)
  Configuration.usepan = load_configuration_boolean("Interface", "UsePan", true)
  Configuration.soundcard = readconfig("SoundCard", "SoundCard", "")
  if Configuration.soundcard==""
                Sapi.set_device(-1) if defined?(Sapi)
                  Bass.setdevice(-1)
                else
    sc=Bass.soundcards
  for i in 0...sc.size
    if sc[i].name==Configuration.soundcard
    Bass.setdevice(i)
    end
  end
    devices=defined?(Sapi) ? Sapi.devices : []
    for i in 0...devices.size
            if Configuration.soundcard==devices[i]
                Sapi.set_device(i)
        end
      end
      end
Configuration.microphone = readconfig("SoundCard", "Microphone", "")
  s=false
  mc=Bass.microphones
  for i in 0...mc.size
    if mc[i].name==Configuration.microphone
          Bass.setrecorddevice(i)
    s=true
    end
  end
  if s==false
    defl=mc.index(mc.find{|m|m.default?})||-1
  Bass.setrecorddevice(defl)
  end
    Configuration.controlspresentation = load_configuration_choice("Interface", "ControlsPresentation", [:voice_and_sound, :sound_only, :voice_only], :voice_and_sound)
  Configuration.contextmenubar = load_configuration_boolean("Interface", "ContextMenuBar", true)
Configuration.soundthemeactivation = load_configuration_boolean("Interface", "SoundThemeActivation", true)
Configuration.typingecho = load_configuration_choice("Interface", "TypingEcho", [:characters, :words, :characters_and_words, :none], :characters)
Configuration.bgsounds = load_configuration_boolean("Interface", "BGSounds", true)
Configuration.linewrapping = load_configuration_boolean("Interface", "LineWrapping", true)
Configuration.hidewindow = load_configuration_boolean("Interface", "HideWindow", false)
Configuration.synctime = load_configuration_boolean("Advanced", "SyncTime", true)
Configuration.saytimeperiod = load_configuration_choice("Clock", "SayTimePeriod", [:hourly, :half_hourly, :quarter_hourly], :hourly)
Configuration.saytimetype = load_configuration_choice("Clock", "SayTimeType", [:none, :voice_and_sound, :voice_only, :sound_only], :voice_and_sound)
Configuration.registeractivity = load_configuration_value("Privacy", "RegisterActivity", { "unset" => nil, "false" => false, "true" => true }, nil)
Configuration.checkupdates = load_configuration_boolean("Updates", "CheckAtStartup", true)
Configuration.autoplay = load_configuration_choice("Interface", "AutoPlay", [:always, :without_transcription, :never], :always)
Configuration.branch = load_configuration_choice("Updates", "Branch", [:auto, :stable, :rc, :beta], :auto)
if tray_supported?
c_autostart=load_configuration_boolean("System", "AutoStart", false)
path=EltenSystemHelpers.autostart_executable_path(current_executable_path)
c_autostart=false if !EltenSystemHelpers.autostart_executable?(path)
autostart_cmd=EltenSystemHelpers.autostart_command(path)
EltenSystemHelpers.sync_autostart(c_autostart, autostart_cmd)
end
Configuration.voice = readconfig("Voice","Voice","")
if $rvc==nil
      if (/\/voice (-?)(\d+)/=~$commandline) != nil
        $rvc=$1+$2
        Configuration.voice=$rvc.to_s
            end
          end
          if Configuration.voice.to_i.to_s==Configuration.voice
            if Configuration.voice.to_i==-1
              Configuration.voice=defined?(NVDA) ? "NVDA" : ""
              elsif Configuration.voice.to_i>=0
            voices=defined?(Sapi) ? SpeechOutput.voices.find_all{|voice|voice.output==Sapi} : []
            if Configuration.voice.to_i<voices.size
            Configuration.voice=voices[Configuration.voice.to_i].voiceid
          else
            Configuration.voice=""
          end
        else
          Configuration.voice=""
        end
                  writeconfig("Voice", "Voice", Configuration.voice)
                end
                Configuration.enablebraille = load_configuration_boolean("Interface", "EnableBraille", false)
                Configuration.usevoicedictionary = load_configuration_boolean("Voice", "UseVoiceDictionary", true)
          Configuration.language = readconfig("Interface", "Language", "")
          if Configuration.language.include?("_")
            Configuration.language.gsub!("_","-")
            writeconfig("Interface", "Language", Configuration.language)
          end
          Configuration.voicerate = readconfig("Voice","Rate",50)
        if $rvcr==nil
      if (/\/voicerate (\d+)/=~$commandline) != nil
        $rvcr=$1
        Configuration.voicerate=$rvcr.to_i
            end
    end

                  SpeechOutput.list.each{|output| output.set_rate(Configuration.voicerate) if output.rate_supported?}
                      Configuration.voicevolume = readconfig("Voice","Volume",100)
    if $rvcv==nil
      if (/\/voicevolume (\d+)/=~$commandline) != nil
        $rvcv=$1
        Configuration.voicevolume=$rvcv.to_i
            end
    end
    SpeechOutput.list.each{|output| output.set_volume(Configuration.voicevolume) if output.volume_supported?}
    Configuration.voicepitch = readconfig("Voice","Pitch",50)
    if Configuration.voice!="" && Configuration.voice!="?"
                      output=SpeechOutput.output_for_voice(Configuration.voice)
                      if output!=nil
                        output.apply_voice(Configuration.voice)
                      else
                        Configuration.voice=""
                        writeconfig("Voice", "Voice", Configuration.voice)
                      end
                    end
                    if Configuration.voice==""
                      Sapi.apply_default_voice if defined?(Sapi)
    end
    SpeechOutput.apply_current_settings if defined?(SpeechOutput)
          Configuration.soundtheme = readconfig("Interface","SoundTheme","")
            Configuration.soundtheme=nil if Configuration.soundtheme.size == 0
stheme=nil
stheme=EltenPath.join(Dirs.soundthemes, Configuration.soundtheme+".elsnd") if Configuration.soundtheme!=nil
use_soundtheme(stheme)
                          Configuration.volume = readconfig("Interface", "MainVolume", 50)
                          Configuration.usefx = load_configuration_value("Advanced", "UseFX", { "auto" => :auto, "false" => false, "true" => true }, :auto)
                          Configuration.usedenoising = load_configuration_choice("Advanced", "UseDenoising", [:never, :conferences, :conferences_and_recording], :never)
                          Configuration.useechocancellation = load_configuration_boolean("Advanced", "UseEchoCancellation", false)
                          Configuration.usebilinearhrtf = load_configuration_boolean("Advanced", "UseBilinearHRTF", false)
                          Configuration.disableconferencemiconrecord = load_configuration_boolean("Advanced", "DisableConferenceMicOnRecord", false)
                          Configuration.enableaudiobuffering = load_configuration_boolean("Advanced", "EnableAudioBuffering", false)
                          Configuration.sessiontime = readconfig("Advanced", "AgentSessionTime", 2)
                          Configuration.disablehttp2 = load_configuration_boolean("Advanced", "DisableHTTP2", false)
                          Configuration.requestresponsecachemode = load_configuration_choice("Advanced", "RequestResponseCacheMode", [:disabled, :mutating, :all], :mutating)
                      Configuration.tcpconferences = load_configuration_boolean("Advanced", "ConferencesTCPOnly", false)
                      Configuration.conferencesaudiobuffer = readconfig("Advanced", "ConferencesAudioBuffer", 0)
                      Configuration.conferencesaudiobuffercutoff = readconfig("Advanced", "ConferencesAudioBufferCutOff", 250)
                      Configuration.udppacketsize = readconfig("Advanced", "UDPMaxPacketSize", 1480)
                          Configuration.autologin = load_configuration_boolean("Login", "EnableAutoLogin", true)
                          if lang!=Configuration.language
                            setlocale(Configuration.language)
                            SpeechOutput.apply_current_settings if defined?(SpeechOutput)
                          end
                                if Configuration.registeractivity==nil
  Configuration.registeractivity = confirm(p_("EAPI_EltenAPI", "Do you want to send reports on how Elten is used? This data does not contain any confidential information and is very helpful in program development. This selection can be changed at any time from the Settings."))
  writeconfig("Privacy", "RegisterActivity", Configuration.registeractivity)
  end
  if Elten.branch.to_s.downcase!="stable" && Configuration.registeractivity==false
    delay(1)
    alert(p_("EAPI_EltenAPI", "You are currently using a beta version of Elten. In these versions, uploading usage statistics is always enabled. They contain information about the most frequently used functions, configurations and problems with program operation. They do not contain any confidential or private information. If you do not want to send statistics, please use the stable version of Elten."))
  Configuration.registeractivity = true
  writeconfig("Privacy", "RegisterActivity", Configuration.registeractivity)
  end
                        end

end
