# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Resources
    class << self
      def read(name, base: "resources")
        name = normalize_name(name)
        return nil if name == nil

        embedded = embedded_resources[name]
        return embedded.to_s if embedded != nil

        path = File.join(base.to_s, *name.split("/"))
        File.file?(path) ? File.binread(path) : nil
      rescue Exception => e
        Log.warning("Cannot read resource #{name}: #{e.class}: #{e.message}") if defined?(Log)
        nil
      end

      def keys(prefix = nil, base: "resources")
        prefix = normalize_prefix(prefix)
        result = []
        embedded_resources.keys.each do |key|
          key = normalize_name(key)
          result << key if key != nil && (prefix == nil || key.start_with?(prefix))
        end
        result.concat(file_keys(prefix, base))
        result.uniq.sort_by(&:downcase)
      rescue Exception => e
        Log.warning("Cannot list resources #{prefix}: #{e.class}: #{e.message}") if defined?(Log)
        []
      end

      private

      def embedded_resources
        resources = defined?($ELTEN_EMBEDDED_RESOURCES) ? $ELTEN_EMBEDDED_RESOURCES : nil
        resources.respond_to?(:[]) ? resources : {}
      end

      def file_keys(prefix, base)
        root = base.to_s
        scan_root = prefix == nil ? root : File.join(root, *prefix.delete_suffix("/").split("/"))
        return [] if !File.directory?(scan_root)

        keys = []
        Dir.glob(File.join(scan_root, "**", "*"), File::FNM_DOTMATCH).each do |path|
          next if File.directory?(path)
          relative = path.delete_prefix(root).sub(/\A[\/\\]/, "").tr("\\", "/")
          relative = normalize_name(relative)
          keys << relative if relative != nil && (prefix == nil || relative.start_with?(prefix))
        end
        keys
      end

      def normalize_name(name)
        value = name.to_s.tr("\\", "/").sub(/\A\.\//, "")
        return nil if value == "" || value.start_with?("/") || value.include?("../")
        value
      end

      def normalize_prefix(prefix)
        return nil if prefix == nil
        value = normalize_name(prefix)
        return nil if value == nil
        value.end_with?("/") ? value : value + "/"
      end
    end
  end
end
