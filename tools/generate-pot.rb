#!/usr/bin/env ruby
# frozen_string_literal: true

require "gettext/tools/xgettext"
require "tempfile"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "locale", "elten.pot")

Dir.chdir(__dir__) do
  sources = Dir["../src/**/*.rb"]

  Tempfile.create(["elten", ".pot"], ROOT) do |temporary|
    temporary.close

    GetText::Tools::XGetText.run(
      "--output=#{temporary.path}",
      "--package-name=Elten",
      "--package-version=3.0",
      "--msgid-bugs-address=dawidpieper@o2.pl",
      "--copyright-holder=Dawid Pieper",
      "--copyright-year=#{Time.now.year}",
      *sources
    )

    File.binwrite(OUTPUT, File.binread(temporary.path))
  end
end
