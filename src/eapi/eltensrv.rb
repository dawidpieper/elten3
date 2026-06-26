# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module EltenSRV
    private

    def elten_link
      @elten_link ||= EltenLink::Client.new(self)
    end

    def name_attachments(attachments, names = [])
      EltenLink::Attachments.names(elten_link, attachments, names: names)
    rescue EltenLink::Error => e
      Log.warning("Attachment name lookup failed: #{e.message}")
      names || []
    end

    def send_attachment(file)
      EltenLink::Attachments.send_file(elten_link, file)
    rescue EltenLink::Error => e
      Log.warning("Attachment upload failed: #{e.message}")
      alert(_("Error"))
      nil
    end

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

    def feed(message, response = 0)
      EltenLink::Feeds.publish(elten_link, message, response: response)
    end

    def delete_feed(id)
      EltenLink::Feeds.delete(elten_link, id)
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

    def blogowners(user)
      EltenLink::Blog.owners(elten_link, blog: user)
    rescue EltenLink::Error => e
      Log.warning("Blog owner lookup failed: #{e.message}")
      []
    end

    def set_feed_follow(user, follow:)
      EltenLink::Feeds.follow(elten_link, user, follow: follow)
      NotificationService.reset_feeds
      EltenAPI::InvisibleInterface.reset_feeds if defined?(EltenAPI::InvisibleInterface)
      Session.feeds_clear
      true
    rescue EltenLink::Error => e
      Log.warning("Feed follow toggle failed: #{e.message}")
      alert(_("Error"))
      false
    end

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

    def self.cancel_call(id, client_context = nil)
      EltenLink::Calls.cancel(EltenLink.client(client_context || self), id)
      true
    rescue EltenLink::Error => e
      Log.warning("Call cancel failed: #{e.message}")
      false
    end

    def elten_api_base_url
      EltenLink::Client.api_base_url
    end

    def soundfont_url
      EltenLink::System.soundfont_url
    end

    def legacy_line_to_text(text)
      EltenLink.legacy_line_to_text(text)
    end

    # Opens notifications.
    def notifications(quiet=false)
      $scene = Scene_Notifications.new(quiet)
    end
    # Sends a bug report.
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

    # Opens a list of contacts allowing user to select one.
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
      (0..contact.size - 1).each do |i|
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
        (1..vc.size - 1).each do |i|
          text += vc[i]
        end
      end
      input_text(p_("EAPI_Common", "Visiting card of %{user}:")%{:user=>user},flags: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine,text: text, escapable: true)
      $focus = true if $scene.is_a?(Scene_Main) == false
      dialog_close
      return 0
    end

    # Gets the main honor of specified user.
    def gethonor(user)
      EltenLink::Honors.main(elten_link, user, Configuration.language)
    end

    def process_attachment(at)
      name=EltenLink::Attachments.name(elten_link, at)
      if name==nil
        alert(_("Error"))
        $scene=Scene_Main.new
        return
      end
      id=at
      ac=0
      if [".mp3",".wav",".ogg",".mid",".mod",".m4a",".flac",".wma",".opus",".aac",".aiff"].include?(File.extname(name).downcase)
        ac=selector([p_("EAPI_Common", "Save"),p_("EAPI_Common", "Play"),_("Cancel")],header: name,start_index: 0,cancel_index: 2,flags: 1)
      end
      case ac
      when 0
        loc=get_file(p_("EAPI_Common", "Where do you want to save this file?"), path: EltenPath.join(Dirs.user, "Documents"), save: true)
        if loc!=nil
          waiting {
            download_file(EltenLink::Attachments.download_url(id),EltenPath.join(loc, name))
            speak(p_("EAPI_Common", "The attachment has been downloaded."))
          }
        else
          loop_update
        end
      when 1
        player(EltenLink::Attachments.download_url(id))
      end
    end

    def feedshow(feed)
      return if feed==nil
      likes=[]
      begin
        likes=EltenLink::Feeds.likes(elten_link, feed.id)
      rescue EltenLink::Error => e
        Log.warning("Feed likes failed: #{e.message}")
      end
      form=Form.new([
        edt_message = EditBox.new(p_("EAPI_Common", "Message"), type: EditBox::Flags::ReadOnly, text: feed.message, quiet: true),
        lst_likes = ListBox.new(likes, header: p_("EAPI_Common", "Users liking this message")),
        btn_close = Button.new(p_("EAPI_Common", "Close"))
        ], index: 0, silent: false, quiet: true)
      btn_close.on(:press) {form.resume}
      edt_message.bind_context{|menu|menu.useroption(feed.user)}
      lst_likes.bind_context{|menu|
        if likes.size>0
          menu.useroption(likes[lst_likes.index])
        end
      }
      form.cancel_button=btn_close
      dialog_open
      form.wait
      dialog_close
    end
  end

  include EltenSRV
end
