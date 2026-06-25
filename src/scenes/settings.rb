# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2022 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Settings
  def initialize
    @settings=[]
    @values={}
  end
  def currentconfig(group, key)
    return @values[[group,key]]||readconfig(group,key)
  end
  def setcurrentconfig(group,key,val)
@values[[group,key]]=val.to_s
end
def speaker_waiter
 loop do
   loop_update
   if key_any_pressed?
     speech_stop
     end
   break if speech_actived==false
   end
  end
  def setting_category(cat)
    @settings.push([cat, nil])
    @form.fields[0].options.push(cat)
  end
  def on_load(&func)
    return if @settings.size==0
    @settings.last[1]=func
    end
def make_setting(label, type, section, config=nil, mapping=nil, multi=false)
  return if @settings.size==0
  mapping=mapping.map{|x|x.to_s} if mapping!=nil
  @settings.last.push([label, type, section, config, mapping, multi])
end
def save_category
  for i in 2...@settings[@category].size
    setting=@settings[@category][i]
        next if setting==nil || setting[1]==:custom
    index=i-1
    field=@form.fields[index]
    next if field==nil
    val=field.value
    val=val.to_i if setting[1]==:number
    val=val ? 1 : 0 if setting[1]==:bool
    val=setting[4][val] if setting[4]!=nil
    if setting[1].is_a?(Array) && setting[5]==true
      mpg=setting[4]
      mpg=(0...setting[1].size).to_a.map{|a|a.to_s} if mpg==nil
      vl=[]
      for i in 0...mpg.size
        vl.push(mpg[i]) if field.selected[i]
      end
      val=vl.join(",")
      end
    setcurrentconfig(setting[2], setting[3], val)
    end
  end
def show_category(id)
  return if @form==nil or @settings[id]==nil
  save_category if @category!=nil
  @category=id
  @form.show_all
  @form.fields[1...-3]=[]
  f=[]
for s in @settings[id][2..-1]
  label, type, section, config, mapping, multi = s
  field=nil
  case type
  when :text
    field=EditBox.new(label, type: 0, text: currentconfig(section, config),quiet: true)
    when :number
    field=EditBox.new(label, type: EditBox::Flags::Numbers, text: currentconfig(section, config),quiet: true)
    when :bool
      field=CheckBox.new(label, checked: currentconfig(section, config).to_i!=0)
      when :custom
        field=Button.new(label)
        proc=section
                field.on(:press, 0, true, &proc)
              else
                index=0
                if multi==false
      index=currentconfig(section, config)
      index=mapping.find_index(index)||0 if mapping!=nil
      end
      flags=0
      flags|=ListBox::Flags::MultiSelection if multi==true
      field=ListBox.new(type, header: label, index: index.to_i, flags: flags)
      if multi==true
      mpg=mapping
      mpg||=(0...type.size).to_a.map{|a|a.to_s}
      mpg=mpg.map{|a|a.delete(",")}
      flds=currentconfig(section, config).split(",")
      for f in flds
        ind=mpg.find_index(f)
        field.selected[ind]=true if ind!=nil
        end
        end
    end
@form.fields.insert(@form.fields.size-3, field)
end
@settings[id][1].call if @settings[id][1]!=nil
end
def apply_settings
  save_category
  for k in @values.keys
    v=@values[k]
    writeconfig(k[0], k[1], v)
  end
  load_configuration
  end
