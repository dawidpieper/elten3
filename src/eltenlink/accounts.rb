# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class AutoLoginEntry
    attr_accessor :created_at, :ip, :computer

    def initialize(created_at:, ip:, computer:)
      @created_at = created_at
      @ip = ip.to_s
      @computer = computer.to_s
    end
  end

  class LastLoginEntry
    attr_accessor :created_at, :ip

    def initialize(created_at:, ip:)
      @created_at = created_at
      @ip = ip.to_s
    end
  end

  class ExportStatus
    attr_accessor :ready, :pending, :export_time, :next_time

    def initialize(ready:, pending:, export_time:, next_time:)
      @ready = ready
      @pending = pending
      @export_time = export_time
      @next_time = next_time
    end
  end

  class ExportFile
    attr_accessor :time, :file, :url

    def initialize(time:, file:, url: "")
      @time = time
      @file = file.to_s
      @url = url.to_s
    end
  end

  class MailEventsState
    attr_accessor :verified, :enabled

    def initialize(verified:, enabled:)
      @verified = verified
      @enabled = enabled
    end
  end

  class RegistrationResult
    attr_reader :name

    def initialize(data)
      @name = data["name"].to_s
      @registered = truthy?(data["registered"])
      @activated = truthy?(data["activated"])
      @activation_required = truthy?(data["activation_required"])
    end

    def registered?
      @registered
    end

    def activated?
      @activated
    end

    def activation_required?
      @activation_required
    end

    private

    def truthy?(value)
      value == true || value.to_s == "1" || value.to_s.downcase == "true"
    end
  end

  module Accounts
    class << self
      def register(client, name:, password:, mail:, stamp: nil)
        params = { "name" => name, "password" => password, "mail" => mail }
        if stamp != nil
          params["stamp_timestamp"] = stamp["timestamp"]
          params["stamp_key_sha256"] = stamp["key_sha256"]
          params["stamp_hwid"] = stamp["hwid"]
          params["stamp_hmac"] = stamp["hmac"]
        end
        data = client.api_data("POST", "/api/v1/accounts", params)
        RegistrationResult.new(data)
      end

      def activate(client, code:)
        client.api_data("POST", "/api/v1/accounts/activation", { "code" => code })
        true
      end

      def resend_activation(client, name:, mail: nil)
        params = { "name" => name }
        params["mail"] = mail if mail != nil
        client.api_data("POST", "/api/v1/accounts/activation/resend", params)
        true
      end

      def user_mail_matches?(client, user:, mail:)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/exists", { "mail" => mail })
        truthy?(data["mail_matches"]) && truthy?(data["exists"])
      end

      def request_password_reset(client, user:, mail:)
        client.api_data("POST", "/api/v1/accounts/password-reset", { "name" => user, "mail" => mail })
        true
      end

      def verify_password_reset(client, user:, mail:, key:)
        client.api_data("POST", "/api/v1/accounts/password-reset/verify", { "name" => user, "mail" => mail, "key" => key })
        true
      end

      def change_password_with_reset(client, user:, mail:, key:, new_password:)
        client.api_data("POST", "/api/v1/accounts/password-reset/change", { "name" => user, "mail" => mail, "key" => key, "new_password" => new_password })
        true
      end

      def config(client)
        client.api_data("GET", "/api/v1/accounts/me/config")
      rescue Error
        {}
      end

      def update_config(client, values)
        client.api_data("PATCH", "/api/v1/accounts/me/config", { "config" => values })
        true
      end

      def change_password(client, old_password:, new_password:)
        client.api_data("PATCH", "/api/v1/accounts/me/password", { "old_password" => old_password, "new_password" => new_password })
        true
      end

      def change_mail(client, password:, mail:)
        client.api_data("PATCH", "/api/v1/accounts/me/mail", { "password" => password, "mail" => mail })
        true
      end

      def auto_logins(client, password)
        data = client.api_data("GET", "/api/v1/accounts/me/autologins", { "password" => password })
        parse_auto_logins(data["autologins"])
      end

      def global_logout(client, password)
        client.api_data("POST", "/api/v1/accounts/me/global-logout", { "password" => password })
        true
      end

      def blacklist(client)
        client.api_data("GET", "/api/v1/accounts/me/blacklist")["users"].to_a.map(&:to_s)
      end

      def add_to_blacklist(client, user)
        client.api_data("POST", "/api/v1/accounts/me/blacklist", { "user" => user })
        true
      end

      def delete_from_blacklist(client, user)
        client.api_data("DELETE", "/api/v1/accounts/me/blacklist/#{user.to_s.urlenc}")
        true
      end

      def last_logins(client, password)
        data = client.api_data("GET", "/api/v1/accounts/me/last-logins", { "password" => password })
        parse_last_logins(data["logins"])
      end

      def mail_events_state(client, password)
        data = client.api_data("GET", "/api/v1/accounts/me/mail-events", { "password" => password })
        MailEventsState.new(verified: truthy?(data["verified"]), enabled: truthy?(data["enabled"]))
      end

      def verify_mail_events(client, password, code: nil)
        params = { "password" => password }
        params["code"] = code if code != nil
        path = code == nil ? "/api/v1/accounts/me/mail-events/verification" : "/api/v1/accounts/me/mail-events/verify"
        client.api_data("POST", path, params)
        true
      end

      def set_mail_events(client, password, enabled:, code: nil)
        params = { "password" => password, "enabled" => (enabled ? "1" : "0") }
        params["code"] = code if code != nil
        client.api_data("PATCH", "/api/v1/accounts/me/mail-events", params)
        true
      end

      def archive(client, password)
        client.api_data("POST", "/api/v1/accounts/me/archive", { "password" => password })
        true
      end

      def export_status(client)
        data = client.api_data("GET", "/api/v1/accounts/me/export")
        ExportStatus.new(
          ready: data["status"].to_i == 1,
          pending: data["time_started"].to_i > 0,
          export_time: data["time_completed"].to_i,
          next_time: data["next_time"].to_i
        )
      end

      def enqueue_export(client, password)
        client.api_data("POST", "/api/v1/accounts/me/export", { "password" => password })
        true
      end

      def export_file(client, password)
        data = client.api_data("GET", "/api/v1/accounts/me/export/file", { "password" => password })
        ExportFile.new(time: data["time_completed"].to_i, file: data["file"].to_s, url: data["url"].to_s)
      end

      def export_download_url(export_file)
        return export_file.url if export_file.respond_to?(:url) && export_file.url.to_s != ""

        Client.absolute_api_url("/api/v1/accounts/exports/#{export_file.file.to_s.urlenc}/download")
      end

      private

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end

      def parse_auto_logins(rows)
        rows.to_a.map do |row|
          AutoLoginEntry.new(
            created_at: Time.at(row["created_at"].to_i),
            ip: row["ip"].to_s,
            computer: row["computer"].to_s
          )
        end
      end

      def parse_last_logins(rows)
        rows.to_a.map do |row|
          LastLoginEntry.new(
            created_at: Time.at(row["created_at"].to_i),
            ip: row["ip"].to_s
          )
        end
      end
    end
  end
end
