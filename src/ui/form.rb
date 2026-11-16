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

    class FormRegistration
      def initialize(owner, kind, entry)
        @owner, @kind, @entry = owner, kind, entry
        @mutex = Mutex.new
      end

      def close
        owner, kind, entry = @mutex.synchronize do
          return false if @owner == nil
          current = [@owner, @kind, @entry]
          @owner = @entry = nil
          current
        end
        owner.__send__(:remove_form_registration, kind, entry)
        true
      end

      def closed?
        @mutex.synchronize { @owner == nil }
      end

      private

      def owned_by?(owner, kind)
        @mutex.synchronize { @owner.equal?(owner) && @kind == kind }
      end
    end
    private_constant :FormRegistration

    class FormBindings
      def initialize(owner: nil)
        @resources = Resources::Registry.new
        @mutex = Mutex.new
        @closed = false
        @owner = owner
        owner.manage(self) if owner != nil
      end

      def on(control, event, time=0, getparams=false, &block)
        register { control.__send__(:register_event, event, time, getparams, &block) }
      end

      def context(control, header="", &block)
        register { control.__send__(:register_context, header, &block) }
      end

      def timer(form, interval, repeat: false, &block)
        register { form.__send__(:register_timer, interval, repeat: repeat, &block) }
      end

      def clear
        resources = @mutex.synchronize do
          return 0 if @closed
          current = @resources
          @resources = Resources::Registry.new
          current
        end
        resources.close
      end

      def close
        resources, owner = @mutex.synchronize do
          return 0 if @closed
          @closed = true
          current = [@resources, @owner]
          @owner = nil
          current
        end
        begin
          resources.close
        ensure
          owner.release(self) if owner != nil
        end
      end

      def closed?
        @mutex.synchronize { @closed }
      end

      private

      def register
        resources = @mutex.synchronize do
          raise RuntimeError, "form bindings are closed" if @closed
          @resources
        end
        registration = yield
        begin
          resources.manage(registration)
        rescue Exception
          registration.close
          raise
        end
      end
    end

      class FormBase
        attr_accessor :header
        def params
          @params||={}
          @params
          end
        def on(event, time=0, getparams=false, &block)
      register_event(event, time, getparams, &block)
    end
    def remove_event(registration)
      return false unless registration.is_a?(FormRegistration) && registration.__send__(:owned_by?, self, :event)
      registration.close
    end
    def register_event(event, time, getparams, &block)
      @events||=[]
      entry=[event,time,0,getparams,block]
      @events.push(entry)
      FormRegistration.new(self, :event, entry)
    end
    def remove_form_registration(kind, entry)
      entries=kind==:event ? @events : @contexts
      entry.clear
      entries.delete_if { |item| item.equal?(entry) }
    end
    private :register_event, :remove_form_registration

    def trigger(event, *params)
      return if @events==nil
      @events.dup.each do |entry|
        name, time, last, getparams, block=entry
        next if entry.empty?
        if name==event && last<=Time.now.to_f-time
          entry[2]=Time.now.to_f
          params.insert(0, params) if getparams==true
          block.call(params)
        end
      end
      @events
    end
    def wait
      if @announce_wait!=false && (@updated==true || @quiet==true)
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
    def resume_for_refresh
      @wait=false
    end
    def wait_without_announcement
      previous=@announce_wait
      @announce_wait=false
      @playmarker=false
      wait
    ensure
      @announce_wait=previous
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
      register_context(h, &b)
    end
    def register_context(header="", &block)
      @contexts||=[]
      entry=[block, header]
      @contexts.push(entry)
      FormRegistration.new(self, :context, entry)
    end
    private :register_context

             def hascontext
               return false if @contexts==nil
               return @contexts.size>0
               end
    def context(menu, submenu=true)
      return if submenu && @disable_contextinglobal==true
      @contexts||=[]
      @contexts.dup.each{|c|
      block, s=c
      next if c.empty?
      s=@header if s=="" and @header.is_a?(String)
      if s==""
        s=_("Context menu")
      else
        s+=" ("+_("Context menu")+")"
        end
      if submenu
      menu.submenu(s) {|m|
      block.call(m) unless c.empty?
      }
    else
      block.call(menu)
      end
      }
      @contexts
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
    @starttime=@monotonic_starttime=nil
    @completed=false
    @action=action
    start if autostart
  end
  def start
    @starttime=Time.now.to_f
    @monotonic_starttime=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @completed=false
  end
  def stop
    @starttime=@monotonic_starttime=nil
  end
  def update
    starttime=@monotonic_starttime
    return if starttime==nil || @completed==true
    if Process.clock_gettime(Process::CLOCK_MONOTONIC)-starttime>=@time
      action=@action
      action.call if @completed==false && action!=nil
      return if @monotonic_starttime==nil
      @completed=true
      @starttime=@monotonic_starttime=nil
      start if repeat
      end
    end
  def dispose
    @starttime=@monotonic_starttime=@action=nil
  end
  private :dispose
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
            focus if @fields[@index]!=nil && @hidden[@index]!=true
            $focus=false
            end
          @index-=1 while (@fields[@index]==nil or @hidden[@index]==true) and @index>0
      @index+=1 while (@fields[@index]==nil or @hidden[@index]==true) and @index<@fields.size-1
                oldindex=@index
      if @fields[@index]!=nil && @hidden[@index]!=true
      if key_pressed?(0x09) == true
                                        speech_stop
            if key_held?(0x10) == false and @fields[@index].subindex==@fields[@index].maxsubindex
              ind=@index
              @index += 1
              while (@fields[@index] == nil or @hidden[@index]==true) and @index<@fields.size
                @index+=1
              end
              if @index >= @fields.size
                if Configuration.roundupforms==false
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
                            if Configuration.roundupforms==false
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
  update_timers
