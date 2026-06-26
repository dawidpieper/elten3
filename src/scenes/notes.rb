# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Notes
  def main(index=0)
    if Session.name=="guest"
      alert(_("This section is unavailable for guests"))
      $scene=Scene_Main.new
      return
      end
  begin
    @notes = EltenLink::Notes.list(elten_link)
  rescue EltenLink::Error => e
    Log.warning("Notes list failed: #{e.message}")
    alert(_("Error"))
    $scene=Scene_Main.new
    return
    end
  selt=[]
  @notes.each do |n|
    selt.push(n.name+"\r\n#{p_("Notes", "Author")}: "+n.author+"\r\n#{p_("Notes", "Modified")}: "+format_date(n.modified, false, false))
  end
  @sel=ListBox.new(selt,header: p_("Notes", "Notes"), index: index, flags: 0, quiet: false)
  @sel.bind_context{|menu|context(menu)}
  loop do
    loop_update
    @sel.update
    $scene=Scene_Main.new if key_pressed?(:key_escape)
    if key_pressed?(:key_enter) and @notes.size>0
        show(@notes[@sel.index])
        @sel.focus if @refresh!=true
              end
              if @refresh == true
                    @refresh = false
                    main(@sel.index)
                    return
          end
      break if $scene!=self
    end
  end
  def context(menu)
    if @sel.index<@notes.size    
    note=@notes[@sel.index]
    menu.option(p_("Notes", "Read")) {
              show(note)
    }
    menu.option(p_("Notes", "Edit"), nil, "e") {
                show(note,true)
                @sel.focus if @refresh!=true
    }
    if note.author==Session.name
    menu.option(_("Delete"), nil, :del) {
                  delete(note)
    }
    menu.option(p_("Notes", "Rename")) {
    rename(note)
    }
  else
    menu.option(p_("Notes", "Don't share this note"), nil, :del) {
                  delete(note)
    }
  end
  end
    menu.option(p_("Notes", "New note"), nil, "n") {
          $scene=Scene_Notes_New.new
  }
  menu.option(_("Refresh"), nil, "r") {
  main
  }
            end
  def show(note,edit=false)
    id=note.id
    changed=false
    shares=[]
begin
  shares = EltenLink::Notes.shares(elten_link, note)
rescue EltenLink::Error => e
  Log.warning("Notes share list failed: #{e.message}")
    alert(_("Error"))
    return
end
shares.map! { |share| share == Session.name ? note.author : share }
sharest=shares+[]
@fields=[EditBox.new(note.name,type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly,text: note.text,quiet: true),Button.new(p_("Notes", "Edit")),ListBox.new(sharest,header: p_("Notes", "Note shared with")),nil,Button.new(_("Cancel"))]
@fields[0].on(:change) {changed=true}
@form=Form.new(@fields)
@form.bind_context{|menu|
if note.author==Session.name
menu.option(p_("Notes", "Share")) {
        inpt=EditBox.new(p_("Notes", "Who do you want to share this note with?"))
    loop do
      loop_update
      inpt.update
      if key_pressed?(:key_escape)
        dialog_close
        break
        end
      inpt.set_text(selectcontact) if key_pressed?(:key_up) or key_pressed?(:key_down)
      if key_pressed?(:key_enter)
        user=EltenLink.legacy_line_to_text(inpt.text).delete("\r\n")
                user=finduser(user) if finduser(user).upcase==user.upcase
                if user_exists(user) == false
          alert(p_("Notes", "User cannot be found"))
        else
          begin
            EltenLink::Notes.add_share(elten_link, note, user)
          rescue EltenLink::Error => e
            Log.warning("Note share add failed: #{e.message}")
            alert(_("Error"))
          else
            speak(p_("Notes", "From now on you share this note with %{user}")%{:user=>user})
            speech_wait
            shares.push(user)
            sharest=shares
            @form.fields[2].options=sharest
                        break
            end
          end
        end
    end
}
end
}
if edit == true
@form.fields[0].flags=EditBox::Flags::MultiLine
@form.fields[1]=Button.new(_("Save"))
end
@form.fields[3]=Button.new(_("Delete")) if note.author==Session.name
    loop do
  loop_update
  @form.update
  if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==4)
    if changed==false or confirm(p_("Notes", "Are you sure you want to close this note without saving?"))
