# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common

# EltenAPI common functions
    # Opens the quit menu
    #
    # @param header [String] a message to read, header of the menu
        def quit(header=p_("EAPI_Common", "Exit..."))
         dialog_open
            options = [_("Cancel")]
            options.push(p_("EAPI_Common", "Hide program in Tray")) if tray_supported?
            options.push(_("Exit"))
            sel = ListBox.new(options,header: header,index: 0,flags: ListBox::Flags::AnyDir, quiet: false)
            sel.disable_menu
      loop do
        loop_update
        sel.update
        if physical_control_held? and key_pressed?(81)
sel.options=[p_("EAPI_Common","Break this window's glass"),p_("EAPI_Common","Get off my desktop"),p_("EAPI_Common","Shut up!"),p_("EAPI_Common","I do not wish seeing you anymore")]
          sel.focus
          end
        if key_pressed?(:key_escape)
          sel.enable_menu
          dialog_close
loop_update
          break
            $exit = false
            return(false)
            end
        if key_pressed?(:key_enter)
          sel.enable_menu
          loop_update
          dialog_close
          if !tray_supported? && sel.index == options.size - 1
              $scene = nil
              break
          end
          case sel.index
          when 0
loop_update
            break
            $exit = false
            return(false)
            when 1
loop_update
              $exit = false
              tray
              return false
            when 2
              $scene = nil
              break
              $exit = true
              return(true)
                $exit = false
                return false
                when 3
                                  return quit(p_("EAPI_Common","Could you provide me more details on that matter? I have no sense of seeing. And do you?"))
          end
          end
        end
      end
  end
  include Common
end
