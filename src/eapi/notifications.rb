# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module NotificationService
    class << self
      include EltenAPI
      MAX_INFLIGHT_REQUESTS = 4
      REQUEST_STALE_AFTER = 45.0
      NOTIFICATION_QUERY_OVERLAP = 86_400
      NOTIFICATION_DEDUP_LIMIT = 8_192
      VIRTUAL_UPDATE_CHECK_INTERVAL = 600.0
      INITIAL_RUNTIME_STATE_TIMEOUT = 5.0

      def start
        ensure_state
        return true if @thread != nil && @thread.alive?
        @stopped = false
        @thread = Thread.new { worker_loop }
        @thread.report_on_exception = false
        true
      end

      def stop
        ensure_state
        @stopped = true
      end

      def running?
        @thread != nil && @thread.alive? && @stopped != true
      end

      def reset_feeds
        ensure_state
        @feed_request_pending = false
        @ag_feed = 0
        @ag_feedtime = 0
        @feedstime = 0
        @notificationtime = 0
        @lastfeeds = nil
        $feeds = {}
      end

      def drain_events(limit=50)
        ensure_state
        start if !running?
        return [] if @events.empty?
        events = []
        while events.size < limit && !@events.empty?
          begin
            events << @events.pop(true)
          rescue ThreadError
            break
          end
        end
        events
      end

      def server_time
        ensure_state
        @wnlasttime
      end

      def active_notifications
        ensure_state
        key = session_key
        @active_notifications_mutex.synchronize do
          return [] if key == nil || @session_key != key

          @active_notifications.dup
        end
      rescue Exception
        []
      end

      def synchronize_active_notifications(notifications)
        ensure_state
        values = normalize_active_notifications(notifications)
        changed = false
        @active_notifications_mutex.synchronize do
          return false if @session_key != session_key

          changed = active_notification_signature(@active_notifications) != active_notification_signature(values)
          @active_notifications = values
          @active_notifications_request_id = @request_serial.to_i + 1
        end
        enqueue_event("func" => "notifications") if changed
        true
      end

      def revoke_active_notifications(ids=nil)
        ensure_state
        values = ids == nil ? nil : Array(ids).flatten.map(&:to_i).select(&:positive?).uniq
        changed = false
        @active_notifications_mutex.synchronize do
          return false if @session_key != session_key

          previous_size = @active_notifications.size
          if values == nil
            @active_notifications = []
          elsif !values.empty?
            @active_notifications = @active_notifications.reject { |notification| values.include?(notification.id.to_i) }
          end
          changed = previous_size != @active_notifications.size
          @active_notifications_hash = ""
          @active_notifications_request_id = @request_serial.to_i + 1
          @next_request_at = monotonic_time
        end
        enqueue_event("func" => "notifications") if changed
        true
      end

      def refresh_active_notifications
        ensure_state
        @active_notifications_mutex.synchronize do
          return false if @session_key != session_key

          @active_notifications_hash = ""
          @active_notifications_request_id = @request_serial.to_i + 1
          @next_request_at = monotonic_time
        end
        true
      end

      def synchronize_runtime_state(timeout=INITIAL_RUNTIME_STATE_TIMEOUT)
        ensure_state
        key = session_key
        return false if key == nil

        ticket = queue_runtime_state_refresh(key)
        start
        deadline = monotonic_time + [timeout.to_f, 0.0].max
        loop do
          return true if runtime_state_refresh_completed?(key, ticket)
          if monotonic_time >= deadline
            Log.warning("Initial runtime state synchronization timed out")
            return false
          end
          loop_update(false)
        end
      rescue StandardError => e
        Log.warning("Initial runtime state synchronization failed: #{e.class}: #{e.message}")
        false
      end

      private

      def ensure_state
        return if @state_initialized == true
        @state_initialized = true
        @events = Queue.new
        @responses = Queue.new
        @background_responses = Queue.new
        @notification_ids = {}
        @active_notifications_mutex = Mutex.new
        @runtime_state_mutex = Mutex.new
        @active_notifications = []
        @active_notifications_hash = ""
        @active_notifications_request_id = 0
        @runtime_state_refresh_serial = 0
        @pending_runtime_state_refresh = nil
        @completed_runtime_state_key = nil
        @completed_runtime_state_refresh = 0
        @sigids = []
        @request_serial = 0
        @inflight_requests = {}
        @feed_request_pending = false
        @virtual_update_request_pending = false
        @next_virtual_update_check_at = 0.0
        @feedstime = 0
        @notificationtime = 0
        $feeds = {}
        @next_request_at = monotonic_time
        @stopped = false
      end

      def worker_loop
        loop do
          break if @stopped == true
          begin
            key = session_key
            if key == nil
              reset_session(nil)
              clear_responses
              clear_background_responses
              @inflight_requests.clear
              @next_request_at = monotonic_time + 1.0
            else
              reset_session(key) if @session_key != key
              now = monotonic_time
              drain_responses
              drain_background_responses
              clear_stale_requests(now)
              @feed_request_pending = false if @feed_request_pending == true && now - (@feed_request_started_at || 0) > 30
              @virtual_update_request_pending = false if @virtual_update_request_pending == true && now - (@virtual_update_request_started_at || 0) > REQUEST_STALE_AFTER
              refresh_ticket = pending_runtime_state_refresh(key)
              if refresh_ticket != nil && @inflight_requests.size < MAX_INFLIGHT_REQUESTS
                request_status(key, refresh_ticket)
                consume_runtime_state_refresh(key, refresh_ticket)
              elsif now >= (@next_request_at || 0) && @inflight_requests.size < MAX_INFLIGHT_REQUESTS
                request_status(key)
              end
              if now >= (@next_virtual_update_check_at || 0) && @virtual_update_request_pending != true
                if launched_by_launcher?
                  request_virtual_updates(key, now)
                else
                  @next_virtual_update_check_at = now + VIRTUAL_UPDATE_CHECK_INTERVAL
                end
              end
            end
          rescue Exception
            Log.error("Notification worker: #{$!.class}: #{$!.message}")
            @next_request_at = monotonic_time + 1.0
          end
          sleep 0.1
        end
      end

      def session_key
        return nil unless Session.logged?
        name = Session.name
        token = Session.token
        [name.to_s, token.to_s]
      rescue Exception
        nil
      end

      def reset_session(key)
        return if @session_key == key
        clear_events
        clear_responses
        clear_background_responses
        enqueue_event("func" => "call_stop", "call_id" => @call_id, "caller" => @call_caller) if @ringingplaying == true || @call_id != nil
        @session_key = key
        @wnlasttime = nil
        @ag_msg = nil
        @ag_feed = 0
        @ag_feedtime = 0
        @feedstime = 0
        @notificationtime = 0
        @lastfeeds = nil
        @sigids = []
        @premiumpackages = []
        @auctions = nil
        @call_id = nil
        @call_caller = nil
        @ringingplaying = false
        @inflight_requests.clear
        @feed_request_pending = false
        @virtual_update_request_pending = false
        @next_virtual_update_check_at = 0.0
        @notification_ids.clear
        @active_notifications_mutex.synchronize do
          @active_notifications = []
          @active_notifications_hash = ""
          @active_notifications_request_id = 0
        end
        @runtime_state_mutex.synchronize do
          @completed_runtime_state_key = nil
          @completed_runtime_state_refresh = 0
        end
        NotificationGroups.clear_virtual_notifications if defined?(NotificationGroups)
      end

      def queue_runtime_state_refresh(key)
        @runtime_state_mutex.synchronize do
          @runtime_state_refresh_serial += 1
          @pending_runtime_state_refresh = [key, @runtime_state_refresh_serial]
          @runtime_state_refresh_serial
        end
      end

      def pending_runtime_state_refresh(key)
        @runtime_state_mutex.synchronize do
          pending_key, ticket = @pending_runtime_state_refresh
          pending_key == key ? ticket : nil
        end
      end

      def consume_runtime_state_refresh(key, ticket)
        @runtime_state_mutex.synchronize do
          @pending_runtime_state_refresh = nil if @pending_runtime_state_refresh == [key, ticket]
        end
      end

      def complete_runtime_state_refresh(key, ticket)
        return if ticket == nil
        @runtime_state_mutex.synchronize do
          @completed_runtime_state_key = key
          @completed_runtime_state_refresh = [@completed_runtime_state_refresh.to_i, ticket.to_i].max
        end
      end

      def runtime_state_refresh_completed?(key, ticket)
        @runtime_state_mutex.synchronize do
          @completed_runtime_state_key == key && @completed_runtime_state_refresh.to_i >= ticket.to_i
        end
      end

      def refresh_interval
        value = Configuration.sessiontime.to_i

        value = 1 if value < 1
        value = 15 if value > 15
        if @last_refresh_interval != value
          @last_refresh_interval = value
          Log.debug("Session refresh interval: #{value}s")
        end
        value
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue Exception
        Time.now.to_f
      end

      def request_status(key, refresh_ticket=nil)
        @request_serial += 1
        request_id = @request_serial
        started_at = monotonic_time
        base_lasttime = @wnlasttime
        calibrating = base_lasttime == nil
        @next_request_at = started_at + refresh_interval
        name, token = key
        shown = window_active?
        lasttime = notification_request_lasttime(base_lasttime, calibrating)
        @inflight_requests[request_id] = { "started_at" => started_at, "calibrating" => calibrating, "refresh_ticket" => refresh_ticket }
        params = notification_request_params(name, token, lasttime, shown)
        path = EltenLink::Client.append_query("/api/v1/system/realtime-state", params)
        elten_link.e_json_request("GET", path, {}, [key, request_id]) do |answer, request_data|
          request_key, returned_id = request_data
          @responses << [answer, request_key, returned_id]
        rescue Exception
          Log.error("Notification callback error: #{$!.class}: #{$!.message}")
        end
      rescue Exception
        @inflight_requests.delete(request_id)
        raise
      end

      def drain_responses(limit=20)
        count = 0
        while count < limit
          begin
            answer, key, request_id = @responses.pop(true)
          rescue ThreadError
            break
          end
          info = @inflight_requests.delete(request_id)
          calibrating = info.is_a?(Hash) && info["calibrating"] == true
          refresh_ticket = info.is_a?(Hash) ? info["refresh_ticket"] : nil
          handle_status_response(answer, key, calibrating, request_id, refresh_ticket)
          count += 1
        end
      end

      def handle_status_response(answer, key, calibrating=false, request_id=0, refresh_ticket=nil)
        return if key != @session_key
        return if !answer.is_a?(String)
        body = answer.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
        response = status_response_data(JSON.load(body))
        return unless response.is_a?(Hash)

        handle_auctions(response)
        if response["time"].is_a?(Integer)
          server_time = response["time"].to_i
          @wnlasttime = @wnlasttime == nil ? server_time : [@wnlasttime.to_i, server_time].max
        end
        handle_message_counter(response)
        handle_feed_counter(response, key)
        handle_active_notifications(response, request_id)
        handle_notification_counter(response, calibrating)
        handle_signals(response) if calibrating != true
        handle_premium_packages(response)
        handle_call(response, key)
        if calibrating == true
          prime_window_notifications(response)
        else
          handle_window_notifications(response)
        end
        complete_runtime_state_refresh(key, refresh_ticket)
      rescue JSON::ParserError
        Log.error("Notification JSON parse error")
      rescue Exception
        Log.error("Notification response error: #{$!.class}: #{$!.message}")
      end

      def handle_auctions(response)
        active = response["auctions"] == true
        return if @auctions == active
        @auctions = active
        enqueue_event("func" => "auctions", "auctions" => active)
      end

      def handle_message_counter(response)
        count = response["msg"].to_i
        @ag_msg ||= count
        return if @ag_msg >= count
        @ag_msg = count
        enqueue_event("func" => "msg", "msgs" => @ag_msg)
      end

      def handle_feed_counter(response, key)
        feed = response["feed"].to_i
        feedtime = response["feedtime"].to_i
        return if @feed_request_pending == true
        return if @lastfeeds != nil && @ag_feed == feed && @ag_feedtime >= feedtime

        fetch_feeds(key, feed: feed, feedtime: feedtime)
      end

      def handle_notification_counter(response, calibrating=false)
        notificationtime = response["notificationtime"].to_i
        return if notificationtime <= 0

        previous = @notificationtime.to_i
        @notificationtime = [previous, notificationtime].max
        return if calibrating == true || previous <= 0 || notificationtime <= previous

        enqueue_event("func" => "notifications", "notificationtime" => notificationtime)
      end

      def handle_active_notifications(response, request_id)
        rows = response["notifications_state"]
        return unless rows.is_a?(Array)

        values = normalize_active_notifications(rows.map { |row| EltenLink::Notifications.from_data(row) })
        changed = false
        @active_notifications_mutex.synchronize do
          return if request_id.to_i < @active_notifications_request_id.to_i

          changed = active_notification_signature(@active_notifications) != active_notification_signature(values)
          @active_notifications = values
          @active_notifications_hash = response["notifications_hash"].to_s
          @active_notifications_request_id = request_id.to_i
        end
        enqueue_event("func" => "notifications") if changed
      end

      def handle_signals(response)
        return if !response["signals"].is_a?(Array)
        response["signals"].each do |signal|
          id = signal["id"]
          next if @sigids.include?(id)
          @sigids << id
          @sigids.shift while @sigids.size > 1024
          enqueue_event(
            "func" => "sig",
            "appid" => signal["appid"],
            "time" => signal["time"],
            "packet" => signal["packet"],
            "sender" => signal["sender"],
            "id" => id
          )
        end
      end

      def handle_premium_packages(response)
        packages = response["premiumpackages"]
        return if !packages.is_a?(Array) || @premiumpackages == packages
        enqueue_event("func" => "notif", "sound" => "signal") if @premiumpackages.is_a?(Array) && @premiumpackages.size > 0
        @premiumpackages = packages
        enqueue_event("func" => "premiumpackages", "premiumpackages" => packages.join(","))
      end

      def handle_call(response, key)
        call = response["call"]
        if call.is_a?(Hash)
          return if call["id"] == @call_id
          @call_id = call["id"]
          @call_caller = call["caller"]
          @ringingplaying = true
          enqueue_event(
            "func" => "call_start",
            "call_id" => call["id"],
            "caller" => call["caller"],
            "channel" => call["channel"].to_i,
            "password" => call["channel_password"],
            "ringtone" => ringtone_for(call["caller"])
          )
        elsif @ringingplaying == true || @call_id != nil
          call_id = @call_id
          caller = @call_caller
          @ringingplaying = false
          @call_id = nil
          @call_caller = nil
          enqueue_event("func" => "call_stop", "call_id" => call_id, "caller" => caller)
        end
      end

      def handle_window_notifications(response)
        notifications = response["wn"]
        return if !notifications.is_a?(Array)
        now = monotonic_time
        @next_request_at = [@next_request_at || now, now + 0.5].min if notifications.size > 0
        queued = []
        notifications.each do |notification|
          id = notification["id"]
          queued << notification if remember_notification(id)
        end
        visible, invisible = queued.partition { |notification| !notification_invisible?(notification) }
        if visible.size > 10
          enqueue_event("func" => "notif", "sound" => "new")
        else
          visible.each do |notification|
            enqueue_event(
              "func" => "notif",
              "alert" => notification["alert"],
              "sound" => notification["sound"],
              "id" => notification["id"]
            )
          end
        end
        invisible.each do |notification|
          enqueue_event(
            "func" => "notif",
            "alert" => notification["alert"],
            "sound" => notification["sound"],
            "id" => notification["id"],
            "invisible" => true
          )
        end
      end

      def prime_window_notifications(response)
        notifications = response["wn"]
        return if !notifications.is_a?(Array)
        notifications.each do |notification|
          id = notification["id"]
          next if id == nil || id == ""
          remember_notification(id)
        end
      end

      def fetch_feeds(key, feed: nil, feedtime: nil)
        return if @feed_request_pending == true
        name, token = key
        @feed_request_pending = true
        @feed_request_started_at = monotonic_time
        params = {
          "name" => name,
          "token" => token,
          "time" => (@feedstime || 0),
          "limit" => 1500
        }
        path = EltenLink::Client.append_query("/api/v1/feeds/followed", params)
        request_data = { "session_key" => key, "feed" => feed.to_i, "feedtime" => feedtime.to_i }
        elten_link.e_json_request("GET", path, {}, request_data) do |answer, data|
          @background_responses << ["feeds", answer, data]
        rescue Exception
          Log.error("Notification feed callback error: #{$!.class}: #{$!.message}")
        end
      end

      def request_virtual_updates(key, now=monotonic_time)
        return if @virtual_update_request_pending == true

        @virtual_update_request_pending = true
        @virtual_update_request_started_at = now
        @next_virtual_update_check_at = now + VIRTUAL_UPDATE_CHECK_INTERVAL
        name, = key
        params = {
          "branch" => get_updatesbranch,
          "os" => platform_os,
          "current_build_id" => Elten.build_id.to_s,
          "name" => name,
          "apps" => NotificationGroups.installed_program_update_payload
        }
        elten_link.e_json_request("POST", "/api/v1/system/updates", params, { "session_key" => key }) do |answer, data|
          @background_responses << ["virtual_updates", answer, data]
        rescue Exception
          Log.error("Notification virtual update callback error: #{$!.class}: #{$!.message}")
        end
      rescue Exception
        @virtual_update_request_pending = false
        Log.warning("Notification virtual update request failed: #{$!.class}: #{$!.message}")
      end

      def handle_virtual_updates_response(answer, request_data)
        key = request_data.is_a?(Hash) ? request_data["session_key"] : request_data
        return if key != @session_key || !answer.is_a?(String)

        body = answer.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
        payload = JSON.load(body)
        return unless payload.is_a?(Hash) && payload["success"] == true

        response_data = payload["data"].is_a?(Hash) ? payload["data"] : {}
        NotificationGroups.refresh_virtual_notifications(system_updates_from_response(response_data))
      rescue JSON::ParserError
        Log.warning("Notification virtual update JSON parse error")
      rescue Exception
        Log.warning("Notification virtual update error: #{$!.class}: #{$!.message}")
      end

      def system_updates_from_response(data)
        client_data = data["client"].is_a?(Hash) ? data["client"] : {}
        app_updates = (data["apps"] || data["app_updates"]).to_a.map do |row|
          EltenLink::AppUpdateInfo.new(
            id: row["id"].to_s,
            path: row["path"].to_s,
            name: row["name"].to_s,
            version: row["version"].to_s,
            build_id: EltenLink::System.normalize_build_id(row["build_id"]),
            current_build_id: EltenLink::System.normalize_build_id(row["current_build_id"]),
            author: row["author"].to_s,
            size: row["size"].to_i,
            url: row["url"].to_s
          )
        end
        EltenLink::SystemUpdateInfo.new(
          client: EltenLink::ClientUpdateInfo.new(
            build_id: EltenLink::System.normalize_build_id(client_data["build_id"]),
            current_build_id: EltenLink::System.normalize_build_id(client_data["current_build_id"]),
            version_string: client_data["version_string"].to_s,
            update: EltenLink::Client.truthy?(client_data["update"])
          ),
          apps: app_updates
        )
      end
      def handle_feeds_response(answer, request_data)
        key = request_data.is_a?(Hash) ? request_data["session_key"] : request_data
        return if key != @session_key || !answer.is_a?(String)
        body = answer.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
        payload = JSON.load(body)
        return unless payload.is_a?(Hash) && payload["success"] == true

        response_data = payload["data"].is_a?(Hash) ? payload["data"] : {}
        rows = response_data["messages"].is_a?(Array) ? response_data["messages"] : []
        feeds = rows.each_with_object({}) do |row, result|
          feed = EltenLink::Feeds.message_from_row(row, feed_message_class)
          result[feed.id] = feed if feed.id > 0
        end
        current_feeds = @lastfeeds == nil ? feeds : @lastfeeds.dup
        changed = []
        played = false
        feeds.each do |id, current|
          previous = @lastfeeds == nil ? nil : @lastfeeds[id]
          next if previous != nil && previous.message == current.message && previous.responses == current.responses && previous.likes == current.likes && previous.liked == current.liked && previous.audio_url == current.audio_url
          if previous == nil && @lastfeeds != nil && current.message != "" && mention?(current.message)
            enqueue_event("func" => "notif", "sound" => "feed_mention") if $donotdisturb != true
          end
          if played == false && previous == nil && @lastfeeds != nil && current.message != ""
            played = true
            enqueue_event("func" => "notif", "sound" => "feed_update") if $donotdisturb != true && Configuration.disablefeednotifications != true
          end
          changed << current
          current_feeds[id] = current
        end
        @feedstime = [@feedstime.to_i, response_data["feedtime"].to_i, @ag_feedtime.to_i].max
        @ag_feed = request_data["feed"].to_i if request_data.is_a?(Hash)
        @ag_feedtime = [@ag_feedtime.to_i, request_data.is_a?(Hash) ? request_data["feedtime"].to_i : 0, @feedstime.to_i].max
        $feeds = current_feeds
        enqueue_event("func" => "feeds", "changed" => changed.map { |feed| feed.to_h }) if changed.size > 0
        @lastfeeds = current_feeds
      rescue Exception
        Log.error("Notification feed error: #{$!.class}: #{$!.message}")
      end

      def request_missed_call_status(key, call_id, caller)
        return if call_id == nil
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            active = EltenLink::Calls.active?(elten_link, call_id, absolute: true)
            @background_responses << ["missed_call", active, [key, caller]]
          rescue Exception
            Log.error("Missed call status request error: #{$!.class}: #{$!.message}")
          end
        end
      end

      def drain_background_responses(limit=10)
        count = 0
        while count < limit
          begin
            type, answer, data = @background_responses.pop(true)
          rescue ThreadError
            break
          end
          case type
          when "feeds"
            begin
              handle_feeds_response(answer, data)
            ensure
              @feed_request_pending = false
            end
          when "missed_call"
            handle_missed_call_response(answer, data)
          when "virtual_updates"
            begin
              handle_virtual_updates_response(answer, data)
            ensure
              @virtual_update_request_pending = false
            end
          end
          count += 1
        end
      end

      def handle_missed_call_response(answer, data)
        request_key, request_caller = data
        return if request_key != @session_key
        enqueue_event("func" => "missed_call", "caller" => request_caller) if answer == true
      rescue Exception
        Log.error("Missed call status error: #{$!.class}: #{$!.message}")
      end

      def remember_notification(id=nil)
        now = monotonic_time
        id = "nocat#{rand(10**16)}" if id == nil || id == ""
        id = id.to_s
        if @notification_ids.key?(id)
          @notification_ids[id] = now
          return false
        end
        @notification_ids[id] = now
        if @notification_ids.size > NOTIFICATION_DEDUP_LIMIT
          @notification_ids.sort_by { |_key, seen_at| seen_at }[0, @notification_ids.size - NOTIFICATION_DEDUP_LIMIT].each { |key, _seen_at| @notification_ids.delete(key) }
        end
        true
      end

      def notification_invisible?(notification)
        value = notification["invisible"]
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end

      def enqueue_event(event)
        @events << event
      end

      def clear_events
        loop do
          @events.pop(true)
        rescue ThreadError
          break
        end
      end

      def clear_responses
        loop do
          @responses.pop(true)
        rescue ThreadError
          break
        end
      end

      def clear_background_responses
        loop do
          @background_responses.pop(true)
        rescue ThreadError
          break
        end
      end

      def clear_stale_requests(now=monotonic_time)
        before = @inflight_requests.size
        @inflight_requests.delete_if do |_request_id, info|
          started_at = info.is_a?(Hash) ? info["started_at"] : info
          now - started_at > REQUEST_STALE_AFTER
        end
        Log.warning("Notification stale requests cleared: #{before - @inflight_requests.size}") if before > @inflight_requests.size
      end

      def feed_message_class
        return ::FeedMessage if defined?(::FeedMessage)
        return EltenAPI::Common::FeedMessage if defined?(EltenAPI::Common::FeedMessage)
        FeedMessage
      end

      def configuration_string(name, default="")
        return default if !Configuration.respond_to?(name)
        value = Configuration.__send__(name)
        value == nil ? default : value.to_s
      end

      def window_active?
        EltenWindow.active_or_child?
      rescue Exception
        false
      end

      def notification_request_params(name, token, lasttime, shown)
        params = {
          "name" => name,
          "token" => token,
          "lasttime" => lasttime,
          "language" => configuration_string(:language),
          "soundtheme" => configuration_string(:soundtheme),
          "notifications_hash" => active_notifications_hash
        }
        params["shown"] = 1 if shown == true
        params
      end

      def active_notifications_hash
        @active_notifications_mutex.synchronize { @active_notifications_hash.to_s }
      end

      def normalize_active_notifications(notifications)
        now = Time.now.to_i
        notifications.to_a.each_with_object({}) do |notification, result|
          next unless notification.is_a?(EltenLink::Notification)
          next if notification.id.to_i <= 0 || notification.revoked == true
          next if notification.expiration.to_i > 0 && notification.date.to_i + notification.expiration.to_i < now

          result[notification.id.to_i] = notification
        end.values.sort_by { |notification| [notification.date.to_i, notification.id.to_i] }
      end

      def active_notification_signature(notifications)
        notifications.to_a.map { |notification| [notification.id.to_i, notification.update_time.to_i] }
      end

      def notification_request_lasttime(base_lasttime, calibrating=false)
        return 0 if calibrating == true || base_lasttime == nil
        lasttime = base_lasttime.to_i - NOTIFICATION_QUERY_OVERLAP
        lasttime < 0 ? 0 : lasttime
      end

      def status_response_data(payload)
        return payload["data"] if payload.is_a?(Hash) && payload["success"] == true && payload["data"].is_a?(Hash)

        payload
      end

      def mention?(text)
        name = @session_key == nil ? nil : @session_key[0]
        return false if name == nil || name == ""
        (/\@#{Regexp.escape(name)}([^a-zA-Z0-9\.\-\_]|$)/i =~ text.to_s) != nil
      end

      def ringtone_for(caller)
        return "ringing" if !@premiumpackages.is_a?(Array) || !@premiumpackages.include?("audiophile")
        file = EltenPath.join(Dirs.eltendata, "ringtones.json")
        return "ringing" if !FileTest.exist?(file)
        json = JSON.load(IO.binread(file))
        candidate = json[caller]
        candidate != nil && FileTest.exist?(candidate) ? candidate : "ringing"
      rescue Exception
        "ringing"
      end
    end
  end
end
