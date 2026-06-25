# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  module Attachments
    @name_cache = {}

    class << self
      def names(client, attachments, names: [])
        return names if names != nil && names.size > 0
        attachments.dup.each do |attachment|
          if @name_cache[attachment] != nil
            names.push(@name_cache[attachment])
            next
          end
          info = client.api_payload("GET", "/api/v1/attachments/#{attachment.to_s.urlenc}")
          if !info.is_a?(Hash) || !info["success"]
            attachments.delete(attachment)
            next
          end
          name = (info["data"] || {})["name"].to_s
          names.push(name)
          @name_cache[attachment] = name
        end
        names
      end

      def name(client, attachment)
        names(client, [attachment], names: [])[0]
      end

      def send_file(client, file)
        data = File.binread(file)
        result = client.api_binary_data(
          "POST",
          "/api/v1/attachments",
          data,
          { "Content-Type" => "application/octet-stream", "X-Elten-Filename" => File.basename(file) }
        )
        result["id"].to_s
      end

      def download_url(attachment)
        Client.absolute_api_url("/api/v1/attachments/#{attachment.to_s.urlenc}/download")
      end
    end
  end
end
