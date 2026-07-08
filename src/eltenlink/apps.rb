# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

require "json"

module EltenLink
  class AppPackage
    attr_accessor :id, :name, :size, :version, :build_id, :author, :path, :url
    attr_reader :realpath

    def initialize(path:, name:, version:, author:, size:, realpath: nil, url: "", build_id: nil, id: "")
      @id = id.to_s
      @path = path
      @name = name
      @version = version
      @build_id = Apps.normalize_build_id(build_id)
      @author = author
      @size = size.to_i
      @realpath = realpath
      @url = url.to_s
    end
  end

  module Apps
    class AppTable
      def initialize(client, app_uuid, table)
        @client = client
        @app_uuid = app_uuid.to_s
        @table = table.to_s
      end

      def select(where: nil, order: nil, limit: nil, offset: nil)
        params = Apps.stamp_params
        params["where"] = JSON.generate(where) if where != nil
        params["order"] = JSON.generate(order) if order != nil
        params["limit"] = limit if limit != nil
        params["offset"] = offset if offset != nil
        data = @client.api_data("GET", path, params)
        data["rows"].to_a
      end

      def insert(values)
        data = @client.api_data("POST", path, Apps.stamp_params.merge("values" => values))
        data["row"]
      end

      def upsert(values)
        data = @client.api_data("PUT", path, Apps.stamp_params.merge("values" => values))
        data["row"]
      end

      def update(id, values)
        data = @client.api_data("PATCH", "#{path}/#{id.to_i}", Apps.stamp_params.merge("values" => values))
        data["row"]
      end

      def delete(id)
        @client.api_data("DELETE", "#{path}/#{id.to_i}", Apps.stamp_params)
        true
      end

      private

      def path
        "/api/v1/apps/#{Apps.query_escape(@app_uuid)}/tables/#{Apps.query_escape(@table)}/rows"
      end
    end

    class << self
      def list(client, os: nil)
        prm = {}
        prm["os"] = os if os != nil
        data = client.api_data("GET", "/api/v1/apps", prm)
        data["apps"].to_a.map do |row|
          AppPackage.new(
            id: row["id"].to_s,
            path: row["path"].to_s,
            name: row["name"].to_s,
            version: row["version"].to_s,
            build_id: normalize_build_id(row["build_id"]),
            author: row["author"].to_s,
            size: row["size"].to_i,
            url: row["url"].to_s
          )
        end
      end

      def signal(client, appid:, user:, packet:)
        client.api_data("POST", "/api/v1/apps/signals", { "appid" => appid, "user" => user, "packet" => packet })
        true
      end

      def register(client, name:, data: nil, tables: nil, tables_protected: false)
        params = { "name" => name.to_s }
        params["data"] = data if data != nil
        params["tables"] = tables if tables != nil
        params["tables_protected"] = tables_protected == true || tables_protected.to_s == "1" || tables_protected.to_s.downcase == "true"
        data = client.api_data("POST", "/api/v1/apps", params)
        data.dig("app", "uuid").to_s
      end

      def update(client, uuid, name: nil, data: nil, tables: nil, tables_protected: nil)
        params = {}
        params["name"] = name.to_s if name != nil
        params["data"] = data if data != nil
        params["tables"] = tables if tables != nil
        params["tables_protected"] = tables_protected == true || tables_protected.to_s == "1" || tables_protected.to_s.downcase == "true" if tables_protected != nil
        data = client.api_data("PUT", "/api/v1/apps/#{query_escape(uuid)}", params)
        data["app"]
      end

      def info(client, uuid)
        data = client.api_data("GET", "/api/v1/apps/#{query_escape(uuid)}")
        data["app"]
      end

      def schema(client, uuid)
        data = client.api_data("GET", "/api/v1/apps/#{query_escape(uuid)}/schema")
        data["app"]
      end

      def table(client, uuid, table)
        AppTable.new(client, uuid, table)
      end

      def package_url(base_url_or_app, app = nil)
        app = base_url_or_app if app == nil
        return app.url if app.respond_to?(:url) && app.url.to_s != ""

        Client.absolute_api_url("/" + Client.append_query("api/v1/apps/#{query_escape(app_path(app))}/package", {}))
      end

      def app_path(app)
        app.respond_to?(:path) ? app.path : app
      end

      def query_escape(value)
        string = value.to_s.dup
        string.force_encoding(Encoding::UTF_8) if string.encoding == Encoding::ASCII_8BIT
        string = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        string.gsub(/([^ a-zA-Z0-9_.-]+)/) do |match|
          match.bytes.map { |byte| "%" + byte.to_s(16).rjust(2, "0").upcase }.join
        end.tr(" ", "+")
      end

      def normalize_build_id(value)
        return nil if value == nil

        text = value.to_s.strip
        return nil if text == "" || text == "0"

        text
      end

      def stamp_params
        stamp = launcher_stamp
        return {} if stamp == nil

        {
          "stamp_timestamp" => stamp["timestamp"],
          "stamp_key_sha256" => stamp["key_sha256"],
          "stamp_hwid" => stamp["hwid"],
          "stamp_hmac" => stamp["hmac"]
        }.select { |_key, value| value.to_s != "" }
      end

      def launcher_stamp
        session = Client.session_object
        return nil if session == nil || session.name.to_s == "" || session.name.to_s == "guest"

        get_stamp(session.name)
      rescue StandardError
        nil
      end

      private :app_path

    end
  end
end
