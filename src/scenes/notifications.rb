# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

class Scene_Notifications
  include NotificationGroups

  def initialize(quiet=false)
    @quiet = quiet
    @index = 0
  end

  def main
    if Session.name == "guest"
      alert(_("This section is unavailable for guests")) if @quiet != true
      $scene = Scene_Main.new
      return
    end

    load_groups
    if @groups.empty?
      alert(p_("Notifications", "No notifications.")) if @quiet != true
      $scene = Scene_Main.new
      return
    end

    @list.focus
    loop do
      loop_update
      @list.update
      if key_pressed?(:key_escape) || @list.collapsed?
        $scene = Scene_Main.new
      elsif @list.selected? || @list.expanded?
        open_current
      end
      break if $scene != self
    end
  end

  private

  def load_groups(index=@index)
    notifications = fetch_notifications
    groups = build_notification_groups(notifications, include_revoked: true)
    append_virtual_notification_groups(groups, collect_virtual_notification_groups, include_revoked: true)
    @groups = limit_visible_notification_groups(sort_notification_groups(groups))
    @index = [[index.to_i, 0].max, [@groups.size - 1, 0].max].min
    @list = TableBox.new(notification_columns, notification_rows(@groups), index: @index, header: p_("Notifications", "Notifications"), quiet: false)
    apply_notification_group_states(@list, @groups)
    @list.bind_context { |menu| context(menu) }
  end

  def fetch_notifications
    EltenLink::Notifications.list(elten_link, all: true)
  rescue EltenLink::Error => e
    Log.warning("Notifications list failed: #{e.message}")
    alert(_("Error")) if @quiet != true
    []
  end

  def context(menu)
    return if current_group == nil

    menu.option(p_("Notifications", "Open"), nil, :enter) { open_current }
    if !current_group.revoked && (current_group.ids.size > 0 || current_group.virtual?)
      menu.option(p_("Notifications", "Mark as read"), nil, "w") { revoke_current }
    end
    if revocable_notification_groups?(@groups)
      menu.option(p_("Notifications", "Mark all as read"), nil, "W") { revoke_all }
    end
    menu.option(_("Refresh"), nil, "r") do
      @index = @list.index
      load_groups(@index)
      @list.sayoption if @groups.size > 0
    end
  end

  def open_current
    group = current_group
    return if group == nil

    old_index = @list.index
    opened = open_notification_group(group)
    if opened
        2.times{loop_update}
      load_groups(old_index)
      @list.sayoption if @groups.size > 0
    end
  end

  def revoke_current
    group = current_group
    return if group == nil

    old_index = @list.index
    if revoke_notification_group(group)
      load_groups(old_index)
      @list.sayoption if @groups.size > 0
    end
  end

  def revoke_all
    old_index = @list.index
    if revoke_all_notification_groups(@groups)
      load_groups(old_index)
      @list.sayoption if @groups.size > 0
    end
  end

  def current_group
    return nil if @groups.empty? || @list == nil

    @groups[@list.index]
  end
end
