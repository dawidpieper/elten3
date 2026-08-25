# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

class Scene_Notifications
  include NotificationGroups

  MODES = [:history, :whatsnew].freeze

  def self.whatsnew
    scene = new(false, mode: :whatsnew)
    scene.prepare
  end

  def initialize(quiet=false, mode: :history)
    raise ArgumentError, "Invalid notifications mode: #{mode}" if !MODES.include?(mode)
    @quiet = quiet
    @mode = mode
    @index = 0
  end

  def prepare
    load_groups
    @groups.empty? ? nil : self
  end

  def main
    unless Session.logged?
      alert(_("This section is unavailable for guests")) if @quiet != true
      $scene = Scene_Main.new
      return
    end

    load_groups if @groups == nil
    if @groups.empty?
      alert(empty_message) if @quiet != true
      $scene = Scene_Main.new
      return
    end

    @list.focus
    loop do
      loop_update
      notifications_changed = whatsnew? && Session.notifications_updated?
      if whatsnew? && ($main_notifications_changed == true || notifications_changed)
        $main_notifications_changed = false
        @index = @list.index
        load_groups(@index)
        finish_reload
        break if $scene != self
      end
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

  def whatsnew?
    @mode == :whatsnew
  end

  def empty_message
    whatsnew? ? p_("Notifications", "There is nothing new.") : p_("Notifications", "No notifications.")
  end

  def notification_list_header
    whatsnew? ? p_("Notifications", "Notifications") : p_("Notifications", "Notification history")
  end

  def load_groups(index=@index)
    notifications = fetch_notifications
    if whatsnew?
      @groups = build_active_main_notification_groups(notifications)
    else
      groups = build_notification_groups(notifications, include_revoked: true)
      append_virtual_notification_groups(groups, collect_virtual_notification_groups, include_revoked: true)
      @groups = limit_visible_notification_groups(sort_notification_groups(groups))
    end
    @index = [[index.to_i, 0].max, [@groups.size - 1, 0].max].min
    @list = TableBox.new(notification_columns, notification_rows(@groups), index: @index, header: notification_list_header, quiet: whatsnew?)
    apply_notification_group_states(@list, @groups) if !whatsnew?
    @list.bind_context { |menu| context(menu) }
  end

  def fetch_notifications
    return EltenAPI::NotificationService.active_notifications if whatsnew?

    notifications = EltenLink::Notifications.list(elten_link, all: true)
    EltenAPI::NotificationService.synchronize_active_notifications(notifications)
    notifications
  rescue EltenLink::Error => e
    Log.warning("Notifications list failed: #{e.message}")
    alert(_("Error")) if @quiet != true
    []
  end

  def context(menu)
    return if current_group == nil

    menu.option(p_("Notifications", "Open")) { open_current }
    if !current_group.revoked && (current_group.ids.size > 0 || current_group.virtual?)
      menu.option(p_("Notifications", "Mark as read"), nil, "w") { revoke_current }
    end
    if revocable_notification_groups?(@groups)
      menu.option(p_("Notifications", "Mark all as read"), nil, "W") { revoke_all }
    end
    menu.option(_("Refresh"), nil, "r") do
      @index = @list.index
      EltenAPI::NotificationService.refresh_active_notifications if whatsnew?
      load_groups(@index)
      finish_reload
    end
  end

  def finish_reload
    if whatsnew? && @groups.empty? && $scene == self
      alert(empty_message) if @quiet != true
      $scene = Scene_Main.new
    elsif @groups.size > 0
      @list.sayoption
    end
  end

  def open_current
    group = current_group
    return if group == nil

    old_index = @list.index
    opened = open_notification_group(group)
    if opened && $scene == self
      load_groups(old_index)
      finish_reload
    end
  end

  def revoke_current
    group = current_group
    return if group == nil

    old_index = @list.index
    if revoke_notification_group(group)
      load_groups(old_index)
      finish_reload
    end
  end

  def revoke_all
    old_index = @list.index
    if revoke_all_notification_groups(@groups)
      load_groups(old_index)
      finish_reload
    end
  end

  def current_group
    return nil if @groups.empty? || @list == nil

    @groups[@list.index]
  end
end
