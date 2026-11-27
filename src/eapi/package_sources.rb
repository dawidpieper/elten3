# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module Programs
  class PackageSources
    SOUND_EXTENSIONS = %w[.ogg .opus .wav .wave .mp3 .flac .aac .m4a .wma .spx .webm].freeze

    def self.sound?(relative)
      relative.start_with?("Audio/") && SOUND_EXTENSIONS.include?(File.extname(relative).downcase)
    end

    def self.language_code(relative)
      ext = File.extname(relative)
      return unless relative.start_with?("locale/") && ext.downcase == ".mo"
      code = File.basename(relative, ext)[0, 2]
      code.upcase if code.match?(/\A[a-zA-Z]{2}\z/)
    end

    def initialize(root, &accept_file)
      @root = File.expand_path(root)
      @accept_file = accept_file
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
      return @files if @files
      @excluded_files = []
      @files = Dir.glob("**/*", base: @root).filter_map do |relative|
        path = File.join(@root, relative)
        next unless File.file?(path) && (!@accept_file || @accept_file.call(path))
        if excluded?(relative)
          @excluded_files << relative
          next
        end
        path
      end
    end

    def excluded_required_asset?(type, name)
      return false if @rules.empty?
      files
      case type
      when "files"
        return @excluded_files.include?(name.tr("\\", "/").delete_prefix("./"))
      when "sounds"
        ext = File.extname(name).downcase
        names = [name]
        names << File.basename(name, ext) unless ext.empty?
        matches = ->(path) { self.class.sound?(path) && names.include?(File.basename(path, File.extname(path).downcase)) }
      when "languages"
        code = name[0, 2].upcase
        matches = ->(path) { self.class.language_code(path) == code }
      else
        return false
      end
      @excluded_files.any?(&matches) && @files.none? { |path| matches.call(path.delete_prefix(@root + "/")) }
    end
  end
end
