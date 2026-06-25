# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2022 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users_Sponsors
  def main
    begin
      @users = EltenLink::Admins.users(elten_link, "sponsors")
    rescue EltenLink::Error => e
      Log.warning("Sponsors list failed: #{e.message}")
      @users = []
      alert(_("Error"))
    end
                    selt = @users.map{|u|user_with_status(u)}
    @sel = ListBox.new(selt,header: p_("Users_Sponsors", "Sponsors"), index: 0, flags: 0, quiet: false)
    apply_user_status_states(@sel, @users)
                        @sel.bind_context{|menu|context(menu)}
    loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape)
        $scene = Scene_Main.new
        break
      end
      if key_pressed?(:key_enter)
                usermenu(@users[@sel.index],false)
        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@users[@sel.index])
menu.option(_("Refresh"), nil, "r") {
main
}
end
end
