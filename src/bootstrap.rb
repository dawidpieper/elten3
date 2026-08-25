# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require "base64"
require "etc"
require "fileutils"
require "json"
require "json/ext"
require "net/http"
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

  def extname(path)
    value = normalize(path)
    extension = File.extname(value)
    return extension unless extension.empty?

    name = File.basename(value)
    name.match?(/\A\.[^.]+\z/) ? name : ""
  end

  def relative_from(path, root)
    value = normalize(path)
    prefix = with_separator(root)
    value.start_with?(prefix) ? value[prefix.length..-1].to_s : value
  end
end
