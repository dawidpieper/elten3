# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  module QuickActions
            @@actions=nil
            @@hotkey_actions=nil
        @@addprocs = []
    EMPTY_HOTKEY_ACTIONS = [].freeze
    class QuickAction
      attr_accessor :label, :key, :show
      attr_reader :action, :params
      def initialize(action, label="", params=[], key=0, show=true)
        @label, @action, @params, @key, @show = label, action, params, key, show
      end
      def detail
        l=@label
        if @key!=0
          l+=" ("
          l+=KeyboardScheme.modifier_name+"+" if @key.abs>12
          l+="SHIFT+" if @key<0
          l+="F"+(@key.abs%12).to_s
          l+=")"
          end
        return l
        end
      def call
        if @action.is_a?(Symbol)
          call_symbol
          else
        scene=QuickActions.resolve_scene(@action)
        if scene==nil
          alert(_("Error"), false)
          return
        end
        insert_scene(scene.new(*@params)) if !GlobalMenu.opened?
        end
      rescue Exception => e
        Log.error("Quick action failed: #{e.class}: #{e.message}") if defined?(Log)
        alert(_("Error"), false)
      end
      def gettime
        if Configuration.synctime == true
          time = EltenLink::System.server_time(EltenLink.client(self))
                    else
                                            time=Time.now
                                          end
                                          return time
        end
      def call_symbol
        case @action
        when :context
                   $opencontextmenu=true
        when :lastspeech
          speak($speech_lasttext)
          when :copylastspeech
            Clipboard.text=$speech_lasttext
            alert(p_("EAPI_Common", "Last spoken text copied to clipboard"), false)
            when :tips
              tps=get_tips||[]
              text=""
              if tps.size==0
                text=p_("EAPI_Common", "No tips available")
              else
                for i in 1...tps.size
                  next if tps[i].size<2
                  t=tps[i]+""
                  t[0..0]=t[0..0].downcase if t[1..1].downcase==t[1..1].downcase
                  tps[i]=t
                  end
                text=tps.join(",\n")
              end
              alert(text, false)
              when :feed
                if $feedwriting!=true
                  begin
                $feedwriting=true
                  inp = input_text(p_("EAPI_Common", "Message"), flags: 0, text: "", escapable: true, permitted_characters: [], denied_characters: [], max_length: 300)
                loop_update
  feed(inp) if inp!=nil
  $feedwriting=false
  ensure
  $feedwriting=false
  end
  end
  when :alarm
    Scene_Clock.editalarm
    loop_update
  when :tray
            $totray=true if tray_supported?
            when :srsapi
                      nvda = defined?(NVDA) ? NVDA : nil
                      sapi = defined?(Sapi) ? Sapi : nil
                      current_output = SpeechOutput.output_for_voice(Configuration.voice)
                      if nvda != nil && current_output==nvda
      target=readconfig("Voice","Voice","").to_s
      if target=="" || SpeechOutput.output_for_voice(target)==nvda
        voice=SpeechOutput.voices.find{|voice|sapi != nil && voice.output==sapi}
        target=voice.voiceid if voice!=nil
      end
      Configuration.voice=target
          elsif nvda != nil && nvda.usable?
      Configuration.voice="NVDA"
      end
      SpeechOutput.apply_current_voice
  if nvda != nil && SpeechOutput.output_for_voice(Configuration.voice)==nvda
        alert(p_("EAPI_Common", "Using NVDA"), false)
    else
    alert(p_("EAPI_Common", "Using a selected SAPI synthesizer"), false)
  end
        when :date
          alert(gettime.strftime("%Y-%m-%d"), false)
          when :time
            alert(gettime.strftime("%H:%M:%S"), false)
            when :volumedown
                Configuration.volume -= 5 if Configuration.volume > 5
  writeconfig("Interface","MainVolume",Configuration.volume)
  play_sound("listbox_focus")
              when :volumeup
                  Configuration.volume += 5 if Configuration.volume < 100
  writeconfig("Interface","MainVolume",Configuration.volume)
  play_sound("listbox_focus")
  when :donotdisturb
    if $donotdisturb!=true
      $donotdisturb=true
      alert(p_("EAPI_Common", "Do not disturb on"))
    else
      $donotdisturb=false
      alert(p_("EAPI_Common", "Do not disturb off"))
    end
    when :conference_streaming
      if Conference.opened?
        if Conference.streaming?
          Conference.remove_stream
        else
                file=get_file(p_("EAPI_Common", "Select audio file"), path: EltenPath.with_separator(Dirs.documents), save: false, extensions: [".mp3",".wav",".ogg",".mid",".mod",".m4a",".flac",".wma",".opus",".aac",".aiff",".w64"])
      if file!=nil
        Conference.set_stream(file)
      end
    end
  end
  when :conference_setvolumes
    if Conference.opened?
    Scene_Conference.setvolumes
  end
  when :conference_mutemic
    if Conference.opened?
    Conference.muted=!Conference.muted
    if Conference.muted
      speak(p_("EAPI_Common", "Microphone muted"))
    else
      speak(p_("EAPI_Common", "Microphone unmuted"))
      end
    end
  when :conference_pushtotalk
    if Conference.opened?
      Conference.pushtotalk=!Conference.pushtotalk
  LocalConfig["ConferencePushToTalk"]=(Conference.pushtotalk)?(1):(0)
      end
    when :conference_diceroll
      Conference.diceroll(6)
      when :conference_dicerollcustom
      Scene_Conference.custom_diceroll
