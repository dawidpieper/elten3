# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module TaskTimer
    PRESETS = [15, 25, 30, 45, 60].freeze
    MAX_MINUTES = 600
    DEFAULT_MINUTES = 25
    LAST_MINUTES_KEY = "TaskTimerMinutes"

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
            minutes: minutes,
            ends_at: monotonic_time + minutes * 60,
            paused_remaining: nil
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
        @mutex.synchronize do
          return p_("EAPI_TaskTimer", "No focus timer is running") if @state == nil
          name = @state[:task_name]
          left = remaining_unlocked
          paused = @state[:paused_remaining] != nil
        end
        return p_("EAPI_TaskTimer", "%{task}: focus time is up") % { task: name } if left <= 0
        if paused
          p_("EAPI_TaskTimer", "%{task}: paused, %{time} left") % { task: name, time: duration_text(left) }
        else
          p_("EAPI_TaskTimer", "%{task}: %{time} left") % { task: name, time: duration_text(left) }
        end
      end

      private

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
