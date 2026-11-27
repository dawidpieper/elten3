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
    @status_time = 0
    @status_users = []
    @status_texts = []
    @online = []
    @sponsors = []

    class << self
      def status(client, name, online: true, sponsor: true)
        status_info(client, name, online: online, sponsor: sponsor).text
      end

      def status_info(client, name, online: true, sponsor: true)
        refresh_status_cache(client) if Time.now.to_i - 15 > @status_time
        return UserStatus.new(text: "", online: false, sponsor: false) if @status_users == nil || @online == nil
        text = ""
        @status_users.each_with_index do |user, index|
          text = @status_texts[index] if name == user
        end
        UserStatus.new(
          text: text,
          online: online && @online.include?(name),
          sponsor: sponsor && @sponsors.include?(name)
        )
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

      def refresh_status_cache(client)
        @status_time = Time.now.to_i
        statuses = client.api_data("GET", "/api/v1/users/statuses")["statuses"].to_a
        online = client.api_data("GET", "/api/v1/users/online")["users"].to_a
        sponsors = client.api_data("GET", "/api/v1/admins", { "category" => "sponsors" })["users"].to_a

        @online = online.map(&:to_s).select { |line| line.size > 0 }
        @sponsors = sponsors.map(&:to_s)
        @status_users = []
        @status_texts = []
        statuses.each_with_index do |row, index|
          @status_users[index] = row["name"].to_s
          @status_texts[index] = row["status"].to_s
        end
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
