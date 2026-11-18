# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class Scene_Honors
  def initialize(user = nil, toscene = nil, honor = nil)
    @user = user
    @toscene = toscene
    @honor = honor
  end

  def main
    begin
      @honors = EltenLink::Honors.list(elten_link, user: @user)
    rescue EltenLink::Error
      alert(_("Error"))
      $scene = Scene_Main.new
      return
    end

    if @user != nil && @honors.empty?
      alert(p_("Honors", "The user has not been awarded any honors."))
      $scene = @toscene || Scene_Main.new
      return
    end

    selected = @honors.index { |honor| honor.id == @honor } || 0
    header = if @user == nil
               p_("Honors", "Badges")
             else
               p_("Honors", "Badges of %{user}") % { user: @user }
             end
    @sel = ListBox.new(@honors.map { |honor| honor_label(honor) }, header: header, index: selected, flags: 0, quiet: false)
    @sel.bind_context { |menu| context(menu) }

    loop do
      loop_update
      @sel.update
      if (key_pressed?(:key_enter) || key_pressed?(:key_right)) && @sel.index < @honors.size
        $scene = Scene_Honors_Users.new(@honors[@sel.index].id, @user, @toscene)
      elsif key_pressed?(:key_escape)
        $scene = @toscene || Scene_Main.new
      end
      break if $scene != self
    end
  end

  def honor_label(honor)
    text = honor.name.to_s
    text += " (#{p_("Honors", "Level")} #{honor.level + 1})" if honor.levels.size > 1 && @user != nil
    text += ":\r\n#{honor.description}\r\n"
    if honor.levels.size == 1
      text += honor.levels.first.to_s
    elsif honor.levels.size > 1
      start = @user == nil ? 0 : honor.level
      (start...honor.levels.size).each do |index|
        text += "#{p_("Honors", "Level")}#{index + 1}: #{honor.levels[index]}\r\n"
      end
    end
    text
  end

  def context(menu)
    return if @honors.empty? || @sel.index >= @honors.size

    honor = @honors[@sel.index]
    menu.option(p_("Honors", "Set as primary honor")) do
      begin
        EltenLink::Honors.set_main(elten_link, honor)
      rescue EltenLink::Error
        alert(_("Error"))
      else
        alert(p_("Honors", "The honor has been set as the primary honor."))
      end
    end

    if Session.moderator == 1
      menu.option(p_("Honors", "Grant a badge")) do
        user = input_user(p_("Honors", "Who should receive this honor?"))
        grant(user, honor) unless user == nil
      end
    end

    menu.option(_("Refresh")) do
      $scene = Scene_Honors.new(@user, @toscene, honor.id)
    end
  end

  def grant(user, honor)
    level = 0
    if honor.levels.size > 1
      choices = honor.levels.each_with_index.map do |challenge, index|
        "#{p_("Honors", "Level")} #{index + 1}: #{challenge}"
      end
      level = selector(choices, header: p_("Honors", "Select the level to grant"), start_index: 0, cancel_index: -1)
      return if level < 0
    end

    begin
      EltenLink::Honors.award(elten_link, user: user, honor: honor, level: level)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(p_("Honors", "The badge has been granted"))
    end
  end
end

class Scene_Honors_Users
  def initialize(honor, user = nil, toscene = nil)
    @honor = honor
    @user = user
    @toscene = toscene
  end

  def main
    honor_users = fetch_honor_users
    if honor_users == nil
      $scene = Scene_Honors.new(@user, @toscene, @honor)
      return
    end

    @users, labels = honor_user_rows(honor_users)

    @sel = ListBox.new(labels.map { |label| user_with_status(label, false) }, header: "", index: 0, flags: 0, quiet: false)
    apply_user_status_states(@sel, @users, false)
    @sel.bind_context { |menu| context(menu) }
    @refresh = false
    loop do
      loop_update
      @sel.update
      if key_pressed?(:key_escape) || key_pressed?(:key_left)
        $scene = Scene_Honors.new(@user, @toscene, @honor)
      elsif key_pressed?(:key_enter) && !@users.empty?
        usermenu(@users[@sel.index], false)
      end
      if @refresh
        @refresh = false
        refresh_honor_users(@sel.index)
      end
      break if $scene != self
    end
  end

  def context(menu)
    menu.useroption(@users[@sel.index]) unless @users.empty?
    menu.option(_("Refresh")) { @refresh = true }
  end

  def fetch_honor_users
    EltenLink::Honors.users(elten_link, @honor)
  rescue EltenLink::Error
    alert(_("Error"))
    nil
  end

  def honor_user_rows(honor_users)
    grouped = honor_users.group_by(&:level)
    users = []
    labels = []
    grouped.keys.sort.reverse_each do |level|
      grouped[level].sort_by { |entry| entry.name.downcase }.each do |entry|
        users << entry.name
        labels << "#{entry.name} (#{p_("Honors", "level")}#{level + 1})"
      end
    end
    [users, labels]
  end

  def refresh_honor_users(index)
    honor_users = fetch_honor_users
    if honor_users == nil
      @sel.focus
      return false
    end

    @users, labels = honor_user_rows(honor_users)
    @sel.options = labels.map { |label| user_with_status(label, false) }
    apply_user_status_states(@sel, @users, false)
    @sel.index = [[index.to_i, 0].max, [@users.size - 1, 0].max].min
    @users.empty? ? @sel.focus : @sel.sayoption
    true
  end
end

class Struct_Honor < EltenLink::Honor
end
