# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module Programs
  class PackageSources
    def initialize(root)
      @root = root
      ignore = File.join(root, ".eltenignore")
      @rules = []
      return unless File.file?(ignore) && !File.symlink?(ignore)

      File.foreach(ignore, encoding: "bom|utf-8", chomp: true) do |line|
        next if line.empty? || line.start_with?("#")
        include_path = line.start_with?("!")
        pattern = include_path ? line.delete_prefix("!") : line
        directory = pattern.end_with?("/")
        pattern = pattern.delete_suffix("/")
        @rules << [pattern.delete_prefix("/"), pattern.include?("/"), directory, include_path] unless pattern.empty?
      end
    end

    def excluded?(relative)
      return false if @rules.empty?
      parts = relative.tr("\\", "/").delete_prefix("./").split("/")
      excluded = false
      @rules.each do |pattern, anchored, directory, include_path|
        matched = parts.each_index.any? do |index|
          next false if directory && index == parts.size - 1
          path = anchored ? parts.take(index + 1).join("/") : parts[index]
          File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
        end
        excluded = !include_path if matched
      end
      excluded
    end

    def files
      @files ||= Dir.glob("**/*", base: @root).filter_map do |relative|
        path = File.join(@root, relative)
        path if File.file?(path) && !excluded?(relative)
      end
    end
  end
end
