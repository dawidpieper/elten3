# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class SpellCheck
  class Result
    attr_accessor :index, :length
    attr_reader :suggestions

    def initialize
      @suggestions = []
    end
  end

  CLSCTX_INPROC_SERVER = 1
  COINIT_APARTMENTTHREADED = 2
  RPC_E_CHANGED_MODE = -2147417850
  S_OK = 0
  S_FALSE = 1
  CORRECTIVE_ACTION_GET_SUGGESTIONS = 1
  CORRECTIVE_ACTION_REPLACE = 2
  CORRECTIVE_ACTION_DELETE = 3
  MAX_ERRORS = 30
  COM_THREAD_KEY = :elten_spellcheck_native_com_initialized

  class << self
    def available?
      true
    end

    def languages
      factory = create_factory
      return [] if factory == 0
      enum = 0
      begin
        pp = pointer_buffer
        hr = com_call(factory, 3, [factory, pp], [PTR, PTR])
        return [] if failed?(hr)
        enum = pointer_value(pp)
        enum_strings(enum)
      ensure
        release(enum)
        release(factory)
      end
    rescue Exception
      Log.warning("SpellCheck languages failed: #{$!.class}: #{$!.message}")
      []
    end

    def check(language, text)
      text = text.to_s
      return [] if text == ""
      factory = create_factory
      return [] if factory == 0
      checker = 0
      errors = 0
      begin
        language_w = wide_string(language)
        supported = [0].pack("l")
        hr = com_call(factory, 4, [factory, language_w, supported], [PTR, PTR, PTR])
        return [] if failed?(hr) || supported.unpack("l").first == 0
        pp = pointer_buffer
        hr = com_call(factory, 5, [factory, language_w, pp], [PTR, PTR, PTR])
        return [] if failed?(hr)
        checker = pointer_value(pp)
        text_w = wide_string(text)
        pp = pointer_buffer
        hr = com_call(checker, 4, [checker, text_w, pp], [PTR, PTR, PTR])
        return [] if failed?(hr)
        errors = pointer_value(pp)
        collect_errors(checker, errors, text)
      ensure
        release(errors)
        release(checker)
        release(factory)
      end
    rescue Exception
      Log.warning("SpellCheck failed: #{$!.class}: #{$!.message}")
      []
    end

    private

    PTR = Fiddle::TYPE_VOIDP
    INT = Fiddle::TYPE_INT
    UINT = Fiddle::TYPE_INT
    ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
    CLSID_SPELLCHECKER_FACTORY = "{7AB36653-1796-484B-BDFA-E74F1DB7C1DC}"
    IID_ISPELLCHECKER_FACTORY = "{8E018A9D-2415-4677-BF08-794EA61F94BB}"

    def ole32
      @ole32 ||= Fiddle.dlopen("ole32")
    end

    def co_initialize_ex
      @co_initialize_ex ||= Fiddle::Function.new(ole32["CoInitializeEx"], [PTR, INT], INT, ABI)
    end

    def co_create_instance
      @co_create_instance ||= Fiddle::Function.new(ole32["CoCreateInstance"], [PTR, PTR, UINT, PTR, PTR], INT, ABI)
    end

    def co_task_mem_free
      @co_task_mem_free ||= Fiddle::Function.new(ole32["CoTaskMemFree"], [PTR], Fiddle::TYPE_VOID, ABI)
    end

    def initialized_com!
      return true if Thread.current[COM_THREAD_KEY]
      hr = co_initialize_ex.call(0, COINIT_APARTMENTTHREADED)
      initialized = succeeded?(hr) || hresult(hr) == RPC_E_CHANGED_MODE
      Thread.current[COM_THREAD_KEY] = true if initialized
      initialized
    end

    def create_factory
      return 0 unless initialized_com!
      pp = pointer_buffer
      hr = co_create_instance.call(guid(CLSID_SPELLCHECKER_FACTORY), 0, CLSCTX_INPROC_SERVER, guid(IID_ISPELLCHECKER_FACTORY), pp)
      return 0 if failed?(hr)
      pointer_value(pp)
    end

    def collect_errors(checker, errors, text)
      results = []
      loop do
        pp_error = pointer_buffer
        hr = com_call(errors, 3, [errors, pp_error], [PTR, PTR])
        break if hr == S_FALSE || failed?(hr)
        error = pointer_value(pp_error)
        next if error == 0
        begin
          result = error_to_result(checker, error, text)
          results << result if result != nil
          break if results.size >= MAX_ERRORS
        ensure
          release(error)
        end
      end
      results
    end

    def error_to_result(checker, error, text)
      start_units = out_ulong { |buf| com_call(error, 3, [error, buf], [PTR, PTR]) }
      length_units = out_ulong { |buf| com_call(error, 4, [error, buf], [PTR, PTR]) }
      return nil if start_units == nil || length_units == nil
      result = Result.new
      result.index = utf16_units_to_chars(text, start_units)
      result.length = utf16_units_to_chars(text, start_units + length_units) - result.index
      action = out_int { |buf| com_call(error, 5, [error, buf], [PTR, PTR]) }
      case action
      when CORRECTIVE_ACTION_DELETE
        result.suggestions << ""
      when CORRECTIVE_ACTION_REPLACE
        replacement = out_wide_string { |buf| com_call(error, 6, [error, buf], [PTR, PTR]) }
        result.suggestions << replacement if replacement != nil
      when CORRECTIVE_ACTION_GET_SUGGESTIONS
        word = text[result.index, result.length] || ""
        result.suggestions.concat(suggestions(checker, word))
      end
      result
    end

    def suggestions(checker, word)
      pp = pointer_buffer
      word_w = wide_string(word)
      hr = com_call(checker, 5, [checker, word_w, pp], [PTR, PTR, PTR])
      return [] if failed?(hr)
      enum = pointer_value(pp)
      enum_strings(enum)
    ensure
      release(enum)
    end

    def enum_strings(enum)
      values = []
      return values if enum == nil || enum == 0
      loop do
        strbuf = pointer_buffer
        fetched = [0].pack("L")
        hr = com_call(enum, 3, [enum, 1, strbuf, fetched], [PTR, UINT, PTR, PTR])
        break if hr != S_OK
        ptr = pointer_value(strbuf)
        next if ptr == 0
        begin
          values << wide_pointer_to_utf8(ptr)
        ensure
          co_task_mem_free.call(ptr)
        end
      end
      values
    end

    def out_ulong
      buffer = [0].pack("L")
      hr = yield(buffer)
      return nil if failed?(hr)
      buffer.unpack("L").first
    end

    def out_int
      buffer = [0].pack("l")
      hr = yield(buffer)
      return nil if failed?(hr)
      buffer.unpack("l").first
    end

    def out_wide_string
      buffer = pointer_buffer
      hr = yield(buffer)
      return nil if failed?(hr)
      ptr = pointer_value(buffer)
      return nil if ptr == 0
      begin
        wide_pointer_to_utf8(ptr)
      ensure
        co_task_mem_free.call(ptr)
      end
    end

    def release(object)
      return if object == nil || object == 0
      com_call(object, 2, [object], [PTR])
    rescue Exception
    end

    def com_call(object, index, args, types, ret = INT)
      pointer = vtable_method(object, index)
      function = Fiddle::Function.new(pointer, types, ret, ABI)
      function.call(*args)
    end

    def vtable_method(object, index)
      object_pointer = Fiddle::Pointer.new(object.to_i)
      vtable = pointer_value(object_pointer[0, EltenWin32::POINTER_SIZE])
      vtable_pointer = Fiddle::Pointer.new(vtable.to_i)
      pointer_value(vtable_pointer[index.to_i * EltenWin32::POINTER_SIZE, EltenWin32::POINTER_SIZE])
    end

    def guid(value)
      parts = value.delete("{}").split("-")
      data4 = (parts[3] + parts[4]).scan(/../).map { |byte| byte.to_i(16) }
      [parts[0].to_i(16), parts[1].to_i(16), parts[2].to_i(16), *data4].pack("L<S<S<C8")
    end

    def pointer_buffer(value = 0)
      EltenWin32.pointer_buffer(value)
    end

    def pointer_value(buffer)
      EltenWin32.pointer_value(buffer)
    end

    def wide_string(value)
      (value.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace) + [0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
    end

    def wide_pointer_to_utf8(pointer)
      ptr = Fiddle::Pointer.new(pointer.to_i)
      bytes = +""
      offset = 0
      loop do
        chunk = ptr[offset, 2]
        break if chunk == nil || chunk.bytesize < 2 || chunk == "\0\0"
        bytes << chunk
        offset += 2
      end
      bytes.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    end

    def utf16_units_to_chars(text, units)
      target = units.to_i
      used = 0
      chars = 0
      text.to_s.each_char do |char|
        char_units = char.encode("UTF-16LE", invalid: :replace, undef: :replace).bytesize / 2
        break if used + char_units > target
        used += char_units
        chars += 1
      end
      chars
    end

    def hresult(value)
      hr = value.to_i
      hr -= 0x100000000 if hr > 0x7fffffff
      hr
    end

    def succeeded?(hr)
      hresult(hr) >= 0
    end

    def failed?(hr)
      !succeeded?(hr)
    end
  end
end
