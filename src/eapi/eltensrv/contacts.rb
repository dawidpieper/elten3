# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def selectcontact
      begin
        contact = EltenLink::Contacts.list(elten_link)
        err = 0
      rescue EltenLink::Error => e
        Log.warning("Select contact list failed: #{e.message}")
        contact = []
        err = e.code.to_i
      end
      case err
      when -1
        alert(_("Database Error"))
        $scene = Scene_Main.new
        return
      when -2
        alert(_("Token expired"))
        $scene = Scene_Loading.new
        return
      end
      if contact.size < 1
        speak(p_("EAPI_Common", "Empty list"))
        speech_wait
      end
      selt = []
      for i in 0..contact.size - 1
        selt[i] = user_with_status(contact[i])
      end
      sel = ListBox.new(selt,header: p_("EAPI_Common", "Select contact"), index: 0, flags: 0, quiet: false)
      apply_user_status_states(sel, contact)
      loop do
        loop_update
        sel.update if contact.size > 0
        if key_pressed?(:key_escape)
          loop_update
          $focus = true
          return(nil)
        end
        if key_pressed?(:key_enter) and contact.size > 0
          loop_update
          $focus = true
          play_sound("listbox_select")
          return(contact[sel.index])
        end
      end
    end

    # Opens a visiting card of a specified user.
  end
end
