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
      text += "#{if honor==nil;p_("EAPI_Common", "User");else;honor;end}: #{user} \r\n"
      if card.ban&.active?
        text += p_("EAPI_Common", "Banned until %{date}") % { date: format_date(Time.at(card.ban.totime)) }
        text += "\r\n"
        text += p_("EAPI_Common", "Ban reason: %{reason}") % { reason: card.ban.reason }
        text += "\r\n"
      end
      text += card.status.text
      text += "\r\n"
      fullname = ""
      gender = -1
      birthdateyear = 0
      birthdatemonth = 0
      birthdateday = 0
      location = ""
      if pr != nil
        fullname = pr.fullname
        gender = pr.gender
        if pr.birthdate.complete?
          birthdateyear = pr.birthdate.year
          birthdatemonth = pr.birthdate.month
          birthdateday = pr.birthdate.day
        end
        location = pr.location
        text += fullname+"\r\n"
        if gender == 0
          text += "#{p_("EAPI_Common", "Gender")}: #{_("Female")}\r\n"
        elsif gender == 1
          text += "#{p_("EAPI_Common", "Gender")}: #{_("male")}\r\n"
        end
        if birthdateyear.to_i>0
          age = Time.now.year-birthdateyear.to_i
          if Time.now.month < birthdatemonth.to_i
            age -= 1
          elsif Time.now.month == birthdatemonth.to_i
            if Time.now.day < birthdateday.to_i
              age -= 1
            end
          end
          age -= 2000 if age > 2000
          text += "#{p_("EAPI_Common", "Age")}: #{age.to_s}\r\n"
        end
        if location!="" and (location.to_i>0 or Lists.locations.map{|l| l['country']}.uniq.include?(location))
          text+=p_("EAPI_Common", "Location")+": "
          if location.to_i>0
            loc={}
            Lists.locations.each {|l| loc=l if l['geonameid']==location.to_i}
            text+=(loc['name']||"")+", "+(loc['country']||"") if loc!=nil
          else
            text+=location
          end
          text+="\r\n"
        end
      end
      if ui != -1
        if gender == 0
          text += p_("EAPI_Common_female", "Last seen")
        elsif gender == 1
          text += p_("EAPI_Common_male", "Last seen")
        else
          text += p_("EAPI_Common", "Last seen")
        end
        text+= ": " + format_date(ui.last_seen, false, false) + "\r\n"
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

    # Gets the main honor of specified user.
  end
end
