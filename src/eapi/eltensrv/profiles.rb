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
        vc = EltenLink::Profiles.visiting_card(elten_link, user)
        pr = EltenLink::Profiles.profile(elten_link, user)
      rescue EltenLink::Error => e
        Log.warning("Visiting card failed: #{e.message}")
        alert(_("Database Error"))
        return -1
      end
      dialog_open
      text = ""
      honor=gethonor(user)
      text += "#{if honor==nil;p_("EAPI_Common", "User");else;honor;end}: #{user} \r\n"
      text += getstatus(user,false,false)
      text += "\r\n"
      fullname = ""
      gender = -1
      birthdateyear = 0
      birthdatemonth = 0
      birthdateday = 0
      location = ""
      if pr != nil && pr[0].to_i == 0
        fullname = pr[1].delete("\r\n")
        gender = pr[2].delete("\r\n").to_i
        if pr[3].to_i>1900 and pr[4].to_i > 0 and pr[4].to_i < 13 and pr[5].to_i > 0 and pr[5].to_i < 32
          birthdateyear = pr[3].delete("\r\n")
          birthdatemonth = pr[4].delete("\r\n")
          birthdateday = pr[5].delete("\r\n")
        end
        location = pr[6].delete("\r\n")
        text += fullname+"\r\n"
        text+="#{p_("EAPI_Common", "Gender")}: "
        if gender == 0
          text += "#{_("Female")}\r\n"
        else
          text += "#{_("male")}\r\n"
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
      ui = userinfo(user)
      if ui != -1
        if gender == 0
          text += p_("EAPI_Common_female", "Last seen")
        elsif gender == 1
          text += p_("EAPI_Common_male", "Last seen")
        else
          text += p_("EAPI_Common", "Last seen")
        end
        text+= ": " + ui[0] + "\r\n"
        text += p_("EAPI_Common", "User has a blog")+"\r\n" if ui[1] == true
        text += "#{np_("EAPI_Common", "Knows %{count} user", "Knows %{count} users", ui[2])%{:count=>ui[2].to_s}}\r\n"
        if gender == -1
          text += np_("EAPI_Common", "Known by %{count} user", "Known by %{count} users", ui[3])%{:count=>ui[3].to_s}
        elsif gender == 0
          text += np_("EAPI_Common_female", "Known by %{count} user", "Known by %{count} users", ui[3])%{:count=>ui[3].to_s}
        elsif gender == 1
          text += np_("EAPI_Common_male", "Known by %{count} user", "Known by %{count} users", ui[3])%{:count=>ui[3].to_s}
        end
        text += "\r\n"
        text += "#{p_("EAPI_Common", "Forum posts")}: " + ui[4].to_s + "\r\n"
        text += "#{p_("EAPI_Common", "Polls answered")}: " + ui[7].to_s.delete("\r\n") + "\r\n"
        v=""
        ui[5].split(" ").each {|e|
          if v==""
            e=e.delete(".").split("").join(".")
          else
            v+=" "
          end
          v+=e
        }
        text += "#{p_("EAPI_Common", "Used version")}: " + v + "\r\n"
        text += "#{p_("EAPI_Common", "Registered")}: " + ui[6].to_s.split(" ")[0] + "\r\n" if ui[6]!=""
      end
      if vc[1]!="     " and vc.size!=1
        text += "\r\n\r\n"
        for i in 1..vc.size - 1
          text += vc[i]
        end
      end
      input_text(p_("EAPI_Common", "Visiting card of %{user}:")%{:user=>user},flags: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine,text: text, escapable: true)
      $focus = true if $scene.is_a?(Scene_Main) == false
      dialog_close
      return 0
    end

    # Gets the main honor of specified user.
  end
end
