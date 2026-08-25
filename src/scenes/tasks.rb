# A part of Elten - Elten desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

require "date"

module TasksSceneHelpers
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
      due_control = if goal
                      parent_due_label = if parent.due?
                                           p_("Tasks", "Task due date: %{date}") % { date: task_date_label(parent.plantime) }
                                         else
                                           p_("Tasks", "Task due date: not set")
                                         end
                      due_options = [parent_due_label]
                      due_options << p_("Tasks", "Custom due date") if parent.due?
                      ListBox.new(
                        due_options,
                        header: p_("Tasks", "Goal due date"),
                        index: task != nil && task.due? && parent.due? ? 1 : 0
                      )
                    else
                      CheckBox.new(p_("Tasks", "Set a due date"), checked: task != nil && task.due?)
                    end,
      btn_due = DateButton.new(p_("Tasks", "Due date"), (min_year..max_year), include_hour: false),
      Button.new(task == nil ? p_("Tasks", "Add task") : _("Save")),
      Button.new(_("Cancel"))
    ]
    btn_due.setdate(due_time.year, due_time.month, due_time.day, 0, 0, 0)
    form = Form.new(fields)
    form.hide(lst_project) if goal
    manual_due_selected = proc do
      goal ? parent.due? && due_control.index.to_i == 1 : due_control.checked
    end
    due_control.on(goal ? :move : :change) do
      manual_due_selected.call ? form.show(btn_due) : form.hide(btn_due)
    end
    due_control.trigger(goal ? :move : :change)
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
    init_name = edt_name.text.to_s
    init_desc = edt_description.text.to_s
    dialog_open
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) ||
          ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 7)
        break if (edt_name.text.to_s == init_name && edt_description.text.to_s == init_desc) || confirm(p_("Tasks", "Are you sure you want to close without saving?"))
      end
      if (key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 6
        if edt_name.text.to_s.strip.empty?
          alert(p_("Tasks", "Enter a task name"))
          edt_name.focus
        elsif manual_due_selected.call &&
            (btn_due.year.to_i <= 0 || btn_due.month.to_i <= 0 || btn_due.day.to_i <= 0)
          alert(p_("Tasks", "Select a valid due date"))
        else
          if manual_due_selected.call
            plantime = Time.local(btn_due.year, btn_due.month, btn_due.day, 23, 59, 59)
            if goal && parent.due? && plantime.to_i > parent.plantime.to_i
              alert(p_("Tasks", "The goal due date cannot be after the task due date"))
              next
            end
          else
            plantime = nil
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
      parent: parent_id.to_i
    }
  rescue ArgumentError
    alert(p_("Tasks", "Select a valid due date"))
    nil
  end

  def task_date_label(time)
    format_localized_date(Date.new(time.year, time.month, time.day))
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

  def initialize(project_id=nil, status=:pending)
    @filter_project_id = project_id == nil ? nil : project_id.to_i
    @status = status.to_sym
  end

  def main(index=0)
    unless Session.logged?
      alert(_("This section is unavailable for guests"))
      $scene = Scene_Main.new
      return
    end
    unless load_tasks
      $scene = Scene_Main.new
      return
    end
    build_list(index)
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
        parent: values[:parent]
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
        parent: values[:parent]
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

  def manage_goals(task)
    selected_id = nil
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
