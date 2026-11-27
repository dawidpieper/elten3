# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module TaskTimer
    PRESETS = [15, 25, 30, 45, 60].freeze
    MAX_MINUTES = 600
    DEFAULT_MINUTES = 25
    LAST_MINUTES_KEY = "TaskTimerMinutes"
    BREAK_MINUTES = 5

    @mutex = Mutex.new
    @state = nil

    class << self
      def start(task, minutes)
        minutes = minutes.to_i
        raise ArgumentError, "Invalid focus time: #{minutes}" if minutes < 1 || minutes > MAX_MINUTES

        @mutex.synchronize do
          @state = {
            account: session_key,
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
        @mutex.synchronize { @state != nil && @state[:task_id] == task.id && same_session_unlocked? }
      end

      # Whether the timer was started in the session that is signed in now.
      # Server actions for the timer's task must only use that session.
      def same_session?
        @mutex.synchronize { same_session_unlocked? }
      end

      def current_task?(task_id)
        @mutex.synchronize { @state != nil && @state[:task_id] == task_id }
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

      # Advances the timer. When a break ends, the next focus session starts
      # and its details are returned so that the caller can announce it.
      # When a focus session ends, the prompt becomes pending.
      def update
        @mutex.synchronize do
          return nil if @state == nil || @state[:paused_remaining] != nil || remaining_unlocked > 0
          if @state[:phase] == :break
            @state[:session] += 1
            start_phase_unlocked(:focus, @state[:minutes])
            return { task_name: @state[:task_name], minutes: @state[:minutes], session: @state[:session] }
          end
          @state[:prompt] = :pending if @state[:prompt] == nil
          nil
        end
      end

      def prompt_pending?
        @mutex.synchronize { @state != nil && @state[:prompt] == :pending }
      end

      # Marks the end-of-session prompt as shown and returns a snapshot of the
      # timer for it, or nil if no focus session is waiting for a decision.
      def claim_prompt
        @mutex.synchronize do
          return nil if @state == nil || @state[:phase] != :focus || @state[:prompt] == :shown
          return nil if @state[:paused_remaining] != nil || remaining_unlocked > 0
          @state[:prompt] = :shown
          @state.dup
        end
      end

      # Keeps the decision for later, after the prompt was closed without one.
      def postpone_prompt(task_id)
        @mutex.synchronize do
          @state[:prompt] = :postponed if @state != nil && @state[:task_id] == task_id && @state[:prompt] == :shown
        end
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
        return p_("EAPI_TaskTimer", "Focus time is up, %{task}") % { task: name } if left <= 0 && !on_break
        if on_break
          if paused
            p_("EAPI_TaskTimer", "Break paused, %{time} left, %{task}") % { task: name, time: duration_text(left) }
          else
            p_("EAPI_TaskTimer", "Break, %{time} left, %{task}") % { task: name, time: duration_text(left) }
          end
        elsif paused
          p_("EAPI_TaskTimer", "Paused, %{time} left, %{task}") % { task: name, time: duration_text(left) }
        else
          p_("EAPI_TaskTimer", "%{time} left, %{task}") % { task: name, time: duration_text(left) }
        end
      end

      private

      def start_phase_unlocked(phase, minutes)
        @state[:phase] = phase
        @state[:ends_at] = monotonic_time + minutes.to_i * 60
        @state[:paused_remaining] = nil
        @state[:prompt] = nil
      end

      def session_key
        return nil unless Session.logged?
        [Session.name.to_s, Session.token.to_s]
      rescue Exception
        nil
      end

      def same_session_unlocked?
        key = session_key
        @state != nil && key != nil && @state[:account] == key
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
