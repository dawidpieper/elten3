# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def add_online_monitor(user, permanent:)
      EltenLink::Monitors.add(elten_link, user, permanent: permanent)
      true
    rescue EltenLink::Error => e
      Log.warning("Monitor add failed: #{e.message}")
      alert(_("Error"))
      false
    end

    def delete_online_monitor(user)
      EltenLink::Monitors.delete(elten_link, user)
      true
    rescue EltenLink::Error => e
      Log.warning("Monitor delete failed: #{e.message}")
      alert(_("Error"))
      false
    end
  end
end
