require "base64"
require "etc"
require "fileutils"
require "json"
require "json/ext"
require "openssl"
require "ostruct"
require "rbconfig"
require "socket"
require "strscan"
require "stringio"
require "tmpdir"
require "zlib"
require "zstd-ruby"

module EltenPath
  module_function

  def normalize(path)
    path.to_s.tr("\\", "/")
  end

  def join(*parts)
    parts = parts.flatten.compact.map { |part| normalize(part) }.reject { |part| part == "" }
    return "" if parts.empty?
    first = parts.shift
    rest = parts.map { |part| part.sub(/\A[\/]+/, "") }
    File.join(first, *rest)
  end

  def with_separator(path)
    value = normalize(path)
    return value if value == "" || value.end_with?("/")
    value + "/"
  end

  def basename(path)
    File.basename(normalize(path))
  end

  def dirname(path)
    File.dirname(normalize(path))
  end

  def relative_from(path, root)
    value = normalize(path)
    prefix = with_separator(root)
    value.start_with?(prefix) ? value[prefix.length..-1].to_s : value
  end
end
