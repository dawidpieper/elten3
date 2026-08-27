# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
    class ChoiceListBox < FormField
      Row = Struct.new(:label, :options, :value)

      class Flags
        Silent = ListBox::Flags::Silent
        Circular = ListBox::Flags::Circular
        HotKeys = ListBox::Flags::HotKeys
        CircularValues = 128
      end

      LIST_BOX_FLAGS = Flags::Silent | Flags::Circular | Flags::HotKeys

      attr_reader :rows, :sel

      def initialize(rows=[], header: "", index: 0, quiet: true, flags: 0)
        @flags = flags.to_i
        @header = text_utf8(header)
        @rows = normalize_rows(rows)
        @wait_for_choice_quiet = quiet
        @wait_for_choice_started = false
        list_flags = @flags & LIST_BOX_FLAGS
        @sel = ListBox.new(format_rows, header: @header, index: index, flags: list_flags, quiet: quiet)
        @sel.on(:move) { |args| trigger(:move, args) }
        @sel.on(:select) { |args| trigger(:select, args) }
        @sel.on(:border) { |args| trigger(:border, args) }
      end

      def header
        @header
      end

      def header=(header)
        @header = text_utf8(header)
        @sel.header = @header if @sel!=nil
      end

      def rows=(rows)
        @rows = normalize_rows(rows)
        reload
      end

      def append(label, options, value: 0)
        options = options.is_a?(Array) ? options.dup : []
        @rows.push(Row.new(label, options, normalize_value(value, options)))
        reload
        @rows.size - 1
      end

      def reload
        return if @sel==nil
        @sel.options = format_rows
        @sel.index = [[@sel.index.to_i, 0].max, [@rows.size - 1, 0].max].min
      end

      def index
        @sel.index
      end

      def index=(index)
        @sel.index = index
      end

      def value(row=index)
        entry = row_at(row)
        entry==nil ? nil : entry.value
      end

      def values
        @rows.map(&:value)
      end

      def selected_option(row=index)
        entry = row_at(row)
        return nil if entry==nil || entry.options.empty?
        entry.options[entry.value]
      end

      def set_value(row, value)
        entry = row_at(row)
        return false if entry==nil
        normalized = normalize_value(value, entry.options)
        changed = entry.value!=normalized
        entry.value = normalized
        refresh_row(row)
        changed
      end

      def set_options(row, options, value: 0)
        entry = row_at(row)
        return false if entry==nil
        entry.options = options.is_a?(Array) ? options.dup : []
        entry.value = normalize_value(value, entry.options)
        refresh_row(row)
        true
      end

      def autosayoption
        @sel.autosayoption
      end

      def autosayoption=(value)
        @sel.autosayoption = value
      end

      def say_option
        @sel.say_option
      end
      alias sayoption say_option

      def update
        super
        @sel.update
        return if raw_key_held?(:key_shift) || raw_key_held?(:key_insert) || navigation_modifier_held?
        if key_pressed?(:key_left)
          move_value(-1)
        elsif key_pressed?(:key_right)
          move_value(1)
        end
      end

      def focus(index=nil, count=nil)
        @sel.focus(index, count)
      end

      def selected?
        @sel.selected?
      end

      # Runs this control as a standalone choice dialog.
      # @return [Array(Integer, Array<Integer>), nil] the active row and values,
      #   or nil when cancelled
      def wait_for_choice
        focus if @wait_for_choice_started || @wait_for_choice_quiet != false
        @wait_for_choice_started = true
        loop do
          loop_update
          update
          return nil if key_pressed?(:key_escape) || key_pressed?(:key_alt)
          return [index, values] if selected? && row_at(index) != nil
        end
      end

      def collapsed?
        false
      end

      def expanded?
        false
      end

      def lpos
        @sel.lpos
      end

      def key_processed(key)
        return true if key==:left || key==:right
        @sel.key_processed(key)
      end

      private

      def normalize_rows(rows)
        rows.to_a.map do |row|
          label, options, value = row.to_a
          options = options.is_a?(Array) ? options.dup : []
          Row.new(label, options, normalize_value(value, options))
        end
      end

      def normalize_value(value, options)
        return 0 if options.empty?
        [[value.to_i, 0].max, options.size - 1].min
      end

      def row_at(row)
        row = row.to_i
        return nil if row<0 || row>=@rows.size
        @rows[row]
      end

      def format_rows
        @rows.map { |row| format_row(row) }
      end

      def format_row(row)
        label = speech_value(row.label)
        option = row.options.empty? ? "" : speech_value(row.options[row.value])
        return option if label.to_s.empty?
        return label if option.to_s.empty?
        speech_append(speech_append(label, ": "), option)
      end

      def speech_value(value)
        value.is_a?(SpeechSequence) ? value : text_utf8(value)
      end

      def speech_append(value, part)
        if value.is_a?(SpeechSequence) || part.is_a?(SpeechSequence)
          SpeechSequence.new(value, part)
        else
          value.to_s + part.to_s
        end
      end

      def refresh_row(row)
        return if @sel==nil
        row = row.to_i
        return if row<0 || row>=@rows.size
        @sel.options = format_rows
      end

      def circular_values?
        (@flags & Flags::CircularValues)>0
      end

      def move_value(direction)
        entry = row_at(index)
        return if entry==nil
        if entry.options.empty?
          value_border(direction) unless circular_values?
          return
        end
        new_value = entry.value + direction
        if circular_values?
          new_value %= entry.options.size
          return if new_value==entry.value
        elsif new_value<0 || new_value>=entry.options.size
          value_border(direction)
          return
        end
        entry.value = new_value
        refresh_row(index)
        play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) if @sel.silent==false
        @sel.say_option
        trigger(:change, index, new_value)
      end

      def value_border(direction)
        play_sound("border", volume: 100, pitch: 100, pan: lpos) if @sel.silent==false
        trigger(:border, index, direction<0 ? :left : :right)
      end
    end
  end
end
