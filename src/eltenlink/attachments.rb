# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  AttachmentInfo = Struct.new(:id, :name, :size, :url, :uploadtime, :uploader, keyword_init: true)

  module Attachments
    @name_cache = {}
    @info_cache = {}

    class << self
      def names(client, attachments, names: [])
        return names if names != nil && names.size > 0
        attachments.dup.each do |attachment|
          key = attachment.to_s
          if @name_cache[key] != nil
            names.push(@name_cache[key])
            next
          end
          attachment_info = info(client, attachment)
          if attachment_info == nil
            attachments.delete(attachment)
            next
          end
          names.push(attachment_info.name)
        end
        names
      end

      def name(client, attachment)
        names(client, [attachment], names: [])[0]
      end

      def info(client, attachment)
        key = attachment.to_s
        return @info_cache[key] if @info_cache.key?(key)

        payload = client.api_payload("GET", "/api/v1/attachments/#{key.urlenc}")
        return nil unless payload.is_a?(Hash) && payload["success"]

        attachment_info = build_info(payload["data"], key)
        @info_cache[key] = attachment_info
        @name_cache[key] = attachment_info.name
        attachment_info
      end

      def cache_infos(rows, ids: [])
        infos = ids.to_h { |id| [id.to_s, nil] }
        rows.each do |row|
          key = row["id"].to_s
          next if key.empty?

          infos[key] = build_info(row, key)
        end
        infos.each do |key, info|
          @info_cache[key] = info
          if info == nil
            @name_cache.delete(key)
          else
            @name_cache[key] = info.name
          end
        end
      end

      def send_file(client, file)
        File.open(file, "rb") do |input|
          result = client.api_binary_data(
            "POST",
            "/api/v1/attachments",
            input,
            { "Content-Type" => "application/octet-stream", "X-Elten-Filename" => File.basename(file) }
          )
          result["id"].to_s
        end
      end

      def download_url(attachment)
        Client.absolute_api_url("/api/v1/attachments/#{attachment.to_s.urlenc}/download")
      end

      private

      def build_info(data, fallback_id)
        data = {} unless data.is_a?(Hash)
        id = data["id"].to_s
        id = fallback_id if id == ""
        size = begin
          value = Integer(data["size"])
          value >= 0 ? value : nil
        rescue ArgumentError, TypeError
          nil
        end
        url = data["url"].to_s
        url = download_url(id) if url == ""
        AttachmentInfo.new(
          id: id,
          name: data["name"].to_s,
          size: size,
          url: url,
          uploadtime: data["uploadtime"].to_i,
          uploader: data["uploader"].to_s
        )
      end
    end
  end
end
