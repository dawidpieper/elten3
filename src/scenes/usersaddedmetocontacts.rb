# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users_AddedMeToContacts
  def initialize(new=false)
    @new=new
    end
  def main
    if Session.name=="guest"
      alert(_("UsersAddedMeToThis section is unavailable for guests"))
      $scene=Scene_Main.new
      return
      end
      begin
        usr = EltenLink::Contacts.added_me(elten_link, new_only: @new)
      rescue EltenLink::Error => e
        Log.warning("Users added me list failed: #{e.message}")
        usr = []
        alert(_("Error"))
      end
    selt = []
    for i in 0..usr.size - 1
      selt[i] = user_with_status(usr[i])
      end
    header=p_("UsersAddedMeToContacts", "Users who added me to their contacts list")
    header="" if @new==true
      @sel = ListBox.new(selt,header: header, index: 0, flags: 0, quiet: false)
      apply_user_status_states(@sel, usr)
      @sel.bind_context{|menu|context(menu)}
    @user = usr
    loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape)
        begin
          EltenLink::Contacts.acknowledge_added_me(elten_link)
        rescue EltenLink::Error => e
          Log.warning("Users added me acknowledgement failed: #{e.message}")
        end
        if @new==false
        $scene = Scene_Main.new
      else
        $scene=Scene_Notifications.new
        end
        break
      end
      if key_pressed?(:key_enter)
                usermenu(@user[@sel.index],false)
        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@user[@sel.index])
menu.option(_("Refresh"), nil, "r") {
main
}
end
end
