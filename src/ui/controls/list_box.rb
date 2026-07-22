# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
    class ListBox < FormField
      # @return [Numeric] a listbox index
attr_accessor :index
# @return [Array] listbox options
attr_reader :options
attr_reader :grayed
attr_reader :item_states
attr_reader :item_audio_urls
attr_reader :selected
attr_accessor :silent
attr_accessor :header
attr_accessor :autosayoption
attr_accessor :limit
# Creates a listbox
#
class Flags
  MultiSelection=1
  LeftRight=2
  Silent=4
  AnyDir=8
  Circular=16
  HotKeys=32
  Tagged=64
  end

  @@audio_entries={}
  ItemStatus = Struct.new(:sound, :speech_prefix, :braille_prefix, keyword_init: true) do
    def key
      [:custom, sound.to_s, speech_prefix.to_s, braille_prefix.to_s]
    end
  end

  def self.item_status(sound, speech_prefix, braille_prefix)
    ItemStatus.new(sound: sound, speech_prefix: speech_prefix, braille_prefix: braille_prefix)
  end

  def self.tick_audio_players
    serial=$input_frame_serial||0
    @@audio_entries.delete_if do |id, entry|
      player=entry[:player]
      if player==nil
        true
      elsif player.completed
        begin
          player.close
        rescue Exception
        end
        entry[:player]=nil
        true
      elsif entry[:last_update_serial].to_i<serial-1
        begin
          player.close
        rescue Exception
        end
        entry[:player]=nil
        true
      else
        false
      end
    end
  end
  #
# @param options [Array] an options list
# @param header [String] a listbox caption
# @param index [Numeric] an initial index
# @param flags [Int] combination of flags
# @param quiet [Boolean] don't read a caption at creation
def initialize(options, header: "", index: 0, flags: 0, quiet: true)
    $lastkeychar=nil
    @border = true
            @border=false if Configuration.listtype == 1 or (flags&Flags::Circular)>0
                                    @lr=((flags & Flags::LeftRight)>0)
            @multi=((flags & Flags::MultiSelection)>0)
@silent=((flags & Flags::Silent)>0)
@anydir=((flags & Flags::AnyDir)>0)
@hk=((flags & Flags::HotKeys)>0)
@tagged=((flags & Flags::Tagged)>0)
@limit=-1
@item_states=[]
@item_audio_urls=[]
@item_audio_entries={}
@late_state_focus_until=0.0
@late_state_focus_index=nil
@late_state_focus_pos=50
@late_state_focus_known_states=[]
@late_state_focus_played={}
@selected_now=false
@requested_select=false
  options=options.deep_dup
        index = 0 if index == nil
           index = 0 if index >= options.size
      index+=options.size if index<0
      self.index = index
self.options=(options)
                                                @selected = []
                                                            for i in 0..@options.size - 1
              @grayed[i] = false if @grayed[i]!=true
              @selected[i] = false
              end
                        header="" if header==nil
                                    @header = text_utf8(header)
                                    @autosayoption=true
                                                  focus if quiet == false
                                        end

            def options=(opts)
              if @options==nil
                @options=[]
                else
              @options.clear
              end
              @grayed||=[]
              @grayed.clear
              @selected.clear if @selected!=nil
              @item_states||=[]
              @item_states.clear
              clear_item_audio
              @hotkeys||={}
              @hotkeys.clear
                                                                                                                                                                                                                                      for i in 0..opts.size - 1
                                                                          gray=false
              if opts[i]!=nil
                ind=nil
if @hk
                opttext=text_utf8(opts[i])
                ind=opttext.index("\&")
    @hotkeys[opttext[ind+1..ind+1].upcase.getbyte(0)] = i if ind!=nil && ind<opttext.length-1
    end
opt=opts[i]
opt=text_utf8(opt).dup if opt.is_a?(String)
opt.delete!("&") if opt.is_a?(String) && ind!=nil
else
  opt=""
  gray=true
end
@options.push(opt)
@item_states[@options.size-1]={}
@grayed[@options.size-1]=true if gray
@selected[@options.size-1]=false if @selected!=nil
end
end

