# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
# @return [String] returns ALT if menu was closed using an alt menu
    def usermenu(user,submenu=false, left=false)
      ui=userinfo(user, true)
      return if ui==-1
      if ui[15]==true
        alert(p_("EAPI_Common", "This account is archived"))
        return
        end
            @incontacts = ui[8].to_b if Session.name!="guest"
@isbanned = ui[10].to_b
      @hasblog = ui[1]
    @hashonors=(ui[11]>0)
   @callable=ui[12].to_b
   @feedfollowed = ui[13].to_b
   @monitored = ui[14].to_b
    play_sound("menu_open") if submenu != true
Menu.menubg_play if submenu != true and (Configuration.bgsounds==true && Configuration.soundthemeactivation==true)
sel = [p_("EAPI_Common", "Write a private message"),p_("EAPI_Common", "Visiting card"),p_("EAPI_Common", "Show user blogs"),p_("EAPI_Common", "badges of this user")]
if Session.name!="guest"
if @incontacts == true
  sel.push(p_("EAPI_Common", "Remove from contacts' list"))
else
  sel.push(p_("EAPI_Common", "Add to contacts' list"))
end
if @feedfollowed == true
  sel.push(p_("EAPI_Common", "Unfollow feed"))
else
  sel.push(p_("EAPI_Common", "Follow feed"))
end
else
  sel.push("")
  sel.push("")
end
ringtone=false
  begin
  ringtone_file=EltenPath.join(Dirs.eltendata, "ringtones.json")
  if FileTest.exists?(ringtone_file)
json=JSON.load(File.binread(ringtone_file))
ringtone=true if json[user].is_a?(String) && FileTest.exists?(json[user])
  end
end
if ringtone
  sel.push(p_("EAPI_Common", "Unset ringtone"))
  else
  sel.push(p_("EAPI_Common", "Set ringtone"))
  end
  sel.push(p_("EAPI_Common", "Call this user"))
  sel.push(p_("EAPI_Common", "Show feed"))
  if @monitored==false
  sel.push(p_("EAPI_Common", "Monitor when this user becomes online"))
else
  sel.push(p_("EAPI_Common", "Do not monitor this user"))
    end
  if Session.moderator > 0
  if @isbanned == false
    sel.push(p_("EAPI_Common", "Ban"))
  else
    sel.push(p_("EAPI_Common", "Unban"))
  end
else
  sel.push("")
  end
    if $usermenuextra.is_a?(Hash) and Session.name!="guest"
      for k in $usermenuextra.keys
    sel.push(k)
    end
    end
  if submenu==false
    menu = ListBox.new(sel,header: "",index: 0,flags: ListBox::Flags::AnyDir)
  else
    menu = ListBox.new(sel,header: "")
    end
  menu.disable_item(2) if @hasblog == false
if Session.name=="guest"
  menu.disable_item(0)
    menu.disable_item(4)
    menu.disable_item(5)
   menu.disable_item(6)
    menu.disable_item(7)
    menu.disable_item(9)
  end
menu.disable_item(3) if @hashonors==false
menu.disable_item(7) if @callable==false
menu.disable_item(10) if Session.moderator==0
menu.focus
loop do
loop_update
if key_pressed?(:key_enter)
  play_sound("menu_close")
    Menu.menubg_close
  case menu.index
  when 0
    insert_scene(Scene_Messages_New.new(user,"","",Scene_Main.new), true)
        loop_update
    return "ALT"
    when 1
            visitingcard(user)
      loop_update
            return("ALT")
      break
            when 2
        insert_scene(Scene_Blog_List.new(user,Scene_Main.new), true)
    loop_update
        return "ALT"
        break
    when 3
        insert_scene(Scene_Honors.new(user,Scene_Main.new), true)
    loop_update
    return "ALT"
          when 4
      if @incontacts == true
        confirm(p_("EAPI_Common", "Are you sure you want to delete this contact?")) {
        insert_scene(Scene_Contacts_Delete.new(user,Scene_Main.new), true)
        }
      else
        insert_scene(Scene_Contacts_Insert.new(user,Scene_Main.new), true)
      end
    loop_update
    return "ALT"
    when 5
      if set_feed_follow(user, follow: !@feedfollowed)
        if @feedfollowed
          alert(p_("EAPI_Common", "Feed unfollowed"))
        else
          alert(p_("EAPI_Common", "Feed followed"))
        end
      end
      loop_update
    return "ALT"
    when 6
      if ringtone
        set_ringtone(user, nil)
        alert(p_("EAPI_Common", "Ringtone removed"))
      else
        if requires_premiumpackage("audiophile")
        file=get_file(p_("EAPI_Common", "Select ringtone for user %{user}")%{:user=>user}, path: EltenPath.with_separator(Dirs.documents), save: false, extensions: [".mp3",".wav",".ogg",".mod",".m4a",".flac",".wma",".opus",".aac",".aiff",".w64"])
        if file!=nil
        set_ringtone(user, file)
        alert(p_("EAPI_Common", "Ringtone changed"))
        end
        end
    end
      loop_update
    return "ALT"
        when 7
        voicecall(nil, nil, [user])
        when 8
          insert_scene(Scene_FeedViewer.new(user))
          loop_update
          return "ALT"
        when 9
if @monitored==false
  opts = [p_("EAPI_Common", "Notify me one time when this user becomes online"), p_("EAPI_Common", "Notify me whenever this user becomes online")]
  o = selector(opts, header: p_("EAPI_Common", "Online monitor"), start_index: 0, cancel_index: -1)
  if o>=0
    if add_online_monitor(user, permanent: o)
      alert(p_("EAPI_Common", "This user is now monitored"))
    end
  end
else
  if delete_online_monitor(user)
    alert(p_("EAPI_Common", "This user is no longer monitored"))
  end
  end
      loop_update
    return "ALT"
          when 10
        if @isbanned == false
          insert_scene(Scene_Ban_Ban.new(user,Scene_Main.new), true)
        else
          insert_scene(Scene_Ban_Unban.new(user,Scene_Main.new), true)
        end
    loop_update
    return "ALT"
      else
                if $usermenuextra.is_a?(Hash)
                                    a=$usermenuextra.values[menu.index-11]
                                    s=a[0].new
                                    s.userevent(user, *a[1..-1])
                      insert_scene(s, true)
                                                                 return "ALT"
                  break
                  end
end
break
end
if key_pressed?(:key_alt)
  if submenu != true
    break
else
  return("ALT")
  break
end
end
if key_pressed?(:key_escape)
  loop_update
  if submenu == true
        return
    break
  else
        break
    end
  end
  if ((key_pressed?(:key_up) and !left and menu.index==0) or (key_pressed?(:key_left) and left)) and submenu == true
        loop_update
    return
    break
  end
  menu.update
end
Menu.menubg_close if submenu != true
play_sound("menu_close") if submenu != true
end
  end
end
