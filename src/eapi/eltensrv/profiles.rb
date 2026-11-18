# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def visitingcard(user=Session.name)
      begin
        card = EltenLink::Profiles.card(elten_link, user)
      rescue EltenLink::Error => e
        if e.code.to_s == "cancelled"
          Log.debug("Visiting card request cancelled")
          return 0
        end
        Log.warning("Visiting card failed: #{e.message}")
        alert(_("Database Error"))
        return -1
      end
      vc = card.visiting_card
      pr = card.profile
      ui = card.info
      dialog_open
      text = ""
      honor = card.main_honor&.name_for(Configuration.language)
      honor = nil if honor.to_s.empty?
      text += "#{if honor==nil;p_("EAPI_Common", "User");else;honor;end}: #{user} \r\n"
      if card.ban&.active?
        text += p_("EAPI_Common", "Banned until %{date}") % { date: format_date(Time.at(card.ban.totime)) }
        text += "\r\n"
        text += p_("EAPI_Common", "Ban reason: %{reason}") % { reason: card.ban.reason }
        text += "\r\n"
      end
      text += card.status.text
      text += "\r\n"
      if card.profile_hidden
        text += p_("EAPI_Common", "This profile is only visible to the user's contacts.") + "\r\n"
      end
      fullname = ""
      gender = -1
      if pr != nil
        fullname = pr.fullname
        gender = pr.gender
        text += fullname+"\r\n"
        if gender == 0
          text += "#{p_("EAPI_Common", "Gender")}: #{_("Female")}\r\n"
        elsif gender == 1
          text += "#{p_("EAPI_Common", "Gender")}: #{_("male")}\r\n"
        end
        age = visitingcard_age(pr.birthdate)
        if age != nil
          text += "#{p_("EAPI_Common", "Age")}: #{age.to_s}\r\n"
        end
        location = visitingcard_location(pr.location)
        if location != nil
          text += "#{p_("EAPI_Common", "Location")}: #{location}\r\n"
        end
      end
      if ui != nil
        if ui.last_seen != nil
          if gender == 0
            text += p_("EAPI_Common_female", "Last seen")
          elsif gender == 1
            text += p_("EAPI_Common_male", "Last seen")
          else
            text += p_("EAPI_Common", "Last seen")
          end
          text+= ": " + format_date(ui.last_seen, false, false) + "\r\n"
        end
        text += p_("EAPI_Common", "User has a blog")+"\r\n" if ui.has_blog
        text += "#{np_("EAPI_Common", "Knows %{count} user", "Knows %{count} users", ui.knows)%{:count=>ui.knows.to_s}}\r\n"
        if gender == -1
          text += np_("EAPI_Common", "Known by %{count} user", "Known by %{count} users", ui.known_by)%{:count=>ui.known_by.to_s}
        elsif gender == 0
          text += np_("EAPI_Common_female", "Known by %{count} user", "Known by %{count} users", ui.known_by)%{:count=>ui.known_by.to_s}
        elsif gender == 1
          text += np_("EAPI_Common_male", "Known by %{count} user", "Known by %{count} users", ui.known_by)%{:count=>ui.known_by.to_s}
        end
        text += "\r\n"
        text += "#{p_("EAPI_Common", "Forum posts")}: " + ui.forum_posts.to_s + "\r\n"
        text += "#{p_("EAPI_Common", "Polls answered")}: " + ui.polls.to_s + "\r\n"
        text += "#{p_("EAPI_Common", "Registered")}: " + format_date(ui.registered, true) + "\r\n" if ui.registered != nil
      end
      if vc != nil
        text += "\r\n\r\n"
        text += vc
      end
      input_text(p_("EAPI_Common", "Visiting card of %{user}:")%{:user=>user},flags: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine,text: text, escapable: true)
      $focus = true if $scene.is_a?(Scene_Main) == false
      dialog_close
      return 0
    end

    def visitingcard_age(birthdate, now = Time.now)
      return nil unless birthdate&.complete?

      year = birthdate.year.to_i
      month = birthdate.month.to_i
      day = birthdate.day.to_i
      future = year > now.year ||
        (year == now.year && month > now.month) ||
        (year == now.year && month == now.month && day > now.day)
      return nil if future

      age = now.year - year
      age -= 1 if month > now.month || (month == now.month && day > now.day)
      age
    end

    def visitingcard_location(value)
      location = value.to_s
      return nil if location.empty?

      locations = Lists.locations.to_a
      location_id = Integer(location, exception: false)
      if location_id != nil && location_id > 0
        row = locations.find { |entry| entry.is_a?(Hash) && entry["geonameid"].to_i == location_id }
        return nil if row == nil

        label = [row["name"], row["country"]].map(&:to_s).reject(&:empty?).join(", ")
        return label.empty? ? nil : label
      end

      locations.any? { |entry| entry.is_a?(Hash) && entry["country"].to_s == location } ? location : nil
    end

    # Gets the main honor of specified user.
  end
end