def clear_options
  @options.clear
  @grayed.clear
  @selected.clear if @selected!=nil
  @item_states.clear
  clear_item_audio
  @hotkeys.clear if @hotkeys!=nil
end

def request_select
  @requested_select=true
end

def prepend_options(opts, states=[], audio_urls=[])
  old_options=@options.dup
  old_grayed=@grayed.dup
  old_selected=@selected.dup
  old_states=@item_states.dup
  old_audio_urls=@item_audio_urls.dup
  old_audio_entries=@item_audio_entries.dup
  @item_audio_entries={}
  self.options=opts
  for i in 0...states.size
    set_item_states(i, states[i]) if states[i]!=nil
  end
  for i in 0...audio_urls.size
    set_item_audio(i, audio_urls[i]) if audio_urls[i]!=nil && audio_urls[i].to_s!=""
  end
  @options+=old_options
  @grayed+=old_grayed
  @selected+=old_selected
  @item_states+=old_states
  @item_audio_urls+=old_audio_urls
  audio_offset=opts.size
  old_audio_entries.each{|i, entry|@item_audio_entries[i+audio_offset]=entry}
end

def set_item_states(id, states)
  if states.is_a?(Hash)
    states.each do |status, value|
      set_item_state(id, status, value!=false)
    end
  else
    states.to_a.each do |status|
      set_item_state(id, status)
    end
  end
end

def set_item_state(id, status, value=true)
  return if id==nil || id<0
  return unless status.is_a?(ItemStatus)
  @item_states||=[]
  @item_states[id]||={}
  state=status.key
  if value
    @item_states[id][state]=status
    play_late_focus_state(id, state)
  else
    @item_states[id].delete(state)
  end
end

def set_item_status(id, sound, speech_prefix, braille_prefix)
  status=self.class.item_status(sound, speech_prefix, braille_prefix)
  set_item_state(id, status)
end

def clear_item_state(id, state=nil)
  return if id==nil || id<0 || @item_states==nil || @item_states[id]==nil
  if state==nil
    @item_states[id].clear
  else
    return unless state.is_a?(ItemStatus)
    @item_states[id].delete(state.key)
  end
end

def clear_item_status(id, sound, speech_prefix, braille_prefix)
  clear_item_state(id, self.class.item_status(sound, speech_prefix, braille_prefix))
end

def item_state?(id, state)
  return false if id==nil || id<0 || @item_states==nil || @item_states[id]==nil
  return false unless state.is_a?(ItemStatus)
  @item_states[id].key?(state.key)
end

def item_states_for(id)
  return {} if id==nil || id<0 || @item_states==nil || @item_states[id]==nil
  @item_states[id]
end

def set_item_audio(id, url)
  return if id==nil || id<0
  @item_audio_urls||=[]
  @item_audio_entries||={}
  old=@item_audio_urls[id]
  if url==nil || url.to_s==""
    clear_item_audio(id)
    return
  end
  if old!=nil && old.to_s!=url.to_s
    close_item_audio(id)
  end
  @item_audio_urls[id]=url.to_s
end
alias set_item_audio_url set_item_audio

def clear_item_audio(id=nil)
  @item_audio_urls||=[]
  @item_audio_entries||={}
  if id==nil
    @item_audio_entries.keys.each{|i|close_item_audio(i)}
    @item_audio_urls.clear
  else
    close_item_audio(id)
    @item_audio_urls[id]=nil
  end
end

def item_audio_url(id=self.index)
  return "" if id==nil || id<0 || @item_audio_urls==nil
  @item_audio_urls[id].to_s
end

def item_audio?(id=self.index)
  item_audio_url(id)!=""
end

def close_item_audio(id)
  return if @item_audio_entries==nil || @item_audio_entries[id]==nil
  entry=@item_audio_entries.delete(id)
  @@audio_entries.delete(entry.object_id)
  begin
    entry[:player].close if entry[:player]!=nil
  rescue Exception
  end
end

