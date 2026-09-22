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
    attr_accessor :id, :size, :version, :build_id, :elten_api_version, :eltenlink_contract_version,
      :author, :owner, :path, :url, :original_filename, :recommended, :creation_time, :update_time,
      :verified, :platforms, :metadata
    attr_reader :realpath, :raw_name, :raw_description, :localized_names, :localized_descriptions,
      :name_languages, :description_languages, :main_language, :supported_languages

    def initialize(path:, name:, version:, author:, size:, realpath: nil, url: "", build_id: nil,
      elten_api_version: "", eltenlink_contract_version: "", id: "", description: "",
      raw_name: nil, raw_description: nil, localized_names: {}, localized_descriptions: {},
      main_language: "unknown", supported_languages: [], owner: "", original_filename: "",
      supported_languages_declared: nil, recommended: false, creation_time: 0, update_time: 0,
      verified: false, platforms: [], metadata: {})
      @id = id.to_s
      @path = path
      @raw_name = (raw_name.nil? ? name : raw_name).to_s
      @raw_description = (raw_description.nil? ? description : raw_description).to_s
      @version = version
      @build_id = Apps.normalize_build_id(build_id)
      @elten_api_version = elten_api_version.to_s
      @eltenlink_contract_version = eltenlink_contract_version.to_s
      @author = author
      @owner = owner.to_s
      @size = size.to_i
      @realpath = realpath
      @url = url.to_s
      @localized_names = normalize_localizations(localized_names)
      @localized_descriptions = normalize_localizations(localized_descriptions)
      @metadata = metadata.is_a?(Hash) ? metadata : {}
      @main_language = normalize_language(main_language, allow_unknown: true) || "unknown"
      add_raw_localization(@localized_names, @raw_name)
      add_raw_localization(@localized_descriptions, @raw_description)
      @name_languages = @localized_names.keys.sort.freeze
      @description_languages = @localized_descriptions.keys.sort.freeze
      @supported_languages_declared = supported_languages_declared.nil? ?
        (@metadata.is_a?(Hash) && @metadata.key?("supported_languages")) : supported_languages_declared == true
      normalized_supported = Array(supported_languages).filter_map { |language| normalize_language(language) }.uniq
      if @supported_languages_declared && @main_language != "unknown" && !normalized_supported.include?(@main_language)
        normalized_supported << @main_language
      end
      @supported_languages = normalized_supported.sort.freeze
      @original_filename = original_filename.to_s
      @recommended = recommended == true || recommended.to_s == "1" || recommended.to_s.casecmp?("true")
      @verified = verified == true || verified.to_s == "1" || verified.to_s.casecmp?("true")
      @creation_time = creation_time.to_i
      @update_time = update_time.to_i
      @platforms = Array(platforms).map(&:to_s)
    end

    def supported_languages_declared?
      @supported_languages_declared
    end

    def verified?
      @verified == true
    end

    def name(language = nil)
      localized_value(@localized_names, @raw_name, language)
    end

    def name=(value)
      @raw_name = value.to_s
    end

    def description(language = nil)
      localized_value(@localized_descriptions, @raw_description, language)
    end

    def description=(value)
      @raw_description = value.to_s
    end

    private

    def normalize_localizations(value)
      return {} unless value.is_a?(Hash)
      value.each_with_object({}) do |(language, text), result|
        code = normalize_language(language)
        content = text.to_s.strip
        result[code] = content if code != nil && !content.empty?
      end
    end

    def normalize_language(value, allow_unknown: false)
      text = value.to_s.strip.tr("_", "-")
      return "unknown" if allow_unknown && text.casecmp?("unknown")
      match = /\A([a-zA-Z]{2})(?:-[a-zA-Z]{2})?\z/.match(text)
      match && match[1].downcase
    end

    def add_raw_localization(values, raw)
      return if @main_language == "unknown" || raw.to_s.empty? || values.key?(@main_language)
      values[@main_language] = raw.to_s
    end

    def localized_value(values, raw, language)
      requested = language == nil ? current_elten_language : normalize_language(language)
      [requested, "en", @main_language].compact.reject { |candidate| candidate == "unknown" }.uniq.each do |candidate|
        value = values[candidate]
        return value if value != nil && !value.empty?
      end
      values.keys.sort.each do |candidate|
        value = values[candidate]
        return value if value != nil && !value.empty?
      end
      raw.to_s
    end

    def current_elten_language
      return nil unless defined?(Configuration) && Configuration.respond_to?(:language)
      normalize_language(Configuration.language)
    rescue Exception
      nil
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

      def list(timeout: nil, cancellation_token: nil)
        data = @client.api_data("GET", path, **request_options(timeout, cancellation_token))
        @maxsize = data["maxsize"].to_i
        @used_size = data["used_size"].to_i
        data["resources"].to_a.map { |row| Apps.resource_from(row, @app_uuid) }
      end

      def info(resource, timeout: nil, cancellation_token: nil)
        data = @client.api_data("GET", "#{path}/#{resource_id(resource)}", **request_options(timeout, cancellation_token))
        Apps.resource_from(data, @app_uuid)
      end

      def upload(resource, data, meta: nil, timeout: nil, cancellation_token: nil)
        Apps.validate_resource_name!(resource)
        Apps.validate_resource_meta!(meta)
        params = { "resource" => resource.to_s }
        params["meta"] = meta.to_s if meta != nil
        options = { timeout: timeout }
        options[:cancellation_token] = cancellation_token if cancellation_token != nil
        result = @client.api_binary_data(
          "POST",
          path,
          data.to_s.b,
          { "Content-Type" => "application/octet-stream" },
          params,
          **options
        )
        Apps.resource_from(result, @app_uuid)
      end

      def delete(resource, timeout: nil, cancellation_token: nil)
        @client.api_data("DELETE", "#{path}/#{resource_id(resource)}", **request_options(timeout, cancellation_token))
        true
      end

      def download_url(resource)
        return resource.url.to_s if resource.respond_to?(:url) && resource.url.to_s != ""

        Client.absolute_api_url("#{path}/#{resource_id(resource)}/download")
      end

      private

      def request_options(timeout, cancellation_token)
        options = {}
        options[:timeout] = timeout if timeout != nil
        options[:cancellation_token] = cancellation_token if cancellation_token != nil
        options
      end

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

      def select(where: nil, order: nil, limit: nil, offset: nil, columns: nil, distinct: nil,
        group_by: nil, aggregates: nil, joins: nil, include_access: nil)
        extended = {
          columns: columns, distinct: distinct, group_by: group_by, aggregates: aggregates,
          joins: joins, include_access: include_access
        }.reject { |_key, value| value.nil? }
        unless extended.empty?
          return query(where: where, order: order, limit: limit, offset: offset, **extended)
        end
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

      # Extended queries are JSON POSTs. Plain select keeps the original GET
      # request and response, including compatibility with older servers.
      def query(where: nil, order: nil, limit: nil, offset: nil, columns: nil, distinct: nil,
        group_by: nil, aggregates: nil, joins: nil, include_access: nil)
        options = {
          "where" => where, "order" => order, "limit" => limit, "offset" => offset,
          "columns" => columns, "distinct" => distinct, "group_by" => group_by,
          "aggregates" => aggregates, "joins" => joins, "include_access" => include_access
        }.reject { |_key, value| value.nil? }
        data = @client.api_data("POST", "#{path}/query", Apps.stamp_params.merge(options))
        data["rows"].to_a
      end

      def insert_many(values)
        bulk("insert", "values" => values)["rows"].to_a
      end

      def upsert_many(values)
        bulk("upsert", "values" => values)["rows"].to_a
      end

      def delete_many(ids)
        bulk("delete", "ids" => ids)["count"].to_i
      end

      def share_many(ids, users: nil, contacts: false)
        bulk("share", "ids" => ids, "targets" => share_targets(users, contacts))["count"].to_i
      end

      def unshare_many(ids, users: nil, contacts: false)
        bulk("unshare", "ids" => ids, "targets" => share_targets(users, contacts))["count"].to_i
      end

      def share(id, user: nil, contacts: false)
        raise ArgumentError, "Specify either user or contacts" if contacts && !user.nil?
        params = Apps.stamp_params
        if contacts
          params["contacts"] = true
        else
          raise ArgumentError, "A user is required" if user.to_s.strip.empty?
          params["shared_with"] = user.to_s
        end
        data = @client.api_data("POST", "#{path}/#{share_row_id(id)}/shares", params)
        data["share"]
      end

      # Omitting user preserves the server's self-unshare operation. Contacts
      # policies can only be removed by the creator of the row.
      def unshare(id, user: nil, contacts: false)
        raise ArgumentError, "Specify either user or contacts" if contacts && !user.nil?
        params = Apps.stamp_params
        params["contacts"] = true if contacts
        request_path = "#{path}/#{share_row_id(id)}/shares"
        request_path += "/#{Apps.query_escape(user.to_s)}" unless user.nil?
        @client.api_data("DELETE", request_path, params)
        true
      end

      private

      def bulk(operation, params)
        @client.api_data("POST", "#{path}/bulk", Apps.stamp_params.merge(params).merge("operation" => operation))
      end

      def share_targets(users, contacts)
        raise ArgumentError, "Users must be an array" unless users.nil? || users.is_a?(Array)
        targets = (users || []).map { |user| { "type" => "user", "user" => user.to_s } }
        targets << { "type" => "contacts" } if contacts
        raise ArgumentError, "At least one sharing target is required" if targets.empty?
        targets
      end

      def share_row_id(id)
        raise ArgumentError, "Invalid app table row ID" unless id.to_s.match?(/\A[1-9]\d*\z/)
        id.to_i
      end

      def path
        "/api/v1/apps/#{Apps.query_escape(@app_uuid)}/tables/#{Apps.query_escape(@table)}/rows"
      end
    end

    class << self
      def list(client, os: nil)
        prm = {}
        prm["os"] = os if os != nil
        data = client.api_data("GET", "/api/v1/apps", prm)
        data["apps"].to_a.map { |row| package_from(row) }
      end

      def upload_package(elten_link, file, uuid: nil, original_filename: nil, timeout: nil, cancellation_token: nil)
        path = File.expand_path(file.to_s)
        raise ArgumentError, "Program package file not found" unless File.file?(path)

        if uuid.to_s.empty? && defined?(Programs) && Programs.respond_to?(:setup_package_info)
          uuid = Programs.setup_package_info(path).dig(:manifest)&.id
        end
        uuid = uuid.to_s.downcase
        unless uuid.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
          raise ArgumentError, "A valid program UUID is required"
        end

        filename = original_filename.to_s
        filename = File.basename(path.tr("\\", "/")) if filename.empty?
        File.open(path, "rb") do |input|
          data = elten_link.api_binary_data(
            "PUT",
            "/api/v1/apps/#{query_escape(uuid)}/package",
            input,
            { "Content-Type" => "application/vnd.elten.setup" },
            { "original_filename" => filename },
            timeout: timeout,
            cancellation_token: cancellation_token
          )
          package_from(data["package"] || {})
        end
      end

      def package_from(row)
        row = {} unless row.is_a?(Hash)
        metadata = row["metadata"].is_a?(Hash) ? row["metadata"] : {}
        id = (row["id"] || metadata["id"]).to_s
        path = row["path"].to_s
        path = id if path.empty?
        original_filename = row["original_filename"].to_s
        if original_filename.empty?
          base = File.basename(path.tr("\\", "/"))
          original_filename = base.downcase.end_with?(".eltsetup") ? base : "#{base}.eltsetup"
        end
        AppPackage.new(
          id: id,
          path: path,
          name: (row["name"] || metadata["name"]).to_s,
          description: (row["description"] || metadata["description"]).to_s,
          raw_name: (row["raw_name"] || row["name"] || metadata["name"]),
          raw_description: (row["raw_description"] || row["description"] || metadata["description"]),
          localized_names: row["localized_names"] || metadata["localized_names"] || {},
          localized_descriptions: row["localized_descriptions"] || metadata["localized_descriptions"] || {},
          main_language: row["main_language"] || metadata["main_language"] || "unknown",
          supported_languages: row["supported_languages"] || metadata["supported_languages"] || [],
          supported_languages_declared: row.key?("supported_languages_declared") ?
            row["supported_languages_declared"] : (row.key?("supported_languages") ? true : nil),
          version: (row["version"] || metadata["version"] || metadata["version_string"]).to_s,
          build_id: normalize_build_id(row["build_id"] || metadata["build_id"] || metadata["BuildID"]),
          elten_api_version: (row["elten_api_version"] || metadata["EltenAPIVersion"]).to_s,
          eltenlink_contract_version: (row["eltenlink_contract_version"] || metadata["EltenLinkContractVersion"]).to_s,
          author: (row["author"] || metadata["author"]).to_s,
          owner: row["owner"].to_s,
          size: row["size"].to_i,
          url: row["url"].to_s,
          original_filename: original_filename,
          recommended: row["recommended"],
          verified: row["verified"],
          creation_time: row["creation_time"],
          update_time: row["update_time"],
          platforms: row["platforms"] || metadata["platforms"] || [],
          metadata: metadata
        )
      end

      def signal(client, appid:, user:, packet:)
        client.api_data("POST", "/api/v1/apps/signals", { "appid" => appid, "user" => user, "packet" => packet })
        true
      end

      def create_live_session(client, appid:, instance_id:, metadata: {}, participant_metadata: {}, capacity: 2, visibility: :private, join_code: nil, discovery_metadata: {}, hide_participants: false, stack_entry_bytes: 256, stack_entries: 0, pool_count: 0, private_messages: false)
        raise ArgumentError, "hide_participants must be boolean" unless hide_participants == true || hide_participants == false
        if hide_participants
          discovery = client.api_data("GET", "/api/v1/apps/live-sessions/discover", { "appid" => appid, "instance_id" => instance_id, "sources" => "created", "limit" => 1 })
          unless discovery.dig("limits", "hide_participants") == true
            raise Error.new("Server does not support hiding live session participants", code: "apps.live_sessions.discovery_unsupported")
          end
        end
        client.api_data(
          "POST",
          "/api/v1/apps/live-sessions",
          {
            "appid" => appid,
            "instance_id" => instance_id,
            "metadata" => metadata,
            "participant_metadata" => participant_metadata,
            "capacity" => capacity,
            "stack_entry_bytes" => stack_entry_bytes,
            "stack_entries" => stack_entries, "pool_count" => pool_count, "private_messages" => private_messages,
            "visibility" => visibility.to_s, "join_code" => join_code, "discovery_metadata" => discovery_metadata, "hide_participants" => hide_participants
          }
        )
      end

      def invite_live_session(client, session_id:, participant_id:, user:, metadata: {})
        client.api_data(
          "POST",
          "#{live_session_path(session_id)}/invitations",
          { "participant_id" => participant_id, "user" => user, "metadata" => metadata }
        )
      end

      def accept_live_session(client, session_id:, appid:, instance_id:, participant_metadata: {}, invitation_id: nil)
        client.api_data(
          "POST",
          "#{live_session_path(session_id)}/accept",
          {
            "appid" => appid,
            "instance_id" => instance_id,
            "participant_metadata" => participant_metadata, "invitation_id" => invitation_id
          }
        )
      end

      def reject_live_session(client, session_id:, appid:, invitation_id: nil)
        client.api_data("POST", "#{live_session_path(session_id)}/reject", { "appid" => appid, "invitation_id" => invitation_id })
        true
      end

      def send_live_session(client, session_id:, participant_id:, packet:, message_id:, timeout: Client::DEFAULT_TIMEOUT, cancellation_token: nil)
        client.api_data(
          "POST",
          "#{live_session_path(session_id)}/messages",
          {
            "participant_id" => participant_id,
            "message_id" => message_id,
            "packet" => packet
          },
          timeout: timeout, cancellation_token: cancellation_token
        )
      end

      def live_session_discovery_request(operation, params, session_id: nil)
        path = "/api/v1/apps/live-sessions"
        case operation
        when :create
          ["POST", path, params]
        when :discover_sessions
          ["GET", "#{path}/discover", params]
        when :find_by_code
          ["POST", "#{path}/resolve-code", params]
        when :refresh
          ["GET", "#{live_session_path(session_id)}/discovery", params]
        when :update_metadata
          ["PUT", "#{live_session_path(session_id)}/discovery-metadata", params]
        when :join, :accept, :reject
          ["POST", "#{live_session_path(session_id)}/#{operation}", params]
        else
          raise ArgumentError, "Invalid live session discovery operation"
        end
      end

      def live_session_private_request(session_id, participant_id, params)
        ["POST", "#{live_session_path(session_id)}/private-messages", params.merge("participant_id" => participant_id)]
      end

      def live_session_pool_request(session_id, participant_id, operation, params = {}, pool_id: nil, draw_id: nil)
        path = "#{live_session_path(session_id)}/pools"
        [pool_id, draw_id].compact.each do |id|
          raise ArgumentError, "Invalid pool identifier" unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9_-]{16,64}\z/)
        end
        path += "/#{pool_id}" if pool_id
        method = case operation
        when :create then "POST"
        when :list, :state then "GET"
        when :delete then "DELETE"
        when :take
          path += "/take"
          "POST"
        when :draws, :draw, :reveal
          path += "/draws"
          path += "/#{draw_id}" if draw_id
          path += "/reveal" if operation == :reveal
          operation == :reveal ? "POST" : "GET"
        else
          raise ArgumentError, "Invalid pool operation"
        end
        [method, path, params.merge("participant_id" => participant_id)]
      end

      def live_session_random_request(session_id, participant_id, operation, params = {})
        suffix = { random: "random", stack_random: "stack/random" }.fetch(operation)
        ["POST", "#{live_session_path(session_id)}/#{suffix}", params.merge("participant_id" => participant_id)]
      end

      def live_session_stack_request(session_id, participant_id, operation, params = {})
        method = { push: "POST", read: "GET", trim: "DELETE" }.fetch(operation)
        [method, "#{live_session_path(session_id)}/stack", params.merge("participant_id" => participant_id)]
      end

      def leave_live_session(client, session_id:, participant_id:, timeout: Client::DEFAULT_TIMEOUT)
        client.api_data("POST", "#{live_session_path(session_id)}/leave", { "participant_id" => participant_id }, timeout: timeout)
        true
      end

      # Proposed endpoint; only used when limits["ownership_transfer"] is true.
      def live_session_ownership_request(session_id, participant_id, params)
        ["POST", "#{live_session_path(session_id)}/ownership", params.merge("participant_id" => participant_id)]
      end

      def close_live_session(client, session_id:, participant_id:, timeout: Client::DEFAULT_TIMEOUT)
        client.api_data("POST", "#{live_session_path(session_id)}/close", { "participant_id" => participant_id }, timeout: timeout)
        true
      end

      def live_session_path(session_id)
        "/api/v1/apps/live-sessions/#{query_escape(session_id.to_s)}"
      end

      def notify(client, appid:, user:, type:, metadata: {}, expires_in: 0)
        client.api_data(
          "POST",
          "/api/v1/apps/notifications",
          {
            "appid" => appid.to_s,
            "user" => user.to_s,
            "type" => type.to_s,
            "metadata" => metadata,
            "expires_in" => expires_in.to_i
          }
        )
        true
      end

      def register(client, name:, data: nil, tables: nil, tables_protected: false, notifications: false)
        params = { "name" => name.to_s }
        params["data"] = data if data != nil
        params["tables"] = tables if tables != nil
        params["tables_protected"] = tables_protected == true || tables_protected.to_s == "1" || tables_protected.to_s.downcase == "true"
        params["notifications"] = notifications == true || notifications.to_s == "1" || notifications.to_s.downcase == "true"
        data = client.api_data("POST", "/api/v1/apps", params)
        data.dig("app", "uuid").to_s
      end

      def update(client, uuid, name: nil, data: nil, tables: nil, tables_protected: nil, notifications: nil)
        params = {}
        params["name"] = name.to_s if name != nil
        params["data"] = data if data != nil
        params["tables"] = tables if tables != nil
        params["tables_protected"] = tables_protected == true || tables_protected.to_s == "1" || tables_protected.to_s.downcase == "true" if tables_protected != nil
        params["notifications"] = notifications == true || notifications.to_s == "1" || notifications.to_s.downcase == "true" if notifications != nil
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
