# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

unless defined?(Fiddle)
  verbose = $VERBOSE
  $VERBOSE = nil
  begin
    require "fiddle"
  ensure
    $VERBOSE = verbose
  end
end

module EltenSystemHelpers
  ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
  INT = Fiddle::TYPE_INT
  PTR = Fiddle::TYPE_VOIDP
  KERNEL32 = Fiddle.dlopen("kernel32.dll")
  CRYPT32 = Fiddle.dlopen("crypt32.dll")
  SHELL32 = Fiddle.dlopen("shell32.dll")
  VERSION_DLL = Fiddle.dlopen("version.dll")
  SIZE_T = EltenWin32::POINTER_SIZE == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
  GET_USER_DEFAULT_LCID = Fiddle::Function.new(KERNEL32["GetUserDefaultLCID"], [], INT, ABI)
  GET_LOCALE_INFO_W = Fiddle::Function.new(KERNEL32["GetLocaleInfoW"], [INT, INT, PTR, INT], INT, ABI)
  GET_LOGICAL_DRIVE_STRINGS = Fiddle::Function.new(KERNEL32["GetLogicalDriveStringsW"], [INT, PTR], INT, ABI)
  SET_DLL_DIRECTORY = Fiddle::Function.new(KERNEL32["SetDllDirectoryW"], [PTR], INT, ABI)
  IS_BAD_READ_PTR = Fiddle::Function.new(KERNEL32["IsBadReadPtr"], [PTR, SIZE_T], INT, ABI)
  COMPARE_STRING_W = Fiddle::Function.new(KERNEL32["CompareStringW"], [INT, INT, PTR, INT, PTR, INT], INT, ABI)
  LCMAP_STRING_W = Fiddle::Function.new(KERNEL32["LCMapStringW"], [INT, INT, PTR, INT, PTR, INT], INT, ABI)
  LOCAL_FREE = Fiddle::Function.new(KERNEL32["LocalFree"], [PTR], PTR, ABI)
  SH_GET_FOLDER_PATH = Fiddle::Function.new(SHELL32["SHGetFolderPathW"], [PTR, INT, PTR, INT, PTR], INT, ABI)
  SHELL_EXECUTE = Fiddle::Function.new(SHELL32["ShellExecuteW"], [PTR, PTR, PTR, PTR, PTR, INT], PTR, ABI)
  CRYPT_PROTECT_DATA = Fiddle::Function.new(CRYPT32["CryptProtectData"], [PTR, PTR, PTR, PTR, PTR, INT, PTR], INT, ABI)
  CRYPT_UNPROTECT_DATA = Fiddle::Function.new(CRYPT32["CryptUnprotectData"], [PTR, PTR, PTR, PTR, PTR, INT, PTR], INT, ABI)
  GET_FILE_VERSION_INFO_SIZE = Fiddle::Function.new(VERSION_DLL["GetFileVersionInfoSizeW"], [PTR, PTR], INT, ABI)
  GET_FILE_VERSION_INFO = Fiddle::Function.new(VERSION_DLL["GetFileVersionInfoW"], [PTR, INT, INT, PTR], INT, ABI)
  VER_QUERY_VALUE = Fiddle::Function.new(VERSION_DLL["VerQueryValueW"], [PTR, PTR, PTR, PTR], INT, ABI)
  LOCALE_SNAME = 0x5C
  LOCALE_USER_DEFAULT = 0x400
  CSIDL_APPDATA = 0x001A
  CSIDL_PROFILE = 0x0028
  CSIDL_PERSONAL = 0x0005
  CSIDL_DESKTOPDIRECTORY = 0x0010
  CSIDL_MYMUSIC = 0x000D
  SHGFP_TYPE_CURRENT = 0
  LCMAP_SORTKEY = 0x400
  NORM_IGNORECASE = 0x1
  NORM_IGNOREKANATYPE = 0x10000
  NORM_IGNOREWIDTH = 0x20000
  SORT_FLAGS = LCMAP_SORTKEY | NORM_IGNORECASE | 8

  class << self
    def current_lcid
      GET_USER_DEFAULT_LCID.call
    rescue Exception
      0
    end

    def current_locale_name
      lcid = current_lcid
      return "" if lcid.to_i == 0
      buffer = "\0" * 170
      length = GET_LOCALE_INFO_W.call(lcid, LOCALE_SNAME, buffer, buffer.bytesize / 2)
      return "" if length.to_i <= 0
      from_wide(buffer.byteslice(0, (length - 1) * 2).to_s)
    rescue Exception
      ""
    end

    def logical_drives
      buffer = "\0" * 2048
      length = GET_LOGICAL_DRIVE_STRINGS.call(buffer.bytesize / 2, buffer)
      return [] if length.to_i <= 0
      text = from_wide(buffer.byteslice(0, length * 2).to_s)
      text.split("\0").map { |drive| drive.end_with?("\\") ? drive[0...-1] : drive }.reject { |drive| drive == "" }
    rescue Exception
      []
    end

    def appdata_dir
      known_folder(CSIDL_APPDATA) || fallback_env("APPDATA") || File.join(home_dir, "AppData", "Roaming")
    end

    def user_dir
      known_folder(CSIDL_PROFILE) || fallback_env("USERPROFILE") || home_dir
    end

    def documents_dir
      known_folder(CSIDL_PERSONAL) || File.join(user_dir, "Documents")
    end

    def desktop_dir
      known_folder(CSIDL_DESKTOPDIRECTORY) || File.join(user_dir, "Desktop")
    end

    def music_dir
      known_folder(CSIDL_MYMUSIC) || File.join(user_dir, "Music")
    end

    def command_line_join(parts)
      parts.map { |part| command_line_quote(part) }.join(" ")
    end

    def set_dll_directory(path)
      return false if path.to_s == ""
      SET_DLL_DIRECTORY.call(wide(path)) != 0
    rescue Exception
      false
    end

    def readable_memory?(address, length)
      address = address.to_i
      length = length.to_i
      return false if address == 0 || length <= 0
      IS_BAD_READ_PTR.call(address, length) == 0
    rescue Exception
      false
    end

    def open_url(url)
      return false if url.to_s == ""
      SHELL_EXECUTE.call(nil, wide("open"), wide(url), nil, nil, 1).to_i > 32
    rescue Exception
      false
    end

    def locale_compare(a, b)
      return a <=> b if !a.is_a?(String) || !b.is_a?(String)
      left = wide(a.downcase)
      right = wide(b.downcase)
      COMPARE_STRING_W.call(LOCALE_USER_DEFAULT, NORM_IGNOREKANATYPE | 8, left, left.bytesize / 2, right, right.bytesize / 2) - 2
    rescue Exception
      a.to_s.downcase <=> b.to_s.downcase
    end

    def locale_sort_key(value)
      return value if !value.is_a?(String)
      text = wide(value.downcase)
      size = LCMAP_STRING_W.call(LOCALE_USER_DEFAULT, SORT_FLAGS, text, text.bytesize / 2, nil, 0)
      return value.downcase if size.to_i <= 0
      key = ("\0" * size.to_i).b
      LCMAP_STRING_W.call(LOCALE_USER_DEFAULT, SORT_FLAGS, text, text.bytesize / 2, key, key.bytesize)
      key
    rescue Exception
      value.to_s.downcase
    end

    def protect_data(data, entropy = nil)
      pin = EltenWin32.data_blob(data)
      pout = EltenWin32.data_blob
      pcode = entropy == nil ? nil : EltenWin32.data_blob(entropy)
      return "".b if CRYPT_PROTECT_DATA.call(pin, nil, pcode, nil, nil, 0, pout) == 0
      blob_bytes(pout)
    end

    def unprotect_data(data, entropy = nil)
      pin = EltenWin32.data_blob(data)
      pout = EltenWin32.data_blob
      pcode = entropy == nil ? nil : EltenWin32.data_blob(entropy)
      return nil if CRYPT_UNPROTECT_DATA.call(pin, nil, pcode, nil, nil, 0, pout) == 0
      result = blob_bytes(pout)
      result == "" ? nil : result
    rescue Exception
      nil
    end

    def file_version_info(file, verinfo)
      handle = EltenWin32.dword_buffer
      size = GET_FILE_VERSION_INFO_SIZE.call(wide(file), handle)
      return nil if size.to_i == 0
      version_info = "\0" * size.to_i
      GET_FILE_VERSION_INFO.call(wide(file), 0, size.to_i, version_info)
      pointer = EltenWin32.pointer_buffer
      length = EltenWin32.dword_buffer
      VER_QUERY_VALUE.call(version_info, wide("\\StringFileInfo\\040904b0\\#{verinfo}"), pointer, length)
      strlen = EltenWin32.dword_value(length)
      address = EltenWin32.pointer_value(pointer)
      return nil if address.to_i == 0 || strlen.to_i <= 0
      from_wide(Fiddle::Pointer.new(address.to_i)[0, strlen.to_i * 2])
    rescue Exception
      nil
    end

    def platform_os
      "windows"
    end

    def platform_target
      cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
      arch = cpu =~ /arm64|aarch64/ ? "arm64" : (cpu.include?("64") ? "x64" : "x86")
      "windows-#{arch}"
    rescue Exception
      "windows-x86"
    end

    def runtime_directory_name(architecture)
      "windows-#{architecture}"
    end

    def configure_library_search(dirs, arch_bin)
      path_key = ENV.key?("PATH") ? "PATH" : "Path"
      current_path = ENV[path_key] || ""
      ENV[path_key] = (dirs + current_path.split(";")).reject { |entry| entry.to_s == "" }.uniq.join(";")
      set_dll_directory(arch_bin) if File.directory?(arch_bin)
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
          if lower.start_with?("windows-x64/", "windows-x86/", "windows-arm64/", "osx/")
            candidates << File.expand_path(variant, root)
          elsif lower.start_with?("x64/", "x86/", "arm64/")
            legacy_arch, rest = suffix.split("/", 2)
            candidates << File.join(bin_root, "windows-#{legacy_arch}", rest) if rest.to_s != ""
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
      names = [base, "#{stem}.dll"]
      names.uniq.map { |name| dir == "." ? name : File.join(dir, name) }
    end

    def library_candidate_available?(root, candidate)
      File.file?(File.join(root, candidate)) || File.file?(File.join(root, "#{candidate}.dll"))
    end

    def dlopen_library(file, _name)
      Fiddle.dlopen(file)
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
      [".dll"]
    end

    def obsolete_extra_entries
      ["youtube-dl.exe", "Calibre Portable"]
    end

    def legacy_installation_files
      ["ffmpeg.exe", "avcodec58.dll", "avdevice58.dll", "avformat58.dll", "openal32.dll", "rar.exe"]
    end

    def legacy_installation_warning
      [
        "Previous installation detected",
        "Elten detected files created by old installation, beta 59 or earlier.\r\nPlease remove the program and reinstall it again to delete those files.\r\nIf you don't want to remove your configuration, you can just delete Elten directory in \"Program files\"."
      ]
    end

    def bass_abi(architecture)
      if architecture.to_s == "x86" && defined?(Fiddle::Function::STDCALL)
        Fiddle::Function::STDCALL
      else
        Fiddle::Function::DEFAULT
      end
    end

    def os_version
      require "win32/registry"
      Win32::Registry::HKEY_LOCAL_MACHINE.open("SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion") do |reg|
        product = registry_value(reg, "ProductName")
        display = registry_value(reg, "DisplayVersion")
        build = registry_value(reg, "CurrentBuildNumber")
        ubr = registry_value(reg, "UBR")
        build = [build, ubr].reject { |part| part.to_s == "" }.join(".")
        [product, display, build == "" ? nil : "build #{build}"].compact.reject(&:empty?).join(", ")
      end
    rescue Exception
      ""
    end

    def environment_architecture
      [ENV["PROCESSOR_ARCHITECTURE"], ENV["PROCESSOR_ARCHITEW6432"]].compact.reject(&:empty?).uniq.join(" / ")
    rescue Exception
      ""
    end

    def original_process_arguments
      if defined?(EltenBoot) && EltenBoot.respond_to?(:command_line_args, true)
        args = EltenBoot.send(:command_line_args)
        return args.map(&:to_s) if args.is_a?(Array) && args.size > 0
      end
      []
    rescue Exception
      []
    end

    def embedded_executable_path(root, architecture)
      executable = case architecture.to_s
      when "arm64"
        "elten-arm64.exe"
      when "x64"
        "elten-x64.exe"
      else
        "elten-x86.exe"
      end
      File.expand_path(executable, root)
    end

    def autostart_executable_path(default_path)
      path = default_path.to_s
      if defined?(EltenRuntimePaths)
        facade_path = File.expand_path("elten.exe", EltenRuntimePaths.root)
        path = facade_path if File.executable?(facade_path)
      end
      path
    rescue Exception
      default_path.to_s
    end

    def autostart_executable?(path)
      ["elten.exe", "elten-x86.exe", "elten-x64.exe", "elten-arm64.exe"].include?(File.basename(path.to_s).downcase)
    rescue Exception
      false
    end

    def autostart_command(path)
      "\"#{path}\" /hidden"
    end

    def sync_autostart(enabled, command)
      return false if command.to_s == ""
      require "win32/registry"
      runkey = Win32::Registry::HKEY_CURRENT_USER.create("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
      begin
        current = runkey["elten"].to_s == command.to_s
        current_known = true
      rescue Exception
        current = false
        current_known = false
      end

      requested = enabled == true
      if current != requested
        if requested
          Log.debug("AUT") if defined?(Log)
          runkey["elten"] = command.to_s
        else
          runkey.delete("elten") rescue nil
        end
      elsif current_known && !requested
        runkey.delete("elten") rescue nil
      end
      true
    rescue Exception
      false
    ensure
      runkey.close if defined?(runkey) && runkey != nil
    end

    def prepare_os_microphone(_timeout = 0)
      true
    end

    def beta_version_creation_supported?
      true
    end

    def autologin_key_encryption_supported?
      true
    end

    def installer_extension
      "exe"
    end

    def installer_filename
      "eltenup.exe"
    end

    def installer_path(data_dir)
      EltenPath.join(data_dir, installer_filename)
    end

    def update_install_command(installer, silent: true)
      command = "\"#{installer}\""
      command += " /tasks=\"\" /silent" if silent
      command
    end

    private

    def blob_bytes(blob)
      size, pointer = EltenWin32.data_blob_values(blob)
      bytes = pointer.to_i == 0 || size.to_i <= 0 ? "".b : Fiddle::Pointer.new(pointer.to_i)[0, size.to_i].to_s.b
      LOCAL_FREE.call(pointer) if pointer.to_i != 0
      bytes
    rescue Exception
      LOCAL_FREE.call(pointer) if defined?(pointer) && pointer.to_i != 0 rescue nil
      "".b
    end

    def wide(text)
      (text.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace) + [0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
    end

    def from_wide(text)
      text.to_s.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    end

    def known_folder(csidl)
      buffer = ("\0" * 260 * 2).b
      return nil if SH_GET_FOLDER_PATH.call(nil, csidl, nil, SHGFP_TYPE_CURRENT, buffer) != 0
      from_wide(buffer).split("\0", 2).first
    rescue Exception
      nil
    end

    def fallback_env(name)
      value = ENV[name].to_s
      value == "" ? nil : value
    rescue Exception
      nil
    end

    def home_dir
      Dir.home
    rescue Exception
      "."
    end

    def command_line_quote(text)
      text = text.to_s
      return '""' if text == ""
      return text if text !~ /[\s"]/
      '"' + text.gsub(/(\\*)"/, '\\1\\1\"').gsub(/\\+\z/) { |slashes| slashes * 2 } + '"'
    end

    def registry_value(registry, name)
      registry[name].to_s
    rescue Exception
      ""
    end

    def absolute_path?(path)
      path =~ /\A[A-Za-z]:[\\\/]/ || path.start_with?("//") || path.start_with?("\\\\") || path.start_with?("/")
    end
  end
end
