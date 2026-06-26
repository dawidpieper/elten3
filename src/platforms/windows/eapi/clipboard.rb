# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "fiddle"

class ClipboardError < StandardError; end

class Clipboard
  TEXT = 1
  OEMTEXT = 7
  UNICODETEXT = 13
  HDROP = 15

  GMEM_MOVEABLE = 0x0002
  GMEM_ZEROINIT = 0x0040
  GHND = GMEM_MOVEABLE | GMEM_ZEROINIT

  class << self
    def open
      raise ClipboardError, "OpenClipboard() failed" if native.open_clipboard.call(0).to_i == 0
      self
    end

    def close
      native.close_clipboard.call
      self
    end

    def set_data(clip_data, format = TEXT)
      data = normalize_clip_data(clip_data, format)
      hmem = 0
      transferred = false
      open
      begin
        native.empty_clipboard.call
        hmem = native.global_alloc.call(GHND, [data.bytesize, 1].max)
        raise ClipboardError, "GlobalAlloc() failed" if hmem == nil || hmem.to_i == 0

        mem = native.global_lock.call(hmem)
        raise ClipboardError, "GlobalLock() failed" if mem == nil || mem.to_i == 0
        begin
          Fiddle::Pointer.new(mem.to_i)[0, data.bytesize] = data if data.bytesize > 0
        ensure
          native.global_unlock.call(hmem)
        end

        if native.set_clipboard_data.call(format.to_i, hmem).to_i == 0
          raise ClipboardError, "SetClipboardData() failed"
        end
        transferred = true
        self
      ensure
        native.global_free.call(hmem) if hmem != nil && hmem.to_i != 0 && transferred == false
        close rescue nil
      end
    end

    def data(format = TEXT)
      with_open { native.get_clipboard_data.call(format.to_i) }
    rescue ClipboardError
      ""
    end
    alias get_data data

    def empty
      with_open { native.empty_clipboard.call }
      self
    end

    def text
      with_open do
        handle = native.get_clipboard_data.call(UNICODETEXT)
        return "" if handle == nil || handle.to_i == 0
        read_utf16_handle(handle)
      end
    rescue ClipboardError
      ""
    end

    def text=(value)
      set_data(utf16le_z(value), UNICODETEXT)
    end

    def files
      with_open do
        handle = native.get_clipboard_data.call(HDROP)
        return [] if handle == nil || handle.to_i == 0
        count = native.drag_query_file.call(handle, -1, nil, 0).to_i
        files = []
        (0...count).each do |index|
          length = native.drag_query_file.call(handle, index, nil, 0).to_i
          next if length <= 0
          buffer = "\0" * ((length + 1) * 2)
          native.drag_query_file.call(handle, index, buffer, length + 1)
          files.push(utf16le_to_utf8(buffer))
        end
        files
      end
    rescue ClipboardError
      []
    end

    def files=(paths)
      return if !paths.is_a?(Array)
      header = [20, 0, 0, 0, 1].pack("LllLL")
      payload = paths.map { |path| utf16le_z(path) }.join.b + "\0\0".b
      set_data(header.b + payload, HDROP)
    end

    private

    def with_open
      open
      begin
        yield
      ensure
        close rescue nil
      end
    end

    def normalize_clip_data(data, format)
      bytes = data.to_s.b
      case format
      when UNICODETEXT
        bytes.end_with?("\0\0".b) ? bytes : bytes + "\0\0".b
      when TEXT, OEMTEXT
        bytes.end_with?("\0".b) ? bytes : bytes + "\0".b
      else
        bytes
      end
    end

    def read_utf16_handle(handle)
      mem = native.global_lock.call(handle)
      return "" if mem == nil || mem.to_i == 0
      begin
        size = native.global_size.call(handle).to_i
        return "" if size <= 0
        utf16le_to_utf8(Fiddle::Pointer.new(mem.to_i)[0, size])
      ensure
        native.global_unlock.call(handle)
      end
    end

    def utf16le_z(text)
      text.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace).b + "\0\0".b
    end

    def utf16le_to_utf8(bytes)
      data = bytes.to_s.b
      cutoff = nil
      index = 0
      while index + 1 < data.bytesize
        if data.getbyte(index) == 0 && data.getbyte(index + 1) == 0
          cutoff = index
          break
        end
        index += 2
      end
      data = data.byteslice(0, cutoff) if cutoff != nil
      data.to_s.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    end

    def native
      @native ||= Native.new
    end
  end

  class Native
    ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
    INT = Fiddle::TYPE_INT
    PTR = Fiddle::TYPE_VOIDP
    SIZE_T = EltenWin32::POINTER_SIZE == 8 && defined?(Fiddle::TYPE_LONG_LONG) ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_LONG

    attr_reader :open_clipboard, :close_clipboard, :get_clipboard_data, :set_clipboard_data,
      :empty_clipboard, :global_alloc, :global_lock, :global_unlock, :global_free,
      :global_size, :drag_query_file

    def initialize
      user32 = Fiddle.dlopen("user32.dll")
      kernel32 = Fiddle.dlopen("kernel32.dll")
      shell32 = Fiddle.dlopen("shell32.dll")

      @open_clipboard = bind(user32, "OpenClipboard", [PTR], INT)
      @close_clipboard = bind(user32, "CloseClipboard", [], INT)
      @get_clipboard_data = bind(user32, "GetClipboardData", [INT], PTR)
      @set_clipboard_data = bind(user32, "SetClipboardData", [INT, PTR], PTR)
      @empty_clipboard = bind(user32, "EmptyClipboard", [], INT)

      @global_alloc = bind(kernel32, "GlobalAlloc", [INT, SIZE_T], PTR)
      @global_lock = bind(kernel32, "GlobalLock", [PTR], PTR)
      @global_unlock = bind(kernel32, "GlobalUnlock", [PTR], INT)
      @global_free = bind(kernel32, "GlobalFree", [PTR], PTR)
      @global_size = bind(kernel32, "GlobalSize", [PTR], SIZE_T)

      @drag_query_file = bind(shell32, "DragQueryFileW", [PTR, INT, PTR, INT], INT)
    end

    private

    def bind(library, name, args, ret)
      Fiddle::Function.new(library[name], args, ret, ABI)
    end
  end
end
