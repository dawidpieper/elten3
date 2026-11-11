# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users_AddedMeToContacts
  def initialize(new=false, scene=nil)
    @new=new
    @scene=scene
    end
  def main
    unless Session.logged?
      alert(_("This section is unavailable to guests"))
      $scene=Scene_Main.new
      return
      end
      usr = load_users
      return return_to_previous_scene if usr == nil
      if usr.empty?
        alert(p_("UsersAddedMeToContacts", "No users have added you to their contacts."))
        return return_to_previous_scene
      end
    selt = []
    for i in 0..usr.size - 1
      selt[i] = user_with_status(usr[i])
      end
    header=p_("UsersAddedMeToContacts", "Users who added me to their contact list")
    header="" if @new==true
      @sel = ListBox.new(selt,header: header, index: 0, flags: 0, quiet: false, keys: usr)
      apply_user_status_states(@sel, usr)
      @sel.bind_context{|menu|context(menu)}
    @user = usr
    loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape) or (@new==true and @sel.collapsed?)
        begin
          EltenLink::Contacts.acknowledge_added_me(elten_link)
        rescue EltenLink::Error => e
          Log.warning("Users added me acknowledgement failed: #{e.message}")
        end
        $scene = @scene || Scene_Main.new
        break
      end
      if key_pressed?(:key_enter) and @user.size > 0
                usermenu(@user[@sel.index],false)
        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@user[@sel.index]) if @user.size > 0
menu.option(_("Refresh"), nil, "r") {
refresh
}
end

  def load_users
    EltenLink::Contacts.added_me(elten_link, new_only: @new)
  rescue EltenLink::Error => e
    cancelled = e.code.to_s == "cancelled"
    Log.warning("Users added me list failed: #{e.message}") unless cancelled
    alert(_("Error")) unless cancelled
    nil
  end

  def refresh
    users = load_users
    return @sel.focus if users == nil
    if users.empty?
      alert(p_("UsersAddedMeToContacts", "No users have added you to their contacts."))
      return @sel.focus
    end
    @user = users
    @sel.update_options(@user.map { |user| user_with_status(user) }, keys: @user)
    apply_user_status_states(@sel, @user)
    @sel.focus
  end

  def return_to_previous_scene
    $scene = @scene || Scene_Main.new
  end
end
