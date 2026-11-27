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
    def premium_feature_label(label, package)
      return label if !package || holds_premiumpackage(package)
      p_("EAPI_Common", "%{feature} (Sponsorship package)") % {feature: label}
    end

  def holds_premiumpackage(package)
    return false unless Session.logged?
    return @@premiumpackages.include?(package)
    end

    def requires_premiumpackage(package)
      return true if holds_premiumpackage(package)
      package_name=''
      case package
      when "courier"
        package_name=p_("EAPI_Common", "Courier")
when "audiophile"
        package_name=p_("EAPI_Common", "Audiophile")
        when "scribe"
        package_name=p_("EAPI_Common", "Scribe")
when "director"
        package_name=p_("EAPI_Common", "Director")
      end
      confirm(p_("EAPI_Common", "This feature requires the %{package} premium package. Would you like to see the available premium packages?")%{:package=>package_name}) {insert_scene(Scene_PremiumPackages.new)
      }
      return false
      end
  end
end
