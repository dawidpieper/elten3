# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module TaskTimer
    PRESETS = [15, 25, 30, 45, 60].freeze
    MAX_MINUTES = 600
    DEFAULT_MINUTES = 25
    LAST_MINUTES_KEY = "TaskTimerMinutes"
    EXTEND_CHOICES = [5, 15].freeze
    BREAK_MINUTES = 5
    PROMPT_REPEAT_SECONDS = 10
    DO_NOT_DISTURB_VOLUME = 60

    @mutex = Mutex.new
    @state = nil

    class << self
      def start(task, minutes)
        minutes = minutes.to_i
        raise ArgumentError, "Invalid focus time: #{minutes}" if minutes < 1 || minutes > MAX_MINUTES

        @mutex.synchronize do
          @state = {
            task_id: task.id,
            project_id: task.project_id,
            task_name: task.name.to_s,
            task_parent: task.parent.to_i,
            performer: task.performer.to_s,
            has_goals: task.composite?,
            minutes: minutes,
            phase: :focus,
            session: 1,
            ends_at: monotonic_time + minutes * 60,
            paused_remaining: nil,
            prompt: nil
          }
        end
        LocalConfig[LAST_MINUTES_KEY] = minutes
        true
      end

      def stop
        @mutex.synchronize do
          active = @state != nil
          @state = nil
          active
        end
      end

      def active?
        @mutex.synchronize { @state != nil }
      end

      def running_for?(task)
        return false if task == nil
        @mutex.synchronize { @state != nil && @state[:task_id] == task.id }
      end

      def task_id
        @mutex.synchronize { @state && @state[:task_id] }
      end

      def project_id
        @mutex.synchronize { @state && @state[:project_id] }
      end

      def task_name
        @mutex.synchronize { @state && @state[:task_name] }
      end

      def on_break?
        @mutex.synchronize { @state != nil && @state[:phase] == :break }
      end

      def paused?
        @mutex.synchronize { @state != nil && @state[:paused_remaining] != nil }
      end

      def remaining
        @mutex.synchronize { remaining_unlocked }
      end

      def finished?
        @mutex.synchronize do
          @state != nil && @state[:paused_remaining] == nil && remaining_unlocked <= 0
        end
      end

      def pause
        @mutex.synchronize do
          return false if @state == nil || @state[:paused_remaining] != nil
          left = remaining_unlocked
          return false if left <= 0
          @state[:paused_remaining] = left
          true
        end
      end

      def resume
        @mutex.synchronize do
          return false if @state == nil || @state[:paused_remaining] == nil
          @state[:ends_at] = monotonic_time + @state[:paused_remaining]
          @state[:paused_remaining] = nil
          true
        end
      end

      def toggle_pause
        paused? ? resume : pause
      end

      def extend_focus(minutes)
        @mutex.synchronize do
          return false if @state == nil
          start_phase_unlocked(:focus, minutes)
          true
        end
      end

      def start_break(minutes=BREAK_MINUTES)
        @mutex.synchronize do
          return false if @state == nil
          start_phase_unlocked(:break, minutes)
          true
        end
      end

      def update
        started = nil
        @mutex.synchronize do
          return if @state == nil || @state[:paused_remaining] != nil || remaining_unlocked > 0
          if @state[:phase] == :break
            @state[:session] += 1
            start_phase_unlocked(:focus, @state[:minutes])
            started = [@state[:task_name], @state[:minutes], @state[:session]]
          elsif @state[:prompt] == nil
            @state[:prompt] = :pending
          end
        end
        announce_next_session(*started) if started != nil
      rescue Exception => e
        Log.error("Task timer update: #{e.class}: #{e.message}")
      end

      def prompt_pending?
        @mutex.synchronize { @state != nil && @state[:prompt] == :pending }
      end

      def show_prompt
        info = nil
        @mutex.synchronize do
          return false if @state == nil || @state[:phase] != :focus || @state[:prompt] == :shown
          return false if @state[:paused_remaining] != nil || remaining_unlocked > 0
          @state[:prompt] = :shown
          info = @state.dup
        end
        handle_prompt(info)
        true
      rescue Exception => e
        Log.error("Task timer prompt: #{e.class}: #{e.message}")
        false
      end

      def last_minutes
        value = LocalConfig[LAST_MINUTES_KEY, DEFAULT_MINUTES, type: :numeric].to_i
        value < 1 || value > MAX_MINUTES ? DEFAULT_MINUTES : value
      rescue Exception
        DEFAULT_MINUTES
      end

      def duration_text(seconds)
        seconds = seconds.to_f.ceil
        minutes = seconds / 60
        secs = seconds % 60
        parts = []
        if minutes > 0
          parts << np_("EAPI_TaskTimer", "%{count} minute", "%{count} minutes", minutes) % { count: minutes }
        end
        if secs > 0 || minutes == 0
          parts << np_("EAPI_TaskTimer", "%{count} second", "%{count} seconds", secs) % { count: secs }
        end
        parts.join(" ")
      end

      def status_text
        name = nil
        left = nil
        paused = false
        on_break = false
        @mutex.synchronize do
          return p_("EAPI_TaskTimer", "No focus timer is running") if @state == nil
          name = @state[:task_name]
          left = remaining_unlocked
          paused = @state[:paused_remaining] != nil
          on_break = @state[:phase] == :break
        end
        return p_("EAPI_TaskTimer", "%{task}: focus time is up") % { task: name } if left <= 0 && !on_break
        if on_break
          if paused
            p_("EAPI_TaskTimer", "%{task}: break paused, %{time} left") % { task: name, time: duration_text(left) }
          else
            p_("EAPI_TaskTimer", "%{task}: break, %{time} left") % { task: name, time: duration_text(left) }
          end
        elsif paused
          p_("EAPI_TaskTimer", "%{task}: paused, %{time} left") % { task: name, time: duration_text(left) }
        else
          p_("EAPI_TaskTimer", "%{task}: %{time} left") % { task: name, time: duration_text(left) }
        end
      end

      private

      def alert_volume
        EltenAPI::UI.notifications_muted? ? DO_NOT_DISTURB_VOLUME : 100
      end

      def start_phase_unlocked(phase, minutes)
        @state[:phase] = phase
        @state[:ends_at] = monotonic_time + minutes.to_i * 60
        @state[:paused_remaining] = nil
        @state[:prompt] = nil
      end

      def announce_next_session(name, minutes, session)
        play_sound("clock", volume: alert_volume)
        alert(p_("EAPI_TaskTimer", "Break is over. Focus session %{session} started: %{task}, %{time}") %
              { session: session, task: name, time: duration_text(minutes * 60) }, false)
      end

      def handle_prompt(info)
        choices = []
        choices << [:complete, p_("EAPI_TaskTimer", "Mark as completed")] unless info[:has_goals]
        EXTEND_CHOICES.each do |minutes|
          choices << [minutes, p_("EAPI_TaskTimer", "Extend by %{time}") % { time: duration_text(minutes * 60) }]
        end
        choices << [:break, p_("EAPI_TaskTimer", "Take a %{time} break, then start another session") %
                            { time: duration_text(BREAK_MINUTES * 60) }]
        choices << [:finish, p_("EAPI_TaskTimer", "Finish without completing")]
        header = p_("EAPI_TaskTimer", "%{task}: time is up") % { task: info[:task_name] }

        loop do
          index = ask_with_alarm(header, choices.map(&:last))
          if index == nil
            postpone_prompt(info[:task_id])
            alert(p_("EAPI_TaskTimer", "You can decide later from the focus timer in the task menu"))
            return
          end
          return unless current_task?(info[:task_id])
          choice = choices[index][0]
          case choice
          when :complete
            return if try_complete_task(info)
          when Integer
            extend_focus(choice)
            alert(p_("EAPI_TaskTimer", "Focus time extended: %{time} left") % { time: duration_text(choice * 60) })
            return
          when :break
            start_break
            alert(p_("EAPI_TaskTimer", "Break started: %{time}. The next focus session will start after it") %
                  { time: duration_text(BREAK_MINUTES * 60) })
            return
          when :finish
            stop
            alert(p_("EAPI_TaskTimer", "The focus timer has been stopped"))
            return
          end
        end
      end

      def ask_with_alarm(header, labels)
        dialog_open
        list = EltenAPI::Controls::ListBox.new(labels, header: header)
        list.focus
        alarm_sound_start(volume: alert_volume)
        ringing = true
        repeat_at = monotonic_time + PROMPT_REPEAT_SECONDS
        begin
          loop do
            loop_update
            if ringing
              if key_any_pressed?
                alarm_sound_stop
                ringing = false
              elsif monotonic_time >= repeat_at
                speak(header)
                repeat_at = monotonic_time + PROMPT_REPEAT_SECONDS
              end
            end
            list.update
            return list.index if key_pressed?(:key_enter)
            return nil if key_pressed?(:key_escape)
          end
        ensure
          alarm_sound_stop
          dialog_close
          loop_update
        end
      end

      def postpone_prompt(task_id)
        @mutex.synchronize do
          @state[:prompt] = :postponed if @state != nil && @state[:task_id] == task_id && @state[:prompt] == :shown
        end
      end

      def current_task?(task_id)
        @mutex.synchronize { @state != nil && @state[:task_id] == task_id }
      end

      def try_complete_task(info)
        performer = info[:performer].to_s
        if !performer.empty? && performer.casecmp(Session.name.to_s) != 0
          question = p_("EAPI_TaskTimer", "This task is assigned to %{user}. Do you want to mark it as completed anyway?") %
                     { user: performer }
          return false unless confirm(question)
        end
        EltenLink::Tasks.complete(EltenLink::Client.new, info[:task_id])
        stop if current_task?(info[:task_id])
        alert(p_("EAPI_TaskTimer", "The task has been completed"))
        if $scene.is_a?(Scene_Tasks)
          $scene.request_reload(info[:task_parent] > 0 ? info[:task_parent] : info[:task_id])
        end
        true
      rescue EltenLink::Error => e
        Log.warning("Task timer completion failed: #{e.message}")
        alert(e.message.to_s.empty? ? _("Error") : e.message)
        false
      end

      def remaining_unlocked
        return nil if @state == nil
        return @state[:paused_remaining] if @state[:paused_remaining] != nil
        [@state[:ends_at] - monotonic_time, 0].max
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
