# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
# Shows user agreement
#
# @param omit [Boolean] determines whether to allow user to close the window without accepting
    def license(omit=false)
    @license = licensetext
    @rules = _doc('rules')
    @privacypolicy = _doc('privacypolicy')
form = Form.new([
EditBox.new(p_("EAPI_Common", "License agreement"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::MarkDown,text: @license,quiet: true),
EditBox.new(p_("EAPI_Common", "Terms and Conditions"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::MarkDown,text: @rules,quiet: true),
EditBox.new(p_("EAPI_Common", "Privacy Policy"),type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::MarkDown,text: @privacypolicy,quiet: true),
Button.new(p_("EAPI_Common", "I accept Elten license agreement, Terms and Conditions and Privacy Policy")),Button.new(p_("EAPI_Common", "I do not accept, exit"))])
loop do
  loop_update
  form.update
  if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index == 4
    exit
  end
  if (key_pressed?(:key_space) or key_pressed?(:key_enter)) and form.index == 3
    break
  end
  if key_pressed?(:key_escape)
    if omit == true
      break
    else
      if form.index==0 or form.index==1
        form.index+=1
        form.focus
        else
    q = confirm(p_("EAPI_Common", "Do you accept Elten license agreement, terms and conditions and privacy policy?"))
    if q == 0
      exit
    else
      break
      end
    end
    end
    end
  end
end
  end
end
