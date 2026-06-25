# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class ClipboardError < StandardError; end unless defined?(ClipboardError)

class Clipboard
  TEXT = 1 unless const_defined?(:TEXT)
  OEMTEXT = 7 unless const_defined?(:OEMTEXT)
  UNICODETEXT = 13 unless const_defined?(:UNICODETEXT)
  HDROP = 15 unless const_defined?(:HDROP)
  NS_UTF8_STRING_ENCODING = 4 unless const_defined?(:NS_UTF8_STRING_ENCODING)
  PASTEBOARD_TEXT_TYPES = ["public.utf8-plain-text", "NSStringPboardType"].freeze unless const_defined?(:PASTEBOARD_TEXT_TYPES)

  class << self
    def available?
      initialize_native
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
      clear_pasteboard
      self
    end

    def text
      return "" unless available?
      with_autorelease_pool do
        pasteboard = general_pasteboard
        PASTEBOARD_TEXT_TYPES.each do |type|
          value = @msg_id_id.call(pasteboard, sel("stringForType:"), ns_string(type))
          return objc_string(value) if value.to_i != 0
        end
        ""
      end
    rescue Exception
      ""
    end

    def text=(value)
      return value unless available?
      with_autorelease_pool do
        pasteboard = general_pasteboard
        @msg_integer.call(pasteboard, sel("clearContents"))
        string = ns_string(value)
        PASTEBOARD_TEXT_TYPES.each do |type|
          @msg_bool_id_id.call(pasteboard, sel("setString:forType:"), string, ns_string(type))
        end
      end
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

    def initialize_native
      return @native_available if defined?(@native_available)
      @native_available = false
      unless defined?(Fiddle)
        verbose = $VERBOSE
        $VERBOSE = nil
        begin
          require "fiddle"
        ensure
          $VERBOSE = verbose
        end
      end
      Fiddle.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation")
      Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
      objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      id = Fiddle::TYPE_VOIDP
      sel_type = Fiddle::TYPE_VOIDP
      bool = Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR
      native_integer = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_LONG
      native_unsigned = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_ULONG_LONG : Fiddle::TYPE_ULONG
      @objc_get_class = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], id)
      @sel_register_name = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], sel_type)
      msg = objc["objc_msgSend"]
      @msg_id = Fiddle::Function.new(msg, [id, sel_type], id)
      @msg_id_id = Fiddle::Function.new(msg, [id, sel_type, id], id)
      @msg_bool_id_id = Fiddle::Function.new(msg, [id, sel_type, id, id], bool)
      @msg_void = Fiddle::Function.new(msg, [id, sel_type], Fiddle::TYPE_VOID)
      @msg_integer = Fiddle::Function.new(msg, [id, sel_type], native_integer)
      @msg_id_bytes = Fiddle::Function.new(msg, [id, sel_type, Fiddle::TYPE_VOIDP, native_unsigned, native_unsigned], id)
      @msg_ulong_ulong = Fiddle::Function.new(msg, [id, sel_type, native_unsigned], native_unsigned)
      @native_available = cls("NSPasteboard").to_i != 0 && cls("NSString").to_i != 0
    rescue Exception
      @native_available = false
    end

    def general_pasteboard
      @msg_id.call(cls("NSPasteboard"), sel("generalPasteboard"))
    end

    def with_autorelease_pool
      pool = @msg_id.call(cls("NSAutoreleasePool"), sel("new"))
      yield
    ensure
      @msg_void.call(pool, sel("drain")) if pool.to_i != 0
    end

    def clear_pasteboard
      return false unless available?
      with_autorelease_pool do
        @msg_integer.call(general_pasteboard, sel("clearContents"))
      end
      true
    rescue Exception
      false
    end

    def normalize_text(value)
      str = value.to_s
      return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?
      str = str.dup
      str.force_encoding(Encoding::UTF_8) if str.encoding == Encoding::ASCII_8BIT
      str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    rescue Encoding::CompatibilityError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      value.to_s.b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end

    def utf8_bytes(value)
      normalize_text(value).encode(Encoding::UTF_8, invalid: :replace, undef: :replace).b
    end

    def ns_string(value)
      bytes = utf8_bytes(value)
      @msg_id_bytes.call(cls("NSString"), sel("stringWithBytes:length:encoding:"), bytes, bytes.bytesize, NS_UTF8_STRING_ENCODING)
    end

    def objc_string(object)
      return "" if object.to_i == 0
      pointer = @msg_id.call(object, sel("UTF8String"))
      return "" if pointer.to_i == 0
      length = @msg_ulong_ulong.call(object, sel("lengthOfBytesUsingEncoding:"), NS_UTF8_STRING_ENCODING).to_i
      bytes = length > 0 ? Fiddle::Pointer.new(pointer)[0, length] : ""
      normalize_text(bytes)
    end

    def cls(name)
      @classes ||= {}
      @classes[name] ||= @objc_get_class.call(name.to_s.b + "\0".b)
    end

    def sel(name)
      @selectors ||= {}
      @selectors[name] ||= @sel_register_name.call(name.to_s.b + "\0".b)
    end
  end
end
