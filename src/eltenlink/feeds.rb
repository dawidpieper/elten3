# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Feeds
    class << self
      def publish(client, message, response: 0)
        response = 0 if response <= 1
        return false if message == "" || !message.is_a?(String)
        message = message.split("")[0...300].join("")
        client.api_success?("POST", "/api/v1/feeds", { "response" => response, "text" => message })
      end

      def delete(client, id)
        client.api_data("DELETE", "/api/v1/feeds/#{id.to_i}")
        true
      end

      def follow(client, user, follow:)
        if follow
          client.api_data("POST", "/api/v1/feeds/follows", { "user" => user })
        else
          client.api_data("DELETE", "/api/v1/feeds/follow/#{user.to_s.urlenc}")
        end
        true
      end

      def likes(client, message_id)
        client.api_data("GET", "/api/v1/feeds/#{message_id.to_i}/likes")["users"].to_a.map(&:to_s)
      end

      def show(client, user)
        parse_messages(client.api_data("GET", "/api/v1/feeds", { "user" => user }))
      end

      def responses(client, id)
        parse_messages(client.api_data("GET", "/api/v1/feeds/#{id.to_i}/responses"))
      end

      def followed_updates(client, time: 0, limit: 1500)
        data = client.api_data("GET", "/api/v1/feeds/followed", { "time" => time.to_i, "limit" => limit.to_i })
        {
          "messages" => parse_messages(data),
          "count" => data["count"].to_i,
          "feedtime" => data["feedtime"].to_i
        }
      end

      def set_liked(client, message_id, liked)
        method = liked ? "PUT" : "DELETE"
        client.api_data(method, "/api/v1/feeds/#{message_id.to_i}/like")
        true
      end

      private

      def parse_messages(data)
        data["messages"].to_a.map do |row|
          FeedMessage.new(
            row["id"].to_i,
            row["user"].to_s,
            row["time"].to_i,
            row["message"].to_s,
            row["response"].to_i,
            row["responses"].to_i,
            row["liked"] == true || row["liked"].to_s == "1",
            row["likes"].to_i
          )
        end
      end
    end
  end
end
