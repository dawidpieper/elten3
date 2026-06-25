# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Payments
    class << self
      def prices(client)
        client.api_data("GET", "/api/v1/payments/prices")
      end

      def methods(client, currency:, language:)
        data = client.api_data("GET", "/api/v1/payments/methods", { "currency" => currency, "lang" => language })
        data["methods"].is_a?(Array) ? data["methods"] : []
      end

      def pay(client, method:, package: nil, currency: nil, time: nil, amount: nil, code: nil)
        params = { "method" => method }
        params["package"] = package if package != nil
        params["currency"] = currency if currency != nil
        params["time"] = time if time != nil
        params["amount"] = amount if amount != nil
        params["code"] = code if code != nil
        data = client.api_data("POST", "/api/v1/payments", params)
        data["link"].to_s
      end
    end
  end
end
