# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper, Arkadiusz Koziol
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module LinuxSystemNative
  class << self
    def available?
      true
    end

    def current_locale_name
      locale = ENV["LC_ALL"].to_s
      locale = ENV["LC_MESSAGES"].to_s if locale == ""
      locale = ENV["LANG"].to_s if locale == ""
      locale.to_s.split(".").first.to_s
    rescue Exception
      ""
    end

    def open_url(value)
      return false if value.to_s == ""
      pid = Process.spawn("xdg-open", value.to_s, [:out, :err] => File::NULL)
      Process.detach(pid)
      true
    rescue Exception
      false
    end
  end
end

module EltenSystemHelpers
  NATIVE_OPEN_COMMAND = "__elten_native_open__" unless const_defined?(:NATIVE_OPEN_COMMAND)

  # System libraries that ship with versioned sonames (no -dev symlink guaranteed).
  SYSTEM_LIBRARY_SONAMES = {
    "sdl2" => ["libSDL2-2.0.so.0", "libSDL2.so"]
  }.freeze unless const_defined?(:SYSTEM_LIBRARY_SONAMES)

  # The codecs we ship are stored under their soname rather than a flat name,
  # because the audio server's libsndfile asks for them by that name and finds
  # our directory first through LD_LIBRARY_PATH. Naming the files anything else
  # leaves it loading the distribution's copy alongside ours, and two versions
  # of libopus in one process crash the moment an encoder is created. The names
  # here are what we ask for; the files answer to what the loader asks for.
  BUNDLED_LIBRARY_SONAMES = {
    "ogg" => ["libogg.so.0"],
    "libogg" => ["libogg.so.0"],
    "opus" => ["libopus.so.0"],
    "libopus" => ["libopus.so.0"],
    "vorbis" => ["libvorbis.so.0"],
    "libvorbis" => ["libvorbis.so.0"],
    "vorbisenc" => ["libvorbisenc.so.2"],
    "libvorbisenc" => ["libvorbisenc.so.2"],
    "speexdsp" => ["libspeexdsp.so.1"],
    "libspeexdsp" => ["libspeexdsp.so.1"],
    "zstd" => ["libzstd.so.1"],
    "libzstd" => ["libzstd.so.1"],
    "lzma" => ["liblzma.so.5"],
    "liblzma" => ["liblzma.so.5"]
  }.freeze unless const_defined?(:BUNDLED_LIBRARY_SONAMES)

  class << self
    def current_lcid
      0
    end

    def current_locale_name
      locale = LinuxSystemNative.current_locale_name
      locale = ENV["LANG"].to_s.split(".").first if locale.to_s == ""
      locale.to_s
    rescue Exception
      ""
    end

    # First day of the week as 0=Sunday..6=Saturday, matching what the shared
    # calendar grid expects (and the Windows/macOS implementations return).
    #
    # glibc exposes this through the LC_TIME locale, which Ruby's stdlib cannot
    # read, so ask the `locale` tool. Its two fields need combining: week-1stday
    # is a reference date (conventionally 1997-11-30, a Sunday) and first_weekday
    # is a 1-based offset from it, so the real first day is that date shifted by
    # first_weekday-1 and taken as a weekday. Memoised because the grid asks once
    # per day cell and this shells out.
    def first_day_of_week
      return @first_day_of_week if defined?(@first_day_of_week)
      require "date"
      out = `locale first_weekday week-1stday 2>/dev/null`
      first_weekday, week_1stday = out.lines.map(&:strip)
      offset = first_weekday.to_i
      reference = Date.strptime(week_1stday.to_s, "%Y%m%d")
      day = (reference + (offset - 1)).wday
      @first_day_of_week = (0..6).include?(day) ? day : 1
    rescue Exception
      @first_day_of_week = 1
    end

    def logical_drives
      drives = ["/"]
      ["/media", "/mnt", File.join(home_dir, ".local", "share", "gvfs")].each do |volumes|
        next unless File.directory?(volumes)
        Dir.children(volumes).sort.each do |entry|
          path = File.join(volumes, entry)
          drives << path if File.directory?(path)
        end
      rescue Exception
      end
      drives.uniq
    rescue Exception
      ["/"]
    end

    def appdata_dir
      xdg_dir("XDG_DATA_HOME", ".local", "share")
    end

    def user_dir
      home_dir
    end

    def documents_dir
      xdg_user_dir("DOCUMENTS") || File.join(home_dir, "Documents")
    end

    def desktop_dir
      xdg_user_dir("DESKTOP") || File.join(home_dir, "Desktop")
    end

    def music_dir
      xdg_user_dir("MUSIC") || File.join(home_dir, "Music")
    end

    def command_line_join(parts)
      require "shellwords"
      Shellwords.join(parts.map(&:to_s))
    end

    def set_dll_directory(_path)
      false
    end

    def readable_memory?(address, length)
      address.to_i != 0 && length.to_i > 0
    end

    def open_url(url)
      LinuxSystemNative.open_url(url)
    rescue Exception
      false
    end

    def locale_compare(a, b)
      return a <=> b if !a.is_a?(String) || !b.is_a?(String)
      locale_sort_key(a) <=> locale_sort_key(b)
    rescue Exception
      a.to_s.downcase <=> b.to_s.downcase
    end

    def locale_sort_key(value)
      return value if !value.is_a?(String)
      value.to_s.unicode_normalize(:nfd).downcase
    rescue Exception
      value.to_s.downcase
    end

    def protect_data(_data, _entropy = nil)
      "".b
    end

    def unprotect_data(_data, _entropy = nil)
      nil
    end

    def file_version_info(_file, _verinfo)
      nil
    end

    def platform_os
      "linux"
    end

    def platform_target
      cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
      arch = case cpu
             when /aarch64|arm64/ then "arm64"
             when /i[3-6]86/ then "x86"
             when /arm/ then "armhf"
             else "x64"
             end
      "linux-#{arch}"
    rescue Exception
      "linux-x64"
    end

    def runtime_directory_name(architecture)
      "linux-#{architecture}"
    end

    def configure_library_search(dirs, _arch_bin)
      path_key = ENV.key?("PATH") ? "PATH" : "Path"
      current_path = ENV[path_key] || ""
      ENV[path_key] = (dirs + current_path.split(":")).reject { |entry| entry.to_s == "" }.uniq.join(":")

      current_ld = ENV["LD_LIBRARY_PATH"].to_s
      ENV["LD_LIBRARY_PATH"] = (dirs + current_ld.split(":")).reject { |entry| entry.to_s == "" }.uniq.join(":")
      true
    rescue Exception
      false
    end

    def library_candidates(name, root:, bin_root:, arch_bin:, legacy_bin:, dll_directories:)
      raw = name.to_s.tr("\\", "/")
      variants = library_variants(raw)
      candidates = []
      variants.each do |variant|
        if absolute_path?(variant)
          candidates << variant
          next
        end

        if variant.to_s.downcase.start_with?("bin/")
          suffix = variant[4..-1]
          lower = suffix.downcase
          if lower.start_with?("linux-x64/", "linux-x86/", "linux-arm64/", "linux-armhf/", "osx/", "windows-x64/", "windows-x86/", "windows-arm64/")
            candidates << File.expand_path(variant, root)
          else
            candidates << File.join(arch_bin, suffix)
            candidates << File.join(legacy_bin, suffix)
          end
        end

        candidates << variant
        candidates << File.expand_path(variant, root)
        candidates << File.expand_path(variant, Dir.pwd)

        base = File.basename(variant)
        dll_directories.each do |dir|
          candidates << File.join(dir, base)
        end
      end
      candidates.uniq
    end

    def library_variants(raw)
      raw = raw.to_s.tr("\\", "/")
      dir = File.dirname(raw)
      base = File.basename(raw)
      stem = base.sub(/\.(dll|dylib|so)\z/i, "")
      names = [base]
      bundled = BUNDLED_LIBRARY_SONAMES[stem.downcase]
      names.concat(bundled) if bundled != nil
      sonames = SYSTEM_LIBRARY_SONAMES[stem.downcase]
      names.concat(sonames) if sonames != nil
      names << "#{stem}.so"
      names << "lib#{stem}.so" unless stem.start_with?("lib")
      names.uniq.map { |name| dir == "." ? name : File.join(dir, name) }
    end

    def library_candidate_available?(root, candidate)
      File.file?(File.join(root, candidate))
    end

    def dlopen_library(file, name)
      preload_library_dependencies(name) do |dependency|
        yield dependency if block_given?
      end
      flags = 0
      flags |= Fiddle::RTLD_NOW if defined?(Fiddle::RTLD_NOW)
      flags |= Fiddle::RTLD_GLOBAL if defined?(Fiddle::RTLD_GLOBAL)
      flags = nil if flags == 0
      begin
        open_handle(file, flags)
      rescue Fiddle::DLError => error
        retry_missing_library_dependency(error) do |dependency|
          yield dependency if block_given?
        end
        # When the resolved path is not a real file, fall back to letting the
        # dynamic loader resolve the library by soname (system libraries in
        # /usr/lib etc.), mirroring how the Windows loader searches PATH.
        soname_candidates(file, name).each do |candidate|
          return open_handle(candidate, flags)
        rescue Fiddle::DLError
          next
        end
        open_handle(file, flags)
      end
    end

    def native_extension
      ".so"
    end

    def opus_library_name
      "opus"
    end

    def speexdsp_library_name
      "libspeexdsp"
    end

    def vst2_extensions
      [".so"]
    end

    def obsolete_extra_entries
      []
    end

    def legacy_installation_files
      []
    end

    def legacy_installation_warning
      ["", ""]
    end

    def bass_abi(_architecture)
      Fiddle::Function::DEFAULT
    end

    def os_version
      release = "/etc/os-release"
      return "" unless File.file?(release)
      text = File.binread(release)
      name = text[/^PRETTY_NAME="?([^"\n]+)"?/, 1].to_s
      name = text[/^NAME="?([^"\n]+)"?/, 1].to_s if name == ""
      [name, RbConfig::CONFIG["host_os"].to_s].reject(&:empty?).join(" ")
    rescue Exception
      ""
    end

    def environment_architecture
      RbConfig::CONFIG["host_cpu"].to_s
    rescue Exception
      ""
    end

    def original_process_arguments
      []
    end

    def embedded_executable_path(root, _architecture)
      File.expand_path("elten", root)
    end

    def autostart_executable_path(default_path)
      default_path.to_s
    end

    def autostart_executable?(_path)
      false
    end

    def autostart_command(path, hidden: false)
      command_line_join([path.to_s, hidden ? "--hidden" : nil].compact)
    end

    def sync_autostart(_enabled, _command)
      false
    end

    def prepare_os_microphone
      true
    end

    def beta_version_creation_supported?
      false
    end

    def autologin_key_encryption_supported?
      false
    end

    def installer_extension
      "run"
    end

    def installer_filename
      "elten.run"
    end

    def installer_path(data_dir)
      EltenPath.join(data_dir, installer_filename)
    end

    # The downloaded file is the same self-extracting installer distributed to
    # users. It selects the current architecture, verifies its embedded payload
    # and handles privilege elevation, so updates and fresh installs exercise
    # exactly the same path.
    def update_install_command(installer, silent: true)
      script = <<~'SH'
        sleep 2
        installer="$1"
        chmod 0700 "$installer" || exit 1
        if [ "$2" = "1" ]; then
          "$installer" --silent || exit 1
        else
          "$installer" || exit 1
        fi
        [ -x /opt/elten/elten ] && exec /opt/elten/elten
      SH
      ["/bin/sh", "-c", script, "elten-update", installer.to_s, silent ? "1" : "0"]
    end

    private

    def open_handle(file, flags)
      flags == nil ? Fiddle::Handle.new(file) : Fiddle::Handle.new(file, flags)
    end

    def soname_candidates(file, name)
      candidates = []
      candidates.concat(library_variants(name.to_s)) if name.to_s != "" && !absolute_path?(file.to_s)
      candidates << File.basename(file.to_s) if !absolute_path?(file.to_s)
      candidates.reject { |candidate| candidate.to_s == "" || candidate == file }.uniq
    rescue Exception
      []
    end

    def home_dir
      Dir.home
    rescue Exception
      "."
    end

    # Per the XDG spec an unset variable, an empty one and a relative path all
    # mean "use the default" - the last one because a relative base directory
    # would resolve against whatever the current directory happens to be.
    def xdg_dir(variable, *default_parts)
      value = ENV[variable].to_s
      return value if value.start_with?("/")
      File.join(home_dir, *default_parts)
    rescue Exception
      File.join(home_dir, *default_parts)
    end

    def xdg_user_dir(name)
      config = xdg_dir("XDG_CONFIG_HOME", ".config")
      file = File.join(config, "user-dirs.dirs")
      return nil unless File.file?(file)
      line = File.foreach(file).find { |entry| entry =~ /\AXDG_#{name}_DIR=/ }
      return nil if line == nil
      value = line.split("=", 2)[1].to_s.strip.sub(/\A"/, "").sub(/"\z/, "")
      value = value.sub(/\A\$HOME/, home_dir)
      value == "" ? nil : value
    rescue Exception
      nil
    end

    def absolute_path?(path)
      path =~ /\A[A-Za-z]:[\\\/]/ || path.start_with?("//") || path.start_with?("\\\\") || path.start_with?("/")
    end

    def preload_library_dependencies(name)
      dependencies_for(name).each do |dependency|
        yield dependency if block_given?
      rescue Exception
      end
    end

    def dependencies_for(name)
      stem = File.basename(name.to_s.tr("\\", "/")).sub(/\.(dll|dylib|so)\z/i, "").downcase
      stem = stem[3..-1] if stem.start_with?("lib")
      dependencies = []
      dependencies << "bass" if stem.start_with?("bass") && stem != "bass"
      dependencies << "ogg" if ["vorbis", "vorbisenc", "vorbisfile"].include?(stem)
      dependencies << "ogg" if stem == "opus"
      dependencies
    end

    def retry_missing_library_dependency(error)
      missing = error.message.to_s[/cannot open shared object file[^\n]*?([A-Za-z0-9_.+-]+\.so[0-9.]*)/, 1]
      missing ||= error.message.to_s[/([A-Za-z0-9_.+-]+\.so[0-9.]*)/, 1]
      return if missing.to_s == ""
      missing_dependency_candidates(missing).each do |candidate|
        yield candidate if block_given?
        return
      rescue Exception
      end
    end

    def missing_dependency_candidates(missing)
      base = File.basename(missing.to_s)
      names = [base]
      names << base.sub(/\.so[0-9.]*\z/, ".so")
      names.uniq
    end
  end
end
