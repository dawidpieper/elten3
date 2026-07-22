# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
    private
# Controls and forms related class

    def keyevents
      k=[]
      ks = {
65=>"a", 66=>"b", 67=>"c", 68=>"d", 69=>"e", 70=>"f", 71=>"g", 72=>"h", 73=>"i", 74=>"j",
75=>"k", 76=>"l", 77=>"m", 78=>"n", 79=>"o", 80=>"p", 81=>"q", 82=>"r", 83=>"s", 84=>"t",
85=>"u", 86=>"v", 87=>"w", 88=>"x", 89=>"y", 90=>"z",
48=>"0", 49=>"1", 50=>"2", 51=>"3", 52=>"4", 53=>"5", 54=>"6", 55=>"7", 56=>"8", 57=>"9",
32=>"space",
8=>"backspace", 9=>"tab", 13=>"enter",
0x10=>"shift", 0x11=>"control", 0x12=>"alt", 0x1B=>"escape",
0x21=>"pageup", 0x22=>"pagedown", 0x23=>"end", 0x24=>"home", 0x2D=>"insert", 0x2E=>"delete",
0xBC=>"comma", 0xBD=>"minus", 0xBE=>"period",
0x25=>"left", 0x26=>"up", 0x27=>"right", 0x28=>"down"
}
     for e in ks.keys
       k.push([("key_"+ks[e]).to_sym, ks[e].to_sym]) if key_pressed?(e)
       k.push([("keyr_"+ks[e]).to_sym, ks[e].to_sym]) if key_held?(e)
       k.push([("keyup_"+ks[e]).to_sym, ks[e].to_sym]) if key_released?(e)
       end
      return k
      end

      class FormBase
        attr_accessor :header
        def params
          @params||={}
          @params
          end
        def on(event, time=0, getparams=false, &block)
      @events||=[]
      @events.push([event,time,0,getparams,block])
    end
    def trigger(event, *params)
      return if @events==nil
      @events.each {|e|
if e[0]==event and e[2]<=Time.now.to_f-e[1]
e[2]=Time.now.to_f
a=params
a||=[]
a.insert(0, params) if e[3]==true
e[4].call(a)
end
}
    end
    def wait
      if @updated==true || @quiet==true
      @playmarker=false
            play_sound("form_marker")
      focus
      end
      @wait=true
      while @wait==true
        loop_update
        self.update
        end
    end
    def resume
      @wait=false
      loop_update
    end
    def disable_menu
      @disable_menu=true
    end
        def enable_menu
      @disable_menu=false
    end
    def menu_enabled?
      @disable_menu!=true
    end
    def disable_contextinglobal
      @disable_contextinglobal=true
    end
        def enable_contextinglobal
      @disable_contextinglobal=false
    end
    def contextinglobal_enabled?
      @disable_contextinglobal!=true
      end
                 def bind_context(h="", &b)
                                  @contexts||=[]
               @contexts.push([b, h])
             end
             def hascontext
               return false if @contexts==nil
               return @contexts.size>0
               end
    def context(menu, submenu=true)
      return if submenu && @disable_contextinglobal==true
      @contexts||=[]
      @contexts.each{|c|
      s=c[1]
      s=@header if s=="" and @header.is_a?(String)
      if s==""
        s=_("Context menu")
      else
        s+=" ("+_("Context menu")+")"
        end
      if submenu
      menu.submenu(s) {|m|
      c[0].call(m)
      }
    else
      c[0].call(menu)
      end
      }
      end
        def keyboard_idle_frame?
          keyboard_input_idle?
        rescue Exception
          false
        end

        def update(*arg)
      if @events!=nil && @events.size>0 && !keyboard_idle_frame?
        keyevents.each {|a| trigger(a[0], raw_key_held?(:key_shift), modifier_held?(:main_modifier), modifier_held?(:option)) if !key_processed(a[1])}
      end
      $activecontrols.push(self) if $activecontrols.is_a?(Array)
    end
    def focus(index=nil,count=nil)
    end
    def blur
    end
    def key_processed(k)
      return false
    end
    def add_tip(tip)
      @customtips||=[]
      @customtips.push(tip)
      end
def get_tips
  tps=[]
  if @customtips!=nil
  tps=@customtips
end
ti=tips
if ti!=nil
  tps+=ti
  end
return tps
  end
    def tips
      return []
      end
    end

