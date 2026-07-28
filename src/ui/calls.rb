# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module UI
    private
class CallWindow
      attr_reader :id, :caller, :channel, :password
      def initialize(id, caller, channel, password)
        @id, @caller, @channel, @password = id, caller, channel, password
        @form = Form.new([
        @st_caller = Static.new(p_("EAPI_UI", "%{user} is calling you")%{:user=>@caller}),
        @btn_answer = Button.new(p_("EAPI_UI", "Answer")),
        @btn_reject = Button.new(p_("EAPI_UI", "Reject"))
        ])
      end
      def update
        @form.update
          cancel if @btn_reject.pressed?
          if @btn_answer.pressed?
            cancel
            voicecall(@channel, @password)
            end
        end
        def cancel
          EltenAPI::UI.call_sound_stop
          EltenAPI::EltenSRV.cancel_call(@id, self)
          end
      end

      class MissedCallsWindow
      def initialize(callers=[])
        @callers=callers
        @form = Form.new([
        @lst_callers = ListBox.new(@callers, header: p_("EAPI_UI", "Unanswered calls")),
        @btn_callback = Button.new(p_("EAPI_UI", "Call back")),
        @btn_close = Button.new(p_("EAPI_UI", "Close"))
        ])
@form.cancel_button = @btn_close
@btn_callback.on(:press) {
caller=@callers[@lst_callers.index]
if caller!=nil
ui=userinfo(caller)
if ui!=-1
  callable=ui[12].to_b
  if callable
    voicecall(nil, nil, [caller])
        close
      else
        alert(p_("EAPI_UI", "You cannot call this user"))
    end
  end
  end
}
@btn_close.on(:press) {close}
end
def close
  clear_callers
end
def active
  @callers.size>0
  end
def update
  @form.update
end
def add_caller(caller)
  @callers.push(caller)
  update_list
  focus if @callers.size==1
end
def clear_callers
  @callers=[]
  update_list
end
def update_list
  @lst_callers.options=@callers
end
def focus
  @form.focus
  end
      end

def update_window_tray_visibility
  return if !tray_supported?
  if $tray_restore_ignore_until != nil
    if Time.now.to_f < $tray_restore_ignore_until.to_f
      EltenWindow.consume_minimize_request
      return
    end
    $tray_restore_ignore_until = nil
  end
  minimize_requested = EltenWindow.consume_minimize_request
  return if Configuration.hidewindow != true
  return if $trayreturn == true || $window_hidden_to_tray == true
  return if minimize_requested != true && !EltenWindow.minimized?
  Log.info("Elten window minimized")
  play_sound("minimize") rescue nil
  $totray = true
rescue Exception => e
  Log.error("Elten window auto-hide failed: #{e.class}: #{e.message}")end


  end
end