def item_audio_entry(id=self.index)
  url=item_audio_url(id)
  return nil if url==""
  @item_audio_entries||={}
  entry=@item_audio_entries[id]
  if entry==nil || entry[:url]!=url
    close_item_audio(id) if entry!=nil
    entry={:url=>url, :player=>nil, :last_update_serial=>0}
    @item_audio_entries[id]=entry
  end
  entry
end

def item_audio_player(id=self.index)
  entry=item_audio_entry(id)
  return nil if entry==nil
  if entry[:player]==nil || entry[:player].completed
    begin
      entry[:player].close if entry[:player]!=nil
    rescue Exception
    end
    entry[:player]=Player.new(entry[:url], label: @header, autoplay: false, quiet: true, stream: nil, lazy: true)
  end
  entry[:player]
end

def mark_item_audio_active(id=self.index)
  entry=item_audio_entry(id)
  return if entry==nil
  entry[:last_update_serial]=($input_frame_serial||0)+1
  @@audio_entries[entry.object_id]=entry if entry[:player]!=nil
end

def pause_item_audio(id)
  entry=@item_audio_entries[id] if @item_audio_entries!=nil
  return if entry==nil || entry[:player]==nil
  entry[:player].pause if entry[:player].respond_to?(:pause) && !entry[:player].paused?
end

def pause_other_item_audio(id)
  return if @item_audio_entries==nil
  @item_audio_entries.keys.each do |i|
    pause_item_audio(i) if i!=id
  end
end

def close_other_item_audio(id)
  return if @item_audio_entries==nil
  @item_audio_entries.keys.dup.each do |i|
    close_item_audio(i) if i!=id
  end
end

def play_item_audio(id=self.index)
  return if id==nil || id<0 || hidden?(id) || item_audio_url(id)==""
  close_other_item_audio(id)
  player=item_audio_player(id)
  return if player==nil
  mark_item_audio_active(id)
  player.play if player.paused?
end

def toggle_item_audio(id=self.index)
  return false if id==nil || id<0 || hidden?(id) || item_audio_url(id)==""
  player=item_audio_player(id)
  return false if player==nil
  mark_item_audio_active(id)
  if player.paused?
    close_other_item_audio(id)
    player.play
  else
    player.pause if player.respond_to?(:pause)
  end
  true
end

def ordered_item_state_keys(id)
  item_states_for(id).keys
end

def remember_late_focus_states(pos)
  @late_state_focus_until=Time.now.to_f+0.75
  @late_state_focus_index=self.index
  @late_state_focus_pos=lpos
  @late_state_focus_known_states=item_states_for(self.index).keys
  @late_state_focus_played={}
end

def play_late_focus_state(id, state)
  return if @late_state_focus_until==nil || Time.now.to_f>@late_state_focus_until
  return if id!=@late_state_focus_index
  return if @late_state_focus_known_states.include?(state)
  return if @late_state_focus_played[state]
  status=item_states_for(id)[state]
  sound=status.sound if status!=nil
  play_sound(sound, volume: 100, pitch: 100, pan: @late_state_focus_pos) if sound!=nil
  @late_state_focus_played[state]=true
end

def play_item_states(id, pos=lpos)
  states=item_states_for(id)
  ordered_item_state_keys(id).each do |state|
    sound=states[state].sound if states[state]!=nil
    play_sound(sound, volume: 100, pitch: 100, pan: pos) if sound!=nil
  end
end

def option_plain_text(id=self.index, base=nil)
  text_utf8(base==nil ? @options[id] : base).delete("&")
end

def speech_value_prepend(prefix, value)
  return value if prefix==nil || prefix.to_s==""
  value.is_a?(SpeechSequence) ? SpeechSequence.new(prefix.to_s, value) : prefix.to_s+value.to_s
end

def speech_value_append(value, suffix)
  return value if suffix==nil || suffix.to_s==""
  value.is_a?(SpeechSequence) ? SpeechSequence.new(value, suffix.to_s) : value.to_s+suffix.to_s
end

def speech_value_gsub(value, pattern, replacement="")
  return value.gsub(pattern, replacement) if !value.is_a?(SpeechSequence)
  SpeechSequence.new(value.to_s.gsub(pattern, replacement))
end

