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
    loop do
        loop_update
        sel.update
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
    else
 if sel.index<=5
   return false
 elsif sel.index <= 9
   yield if block_given?
   return true
 else
   result=rand(2)==1
   yield if result && block_given?
   return result
   end
      end
      end
if key_held?(0x10) and key_held?(84) and key_held?(78)
  sel = ListBox.new(["Hmmmm, nie, podziÄ™kujÄ™","CoĹ› ty, oszalaĹ‚eĹ›?","Nie ma mowy","Nigdy w ĹĽyciu","PogiÄ™Ĺ‚o ciÄ™? Jasne, ĹĽe nie","Chyba masz jakieĹ› zwidy jeĹ›li sÄ…dzisz, ĹĽe siÄ™ zgodzÄ™","W sumie, czemu nie","HMMM, kusi, pomyĹ›lmy, no ok, zgoda","Jasne, genialny pomysĹ‚","Jestem za","A ty zdecyduj"],header: "MoĹĽesz siÄ™ szybciej decydowaÄ‡? "+text,index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
  end
      end
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
        if (((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index==1) or (key_pressed?(:key_enter) and key_held?(0x11) and form.index==0)) and form.fields[0].text!=""
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

  def dialog_opened
    return @@dialogopened
    end

  def dialog_mute
    @@dialogvoice_muted_generation=@@dialogvoice_generation
    @@dialogvoice.volume=0 if @@dialogvoice!=nil
    end

      # Opens a dialog
  def dialog_open
            play_sound("dialog_open")
            dialog_close if @@dialogvoice!=nil
            generation = (@@dialogvoice_generation += 1)
        if Configuration.bgsounds==1 && Configuration.soundthemeactivation==1
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
end

# Closes a dialog
def dialog_close
    @@dialogvoice_generation += 1
    if @@dialogvoice != nil
    @@dialogvoice.close
    @@dialogvoice=nil
  end
  play_sound("dialog_close")
  NVDA.braille("") if defined?(NVDA) && NVDA.check
  @@dialogopened=false
  end
   class ConfigEntry
     attr_accessor :id, :name, :value_type, :current_value
     end

  end
end
