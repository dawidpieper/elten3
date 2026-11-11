# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  AttachmentInfo = Struct.new(:id, :name, :size, :url, :uploadtime, :uploader, keyword_init: true)

  module Attachments
    CacheLimit = 1024
    @info_cache = {}
    @cache_mutex = Mutex.new

    class << self
      def names(client, attachments, names: [])
        return names if names != nil && names.size > 0
        attachments.dup.each do |attachment|
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
        cached, attachment_info = cached_info(key)
        return attachment_info if cached

        payload = client.api_payload("GET", "/api/v1/attachments/#{key.urlenc}")
        return nil unless payload.is_a?(Hash) && payload["success"]

        attachment_info = build_info(payload["data"], key)
        store_info(key, attachment_info)
      end

      def cache_infos(rows, ids: [])
        infos = ids.to_h { |id| [id.to_s, nil] }
        rows.each do |row|
          key = row["id"].to_s
          next if key.empty?

          infos[key] = build_info(row, key)
        end
        store_infos(infos)
        infos
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

      private

      def cached_info(key)
        @cache_mutex.synchronize do
          return [false, nil] unless @info_cache.key?(key)
          attachment_info = @info_cache.delete(key)
          @info_cache[key] = attachment_info
          [true, attachment_info]
        end
      end

      def store_info(key, attachment_info)
        @cache_mutex.synchronize do
          @info_cache.delete(key)
          @info_cache[key] = attachment_info
          @info_cache.shift while @info_cache.size > CacheLimit
        end
        attachment_info
      end

      def store_infos(infos)
        @cache_mutex.synchronize do
          infos.each do |key, attachment_info|
            @info_cache.delete(key)
            @info_cache[key] = attachment_info
          end
          @info_cache.shift while @info_cache.size > CacheLimit
        end
      end

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
