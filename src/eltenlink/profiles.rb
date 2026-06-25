# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Profiles
    class << self
      def visiting_card(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/visiting-card")
        ["0\r\n", (data["exists"] ? data["text"].to_s : "     ")]
      end

      def set_visiting_card(client, text:)
        client.api_data("PATCH", "/api/v1/users/me/visiting-card", { "text" => text })
        true
      end

      def profile(client, user)
        payload = client.api_payload("GET", "/api/v1/users/#{user.to_s.urlenc}/profile")
        return nil unless payload.is_a?(Hash) && Client.truthy?(payload["success"])

        data = payload["data"] || {}
        birthdate = data["birthdate"] || {}
        [
          "0\r\n",
          "#{data["fullname"]}\r\n",
          "#{data["gender"].to_i}\r\n",
          "#{birthdate["year"].to_i}\r\n",
          "#{birthdate["month"].to_i}\r\n",
          "#{birthdate["day"].to_i}\r\n",
          "#{data["location"]}\r\n",
          "#{data["public_profile"].to_i}\r\n"
        ]
      end

      def update_profile(client, fullname: nil, gender: nil, birthdate_year: nil, birthdate_month: nil, birthdate_day: nil, location: nil, public_profile: nil, public_mail: nil)
        client.api_data("PATCH", "/api/v1/users/me/profile", clean_hash(
          "fullname" => fullname,
          "gender" => gender,
          "birthdateyear" => birthdate_year,
          "birthdatemonth" => birthdate_month,
          "birthdateday" => birthdate_day,
          "location" => location,
          "publicprofile" => public_profile,
          "publicmail" => public_mail
        ))
        true
      end

      private

      def clean_hash(hash)
        hash.each_with_object({}) { |(key, value), result| result[key] = value unless value.nil? }
      end
    end
  end
end
