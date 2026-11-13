# A part of Elten - Elten desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

require "date"

module TasksSceneHelpers
  def task_reminders(project=nil)
    data = EltenLink::Tasks.reminder_settings(elten_link, project)
    profile = data["preferences"]
    profile["timezone"] ||= EltenLink::TimeZones.system
    saved_profile = JSON.generate(profile)
    projects = project ? [project] : [nil] + EltenLink::Tasks.projects(elten_link)
    overrides, saved_overrides, pages = {}, {}, {}
    if project
      overrides[project.id] = data["override"]
      saved_overrides[project.id] = JSON.generate(data["override"])
    else
      saved_delivery = EltenLink::Accounts.config(elten_link)["wn_tasks"].to_i
      delivery = ListBox.new([p_("Account", "Show in what's new"), p_("Account", "Alert on PC"), p_("Account", "Notify on mobile devices")],
        header: p_("Tasks", "Delivery channels"), flags: ListBox::Flags::MultiSelection)
      3.times { |index| delivery.selected[index] = (saved_delivery & (1 << index)) == 0 }
      category = ListBox.new([p_("Tasks", "Global")] + projects.drop(1).map { |item| task_project_label(item) },
        header: p_("Tasks", "Notification settings"))
    end
    page = proc do |item|
      key = item && item.id
      unless pages.key?(key)
        if item && !overrides.key?(key)
          override = EltenLink::Tasks.reminder_settings(elten_link, item)["override"]
          overrides[key] = override
          saved_overrides[key] = JSON.generate(override)
        end
        fields = task_reminder_fields(profile, item, overrides[key])
        fields.unshift(delivery) unless item
        fields << task_reminder_timezone(profile) if !item || project && !data["configured"]
        pages[key] = fields
      end
      pages[key]
    end
    save = Button.new(_("Save"))
    cancel = Button.new(_("Cancel"))
    form = Form.new([category].compact + page.call(projects.first) + [save, cancel])
    form.cancel_button = cancel
    if category
      current = 0
      category.on(:move) do
        begin
          fields = page.call(projects[category.index])
          form.replace_fields([category] + fields + [save, cancel])
          current = category.index
        rescue EltenLink::Error => error
          category.index = current
          Log.warning("Task reminder settings failed: #{error.message}")
          alert(_("Error"))
          category.focus
        end
      end
    end
    cancel.on(:press) { form.resume }
    save.on(:press) do
      if profile["timezone"] == nil
        alert(p_("Tasks", "Select a time zone for reminders"))
        next
      end
      begin
        if delivery
          flags = (0...3).sum { |index| delivery.selected[index] ? 0 : 1 << index }
          if flags != saved_delivery
            EltenLink::Accounts.update_config(elten_link, { "wn_tasks" => flags })
            saved_delivery = flags
          end
        end
        if !project && (!data["configured"] || JSON.generate(profile) != saved_profile)
          EltenLink::Tasks.update_reminder_settings(elten_link, profile)
          saved_profile = JSON.generate(profile)
          data["configured"] = true
        end
        overrides.each do |id, override|
          next if !project && JSON.generate(override) == saved_overrides[id]
          EltenLink::Tasks.update_reminder_settings(elten_link, override.merge("timezone" => profile["timezone"]), id)
          saved_overrides[id] = JSON.generate(override)
        end
        form.resume
      rescue EltenLink::Error => error
        Log.warning("Task reminder settings failed: #{error.message}")
        alert(_("Error"))
      end
    end
    form.wait
  rescue EltenLink::Error => error
    Log.warning("Task reminder settings failed: #{error.message}")
    alert(_("Error"))
  end

  def task_reminder_fields(profile, project, override)
    if project
      modes = %w[inherit custom off]
      mode = ListBox.new([p_("Tasks", "Use default reminders"), p_("Tasks", "Custom reminders"), p_("Tasks", "Reminders disabled")],
        header: p_("Tasks", "Reminders"), index: modes.index(override["mode"]) || 0)
      kind = project.personal? ? "personal" : project.owned_by?(Session.name) ? "owned" : "shared"
      mode.on(:move) do
        if modes[mode.index] == "custom" && override["mode"] == "inherit"
          override.merge!(JSON.parse(JSON.generate(profile["defaults"][kind])))
        end
        override["mode"] = modes[mode.index]
      end
      edit = Button.new(p_("Tasks", "Edit reminders"))
      edit.on(:press) do
        value = override["mode"] == "inherit" ? profile["defaults"][kind] : override
        updated = task_reminder_profile(value, personal: project.personal?)
        if updated
          override.merge!(updated)
          override["mode"] = "custom"
          mode.index = 1
        end
      end
      [mode, edit]
    else
      labels = [p_("Tasks", "Personal tasks"), p_("Tasks", "Owned projects"), p_("Tasks", "Shared projects")]
      %w[personal owned shared].each_with_index.map do |kind, index|
        button = Button.new(labels[index])
        button.on(:press) do
          updated = task_reminder_profile(profile["defaults"][kind], personal: kind == "personal")
          profile["defaults"][kind] = updated if updated
        end
        button
      end
    end
  end

  def task_reminder_profile(value, personal: false)
    scopes = %w[mine mine_or_unassigned all]
    scope = ListBox.new([p_("Tasks", "Assigned to me"), p_("Tasks", "Assigned to me or unassigned"), p_("Tasks", "All tasks")],
      header: p_("Tasks", "Notify about"), index: scopes.index(value["scope"]) || 0)
    rules = JSON.parse(JSON.generate(value["rules"]))
    target_labels = [p_("Account", "Notifications list"), p_("Account", "Computer"), p_("Account", "Mobile devices")]
    rows = proc do
      rules.map do |rule|
        time = format("%02d:%02d", rule["minute_of_day"] / 60, rule["minute_of_day"] % 60)
        label = p_("Tasks", "%{count} days before the due date at %{time}") % { count: rule["days"], time: time }
        [label, rule["targets"].map { |target| target_labels[%w[list pc mobile].index(target)] }.join(", ")]
      end
    end
    table = TableBox.new([p_("Tasks", "Reminder"), p_("Tasks", "Deliver to")], rows.call, header: p_("Tasks", "Reminders"))
    add = Button.new(p_("Tasks", "Add reminder"))
    edit = Button.new(_("Edit"))
    remove = Button.new(_("Delete"))
    done = Button.new(_("Done"))
    cancel = Button.new(_("Cancel"))
    form = Form.new((personal ? [] : [scope]) + [table, add, edit, remove, done, cancel])
    accepted = false
    refresh = proc do
      index = table.index
      table.rows = rows.call
      table.reload
      table.index = [[index, rules.size - 1].min, 0].max
    end
    add.on(:press) do
      rule = task_reminder_rule
      rules << rule if rule
      refresh.call
    end
    edit.on(:press) do
      next if rules.empty?
      rule = task_reminder_rule(rules[table.index])
      rules[table.index] = rule if rule
      refresh.call
    end
    remove.on(:press) do
      next if rules.empty?
      rules.delete_at(table.index)
      refresh.call
    end
    table.bind_context do |menu|
      menu.option(p_("Tasks", "Add reminder"), nil, "n") { add.press }
      unless rules.empty?
        menu.option(_("Edit")) { edit.press }
        menu.option(_("Delete"), nil, :del) { remove.press }
      end
    end
    table.sel.on(:select) { edit.press }
    done.on(:press) { accepted = true; form.resume }
    cancel.on(:press) { form.resume }
    form.cancel_button = cancel
    form.wait
    accepted ? { "scope" => personal ? "all" : scopes[scope.index], "rules" => rules.uniq } : nil
  end

  def task_reminder_rule(rule=nil)
    rule ||= { "days" => 0, "minute_of_day" => 540, "targets" => %w[list pc mobile] }
    days = EditBox.new(p_("Tasks", "Days before the due date"), type: EditBox::Flags::Numbers, text: rule["days"].to_s)
    hour = ListBox.new((0..23).map { |value| format("%02d", value) }, header: p_("Tasks", "Hour"), index: rule["minute_of_day"] / 60)
    minute = ListBox.new((0..59).map { |value| format("%02d", value) }, header: p_("Tasks", "Minute"), index: rule["minute_of_day"] % 60)
    targets = ListBox.new([p_("Account", "Notifications list"), p_("Account", "Computer"), p_("Account", "Mobile devices")],
      header: p_("Tasks", "Deliver to"), flags: ListBox::Flags::MultiSelection)
    %w[list pc mobile].each_with_index { |target, index| targets.selected[index] = rule["targets"].include?(target) }
    save = Button.new(_("Save"))
    cancel = Button.new(_("Cancel"))
    form = Form.new([days, hour, minute, targets, save, cancel])
    result = nil
    save.on(:press) do
      if !days.text.match?(/\A\d+\z/) || days.text.to_i > 365 || targets.multiselections.empty?
        alert(p_("Tasks", "Enter a valid advance time and select at least one delivery target"))
        next
      end
      result = { "days" => days.text.to_i, "minute_of_day" => hour.index * 60 + minute.index,
        "targets" => targets.multiselections.map { |index| %w[list pc mobile][index] } }
      form.resume
    end
    cancel.on(:press) { form.resume }
    form.cancel_button = cancel
    form.wait
    result
  end

  def task_reminder_timezone(profile)
    button = Button.new("")
    update = proc { button.label = "#{p_("Tasks", "Reminder time zone")}: #{profile["timezone"] || p_("Tasks", "Not specified")}" }
    update.call
    button.on(:press) do
      zones = EltenLink::TimeZones.identifiers.dup
      timezone = profile["timezone"]
      zones << timezone if timezone && !zones.include?(timezone)
      choices = zones.map { |zone| [zone, EltenLink::TimeZones.label(zone, Date.today)] }.sort_by { |_, label| label.downcase }
      zones, labels = choices.transpose
      selected = selector(labels, header: p_("Tasks", "Reminder time zone"), start_index: zones.index(timezone) || 0, cancel_index: -1)
      profile["timezone"] = zones[selected] if selected >= 0
      update.call
      button.focus
    end
    button
  end

  def task_project_label(project)
    return p_("Tasks", "Personal tasks") if project.personal?

    label = project.name.to_s
    label = p_("Tasks", "Unnamed project") if label.empty?
    if project.author.to_s != Session.name.to_s
      label += ", #{p_("Tasks", "by %{user}") % { user: project.author }}"
    end
    label
  end

  def task_label(task, project=nil, parent=nil)
    parts = [task.name.to_s]
    due_time = effective_task_due_time(task, parent)
    if task.completed?
      parts << p_("Tasks", "completed")
    elsif due_time != nil && due_time.to_i < Time.now.to_i
      parts << p_("Tasks", "overdue")
    end
    if due_time != nil
      due_label = p_("Tasks", "due %{date}") % { date: task_date_label(due_time) }
      due_label += " (#{p_("Tasks", "task due date")})" if !task.due? && parent != nil
      parts << due_label
    end
    parts << task_repeat_label(task) if task.recurring?
    if task.performer != nil
      performer_label = task.completed? ? p_("Tasks", "completed by %{user}") : p_("Tasks", "assigned to %{user}")
      parts << (performer_label % { user: task.performer })
    end
    if task.children_count.positive?
      parts << (np_("Tasks", "%{count} goal", "%{count} goals", task.children_count) % { count: task.children_count })
    end
    parts << task_project_label(project) if project != nil
    parts.join(", ")
  end

  def task_details_text(task, project=nil, parent=nil)
    lines = [task_label(task, project, parent)]
    lines << task.description.to_s unless task.description.to_s.empty?
    lines << (p_("Tasks", "Created by %{user}") % { user: task.creator })
    lines << (p_("Tasks", "Created %{date}") % { date: format_date(task.creationtime, false, false) })
    if task.completed? && task.completiontime != nil
      lines << (p_("Tasks", "Completed %{date}") % { date: format_date(task.completiontime, false, false) })
    end
    lines.join("\r\n")
  end

  def show_task_details(task, project=nil, parent=nil)
    input_text(
      p_("Tasks", "Task details"),
      flags: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly,
      text: task_details_text(task, project, parent),
      escapable: true
    )
  end

  def task_dialog(projects, participants_by_project, selected_project, task=nil, parent=nil)
    goal = parent != nil
    parent_id = goal ? parent.id : (task == nil ? 0 : task.parent)
    available = goal ? [selected_project] : projects
    project_index = available.index { |project| project.id == selected_project.id } || 0
    performer_users = participants_by_project.fetch(available[project_index].id, []).dup
    current_performer = task == nil ? nil : task.performer
    current_performer_index = current_performer == nil ? nil : performer_users.index(current_performer)
    performer_index = current_performer_index == nil ? 0 : current_performer_index + 1
    due_time = if task != nil && task.due?
                 task.plantime
               elsif goal && parent.due?
                 parent.plantime
               else
                 Time.now
               end
    min_year = [due_time.year, Time.now.year].min
    max_year = [due_time.year, Time.now.year].max + 20
    if goal
      parent_due_label = if parent.due?
                           p_("Tasks", "Task due date: %{date}") % { date: task_date_label(parent.plantime) }
                         else
                           p_("Tasks", "Task due date: not set")
                         end
      due_entries = [[parent_due_label, :inherit]]
      if parent.due?
        due_entries += task_due_presets(Date.today, task_date(parent.plantime))
        due_entries << [p_("Tasks", "Custom due date"), :custom]
      end
    else
      due_entries = [[p_("Tasks", "No due date"), :none]] +
                    task_due_presets(Date.today) +
                    [[p_("Tasks", "Custom due date"), :custom]]
    end
    due_index = 0
    if task != nil && task.due? && (!goal || parent.due?)
      current_date = task_date(task.plantime)
      due_index = due_entries.index { |_, value| value == current_date } || due_entries.size - 1
    end
    repeat_values = [0, 1, 7, -1, :custom]
    repeat_labels = [
      p_("Tasks", "Does not repeat"),
      p_("Tasks", "Daily"),
      p_("Tasks", "Weekly"),
      p_("Tasks", "Monthly on the due day"),
      p_("Tasks", "Every N days")
    ]
    current_frequency = task == nil || goal ? 0 : task.frequency
    repeat_index = repeat_values.index(current_frequency) || repeat_values.index(:custom)
    custom_repeat = repeat_values[repeat_index] == :custom ? current_frequency.to_s : "2"
    fields = [
      edt_name = EditBox.new(p_("Tasks", "Task name"), text: task == nil ? "" : task.name, quiet: true),
      edt_description = EditBox.new(
        p_("Tasks", "Description"),
        type: EditBox::Flags::MultiLine,
        text: task == nil ? "" : task.description,
        quiet: true
      ),
      lst_project = ListBox.new(
        available.map { |project| task_project_label(project) },
        header: p_("Tasks", "Project"),
        index: project_index
      ),
      lst_performer = ListBox.new(
        [p_("Tasks", "No performer")] + performer_users,
        header: p_("Tasks", "Performer"),
        index: performer_index
      ),
      due_control = ListBox.new(
        due_entries.map(&:first),
        header: goal ? p_("Tasks", "Goal due date") : p_("Tasks", "Due date"),
        index: due_index
      ),
      btn_due = DateField.new(p_("Tasks", "Custom due date"), date: due_time, years: (min_year..max_year)),
      lst_repeat = ListBox.new(repeat_labels, header: p_("Tasks", "Repeat"), index: repeat_index),
      edt_repeat_days = EditBox.new(p_("Tasks", "Number of days"), type: EditBox::Flags::Numbers, text: custom_repeat, quiet: true),
      btn_save = Button.new(task == nil ? p_("Tasks", "Add task") : _("Save")),
      btn_cancel = Button.new(_("Cancel"))
    ]
    form = Form.new(fields)
    form.hide(lst_project) if goal
    custom_repeat_selected = proc { !goal && repeat_values[lst_repeat.index.to_i] == :custom }
    lst_repeat.on(:move) do
      custom_repeat_selected.call ? form.show(edt_repeat_days) : form.hide(edt_repeat_days)
    end
    lst_repeat.trigger(:move)
    form.hide(lst_repeat) if goal
    selected_due = proc { due_entries[due_control.index.to_i][1] }
    manual_due_selected = proc { selected_due.call == :custom }
    due_control.on(:move) do
      manual_due_selected.call ? form.show(btn_due) : form.hide(btn_due)
    end
    due_control.trigger(:move)
    lst_project.on(:move) do
      selected_user = lst_performer.index.to_i.zero? ? nil : performer_users[lst_performer.index - 1]
      project = available[lst_project.index]
      performer_users = participants_by_project.fetch(project.id, []).dup
      lst_performer.options = [p_("Tasks", "No performer")] + performer_users
      lst_performer.index = selected_user != nil && performer_users.include?(selected_user) ?
        performer_users.index(selected_user) + 1 : 0
    end
    accepted = false
    plantime = nil
    frequency = 0
    init_name = edt_name.text.to_s
    init_desc = edt_description.text.to_s
    dialog_open
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) ||
          ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && fields[form.index] == btn_cancel)
        break if (edt_name.text.to_s == init_name && edt_description.text.to_s == init_desc) || confirm(p_("Tasks", "Are you sure you want to close without saving?"))
      end
      if (key_pressed?(:key_enter) || key_pressed?(:key_space)) && fields[form.index] == btn_save
        if edt_name.text.to_s.strip.empty?
          alert(p_("Tasks", "Enter a task name"))
          edt_name.focus
        else
          due = selected_due.call
          plantime = if due == :custom
                       btn_due.time
                     elsif due.is_a?(Date)
                       Time.local(due.year, due.month, due.day, 23, 59, 59)
                     end
          if plantime != nil && goal && parent.due? && plantime.to_i > parent.plantime.to_i
            alert(p_("Tasks", "The goal due date cannot be after the task due date"))
            next
          end
          frequency = goal ? 0 : repeat_values[lst_repeat.index.to_i]
          if frequency == :custom
            frequency = edt_repeat_days.text.to_i
            if frequency <= 0 || frequency > 2_147_483_647
              alert(p_("Tasks", "Enter a valid number of days"))
              edt_repeat_days.focus
              next
            end
          end
          if frequency != 0 && plantime == nil
            alert(p_("Tasks", "A repeating task needs a due date"))
            due_control.focus
            next
          end
          accepted = true
          break
        end
      end
    end
    dialog_close
    return nil unless accepted

    {
      project: available[lst_project.index],
      name: edt_name.text.to_s,
      description: edt_description.text.to_s,
      plantime: plantime,
      performer: lst_performer.index.to_i.zero? ? nil : performer_users[lst_performer.index - 1],
      parent: parent_id.to_i,
      frequency: frequency
    }
  rescue ArgumentError
    alert(p_("Tasks", "Select a valid due date"))
    nil
  end

  def task_date_label(time)
    format_localized_date(task_date(time))
  end

  def task_repeat_label(task)
    case task.frequency
    when 1
      p_("Tasks", "repeats daily")
    when 7
      p_("Tasks", "repeats weekly")
    when -1
      if task.due?
        p_("Tasks", "repeats monthly on day %{day}") % { day: task.plantime.day }
      else
        p_("Tasks", "repeats monthly")
      end
    else
      np_("Tasks", "repeats every %{count} day", "repeats every %{count} days", task.frequency) % { count: task.frequency }
    end
  end

  def task_date(time)
    Date.new(time.year, time.month, time.day)
  end

  def task_due_presets(today, limit=nil)
    presets = []
    add = proc do |label, date|
      next if limit != nil && date > limit
      next if presets.any? { |_, existing| existing == date }

      presets << [label % { date: format_localized_date(date) }, date]
    end
    add.call(p_("Tasks", "Today, %{date}"), today)
    add.call(p_("Tasks", "Tomorrow, %{date}"), today + 1)
    (2..6).each { |offset| add.call("%{date}", today + offset) }
    add.call(p_("Tasks", "In a week, %{date}"), today + 7)
    add.call(p_("Tasks", "In two weeks, %{date}"), today + 14)
    add.call(p_("Tasks", "End of this month, %{date}"), Date.new(today.year, today.month, -1))
    next_month = today >> 1
    add.call(p_("Tasks", "End of next month, %{date}"), Date.new(next_month.year, next_month.month, -1))
    presets.sort_by { |_, date| date }
  end

  def effective_task_due_time(task, parent=nil)
    return task.plantime if task.due?
    return parent.plantime if task.parent.positive? && parent != nil && parent.due?

    nil
  end

  def apply_pending_task_sounds(list, tasks)
    tasks.each_with_index do |task, index|
      list.set_item_status(index, "new", "", "") unless task.completed?
    end
  end
