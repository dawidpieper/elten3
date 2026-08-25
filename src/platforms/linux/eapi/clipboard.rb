# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper, Arkadiusz Koziol
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class ClipboardError < StandardError; end unless defined?(ClipboardError)

class Clipboard
  TEXT = 1 unless const_defined?(:TEXT)
  OEMTEXT = 7 unless const_defined?(:OEMTEXT)
  UNICODETEXT = 13 unless const_defined?(:UNICODETEXT)
  HDROP = 15 unless const_defined?(:HDROP)

  class << self
    def available?
      SDL2.available?
    rescue Exception
      false
    end

    def open
      self
    end

    def close
      self
    end

    def set_data(clip_data, _format = TEXT)
      self.text = clip_data.to_s
    end

    def data(_format = TEXT)
      text
    end
    alias get_data data

    def empty
      self.text = ""
      self
    end

    def text
      return "" unless available?
      pointer = SDL2::SDL_GetClipboardText.call
      return "" if pointer.to_i == 0
      begin
        normalize_text(SDL2.read_cstring(pointer))
      ensure
        SDL2::SDL_free.call(pointer) if pointer.to_i != 0
      end
    rescue Exception
      ""
    end

    def text=(value)
      return value unless available?
      SDL2::SDL_SetClipboardText.call(SDL2.cstring(value))
      value
    rescue Exception
      value
    end

    def files
      []
    end

    def files=(_paths)
      nil
    end

    private

    def normalize_text(value)
      str = value.to_s
      return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?
      str = str.dup
      str.force_encoding(Encoding::UTF_8) if str.encoding == Encoding::ASCII_8BIT
      str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    rescue Encoding::CompatibilityError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      value.to_s.b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
  end
end
