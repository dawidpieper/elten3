# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def getstatus(name, onl = true, spn = true)
      info=EltenLink::Users.status_info(elten_link, name, online: onl, sponsor: spn)
      parts=[]
      parts.push(info.text) if info.text.to_s!=""
      parts.reject{|part|part.to_s==""}.join(". ")
    rescue EltenLink::Error => e
      Log.warning("Status lookup failed: #{e.message}")
      alert(_("Error"))
      $scene = Scene_Main.new
      ""
    end

    def getstatusinfo(name, onl = true, spn = true)
      EltenLink::Users.status_info(elten_link, name, online: onl, sponsor: spn)
    rescue EltenLink::Error => e
      Log.warning("Status lookup failed: #{e.message}")
      EltenLink::UserStatus.new(text: "", online: false, sponsor: false)
    end

    def user_with_status(name, onl = true, spn = true, separator = " ", label = nil)
      info=getstatusinfo(name, onl, spn)
      parts=[(label || name).to_s, separator.to_s]
      parts << SpeechCommands::SoundCommand.new("user_online", " "+p_("EAPI_Speech", "Online")+" ", "(online: ", immediate: true) if onl && info.online
      parts << SpeechCommands::SoundCommand.new("user_sponsor", " "+p_("EAPI_Speech", "Sponsor")+" ", "(sponsor!)", immediate: true) if spn && info.sponsor
      parts << info.text.to_s if info.text.to_s!=""
      SpeechSequence.new(parts)
    end

    def user_status_item_states(user_or_info, onl = true, spn = true)
      info = user_or_info.is_a?(EltenLink::UserStatus) ? user_or_info : getstatusinfo(user_or_info, onl, spn)
      states = []
      states << EltenAPI::Controls::ListBox.item_status("user_online", p_("EAPI_Speech", "Online"), p_("EAPI_Speech", "Online")) if info.online
      states << EltenAPI::Controls::ListBox.item_status("user_sponsor", p_("EAPI_Speech", "Sponsor"), p_("EAPI_Speech", "Sponsor")) if info.sponsor
      states
    end

    def apply_user_status_states(listbox, users, onl = true, spn = true, offset = 0)
      return listbox if listbox == nil || users == nil || !listbox.respond_to?(:set_item_states)
      users.each_with_index do |user, index|
        next if listbox.respond_to?(:options) && listbox.options[index + offset].is_a?(SpeechSequence)
        states = user_status_item_states(user, onl, spn)
        listbox.set_item_states(index + offset, states) if states.size > 0
      end
      listbox
    end

    def setstatus(text)
      EltenLink::Users.set_status(elten_link, text)
    rescue EltenLink::Error => e
      Log.warning("Status update failed: #{e.message}")
      e.code || -1
    end

    def userinfo(user, stateonly = false)
      EltenLink::Users.info(elten_link, user, stateonly: stateonly)
    rescue EltenLink::Error => e
      Log.warning("User info lookup failed: #{e.message}")
      alert(_("Error"))
      -1
    end

    def user_exists(user)
      EltenLink::Users.exists?(elten_link, user)
    rescue EltenLink::Error => e
      Log.warning("User existence lookup failed: #{e.message}")
      alert(_("Error"))
      false
    end

    def signature(user)
      EltenLink::Users.signature(elten_link, user)
    rescue EltenLink::Error => e
      Log.warning("Signature lookup failed: #{e.message}")
      alert(_("Error"))
      ""
    end

    def isbanned(user = Session.name)
      EltenLink::Users.banned?(elten_link, user)
    end

    def finduser(user, type = 0)
      results = EltenLink::Users.search(elten_link, user)
      if results.empty?
        return "" if type <= 2
        return []
      end
      return results[0] || "" if type == 0 || (type == 1 && results.size == 1)
      return results if type == 2
      index = selector(results, header: p_("EAPI_EltenSRV", "Select a user"), start_index: 0, cancel_index: -1)
      index == -1 ? "" : (results[index] || "")
    rescue EltenLink::Error => e
      Log.warning("User search failed: #{e.message}")
      alert(_("Error"))
      type < 2 ? "" : []
    end
  end
end
