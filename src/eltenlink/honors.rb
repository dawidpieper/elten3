# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class Honor
    attr_accessor :id, :name, :description, :enname, :endescription, :levels, :enlevels, :level

    def initialize(id = 0)
      @id = id.to_i
      @name = ""
      @description = ""
      @enname = ""
      @endescription = ""
      @levels = []
      @enlevels = []
      @level = 0
    end
  end

  class HonorUser
    attr_accessor :name, :level

    def initialize(name, level)
      @name = name.to_s
      @level = level.to_i
    end
  end

  module Honors
    class << self
      def main(client, user, language)
        payload = client.api_payload("GET", "/api/v1/honors", { "user" => user, "main" => "1" })
        return nil unless payload.is_a?(Hash) && Client.truthy?(payload["success"])
        honor = (payload["data"] || {})["honors"].to_a.first
        return nil if honor == nil
        language == "pl-PL" ? honor["name"].to_s : honor["enname"].to_s
      end

      def list(client, user: nil)
        params = {}
        params["user"] = user if user != nil
        parse_list(client.api_data("GET", "/api/v1/honors", params)["honors"])
      end

      def set_main(client, honor)
        client.api_data("PUT", "/api/v1/honors/#{honor_id(honor)}/main")
        true
      end

      def award(client, user:, honor:)
        client.api_data("POST", "/api/v1/honors/#{honor_id(honor)}/awards", { "user" => user })
        true
      end

      def delete(client, honor)
        client.api_data("DELETE", "/api/v1/honors/#{honor_id(honor)}")
        true
      end

      def set_levels(client, honor, levels, enlevels)
        client.api_data("PATCH", "/api/v1/honors/#{honor_id(honor)}/levels", {
          "levels" => JSON.generate(levels),
          "enlevels" => JSON.generate(enlevels)
        })
        true
      end

      def users(client, honor)
        parse_users(client.api_data("GET", "/api/v1/honors/#{honor_id(honor)}/users")["users"])
      end

      def add(client, name:, description:, enname:, endescription:)
        client.api_data("POST", "/api/v1/honors", {
          "name" => name,
          "description" => description,
          "enname" => enname,
          "endescription" => endescription
        })
        true
      end

      private

      def parse_list(rows)
        rows.to_a.map do |row|
          honor = Honor.new(row["id"])
          honor.name = row["name"].to_s
          honor.description = row["description"].to_s
          honor.enname = row["enname"].to_s
          honor.endescription = row["endescription"].to_s
          honor.levels = row["levels"].is_a?(Array) ? row["levels"] : parse_json_array(row["levels"].to_s)
          honor.enlevels = row["enlevels"].is_a?(Array) ? row["enlevels"] : parse_json_array(row["enlevels"].to_s)
          honor.level = row["level"].to_i
          honor
        end
      end

      def parse_users(rows)
        rows.to_a.map { |row| HonorUser.new(row["user"].to_s, row["level"].to_i) }
      end

      def parse_json_array(text)
        return [] if text == ""
        parsed = JSON.load(text)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        []
      end

      def honor_id(honor)
        honor.respond_to?(:id) ? honor.id : honor
      end
    end
  end
end
