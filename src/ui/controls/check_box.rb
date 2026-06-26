# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
      class CheckBox < FormField
        # @return [String] a checkbox label
        attr_accessor :label
        # @return [Numeric] 0 if non-checked, 1 if checked
        attr_reader :checked

        # Creates a checkbox
        #
        # @param checked [Numeric] specifies the default state of a checkbox (0 - not checked, 1 - checked)
        # @param label [String] a checkbox label
        def initialize(label="", checked: false)
          @label = label
          self.checked = checked
        end
        def checked=(checked)
          @checked = (checked == true || (checked.respond_to?(:to_i) && checked.to_i != 0))
        end

        # Updates a checkbox
        def update
super
  focus(nil, nil, true,false) if key_held?(0x2D) and key_pressed?(:key_up)
          if key_pressed?(:key_space)
            if @checked == true
              @checked = false
              alert(p_("EAPI_Form", "unchecked"), false)
            else
              @checked = true
              alert(p_("EAPI_Form", "Checked"), false)
            end
            focus(nil, nil, false)
            trigger(:change)
            end
          end

          def value
            return @checked
            end

                    def focus(index=nil,count=nil, spk=true, snd=true)
                      pos=50
    pos=index.to_f/(count-1).to_f*100.0 if index!=nil and count!=nil && count!=0
          play_sound("checkbox_marker", volume: 100, pitch: 100, pan: pos) if spk and snd && Configuration.controlspresentation!=2
          text = @label + " ... "
          if Configuration.controlspresentation!=1
          text += p_("EAPI_Form", "Checkbox")+" "
          end
          if @checked == false
            text += p_("EAPI_Form", "unticked")
          else
            text += p_("EAPI_Form", "ticked")
          end
                    speak(text) if spk
          NVDA.braille(text) if defined?(NVDA) && NVDA.check
        end

        def key_processed(k)
          if k==:space
            return true
          else
            return false
            end
          end
          end

      # Creates a files tree

  end
end
