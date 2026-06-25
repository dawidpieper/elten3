# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class BanInfo
    attr_accessor :banned, :totime, :reason

    def initialize(banned: false, totime: 0, reason: "")
      @banned = banned
      @totime = totime.to_i
      @reason = reason.to_s
    end
  end

  module Bans
    class << self
      def ban(client, user:, totime:, reason:, info:, ip:)
        client.api_data("POST", "/api/v1/bans", { "user" => user, "totime" => totime, "reason" => reason, "info" => info.to_s, "ip" => ip })
        true
      end

      def info(client, user)
        data = client.api_data("GET", "/api/v1/bans/#{user.to_s.urlenc}")
        BanInfo.new(banned: truthy?(data["banned"]), totime: data["totime"], reason: data["reason"].to_s)
      end

      def unban(client, user:, reason:)
        client.api_data("DELETE", "/api/v1/bans/#{user.to_s.urlenc}", { "reason" => reason })
        true
      end

      private

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end
    end
  end
end
