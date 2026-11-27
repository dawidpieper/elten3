# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
  @@premiumpackages=[]
  def update_premiumpackages(packages)
    @@premiumpackages=packages if packages.is_a?(Array)
    end
  def holds_premiumpackage(package)
    return false unless Session.logged?
    return @@premiumpackages.include?(package)
    end

    def requires_premiumpackage(package, description = nil)
      return true if holds_premiumpackage(package)
      message = p_("EAPI_Common", "This feature is unavailable with your current account. It is included in the Sponsorship package.")
      text = [message, description].compact.join("\n\n")
      info = EditBox.new(p_("EAPI_Common", "About this feature"), type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine, text: text, quiet: true)
      purchase = Button.new(p_("PremiumPackages", "Buy the Sponsorship package"))
      close = Button.new(_("Close"))
      form = Form.new([info, purchase, close], silent: true, quiet: true)
      form.hide(purchase) unless Session.logged?
      form.cancel_button = close
      close.on(:press) { form.resume }
      buy = false
      purchase.on(:press) do
        buy = true
        form.resume
      end
      form.wait
      Scene_PremiumPackages.new.buy_sponsorship if buy
      false
    end
  end
end
