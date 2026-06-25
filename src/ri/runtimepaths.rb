# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenRuntimePaths
  class << self
    def root
      embedded_root = if defined?(::EltenEmbedded) && ::EltenEmbedded.const_defined?(:ROOT)
        ::EltenEmbedded::ROOT
      elsif ENV["ELTEN_ROOT"].to_s != ""
        ENV["ELTEN_ROOT"]
      end
      return File.expand_path(embedded_root) if embedded_root.to_s != ""

      File.expand_path("../..", __dir__)
    end

    def architecture
      cpu = RbConfig::CONFIG["target_cpu"].to_s.downcase
      cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase if cpu == ""
      return "arm64" if cpu =~ /arm64|aarch64/
      return "x64" if cpu =~ /x64|x86_64|amd64|64/
      [nil].pack("p").bytesize == 8 ? "x64" : "x86"
    rescue Exception
      [nil].pack("p").bytesize == 8 ? "x64" : "x86"
    end

    def platform
      return @platform if @platform != nil
      tag = nil
      env_platform = ENV["ELTEN_LAUNCHER_PLATFORM"].to_s.downcase
      tag = env_platform.to_sym if env_platform != ""
      tag = ::EltenEmbedded::PLATFORM.to_s.downcase.to_sym if tag == nil && defined?(::EltenEmbedded) && ::EltenEmbedded.const_defined?(:PLATFORM)
      tag = EltenBoot.platform_tags.first if defined?(EltenBoot) && EltenBoot.respond_to?(:platform_tags)
      tag ||= EltenSystemHelpers.platform_os.to_s.downcase.to_sym if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:platform_os)
      @platform = tag || :unknown
    end

    def runtime_directory_name
      return EltenSystemHelpers.runtime_directory_name(architecture) if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:runtime_directory_name)
      platform.to_s
    end

    def bin_root
      File.join(root, "bin")
    end

    def arch_bin
      File.join(bin_root, runtime_directory_name)
    end

    def legacy_bin
      bin_root
    end

    def dll_directories
      [arch_bin, legacy_bin, root, Dir.pwd].uniq
    end

    def configure_dll_search!
      return if @dll_search_configured

      dirs = dll_directories.select { |dir| File.directory?(dir) }
      EltenSystemHelpers.configure_library_search(dirs, arch_bin) if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:configure_library_search)
      @dll_search_configured = true
    end

    def library_candidates(name)
      return [name] unless defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:library_candidates)
      EltenSystemHelpers.library_candidates(
        name,
        root: root,
        bin_root: bin_root,
        arch_bin: arch_bin,
        legacy_bin: legacy_bin,
        dll_directories: dll_directories
      )
    end

    def find_library(name)
      library_candidates(name).find { |candidate| File.file?(candidate) } || name
    end

    def dlopen(name)
      require "fiddle"
      configure_dll_search!
      file = find_library(name)
      handle = if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:dlopen_library)
        EltenSystemHelpers.dlopen_library(file, name) do |dependency|
          if !loaded_library?(dependency)
            dlopen(dependency)
          end
        end
      else
        Fiddle.dlopen(file)
      end
      remember_library(name, file, handle)
      handle
    end

    def relative_library_name(name)
      raw = name.to_s.tr("\\", "/")
      variants = library_variants(raw.sub(/\.(dll|dylib|so)\z/i, ""))
      candidates = [
        *variants.map { |variant| File.join("bin", runtime_directory_name, variant) },
        *variants.map { |variant| File.join("bin", variant) },
        *variants
      ]
      candidates.find { |candidate| library_candidate_available?(candidate) } || candidates.first
    end

    def relative_library_file(name)
      raw = name.to_s.tr("\\", "/")
      variants = library_variants(raw)
      candidates = [
        *variants.map { |variant| File.join("bin", runtime_directory_name, variant) },
        *variants.map { |variant| File.join("bin", variant) },
        *variants
      ]
      candidates.find { |candidate| File.file?(File.join(root, candidate)) } || candidates.first
    end

    def absolute_library_file(name)
      found = find_library(name)
      absolute_path?(found) ? found : File.expand_path(found, root)
    end

    private

    def remember_library(name, file, handle)
      @loaded_libraries ||= {}
      keys = [name.to_s.downcase, File.basename(file.to_s).downcase]
      keys << File.expand_path(file).downcase if absolute_path?(file.to_s)
      keys.each { |key| @loaded_libraries[key] = handle }
      handle
    rescue Exception
      handle
    end

    def loaded_library?(name)
      @loaded_libraries ||= {}
      raw = name.to_s.downcase
      @loaded_libraries.key?(raw) || @loaded_libraries.key?(File.basename(raw))
    end

    def library_variants(raw)
      return EltenSystemHelpers.library_variants(raw) if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:library_variants)
      [raw.to_s]
    end

    def library_candidate_available?(candidate)
      if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:library_candidate_available?)
        EltenSystemHelpers.library_candidate_available?(root, candidate)
      else
        File.file?(File.join(root, candidate))
      end
    end

    def absolute_path?(path)
      path =~ /\A[A-Za-z]:[\\\/]/ || path.start_with?("//") || path.start_with?("\\\\") || path.start_with?("/")
    end

  end
end
