#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "gettext/mo"
require "gettext/po"
require "gettext/po_parser"
require "json"

root = File.expand_path("..", __dir__)
locale = ARGV.fetch(0, File.join(root, "locale"))
output = ARGV.fetch(1, File.join(root, "resources", "translation-coverage.json"))
template = File.read(File.join(locale, "elten.pot"), encoding: "UTF-8").gsub("\r\n", "\n")
po = GetText::PO.new
GetText::POParser.new.parse(template, po)
messages = po.filter_map do |entry|
  next if entry.header? || entry.obsolete?
  key = [entry.msgctxt, entry.msgid].compact.join("\004")
  [entry.plural? ? "#{key}\0#{entry.msgid_plural}" : key, entry.plural?]
end
abort "The Elten translation template contains no messages" if messages.empty?

inputs = Digest::SHA256.new.update("elten.pot #{Digest::SHA256.hexdigest(template)}\n")
percentages = {"en-GB" => 100}
Dir.glob("*/LC_MESSAGES/elten.mo", base: locale).sort.each do |name|
  path = File.join(locale, name)
  inputs.update("#{name} #{Digest::SHA256.file(path).hexdigest}\n")
  mo = GetText::MO.open(path, "UTF-8")
  plural_count = mo[""].to_s[/^Plural-Forms:.*?\bnplurals\s*=\s*(\d+)/i, 1]&.to_i || 2
  translated = messages.count do |key, plural|
    forms = mo[key].to_s.split("\0", -1)
    forms.size == (plural ? plural_count : 1) && forms.none?(&:empty?)
  end
  percentages[name.split("/").first] = translated * 100 / messages.size
end
FileUtils.mkdir_p(File.dirname(output))
File.binwrite(output, JSON.pretty_generate({"inputs" => inputs.hexdigest, "percentages" => percentages}) + "\n")
