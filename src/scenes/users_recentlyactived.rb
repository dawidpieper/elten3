# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users_RecentlyActived
  def main
    begin
      onl = EltenLink::Users.recently_active(elten_link)
    rescue EltenLink::Error => e
      Log.warning("Recently active users list failed: #{e.message}")
      onl = []
      alert(_("Error"))
    end
            selt = []
    for i in 0..onl.size - 1
      selt[i] = user_with_status(onl[i])
      end
    @sel = ListBox.new(selt,header: p_("Users_RecentlyActived", "Recently active users"), index: 0, flags: 0, quiet: false)
        apply_user_status_states(@sel, onl)
        @onl = onl
        @sel.bind_context{|menu|context(menu)}
    loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape)
        $scene = Scene_Main.new
        break
      end
      if key_pressed?(:key_enter)
                usermenu(@onl[@sel.index],false)
        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@onl[@sel.index])
menu.option(_("Refresh"), nil, "r") {
initialize
main
}
end
end
