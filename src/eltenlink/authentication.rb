# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class LoginResult
    attr_reader :name, :token, :moderator, :fullname, :gender, :languages, :greeting, :auto_login_token, :issued_at

    def initialize(data)
      @name = data["name"].to_s
      @token = data["token"].to_s
      @moderator = data["moderator"] ? 1 : 0
      @fullname = data["fullname"].to_s
      @gender = data["gender"].to_i
      @languages = data["languages"].to_s
      @greeting = data["greeting"].to_s
      @auto_login_token = data["auto_login_token"].to_s
      @issued_at = data["issued_at"].to_i
    end

    def success?
      true
    end
  end

  module Authentication
    class << self
      def login(client, name:, password: nil, token: nil, version_string:, version_isdevelopment:, version_islauncher:, appid:, language:, os:, authmethod:, stamp: nil)
        params = {
          "name" => name,
          "version_string" => version_string.to_s.upcase,
          "version_isdevelopment" => version_isdevelopment ? 1 : 0,
          "version_islauncher" => version_islauncher ? 1 : 0,
          "appid" => appid,
          "lang" => language,
          "language" => language,
          "os" => os,
          "authmethod" => authmethod
        }
        if stamp != nil
          params["stamp_timespan"] = stamp["timespan"]
          params["stamp_key_sha256"] = stamp["key_sha256"]
          params["stamp_hwid"] = stamp["hwid"]
          params["stamp_hmac"] = stamp["hmac"]
        end
        if token != nil && token != ""
          params["token"] = token
        else
          params["password"] = password
        end
        LoginResult.new(client.api_data("POST", "/api/v1/session", params))
      end

      def auto_login_token(client, name:, password:, computer:, appid:)
        data = client.api_data("POST", "/api/v1/session/auto-login-token", {
          "name" => name,
          "password" => password,
          "computer" => computer,
          "appid" => appid
        })
        data["token"].to_s
      end

      def state(client)
        data = client.api_data("GET", "/api/v1/authentication")
        data["state"].to_i
      end

      def enable(client, password:, phone:, language:)
        client.api_data("PUT", "/api/v1/authentication", { "password" => password, "phone" => phone, "lang" => language, "language" => language })
        true
      end

      def verify(client, code:, appid:)
        client.api_data("POST", "/api/v1/authentication/verification", { "code" => code, "appid" => appid })
        true
      end

      def disable(client, password:)
        client.api_data("DELETE", "/api/v1/authentication", { "password" => password })
        true
      end

      def backup_codes(client, password:)
        data = client.api_data("POST", "/api/v1/authentication/backup-codes", { "password" => password })
        data["codes"].to_a.map(&:to_s)
      end

      def authenticate(client, appid:, name:, code:)
        client.api_data("POST", "/api/v1/authentication/authorizations", { "appid" => appid, "name" => name, "code" => code })
        true
      end
    end
  end
end
