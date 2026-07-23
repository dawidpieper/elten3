# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  private
    def load_configuration
        Log.info("Loading configuration")
        lang=Configuration.language
  Configuration.listtype = readconfig("Interface", "ListType", 0)
  Configuration.keyboardscheme = readconfig("Interface", "KeyboardScheme", "default")
  Configuration.macoscharacternavigation = readconfig("Interface", "MacOSCharacterNavigation", "default")
  Configuration.disablefeednotifications = readconfig("Interface", "DisableFeedNotifications", 0)
  Configuration.iimodifiers = readconfig("InvisibleInterface", "IIModifiers", 0)
  Configuration.iicards = readconfig("InvisibleInterface", "Cards", "messages,feed,conference")
  Configuration.roundupforms = readconfig("Interface", "RoundUpForms", 0)
  Configuration.usepan = readconfig("Interface", "UsePan", 1)
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
    Configuration.controlspresentation = readconfig("Interface", "ControlsPresentation", 0)
  Configuration.contextmenubar = readconfig("Interface", "ContextMenuBar", 1)
Configuration.soundthemeactivation = readconfig("Interface", "SoundThemeActivation", 1)
Configuration.typingecho = readconfig("Interface", "TypingEcho", 0)
Configuration.bgsounds = readconfig("Interface", "BGSounds", 1)
Configuration.linewrapping = readconfig("Interface", "LineWrapping", 1)
Configuration.hidewindow = readconfig("Interface", "HideWindow", 0)
Configuration.synctime = readconfig("Advanced", "SyncTime", 1)
Configuration.saytimeperiod = readconfig("Clock", "SayTimePeriod", 1)
Configuration.saytimetype = readconfig("Clock", "SayTimeType", 1)
Configuration.registeractivity = readconfig("Privacy", "RegisterActivity", -1)
Configuration.checkupdates = readconfig("Updates", "CheckAtStartup", 1)
Configuration.autoplay = readconfig("Interface", "AutoPlay", 0)
Configuration.branch = readconfig("Updates", "Branch", "")
if tray_supported?
c_autostart=readconfig("System", "AutoStart", 0)
path=EltenSystemHelpers.autostart_executable_path(current_executable_path)
c_autostart=0 if !EltenSystemHelpers.autostart_executable?(path)
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
                Configuration.enablebraille = readconfig("Interface", "EnableBraille", 0)
                Configuration.usevoicedictionary = readconfig("Voice", "UseVoiceDictionary", 1)
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
                          Configuration.usefx = readconfig("Advanced", "UseFX", -1)
                          Configuration.usedenoising = readconfig("Advanced", "UseDenoising", 0)
                          Configuration.useechocancellation = readconfig("Advanced", "UseEchoCancellation", 0)
                          Configuration.usebilinearhrtf = readconfig("Advanced", "UseBilinearHRTF", 0)
                          Configuration.disableconferencemiconrecord = readconfig("Advanced", "DisableConferenceMicOnRecord", 0)
                          Configuration.enableaudiobuffering = readconfig("Advanced", "EnableAudioBuffering", 0)
                          Configuration.sessiontime = readconfig("Advanced", "AgentSessionTime", 2)
                          Configuration.disablehttp2 = readconfig("Advanced", "DisableHTTP2", 0)
                          Configuration.requestresponsecachemode = readconfig("Advanced", "RequestResponseCacheMode", "mutating")
                          unless ["disabled", "mutating", "all"].include?(Configuration.requestresponsecachemode)
                            Configuration.requestresponsecachemode = "mutating"
                            writeconfig("Advanced", "RequestResponseCacheMode", Configuration.requestresponsecachemode)
                          end
                      Configuration.tcpconferences = readconfig("Advanced", "ConferencesTCPOnly", 0)
                      Configuration.conferencesaudiobuffer = readconfig("Advanced", "ConferencesAudioBuffer", 0)
                      Configuration.conferencesaudiobuffercutoff = readconfig("Advanced", "ConferencesAudioBufferCutOff", 250)
                      Configuration.udppacketsize = readconfig("Advanced", "UDPMaxPacketSize", 1480)
                          Configuration.autologin = readconfig("Login", "EnableAutoLogin", 1)
                          if lang!=Configuration.language
                            setlocale(Configuration.language)
                            SpeechOutput.apply_current_settings if defined?(SpeechOutput)
                          end
                                if Configuration.registeractivity==-1
  Configuration.registeractivity = (confirm(p_("EAPI_EltenAPI", "Do you want to send reports on how Elten is used? This data does not contain any confidential information and is very helpful in program development. This selection can be changed at any time from the Settings.")) ? 1 : 0)
  writeconfig("Privacy", "RegisterActivity", Configuration.registeractivity)
  end
  if Elten.branch.to_s.downcase!="stable" && Configuration.registeractivity==0
    delay(1)
    alert(p_("EAPI_EltenAPI", "You are currently using a beta version of Elten. In these versions, uploading usage statistics is always enabled. They contain information about the most frequently used functions, configurations and problems with program operation. They do not contain any confidential or private information. If you do not want to send statistics, please use the stable version of Elten."))
  Configuration.registeractivity = 1
  writeconfig("Privacy", "RegisterActivity", Configuration.registeractivity)
  end
                        end

end
