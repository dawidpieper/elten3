# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private

    # @return [String] returns ALT if menu was closed using an alt menu
    def usermenu(user, submenu = false, left = false)
      user_info = userinfo(user, true)
      return if user_info == -1

      if user_info[15] == true
        alert(p_("EAPI_Common", "This account is archived"))
        return
      end

      ringtone = user_ringtone_set?(user)
      actions = user_menu_actions(user, user_info, ringtone)
      play_sound("menu_open") unless submenu
      Menu.menubg_play if !submenu && Configuration.bgsounds == true && Configuration.soundthemeactivation == true

      labels = actions.map { |action| action[:label] }
      menu = if submenu
        ListBox.new(labels, header: "")
      else
        ListBox.new(labels, header: "", index: 0, flags: ListBox::Flags::AnyDir)
      end
      menu.focus

      loop do
        loop_update
        if key_pressed?(:key_enter)
          action = actions[menu.index]
          if action
            play_sound("menu_close")
            Menu.menubg_close
            action[:handler].call
            if action[:close_all]
              loop_update
              return "ALT"
            end
            break
          end
        end

        if key_pressed?(:key_alt)
          return "ALT" if submenu
          break
        end

        if key_pressed?(:key_escape)
          loop_update
          return if submenu
          break
        end

        if submenu && ((key_pressed?(:key_up) && !left && menu.index == 0) || (key_pressed?(:key_left) && left))
          loop_update
          return
        end
        menu.update
      end

      Menu.menubg_close unless submenu
      play_sound("menu_close") unless submenu
    end

    def user_menu_actions(user, user_info, ringtone)
      guest = Session.name == "guest"
      in_contacts = user_info[8].to_b unless guest
      banned = user_info[10].to_b
      has_blog = user_info[1]
      has_honors = user_info[11] > 0
      callable = user_info[12].to_b
      feed_followed = user_info[13].to_b
      monitored = user_info[14].to_b
      actions = []

      unless guest
        actions << user_menu_action(p_("EAPI_Common", "Write a private message")) do
          insert_scene(Scene_Messages_New.new(user, "", "", Scene_Main.new), true)
        end
      end

      actions << user_menu_action(p_("EAPI_Common", "Visiting card")) do
        visitingcard(user)
      end

      if has_blog
        actions << user_menu_action(p_("EAPI_Common", "Show user blogs")) do
          insert_scene(Scene_Blog_List.new(user, Scene_Main.new), true)
        end
      end

      actions << user_menu_action(p_("EAPI_Common", "Show feed")) do
        insert_scene(Scene_FeedViewer.new(user))
      end

      unless guest
        follow_label = if feed_followed
          p_("EAPI_Common", "Unfollow feed")
        else
          p_("EAPI_Common", "Follow feed")
        end
        actions << user_menu_action(follow_label) do
          if set_feed_follow(user, follow: !feed_followed)
            if feed_followed
              alert(p_("EAPI_Common", "Feed unfollowed"))
            else
              alert(p_("EAPI_Common", "Feed followed"))
            end
          end
        end
      end

      if !guest && callable
        actions << user_menu_action(p_("EAPI_Common", "Call this user"), close_all: false) do
          voicecall(nil, nil, [user])
        end
      end

      unless guest
        ringtone_label = if ringtone
          p_("EAPI_Common", "Unset ringtone")
        else
          p_("EAPI_Common", "Set ringtone")
        end
        actions << user_menu_action(ringtone_label) do
          if ringtone
            set_ringtone(user, nil)
            alert(p_("EAPI_Common", "Ringtone removed"))
          elsif requires_premiumpackage("audiophile")
            file = get_file(
              p_("EAPI_Common", "Select ringtone for user %{user}") % { user: user },
              path: EltenPath.with_separator(Dirs.documents),
              save: false,
              extensions: [".mp3", ".wav", ".ogg", ".mod", ".m4a", ".flac", ".wma", ".opus", ".aac", ".aiff", ".w64"]
            )
            if file
              set_ringtone(user, file)
              alert(p_("EAPI_Common", "Ringtone changed"))
            end
          end
        end
      end

      actions << user_menu_action(p_("EAPI_Common", "Show forum posts")) do
        insert_scene(Scene_Forum_UserPosts.new(user, Scene_Main.new), true)
      end

      if has_honors
        actions << user_menu_action(p_("EAPI_Common", "badges of this user")) do
          insert_scene(Scene_Honors.new(user, Scene_Main.new), true)
        end
      end

      unless guest
        monitor_label = if monitored
          p_("EAPI_Common", "Do not monitor this user")
        else
          p_("EAPI_Common", "Monitor when this user becomes online")
        end
        actions << user_menu_action(monitor_label) do
          if monitored
            if delete_online_monitor(user)
              alert(p_("EAPI_Common", "This user is no longer monitored"))
            end
          else
            options = [
              p_("EAPI_Common", "Notify me one time when this user becomes online"),
              p_("EAPI_Common", "Notify me whenever this user becomes online")
            ]
            selection = selector(options, header: p_("EAPI_Common", "Online monitor"), start_index: 0, cancel_index: -1)
            if selection >= 0 && add_online_monitor(user, permanent: selection)
              alert(p_("EAPI_Common", "This user is now monitored"))
            end
          end
        end

        contacts_label = if in_contacts
          p_("EAPI_Common", "Remove from contacts' list")
        else
          p_("EAPI_Common", "Add to contacts' list")
        end
        actions << user_menu_action(contacts_label) do
          if in_contacts
            confirm(p_("EAPI_Common", "Are you sure you want to delete this contact?")) do
              insert_scene(Scene_Contacts_Delete.new(user, Scene_Main.new), true)
            end
          else
            insert_scene(Scene_Contacts_Insert.new(user, Scene_Main.new), true)
          end
        end
      end

      if Session.moderator > 0
        moderation_label = banned ? p_("EAPI_Common", "Unban") : p_("EAPI_Common", "Ban")
        actions << user_menu_action(moderation_label) do
          scene = banned ? Scene_Ban_Unban.new(user, Scene_Main.new) : Scene_Ban_Ban.new(user, Scene_Main.new)
          insert_scene(scene, true)
        end
      end

      if $usermenuextra.is_a?(Hash) && !guest
        $usermenuextra.each do |label, definition|
          actions << user_menu_action(label) do
            program_class, *arguments = definition
            scene = program_class.new
            scene.userevent(user, *arguments)
            insert_scene(scene, true)
          end
        end
      end

      actions
    end

    def user_menu_action(label, close_all: true, &handler)
      { label: label, close_all: close_all, handler: handler }
    end

    def user_ringtone_set?(user)
      ringtone_file = EltenPath.join(Dirs.eltendata, "ringtones.json")
      return false unless FileTest.exists?(ringtone_file)

      ringtones = JSON.load(File.binread(ringtone_file))
      ringtones[user].is_a?(String) && FileTest.exists?(ringtones[user])
    end
  end
end
