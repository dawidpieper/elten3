# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenLink
  class Calendar
    attr_accessor :id, :author, :creation, :name, :public, :lang, :personal, :moderator

    def initialize(id: 0, author: nil, creation: nil, name: "", public_state: false, lang: nil, personal: false, moderator: false)
      @id = id.to_i
      @author = author.to_s
      @creation = creation.is_a?(Time) ? creation : Time.at(creation.to_i)
      @name = name.to_s
      @public = public_state == true
      @lang = lang == nil ? nil : lang.to_s
      @personal = personal == true || @id == 0
      @moderator = moderator == true
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
    attr_accessor :id, :calendar_id, :author, :starttime, :endtime, :name, :description, :public_calendar

    def initialize(id: 0, calendar_id: 0, author: nil, starttime: nil, endtime: nil, name: "", description: "", public_calendar: false)
      @id = id.to_i
      @calendar_id = calendar_id.to_i
      @author = author.to_s
      @starttime = time_value(starttime)
      @endtime = time_value(endtime)
      @name = name.to_s
      @description = description.to_s
      @public_calendar = public_calendar == true
    end

    def all_day?
      @starttime.year == @endtime.year && @starttime.yday == @endtime.yday &&
        @starttime.hour == 0 && @starttime.min == 0 && @starttime.sec == 0 &&
        @endtime.hour == 23 && @endtime.min == 59 && @endtime.sec == 59
    end

    def public_calendar?
      @public_calendar == true
    end

    private

    def time_value(value)
      value.is_a?(Time) ? value : Time.at(value.to_i)
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

      def create_event(client, calendar, name:, description: "", starttime:, endtime:)
        data = client.api_data(
          "POST",
          "/api/v1/calendars/#{calendar_id(calendar)}/events",
          {
            "name" => name,
            "description" => description,
            "starttime" => time_to_i(starttime),
            "endtime" => time_to_i(endtime)
          }
        )
        data["id"].to_i
      end

      def update_event(client, calendar, event, name: nil, description: nil, starttime: nil, endtime: nil)
        params = {}
        params["name"] = name if name != nil
        params["description"] = description if description != nil
        params["starttime"] = time_to_i(starttime) if starttime != nil
        params["endtime"] = time_to_i(endtime) if endtime != nil
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

      def reject_share(client, calendar)
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
          moderator: truthy?(row["moderator"])
        )
      end

      def event_from(row)
        CalendarEvent.new(
          id: row["id"],
          calendar_id: row["calendar"],
          author: row["author"],
          starttime: row["starttime"],
          endtime: row["endtime"],
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
