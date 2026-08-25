# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
  module WaitForItem
    WAIT_ACTIONS = [:select, :expand, :collapse, :escape].freeze

    # Waits for one of the requested list actions and returns the active item.
    #
    # Selection and expansion return the item. Collapse and Escape cancel the
    # wait and return nil. Actions not included in +actions+ remain regular
    # control input and do not finish the wait.
    # @param actions [Array<Symbol>] actions which can finish the wait
    # @return [Object, nil] the active option or row, or nil when cancelled
    def wait_for_item(actions: WAIT_ACTIONS)
      actions = Array(actions)
      raise ArgumentError, "actions cannot be empty" if actions.empty?
      invalid = actions.reject { |action| WAIT_ACTIONS.include?(action) }
      raise ArgumentError, "unsupported actions: #{invalid.join(', ')}" if invalid.any?
      actions = actions.uniq

      focus if @wait_for_item_started == true || @wait_for_item_quiet != false
      @wait_for_item_started = true
      loop do
        loop_update
        update
        return nil if actions.include?(:escape) && key_pressed?(:key_escape)
        return nil if actions.include?(:collapse) && collapsed?
        activated = (actions.include?(:select) && selected?) ||
          (actions.include?(:expand) && expanded?)
        next unless activated && wait_item_available?(index)
        return wait_item_at(index)
      end
    end

    private

    def wait_item_available?(_index)
      false
    end

    def wait_item_at(_index)
      nil
    end
  end

  class FormField < FormBase
    def text_utf8(value)
      str = value.to_s
      if str.encoding == Encoding::UTF_8
        return str if str.valid_encoding?
      else
        str = str.dup
        str.force_encoding(Encoding::UTF_8) if str.encoding == Encoding::ASCII_8BIT
      end
      str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    private :text_utf8

    def focus(index=nil,count=nil)
      end
    def subindex
      return 0
    end
    def maxsubindex
      return 0
    end
    def update(*arg)
      super
            if $focus==true
        $focus=false
        focus
      end
        end
      end


  end
end
