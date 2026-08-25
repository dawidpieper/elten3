# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  UserProfileBirthdate = Struct.new(:year, :month, :day, keyword_init: true) do
    def complete?
      year.to_i > 1900 && month.to_i.between?(1, 12) && day.to_i.between?(1, 31)
    end
  end
  UserProfile = Struct.new(
    :name,
    :fullname,
    :gender,
    :birthdate,
    :location,
    :public_profile,
    :public_mail,
    keyword_init: true
  )
  class UserCardHonor < Honor
  end
  UserCard = Struct.new(
    :name,
    :profile,
    :info,
    :visiting_card,
    :status,
    :main_honor,
    :ban,
    keyword_init: true
  )

  module Profiles
    class << self
      def card(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/card")
        visiting_card = data["visiting_card"]
        visiting_card = {} unless visiting_card.is_a?(Hash)
        status = data["status"]
        status = {} unless status.is_a?(Hash)
        ban = data["ban"]
        ban = nil unless ban.is_a?(Hash)
        main_honor = data["main_honor"]

        UserCard.new(
          name: data["name"].to_s,
          profile: build_profile(data["profile"]),
          info: Users.build_info(data["info"]),
          visiting_card: Client.truthy?(visiting_card["exists"]) ? visiting_card["text"].to_s : nil,
          status: UserStatus.new(
            text: status["text"].to_s,
            online: Client.truthy?(status["online"]),
            sponsor: Client.truthy?(status["sponsor"])
          ),
          main_honor: Honors.parse(main_honor, klass: UserCardHonor),
          ban: ban == nil ? nil : BanInfo.new(
            banned: Client.truthy?(ban["banned"]),
            totime: ban["totime"],
            reason: ban["reason"]
          )
        )
      end

      def visiting_card(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/visiting-card")
        return nil unless Client.truthy?(data["exists"])

        data["text"].to_s
      end

      def set_visiting_card(client, text:)
        client.api_data("PATCH", "/api/v1/users/me/visiting-card", { "text" => text })
        true
      end

      def profile(client, user)
        payload = client.api_payload("GET", "/api/v1/users/#{user.to_s.urlenc}/profile")
        return nil unless payload.is_a?(Hash) && Client.truthy?(payload["success"])

        build_profile(payload["data"])
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

      def build_profile(data)
        data = {} unless data.is_a?(Hash)
        birthdate = data["birthdate"] || {}
        gender = begin
          Integer(data.fetch("gender").to_s, 10)
        rescue KeyError, ArgumentError, TypeError
          -1
        end
        gender = -1 unless [0, 1].include?(gender)
        UserProfile.new(
          name: data["name"].to_s,
          fullname: data["fullname"].to_s,
          gender: gender,
          birthdate: UserProfileBirthdate.new(
            year: birthdate["year"].to_i,
            month: birthdate["month"].to_i,
            day: birthdate["day"].to_i
          ),
          location: data["location"].to_s,
          public_profile: data["public_profile"].to_i,
          public_mail: data["public_mail"].to_i
        )
      end

      def clean_hash(hash)
        hash.each_with_object({}) { |(key, value), result| result[key] = value unless value.nil? }
      end
    end
  end
end
