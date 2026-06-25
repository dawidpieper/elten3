#!/usr/bin/env ruby
# Builds an Elten setup package. The package is ZIP-compatible, but uses
# the .eltsetup extension and carries an Elten-specific __manifest.json.

require "fileutils"
require "json"
require "optparse"
require "rbconfig"
require "rubygems"
require "zlib"
require "zstd-ruby"
require_relative "../src/EAPI/ProgramSigning"

SETUP_TYPE = "application"
CODE_MAGIC = "Elten3AppPackage".b
PROJECT_ROOT = File.expand_path("..", __dir__)
SOUND_EXTENSIONS = %w[.ogg .opus .wav .wave .mp3 .flac .aac .m4a .wma .spx .webm].freeze
LANGUAGE_EXTENSIONS = %w[.mo].freeze
NATIVE_EXTENSIONS = %w[.so .bundle .dll .dylib .manifest].freeze
RUNTIME_ROOTS = {
  "windows-x64" => ENV["ELTEN_RUNTIME_ROOT_WINDOWS_X64"] || File.join(PROJECT_ROOT, "build", "launcher-windows-x64", "ruby", "windows-x64"),
  "windows-x86" => ENV["ELTEN_RUNTIME_ROOT_WINDOWS_X86"] || File.join(PROJECT_ROOT, "build", "launcher-windows-x86", "ruby", "windows-x86"),
  "windows-arm64" => ENV["ELTEN_RUNTIME_ROOT_WINDOWS_ARM64"] || File.join(PROJECT_ROOT, "build", "launcher-windows-arm64", "ruby", "windows-arm64"),
  "osx-arm64" => ENV["ELTEN_RUNTIME_ROOT_OSX_ARM64"] || File.join(PROJECT_ROOT, "build", "launcher-osx-arm64", "ruby", "osx-arm64")
}.freeze
MANIFEST_BEGIN = /^\=begin[ \t]+Elten3AppInfo[ \t]*\r?\n/.freeze
MANIFEST_END = /^\=end[ \t]+Elten3AppInfo[ \t]*$/m.freeze

def usage
  warn "Usage: ruby tools/build-eltsetup.rb [--unsigned] [--cert CERT.pem --key KEY.pem] SOURCE_DIR OUTPUT.eltsetup"
  exit 1
end

