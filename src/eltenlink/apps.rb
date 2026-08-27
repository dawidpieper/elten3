# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

require "json"

module EltenLink
  AppResource = Struct.new(:id, :appid, :uploader, :resource, :filesize, :meta, :url, keyword_init: true) do
    def name
      resource
    end

    def size
      filesize
    end
  end

  class AppPackage
    attr_accessor :id, :name, :size, :version, :build_id, :elten_api_version, :author, :path, :url
    attr_reader :realpath

    def initialize(path:, name:, version:, author:, size:, realpath: nil, url: "", build_id: nil, elten_api_version: "", id: "")
      @id = id.to_s
      @path = path
      @name = name
      @version = version
      @build_id = Apps.normalize_build_id(build_id)
      @elten_api_version = elten_api_version.to_s
      @author = author
      @size = size.to_i
      @realpath = realpath
      @url = url.to_s
    end
  end

  module Apps
    class AppResources
      attr_reader :maxsize, :used_size

      def initialize(client, app_uuid)
        @client = client
        @app_uuid = app_uuid.to_s
        @maxsize = nil
        @used_size = nil
      end

      def list
        data = @client.api_data("GET", path)
        @maxsize = data["maxsize"].to_i
        @used_size = data["used_size"].to_i
        data["resources"].to_a.map { |row| Apps.resource_from(row, @app_uuid) }
      end

      def info(resource)
        data = @client.api_data("GET", "#{path}/#{resource_id(resource)}")
        Apps.resource_from(data, @app_uuid)
      end

      def upload(resource, data, meta: nil, timeout: nil)
        Apps.validate_resource_name!(resource)
        Apps.validate_resource_meta!(meta)
        params = { "resource" => resource.to_s }
        params["meta"] = meta.to_s if meta != nil
        result = @client.api_binary_data(
          "POST",
          path,
          data.to_s.b,
          { "Content-Type" => "application/octet-stream" },
          params,
          timeout: timeout
        )
        Apps.resource_from(result, @app_uuid)
      end

      def delete(resource)
        @client.api_data("DELETE", "#{path}/#{resource_id(resource)}")
        true
      end

      def download_url(resource)
        return resource.url.to_s if resource.respond_to?(:url) && resource.url.to_s != ""

        Client.absolute_api_url("#{path}/#{resource_id(resource)}/download")
      end

      private

      def path
        "/api/v1/apps/#{Apps.query_escape(@app_uuid)}/resources"
      end

      def resource_id(resource)
        value = resource.respond_to?(:id) ? resource.id : resource
        id = Integer(value.to_s, 10)
        raise ArgumentError, "Invalid app resource ID" if id <= 0

        id
      rescue ArgumentError, TypeError
        raise ArgumentError, "Invalid app resource ID"
      end
    end

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
            elten_api_version: row["elten_api_version"].to_s,
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

      def resources(client, uuid)
        AppResources.new(client, uuid)
      end

      def delete(client, uuid)
        client.api_data("DELETE", "/api/v1/apps/#{query_escape(uuid)}")
        true
      end

      def resource_from(row, fallback_appid = "")
        row = {} unless row.is_a?(Hash)
        appid = row["appid"].to_s
        appid = fallback_appid.to_s if appid == ""
        id = row["id"].to_i
        url = row["url"].to_s
        if url == "" && appid != "" && id > 0
          url = "/api/v1/apps/#{query_escape(appid)}/resources/#{id}/download"
        end
        AppResource.new(
          id: id,
          appid: appid,
          uploader: row["uploader"].to_s,
          resource: row["resource"].to_s,
          filesize: row["filesize"].to_i,
          meta: row.key?("meta") ? row["meta"] : nil,
          url: Client.absolute_api_url(url)
        )
      end

      def validate_resource_name!(name)
        value = name.to_s
        valid = value.length.between?(1, 256) &&
          value.match?(/\A[A-Za-z0-9][A-Za-z0-9._() -]*\z/) &&
          !value.end_with?(".", " ")
        stem = value.split(".", 2).first.to_s.upcase
        reserved = %w[CON PRN AUX NUL CLOCK$].include?(stem) || stem.match?(/\A(?:COM|LPT)[1-9]\z/)
        raise ArgumentError, "Invalid app resource name" if !valid || reserved

        value
      end

      def validate_resource_meta!(meta)
        return nil if meta.nil?

        value = meta.to_s
        raise ArgumentError, "Invalid app resource metadata" if value.length > 1024 || value.include?("\0")

        value
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
        return nil if session == nil || !session.respond_to?(:logged?) || !session.logged?

        get_stamp(session.name)
      rescue StandardError
        nil
      end

      private :app_path

    end
  end
end
