# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module ConferenceResources
    class << self
      def list(client)
        data = client.api_data("GET", "/api/v1/conference-resources")
        data["resources"].to_a.map do |row|
          id = row["id"].to_s
          url = row["url"].to_s
          url = "/api/v1/conference-resources/#{id.urlenc}/download" if url.empty?
          { "resid" => id, "name" => row["name"].to_s, "owner" => row["owner"].to_s, "url" => Client.absolute_api_url(url) }
        end
      end

      def add(client, name, data)
        client.api_binary_data(
          "POST",
          "/api/v1/conference-resources",
          data,
          { "Content-Type" => "application/octet-stream" },
          { "name" => name }
        )
        true
      end

      def delete(client, resource_id)
        client.api_data("DELETE", "/api/v1/conference-resources/#{resource_id.to_s.urlenc}")
        true
      end

      def download_url(resource_id)
        Client.absolute_api_url("/api/v1/conference-resources/#{resource_id.to_s.urlenc}/download")
      end
    end
  end
end
