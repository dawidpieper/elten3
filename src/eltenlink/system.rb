# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class ClientState
    attr_reader :raw

    def initialize(raw)
      @raw = raw
    end

    def [](index)
      @raw[index]
    end

    def error_code
      @raw[0].to_i
    end

    def messages
      @raw[6].to_i
    end

    def posts
      @raw[7].to_i
    end

    def blog_posts
      @raw[8].to_i
    end

    def blog_comments
      @raw[9].to_i
    end

    def forums
      @raw[10].to_i
    end

    def forum_posts
      @raw[11].to_i
    end

    def friends
      @raw[12].to_i
    end

    def birthdays
      @raw[13].to_i
    end

    def mentions
      @raw[14].to_i
    end

    def followed_blog_posts
      @raw[15].to_i
    end

    def blog_followers
      @raw[16].to_i
    end

    def blog_mentions
      @raw[17].to_i
    end

    def group_invitations
      @raw[18].to_i
    end

    def version_string
      @raw[2].to_s
    end
  end

  BuildInfo = Struct.new(:build_id, :version_string, keyword_init: true) do
    def to_i
      build_id.to_i
    end

    def present?
      build_id != nil
    end
  end

  ClientUpdateInfo = Struct.new(:build_id, :current_build_id, :version_string, :update, keyword_init: true) do
    def update?
      update == true
    end
  end

  AppUpdateInfo = Struct.new(:id, :path, :name, :version, :build_id, :current_build_id, :author, :size, :url, keyword_init: true)

  SystemUpdateInfo = Struct.new(:client, :apps, keyword_init: true) do
    def client_update?
      client != nil && client.update?
    end

    def app_updates?
      apps.to_a.size > 0
    end
  end

  module System
    class << self
      def connected?(client)
        ["/api/v1/system/time", "/api/v1/system/build-id"].any? do |path|
          payload = client.api_payload("GET", path)
          payload.is_a?(Hash) && Client.truthy?(payload["success"])
        end
      end

      def build_id(client, branch: nil, os: nil, current_build_id: nil)
        build_info(client, branch: branch, os: os, current_build_id: current_build_id).build_id
      end

      def build_info(client, branch: nil, os: nil, current_build_id: nil)
        params = {}
        params["branch"] = branch if branch != nil
        params["os"] = os if os != nil
        params["build_id"] = normalize_build_id(current_build_id) if normalize_build_id(current_build_id) != nil
        data = client.api_data("GET", "/api/v1/system/build-id", params)
        BuildInfo.new(build_id: normalize_build_id(data["build_id"]), version_string: data["version_string"].to_s)
      rescue EltenLink::Error => e
        Log.warning("Build ID check failed: #{e.code} #{e.message}")
        BuildInfo.new(build_id: nil, version_string: "")
      end

      def updates(client, branch: nil, os: nil, current_build_id: nil, apps: [])
        params = {}
        params["branch"] = branch if branch != nil
        params["os"] = os if os != nil
        params["current_build_id"] = normalize_build_id(current_build_id) if normalize_build_id(current_build_id) != nil
        session_params = Client.session_auth_params
        params["name"] = session_params["name"] if session_params["name"].to_s != ""
        params["apps"] = apps.to_a.map do |app|
          build_id = normalize_build_id(app.respond_to?(:build_id) ? app.build_id : app["build_id"])
          {
            "id" => app.respond_to?(:id) ? app.id.to_s : app["id"].to_s,
            "build_id" => build_id
          }
        end
        data = client.api_data("POST", "/api/v1/system/updates", params)
        client_data = data["client"] || {}
        app_updates = (data["apps"] || data["app_updates"]).to_a.map do |row|
          AppUpdateInfo.new(
            id: row["id"].to_s,
            path: row["path"].to_s,
            name: row["name"].to_s,
            version: row["version"].to_s,
            build_id: normalize_build_id(row["build_id"]),
            current_build_id: normalize_build_id(row["current_build_id"]),
            author: row["author"].to_s,
            size: row["size"].to_i,
            url: row["url"].to_s
          )
        end
        SystemUpdateInfo.new(
          client: ClientUpdateInfo.new(
            build_id: normalize_build_id(client_data["build_id"]),
            current_build_id: normalize_build_id(client_data["current_build_id"]),
            version_string: client_data["version_string"].to_s,
            update: Client.truthy?(client_data["update"])
          ),
          apps: app_updates
        )
      rescue EltenLink::Error => e
        Log.warning("Updates check failed: #{e.code} #{e.message}")
        SystemUpdateInfo.new(client: ClientUpdateInfo.new(build_id: nil, current_build_id: nil, version_string: "", update: false), apps: [])
      end

      def normalize_build_id(value)
        return nil if value == nil

        text = value.to_s.strip
        return nil if text == "" || text == "0"

        text
      end

      def installer_module(branch:, os:)
        params = {
          "branch" => branch.to_s,
          "os" => os.to_s
        }
        "api/v1/system/installer/download?" + params.map { |key, value| "#{query_escape(key)}=#{query_escape(value)}" }.join("&")
      end

      def installer_url(base_url = nil, branch:, os:)
        Client.absolute_api_url("/#{installer_module(branch: branch, os: os)}")
      end

      def extra_url(name)
        Client.absolute_api_url("/api/v1/system/extras/#{name.to_s.urlenc}/download")
      end

      def soundfont_url
        extra_url("soundfont.sf2")
      end

      def server_time(client)
        value = client.api_data("GET", "/api/v1/system/time")["time"].to_i
        value < 0 ? Time.now : Time.at(value)
      end

      def measure_realtime_state(client)
        measure_request(client, "/api/v1/system/realtime-state")
      end

      def measure_forum_structure(client)
        measure_request(client, "/api/v1/forum")
      end

      def measure_messages_conversations(client)
        measure_request(client, "/api/v1/messages", { "conversations" => 1 })
      end

      def measure_blog_list(client)
        measure_request(client, "/api/v1/blogs")
      end

      def logout_autologin(client, computer)
        client.api_data("DELETE", "/api/v1/session", { "computer" => computer })
        true
      end

      def logout_session(client)
        client.api_data("DELETE", "/api/v1/session", {})
        true
      end

      def bug_report(client, info)
        client.api_data("POST", "/api/v1/system/bug-reports", { "buginfo" => info })
        true
      end

      def client_state(client, branch: nil, os: nil)
        params = { "client" => "1" }
        params["branch"] = branch if branch != nil
        params["os"] = os if os != nil
        data = client.api_data("GET", "/api/v1/system/client-state", params)
        version = data["version"] || {}
        profile = data["profile"] || {}
        chat = data["chat"] || {}
        counts = data["counts"] || {}
        ClientState.new([
          "0\r\n",
          "#{data["time"].to_i}\r\n",
          "#{version["version_string"]}\r\n",
          "#{profile["fullname"]}\r\n",
          "#{profile["gender"].to_i}\r\n",
          "#{chat["last"]}\r\n",
          "#{counts["messages"].to_i}\r\n",
          "#{counts["followed_threads"].to_i}\r\n",
          "#{counts["followed_blogs"].to_i}\r\n",
          "#{counts["blog_comments"].to_i}\r\n",
          "#{counts["followed_forums"].to_i}\r\n",
          "#{counts["forum_posts"].to_i}\r\n",
          "#{counts["friends"].to_i}\r\n",
          "#{counts["birthdays"].to_i}\r\n",
          "#{counts["mentions"].to_i}\r\n",
          "#{counts["followed_blog_posts"].to_i}\r\n",
          "#{counts["blog_followers"].to_i}\r\n",
          "#{counts["blog_mentions"].to_i}\r\n",
          "#{counts["group_invitations"].to_i}\r\n"
        ])
      end

      private

      def measure_request(client, path, params = {})
        started = Time.now.to_f
        response = client.json("GET", path, params, timeout: 30)
        response.nil? ? 0 : Time.now.to_f - started
      end

      def query_escape(value)
        string = value.to_s.dup
        string.force_encoding(Encoding::UTF_8) if string.encoding == Encoding::ASCII_8BIT
        string = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        string.gsub(/([^ a-zA-Z0-9_.-]+)/) do |match|
          match.bytes.map { |byte| "%" + byte.to_s(16).rjust(2, "0").upcase }.join
        end.tr(" ", "+")
      end

    end
  end
end
