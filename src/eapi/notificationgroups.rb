# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module NotificationGroups
  NotificationGroup = Struct.new(:key, :cat, :label, :category, :date, :revoked, :ids, :payload, :virtual, :action, keyword_init: true) do
    def virtual?
      virtual == true
    end
  end

  @@virtual_notification_revoked = {}
  @@virtual_notification_groups = []
  @@virtual_notification_seen_at = {}
  @@virtual_notification_mutex = Mutex.new

  def self.virtual_notification_groups
    @@virtual_notification_mutex.synchronize do
      @@virtual_notification_groups.map(&:dup)
    end
  end

  def self.refresh_virtual_notifications(updates)
    helper = Object.new.extend(NotificationGroups)
    groups = []
    client_group = helper.update_notification(updates)
    groups << client_group if client_group != nil
    programs_group = helper.program_updates_notification(updates)
    groups << programs_group if programs_group != nil
    store_virtual_notification_groups(groups)
  end

  def self.clear_virtual_notifications
    store_virtual_notification_groups([])
  end

  def self.store_virtual_notification_groups(groups)
    now = Time.now.to_i
    changed = false
    helper = Object.new.extend(NotificationGroups)
    @@virtual_notification_mutex.synchronize do
      old_keys = @@virtual_notification_groups.map(&:key).sort
      new_keys = groups.map(&:key).sort
      changed = old_keys != new_keys
      groups.each do |group|
        @@virtual_notification_seen_at[group.key.to_s] ||= now
        group.date = @@virtual_notification_seen_at[group.key.to_s]
        group.revoked = @@virtual_notification_revoked[group.key.to_s] == true
        group.label = helper.group_label(group)
      end
      @@virtual_notification_groups = groups
    end
    if changed
      $main_notifications_changed = true
      Session.notifications_update
    end
    changed
  end

  def self.installed_program_update_payload
    return [] unless defined?(Programs)

    Programs.local_entries.filter_map do |entry|
      build_id = EltenLink::System.normalize_build_id(entry.build_id)
      next if entry.id.to_s.empty? || build_id == nil

      { "id" => entry.id.to_s, "build_id" => build_id }
    end
  rescue Exception => e
    Log.warning("Installed programs update snapshot failed: #{e.class}: #{e.message}")
    []
  end

  def build_notification_groups(notifications, include_revoked: true)
    by_key = {}
    notifications.each do |notification|
      next if include_revoked != true && notification.revoked

      change_time = notification_change_time(notification)
      key = [notification.revoked ? "revoked" : "active", notification.cat, group_key(notification)].join("\u001F")
      group = by_key[key]
      if group == nil
        group = NotificationGroup.new(
          key: key,
          cat: notification.cat,
          category: category_label(notification.cat),
          date: change_time,
          revoked: notification.revoked,
          ids: [],
          payload: notification.payload || {},
          virtual: false,
          action: nil
        )
        by_key[key] = group
      end
      group.ids << notification.id if notification.id.to_i > 0
      if change_time >= group.date.to_i
        group.date = change_time
        group.payload = notification.payload || {}
      end
    end

    by_key.values.each do |group|
      group.action = action_for(group.cat, group.payload)
      group.label = group_label(group)
    end
  end

  def collect_virtual_notification_groups
    NotificationGroups.virtual_notification_groups
  end

  def installed_program_update_payload
    NotificationGroups.installed_program_update_payload
  end

  def append_virtual_notification_groups(groups, virtual_groups, include_revoked: true)
    groups.concat(visible_virtual_notification_groups(virtual_groups, include_revoked: include_revoked))
  end

  def visible_virtual_notification_groups(virtual_groups, include_revoked: true)
    virtual_groups.to_a.each_with_object([]) do |group, result|
      next unless group.virtual?

      group.revoked = virtual_notification_revoked?(group.key)
      group.label = group_label(group)
      result << group if include_revoked == true || !group.revoked
    end
  end

  def virtual_notification_revoked?(key)
    @@virtual_notification_revoked[key.to_s] == true
  end

  def revoke_virtual_notification(group)
    @@virtual_notification_revoked[group.key.to_s] = true
    group.revoked = true
    $main_notifications_changed = true
    Session.notifications_update if defined?(Session)
    true
  end
  def update_notification(updates)
    client = updates == nil ? nil : updates.client
    return nil if client == nil || !client.update?

    version = client.version_string.to_s
    version = client.build_id.to_s if version.empty?
    key = "virtual:update:client:#{client.build_id.to_s}"
    NotificationGroup.new(
      key: key,
      cat: "update",
      category: category_label("update"),
      label: "#{category_label("update")}: #{p_("Notifications", "Update available (%{version})") % { version: version }}",
      date: Time.now.to_i,
      revoked: virtual_notification_revoked?(key),
      ids: [],
      payload: { "version" => version },
      virtual: true,
      action: Proc.new { insert_scene(Scene_Update_Confirmation.new(Scene_Main.new, version), true, return_to_main: true) }
    )
  rescue EltenLink::Error => e
    Log.warning("Notifications update check failed: #{e.message}")
    nil
  end

  def program_updates_notification(updates)
    app_updates = updates == nil ? [] : updates.apps.to_a
    return nil if app_updates.empty?

    key = "virtual:update:programs:#{app_updates.map { |app| "#{app.id}:#{app.build_id.to_s}" }.sort.join("|")}"
    names = app_updates.map { |app| app.name.to_s }.reject(&:empty?)
    payload = {
      "count" => app_updates.size,
      "names" => names,
      "updates" => app_updates.map do |app|
        {
          "id" => app.id.to_s,
          "name" => app.name.to_s,
          "version" => app.version.to_s,
          "build_id" => app.build_id,
          "current_build_id" => app.current_build_id
        }
      end
    }
    NotificationGroup.new(
      key: key,
      cat: "program_updates",
      category: category_label("program_updates"),
      label: "#{category_label("program_updates")}: #{program_updates_title(payload)}",
      date: Time.now.to_i,
      revoked: virtual_notification_revoked?(key),
      ids: [],
      payload: payload,
      virtual: true,
      action: Proc.new { insert_scene(Scene_Programs.new(:updates), true, return_to_main: true) }
    )
  rescue EltenLink::Error => e
    Log.warning("Program updates notification failed: #{e.message}")
    nil
  end

  def sort_notification_groups(groups)
    groups.sort_by { |group| [group.revoked ? 1 : 0, -group.date.to_i, group.category.to_s, group.label.to_s] }
  end

  def limit_visible_notification_groups(groups, revoked_limit: 20)
    revoked_count = 0
    groups.to_a.select do |group|
      next true if !group.revoked

      revoked_count += 1
      revoked_count <= revoked_limit.to_i
    end
  end

  def notification_columns
    [p_("Notifications", "Description"), p_("Notifications", "Count"), p_("Notifications", "Type")]
  end

  def notification_rows(groups=@groups)
    groups.to_a.map do |group|
      count = group_count(group)
      [group_description(group), count.to_i == 1 ? nil : count.to_s, group.category]
    end
  end

  def apply_notification_group_states(list, groups)
    new_status = ListBox.item_status("listbox_itemnew", p_("Notifications", "New") + ":", p_("Notifications", "New"))
    groups.to_a.each_with_index do |group, index|
      list.set_row_states(index, [new_status]) if !group.revoked
    end
  end

  def group_count(group)
    virtual_count = group.payload["count"].to_i if group.virtual? && group.payload.is_a?(Hash)
    return virtual_count if virtual_count != nil && virtual_count > 0

    [group.ids.size, 1].max
  end

  def notification_change_time(notification)
    [notification.date.to_i, notification.update_time.to_i].max
  end

  def group_key(notification)
    payload = notification.payload
    payload = {} unless payload.is_a?(Hash)
    cat = notification.cat.to_s
    case cat
    when "message"
      notification.internal_id2.to_s.empty? ? ["message", message_participant(payload), normalized_subject(payload)].join(":") : notification.internal_id2.to_s
    when "followedthread", "followedforum", "followedforumpost", "mention"
      notification.internal_id.to_s.empty? ? ["forum", payload["threadid"].to_i].join(":") : notification.internal_id.to_s
    when "followedblog", "blogcomment", "followedblogpost", "blogmention"
      notification.internal_id.to_s.empty? ? ["blog", payload["blog"], payload["postid"].to_i].join(":") : notification.internal_id.to_s
    when "blogfollower"
      notification.internal_id2.to_s.empty? ? ["blog", payload["blog"]].join(":") : notification.internal_id2.to_s
    when "friend", "birthday", "mtr"
      notification.internal_id.to_s.empty? ? [cat, payload["user"]].join(":") : notification.internal_id.to_s
    when "groupinvitation"
      notification.internal_id.to_s.empty? ? [cat, payload["groupid"].to_i].join(":") : notification.internal_id.to_s
    else
      key = notification.internal_id.to_s
      key = notification.internal_id2.to_s if key.empty?
      key = notification.internal_id3.to_s if key.empty?
      key.empty? ? [cat, notification.id.to_i].join(":") : key
    end
  end

  def group_description(group)
    title = title_for(group.cat, group.payload)
    title = group.payload["title"].to_s if title.to_s.empty? && group.payload.is_a?(Hash)
    title = group.payload["threadname"].to_s if title.to_s.empty? && group.payload.is_a?(Hash)
    title = group.payload["user"].to_s if title.to_s.empty? && group.payload.is_a?(Hash)
    title = p_("Notifications", "Notification") if title.to_s.empty?
    title
  end

  def group_label(group)
    "#{group.category}: #{group_description(group)}"
  end

  def category_label(cat)
    case cat.to_s
    when "message"
      p_("Notifications", "Messages")
    when "followedthread"
      p_("Notifications", "Followed threads")
    when "followedforum"
      p_("Notifications", "Followed forums")
    when "followedforumpost"
      p_("Notifications", "Followed forums")
    when "mention"
      p_("Notifications", "Forum mentions")
    when "friend"
      p_("Notifications", "Contacts")
    when "birthday"
      p_("Notifications", "Birthdays")
    when "followedblog"
      p_("Notifications", "Followed blogs")
    when "blogcomment"
      p_("Notifications", "Blog comments")
    when "followedblogpost"
      p_("Notifications", "Followed blog posts")
    when "blogfollower"
      p_("Notifications", "Blog followers")
    when "blogmention"
      p_("Notifications", "Blog mentions")
    when "groupinvitation"
      p_("Notifications", "Group invitations")
    when "mtr"
      p_("Notifications", "Online monitors")
    when "program_updates"
      p_("Notifications", "Program updates")
    when "update"
      p_("Notifications", "Updates")
    else
      p_("Notifications", "Other")
    end
  end

  def title_for(cat, payload)
    payload = {} unless payload.is_a?(Hash)
    case cat.to_s
    when "message"
      message_title(payload)
    when "followedthread", "followedforum", "followedforumpost"
      payload["threadname"].to_s
    when "mention"
      author = payload["author"].to_s
      thread = payload["threadname"].to_s
      message = payload["message"].to_s
      [thread, author, message].reject(&:empty?).join(" - ")
    when "followedblog", "blogcomment", "followedblogpost"
      blog_post_title(payload)
    when "blogmention"
      [blog_post_title(payload), payload["author"].to_s, payload["message"].to_s].reject(&:empty?).join(" - ")
    when "blogfollower"
      [payload["user"].to_s, payload["blog"].to_s].reject(&:empty?).join(" - ")
    when "friend", "mtr"
      payload["user"].to_s
    when "groupinvitation"
      payload["groupname"].to_s
    when "program_updates"
      program_updates_title(payload)
    when "update"
      update_title(payload)
    else
      payload["alert"].to_s
    end
  end

  def message_title(payload)
    participant = message_participant(payload)
    title = payload["groupname"].to_s
    title = participant if title.empty?
    subject = payload["subject"].to_s
    subject = p_("Notifications", "No subject") if subject.empty?
    [title, subject].reject(&:empty?).join(": ")
  end

  def blog_post_title(payload)
    title = payload["title"].to_s
    blog = payload["blog"].to_s
    return title if blog.empty? || title.include?(blog)
    title.empty? ? blog : "#{blog}: #{title}"
  end

  def update_title(payload)
    version = payload["version"].to_s
    return p_("Notifications", "Update available") if version.empty?

    p_("Notifications", "Update available (%{version})") % { version: version }
  end

  def program_updates_title(payload)
    count = payload["count"].to_i
    names = Array(payload["names"]).map(&:to_s).reject(&:empty?)
    if count == 1 && names[0].to_s != ""
      p_("Notifications", "Program update available: %{name}") % { name: names[0] }
    else
      p_("Notifications", "%{count} program updates available") % { count: count }
    end
  end

  def action_for(cat, payload)
    payload = {} unless payload.is_a?(Hash)
    case cat.to_s
    when "message"
      Proc.new { open_message(payload) }
    when "followedthread", "followedforum", "followedforumpost", "mention"
      Proc.new { open_forum_thread(payload, cat.to_s) }
    when "followedblog", "blogcomment", "followedblogpost", "blogmention"
      Proc.new { open_blog_post(payload) }
    when "blogfollower"
      Proc.new { insert_scene(Scene_Blog_Followers.new(nil), true) }
    when "friend"
      Proc.new { insert_scene(Scene_Users_AddedMeToContacts.new(true), true) }
    when "birthday"
      Proc.new { insert_scene(Scene_Contacts.new(1), true) }
    when "groupinvitation"
      Proc.new { insert_scene(Scene_Forum.new(nil, nil, 4), true) }
    else
      nil
    end
  end

  def open_message(payload)
    participant = message_participant(payload)
    scene = if participant.to_s.empty?
      Scene_Messages.new(true, close_to_main: true)
    else
      Scene_Messages.new(user: participant, subject: message_subject(payload), close_to_main: true)
    end
    insert_scene(scene, true, return_to_main: true)
  end

  def message_participant(payload)
    receiver = payload["receiver"].to_s
    return receiver if receiver.start_with?("[")

    payload["sender"].to_s
  end

  def message_subject(payload)
    subject = payload["subject"].to_s.delete("\r\n").gsub(/re: /i, "")
    subject.empty? ? nil : subject
  end

  def normalized_subject(payload)
    payload["subject"].to_s.delete("\r\n").gsub(/re: /i, "").downcase.strip
  end

  def open_forum_thread(payload, cat=nil)
    thread_id = payload["threadid"].to_i
    if thread_id > 0
      post_id = payload["postid"].to_i
      query = ["followedthread", "followedforumpost"].include?(cat.to_s) ? :first_unread : (post_id > 0 ? post_id : "")
      mention = forum_mention_from_payload(payload) if cat.to_s == "mention" && post_id > 0
      insert_scene(Scene_Forum_Thread.new(thread_id, -13, 0, query, mention, Scene_Main.new), true, return_to_main: true)
    else
      insert_scene(Scene_Forum.new, true, return_to_main: true)
    end
  end

  def forum_mention_from_payload(payload)
    mention = Struct_Forum_Mention.new(payload["mentionid"].to_i)
    mention.thread = payload["threadid"].to_i
    mention.post = payload["postid"].to_i
    mention.author = payload["author"].to_s
    mention.message = payload["message"].to_s
    mention
  end

  def open_blog_post(payload)
    blog = payload["blog"].to_s
    post_id = payload["postid"].to_i
    if blog.empty? || post_id <= 0
      insert_scene(Scene_Blog.new, true)
      return
    end

    post = Struct_Blog_Post.new(post_id)
    post.owner = blog
    post.name = payload["title"].to_s
    post.author = payload["author"].to_s
    insert_scene(Scene_Blog_Read.new(post, -1, 0, 0), true)
  end

  def open_notification_group(group)
    return false if group == nil

    if group.action != nil
      group.action.call
      return revoke_notification_group(group) if !group.revoked && (group.ids.size > 0 || group.virtual?)
      return true
    elsif !group.revoked && (group.ids.size > 0 || group.virtual?)
      return revoke_notification_group(group)
    end
    false
  end

  def revoke_notification_group(group)
    return false if group == nil
    return revoke_virtual_notification(group) if group.virtual?
    return false if group.ids.empty?

    EltenLink::Notifications.revoke_many(elten_link, group.ids)
    group.revoked = true
    $main_notifications_changed = true
    Session.notifications_update if defined?(Session)
    true
  rescue EltenLink::Error => e
    Log.warning("Notification revoke failed: #{e.message}")
    alert(_("Error"))
    false
  end

  def revocable_notification_groups?(groups)
    groups.to_a.any? { |group| !group.revoked && (group.virtual? || !group.ids.empty?) }
  end

  def revoke_all_notification_groups(groups=nil)
    EltenLink::Notifications.revoke_all(elten_link)
    groups.to_a.each do |group|
      revoke_virtual_notification(group) if group.virtual? && !group.revoked
    end
    $main_notifications_changed = true
    Session.notifications_update if defined?(Session)
    true
  rescue EltenLink::Error => e
    Log.warning("Notification revoke all failed: #{e.message}")
    alert(_("Error"))
    false
  end
end
