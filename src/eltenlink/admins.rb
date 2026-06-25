# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Admins
    class << self
      def users(client, category)
        users = client.api_data("GET", "/api/v1/admins", { "category" => category })["users"].to_a.map(&:to_s)
        users.select { |line| line.size > 0 }.polsort
      end

      def administrators(client)
        data = client.api_data("GET", "/api/v1/admins/administrators")
        data["administrators"].to_a.map do |row|
          user = row["user"].to_s
          user.size > 0 ? [user, row["label"].to_s] : nil
        end.compact
      end

      def moderator_groups(client)
        data = client.api_data("GET", "/api/v1/admins/moderator-groups")
        data["groups"].to_a.map do |row|
          { id: row["id"].to_i, name: row["name"].to_s, users: row["users"].to_a.map(&:to_s).polsort }
        end
      end
    end
  end
end
