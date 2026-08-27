# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "date"

module EltenLink
  class Calendar
    attr_accessor :id, :author, :creation, :name, :public, :lang, :personal, :moderator, :subscribers_count

    def initialize(id: 0, author: nil, creation: nil, name: "", public_state: false, lang: nil, personal: false, moderator: false, subscribers_count: 0)
      @id = id.to_i
      @author = author.to_s
      @creation = creation.is_a?(Time) ? creation : Time.at(creation.to_i)
      @name = name.to_s
      @public = public_state == true
      @lang = lang == nil ? nil : lang.to_s
      @personal = personal == true || @id == 0
      @moderator = moderator == true
      @subscribers_count = [subscribers_count.to_i, 0].max
    end

    def personal?
      @personal == true || @id == 0
    end

    def owned_by?(user)
      !personal? && @author.to_s.casecmp(user.to_s) == 0
    end

    def moderator?
      @moderator == true
    end

    def can_manage_events?(user)
      personal? || owned_by?(user) || moderator?
    end
  end

  class CalendarEvent
    attr_accessor :id, :calendar_id, :author, :starttime, :endtime, :frequency, :name, :description, :public_calendar

    def initialize(id: 0, calendar_id: 0, author: nil, starttime: nil, endtime: nil, frequency: 0, name: "", description: "", public_calendar: false)
      @id = id.to_i
      @calendar_id = calendar_id.to_i
      @author = author.to_s
      @starttime = time_value(starttime)
      @endtime = time_value(endtime)
      @frequency = frequency.to_i
      @frequency = 0 if @frequency < -1
      @name = name.to_s
      @description = description.to_s
      @public_calendar = public_calendar == true
    end

    def all_day?
      @starttime.year == @endtime.year && @starttime.yday == @endtime.yday &&
        @starttime.hour == 0 && @starttime.min == 0 && @starttime.sec == 0 &&
        @endtime.hour == 23 && @endtime.min == 59 && @endtime.sec == 59
    end

    def all_day_series?
      @starttime.hour == 0 && @starttime.min == 0 && @starttime.sec == 0 &&
        @endtime.hour == 23 && @endtime.min == 59 && @endtime.sec == 59
    end

    def public_calendar?
      @public_calendar == true
    end

    def recurring?
      @frequency != 0
    end

    def series_event
      self
    end

    def occurrence_on(value)
      date = date_value(value)
      if !recurring?
        return self if start_date <= date && date <= end_date
        return nil
      end
      return nil unless recurrence_date?(date)

      build_occurrence(date)
    end

    def occurrences_on(value)
      date = date_value(value)
      return [self] if !recurring? && start_date <= date && date <= end_date
      return [] if !recurring?

      [date - 1, date].filter_map do |start|
        occurrence = occurrence_on(start)
        next if occurrence == nil

        occurrence if date_value(occurrence.starttime) <= date && date <= date_value(occurrence.endtime)
      end
    end

    def occurrence_date_on_or_after(value)
      target = date_value(value)
      if !recurring?
        candidate = [target, start_date].max
        return candidate if candidate <= end_date
        return nil
      end

      candidate = @frequency == -1 ? monthly_date_on_or_after(target) : interval_date_on_or_after(target)
      candidate if candidate != nil && occurrence_on(candidate) != nil
    end

    def occurrence_date_on_or_before(value)
      target = date_value(value)
      if !recurring?
        candidate = [target, end_date].min
        return candidate if candidate >= start_date
        return nil
      end

      candidate = @frequency == -1 ? monthly_date_on_or_before(target) : interval_date_on_or_before(target)
      while candidate != nil
        return candidate if occurrence_on(candidate) != nil

        candidate = if @frequency == -1
                      monthly_date_on_or_before(candidate - 1)
                    elsif candidate - @frequency >= start_date
                      candidate - @frequency
                    end
      end
      nil
    end

    def event_date_on_or_after(value)
      target = date_value(value)
      return target unless occurrences_on(target).empty?

      occurrence_date_on_or_after(target)
    end

    def event_date_on_or_before(value)
      target = date_value(value)
      return target unless occurrences_on(target).empty?

      occurrence_date = occurrence_date_on_or_before(target)
      return nil if occurrence_date == nil

      occurrence = occurrence_on(occurrence_date)
      [date_value(occurrence.endtime), target].min if occurrence != nil
    end

    def next_occurrence(now=Time.now)
      return self if !recurring? && @endtime >= now
      return nil if !recurring?

      today = date_value(now)
      previous_date = occurrence_date_on_or_before(today)
      previous = occurrence_on(previous_date) if previous_date != nil
      return previous if previous != nil && previous.endtime >= now

      next_date = occurrence_date_on_or_after(today + 1)
      occurrence_on(next_date) if next_date != nil
    end

    private

    def time_value(value)
      value.is_a?(Time) ? value : Time.at(value.to_i)
    end

    def date_value(value)
      return value if value.is_a?(Date)

      Date.new(value.year, value.month, value.day)
    end

    def start_date
      date_value(@starttime)
    end

    def end_date
      date_value(@endtime)
    end

    def recurrence_date?(date)
      return false if date < start_date || date > end_date
      if @frequency == -1
        date.day == start_date.day
      elsif @frequency > 0
        ((date - start_date).to_i % @frequency).zero?
      else
        false
      end
    end

    def build_occurrence(date)
      start_seconds = seconds_since_midnight(@starttime)
      end_seconds = seconds_since_midnight(@endtime)
      occurrence_end_date = end_seconds < start_seconds ? date + 1 : date
      occurrence_start = local_time(date, @starttime)
      occurrence_end = local_time(occurrence_end_date, @endtime)
      return nil if occurrence_start < @starttime || occurrence_end > @endtime

      CalendarEventOccurrence.new(self, occurrence_start, occurrence_end)
    end

    def seconds_since_midnight(time)
      time.hour * 3600 + time.min * 60 + time.sec
    end

    def local_time(date, source)
      Time.local(date.year, date.month, date.day, source.hour, source.min, source.sec)
    end

    def interval_date_on_or_after(target)
      target = start_date if target < start_date
      distance = (target - start_date).to_i
      candidate = start_date + ((distance + @frequency - 1) / @frequency) * @frequency
      candidate if candidate <= end_date
    end

    def interval_date_on_or_before(target)
      target = end_date if target > end_date
      return nil if target < start_date

      start_date + ((target - start_date).to_i / @frequency) * @frequency
    end

    def monthly_date_on_or_after(target)
      target = start_date if target < start_date
      month = [months_between(start_date, target), 0].max
      loop do
        candidate = monthly_date(month)
        return nil if month_start(month) > end_date
        return candidate if candidate != nil && candidate >= target && candidate <= end_date
        month += 1
      end
    end

    def monthly_date_on_or_before(target)
      target = end_date if target > end_date
      return nil if target < start_date

      month = months_between(start_date, target)
      while month >= 0
        candidate = monthly_date(month)
        return candidate if candidate != nil && candidate <= target && candidate >= start_date
        month -= 1
      end
      nil
    end

    def months_between(first, second)
      (second.year - first.year) * 12 + second.month - first.month
    end

    def month_start(offset)
      total = start_date.year * 12 + start_date.month - 1 + offset
      Date.new(total / 12, total % 12 + 1, 1)
    end

    def monthly_date(offset)
      month = month_start(offset)
      Date.new(month.year, month.month, start_date.day)
    rescue Date::Error
      nil
    end
  end

  class CalendarEventOccurrence
    attr_reader :series_event, :starttime, :endtime

    def initialize(series_event, starttime, endtime)
      @series_event = series_event
      @starttime = starttime
      @endtime = endtime
    end

    [:id, :calendar_id, :author, :frequency, :name, :description, :public_calendar].each do |method|
      define_method(method) { @series_event.public_send(method) }
    end

    def all_day?
      @starttime.year == @endtime.year && @starttime.yday == @endtime.yday &&
        @starttime.hour == 0 && @starttime.min == 0 && @starttime.sec == 0 &&
        @endtime.hour == 23 && @endtime.min == 59 && @endtime.sec == 59
    end

    def public_calendar?
      @series_event.public_calendar?
    end

    def recurring?
      true
    end

    def all_day_series?
      @series_event.all_day_series?
    end
  end

  class CalendarShare
    attr_accessor :id, :calendar_id, :user, :accepted, :moderator

    def initialize(id: 0, calendar_id: 0, user: "", accepted: false, moderator: false)
      @id = id.to_i
      @calendar_id = calendar_id.to_i
      @user = user.to_s
      @accepted = accepted == true
      @moderator = moderator == true
    end
  end

  class CalendarInvitation
    attr_accessor :id, :calendar, :user, :accepted, :moderator

    def initialize(id: 0, calendar: nil, user: "", accepted: false, moderator: false)
      @id = id.to_i
      @calendar = calendar
      @user = user.to_s
      @accepted = accepted == true
      @moderator = moderator == true
    end
  end

  module Calendars
    class << self
      def list(client)
        data = client.api_data("GET", "/api/v1/calendars")
        data["calendars"].to_a.map { |row| calendar_from(row) }
      end

      def list_public(client)
        data = client.api_data("GET", "/api/v1/calendars/public")
        data["calendars"].to_a.map { |row| calendar_from(row) }
      end

      def invitations(client)
        data = client.api_data("GET", "/api/v1/calendars/invitations")
        data["invitations"].to_a.map do |row|
          CalendarInvitation.new(
            id: row["id"],
            calendar: calendar_from(row["calendar"] || {}),
            user: row["user"],
            accepted: truthy?(row["accepted"]),
            moderator: truthy?(row["moderator"])
          )
        end
      end

      def create(client, name:, public_state: false, lang: nil)
        data = client.api_data(
          "POST",
          "/api/v1/calendars",
          { "name" => name, "public" => public_state, "lang" => lang }
        )
        data["id"].to_i
      end

      def update(client, calendar, name: nil, public_state: nil)
        params = {}
        params["name"] = name if name != nil
        params["public"] = public_state if public_state != nil
        client.api_data("PATCH", "/api/v1/calendars/#{calendar_id(calendar)}", params)
        true
      end

      def delete(client, calendar)
        client.api_data("DELETE", "/api/v1/calendars/#{calendar_id(calendar)}")
        true
      end

      def events(client, calendar, from: nil, to: nil)
        params = {}
        params["from"] = time_to_i(from) if from != nil
        params["to"] = time_to_i(to) if to != nil
        data = client.api_data("GET", "/api/v1/calendars/#{calendar_id(calendar)}/events", params)
        data["events"].to_a.map { |row| event_from(row) }
      end

      def all_events(client, from: nil, to: nil)
        params = {}
        params["from"] = time_to_i(from) if from != nil
        params["to"] = time_to_i(to) if to != nil
        data = client.api_data("GET", "/api/v1/calendars/events", params)
        data["events"].to_a.map { |row| event_from(row) }
      end

      def create_event(client, calendar, name:, description: "", starttime:, endtime:, frequency: 0)
        data = client.api_data(
          "POST",
          "/api/v1/calendars/#{calendar_id(calendar)}/events",
          {
            "name" => name,
            "description" => description,
            "starttime" => time_to_i(starttime),
            "endtime" => time_to_i(endtime),
            "frequency" => frequency.to_i
          }
        )
        data["id"].to_i
      end

      def update_event(client, calendar, event, name: nil, description: nil, starttime: nil, endtime: nil, frequency: nil)
        params = {}
        params["name"] = name if name != nil
        params["description"] = description if description != nil
        params["starttime"] = time_to_i(starttime) if starttime != nil
        params["endtime"] = time_to_i(endtime) if endtime != nil
        params["frequency"] = frequency.to_i if frequency != nil
        client.api_data("PATCH", "/api/v1/calendars/#{calendar_id(calendar)}/events/#{event_id(event)}", params)
        true
      end

      def delete_event(client, calendar, event)
        client.api_data("DELETE", "/api/v1/calendars/#{calendar_id(calendar)}/events/#{event_id(event)}")
        true
      end

      def shares(client, calendar)
        data = client.api_data("GET", "/api/v1/calendars/#{calendar_id(calendar)}/shares")
        data["shares"].to_a.map do |row|
          CalendarShare.new(
            id: row["id"],
            calendar_id: row["calendar"],
            user: row["user"],
            accepted: truthy?(row["accepted"]),
            moderator: truthy?(row["moderator"])
          )
        end
      end

      def add_share(client, calendar, user, moderator: true)
        client.api_data(
          "POST",
          "/api/v1/calendars/#{calendar_id(calendar)}/shares",
          { "user" => user, "moderator" => moderator == true }
        )
      end

      def subscribe(client, calendar)
        client.api_data("POST", "/api/v1/calendars/#{calendar_id(calendar)}/subscription")
        true
      end

      def accept_share(client, calendar)
        client.api_data("PATCH", "/api/v1/calendars/#{calendar_id(calendar)}/shares/membership")
        true
      end

      def delete_membership(client, calendar)
        client.api_data("DELETE", "/api/v1/calendars/#{calendar_id(calendar)}/shares/membership")
        true
      end

      def delete_share(client, calendar, user)
        client.api_data("DELETE", "/api/v1/calendars/#{calendar_id(calendar)}/shares/#{user.to_s.urlenc}")
        true
      end

      def calendar_from(row)
        Calendar.new(
          id: row["id"],
          author: row["author"],
          creation: row["creation"],
          name: row["name"],
          public_state: truthy?(row["public"]),
          lang: row["lang"],
          personal: truthy?(row["personal"]),
          moderator: truthy?(row["moderator"]),
          subscribers_count: row["subscribers_count"]
        )
      end

      def event_from(row)
        CalendarEvent.new(
          id: row["id"],
          calendar_id: row["calendar"],
          author: row["author"],
          starttime: row["starttime"],
          endtime: row["endtime"],
          frequency: row["frequency"],
          name: row["name"],
          description: row["description"],
          public_calendar: truthy?(row["public"])
        )
      end

      private

      def calendar_id(calendar)
        calendar.respond_to?(:id) ? calendar.id.to_i : calendar.to_i
      end

      def event_id(event)
        event.respond_to?(:id) ? event.id.to_i : event.to_i
      end

      def time_to_i(value)
        value.respond_to?(:to_time) ? value.to_time.to_i : value.to_i
      end

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end
    end
  end
end
