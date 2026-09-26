# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

require "date"

module EltenLink
  module HonorCatalog
    STARTED_ON = Date.new(2014, 8, 24)

    DEFINITIONS = [
      [1, "Developer", "Has left fingerprints in Elten's source code - and the pull request survived review.", [
        "Have 1 pull request accepted into Elten.",
        "Have 5 pull requests accepted into Elten.",
        "Have 20 pull requests accepted into Elten.",
        "Have 50 pull requests accepted into Elten."
      ]],
      [2, "Leader", "Can turn a handful of users, a forum and a plan into a group people actually want to follow.", [
        "Lead a group with at least 20 members and 150 forum posts.",
        "Lead a group with at least 40 members and 750 forum posts.",
        "Lead a group with at least 50 members and 1,500 forum posts.",
        "Lead at least two groups, each with 70 members and 2,000 forum posts."
      ]],
      [3, "Blogger", "Keeps a blog so faithfully that readers have started dropping by on purpose.", [
        "Write 20 blog posts and receive comments from at least 5 different users.",
        "Write 50 blog posts and receive comments from at least 10 different users.",
        "Write 100 blog posts and receive comments from at least 20 different users.",
        "Write 200 blog posts and receive comments from at least 50 different users."
      ]],
      [4, "Sound Designer", "Built an Elten sound theme that at least three users chose to keep in their ears at the same time.", [
        "Create a sound theme used by at least 3 active users at the same time."
      ]],
      [5, "Speaker", "Has yet to meet a recommended-group thread that could not use one more post.", [
        "Write 100 posts in at least 10 different threads in recommended groups.",
        "Write 500 posts in at least 30 different threads in recommended groups.",
        "Write 1,000 posts in at least 100 different threads in recommended groups.",
        "Write 3,000 posts in at least 300 different threads in recommended groups."
      ]],
      [6, "Veteran", "Has been around Elten long enough to remember when some classics were still new.", nil],
      [7, "Debugger", "Helped a beta misbehave in private so a stable Elten release could behave in public.", [
        "Take part in testing an Elten beta that becomes a stable release, starting with version 3.0."
      ]],
      [8, "Promoter", "Packed Elten into an article, podcast or presentation and took it beyond Elten.", [
        "Publish an article, podcast or another presentation about Elten outside Elten."
      ]],
      [9, "Audiophile", "Treats the microphone less like a device and more like a natural extension.", [
        "Create 50 audio posts in the forum.",
        "Create 200 audio posts in the forum.",
        "Create 500 audio posts in the forum.",
        "Create 1,000 audio posts in the forum."
      ]],
      [10, "Celebrity", "Appears in so many contact lists that introductions are becoming a formality.", [
        "Be added to the contact lists of 25 users.",
        "Be added to the contact lists of 50 users.",
        "Be added to the contact lists of 75 users.",
        "Be added to the contact lists of 100 users."
      ]],
      [11, "Reviewer", "Leaves enough comments on other people's blogs to keep both authors and refresh buttons busy.", [
        "Write 20 approved comments on other users' blogs.",
        "Write 50 approved comments on other users' blogs.",
        "Write 100 approved comments on other users' blogs.",
        "Write 500 approved comments on other users' blogs."
      ]],
      [12, "Courier", "Keeps the noble art of writing messages alive, one conversation at a time.", [
        "Exchange 200 messages with at least 5 different users.",
        "Exchange 1,000 messages with at least 10 different users.",
        "Exchange 2,500 messages with at least 20 different users.",
        "Exchange 10,000 messages with at least 50 different users."
      ]],
      [13, "Feed Charmer", "Can make the feed stop scrolling and start liking.", [
        "Publish 10 feed posts that each receive likes from at least 3 different users.",
        "Publish 25 feed posts that each receive likes from at least 3 different users.",
        "Publish 100 feed posts that each receive likes from at least 3 different users.",
        "Publish 500 feed posts that each receive likes from at least 3 different users."
      ]],
      [14, "Conference Regular", "Has spent enough time in Elten conferences to know which chair squeaks.", [
        "Spend 8 hours in Elten conferences.",
        "Spend 24 hours in Elten conferences.",
        "Spend 120 hours in Elten conferences.",
        "Spend 600 hours in Elten conferences."
      ]],
      [15, "Talk of the Town", "Has been summoned into so many forum and blog conversations that appearing should probably come with a puff of smoke.", [
        "Receive 50 mentions in forum and blog conversations.",
        "Receive 250 mentions in forum and blog conversations.",
        "Receive 1,000 mentions in forum and blog conversations.",
        "Receive 5,000 mentions in forum and blog conversations."
      ]],
      [16, "Applause Magnet", "Turns recommended-group posts into small collections of raised thumbs.", [
        "Receive 50 likes on forum posts in recommended groups.",
        "Receive 250 likes on forum posts in recommended groups.",
        "Receive 1,000 likes on forum posts in recommended groups.",
        "Receive 2,500 likes on forum posts in recommended groups."
      ]],
      [17, "Threadsetter", "Starts the sort of threads people follow on purpose, not by accident.", [
        "Have your threads followed by at least 10 different users.",
        "Have your threads followed by at least 30 different users.",
        "Have your threads followed by at least 70 different users.",
        "Have your threads followed by at least 100 different users."
      ]]
    ].map do |id, name, description, levels|
      { id: id, name: name, description: description, levels: levels }.freeze
    end.freeze

    module_function

    def by_name(name, now: Time.now)
      definition = DEFINITIONS.find { |entry| entry[:name] == name.to_s }
      definition && materialize(definition, now)
    end

    def veteran_levels(now = Time.now)
      today = now.respond_to?(:to_date) ? now.to_date : Time.at(now.to_i).to_date
      years = today.year - STARTED_ON.year
      years -= 1 if ([today.month, today.day] <=> [STARTED_ON.month, STARTED_ON.day]) == -1
      (1..[years, 0].max).map do |year|
        "Be registered on Elten for #{year == 1 ? '1 year' : "#{year} years"}."
      end
    end

    def materialize(definition, now)
      levels = definition[:id] == 6 ? veteran_levels(now) : Array(definition[:levels]).dup
      definition.merge(levels: levels)
    end
    private_class_method :materialize
  end

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

    def name_for(language)
      language == "pl-PL" ? name : enname
    end

    def description_for(language)
      language == "pl-PL" ? description : endescription
    end

    def levels_for(language)
      language == "pl-PL" ? levels : enlevels
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

        honor = parse((payload["data"] || {})["honors"].to_a.first)
        honor&.name_for(language)
      end

      def list(client, user: nil)
        params = {}
        params["user"] = user if user != nil
        client.api_data("GET", "/api/v1/honors", params)["honors"].to_a.filter_map { |row| parse(row) }
      end

      def parse(row, klass: Honor)
        return nil unless row.is_a?(Hash)

        honor = klass.new(row["id"])
        english_name = english_value(row, "enname", "name")
        english_description = english_value(row, "endescription", "description")
        english_levels = array_value(row["enlevels"] || row["levels"])
        local = local_values(english_name, english_description, english_levels)
        honor.name = local[:name]
        honor.description = local[:description]
        honor.levels = local[:levels]
        honor.enname = english_name
        honor.endescription = english_description
        honor.enlevels = english_levels
        honor.level = row["level"].to_i
        honor
      end

      def set_main(client, honor)
        client.api_data("PUT", "/api/v1/honors/#{honor_id(honor)}/main")
        true
      end

      def award(client, user:, honor:, level: nil)
        params = { "user" => user }
        params["level"] = level.to_i unless level.nil?
        client.api_data("POST", "/api/v1/honors/#{honor_id(honor)}/awards", params)
        true
      end

      def users(client, honor)
        parse_users(client.api_data("GET", "/api/v1/honors/#{honor_id(honor)}/users")["users"])
      end

      private

      def local_values(name, description, levels)
        definition = HonorCatalog.by_name(name)
        return { name: name, description: description, levels: levels.dup } if definition.nil?

        local_description = definition[:description] == description ? definition[:description] : description
        local_levels = levels.each_with_index.map do |level, index|
          definition[:levels][index] == level ? definition[:levels][index] : level
        end
        { name: definition[:name], description: local_description, levels: local_levels }
      end

      def english_value(row, preferred, fallback)
        value = row[preferred].to_s
        value.empty? ? row[fallback].to_s : value
      end

      def array_value(value)
        return value.map(&:to_s) if value.is_a?(Array)
        return [] if value.to_s.empty?

        parsed = JSON.load(value.to_s)
        parsed.is_a?(Array) ? parsed.map(&:to_s) : []
      rescue JSON::ParserError
        []
      end

      def parse_users(rows)
        rows.to_a.map { |row| HonorUser.new(row["user"].to_s, row["level"].to_i) }
      end

      def honor_id(honor)
        honor.respond_to?(:id) ? honor.id : honor
      end
    end
  end
end
