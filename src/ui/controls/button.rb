# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
        class Button < FormField
        # @return [String] the label of a button
          attr_accessor :label

          # Creates a button
          #
          # @param label [String] a button label
        def initialize(label="")
          @label = label
          @pressed=false
        end

        # Updates a button
        def update
super
  speak(@label) if key_held?(0x2D) and key_pressed?(:key_up)
  @pressed = (key_pressed?(:key_enter)||key_pressed?(:key_space))
  trigger(:press) if @pressed
          end
        def focus(index=nil,count=nil)
          pos=50
    pos=index.to_f/(count-1).to_f*100.0 if index!=nil and count!=nil && count!=0
          play_sound("button_marker", volume: 100, pitch: 100, pan: pos) if Configuration.controlspresentation!=2
          tph="... " + p_("EAPI_Form", "Button")
          tph="" if Configuration.controlspresentation==1
          speak(@label + tph)
          NVDA.braille(@label) if defined?(NVDA) && NVDA.check
        end
        def pressed?
          pr=@pressed
          @pressed=false
          return pr
        end
        def press
          @pressed=true
          trigger(:press)
        end
        def key_processed(k)
          if k==:space || k==:enter
            return true
          else
            return false
            end
          end
      end

      # A checkbox class

  end
end
