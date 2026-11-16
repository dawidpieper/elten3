# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  Notification = Struct.new(:id, :date, :update_time, :alert, :notification, :sound, :cat, :app_uuid, :expiration, :revoked, :payload, keyword_init: true)

  module Notifications
    class << self
      def list(client, all: false, app_uuids: nil)
        params = { "all" => truth_param(all) }
        params["notification_apps"] = Array(app_uuids).join(",") if app_uuids != nil
        data = client.api_data("GET", "/api/v1/notifications", params)
        data["notifications"].to_a.map { |row| from_data(row) }
      end

      def from_data(row)
        Notification.new(
          id: row["id"].to_i,
          date: row["date"].to_i,
          update_time: row["update_time"].to_i,
          alert: row["alert"].to_s,
          notification: row["notification"].to_s,
          sound: row["sound"].to_s,
          cat: row["cat"].to_s,
          app_uuid: row["app_uuid"].to_s,
          expiration: row["expiration"].to_i,
          revoked: truthy?(row["revoked"]),
          payload: row["payload"].is_a?(Hash) ? row["payload"] : {}
        )
      end

      def revoke(client, id, headers: nil, cancellation_token: nil)
        client.api_data("PATCH", "/api/v1/notifications/#{id.to_i}/revoke",
          headers: headers, cancellation_token: cancellation_token)
        true
      end

      def revoke_many(client, ids)
        ids = Array(ids).flatten.map(&:to_i).select(&:positive?).uniq
        return true if ids.empty?

        client.api_data("PATCH", "/api/v1/notifications/revoke", { "ids" => ids.join(",") })
        true
      end

      def revoke_all(client, app_uuids: nil)
        params = {}
        params["notification_apps"] = Array(app_uuids).join(",") if app_uuids != nil
        client.api_data("PATCH", "/api/v1/notifications/revoke-all", params)
        true
      end

      private

      def truth_param(value)
        value ? "1" : "0"
      end

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end
    end
  end
end
