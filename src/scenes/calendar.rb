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
    parts << calendar_label(calendar) if calendar != nil
    parts.join(", ")
  end

  def show_event_details(event, calendar=nil)
    text = event_label(event, calendar)
    text += "\r\n#{event.description}" if event.description.to_s != ""
    input_text(p_("Calendar", "Event details"), flags: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly, text: text, escapable: true)
  end

  def event_dialog(calendars, selected_calendar, selected_date, event=nil)
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
    ranges = [
      p_("Calendar", "All-day event"),
      p_("Calendar", "Time range on selected day"),
      p_("Calendar", "Custom date and time range")
    ]
    range_index = if event == nil || event.all_day?
                    0
                  elsif same_day?(event.starttime, event.endtime)
                    1
                  else
                    2
                  end
    name = event == nil ? "" : event.name.to_s
    description = event == nil ? "" : event.description.to_s

    fields = [
      edt_name = EditBox.new(p_("Calendar", "Event name"), text: name, quiet: true),
      edt_description = EditBox.new(p_("Calendar", "Description"), type: EditBox::Flags::MultiLine, text: description, quiet: true),
      lst_calendar = ListBox.new(available.map { |calendar| calendar_label(calendar) }, header: p_("Calendar", "Calendar"), index: calendar_index),
      lst_range = ListBox.new(ranges, header: p_("Calendar", "Time range"), index: range_index),
      lst_start_hour = ListBox.new(hours, header: p_("Calendar", "Start hour"), index: starttime.hour),
      lst_start_minute = ListBox.new(minutes, header: p_("Calendar", "Start minute"), index: starttime.min),
      lst_end_hour = ListBox.new(hours, header: p_("Calendar", "End hour"), index: endtime.hour),
      lst_end_minute = ListBox.new(minutes, header: p_("Calendar", "End minute"), index: endtime.min),
      btn_start = DateButton.new(p_("Calendar", "Start date and time"), (min_year..max_year), include_hour: true),
      btn_end = DateButton.new(p_("Calendar", "End date and time"), (min_year..max_year), include_hour: true),
      Button.new(event == nil ? p_("Calendar", "Add event") : _("Save")),
      Button.new(_("Cancel"))
    ]
    btn_start.setdate(starttime.year, starttime.month, starttime.day, starttime.hour, starttime.min, starttime.sec)
    btn_end.setdate(endtime.year, endtime.month, endtime.day, endtime.hour, endtime.min, endtime.sec)
    form = Form.new(fields)
    hour_fields = [lst_start_hour, lst_start_minute, lst_end_hour, lst_end_minute]
    custom_fields = [btn_start, btn_end]
    lst_range.on(:move) do
      apply_event_range_visibility(form, lst_range.index, hour_fields, custom_fields)
    end
    apply_event_range_visibility(form, lst_range.index, hour_fields, custom_fields)
    accepted = false
    times = nil
    dialog_open
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 11)
        break
      end
      if (key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 10
        if edt_name.text.to_s.strip == ""
          alert(p_("Calendar", "Enter an event name"))
          edt_name.focus
          next
        end
        if lst_range.index == 2 &&
            (btn_start.year.to_i <= 0 || btn_start.month.to_i <= 0 || btn_start.day.to_i <= 0 ||
             btn_end.year.to_i <= 0 || btn_end.month.to_i <= 0 || btn_end.day.to_i <= 0)
          alert(p_("Calendar", "Select both the start and end date"))
          next
        end
        begin
          times = case lst_range.index
                  when 0
                    all_day_range(date)
                  when 1
                    [
                      Time.local(date.year, date.month, date.day, lst_start_hour.index, lst_start_minute.index, 0),
                      Time.local(date.year, date.month, date.day, lst_end_hour.index, lst_end_minute.index, 0)
                    ]
                  else
                    [
                      Time.local(btn_start.year, btn_start.month, btn_start.day, btn_start.hour, btn_start.min, btn_start.sec),
                      Time.local(btn_end.year, btn_end.month, btn_end.day, btn_end.hour, btn_end.min, btn_end.sec)
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
      endtime: times[1]
    }
  end

  def apply_event_range_visibility(form, range_index, hour_fields, custom_fields)
    hour_fields.each { |field| range_index.to_i == 1 ? form.show(field) : form.hide(field) }
    custom_fields.each { |field| range_index.to_i == 2 ? form.show(field) : form.hide(field) }
  end

  def all_day_range(date)
    [Time.local(date.year, date.month, date.day, 0, 0, 0), Time.local(date.year, date.month, date.day, 23, 59, 59)]
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
    values = event_dialog(calendars, calendar, date, event)
    return false if values == nil

    if event == nil
      EltenLink::Calendars.create_event(
        elten_link,
        values[:calendar],
        name: values[:name],
        description: values[:description],
        starttime: values[:starttime],
        endtime: values[:endtime]
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
        endtime: values[:endtime]
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
end

class Scene_Calendar
  include CalendarSceneHelpers

  def initialize(calendar_id=nil, date=nil)
    @filter_calendar_id = calendar_id == nil ? nil : calendar_id.to_i
    @selected_date = normalize_calendar_date(date || Date.today)
  end

  def main
    if Session.name == "guest"
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
    menu.option(p_("Calendar", "Calendars Management"), nil, "c") do
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
    @events_by_day[date] ||= (@events || []).select do |event|
      first = Date.new(event.starttime.year, event.starttime.month, event.starttime.day)
      last = Date.new(event.endtime.year, event.endtime.month, event.endtime.day)
      first <= date && date <= last
    end
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
      if @sel.selected? && current_calendar != nil
        $scene = Scene_Calendar.new(current_calendar.id, @return_date)
      end
      if @reload
        target_id = @target_calendar_id
        @reload = false
        @target_calendar_id = nil
        if load_management
          index = @calendars.index { |calendar| calendar.id == target_id } || [@sel.index, @calendars.size - 1].min
          build_list([index, 0].max)
        end
      end
      break if $scene != self
    end
  end

  def build_list(index=0)
    @sel = ListBox.new(@calendars.map { |calendar| calendar_label(calendar) }, header: p_("Calendar", "Calendars Management"), index: index, quiet: false)
    @sel.bind_context { |menu| context(menu) }
  end

  def context(menu)
    calendar = current_calendar
    if calendar != nil
      menu.option(p_("Calendar", "Show in calendar")) do
        $scene = Scene_Calendar.new(calendar.id, @return_date)
      end
      if calendar.owned_by?(Session.name)
        menu.option(p_("Calendar", "Share calendar"), nil, "s") { share_calendar(calendar) }
        menu.option(p_("Calendar", "Manage calendar shares")) { manage_shares(calendar) }
        menu.option(p_("Calendar", "Delete calendar"), nil, :del) { delete_calendar(calendar) }
      end
    end
    menu.option(p_("Calendar", "New calendar"), nil, "n") { create_calendar }
    if @invitations.size > 0
      menu.option(p_("Calendar", "Calendar invitations"), nil, "i") { manage_invitations }
    end
    menu.option(p_("Calendar", "Public calendars"), nil, "p") do
      excluded_ids = @calendars.map(&:id) + @invitations.map { |invitation| invitation.calendar.id }
      $scene = Scene_Calendar_Public.new(@return_filter_id, @return_date, excluded_ids)
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

  def current_calendar
    return nil if @calendars == nil || @calendars.empty? || @sel == nil
    @calendars[@sel.index]
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
    dialog_open
    loop do
      loop_update
      form.update
      break if key_pressed?(:key_escape) || ((key_pressed?(:key_enter) || key_pressed?(:key_space)) && form.index == 4)
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

  def delete_calendar(calendar)
    return if !confirm(p_("Calendar", "Do you really want to delete calendar %{name} and all its events?") % { name: calendar.name })

    EltenLink::Calendars.delete(elten_link, calendar)
    play_sound("editbox_delete")
    request_reload(0)
  rescue EltenLink::Error => error
    Log.warning("Calendar delete failed: #{error.message}")
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

  def manage_invitations
    labels = @invitations.map { |invitation| calendar_label(invitation.calendar) }
    index = selector(labels, header: p_("Calendar", "Calendar invitations"), cancel_index: -1)
    return if index < 0
    invitation = @invitations[index]
    action = selector([p_("Calendar", "Accept invitation"), p_("Calendar", "Reject invitation"), _("Cancel")], header: calendar_label(invitation.calendar), cancel_index: 2)
    if action == 0
      EltenLink::Calendars.accept_share(elten_link, invitation.calendar)
      request_reload(invitation.calendar.id)
    elsif action == 1
      EltenLink::Calendars.reject_share(elten_link, invitation.calendar)
      request_reload(current_calendar && current_calendar.id)
    end
  rescue EltenLink::Error => error
    Log.warning("Calendar invitation action failed: #{error.message}")
    alert(_("Error"))
  end
end

class Scene_Calendar_Public
  include CalendarSceneHelpers

  def initialize(return_filter_id=nil, date=nil, excluded_ids=[])
    @return_filter_id = return_filter_id == nil ? nil : return_filter_id.to_i
    @return_date = normalize_calendar_date(date || Date.today)
    @excluded_ids = excluded_ids.map(&:to_i).uniq
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
    @all_calendars.reject! { |calendar| @excluded_ids.include?(calendar.id) }
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
      @calendars.map { |calendar| calendar_label(calendar) },
      header: p_("Calendar", "Public calendars"),
      index: index,
      quiet: false
    )
    @sel.bind_context { |menu| context(menu) }
  end

  def context(menu)
    calendar = current_calendar
    if calendar != nil
      menu.option(p_("Calendar", "Subscribe"), nil, "s") { subscribe(calendar) }
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

  def subscribe(calendar)
    EltenLink::Calendars.subscribe(elten_link, calendar)
    @excluded_ids << calendar.id
    @excluded_ids.uniq!
    @all_calendars.reject! { |item| item.id == calendar.id }
    alert(p_("Calendar", "The calendar has been subscribed"))
    build_list
  rescue EltenLink::Error => error
    Log.warning("Public calendar subscription failed: #{error.message}")
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
    @events = EltenLink::Calendars.all_events(elten_link)
    mark_public_calendar_events(@events, @calendars)
    @events.select! { |event| event.endtime.to_i >= now.to_i }
    if @return_filter_id == nil
      @events.reject!(&:public_calendar?)
    else
      @events.select! { |event| event.calendar_id == @return_filter_id }
    end
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
