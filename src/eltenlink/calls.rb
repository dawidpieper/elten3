# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class CallHistoryEntry
    attr_accessor :caller, :user, :unanswered, :time
  end

  module Calls
    class << self
      def history(client)
        data = client.api_data("GET", "/api/v1/calls")
        calls = []
        data["calls"].to_a.each do |row|
          call = CallHistoryEntry.new
          call.caller = row["caller"].to_s
          call.user = row["user"].to_s
          unanswered = row["unanswered"]
          call.unanswered = unanswered == true || unanswered.to_s == "1" || unanswered.to_s.downcase == "true"
          call.time = row["time"].to_i
          calls << call
        end
        calls
      end

      def call_user(client, channel, user)
        data = client.api_data("POST", "/api/v1/calls", {
          "channel" => channel.id,
          "channel_password" => channel.password,
          "user" => user
        })
        data["id"].to_i
      end

      def cancel(client, call_id)
        client.api_data("DELETE", "/api/v1/calls/#{call_id.to_i}")
        true
      end

      def active?(client, call_id, absolute: false)
        data = client.api_data("GET", "/api/v1/calls/#{call_id.to_i}", { "absolute" => absolute ? 1 : 0 })
        value = data["active"]
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end
    end
  end
end