end
def shortcut_pressed?(key, shift: false, first: false)
  return false unless $activecontrols.is_a?(Array) && $activecontrols.include?(self)
  main_shortcut_pressed?(key, shift: shift, first: first)
end
def add_timer(timer, start=true)
  @timers.push(timer) if timer.is_a?(FormTimer)
end
def delete_timer(timer)
  @updating_timers.to_a.each { |timers| timers.map! { |item| item.equal?(timer) ? nil : item } }
  @timers.delete(timer)
  end

def register_timer(interval, repeat: false, &block)
  timer=FormTimer.new(interval, repeat: repeat, &block)
  registration=FormRegistration.new(self, :timer, timer)
  begin
    add_timer(timer)
  rescue Exception
    registration.close
    raise
  end
  registration
end

def update_timers
  return @timers if @timers.empty?
  timers=@timers.dup
  (@updating_timers||=[]) << timers
  begin
    timers.each { |timer| timer.update if timer != nil }
    @timers
  ensure
    @updating_timers.pop
  end
end

def remove_form_registration(kind, entry)
  return super unless kind==:timer
  entry.__send__(:dispose)
  delete_timer(entry)
end
private :register_timer, :update_timers, :remove_form_registration
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

def replace_fields(fields, fallback: :nearest)
  raise ArgumentError, "fallback must be :nearest or :first" unless [:nearest, :first].include?(fallback)
  unless fields.is_a?(Array) && fields.all? { |field| field.nil? || field.is_a?(FormBase) }
    raise ArgumentError, "fields must contain controls or nil"
  end
  hidden={}.compare_by_identity
  @fields.each_with_index { |field, index| hidden[field]=@hidden[index]==true if !field.nil? }
  current=@fields[@index]
  new_hidden=fields.map { |field| hidden[field]==true }
  available=fields.each_index.select { |index| !fields[index].nil? && !new_hidden[index] }
  index=available.find { |index| fields[index].equal?(current) }
  index||=if fallback==:first
    available.first
  else
    available.min_by { |index| [(index-@index.to_i).abs, -index] }
  end
  target=index==nil ? nil : fields[index]
  @fields.replace(fields)
  @hidden.replace(new_hidden)
  @index=index || 0
  unless current.equal?(target)
    if !current.nil?
      current.trigger(:blur)
      current.blur
    end
    if !target.nil?
      focus
      trigger(:move, @index)
    end
  end
  self
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
  def input_text(header="", flags: 0, text: "", escapable: false, permitted_characters: [], denied_characters: [], max_length: 0, move_to_end: false, select_all: false, character_counter: false)
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
  inp.add_tip(p_("EAPI_Form", "Press Tab to check the number of entered characters")) if character_counter
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
    if character_counter && key_pressed?(0x09)
      speak(p_("EAPI_Form", "%{count} of %{maximum} characters") % {:count=>inp.text.chrsize, :maximum=>max_length})
    end
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
    edt.add_tip(p_("EAPI_Form", "Press the Up or Down Arrow key to select a contact"))
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
          alert(p_("EAPI_Form", "The user does not exist"))
          end
        end
      end
    end



  end
end