def speak_item_option(id=self.index, base=nil, prefix="", include_selection=true, include_hotkey=true, play_states=true, pos=lpos)
  return if id==nil || id<0 || hidden?(id)
  play_item_states(id, pos) if play_states
  text=option_speech_text(id, base)
  if include_selection
    text=speech_value_append(text, "\r\n\r\n(#{text_utf8(p_("EAPI_Common", "Ticked"))})") if @selected[id] == true
    text=speech_value_append(text, "\r\n\r\n(#{text_utf8(p_("EAPI_Common", "Unticked"))})") if @selected[id] == false && @multi==true
  end
  if include_hotkey
    ss=false
    for k in @hotkeys.keys
      ss = k if @hotkeys[k] == id
    end
    text=speech_value_append(text, " ("+text_utf8([ss.to_i & 0xff].pack("C"))+")") if ss.is_a?(Integer)
  end
  text=speech_value_prepend(prefix, text)
  text=speech_value_gsub(text, /\[#{Regexp.escape(text_utf8(@tag))}\]/i, "") if @tag!=nil
  lspeak(text)
  play_item_audio(id)
end

def option_speech_text(id=self.index, base=nil)
  raw=base==nil ? @options[id] : base
  o=raw.is_a?(SpeechSequence) ? raw : text_utf8(raw).delete("&")
  states=item_states_for(id)
  prefixes=[]
  if Configuration.soundthemeactivation!=1
    ordered_item_state_keys(id).each do |state|
      prefix=states[state]==nil ? "" : states[state].speech_prefix.to_s.strip
      prefixes.push(prefix) if prefix!=""
    end
  end
  prefix=prefixes.join(" ").strip
  return o if prefix==""
  speech_value_prepend(prefix+" ", o)
end

def option_braille_text(id=self.index, base=nil)
  raw=base==nil ? @options[id] : base
  o=raw.is_a?(SpeechSequence) ? raw.braille_text : text_utf8(raw).delete("&")
  states=item_states_for(id)
  prefixes=[]
  ordered_item_state_keys(id).each do |state|
    prefix=states[state]==nil ? "" : states[state].braille_prefix.to_s.strip
    prefixes.push("[#{prefix}]") if prefix!=""
  end
  ([prefixes.join(" "), o].reject{|part|part==nil || part==""}).join(" ")
end

def value
  self.index
  end

def idle_update_frame?
  return false if @requested_select == true || @run == true
  keyboard_input_idle?
rescue Exception
  false
end

def idle_update
  $activecontrols.push(self) if $activecontrols.is_a?(Array)
  if $focus==true
    $focus=false
    focus
  end
  @selected_now=false
  mark_item_audio_active(self.index) if item_audio?(self.index)
  true
end

            # Update the listbox
    def update
return idle_update if idle_update_frame?
super
@selected_now=false
mark_item_audio_active(self.index) if item_audio?(self.index)
position_action = keyboard_action_pressed?(:list_position, :list_count)
speak((@index+1).to_s) if position_action == :list_position
speak(@options.size.to_s) if position_action == :list_count
    oldindex = self.index
      options = @options
boundary_action = keyboard_action_pressed?(:list_start, :list_end)
if boundary_action == :list_start && !options.empty?
  @run = true
  self.index = 0
  self.index += 1 while hidden?(self.index) == true
elsif boundary_action == :list_end && !options.empty?
  @run = true
  self.index = options.size - 1
  self.index -= 1 while hidden?(self.index) == true
elsif ((@lr and key_pressed?(:key_left)) or (!@lr and key_pressed?(:key_up)) or (@anydir and (key_pressed?(:key_left) or key_pressed?(:key_up)))) and !raw_key_held?(:key_shift) and !raw_key_held?(:key_insert) and !navigation_modifier_held?
  @run = true
  self.index -= 1
        while hidden?(self.index) == true && self.index>=0
    self.index -= 1
  end
    if self.index < 0
    oldindex = -1 if @border == false
    if @border==false
      self.index=@options.size-1
      while hidden?(self.index) == true
      self.index -= 1
    end
      else
    self.index = 0
    while hidden?(self.index) == true
      self.index += 1
    end
    end
  end
  elsif ((@lr and key_pressed?(:key_right)) or (!@lr and key_pressed?(:key_down)) or (@anydir and (key_pressed?(:key_right) or key_pressed?(:key_down)))) and !raw_key_held?(:key_shift) and !raw_key_held?(:key_insert) and !navigation_modifier_held?
@run = true
    self.index += 1
    while hidden?(self.index) == true
    self.index += 1
  end
  if self.index >= options.size
    if @border==false
    oldindex = -1
    self.index = 0
    while hidden?(self.index) == true
      self.index += 1
      end
    else
    self.index = options.size - 1
    while hidden?(self.index) == true
      self.index -= 1
      end
  end
end
end
if key_held?(0x2D) and key_pressed?(:key_up)
  play_item_states(@index)
  lspeak(option_speech_text(@index))
end
  if key_held?(0x10) and (key_pressed?(:key_up) or key_pressed?(:key_down)) and @tagged
    tgs=tags
  ind=(tgs.index(@tag)||-1)+1
        if key_pressed?(:key_up)
      ind-=1
    elsif key_pressed?(:key_down)
      ind+=1
    end
            ind=ind%(tgs.size+1)
              if ind==0
    self.tag=nil
    speak(p_("EAPI_Form", "All tags"))
  else
    self.tag=tgs[ind-1]
        self.index+=1 while hidden?(self.index) and self.index<options.size-1
    self.index-=1 while hidden?(self.index) and self.index>0
    tag=text_utf8(@tag)
    o=text_utf8(options[self.index]).gsub(/\[#{Regexp.escape(tag)}\]/i, "")
    speak(tag+": "+o)
    end
  end
  if key_pressed?(:key_page_up) == true and @lr==false && !modifier_held?(:command)
    if self.index > 14
            for i in 1..15
              self.index-=1
              while hidden?(self.index) == true and self.index>15-i
    self.index -= 1
  end
              end
          else
            self.index = 0
            end
            @run = true
        while hidden?(self.index) == true
    self.index += 1
  end
    end
        if key_pressed?(:key_page_down) == true and @lr==false && !modifier_held?(:command)
       if self.index < (options.size - 15)
            for i in 1..15
              self.index+=1
                  while hidden?(self.index) == true and self.index<@options.size-i
    self.index += 1
  end
              end
          else
            self.index = options.size-1
            end
            @run = true
  while hidden?(self.index) == true and self.index<@options.size
    self.index += 1
  end
        end
        suc = false
        k=getkeychar
                                  if k != "" and k != " "
                                            k=@lastkey+k if @lastkey!=nil and @lastkeytime>Time.now.to_f-0.25 and k!=@lastkey and @lr==false
          @lastkeytime=Time.now.to_f
          @lastkey=k
          i=text_utf8(k).upcase.getbyte(0)
          if @hotkeys[i]==nil and @hotkeys.size<=@options.size/2
                  @run = true
                  j=self.index
                  l=k.chrsize==1?1:0
                  m=false
adr=1
kup=text_utf8(k).upcase
adr=-1 if key_held?(0x10) && kup!=kup.downcase
                  j+=adr*l
loop do
                                        if j>=options.size||j<=-1
                      if !m
                        j=(key_held?(0x10))?(options.size-1):(0)
                        m=true
                      else
                        break
                        end
                        end
          if options[j]!=nil && !hidden?(j) && option_plain_text(j)[0...kup.length].upcase==kup
                    self.index = j
                    break
  end
                    j+=adr
  break if j==self.index
        end
          elsif @hotkeys[i]!=nil and !hidden?(@hotkeys[i])
      @index = @hotkeys[i]
      @selected_now = true
      end
      end
        if @requested_select
      @selected_now = true
      @requested_select = false
    end
        if @selected_now || key_pressed?(:key_enter)
      play_sound("listbox_select") if @silent == false
      trigger(:select, self.index)
    end
    if collapsed?
      trigger(:collapse, self.index)
    end
    if expanded?
      trigger(:expand, self.index)
      trigger(:selectexpand, self.index)
      end
    self.index = 0 if self.index >= options.size
  if self.index == -1
        while hidden?(self.index) == true
    self.index += 1
  end
  end
if self.index >= @options.size
      while hidden?(self.index) == true
    self.index -= 1
    end
  end
  if @run == true
  speech_stop
  speak_item_option(self.index) if @autosayoption!=false
  play_sound("listbox_statechecked", volume: 100, pitch: 100, pan: self.index.to_f/(options.size-1).to_f*100.0) if @selected[self.index] == true
  focus(nil, nil, @header, false)
end
k=k.to_s if k.is_a?(Integer)
    if oldindex != self.index
  self.index = 0 if options.size == 1 or options[self.index] == nil
    play_sound("listbox_focus", volume: 100, pitch: 100, pan: self.index.to_f/(options.size-1).to_f*100.0) if @silent == false
  trigger(:move, self.index)
@run = false
elsif oldindex == self.index and @run == true and (k.chrsize<=1 or (@options[self.index]!=nil and option_plain_text(self.index)[0...k.length].upcase!=text_utf8(k).upcase))
    play_sound("border", volume: 100, pitch: 100, pan: self.index.to_f/(options.size-1).to_f*100.0) if @silent == false
    trigger(:border, self.index)
    @run = false
  end
  if key_pressed?(:key_space) && @multi != true && item_audio?(self.index)
    toggle_item_audio(self.index)
  elsif key_pressed?(:key_space) and @multi == true
    trigger(:multiselection_beforechanged)
    if @selected[@index] == false
      if @limit<=0 || @selected.count(true)<@limit
            @selected[@index] = true
            trigger(:multiselection_selected, @index)
            trigger(:multiselection_changed)
      play_sound("listbox_statechecked", volume: 100, pitch: 100, pan: self.index.to_f/(options.size-1).to_f*100.0)
      alert(p_("EAPI_Form", "Checked") ,false)
    else
      play_sound("border")
      alert(np_("EAPI_Form", "You can heck only %{count} item", "You can check only %{count} items", @limit)%{:count=>@limit})
      end
    else
      @selected[@index] = false
      trigger(:multiselection_unselected, @index)
      trigger(:multiselection_changed)
      play_sound("listbox_stateunchecked", volume: 100, pitch: 100, pan: self.index.to_f/(options.size-1).to_f*100.0)
      alert(p_("EAPI_Form", "Unchecked"), false)
      end
    end
  end


  def say_option
    speak_item_option(self.index) if @options[self.index]!=nil
  end
  alias sayoption say_option

  def lpos
            pos=50
    pos=self.index.to_f/(self.options.size-1).to_f*100.0 if self.options.size>1
    return pos
    end
  def lspeak(text)
        speak(text, pan: lpos)
    end
def foplay(voice)
  play_sound(voice, volume: 100, pitch: 100, pan: lpos)
  end

def focus(index=nil, count=nil, header=@header, spk=true)
  mark_item_audio_active(self.index) if item_audio?(self.index)
  pos=50
    pos=index.to_f/(count-1).to_f*100.0 if index!=nil and count!=nil && count!=0
  if spk && Configuration.controlspresentation!=2
    if @multi==false
  play_sound("listbox_marker", volume: 100, pitch: 100, pan: pos)  if @silent == false
else
  play_sound("listbox_multimarker", volume: 100, pitch: 100, pan: pos)
end
end
              while hidden?(self.index) == true
                            self.index += 1
            end
            if self.index > @options.size - 1
              while hidden?(self.index) == true
              self.index -= 1
              end
              end
            options=@options
            sp=""
            braille_text=""
            remember_late_focus_states(pos) if spk
            if @header!=nil and @header!=""
            sp = text_utf8(header || @header)
            sp+=" (#{text_utf8(p_("EAPI_Form", "Multiselection list"))})" if @multi==true and Configuration.controlspresentation!=1
                            sp+=": " if !" .:?!,".include?(sp[-1..-1] || "")
              sp+=" " if sp[-1..-1]!=" "
              end
            if options.size>0
              if !hidden?(self.index) && self.index>=0
                o=option_speech_text(self.index)
                b=option_braille_text(self.index)
                o=speech_value_append(o, "\r\n\r\n(#{text_utf8(p_("EAPI_Common", "Checked"))})") if @selected[self.index] == true
                o=speech_value_append(o, "\r\n\r\n(#{text_utf8(p_("EAPI_Common", "Unchecked"))})") if @selected[self.index] == false && @multi==true
                b += "\r\n\r\n(#{text_utf8(p_("EAPI_Common", "Checked"))})" if @selected[self.index] == true
                b += "\r\n\r\n(#{text_utf8(p_("EAPI_Common", "Unchecked"))})" if @selected[self.index] == false && @multi==true
                ss = false
                for k in @hotkeys.keys
                  ss = k if @hotkeys[k] == self.index
                end
                o=speech_value_append(o, " ("+text_utf8([ss.to_i & 0xff].pack("C"))+")") if ss.is_a?(Integer)
                b += " ("+text_utf8([ss.to_i & 0xff].pack("C"))+")" if ss.is_a?(Integer)
                braille_text=sp+b
                if spk
                  speak_item_option(self.index, nil, sp, true, true, true, lpos)
                  sp=""
                else
                  sp += o.to_s
                end
              end
end
sp += text_utf8(p_("EAPI_Form", "Empty list")) if @options.size==0
braille_text=sp if braille_text==""
lspeak(sp) if spk && sp!=""
NVDA.braille(braille_text) if defined?(NVDA) && NVDA.check
end

# Hides a specified item
#
# @param id [Numeric] the id of an item to hide
    def disable_item(id)
  @grayed[id] = true
  options = @options
  while hidden?(self.index) == true
    self.index += 1
  end
  if self.index >= options.size
    oldindex = -1 if @border == false
    self.index = options.size - 1
    while hidden?(self.index) == true
      self.index -= 1
      end
self.index = 0 if @border == false
  end
end
def enable_item(id)
  @grayed[id]=false
end
def hidden?(id)
  return false if id<0 || id>=@options.size
  r=@grayed[id]==true
  r=true if @tag!=nil and !option_plain_text(id).downcase.include?("["+@tag_downcase+"]")
  return r
end
def tags
  tgs=[]
        @options.each {|t|
tgs+=text_utf8(t).scan(/\[([^[\[\]]]+)\]/).map{|x| x[0].downcase}
  }
 tgs.delete(nil)
  return tgs.uniq
end
def tag=(t)
  @tag=t
  if t==nil
    @tag_downcase=t
  else
    @tag_downcase=t.downcase
    end
  end
def tag
  @tag
  end
  def multiselections
  ar=[]
  for i in 0...@options.size
    ar.push(i) if @selected[i]
    end
  return ar
  end
def selected?
  return ((@selected_now == true || key_pressed?(:key_enter)) && @options.size>0 && self.index>=0 && !hidden?(self.index))
end
def expanded?
  return !key_held?(0x10) && ((@lr && key_pressed?(:key_down)) || (!@lr && key_pressed?(:key_right)))
end
def collapsed?
  return !key_held?(0x10) && ((@lr && key_pressed?(:key_up)) || (!@lr && key_pressed?(:key_left)))
end
def key_processed(k)
  if (@lr==false and (k==:up || k==:down))
    return true
  elsif (@lr==true and (k==:left || k==:right))
    return true
  elsif k.to_s.length==1
    return true
  elsif k==:home || k==:end || k==:pageup || k==:pagedown
    return true
  elsif item_audio?(self.index) && k==:space
    return true
  elsif @multi==true and k==:space
    return true
  else
    return false
    end
  end
  def tips
    tps=[]
        if @multi
      tps.push(p_("EAPI_Form", "Use space to select or unselect items"))
      end
    if @tagged
      tps.push(p_("EAPI_Form", "Use shift with up/down arrows to filter content by tags"))
      end
    tps.push(p_("EAPI_Form", "Press CTRL + up arrow to read item index").sub(/CTRL/i, main_modifier_name))
    tps.push(p_("EAPI_Form", "Press CTRL + down arrow to read count of items").sub(/CTRL/i, main_modifier_name))
    return tps
    end
end

# A button class

  end
end
