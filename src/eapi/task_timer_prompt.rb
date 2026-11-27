# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  # User interaction for the task focus timer: announcing the next focus
  # session and asking what to do when a focus session ends. The timer state
  # itself lives in TaskTimer.
  module TaskTimerPrompt
    EXTEND_CHOICES = [5, 15].freeze
    PROMPT_REPEAT_SECONDS = 10
    DO_NOT_DISTURB_VOLUME = 60
    ALARM_KEY_DELAY = 1.0

    class << self
      def update
        started = TaskTimer.update
        announce_next_session(started) if started != nil
      rescue Exception => e
        Log.error("Task timer update: #{e.class}: #{e.message}")
      end

      def pending?
        TaskTimer.prompt_pending?
      end

      def show
        info = TaskTimer.claim_prompt
        return false if info == nil
        run_prompt(info)
        true
      rescue Exception => e
        Log.error("Task timer prompt: #{e.class}: #{e.message}")
        false
      end

      private

      def alert_volume
        EltenAPI::UI.notifications_muted? ? DO_NOT_DISTURB_VOLUME : 100
      end

      def announce_next_session(started)
        play_sound("clock", volume: alert_volume)
        alert(p_("EAPI_TaskTimer", "Break is over. Focus session %{session} started: %{task}, %{time}") %
              { session: started[:session], task: started[:task_name],
                time: TaskTimer.duration_text(started[:minutes] * 60) }, false)
      end

      def prompt_choices(info)
        choices = []
        if !info[:has_goals] && TaskTimer.same_session?
          choices << [:complete, p_("EAPI_TaskTimer", "Mark as completed")]
        end
        EXTEND_CHOICES.each do |minutes|
          choices << [minutes, p_("EAPI_TaskTimer", "Extend by %{time}") % { time: TaskTimer.duration_text(minutes * 60) }]
        end
        choices << [:break, p_("EAPI_TaskTimer", "Take a %{time} break, then start another session") %
                            { time: TaskTimer.duration_text(TaskTimer::BREAK_MINUTES * 60) }]
        choices << [:finish, p_("EAPI_TaskTimer", "Finish without completing")]
        choices
      end

      def run_prompt(info)
        choices = prompt_choices(info)
        header = p_("EAPI_TaskTimer", "%{task}: time is up") % { task: info[:task_name] }
        decided = false
        bindings = Controls::FormBindings.new
        dialog_open
        begin
          form = Controls::Form.new([
            lst_choices = Controls::ListBox.new(choices.map(&:last), header: header),
            btn_later = Controls::Button.new(p_("EAPI_TaskTimer", "Decide later"))
          ])
          form.cancel_button = btn_later
          bindings.on(btn_later, :press) { form.resume }
          bindings.on(lst_choices, :select) do
            if !TaskTimer.current_task?(info[:task_id])
              decided = true
              form.resume
            elsif apply_choice(info, choices[lst_choices.index][0])
              decided = true
              form.resume
            end
          end
          ringing = true
          armed = false
          opened_at = monotonic_time
          alarm_sound_start(volume: alert_volume)
          # A key that was already down when the prompt opened (for example
          # while typing, or the key that opened it from the menu) must not
          # silence the alarm before it is heard. Only a new key press after
          # a short delay and after all keys were released stops it.
          bindings.timer(form, 0, repeat: true) do
            if ringing
              if !armed
                armed = monotonic_time - opened_at >= ALARM_KEY_DELAY && !KeyboardState.any_held?
              elsif key_any_pressed?
                alarm_sound_stop
                ringing = false
              end
            end
          end
          bindings.timer(form, PROMPT_REPEAT_SECONDS, repeat: true) { speak(header) if ringing }
          form.wait
        ensure
          alarm_sound_stop
          bindings.close
          dialog_close
          loop_update
        end
        return if decided

        TaskTimer.postpone_prompt(info[:task_id])
        alert(p_("EAPI_TaskTimer", "You can decide later from the focus timer in the task menu"))
      end

      # Returns true when the choice was carried out and the prompt can close.
      def apply_choice(info, choice)
        case choice
        when :complete
          complete_task(info)
        when Integer
          TaskTimer.extend_focus(choice)
          alert(p_("EAPI_TaskTimer", "Focus time extended: %{time} left") % { time: TaskTimer.duration_text(choice * 60) })
          true
        when :break
          TaskTimer.start_break
          alert(p_("EAPI_TaskTimer", "Break started: %{time}. The next focus session will start after it") %
                { time: TaskTimer.duration_text(TaskTimer::BREAK_MINUTES * 60) })
          true
        when :finish
          TaskTimer.stop
          alert(p_("EAPI_TaskTimer", "The focus timer has been stopped"))
          true
        else
          false
        end
      end

      def complete_task(info)
        return false unless session_matches?
        performer = info[:performer].to_s
        if !performer.empty? && performer.casecmp(Session.name.to_s) != 0
          question = p_("EAPI_TaskTimer", "This task is assigned to %{user}. Do you want to mark it as completed anyway?") %
                     { user: performer }
          return false unless confirm(question)
        end
        # The confirmation may have taken a while, so check the session again.
        return false unless session_matches?

        client = EltenLink::Client.new
        Tasks.run(title: p_("EAPI_TaskTimer", "Completing the task. Press Escape to cancel."), cancellable: true) do |_progress, token|
          EltenLink::Tasks.complete(client, info[:task_id], cancellation_token: token)
        end
        TaskTimer.stop if TaskTimer.current_task?(info[:task_id])
        alert(p_("EAPI_TaskTimer", "The task has been completed"))
        if $scene.is_a?(Scene_Tasks)
          $scene.request_reload(info[:task_parent] > 0 ? info[:task_parent] : info[:task_id])
        end
        true
      rescue Tasks::Cancelled
        alert(p_("EAPI_TaskTimer", "Completing the task was cancelled"))
        false
      rescue Tasks::TimedOut, EltenLink::Error => e
        Log.warning("Task timer completion failed: #{e.message}")
        alert(e.is_a?(EltenLink::Error) && !e.message.to_s.empty? ? e.message : _("Error"))
        false
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def session_matches?
        return true if TaskTimer.same_session?
        alert(p_("EAPI_TaskTimer", "This focus timer was started on another account. Sign in to that account to complete the task."))
        false
      end
    end
  end
end