else
  g = QuickActions.get_proc(action)
if g!=nil
  g.call
else
  alert(_("Error"), false)
end
        end
        end
      end
  class <<self
    def data_path
      EltenPath.join(Dirs.eltendata, "quickactions.json")
    end
    def legacy_data_path
      EltenPath.join(Dirs.eltendata, "quickactions.dat")
    end
        def get
      load_actions if @@actions==nil
            @@actions.dup
    end
    def hotkey_actions(key)
      load_actions if @@actions==nil
      build_hotkey_actions if @@hotkey_actions==nil
      @@hotkey_actions[key.to_i] || EMPTY_HOTKEY_ACTIONS
    end
    def load_actions
      @@actions=[]
      invalidate_hotkey_cache
      if FileTest.exist?(data_path)
        load_json_actions(data_path)
      elsif FileTest.exist?(legacy_data_path)
        migrate_legacy_actions
      else
        load_defaults
      end
    rescue Exception => e
      Log.error("Quick actions load failed: #{e.class}: #{e.message}") if defined?(Log)
      @@actions=[]
      invalidate_hotkey_cache
      load_defaults
      delete_legacy_data_file
      save_actions
    end
    def load_json_actions(path)
      data=JSON.parse(File.binread(path).to_s)
      fail TypeError, "Quick actions JSON must be an array" if !data.is_a?(Array)
      for ac in Array(data)
        action=normalize_record(ac)
        register(*action) if action!=nil
      end
      delete_legacy_data_file
    rescue Exception => e
      Log.error("Quick actions JSON load failed: #{e.class}: #{e.message}") if defined?(Log)
      @@actions=[]
      invalidate_hotkey_cache
      load_defaults
    end
    def migrate_legacy_actions
      begin
        d=load_data(legacy_data_path)
        for ac in Array(d)
          action=normalize_record(ac)
          register(*action) if action!=nil
        end
      rescue Exception => e
        Log.error("Quick actions legacy migration failed: #{e.class}: #{e.message}") if defined?(Log)
        @@actions=[]
        invalidate_hotkey_cache
        load_defaults
      ensure
        delete_legacy_data_file
      end
      save_actions
    end
    def delete_legacy_data_file
      File.delete(legacy_data_path) if FileTest.exist?(legacy_data_path)
    rescue Exception => e
      Log.error("Quick actions legacy delete failed: #{e.class}: #{e.message}") if defined?(Log)
    end
    def reset_defaults
      File.delete(data_path) if FileTest.exist?(data_path)
      delete_legacy_data_file
      @@actions=[]
      invalidate_hotkey_cache
      load_defaults
      true
    end
    def load_defaults
      default_actions.each{|a|
      register(*a)
      }
    end
    def default_actions
      [
      [Scene_Notifications, p_("EAPI_QuickActions", "Notifications"), [], 10],
            [Scene_Contacts, p_("EAPI_QuickActions", "My contacts"), [], 9],
      [Scene_Online, p_("EAPI_QuickActions", "Who is online?"), [], -9],
      [Scene_Messages, p_("EAPI_QuickActions", "Messages"), [], -11],
            [Scene_Forum, p_("EAPI_QuickActions", "Forum")],
      [Scene_Blog, p_("EAPI_QuickActions", "Blogs")],
      [Scene_Conference, p_("EAPI_QuickActions", "Conferences")],
      [Scene_PremiumPackages, p_("EAPI_QuickActions", "Premium packages")],
      ]+predefined_procs(true)
    end
    def register_proc(program, ident, label, proc)
            s=program.to_s+"__"+ident.to_s
      @@addprocs.push([program, s.to_sym, label, proc])
      end
    def unregister_program(program)
      prefix=program.to_s+"__"
      @@addprocs.delete_if{|proc| proc[0]==program}
      if @@actions!=nil
        @@actions.delete_if{|action| action.action.is_a?(Symbol) && action.action.to_s.start_with?(prefix)}
        invalidate_hotkey_cache
      end
    end
    def predefined_procs(defaults=false)
            a=[
                    [:tips, p_("EAPI_QuickActions", "Read tips on the current control"), [], 1, false],
            [:context, p_("EAPI_QuickActions", "Open context menu"), [], -10, false],
            [:time, p_("EAPI_QuickActions", "Say time"), [], 8, false],
      [:date, p_("EAPI_QuickActions", "Say date"), [], -8, false],
      [:lastspeech, p_("EAPI_QuickActions", "Speak last text"), [], 11, false],
      [:tray, p_("EAPI_QuickActions", "Minimize Elten to tray"), [], 3, false],
      [:srsapi, p_("EAPI_QuickActions", "Switch voice output between NVDA and Sapi5"), [], -1, false],
      [:volumedown, p_("EAPI_QuickActions", "Volume down"), [], 5, false],
      [:volumeup, p_("EAPI_QuickActions", "Volume up"), [], 6, false],
      [:donotdisturb, p_("EAPI_QuickActions", "Switch \"Do not disturb\" mode"), [], -2, false],
      [:feed, p_("EAPI_QuickActions", "Publish to a feed"), [], 4, false],
      ]
      a.delete_if{|action| action[0]==:tray} if !tray_supported?
      a.delete_if{|action| action[0]==:srsapi} if !defined?(NVDA) && !defined?(Sapi)
      if defaults!=true
        a+=[
[:copylastspeech, p_("EAPI_QuickActions", "Copy last spoken text to clipboard"), [], 0, false],
[:conference_streaming, p_("EAPI_QuickActions", "Conferences: stream audio file"), [], 0, false],
[:conference_setvolumes, p_("EAPI_QuickActions", "Conferences: set volumes"), [], 0, false],
[:conference_mutemic, p_("EAPI_QuickActions", "Conferences: mute microphone"), [], 0, false],
[:conference_pushtotalk, p_("EAPI_QuickActions", "Conferences: switch push to talk"), [], 0, false],
[:conference_diceroll, p_("EAPI_QuickActions", "Conferences: roll a 6-sided dice"), [], 0, false],
[:conference_dicerollcustom, p_("EAPI_QuickActions", "Conferences: roll a custom dice"), [], 0, false],
[:alarm, p_("EAPI_QuickActions", "Add alarm"), [], 0, false],
        ]
        for ac in @@addprocs
          a.push([ac[1], ac[2]])
          end
        end
      return a
      end
    def register(scene, label="", params=[], key=0, show=true)
      return if scene == :tray && !tray_supported?
      @@actions=[] if @@actions==nil
      action=QuickAction.new(scene, label, params, key, show)
      @@actions.push(action)
      invalidate_hotkey_cache
      action
    end
    def create(scene, label="", params=[], key=0, show=true)
      load_actions if @@actions==nil
      action=register(scene, label, params, key, show)
      return false if action==nil
      return true if save_actions
      @@actions.delete(action)
      invalidate_hotkey_cache
      false
    end
    def delete(index)
      index=normalize_index(index)
      return false if index==nil
      action=@@actions.delete_at(index)
      invalidate_hotkey_cache
      return true if save_actions
      @@actions.insert(index, action)
      invalidate_hotkey_cache
      false
    end
    def rename(index, label)
      index=normalize_index(index)
      return false if index==nil
      old=@@actions[index].label
      @@actions[index].label=label
      return true if save_actions
      @@actions[index].label=old
      false
    end
    def rekey(index, key)
      index=normalize_index(index)
      return false if index==nil
      old=@@actions[index].key
      @@actions[index].key=key
      invalidate_hotkey_cache
      return true if save_actions
      @@actions[index].key=old
      invalidate_hotkey_cache
      false
    end
    def reshow(index, show)
      index=normalize_index(index)
      return false if index==nil
      old=@@actions[index].show
      @@actions[index].show=show
      return true if save_actions
      @@actions[index].show=old
      false
      end
    def up(index)
      index=normalize_index(index)
      return false if index==nil || index<=0
      @@actions[index-1], @@actions[index] = @@actions[index], @@actions[index-1]
      invalidate_hotkey_cache
      return true if save_actions
      @@actions[index-1], @@actions[index] = @@actions[index], @@actions[index-1]
      invalidate_hotkey_cache
      false
    end
    def down(index)
      index=normalize_index(index)
      return false if index==nil || index>=@@actions.size-1
            @@actions[index+1], @@actions[index] = @@actions[index], @@actions[index+1]
      invalidate_hotkey_cache
      return true if save_actions
      @@actions[index+1], @@actions[index] = @@actions[index], @@actions[index+1]
      invalidate_hotkey_cache
      false
      end
    def save_actions
      a=generate_struct
      path=data_path
      if a==default_struct
        File.delete(path) if FileTest.exist?(path)
        return true
      end
      tmp="#{path}.tmp-#{$$}-#{Thread.current.object_id}"
      File.binwrite(tmp, JSON.pretty_generate(a))
      File.delete(path) if FileTest.exist?(path)
      File.rename(tmp, path)
      true
    rescue Exception => e
      Log.error("Quick actions save failed: #{e.class}: #{e.message}") if defined?(Log)
      false
    ensure
      File.delete(tmp) if tmp!=nil && FileTest.exist?(tmp) rescue nil
    end
    def default_struct
      default_actions.map{|action| quick_action_struct(QuickAction.new(*action))}.compact
    end
    def generate_struct
      load_actions if @@actions==nil
            a=[]
      for ac in @@actions
        b=quick_action_struct(ac)
        a.push(b) if b!=nil
      end
      return a
      end
    def quick_action_struct(ac)
      action=serialize_action(ac.action)
      return nil if action==nil
      {
        "action"=>action,
        "label"=>ac.label.to_s,
        "params"=>ac.params.is_a?(Array) ? ac.params : [],
        "key"=>ac.key.to_i,
        "show"=>ac.show!=false
      }
    end
    def normalize_record(record)
      if record.is_a?(Hash)
        action=deserialize_action(record["action"])
        label=record["label"].to_s
        params=record["params"].is_a?(Array) ? record["params"] : []
        key=record["key"].to_i
        show=record.key?("show") ? record["show"]!=false : true
      elsif record.is_a?(Array) && record.size>0
        action=deserialize_action(record[0])
        label=record[1].to_s
        params=record[2].is_a?(Array) ? record[2] : []
        key=record.size>3 ? record[3].to_i : 0
        show=record.size>4 ? record[4]!=false : true
      else
        return nil
      end
      return nil if action==nil
      [action, label, params, key, show]
    end
    def deserialize_action(action)
      return action if action.is_a?(Symbol) || action.is_a?(Class)
      action=action.to_s
      return nil if action==""
      if action[0..0]==":"
        action[1..-1].to_sym
      else
        action
      end
    rescue Exception
      nil
    end
    def serialize_action(action)
      return ":"+action.to_s if action.is_a?(Symbol)
      return action.to_s if action.is_a?(Class)
      return action.to_s if action.is_a?(String) && action!=""
      nil
    end
    def resolve_scene(action)
      return action if action.is_a?(Class)
      return nil if action.is_a?(Symbol)
      action=action.to_s
      return nil if action==""
      Object.const_get(action)
    rescue Exception
      nil
    end
    def normalize_index(index)
      load_actions if @@actions==nil
      return nil if index==nil
      index=index.to_i
      return nil if index<0 || index>=@@actions.size
      index
    end
        def get_proc(pr)
      for a in @@addprocs
        return a[3] if a[1]==pr
      end
      return nil
    end
    def build_hotkey_actions
      index={}
      for action in @@actions||[]
        key=action.key.to_i
        next if key==0
        index[key] ||= []
        index[key].push(action)
      end
      index.each_value{|actions| actions.freeze}
      @@hotkey_actions=index.freeze
    end
    def invalidate_hotkey_cache
      @@hotkey_actions=nil
    end
    end
  end
  end
