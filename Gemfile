source "https://rubygems.org"

# Nokogiri has no Windows x86/arm64 native gem, so source builds need the
# same MiniPortile MSYS path shim that the CMake runtime build uses.
nokogiri_msys_patch = File.expand_path("patchs/mini_portile_msys_path_patch.rb", __dir__)
if Gem.win_platform?
  nokogiri_msys_patch_dir = File.dirname(nokogiri_msys_patch)
  rubylib_paths = ENV["RUBYLIB"].to_s.split(File::PATH_SEPARATOR)
  unless rubylib_paths.include?(nokogiri_msys_patch_dir)
    ENV["RUBYLIB"] = ([nokogiri_msys_patch_dir] + rubylib_paths).reject(&:empty?).join(File::PATH_SEPARATOR)
  end

  nokogiri_msys_patch_option = "-rmini_portile_msys_path_patch"
  rubyopt_options = ENV["RUBYOPT"].to_s.split
  unless rubyopt_options.include?(nokogiri_msys_patch_option)
    ENV["RUBYOPT"] = ([nokogiri_msys_patch_option] + rubyopt_options).join(" ")
  end
end

gem "base62", "1.0.0"
gem "base64", "0.3.0"
gem "bigdecimal", "3.3.1"
gem "nokogiri", "1.19.4"
gem "rubyzip", "3.2.2"
gem "fiddle", "1.1.8"

platforms :windows do
  gem "win32ole", "1.9.2"
end
gem "http-2", "1.1.3"
gem "ostruct", "0.6.3"
gem "ruby-xz", "1.0.3"
gem "sqlite3", "2.9.5"
gem "zstd-ruby", "2.0.6"
