# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Users_Sponsors
  def main
    @users = load_users
    return return_to_main if @users == nil
    if @users.empty?
      alert(p_("Users_Sponsors", "No sponsors were found."))
      return return_to_main
    end
                    selt = @users.map{|u|user_with_status(u)}
    @sel = ListBox.new(selt,header: p_("Users_Sponsors", "Sponsors"), index: 0, flags: 0, quiet: false, keys: @users)
    apply_user_status_states(@sel, @users)
                        @sel.bind_context{|menu|context(menu)}
    loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape)
        $scene = Scene_Main.new
        break
      end
      if key_pressed?(:key_enter) and @users.size > 0
                usermenu(@users[@sel.index],false)
        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@users[@sel.index]) if @users.size > 0
menu.option(_("Refresh"), nil, "r") {
refresh
}
end

  def load_users
    EltenLink::Admins.users(elten_link, "sponsors")
  rescue EltenLink::Error => e
    cancelled = e.code.to_s == "cancelled"
    Log.warning("Sponsors list failed: #{e.message}") unless cancelled
    alert(_("Error")) unless cancelled
    nil
  end

  def refresh
    users = load_users
    return @sel.focus if users == nil
    if users.empty?
      alert(p_("Users_Sponsors", "No sponsors were found."))
      return @sel.focus
    end
    @users = users
    @sel.update_options(@users.map { |user| user_with_status(user) }, keys: @users)
    apply_user_status_states(@sel, @users)
    @sel.focus
  end

  def return_to_main
    $scene = Scene_Main.new
  end
end
