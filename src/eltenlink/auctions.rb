# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class Auction
    attr_accessor :id, :name, :description, :price, :user, :creator, :totime
  end

  class AuctionsList
    attr_reader :auctions
    attr_accessor :enrolled

    def initialize(auctions, enrolled)
      @auctions = auctions
      @enrolled = enrolled
    end
  end

  module Auctions
    class << self
      def list(client)
        data = client.api_data("GET", "/api/v1/auctions")
        AuctionsList.new(parse_list(data["auctions"]), data["enrolled"] == true || data["enrolled"].to_s == "1")
      end

      def bid(client, auction:, price:, enroll: false)
        params = { "price" => price }
        params["enroll"] = 1 if enroll
        client.api_data("POST", "/api/v1/auctions/#{auction.to_i}/bids", params)
        true
      end

      def rules(client)
        client.api_data("GET", "/api/v1/auctions/rules")["text"].to_s
      end

      private

      def parse_list(rows)
        rows.to_a.map do |row|
          auction = Auction.new
          auction.id = row["id"].to_i
          auction.name = row["name"].to_s
          auction.description = row["description"].to_s
          auction.price = row["price"].to_i
          auction.user = row["user"].to_s
          auction.creator = row["creator"].to_s
          auction.totime = row["totime"].to_i
          auction
        end
      end
    end
  end
end
