# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Version
  def main
    txt = Elten.version.to_s
    txt+="\r\nBuild ID: #{Elten.build_id}" if Elten.build_id.to_s!=""
    txt+="\r\nBuild Date: #{Elten.build_date}" if Elten.build_date.to_s!=""
    txt+="\r\n"
txt+="Copyright (C) 2014-2026 Dawid Pieper\r\nElten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. \r\nElten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details."
    txt+="\r\n\r\n"
    txt+=RUBY_DESCRIPTION+"\r\n"
    txt+="BASS Audio Library "+Bass.version.to_s+" (Copyright (c) 1999-2020 Un4seen Developments Ltd. All rights reserved.)\r\n"
    txt+=Opus.version+"\r\n"
    input_text("ELTEN",flags: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine,text: txt)
    $scene=Scene_Main.new
  end
  private
  def buildversion(file)
    str=getfileversioninfo(file, "FileDescription")
str+=" "
str+=getfileversioninfo(file, "ProductVersion")||""
str+=" ("
str+=getfileversioninfo(file, "LegalCopyright")||""
str+=")"
return str
    end
  end