end

class Scene_Tasks_Projects
  include TasksSceneHelpers

  def initialize(return_project_id=nil, status=:pending)
    @return_project_id = return_project_id == nil ? nil : return_project_id.to_i
    @status = status.to_sym
  end

  def main(index=0)
    unless load_projects
      return_to_tasks
      return
    end
    build_list(index)
    loop do
      loop_update
      @sel.update
      return_to_tasks if key_pressed?(:key_escape)
      if @sel.selected? && current_entry != nil
        if current_invitation != nil
          manage_invitation(current_invitation)
        else
          $scene = Scene_Tasks.new(current_project.id, @status)
        end
      end
      if @reload
        target_id = @target_project_id
        @reload = false
        @target_project_id = nil
        if load_projects
          entries = management_entries
          index = entries.index { |entry| project_for_entry(entry).id == target_id } ||
            [@sel.index, entries.size - 1].min
          build_list([index, 0].max)
        end
      end
      break if $scene != self
    end
  end

  def load_projects
    @projects = EltenLink::Tasks.projects(elten_link)
    @invitations = EltenLink::Tasks.invitations(elten_link)
    true
  rescue EltenLink::Error => error
    Log.warning("Task projects list failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def build_list(index=0)
    @entries = management_entries
    labels = @entries.map do |entry|
      project = project_for_entry(entry)
      if entry.is_a?(EltenLink::TaskProjectInvitation)
        p_("Tasks", "Invitation: %{project}") % { project: task_project_label(project) }
      else
        task_project_label(project)
      end
    end
    @sel = ListBox.new(labels, header: p_("Tasks", "Projects management"), index: index, quiet: false)
    @sel.bind_context { |menu| context(menu) }
  end

  def context(menu)
    invitation = current_invitation
    project = current_project
    if invitation != nil
      menu.option(p_("Tasks", "Accept invitation")) { manage_invitation(invitation, 0) }
      menu.option(p_("Tasks", "Reject invitation")) { manage_invitation(invitation, 1) }
    elsif project != nil
      menu.option(p_("Tasks", "Show tasks")) { $scene = Scene_Tasks.new(project.id, @status) }
      menu.option(p_("Tasks", "Notification settings")) { task_reminders(project) }
      if project.owned_by?(Session.name)
        menu.option(_("Edit"), nil, "e") { create_or_edit_project(project) }
        menu.option(p_("Tasks", "Share project"), nil, "s") { share_project(project) }
        menu.option(p_("Tasks", "Manage project shares")) { manage_shares(project) }
        menu.option(p_("Tasks", "Delete project"), nil, :del) { delete_project(project) }
      elsif !project.personal?
        menu.option(p_("Tasks", "Leave project"), nil, "l") { leave_project(project) }
      end
    end
    menu.option(p_("Tasks", "New project"), nil, "n") { create_or_edit_project }
    menu.option(_("Refresh"), nil, "r") { request_reload(project && project.id) }
  end

  def management_entries
    (@invitations || []) + (@projects || [])
  end

  def current_entry
    return nil if @entries == nil || @entries.empty? || @sel == nil
    @entries[@sel.index]
  end

  def current_invitation
    entry = current_entry
    entry if entry.is_a?(EltenLink::TaskProjectInvitation)
  end

  def current_project
    entry = current_entry
    entry == nil ? nil : project_for_entry(entry)
  end

  def project_for_entry(entry)
    entry.is_a?(EltenLink::TaskProjectInvitation) ? entry.project : entry
  end

  def request_reload(project_id=nil)
    @target_project_id = project_id
    @reload = true
  end

  def return_to_tasks
    $scene = Scene_Tasks.new(@return_project_id, @status)
  end

  def create_or_edit_project(project=nil)
    fields = [
      edt_name = EditBox.new(
        p_("Tasks", "Project name"),
        text: project == nil ? "" : project.name,
        quiet: true
      ),
      Button.new(project == nil ? p_("Tasks", "Create project") : _("Save")),
      Button.new(_("Cancel"))
    ]
    form = Form.new(fields)
    accepted = false
    init_name = edt_name.text.to_s
    dialog_open
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) ||
          ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 2)
        break if edt_name.text.to_s == init_name || confirm(p_("Tasks", "Are you sure you want to close without saving?"))
      end
      if (key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 1
        if edt_name.text.to_s.strip.empty?
          alert(p_("Tasks", "Enter a project name"))
          edt_name.focus
        else
          accepted = true
          break
        end
      end
    end
    dialog_close
    return unless accepted

    if project == nil
      id = EltenLink::Tasks.create_project(elten_link, name: edt_name.text)
      request_reload(id)
    else
      EltenLink::Tasks.update_project(elten_link, project, name: edt_name.text)
      request_reload(project.id)
    end
  rescue EltenLink::Error => error
    Log.warning("Task project save failed: #{error.message}")
    alert(_("Error"))
  end

  def share_project(project)
    user = input_user(p_("Tasks", "User to share this project with"), escapable: true)
    return if user == nil || user.to_s.empty?

    EltenLink::Tasks.add_share(elten_link, project, user)
    alert(p_("Tasks", "The project has been shared"))
  rescue EltenLink::Error => error
    Log.warning("Task project share failed: #{error.message}")
    alert(_("Error"))
  end

  def manage_shares(project)
    shares = EltenLink::Tasks.shares(elten_link, project)
    if shares.empty?
      alert(p_("Tasks", "This project is not shared with anyone"))
      return
    end
    labels = shares.map do |share|
      status = share.accepted ? p_("Tasks", "accepted") : p_("Tasks", "pending")
      "#{share.user}, #{status}"
    end
    index = selector(labels, header: p_("Tasks", "Project shares"), cancel_index: -1)
    return if index < 0

    share = shares[index]
    return unless confirm(p_("Tasks", "Do you want to remove sharing with %{user}?") % { user: share.user })

    EltenLink::Tasks.delete_share(elten_link, project, share.user)
    alert(p_("Tasks", "The project share has been removed"))
  rescue EltenLink::Error => error
    Log.warning("Task project shares failed: #{error.message}")
    alert(_("Error"))
  end

  def delete_project(project)
    question = p_("Tasks", "Do you really want to delete project %{name} and all its tasks?")
    return unless confirm(question % { name: project.name })

    EltenLink::Tasks.delete_project(elten_link, project)
    play_sound("editbox_delete")
    request_reload(0)
  rescue EltenLink::Error => error
    Log.warning("Task project delete failed: #{error.message}")
    alert(_("Error"))
  end

  def leave_project(project)
    return unless confirm(p_("Tasks", "Do you really want to leave project %{name}?") % { name: project.name })

    EltenLink::Tasks.delete_membership(elten_link, project)
    play_sound("editbox_delete")
    request_reload
  rescue EltenLink::Error => error
    Log.warning("Task project leave failed: #{error.message}")
    alert(_("Error"))
  end

  def manage_invitation(invitation, action=nil)
    action ||= selector(
      [p_("Tasks", "Accept invitation"), p_("Tasks", "Reject invitation"), _("Cancel")],
      header: task_project_label(invitation.project),
      cancel_index: 2,
      flags: ListBox::Flags::LeftRight
    )
    if action == 0
      EltenLink::Tasks.accept_share(elten_link, invitation.project)
      request_reload(invitation.project.id)
    elsif action == 1
      EltenLink::Tasks.delete_membership(elten_link, invitation.project)
      request_reload
    end
  rescue EltenLink::Error => error
    Log.warning("Task project invitation failed: #{error.message}")
    alert(_("Error"))
  end
end

class Scene_Tasks
  include TasksSceneHelpers

  def initialize(project_id=nil, status=:pending, task_id: nil)
    @filter_project_id = project_id == nil ? nil : project_id.to_i
    @status = status.to_sym
    @opening_task_id = task_id
  end

  def main(index=0)
    unless Session.logged?
      alert(_("This section is unavailable for guests"))
      $scene = Scene_Main.new
      return
    end
    if @opening_task_id
      begin
        target = EltenLink::Tasks.details(elten_link, @opening_task_id)
        @filter_project_id = target.project_id
      rescue EltenLink::Error => error
        Log.warning("Task notification could not be opened: #{error.message}")
        alert(_("Error"))
      end
      @opening_task_id = nil
    end
    unless load_tasks
      $scene = Scene_Main.new
      return
    end
    if target
      parent_id = target.parent.positive? ? target.parent : target.id
      index = @tasks.index { |task| task.id == parent_id } || index
    end
    build_list(index)
    manage_goals(current_task, target.id) if target && target.parent.positive? && current_task && current_task.id == target.parent
    loop do
      loop_update
      @sel.update
      $scene = Scene_Main.new if key_pressed?(:key_escape)
      manage_goals(current_task) if @sel.selected? && current_task != nil
      if @reload
        selected_id = @selected_task_id || (current_task && current_task.id)
        @reload = false
        @selected_task_id = nil
        if load_tasks
          index = @tasks.index { |task| task.id == selected_id } || [@sel.index, @tasks.size - 1].min
          build_list([index, 0].max)
        end
      end
      break if $scene != self
    end
  end

  def build_list(index=0)
    labels = @tasks.map { |task| task_label(task, @filter_project_id == nil ? project_for(task) : nil) }
    @sel = ListBox.new(labels, header: tasks_header, index: index, quiet: false)
    apply_pending_task_sounds(@sel, @tasks) if @status == :all
    @sel.bind_context { |menu| context(menu) }
  end

  def load_tasks
    @projects = EltenLink::Tasks.projects(elten_link)
    @participants_by_project = EltenLink::Tasks.participants(elten_link)
    if @filter_project_id != nil && !@projects.any? { |project| project.id == @filter_project_id }
      @filter_project_id = nil
    end
    @tasks = EltenLink::Tasks.list(
      elten_link,
      project: @filter_project_id,
      parent: 0,
      status: @status
    )
    true
  rescue EltenLink::Error => error
    Log.warning("Tasks list failed: #{error.message}")
    @projects = []
    @participants_by_project = {}
    @tasks = []
    alert(_("Error"))
    false
  end

  def context(menu)
    menu.submenu(p_("Tasks", "Filter by project")) do |submenu|
      submenu.option(p_("Tasks", "All projects")) { switch_filter(nil, @status) }
      @projects.each do |project|
        submenu.option(task_project_label(project)) { switch_filter(project.id, @status) }
      end
    end
    menu.submenu(p_("Tasks", "Show")) do |submenu|
      submenu.option(p_("Tasks", "Pending tasks"), nil, "u") { switch_filter(@filter_project_id, :pending) }
      submenu.option(p_("Tasks", "Completed tasks"), nil, "y") { switch_filter(@filter_project_id, :completed) }
      submenu.option(p_("Tasks", "All tasks"), nil, "t") { switch_filter(@filter_project_id, :all) }
    end

    task = current_task
    if task != nil
      project = project_for(task)
      menu.option(p_("Tasks", "Show details"), nil, "d") { show_task_details(task, project) }
      menu.option(p_("Tasks", "Goals"), nil, "g") { manage_goals(task) }
      unless task.composite?
        if task.completed?
          menu.option(p_("Tasks", "Reopen"), nil, "o") { change_completion(task, false) }
        else
          menu.option(p_("Tasks", "Mark as completed"), nil, "o") { change_completion(task, true) }
        end
      end
      menu.option(_("Edit"), nil, "e") { save_task(task) }
      menu.option(_("Delete"), nil, :del) { delete_task(task) }
    end
    menu.option(p_("Tasks", "Add task"), nil, "n") { save_task }
    menu.option(p_("Tasks", "Projects management"), nil, "m") do
      $scene = Scene_Tasks_Projects.new(@filter_project_id, @status)
    end
    menu.option(p_("Tasks", "Notification settings")) { task_reminders }
    menu.option(_("Refresh"), nil, "r") { request_reload }
  end

  def switch_filter(project_id, status)
    @filter_project_id = project_id
    @status = status
    request_reload
  end

  def current_task
    return nil if @tasks == nil || @tasks.empty? || @sel == nil
    @tasks[@sel.index]
  end

  def project_for(task)
    return nil if task == nil
    @projects.find { |project| project.id == task.project_id }
  end

  def default_project
    if @filter_project_id != nil
      return @projects.find { |project| project.id == @filter_project_id }
    end
    @projects.find(&:personal?) || @projects.first
  end

  def tasks_header
    status = case @status
             when :completed then p_("Tasks", "Completed tasks")
             when :all then p_("Tasks", "All tasks")
             else p_("Tasks", "Pending tasks")
             end
    return status if @filter_project_id == nil

    project = @projects.find { |item| item.id == @filter_project_id }
    project == nil ? status : "#{status}: #{task_project_label(project)}"
  end

  def save_task(task=nil, parent=nil)
    project = if parent != nil
                project_for(parent)
              elsif task != nil
                project_for(task)
              else
                default_project
              end
    return if project == nil

    values = task_dialog(@projects, @participants_by_project, project, task, parent)
    return if values == nil

    if task == nil
      id = EltenLink::Tasks.create(
        elten_link,
        project: values[:project],
        name: values[:name],
        description: values[:description],
        plantime: values[:plantime],
        performer: values[:performer],
        parent: values[:parent],
        frequency: values[:frequency]
      )
      alert(parent == nil ? p_("Tasks", "The task has been added") : p_("Tasks", "The goal has been added"))
      @selected_task_id = parent == nil ? id : parent.id
    else
      EltenLink::Tasks.update(
        elten_link,
        task,
        project: values[:project],
        name: values[:name],
        description: values[:description],
        plantime: values[:plantime],
        performer: values[:performer],
        parent: values[:parent],
        frequency: values[:frequency]
      )
      alert(p_("Tasks", "The task has been updated"))
      @selected_task_id = task.parent.positive? ? task.parent : task.id
    end
    request_reload(@selected_task_id)
    true
  rescue EltenLink::Error => error
    Log.warning("Task save failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def change_completion(task, completed)
    if completed
      return false unless completion_assignment_confirmed?(task)

      EltenLink::Tasks.complete(elten_link, task)
      alert(p_("Tasks", "The task has been completed"))
    else
      EltenLink::Tasks.reopen(elten_link, task)
      alert(p_("Tasks", "The task has been reopened"))
    end
    request_reload(task.parent.positive? ? task.parent : task.id)
    true
  rescue EltenLink::Error => error
    Log.warning("Task completion change failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def completion_assignment_confirmed?(task)
    return true if task.performer == nil || task.performer.to_s.empty?
    return true if task.performer.to_s.casecmp(Session.name.to_s).zero?

    confirm(
      p_("Tasks", "This task is assigned to %{user}. Do you want to mark it as completed anyway?") %
        { user: task.performer }
    )
  end

  def delete_task(task)
    question = if task.children_count.positive?
                 p_("Tasks", "Do you really want to delete %{name} and all its goals?")
               else
                 p_("Tasks", "Do you really want to delete %{name}?")
               end
    return false unless confirm(question % { name: task.name })

    EltenLink::Tasks.delete(elten_link, task)
    play_sound("editbox_delete")
    alert(p_("Tasks", "The task has been deleted"))
    request_reload(task.parent.positive? ? task.parent : nil)
    true
  rescue EltenLink::Error => error
    Log.warning("Task delete failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def request_reload(task_id=nil)
    @selected_task_id = task_id unless task_id.nil?
    @reload = true
  end

  def manage_goals(task, selected_id=nil)
    loop do
      full_task = EltenLink::Tasks.details(elten_link, task)
      goals = full_task.children
      index = goals.index { |goal| goal.id == selected_id } || 0
      labels = goals.map { |goal| task_label(goal, nil, full_task) }
      labels = [p_("Tasks", "No goals")] if labels.empty?
      list = ListBox.new(labels, header: p_("Tasks", "Goals of %{task}") % { task: task.name }, index: index, quiet: false)
      apply_pending_task_sounds(list, goals)
      refresh = false
      close = false
      list.bind_context do |menu|
        goal = goals[list.index] unless goals.empty?
        if goal != nil
          menu.option(p_("Tasks", "Show details"), nil, "d") do
            show_task_details(goal, project_for(task), full_task)
          end
          if goal.completed?
            menu.option(p_("Tasks", "Reopen"), nil, "o") do
              selected_id = goal.id
              refresh = change_completion(goal, false)
            end
          else
            menu.option(p_("Tasks", "Mark as completed"), nil, "o") do
              selected_id = goal.id
              refresh = change_completion(goal, true)
            end
          end
          menu.option(_("Edit"), nil, "e") do
            selected_id = goal.id
            refresh = save_task(goal, full_task)
          end
          menu.option(_("Delete"), nil, :del) do
            refresh = delete_task(goal)
          end
        end
        menu.option(p_("Tasks", "Add goal"), nil, "n") do
          refresh = save_task(nil, full_task)
        end
      end
      dialog_open
      loop do
        loop_update
        list.update
        if key_pressed?(:key_escape)
          close = true
          break
        end
        break if refresh
      end
      dialog_close
      break if close
      next if refresh
    end
    request_reload(task.id)
  rescue EltenLink::Error => error
    Log.warning("Task goals failed: #{error.message}")
    alert(_("Error"))
  end
end
