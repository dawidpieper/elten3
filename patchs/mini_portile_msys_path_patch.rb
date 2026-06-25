# frozen_string_literal: true

begin
  require "mini_portile2"
rescue LoadError
end

if defined?(::MiniPortile)
  class ::MiniPortile
    class << self
      def elten_msys_posix_option(value)
        value.gsub(/(^|[=\s"'`]|-[IL])([A-Za-z]):[\\\/]([^\s"'`]*)/) do
          prefix = Regexp.last_match(1)
          drive = Regexp.last_match(2).downcase
          tail = Regexp.last_match(3).tr("\\", "/")
          "#{prefix}/#{drive}/#{tail}"
        end
      end

      def elten_msys_windows_option(value)
        value.gsub(%r{(^|=|["'`]|-[IL])/([A-Za-z])/([^\s"'`]*)}) do
          prefix = Regexp.last_match(1)
          drive = Regexp.last_match(2).upcase
          tail = Regexp.last_match(3)
          "#{prefix}#{drive}:/#{tail}"
        end
      end
    end

    private

    unless method_defined?(:elten_original_computed_options)
      alias_method :elten_original_computed_options, :computed_options
    end

    unless method_defined?(:elten_original_configure)
      alias_method :elten_original_configure, :configure
    end

    unless method_defined?(:elten_original_compile)
      alias_method :elten_original_compile, :compile
    end

    unless method_defined?(:elten_original_activate)
      alias_method :elten_original_activate, :activate
    end

    def configure_prefix
      "--prefix=#{MiniPortile.elten_msys_posix_option(File.expand_path(port_path))}"
    end

    def computed_options
      elten_original_computed_options.map do |option|
        option.is_a?(String) ? MiniPortile.elten_msys_posix_option(option) : option
      end
    end

    def configure
      elten_original_configure
      elten_patch_generated_build_files
    end

    def compile
      elten_patch_generated_build_files
      elten_original_compile
    end

    def activate
      elten_patch_installed_config_scripts
      elten_original_activate
      ENV["LDFLAGS"] = MiniPortile.elten_msys_posix_option(ENV["LDFLAGS"].to_s)
    end

    def elten_patch_installed_config_scripts
      Dir.glob(File.join(port_path, "bin", "*-config")).each do |config|
        text = File.read(config)
        patched = MiniPortile.elten_msys_windows_option(text)
        File.write(config, patched) if patched != text
      end
    end

    def elten_patch_generated_build_files
      elten_patch_generated_libtool
      Dir.glob(File.join(work_path, "**", "Makefile")).each do |makefile|
        text = File.read(makefile)
        patched = MiniPortile.elten_msys_posix_option(text)
        File.write(makefile, patched) if patched != text
      end
    end

    def elten_patch_generated_libtool
      libtool = File.join(work_path, "libtool")
      return unless File.file?(libtool)

      text = File.read(libtool)
      patched = text
        .sub(/^to_host_file_cmd=.*$/, "to_host_file_cmd=func_convert_file_noop")
        .sub(/^to_tool_file_cmd=.*$/, "to_tool_file_cmd=func_convert_file_noop")
      File.write(libtool, patched) if patched != text
    end

    public :activate
  end
end
