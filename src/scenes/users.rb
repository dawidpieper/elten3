# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users
  def main
    usr = load_users
    return return_to_main if usr == nil
    if usr.empty?
      alert(p_("Users", "No users were found."))
      return return_to_main
    end
        selt = []
    for i in 0..usr.size - 1
      selt[i] = user_with_status(usr[i])
      end
    @sel = ListBox.new(selt,header: p_("Users", "List of users"), index: 0, flags: 0, quiet: false, keys: usr)
    apply_user_status_states(@sel, usr)
        @usr = usr
    @sel.bind_context{|menu|context(menu)}
    loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape)
        $scene = Scene_Main.new
        break
      end
      if key_pressed?(:key_enter) and @usr.size > 0
                usermenu(@usr[@sel.index],false)
                        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@usr[@sel.index]) if @usr.size > 0
menu.option(_("Refresh"), nil, "r") {
refresh
}
end

  def load_users
    EltenLink::Users.list(elten_link)
  rescue EltenLink::Error => e
    cancelled = e.code.to_s == "cancelled"
    Log.warning("Users list failed: #{e.message}") unless cancelled
    return nil if cancelled
    case e.code.to_i
    when -1
      alert(_("Database Error"))
    when -2
      alert(_("Token expired"))
    when -3
      alert(_("You do not have permission to do this"))
    else
      alert(_("Error"))
    end
    nil
  end

  def refresh
    users = load_users
    return @sel.focus if users == nil
    if users.empty?
      alert(p_("Users", "No users were found."))
      return @sel.focus
    end
    @usr = users
    @sel.update_options(@usr.map { |user| user_with_status(user) }, keys: @usr)
    apply_user_status_states(@sel, @usr)
    @sel.focus
  end

  def return_to_main
    $scene = Scene_Main.new
  end
end
