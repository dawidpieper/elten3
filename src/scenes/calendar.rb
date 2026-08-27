# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "date"

module CalendarSceneHelpers
  def calendar_label(calendar)
    return p_("Calendar", "Personal calendar") if calendar.personal?

    label = calendar.name.to_s
    label = p_("Calendar", "Unnamed calendar") if label == ""
    label += " (#{p_("Calendar", "public")})" if calendar.public
    label += ", #{p_("Calendar", "by %{user}") % { user: calendar.author }}" if calendar.author.to_s != Session.name.to_s
    label
  end

  def event_label(event, calendar=nil)
    range = if event.all_day?
              p_("Calendar", "All day")
            elsif same_day?(event.starttime, event.endtime)
              "#{format_date(event.starttime, false, false)}-#{sprintf("%02d:%02d", event.endtime.hour, event.endtime.min)}"
            else
              "#{format_date(event.starttime, false, false)} - #{format_date(event.endtime, false, false)}"
            end
    parts = [event.name.to_s, range]
    parts << calendar_event_recurrence_label(event) if event.recurring?
    parts << calendar_label(calendar) if calendar != nil
    parts.join(", ")
  end

  def show_event_details(event, calendar=nil)
    text = event_label(event, calendar)
    if event.recurring?
      series = calendar_event_series(event)
      text += "\r\n#{p_("Calendar", "Series range: %{start} - %{end}") % { start: format_date(series.starttime), end: format_date(series.endtime) }}"
    end
    text += "\r\n#{event.description}" if event.description.to_s != ""
    input_text(p_("Calendar", "Event details"), flags: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly, text: text, escapable: true)
  end

  def event_dialog(calendars, selected_calendar, selected_date, event=nil)
    event = calendar_event_series(event) if event != nil
    available = if event == nil
                  calendars.select { |calendar| can_manage_calendar_events?(calendar) }
                else
                  [selected_calendar]
                end
    return nil if available.empty?
    calendar_index = available.index { |calendar| calendar.id == selected_calendar.id } || 0
    date = normalize_calendar_date(selected_date)
    date = Date.new(event.starttime.year, event.starttime.month, event.starttime.day) if event != nil
    starttime = event == nil ? Time.local(date.year, date.month, date.day, 9, 0, 0) : event.starttime
    endtime = event == nil ? Time.local(date.year, date.month, date.day, 10, 0, 0) : event.endtime
    hours = (0..23).map { |hour| sprintf("%02d", hour) }
    minutes = (0..59).map { |minute| sprintf("%02d", minute) }
    min_year = [starttime.year, endtime.year, Time.now.year].min - 1
    max_year = [starttime.year, endtime.year, Time.now.year].max + 20
    frequency_values = [0, 1, 7, -1, :custom]
    frequencies = [
      p_("Calendar", "Continuous"),
      p_("Calendar", "Daily"),
      p_("Calendar", "Weekly"),
      p_("Calendar", "Monthly on the start day"),
      p_("Calendar", "Every N days")
    ]
    frequency_index = event == nil ? 0 : frequency_values.index(event.frequency) || 4
    custom_frequency = frequency_index == 4 ? event.frequency.to_s : "2"
    time_types = [p_("Calendar", "All-day event"), p_("Calendar", "Timed event")]
    time_type_index = event == nil || event.all_day_series? ? 0 : 1
    name = event == nil ? "" : event.name.to_s
    description = event == nil ? "" : event.description.to_s

    fields = [
      edt_name = EditBox.new(p_("Calendar", "Event name"), text: name, quiet: true),
      edt_description = EditBox.new(p_("Calendar", "Description"), type: EditBox::Flags::MultiLine, text: description, quiet: true),
      lst_calendar = ListBox.new(available.map { |calendar| calendar_label(calendar) }, header: p_("Calendar", "Calendar"), index: calendar_index),
      lst_frequency = ListBox.new(frequencies, header: p_("Calendar", "Frequency"), index: frequency_index),
      edt_frequency = EditBox.new(p_("Calendar", "Number of days"), type: EditBox::Flags::Numbers, text: custom_frequency, quiet: true),
      btn_start = DateButton.new(p_("Calendar", "Start date"), (min_year..max_year), include_hour: false),
      btn_end = DateButton.new(p_("Calendar", "End date"), (min_year..max_year), include_hour: false),
      lst_time_type = ListBox.new(time_types, header: p_("Calendar", "Event time"), index: time_type_index),
      lst_start_hour = ListBox.new(hours, header: p_("Calendar", "Start hour"), index: starttime.hour),
      lst_start_minute = ListBox.new(minutes, header: p_("Calendar", "Start minute"), index: starttime.min),
      lst_end_hour = ListBox.new(hours, header: p_("Calendar", "End hour"), index: endtime.hour),
      lst_end_minute = ListBox.new(minutes, header: p_("Calendar", "End minute"), index: endtime.min),
      btn_save = Button.new(event == nil ? p_("Calendar", "Add event") : _("Save")),
      btn_cancel = Button.new(_("Cancel"))
    ]
    btn_start.setdate(starttime.year, starttime.month, starttime.day, 0, 0, 0)
    btn_end.setdate(endtime.year, endtime.month, endtime.day, 0, 0, 0)
    form = Form.new(fields)
    time_fields = [lst_start_hour, lst_start_minute, lst_end_hour, lst_end_minute]
    lst_frequency.on(:move) do
      lst_frequency.index == 4 ? form.show(edt_frequency) : form.hide(edt_frequency)
    end
    lst_time_type.on(:move) do
      time_fields.each { |field| lst_time_type.index == 1 ? form.show(field) : form.hide(field) }
    end
    lst_frequency.trigger(:move)
    lst_time_type.trigger(:move)
    accepted = false
    times = nil
    frequency = 0
    current_state = proc do
      [edt_name.text.to_s, edt_description.text.to_s, lst_calendar.index, lst_frequency.index,
       edt_frequency.text.to_s, btn_start.year, btn_start.month, btn_start.day,
       btn_end.year, btn_end.month, btn_end.day, lst_time_type.index,
       lst_start_hour.index, lst_start_minute.index, lst_end_hour.index, lst_end_minute.index]
    end
    initial_state = current_state.call
    dialog_open
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && fields[form.index] == btn_cancel)
        break if current_state.call == initial_state || confirm(p_("Calendar", "Are you sure you want to close without saving?"))
      end
      if (key_pressed?(:key_enter) || key_pressed?(:key_space)) && fields[form.index] == btn_save
        if edt_name.text.to_s.strip == ""
          alert(p_("Calendar", "Enter an event name"))
          edt_name.focus
          next
        end
        if btn_start.year.to_i <= 0 || btn_start.month.to_i <= 0 || btn_start.day.to_i <= 0 ||
            btn_end.year.to_i <= 0 || btn_end.month.to_i <= 0 || btn_end.day.to_i <= 0
          alert(p_("Calendar", "Select both a start date and an end date"))
          next
        end
        frequency = frequency_values[lst_frequency.index]
        if frequency == :custom
          frequency = edt_frequency.text.to_i
          if frequency <= 0 || frequency > 2_147_483_647
            alert(p_("Calendar", "Enter a valid number of days"))
            edt_frequency.focus
            next
          end
        end
        begin
          times = if lst_time_type.index == 0
                    [
                      Time.local(btn_start.year, btn_start.month, btn_start.day, 0, 0, 0),
                      Time.local(btn_end.year, btn_end.month, btn_end.day, 23, 59, 59)
                    ]
                  else
                    [
                      Time.local(btn_start.year, btn_start.month, btn_start.day, lst_start_hour.index, lst_start_minute.index, 0),
                      Time.local(btn_end.year, btn_end.month, btn_end.day, lst_end_hour.index, lst_end_minute.index, 0)
                    ]
                  end
        rescue ArgumentError
          alert(p_("Calendar", "Select a valid date and time range"))
          next
        end
        if times[1] < times[0]
          alert(p_("Calendar", "The end of the event cannot be before its start"))
          next
        end
        accepted = true
        break
      end
    end
    dialog_close
    return nil if !accepted

    calendar = available[lst_calendar.index]
    {
      calendar: calendar,
      name: edt_name.text.to_s,
      description: edt_description.text.to_s,
      starttime: times[0],
      endtime: times[1],
      frequency: frequency
    }
  end

  def can_manage_calendar_events?(calendar)
    calendar != nil && calendar.can_manage_events?(Session.name)
  end

  def mark_public_calendar_events(events, calendars)
    public_ids = (calendars || []).select { |calendar| calendar.public }.map(&:id)
    (events || []).each do |event|
      event.public_calendar = public_ids.include?(event.calendar_id)
    end
  end

  def create_or_update_event(calendars, calendar, date, event=nil)
    event = calendar_event_series(event) if event != nil
    values = event_dialog(calendars, calendar, date, event)
    return false if values == nil

    if event == nil
      EltenLink::Calendars.create_event(
        elten_link,
        values[:calendar],
        name: values[:name],
        description: values[:description],
        starttime: values[:starttime],
        endtime: values[:endtime],
        frequency: values[:frequency]
      )
      alert(p_("Calendar", "The event has been added"))
    else
      EltenLink::Calendars.update_event(
        elten_link,
        calendar,
        event,
        name: values[:name],
        description: values[:description],
        starttime: values[:starttime],
        endtime: values[:endtime],
        frequency: values[:frequency]
      )
      alert(p_("Calendar", "The event has been updated"))
    end
    true
  rescue EltenLink::Error => error
    Log.warning("Calendar event save failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def delete_calendar_event(calendar, event)
    event = calendar_event_series(event)
    return false if !confirm(p_("Calendar", "Do you really want to delete %{name}?") % { name: event.name })

    EltenLink::Calendars.delete_event(elten_link, calendar, event)
    play_sound("editbox_delete")
    alert(p_("Calendar", "The event has been deleted"))
    true
  rescue EltenLink::Error => error
    Log.warning("Calendar event delete failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def same_day?(first, second)
    first.year == second.year && first.yday == second.yday
  end

  def normalize_calendar_date(value)
    return value if value.is_a?(Date)
    Date.new(value.year, value.month, value.day)
  rescue Exception
    Date.today
  end

  def calendar_event_series(event)
    event.respond_to?(:series_event) ? event.series_event : event
  end

  def calendar_event_recurrence_label(event)
    case event.frequency.to_i
    when 1
      p_("Calendar", "Daily")
    when 7
      p_("Calendar", "Weekly")
    when -1
      p_("Calendar", "Monthly on day %{day}") % { day: calendar_event_series(event).starttime.day }
    else
      p_("Calendar", "Every %{count} days") % { count: event.frequency.to_i }
    end
  end
end

class Scene_Calendar
  include CalendarSceneHelpers

  def initialize(calendar_id=nil, date=nil)
    @filter_calendar_id = calendar_id == nil ? nil : calendar_id.to_i
    @selected_date = normalize_calendar_date(date || Date.today)
  end

  def main
    unless Session.logged?
      alert(_("This section is unavailable for guests"))
      $scene = Scene_Main.new
      return
    end
    unless load_calendars
      $scene = Scene_Main.new
      return
    end
    load_events
    @grid = CalendarGrid.new(date: @selected_date, header: calendar_grid_header) do |date|
      calendar_day_note(date)
    end
    @grid.on(:move) do |params|
      @selected_date = params[0]
    end
    @grid.on(:announce) { |params| play_calendar_day_sound(params[0]) }
    @grid.on(:select) { |params| show_day_events(params[0]) }
    @grid.bind_context { |menu| context(menu) }
    @grid.focus

    loop do
      loop_update
      @grid.update
      if keyboard_binding_pressed?([:tab, :shift_optional])
        tab_code, = keyboard_code(:tab)
        direction = keyboard_modifier_held_when_pressed?(tab_code, :shift) ? -1 : 1
        move_to_adjacent_event_day(direction)
      end
      if key_pressed?(:key_escape)
        $scene = Scene_Main.new
      end
      break if $scene != self
    end
  end

  def context(menu)
    menu.submenu(p_("Calendar", "Filter by calendar")) do |submenu|
      submenu.option(p_("Calendar", "All calendars")) { select_calendar(nil) }
      @calendars.each do |calendar|
        submenu.option(calendar_label(calendar)) { select_calendar(calendar) }
      end
    end
    target_calendar = default_calendar
    if can_manage_calendar_events?(target_calendar)
      menu.option(p_("Calendar", "Add event"), nil, "n") do
        if create_or_update_event(@calendars, target_calendar, @grid.date)
          load_events
          @grid.focus
        end
      end
    end
    menu.option(p_("Calendar", "Events on selected day"), nil, "e") { show_day_events(@grid.date) }
    menu.option(p_("Calendar", "Upcoming events"), nil, "u") do
      $scene = Scene_Calendar_Upcoming.new(@filter_calendar_id, @grid.date)
    end
    menu.option(p_("Calendar", "Calendar management"), nil, "c") do
      $scene = Scene_Calendar_Management.new(@filter_calendar_id, @grid.date)
    end
    menu.option(_("Refresh"), nil, "r") do
      if load_calendars
        load_events
        @grid.focus
      end
    end
  end

  def load_calendars
    @calendars = EltenLink::Calendars.list(elten_link)
    if @calendars.empty?
      alert(p_("Calendar", "No calendars are available"))
      return false
    end
    if @filter_calendar_id != nil && !@calendars.any? { |calendar| calendar.id == @filter_calendar_id }
      @filter_calendar_id = nil
    end
    @grid.header = calendar_grid_header if @grid != nil
    true
  rescue EltenLink::Error => error
    Log.warning("Calendar list failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def load_events
    @all_events = EltenLink::Calendars.all_events(elten_link)
    mark_public_calendar_events(@all_events, @calendars)
    apply_event_filter
    true
  rescue EltenLink::Error => error
    Log.warning("Calendar event list failed: #{error.message}")
    @all_events = []
    apply_event_filter
    alert(_("Error"))
    false
  end

  def apply_event_filter
    source = @all_events || []
    @events = if @filter_calendar_id == nil
                source.dup
              else
                source.select { |event| event.calendar_id == @filter_calendar_id }
              end
    @events_by_day = {}
  end

  def events_on(date)
    date = normalize_calendar_date(date)
    @events_by_day ||= {}
    @events_by_day[date] ||= (@events || []).flat_map { |event| event.occurrences_on(date) }
  end

  def calendar_day_event_counts(date)
    day_events = events_on(date)
    public_count = day_events.count(&:public_calendar?)
    [day_events.size - public_count, public_count]
  end

  def calendar_day_note(date)
    private_count, public_count = calendar_day_event_counts(date)
    return p_("Calendar", "no events") if private_count == 0 && public_count == 0

    if @filter_calendar_id != nil
      count = private_count + public_count
      return np_("Calendar", "%{count} event", "%{count} events", count) % { count: count }
    end

    counts = []
    if private_count > 0
      counts << (np_("Calendar", "%{count} private event", "%{count} private events", private_count) % { count: private_count })
    end
    if public_count > 0
      counts << (np_("Calendar", "%{count} public event", "%{count} public events", public_count) % { count: public_count })
    end
    counts.join(p_("Calendar", " and "))
  end

  def play_calendar_day_sound(date)
    private_count, = calendar_day_event_counts(date)
    return if private_count == 0

    play_sound("listbox_itemcontaining", volume: 100, pitch: 100, pan: @grid.lpos)
  end

  def move_to_adjacent_event_day(direction)
    target = adjacent_event_day(@grid.date, direction)
    if target == nil
      play_sound("border", volume: 100, pitch: 100, pan: direction < 0 ? 0 : 100)
    else
      @grid.move_to(target)
    end
  end

  def adjacent_event_day(date, direction)
    current = normalize_calendar_date(date)
    threshold = current + (direction < 0 ? -1 : 1)
    candidates = (@events || []).filter_map do |event|
      if direction < 0
        event.event_date_on_or_before(threshold)
      else
        event.event_date_on_or_after(threshold)
      end
    end
    direction < 0 ? candidates.max : candidates.min
  end

  def select_calendar(calendar)
    @filter_calendar_id = calendar == nil ? nil : calendar.id
    @selected_date = @grid.date
    apply_event_filter
    @grid.header = calendar_grid_header
    @grid.focus
  end

  def calendar_grid_header
    header = p_("Calendar", "Calendar")
    return header if @filter_calendar_id == nil

    calendar = (@calendars || []).find { |item| item.id == @filter_calendar_id }
    return header if calendar == nil

    name = if calendar.personal?
             p_("Calendar", "Personal calendar")
           elsif calendar.name.to_s == ""
             p_("Calendar", "Unnamed calendar")
           else
             calendar.name.to_s
           end
    "#{header}: #{name}"
  end

  def default_calendar
    return @calendars.find { |calendar| calendar.id == @filter_calendar_id } if @filter_calendar_id != nil
    @calendars.find(&:personal?) || @calendars.first
  end

  def calendar_for_event(event)
    @calendars.find { |calendar| calendar.id == event.calendar_id }
  end

  def show_day_events(date)
    date = normalize_calendar_date(date)
    loop do
      day_events = events_on(date).sort_by { |event| [event.starttime.to_i, event.endtime.to_i, event.id] }
      refresh = false
      close = false
      list = ListBox.new(day_events.map { |event| event_label(event, calendar_for_event(event)) }, header: p_("Calendar", "Events on %{date}") % { date: format_localized_date(date) }, quiet: false)
      list.bind_context do |menu|
        if day_events.size > 0
          event = day_events[list.index]
          calendar = calendar_for_event(event)
          menu.option(p_("Calendar", "Show details")) { show_event_details(event, calendar) }
          if can_manage_calendar_events?(calendar)
            menu.option(_("Edit"), nil, "e") do
              refresh = create_or_update_event(@calendars, calendar, date, event)
            end
            menu.option(_("Delete"), nil, :del) do
              refresh = delete_calendar_event(calendar, event)
            end
          end
        end
        target_calendar = default_calendar
        if can_manage_calendar_events?(target_calendar)
          menu.option(p_("Calendar", "Add event"), nil, "n") do
            refresh = create_or_update_event(@calendars, target_calendar, date)
          end
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
        show_event_details(day_events[list.index], calendar_for_event(day_events[list.index])) if list.selected? && day_events.size > 0
        break if refresh
      end
      dialog_close
      if refresh
        @selected_date = date
        load_events
      end
      break if close || !refresh
    end
    loop_update
    @grid.focus if @grid != nil
  end

end

class Scene_Calendar_Management
  include CalendarSceneHelpers

  def initialize(return_filter_id=nil, date=nil)
    @return_filter_id = return_filter_id == nil ? nil : return_filter_id.to_i
    @return_date = normalize_calendar_date(date || Date.today)
  end

  def main
    unless load_management
      $scene = Scene_Calendar.new(@return_filter_id, @return_date)
      return
    end
    build_list
    loop do
      loop_update
      @sel.update
      if key_pressed?(:key_escape)
        $scene = Scene_Calendar.new(@return_filter_id, @return_date)
      end
      if @sel.selected? && current_entry != nil
        if current_invitation != nil
          manage_invitation(current_invitation)
        else
          $scene = Scene_Calendar.new(current_calendar.id, @return_date)
        end
      end
      if @reload
        target_id = @target_calendar_id
        @reload = false
        @target_calendar_id = nil
        if load_management
          entries = management_entries
          index = entries.index { |entry| calendar_for_entry(entry).id == target_id } ||
            [@sel.index, entries.size - 1].min
          build_list([index, 0].max)
        end
      end
      break if $scene != self
    end
  end

  def build_list(index=0)
    @entries = management_entries
    labels = @entries.map do |entry|
      calendar = calendar_for_entry(entry)
      if entry.is_a?(EltenLink::CalendarInvitation)
        p_("Calendar", "Invitation: %{calendar}") % { calendar: calendar_label(calendar) }
      else
        calendar_label(calendar)
      end
    end
    @sel = ListBox.new(labels, header: p_("Calendar", "Calendar management"), index: index, quiet: false)
    @sel.bind_context { |menu| context(menu) }
  end

  def context(menu)
    invitation = current_invitation
    calendar = current_calendar
    if invitation != nil
      menu.option(p_("Calendar", "Accept invitation")) { manage_invitation(invitation, 0) }
      menu.option(p_("Calendar", "Reject invitation")) { manage_invitation(invitation, 1) }
    elsif calendar != nil
      menu.option(p_("Calendar", "Show in calendar")) do
        $scene = Scene_Calendar.new(calendar.id, @return_date)
      end
      if calendar.owned_by?(Session.name)
        menu.option(p_("Calendar", "Edit calendar")) { edit_calendar(calendar) }
        menu.option(p_("Calendar", "Share calendar"), nil, "s") { share_calendar(calendar) }
        menu.option(p_("Calendar", "Manage calendar shares")) { manage_shares(calendar) }
        menu.option(p_("Calendar", "Delete calendar"), nil, :del) { delete_calendar(calendar) }
      elsif !calendar.personal?
        menu.option(p_("Calendar", "Leave calendar"), nil, "l") { leave_calendar(calendar) }
      end
    end
    menu.option(p_("Calendar", "New calendar"), nil, "n") { create_calendar }
    menu.option(p_("Calendar", "Public calendars"), nil, "p") do
      subscribed_ids = @calendars.select do |item|
        item.public && !item.owned_by?(Session.name) && !item.moderator?
      end.map(&:id)
      invitation_ids = @invitations.map { |invitation| invitation.calendar.id }
      $scene = Scene_Calendar_Public.new(@return_filter_id, @return_date, subscribed_ids, invitation_ids)
    end
    menu.option(_("Refresh"), nil, "r") { request_reload(calendar && calendar.id) }
  end

  def load_management
    @calendars = EltenLink::Calendars.list(elten_link)
    @invitations = EltenLink::Calendars.invitations(elten_link)
    true
  rescue EltenLink::Error => error
    Log.warning("Calendar management list failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def management_entries
    (@invitations || []) + (@calendars || [])
  end

  def current_entry
    return nil if @entries == nil || @entries.empty? || @sel == nil
    @entries[@sel.index]
  end

  def current_invitation
    entry = current_entry
    entry if entry.is_a?(EltenLink::CalendarInvitation)
  end

  def current_calendar
    entry = current_entry
    return nil if entry == nil
    calendar_for_entry(entry)
  end

  def calendar_for_entry(entry)
    entry.is_a?(EltenLink::CalendarInvitation) ? entry.calendar : entry
  end

  def request_reload(calendar_id=nil)
    @target_calendar_id = calendar_id
    @reload = true
  end

  def create_calendar
    language_codes = []
    language_labels = []
    Lists.langs.each do |code, language|
      code = code.to_s.downcase
      next if !code.match?(/\A[a-z]{2}\z/)

      language_codes << code
      language_labels << "#{language["name"]} (#{language["nativeName"]})"
    end
    default_language = Configuration.language.to_s.downcase[0, 2]
    language_index = language_codes.index(default_language) || 0
    fields = [
      edt_name = EditBox.new(p_("Calendar", "Calendar name"), quiet: true),
      lst_lang = ListBox.new(language_labels, header: p_("Calendar", "Language"), index: language_index),
      chk_public = CheckBox.new(p_("Calendar", "Public calendar")),
      Button.new(p_("Calendar", "Create calendar")),
      Button.new(_("Cancel"))
    ]
    form = Form.new(fields)
    accepted = false
    init_name = edt_name.text.to_s
    dialog_open
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 4)
        break if edt_name.text.to_s == init_name || confirm(p_("Calendar", "Are you sure you want to close without saving?"))
      end
      if (key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 3
        if edt_name.text.to_s.strip == ""
          alert(p_("Calendar", "Enter a calendar name"))
        else
          accepted = true
          break
        end
      end
    end
    dialog_close
    return if !accepted

    id = EltenLink::Calendars.create(elten_link, name: edt_name.text, public_state: chk_public.checked, lang: language_codes[lst_lang.index])
    request_reload(id)
  rescue EltenLink::Error => error
    Log.warning("Calendar create failed: #{error.message}")
    alert(_("Error"))
  end

  def edit_calendar(calendar)
    fields = [
      edt_name = EditBox.new(p_("Calendar", "Calendar name"), text: calendar.name, quiet: true),
      chk_public = CheckBox.new(p_("Calendar", "Public calendar"), checked: calendar.public),
      Button.new(_("Save")),
      Button.new(_("Cancel"))
    ]
    form = Form.new(fields)
    initial_state = [edt_name.text.to_s, chk_public.checked]
    accepted = false
    dialog_open
    loop do
      loop_update
      form.update
      current_state = [edt_name.text.to_s, chk_public.checked]
      if key_pressed?(:key_escape) || ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 3)
        break if current_state == initial_state || confirm(p_("Calendar", "Are you sure you want to close without saving?"))
      end
      next unless (key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 2

      if edt_name.text.to_s.strip == ""
        alert(p_("Calendar", "Enter a calendar name"))
        next
      end
      if chk_public.checked != calendar.public
        warning = if chk_public.checked
                    p_("Calendar", "Changing this calendar to public will remove all existing shares and pending invitations. Do you want to continue?")
                  else
                    p_("Calendar", "Changing this calendar to private will remove all subscriptions. Do you want to continue?")
                  end
        next unless confirm(warning)
      end
      accepted = true
      break
    end
    dialog_close
    return if !accepted

    EltenLink::Calendars.update(
      elten_link,
      calendar,
      name: edt_name.text,
      public_state: chk_public.checked
    )
    request_reload(calendar.id)
  rescue EltenLink::Error => error
    Log.warning("Calendar update failed: #{error.message}")
    alert(_("Error"))
  end

  def delete_calendar(calendar)
    return if !confirm(p_("Calendar", "Do you really want to delete the calendar %{name} and all its events?") % { name: calendar.name })

    EltenLink::Calendars.delete(elten_link, calendar)
    play_sound("editbox_delete")
    request_reload(0)
  rescue EltenLink::Error => error
    Log.warning("Calendar delete failed: #{error.message}")
    alert(_("Error"))
  end

  def leave_calendar(calendar)
    return if !confirm(p_("Calendar", "Do you really want to leave the calendar %{name}?") % { name: calendar.name })

    EltenLink::Calendars.delete_membership(elten_link, calendar)
    play_sound("editbox_delete")
    request_reload
  rescue EltenLink::Error => error
    Log.warning("Calendar leave failed: #{error.message}")
    alert(_("Error"))
  end

  def share_calendar(calendar)
    user = input_user(p_("Calendar", "User to share this calendar with"), escapable: true)
    return if user == nil || user.to_s == ""

    EltenLink::Calendars.add_share(elten_link, calendar, user, moderator: true)
    alert(p_("Calendar", "The calendar has been shared"))
  rescue EltenLink::Error => error
    Log.warning("Calendar share failed: #{error.message}")
    alert(_("Error"))
  end

  def manage_shares(calendar)
    shares = EltenLink::Calendars.shares(elten_link, calendar)
    if shares.empty?
      alert(p_("Calendar", "This calendar is not shared with anyone"))
      return
    end
    labels = shares.map do |share|
      status = share.accepted ? p_("Calendar", "accepted") : p_("Calendar", "pending")
      "#{share.user}, #{status}"
    end
    index = selector(labels, header: p_("Calendar", "Calendar shares"), cancel_index: -1)
    return if index < 0
    share = shares[index]
    return if !confirm(p_("Calendar", "Do you want to remove sharing with %{user}?") % { user: share.user })

    EltenLink::Calendars.delete_share(elten_link, calendar, share.user)
    alert(p_("Calendar", "The calendar share has been removed"))
  rescue EltenLink::Error => error
    Log.warning("Calendar shares failed: #{error.message}")
    alert(_("Error"))
  end

  def manage_invitation(invitation, action=nil)
    action ||= selector(
      [p_("Calendar", "Accept invitation"), p_("Calendar", "Reject invitation"), _("Cancel")],
      header: calendar_label(invitation.calendar),
      cancel_index: 2,
      flags: ListBox::Flags::LeftRight
    )
    if action == 0
      EltenLink::Calendars.accept_share(elten_link, invitation.calendar)
      request_reload(invitation.calendar.id)
    elsif action == 1
      EltenLink::Calendars.delete_membership(elten_link, invitation.calendar)
      request_reload
    end
  rescue EltenLink::Error => error
    Log.warning("Calendar invitation action failed: #{error.message}")
    alert(_("Error"))
  end
end

class Scene_Calendar_Public
  include CalendarSceneHelpers

  def initialize(return_filter_id=nil, date=nil, subscribed_ids=[], invitation_ids=[])
    @return_filter_id = return_filter_id == nil ? nil : return_filter_id.to_i
    @return_date = normalize_calendar_date(date || Date.today)
    @subscribed_ids = subscribed_ids.map(&:to_i).uniq
    @invitation_ids = invitation_ids.map(&:to_i).uniq
  end

  def main
    unless load_public_calendars
      return_to_management
      return
    end
    build_list
    loop do
      loop_update
      @sel.update
      if key_pressed?(:key_escape)
        return_to_management
      end
      break if $scene != self
    end
  end

  def load_public_calendars
    @all_calendars = EltenLink::Calendars.list_public(elten_link)
    @all_calendars.reject! { |calendar| @invitation_ids.include?(calendar.id) }
    apply_language_filter
    true
  rescue EltenLink::Error => error
    Log.warning("Public calendar list failed: #{error.message}")
    alert(_("Error"))
    false
  end

  def apply_language_filter
    known_languages = Session.languages.to_s.split(",").map { |language| language[0..1].to_s.upcase }
    show_unknown = LocalConfig["CalendarShowUnknownLanguages", type: :bool]
    @calendars = (@all_calendars || []).select do |calendar|
      show_unknown || known_languages.empty? || known_languages.include?(calendar.lang.to_s[0..1].upcase)
    end
  end

  def build_list(calendar_id=nil)
    apply_language_filter
    index = @calendars.index { |calendar| calendar.id == calendar_id } || 0
    @sel = ListBox.new(
      @calendars.map { |calendar| public_calendar_label(calendar) },
      header: p_("Calendar", "Public calendars"),
      index: index,
      quiet: false
    )
    @sel.bind_context { |menu| context(menu) }
  end

  def context(menu)
    calendar = current_calendar
    if calendar != nil
      if @subscribed_ids.include?(calendar.id)
        menu.option(p_("Calendar", "Unsubscribe"), nil, "l") { unsubscribe(calendar) }
      elsif !calendar.owned_by?(Session.name) && !calendar.moderator?
        menu.option(p_("Calendar", "Subscribe"), nil, "l") { subscribe(calendar) }
      end
    end
    if Session.languages.to_s != ""
      label = p_("Calendar", "Show calendars in unknown languages")
      if LocalConfig["CalendarShowUnknownLanguages", type: :bool]
        label = p_("Calendar", "Hide calendars in unknown languages")
      end
      menu.option(label) do
        LocalConfig["CalendarShowUnknownLanguages"] = !LocalConfig["CalendarShowUnknownLanguages", type: :bool]
        build_list(calendar && calendar.id)
      end
    end
    menu.option(_("Refresh"), nil, "r") do
      if load_public_calendars
        build_list(calendar && calendar.id)
      end
    end
  end

  def current_calendar
    return nil if @calendars == nil || @calendars.empty? || @sel == nil
    @calendars[@sel.index]
  end

  def public_calendar_label(calendar)
    count = calendar.subscribers_count.to_i
    subscribers = np_("Calendar", "%{count} subscriber", "%{count} subscribers", count) % { count: count }
    "#{calendar_label(calendar)}, #{subscribers}"
  end

  def subscribe(calendar)
    EltenLink::Calendars.subscribe(elten_link, calendar)
    @subscribed_ids << calendar.id
    @subscribed_ids.uniq!
    calendar.subscribers_count += 1
    alert(p_("Calendar", "The calendar has been subscribed"))
    build_list(calendar.id)
  rescue EltenLink::Error => error
    Log.warning("Public calendar subscription failed: #{error.message}")
    alert(_("Error"))
  end

  def unsubscribe(calendar)
    return if !confirm(p_("Calendar", "Do you really want to unsubscribe from calendar %{name}?") % { name: calendar.name })

    EltenLink::Calendars.delete_membership(elten_link, calendar)
    @subscribed_ids.delete(calendar.id)
    calendar.subscribers_count = [calendar.subscribers_count - 1, 0].max
    alert(p_("Calendar", "The calendar has been unsubscribed"))
    build_list(calendar.id)
  rescue EltenLink::Error => error
    Log.warning("Public calendar unsubscription failed: #{error.message}")
    alert(_("Error"))
  end

  def return_to_management
    $scene = Scene_Calendar_Management.new(@return_filter_id, @return_date)
  end
end

class Scene_Calendar_Upcoming
  include CalendarSceneHelpers

  def initialize(filter_calendar_id=nil, date=nil)
    @return_filter_id = filter_calendar_id == nil ? nil : filter_calendar_id.to_i
    @return_date = normalize_calendar_date(date || Date.today)
  end

  def main(index=0)
    load_upcoming
    @sel = ListBox.new(@events.map { |event| event_label(event, calendar_for(event)) }, header: p_("Calendar", "Upcoming events"), index: index, quiet: false)
    @sel.bind_context { |menu| context(menu) }
    loop do
      loop_update
      @sel.update
      if key_pressed?(:key_escape)
        $scene = Scene_Calendar.new(@return_filter_id, @return_date)
      end
      show_event_details(current_event, calendar_for(current_event)) if @sel.selected? && current_event != nil
      if @refresh
        selected = @sel.index
        @refresh = false
        main(selected)
        return
      end
      break if $scene != self
    end
  end

  def context(menu)
    event = current_event
    if event != nil
      calendar = calendar_for(event)
      menu.option(p_("Calendar", "Show details")) { show_event_details(event, calendar) }
      if can_manage_calendar_events?(calendar)
        menu.option(_("Edit"), nil, "e") do
          @refresh = create_or_update_event(@calendars, calendar, normalize_calendar_date(event.starttime), event)
        end
        menu.option(_("Delete"), nil, :del) do
          @refresh = delete_calendar_event(calendar, event)
        end
      end
    end
    menu.option(_("Refresh"), nil, "r") { @refresh = true }
  end

  def load_upcoming
    @calendars = EltenLink::Calendars.list(elten_link)
    now = Time.now
    events = EltenLink::Calendars.all_events(elten_link)
    mark_public_calendar_events(events, @calendars)
    events.select! { |event| event.endtime.to_i >= now.to_i }
    if @return_filter_id == nil
      events.reject!(&:public_calendar?)
    else
      events.select! { |event| event.calendar_id == @return_filter_id }
    end
    @events = events.filter_map { |event| event.next_occurrence(now) }
    @events.sort_by! { |event| [event.starttime.to_i, event.endtime.to_i, event.id] }
  rescue EltenLink::Error => error
    Log.warning("Upcoming calendars failed: #{error.message}")
    @calendars = []
    @events = []
    alert(_("Error"))
  end

  def current_event
    return nil if @events == nil || @events.empty? || @sel == nil
    @events[@sel.index]
  end

  def calendar_for(event)
    return nil if event == nil
    @calendars.find { |calendar| calendar.id == event.calendar_id }
  end
end
