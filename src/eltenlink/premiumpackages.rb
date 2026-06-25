# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module PremiumPackages
    class << self
      def active_until(client)
        data = client.api_data("GET", "/api/v1/premium-packages")
        packages = {}
        data["packages"].to_a.each do |row|
          packages[row["package"].to_s] = row["totime"].to_i
        end
        packages
      end

      def test_code(client, code)
        client.api_data("GET", "/api/v1/premium-packages/code/#{code.to_s.urlenc}")["extension_time"].to_i
      end

      def use_code(client, package:, code:)
        client.api_data("POST", "/api/v1/premium-packages/codes", { "package" => package, "code" => code })
        true
      end
    end
  end
end
