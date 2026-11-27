# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  UserStatus = Struct.new(:text, :online, :sponsor, keyword_init: true)
  UserInfo = Struct.new(
    :name,
    :last_seen,
    :has_blog,
    :knows,
    :known_by,
    :version,
    :registered,
    :polls,
    :forum_posts,
    :in_contacts,
    :has_avatar,
    :banned,
    :honors,
    :callable,
    :feed_followed,
    :monitored,
    :archived,
    :blacklisted,
    keyword_init: true
  )

  module Users
    STATUS_TTL = 15
    STATUS_RETRY_DELAY = 3
    EMPTY_STATUS = UserStatus.new(text: "".freeze, online: false, sponsor: false).freeze
    StatusCache = Struct.new(:server, :auth, :index, :refresh_at, :refreshing, keyword_init: true)
    private_constant :STATUS_TTL, :STATUS_RETRY_DELAY, :EMPTY_STATUS, :StatusCache

    @status_mutex = Mutex.new
    @status_cache = nil

    class << self
      def status(client, name, online: true, sponsor: true)
        status_info(client, name, online: online, sponsor: sponsor).text
      end

      def status_info(client, name, online: true, sponsor: true)
        entry = (status_index(client)&.[](name) || EMPTY_STATUS).dup
        entry.text = entry.text.dup
        entry.online = online && entry.online
        entry.sponsor = sponsor && entry.sponsor
        entry
      end

      def set_status(client, text)
        client.api_data("PATCH", "/api/v1/users/me/status", { "text" => text })
        true
      end

      def info(client, user, stateonly: false)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}", { "stateonly" => bool_int(stateonly) })
        build_info(data)
      end

      def build_info(data)
        data = {} unless data.is_a?(Hash)
        UserInfo.new(
          name: data["name"].to_s,
          last_seen: time_value(data["last_seen"]),
          has_blog: bool_value(data["has_blog"]),
          knows: int_value(data["knows"]),
          known_by: int_value(data["known_by"]),
          version: data["version"].to_s,
          registered: time_value(data["registered"]),
          polls: int_value(data["polls"]),
          forum_posts: int_value(data["forum_posts"]),
          in_contacts: bool_value(data["in_contacts"]),
          has_avatar: bool_value(data["has_avatar"]),
          banned: bool_value(data["banned"]),
          honors: int_value(data["honors"]),
          callable: bool_value(data["callable"]),
          feed_followed: bool_value(data["feed_followed"]),
          monitored: bool_value(data["monitored"]),
          archived: bool_value(data["archived"]),
          blacklisted: bool_value(data["blacklisted"])
        )
      end

      def exists?(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/exists")
        bool_value(data["exists"])
      end

      def signature(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/signature")
        data["signature"].to_s
      end

      def set_signature(client, text)
        client.api_data("PATCH", "/api/v1/users/me/signature", { "text" => text })
        true
      end

      def banned?(client, user)
        payload = client.api_payload("GET", "/api/v1/users/#{user.to_s.urlenc}/ban")
        return false unless payload.is_a?(Hash) && Client.truthy?(payload["success"])
        bool_value((payload["data"] || {})["banned"])
      end

      def search(client, query)
        data = client.api_data("GET", "/api/v1/users/search", { "query" => query })
        data["users"].to_a.map(&:to_s)
      end

      def list(client)
        users = client.api_data("GET", "/api/v1/users")["users"].to_a.map(&:to_s)
        users.polsort!
        users
      end

      def online(client, period: nil)
        params = {}
        params["period"] = period if period != nil
        users = client.api_data("GET", "/api/v1/users/online", params)["users"].to_a.map(&:to_s)
        users.polsort! if period == nil
        users
      end

      def recently_registered(client, limit: nil)
        params = {}
        params["limit"] = limit if limit != nil
        users = client.api_data("GET", "/api/v1/users/recently-registered", params)["users"].to_a.map(&:to_s)
        limit == nil ? users : users[0...limit.to_i]
      end

      def recently_active(client)
        online(client, period: "86400")
      end

      private

      # Called under @status_mutex. Scene-specific clients use the same API session.
      def current_status_cache
        server = Client.api_base_url
        auth = Client.session_auth_params
        if @status_cache.nil? || @status_cache.server != server || @status_cache.auth != auth
          @status_cache = StatusCache.new(server: server.dup.freeze,
            auth: auth.transform_values { |value| value.dup.freeze }.freeze, refresh_at: 0)
        end
        @status_cache
      end

      def status_index(client)
        cache = @status_mutex.synchronize do
          current = current_status_cache
          # HTTP can pump the UI and re-enter this method while the three GETs run.
          return current.index if current.refreshing || Process.clock_gettime(Process::CLOCK_MONOTONIC) < current.refresh_at

          current.refreshing = true
          current
        end

        begin
          fresh = fetch_status_index(client, cache)
        rescue Error => error
          failure = error
        ensure
          active = @status_mutex.synchronize do
            cache.refreshing = false
            if current_status_cache.equal?(cache)
              cache.refresh_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (fresh ? STATUS_TTL : STATUS_RETRY_DELAY)
              cache.index = fresh if fresh
              true
            end
          end
        end
        return unless active
        raise failure if failure && cache.index.nil?

        cache.index
      end

      def fetch_status_index(client, cache)
        # Pin all three GETs even if the UI changes sessions while a request is sent.
        auth = cache.auth.empty? ? { "name" => "", "token" => "" } : cache.auth
        statuses = client.api_data("GET", "/api/v1/users/statuses", auth)["statuses"].to_a
        return unless @status_mutex.synchronize { current_status_cache.equal?(cache) }

        online = client.api_data("GET", "/api/v1/users/online", auth)["users"].to_a
        return unless @status_mutex.synchronize { current_status_cache.equal?(cache) }

        sponsors = client.api_data("GET", "/api/v1/admins", auth.merge("category" => "sponsors"))["users"].to_a
        index = {}
        statuses.each do |row|
          (index[row["name"].to_s] ||= EMPTY_STATUS.dup).text = row["status"].to_s
        end
        online.each do |user|
          name = user.to_s
          (index[name] ||= EMPTY_STATUS.dup).online = true unless name.empty?
        end
        sponsors.each { |user| (index[user.to_s] ||= EMPTY_STATUS.dup).sponsor = true }
        index.freeze
      end

      def bool_value(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end

      def int_value(value)
        return 0 if value == false || value == nil
        value.to_i
      end

      def time_value(value)
        timestamp = int_value(value)
        timestamp.positive? ? Time.at(timestamp) : nil
      end

      def bool_int(value)
        bool_value(value) ? 1 : 0
      end

    end
  end
end
