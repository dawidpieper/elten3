# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  private
def writeconfig(group, key, val)
  Log.debug("Changing configuration: (#{group}:#{key}): #{val.to_s}")
  val=val.to_s if val!=nil
  writeini(EltenPath.join(Dirs.eltendata, "elten.ini"), group, key, val)
end

module LocalConfig
  extend EltenAPI

  TYPES = [:array, :numeric, :string, :hash, :bool, :bool_or_nil, :array_of_numerics, :array_of_strings].freeze
  DEFAULT_UNSPECIFIED = Object.new.freeze
  CONFERENCE_MOTDS_KEY = "ConferenceMOTDs"
  LEGACY_BOOLEAN_KEYS = [
    "BlogShowUnknownLanguages",
    "CalendarShowUnknownLanguages",
    "ConferenceShowUnknownLanguages",
    "ConsoleAutoClearInput",
    "ConsoleAutoClearOutput",
    "ConsoleDontCopySource",
    "ForumHideSignatures",
    "ForumShowUnknownLanguages",
    "MessagesDefaultToAllMessages",
    "PollsShowUnknownLanguages"
  ].freeze
  LEGACY_NULLABLE_BOOLEAN_MIGRATIONS = {
    "ConferencePushToTalk" => { -1 => nil, 0 => false, 1 => true }.freeze
  }.freeze
  LEGACY_STRING_MIGRATIONS = {
    "BlogPostsSortBy" => {
      values: { 0 => "blog", 1 => "date" }.freeze,
      default: "blog"
    }.freeze,
    "ForumSort" => {
      values: {
        0 => "default",
        1 => "name_ascending",
        -1 => "name_descending",
        2 => "unread_ascending",
        -2 => "unread_descending"
      }.freeze,
      default: "default"
    }.freeze,
    "PremiumPackagesCurrency" => {
      values: { 0 => "unset", 1 => "PLN", 2 => "EUR", 3 => "USD", 4 => "GBP" }.freeze,
      default: "PLN"
    }.freeze
  }.freeze

  class << self
    def load
      mutex.synchronize { load_unlocked }
      true
    end

    def [](key, default = DEFAULT_UNSPECIFIED, type: nil)
      validate_type(type)
      default = default_for(type) if default.equal?(DEFAULT_UNSPECIFIED)
      expected_type = type || type_for(default)
      if expected_type != nil && !type_matches?(default, expected_type)
        raise ArgumentError, "Invalid default value for LocalConfig type #{expected_type.inspect}"
      end
      return deep_copy(default) if !key.is_a?(String)

      mutex.synchronize do
        load_unlocked
        if !@values.key?(key)
          @values[key] = deep_copy(default)
          @dirty = true
          persist_unlocked
          return deep_copy(default)
        end

        value = @values[key]
        if expected_type != nil && !type_matches?(value, expected_type)
          Log.warning("Invalid local configuration value for #{key}: #{value.inspect}; using #{default.inspect}")
          return deep_copy(default)
        end
        deep_copy(value)
      end
    end

    def []=(key, value)
      return 0 if !key.is_a?(String)
      if !json_value?(value)
        Log.warning("Unsupported local configuration value for #{key}: #{value.inspect}")
        return 0
      end

      mutex.synchronize do
        load_unlocked
        return value if @values.key?(key) && @values[key] == value
        @values[key] = deep_copy(value)
        @dirty = true
        persist_unlocked
      end
      value
    end

    def save
      mutex.synchronize do
        load_unlocked
        saved = persist_unlocked
        cleanup_legacy_unlocked if saved
        saved
      end
    end

    private

    def mutex
      @mutex ||= Mutex.new
    end

    def load_unlocked
      return if @loaded

      @values = {}
      @dirty = false
      @legacy_pending = false
      @legacy_conference_motds_pending = false
      if File.file?(data_path)
        @values = read_json
        @legacy_pending = legacy_section?
      else
        @values, @legacy_pending = read_legacy
        @dirty = true
      end
      migrate_legacy_conference_motds_unlocked
      @dirty ? persist_unlocked : cleanup_legacy_unlocked
      @loaded = true
    rescue Exception => e
      Log.warning("Cannot load local configuration: #{e.class}: #{e.message}")
      @values = {}
      @dirty = false
      @legacy_pending = false
      @legacy_conference_motds_pending = false
      @loaded = true
    end

    def data_path
      EltenPath.join(Dirs.eltendata, "local.json")
    end

    def legacy_path
      EltenPath.join(Dirs.eltendata, "elten.ini")
    end

    def legacy_conference_motds_path
      EltenPath.join(Dirs.eltendata, "conferences_motds.json")
    end

    def read_json
      data = JSON.parse(File.binread(data_path).to_s)
      raise TypeError, "Local configuration must be a JSON object" if !data.is_a?(Hash)
      raise TypeError, "Local configuration contains an unsupported value" if !json_value?(data)
      data
    end

    def read_legacy
      values = {}
      in_local = false
      section_found = false
      elten_read_ini_lines(legacy_path).each do |line|
        text = line.to_s.strip
        section = text.match(/^\[(.+?)\]\s*$/)
        if section != nil
          in_local = section[1].casecmp("local") == 0
          section_found = true if in_local
          next
        end
        next if !in_local
        entry = text.match(/^([^=]+?)\s*=\s*(.*)$/)
        next if entry == nil
        key = entry[1].to_s.strip
        next if values.key?(key)
        values[key] = migrate_legacy_value(key, parse_legacy_value(entry[2]))
      end
      [values, section_found]
    end

    def parse_legacy_value(value)
      text = value.to_s
      return text.to_i if !text.start_with?("[")
      text[1...-1].to_s.split(",").map(&:to_i)
    end

    def migrate_legacy_value(key, value)
      return value == 1 if LEGACY_BOOLEAN_KEYS.include?(key)
      nullable_boolean = LEGACY_NULLABLE_BOOLEAN_MIGRATIONS[key]
      return nullable_boolean.fetch(value, false) if nullable_boolean != nil
      migration = LEGACY_STRING_MIGRATIONS[key]
      return value if migration == nil
      migration[:values].fetch(value, migration[:default])
    end

    def legacy_section?
      read_legacy[1]
    end

    def migrate_legacy_conference_motds_unlocked
      path = legacy_conference_motds_path
      return if !File.file?(path)

      motds = JSON.parse(File.binread(path).to_s)
      if !conference_motds?(motds)
        raise TypeError, "Conference MOTDs must be a JSON object with string keys and values"
      end
      if !conference_motds?(@values[CONFERENCE_MOTDS_KEY])
        @values[CONFERENCE_MOTDS_KEY] = motds
        @dirty = true
      end
      @legacy_conference_motds_pending = true
    rescue Exception => e
      Log.warning("Cannot migrate conferences_motds.json: #{e.class}: #{e.message}")
    end

    def conference_motds?(value)
      value.is_a?(Hash) && value.all? { |uuid, digest| uuid.is_a?(String) && digest.is_a?(String) }
    end

    def cleanup_legacy_unlocked
      ini_cleaned = cleanup_legacy_ini_unlocked
      motds_cleaned = cleanup_legacy_conference_motds_unlocked
      ini_cleaned && motds_cleaned
    end

    def cleanup_legacy_ini_unlocked
      return true if !@legacy_pending

      lines = elten_read_ini_lines(legacy_path)
      result = []
      in_local = false
      lines.each do |line|
        text = line.to_s.strip
        section = text.match(/^\[(.+?)\]\s*$/)
        if section != nil
          in_local = section[1].casecmp("local") == 0
          result << line if !in_local
        elsif !in_local
          result << line
        end
      end
      write_atomic(legacy_path, result.join("\r\n") + "\r\n")
      @legacy_pending = false
      true
    rescue Exception => e
      Log.warning("Cannot remove migrated local configuration from elten.ini: #{e.class}: #{e.message}")
      false
    end

    def cleanup_legacy_conference_motds_unlocked
      return true if !@legacy_conference_motds_pending

      path = legacy_conference_motds_path
      File.delete(path) if File.file?(path)
      @legacy_conference_motds_pending = false
      true
    rescue Exception => e
      Log.warning("Cannot remove migrated conferences_motds.json: #{e.class}: #{e.message}")
      false
    end

    def persist_unlocked
      return true if !@dirty
      write_atomic(data_path, JSON.pretty_generate(@values))
      @dirty = false
      cleanup_legacy_unlocked
      true
    rescue Exception => e
      Log.warning("Cannot save local configuration: #{e.class}: #{e.message}")
      false
    end

    def write_atomic(path, contents)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp-#{$$}-#{Thread.current.object_id}"
      File.binwrite(tmp, contents)
      File.rename(tmp, path)
      true
    ensure
      File.delete(tmp) if tmp != nil && File.file?(tmp) rescue nil
    end

    def validate_type(type)
      raise ArgumentError, "Unsupported LocalConfig type #{type.inspect}" if type != nil && !TYPES.include?(type)
    end

    def default_for(type)
      case type
      when :array, :array_of_numerics, :array_of_strings
        []
      when :numeric, nil
        0
      when :string
        ""
      when :hash
        {}
      when :bool
        false
      when :bool_or_nil
        nil
      end
    end

    def type_for(value)
      case value
      when Array
        :array
      when Numeric
        :numeric
      when String
        :string
      when Hash
        :hash
      when true, false
        :bool
      end
    end

    def type_matches?(value, type)
      case type
      when :array
        value.is_a?(Array)
      when :numeric
        value.is_a?(Numeric)
      when :string
        value.is_a?(String)
      when :hash
        value.is_a?(Hash)
      when :bool
        value == true || value == false
      when :bool_or_nil
        value == nil || value == true || value == false
      when :array_of_numerics
        value.is_a?(Array) && value.all? { |entry| entry.is_a?(Numeric) }
      when :array_of_strings
        value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }
      end
    end

    def json_value?(value)
      case value
      when Hash
        value.all? { |key, entry| key.is_a?(String) && json_value?(entry) }
      when Array
        value.all? { |entry| json_value?(entry) }
      when String, Integer, NilClass, TrueClass, FalseClass
        true
      when Float
        value.finite?
      else
        false
      end
    end

    def deep_copy(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, entry), result| result[key.dup] = deep_copy(entry) }
      when Array
        value.map { |entry| deep_copy(entry) }
      when String
        value.dup
      else
        value
      end
    end
  end
end
end
