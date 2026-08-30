# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Settings
  def initialize
    @settings=[]
    @values={}
    @bound_settings={}
    @speaker_preview_restorer=nil
  end
  def currentconfig(group, key)
    if group==:extension_setting
      value_key=[group,key]
      return @values[value_key] if @values.key?(value_key)
      binding=@bound_settings[key.to_s]
      if binding!=nil
        begin
          return binding[0].call.to_s
        rescue Exception => error
          Log.error("Cannot read extension setting #{key}: #{error.class}: #{error.message}")
          return ""
        end
      end
      return ""
    end
    return @values[[group,key]]||readconfig(group,key)
  end
  def setcurrentconfig(group,key,val)
@values[[group,key]]=val.to_s
end
def start_speaker_preview(&restorer)
  restore_speaker_preview
  @speaker_preview_restorer=restorer
end
def restore_speaker_preview
  restorer=@speaker_preview_restorer
  @speaker_preview_restorer=nil
  restorer.call if restorer!=nil
end
def stop_speaker_preview
  return if @speaker_preview_restorer==nil
  speech_stop
  restore_speaker_preview
end
def update_speaker_preview
  return if @speaker_preview_restorer==nil
  if key_any_pressed?
    stop_speaker_preview
  elsif speech_actived==false
    restore_speaker_preview
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
def make_order_setting(label, options, section, config, mapping)
  return if @settings.size==0
  raise ArgumentError, "Ordered setting options and mapping must have the same size" if options.size!=mapping.size
  @settings.last.push([label, :order, section, config, mapping.map{|x|x.to_s}, false, options])
end
def make_bound_setting(label, type, key, getter, setter, mapping=nil, multi=false)
  @bound_settings[key.to_s]=[getter,setter]
  make_setting(label,type,:extension_setting,key.to_s,mapping,multi)
end
def save_category
  for i in 2...@settings[@category].size
    setting=@settings[@category][i]
        next if setting==nil || setting[1]==:custom
    index=i-1
    field=@form.fields[index]
    next if field==nil
    if setting[1]==:order
      setcurrentconfig(setting[2], setting[3], field.params[:setting_order].join(","))
      next
    end
    val=field.value
    val=val.to_i if setting[1]==:number
    val=val ? "true" : "false" if setting[1]==:bool
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
  stop_speaker_preview
  save_category if @category!=nil
  @category=id
  @form.show_all
  @form.fields[1...-3]=[]
  f=[]
for s in @settings[id][2..-1]
  label, type, section, config, mapping, multi, order_options = s
  field=nil
  case type
  when :text
    field=EditBox.new(label, type: 0, text: currentconfig(section, config),quiet: true)
    when :number
    field=EditBox.new(label, type: EditBox::Flags::Numbers, text: currentconfig(section, config),quiet: true)
    when :bool
      field=CheckBox.new(label, checked: currentconfig(section, config)=="true")
      when :custom
        field=Button.new(label)
        proc=section
                field.on(:press, 0, true, &proc)
      when :order
        field=make_order_setting_field(label, order_options, section, config, mapping)
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
  stop_speaker_preview
  save_category
  begin
    for k in @values.keys
      v=@values[k]
      if k[0]==:extension_setting
        binding=@bound_settings[k[1].to_s]
        binding[1].call(v) if binding!=nil
      else
        writeconfig(k[0], k[1], v)
      end
    end
    load_configuration
    true
  rescue Exception => error
    Log.error("Cannot apply settings: #{error.class}: #{error.message}")
    alert(p_("Settings", "Cannot save settings: %{error}") % {:error => error.message.to_s})
    false
  end
