# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Monitors
    class << self
      def add(client, user, permanent:)
        client.api_data("POST", "/api/v1/monitors", { "user" => user, "permanent" => permanent })
        true
      end

      def delete(client, user)
        client.api_data("DELETE", "/api/v1/monitors/#{user.to_s.urlenc}")
        true
      end
    end
  end
end
