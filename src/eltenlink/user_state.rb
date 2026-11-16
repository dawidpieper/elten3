# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "json"

module EltenLink
  class UserState
    PATH = "/api/v1/accounts/me/state".freeze

    attr_reader :app_uuid, :collection_name

    def initialize(client, app_uuid: nil, collection: "", owner: nil)
      @client = client
      @app_uuid = app_uuid == nil ? nil : app_uuid.to_s.dup.freeze
      @owner = owner
      unless collection.is_a?(String) && collection.valid_encoding?
        raise ArgumentError, "Collection must be a UTF-8 string"
      end
      collection = collection.encode(Encoding::UTF_8)
      raise ArgumentError, "Collection must contain at most 128 UTF-8 bytes" if collection.bytesize > 128

      @collection_name = collection.dup.freeze
      @auth = Client.session_auth_params.transform_values { |value| value.to_s.dup.freeze }.freeze
      raise Error.new("Login is required", code: "auth.unauthorized") if @auth.empty?
    end

    def read(key, timeout: Client::DEFAULT_TIMEOUT, cancellation_token: nil)
      request("GET", PATH, entry_params(key), timeout, cancellation_token)["value"]
    end

    def write(key, value, override: false, evict_oldest: false, ttl: nil,
      timeout: Client::DEFAULT_TIMEOUT, cancellation_token: nil)
      params = write_params(key, value, override, evict_oldest, ttl)
      request("PUT", PATH, params, timeout, cancellation_token)["written"] == true
    end

    def delete(key, timeout: Client::DEFAULT_TIMEOUT, cancellation_token: nil)
      request("DELETE", PATH, entry_params(key), timeout, cancellation_token)["deleted"] == true
    end

    def read_async(key, timeout: Client::DEFAULT_TIMEOUT)
      params = entry_params(key)
      start(timeout) { |token| request("GET", PATH, params, timeout, token)["value"] }
    end

    def write_async(key, value, override: false, evict_oldest: false, ttl: nil, timeout: Client::DEFAULT_TIMEOUT)
      params = write_params(key, value, override, evict_oldest, ttl)
      start(timeout) { |token| request("PUT", PATH, params, timeout, token)["written"] == true }
    end

    def delete_async(key, timeout: Client::DEFAULT_TIMEOUT)
      params = entry_params(key)
      start(timeout) { |token| request("DELETE", PATH, params, timeout, token)["deleted"] == true }
    end

    def clear_all(timeout: Client::DEFAULT_TIMEOUT, cancellation_token: nil)
      raise ArgumentError, "Clearing all user state requires the Elten instance" if @app_uuid != nil || @collection_name != ""

      request("DELETE", "#{PATH}/all", {}, timeout, cancellation_token)["deleted_count"].to_i
    end

    private

    def entry_params(key)
      unless key.is_a?(String) && key.valid_encoding?
        raise ArgumentError, "Key must be a UTF-8 string"
      end
      key = key.encode(Encoding::UTF_8)
      raise ArgumentError, "Key must contain between 1 and 256 UTF-8 bytes" unless key.bytesize.between?(1, 256)

      params = { "key" => key.dup, "collection" => @collection_name }
      params["app_uuid"] = @app_uuid if @app_uuid != nil
      params
    end

    def write_params(key, value, override, evict_oldest, ttl)
      unless [true, false].include?(override) && [true, false].include?(evict_oldest)
        raise ArgumentError, "override and evict_oldest must be booleans"
      end
      unless ttl == nil || (ttl.is_a?(Integer) && ttl >= 0)
        raise ArgumentError, "TTL must be a non-negative number of seconds"
      end
      params = entry_params(key).merge(
        "app_uuid" => @app_uuid, "value" => JSON.parse(JSON.generate(value)),
        "override" => override, "evict_oldest" => evict_oldest
      )
      params["ttl"] = ttl if ttl != nil
      params
    end

    def start(timeout, &block)
      ensure_session!
      EltenAPI::Tasks.start(owner: @owner, timeout: timeout, &block)
    end

    def ensure_session!
      return if Client.session_auth_params == @auth

      raise Error.new("The user session has changed", code: "auth.session_changed")
    end

    def request(method, path, params, timeout, token)
      ensure_session!
      @client.dup.api_data(method, path, params, timeout: timeout, cancellation_token: token,
        headers: { "X-Elten-Name" => @auth.fetch("name"), "X-Elten-Token" => @auth.fetch("token") })
    end
  end
end
