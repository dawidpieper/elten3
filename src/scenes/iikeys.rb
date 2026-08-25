# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_IIKeys
  def main
    @keys=[]
    add("Up/Down Arrow", p_("IIKeys", "Move up or down through lists"))
    add("Left/Right Arrow", p_("IIKeys", "Change current tab"))
    add("Home/End", p_("IIKeys", "Jump to the first or last item"))
    add("Page up / Page down", p_("IIKeys", "In messages, jump to another conversation"))
    add("Enter", p_("IIKeys", "Activate the selected item"))
    add("Backspace", p_("IIKeys", "Cancel speech and stop the audio that is currently playing"))
    add("Space", p_("IIKeys", "Repeat the currently selected item"))
add("R", p_("IIKeys", "Reply"))
add("K", p_("IIKeys", "Like or dislike a feed message"))
    add("M", p_("IIKeys", "Write a new message"))
    add("F", p_("IIKeys", "Post on a feed"))
show    
loop {
loop_update
@sel.update
break if key_pressed?(:key_escape)
}
$scene=Scene_Main.new
  end
  def add(k, v)
    @keys.push([k, v])
    end
  def show
    keys=ConfigurationValues.invisible_interface_modifier_names(Configuration.iimodifiers)
         hkname=keys.join(" + ")
         selt = @keys.map{|k|
         [hkname+" + "+k[0], k[1]]
         }
         @sel = TableBox.new([nil, nil], selt, index: 0, header: p_("IIKeys", "Invisible Interface keyboard shortcuts"), quiet: false)
  end
  end
