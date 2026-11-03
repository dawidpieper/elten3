# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "securerandom"

module Programs
  class NotificationLifecycle
    attr_reader :interval, :expires_after_receipt, :callback

    def initialize(interval: 900, expires_after_receipt: nil, &callback)
      @interval = Float(interval)
      raise ArgumentError, "Notification lifecycle interval must be positive" if !@interval.finite? || @interval <= 0
      unless expires_after_receipt == nil || (expires_after_receipt.is_a?(Integer) && expires_after_receipt.between?(0, 1_209_600))
        raise ArgumentError, "Notification receipt expiry must be between 0 and 1209600 seconds"
      end
      @expires_after_receipt = expires_after_receipt
      @callback = callback
      freeze
    end
  end

  class LocalNotification
    attr_reader :id, :program, :runtime, :created_at, :type, :metadata, :presentation, :lifecycle_definition

    def initialize(program, runtime, body, title: nil, sound: "notification", action: nil, metadata: {},
      type: "", expires_in: 0, lifecycle: nil, &block)
      raise ArgumentError, "Specify either action or a block" if action != nil && block != nil
      unless lifecycle == nil || lifecycle.is_a?(NotificationLifecycle)
        raise ArgumentError, "Lifecycle must be a NotificationLifecycle or nil"
      end
      duration = Float(expires_in)
      raise ArgumentError, "Notification expiry must be finite and non-negative" if !duration.finite? || duration < 0
      @id = "local:#{SecureRandom.uuid}".freeze
      @program, @runtime = program, runtime
      @created_at = Time.now.to_i
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @expires_at = duration > 0 ? @started_at + duration : nil
      @type = type.to_s.dup.freeze
      @presentation = NotificationPresentation.new(title: title == nil ? program.name : title,
        body: body, sound: sound, action: action || block, metadata: metadata)
      @metadata = @presentation.metadata
      @lifecycle_definition = lifecycle
      @revoked = false
      limit_lifetime(lifecycle.expires_after_receipt) if lifecycle != nil
    end

    def local?
      true
    end

    def revoked?
      @revoked
    end

    def active?
      LocalNotifications.include?(self) && !revoked?
    end

    def revoke
      LocalNotifications.revoke(self)
    end

    def lifecycle(interval: 900, expires_after_receipt: nil, &block)
      NotificationLifecycle.new(interval: interval, expires_after_receipt: expires_after_receipt, &block)
    end

    private

    def expired?(now)
      @expires_at != nil && now >= @expires_at
    end

    def limit_lifetime(seconds)
      return unless seconds != nil && seconds > 0
      deadline = @started_at + seconds
      @expires_at = @expires_at == nil ? deadline : [@expires_at, deadline].min
    end

    def mark_revoked
      @revoked = true
    end
  end

  module LocalNotifications
    @mutex = Mutex.new
    @notifications = {}
    @pending = []
    @session_key = nil
    @changed = false

    class << self
      def create(program, body, **options, &block)
        runtime = Programs.runtime_for(program)
        unless runtime != nil && Programs.runtime_registered?(runtime)
          raise ProgramError, "Local notifications require a loaded application"
        end
        scope = session_key
        notification = LocalNotification.new(program, runtime, body, **options, &block)
        synchronize do
          raise ProgramError, "The user session has changed" unless @session_key == scope
          raise ProgramError, "The application has been unloaded" unless Programs.runtime_registered?(runtime)
          @notifications[notification.id] = notification
          @pending << notification.id
          @changed = true
        end
        notification
      end

      def list(include_revoked: false)
        synchronize { @notifications.values.select { |notification| include_revoked || !notification.revoked? } }
      end

      def include?(notification)
        synchronize { @notifications[notification.id].equal?(notification) }
      end

      def revoke(notification)
        synchronize do
          next false unless @notifications[notification.id].equal?(notification)
          next true if notification.revoked?
          notification.__send__(:mark_revoked)
          @pending.delete(notification.id)
          @changed = true
          true
        end
      end

      def limit_lifetime(notification, seconds)
        synchronize do
          next unless @notifications[notification.id].equal?(notification)
          notification.__send__(:limit_lifetime, seconds)
        end
      end

      def drain(limit: 50)
        synchronize do
          pending = @pending.shift(limit).filter_map { |id| @notifications[id] }
          changed = @changed
          @changed = false
          [pending, changed]
        end
      end

      private

      def session_key
        Session.logged? ? [Session.name.to_s, Session.token.to_s] : nil
      end

      def synchronize
        @mutex.synchronize do
          scope = session_key
          if @session_key != scope
            @changed = true unless @notifications.empty?
            @notifications.clear
            @pending.clear
            @session_key = scope
          end
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          runtimes = {}
          @notifications.delete_if do |_id, notification|
            runtime = notification.runtime
            runtimes[runtime] = Programs.runtime_registered?(runtime) unless runtimes.key?(runtime)
            remove = !runtimes[runtime] || notification.__send__(:expired?, now)
            @changed = true if remove
            remove
          end
          history = @notifications.values.select(&:revoked?)
          history[0, [history.size - NotificationGroups::NOTIFICATION_HISTORY_LIMIT, 0].max].each do |notification|
            @notifications.delete(notification.id)
            @changed = true
          end
          @pending.select! { |id| @notifications.key?(id) }
          yield
        end
      end
    end
  end

  module NotificationLifecycles
    Entry = Struct.new(:program, :runtime, :notification, :definition, :task, :expiry_pending, :check_at, :retry_at, :checking)
    private_constant :Entry

    class << self
      def tick
        return if @ticking
        @ticking = true
        begin
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          auth = Session.logged? ? EltenLink::Client.session_auth_params : {}
          if @auth != auth
            (@entries || {}).each_value { |entry| close_entry(entry) }
            @entries = {}
            @auth = auth.transform_values { |value| value.to_s.dup.freeze }.freeze
            @next_tick = 0
          end
          return if now < @next_tick.to_f
          @next_tick = now + 1.0

          programs = Programs.notification_programs.to_h { |program| [program.server_app_uuid.to_s.downcase, program] }
          notifications = auth.empty? ? {} : EltenAPI::NotificationService.active_notifications.to_h { |notification| [notification.id, notification] }
          LocalNotifications.list.each { |notification| notifications[notification.id] = notification }
          @entries.delete_if do |id, entry|
            current = notifications[id]
            program = current.is_a?(LocalNotification) ? current.program : programs[current&.app_uuid.to_s.downcase]
            removed = current == nil || !program.equal?(entry.program) ||
              !Programs.runtime_for(entry.program).equal?(entry.runtime) || !Programs.runtime_registered?(entry.runtime)
            close_entry(entry) if removed
            removed
          end
          notifications.each do |id, value|
            next if @entries.key?(id)
            local = value.is_a?(LocalNotification)
            program = local ? value.program : programs[value.app_uuid.downcase]
            next if program == nil
            runtime = Programs.runtime_for(program)
            next if runtime == nil || !Programs.runtime_registered?(runtime)
            notification = local ? value : Programs.app_notification_from(value)
            definition = local ? value.lifecycle_definition : nil
            definition ||= declaration(program, runtime, notification)
            LocalNotifications.limit_lifetime(notification, definition.expires_after_receipt) if local && definition != nil
            @entries[id] = Entry.new(program, runtime, notification, definition, nil,
              !local && definition != nil && definition.expires_after_receipt.to_i > 0,
              now + (definition&.interval || 900), now, false)
          end
          @entries.each_value do |entry|
            next if entry.definition == nil
            collect(entry, now) if entry.task != nil && entry.task.done?
            next if entry.definition == nil || entry.task != nil
            check = entry.definition.callback != nil && now >= entry.check_at
            expiry = entry.expiry_pending && now >= entry.retry_at
            start(entry, check, expiry) if check || expiry
          end
        rescue Exception => error
          Log.error("Program notification lifecycle failed: #{error.class}: #{error.message}")
        ensure
          @ticking = false
        end
      end

      private

      def declaration(program, runtime, notification)
        definition = Programs.with_runtime(runtime) { program.notification_lifecycle(notification) }
        unless definition == nil || definition.is_a?(NotificationLifecycle)
          raise ProgramError, "Notification lifecycle must be a NotificationLifecycle or nil"
        end
        definition
      rescue Exception => error
        Log.error("Program notification lifecycle declaration failed for #{program}: #{error.class}: #{error.message}")
        nil
      end

      def start(entry, check, expiry)
        auth = @auth
        entry.checking = check
        entry.task = EltenAPI::Tasks.start(owner: entry.runtime) do |token|
          result = { notification: nil, revoked: false, expiry_set: false }
          next result unless current?(entry, auth, token)
          if entry.notification.local?
            result[:revoked] = entry.definition.callback.call(entry.notification) == false if check
            next result
          end
          headers = { "X-Elten-Name" => auth.fetch("name"), "X-Elten-Token" => auth.fetch("token") }
          client = EltenLink.client(entry.program)
          if expiry
            result[:notification] = EltenLink::Apps.notification_lifecycle(client,
              appid: entry.notification.app_uuid, id: entry.notification.id,
              expires_after_receipt: entry.definition.expires_after_receipt, headers: headers, cancellation_token: token)
            result[:expiry_set] = true
          end
          if check && current?(entry, auth, token)
            valid = entry.definition.callback.call(entry.notification)
            if valid == false && current?(entry, auth, token)
              EltenLink::Notifications.revoke(client, entry.notification.id, headers: headers, cancellation_token: token)
              result[:revoked] = true
            end
          end
          result
        end
      rescue EltenAPI::Tasks::Busy
        nil
      end

      def collect(entry, now)
        outcome = entry.task.take
        entry.task.close
        entry.task = nil
        entry.check_at = now + entry.definition.interval if entry.checking
        entry.retry_at = now + 60
        return if outcome == nil
        if outcome.error
          if !entry.notification.local? && outcome.error.respond_to?(:code) && outcome.error.code == "notifications.not_found"
            EltenAPI::NotificationService.revoke_active_notifications([entry.notification.id])
            entry.definition = nil
          else
            Log.error("Program notification lifecycle check failed for #{entry.program}: #{outcome.error.class}: #{outcome.error.message}")
          end
          return
        end
        result = outcome.value
        return unless result.is_a?(Hash)
        entry.expiry_pending = false if result[:expiry_set]
        EltenAPI::NotificationService.update_active_notification(result[:notification]) if result[:notification]
        if result[:revoked]
          if entry.notification.local?
            entry.notification.revoke
          else
            EltenAPI::NotificationService.revoke_active_notifications([entry.notification.id])
          end
          entry.definition = nil
        end
      end

      def current?(entry, auth, token)
        return false if token.cancelled? || !Programs.runtime_registered?(entry.runtime)
        return entry.notification.active? if entry.notification.local?

        Session.logged? && EltenLink::Client.session_auth_params == auth &&
          EltenAPI::NotificationService.active_notifications.any? { |notification| notification.id == entry.notification.id }
      end

      def close_entry(entry)
        return if entry.task == nil
        entry.task.cancel
        entry.task.close
      end
    end
  end
end
