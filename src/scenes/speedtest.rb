# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_SpeedTest
  def main
    @form=Form.new([ListBox.new([p_("SpeedTest", "Session refresh"),p_("SpeedTest", "Forum structure"),p_("SpeedTest", "Messages recipients"),p_("SpeedTest", "Blogs list")],header: p_("SpeedTest", "Component to test")),EditBox.new(p_("SpeedTest", "Number of test runs"),type: EditBox::Flags::Numbers,text: "10",quiet: true),Button.new(p_("SpeedTest", "Start")),Button.new(_("Cancel"))])
    loop do
      loop_update
      @form.update
      insert_scene(Scene_Palantiri.new, true) if keyboard_binding_pressed?([:p, :control], first: true)
      break if $scene!=self
      $scene=Scene_Main.new if ((key_pressed?(:key_space) or key_pressed?(:key_enter)) and @form.index==3) or key_pressed?(:key_escape)
      if @form.fields[2].pressed? and @form.fields[1].text.to_i>0
        n=@form.fields[1].text.to_i
        next unless confirm_attempt_count(n)
        measure = nil
        case @form.fields[0].index
        when 0
          measure = proc { EltenLink::System.measure_realtime_state(elten_link) }
            when 1
              measure = proc { EltenLink::System.measure_forum_structure(elten_link) }
              when 2
                measure = proc { EltenLink::System.measure_messages_conversations(elten_link) }
                when 3
                  measure = proc { EltenLink::System.measure_blog_list(elten_link) }
                end
                speak(p_("SpeedTest", "Test in progress. Please wait."))
                times=[]
                errors=0
                waiting {
                  n.times {
            t=measure.call
     if t>0
            times.push(t)
          else
            errors+=1
            end
     loop_update
           }
           }
result = "#{p_("SpeedTest", "Average time")}: #{((times.sum).to_f / (n-errors.to_f) * 1000).round}ms           
#{p_("SpeedTest", "Minimum time")}: #{((times.min)*1000).round}ms
#{p_("SpeedTest", "Maximum time")}: #{((times.max)*1000).round}ms
#{p_("SpeedTest", "Number of errors")}: #{errors}

"
      for i in 0...n
        result+=(i+1).to_s+". "+(times[i]*1000).round.to_s+"ms\r\n"
        end
      input_text(p_("SpeedTest", "Test results"),flags: EditBox::Flags::ReadOnly,text: result)
      @form.focus
      end
      end
  end

  def confirm_attempt_count(attempts)
    if attempts == 418
      alert(p_("SpeedTest", "HTCPCP/1.0 418. The teapot refuses to brew coffee. No request has been sent."))
      return false
    end
    return true if attempts <= 20

    confirm(p_("SpeedTest", "The server rate limiter may limit the number of requests depending on the current load. Are you sure you want to continue?"))
  end

  end
