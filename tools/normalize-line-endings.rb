#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

ROOT = File.expand_path("..", __dir__)

CHECK_ONLY = ARGV.delete("--check") != nil

PATTERNS = [
  File.join(ROOT, "*.rb"),
  File.join(ROOT, "tools", "**", "*.rb"),
  File.join(ROOT, "src", "**", "*.rb"),
  File.join(ROOT, "launcher", "**", "*.h"),
  File.join(ROOT, "launcher", "**", "*.c"),
  File.join(ROOT, "launcher", "**", "*.cpp")
].freeze

def source_files
  PATTERNS.each_with_object(Set.new) do |pattern, files|
    Dir.glob(pattern) { |path| files << File.expand_path(path) if File.file?(path) }
  end.to_a.sort
end

def normalize_line_endings(path, check_only:)
  data = File.binread(path)
  normalized = data.gsub(/\r\n?/, "\n")
  changed = normalized != data
  File.binwrite(path, normalized) if changed && !check_only
  changed
end

changed = []

source_files.each do |path|
  changed << path if normalize_line_endings(path, check_only: CHECK_ONLY)
end

if CHECK_ONLY && changed.any?
  warn "Files with non-LF line endings:"
  changed.each { |path| warn "  #{path.sub(ROOT + File::SEPARATOR, "")}" }
  exit 1
end

action = CHECK_ONLY ? "checked" : "normalized"
puts "#{source_files.size} files #{action}; #{changed.size} changed."
