#!/usr/bin/env ruby
# Builds an Elten 3 program package from a source directory.

require "json"
require "fileutils"
require "optparse"
require "zstd-ruby"
require_relative "../src/EAPI/ProgramSigning"

MAGIC = "Elten3AppPackage".b
SOUND_EXTENSIONS = %w[.ogg .opus .wav .wave .mp3 .flac .aac .m4a .wma .spx .webm].freeze
LANGUAGE_EXTENSIONS = %w[.mo].freeze
MANIFEST_BEGIN = /^\=begin[ \t]+Elten3AppInfo[ \t]*\r?\n/.freeze
MANIFEST_END = /^\=end[ \t]+Elten3AppInfo[ \t]*$/m.freeze

def usage
  warn "Usage: ruby tools/build-eltenapp.rb [--unsigned] [--cert CERT.pem --key KEY.pem] SOURCE_DIR OUTPUT.eltenapp"
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

def write_bytes(io, data)
  io.respond_to?(:write) ? io.write(data) : io << data
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

def write_named_record(io, type, name, content)
  write_u8(io, type)
  name_bytes = name.encode("UTF-8")
  raise "File name too long: #{name}" if name_bytes.bytesize > 0xffff
  write_u16(io, name_bytes.bytesize)
  write_bytes(io, name_bytes)
  write_u32(io, content.bytesize)
  write_bytes(io, content)
end

def language_code(relative)
  return nil if !relative.start_with?("locale/")
  return nil if !LANGUAGE_EXTENSIONS.include?(File.extname(relative).downcase)
  code = File.basename(relative, File.extname(relative))[0, 2].to_s
  return nil if code !~ /\A[a-zA-Z]{2}\z/
  code.upcase
end

options = {
  :sign => true,
  :certificate => Programs::ProgramSigning.default_certificate_path,
  :private_key => Programs::ProgramSigning.default_private_key_path
}
OptionParser.new do |opts|
  opts.on("--unsigned") { options[:sign] = false }
  opts.on("--cert PATH") { |path| options[:certificate] = path }
  opts.on("--key PATH") { |path| options[:private_key] = path }
end.parse!(ARGV)

source_dir, output = ARGV
usage if source_dir.to_s == "" || output.to_s == ""
source_dir = File.expand_path(source_dir)
output = File.expand_path(output)
raise "SOURCE_DIR is not a directory: #{source_dir}" if !File.directory?(source_dir)
if options[:sign] && !Programs::ProgramSigning.signing_available?(options[:certificate], options[:private_key])
  raise "Program signing certificate or key is missing. Use --cert/--key or --unsigned."
end

main_file = manifest_file(source_dir)
metadata = extract_manifest(File.binread(main_file), main_file)
metadata["main"] = normalize(main_file.delete_prefix(source_dir + File::SEPARATOR)) if metadata["main"].to_s == ""

files = []
Dir.glob(File.join(source_dir, "**", "*")).sort.each do |file|
  next if !File.file?(file)
  relative = normalize(file.delete_prefix(source_dir + File::SEPARATOR))
  ext = File.extname(relative).downcase
  if ext == ".rb"
    content = Zstd.compress(File.binread(file).b, level: 19)
    files << [1, relative, content]
  elsif relative.start_with?("Audio/") && SOUND_EXTENSIONS.include?(ext)
    content = File.binread(file).b
    files << [2, relative, content]
  elsif (code = language_code(relative)) != nil
    content = Zstd.compress(File.binread(file).b, level: 19)
    files << [3, code, content]
  end
end

FileUtils.mkdir_p(File.dirname(output))
code_file = +"".b
code_file << MAGIC
compressed_metadata = Zstd.compress(JSON.generate(metadata).b, level: 19)
write_u32(code_file, compressed_metadata.bytesize)
code_file << compressed_metadata
files.each do |type, name, content|
  if type == 3
    write_u8(code_file, type)
    code_file << name.encode("ASCII")
    write_u32(code_file, content.bytesize)
    code_file << content
  else
    write_named_record(code_file, type, name, content)
  end
end
data = if options[:sign]
         Programs::ProgramSigning.sign_code_file(
           code_file,
           :certificate_path => options[:certificate],
           :private_key_path => options[:private_key]
         )
       else
         code_file
       end
File.binwrite(output, data)

puts "Built #{output}"
