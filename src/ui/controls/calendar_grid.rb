# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "date"

module EltenAPI
  module Controls
    private

    class CalendarGrid < FormField
      attr_accessor :header, :silent
      attr_reader :date

      def initialize(date: Date.today, header: "", quiet: true, &note_provider)
        @date = normalize_date(date)
        @header = text_utf8(header)
        @silent = false
        @note_provider = note_provider
        focus if quiet == false
      end

      def date=(value)
        @date = normalize_date(value)
      end

      def day_note
        return "" if @note_provider == nil

        text_utf8(@note_provider.call(@date)).strip
      rescue Exception
        ""
      end

      def focus(index=nil, count=nil, spk=true, include_header: true)
        pan = lpos
        play_sound("listbox_marker", volume: 100, pitch: 100, pan: pan) if spk && !@silent && Configuration.controlspresentation != 2
        trigger(:announce, @date) if spk
        text = announcement
        text = "#{@header}: #{text}" if include_header && @header != nil && @header != ""
        speak(text, pan: pan) if spk
        NVDA.braille(text) if defined?(NVDA) && NVDA.check
      end

      def update
        super
        target = nil
        target = @date - 1 if key_pressed?(:key_left)
        target = @date + 1 if key_pressed?(:key_right)
        target = @date - 7 if key_pressed?(:key_up)
        target = @date + 7 if key_pressed?(:key_down)
        target = shift_month(-1) if key_pressed?(0x21)
        target = shift_month(1) if key_pressed?(0x22)
        target = Date.today if key_pressed?(0x24)

        move_to(target) if target != nil
        trigger(:select, @date) if key_pressed?(:key_enter) || key_pressed?(:key_space)
      end

      def move_to(value, announce: true)
        target = normalize_date(value)
        return if target == @date

        @date = target
        trigger(:move, @date)
        play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) if !@silent
        focus(nil, nil, announce, include_header: false)
      end

      def announcement(note=day_note)
        date_text = format_localized_date(@date)
        note = text_utf8(note).strip
        return date_text if note == ""

        p_("Calendar", "%{date}, %{note}") % { date: date_text, note: note }
      end

      def lpos
        (@date.cwday - 1).to_f / 6.0 * 100.0
      end

      def tips
        [
          p_("Calendar", "Use left and right arrows to move by days"),
          p_("Calendar", "Use up and down arrows to move by weeks"),
          p_("Calendar", "Use Page Up and Page Down to move by months"),
          p_("Calendar", "Press Home to return to today")
        ]
      end

      def key_processed(key)
        return true if [:left, :right, :up, :down, :pageup, :pagedown, :home, :enter, :space].include?(key)

        false
      end

      private

      def shift_month(offset)
        @date >> offset.to_i
      end

      def normalize_date(value)
        return value if value.is_a?(Date)
        return Date.new(value.year, value.month, value.day) if value.respond_to?(:year) && value.respond_to?(:month) && value.respond_to?(:day)

        Date.parse(value.to_s)
      rescue Exception
        Date.today
      end

    end
  end
end
