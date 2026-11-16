# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

require "json"

module Programs
  module ProgramPackageMetadata
    LOCALIZED_FIELDS = {
      "localized_names" => "name",
      "localized_descriptions" => "description"
    }.freeze
    LOCALIZED_FILE_PATTERN = /\Alocale\/([a-zA-Z]{2}(?:[-_][a-zA-Z]{2})?)_metadata\.json\z/i.freeze

    class << self
      def prepare(metadata, source_dir:, warning: nil)
        raise_metadata_error("Package metadata must be an object") if !metadata.is_a?(Hash)
        root = File.expand_path(source_dir)
        prepared = metadata.dup
        encoding = normalize_sources_default_encoding(prepared["sources_default_encoding"])
        prepared["sources_default_encoding"] = encoding.name if encoding != nil
        files, detected_languages = scan_locale(root)

        LOCALIZED_FIELDS.each do |manifest_key, file_kind|
          values = normalize_localizations(prepared[manifest_key], manifest_key)
          files[file_kind].each { |language, text| values[language] ||= text }
          prepared[manifest_key] = sorted_hash(values) if prepared.key?(manifest_key) || !values.empty?
        end

        main_declared = prepared.key?("main_language") && prepared["main_language"].to_s.strip != ""
        emit_warning(warning, "Program manifest has no main_language; using unknown") if !main_declared
        main_language = main_declared ? normalize_language!(prepared["main_language"], "main_language", :allow_unknown => true) : "unknown"
        prepared["main_language"] = main_language if main_declared

        supported_declared = prepared.key?("supported_languages")
        supported_languages = supported_declared ? normalize_languages(prepared["supported_languages"], "supported_languages") : []
        if supported_declared && main_language != "unknown" && !supported_languages.include?(main_language)
          supported_languages << main_language
          supported_languages.sort!
          emit_warning(warning, "Program main_language #{main_language.inspect} was missing from supported_languages and has been added")
        end
        prepared["supported_languages"] = supported_languages if supported_declared

        unsupported_files = detected_languages.reject { |language| supported_languages.include?(language) }
        if !unsupported_files.empty?
          emit_warning(warning, "Program locale files declare languages missing from supported_languages: #{unsupported_files.join(", ")}")
        end
        prepared
      end

      def normalize_sources_default_encoding(value)
        return nil if value == nil
        encoding = Encoding.find(value) if value.is_a?(String) && !%w[external internal locale filesystem].include?(value.downcase)
        raise ArgumentError if encoding == nil || !encoding.ascii_compatible? || encoding.dummy?
        encoding
      rescue ArgumentError
        raise_metadata_error("Invalid sources_default_encoding #{value.inspect}; expected an ASCII-compatible Ruby encoding")
      end

      def normalize_language(value, allow_unknown: false)
        text = value.to_s.strip.tr("_", "-")
        return "unknown" if allow_unknown && text.casecmp("unknown").zero?
        match = /\A([a-zA-Z]{2})(?:-[a-zA-Z]{2})?\z/.match(text)
        match == nil ? nil : match[1].downcase
      end

      def normalize_language!(value, field, allow_unknown: false)
        language = normalize_language(value, :allow_unknown => allow_unknown)
        raise_metadata_error("Invalid language #{value.inspect} in #{field}") if language == nil
        language
      end

      def normalize_languages(value, field)
        Array(value).map { |language| normalize_language!(language, field) }.uniq.sort
      end

      def normalize_localizations(value, field)
        return {} if value == nil
        raise_metadata_error("Invalid #{field}; expected an object") if !value.is_a?(Hash)
        values = {}
        value.each do |language, text|
          code = normalize_language!(language, field)
          content = text.to_s.strip
          next if content == ""
          values[code] = content
        end
        sorted_hash(values)
      end

      private

      def scan_locale(root)
        values = { "name" => {}, "description" => {} }
        detected = []
        locale_root = File.join(root, "locale")
        return [values, detected] if !File.directory?(locale_root)

        Dir.glob(File.join(locale_root, "**", "*")).sort.each do |file|
          next if !File.file?(file)
          relative = file.delete_prefix(root + File::SEPARATOR).tr("\\", "/")
          match = LOCALIZED_FILE_PATTERN.match(relative)
          if match != nil
            language = normalize_language!(match[1], relative)
            detected << language
            localized_metadata = read_localized_metadata(file, relative)
            LOCALIZED_FIELDS.each_value do |field|
              content = localized_metadata[field]
              values[field][language] ||= content if content != nil && content != ""
            end
          elsif File.extname(relative).downcase == ".mo" && relative.start_with?("locale/")
            language = File.basename(relative, File.extname(relative))[0, 2].to_s
            detected << language.downcase if language.match?(/\A[a-zA-Z]{2}\z/)
          end
        end
        [values, detected.uniq.sort]
      end

      def read_localized_metadata(file, relative)
        text = File.binread(file).dup.force_encoding(Encoding::UTF_8)
        raise_metadata_error("Invalid UTF-8 in #{relative}") if !text.valid_encoding?
        text = text.delete_prefix("\uFEFF")
        metadata = JSON.parse(text)
        raise_metadata_error("Invalid metadata in #{relative}; expected an object") if !metadata.is_a?(Hash)
        LOCALIZED_FIELDS.each_value.each_with_object({}) do |field, result|
          next if !metadata.key?(field)
          content = metadata[field].to_s.strip
          result[field] = content if content != ""
        end
      rescue JSON::ParserError => e
        raise_metadata_error("Invalid JSON in #{relative}: #{e.message}")
      end

      def sorted_hash(value)
        value.keys.sort.each_with_object({}) { |key, result| result[key] = value[key] }
      end

      def emit_warning(callback, message)
        callback.call(message) if callback != nil
      end

      def raise_metadata_error(message)
        error = Programs.const_defined?(:ProgramError, false) ? Programs::ProgramError : RuntimeError
        raise error, message
      end
    end
  end
end