def normalize(path)
  path.to_s.tr("\\", "/").sub(/\A\.\//, "")
end

def extract_manifest(code, source)
  start_match = MANIFEST_BEGIN.match(code)
  raise "Missing Elten3AppInfo in #{source}" if start_match == nil
  rest = code[start_match.end(0)..-1].to_s
  end_match = MANIFEST_END.match(rest)
  raise "Unclosed Elten3AppInfo in #{source}" if end_match == nil
  JSON.parse(rest[0...end_match.begin(0)].to_s)
end

def manifest_file(source_dir)
  default = File.join(source_dir, "__app.rb")
  return default if File.file?(default)

  matches = Dir.glob(File.join(source_dir, "**", "*.rb")).select do |file|
    File.binread(file).match?(MANIFEST_BEGIN)
  end
  raise "More than one Elten3AppInfo block found" if matches.size > 1
  raise "No Elten3AppInfo block found" if matches.empty?
  matches[0]
end

def write_u8(io, value)
  write_bytes(io, [value.to_i].pack("C"))
end

def write_u16(io, value)
  write_bytes(io, [value.to_i].pack("S<"))
end

def write_u32(io, value)
  write_bytes(io, [value.to_i].pack("L<"))
end

def write_bytes(io, data)
  io.respond_to?(:write) ? io.write(data) : io << data
end

def language_code(relative)
  return nil if !relative.start_with?("locale/")
  return nil if !LANGUAGE_EXTENSIONS.include?(File.extname(relative).downcase)
  code = File.basename(relative, File.extname(relative))[0, 2].to_s
  return nil if code !~ /\A[a-zA-Z]{2}\z/
  code.upcase
end

def gem_declarations(metadata)
  Array(metadata["gems"]).map do |entry|
    if entry.is_a?(Hash)
      name = entry["name"].to_s
      requirement = entry["requirement"] || entry["version"] || ">= 0"
    else
      name = entry.to_s
      requirement = ">= 0"
    end
    [name, requirement.to_s]
  end.reject { |name, _requirement| name == "" }
end

def host_gems
  @host_gems ||= begin
    gemfile = File.join(PROJECT_ROOT, "Gemfile")
    names = {}
    if File.file?(gemfile)
      File.readlines(gemfile, encoding: "UTF-8").each do |line|
        line = line.sub(/#.*/, "")
        match = line.match(/^\s*gem\s+["']([^"']+)["']/)
        names[match[1].downcase] = true if match != nil
      end
    end
    names
  end
end

def host_gem?(name)
  host_gems.key?(name.to_s.downcase)
end

def find_installed_spec(name, requirement)
  dependency = Gem::Dependency.new(name, requirement)
  spec = dependency.matching_specs.sort_by(&:version).last
  raise "Gem #{name} (#{requirement}) is not installed. Install it in the Ruby used for building and rerun." if spec == nil
  spec
end

def collect_gem_specs(metadata)
  queue = gem_declarations(metadata).reject { |name, _requirement| host_gem?(name) }.map { |name, requirement| find_installed_spec(name, requirement) }
  specs = []
  seen = {}
  until queue.empty?
    spec = queue.shift
    next if seen[spec.full_name]
    seen[spec.full_name] = true
    specs << spec
    spec.runtime_dependencies.each do |dependency|
      next if host_gem?(dependency.name)
      dep_spec = dependency.matching_specs.sort_by(&:version).last
      raise "Missing dependency #{dependency.name} (#{dependency.requirement}) for gem #{spec.full_name}" if dep_spec == nil
      queue << dep_spec
    end
  end
  specs
end

def gem_code_entries(specs)
  entries = []
  specs.each do |spec|
    spec.require_paths.each do |require_path|
      root = File.join(spec.full_gem_path, require_path)
      next if !File.directory?(root)
      Dir.glob(File.join(root, "**", "*.rb")).sort.each do |file|
        relative = normalize(file.delete_prefix(spec.full_gem_path + File::SEPARATOR))
        entries << ["gems/#{spec.full_name}/#{relative}", File.binread(file).b]
      end
    end
  end
  entries
end

def native_file?(file)
  return false if normalize(file).split("/").any? { |part| part.end_with?(".dSYM") }
  NATIVE_EXTENSIONS.include?(File.extname(file).downcase)
end

def builder_platform
  os = RUBY_PLATFORM =~ /darwin/i ? "osx" : "windows"
  cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
  arch = cpu =~ /arm|aarch64/ ? "arm64" : (cpu =~ /64/ ? "x64" : "x86")
  "#{os}-#{arch}"
end

def runtime_gem_dirs(root, spec)
  dirs = Dir.glob(File.join(root, "lib", "ruby", "gems", "*", "gems", spec.full_name))
  dirs = Dir.glob(File.join(root, "lib", "ruby", "gems", "*", "gems", "#{spec.name}-*")) if dirs.empty?
  dirs.select { |dir| File.directory?(dir) }
end

def runtime_extension_dirs(root, spec)
  dirs = Dir.glob(File.join(root, "lib", "ruby", "gems", "*", "extensions", "**", spec.full_name))
  dirs += Dir.glob(File.join(root, "lib", "ruby", "gems", "*", "extensions", "**", "#{spec.name}-*")) if dirs.empty?
  dirs.select { |dir| File.directory?(dir) }
end

def gem_native_entries(specs)
  entries = []
  current_platform = builder_platform
  specs.each do |spec|
    Dir.glob(File.join(spec.full_gem_path, "**", "*")).sort.each do |file|
      next if !File.file?(file) || !native_file?(file)
      relative = normalize(file.delete_prefix(spec.full_gem_path + File::SEPARATOR))
      entries << ["#{current_platform}/gems/#{File.basename(spec.full_gem_path)}/#{relative}", File.binread(file).b]
    end
    if spec.extension_dir != nil && File.directory?(spec.extension_dir)
      Dir.glob(File.join(spec.extension_dir, "**", "*")).sort.each do |file|
        next if !File.file?(file) || !native_file?(file)
        relative = normalize(file.delete_prefix(spec.extension_dir + File::SEPARATOR))
        entries << ["#{current_platform}/gems/#{spec.full_name}/extensions/#{relative}", File.binread(file).b]
      end
    end
  end
  RUNTIME_ROOTS.each do |platform, root|
    next if !File.directory?(root)
    specs.each do |spec|
      runtime_gem_dirs(root, spec).each do |gem_dir|
        Dir.glob(File.join(gem_dir, "**", "*")).sort.each do |file|
          next if !File.file?(file) || !native_file?(file)
          relative = normalize(file.delete_prefix(gem_dir + File::SEPARATOR))
          entries << ["#{platform}/gems/#{File.basename(gem_dir)}/#{relative}", File.binread(file).b]
        end
      end
      runtime_extension_dirs(root, spec).each do |extension_dir|
        Dir.glob(File.join(extension_dir, "**", "*")).sort.each do |file|
          next if !File.file?(file) || !native_file?(file)
          relative = normalize(file.delete_prefix(extension_dir + File::SEPARATOR))
          entries << ["#{platform}/gems/#{File.basename(extension_dir)}/extensions/#{relative}", File.binread(file).b]
        end
      end
    end
  end
  entries.uniq { |name, _data| name }
end

def write_named_record(buffer, type, name, content)
  write_u8(buffer, type)
  name_bytes = name.encode("UTF-8")
  raise "File name too long: #{name}" if name_bytes.bytesize > 0xffff
  write_u16(buffer, name_bytes.bytesize)
  buffer << name_bytes
  write_u32(buffer, content.bytesize)
  buffer << content
end

def build_code_container(source_dir, metadata, signing_options)
  buffer = +"".b
  buffer << CODE_MAGIC
  compressed_metadata = Zstd.compress(JSON.generate(metadata).b, level: 19)
  buffer << [compressed_metadata.bytesize].pack("L<")
  buffer << compressed_metadata

  gem_specs = collect_gem_specs(metadata)
  puts "Bundling gems: #{gem_specs.map(&:full_name).join(", ")}" if !gem_specs.empty?

  Dir.glob(File.join(source_dir, "**", "*")).sort.each do |file|
    next if !File.file?(file)
    relative = normalize(file.delete_prefix(source_dir + File::SEPARATOR))
    ext = File.extname(relative).downcase
    if ext == ".rb"
      content = Zstd.compress(File.binread(file).b, level: 19)
      type = 1
    elsif relative.start_with?("Audio/") && SOUND_EXTENSIONS.include?(ext)
      content = File.binread(file).b
      type = 2
    elsif (code = language_code(relative)) != nil
      content = Zstd.compress(File.binread(file).b, level: 19)
      type = 3
    else
      next
    end
    write_u8(buffer, type)
    if type == 3
      buffer << code.encode("ASCII")
      write_u32(buffer, content.bytesize)
      buffer << content
    else
      name_bytes = relative.encode("UTF-8")
      raise "File name too long: #{relative}" if name_bytes.bytesize > 0xffff
      write_u16(buffer, name_bytes.bytesize)
      buffer << name_bytes
      write_u32(buffer, content.bytesize)
      buffer << content
    end
  end

  gem_code_entries(gem_specs).each do |relative, data|
    content = Zstd.compress(data, level: 19)
    write_named_record(buffer, 1, relative, content)
  end

  gem_native_entries(gem_specs).each do |relative, data|
    write_named_record(buffer, 4, relative, data)
  end

  signing_options[:sign] ? Programs::ProgramSigning.sign_code_file(
    buffer,
    :certificate_path => signing_options[:certificate],
    :private_key_path => signing_options[:private_key]
  ) : buffer
end

class EltsetupZipWriter
  Entry = Struct.new(:name, :crc, :compressed_size, :uncompressed_size, :method, :offset, :dos_time, :dos_date, keyword_init: true)

  def initialize(file)
    @io = File.open(file, "wb")
    @entries = []
  end

  def add(name, data, mtime = Time.now)
    name = normalize(name)
    data = data.to_s.b
    compressed = deflate(data)
    method = 8
    if compressed.bytesize >= data.bytesize
      compressed = data
      method = 0
    end
    dos_time, dos_date = dos_datetime(mtime)
    entry = Entry.new(
      name: name,
      crc: Zlib.crc32(data),
      compressed_size: compressed.bytesize,
      uncompressed_size: data.bytesize,
      method: method,
      offset: @io.pos,
      dos_time: dos_time,
      dos_date: dos_date
    )
    name_bytes = name.encode("UTF-8")
    @io.write([0x04034b50, 20, 0x0800, method, dos_time, dos_date, entry.crc, entry.compressed_size, entry.uncompressed_size, name_bytes.bytesize, 0].pack("L<S<S<S<S<S<L<L<L<S<S<"))
    @io.write(name_bytes)
    @io.write(compressed)
    @entries << entry
  end

  def close
    central_offset = @io.pos
    @entries.each { |entry| write_central_entry(entry) }
    central_size = @io.pos - central_offset
    @io.write([0x06054b50, 0, 0, @entries.size, @entries.size, central_size, central_offset, 0].pack("L<S<S<S<S<L<L<S<"))
    @io.close
  end

  private

  def deflate(data)
    z = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
    z.deflate(data, Zlib::FINISH)
  ensure
    z.close if z != nil
  end

  def dos_datetime(time)
    year = [[time.year, 1980].max, 2107].min
    dos_time = (time.hour << 11) | (time.min << 5) | (time.sec / 2)
    dos_date = ((year - 1980) << 9) | (time.month << 5) | time.day
    [dos_time, dos_date]
  end

  def write_central_entry(entry)
    name_bytes = entry.name.encode("UTF-8")
    @io.write([
      0x02014b50, 20, 20, 0x0800, entry.method, entry.dos_time, entry.dos_date,
      entry.crc, entry.compressed_size, entry.uncompressed_size, name_bytes.bytesize,
      0, 0, 0, 0, 0, entry.offset
    ].pack("L<S<S<S<S<S<S<L<L<L<S<S<S<S<S<L<L<"))
    @io.write(name_bytes)
  end
end

signing_options = {
  :sign => true,
  :certificate => Programs::ProgramSigning.default_certificate_path,
  :private_key => Programs::ProgramSigning.default_private_key_path
}
OptionParser.new do |opts|
  opts.on("--unsigned") { signing_options[:sign] = false }
  opts.on("--cert PATH") { |path| signing_options[:certificate] = path }
  opts.on("--key PATH") { |path| signing_options[:private_key] = path }
end.parse!(ARGV)

source_dir, output = ARGV
usage if source_dir.to_s == "" || output.to_s == ""
source_dir = File.expand_path(source_dir)
output = File.expand_path(output)
raise "SOURCE_DIR is not a directory: #{source_dir}" if !File.directory?(source_dir)
if signing_options[:sign] && !Programs::ProgramSigning.signing_available?(signing_options[:certificate], signing_options[:private_key])
  raise "Program signing certificate or key is missing. Use --cert/--key or --unsigned."
end

main_file = manifest_file(source_dir)
metadata = extract_manifest(File.binread(main_file), main_file)
metadata["main"] = normalize(main_file.delete_prefix(source_dir + File::SEPARATOR)) if metadata["main"].to_s == ""

code_name = "#{File.basename(output, ".eltsetup")}.eltenapp"
setup_manifest = {
  "type" => SETUP_TYPE,
  "payload" => metadata.merge("entry" => code_name)
}

FileUtils.mkdir_p(File.dirname(output))
writer = EltsetupZipWriter.new(output)
writer.add("__manifest.json", JSON.pretty_generate(setup_manifest) + "\n")
writer.add(code_name, build_code_container(source_dir, metadata, signing_options))

Dir.glob(File.join(source_dir, "**", "*")).sort.each do |file|
  next if !File.file?(file)
  relative = normalize(file.delete_prefix(source_dir + File::SEPARATOR))
  ext = File.extname(relative).downcase
  next if ext == ".rb" || ext == ".eltenapp"
  next if relative == "__manifest.json"
  next if relative.start_with?("Audio/") && SOUND_EXTENSIONS.include?(ext)
  next if relative.start_with?("locale/")
  writer.add(relative, File.binread(file).b, File.mtime(file))
end
writer.close

puts "Built #{output}"
