# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_UserSearch
  def main
    usr=""
    while usr==""
      usr=input_text(p_("UserSearch", "Search users"),flags: 0,text: "",escapable: true)
    end
    if usr==nil
      $scene=Scene_Main.new
      return
      end
    begin
      @results=EltenLink::Users.search(elten_link, usr)
    rescue EltenLink::Error => e
      Log.warning("User search failed: #{e.message}")
  alert(_("Error"))
    $scene=Scene_Main.new
    return
  end
if @results.size==0
  alert(p_("UserSearch", "No match found."))
  $scene=Scene_Main.new
  return
end
selt=[]
@results.each do |r|
  selt.push(user_with_status(r, true, true, "\r\n"))
  end
@sel=ListBox.new(selt,header: p_("UserSearch", "Found items"), index: 0, flags: 0, quiet: false)
apply_user_status_states(@sel, @results)
@sel.bind_context{|menu|context(menu)}
loop do
  loop_update
  @sel.update
  usermenu(@results[@sel.index]) if key_pressed?(:key_enter)
  $scene=Scene_Main.new if key_pressed?(:key_escape)
  break if $scene!=self
  end
end
def context(menu)
menu.useroption(@results[@sel.index])
menu.option(p_("UserSearch", "Search again")) {
initialize
main
}
end
end