class FormTimer
  attr_reader :time, :repeat, :starttime
  def initialize(time, repeat: false, autostart: true, &action)
    @time, @repeat = time, repeat
    @starttime=nil
    @completed=false
    @action=action
    start if autostart
  end
  def start
    @starttime=Time.now.to_f
    @completed=false
  end
  def stop
    @starttime=nil
  end
  def update
    return if @starttime==nil || @completed==true
    if Time.now.to_f-@starttime>=@time
      @action.call if @completed==false && @action!=nil
      @completed=true
      @starttime=nil
      start if repeat
      end
    end
  end

    # A form
    class Form < FormBase
      # @return   [Numeric] a form index
      attr_reader :index
      # @return [Array] an array of form fields
        attr_accessor :fields
        attr_accessor :cancel_button, :accept_button
        # Creates a form
        #
        # @param fields [Array] an array of form fields
        # @param index [Numeric] the initial index
        def initialize(fields=[], index: 0, silent: false, quiet: false)
          @fields = fields
          @index = index
          @silent=silent
          @hidden=[]
          if @fields[@index].is_a?(Array)
            if @fields[@index][0] == 0
              @fields[@index] = EditBox.new(@fields[@index][1], type: @fields[@index][2], text: @fields[@index][3], quiet: false, init: @fields[@index][4])
            end
            end
          if @fields[@index]!=nil && quiet==false
            @fields[@index].trigger(:before_focus)
            @fields[@index].focus(@index, @fields.size)
            @fields[@index].trigger(:focus)
          end
          @timers=[]
          @playmarker=false
          @playmarker=true if @silent==false
          @updated=false
          @quiet=quiet
          loop_update
        end

        # Updates a form
        def update
          @updated=true
          if @playmarker==true
            @playmarker=false
            play_sound("form_marker")
            end
          super
          if $focus==true
            focus
            $focus=false
            end
          @index-=1 while (@fields[@index]==nil or @hidden[@index]==true) and @index>0
      @index+=1 while (@fields[@index]==nil or @hidden[@index]==true) and @index<@fields.size-1
                oldindex=@index
      if key_pressed?(0x09) == true
                                        speech_stop
            if key_held?(0x10) == false and @fields[@index].subindex==@fields[@index].maxsubindex
              ind=@index
              @index += 1
              while (@fields[@index] == nil or @hidden[@index]==true) and @index<@fields.size
                @index+=1
              end
              if @index >= @fields.size
                if Configuration.roundupforms==0
                @index=ind
                trigger(:border, @index)
                play_sound("border", volume: 100, pitch: 100, pan: @index.to_f/(@fields.size-1).to_f*100.0)
              else
                @index = 0
              while (@fields[@index] == nil or @hidden[@index]==true) and @index<@fields.size
                @index+=1
              end
                end
            end
          elsif key_held?(0x10) and @fields[@index].subindex==0
ind=@index
            @index-=1
            while @fields[@index]==nil or @hidden[@index]==true
              @index-=1
              end
            if @index < 0
                            if Configuration.roundupforms==0
              @index = ind
              trigger(:border, @index)
                          play_sound("border", volume: 100, pitch: 100, pan: @index.to_f/(@fields.size-1).to_f*100.0)
                        else
                          @index=@fields.size-1
            while @fields[@index]==nil or @hidden[@index]==true
              @index-=1
            end
            @index=ind if @index<0
                          end
                                      end
          end
          if @fields[@index].is_a?(Array)
            if @fields[@index][0] == 0
@fields[@index] = EditBox.new(@fields[@index][1],type: @fields[@index][2],text: @fields[@index][3],quiet: false,init: @fields[@index][4])
            end
          end
          @fields[oldindex].trigger(:blur)
          @fields[oldindex].blur
          @fields[@index].trigger(:before_focus)
            @fields[@index].focus(@index, @fields.size)
            @fields[@index].trigger(:focus)
            trigger(:move, @index)
        else
                    @fields[@index].update
                  end
                  if key_pressed?(:key_escape) && @cancel_button.is_a?(Button)
                    @cancel_button.press
                  end
if @fields[@index]!=nil && @accept_button!=nil && !@fields[@index].is_a?(Button)
  f=@fields[@index]
  if key_pressed?(:key_enter) and (!f.key_processed(:enter) || key_held?(0x10))
    @accept_button.press
    end
  end
  @timers.each{|timer|timer.update}
end
def add_timer(timer, start=true)
  @timers.push(timer) if timer.is_a?(FormTimer)
