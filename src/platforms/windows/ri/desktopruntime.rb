# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

unless defined?(Fiddle)
  verbose = $VERBOSE
  $VERBOSE = nil
  begin
    require "fiddle"
  ensure
    $VERBOSE = verbose
  end
end

require "monitor"

module EltenKeyboard
  ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
  USER32 = Fiddle.dlopen("user32.dll")
  GET_KEYBOARD_STATE = Fiddle::Function.new(USER32["GetKeyboardState"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, ABI)
  GET_ASYNC_KEY_STATE = Fiddle::Function.new(USER32["GetAsyncKeyState"], [Fiddle::TYPE_INT], Fiddle.const_defined?(:TYPE_SHORT) ? Fiddle::TYPE_SHORT : Fiddle::TYPE_INT, ABI)
  SYSTEM_PARAMETERS_INFO = Fiddle::Function.new(USER32["SystemParametersInfoW"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT, ABI)
  TO_UNICODE = Fiddle::Function.new(USER32["ToUnicode"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT, ABI)
  MAP_VIRTUAL_KEY = Fiddle::Function.new(USER32["MapVirtualKeyW"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT, ABI)
  SPI_GETKEYBOARDSPEED = 0x000A
  SPI_GETKEYBOARDDELAY = 0x0016
  KEYBOARD_SPEED_MIN_CPS = 2.5
  KEYBOARD_SPEED_MAX_CPS = 30.0
  STALE_REPEATABLE_KEY_SECONDS = 1.5
  STALE_MODIFIER_KEY_SECONDS = 15.0
  MODIFIER_KEYS = [0x10, 0x11, 0x12, 0x14, 0x5B, 0x5C, 0x5D]

  class << self
    def fill_flags(buffer)
      state = keyboard_state
      events = key_events
      keyboard_monitor.synchronize do
        initialize_state
        now = monotonic_time
        refresh_repeat_settings(now)
        event_flags = apply_key_events_to_state(state, events, now)
        flags = Array.new(256, 0)
        for key in 0..255
          down = key_down?(state, key)
          @stale_suppressed[key] = false if !down && @stale_suppressed[key] == true
          if down && stale_key_down?(key, now)
            already_suppressed = @stale_suppressed[key] == true
            down = false
            state.setbyte(key, state.getbyte(key).to_i & 0x7f)
            flags[key] |= 2 if @last_down[key]
            @next_repeat[key] = 0.0
            @last_down_event[key] = nil
            suppress_stale_key(key)
            Log.debug("Keyboard stale key released: #{key}") if !already_suppressed
          end
          if down
            if @last_down[key]
              flags[key] |= 4
              if repeatable_key?(key) && now >= @next_repeat[key].to_f
                flags[key] |= 1
                @next_repeat[key] = next_repeat_time(now, @next_repeat[key].to_f)
              end
            else
              flags[key] |= 1
              @next_repeat[key] = now + @repeat_delay
              @last_down_event[key] ||= now
            end
          elsif @last_down[key]
            flags[key] |= 2
            @next_repeat[key] = 0.0
            @last_down_event[key] = nil
          end
          @last_down[key] = down
        end
        for key in 0..255
          flags[key] |= event_flags[key]
        end
        @flags_state = state.byteslice(0, 256).to_s.dup
        for key in 0..255
          buffer.setbyte(key, flags[key]) if buffer.respond_to?(:setbyte)
        end
        0
      end
    end

    def sync_physical_state
      state = keyboard_state
      keyboard_monitor.synchronize do
        initialize_state
        now = monotonic_time
        for key in 0..255
          down = key_down?(state, key)
          @event_down[key] = down
          @last_down[key] = down
          @last_down_event[key] = down ? now : nil
          @stale_suppressed[key] = false
          @next_repeat[key] = 0.0
        end
      end
      true
    end

    def clear_state
      keyboard_monitor.synchronize do
        initialize_state
        @last_down = Array.new(256, false)
        @event_down = Array.new(256, false)
        @next_repeat = Array.new(256, 0.0)
        @last_down_event = Array.new(256)
        @stale_suppressed = Array.new(256, false)
      end
      true
    end

    def raw_state
      keyboard_state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
    rescue Exception
      "\0" * 256
    end

    def flags_state
      keyboard_monitor.synchronize do
        initialize_state
        @flags_state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
      end
    rescue Exception
      "\0" * 256
    end

    def active_pressed_keys
      return Array.new(256, false) if !EltenWindow.keyboard_active?
      state = raw_state
      keys = Array.new(256, false)
      for key in 0..255
        keys[key] = key_down?(state, key)
      end
      keys
    rescue Exception
      Array.new(256, false)
    end

    def translate_virtual_key(key, state = nil, flags = 4)
      state = normalize_keyboard_state(state)
      buffer = "\0" * 16
      count = TO_UNICODE.call(key.to_i, MAP_VIRTUAL_KEY.call(key.to_i, 0), state, buffer, buffer.bytesize / 2, flags.to_i)
      return "" if count <= 0
      buffer.byteslice(0, count * 2).to_s.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    rescue Exception
      ""
    end

    def stale_suppressed?(key)
      keyboard_monitor.synchronize do
        @stale_suppressed ||= Array.new(256, false)
        @stale_suppressed[key.to_i & 0xff] == true
      end
    rescue Exception
      false
    end

    def async_key_down?(key)
      (GET_ASYNC_KEY_STATE.call(key.to_i & 0xff).to_i & 0x8000) != 0
    rescue Exception
      false
    end

    def global_key_down?(key)
      async_key_down?(key)
    end

    private

    def keyboard_monitor
      @keyboard_monitor ||= Monitor.new
    end

    def initialize_state
      @last_down ||= Array.new(256, false)
      @event_down ||= Array.new(256, false)
      @next_repeat ||= Array.new(256, 0.0)
      @last_down_event ||= Array.new(256)
      @stale_suppressed ||= Array.new(256, false)
      @repeat_delay ||= 0.5
      @repeat_interval ||= 1.0 / 30.0
    end

    def keyboard_state
      state = EltenWindow.keyboard_state.to_s
      state.bytesize >= 256 ? state : state.ljust(256, "\0")
    rescue Exception
      "\0" * 256
    end

    def key_events
      EltenWindow.consume_key_events
    rescue Exception
      []
    end

    def apply_key_events_to_state(state, events, now)
      flags = Array.new(256, 0)
      events.each do |key, down|
        key = key.to_i
        next if key < 0 || key > 255
        byte = state.getbyte(key).to_i
        if down == true
          @event_down[key] = true
          state.setbyte(key, byte | 0x80)
          flags[key] |= 1
          @last_down_event[key] = now
          @stale_suppressed[key] = false
        elsif down == :repeat
          @event_down[key] = true
          state.setbyte(key, byte | 0x80)
          @last_down_event[key] = now
          @stale_suppressed[key] = false
        else
          @event_down[key] = false
          state.setbyte(key, byte & 0x7f)
          flags[key] |= 2
          @last_down_event[key] = nil
          @stale_suppressed[key] = false
        end
      end
      for key in 0..255
        state.setbyte(key, state.getbyte(key).to_i | 0x80) if @event_down[key] == true
      end
      flags
    rescue Exception
      Array.new(256, 0)
    end

    def key_down?(state, key)
      (state.getbyte(key).to_i & 0x80) != 0
    end

    def stale_key_down?(key, now)
      return true if @stale_suppressed[key] == true
      return false if @last_down[key] != true
      last = @last_down_event[key]
      return false if last == nil
      now - last.to_f > stale_key_timeout(key)
    rescue Exception
      false
    end

    def stale_key_timeout(key)
      repeatable_key?(key) ? STALE_REPEATABLE_KEY_SECONDS : STALE_MODIFIER_KEY_SECONDS
    end

    def suppress_stale_key(key)
      @event_down[key] = false if @event_down != nil
      @stale_suppressed[key] = true
    rescue Exception
    end

    def normalize_keyboard_state(state)
      if state.is_a?(Array)
        state.map { |key| key ? 255 : 0 }.pack("C*")
      else
        state.to_s
      end.byteslice(0, 256).to_s.ljust(256, "\0")
    rescue Exception
      "\0" * 256
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue Exception
      Time.now.to_f
    end

    def refresh_repeat_settings(now)
      return if @repeat_settings_checked != nil && now - @repeat_settings_checked < 5.0
      @repeat_settings_checked = now
      delay = [0].pack("i")
      if SYSTEM_PARAMETERS_INFO.call(SPI_GETKEYBOARDDELAY, 0, delay, 0) != 0
        delay_index = delay.unpack("i").first.to_i
        delay_index = 0 if delay_index < 0
        delay_index = 3 if delay_index > 3
        @repeat_delay = 0.25 + delay_index * 0.25
      end

      speed = [31].pack("i")
      if SYSTEM_PARAMETERS_INFO.call(SPI_GETKEYBOARDSPEED, 0, speed, 0) != 0
        speed_index = speed.unpack("i").first.to_i
        speed_index = 0 if speed_index < 0
        speed_index = 31 if speed_index > 31
        cps = KEYBOARD_SPEED_MIN_CPS + (KEYBOARD_SPEED_MAX_CPS - KEYBOARD_SPEED_MIN_CPS) * speed_index / 31.0
        @repeat_interval = 1.0 / cps
      end
    rescue Exception
      @repeat_delay ||= 0.5
      @repeat_interval ||= 1.0 / 30.0
    end

    def next_repeat_time(now, previous)
      interval = @repeat_interval || (1.0 / 30.0)
      next_time = previous + interval
      if next_time <= now
        missed = ((now - previous) / interval).floor
        next_time = previous + interval * (missed + 1)
      end
      next_time <= now ? now + interval : next_time
    end

    def repeatable_key?(key)
      !MODIFIER_KEYS.include?(key)
    end
  end
end

module EltenWindow
  ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
  PTR = Fiddle::TYPE_VOIDP
  HANDLE = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
  INT = Fiddle::TYPE_INT
  USER32 = Fiddle.dlopen("user32.dll")
  KERNEL32 = Fiddle.dlopen("kernel32.dll")
  GET_CURRENT_THREAD_ID = Fiddle::Function.new(KERNEL32["GetCurrentThreadId"], [], INT, ABI)
  GET_LAST_ERROR = Fiddle::Function.new(KERNEL32["GetLastError"], [], INT, ABI)
  SHOW_WINDOW = Fiddle::Function.new(USER32["ShowWindow"], [HANDLE, INT], INT, ABI)
  GET_MESSAGE = Fiddle::Function.new(USER32["GetMessageW"], [PTR, HANDLE, INT, INT], INT, ABI)
  TRANSLATE_MESSAGE = Fiddle::Function.new(USER32["TranslateMessage"], [PTR], INT, ABI)
  DISPATCH_MESSAGE = Fiddle::Function.new(USER32["DispatchMessageW"], [PTR], HANDLE, ABI)
  POST_MESSAGE = Fiddle::Function.new(USER32["PostMessageW"], [HANDLE, INT, HANDLE, HANDLE], INT, ABI)
  POST_THREAD_MESSAGE = Fiddle::Function.new(USER32["PostThreadMessageW"], [INT, INT, HANDLE, HANDLE], INT, ABI)
  DESTROY_WINDOW = Fiddle::Function.new(USER32["DestroyWindow"], [HANDLE], INT, ABI)
  DEF_WINDOW_PROC = Fiddle::Function.new(USER32["DefWindowProcW"], [HANDLE, INT, HANDLE, HANDLE], HANDLE, ABI)
  POST_QUIT_MESSAGE = Fiddle::Function.new(USER32["PostQuitMessage"], [INT], Fiddle::TYPE_VOID, ABI)
  REGISTER_HOT_KEY = Fiddle::Function.new(USER32["RegisterHotKey"], [HANDLE, INT, INT, INT], INT, ABI)
  UNREGISTER_HOT_KEY = Fiddle::Function.new(USER32["UnregisterHotKey"], [HANDLE, INT], INT, ABI)
  GET_FOREGROUND_WINDOW = Fiddle::Function.new(USER32["GetForegroundWindow"], [], HANDLE, ABI)
  GET_PARENT = Fiddle::Function.new(USER32["GetParent"], [HANDLE], HANDLE, ABI)
  IS_ICONIC = Fiddle::Function.new(USER32["IsIconic"], [HANDLE], INT, ABI)
  GET_WINDOW_LONG = Fiddle::Function.new(USER32["GetWindowLongW"], [HANDLE, INT], INT, ABI)
  SET_WINDOW_LONG = Fiddle::Function.new(USER32["SetWindowLongW"], [HANDLE, INT, INT], INT, ABI)
  SET_FOREGROUND_WINDOW = Fiddle::Function.new(USER32["SetForegroundWindow"], [HANDLE], INT, ABI)
  SET_ACTIVE_WINDOW = Fiddle::Function.new(USER32["SetActiveWindow"], [HANDLE], HANDLE, ABI)
  SET_FOCUS = Fiddle::Function.new(USER32["SetFocus"], [HANDLE], HANDLE, ABI)
  MESSAGE_BOX = Fiddle::Function.new(USER32["MessageBoxW"], [HANDLE, PTR, PTR, INT], INT, ABI)
  GET_KEYBOARD_STATE = Fiddle::Function.new(USER32["GetKeyboardState"], [PTR], INT, ABI)
  SET_KEYBOARD_STATE = Fiddle::Function.new(USER32["SetKeyboardState"], [PTR], INT, ABI)
  WINDOW_TITLE = "Elten"
  WS_CAPTION = 0x00C00000
  WS_SYSMENU = 0x00080000
  WS_MINIMIZEBOX = 0x00020000
  WINDOW_STYLE = WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
  SW_HIDE = 0
  SW_SHOW = 5
  SW_RESTORE = 9
  WM_CLOSE = 0x0010
  WM_DESTROY = 0x0002
  WM_QUIT = 0x0012
  WM_SIZE = 0x0005
  WM_ACTIVATE = 0x0006
  WM_SETFOCUS = 0x0007
  WM_KILLFOCUS = 0x0008
  WM_ACTIVATEAPP = 0x001C
  WM_KEYDOWN = 0x0100
  WM_KEYUP = 0x0101
  WM_SYSCOMMAND = 0x0112
  WM_CHAR = 0x0102
  WM_DEADCHAR = 0x0103
  WM_SYSKEYDOWN = 0x0104
  WM_SYSKEYUP = 0x0105
  WM_SYSCHAR = 0x0106
  WM_UNICHAR = 0x0109
  WM_HOTKEY = 0x0312
  WM_APP = 0x8000
  WM_DISPATCH_ACTIONS = WM_APP + 0x51
  WM_REQUEST_EXIT = WM_APP + 0x52
  RESTORE_HOTKEY_ID = 0x454C
  RESTORE_HOTKEY_MODIFIERS = 0x0001 | 0x0002 | 0x0004 | 0x4000
  VK_T = 0x54
  VK_CONTROL = 0x11
  VK_MENU = 0x12
  VK_F4 = 0x73
  VK_LCONTROL = 0xA2
  UNICODE_NOCHAR = 0xFFFF
  SIZE_MINIMIZED = 1
  GWL_STYLE = -16
  SC_KEYMENU = 0xF100
  SC_CLOSE = 0xF060
  SC_MINIMIZE = 0xF020
  KEYBOARD_ACTIVATION_MIN_DELAY = 0.05
  KEYBOARD_ACTIVATION_MAX_DELAY = 0.5
  ACTIVATION_ACK_WARNING_SECONDS = 1.0
  WINDOW_UPDATE_WARNING_SECONDS = 1.0
  MINIMIZE_RESTORE_SUPPRESS_TIME = 1.0
  MSG_SIZE = Fiddle::SIZEOF_VOIDP == 8 ? 48 : 28

  class << self
    attr_reader :hwnd

    def ensure_window
      @window_thread ||= Thread.current
      window_state_monitor
      pump_sync
      return @hwnd if @hwnd != nil && @hwnd != 0
      if $wnd != nil && $wnd != 0
        @hwnd = $wnd
        ensure_window_style
        return @hwnd
      end
      raise RuntimeError, "Main window must be created on its message thread" unless window_thread?
      @hwnd = EltenBoot.create_window.to_i
      raise RuntimeError, "Failed to create the Elten main window" if @hwnd == 0
      $wnd = @hwnd
      ensure_window_style
      @hwnd
    end

    def show(command = SW_SHOW)
      return post_window_action(true) { show(command) } unless window_thread?
      ensure_window
      show_window(@hwnd, command)
      @hwnd
    end

    def hide
      hide_window
    end

    def show_window(hwnd = nil, command = SW_SHOW)
      return post_window_action(true) { show_window(hwnd, command) } unless window_thread?
      hwnd = window_handle(hwnd)
      return 0 if hwnd == 0
      SHOW_WINDOW.call(hwnd, command.to_i)
    rescue Exception
      0
    end

    def hide_window(hwnd = nil)
      show_window(hwnd, SW_HIDE)
    end

    def focus(hwnd = nil)
      return post_window_action(true) { focus(hwnd) } unless window_thread?
      hwnd = window_handle(hwnd)
      return false if hwnd == 0
      set_foreground_window.call(hwnd)
      set_active_window.call(hwnd)
      set_focus.call(hwnd)
      true
    rescue Exception
      false
    end

    def message_box(text, caption = WINDOW_TITLE, flags = 0, owner = nil)
      return post_window_action(true) { message_box(text, caption, flags, owner) } unless window_thread?
      owner = window_handle(owner, false)
      MESSAGE_BOX.call(owner, wide_string(text), wide_string(caption), flags.to_i)
    rescue Exception
      0
    end

    def foreground_window
      GET_FOREGROUND_WINDOW.call
    rescue Exception
      0
    end

    def active_or_child?(hwnd = nil)
      target = window_handle(hwnd, false)
      return false if target == 0
      current = foreground_window.to_i
      16.times do
        return true if current == target
        break if current == 0
        current = GET_PARENT.call(current).to_i
      end
      false
    rescue Exception
      false
    end

    def minimized?
      ensure_window
      return false if @hwnd == nil || @hwnd == 0
      return false if minimize_request_suppressed?
      is_iconic.call(@hwnd) != 0
    rescue Exception
      false
    end

    def tray_supported?
      true
    end

    def hide_to_tray
      return post_window_action(true) { hide_to_tray } unless window_thread?
      ensure_window
      return false if @hwnd == nil || @hwnd == 0
      EltenTray.show(@hwnd) if defined?(EltenTray)
      hide
      clear_input_state
      true
    rescue Exception => e
      Log.warning("Elten window hide to tray failed: #{e}")
      false
    end

    def restore_from_tray
      return post_window_action(true) { restore_from_tray } unless window_thread?
      ensure_window
      return false if @hwnd == nil || @hwnd == 0
      suppress_minimize_requests
      show(SW_RESTORE)
      focus(@hwnd)
      clear_input_state(preserve_activation_guard: true)
      suppress_minimize_requests
      true
    rescue Exception => e
      Log.warning("Elten window restore from tray failed: #{e}")
      false
    end

    def keyboard_active?
      ensure_window
      return false if @hwnd == nil || @hwnd == 0
      foreground_window_active?
    end

    def keyboard_key_held?(key)
      return false if !keyboard_active?
      EltenKeyboard.async_key_down?(key)
    rescue Exception
      false
    end

    def pump_messages
      true
    end

    def run_windows_message_loop
      ensure_window
      @window_thread = Thread.current
      @window_thread_id = GET_CURRENT_THREAD_ID.call.to_i
      @message_loop_stopped = false
      register_restore_hotkey
      message = "\0" * MSG_SIZE
      loop do
        result = GET_MESSAGE.call(message, 0, 0, 0).to_i
        break if result == 0
        raise RuntimeError, "GetMessageW failed: #{GET_LAST_ERROR.call}" if result == -1
        TRANSLATE_MESSAGE.call(message)
        DISPATCH_MESSAGE.call(message)
      end
      true
    ensure
      unregister_restore_hotkey
      window_state_monitor.synchronize { @close_requested = true }
      fail_pending_window_actions(RuntimeError.new("Windows message loop has stopped"))
    end

    def request_windows_exit
      hwnd = window_handle(nil, false)
      return true if hwnd != 0 && POST_MESSAGE.call(hwnd, WM_REQUEST_EXIT, 0, 0) != 0
      thread_id = @window_thread_id.to_i
      return true if thread_id == 0
      POST_THREAD_MESSAGE.call(thread_id, WM_QUIT, 0, 0) != 0
    rescue Exception
      false
    end

    def window_proc(hwnd, message, wparam, lparam)
      message = message.to_i
      wparam = wparam.to_i
      lparam = lparam.to_i
      case message
      when WM_HOTKEY
        if wparam == RESTORE_HOTKEY_ID
          EltenTray.request_restore("hotkey CTRL+ALT+SHIFT+T") if defined?(EltenTray)
          return 0
        end
      when WM_DISPATCH_ACTIONS
        service_window_requests(wparam)
        return 0
      when WM_REQUEST_EXIT
        if DESTROY_WINDOW.call(hwnd) == 0
          Log.error("DestroyWindow failed: #{GET_LAST_ERROR.call}") if defined?(Log)
          POST_QUIT_MESSAGE.call(1)
        end
        return 0
      when WM_DESTROY
        window_state_monitor.synchronize do
          @close_requested = true
          @hwnd = 0 if @hwnd.to_i == hwnd.to_i
          $wnd = 0 if $wnd.to_i == hwnd.to_i
        end
        POST_QUIT_MESSAGE.call(0)
        return 0
      end

      focus_message(message, wparam)
      return 0 if activation_key_message?(message)
      if defined?(EltenTray) && message == EltenTray::CALLBACK_MESSAGE
        return 0 if EltenTray.handle_callback(wparam, lparam)
      end
      return 0 if close_message?(message, wparam, lparam)
      minimize_message(message, wparam)
      record_key_message(message, wparam, lparam)
      if character_message?(message)
        return 1 if message == WM_UNICHAR && wparam == UNICODE_NOCHAR
        enqueue_character_message(message, wparam) unless activation_input_blocked?
        return 0
      end
      return 0 if menu_message?(message, wparam)
      DEF_WINDOW_PROC.call(hwnd, message, wparam, lparam)
    rescue Exception => e
      Log.error("Main window procedure failed: #{e.class}: #{e.message}") if defined?(Log)
      DEF_WINDOW_PROC.call(hwnd, message, wparam, lparam) rescue 0
    end

    def activation_input_blocked?(consume_finish: false)
      unless window_thread?
        return window_state_monitor.synchronize { @activation_input_guard_active == true }
      end
      window_state_monitor.synchronize do
        next false if @activation_input_guard_active != true
        now = monotonic_time
        state = capture_keyboard_state_raw
        if @activation_input_acknowledged != true
          sync_keyboard_state_without_delivery(state)
          clear_character_queue
          next true
        end
        if now <= @activation_ignore_min_until.to_f || (now <= @activation_ignore_max_until.to_f && keyboard_state_has_pressed_keys?(state))
          sync_keyboard_state_without_delivery(state)
          clear_character_queue
          next true
        end
        finish_activation_ignore(state)
        consume_finish == true
      end
    rescue Exception
      clear_activation_guard
      false
    end

    def close_requested?
      window_state_monitor.synchronize { @close_requested == true }
    end

    def restore_hotkey_registered?
      @restore_hotkey_registered == true
    end

    def consume_close_request
      window_state_monitor.synchronize do
        requested = @close_requested == true
        @close_requested = false
        requested
      end
    end

    def consume_quit_shortcut_request
      window_state_monitor.synchronize do
        requested = @quit_shortcut_requested == true
        @quit_shortcut_requested = false
        requested
      end
    rescue Exception
      false
    end

    def consume_alt_quit_shortcut_request
      window_state_monitor.synchronize do
        requested = @alt_quit_shortcut_requested == true
        @alt_quit_shortcut_requested = false
        requested
      end
    rescue Exception
      false
    end

    def consume_minimize_request
      window_state_monitor.synchronize do
        if minimize_request_suppressed?
          @minimize_requested = false
          next false
        end
        requested = @minimize_requested == true
        @minimize_requested = false
        requested
      end
    end

    def update_messages
      if window_thread?
        service_window_requests
      else
        request_window_update
      end
      true
    end

    def service_window_update
      return service_window_requests if window_thread?
      request_window_update
    end

    def keyboard_state
      window_state_monitor.synchronize do
        @keyboard_state ||= ("\0" * 256)
        normalize_altgr_keyboard_state(@keyboard_state.dup)
      end
    end

    def clear_input_state(preserve_activation_guard: false)
      clear_activation_guard if preserve_activation_guard != true
      if !window_thread?
        post_window_action(true) { clear_input_state(preserve_activation_guard: preserve_activation_guard) }
        return true
      end
      clear_native_keyboard_state
      window_state_monitor.synchronize do
        @keyboard_state = "\0" * 256
        clear_character_queue
        clear_key_events
      end
      EltenKeyboard.clear_state
      true
    end

    def clear_input_state_preserving_activation_guard
      clear_input_state(preserve_activation_guard: true)
    end

    def post_window_action(wait = false, &block)
      return false if block == nil
      return block.call if window_thread?
      pump_sync
      action = { :block => block, :done => false, :result => nil, :error => nil }
      @pump_mutex.synchronize do
        @window_actions ||= []
        @window_actions << action
      end
      begin
        wake_window_thread(0)
      rescue Exception => e
        @pump_mutex.synchronize do
          @window_actions.delete(action)
          action[:error] = e
          action[:done] = true
          @pump_cond.broadcast
        end
        raise
      end
      return true unless wait
      @pump_mutex.synchronize do
        @pump_cond.wait(@pump_mutex) while action[:done] != true && @message_loop_stopped != true
        raise action[:error] if action[:error] != nil
        raise RuntimeError, "Windows message loop stopped before executing an action" if action[:done] != true
        action[:result]
      end
    end

    def window_thread?
      @window_thread ||= (($mainthread != nil) ? $mainthread : Thread.current)
      Thread.current == @window_thread
    end

    def begin_input_frame
      window_state_monitor.synchronize do
        @character_queue ||= []
        @character_queue.shift(@character_frame_prefix_size.to_i) if @character_frame_consumed != true
        @character_frame_prefix_size = 0
        @character_frame_consumed = false
      end
      true
    end

    def keyboard_flags_driven?
      false
    end

    def character_input_supported?
      true
    end

    def keyboard_event_driven?
      true
    end

    def keyboard_pressed_implies_held?
      false
    end

    def keyboard_native_repeat_events?
      true
    end

    def keyboard_scene_transition_guard?
      true
    end

    def take_character(multi = false)
      window_state_monitor.synchronize do
        @character_queue ||= []
        @character_frame_consumed = true
        next "" if @character_queue.empty?
        if multi
          text = @character_queue.join
          @character_queue.clear
          text
        else
          @character_queue.shift.to_s
        end
      end
    end

    def consume_key_events
      window_state_monitor.synchronize do
        @key_event_queue ||= []
        events = normalize_altgr_key_events(@key_event_queue)
        @key_event_queue = []
        events
      end
    end

    def consume_keyboard_snapshot
      window_state_monitor.synchronize do
        @keyboard_state ||= ("\0" * 256)
        @key_event_queue ||= []
        state = normalize_altgr_keyboard_state(@keyboard_state.dup)
        events = normalize_altgr_key_events(@key_event_queue)
        @key_event_queue = []
        clear_finished_altgr_character_input
        [state, events]
      end
    end

    private

    def request_window_update
      pump_sync
      started_at = monotonic_time
      token = nil
      @pump_mutex.synchronize do
        @pump_request += 1
        token = @pump_request
      end
      wake_window_thread(token)
      @pump_mutex.synchronize do
        @pump_cond.wait(@pump_mutex) while @completed_updates[token] != true && @message_loop_stopped != true
        raise RuntimeError, "Windows message loop stopped during an update" if @completed_updates[token] != true
        @completed_updates.delete(token)
      end
      elapsed = monotonic_time - started_at
      Log.warning("Windows window update dispatch waited %.3f seconds" % elapsed) if elapsed >= WINDOW_UPDATE_WARNING_SECONDS && defined?(Log)
      true
    end

    def pump_sync
      @pump_mutex ||= Mutex.new
      @pump_cond ||= ConditionVariable.new
      @pump_request ||= 0
      @completed_updates ||= {}
    end

    def window_state_monitor
      @window_state_monitor ||= Monitor.new
    end

    def wake_window_thread(token)
      hwnd = window_handle(nil, false)
      raise RuntimeError, "Elten main window is not available" if hwnd == 0
      result = POST_MESSAGE.call(hwnd, WM_DISPATCH_ACTIONS, token.to_i, 0)
      raise RuntimeError, "PostMessageW failed: #{GET_LAST_ERROR.call}" if result == 0
      true
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue Exception
      Time.now.to_f
    end

    def suppress_minimize_requests(duration = MINIMIZE_RESTORE_SUPPRESS_TIME)
      window_state_monitor.synchronize do
        @minimize_requested = false
        @minimize_suppressed_until = monotonic_time + duration.to_f
      end
      true
    rescue Exception
      false
    end

    def minimize_request_suppressed?
      window_state_monitor.synchronize do
        next false if @minimize_suppressed_until == nil
        if monotonic_time < @minimize_suppressed_until.to_f
          true
        else
          @minimize_suppressed_until = nil
          false
        end
      end
    rescue Exception
      false
    end

    def foreground_window_active?
      foreground_window.to_i == @hwnd.to_i
    rescue Exception
      false
    end

    def window_handle(hwnd = nil, create = true)
      return hwnd.to_i if hwnd != nil && hwnd.to_i != 0
      ensure_window if create
      return @hwnd.to_i if @hwnd != nil && @hwnd.to_i != 0
      return $wnd.to_i if $wnd != nil && $wnd.to_i != 0
      0
    rescue Exception
      0
    end

    def ensure_window_style
      return false if @hwnd == nil || @hwnd == 0
      style = get_window_long.call(@hwnd, GWL_STYLE).to_i
      desired = style | WINDOW_STYLE
      set_window_long.call(@hwnd, GWL_STYLE, desired) if desired != style
      true
    rescue Exception
      false
    end

    def is_iconic
      IS_ICONIC
    end

    def get_window_long
      GET_WINDOW_LONG
    end

    def set_window_long
      SET_WINDOW_LONG
    end

    def set_foreground_window
      SET_FOREGROUND_WINDOW
    end

    def set_active_window
      SET_ACTIVE_WINDOW
    end

    def set_focus
      SET_FOCUS
    end

    def update_focus_state(active = nil)
      active = foreground_window_active? if active == nil
      window_state_monitor.synchronize do
        previous = @keyboard_foreground_active
        @keyboard_foreground_active = active
        if active == true && previous != true
          ignore_activation_input
        elsif active != true && previous == true
          clear_activation_guard
          clear_character_queue
          clear_key_events
          @keyboard_state = "\0" * 256
          EltenKeyboard.clear_state
        end
      end
      active
    rescue Exception
      false
    end

    def ignore_activation_input
      window_state_monitor.synchronize do
        now = monotonic_time
        @activation_input_guard_active = true
        @activation_input_acknowledged = false
        @activation_input_started_at = now
        @activation_ignore_min_until = nil
        @activation_ignore_max_until = nil
        clear_character_queue
        clear_key_events
        EltenKeyboard.clear_state
      end
      true
    end

    def clear_activation_guard
      window_state_monitor.synchronize do
        @activation_input_guard_active = false
        @activation_input_acknowledged = false
        @activation_input_started_at = nil
        @activation_ignore_min_until = nil
        @activation_ignore_max_until = nil
      end
      true
    end

    def acknowledge_activation_input
      delay = window_state_monitor.synchronize do
        return false if @activation_input_guard_active != true
        return true if @activation_input_acknowledged == true
        now = monotonic_time
        @activation_input_acknowledged = true
        @activation_ignore_min_until = now + KEYBOARD_ACTIVATION_MIN_DELAY
        @activation_ignore_max_until = now + KEYBOARD_ACTIVATION_MAX_DELAY
        now - @activation_input_started_at.to_f
      end
      if delay >= ACTIVATION_ACK_WARNING_SECONDS && defined?(Log)
        Log.warning("Windows input activation waited %.3f seconds for UI acknowledgement" % delay)
      end
      true
    rescue Exception
      clear_activation_guard
      false
    end

    def finish_activation_ignore(state = nil)
      window_state_monitor.synchronize do
        state ||= capture_keyboard_state_raw
        @keyboard_state = state
        EltenKeyboard.sync_physical_state
        clear_activation_guard
        clear_character_queue
        clear_key_events
      end
      true
    end

    def sync_keyboard_state_without_delivery(state)
      window_state_monitor.synchronize do
        @keyboard_state = state
        EltenKeyboard.sync_physical_state
        @keyboard_state = "\0" * 256
        clear_key_events
      end
      true
    rescue Exception
      window_state_monitor.synchronize { @keyboard_state = "\0" * 256 }
      false
    end

    def keyboard_state_has_pressed_keys?(state)
      state = state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
      for key in 0...256
        return true if (state.getbyte(key).to_i & 0x80) != 0
      end
      false
    rescue Exception
      false
    end

    def clear_character_queue
      window_state_monitor.synchronize do
        @character_queue ||= []
        @character_queue.clear
        @character_frame_prefix_size = 0
        @character_frame_consumed = false
        @high_surrogate = nil
      end
      true
    end

    def clear_key_events
      window_state_monitor.synchronize do
        @key_event_queue ||= []
        @key_event_queue.clear
        @key_message_down = Array.new(256, false)
        @right_alt_down = false
        @altgr_character_input = false
      end
      true
    end

    def run_window_actions
      actions = []
      @pump_mutex.synchronize do
        actions = @window_actions || []
        @window_actions = []
      end
      actions.each do |action|
        begin
          action[:result] = action[:block].call
        rescue Exception => e
          action[:error] = e
        ensure
          @pump_mutex.synchronize do
            action[:done] = true
            @pump_cond.broadcast
          end
        end
      end
      true
    end

    def service_window_requests(token = nil)
      return false unless window_thread?
      pump_sync
      token = token.to_i
      run_window_actions
      capture_keyboard_state
      acknowledge_activation_input if token > 0
      run_window_actions
      snapshot_character_frame if token > 0
      @pump_mutex.synchronize do
        @completed_updates[token] = true if token > 0
        @pump_cond.broadcast
      end
      true
    end

    def snapshot_character_frame
      window_state_monitor.synchronize do
        @character_queue ||= []
        @character_frame_prefix_size = @character_queue.size
      end
      true
    end

    def fail_pending_window_actions(error)
      pump_sync
      actions = []
      @pump_mutex.synchronize do
        @message_loop_stopped = true
        actions = @window_actions || []
        @window_actions = []
        actions.each do |action|
          action[:error] ||= error
          action[:done] = true
        end
        @pump_cond.broadcast
      end
      true
    end

    def register_restore_hotkey
      hwnd = window_handle(nil, false)
      @restore_hotkey_hwnd = hwnd
      @restore_hotkey_registered = hwnd != 0 && REGISTER_HOT_KEY.call(hwnd, RESTORE_HOTKEY_ID, RESTORE_HOTKEY_MODIFIERS, VK_T) != 0
      Log.warning("Could not register restore hotkey CTRL+ALT+SHIFT+T; using polling fallback") if !@restore_hotkey_registered && defined?(Log)
      @restore_hotkey_registered
    rescue Exception => e
      @restore_hotkey_registered = false
      Log.warning("Restore hotkey registration failed: #{e}") if defined?(Log)
      false
    end

    def unregister_restore_hotkey
      hwnd = @restore_hotkey_hwnd.to_i
      UNREGISTER_HOT_KEY.call(hwnd, RESTORE_HOTKEY_ID) if @restore_hotkey_registered == true && hwnd != 0
      @restore_hotkey_registered = false
      @restore_hotkey_hwnd = nil
      true
    rescue Exception
      @restore_hotkey_registered = false
      @restore_hotkey_hwnd = nil
      false
    end

    def capture_keyboard_state
      state = capture_keyboard_state_raw
      window_state_monitor.synchronize do
        @keyboard_state = state
        update_focus_state(foreground_window_active?)
        activation_input_blocked?
      end
      true
    rescue Exception
      window_state_monitor.synchronize { @keyboard_state ||= ("\0" * 256) }
      false
    end

    def capture_keyboard_state_raw
      state = "\0" * 256
      GET_KEYBOARD_STATE.call(state)
      state
    rescue Exception
      "\0" * 256
    end

    def clear_native_keyboard_state
      state = "\0" * 256
      GET_KEYBOARD_STATE.call(state)
      for i in 0...256
        state.setbyte(i, state.getbyte(i).to_i & 1)
      end
      SET_KEYBOARD_STATE.call(state)
      true
    rescue Exception
      false
    end

    def character_message?(message)
      message == WM_CHAR || message == WM_DEADCHAR || message == WM_UNICHAR
    end

    def close_message?(message, wparam, lparam = 0)
      if message == WM_CLOSE
        window_state_monitor.synchronize { @close_requested = true; @quit_shortcut_requested = true }
        return true
      end
      if message == WM_SYSKEYDOWN && wparam.to_i == VK_F4
        return true if repeated_key_message?(lparam)
        return true if activation_input_blocked?
        window_state_monitor.synchronize do
          @close_requested = true
          @quit_shortcut_requested = true
          @alt_quit_shortcut_requested = true
        end
        return true
      end
      return false unless message == WM_SYSCOMMAND
      command = wparam.to_i & 0xfff0
      if command == SC_CLOSE
        window_state_monitor.synchronize { @close_requested = true; @quit_shortcut_requested = true }
        return true
      end
      false
    end

    def minimize_message(message, wparam)
      window_state_monitor.synchronize do
        if minimize_request_suppressed?
          @minimize_requested = false
          next false
        end
        if message == WM_SIZE
          @minimize_requested = true if wparam.to_i == SIZE_MINIMIZED
        elsif message == WM_SYSCOMMAND
          @minimize_requested = true if (wparam.to_i & 0xfff0) == SC_MINIMIZE
        end
      end
      false
    rescue Exception
      false
    end

    def focus_message(message, wparam)
      case message
      when WM_SETFOCUS
        update_focus_state(true)
      when WM_KILLFOCUS
        update_focus_state(false)
      when WM_ACTIVATE
        update_focus_state((wparam & 0xffff) != 0)
      when WM_ACTIVATEAPP
        update_focus_state(wparam != 0)
      end
      false
    rescue Exception
      false
    end

    def activation_key_message?(message)
      return false unless message == WM_KEYDOWN || message == WM_KEYUP || message == WM_SYSKEYDOWN || message == WM_SYSKEYUP || message == WM_SYSCHAR
      activation_input_blocked?(consume_finish: true)
    rescue Exception
      false
    end

    def record_key_message(message, wparam, lparam)
      return false unless message == WM_KEYDOWN || message == WM_KEYUP || message == WM_SYSKEYDOWN || message == WM_SYSKEYUP
      key = wparam.to_i & 0xff
      return false if key <= 0 || key > 255
      down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN
      event = down && repeated_key_message?(lparam) ? :repeat : down
      press_state = capture_key_event_state if down
      window_state_monitor.synchronize do
        @key_message_down ||= Array.new(256, false)
        next if event == :repeat && @key_message_down[key] != true
        @key_message_down[key] = down
        @right_alt_down = down if key == VK_MENU && extended_key_message?(lparam)
        if @altgr_character_input == true && altgr_modifier_key?(key)
          if down == false
            next
          elsif @right_alt_down == true
            next
          else
            @altgr_character_input = false
          end
        end
        @key_event_queue ||= []
        @key_event_queue << [key, event, press_state]
        @key_event_queue.shift while @key_event_queue.size > 256
      end
      false
    rescue Exception
      false
    end

    def repeated_key_message?(lparam)
      (lparam.to_i & (1 << 30)) != 0
    rescue Exception
      false
    end

    def extended_key_message?(lparam)
      (lparam.to_i & (1 << 24)) != 0
    rescue Exception
      false
    end

    def capture_key_event_state
      state = "\0" * 256
      return nil if GET_KEYBOARD_STATE.call(state) == 0
      state
    rescue Exception
      nil
    end

    def enqueue_character_message(message, wparam)
      code = wparam.to_i
      return if code == 0 || code == UNICODE_NOCHAR || code < 32 || (code >= 0x7F && code <= 0x9F)
      return if message == WM_DEADCHAR
      window_state_monitor.synchronize do
        @character_queue ||= []
        begin_altgr_character_input if @right_alt_down == true
        if code >= 0xD800 && code <= 0xDBFF
          @high_surrogate = code
          next
        elsif code >= 0xDC00 && code <= 0xDFFF && @high_surrogate != nil
          @character_queue << [@high_surrogate, code].pack("S<S<").force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
          @high_surrogate = nil
        else
          @high_surrogate = nil
          @character_queue << [code].pack("U")
        end
      end
    rescue Exception
      @high_surrogate = nil
    end

    def begin_altgr_character_input
      @altgr_character_input = true
      @key_event_queue ||= []
      @key_event_queue.delete_if { |key, _event, _press_state| altgr_modifier_key?(key) }
    end

    def normalize_altgr_keyboard_state(state)
      return state if @altgr_character_input != true
      [VK_CONTROL, VK_LCONTROL, VK_MENU].each do |key|
        state.setbyte(key, state.getbyte(key).to_i & 0x7f)
      end
      state
    end

    def normalize_altgr_key_events(events)
      return events if @altgr_character_input != true
      events.reject { |key, _event, _press_state| altgr_modifier_key?(key) }
    end

    def clear_finished_altgr_character_input
      return if @altgr_character_input != true || @right_alt_down == true
      control_down = [VK_CONTROL, VK_LCONTROL].any? do |key|
        (@keyboard_state.getbyte(key).to_i & 0x80) != 0
      end
      @altgr_character_input = false if !control_down
    end

    def altgr_modifier_key?(key)
      key.to_i == VK_CONTROL || key.to_i == VK_LCONTROL || key.to_i == VK_MENU
    end

    def menu_message?(message, wparam)
      return true if message == WM_SYSKEYDOWN || message == WM_SYSKEYUP || message == WM_SYSCHAR
      return false if message != WM_SYSCOMMAND
      (wparam.to_i & 0xfff0) == SC_KEYMENU
    end

    def wide_string(text)
      (text.to_s.encode("UTF-16LE") + [0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
    end
  end
end

module EltenTray
  INTPTR = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
  NIM_ADD = 0
  NIM_MODIFY = 1
  NIM_DELETE = 2
  NIF_MESSAGE = 1
  NIF_ICON = 2
  NIF_TIP = 4
  WM_APP = 0x8000
  CALLBACK_MESSAGE = WM_APP + 0x4D
  WM_LBUTTONDOWN = 0x0201
  WM_LBUTTONUP = 0x0202
  WM_LBUTTONDBLCLK = 0x0203
  WM_RBUTTONDOWN = 0x0204
  WM_RBUTTONUP = 0x0205
  WM_CONTEXTMENU = 0x007B
  NIN_SELECT = 0x0400
  NIN_KEYSELECT = 0x0401
  NIN_BALLOONUSERCLICK = 0x0405
  IDI_APPLICATION = 32512
  ICON_ID = 1

  class << self
    def supported?
      true
    end

    def show(hwnd = 0)
      if defined?(EltenWindow) && !EltenWindow.window_thread?
        return EltenWindow.post_window_action(true) { show(hwnd) }
      end
      hwnd = hwnd.to_i
      hwnd = @hwnd.to_i if hwnd == 0 && @hwnd.to_i != 0
      hwnd = $wnd.to_i if hwnd == 0 && $wnd != nil
      return 0 if hwnd == 0
      ensure_api
      @hwnd = hwnd
      @nid = notify_icon_data(hwnd)
      result = @shell_notify_icon.call(@visible == true ? NIM_MODIFY : NIM_ADD, @nid)
      if result == 0 && @visible == true
        result = @shell_notify_icon.call(NIM_ADD, @nid)
      end
      @visible = result != 0
      result
    end

    def hide
      if defined?(EltenWindow) && !EltenWindow.window_thread?
        return EltenWindow.post_window_action(true) { hide }
      end
      return 1 if @visible != true || @nid == nil
      ensure_api
      result = @shell_notify_icon.call(NIM_DELETE, @nid)
      @visible = false if result != 0
      result
    end

    def restore_hotkey_pressed?
      return false if defined?(EltenWindow) && EltenWindow.restore_hotkey_registered?
      ensure_api
      pressed = key_down?(0x11) && key_down?(0x12) && key_down?(0x10) && key_down?(0x54)
      triggered = pressed && @restore_hotkey_down != true
      @restore_hotkey_down = pressed
      request_restore("hotkey CTRL+ALT+SHIFT+T") if triggered
      triggered
    rescue Exception
      false
    end

    def request_restore(source = nil)
      $trayreturn_source = source.to_s if source != nil
      $trayreturn = true if defined?($trayreturn) || defined?($scene)
      true
    end

    def handle_callback(wparam, lparam)
      event = lparam.to_i & 0xffff
      icon_id = (lparam.to_i >> 16) & 0xffff
      return false if wparam.to_i != ICON_ID && icon_id != ICON_ID
      request_restore("tray icon #{event_name(event)}") if restore_event?(event)
      true
    end

    private

    def ensure_api
      return if @shell_notify_icon != nil
      shell32 = Fiddle.dlopen("shell32")
      user32 = Fiddle.dlopen("user32")
      @shell_notify_icon = Fiddle::Function.new(shell32["Shell_NotifyIconW"], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @load_icon = Fiddle::Function.new(user32["LoadIconW"], [INTPTR, INTPTR], INTPTR)
      @get_async_key_state = Fiddle::Function.new(user32["GetAsyncKeyState"], [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT)
    end

    def key_down?(key)
      (@get_async_key_state.call(key) & 0x8000) != 0
    end

    def restore_event?(event)
      event == WM_LBUTTONDOWN ||
        event == WM_LBUTTONUP ||
        event == WM_LBUTTONDBLCLK ||
        event == WM_RBUTTONDOWN ||
        event == WM_RBUTTONUP ||
        event == WM_CONTEXTMENU ||
        event == NIN_SELECT ||
        event == NIN_KEYSELECT ||
        event == NIN_BALLOONUSERCLICK
    end

    def event_name(event)
      case event
      when WM_LBUTTONDOWN
        "left button down"
      when WM_LBUTTONUP
        "left button up"
      when WM_LBUTTONDBLCLK
        "left double click"
      when WM_RBUTTONDOWN
        "right button down"
      when WM_RBUTTONUP
        "right button up"
      when WM_CONTEXTMENU
        "context menu"
      when NIN_SELECT
        "select"
      when NIN_KEYSELECT
        "keyboard select"
      when NIN_BALLOONUSERCLICK
        "balloon click"
      else
        "event #{event}"
      end
    end

    def notify_icon_data(hwnd)
      buffer = "\0" * (EltenWin32::POINTER_SIZE == 8 ? 976 : 956)
      if EltenWin32::POINTER_SIZE == 8
        hwnd_offset = 8
        icon_offset = 32
        tip_offset = 40
      else
        hwnd_offset = 4
        icon_offset = 20
        tip_offset = 24
      end
      EltenWin32.set_dword(buffer, 0, buffer.bytesize)
      EltenWin32.set_pointer(buffer, hwnd_offset, hwnd)
      EltenWin32.set_dword(buffer, hwnd_offset + EltenWin32::POINTER_SIZE, ICON_ID)
      EltenWin32.set_dword(buffer, hwnd_offset + EltenWin32::POINTER_SIZE + 4, NIF_MESSAGE | NIF_ICON | NIF_TIP)
      EltenWin32.set_dword(buffer, hwnd_offset + EltenWin32::POINTER_SIZE + 8, CALLBACK_MESSAGE)
      EltenWin32.set_pointer(buffer, icon_offset, @load_icon.call(0, IDI_APPLICATION))
      write_wide_fixed(buffer, tip_offset, 128, "Elten")
      buffer
    end

    def write_wide_fixed(buffer, offset, max_chars, text)
      raw = text.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace).b
      raw = raw.byteslice(0, (max_chars - 1) * 2) || ""
      raw = (raw.b + "\0\0".b).b
      buffer[offset, max_chars * 2] = raw.ljust(max_chars * 2, "\0")
    end
  end
end

class Bitmap
  attr_reader :filename

  def initialize(filename = nil, height = nil)
    @filename = filename
    @height = height
  end

  def dispose
    true
  end
end

class Sprite
  attr_accessor :bitmap, :x, :y, :z, :visible, :opacity

  def initialize(viewport = nil)
    @viewport = viewport
    @visible = true
    @opacity = 255
    @x = 0
    @y = 0
    @z = 0
  end

  def dispose
    @bitmap = nil
    true
  end
end

module Kernel
  def load_data(filename)
    File.open(filename, "rb") { |file| Marshal.load(file) }
  end
  private :load_data

  def save_data(object, filename)
    File.open(filename, "wb") { |file| Marshal.dump(object, file) }
    true
  end
  private :save_data
end

begin
  if $elten_start_hidden == true && $wnd != nil && $wnd != 0
    EltenTray.show($wnd) if defined?(EltenTray)
  end
rescue Exception
end
