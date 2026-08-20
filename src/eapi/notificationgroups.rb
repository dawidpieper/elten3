# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module NotificationGroups
  NOTIFICATION_TYPE_ORDER = %w[
    message
    followedthread
    followedforum
    mention
    friend
    birthday
    followedblog
    blogcomment
    followedblogpost
    blogfollower
    blogmention
    groupinvitation
    mtr
    program_updates
    update
  ].freeze
  NOTIFICATION_TYPE_ALIASES = {
    "followedforumpost" => "followedforum"
  }.freeze
  NOTIFICATION_HISTORY_LIMIT = 100

  NotificationGroup = Struct.new(:key, :cat, :label, :category, :date, :revoked, :ids, :payload, :payloads, :fallback_text, :event_count, :virtual, :action, keyword_init: true) do
    def virtual?
      virtual == true
    end
  end

  @@virtual_notification_revoked = {}
  @@virtual_notification_groups = []
  @@virtual_notification_seen_at = {}
  @@virtual_notification_mutex = Mutex.new

  def self.default_notification_type_order
    NOTIFICATION_TYPE_ORDER.dup
  end

  def self.notification_type_key(cat)
    key = cat.to_s
    key = NOTIFICATION_TYPE_ALIASES[key] if NOTIFICATION_TYPE_ALIASES.key?(key)
    NOTIFICATION_TYPE_ORDER.include?(key) ? key : nil
  end

  def self.normalize_notification_type_order(order)
    values = order.is_a?(String) ? order.split(",") : Array(order)
    normalized = []
    values.each do |value|
      key = value.to_s
      normalized << key if NOTIFICATION_TYPE_ORDER.include?(key) && !normalized.include?(key)
    end
    normalized.concat(NOTIFICATION_TYPE_ORDER - normalized)
  end

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
      payload = notification.payload
      payload = {} unless payload.is_a?(Hash)
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
          payload: payload,
          payloads: [],
          fallback_text: "",
          virtual: false,
          action: nil
        )
        by_key[key] = group
      end
      group.ids << notification.id if notification.id.to_i > 0
      group.payloads << {
        date: change_time,
        id: notification.id.to_i,
        payload: payload,
        fallback_text: notification_fallback_text(notification)
      }
    end

    groups = unify_overlapping_notification_groups(by_key.values)
    groups.each do |group|
      entries = group.payloads.sort_by { |entry| [-entry[:date].to_i, -entry[:id].to_i] }
      group.event_count ||= entries.length
      latest = entries.first
      if latest != nil
        group.date = latest[:date]
        group.payload = latest[:payload]
        group.fallback_text = latest[:fallback_text]
      end
      group.payloads = entries.map { |entry| entry[:payload] }
      group.action = action_for(group.cat, group.payload)
      group.label = group_label(group)
    end
  end

  def unify_overlapping_notification_groups(groups)
    groups = groups.dup
    unify_followed_forum_groups(groups)
    unify_blog_comment_groups(groups)
    groups
  end

  def unify_followed_forum_groups(groups)
    buckets = groups.select { |group| %w[followedthread followedforum followedforumpost].include?(group.cat.to_s) }
      .group_by { |group| [group.revoked == true, forum_thread_id(group)] }

    buckets.each do |(_revoked, thread_id), related|
      next unless thread_id.to_i > 0

      followed_thread = related.find { |group| group.cat.to_s == "followedthread" }
      next if followed_thread == nil

      related.select { |group| group.cat.to_s == "followedforumpost" }.each do |followed_forum_post|
        original_count = followed_forum_post.payloads.length
        remove_exact_duplicate_entries(followed_thread, followed_forum_post, "postid")
        if followed_forum_post.payloads.empty?
          groups.delete(followed_forum_post)
        elsif unreliable_entry_identity?(followed_thread, followed_forum_post, identity_field: "postid")
          followed_forum_post.event_count = original_count
          merge_parallel_groups(followed_thread, followed_forum_post)
          groups.delete(followed_forum_post)
        end
      end

      related.select { |group| group.cat.to_s == "followedforum" }.each do |followed_forum|
        remove_exact_duplicate_entries(followed_thread, followed_forum, "postid")
        groups.delete(followed_forum) if followed_forum.payloads.empty?
      end
    end
  end

  def unify_blog_comment_groups(groups)
    buckets = groups.select { |group| %w[blogcomment followedblogpost].include?(group.cat.to_s) }
      .group_by { |group| [group.revoked == true, blog_post_identity(group)] }

    buckets.each do |(_revoked, identity), related|
      next if identity == nil

      own_post = related.find { |group| group.cat.to_s == "blogcomment" }
      followed_post = related.find { |group| group.cat.to_s == "followedblogpost" }
      next if own_post == nil || followed_post == nil

      merge_parallel_groups(own_post, followed_post)
      groups.delete(followed_post)
    end
  end

  def forum_thread_id(group)
    group.payloads.each do |entry|
      thread_id = notification_entry_payload(entry)["threadid"].to_i
      return thread_id if thread_id > 0
    end
    0
  end

  def blog_post_identity(group)
    group.payloads.each do |entry|
      payload = notification_entry_payload(entry)
      blog = payload["blog"].to_s.downcase
      post_id = payload["postid"].to_i
      return [blog, post_id] if !blog.empty? && post_id > 0
    end
    nil
  end

  def remove_exact_duplicate_entries(winner, duplicate, identity_field)
    winner_identities = winner.payloads.filter_map do |entry|
      identity = notification_entry_payload(entry)[identity_field].to_i
      identity if identity > 0
    end
    return if winner_identities.empty?

    removed, remaining = duplicate.payloads.partition do |entry|
      identity = notification_entry_payload(entry)[identity_field].to_i
      identity > 0 && winner_identities.include?(identity)
    end
    return if removed.empty?

    winner.ids.concat(removed.map { |entry| entry[:id].to_i }.select { |id| id > 0 }).uniq!
    duplicate.payloads = remaining
    duplicate.ids = remaining.map { |entry| entry[:id].to_i }.select { |id| id > 0 }.uniq
  end

  def unreliable_entry_identity?(*groups, identity_field:)
    groups.any? do |group|
      group.payloads.any? { |entry| notification_entry_payload(entry)[identity_field].to_i <= 0 }
    end
  end

  def merge_parallel_groups(winner, duplicate)
    winner_count = winner.event_count.to_i > 0 ? winner.event_count.to_i : winner.payloads.length
    duplicate_count = duplicate.event_count.to_i > 0 ? duplicate.event_count.to_i : duplicate.payloads.length
    winner.event_count = [winner_count, duplicate_count].max
    winner.ids.concat(duplicate.ids).uniq!
    winner.payloads.concat(duplicate.payloads)
  end

  def notification_entry_payload(entry)
    payload = entry[:payload]
    payload.is_a?(Hash) ? payload : {}
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

  def sort_main_notification_groups(groups, sort_mode: :time, type_order: NotificationGroups.default_notification_type_order)
    return sort_notification_groups(groups) if sort_mode.to_sym != :type

    sort_notification_groups_by_type(groups, type_order)
  end

  def sort_notification_groups_by_type(groups, type_order)
    order = NotificationGroups.normalize_notification_type_order(type_order)
    ranks = order.each_with_index.to_h
    fallback_rank = order.size
    groups.sort_by do |group|
      type_key = NotificationGroups.notification_type_key(group.cat)
      [group.revoked ? 1 : 0, ranks.fetch(type_key, fallback_rank), -group.date.to_i, group.category.to_s, group.label.to_s]
    end
  end

  def limit_visible_notification_groups(groups, revoked_limit: NOTIFICATION_HISTORY_LIMIT)
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

    event_count = group.event_count.to_i if group.respond_to?(:event_count)
    return event_count if event_count != nil && event_count > 0

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
      if messages_grouped_by_subject?
        ["message", message_participant(payload), normalized_subject(payload)].join(":")
      else
        ["message", message_participant(payload)].join(":")
      end
    when "followedthread", "followedforum", "followedforumpost"
      ["forum", payload["threadid"].to_i].join(":")
    when "followedblog", "blogcomment", "followedblogpost"
      ["blog", payload["blog"], payload["postid"].to_i].join(":")
    when "blogfollower"
      ["blog", payload["blog"]].join(":")
    when "friend", "mtr"
      [cat, payload["user"]].join(":")
    else
      [cat, notification.id.to_i].join(":")
    end
  end

  def group_description(group)
    title = title_for(group.cat, group.payload, count: group_count(group), payloads: group.payloads)
    title = single_line_notification_text(group.fallback_text) if title.to_s.empty?
    title = single_line_notification_text(group.payload["title"]) if title.to_s.empty? && group.payload.is_a?(Hash)
    title = single_line_notification_text(group.payload["threadname"]) if title.to_s.empty? && group.payload.is_a?(Hash)
    title = single_line_notification_text(group.payload["user"]) if title.to_s.empty? && group.payload.is_a?(Hash)
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

  def title_for(cat, payload, count: 1, payloads: nil)
    payload = {} unless payload.is_a?(Hash)
    payloads = notification_payloads(payload, payloads)
    case cat.to_s
    when "message"
      message_title(payload, count: count, payloads: payloads)
    when "followedthread"
      followed_thread_title(payload, count: count, payloads: payloads)
    when "followedforum"
      followed_forum_thread_title(payload, payloads: payloads)
    when "followedforumpost"
      followed_forum_post_title(payload, count: count, payloads: payloads)
    when "mention"
      forum_mention_title(payload, payloads: payloads)
    when "followedblog"
      followed_blog_title(payload, payloads: payloads)
    when "blogcomment"
      blog_comment_title(payload, count: count, payloads: payloads, followed: false)
    when "followedblogpost"
      blog_comment_title(payload, count: count, payloads: payloads, followed: true)
    when "blogmention"
      blog_mention_title(payload, payloads: payloads)
    when "blogfollower"
      blog_follower_title(payload, count: count, payloads: payloads)
    when "friend"
      contact_title(payload, payloads: payloads)
    when "birthday"
      birthday_title(payload, payloads: payloads)
    when "groupinvitation"
      group_invitation_title(payload, payloads: payloads)
    when "mtr"
      monitor_title(payload, count: count, payloads: payloads)
    when "program_updates"
      program_updates_title(payload)
    when "update"
      update_title(payload)
    else
      ""
    end
  end

  def message_title(payload, count: 1, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    senders = payload_name_list(payloads, "sender")
    return "" if senders.empty?

    group = first_payload_value(payload, payloads, "groupname")
    subject = display_message_subject(first_payload_value(payload, payloads, "subject")) if messages_grouped_by_subject?
    if !subject.to_s.empty?
      if !group.empty?
        return np_("Notifications", "%{sender} sent a new message to %{group}: %{subject}", "%{sender} sent new messages to %{group}: %{subject}", count) % { sender: senders, group: group, subject: subject }
      end
      return np_("Notifications", "%{sender} sent a new message: %{subject}", "%{sender} sent new messages: %{subject}", count) % { sender: senders, subject: subject }
    end

    if !group.empty?
      return np_("Notifications", "%{sender} sent a new message to %{group}", "%{sender} sent new messages to %{group}", count) % { sender: senders, group: group }
    end
    np_("Notifications", "%{sender} sent a new message", "%{sender} sent new messages", count) % { sender: senders }
  end

  def followed_thread_title(payload, count: 1, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    thread = first_payload_value(payload, payloads, "threadname")
    return "" if thread.empty?

    authors = payload_name_list(payloads, "author")
    if !authors.empty?
      return np_("Notifications", "%{thread}: new post by %{authors} in a thread you follow", "%{thread}: new posts by %{authors} in a thread you follow", count) % { thread: thread, authors: authors }
    end
    np_("Notifications", "%{thread}: new post in a thread you follow", "%{thread}: new posts in a thread you follow", count) % { thread: thread }
  end

  def followed_forum_thread_title(payload, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    thread = first_payload_value(payload, payloads, "threadname")
    return "" if thread.empty?

    forum = first_payload_value(payload, payloads, "forumname")
    authors = payload_name_list(payloads, "author")
    if !forum.empty? && !authors.empty?
      return p_("Notifications", "%{thread}: new thread started by %{authors} in %{forum}, a forum you follow") % { forum: forum, authors: authors, thread: thread }
    elsif !forum.empty?
      return p_("Notifications", "%{thread}: new thread in %{forum}, a forum you follow") % { forum: forum, thread: thread }
    elsif !authors.empty?
      return p_("Notifications", "%{thread}: new thread started by %{authors} in a forum you follow") % { authors: authors, thread: thread }
    end
    p_("Notifications", "%{thread}: new thread in a forum you follow") % { thread: thread }
  end

  def followed_forum_post_title(payload, count: 1, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    thread = first_payload_value(payload, payloads, "threadname")
    return "" if thread.empty?

    forum = first_payload_value(payload, payloads, "forumname")
    authors = payload_name_list(payloads, "author")
    if !forum.empty? && !authors.empty?
      return np_("Notifications", "%{thread}: new post by %{authors} in %{forum}, a forum you follow", "%{thread}: new posts by %{authors} in %{forum}, a forum you follow", count) % { forum: forum, authors: authors, thread: thread }
    elsif !forum.empty?
      return np_("Notifications", "%{thread}: new post in %{forum}, a forum you follow", "%{thread}: new posts in %{forum}, a forum you follow", count) % { forum: forum, thread: thread }
    elsif !authors.empty?
      return np_("Notifications", "%{thread}: new post by %{authors} in a forum you follow", "%{thread}: new posts by %{authors} in a forum you follow", count) % { thread: thread, authors: authors }
    end
    np_("Notifications", "%{thread}: new post in a forum you follow", "%{thread}: new posts in a forum you follow", count) % { thread: thread }
  end

  def forum_mention_title(payload, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    author = first_payload_value(payload, payloads, "author")
    return "" if author.empty?

    thread = first_payload_value(payload, payloads, "threadname")
    message = first_payload_value(payload, payloads, "message")
    if !thread.empty?
      return p_("Notifications", "%{author} sent you a forum mention in %{thread}") % { author: author, thread: thread } if message.empty?
      return p_("Notifications", "%{author} sent you a forum mention in %{thread}: %{message}") % { author: author, thread: thread, message: message }
    end
    return p_("Notifications", "%{author} sent you a forum mention") % { author: author } if message.empty?
    p_("Notifications", "%{author} sent you a forum mention: %{message}") % { author: author, message: message }
  end

  def followed_blog_title(payload, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    blog = first_blog_display_name(payload, payloads)
    post = first_payload_value(payload, payloads, "title")
    return "" if blog.empty? || post.empty?

    p_("Notifications", "%{blog}, a blog you follow, has a new post: %{post}") % { blog: blog, post: post }
  end

  def blog_comment_title(payload, count: 1, payloads: nil, followed: false)
    payloads = notification_payloads(payload, payloads)
    blog = first_blog_display_name(payload, payloads)
    post = first_payload_value(payload, payloads, "title")
    return "" if blog.empty? || post.empty?

    authors = payload_name_list(payloads, "author")
    if followed
      if !authors.empty?
        return np_("Notifications", "%{post}, a post you follow on %{blog}, has a new comment from %{authors}", "%{post}, a post you follow on %{blog}, has new comments from %{authors}", count) % { blog: blog, authors: authors, post: post }
      end
      return np_("Notifications", "%{post}, a post you follow on %{blog}, has a new comment", "%{post}, a post you follow on %{blog}, has new comments", count) % { blog: blog, post: post }
    end

    if !authors.empty?
      return np_("Notifications", "%{post}, your post on %{blog}, has a new comment from %{authors}", "%{post}, your post on %{blog}, has new comments from %{authors}", count) % { blog: blog, authors: authors, post: post }
    end
    np_("Notifications", "%{post}, your post on %{blog}, has a new comment", "%{post}, your post on %{blog}, has new comments", count) % { blog: blog, post: post }
  end

  def blog_mention_title(payload, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    author = first_payload_value(payload, payloads, "author")
    post = first_payload_value(payload, payloads, "title")
    return "" if author.empty? || post.empty?

    message = first_payload_value(payload, payloads, "message")
    return p_("Notifications", "%{author} sent you a blog mention in %{post}") % { author: author, post: post } if message.empty?
    p_("Notifications", "%{author} sent you a blog mention in %{post}: %{message}") % { author: author, post: post, message: message }
  end

  def blog_follower_title(payload, count: 1, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    blog = first_blog_display_name(payload, payloads)
    users = payload_name_list(payloads, "user")
    return "" if blog.empty? || users.empty?

    np_("Notifications", "Blog %{blog} has a new follower: %{users}", "Blog %{blog} has new followers: %{users}", count) % { blog: blog, users: users }
  end

  def contact_title(payload, payloads: nil)
    user = first_payload_value(payload, notification_payloads(payload, payloads), "user")
    return "" if user.empty?

    p_("Notifications", "%{user} added you to their contacts") % { user: user }
  end

  def birthday_title(payload, payloads: nil)
    user = first_payload_value(payload, notification_payloads(payload, payloads), "user")
    return "" if user.empty?

    p_("Notifications", "It is %{user}'s birthday today") % { user: user }
  end

  def group_invitation_title(payload, payloads: nil)
    payloads = notification_payloads(payload, payloads)
    group = first_payload_value(payload, payloads, "groupname")
    return "" if group.empty?

    inviter = first_payload_value(payload, payloads, "inviter")
    if !inviter.empty?
      return p_("Notifications", "%{inviter} invited you to join the group %{group}") % { inviter: inviter, group: group }
    end
    p_("Notifications", "You have been invited to join the group %{group}") % { group: group }
  end

  def monitor_title(payload, count: 1, payloads: nil)
    user = first_payload_value(payload, notification_payloads(payload, payloads), "user")
    return "" if user.empty?

    np_("Notifications", "%{user} came online", "%{user} came online more than once", count) % { user: user }
  end

  def notification_payloads(payload, payloads)
    values = Array(payloads).select { |value| value.is_a?(Hash) }
    values = [payload] if values.empty? && payload.is_a?(Hash)
    values
  end

  def first_payload_value(payload, payloads, key)
    (notification_payloads(payload, payloads) + [payload]).each do |value|
      text = single_line_notification_text(value[key])
      return text unless text.empty?
    end
    ""
  end

  def first_blog_display_name(payload, payloads)
    name = first_payload_value(payload, payloads, "blogname")
    name.empty? ? first_payload_value(payload, payloads, "blog") : name
  end

  def payload_name_list(payloads, key)
    values = []
    incomplete = false
    payloads.each do |payload|
      name = single_line_notification_text(payload[key])
      if name.empty?
        incomplete = true
      else
        values << name
      end
    end
    format_notification_name_list(values, include_others: incomplete && !values.empty?)
  end

  def format_notification_name_list(values, include_others: false, limit: 4)
    names = []
    seen = {}
    Array(values).each do |value|
      name = single_line_notification_text(value)
      next if name.empty?

      key = name.downcase
      next if seen[key]

      seen[key] = true
      names << name
    end
    more = include_others || names.size > limit.to_i
    names = names.first(limit.to_i)
    return "" if names.empty?
    return "#{names.join(", ")} #{p_("Notifications", "and others")}" if more
    return names[0] if names.size == 1

    "#{names[0...-1].join(", ")} #{p_("Notifications", "and")} #{names[-1]}"
  end

  def display_message_subject(value)
    single_line_notification_text(value).sub(/\A(?:re:\s*)+/i, "").strip
  end

  def single_line_notification_text(value)
    value.to_s.gsub(/[\r\n\t]+/, " ").gsub(/ {2,}/, " ").strip
  end

  def notification_fallback_text(notification)
    text = notification.notification.to_s if notification.respond_to?(:notification)
    text = notification.alert.to_s if text.to_s.empty? && notification.respond_to?(:alert)
    single_line_notification_text(text)
  end

  def blog_post_title(payload)
    title = payload["title"].to_s
    blog = blog_display_name(payload)
    return title if blog.empty? || title.include?(blog)
    title.empty? ? blog : "#{blog}: #{title}"
  end

  def blog_display_name(payload)
    name = single_line_notification_text(payload["blogname"])
    name.empty? ? single_line_notification_text(payload["blog"]) : name
  end

  def update_title(payload)
    version = single_line_notification_text(payload["version"])
    return p_("Notifications", "A new Elten version is available") if version.empty?

    p_("Notifications", "A new Elten version is available: %{version}") % { version: version }
  end

  def program_updates_title(payload)
    count = payload["count"].to_i
    count = 1 if count <= 0
    known_names = Array(payload["names"])
      .map { |name| single_line_notification_text(name) }
      .reject(&:empty?)
      .uniq { |name| name.downcase }
    names = format_notification_name_list(known_names, include_others: count > known_names.size)
    if names.empty?
      return np_("Notifications", "A program update is available", "Program updates are available", count)
    end
    np_("Notifications", "A program update is available: %{programs}", "Program updates are available: %{programs}", count) % { programs: names }
  end

  def action_for(cat, payload)
    payload = {} unless payload.is_a?(Hash)
    case cat.to_s
    when "message"
      Proc.new { open_message(payload) }
    when "followedthread", "followedforum", "followedforumpost", "mention"
      Proc.new { open_forum_thread(payload, cat.to_s) }
    when "followedblog", "blogcomment", "followedblogpost", "blogmention"
      Proc.new { open_blog_post(payload, cat.to_s) }
    when "blogfollower"
      Proc.new { insert_scene(Scene_Blog_Followers.new(nil), true, return_to_main: true) }
    when "friend"
      Proc.new { insert_scene(Scene_Users_AddedMeToContacts.new(true), true) }
    when "birthday"
      Proc.new { open_birthday(payload) }
    when "groupinvitation"
      Proc.new { insert_scene(Scene_Forum.new(nil, nil, 4), true) }
    else
      nil
    end
  end

  def open_birthday(payload)
    user = payload["user"].to_s
    if user.empty?
      insert_scene(Scene_Contacts.new(1), true)
    else
      usermenu(user)
    end
  end

  def open_message(payload)
    participant = message_participant(payload)
    scene = if participant.to_s.empty?
      Scene_Messages.new(true, close_to_main: true)
    else
      subject = message_subject(payload) if messages_grouped_by_subject?
      Scene_Messages.new(user: participant, subject: subject, close_to_main: true)
    end
    insert_scene(scene, true, return_to_main: true)
  end

  def messages_grouped_by_subject?
    !LocalConfig['MessagesDefaultToAllMessages', type: :bool]
  end

  def message_participant(payload)
    receiver = payload["receiver"].to_s
    return receiver if receiver.start_with?("[")

    payload["sender"].to_s
  end

  def message_subject(payload)
    payload["subject"].to_s.delete("\r\n").gsub(/re: /i, "")
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

  def open_blog_post(payload, cat=nil)
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
    post.followed = true if cat.to_s == "followedblogpost"
    post.mention = blog_mention_from_payload(payload) if cat.to_s == "blogmention" && payload["mentionid"].to_i > 0
    insert_scene(Scene_Blog_Read.new(post, -1, 0, 0, Scene_Main.new), true, return_to_main: true)
  end

  def blog_mention_from_payload(payload)
    mention = Struct_Blog_Mention.new
    mention.id = payload["mentionid"].to_i
    mention.blog = payload["blog"].to_s
    mention.postid = payload["postid"].to_i
    mention.author = payload["author"].to_s
    mention.message = payload["message"].to_s
    mention
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
    EltenAPI::NotificationService.revoke_active_notifications(group.ids)
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
    EltenAPI::NotificationService.revoke_active_notifications
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
