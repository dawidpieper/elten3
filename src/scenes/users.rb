# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users
  def main
    begin
      usr = EltenLink::Users.list(elten_link)
      err = 0
    rescue EltenLink::Error => e
      Log.warning("Users list failed: #{e.message}")
      usr = []
      err = e.code.to_i
    end
    case err
    when -1
      alert(_("Database Error"))
      $scene = Scene_Main.new
      return
      when -2
        alert(_("Token expired"))
        $scene = Scene_Main.new
        return
        when -3
          alert(_("You haven't permissions to do this"))
          $scene = Scene_Main.new
          return
    end
        selt = []
    for i in 0..usr.size - 1
      selt[i] = user_with_status(usr[i])
      end
    @sel = ListBox.new(selt,header: p_("Users", "List of users"), index: 0, flags: 0, quiet: false)
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
      if key_pressed?(:key_enter)
                usermenu(@usr[@sel.index],false)
                        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@usr[@sel.index])
menu.option(_("Refresh"), nil, "r") {
main
}
end
end
