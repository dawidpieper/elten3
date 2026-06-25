# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module OSXSystemNative
  UTF8_ENCODING = 4 unless const_defined?(:UTF8_ENCODING)
  PTR_SIZE = [nil].pack("p").bytesize unless const_defined?(:PTR_SIZE)
  PTR_PACK = PTR_SIZE == 8 ? "Q" : "L" unless const_defined?(:PTR_PACK)
  BLOCK_IS_GLOBAL = 1 << 28 unless const_defined?(:BLOCK_IS_GLOBAL)
  BLOCK_HAS_SIGNATURE = 1 << 30 unless const_defined?(:BLOCK_HAS_SIGNATURE)
  AV_AUTHORIZATION_STATUS_NOT_DETERMINED = 0 unless const_defined?(:AV_AUTHORIZATION_STATUS_NOT_DETERMINED)
  AV_AUTHORIZATION_STATUS_RESTRICTED = 1 unless const_defined?(:AV_AUTHORIZATION_STATUS_RESTRICTED)
  AV_AUTHORIZATION_STATUS_DENIED = 2 unless const_defined?(:AV_AUTHORIZATION_STATUS_DENIED)
  AV_AUTHORIZATION_STATUS_AUTHORIZED = 3 unless const_defined?(:AV_AUTHORIZATION_STATUS_AUTHORIZED)

  class << self
    def available?
      initialize_native
    end

    def current_locale_name
      return "" unless available?
      locale = @msg_id.call(cls("NSLocale"), sel("currentLocale"))
      identifier = @msg_id.call(locale, sel("localeIdentifier"))
      objc_string(identifier)
    rescue Exception
      ""
    end

    def open_url(value)
      return false if value.to_s == "" || !available?
      url = ns_url(value.to_s)
      return false if url.to_i == 0
      workspace = @msg_id.call(cls("NSWorkspace"), sel("sharedWorkspace"))
      @msg_bool_id.call(workspace, sel("openURL:"), url).to_i != 0
    rescue Exception
      false
    end

    def request_microphone_access(timeout = 15.0)
      return true unless available?
      return true unless avfoundation_available?
      status = microphone_authorization_status
      return true if status == AV_AUTHORIZATION_STATUS_AUTHORIZED
      return false if status == AV_AUTHORIZATION_STATUS_RESTRICTED || status == AV_AUTHORIZATION_STATUS_DENIED
      return true if status != AV_AUTHORIZATION_STATUS_NOT_DETERMINED

      request_microphone_access_native(timeout)
    rescue Exception
      true
    end

    def microphone_authorization_status
      return -1 unless available?
      return -1 unless avfoundation_available?
      device_class = cls("AVCaptureDevice")
      media_type = av_media_type_audio
      return -1 if device_class.to_i == 0 || media_type.to_i == 0
      @msg_long_id.call(device_class, sel("authorizationStatusForMediaType:"), media_type).to_i
    rescue Exception
      -1
    end

    private

    def initialize_native
      return @native_available if defined?(@native_available)
      @native_available = false
      unless defined?(Fiddle)
        verbose = $VERBOSE
        $VERBOSE = nil
        begin
          require "fiddle"
        ensure
          $VERBOSE = verbose
        end
      end
      unless defined?(Fiddle::Closure)
        verbose = $VERBOSE
        $VERBOSE = nil
        begin
          require "fiddle/closure"
          require "thread"
        ensure
          $VERBOSE = verbose
        end
      end
      Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
      Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
      objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      id = Fiddle::TYPE_VOIDP
      sel_type = Fiddle::TYPE_VOIDP
      bool = Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR
      native_unsigned = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_ULONG_LONG : Fiddle::TYPE_ULONG
      @objc_get_class = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], id)
      @sel_register_name = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], sel_type)
      msg = objc["objc_msgSend"]
      @msg_id = Fiddle::Function.new(msg, [id, sel_type], id)
      @msg_id_id = Fiddle::Function.new(msg, [id, sel_type, id], id)
      @msg_bool_id = Fiddle::Function.new(msg, [id, sel_type, id], bool)
      @msg_long_id = Fiddle::Function.new(msg, [id, sel_type, id], Fiddle::TYPE_LONG)
      @msg_void_id_ptr = Fiddle::Function.new(msg, [id, sel_type, id, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
      @msg_id_bytes = Fiddle::Function.new(msg, [id, sel_type, Fiddle::TYPE_VOIDP, native_unsigned, native_unsigned], id)
      @msg_ulong_ulong = Fiddle::Function.new(msg, [id, sel_type, native_unsigned], native_unsigned)
      @native_available = cls("NSLocale").to_i != 0 && cls("NSWorkspace").to_i != 0 && cls("NSURL").to_i != 0 && cls("NSString").to_i != 0
    rescue Exception
      @native_available = false
    end

    def avfoundation
      return @avfoundation if defined?(@avfoundation)
      @avfoundation = Fiddle.dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation")
    rescue Exception
      @avfoundation = nil
    end

    def avfoundation_available?
      return @avfoundation_available if defined?(@avfoundation_available)
      @avfoundation_available = avfoundation != nil && cls("AVCaptureDevice").to_i != 0 && av_media_type_audio.to_i != 0
    rescue Exception
      @avfoundation_available = false
    end

    def av_media_type_audio
      return @av_media_type_audio if defined?(@av_media_type_audio)
      symbol = avfoundation["AVMediaTypeAudio"] rescue 0
      if symbol.to_i != 0
        value = Fiddle::Pointer.new(symbol.to_i)[0, PTR_SIZE].unpack(PTR_PACK).first
        return @av_media_type_audio = value if value.to_i != 0
      end
      @av_media_type_audio = ns_string("soun")
    rescue Exception
      @av_media_type_audio = 0
    end

    def request_microphone_access_native(timeout)
      mutex = Mutex.new
      condition = ConditionVariable.new
      state = { :done => false, :granted => false }
      callback = make_access_block do |granted|
        mutex.synchronize do
          state[:granted] = granted == true
          state[:done] = true
          condition.broadcast
        end
      end
      @msg_void_id_ptr.call(cls("AVCaptureDevice"), sel("requestAccessForMediaType:completionHandler:"), av_media_type_audio, callback[:block])
      deadline = Time.now + [timeout.to_f, 0.1].max
      mutex.synchronize do
        until state[:done]
          remaining = deadline - Time.now
          break if remaining <= 0
          condition.wait(mutex, remaining)
        end
      end
      state[:done] ? state[:granted] : microphone_authorization_status == AV_AUTHORIZATION_STATUS_AUTHORIZED
    rescue Exception
      true
    end

    def make_access_block(&block)
      bool = Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR
      closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, bool]) do |_block, granted|
        block.call(granted.to_i != 0)
      end
      signature = cstring("v@?B")
      descriptor = pointer_buffer(0, block_literal_size, signature.to_i)
      literal = block_literal_buffer(ns_concrete_global_block, BLOCK_HAS_SIGNATURE | BLOCK_IS_GLOBAL, closure.to_i, descriptor.to_i)
      callback = {
        :block => literal,
        :closure => closure,
        :descriptor => descriptor,
        :signature => signature
      }
      @microphone_access_callbacks ||= []
      @microphone_access_callbacks << callback
      callback
    end

    def block_literal_size
      PTR_SIZE + 4 + 4 + PTR_SIZE + PTR_SIZE
    end

    def block_literal_buffer(isa, flags, invoke, descriptor)
      pointer = Fiddle::Pointer.malloc(block_literal_size)
      offset = 0
      pointer[offset, PTR_SIZE] = [isa.to_i].pack(PTR_PACK)
      offset += PTR_SIZE
      pointer[offset, 4] = [flags.to_i].pack("l")
      offset += 4
      pointer[offset, 4] = [0].pack("l")
      offset += 4
      pointer[offset, PTR_SIZE] = [invoke.to_i].pack(PTR_PACK)
      offset += PTR_SIZE
      pointer[offset, PTR_SIZE] = [descriptor.to_i].pack(PTR_PACK)
      pointer
    end

    def pointer_buffer(*values)
      pointer = Fiddle::Pointer.malloc(PTR_SIZE * values.size)
      values.each_with_index do |value, index|
        pointer[index * PTR_SIZE, PTR_SIZE] = [value.to_i].pack(PTR_PACK)
      end
      pointer
    end

    def ns_concrete_global_block
      return @ns_concrete_global_block if @ns_concrete_global_block != nil
      handle = Fiddle.dlopen(nil)
      @ns_concrete_global_block = handle["_NSConcreteGlobalBlock"]
    rescue Exception
      @ns_concrete_global_block = Fiddle.dlopen("/usr/lib/libSystem.B.dylib")["_NSConcreteGlobalBlock"]
    end

    def cstring(text)
      bytes = text.to_s.b + "\0"
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def ns_url(value)
      if value =~ /\A[A-Za-z][A-Za-z0-9+.-]*:/
        @msg_id_id.call(cls("NSURL"), sel("URLWithString:"), ns_string(value))
      else
        @msg_id_id.call(cls("NSURL"), sel("fileURLWithPath:"), ns_string(File.expand_path(value)))
      end
    rescue Exception
      0
    end

    def ns_string(value)
      bytes = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).b
      @msg_id_bytes.call(cls("NSString"), sel("stringWithBytes:length:encoding:"), bytes, bytes.bytesize, UTF8_ENCODING)
    end

    def objc_string(object)
      return "" if object.to_i == 0
      pointer = @msg_id.call(object, sel("UTF8String"))
      return "" if pointer.to_i == 0
      length = @msg_ulong_ulong.call(object, sel("lengthOfBytesUsingEncoding:"), UTF8_ENCODING).to_i
      bytes = length > 0 ? Fiddle::Pointer.new(pointer)[0, length] : ""
      bytes.force_encoding(Encoding::UTF_8)
      bytes.valid_encoding? ? bytes : bytes.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    rescue Exception
      ""
    end

    def cls(name)
      @classes ||= {}
      @classes[name] ||= @objc_get_class.call(name.to_s.b + "\0".b)
    end

    def sel(name)
      @selectors ||= {}
      @selectors[name] ||= @sel_register_name.call(name.to_s.b + "\0".b)
    end
  end
