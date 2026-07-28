# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module ActivityReports
    INTERVAL = 3600
    REQUEST_TIMEOUT = 20.0
    SHUTDOWN_TIMEOUT = 10.0

    Job = Struct.new(:name, :token, :activity, :config, :mutex, :done, :success)

    class << self
      def track(scene_name, seconds)
        ensure_state
        now = Time.now.to_i
        should_flush = false
        @mutex.synchronize do
          key = current_session_key
          reset_session_locked(key, now) if @session_key != key
          if key == nil || !enabled?
            @activity.clear
            @last_flush_at = now
            return false
          end
          scene = scene_name.to_s
          if scene != ""
            @activity[scene] ||= 0.0
            @activity[scene] += seconds.to_f
          end
          should_flush = now - @last_flush_at >= INTERVAL
        end
        flush if should_flush
        true
      rescue Exception => e
        Log.error("Activity report tracking: #{e.class}: #{e.message}")
        false
      end

      def flush(wait: false, force: false, timeout: SHUTDOWN_TIMEOUT)
        ensure_state
        deadline = monotonic_time + timeout.to_f
        wait_until_idle(deadline) if wait
        job = nil
        @mutex.synchronize do
          now = Time.now.to_i
          key = current_session_key
          reset_session_locked(key, now) if @session_key != key
          return false if key == nil || !enabled?
          return false if @pending_count.to_i > 0
          activity = activity_snapshot_locked
          if activity.empty?
            @last_flush_at = now if force
            return false
          end
          @activity.clear
          @last_flush_at = now
          job = Job.new(key[0], key[1], activity, config_snapshot, Mutex.new, false, false)
          @pending_count += 1
        end
        start_worker
        @queue << job
        wait ? wait_job(job, deadline) : true
      rescue Exception => e
        Log.error("Activity report flush: #{e.class}: #{e.message}")
        false
      end

      def shutdown(timeout=SHUTDOWN_TIMEOUT)
        flush(wait: true, force: true, timeout: timeout)
        stop
      end

      def stop
        ensure_state
        @stopped = true
        @queue << :stop if @queue != nil
        @worker.join(0.5) if @worker != nil && @worker.alive?
      rescue Exception
      end

      def running?
        @worker != nil && @worker.alive?
      end

      private

      def ensure_state
        return if @state_ready == true
        @state_ready = true
        @mutex = Mutex.new
        @queue = Queue.new
        @activity = {}
        @pending_count = 0
        @session_key = nil
        @last_flush_at = Time.now.to_i
        @stopped = false
      end

      def start_worker
        ensure_state
        return if @worker != nil && @worker.alive?
        @stopped = false
        @worker = Thread.new { worker_loop }
        @worker.report_on_exception = false
      end

      def worker_loop
        loop do
          job = @queue.pop
          break if job == :stop || @stopped == true
          begin
            success = send_job(job)
            Log.debug("User activity report sent to server") if success
          rescue Exception => e
            Log.error("Activity report worker: #{e.class}: #{e.message}")
            success = false
          ensure
            complete_job(job, success) if job.is_a?(Job)
          end
        end
      end

      def send_job(job)
        EltenLink::Activities.register(
          elten_link,
          name: job.name,
          token: job.token,
          activity: job.activity,
          config: job.config,
          timeout: REQUEST_TIMEOUT
        )
      rescue Exception => e
        Log.error("Activity report request: #{e.class}: #{e.message}")
        false
      end

      def elten_link
        @elten_link ||= EltenLink::Client.new
      end

      def complete_job(job, success)
        job.mutex.synchronize do
          job.success = success == true
          job.done = true
        end
        @mutex.synchronize do
          @pending_count -= 1 if @pending_count.to_i > 0
        end
      end

      def wait_job(job, deadline)
        loop do
          job.mutex.synchronize do
            return job.success if job.done == true
          end
          return false if monotonic_time >= deadline
          sleep 0.05
        end
      end

      def wait_until_idle(deadline)
        loop do
          @mutex.synchronize do
            return true if @pending_count.to_i <= 0
          end
          return false if monotonic_time >= deadline
          sleep 0.05
        end
      end

      def current_session_key
        name = Session.name
        token = Session.token
        return nil if name == nil || name == "" || name == "guest" || token == nil || token == ""
        [name.to_s, token.to_s]
      rescue Exception
        nil
      end

      def enabled?
        Configuration.registeractivity == true
      rescue Exception
        false
      end

      def reset_session_locked(key, now)
        @session_key = key
        @activity.clear
        @last_flush_at = now
      end

      def activity_snapshot_locked
        report = {}
        @activity.each do |key, value|
          amount = value.to_f.round
          report[key.to_s] = amount if amount > 0
        end
        report
      end

      def config_snapshot
        Configuration.to_h.dup
      rescue Exception
        {}
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue Exception
        Time.now.to_f
      end
    end
  end
end
