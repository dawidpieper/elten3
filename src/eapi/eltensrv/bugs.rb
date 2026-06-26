# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def bug(getinfo=true,info="")
      loop_update
      if getinfo == true
        info = prompt(p_("EAPI_Common", "Describe the found error"),p_("EAPI_Common", "Send"))
        if info == ""
          return 1
        end
        info += "\r\n|||\r\n\r\n\r\n\r\n\r\n\r\n"
      end
      di = createdebuginfo
      info += di
      begin
        EltenLink::System.bug_report(elten_link, info)
        err = 0
      rescue EltenLink::Error => e
        Log.warning("Bug report failed: #{e.message}")
        err = e.code.to_i
      end
      if err != 0
        alert(_("Error"))
        r = err
      else
        alert(p_("EAPI_Common", "Sent."))
        r = 0
      end
      speech_wait
      return r
    end
  end
end
