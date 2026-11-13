# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

require "date"

module EltenAPI
  module Controls
    private

    class DateField < FormField
      SEGMENTS = [:year, :month, :day, :hour, :minute].freeze
      TYPE_TIMEOUT = 1.0

      attr_accessor :header, :silent
      attr_reader :year, :month, :day, :hour, :minute

      def initialize(header="", date: Date.today, years: nil, include_time: false, hour: 23, minute: 59)
        @header = text_utf8(header)
        @silent = false
        @include_time = include_time
        @years = years
        @segments = include_time ? SEGMENTS : SEGMENTS.first(3)
        @segment = @segments.index(:day)
        @typed = ""
        @typed_at = 0.0
        @hour = hour.to_i.clamp(0, 23)
        @minute = minute.to_i.clamp(0, 59)
        self.date = date
      end

      def date
        Date.new(@year, @month, @day)
      end

      def date=(value)
        @hour, @minute = value.hour, value.min if @include_time && value.respond_to?(:hour) && !value.is_a?(Date)
        value = Date.new(value.year, value.month, value.day) if !value.is_a?(Date) && value.respond_to?(:day)
        value = Date.today unless value.is_a?(Date)
        @year, @month, @day = value.year, value.month, value.day
        clamp_year
      end

      def time
        Time.local(@year, @month, @day, @hour, @minute, @include_time ? 0 : 59)
      end

      def value
        date
      end

      def focus(index=nil, count=nil, spk=true)
        play_sound("listbox_marker", volume: 100, pitch: 100, pan: lpos) if spk && !@silent && Configuration.controlspresentation != :voice_only
        text = full_label
        text = "#{@header}: #{text}" if @header != ""
        text += " ... " + p_("EAPI_Form", "Date, use arrows to change") if spk && Configuration.controlspresentation != :sound_only
        speak(text, pan: lpos) if spk
        NVDA.braille(text) if defined?(NVDA) && NVDA.check
      end

      def update
        super
        if key_pressed?(:key_left)
          move_segment(-1)
        elsif key_pressed?(:key_right)
          move_segment(1)
        elsif key_pressed?(:key_up)
          cycle_segment(1)
        elsif key_pressed?(:key_down)
          cycle_segment(-1)
        elsif key_pressed?(0x21)
          shift_days(-7)
        elsif key_pressed?(0x22)
          shift_days(7)
        elsif keyboard_action_pressed?(:calendar_today)
          self.date = Date.today
          changed(full_label)
        else
          k = getkeychar
          type_digit(k) if k =~ /\A[0-9]\z/
        end
      end

      def key_processed(key)
        return true if [:left, :right, :up, :down, :pageup, :pagedown, :home].include?(key)
        return true if key.to_s =~ /\A[0-9]\z/

        false
      end

      def tips
        [
          p_("EAPI_Form", "Use the Left and Right Arrow keys to move between year, month and day"),
          p_("EAPI_Form", "Use the Up and Down Arrow keys to change the value, or type it with digits"),
          p_("EAPI_Form", "Use Page Up and Page Down to move by a week"),
          p_("EAPI_Form", "Press Home to return to today")
        ]
      end

      private

      def segment
        @segments[@segment]
      end

      def move_segment(offset)
        target = @segment + offset
        if target < 0 || target >= @segments.size
          play_sound("border", volume: 100, pitch: 100, pan: lpos) if !@silent
          return
        end
        @segment = target
        @typed = ""
        play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) if !@silent
        speak(segment_label(true), pan: lpos)
      end

      def cycle_segment(delta)
        @typed = ""
        case segment
        when :year
          @year += delta
          clamp_year
        when :month
          @month = (@month - 1 + delta) % 12 + 1
        when :day
          @day = (@day - 1 + delta) % days_in_month + 1
        when :hour
          @hour = (@hour + delta) % 24
        when :minute
          @minute = (@minute + delta) % 60
        end
        clamp_day_to_month
        changed(segment_label)
      end

      def shift_days(days)
        @typed = ""
        self.date = date + days
        changed(full_label)
      end

      def type_digit(digit)
        now = Time.now.to_f
        @typed = "" if now - @typed_at > TYPE_TIMEOUT
        @typed_at = now
        @typed += digit
        @typed = digit if @typed.size > (segment == :year ? 4 : 2)
        number = @typed.to_i
        case segment
        when :year
          return speak(@typed) if @typed.size < 4
          @year = number
          clamp_year
        when :month
          return speak(@typed) unless (1..12).include?(number)
          @month = number
        when :day
          return speak(@typed) unless (1..days_in_month).include?(number)
          @day = number
        when :hour
          return speak(@typed) unless (0..23).include?(number)
          @hour = number
        when :minute
          return speak(@typed) unless (0..59).include?(number)
          @minute = number
        end
        clamp_day_to_month
        changed(segment_label)
      end

      def changed(text)
        play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) if !@silent
        speak(text, pan: lpos)
        NVDA.braille(full_label) if defined?(NVDA) && NVDA.check
        trigger(:change, date)
      end

      def segment_label(with_name=false)
        value = case segment
                when :year then @year.to_s
                when :month then month_name
                when :day then "#{@day}, #{weekday_name}"
                when :hour then sprintf("%02d", @hour)
                when :minute then sprintf("%02d", @minute)
                end
        return value unless with_name

        names = {
          year: p_("EAPI_Form", "Year"),
          month: p_("EAPI_Form", "Month"),
          day: p_("EAPI_Form", "Day"),
          hour: p_("EAPI_Form", "Hour"),
          minute: p_("EAPI_Form", "Minute")
        }
        "#{names[segment]}: #{value}"
      end

      def full_label
        text = format_localized_date(date)
        text += sprintf(", %02d:%02d", @hour, @minute) if @include_time
        text
      end

      def month_name
        [
          p_("EAPI_Form", "January"), p_("EAPI_Form", "February"), p_("EAPI_Form", "March"),
          p_("EAPI_Form", "April"), p_("EAPI_Form", "May"), p_("EAPI_Form", "June"),
          p_("EAPI_Form", "July"), p_("EAPI_Form", "August"), p_("EAPI_Form", "September"),
          p_("EAPI_Form", "October"), p_("EAPI_Form", "November"), p_("EAPI_Form", "December")
        ][@month - 1]
      end

      def weekday_name
        [
          p_("EAPI_Date_Weekday", "Monday"), p_("EAPI_Date_Weekday", "Tuesday"),
          p_("EAPI_Date_Weekday", "Wednesday"), p_("EAPI_Date_Weekday", "Thursday"),
          p_("EAPI_Date_Weekday", "Friday"), p_("EAPI_Date_Weekday", "Saturday"),
          p_("EAPI_Date_Weekday", "Sunday")
        ][date.cwday - 1]
      end

      def days_in_month
        Date.new(@year, @month, -1).day
      end

      def clamp_day_to_month
        @day = days_in_month if @day > days_in_month
      end

      def clamp_year
        @year = @year.clamp(@years.begin, @years.end) if @years != nil
        clamp_day_to_month
      end

      def lpos
        @segments.size <= 1 ? 50.0 : @segment.to_f / (@segments.size - 1) * 100.0
      end
    end
  end
end