end

module EltenSystemHelpers
  NATIVE_OPEN_COMMAND = "__elten_native_open__" unless const_defined?(:NATIVE_OPEN_COMMAND)

  class << self
    def current_lcid
      0
    end

    def current_locale_name
      locale = OSXSystemNative.current_locale_name
      locale = ENV["LANG"].to_s.split(".").first if locale.to_s == ""
      locale.to_s
    rescue Exception
      ""
    end

    def logical_drives
      drives = ["/"]
      volumes = "/Volumes"
      if File.directory?(volumes)
        Dir.children(volumes).sort.each do |entry|
          path = File.join(volumes, entry)
          drives << path if File.directory?(path)
        end
      end
      drives.uniq
    rescue Exception
      ["/"]
    end

    def appdata_dir
      File.join(home_dir, "Library", "Application Support")
    end

    def user_dir
      home_dir
    end

    def documents_dir
      File.join(home_dir, "Documents")
    end

    def desktop_dir
      File.join(home_dir, "Desktop")
    end

    def music_dir
      File.join(home_dir, "Music")
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
      OSXSystemNative.open_url(url)
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
      "osx"
    end

    def platform_target
      cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
      arch = cpu =~ /arm|aarch64/ ? "arm64" : "x64"
      "osx-#{arch}"
    rescue Exception
      "osx-x64"
    end

    def runtime_directory_name(_architecture)
      "osx"
    end

    def configure_library_search(dirs, _arch_bin)
      path_key = ENV.key?("PATH") ? "PATH" : "Path"
      current_path = ENV[path_key] || ""
      ENV[path_key] = (dirs + current_path.split(":")).reject { |entry| entry.to_s == "" }.uniq.join(":")

      current_dyld = ENV["DYLD_LIBRARY_PATH"].to_s
      ENV["DYLD_LIBRARY_PATH"] = (dirs + current_dyld.split(":")).reject { |entry| entry.to_s == "" }.uniq.join(":")
      current_fallback = ENV["DYLD_FALLBACK_LIBRARY_PATH"].to_s
      ENV["DYLD_FALLBACK_LIBRARY_PATH"] = (dirs + current_fallback.split(":")).reject { |entry| entry.to_s == "" }.uniq.join(":")
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
          if lower.start_with?("osx/", "windows-x64/", "windows-x86/", "windows-arm64/")
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
      names << "#{$1}.dylib" if stem =~ /\A(.+)\.\1\z/
      names << "#{$1}.dylib" if stem =~ /\A(lib.+)\.lib(.+)\z/ && $1 == "lib#{$2}"
      names << "#{stem}.dylib"
      names << "lib#{stem}.dylib" unless stem.start_with?("lib")
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
        flags == nil ? Fiddle::Handle.new(file) : Fiddle::Handle.new(file, flags)
      rescue Fiddle::DLError => error
        retry_missing_library_dependency(error) do |dependency|
          yield dependency if block_given?
        end
        flags == nil ? Fiddle::Handle.new(file) : Fiddle::Handle.new(file, flags)
      end
    end

    def native_extension
      ".bundle"
    end

    def opus_library_name
      "opus"
    end

    def speexdsp_library_name
      "libspeexdsp"
    end

    def vst2_extensions
      [".vst"]
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
      plist = "/System/Library/CoreServices/SystemVersion.plist"
      return "" unless File.file?(plist)
      text = File.binread(plist)
      product = text[/<key>ProductName<\/key>\s*<string>([^<]+)<\/string>/, 1].to_s
      version = text[/<key>ProductVersion<\/key>\s*<string>([^<]+)<\/string>/, 1].to_s
      build = text[/<key>ProductBuildVersion<\/key>\s*<string>([^<]+)<\/string>/, 1].to_s
      [product, version, build == "" ? nil : "build #{build}"].compact.reject(&:empty?).join(" ")
    rescue Exception
      ""
    end

    def environment_architecture
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

    def autostart_command(path)
      command_line_join([path.to_s])
    end

    def sync_autostart(_enabled, _command)
      false
    end

    def prepare_os_microphone(timeout = 15.0)
      granted = OSXSystemNative.request_microphone_access(timeout)
      Log.warning("macOS microphone access denied or restricted") if granted == false && defined?(Log)
      granted != false
    rescue Exception
      true
    end

    def beta_version_creation_supported?
      false
    end

    def autologin_key_encryption_supported?
      false
    end

    def installer_extension
      "pkg"
    end

    def installer_filename
      "elten.pkg"
    end

    def installer_path(data_dir)
      EltenPath.join(data_dir, installer_filename)
    end

    def update_install_command(installer, silent: true)
      [NATIVE_OPEN_COMMAND, installer.to_s]
    end

    private

    def home_dir
      Dir.home
    rescue Exception
      "."
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
      missing = error.message.to_s[/Library not loaded:\s+([^\s]+)/, 1]
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
      names << "#{$1}#{$2}" if base =~ /\A(.+)\.\1(\.dylib)\z/
      names << "#{$1}#{$3}" if base =~ /\A(lib.+)\.lib(.+)(\.dylib)\z/ && $1 == "lib#{$2}"
      names.uniq
    end
  end
end
