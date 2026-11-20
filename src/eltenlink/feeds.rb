# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Feeds
    DEFAULT_MESSAGE_MAX_LENGTH = 300
    DEFAULT_AUDIO_MAX_DURATION_SECONDS = 60

    class << self
      def default_limits
        {
          "message_max_length" => DEFAULT_MESSAGE_MAX_LENGTH,
          "audio_max_duration_seconds" => DEFAULT_AUDIO_MAX_DURATION_SECONDS
        }
      end

      def limits(client)
        data = client.api_data("GET", "/api/v1/feeds/limits")
        message_max_length = data["message_max_length"].to_i
        audio_max_duration = data["audio_max_duration_seconds"].to_i
        {
          "message_max_length" => message_max_length > 0 ? message_max_length : DEFAULT_MESSAGE_MAX_LENGTH,
          "audio_max_duration_seconds" => audio_max_duration > 0 ? audio_max_duration : DEFAULT_AUDIO_MAX_DURATION_SECONDS
        }
      end

      def publish(client, message, response: 0, audio: nil, message_max_length: DEFAULT_MESSAGE_MAX_LENGTH)
        response = 0 if response <= 1
        return false if message == "" || !message.is_a?(String)
        message_max_length = DEFAULT_MESSAGE_MAX_LENGTH if message_max_length.to_i <= 0
        message = message.split("")[0...message_max_length.to_i].join("")
        if audio != nil
          return false if !audio.respond_to?(:bytesize) || audio.bytesize == 0
          client.api_binary_data(
            "POST",
            "/api/v1/feeds",
            audio,
            { "Content-Type" => "application/octet-stream" },
            { "response" => response, "text" => message, "audio" => 1, "datasize" => audio.bytesize }
          )
          true
        else
          client.api_data("POST", "/api/v1/feeds", { "response" => response, "text" => message })
          true
        end
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

      def responses(client, id, cancellation_token: nil)
        parse_messages(client.api_data("GET", "/api/v1/feeds/#{id.to_i}/responses", cancellation_token: cancellation_token))
      end

      def followed_updates(client, time: 0, limit: 1500)
        data = client.api_data("GET", "/api/v1/feeds/followed", { "time" => time.to_i, "limit" => limit.to_i })
        {
          "messages" => parse_messages(data),
          "count" => data["count"].to_i,
          "feedtime" => data["feedtime"].to_i
        }
      end

      def followed_users(client)
        data = client.api_data("GET", "/api/v1/feeds/follows")
        data["users"].to_a.map(&:to_s)
      end

      def set_liked(client, message_id, liked)
        method = liked ? "PUT" : "DELETE"
        client.api_data(method, "/api/v1/feeds/#{message_id.to_i}/like")
        true
      end

      def message_from_row(row, message_class=FeedMessage)
        audio = row["audio"]
        audio = audio["url"] || audio[:url] if audio.is_a?(Hash)
        audio = row["audio_url"] if audio.to_s == ""
        message_class.new(
          row["id"].to_i,
          row["user"].to_s,
          row["time"].to_i,
          row["message"].to_s,
          row["response"].to_i,
          row["responses"].to_i,
          row["liked"] == true || row["liked"].to_s == "1",
          row["likes"].to_i,
          audio.to_s
        )
      end

      private

      def parse_messages(data)
        data["messages"].to_a.map do |row|
          message_from_row(row)
        end
      end
    end
  end
end