def make_window
  @form=Form.new
  @form.fields[0] = ListBox.new([], header: p_("Settings", "Category"))
  @form.fields[1]=Button.new(_("Apply"))
  @form.fields[2]=Button.new(_("Save"))
  @form.fields[3]=Button.new(_("Cancel"))
  end
  def load_general
    setting_category(p_("Settings", "General"))
        l=loadedlanguages.map{|l|l.realcode}
        langsmapping=["en-GB"]
    for d in l
        langsmapping.push(d) if !langsmapping.include?(d)
        end
  langsmapping=langsmapping.find_all{|l|Lists.langs[l[0..1].downcase].is_a?(Hash)}
        langs=langsmapping.map{|l|Lists.langs[l[0..1].downcase]['name']+" ("+Lists.langs[l[0..1].downcase]['nativeName']+")"}  
      make_setting(p_("Settings", "Language"), langs, "Interface", "Language", langsmapping)
                            make_setting(p_("Settings", "Automatically minimize Elten Window to system tray"), :bool, "Interface", "HideWindow") if tray_supported?
                                        make_setting(p_("Settings", "Enable auto log in"), :bool, "Login", "EnableAutoLogin", [0, 1])
        make_setting(p_("Settings", "Automatically start Elten after I log on to Windows"), :bool, "System", "AutoStart") if tray_supported?
        make_setting(p_("Settings", "Check for updates at startup"), :bool, "Updates", "CheckAtStartup")
        make_setting(p_("Settings", "Updates branch"), [p_("Settings", "Auto"),p_("Settings", "Stable"), p_("Settings", "RC"), p_("Settings", "Beta")], "Updates", "Branch", ["","stable","rc","beta"])
        make_setting(p_("Settings", "Send Elten usage reports"), :bool, "Privacy", "RegisterActivity")
      end
      def load_interface
        setting_category(p_("Settings", "Interface"))
                make_setting(p_("Settings", "Play sounds of sound themes"), :bool, "Interface", "SoundThemeActivation")
                make_setting(p_("Settings", "Soundtheme volume"), (5..100).to_a.reverse.map{|x|x.to_s+"%"}, "Interface", "MainVolume", (5..100).to_a.reverse)
                 make_setting(p_("Settings", "Manage sound themes"), :custom, Proc.new{insert_scene(Scene_SoundThemes.new)})
                 make_setting(p_("Settings", "Use Stereo positioning for user interface"), :bool,"Interface", "UsePan")
                                                  make_setting(p_("Settings", "Use background sounds in menu and dialog windows"), :bool, "Interface", "BGSounds")
                 make_setting(p_("Settings", "Display context menu in menu bar"), :bool, "Interface", "ContextMenuBar")
                 make_setting(p_("Settings", "Control types announcement"), [p_("Settings", "Voice and sound"),p_("Settings", "Sound only"), p_("Settings", "Voice only")], "Interface", "ControlsPresentation")                    
                    make_setting(p_("Settings", "Wrap long lines in text fields"), :bool, "Interface", "LineWrapping")
            make_setting(p_("Settings", "The display method of selection lists"), [p_("Settings", "Linear"),p_("Settings", "Circular")], "Interface", "ListType")                    
            make_setting(p_("Settings", "Round up the forms"), :bool, "Interface", "RoundUpForms")                    
            make_setting(p_("Settings", "Disable feed notifications"), :bool, "Interface", "DisableFeedNotifications")
            make_setting(p_("Settings", "Automatically play audio content"), [p_("Settings", "Always"),p_("Settings", "Only when transcription is not available"), p_("Settings", "Never")], "Interface", "AutoPlay")                    
            on_load {
            @form.fields[1].on(:change) {
            if @form.fields[1].checked
              @form.show(2)
              @form.show(3)
              @form.show(4)
              @form.show(5)
            else
              @form.hide(2)
              @form.hide(3)
              @form.hide(4)
              @form.hide(5)
              end
            }
            @form.fields[1].trigger(:change)
            }
        end
      def load_voice
        setting_category(p_("Settings", "Voice"))
                speechvoices=SpeechOutput.voices
        voices=speechvoices.map{|v|v.name}
        voicesmapping=speechvoices.map{|v|v.voiceid}
        make_setting(p_("Settings", "Voice"), voices, "Voice", "Voice", voicesmapping)
        make_setting(p_("Settings", "Speech rate"), (0..100).to_a.reverse.map{|x|x.to_s+"%"}, "Voice", "Rate", (0..100).to_a.reverse)
        make_setting(p_("Settings", "Speech volume"), (5..100).to_a.reverse.map{|x|x.to_s+"%"}, "Voice", "Volume", (5..100).to_a.reverse)
        make_setting(p_("Settings", "Speech pitch"), (0..100).to_a.reverse.map{|x|x.to_s+"%"}, "Voice", "Pitch", (0..100).to_a.reverse)
        make_setting(p_("Settings", "Enable braille output (requires NVDA addon)"), :bool, "Interface", "EnableBraille") if SpeechOutput.list.any?{|output| output.braille_supported?}
        make_setting(p_("Settings", "Use a voice dictionary when processing characters (requires NVDA addon when using NVDA as a speech output)"), :bool, "Voice", "UseVoiceDictionary")
                        make_setting(p_("Settings", "Typing echo"), [p_("Settings", "Characters"),p_("Settings", "Words"),p_("Settings", "Characters and words"),p_("Settings", "None")], "Interface", "TypingEcho")
        on_load {
        voice_output=Proc.new {
          voice=voicesmapping[@form.fields[1].index].to_s
          SpeechOutput.output_for_voice(voice) || SpeechOutput.default_output
        }
        @form.fields[1].on(:move) {
          output=voice_output.call
          output!=nil && output.rate_supported? ? @form.show(2) : @form.hide(2)
          output!=nil && output.volume_supported? ? @form.show(3) : @form.hide(3)
          output!=nil && output.pitch_supported? ? @form.show(4) : @form.hide(4)
        }
        @form.fields[1].trigger(:move)
        @form.fields[1].on(:move) {
        speech_stop
          output=voice_output.call
          vc=Configuration.voice
          Configuration.voice=voicesmapping[@form.fields[1].index].to_s
          output.apply_voice(Configuration.voice) if output!=nil
          @form.fields[1].say_option
          speaker_waiter
          Configuration.voice=vc
          SpeechOutput.apply_current_voice
        }
        @form.fields[2].on(:move) {
        speech_stop
        output=voice_output.call
        output.set_rate(100-@form.fields[2].index) if output!=nil && output.rate_supported?
                @form.fields[2].say_option
                speaker_waiter
                SpeechOutput.current_output.set_rate(Configuration.voicerate) if SpeechOutput.current_output!=nil && SpeechOutput.current_output.rate_supported?
        }
        @form.fields[3].on(:move) {
        speech_stop
        output=voice_output.call
        output.set_volume(100-@form.fields[3].index) if output!=nil && output.volume_supported?
        @form.fields[3].say_option
        speaker_waiter
        SpeechOutput.current_output.set_volume(Configuration.voicevolume) if SpeechOutput.current_output!=nil && SpeechOutput.current_output.volume_supported?
        }
        @form.fields[4].on(:move) {
        speech_stop
        output=voice_output.call
        next if output==nil || !output.pitch_supported?
        pt=Configuration.voicepitch
        Configuration.voicepitch=100-@form.fields[4].index
        @form.fields[4].say_option
        speaker_waiter
        Configuration.voicepitch=pt
        }
        }
      end
      def load_clock
        setting_category(p_("Settings", "Clock"))
        make_setting(p_("Settings", "Clock information"), [p_("Settings", "None"),p_("Settings", "Voice and sound"),p_("Settings", "Voice only"),p_("Settings", "Sound only")], "Clock", "SayTimeType")
        make_setting(p_("Settings", "announcement time"), [p_("Settings", "every hour"),p_("Settings", "every half hour"),p_("Settings", "every quarter of an hour")], "Clock", "SayTimePeriod", [1, 2, 3])
        make_setting(p_("Settings", "Alarms"), :custom, Proc.new{insert_scene(Scene_Clock.new)})
        on_load {
        @form.fields[1].on(:move) {
        if @form.fields[1].index==0
          @form.hide(2)
        else
          @form.show(2)
          end
        }
        @form.fields[1].trigger(:move)
        }
      end
      def load_soundcards
        setting_category(p_("Settings", "Sound devices"))
        if @soundsettings==nil
            @soundcards=Bass.soundcards
            @microphones=Bass.microphones
    @soundcards[0]=Bass::Device.new(p_("Settings", "Use Default"), "", 1|2)
    @soundcards.delete_at(1)
    @microphones=[Bass::Device.new(p_("Settings", "Use Default"), "", 1|2)]+@microphones
    @soundcardsmapping=@soundcards.map{|c|c.name}
    @soundcardsmapping[0]=""
    @microphonesmapping=@microphones.map{|m|m.name}
    @microphonesmapping[0]=""
    i=1
    while i<@soundcards.size
      if @soundcards[i].disabled?
      @soundcards.delete_at(i)
      @soundcardsmapping.delete_at(i)
        else
        i+=1
        end
      end
    i=1
    while i<@microphones.size
      if @microphones[i].disabled?
      @microphones.delete_at(i)
      @microphonesmapping.delete_at(i)
        else
        i+=1
        end
      end
      @soundcards=@soundcards.map{|c|c.name}
      @microphones=@microphones.map{|m|o="";o=" ("+p_("Settings", "Loopback device")+")" if m.loopback?;m.name+o}
      @soundsettings=true
    end
    make_setting(p_("Settings", "Output device"), @soundcards, "SoundCard", "SoundCard", @soundcardsmapping)
    make_setting(p_("Settings", "Input device"), @microphones, "SoundCard", "Microphone", @microphonesmapping)
    make_setting(p_("Settings", "Mute the microphone in conferences while recording other content"), :bool, "Advanced", "DisableConferenceMicOnRecord")
    make_setting(p_("Settings", "Use noise reduction"), [p_("Settings", "Never"), p_("Settings", "In audio conferences only"), p_("Settings", "In audio conferences and when recording")], "Advanced", "UseDenoising")
    make_setting(p_("Settings", "Enable echo cancellation"), :bool, "Advanced", "UseEchoCancellation")
      end
  def load_ii
    return if !defined?(EltenAPI::InvisibleInterface) || (EltenAPI::InvisibleInterface.respond_to?(:available?) && !EltenAPI::InvisibleInterface.available?)
    setting_category(p_("Settings", "Invisible interface"))
                ii={
            "ALT+CTRL+WINDOWS"=>0x1|0x2|0x8,
            "ALT+WINDOWS+SHIFT"=>0x1|0x4|0x8,
            "ALT+CTRL+SHIFT"=>0x1|0x2|0x4,
            "ALT+CTRL"=>0x1|0x2,
            "ALT+SHIFT"=>0x1|0x4,
            }
            iimodifiers=[]
            iimodifiersmapping=[]
            ii.each{|k|iimodifiers.push(k[0]);iimodifiersmapping.push(k[1])}
            make_setting(p_("Settings", "Modifier keys"), iimodifiers, "InvisibleInterface", "IIModifiers", iimodifiersmapping)
            make_setting(p_("Settings", "Cards to show"), [p_("Settings","Messages"), p_("Settings","Feed"), p_("Settings", "Conference options")], "InvisibleInterface", "Cards", ["messages", "feed", "conference"], true)
    end
    def load_advanced
          setting_category(p_("Settings", "Advanced"))
    make_setting(p_("Settings", "Enable FX effects"), :bool, "Advanced", "UseFX")
    make_setting(p_("Settings", "Use bilinear HRTF interpolation"), :bool, "Advanced", "UseBilinearHRTF")
    make_setting(p_("Settings", "Session refresh time in seconds"), :number, "Advanced", "AgentSessionTime")
    make_setting(p_("Settings", "Disable concurrent requests (HTTP2)"), :bool, "Advanced", "DisableHTTP2")
    make_setting(p_("Settings", "Use only TCP packets in conferences"), :bool, "Advanced", "ConferencesTCPOnly")
    make_setting(p_("Settings", "Maximum UDP packet payload size"), :number, "Advanced", "UDPMaxPacketSize")
    make_setting(p_("Settings", "Conferences audio buffer in frames"), :number, "Advanced", "ConferencesAudioBuffer")
    make_setting(p_("Settings", "Conference buffer cut-off threshold in milliseconds"), :number, "Advanced", "ConferencesAudioBufferCutOff")
    end
    def main
        make_window
        load_general
        load_interface
        load_voice
        load_clock
        load_soundcards
        load_ii
        load_advanced
        @form.focus
        loop do
          loop_update
          @form.update
          show_category(@form.fields[0].index) if @category!=@form.fields[0].index
          if @form.fields[-3].pressed?
            apply_settings
            speak(_("Saved"))
          end
                    if @form.fields[-2].pressed? or (key_pressed?(:key_enter) and !@form.fields[@form.index].is_a?(Button))
            apply_settings
            alert(_("Saved"))
            $scene=Scene_Main.new
          end
          if key_pressed?(:key_escape) or @form.fields[-1].pressed?
            $scene=Scene_Main.new
          end
          break if $scene!=self
        end
      end
      end