end
def make_window
  @form=Form.new
  @form.fields[0] = ListBox.new([], header: p_("Settings", "Category"))
  @form.fields[1]=Button.new(_("Apply"))
  @form.fields[2]=Button.new(_("Save"))
  @form.fields[3]=Button.new(_("Cancel"))
  end
  def normalize_setting_order(value, mapping)
    available = mapping.map{|item|item.to_s}
    requested = value.is_a?(Array) ? value.map{|item|item.to_s} : value.to_s.split(",")
    normalized = []
    requested.each do |item|
      normalized.push(item) if available.include?(item) && !normalized.include?(item)
    end
    normalized.concat(available-normalized)
  end
  def make_order_setting_field(label, options, section, config, mapping)
    order = normalize_setting_order(currentconfig(section, config), mapping)
    labels = {}
    mapping.each_with_index{|value,index|labels[value.to_s]=options[index]}
    field = ListBox.new(order.map{|value|labels[value]}, header: label, index: 0, flags: 0)
    field.params[:setting_order]=order
    field.params[:setting_order_labels]=labels
    field.add_tip(p_("Settings", "Use Shift with up/down arrows to move items"))
    field.bind_context do |menu|
      menu.option(p_("Settings", "Move up")){move_order_setting(field,-1)} if field.index>0
      menu.option(p_("Settings", "Move down")){move_order_setting(field,1)} if field.index<order.size-1
    end
    field
  end
  def order_setting_field?(field)
    field!=nil && field.respond_to?(:params) && field.params[:setting_order].is_a?(Array)
  end
  def move_order_setting(field, offset)
    return false if !order_setting_field?(field)
    order=field.params[:setting_order]
    old_index=field.index
    new_index=old_index+offset.to_i
    return false if new_index<0 || new_index>=order.size
    order[old_index],order[new_index]=order[new_index],order[old_index]
    labels=field.params[:setting_order_labels]
    field.options=order.map{|value|labels[value]}
    field.index=new_index
    field.say_option
    true
  end
  def update_order_setting
    field=@form.fields[@form.index]
    return if !order_setting_field?(field) || !key_held?(0x10)
    move_order_setting(field,-1) if key_pressed?(:key_up)
    move_order_setting(field,1) if key_pressed?(:key_down)
  end
  def notification_type_order_labels(order)
    helper = Object.new.extend(NotificationGroups)
    order.map { |type| helper.category_label(type) }
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
                                        make_setting(p_("Settings", "Enable auto-login"), :bool, "Login", "EnableAutoLogin")
        make_setting(
          p_("Settings", "Start Elten after I log on to Windows"),
          [p_("Settings", "Do not start automatically"), p_("Settings", "Start hidden"), p_("Settings", "Start with the window visible")],
          "System",
          "AutoStart",
          ["disabled", "hidden", "visible"]
        ) if tray_supported?
        make_setting(p_("Settings", "Check for updates at startup"), :bool, "Updates", "CheckAtStartup")
        make_setting(p_("Settings", "Updates branch"), [p_("Settings", "Auto"),p_("Settings", "Stable"), p_("Settings", "RC"), p_("Settings", "Beta")], "Updates", "Branch", ["auto","stable","rc","beta"])
        make_setting(p_("Settings", "Send Elten usage reports"), :bool, "Privacy", "RegisterActivity")
      end
      def load_interface
        setting_category(p_("Settings", "Interface"))
                make_setting(p_("Settings", "Play sounds from sound themes"), :bool, "Interface", "SoundThemeActivation")
                make_setting(p_("Settings", "Sound theme volume"), (5..100).to_a.reverse.map{|x|x.to_s+"%"}, "Interface", "MainVolume", (5..100).to_a.reverse)
                 make_setting(p_("Settings", "Manage sound themes"), :custom, Proc.new{insert_scene(Scene_SoundThemes.new)})
                 make_setting(p_("Settings", "Use Stereo positioning for user interface"), :bool,"Interface", "UsePan")
                                                  make_setting(p_("Settings", "Use background sounds in menu and dialog windows"), :bool, "Interface", "BGSounds")
                 make_setting(p_("Settings", "Display context menu in menu bar"), :bool, "Interface", "ContextMenuBar")
                 make_setting(p_("Settings", "Announce control types"), [p_("Settings", "Voice and sound"),p_("Settings", "Sound only"), p_("Settings", "Voice only")], "Interface", "ControlsPresentation", ["voice_and_sound", "sound_only", "voice_only"])
                    make_setting(p_("Settings", "Wrap long lines in text fields"), :bool, "Interface", "LineWrapping")
            make_setting(p_("Settings", "Selection-list navigation mode"), [p_("Settings", "Linear"),p_("Settings", "Circular")], "Interface", "ListType", ["linear", "circular"])
            make_setting(p_("Settings", "Wrap focus within forms"), :bool, "Interface", "RoundUpForms")
            make_setting(p_("Settings", "Automatically play audio content"), [p_("Settings", "Always"),p_("Settings", "Only when transcription is not available"), p_("Settings", "Never")], "Interface", "AutoPlay", ["always", "without_transcription", "never"])
            make_setting(p_("Settings", "Keyboard scheme"), [p_("Settings", "Default"), p_("Settings", "Windows"), p_("Settings", "macOS")], "Interface", "KeyboardScheme", ["default", "windows", "macos"])
            make_setting(p_("Settings", "Use macOS-style character navigation in text fields"), [p_("Settings", "System Default"), p_("Settings", "Disable"), p_("Settings", "Enable")], "Interface", "MacOSCharacterNavigation", ["default", "disabled", "enabled"])
            make_setting(p_("Settings", "Manage keyboard shortcuts"), :custom, Proc.new { insert_scene(Scene_KeyboardShortcuts.new) })
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
      def load_main_window
        setcurrentconfig("MainWindow", "Tabs", Configuration.maintabs.join(","))
        setcurrentconfig("MainWindow", "ShowNotificationsWhenEmpty", Configuration.showemptynotifications.to_s)
        setcurrentconfig("MainWindow", "NotificationFocus", Configuration.mainnotificationfocus.to_s)
        setcurrentconfig("MainWindow", "NotificationSort", Configuration.mainnotificationsort.to_s)
        setcurrentconfig("MainWindow", "NotificationTypeOrder", Configuration.mainnotificationtypeorder.join(","))
        setting_category(p_("Settings", "Main window"))
        make_setting(
          p_("Settings", "Tabs visible in the main window"),
          [p_("Settings", "Notifications"), p_("Settings", "Feed"), p_("Settings", "Quick actions")],
          "MainWindow",
          "Tabs",
          ["notifications", "feed", "actions"],
          true
        )
        make_setting(p_("Settings", "Show the notifications tab even when there are no new notifications"), :bool, "MainWindow", "ShowNotificationsWhenEmpty")
        make_setting(
          p_("Settings", "Notification focus after returning to the main window"),
          [
            p_("Settings", "Keep the previously selected tab"),
            p_("Settings", "Switch only when new notifications arrive"),
            p_("Settings", "Switch whenever unread notifications are present")
          ],
          "MainWindow",
          "NotificationFocus",
          ["keep_current", "new_notifications", "unread_notifications"]
        )
        make_setting(
          p_("Settings", "Notification sorting"),
          [p_("Settings", "By time"), p_("Settings", "By type, then by time")],
          "MainWindow",
          "NotificationSort",
          ["time", "type"]
        )
        notification_types=NotificationGroups.default_notification_type_order
        make_order_setting(
          p_("Settings", "Notification type order"),
          notification_type_order_labels(notification_types),
          "MainWindow",
          "NotificationTypeOrder",
          notification_types
        )
        make_setting(p_("Settings", "Disable feed notifications"), :bool, "Interface", "DisableFeedNotifications")
        make_setting(p_("Settings", "Reset quick actions"), :custom, Proc.new {
          confirm(p_("Settings", "Are you sure you want to restore default quick actions?")) {
            begin
              QuickActions.reset_defaults
              alert(p_("Settings", "Quick actions have been reset"))
            rescue Exception => error
              Log.error("Cannot reset quick actions: #{error.class}: #{error.message}")
              alert(_("Error"))
            end
          }
        })
        on_load do
          @form.fields[4].on(:move) do
            @form.fields[4].index == 1 ? @form.show(5) : @form.hide(5)
          end
          @form.fields[4].trigger(:move)
        end
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
        if SpeechOutput.list.any? { |output| output.braille_supported? }
          braille_label = if defined?(OSXVoiceOverOutput) && OSXVoiceOverOutput.available?
            p_("Settings", "Enable braille output")
          else
            p_("Settings", "Enable braille output (requires NVDA addon)")
          end
          make_setting(braille_label, :bool, "Interface", "EnableBraille")
        end
        make_setting(p_("Settings", "Use a voice dictionary when processing characters (requires NVDA addon when using NVDA as a speech output)"), :bool, "Voice", "UseVoiceDictionary")
                        make_setting(p_("Settings", "Typing echo"), [p_("Settings", "Characters"),p_("Settings", "Words"),p_("Settings", "Characters and words"),p_("Settings", "None")], "Interface", "TypingEcho", ["characters", "words", "characters_and_words", "none"])
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
          restore_speaker_preview
          output=voice_output.call
          vc=Configuration.voice
          start_speaker_preview {
            Configuration.voice=vc
            SpeechOutput.apply_current_voice
          }
          Configuration.voice=voicesmapping[@form.fields[1].index].to_s
          output.apply_voice(Configuration.voice) if output!=nil
          @form.fields[1].say_option
        }
        @form.fields[2].on(:move) {
        speech_stop
        restore_speaker_preview
        output=voice_output.call
        start_speaker_preview {
          SpeechOutput.current_output.set_rate(Configuration.voicerate) if SpeechOutput.current_output!=nil && SpeechOutput.current_output.rate_supported?
        }
        output.set_rate(100-@form.fields[2].index) if output!=nil && output.rate_supported?
                @form.fields[2].say_option
        }
        @form.fields[3].on(:move) {
        speech_stop
        restore_speaker_preview
        output=voice_output.call
        start_speaker_preview {
          SpeechOutput.current_output.set_volume(Configuration.voicevolume) if SpeechOutput.current_output!=nil && SpeechOutput.current_output.volume_supported?
        }
        output.set_volume(100-@form.fields[3].index) if output!=nil && output.volume_supported?
        @form.fields[3].say_option
        }
        @form.fields[4].on(:move) {
        speech_stop
        restore_speaker_preview
        output=voice_output.call
        next if output==nil || !output.pitch_supported?
        pt=Configuration.voicepitch
        start_speaker_preview {
          Configuration.voicepitch=pt
        }
        Configuration.voicepitch=100-@form.fields[4].index
        @form.fields[4].say_option
        }
        }
      end
      def load_clock
        setting_category(p_("Settings", "Clock"))
        make_setting(p_("Settings", "Clock information"), [p_("Settings", "None"),p_("Settings", "Voice and sound"),p_("Settings", "Voice only"),p_("Settings", "Sound only")], "Clock", "SayTimeType", ["none", "voice_and_sound", "voice_only", "sound_only"])
        make_setting(p_("Settings", "announcement time"), [p_("Settings", "every hour"),p_("Settings", "every half hour"),p_("Settings", "every quarter of an hour")], "Clock", "SayTimePeriod", ["hourly", "half_hourly", "quarter_hourly"])
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
    make_setting(p_("Settings", "Use noise reduction"), [p_("Settings", "Never"), p_("Settings", "In audio conferences only"), p_("Settings", "In audio conferences and when recording")], "Advanced", "UseDenoising", ["never", "conferences", "conferences_and_recording"])
    make_setting(p_("Settings", "Enable echo cancellation"), :bool, "Advanced", "UseEchoCancellation")
      end
  def load_ii
    return if !defined?(EltenAPI::InvisibleInterface) || (EltenAPI::InvisibleInterface.respond_to?(:available?) && !EltenAPI::InvisibleInterface.available?)
    setting_category(p_("Settings", "Invisible interface"))
            ii={
            "ALT+CTRL+WINDOWS"=>"alt_ctrl_windows",
            "ALT+WINDOWS+SHIFT"=>"alt_shift_windows",
            "ALT+CTRL+SHIFT"=>"alt_ctrl_shift",
            "ALT+CTRL"=>"alt_ctrl",
            "ALT+SHIFT"=>"alt_shift",
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
    make_setting(p_("Settings", "Disable concurrent requests (HTTP/2)"), :bool, "Advanced", "DisableHTTP2")
    make_setting(p_("Settings", "Recover responses after request timeout"), [p_("Settings", "Disabled"), p_("Settings", "Mutating requests"), p_("Settings", "All requests")], "Advanced", "RequestResponseCacheMode", ["disabled", "mutating", "all"])
    make_setting(p_("Settings", "Use only TCP packets in conferences"), :bool, "Advanced", "ConferencesTCPOnly")
    make_setting(p_("Settings", "Maximum UDP packet payload size"), :number, "Advanced", "UDPMaxPacketSize")
    make_setting(p_("Settings", "Conference audio buffer in frames"), :number, "Advanced", "ConferencesAudioBuffer")
    make_setting(p_("Settings", "Conference buffer cut-off threshold in milliseconds"), :number, "Advanced", "ConferencesAudioBufferCutOff")
    end
    def main
        make_window
        load_general
        load_interface
        load_main_window
        load_voice
        load_clock
        load_soundcards
        load_ii
        load_advanced
        Programs::Extensions.render_settings(self) if defined?(Programs::Extensions)
        @form.focus
        loop do
          loop_update
          update_speaker_preview
          @form.update
          update_order_setting
          show_category(@form.fields[0].index) if @category!=@form.fields[0].index
          if @form.fields[-3].pressed?
            speak(_("Saved")) if apply_settings
          end
                    if @form.fields[-2].pressed? or (key_pressed?(:key_enter) and !@form.fields[@form.index].is_a?(Button))
            if apply_settings
              alert(_("Saved"))
              $scene=Scene_Main.new
            end
          end
          if key_pressed?(:key_escape) or @form.fields[-1].pressed?
            $scene=Scene_Main.new
          end
          break if $scene!=self
        end
      ensure
        stop_speaker_preview
      end
      end
