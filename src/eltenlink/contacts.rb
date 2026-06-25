# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Contacts
    class << self
      def list(client, birthday: false)
        path = birthday ? "/api/v1/contacts/birthdays" : "/api/v1/contacts"
        data = client.api_data("GET", path)
        data["users"].to_a.map(&:to_s).select { |line| line.size > 1 }.polsort
      end

      def acknowledge_birthdays(client)
        client.api_data("PATCH", "/api/v1/contacts/birthdays")
        true
      end

      def add(client, user)
        client.api_data("POST", "/api/v1/contacts", { "user" => user })
        true
      end

      def delete(client, user)
        client.api_data("DELETE", "/api/v1/contacts/#{user.to_s.urlenc}")
        true
      end

      def added_me(client, new_only: false)
        params = new_only ? { "new_only" => "1" } : {}
        data = client.api_data("GET", "/api/v1/contacts/added-me", params)
        data["users"].to_a.map(&:to_s).select { |line| line.size > 1 }.polsort
      end

      def acknowledge_added_me(client)
        client.api_data("PATCH", "/api/v1/contacts/added-me")
        true
      end

    end
  end
end
