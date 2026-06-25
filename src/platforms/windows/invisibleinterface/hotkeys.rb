# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module InvisibleInterface
    module Hotkeys
      MOD_ALT = 0x0001
      MOD_CONTROL = 0x0002
      MOD_SHIFT = 0x0004
      MOD_WIN = 0x0008
      WM_HOTKEY = 0x0312
      WM_QUIT = 0x0012
      KEY_ID_BASE = 0x8000
      KEY_CODES = [0x25, 0x26, 0x27, 0x28, 0x20, 0x21, 0x22, 0x24, 0x23, 0x0d, 0x08, 70, 75, 77, 82].freeze
      AUTO_MODIFIERS = [
        MOD_ALT | MOD_CONTROL | MOD_WIN,
        MOD_ALT | MOD_SHIFT | MOD_WIN,
        MOD_ALT | MOD_CONTROL | MOD_SHIFT,
        MOD_ALT | MOD_CONTROL,
        MOD_ALT | MOD_SHIFT
      ].freeze
      MSG_SIZE = Fiddle::SIZEOF_VOIDP == 8 ? 48 : 28
      MESSAGE_OFFSET = Fiddle::SIZEOF_VOIDP
      WPARAM_OFFSET = Fiddle::SIZEOF_VOIDP == 8 ? 16 : 8
      PTR = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT

      class << self
        def configure(modifiers, queue)
          modifiers = modifiers.to_i
          return true if @thread != nil && @thread.alive? && @modifiers == modifiers
          stop
          @modifiers = modifiers
          @queue = queue
          @thread = Thread.new { run(modifiers, queue) }
          @thread.report_on_exception = false
          true
        end

        def running?
          @thread != nil && @thread.alive?
        end

        def stop
          @stopping = true
          post_quit
          @thread.join(0.5) if @thread != nil && @thread.alive?
        rescue Exception
        ensure
          @thread = nil if @thread != nil && !@thread.alive?
          @thread_id = nil if @thread == nil
          @stopping = false
        end

        private

        def run(modifiers, queue)
          ensure_api
          @thread_id = @get_current_thread_id.call
          ensure_message_queue
          selected = register_configured(modifiers, queue)
          Log.info("Invisible Interface hotkeys registered: modifiers=#{selected}")
          queue << [:hotkey_modifiers_selected, selected] if modifiers.to_i == 0 && selected.to_i != 0
          message_loop(queue)
        rescue Exception => e
          queue << [:hotkey_error, e]
        ensure
          unregister_all
        end

        def register_configured(modifiers, queue)
          if modifiers.to_i == 0
            AUTO_MODIFIERS.each do |candidate|
              errors = register_all(candidate)
              return candidate if errors == 0
            end
            errors = register_all(AUTO_MODIFIERS.last)
            queue << [:hotkey_errors, errors] if errors > 0
            AUTO_MODIFIERS.last
          else
            errors = register_all(modifiers)
            queue << [:hotkey_errors, errors] if errors > 0
            modifiers
          end
        end

        def register_all(modifiers)
          unregister_all
          @registered = []
          errors = 0
          KEY_CODES.each do |key|
            id = KEY_ID_BASE + key
            if @register_hotkey.call(0, id, modifiers.to_i, key) == 0
              errors += 1
            else
              @registered << id
            end
          end
          errors
        end

        def unregister_all
          (@registered || []).each { |id| @unregister_hotkey.call(0, id) rescue nil }
          @registered = []
        end

        def message_loop(queue)
          msg = "\0" * MSG_SIZE
          loop do
            result = @get_message.call(msg, 0, 0, 0)
            break if result.to_i <= 0 || @stopping == true
            message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
            if message == WM_HOTKEY
              id = EltenWin32.pointer_value(msg, WPARAM_OFFSET)
              key = id.to_i - KEY_ID_BASE
              queue << [:hotkey, key] if key > 0
            else
              @translate_message.call(msg)
              @dispatch_message.call(msg)
            end
          end
        end

        def post_quit
          return if @thread_id == nil
          ensure_api
          @post_thread_message.call(@thread_id, WM_QUIT, 0, 0)
        rescue Exception
        end

        def ensure_api
          return if @register_hotkey != nil
          kernel32 = Fiddle.dlopen("kernel32")
          user32 = Fiddle.dlopen("user32")
          @get_current_thread_id = Fiddle::Function.new(kernel32["GetCurrentThreadId"], [], Fiddle::TYPE_INT)
          @register_hotkey = Fiddle::Function.new(user32["RegisterHotKey"], [PTR, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @unregister_hotkey = Fiddle::Function.new(user32["UnregisterHotKey"], [PTR, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @get_message = Fiddle::Function.new(user32["GetMessageW"], [Fiddle::TYPE_VOIDP, PTR, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @peek_message = Fiddle::Function.new(user32["PeekMessageW"], [Fiddle::TYPE_VOIDP, PTR, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @translate_message = Fiddle::Function.new(user32["TranslateMessage"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @dispatch_message = Fiddle::Function.new(user32["DispatchMessageW"], [Fiddle::TYPE_VOIDP], PTR)
          @post_thread_message = Fiddle::Function.new(user32["PostThreadMessageW"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, PTR, PTR], Fiddle::TYPE_INT)
        end

        def ensure_message_queue
          msg = "\0" * MSG_SIZE
          @peek_message.call(msg, 0, 0, 0, 0)
        end
      end
    end
  end
end
