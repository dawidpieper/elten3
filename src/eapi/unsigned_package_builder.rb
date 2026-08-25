# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

require "fileutils"
require "json"
require "securerandom"
require "zlib"

module Programs
  # Shared, deliberately reduced builder for local developer workflows. It
  # produces unsigned packages and rejects manifests requiring gem bundling.
  # Production builds continue to use the signed canonical build tools.
  class UnsignedPackageBuilder
    LANGUAGE_EXTENSIONS = [".mo"].freeze

    class ZipWriter
      Entry = Struct.new(:name, :crc, :compressed_size, :uncompressed_size, :method,
        :offset, :dos_time, :dos_date, keyword_init: true)

      def initialize(path)
        @io = File.open(path, "wb")
        @entries = []
      end

      def add(name, data, mtime = Time.now)
        normalized = name.to_s.tr("\\", "/")
        parts = normalized.split("/")
        raise ProgramError, "Unsafe setup entry #{name.inspect}" if normalized.empty? || normalized.start_with?("/") || normalized.include?(":") || parts.include?("..")
        data = data.to_s.b
        compressed = deflate(data)
        method = 8
        if compressed.bytesize >= data.bytesize
          compressed = data
          method = 0
        end
        dos_time, dos_date = dos_datetime(mtime)
        entry = Entry.new(:name => normalized, :crc => Zlib.crc32(data),
          :compressed_size => compressed.bytesize, :uncompressed_size => data.bytesize,
          :method => method, :offset => @io.pos, :dos_time => dos_time, :dos_date => dos_date)
        name_bytes = normalized.encode(Encoding::UTF_8)
        @io.write([0x04034b50, 20, 0x0800, method, dos_time, dos_date, entry.crc,
          entry.compressed_size, entry.uncompressed_size, name_bytes.bytesize, 0].pack("L<S<S<S<S<S<L<L<L<S<S<"))
        @io.write(name_bytes)
        @io.write(compressed)
        @entries << entry
      end

      def close
        return if @io == nil
        central_offset = @io.pos
        @entries.each { |entry| write_central_entry(entry) }
        central_size = @io.pos - central_offset
        @io.write([0x06054b50, 0, 0, @entries.size, @entries.size, central_size,
          central_offset, 0].pack("L<S<S<S<S<L<L<S<"))
        @io.close
        @io = nil
      end

      private

      def deflate(data)
        stream = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
        stream.deflate(data, Zlib::FINISH)
      ensure
        stream.close if stream != nil
      end

      def dos_datetime(time)
        year = [[time.year, 1980].max, 2107].min
        [(time.hour << 11) | (time.min << 5) | (time.sec / 2),
          ((year - 1980) << 9) | (time.month << 5) | time.day]
      end

      def write_central_entry(entry)
        name_bytes = entry.name.encode(Encoding::UTF_8)
        @io.write([0x02014b50, 20, 20, 0x0800, entry.method, entry.dos_time,
          entry.dos_date, entry.crc, entry.compressed_size, entry.uncompressed_size,
          name_bytes.bytesize, 0, 0, 0, 0, 0, entry.offset].pack("L<S<S<S<S<S<S<L<L<L<S<S<S<S<S<L<L<"))
        @io.write(name_bytes)
      end
    end

    class << self
      def build(source_dir:, output:, format:, metadata:)
        require "zstd-ruby" if !defined?(Zstd)
        root = File.realpath(source_dir)
        target = File.expand_path(output)
        format = format.to_s.downcase
        raise ProgramError, "format must be eltenapp or eltsetup" if !%w[eltenapp eltsetup].include?(format)
        raise ProgramError, "Package metadata must be an object" if !metadata.is_a?(Hash)
        raise ProgramError, "Unsigned developer builder does not bundle declared gems" if !Array(metadata["gems"]).empty?
        root_key = normalized_path(root)
        target_key = normalized_path(target)
        raise ProgramError, "Package output cannot be inside its source directory" if target_key.start_with?(root_key + "/")
        FileUtils.mkdir_p(File.dirname(target))
        temporary = "#{target}.tmp-#{SecureRandom.hex(6)}"
        code = code_container(root, metadata)
        if format == "eltenapp"
          File.binwrite(temporary, code)
        else
          setup_package(root, temporary, target, metadata, code)
        end
        File.rename(temporary, target)
        { "path" => target, "format" => format, "size" => File.size(target).to_i,
          "signed" => false, "builder_profile" => "unsigned_without_declared_gems" }
      rescue LoadError
        raise ProgramError, "zstd-ruby is unavailable; the program cannot be packaged"
      ensure
        File.delete(temporary) if defined?(temporary) && temporary != nil && File.file?(temporary)
      end

      private

      def code_container(root, metadata)
        buffer = +"".b
        buffer << Programs::MAGIC
        compressed_metadata = Zstd.compress(JSON.generate(metadata).b, :level => 19)
        buffer << [compressed_metadata.bytesize].pack("L<") << compressed_metadata
        each_source_file(root) do |file, relative|
          extension = File.extname(relative).downcase
          if extension == ".rb"
            write_named_record(buffer, 1, relative, Zstd.compress(File.binread(file).b, :level => 19))
          elsif relative.start_with?("Audio/") && Programs::SOUND_EXTENSIONS.include?(extension)
            write_named_record(buffer, 2, relative, File.binread(file).b)
          elsif (language = language_code(relative)) != nil
            content = Zstd.compress(File.binread(file).b, :level => 19)
            buffer << [3].pack("C") << language << [content.bytesize].pack("L<") << content
          end
        end
        buffer
      end

      def setup_package(root, output, final_output, metadata, code)
        code_name = "#{File.basename(final_output, ".eltsetup")}.eltenapp"
        setup_manifest = { "type" => "application", "payload" => metadata.merge("entry" => code_name) }
        writer = ZipWriter.new(output)
        writer.add("__manifest.json", JSON.pretty_generate(setup_manifest) + "\n")
        writer.add(code_name, code)
        each_source_file(root) do |file, relative|
          extension = File.extname(relative).downcase
          next if extension == ".rb" || extension == ".eltenapp" || relative == "__manifest.json"
          next if relative.start_with?("Audio/") && Programs::SOUND_EXTENSIONS.include?(extension)
          next if relative.start_with?("locale/")
          writer.add(relative, File.binread(file).b, File.mtime(file))
        end
        writer.close
      ensure
        writer.close if defined?(writer) && writer != nil
      end

      def each_source_file(root)
        root_key = normalized_path(root)
        Dir.glob(File.join(root, "**", "*")).sort.each do |file|
          next if !File.file?(file) || File.symlink?(file)
          resolved = normalized_path(File.realpath(file))
          next if !resolved.start_with?(root_key + "/")
          yield file, file.delete_prefix(root + File::SEPARATOR).tr("\\", "/")
        end
      end

      def write_named_record(buffer, type, name, content)
        name_bytes = name.encode(Encoding::UTF_8)
        raise ProgramError, "Program file name is too long: #{name}" if name_bytes.bytesize > 0xffff
        buffer << [type, name_bytes.bytesize].pack("CS<") << name_bytes
        buffer << [content.bytesize].pack("L<") << content
      end

      def language_code(relative)
        return nil if !relative.start_with?("locale/") || !LANGUAGE_EXTENSIONS.include?(File.extname(relative).downcase)
        code = File.basename(relative, File.extname(relative))[0, 2].to_s
        code.match?(/\A[a-zA-Z]{2}\z/) ? code.upcase : nil
      end

      def normalized_path(path)
        value = path.to_s.tr("\\", "/")
        RUBY_PLATFORM.match?(/mswin|mingw|cygwin/i) ? value.downcase : value
      end
    end
  end
end