break
end
    end
  if (((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==1)) or (key_held?(0x11) && !key_held?(0x12) && !key_held?(0x10) && key_pressed?(69))
    if edit == false
    edit=true
    @form.fields[0].flags=EditBox::Flags::MultiLine
    @form.index=0
    @form.fields[0].focus
    @form.fields[1]=Button.new(_("Save"))
  else
    text=@form.fields[0].text
    begin
      EltenLink::Notes.update(elten_link, note, text)
    rescue EltenLink::Error => e
      Log.warning("Note update failed: #{e.message}")
          alert(_("Error"))
    else
          alert(p_("Notes", "The note has been modified."))
          @refresh=true
          break
          end
    end
        end
  if key_pressed?(0x2e) and @form.index==2 and note.author==Session.name and @form.fields[2].index<shares.size
  if confirm(p_("Notes", "Do you want to stop sharing this note with %{user}?")%{:user=>@form.fields[2].options[@form.fields[2].index]})
  user=shares[@form.fields[2].index]
          begin
            EltenLink::Notes.delete_share(elten_link, note, user)
          rescue EltenLink::Error => e
            Log.warning("Note share delete failed: #{e.message}")
            alert(_("Error"))
          else
            speak(p_("Notes", "You no longer share this note with %{user}")%{:user=>user})
                        shares.delete(user)
            sharest=shares
@form.fields[2].index-=1
@form.fields[2].index=0 if @form.fields[2].index<0
            @form.fields[2].options=sharest
            speech_wait
          end
        end
        @form.fields[2].focus
  end
if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==3
  if delete(note) == true
break
else
  @form.fields[3].focus
  end
  end
end
        end
def delete(note)
  id=note.id
if note.author==Session.name
  cnf=p_("Notes", "Do you really want to delete %{name}?")%{:name => note.name}
  else
  cnf=p_("Notes", "Do you really want to end sharing %{name}? It will be deleted from your notes list.")%{:name => note.name}
  end
  if !confirm(cnf)
    return false
  else
    begin
      EltenLink::Notes.delete(elten_link, note)
    rescue EltenLink::Error => e
      Log.warning("Note delete failed: #{e.message}")
      alert(_("Error"))
      return false
else
    alert(p_("Notes", "The note has been deleted."))
    end
    @refresh=true
    return true
        end
      end
      def rename(note)
        name = input_text(p_("Notes", "New note name"), flags: 0, text: note.name, escapable: true)
        if name!=nil and name!=note.name
          begin
            EltenLink::Notes.rename(elten_link, note, name)
          rescue EltenLink::Error => e
            Log.warning("Note rename failed: #{e.message}")
            alert(_("Error"))
          else
            alert(p_("Notes", "The note has been renamed"))
          end
          end
          @refresh=true
        end
        end

class Scene_Notes_New
  def main
    @fields=[EditBox.new(p_("Notes", "note title"),type: 0,text: "",quiet: true),EditBox.new(p_("Notes", "Note content"),type: EditBox::Flags::MultiLine,text: "",quiet: true),Button.new(p_("Notes", "Add")),Button.new(_("Cancel"))]
    @form=Form.new(@fields)
    btn=@form.fields[2]
    loop do
      loop_update
      if (@form.fields[0].text=="" or @form.fields[1].text=="") and @form.fields[2]!=nil
        btn=@form.fields[2]
        @form.fields[2]=nil
      elsif (@form.fields[0].text!="" and @form.fields[1].text!="") and @form.fields[2]==nil
        @form.fields[2]=btn
        end
      @form.update
      break if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==3)
      if ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==2)
        name=@form.fields[0].text
        text=@form.fields[1].text
        begin
          EltenLink::Notes.create(elten_link, name, text)
        rescue EltenLink::Error => e
          Log.warning("Note create failed: #{e.message}")
          alert(_("Error"))
        else
          alert(p_("Notes", "The note has been created"))
          break
          end
        end
    end
    $scene=Scene_Notes.new
  end
  end

class Struct_Note < EltenLink::Note
  def initialize(id=0)
    super(id: id)
  end
end
