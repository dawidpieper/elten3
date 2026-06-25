# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Activities
    class << self
      def register(client, name:, token:, activity:, config:, timeout: 20.0)
        data = client.api_data("POST", "/api/v1/activities", {
          "activity" => activity || {},
          "config" => config || {}
        }, timeout: timeout, headers: {
          "x-elten-name" => name.to_s,
          "x-elten-token" => token.to_s
        })
        Client.truthy?(data["registered"])
      end
    end
  end
end
