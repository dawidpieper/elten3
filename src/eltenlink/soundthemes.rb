# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class SoundThemeInfo
    attr_accessor :name, :file, :url, :size, :stamp, :user, :time, :count
  end

  module SoundThemes
    class << self
      def list(client)
        data = client.api_data("GET", "/api/v1/sound-themes")
        data["themes"].to_a.map do |row|
          theme = SoundThemeInfo.new
          theme.file = row["file"].to_s
          theme.url = Client.absolute_api_url(row["url"].to_s.empty? ? "/api/v1/sound-themes/#{theme.file.sub(/\.elsnd\z/i, "").urlenc}/download" : row["url"].to_s)
          theme.size = row["size"].to_i
          theme.name = row["name"].to_s
          theme.stamp = row["stamp"].to_s
          theme.user = row["user"].to_s
          theme.time = row["time"].to_i
          theme.count = row["count"].to_i
          theme
        end
      end

      def delete(client, theme_id)
        client.api_data("DELETE", "/api/v1/sound-themes/#{theme_id.to_s.urlenc}")
        true
      end

      def upload(client, theme_id, data)
        client.api_binary_data(
          "PUT",
          "/api/v1/sound-themes/#{theme_id.to_s.urlenc}",
          data,
          { "Content-Type" => "application/octet-stream" }
        )
        true
      end

      def download_url(theme)
        return theme.url if theme.respond_to?(:url) && theme.url.to_s != ""

        file = theme.respond_to?(:file) ? theme.file.to_s : theme.to_s
        id = file.sub(/\.elsnd\z/i, "")
        Client.absolute_api_url("/api/v1/sound-themes/#{id.urlenc}/download")
      end
    end
  end
end
