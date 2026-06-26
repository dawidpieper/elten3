# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
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
        if key_held?(0x11) and key_pressed?(81)
sel.options=["Zabieraj mi to okno","Spadaj z mojego pulpitu","Mam ciebie dość, zamknij się","Zejdź mi z oczu"]
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
                                  return quit("W zasadzie, jak mam zejść z oczu osobie niewidomej? Nie rozumiem. Proszę o doprecyzowanie.")
          end
          end
        end
      end

    class Console
      attr_reader :codes

      def initialize
        @b = binding
        @codes = []
        @hooks = []
      end

      def run(code)
        @codes.unshift(code)
        @codes.pop while @codes.size > 50
        return eval(code, @b, "Console")
      end

      def on_str(&h)
        @hooks.push(h) if h != nil
      end

      def puts(t)
        @hooks.each { |h| h.call(t.to_s) }
        return nil
      end
    end

    # Opens a console
    def console
      if !(defined?(developer_mode?) && developer_mode?)
        Log.warning("Console blocked outside developer mode")
        alert(p_("EAPI_Common", "Console is available only in developer mode.")) if respond_to?(:alert, true)
        return false
      end
      form = Form.new([
        EditBox.new(p_("EAPI_Common", "Enter the command to execute"), type: EditBox::Flags::MultiLine, text: "", quiet: true),
        EditBox.new(p_("EAPI_Common", "Output"), type: EditBox::Flags::ReadOnly, text: "", quiet: true),
        Button.new(p_("EAPI_Common", "Execute"))
      ])
      container = Console.new
      container.on_str { |str| form.fields[1].set_text(form.fields[1].text + "\r\n" + str) }
      form.bind_context { |menu|
        if LocalConfig['ConsoleAutoClearInput']==1
          s=p_("EAPI_Common", "Disable auto clear input")
        else
          s=p_("EAPI_Common", "Enable auto clear input")
        end
        menu.option(s, nil, "i") {
          if LocalConfig['ConsoleAutoClearInput']==1
            LocalConfig['ConsoleAutoClearInput']=0
            alert(p_("EAPI_Common", "Disabled"))
          else
            LocalConfig['ConsoleAutoClearInput']=1
            alert(p_("EAPI_Common", "Enabled"))
          end
        }
        if LocalConfig['ConsoleAutoClearOutput']==1
          s=p_("EAPI_Common", "Disable auto clear output")
        else
          s=p_("EAPI_Common", "Enable auto clear output")
        end
        menu.option(s, nil, "o") {
          if LocalConfig['ConsoleAutoClearOutput']==1
            LocalConfig['ConsoleAutoClearOutput']=0
            alert(p_("EAPI_Common", "Disabled"))
          else
            LocalConfig['ConsoleAutoClearOutput']=1
            alert(p_("EAPI_Common", "Enabled"))
          end
        }
        #By default, source should be copied to output.
        if LocalConfig['ConsoleDontCopySource']==1
          s=p_("EAPI_Common", "Enable source in output")
        else
          s=p_("EAPI_Common", "Disable source in output")
        end
        menu.option(s, nil, "s") {
          if LocalConfig['ConsoleDontCopySource']==1
            LocalConfig['ConsoleDontCopySource']=0
            alert(p_("EAPI_Common", "Enabled"))
          else
            LocalConfig['ConsoleDontCopySource']=1
            alert(p_("EAPI_Common", "Disabled"))
          end
        }
        if container.codes.size > 0
          menu.option(p_("EAPI_Common", "Load last code"), nil, "l") {
            form.fields[0].set_text(container.codes[0])
            form.focus
          }
          menu.submenu(p_("EAPI_Common", "Last codes")) { |m|
            for c in container.codes
              menu.option(c[0...100], c) { |c|
                form.fields[0].set_text(c)
                form.focus
              }
            end
          }
        end
      }
      loop do
        loop_update
        form.update
        if form.fields[2].pressed? or (key_held?(0x11) and key_pressed?(:key_enter))
          kom = form.fields[0].text
          if LocalConfig['ConsoleDontCopySource']==1
            outKom=""
          else
            outKom=kom
          end
          if LocalConfig['ConsoleAutoClearOutput']==1
            form.fields[1].set_text(outKom)
          else
            form.fields[1].set_text(form.fields[1].text + "\r\n\r\n" + outKom)
          end
          begin
            r = container.run(kom).inspect
          rescue Exception
            plc = ""
            if $@.is_a?(Array)
              for e in $@
                if e != nil
                  plc += e + "\n" if e != nil and e[0..6] != "Section"
                end
              end
              lin = $@[0].split(":")[1].to_i
              plc += kom.delete("\r").split("\n")[lin - 1] || ""
            end
            r = $!.class.to_s + " (" + $!.to_s + ")\n" + plc
          end
          speak(r)
          form.fields[0].set_text("") if LocalConfig['ConsoleAutoClearInput']==1
          form.fields[1].set_text(form.fields[1].text + "\r\n#=> " + r, false)
          loop_update
        end
        if key_pressed?(:key_escape)
          if form.fields[0].text=="" || confirm(p_("EAPI_Common", "Are you sure you want to exit console?"))
            break
            end
          end
      end
    end

# Opens a menu of a specified user
#
# @param user name of the user whose menu you want to open
  end
end
