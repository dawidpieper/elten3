# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require_relative "programsigning" if !defined?(Programs::ProgramSigning)
require "fileutils"
require "json"
require "ostruct"
require "stringio"

module Programs
  MAGIC = "Elten3AppPackage".b
  ELTEN_API_VERSION = "3.0".freeze
  MANIFEST_BEGIN = /^\=begin[ \t]+Elten3AppInfo[ \t]*\r?\n/.freeze
  MANIFEST_END = /^\=end[ \t]+Elten3AppInfo[ \t]*$/m.freeze
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i.freeze
  SOUND_EXTENSIONS = %w[.ogg .opus .wav .wave .mp3 .flac .aac .m4a .wma .spx .webm].freeze

  @@programs = []
  @@bypaths = {}
  @@listeners = []
  @@configs = {}
  @@runtimes = {}
  @@runtime_by_prefix = {}
  @@runtime_by_root = {}
  @@apps_registry_cache = nil

  class ProgramError < StandardError
  end

  class EventListener
    attr_accessor :event, :cls, :proc

    def call
      proc.call if proc.is_a?(Proc)
    end
  end

  class Manifest
    attr_reader :id, :name, :version, :build_id, :elten_api_version, :author, :main, :main_class, :platforms, :menu, :gems, :raw

    def initialize(raw, source)
      @raw = raw.is_a?(Hash) ? raw : {}
      @source = source
      @id = string_value("id")
      @name = string_value("name")
      @version = string_value("version", "version_string")
      @build_id = normalize_build_id(string_value("build_id", "BuildID"))
      @elten_api_version = string_value("EltenAPIVersion")
      @author = string_value("author")
      @main = string_value("main", "file")
      @main_class = string_value("main_class", "class")
      @platforms = Array(@raw["platforms"]).map { |platform| platform.to_s.downcase.strip }.reject { |platform| platform == "" }
      @menu = @raw["menu"].is_a?(Hash) ? @raw["menu"] : {}
      @gems = Array(@raw["gems"]).map { |gem| gem.is_a?(Hash) ? gem["name"].to_s : gem.to_s }.reject { |gem| gem == "" }
      validate
    end

    def menu_label
      value = @menu["main"]
      value = @name if value == nil || value.to_s == ""
      value.to_s
    end

    def hidden?
      @menu["hidden"] == true
    end

    def user_menu
      @menu["user"].is_a?(Hash) ? @menu["user"] : {}
    end

    def supports_current_platform?
      family = Programs.platform_family
      target = Programs.platform_target
      @platforms.include?("all") || @platforms.include?("universal") || @platforms.include?("*") || @platforms.include?(family) || @platforms.include?(target)
    end

    def namespace_name
      "P" + @id.delete("-")
    end

    def to_config(main_file = nil)
      {
        :id => @id,
        :name => @name,
        :version => @version,
        :build_id => @build_id,
        :elten_api_version => @elten_api_version,
        :author => @author,
        :file => main_file || @main,
        :main_class => @main_class,
        :platforms => @platforms,
        :gems => @gems
      }
    end

    private

    def string_value(*keys)
      keys.each do |key|
        value = @raw[key]
        return value.to_s if value != nil && value.to_s != ""
      end
      ""
    end

    def integer_value(*keys)
      keys.each do |key|
        value = @raw[key]
        return Integer(value) if value != nil && value.to_s != ""
      end
      nil
    rescue ArgumentError
      nil
    end

    def normalize_build_id(value)
      return nil if value == nil

      text = value.to_s.strip
      return nil if text == "" || text == "0"

      text
    end

    def validate
      raise ProgramError, "Missing program id in #{@source}" if @id == ""
      raise ProgramError, "Invalid program UUID #{@id.inspect} in #{@source}" if @id !~ UUID_PATTERN
      raise ProgramError, "Missing program name in #{@source}" if @name == ""
      raise ProgramError, "Missing program author in #{@source}" if @author == ""
      raise ProgramError, "Missing program version in #{@source}" if @version == ""
      raise ProgramError, "Missing program build_id in #{@source}" if @build_id == nil
      raise ProgramError, "Missing EltenAPIVersion in #{@source}" if @elten_api_version == ""
      raise ProgramError, "Program #{@name} requires unsupported Elten API #{@elten_api_version}" if !Programs.api_version_compatible?(@elten_api_version)
      raise ProgramError, "Missing program main_class in #{@source}" if @main_class == ""
      raise ProgramError, "Missing program platforms in #{@source}" if @platforms.empty?
    end
  end

  class CodeManifestParser
    class << self
      def parse_file(file)
        parse(File.binread(file), file)
      end

      def parse(code, source)
        json = extract(code, source)
        Manifest.new(JSON.parse(json), source)
      rescue JSON::ParserError => e
        raise ProgramError, "Invalid Elten3AppInfo JSON in #{source}: #{e.message}"
      end

      def has_manifest?(code)
        MANIFEST_BEGIN.match?(code.to_s)
      end

      private

      def extract(code, source)
        text = code.to_s
        start_match = MANIFEST_BEGIN.match(text)
        raise ProgramError, "Missing Elten3AppInfo in #{source}" if start_match == nil
        rest = text[start_match.end(0)..-1].to_s
        end_match = MANIFEST_END.match(rest)
        raise ProgramError, "Unclosed Elten3AppInfo in #{source}" if end_match == nil
        rest[0...end_match.begin(0)].to_s
      end
    end
  end

  class EltenAppPackage
    attr_reader :file, :manifest, :code_files, :sound_files, :language_files, :native_files, :signature_info

    def initialize(file)
      @file = file
      @code_files = {}
      @sound_files = {}
      @language_files = {}
      @native_files = {}
      @signature_info = nil
      parse
    end

    def self.package?(file)
      return false if !File.file?(file)
      header = File.open(file, "rb") { |io| io.read([MAGIC.bytesize, ProgramSigning::SIGNATURE_MAGIC.bytesize].max) }.to_s.b
      header.start_with?(MAGIC) || header.start_with?(ProgramSigning::SIGNATURE_MAGIC)
    rescue Exception
      false
    end

    def self.manifest_from_data(data, source = "eltenapp")
      data = ProgramSigning.decode_package(data.to_s.b, :source => source)[:code_file]
      raise ProgramError, "Wrong eltenapp header in #{source}" if data.byteslice(0, MAGIC.bytesize) != MAGIC
      metadata_size = data.byteslice(MAGIC.bytesize, 4).to_s.unpack1("L<")
      raise ProgramError, "Missing eltenapp metadata in #{source}" if metadata_size == nil
      metadata = decompress_data(data.byteslice(MAGIC.bytesize + 4, metadata_size), "metadata")
      Manifest.new(JSON.parse(metadata), source)
    rescue JSON::ParserError => e
      raise ProgramError, "Invalid eltenapp metadata JSON in #{source}: #{e.message}"
    end

    private

    def parse
      decoded = ProgramSigning.decode_package(File.binread(@file), :source => @file)
      verify_package_signature(decoded)
      StringIO.open(decoded[:code_file]) do |io|
        magic = io.read(MAGIC.bytesize)
        raise ProgramError, "Wrong eltenapp header in #{@file}" if magic != MAGIC
        metadata_size = read_u32(io)
        metadata_payload = io.read(metadata_size).to_s.b
        metadata = decompress(metadata_payload, "metadata")
        @manifest = Manifest.new(JSON.parse(metadata), @file)
        until io.eof?
          type = read_u8(io)
          case type
          when 1
            name, content = read_named_content(io)
            @code_files[name] = decompress(content, name).to_s
          when 2
            name, content = read_named_content(io)
            @sound_files[name] = content
          when 3
            code = normalize_language_code(io.read(2).to_s)
            content_size = read_u32(io)
            content = io.read(content_size).to_s.b
            @language_files[code] = decompress(content, "locale/#{code}.mo").to_s.b
          when 4
            name, content = read_named_content(io)
            @native_files[name] = content
          else
            raise ProgramError, "Unsupported eltenapp file type #{type} in #{@file}"
          end
        end
      end
      @manifest.instance_variable_set(:@main, "__app.rb") if @manifest.main == "" && @code_files.key?("__app.rb")
      raise ProgramError, "Missing main file in #{@file}" if @manifest.main == ""
      raise ProgramError, "Main file #{@manifest.main} not found in #{@file}" if !@code_files.key?(normalize_name(@manifest.main))
    rescue JSON::ParserError => e
      raise ProgramError, "Invalid eltenapp metadata JSON in #{@file}: #{e.message}"
    rescue ProgramSigning::SignatureError => e
      raise ProgramError, "Invalid or missing eltenapp signature in #{@file}: #{e.message}"
    end

    def decompress(data, name)
      self.class.decompress_data(data, name)
    rescue LoadError
      raise ProgramError, "ZSTD support is unavailable while reading #{name}"
    rescue Exception => e
      raise ProgramError, "Cannot decompress #{name}: #{e.class}: #{e.message}"
    end

    def self.decompress_data(data, name)
      require "zstd-ruby" if !defined?(Zstd)
      Zstd.decompress(data.to_s.b)
    end

    def read_u8(io)
      data = io.read(1)
      raise ProgramError, "Unexpected end of #{@file}" if data == nil || data.bytesize != 1
      data.unpack1("C")
    end

    def read_u16(io)
      data = io.read(2)
      raise ProgramError, "Unexpected end of #{@file}" if data == nil || data.bytesize != 2
      data.unpack1("S<")
    end

    def read_u32(io)
      data = io.read(4)
      raise ProgramError, "Unexpected end of #{@file}" if data == nil || data.bytesize != 4
      data.unpack1("L<")
    end

    def read_named_content(io)
      name_size = read_u16(io)
      name = io.read(name_size).to_s.force_encoding(Encoding::UTF_8)
      name = sanitize_name(name)
      content_size = read_u32(io)
      [name, io.read(content_size).to_s.b]
    end

    def verify_package_signature(decoded)
      @signature_info = ProgramSigning.verify_decoded!(decoded, :source => @file)
    rescue ProgramSigning::SignatureError => e
      if ProgramSigning.developer_mode?
        Log.warning("Program signature ignored in developer mode for #{@file}: #{e.message}")
      else
        raise ProgramError, "Invalid or missing eltenapp signature in #{@file}: #{e.message}"
      end
    end

    def sanitize_name(name)
      normalized = normalize_name(name)
      raise ProgramError, "Unsafe path #{name.inspect} in #{@file}" if normalized == "" || normalized.start_with?("/") || normalized.include?("../")
      normalized
    end

    def normalize_name(name)
      name.to_s.tr("\\", "/").sub(/\A\.\//, "")
    end

    def normalize_language_code(code)
      code.to_s[0, 2].to_s.downcase
    end
  end

  class SoundAsset
    attr_reader :name, :logical_path, :extension

    def initialize(runtime, name, logical_path, physical_path: nil, data: nil)
      @runtime = runtime
      @name = name.to_s
      @logical_path = logical_path.to_s
      @physical_path = physical_path
      @data = data == nil ? nil : data.to_s.b
      @extension = File.extname(@logical_path).downcase
    end

    def path
      return @physical_path if @physical_path != nil
      @runtime.materialize_asset(@logical_path, @data)
    end

    def data
      return File.binread(@physical_path) if @physical_path != nil && File.file?(@physical_path)
      @data.to_s.b
    end

    def create_sound(sample: false, loop: false)
      return nil if !defined?(::Sound)
      sound = nil
      if sample == true || (@physical_path != nil && File.file?(@physical_path))
        source = path
        return nil if source == nil || source.to_s == ""
        sound = ::Sound.new(source, sample: sample, loop: loop)
      else
        source = @data.to_s.b
        return nil if source.bytesize == 0
        sound = ::Sound.new(stream: source.dup.b, loop: loop)
      end
      return sound if sound.opened?
      sound.close rescue nil
      nil
    rescue Exception => e
      Log.warning("Program sound asset #{@name} failed: #{e.class}: #{e.message}")
      sound.close rescue nil
      nil
    end

    def play(volume: 100, pitch: 100, pan: 50, ignore_elten_volume: false)
      return false if !defined?(Bass)
      stream = create_bass_stream
      return false if stream.to_i == 0
      apply_bass_attributes(stream, volume: volume, pitch: pitch, pan: pan, ignore_elten_volume: ignore_elten_volume)
      Bass::BASS_ChannelPlay.call(stream, 0) != 0
    rescue Exception => e
      Log.warning("Program sound asset #{@name} play failed: #{e.class}: #{e.message}")
      false
    end

    private

    def create_bass_stream
      if @physical_path != nil && File.file?(@physical_path)
        Bass.create_file_stream_from_path(@physical_path, 0, Bass::BASS_STREAM_AUTOFREE)
      else
        source = @data.to_s
        return 0 if source.bytesize == 0
        Bass.create_file_stream_from_memory(source, Bass::BASS_STREAM_AUTOFREE)
      end
    end

    def apply_bass_attributes(stream, volume:, pitch:, pan:, ignore_elten_volume:)
      volume = normalize_volume(volume, ignore_elten_volume: ignore_elten_volume)
      Bass::BASS_ChannelSetAttribute.call(stream, 2, volume.to_f / 100.0 * 0.5)
      apply_pitch(stream, pitch)
      if Configuration.usepan.to_i == 1
        Bass::BASS_ChannelSetAttribute.call(stream, 3, pan.to_f / 50.0 - 1.0)
      end
    end

    def normalize_volume(volume, ignore_elten_volume:)
      volume = volume.to_f
      if ignore_elten_volume == true
        volume = volume.abs
        volume = 100 if volume > 100
        return volume
      end
      if volume >= 0
        master = Configuration.volume.to_f
        volume = volume * master / 100.0
        volume = 100 if volume > 100
        volume = 1 if volume < 1
        volume.to_i
      else
        volume *= -1
        volume = 100 if volume > 100
        volume
      end
    end

    def apply_pitch(stream, pitch)
      return if pitch.to_f == 100.0
      f = [0].pack("f")
      Bass::BASS_ChannelGetAttribute.call(stream, 1, f)
      frequency = f.unpack1("f").to_f * pitch.to_f / 100.0
      Bass::BASS_ChannelSetAttribute.call(stream, 1, frequency)
    end
  end

  class Runtime
    attr_reader :entry_id, :root, :manifest, :namespace, :virtual_files, :sound_assets, :language_files

    def initialize(entry_id:, root:, manifest:, virtual_files: {}, language_files: {}, native_files: {}, package_file: nil)
      @entry_id = entry_id
      @root = root
      @manifest = manifest
      @virtual_files = {}
      virtual_files.each { |name, code| @virtual_files[normalize_name(name)] = code.to_s }
      @native_files = {}
      native_files.each { |name, data| @native_files[normalize_name(name).downcase] = data.to_s.b }
      @package_file = package_file
      @loaded = {}
      @native_loaded = {}
      @native_materialized = false
      @sound_assets = {}
      @language_files = {}
      language_files.each { |code, data| @language_files[normalize_language_code(code)] = data.to_s.b }
      @namespace = Programs.namespace_for(manifest)
      @gem_load_paths = collect_gem_load_paths
      @native_lookup = build_native_lookup
      collect_physical_sound_assets
      Programs.register_runtime(self)
    end

    def virtual_prefix
      "eltenapp://#{@manifest.id}/"
    end

    def main_virtual_path
      virtual_path(@manifest.main)
    end

    def load_main
      load_program_file(@manifest.main)
    end

    def load_program_file(name)
      logical = normalize_name(name)
      return false if @loaded[logical]
      code = code_for(logical)
      raise ProgramError, "Cannot load missing program file #{logical}" if code == nil
      @loaded[logical] = true
      previous = Thread.current[:elten_program_runtime]
      Thread.current[:elten_program_runtime] = self
      @namespace.module_eval(code, virtual_path(logical), 1)
      true
    ensure
      Thread.current[:elten_program_runtime] = previous
    end

    def require_file(name)
      candidate_names(name).each do |logical|
        if code_for(logical) != nil
          load_program_file(logical)
          return true
        end
      end
      native = native_for(name)
      if native != nil
        load_native_file(native[0])
        return true
      end
      false
    end

    def require_relative_file(name, caller_path)
      base = logical_path_from_runtime_path(caller_path)
      return false if base == nil
      require_file(join_logical(File.dirname(base), name.to_s))
    end

    def code_for(logical)
      logical = normalize_name(logical)
      return @virtual_files[logical] if @virtual_files.key?(logical)
      physical = physical_path(logical)
      return File.binread(physical) if physical != nil && File.file?(physical)
      nil
    end

    def physical_path(logical = "")
      return nil if @root == nil || @root == ""
      logical = normalize_name(logical)
      return @root if logical == ""
      path = File.expand_path(EltenPath.join(@root, logical))
      root_path = File.expand_path(@root)
      return nil if path != root_path && !path.start_with?(root_path + File::SEPARATOR)
      path
    rescue Exception
      nil
    end

    def virtual_path(logical)
      virtual_prefix + normalize_name(logical)
    end

    def root_path
      @root.to_s
    end

    def asset_path(path)
      physical_path(path)
    end

    def data_dir
      path = Programs.app_data_dir(@entry_id)
      FileUtils.mkdir_p(path) if !File.directory?(path)
      path
    end

    def data_path(path = "")
      path = normalize_name(path)
      return data_dir if path == ""
      full = File.expand_path(EltenPath.join(data_dir, path))
      root = File.expand_path(data_dir)
      raise ProgramError, "Unsafe app data path #{path.inspect}" if full != root && !full.start_with?(root + File::SEPARATOR)
      FileUtils.mkdir_p(File.dirname(full)) if !File.directory?(File.dirname(full))
      full
    end

    def cache_path(path = "")
      path = normalize_name(path)
      root = Programs.app_cache_dir(@entry_id)
      FileUtils.mkdir_p(root) if !File.directory?(root)
      return root if path == ""
      full = File.expand_path(EltenPath.join(root, path))
      root = File.expand_path(root)
      raise ProgramError, "Unsafe app cache path #{path.inspect}" if full != root && !full.start_with?(root + File::SEPARATOR)
      FileUtils.mkdir_p(File.dirname(full)) if !File.directory?(File.dirname(full))
      full
    end

    def read_json(path, default: nil)
      file = data_path(path)
      return default if !File.file?(file)
      JSON.parse(File.binread(file))
    rescue Exception
      default
    end

    def write_json(path, data)
      write_text(path, JSON.generate(data))
    end

    def read_text(path, default: "")
      file = data_path(path)
      return default if !File.file?(file)
      File.binread(file).to_s.force_encoding(Encoding::UTF_8)
    rescue Exception
      default
    end

    def write_text(path, text)
      write_binary(path, text.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace))
    end

    def read_binary(path, default: "".b)
      file = data_path(path)
      return default if !File.file?(file)
      File.binread(file)
    rescue Exception
      default
    end

    def write_binary(path, data)
      file = data_path(path)
      tmp = file + ".tmp-#{$$}-#{Thread.current.object_id}"
      File.binwrite(tmp, data.to_s.b)
      FileUtils.mv(tmp, file)
      true
    ensure
      File.delete(tmp) if tmp != nil && File.file?(tmp) rescue nil
    end

    def add_sound_asset(logical_path, data: nil, physical_path: nil)
      ext = File.extname(logical_path).downcase
      return if !SOUND_EXTENSIONS.include?(ext)
      name = File.basename(logical_path, ext)
      @sound_assets[name] = SoundAsset.new(self, name, logical_path, physical_path: physical_path, data: data)
    end

    def sound_asset(name)
      @sound_assets[name.to_s]
    end

    def sound_asset_path(name)
      asset = sound_asset(name)
      asset == nil ? nil : asset.path
    end

    def sound_asset_data(name)
      asset = sound_asset(name)
      asset == nil ? nil : asset.data
    end

    def create_sound_from_asset(name, sample: false, loop: false)
      asset = sound_asset(name)
      asset == nil ? nil : asset.create_sound(sample: sample, loop: loop)
    end

    def language_data(code)
      code = normalize_language_code(code)
      data = @language_files[code]
      return data if data != nil
      path = physical_path(EltenPath.join("locale", "#{code}.mo"))
      return File.binread(path) if path != nil && File.file?(path)
      nil
    end

    def play_app_sound(name, volume: 100, pitch: 100, pan: 50, ignore_elten_volume: false)
      asset = sound_asset(name)
      asset != nil && asset.play(volume: volume, pitch: pitch, pan: pan, ignore_elten_volume: ignore_elten_volume)
    rescue Exception => e
      Log.warning("Program sound #{name} failed: #{e.class}: #{e.message}")
      false
    end

    def materialize_asset(logical_path, data)
      file = cache_path(EltenPath.join("assets", logical_path))
      File.binwrite(file, data.to_s.b) if !File.file?(file) || File.size(file) != data.to_s.bytesize
      file
    end

    def materialize_native_files
      return if @native_materialized
      platform_prefix = Programs.platform_target.downcase + "/"
      @native_files.each do |logical, data|
        next if !logical.start_with?(platform_prefix)
        relative = logical[platform_prefix.size..-1]
        file = cache_path(EltenPath.join("native", relative))
        File.binwrite(file, data.to_s.b) if !File.file?(file) || File.size(file) != data.to_s.bytesize
      end
      @native_materialized = true
    end

    private

    def collect_physical_sound_assets
      audio = physical_path("Audio")
      return if audio == nil || !File.directory?(audio)
      Dir.children(audio).each do |entry|
        path = File.join(audio, entry)
        add_sound_asset("Audio/#{entry}", physical_path: path) if File.file?(path)
      end
    rescue Exception => e
      Log.warning("Cannot collect program sound assets for #{@entry_id}: #{e.class}: #{e.message}")
    end

    def candidate_names(name)
      base = normalize_name(name)
      values = [base]
      values << "#{base}.rb" if File.extname(base) == ""
      values << EltenPath.join(base, "__app.rb") if File.extname(base) == ""
      if !base.start_with?("gems/")
        @gem_load_paths.each do |load_path|
          gem_base = join_logical(load_path, base)
          values << gem_base
          values << "#{gem_base}.rb" if File.extname(gem_base) == ""
        end
      end
      values.uniq
    end

    def native_for(name)
      native_candidate_names(name).each do |candidate|
        logical = @native_lookup[candidate]
        return [logical, @native_files[logical]] if logical != nil && @native_files.key?(logical)
      end
      nil
    end

    def native_candidate_names(name)
      ext = Programs.native_extension
      base = normalize_name(name)
      values = [base]
      values << "#{base}#{ext}" if File.extname(base) == ""
      values << "#{base}.so" if File.extname(base) == "" && ext != ".so"
      if !base.start_with?("gems/")
        @gem_load_paths.each do |load_path|
          gem_base = join_logical(load_path, base)
          values << gem_base
          values << "#{gem_base}#{ext}" if File.extname(gem_base) == ""
          values << "#{gem_base}.so" if File.extname(gem_base) == "" && ext != ".so"
        end
      end
      values.map { |value| normalize_name(value).downcase }.uniq
    end

    def load_native_file(logical)
      return false if @native_loaded[logical]
      materialize_native_files
      relative = logical.sub(/\A#{Regexp.escape(Programs.platform_target.downcase)}\//, "")
      path = cache_path(EltenPath.join("native", relative))
      @native_loaded[logical] = true
      begin
        Programs.original_require(path)
      rescue Exception
        @native_loaded.delete(logical)
        raise
      end
      true
    end

    def collect_gem_load_paths
      paths = @virtual_files.keys.grep(/\Agems\/[^\/]+\/lib\//).map { |file| file.sub(/\/lib\/.*\z/, "/lib") }
      gems_root = physical_path("gems")
      if gems_root != nil && File.directory?(gems_root)
        Dir.glob(File.join(gems_root, "*", "lib")).each do |path|
          rel = EltenPath.relative_from(path, @root) rescue nil
          paths << normalize_name(rel) if rel != nil
        end
      end
      paths.uniq.sort
    end

    def build_native_lookup
      lookup = {}
      platform_prefix = Programs.platform_target.downcase + "/"
      @native_files.keys.each do |logical|
        next if !logical.start_with?(platform_prefix)
        relative = logical[platform_prefix.size..-1]
        native_aliases(relative).each { |key| lookup[key] ||= logical }
      end
      lookup
    end

    def native_aliases(relative)
      relative = normalize_name(relative).downcase
      values = [relative, relative.sub(/\.(so|bundle|dll|dylib)\z/i, "")]
      if (index = relative.index("/lib/")) != nil
        tail = relative[(index + 5)..-1]
        values << tail
        values << tail.sub(/\.(so|bundle|dll|dylib)\z/i, "")
      end
      if (index = relative.index("/extensions/")) != nil
        tail = relative[(index + 12)..-1]
        values << tail
        values << tail.sub(/\.(so|bundle|dll|dylib)\z/i, "")
      end
      values << File.basename(relative)
      values << File.basename(relative).sub(/\.(so|bundle|dll|dylib)\z/i, "")
      values.compact.reject { |value| value == "" }.uniq
    end

    def logical_path_from_runtime_path(path)
      normalized = path.to_s.tr("\\", "/")
      return normalized[virtual_prefix.size..-1] if normalized.start_with?(virtual_prefix)
      physical = File.expand_path(path).tr("\\", "/").downcase rescue nil
      root = File.expand_path(@root).tr("\\", "/").downcase rescue nil
      return nil if physical == nil || root == nil
      return "" if physical == root
      return physical[(root.size + 1)..-1] if physical.start_with?(root + "/")
      nil
    end

    def join_logical(base, path)
      parts = []
      (normalize_name(base).split("/") + normalize_name(path).split("/")).each do |part|
        next if part == "" || part == "."
        part == ".." ? parts.pop : parts << part
      end
      parts.join("/")
    end

    def normalize_name(name)
      name.to_s.tr("\\", "/").sub(/\A\.\//, "")
    end

    def normalize_language_code(code)
      code.to_s[0, 2].to_s.downcase
    end
  end

  class << self
    include EltenAPI

    def pathindexed?
      current_runtime != nil
    end

    def current_runtime
      Thread.current[:elten_program_runtime]
    end

    def register_runtime(runtime)
      @@runtimes[runtime.entry_id] = runtime
      @@runtime_by_prefix[runtime.virtual_prefix] = runtime
      if runtime.root.to_s != ""
        root = File.expand_path(runtime.root).tr("\\", "/").downcase rescue nil
        @@runtime_by_root[root] = runtime if root != nil
      end
    end

    def namespace_for(manifest)
      Object.const_set(:EltenPrograms, Module.new) if !Object.const_defined?(:EltenPrograms, false)
      root = Object.const_get(:EltenPrograms)
      name = manifest.namespace_name.to_sym
      if root.const_defined?(name, false)
        namespace = root.const_get(name, false)
        return namespace if runtime_namespace_active?(namespace)
        root.send(:remove_const, name)
      end
      root.const_set(name, Module.new)
    end

    def unregister_runtime(runtime)
      return if runtime == nil
      @@runtime_by_prefix.delete(runtime.virtual_prefix)
      root = File.expand_path(runtime.root).tr("\\", "/").downcase rescue nil
      @@runtime_by_root.delete(root) if root != nil
      remove_runtime_namespace(runtime)
    end

    def runtime_namespace_active?(namespace)
      @@runtimes.each_value.any? { |runtime| runtime.namespace.equal?(namespace) }
    end

    def remove_runtime_namespace(runtime)
      return if runtime == nil || runtime_namespace_active?(runtime.namespace)
      return if !Object.const_defined?(:EltenPrograms, false)
      root = Object.const_get(:EltenPrograms)
      name = runtime.manifest.namespace_name.to_sym
      return if !root.const_defined?(name, false)
      return if !root.const_get(name, false).equal?(runtime.namespace)
      root.send(:remove_const, name)
    rescue Exception => e
      Log.warning("Cannot remove program namespace #{runtime.manifest.namespace_name}: #{e.class}: #{e.message}")
    end

    def remove_all_program_namespaces
      Object.send(:remove_const, :EltenPrograms) if Object.const_defined?(:EltenPrograms, false)
    rescue Exception => e
      Log.warning("Cannot remove program namespaces: #{e.class}: #{e.message}")
    end

    def platform_family
      if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:platform_os)
        EltenSystemHelpers.platform_os.to_s
      elsif defined?(EltenBoot) && EltenBoot.respond_to?(:platform_tags)
        EltenBoot.platform_tags.first.to_s.split("-", 2).first
      else
        "unknown"
      end
    end

    def platform_target
      return EltenSystemHelpers.platform_target if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:platform_target)
      cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
      arch = cpu =~ /arm|aarch64/ ? "arm64" : (cpu =~ /64/ ? "x64" : "x86")
      "#{platform_family}-#{arch}"
    end

    def elten_api_version
      ELTEN_API_VERSION
    end

    def api_version_compatible?(required)
      required_parts = parse_api_version(required)
      current_parts = parse_api_version(ELTEN_API_VERSION)
      return false if required_parts == nil || current_parts == nil
      max = [required_parts.size, current_parts.size].max
      required_parts += [0] * (max - required_parts.size)
      current_parts += [0] * (max - current_parts.size)
      return false if required_parts[0] != current_parts[0]
      (current_parts <=> required_parts).to_i >= 0
    end

    def setup_package_info(file)
      open_zip(file) do |zip|
        entries = zip_entries(zip)
        setup_file = entries.find { |entry| normalize_entry_name(entry.name) == "__manifest.json" }
        raise ProgramError, "Missing __manifest.json in #{file}" if setup_file == nil
        setup_payload = setup_payload_from_json(zip_read(setup_file), "#{file}:__manifest.json")
        packages = entries.select do |entry|
          name = normalize_entry_name(entry.name)
          !name.end_with?("/") && File.extname(name).downcase == ".eltenapp"
        end
        raise ProgramError, "Missing eltenapp payload in #{file}" if packages.empty?
        raise ProgramError, "More than one eltenapp payload in #{file}" if packages.size > 1
        payload_entries = entries.map { |entry| normalize_entry_name(entry.name) }.reject do |name|
          name == "" || name.end_with?("/") || name == "__manifest.json"
        end
        app_entry = packages[0]
        app_name = normalize_entry_name(app_entry.name)
        app_manifest = EltenAppPackage.manifest_from_data(zip_read(app_entry), "#{file}:#{app_name}")
        validate_setup_payload!(setup_payload, app_manifest, file, app_name)
        {
          :payload => setup_payload,
          :manifest => app_manifest,
          :entry => app_name,
          :entries => payload_entries,
          :single_file => payload_entries.size == 1 && payload_entries[0] == app_name,
          :size => (File.size(file) rescue 0)
        }
      end
    rescue Zip::Error => e
      raise ProgramError, "Invalid setup ZIP #{file}: #{e.message}"
    end

    def open_zip(file, &block)
      require "zip"
      Zip::File.open(file, &block)
    end

    def zip_entries(zip)
      zip.entries
    end

    def zip_read(entry)
      entry.get_input_stream { |io| io.read }
    end

    def zip_extract(entry, destination)
      FileUtils.mkdir_p(File.dirname(destination))
      entry.get_input_stream do |input|
        File.open(destination, "wb") do |output|
          while (chunk = input.read(64 * 1024))
            output.write(chunk)
          end
        end
      end
    end

    def safe_zip_entry_name(entry)
      name = normalize_entry_name(entry.respond_to?(:name) ? entry.name : entry.to_s)
      raise ProgramError, "Unsafe package path #{name}" if name == "" || name.start_with?("/") || name.split("/").include?("..") || name.include?(":")

      name
    end

    def zip_directory_entry?(entry)
      name = entry.respond_to?(:name) ? entry.name.to_s : entry.to_s
      name.end_with?("/") || (entry.respond_to?(:directory?) && entry.directory?)
    end

    def validate_setup_package!(file)
      setup_package_info(file)[:payload]
    end

    def require_in_current_program(name)
      runtime = current_runtime || runtime_from_caller
      return false if runtime == nil
      runtime.require_file(name)
    rescue ProgramError => e
      Log.error("Program require failed: #{e.message}")
      false
    end

    def require_relative_in_current_program(name, caller_path)
      runtime = runtime_from_path(caller_path)
      return false if runtime == nil
      runtime.require_relative_file(name, caller_path)
    rescue ProgramError => e
      Log.error("Program require_relative failed: #{e.message}")
      false
    end

    def original_require(path)
      Object.new.send(:__elten_program_original_require, path)
    end

    def native_extension
      return EltenSystemHelpers.native_extension if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:native_extension)
      ".so"
    end

    def runtime_from_caller
      caller_locations(2, 12).each do |location|
        path = location.absolute_path || location.path
        runtime = runtime_from_path(path)
        return runtime if runtime != nil
      end
      nil
    end

    def runtime_from_path(path)
      return nil if path == nil
      normalized = path.to_s.tr("\\", "/")
      @@runtime_by_prefix.each do |prefix, runtime|
        return runtime if normalized.start_with?(prefix)
      end
      physical = File.expand_path(path).tr("\\", "/").downcase rescue nil
      return nil if physical == nil
      @@runtime_by_root.each do |root, runtime|
        return runtime if physical == root || physical.start_with?(root + "/")
      end
      nil
    end

    def register(cls, path = nil, listed = nil)
      return if !cls.is_a?(Class)
      listed = (cls < Program) if listed == nil
      if path != nil
        Log.debug("Registering class #{cls} to program #{path}")
        @@bypaths[path] ||= []
        @@bypaths[path].push(cls) if !@@bypaths[path].include?(cls)
      else
        Log.warning("Registered program class without identification: #{cls}")
      end
      if listed
        @@programs.push(cls) if !@@programs.include?(cls)
        initialize_program_class(cls)
      end
    end

    def discover(cls)
      return if !cls.is_a?(Class)
      return if cls == Program || !(cls < Program)
      runtime = current_runtime || runtime_from_caller
      if runtime != nil
        Log.debug("Discovered program class #{cls.name || cls.inspect}")
      else
        Log.debug("Registered new program class #{cls.name || cls.inspect}")
        register(cls)
      end
    end

    def initialize_program_class(cls)
      return if !cls.is_a?(Class)
      Thread.new do
        begin
          cls.init
          user_menu = cls.respond_to?(:user_menu_options) ? cls.user_menu_options : {}
          if user_menu.is_a?(Hash) && !user_menu.empty?
            $usermenuextra = {} if $usermenuextra == nil
            user_menu.each do |key, value|
              $usermenuextra[key] = [cls] + Array(value)
            end
          end
        rescue Exception => e
          Log.error("Error loading program #{cls}: #{e}, #{e.backtrace}")
        end
      end
    end

    def unregister(program)
      i = 0
      while i < @@listeners.size
        if @@listeners[i].cls == program
          @@listeners.delete_at(i)
        else
          i += 1
        end
      end
      Log.debug("Unregistering program class #{program}")
      return if !program.is_a?(Class)
      @@programs.delete(program)
      if $usermenuextra.is_a?(Hash)
        $usermenuextra.delete_if { |_key, value| value.is_a?(Array) && value[0] == program }
      end
      QuickActions.unregister_program(program) if defined?(QuickActions) && QuickActions.respond_to?(:unregister_program)
      MediaFinders.unregister(program) if defined?(MediaFinders) && MediaFinders.list.include?(program)
      MediaEncoders.unregister(program) if defined?(MediaEncoders) && MediaEncoders.list.include?(program)
      EditBox.unregister_class(program) if defined?(EditBox)
    end

    def delete(path)
      Log.info("Deleting program #{path}")
      classes = @@bypaths[path] || []
      @@bypaths.delete(path)
      @@configs.delete(path)
      runtime = @@runtimes.delete(path)
      unregister_runtime(runtime)
      classes.each { |cls| unregister(cls) }
      classes.size > 0
    end

    def delete_all
      Log.info("Flushing programs data")
      @@bypaths.keys.dup.each { |key| delete(key) }
      count = @@programs.size
      unregister(@@programs[0]) while @@programs.size > 0
      @@configs.clear
      @@runtimes.clear
      @@runtime_by_prefix.clear
      @@runtime_by_root.clear
      remove_all_program_namespaces
      count
    end

    def appsdata_dir
      if defined?(Dirs) && Dirs.respond_to?(:appsdata) && Dirs.appsdata.to_s != ""
        Dirs.appsdata
      elsif defined?(Dirs) && Dirs.respond_to?(:apps) && Dirs.apps.to_s != ""
        File.dirname(Dirs.apps)
      else
        "apps"
      end
    end

    def apps_registry_file
      EltenPath.join(appsdata_dir, "apps.json")
    end

    def apps_data_root
      EltenPath.join(appsdata_dir, "data")
    end

    def apps_cache_root
      EltenPath.join(appsdata_dir, "cache")
    end

    def entry_storage_id(entry)
      name = normalize_entry_name(entry.to_s).split("/")[0].to_s
      name = name.sub(/\.eltenapp\z/i, "")
      name = name.gsub(/[\\\/:*?"<>|]/, "_").strip
      name == "" ? "program" : name
    end

    def app_data_dir(entry)
      EltenPath.join(apps_data_root, storage_id_for_entry(entry))
    end

    def app_cache_dir(entry)
      EltenPath.join(apps_cache_root, storage_id_for_entry(entry))
    end

    def apps_registry
      return @@apps_registry_cache if @@apps_registry_cache != nil
      file = apps_registry_file
      return @@apps_registry_cache = { "apps" => {} } if !File.file?(file)
      data = JSON.parse(File.binread(file).to_s)
      apps = data.is_a?(Hash) && data["apps"].is_a?(Hash) ? data["apps"] : {}
      @@apps_registry_cache = { "apps" => apps }
    rescue Exception => e
      Log.warning("Ignoring invalid apps registry #{file}: #{e.class}: #{e.message}")
      @@apps_registry_cache = { "apps" => {} }
    end

    def save_apps_registry(registry)
      file = apps_registry_file
      FileUtils.mkdir_p(File.dirname(file))
      apps = registry.is_a?(Hash) && registry["apps"].is_a?(Hash) ? registry["apps"] : {}
      apps.each_value do |record|
        next if !record.is_a?(Hash)
        record.delete("entry")
      end
      tmp = "#{file}.tmp-#{$$}-#{Thread.current.object_id}"
      File.binwrite(tmp, JSON.pretty_generate({ "apps" => apps }))
      FileUtils.mv(tmp, file)
      @@apps_registry_cache = { "apps" => apps }
      true
    rescue Exception => e
      Log.warning("Cannot save apps registry #{file}: #{e.class}: #{e.message}")
      false
    ensure
      File.delete(tmp) if tmp != nil && File.file?(tmp) rescue nil
    end

    def registry_record(entry)
      apps_registry["apps"][storage_id_for_entry(entry)]
    end

    def registry_known?(entry)
      registry_record(entry) != nil
    end

    def registry_loaded?(entry)
      record = registry_record(entry)
      record.is_a?(Hash) && record["loaded"] == true
    end

    def registry_uuid_for_storage_id(storage_id)
      record = apps_registry["apps"][storage_id.to_s]
      record.is_a?(Hash) ? record["uuid"].to_s : ""
    end

    def registry_storage_id_for_uuid(uuid)
      uuid = uuid.to_s.downcase
      return "" if uuid == ""
      apps_registry["apps"].each do |storage_id, record|
        next if !record.is_a?(Hash)
        return storage_id.to_s if record["uuid"].to_s.downcase == uuid
      end
      ""
    end

    def storage_id_for_entry(entry, uuid: nil)
      uuid = uuid.to_s.downcase
      if uuid == ""
        begin
          source = discover_source(entry)
          uuid = source[:manifest].id.to_s.downcase if source != nil && source[:manifest] != nil
        rescue Exception
        end
      end
      registered = registry_storage_id_for_uuid(uuid)
      return registered if registered != ""
      entry_storage_id(entry)
    end

    def remove_registry_storage(storage_id)
      storage_id = storage_id.to_s
      return false if storage_id == ""
      registry = apps_registry
      apps = registry["apps"]
      return false if !apps.is_a?(Hash)
      removed = apps.delete(storage_id) != nil
      save_apps_registry(registry) if removed
      removed
    end

    def register_app_entry(entry, uuid:, loaded:, installation_source: nil, installation_source_path: nil)
      registry = apps_registry
      apps = registry["apps"]
      uuid = uuid.to_s.downcase
      key = registry_storage_id_for_uuid(uuid)
      key = entry_storage_id(entry) if key == ""
      apps.each do |other_key, record|
        next if other_key == key || !record.is_a?(Hash)
        record["loaded"] = false if uuid != "" && record["uuid"].to_s.downcase == uuid
      end
      record = apps[key].is_a?(Hash) ? apps[key] : {}
      previous_uuid = record["uuid"].to_s.downcase
      now = Time.now.to_i
      uuid_changed = uuid != "" && previous_uuid != "" && previous_uuid != uuid
      record["uuid"] = uuid if uuid != ""
      record["loaded"] = loaded == true
      record.delete("entry")
      if record["installation_time"].to_s.to_i <= 0 || uuid_changed
        record["installation_time"] = now
      end
      if installation_source != nil
        record["installation_source"] = normalize_installation_source(installation_source)
        source_path = installation_source_path.to_s
        if source_path == ""
          record.delete("installation_source_path")
        else
          record["installation_source_path"] = source_path
        end
        record["update_time"] = now
      elsif record["installation_source"].to_s == ""
        record["installation_source"] = "autodetected"
      end
      record["update_time"] = now if uuid_changed
      record["update_time"] = record["installation_time"].to_s.to_i if record["update_time"].to_s.to_i <= 0
      apps[key] = record
      save_apps_registry(registry)
    end

    def set_entry_loaded(entry, loaded)
      uuid = ""
      begin
        source = discover_source(entry)
        uuid = source[:manifest].id if source != nil && source[:manifest] != nil
      rescue Exception
      end
      record = registry_record(entry)
      uuid = record["uuid"].to_s if uuid == "" && record.is_a?(Hash)
      source = record.is_a?(Hash) ? nil : "autodetected"
      register_app_entry(entry, uuid: uuid, loaded: loaded == true, installation_source: source)
    end

    def normalize_installation_source(source)
      value = source.to_s.downcase.strip.tr("-", "_")
      return "server" if value == "server"
      return "file" if value == "file" || value == "local_file"
      return "autodetected" if value == "" || value == "auto" || value == "autodetect" || value == "autodetected"
      value
    end

    def migrate_legacy_apps_layout
      root = appsdata_dir
      src = Dirs.apps
      return if root.to_s == "" || src.to_s == ""
      return if File.expand_path(root) == File.expand_path(src)
      FileUtils.mkdir_p(src)
      reserved = %w[src data cache apps.json inis]
      Dir.children(root).each do |entry|
        next if reserved.include?(entry.downcase) || ignored_program_entry?(entry)
        old_path = EltenPath.join(root, entry)
        next if !File.file?(old_path) && !File.directory?(old_path)
        next if !legacy_layout_program_entry?(old_path, entry)
        new_path = EltenPath.join(src, entry)
        if File.exist?(new_path)
          Log.warning("Cannot migrate program #{entry}: destination already exists")
          next
        end
        FileUtils.mv(old_path, new_path)
        Log.info("Migrated program #{entry} to apps/src")
      end
    rescue Exception => e
      Log.warning("Legacy apps layout migration failed: #{e.class}: #{e.message}")
    end

    def legacy_layout_program_entry?(path, entry)
      if File.file?(path)
        ext = File.extname(entry).downcase
        return true if ext == ".eltenapp"
        return ext == ".rb" && legacy_program_source?(File.binread(path))
      end
      return false if !File.directory?(path)
      return true if File.file?(EltenPath.join(path, "__app.rb")) || File.file?(EltenPath.join(path, "__app.ini"))
      return true if Dir.glob(EltenPath.join(path, "*.eltenapp")).any?
      Dir.glob(EltenPath.join(path, "**", "*.rb")).any? do |file|
        code = File.binread(file)
        CodeManifestParser.has_manifest?(code) || legacy_program_source?(code)
      end
    rescue Exception
      false
    end

    def load_all
      Log.info("Loading programs")
      apps_registry["apps"].each do |storage_id, record|
        next if !record.is_a?(Hash) || record["loaded"] != true
        entry = registry_entry_for_record(storage_id, record)
        next if entry == "" || ignored_program_entry?(entry)
        next if !program_entry?(entry)
        load_sig(entry, persist: false)
      end
    rescue Exception => e
      Log.error("Programs loading failed: #{e.class}: #{e.message}, #{e.backtrace}")
    end

    def program_entry?(entry)
      return false if ignored_program_entry?(entry)
      full = EltenPath.join(Dirs.apps, entry)
      return File.file?(full) && File.extname(entry).downcase == ".eltenapp" if File.file?(full)
      return false if !File.directory?(full)
      discover_source(entry) != nil
    rescue Exception
      false
    end

    def local_entries
      Dir.children(Dirs.apps).reject { |entry| ignored_program_entry?(entry) }.map { |entry| local_entry(entry) }.compact
    rescue Exception
      []
    end

    def registry_entry_for_record(storage_id, record)
      uuid = record.is_a?(Hash) ? record["uuid"].to_s.downcase : ""
      if uuid != ""
        entry = entry_for_uuid(uuid)
        return entry if entry != ""
      end
      entry_for_storage_id(storage_id)
    end

    def entry_for_uuid(uuid)
      uuid = uuid.to_s.downcase
      return "" if uuid == ""
      Dir.children(Dirs.apps).reject { |entry| ignored_program_entry?(entry) }.each do |entry|
        source = discover_source(entry)
        return entry if source != nil && source[:manifest] != nil && source[:manifest].id.to_s.downcase == uuid
      rescue Exception
      end
      ""
    rescue Exception
      ""
    end

    def entry_for_storage_id(storage_id)
      storage_id = storage_id.to_s
      return "" if storage_id == ""
      entries = Dir.children(Dirs.apps).reject { |entry| ignored_program_entry?(entry) }.select do |entry|
        entry_storage_id(entry) == storage_id && program_entry?(entry)
      end
      entries.size == 1 ? entries[0].to_s : ""
    rescue Exception
      ""
    end

    def installed_entries
      local_entries.select { |entry| entry.respond_to?(:id) && entry.id.to_s != "" }
    end

    def ignored_program_entry?(entry)
      entry.to_s.start_with?(".")
    end

    def installed_entry(entry)
      local_entry(entry)&.then { |record| record.id.to_s == "" ? nil : record }
    rescue Exception => e
      Log.warning("Cannot read installed program #{entry}: #{e.class}: #{e.message}")
      nil
    end

    def local_entry(entry)
      full = EltenPath.join(Dirs.apps, entry)
      source = discover_source(entry)
      if source == nil
        status = legacy_program_entry?(entry, full) ? :legacy : :invalid
        return local_entry_record(
          entry: entry,
          id: "",
          name: entry.sub(/\.eltenapp\z/i, ""),
          version: "",
          build_id: nil,
          author: "",
          size: local_entry_size(full),
          install_type: status,
          status: status
        )
      end

      manifest = source[:manifest]
      status = if !manifest.supports_current_platform?
                 :unsupported_platform
               elsif source[:type] == :ruby && !ProgramSigning.developer_mode?
                 :developer_mode_only
               elsif @@runtimes.key?(entry)
                 :loaded
               else
                 :not_loaded
               end
      local_entry_record(
        entry: entry,
        id: manifest.id,
        name: manifest.name,
        version: manifest.version,
        build_id: manifest.build_id,
        author: manifest.author,
        size: source[:size].to_i,
        install_type: source_install_type(source),
        status: status,
        source_type: source[:type],
        source_path: source[:source_path] || source[:package_file],
        signature_info: source[:signature_info],
        elten_api_version: manifest.elten_api_version,
        platforms: manifest.platforms,
        main: source[:main]
      )
    rescue ProgramError => e
      unsigned_file = unsigned_package_error?(e) ? unsigned_package_file(full) : nil
      unsigned = unsigned_file != nil
      manifest = unsigned ? unsigned_package_manifest(unsigned_file) : nil
      status = if unsigned
                 :not_signed
               elsif legacy_program_entry?(entry, full)
                 :legacy
               else
                 :incompatible
               end
      local_entry_record(
        entry: entry,
        id: manifest == nil ? "" : manifest.id,
        name: manifest == nil ? entry.sub(/\.eltenapp\z/i, "") : manifest.name,
        version: manifest == nil ? "" : manifest.version,
        build_id: manifest == nil ? nil : manifest.build_id,
        author: manifest == nil ? "" : manifest.author,
        size: local_entry_size(full),
        install_type: unsigned ? :application_bundle : status,
        status: status,
        source_type: unsigned ? :eltenapp : nil,
        source_path: unsigned ? unsigned_file : nil,
        elten_api_version: manifest == nil ? "" : manifest.elten_api_version,
        platforms: manifest == nil ? [] : manifest.platforms,
        main: manifest == nil ? "" : manifest.main,
        error: e.message
      )
    rescue Exception => e
      local_entry_record(
        entry: entry,
        id: "",
        name: entry.sub(/\.eltenapp\z/i, ""),
        version: "",
        build_id: nil,
        author: "",
        size: local_entry_size(full),
        install_type: :invalid,
        status: :invalid,
        error: e.message
      )
    end

    def normalize_build_id(value)
      return nil if value == nil

      text = value.to_s.strip
      return nil if text == "" || text == "0"

      text
    end

    def local_entry_record(entry:, id:, name:, version:, build_id:, author:, size:, install_type:, status:, source_type: nil, source_path: nil, signature_info: nil, elten_api_version: "", platforms: [], main: "", error: nil)
      storage_id = storage_id_for_entry(entry, uuid: id)
      record = apps_registry["apps"][storage_id]
      installation_source = record.is_a?(Hash) ? record["installation_source"].to_s : "autodetected"
      installation_source = "autodetected" if installation_source == ""
      OpenStruct.new(
        :id => id.to_s,
        :path => storage_id,
        :storage_id => storage_id,
        :realpath => entry,
        :name => name.to_s,
        :version => version.to_s,
        :build_id => normalize_build_id(build_id),
        :author => author.to_s,
        :size => size.to_i,
        :install_type => install_type,
        :source_type => source_type,
        :source_path => source_path.to_s,
        :signature_info => signature_info,
        :elten_api_version => elten_api_version.to_s,
        :platforms => Array(platforms).map(&:to_s),
        :main => main.to_s,
        :status => status,
        :loaded => status == :loaded,
        :registered => record.is_a?(Hash),
        :registry_loaded => record.is_a?(Hash) && record["loaded"] == true,
        :installation_source => installation_source,
        :installation_source_path => record.is_a?(Hash) ? record["installation_source_path"].to_s : "",
        :installation_time => record.is_a?(Hash) ? record["installation_time"].to_s.to_i : 0,
        :update_time => record.is_a?(Hash) ? record["update_time"].to_s.to_i : 0,
        :error => error.to_s
      )
    end

    def legacy_program_entry?(entry, full = nil)
      full ||= EltenPath.join(Dirs.apps, entry)
      return false if !File.exist?(full)
      if File.file?(full)
        return false if File.extname(full).downcase == ".eltenapp"
        return legacy_program_source?(File.binread(full)) if File.extname(full).downcase == ".rb"
        return false
      end
      return true if File.file?(EltenPath.join(full, "__app.ini"))
      Dir.glob(EltenPath.join(full, "**", "*.rb")).any? { |file| legacy_program_source?(File.binread(file)) }
    rescue Exception
      false
    end

    def legacy_program_source?(code)
      text = code.to_s
      text.include?("EltenAppInfo") && !text.include?("Elten3AppInfo")
    end

    def local_entry_size(path)
      File.directory?(path) ? directory_size(path) : (File.size(path) rescue 0)
    end

    def installed_entry_for_id(id)
      id = id.to_s.downcase
      return nil if id == ""
      installed_entries.find { |entry| entry.respond_to?(:id) && entry.id.to_s.downcase == id }
    end

    def source_install_type(source)
      return :code_file if source[:type] != :eltenapp
      source[:signature_info] == nil ? :application_bundle : :signed_application_bundle
    end

    def unsigned_package_error?(error)
      current = error
      while current != nil
        return true if current.is_a?(ProgramSigning::MissingSignatureError)
        current = current.respond_to?(:cause) ? current.cause : nil
      end
      false
    end

    def unsigned_package_manifest(file)
      EltenAppPackage.manifest_from_data(File.binread(file), file)
    rescue Exception
      nil
    end

    def unsigned_package_file(full)
      return full if File.file?(full) && File.extname(full).downcase == ".eltenapp"
      if File.directory?(full)
        packages = Dir.children(full).select { |name| File.file?(EltenPath.join(full, name)) && File.extname(name).downcase == ".eltenapp" }
        return EltenPath.join(full, packages[0]) if packages.size == 1
      end
      nil
    rescue Exception
      nil
    end

    def load_sig(entry, persist: true, installation_source: nil, installation_source_path: nil)
      Log.info("Loading program #{entry}")
      return true if @@runtimes.key?(entry)
      source = discover_source(entry)
      raise ProgramError, "Program #{entry} has no Elten3AppInfo" if source == nil
      manifest = source[:manifest]
      raise ProgramError, "Code file programs can be loaded only in developer mode" if source[:type] == :ruby && !ProgramSigning.developer_mode?
      @@configs[entry] = manifest.to_config(source[:main])
      if !manifest.supports_current_platform?
        Log.info("Skipping program #{manifest.name}: unsupported platform #{platform_target}")
        return false
      end
      runtime = Runtime.new(
        :entry_id => entry,
        :root => source[:root],
        :manifest => manifest,
        :virtual_files => source[:virtual_files] || {},
        :package_file => source[:package_file],
        :language_files => source[:language_files] || {},
        :native_files => source[:native_files] || {},
      )
      load_runtime_locale(runtime)
      (source[:sound_files] || {}).each { |name, data| runtime.add_sound_asset(name, :data => data) }
      runtime.load_main
      main_class = resolve_main_class(runtime)
      bind_manifest(main_class, runtime)
      register(main_class, entry, true)
      if persist
        source = installation_source
        source = "autodetected" if source == nil && registry_record(entry) == nil
        register_app_entry(entry, uuid: manifest.id, loaded: true, installation_source: source, installation_source_path: installation_source_path)
      end
      true
    rescue Exception => e
      Log.error("Failed to load program #{entry}: #{e.class}: #{e.message}, #{e.backtrace}")
      false
    end

    def discover_source(entry)
      full = EltenPath.join(Dirs.apps, entry)
      if File.file?(full) && File.extname(entry).downcase == ".eltenapp"
        package_source(entry, full, nil)
      elsif File.directory?(full)
        discover_folder_source(entry, full)
      else
        nil
      end
    end

    def discover_folder_source(entry, folder)
      packages = Dir.children(folder).select { |name| File.file?(EltenPath.join(folder, name)) && File.extname(name).downcase == ".eltenapp" }
      if packages.size == 1
        source = package_source(entry, EltenPath.join(folder, packages[0]), folder)
        validate_setup_folder!(folder, source[:manifest], packages[0])
        return source
      elsif packages.size > 1
        raise ProgramError, "More than one eltenapp file in #{entry}"
      end

      default = EltenPath.join(folder, "__app.rb")
      if File.file?(default)
        return code_source(entry, folder, "__app.rb", default)
      end

      matches = []
      Dir.glob(EltenPath.join(folder, "**", "*.rb")).each do |file|
        code = File.binread(file)
        matches << file if CodeManifestParser.has_manifest?(code)
      end
      raise ProgramError, "More than one Elten3AppInfo block in #{entry}" if matches.size > 1
      return nil if matches.empty?
      rel = EltenPath.relative_from(matches[0], folder)
      code_source(entry, folder, rel, matches[0])
    end

    def package_source(entry, package_file, root)
      package = EltenAppPackage.new(package_file)
      size = File.size(package_file) rescue 0
      {
        :type => :eltenapp,
        :manifest => package.manifest,
        :root => root,
        :main => package.manifest.main,
        :package_file => package_file,
        :virtual_files => package.code_files,
        :sound_files => package.sound_files,
        :language_files => package.language_files,
        :native_files => package.native_files,
        :signature_info => package.signature_info,
        :source_path => package_file,
        :size => size
      }
    end

    def validate_setup_folder!(folder, app_manifest, app_entry)
      manifest_file = EltenPath.join(folder, "__manifest.json")
      return if !File.file?(manifest_file)
      payload = setup_payload_from_json(File.binread(manifest_file), manifest_file)
      validate_setup_payload!(payload, app_manifest, manifest_file, app_entry)
    end

    def setup_payload_from_json(data, source)
      setup = JSON.parse(data.to_s)
      type = setup["type"].to_s.downcase
      raise ProgramError, "Invalid setup type in #{source}" if type != "application" && type != "app"
      payload = setup["payload"]
      raise ProgramError, "Missing setup payload in #{source}" if !payload.is_a?(Hash)
      payload
    rescue JSON::ParserError => e
      raise ProgramError, "Invalid setup manifest JSON in #{source}: #{e.message}"
    end

    def validate_setup_payload!(payload, app_manifest, source, app_entry = nil)
      setup_id = payload["id"].to_s
      raise ProgramError, "Missing setup application id in #{source}" if setup_id == ""
      raise ProgramError, "Setup/application UUID mismatch in #{source}: #{setup_id} != #{app_manifest.id}" if setup_id.downcase != app_manifest.id.downcase
      entry = payload["entry"].to_s
      return if app_entry == nil || entry == ""
      raise ProgramError, "Setup entry mismatch in #{source}: #{entry} != #{app_entry}" if normalize_entry_name(entry) != normalize_entry_name(app_entry)
    end

    def normalize_entry_name(name)
      name.to_s.tr("\\", "/").sub(/\A\.\//, "")
    end

    def parse_api_version(version)
      parts = version.to_s.strip.split(".")
      return nil if parts.empty? || parts.any? { |part| part !~ /\A\d+\z/ }
      parts.map(&:to_i)
    end

    def code_source(entry, folder, main, file)
      manifest = CodeManifestParser.parse_file(file)
      manifest.instance_variable_set(:@main, main)
      {
        :type => :ruby,
        :manifest => manifest,
        :root => folder,
        :main => main,
        :virtual_files => {},
        :sound_files => {},
        :native_files => {},
        :source_path => file,
        :size => directory_size(folder)
      }
    end

    def directory_size(folder)
      Dir.glob(EltenPath.join(folder, "**", "*")).sum { |file| File.file?(file) ? File.size(file).to_i : 0 }
    rescue Exception
      0
    end

    def resolve_main_class(runtime)
      parts = runtime.manifest.main_class.split("::").reject { |part| part == "" }
      current = runtime.namespace
      parts.each do |part|
        raise ProgramError, "Invalid main_class #{runtime.manifest.main_class}" if part !~ /\A[A-Z]\w*\z/
        raise ProgramError, "Main class #{runtime.manifest.main_class} not found" if !current.const_defined?(part.to_sym, false)
        current = current.const_get(part.to_sym, false)
      end
      raise ProgramError, "Main class #{runtime.manifest.main_class} is not a Program" if !(current < Program)
      current
    end

    def bind_manifest(cls, runtime)
      cls.instance_variable_set(:@app_info, runtime.manifest)
      cls.instance_variable_set(:@app_runtime, runtime)
      set_class_constant(cls, :Name, runtime.manifest.name)
      set_class_constant(cls, :Version, runtime.manifest.version)
      set_class_constant(cls, :BuildID, runtime.manifest.build_id)
      set_class_constant(cls, :EltenAPIVersion, runtime.manifest.elten_api_version)
      set_class_constant(cls, :Author, runtime.manifest.author)
      set_class_constant(cls, :MainMenuOption, runtime.manifest.menu_label)
      set_class_constant(cls, :NoMenuItem, runtime.manifest.hidden?)
      set_class_constant(cls, :UserMenuOptions, runtime.manifest.user_menu)
      app_id = runtime.manifest.raw["app_id"] || runtime.manifest.raw["appid"] || 0
      set_class_constant(cls, :AppID, app_id.to_i)
    end

    def set_class_constant(cls, name, value)
      cls.send(:remove_const, name) if cls.const_defined?(name, false)
      cls.const_set(name, value)
    end

    def list
      @@programs
    end

    def register_event_listener(event, cls, proc)
      listener = EventListener.new
      listener.event = event
      listener.cls = cls
      listener.proc = proc
      @@listeners.push(listener)
    end

    def emit_event(event)
      @@listeners.each { |listener| listener.call if listener.event == event }
    end

    def get_conf(path)
      entry = installed_entry(path)
      if entry == nil
        @@configs[path] = nil
        return nil, nil, nil, nil
      end
      @@configs[path] = {
        :id => nil,
        :name => entry.name,
        :author => entry.author,
        :version => entry.version,
        :build_id => entry.build_id,
        :file => nil
      }
      [entry.name, entry.author, entry.version, nil]
    end

    def configs
      @@configs.dup
    end

    def language_locale_data(code)
      code = code.to_s[0, 2].to_s.downcase
      data = []
      @@runtimes.each_value do |runtime|
        locale = runtime.language_data(code)
        data << locale if locale != nil
      end
      data
    end

    def load_runtime_locale(runtime)
      return if Configuration.language == nil
      data = runtime.language_data(Configuration.language)
      loadmo(data, false) if data != nil && respond_to?(:loadmo, true)
    rescue Exception => e
      Log.warning("Cannot load program locale #{runtime.entry_id}: #{e.class}: #{e.message}")
    end
  end
end

module Kernel
  unless method_defined?(:__elten_program_original_require)
    alias __elten_program_original_require require
    alias __elten_program_original_require_relative require_relative

    def require(path)
      return true if Programs.require_in_current_program(path)
      __elten_program_original_require(path)
    end

    def require_relative(path)
      location = caller_locations(1, 1)[0]
      return true if Programs.require_relative_in_current_program(path, location && location.path)
      base = location && (location.absolute_path || location.path)
      return __elten_program_original_require_relative(path) if base == nil
      __elten_program_original_require(File.expand_path(path.to_s, File.dirname(base)))
    end
  end
end

class Program
  public
  Name = ""
  Version = "0.0"
  BuildID = nil
  EltenAPIVersion = Programs::ELTEN_API_VERSION
  Author = ""
  UserMenuOptions = {}
  MainMenuOption = nil
  AppID = 0
  NoMenuItem = false

  class << self
    attr_reader :app_info, :app_runtime

    def init
    end

    def get_configuration
      nil
    end

    def set_configuration(_configuration)
      nil
    end

    def name
      @app_info == nil ? const_get(:Name) : @app_info.name
    end

    def version
      @app_info == nil ? const_get(:Version) : @app_info.version
    end

    def build_id
      @app_info == nil ? const_get(:BuildID) : @app_info.build_id
    end

    def elten_api_version
      @app_info == nil ? const_get(:EltenAPIVersion) : @app_info.elten_api_version
    end

    def author
      @app_info == nil ? const_get(:Author) : @app_info.author
    end

    def menu_label
      @app_info == nil ? (const_get(:MainMenuOption) || name) : @app_info.menu_label
    end

    def hidden?
      @app_info == nil ? const_get(:NoMenuItem) == true : @app_info.hidden?
    end

    def user_menu_options
      @app_info == nil ? const_get(:UserMenuOptions) : @app_info.user_menu
    end

    def app_file(file = "")
      return file if @app_runtime == nil
      @app_runtime.physical_path(file) || file
    end

    alias appfile app_file

    def asset_path(path)
      @app_runtime == nil ? app_file(path) : @app_runtime.asset_path(path)
    end

    def data_path(path = "")
      @app_runtime == nil ? app_file(path) : @app_runtime.data_path(path)
    end

    def cache_path(path = "")
      @app_runtime == nil ? app_file(path) : @app_runtime.cache_path(path)
    end

    def read_json(path, default: nil)
      @app_runtime == nil ? default : @app_runtime.read_json(path, :default => default)
    end

    def write_json(path, data)
      @app_runtime != nil && @app_runtime.write_json(path, data)
    end

    def read_text(path, default: "")
      @app_runtime == nil ? default : @app_runtime.read_text(path, :default => default)
    end

    def write_text(path, text)
      @app_runtime != nil && @app_runtime.write_text(path, text)
    end

    def read_binary(path, default: "".b)
      @app_runtime == nil ? default : @app_runtime.read_binary(path, :default => default)
    end

    def write_binary(path, data)
      @app_runtime != nil && @app_runtime.write_binary(path, data)
    end

    def sound_asset(name)
      @app_runtime == nil ? nil : @app_runtime.sound_asset(name)
    end

    def sound_asset_path(name)
      @app_runtime == nil ? nil : @app_runtime.sound_asset_path(name)
    end

    def sound_asset_data(name)
      @app_runtime == nil ? nil : @app_runtime.sound_asset_data(name)
    end

    def create_sound_from_asset(name, sample: false, loop: false)
      @app_runtime == nil ? nil : @app_runtime.create_sound_from_asset(name, sample: sample, loop: loop)
    end

    def play_app_sound(name, volume: 100, pitch: 100, pan: 50, ignore_elten_volume: false)
      @app_runtime != nil && @app_runtime.play_app_sound(name, volume: volume, pitch: pitch, pan: pan, ignore_elten_volume: ignore_elten_volume)
    end

    def app_uuid
      @app_info == nil ? const_get(:AppID).to_s : @app_info.id.to_s
    end

    def register_server_app(name: nil, data: nil, tables: nil, tables_protected: false)
      EltenLink::Apps.register(EltenLink.client(self), :name => (name || self.name), :data => data, :tables => tables, :tables_protected => tables_protected)
    end

    def update_server_app(uuid = nil, name: nil, data: nil, tables: nil, tables_protected: nil)
      EltenLink::Apps.update(EltenLink.client(self), uuid || app_uuid, :name => (name || self.name), :data => data, :tables => tables, :tables_protected => tables_protected)
    end

    def server_table(name, uuid = nil)
      EltenLink::Apps.table(EltenLink.client(self), uuid || app_uuid, name)
    end

    def on(event, &proc)
      Programs.register_event_listener(event, self, proc)
    end

    def register_quickaction(ident, label, &proc)
      QuickActions.register_proc(self, ident, label, proc)
    end

    def inherited(cls)
      Programs.discover(cls)
    end
  end

  def app
    self.class.app_runtime
  end

  def server_table(name, uuid = nil)
    self.class.server_table(name, uuid)
  end

  def sound_asset(name)
    self.class.sound_asset(name)
  end

  def sound_asset_path(name)
    self.class.sound_asset_path(name)
  end

  def sound_asset_data(name)
    self.class.sound_asset_data(name)
  end

  def create_sound_from_asset(name, sample: false, loop: false)
    self.class.create_sound_from_asset(name, sample: sample, loop: loop)
  end

  def play_app_sound(name, volume: 100, pitch: 100, pan: 50, ignore_elten_volume: false)
    self.class.play_app_sound(name, volume: volume, pitch: pitch, pan: pan, ignore_elten_volume: ignore_elten_volume)
  end

  def finish(v = nil)
    close
    Log.info("Program exited #{self.class}")
    alert(p_("Program", "The program has been closed."))
    $scene = Scene_Main.new
    v
  end

  def close
  end

  def on(event, &proc)
    self.class.on(event, &proc)
  end

  def register_quickaction(ident, label, &proc)
    self.class.register_quickaction(ident, label, &proc)
  end

  def exit(v = 0)
    finish(v)
  end

  protected

  def appsignature
    [self.class.name, self.class.version, self.class.author].join("\r\n")
  end

  def app_file(file = "")
    self.class.app_file(file)
  end

  alias appfile app_file

  def app_cache
    self.class.app_cache
  end

  def self.app_cache
    @appcache = FileCache.new(cache_path("cache.dat")) if @appcache == nil
    @appcache
  end

  def signaled(_user, _packet)
  end

  def signal(user, packet)
    fail(ArgumentError, "Not JSON-convertable value") if !packet.is_a?(String) && !packet.is_a?(Array) && !packet.is_a?(Hash) && packet != nil && packet != false && packet != true && !packet.is_a?(Integer)
    fail(ArgumentError, "user must be a string") if !user.is_a?(String)
    appid = self.class.app_uuid
    fail(RuntimeError, "AppID not set") if appid.to_s.empty? || appid.to_s == "0"
    EltenLink::Apps.signal(EltenLink.client(self), :appid => appid, :user => user, :packet => packet)
  end
end

class EltenApp
  attr_reader :file

  def initialize(file)
    @file = file
    @package = Programs::EltenAppPackage.new(file)
  end

  def manifest
    @package.manifest.raw
  end

  def name
    @package.manifest.name
  end

  def version
    @package.manifest.version
  end

  def build_id
    @package.manifest.build_id
  end

  def author
    @package.manifest.author
  end
end
