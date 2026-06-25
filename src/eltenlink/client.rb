# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

require "json"
require "uri"

module EltenLink
  class Client
    API_BASE_URL = "https://api.elten.link".freeze
    DEFAULT_TIMEOUT = 15

    attr_reader :context, :last_error

    def initialize(context = nil)
      @context = context
      @last_error = nil
    end

    def json(method, path, params = nil, timeout: DEFAULT_TIMEOUT, headers: nil)
      Log.debug("Server JSON request to #{self.class.redacted_path(path)}")
      call_context(:play, "signal") if $netsignal
      params = params.is_a?(Hash) ? params.dup : {}
      headers = headers.is_a?(Hash) ? headers.dup : {}
      auth_params = self.class.headers_have_auth?(headers) ? {} : self.class.session_auth_params
      request_path = path
      request_params = params
      if ["GET", "DELETE"].include?(method.to_s.upcase)
        request_path = self.class.append_query(path, auth_params.merge(params))
        request_params = {}
      elsif auth_params.size > 0 && !self.class.path_has_auth?(request_path)
        request_path = self.class.append_query(path, auth_params)
      end

      response = nil
      done = false
      @last_error = nil
      safe_request_path = self.class.redacted_path(request_path)
      submit_json_request(method, request_path, request_params, headers: headers) do |resp, _data|
        response = resp == :error ? nil : resp
        @last_error = Error.network(module_name: safe_request_path) if resp == :error
        done = true
      end

      started = Time.now.to_f
      waiting_visible = false
      while done == false
        if @context != nil
          call_context(:loop_update, false)
        else
          sleep(0.01)
        end
        elapsed = Time.now.to_f - started
        if elapsed > 2 && waiting_visible == false
          call_context(:waiting)
          waiting_visible = true
        elsif elapsed > timeout.to_f
          Log.warning("Session timed out for JSON request to #{safe_request_path}")
          @last_error = Error.timeout(module_name: safe_request_path)
          call_context(:waiting_end)
          break
        end
        if call_context(:key_pressed?, :key_escape) && waiting_visible
          call_context(:play, "cancel")
          Log.debug("Server JSON request to #{safe_request_path} cancelled by user")
          @last_error = Error.cancelled(module_name: safe_request_path)
          call_context(:waiting_end)
          return nil
        end
      end
      call_context(:waiting_end) if waiting_visible
      response
    end

    def api_payload(method, path, params = nil, timeout: DEFAULT_TIMEOUT, headers: nil)
      raw = json(method, path, params, timeout: timeout, headers: headers)
      return nil if raw == nil
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      safe_path = self.class.redacted_path(path)
      @last_error = Error.new("Invalid JSON response (#{safe_path})", code: "invalid_json", module_name: safe_path, response: raw)
      nil
    end

    def api_data(method, path, params = nil, timeout: DEFAULT_TIMEOUT, headers: nil)
      payload = api_payload(method, path, params, timeout: timeout, headers: headers)
      raise @last_error if payload == nil && @last_error != nil
      unless payload.is_a?(Hash) && self.class.truthy?(payload["success"])
        @last_error = api_error(payload, path)
        raise @last_error
      end
      payload["data"] || {}
    end

    def api_success?(method, path, params = nil, timeout: DEFAULT_TIMEOUT, headers: nil)
      payload = api_payload(method, path, params, timeout: timeout, headers: headers)
      payload.is_a?(Hash) && self.class.truthy?(payload["success"])
    end

    def api_binary_payload(method, path, body, headers = {}, params = nil, timeout: DEFAULT_TIMEOUT)
      params = params.is_a?(Hash) ? params.dup : {}
      self.class.session_auth_params.each { |key, value| params[key] = value if params[key] == nil }
      request_path = self.class.append_query(path, params)
      safe_request_path = self.class.redacted_path(request_path)
      response = nil
      done = false
      @last_error = nil
      e_read_url(self.class.absolute_api_url(request_path), method.to_s.upcase, body.to_s.b, headers, nil) do |resp, _data|
        response = resp == :error ? nil : resp
        @last_error = Error.network(module_name: safe_request_path) if resp == :error
        done = true
      end

      started = Time.now.to_f
      while done == false
        @context == nil ? sleep(0.01) : call_context(:loop_update, false)
        if Time.now.to_f - started > timeout.to_f
          @last_error = Error.timeout(module_name: safe_request_path)
          break
        end
      end
      return nil if response == nil
      JSON.parse(response.to_s)
    rescue JSON::ParserError
      safe_path = self.class.redacted_path(path)
      @last_error = Error.new("Invalid JSON response (#{safe_path})", code: "invalid_json", module_name: safe_path, response: response)
      nil
    end

    def api_binary_data(method, path, body, headers = {}, params = nil, timeout: DEFAULT_TIMEOUT)
      payload = api_binary_payload(method, path, body, headers, params, timeout: timeout)
      raise @last_error if payload == nil && @last_error != nil
      unless payload.is_a?(Hash) && self.class.truthy?(payload["success"])
        @last_error = api_error(payload, path)
        raise @last_error
      end
      payload["data"] || {}
    end

    def e_json_request(method, path, params, data=nil, headers: nil, &block)
      ::EltenAPI::HTTPClient.ejrequest(method, path, params, data, headers: headers, &block)
    end

    def e_read_url(url, method="get", body="", headers={}, data=nil, &block)
      ::EltenAPI::HTTPClient.readurl(url, method, body, headers, data, &block)
    end

    def e_download_file(source, destination, data=nil, &block)
      ::EltenAPI::HTTPClient.downloadfile(source, destination, data, &block)
    end

    def e_server_verify
      ::EltenAPI::HTTPClient.server_verify
    end

    def self.query(params)
      if params.is_a?(Hash)
        query_hash(params).map { |key, value| "#{key}=#{url_encode(value)}" }.join("&")
      elsif params.is_a?(String)
        parsed = {}
        params.split("&").each do |part|
          key, value = part.split("=", 2)
          value = "" if value == nil
          value = url_decode(value) if value.include?("%")
          parsed[key] = value
        end
        parsed.map { |key, value| "#{key}=#{url_encode(value)}" }.join("&")
      else
        params.to_s
      end
    end

    def self.url_encode(value)
      URI.encode_www_form_component(value.to_s)
    end

    def self.url_decode(value)
      URI.decode_www_form_component(value.to_s)
    rescue ArgumentError
      value.to_s
    end

    def self.query_hash(params)
      auth_params = session_auth_params
      return params if auth_params.empty? || params["name"] != nil
      result = params.dup
      result.merge!(auth_params)
      result
    end

    def self.session_auth_params
      session = session_object
      return {} if session == nil || !session.respond_to?(:name) || !session.respond_to?(:token)
      name = session.name
      token = session.token
      return {} if name == nil || name.to_s == "" || token == nil || token.to_s == ""
      { "name" => name, "token" => token }
    end

    def self.session_object
      return Object.const_get(:Session) if Object.const_defined?(:Session)
      return ::EltenAPI::Structs::Session if defined?(::EltenAPI::Structs::Session)
      return ::EltenAPI::Session if defined?(::EltenAPI::Session)

      nil
    end

    def self.append_query(path, params)
      query_string = query(params)
      return path if query_string == ""
      separator = path.include?("?") ? "&" : "?"
      path + separator + query_string
    end

    def self.path_has_auth?(path)
      value = path.to_s
      value.match?(/[?&]name=/) && value.match?(/[?&]token=/)
    end

    def self.headers_have_auth?(headers)
      return false unless headers.is_a?(Hash)
      normalized = {}
      headers.each { |key, value| normalized[key.to_s.downcase] = value }
      name = normalized["x-elten-name"] || normalized["x-elten-user"]
      token = normalized["x-elten-token"]
      authorization = normalized["authorization"].to_s
      (!name.to_s.empty? && !token.to_s.empty?) ||
        authorization.match?(/\ABasic\s+/i) ||
        (!name.to_s.empty? && authorization.match?(/\ABearer\s+/i))
    end

    def self.redacted_path(path)
      path.to_s.gsub(/([?&](?:name|token|password|autotoken|notificationstoken)=)[^&]*/i, "\\1[REDACTED]")
    end

    def self.api_base_url
      API_BASE_URL
    end

    def self.absolute_api_url(path)
      value = path.to_s
      value = "/api/v1/audio/messages/#{$1}" if value =~ %r{\Ahttps?://s\.elten(?:-net)?\.eu/m/([a-zA-Z0-9]+)(?:\.[a-zA-Z0-9_?=&-]+)?\z}i
      value = "/api/v1/audio/blog-posts/#{$1}" if value =~ %r{\Ahttps?://s\.elten(?:-net)?\.eu/b/([a-zA-Z0-9]+)(?:\.[a-zA-Z0-9_?=&-]+)?\z}i
      return value if value.match?(/\Ahttps?:\/\//i)
      value = "/api/v1/audio/messages/#{$1}" if value =~ %r{\A/audiomessages/([a-zA-Z0-9]+)\z}
      value = "/api/v1/audio/forum-posts/#{$1}" if value =~ %r{\A/audioforums/posts/([a-zA-Z0-9\/]+)\z}
      value = "/api/v1/audio/blog-posts/#{$1}" if value =~ %r{\A/audioblogs/posts/([a-zA-Z0-9]+)\z}
      value = "/" + value if value[0] != "/"
      "#{api_base_url}#{value}"
    end

    def self.api_audio_url?(path)
      absolute_api_url(path).match?(%r{\A#{Regexp.escape(api_base_url)}/api/v1/audio/}i)
    end

    def self.truthy?(value)
      value == true || value.to_s == "1" || value.to_s.downcase == "true"
    end

    private

    def api_error(payload, path)
      code = nil
      message = "API request failed"
      if payload.is_a?(Hash)
        error = payload["error"]
        if error.is_a?(Hash)
          code = error["code"]
          message = error["message"] || code || message
        elsif error != nil
          message = error.to_s
        end
      end
      safe_path = self.class.redacted_path(path)
      Error.new(message, code: code || "api_error", module_name: safe_path, response: payload)
    end

    def submit_json_request(method, path, params, headers: nil, &block)
      e_json_request(method, path, params, nil, headers: headers, &block)
    end

    def call_context(name, *args)
      return nil if @context == nil || !@context.respond_to?(name, true)
      @context.__send__(name, *args)
    end
  end
end
