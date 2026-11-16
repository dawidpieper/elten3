# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "tzinfo"
require "tzinfo/data"

module EltenLink
  module TimeZones
    class << self
      def fixed_offset(identifier)
        return 0 if identifier == "UTC"
        match = /\AUTC([+-])(\d{2}):(\d{2})\z/.match(identifier.to_s)
        return nil unless match
        hours, minutes = match[2].to_i, match[3].to_i
        return nil if minutes > 59 || hours > 14 || (hours == 14 && minutes != 0)

        (hours * 3600 + minutes * 60) * (match[1] == "-" ? -1 : 1)
      end

      def offset_label(offset)
        return "UTC" if offset == 0

        format("UTC%s%02d:%02d", offset < 0 ? "-" : "+", offset.abs / 3600, offset.abs % 3600 / 60)
      end

      def local(identifier, time)
        return time if identifier == nil

        offset = fixed_offset(identifier)
        return time.getlocal(offset) if offset != nil

        zone(identifier).to_local(time)
      end

      def local_times(identifier, date, hour=0, minute=0, second=0, resolve: false)
        return [Time.local(date.year, date.month, date.day, hour, minute, second)] if identifier == nil

        wall = Time.utc(date.year, date.month, date.day, hour, minute, second)
        offset = fixed_offset(identifier)
        return [Time.at(wall.to_i - offset).getlocal(offset)] if offset != nil

        timezone = zone(identifier)
        periods = timezone.periods_for_local(wall)
        if periods.empty?
          raise TZInfo::PeriodNotFound, "The selected time does not exist in this time zone" unless resolve

          transition = timezone.transitions_up_to(wall + 172800, wall - 172800).find do |item|
            before = item.previous_offset.observed_utc_offset
            after = item.offset.observed_utc_offset
            after > before && wall.to_i >= item.timestamp_value + before && wall.to_i < item.timestamp_value + after
          end
          raise TZInfo::PeriodNotFound, "No time zone transition found" unless transition

          return [timezone.to_local(Time.at(wall.to_i - transition.previous_offset.observed_utc_offset))]
        end
        periods.map { |period| timezone.to_local(Time.at(wall.to_i - period.observed_utc_offset)) }.sort
      end

      def identifiers
        @identifiers ||= (["UTC"] + TZInfo::Timezone.all_country_zone_identifiers.sort +
          (-48..56).reject(&:zero?).map { |quarter| offset_label(quarter * 900) }).freeze
      end

      def label(identifier, date)
        return nil if identifier == nil
        return identifier if fixed_offset(identifier) != nil

        time = local_times(identifier, date, 12, resolve: true).first
        parts = identifier.tr("_", " ").split("/")
        "#{parts.pop}, #{parts.join("/")} (#{offset_label(time.utc_offset)})"
      end

      def system
        identifier = EltenSystemHelpers.current_timezone
        return nil if identifier.to_s.empty?
        zone(identifier) if fixed_offset(identifier) == nil
        identifier
      rescue TZInfo::InvalidTimezoneIdentifier
        nil
      end

      private

      def zone(identifier)
        @zones ||= {}
        @zones[identifier] ||= TZInfo::Timezone.get(identifier)
      end
    end
  end
end
