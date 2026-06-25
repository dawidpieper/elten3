# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Debug
  def main
    @form=Form.new([EditBox.new(p_("Debug", "A report"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly,text: createdebuginfo),CheckBox.new(p_("Debug", "Report connections to the server"),checked: $netsignal.to_i!=0),Button.new(p_("Debug", "OK"))])
    loop do
      loop_update
      @form.update
      break if key_pressed?(:key_escape)
      if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==2
                $netsignal=@form.fields[1].checked
        break
        end
      end
      $scene=Scene_Main.new
  end
  end
