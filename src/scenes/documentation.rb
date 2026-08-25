# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Documentation
  def initialize(docid)
    @docid=docid
  end
  def main
    label=""
    text=""
    case @docid
    when "license"
      label=p_("Documentation", "Licence agreement")
      text= licensetext
      when "rules"
        label=p_("Documentation", "EltenLink terms and conditions")
        text=_doc('rules')
        when "privacypolicy"
          label=p_("Documentation", "EltenLink Privacy Policy")
          text=_doc('privacypolicy')
          when "readme"
            label=p_("Documentation", "Read me")
            text=_doc('readme')
            when "migration24"
              label=p_("Documentation", "Information about migration to Elten version 2.4")
            text=_doc('migration24')
    end
    @form=Form.new([
    edt_text = EditBox.new(label, type: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine|EditBox::Flags::MarkDown, text: text, quiet: true),
    btn_close = Button.new(p_("Documentation", "Close"))
    ], index: 0, silent: false, quiet: true)
    btn_close.on(:press) {@form.resume}
    @form.cancel_button=@form.accept_button=btn_close
    @form.wait
    $scene=Scene_Main.new
  end
end