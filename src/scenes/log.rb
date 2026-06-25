# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Log
  def main
    @fields=[
    ListBox.new(["Debug", "Info", "Warning", "Error"], header: p_("Log", "Log level"), index: 1),
    CheckBox.new(p_("Log", "Show event level"), checked: true),
    CheckBox.new(p_("Log","Show event time"), checked: true),
    EditBox.new(p_("Log", "Log"), type: EditBox::Flags::ReadOnly, text: "", quiet: true),
    Button.new(_("Close"))
    ]
    @form=Form.new(@fields)
    loop do
      loop_update
      @form.update
      if @oldlevel!=@form.fields[0].index || @olddsplevel!=@form.fields[1].checked||@olddspdate!=@form.fields[2].checked
        @oldlevel=@form.fields[0].index
        @olddsplevel=@form.fields[1].checked
        @olddspdate=@form.fields[2].checked
        @form.fields[3].set_text(Log.get(1000, @oldlevel-1, @olddsplevel.to_b, @olddspdate.to_b))
      end
      break if key_pressed?(:key_escape) or @form.fields[4].pressed?
    end
    $scene=Scene_Main.new
  end
  end