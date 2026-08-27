# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module UI
    private
  # Creates a simple dialog with options yes and no and returns the user's decision
#
# @param text [String] a question to ask
# @return [Boolean] returns true if user selected yes, otherwise false.
def confirm(text="")
  text.gsub!("jesteĹ› pewien","jesteĹ› pewna") if Configuration.language=="pl-PL" and Session.gender==0
  dialog_open
  sel = ListBox.new([_("No"),_("Yes")],header: text,index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
  tab_held_since = nil
  easter_egg = false
  loop do
    loop_update
    sel.update
    sel.focus if key_first_pressed?(:key_tab)
    if key_pressed?(:key_escape)
      loop_update
      dialog_close
      return false
    end
    if key_pressed?(:key_enter)
      loop_update
      dialog_close
      if sel.options.size==2
        yield if sel.index==1 and block_given?
        return sel.index==1
      elsif sel.index<=5
        return false
      elsif sel.index<=9
        yield if block_given?
        return true
      else
        result=rand(2)==1
        yield if result && block_given?
        return result
      end
    end

    next if easter_egg

    if !key_held?(:key_tab)
      tab_held_since = nil
    elsif tab_held_since==nil
      tab_held_since = loop_update_time
    elsif loop_update_time-tab_held_since>=3.0
      sel = ListBox.new(
        confirmation_easter_egg_options,
        header: p_("EAPI_UI_Confirmation", "Could you make up your mind a little faster? %{question}") % {question: text},
        index: 0,
        flags: ListBox::Flags::AnyDir,
        quiet: false
      )
      easter_egg = true
    end
  end
end

def confirmation_easter_egg_options
  [
    p_("EAPI_UI_Confirmation", "Hmm... no, thank you."),
    p_("EAPI_UI_Confirmation", "Have you lost your mind?"),
    p_("EAPI_UI_Confirmation", "Not a chance."),
    p_("EAPI_UI_Confirmation", "Not in this lifetime."),
    p_("EAPI_UI_Confirmation", "Have you completely lost it? Of course not."),
    p_("EAPI_UI_Confirmation", "You must be seeing things if you think I'll agree to that."),
    p_("EAPI_UI_Confirmation", "Actually, why not?"),
    p_("EAPI_UI_Confirmation", "Hmm... tempting. All right, I'm in."),
    p_("EAPI_UI_Confirmation", "Absolutely. Brilliant idea!"),
    p_("EAPI_UI_Confirmation", "Count me in."),
    p_("EAPI_UI_Confirmation", "You decide.")
  ]
end

    # Creates a dialog with a listbox and returns the option selected by user
    #
    # @param options [Array] an array of option
    # @param header [String] a window caption
    # @param index [Numeric] an initial index
    # @param escapeindex [Numeric] a value to return when pressed the escape key, if nil, the escape is not supported
    # @param type [Numeric] if 1, the listbox is horizontal
    # @param focus_on_tab [Boolean] whether Tab reads the selector header and current option
    # @return [Numeric] the index of a selected option
    def selector(options, header: "", start_index: 0, cancel_index: nil, flags: 0, border: true, cancel_key: nil, focus_on_tab: true)
      dialog_open
      dis=[]
      for i in 0..options.size-1
        if options[i]==nil
          dis.push(i)
          options[i]=""
        end
      end
      list_flags=flags
      list_flags=EltenAPI::Controls::ListBox::Flags::AnyDir if flags==1
      lsel=EltenAPI::Controls::ListBox.new(options, header: header, index: start_index, flags: list_flags)
      for d in dis
        lsel.disable_item(d)
      end
      lsel.focus
      @cancel=false
      if cancel_key!=nil
        begin
          s=("key_"+cancel_key.to_s).to_sym
          lsel.on(s) {@cancel=true}
        rescue Exception
        end
      end
      loop do
        loop_update
        lsel.update
        lsel.focus if focus_on_tab && !header.to_s.empty? && key_pressed?(:key_tab)
        if key_pressed?(:key_enter)
          dialog_close
          return lsel.index
        end
        if (key_pressed?(:key_escape) or @cancel==true) and cancel_index!=nil
          dialog_close
          loop_update
          return cancel_index
        end
      end
    end

    def display_text(text, header: "", markdown: false, escapable: true)
      flags = EltenAPI::Controls::EditBox::Flags::ReadOnly | EltenAPI::Controls::EditBox::Flags::MultiLine
      flags |= EltenAPI::Controls::EditBox::Flags::MarkDown if markdown == true
      input_text(header, flags: flags, text: text.to_s, escapable: escapable)
    end

    def display_list(options, header: "", start_index: 0, quiet: false, flags: 0, empty_label: nil)
      options = Array(options)
      dialog_open
      begin
        list = EltenAPI::Controls::ListBox.new(
          options,
          index: start_index,
          header: header,
          quiet: quiet,
          flags: flags,
          empty_label: empty_label
        )
        list.focus
        loop do
          loop_update
          list.update
          return options.empty? ? nil : list.index if key_pressed?(:key_enter)
          return nil if key_pressed?(:key_escape) || key_pressed?(:key_alt)
        end
      ensure
        dialog_close
        loop_update
      end
    end

    def display_table(columns, rows, header: "", start_index: 0, quiet: false, flags: 0, empty_label: nil)
      columns = Array(columns)
      rows = Array(rows).map { |row| Array(row) }
      raise ArgumentError, "columns cannot be empty" if columns.empty?
      dialog_open
      begin
        table = EltenAPI::Controls::TableBox.new(
          columns,
          rows,
          index: start_index,
          header: header,
          quiet: quiet,
          flags: flags,
          empty_label: empty_label
        )
        table.focus
        loop do
          loop_update
          table.update
          return rows.empty? ? nil : table.index if key_pressed?(:key_enter)
          return nil if key_pressed?(:key_escape) || key_pressed?(:key_alt)
        end
      ensure
        dialog_close
        loop_update
      end
    end

    def select_action(actions, header: "", start: nil, cancel: nil, flags: 0, cancel_key: nil, focus_on_tab: true)
      entries = if actions.respond_to?(:each_pair)
        actions.map { |key, label| [key, label] }
      else
        Array(actions).map { |entry| entry.is_a?(Array) ? [entry[0], entry[1]] : [entry, entry.to_s] }
      end
      raise ArgumentError, "actions cannot be empty" if entries.empty?
      start_index = if start.is_a?(Integer)
        [[start, 0].max, entries.size - 1].min
      else
        entries.index { |key, _label| key == start } || 0
      end
      cancelled_index = entries.size
      selected = selector(
        entries.map { |_key, label| label },
        header: header,
        start_index: start_index,
        cancel_index: cancelled_index,
        flags: flags,
        cancel_key: cancel_key,
        focus_on_tab: focus_on_tab
      )
      return cancel if selected == nil || selected == cancelled_index
      entry = entries[selected]
      entry == nil ? cancel : entry[0]
    end

    def menuselector(options)
      dis=[]
      for i in 0..options.size-1
        if options[i]==nil
          dis.push(i)
          options[i]=""
        end
      end
      play_sound("menu_open")
      EltenAPI::Controls::Menu.menubg_play if Configuration.bgsounds==true && Configuration.soundthemeactivation==true
      lsel=EltenAPI::Controls::ListBox.new(options, header: "", index: 0, flags: EltenAPI::Controls::ListBox::Flags::AnyDir)
      for d in dis
        lsel.disable_item(d)
      end
      lsel.update
      lsel.focus
      ret=-1
      loop do
        loop_update
        lsel.update
        if key_pressed?(:key_enter)
          ret=lsel.index
          break
        end
        if key_pressed?(:key_alt) or key_pressed?(:key_escape)
          ret=-1
          break
        end
      end
      EltenAPI::Controls::Menu.menubg_close
      play_sound("menu_close")
      loop_update
      ret
    end

    def prompt(header="",confirmation="Ok",cancellation=_("Cancel"))
      form=Form.new([EditBox.new(header,type: EditBox::Flags::MultiLine),Button.new(confirmation),Button.new(cancellation)])
      snd=form.fields[1]
      dialog_open
      loop do
loop_update
if form.fields[0].text=="" and form.fields[1]!=nil
  form.fields[1]=nil
elsif form.fields[0].text!="" and form.fields[1]==nil
  form.fields[1]=snd
  end
        form.update
        if (((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index==1) or (keyboard_action_pressed?(:submit) and form.index==0)) and form.fields[0].text!=""
          dialog_close
          return legacy_line_to_text(form.fields[0].text)
          break
        end
        if ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index==2) or key_pressed?(:key_escape)
          dialog_close
          return ""
          break
          end
        end
      end

      @@waitingvoice=nil
      @@waitingopened=false

      def waiting_opened
        @@waitingopened
        end

    # Opens a waiting dialog
  def waiting(&b)
    snd=getsound("waiting")
    waiting_end if @@waitingvoice!=nil
          if snd!=nil
                          @@waitingvoice = Sound.new(loop: true, stream: snd)
                          @@waitingvoice.volume = Configuration.volume.to_f/150.0
                          @@waitingvoice.play
                          end
                            @@waitingopened = true
                                                      if b!=nil
                            b.call
                            waiting_end
                            end
end

# Closes a waiting dialog
def waiting_end
    if @@waitingvoice != nil
      @@waitingvoice.close
    @@waitingvoice = nil
    end
    @@waitingopened = false
  end

  @@dialogvoice=nil
  @@dialogvoice_generation=0
  @@dialogvoice_muted_generation=nil
  @@dialogopened=false
  @@modal_interaction_depth=0
  @@modal_interaction_started_at=nil
  @@modal_interaction_elapsed=0.0
  @@modal_interaction_mutex=Mutex.new

  def dialog_opened
    return @@dialogopened
    end

  def modal_interaction_elapsed
    now = modal_interaction_time
    @@modal_interaction_mutex.synchronize do
      modal_interaction_elapsed_at(now)
    end
  end

  def modal_interaction_adjusted_time
    now = modal_interaction_time
    @@modal_interaction_mutex.synchronize do
      now - modal_interaction_elapsed_at(now)
    end
  end

  def dialog_mute
    @@dialogvoice_muted_generation=@@dialogvoice_generation
    @@dialogvoice.volume=0 if @@dialogvoice!=nil
    end

      # Opens a dialog
  def dialog_open
    modal_interaction_open
    opened = false
    begin
      play_sound("dialog_open")
      close_dialog_output if @@dialogvoice!=nil
      generation = (@@dialogvoice_generation += 1)
      if Configuration.bgsounds==true && Configuration.soundthemeactivation==true
        snd=getsound("dialog_background")
        if snd!=nil
          Thread.new do
            Thread.current.report_on_exception = false
            begin
              sound = Sound.new(loop: true, stream: snd)
              sound.volume=Configuration.volume.to_f/100.0
              sound.position=0
              if @@dialogvoice_generation == generation
                @@dialogvoice = sound
                sound.volume=0 if @@dialogvoice_muted_generation == generation
                @@dialogvoice.play
              else
                sound.close
              end
            rescue Exception => e
              Log.warning("Dialog background sound failed: #{e.class}: #{e.message}")
            end
          end
        end
      end
      @@dialogopened = true
      opened = true
    ensure
      modal_interaction_close if !opened
    end
  end

# Closes a dialog
def dialog_close
  begin
    close_dialog_output
  ensure
    modal_interaction_close
    @@dialogopened=modal_interaction_active?
  end
end

def close_dialog_output
  @@dialogvoice_generation += 1
  if @@dialogvoice != nil
    @@dialogvoice.close
    @@dialogvoice=nil
  end
  play_sound("dialog_close")
  NVDA.braille("") if defined?(NVDA) && NVDA.check
end

def modal_interaction_open
  now = modal_interaction_time
  @@modal_interaction_mutex.synchronize do
    if @@modal_interaction_depth == 0
      @@modal_interaction_started_at = now
    end
    @@modal_interaction_depth += 1
  end
end

def modal_interaction_close
  now = modal_interaction_time
  @@modal_interaction_mutex.synchronize do
    return if @@modal_interaction_depth <= 0
    @@modal_interaction_depth -= 1
    if @@modal_interaction_depth == 0
      @@modal_interaction_elapsed += now - @@modal_interaction_started_at
      @@modal_interaction_started_at = nil
    end
  end
end

def modal_interaction_active?
  @@modal_interaction_mutex.synchronize { @@modal_interaction_depth > 0 }
end

def modal_interaction_elapsed_at(time)
  elapsed = @@modal_interaction_elapsed
  elapsed += time - @@modal_interaction_started_at if @@modal_interaction_depth > 0
  [elapsed, 0.0].max
end

def modal_interaction_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
   class ConfigEntry
     attr_accessor :id, :name, :value_type, :current_value
     end

  end
end
