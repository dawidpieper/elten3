# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Notes
  def main(index=0)
    unless Session.logged?
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
  for n in @notes
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
menu.option(p_("Notes", "Share"), nil, "n") {
  share(note, shares)
  @form.fields[2].options = shares.dup
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
    EltenWindow.take_character(true) if defined?(EltenWindow) && EltenWindow.respond_to?(:take_character)
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
            speak(p_("Notes", "You are no longer sharing this note with %{user}")%{:user=>user})
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
  def share(note, shares)
    users = EltenAPI::Tasks.run(title: p_("Notes", "Loading contacts")) do
      EltenLink::Contacts.list(EltenLink::Client.new)
    end
    excluded = ([note.author] + shares).map { |user| user.to_s.downcase }
    unconfirmed = []
    users = users.uniq { |user| user.downcase }.reject { |user| excluded.include?(user.downcase) }
    list = ListBox.new(users.dup, header: p_("Notes", "Who do you want to share this note with?"), flags: ListBox::Flags::MultiSelection)
    add = Button.new(p_("Notes", "Add another user"))
    send = Button.new(p_("Notes", "Share"))
    cancel = Button.new(_("Cancel"))
    form = Form.new([list, add, send, cancel])
    form.accept_button = send
    form.cancel_button = cancel
    form.hide(send)
    list.on(:multiselection_changed) { list.multiselections.empty? ? form.hide(send) : form.show(send) }
    add.on(:press) do
      name = input_text(p_("Notes", "User name"), flags: 0, escapable: true)
      next if name == nil || name.strip.empty?
      begin
        user = EltenAPI::Tasks.run(title: p_("Notes", "Finding user")) do
          EltenLink::Users.search(EltenLink::Client.new, name.strip).find { |candidate| candidate.casecmp?(name.strip) }
        end
        if user == nil
          alert(p_("Notes", "The user cannot be found"))
          next
        end
        if unconfirmed.include?(user.downcase)
          alert(p_("Notes", "Reopen the note to check access before retrying."))
          next
        end
        if excluded.include?(user.downcase)
          alert(p_("Notes", "This user already has access to the note."))
          next
        end
        selected = list.multiselections.map { |index| users[index] }
        index = users.index { |candidate| candidate.casecmp?(user) }
        if index == nil
          users << user
          list.options = users.dup
          selected.each { |candidate| list.selected[users.index(candidate)] = true }
          index = users.size - 1
        end
        list.selected[index] = true
        list.index = index
        form.show(send)
        form.index = 0
        list.focus
      rescue EltenAPI::Tasks::Cancelled
        # Keep the selection when lookup is cancelled.
      rescue EltenLink::Error => error
        alert(_("Error")) unless error.code.to_s == "cancelled"
      end
    end
    send.on(:press) do
      selected = list.multiselections.map { |index| users[index] }
      next if selected.empty?
      result = share_with_users(note, selected)
      result[:shared].each { |user| shares << user unless shares.any? { |existing| existing.casecmp?(user) } }
      # Do not offer an uncertain POST again in this dialog. The server may
      # already have applied it even though its response did not arrive.
      completed = result[:shared] + result[:unknown]
      excluded.concat(result[:shared].map(&:downcase))
      unconfirmed.concat(result[:unknown].map(&:downcase))
      users.reject! { |user| completed.include?(user) }
      remaining = selected - completed
      list.options = users.dup
      remaining.each { |user| list.selected[users.index(user)] = true }
      messages = []
      messages << p_("Notes", "Now sharing with %{users}.") % { users: result[:shared].join(", ") } unless result[:shared].empty?
      messages << p_("Notes", "Could not share with %{users}.") % { users: result[:failed].join(", ") } unless result[:failed].empty?
      messages << p_("Notes", "Sharing could not be confirmed for %{users}. Reopen the note to check access before retrying.") % { users: result[:unknown].join(", ") } unless result[:unknown].empty?
      alert(messages.join("\n")) unless messages.empty?
      if remaining.empty?
        form.resume
      else
        form.index = 0
        list.focus
      end
    end
    cancel.on(:press) { form.resume }
    form.wait
  rescue EltenAPI::Tasks::Cancelled
    nil
  rescue EltenLink::Error => error
    alert(_("Error")) unless error.code.to_s == "cancelled"
  end

  def share_with_users(note, users)
    users = users.uniq { |user| user.downcase }.reject { |user| user.casecmp?(note.author) }
    result = { shared: [], failed: [], unknown: [] }
    pending = nil
    begin
      EltenAPI::Tasks.run(title: p_("Notes", "Sharing note")) do |progress, token|
        client = EltenLink::Client.new
        current = EltenLink::Notes.shares(client, note, cancellation_token: token).map(&:downcase)
        users.each_with_index do |user, index|
          token.raise_if_cancelled!
          begin
            unless current.include?(user.downcase)
              pending = user
              EltenLink::Notes.add_share(client, note, user, cancellation_token: token)
            end
            result[:shared] << user
            pending = nil
          rescue EltenLink::Error => error
            Log.warning("Note share add failed: #{error.message}")
            # A definitive client error can be retried explicitly. A lost or
            # invalid response (or server error) is not proof that sharing failed.
            if error.status.to_i.between?(400, 499) && error.status.to_i != 408
              result[:failed] << user
              pending = nil
            else
              break
            end
          end
          progress.update(index + 1, total: users.size)
        end
      end
    rescue EltenAPI::Tasks::Cancelled
      # Completed shares remain valid; leave unattempted users selected.
    rescue EltenLink::Error => error
      Log.warning("Note share list failed: #{error.message}")
      result[:failed] = users - result[:shared] unless error.code.to_s == "cancelled"
    end
    result[:unknown] << pending if pending != nil && !result[:shared].include?(pending)
    result
  end

def delete(note)
  id=note.id
if note.author==Session.name
  cnf=p_("Notes", "Do you really want to delete %{name}?")%{:name => note.name}
  else
  cnf=p_("Notes", "Do you really want to stop sharing %{name}? It will be deleted from your list of notes.")%{:name => note.name}
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
      if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==3)
        break if (@form.fields[0].text=="" and @form.fields[1].text=="") or confirm(p_("Notes", "Are you sure you want to close this note without saving?"))
      end
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