end
def delete_timer(timer)
  @timers.delete(timer)
  end
                def append(field)
                  @fields.push(field)
                  return field
                end

                def insert(index, field)
                  @fields.insert(index, field)
                end

                def insert_before(sfield, field)
                  f=@fields.index(sfield)||-1
                  @fields.insert(f, field)
                end

                def insert_after(sfield, field)
                  f=@fields.index(sfield)||-2
                  @fields.insert(f+1, field)
                  end

                def index=(ind)
                  ind=@fields.find_index(ind) if ind.is_a?(FormBase)
                  return if !ind.is_a?(Integer)
                  if @fields[@index].is_a?(FormBase)
                  @fields[@index].blur
                  @fields[@index].trigger(:blur)
                end
                @index=ind
                if @fields[@index].is_a?(FormBase)
                  @fields[@index].blur
                  @fields[@index].trigger(:blur)
                end
                  end
                def show_all
                  @hidden=[]
                  end
                def hide(index)
                  index=@fields.find_index(index) if index.is_a?(FormBase)
                  return if !index.is_a?(Integer)
                  @hidden[index]=true
                end
                def show(index)
                  index=@fields.find_index(index) if index.is_a?(FormBase)
                  return if !index.is_a?(Integer)
                  @hidden[index]=false
                  end
                def focus(index=nil,count=nil)
                  if @fields[@index]!=nil
                    @fields[@index].trigger(:before_focus)
                  @fields[@index].focus(@index, @fields.size)
                  @fields[@index].trigger(:focus)
                  end
                end
                def key_processed(k)
                  if k==:tab
                    return true
                  elsif @fields[@index]!=nil
                    return @fields[@index].key_processed(k)
                  else
                    return false
                    end
                  end
                  end

                # Reads a text from user and returns it
                #
                # @param header [String] a window caption
                # @param type [String] the window type
                #  @see Edit
                # @param text [String] an initial text
  def input_text(header="", flags: 0, text: "", escapable: false, permitted_characters: [], denied_characters: [], max_length: 0, move_to_end: false, select_all: false)
    if flags.is_a?(String)
      Log.warning("String flags are no longer supported: "+Kernel.caller.join(" "))
      flags=0
      end
  ro = (flags & EditBox::Flags::ReadOnly)>0
  ro = (flags & EditBox::Flags::ReadOnly)>0
  ml = (flags & EditBox::Flags::MultiLine)>0
  ae = escapable
  dialog_open
  inp = EditBox.new(header, type: flags, text: text, quiet: false)
  inp.max_length = max_length if max_length>0
  if move_to_end
    inp.index=inp.check=text.length
    end
  permitted_characters.each{|c|inp.permitted_characters.push(c)}
  denied_characters.each{|c|inp.denied_characters.push(c)}
  inp.select_all if select_all
  inp.focus
  loop do
loop_update
    inp.update
    submit = keyboard_action_pressed?(:submit)
    break if key_pressed?(:key_enter) and (ml == false or submit != nil)
    if (ro == true or (flags.is_a?(Numeric) and (flags&EditBox::Flags::ReadOnly)>0)) and (key_pressed?(:key_escape) or key_pressed?(:key_alt) or key_pressed?(:key_enter))
      r = ""
  r = nil if key_pressed?(:key_alt)
    r=nil if key_pressed?(0x09) == true and key_held?(0x10) == false
    r=nil if key_pressed?(0x09) == true and key_held?(0x10) == true
    r=nil if key_pressed?(:key_escape)
    dialog_close
    return r
      break
      end
    if key_pressed?(:key_escape) and ae == true
      dialog_close
      return nil
      break
      end
    end
    r=inp.text
  dialog_close
  loop_update
    return r
  end

  def input_user(header="", escapable: true)
    edt = EditBox.new(header, quiet: true)
    edt.add_tip(p_("EAPI_Form", "Press up or down arrow to select contact"))
    edt.bind_context {|menu|
    menu.option(p_("EAPI_Form", "Select contact")) {
    s=selectcontact
    edt.set_text(s) if s!=nil && s!=""
    edt.focus
    }
    }
    edt.focus
    loop do
      loop_update
      edt.update
      return nil if key_pressed?(:key_escape) and escapable
      if key_pressed?(:key_up) || key_pressed?(:key_down)
s=selectcontact
    edt.set_text(s) if s!=nil && s!=""
    edt.focus
        end
      if key_pressed?(:key_enter)
        usr=edt.text
        usr = finduser(usr) if usr.downcase == finduser(usr).downcase
        if user_exists(usr)
          return usr
        else
          alert(p_("EAPI_Form", "User does not exist"))
          end
        end
      end
    end



  end
end
