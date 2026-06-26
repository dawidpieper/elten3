# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
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
      initialize_state
      now = monotonic_time
      refresh_repeat_settings(now)
      state = keyboard_state
      events = key_events
      event_flags = apply_key_events_to_state(state, events, now)
      flags = Array.new(256, 0)
      (0..255).each do |key|
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
      (0..255).each do |key|
        flags[key] |= event_flags[key]
      end
      @flags_state = state.byteslice(0, 256).to_s.dup
      (0..255).each do |key|
        buffer.setbyte(key, flags[key]) if buffer.respond_to?(:setbyte)
      end
      0
    end

    def sync_physical_state
      initialize_state
      state = keyboard_state
      now = monotonic_time
      (0..255).each do |key|
        down = key_down?(state, key)
        @event_down[key] = down
        @last_down[key] = down
        @last_down_event[key] = down ? now : nil
        @stale_suppressed[key] = false
        @next_repeat[key] = 0.0
      end
      true
    end

    def clear_state
      initialize_state
      @last_down = Array.new(256, false)
      @event_down = Array.new(256, false)
      @next_repeat = Array.new(256, 0.0)
      @last_down_event = Array.new(256)
      @stale_suppressed = Array.new(256, false)
      true
    end

    def raw_state
      keyboard_state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
    rescue Exception
      "\0" * 256
    end

    def flags_state
      initialize_state
      @flags_state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
    rescue Exception
      "\0" * 256
    end

    def active_pressed_keys
      return Array.new(256, false) if !EltenWindow.keyboard_active?
      state = raw_state
      keys = Array.new(256, false)
      (0..255).each do |key|
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
      @stale_suppressed ||= Array.new(256, false)
      @stale_suppressed[key.to_i & 0xff] == true
    rescue Exception
      false
    end

    def async_key_down?(key)
      (GET_ASYNC_KEY_STATE.call(key.to_i & 0xff).to_i & 0x8000) != 0
    rescue Exception
      false
    end

    private

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
      (0..255).each do |key|
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
  GET_MODULE_HANDLE = Fiddle::Function.new(KERNEL32["GetModuleHandleW"], [PTR], HANDLE, ABI)
  CREATE_WINDOW_EX = Fiddle::Function.new(USER32["CreateWindowExW"], [INT, PTR, PTR, INT, INT, INT, INT, INT, HANDLE, HANDLE, HANDLE, PTR], HANDLE, ABI)
  SET_MENU = Fiddle::Function.new(USER32["SetMenu"], [HANDLE, HANDLE], INT, ABI)
  SHOW_WINDOW = Fiddle::Function.new(USER32["ShowWindow"], [HANDLE, INT], INT, ABI)
  PEEK_MESSAGE = Fiddle::Function.new(USER32["PeekMessageW"], [PTR, HANDLE, INT, INT, INT], INT, ABI)
  TRANSLATE_MESSAGE = Fiddle::Function.new(USER32["TranslateMessage"], [PTR], INT, ABI)
  DISPATCH_MESSAGE = Fiddle::Function.new(USER32["DispatchMessageW"], [PTR], HANDLE, ABI)
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
  WINDOW_CLASS = "STATIC"
  WINDOW_TITLE = "Elten"
  WS_CAPTION = 0x00C00000
  WS_SYSMENU = 0x00080000
  WS_MINIMIZEBOX = 0x00020000
  WINDOW_STYLE = WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
  CW_USEDEFAULT = -2147483648
  PM_REMOVE = 0x0001
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
  VK_F4 = 0x73
  UNICODE_NOCHAR = 0xFFFF
  SIZE_MINIMIZED = 1
  GWL_STYLE = -16
  SC_KEYMENU = 0xF100
  SC_CLOSE = 0xF060
  SC_MINIMIZE = 0xF020
  KEYBOARD_ACTIVATION_MIN_DELAY = 0.05
  KEYBOARD_ACTIVATION_MAX_DELAY = 2.0
  MINIMIZE_RESTORE_SUPPRESS_TIME = 1.0
  MSG_SIZE = Fiddle::SIZEOF_VOIDP == 8 ? 48 : 28
  MESSAGE_OFFSET = Fiddle::SIZEOF_VOIDP
  WPARAM_OFFSET = Fiddle::SIZEOF_VOIDP == 8 ? 16 : 8
  LPARAM_OFFSET = Fiddle::SIZEOF_VOIDP == 8 ? 24 : 12

  class << self
    attr_reader :hwnd

    def ensure_window
      @window_thread ||= Thread.current
      return @hwnd if @hwnd != nil && @hwnd != 0
      if $wnd != nil && $wnd != 0
        @hwnd = $wnd
        ensure_window_style
        return @hwnd
      end

      title = wide_string(WINDOW_TITLE)
      klass = wide_string(WINDOW_CLASS)
      instance = GET_MODULE_HANDLE.call(nil)
      @hwnd = CREATE_WINDOW_EX.call(
        0,
        klass,
        title,
        WINDOW_STYLE,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        640,
        360,
        0,
        0,
        instance,
        nil
      )
      SET_MENU.call(@hwnd, 0) if @hwnd != nil && @hwnd != 0
      ensure_window_style if @hwnd != nil && @hwnd != 0
      show if @hwnd != nil && @hwnd != 0 && !($elten_start_hidden == true)
      @hwnd
    end

    def show(command = SW_SHOW)
      ensure_window
      show_window(@hwnd, command)
      @hwnd
    end

    def hide
      hide_window
    end

    def show_window(hwnd = nil, command = SW_SHOW)
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
      ensure_window
      return false if @hwnd == nil || @hwnd == 0
      suppress_minimize_requests
      show(SW_RESTORE)
      focus(@hwnd)
      clear_input_state
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
      return false if false
      EltenKeyboard.async_key_down?(key)
    rescue Exception
      false
    end

    def pump_messages
      msg = "\0" * MSG_SIZE
      while PEEK_MESSAGE.call(msg, 0, 0, 0, PM_REMOVE) != 0
        focus_message?(msg)
        next if activation_key_message?(msg)
        next if defined?(EltenTray) && EltenTray.handle_message?(msg)
        next if close_message?(msg)
        minimize_message?(msg)
        record_key_message(msg)
        next if character_message?(msg)
        next if menu_message?(msg)
        TRANSLATE_MESSAGE.call(msg)
        DISPATCH_MESSAGE.call(msg)
      end
      true
    end

    def activation_input_blocked?
      return false if @activation_ignore_max_until == nil
      now = monotonic_time
      state = capture_keyboard_state_raw
      if now <= @activation_ignore_min_until.to_f || (now <= @activation_ignore_max_until.to_f && keyboard_state_has_pressed_keys?(state))
        sync_keyboard_state_without_delivery(state)
        clear_character_queue
        return true
      end
      finish_activation_ignore(state)
      false
    rescue Exception
      clear_activation_guard
      false
    end

    def close_requested?
      @close_requested == true
    end

    def consume_close_request
      requested = @close_requested == true
      @close_requested = false
      requested
    end

    def consume_minimize_request
      if minimize_request_suppressed?
        @minimize_requested = false
        return false
      end
      requested = @minimize_requested == true
      @minimize_requested = false
      requested
    end

    def update_messages
      if window_thread?
        pump_messages
        capture_keyboard_state
      else
        request_window_update
      end
      true
    end

    def service_window_update
      return false if !window_thread?
      pump_sync
      token = nil
      should_update = false
      @pump_mutex.synchronize do
        token = @pump_request.to_i
        should_update = @pump_done.to_i < token || (@window_actions != nil && @window_actions.empty? == false)
      end
      return false if should_update == false
      run_window_actions
      pump_messages
      capture_keyboard_state
      run_window_actions
      @pump_mutex.synchronize do
        @pump_done = token
        @pump_cond.broadcast
      end
      true
    end

    def keyboard_state
      @keyboard_state ||= ("\0" * 256)
    end

    def clear_input_state
      clear_activation_guard
      if !window_thread?
        @keyboard_state = "\0" * 256
        post_window_action(true) { clear_input_state }
        EltenKeyboard.clear_state
        return true
      end
      clear_native_keyboard_state
      @keyboard_state = "\0" * 256
      @character_queue ||= []
      @character_queue.clear
      @character_delivered = false
      @high_surrogate = nil
      clear_key_events
      EltenKeyboard.clear_state
      true
    end

    def post_window_action(wait = false, &block)
      return false if block == nil
      return block.call if window_thread?
      pump_sync
      action = { :block => block, :done => false, :result => nil, :error => nil }
      @pump_mutex.synchronize do
        @window_actions ||= []
        @window_actions << action
        @pump_request += 1
        @pump_cond.broadcast
        if wait
          deadline = Time.now.to_f + 1.0
          while action[:done] != true
            remaining = deadline - Time.now.to_f
            break if remaining <= 0
            @pump_cond.wait(@pump_mutex, remaining)
          end
          raise action[:error] if action[:error] != nil
          return action[:result]
        end
      end
      true
    end

    def window_thread?
      @window_thread ||= (($mainthread != nil) ? $mainthread : Thread.current)
      Thread.current == @window_thread
    end

    def begin_input_frame
      @character_queue ||= []
      @character_queue.clear
      @character_delivered = false
      @input_frame = (@input_frame || 0) + 1
      update_focus_state
      clear_character_queue if activation_input_blocked?
      true
    end

    def keyboard_flags_driven?
      true
    end

    def character_input_supported?
      true
    end

    def keyboard_event_driven?
      false
    end

    def keyboard_pressed_implies_held?
      true
    end

    def take_character(multi = false)
      @character_queue ||= []
      return "" if @character_queue.empty?
      @character_delivered = true
      if multi
        text = @character_queue.join
        @character_queue.clear
        text
      else
        @character_queue.shift.to_s
      end
    end

    def consume_key_events
      @key_event_queue ||= []
      events = @key_event_queue
      @key_event_queue = []
      events
    end

    private

    def request_window_update(timeout = 0.05)
      pump_sync
      token = nil
      @pump_mutex.synchronize do
        @pump_request += 1
        token = @pump_request
        @pump_cond.broadcast
        deadline = Time.now.to_f + timeout.to_f
        while @pump_done.to_i < token
          remaining = deadline - Time.now.to_f
          break if remaining <= 0
          @pump_cond.wait(@pump_mutex, remaining)
        end
      end
      true
    rescue Exception
      true
    end

    def pump_sync
      @pump_mutex ||= Mutex.new
      @pump_cond ||= ConditionVariable.new
      @pump_request ||= 0
      @pump_done ||= 0
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue Exception
      Time.now.to_f
    end

    def suppress_minimize_requests(duration = MINIMIZE_RESTORE_SUPPRESS_TIME)
      @minimize_requested = false
      @minimize_suppressed_until = monotonic_time + duration.to_f
      true
    rescue Exception
      false
    end

    def minimize_request_suppressed?
      return false if @minimize_suppressed_until == nil
      if monotonic_time < @minimize_suppressed_until.to_f
        true
      else
        @minimize_suppressed_until = nil
        false
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

    def update_focus_state(active = nil, state = nil)
      active = foreground_window_active? if active == nil
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
      active
    rescue Exception
      false
    end

    def ignore_activation_input
      now = monotonic_time
      @activation_ignore_min_until = now + KEYBOARD_ACTIVATION_MIN_DELAY
      @activation_ignore_max_until = now + KEYBOARD_ACTIVATION_MAX_DELAY
      clear_character_queue
      clear_key_events
      EltenKeyboard.clear_state
      true
    end

    def clear_activation_guard
      @activation_ignore_min_until = nil
      @activation_ignore_max_until = nil
      true
    end

    def finish_activation_ignore(state = nil)
      state ||= capture_keyboard_state_raw
      @keyboard_state = state
      EltenKeyboard.sync_physical_state
      clear_activation_guard
      clear_character_queue
      clear_key_events
      true
    end

    def sync_keyboard_state_without_delivery(state)
      @keyboard_state = state
      EltenKeyboard.sync_physical_state
      @keyboard_state = "\0" * 256
      clear_key_events
      true
    rescue Exception
      @keyboard_state = "\0" * 256
      false
    end

    def keyboard_state_has_pressed_keys?(state)
      state = state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
      (0...256).each do |key|
        return true if (state.getbyte(key).to_i & 0x80) != 0
      end
      false
    rescue Exception
      false
    end

    def clear_character_queue
      @character_queue ||= []
      @character_queue.clear
      @character_delivered = false
      @high_surrogate = nil
      true
    end

    def clear_key_events
      @key_event_queue ||= []
      @key_event_queue.clear
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

    def capture_keyboard_state
      state = capture_keyboard_state_raw
      @keyboard_state = state
      update_focus_state(foreground_window_active?, state)
      true
    rescue Exception
      @keyboard_state ||= ("\0" * 256)
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
      (0...256).each do |i|
        state.setbyte(i, state.getbyte(i).to_i & 1)
      end
      SET_KEYBOARD_STATE.call(state)
      true
    rescue Exception
      false
    end

    def character_message?(msg)
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      return false unless message == WM_CHAR || message == WM_DEADCHAR || message == WM_UNICHAR
      return true if activation_input_blocked?
      enqueue_character_message(message, EltenWin32.pointer_value(msg, WPARAM_OFFSET))
      true
    end

    def close_message?(msg)
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      if message == WM_CLOSE || message == WM_DESTROY || message == WM_QUIT
        @close_requested = true
        return true
      end
      if message == WM_SYSKEYDOWN && EltenWin32.pointer_value(msg, WPARAM_OFFSET).to_i == VK_F4
        return true if activation_input_blocked?
        @close_requested = true
        return true
      end
      return false unless message == WM_SYSCOMMAND
      command = EltenWin32.pointer_value(msg, WPARAM_OFFSET) & 0xfff0
      if command == SC_CLOSE
        @close_requested = true
        return true
      end
      false
    end

    def minimize_message?(msg)
      if minimize_request_suppressed?
        @minimize_requested = false
        return false
      end
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      if message == WM_SIZE
        @minimize_requested = true if EltenWin32.pointer_value(msg, WPARAM_OFFSET).to_i == SIZE_MINIMIZED
      elsif message == WM_SYSCOMMAND
        command = EltenWin32.pointer_value(msg, WPARAM_OFFSET) & 0xfff0
        @minimize_requested = true if command == SC_MINIMIZE
      end
      false
    rescue Exception
      false
    end

    def focus_message?(msg)
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      wparam = EltenWin32.pointer_value(msg, WPARAM_OFFSET).to_i
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

    def activation_key_message?(msg)
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      return false unless message == WM_KEYDOWN || message == WM_KEYUP || message == WM_SYSKEYDOWN || message == WM_SYSKEYUP || message == WM_SYSCHAR
      activation_input_blocked?
    rescue Exception
      false
    end

    def record_key_message(msg)
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      return false unless message == WM_KEYDOWN || message == WM_KEYUP || message == WM_SYSKEYDOWN || message == WM_SYSKEYUP
      key = EltenWin32.pointer_value(msg, WPARAM_OFFSET).to_i & 0xff
      return false if key <= 0 || key > 255
      down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN
      event = down && repeated_key_message?(msg) ? :repeat : down
      @key_event_queue ||= []
      @key_event_queue << [key, event]
      @key_event_queue.shift while @key_event_queue.size > 256
      false
    rescue Exception
      false
    end

    def repeated_key_message?(msg)
      (EltenWin32.pointer_value(msg, LPARAM_OFFSET).to_i & (1 << 30)) != 0
    rescue Exception
      false
    end

    def enqueue_character_message(message, wparam)
      code = wparam.to_i
      return if code == 0 || code == UNICODE_NOCHAR || code < 32 || (code >= 0x7F && code <= 0x9F)
      return if message == WM_DEADCHAR
      @character_queue ||= []
      if code >= 0xD800 && code <= 0xDBFF
        @high_surrogate = code
        return
      elsif code >= 0xDC00 && code <= 0xDFFF && @high_surrogate != nil
        @character_queue << [@high_surrogate, code].pack("S<S<").force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
        @high_surrogate = nil
      else
        @high_surrogate = nil
        @character_queue << [code].pack("U")
      end
    rescue Exception
      @high_surrogate = nil
    end

    def menu_message?(msg)
      message = EltenWin32.dword_value(msg, MESSAGE_OFFSET)
      return true if message == WM_SYSKEYDOWN || message == WM_SYSKEYUP || message == WM_SYSCHAR
      return false if message != WM_SYSCOMMAND
      (EltenWin32.pointer_value(msg, WPARAM_OFFSET) & 0xfff0) == SC_KEYMENU
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
  GWL_WNDPROC = -4

  class << self
    def supported?
      true
    end

    def show(hwnd = 0)
      hwnd = hwnd.to_i
      hwnd = @hwnd.to_i if hwnd == 0 && @hwnd.to_i != 0
      hwnd = $wnd.to_i if hwnd == 0 && $wnd != nil
      return 0 if hwnd == 0
      ensure_api
      @hwnd = hwnd
      install_window_proc(hwnd)
      @nid = notify_icon_data(hwnd)
      result = @shell_notify_icon.call(@visible == true ? NIM_MODIFY : NIM_ADD, @nid)
      if result == 0 && @visible == true
        result = @shell_notify_icon.call(NIM_ADD, @nid)
      end
      @visible = result != 0
      result
    end

    def hide
      return 1 if @visible != true || @nid == nil
      ensure_api
      result = @shell_notify_icon.call(NIM_DELETE, @nid)
      @visible = false if result != 0
      result
    end

    def handle_message?(msg)
      return false if EltenWin32.dword_value(msg, EltenWin32::POINTER_SIZE) != CALLBACK_MESSAGE
      wparam = EltenWin32.pointer_value(msg, EltenWin32::POINTER_SIZE == 8 ? 16 : 8)
      lparam = EltenWin32.pointer_value(msg, EltenWin32::POINTER_SIZE == 8 ? 24 : 12)
      handle_callback(wparam, lparam)
    end

    def restore_hotkey_pressed?
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
      @call_window_proc = Fiddle::Function.new(user32["CallWindowProcW"], [INTPTR, INTPTR, Fiddle::TYPE_INT, INTPTR, INTPTR], INTPTR)
      @def_window_proc = Fiddle::Function.new(user32["DefWindowProcW"], [INTPTR, Fiddle::TYPE_INT, INTPTR, INTPTR], INTPTR)
      @set_window_long_ptr = begin
        Fiddle::Function.new(user32["SetWindowLongPtrW"], [INTPTR, Fiddle::TYPE_INT, INTPTR], INTPTR)
      rescue Fiddle::DLError
        Fiddle::Function.new(user32["SetWindowLongW"], [INTPTR, Fiddle::TYPE_INT, INTPTR], INTPTR)
      end
    end

    def key_down?(key)
      (@get_async_key_state.call(key) & 0x8000) != 0
    end

    def install_window_proc(hwnd)
      return if hwnd.to_i == 0
      return if @subclassed_hwnd.to_i == hwnd.to_i
      @wndproc ||= Fiddle::Closure::BlockCaller.new(
        INTPTR,
        [INTPTR, Fiddle::TYPE_INT, INTPTR, INTPTR]
      ) do |window, message, wparam, lparam|
        begin
          if message.to_i == CALLBACK_MESSAGE && handle_callback(wparam.to_i, lparam.to_i)
            0
          else
            call_previous_window_proc(window, message, wparam, lparam)
          end
        rescue Exception
          call_previous_window_proc(window, message, wparam, lparam) rescue 0
        end
      end
      previous = @set_window_long_ptr.call(hwnd, GWL_WNDPROC, @wndproc.to_i)
      @previous_window_proc = previous if previous != nil && previous.to_i != 0
      @subclassed_hwnd = hwnd
    rescue Exception => e
      Log.warning("Tray window subclass failed: #{e}")
    end

    def call_previous_window_proc(window, message, wparam, lparam)
      if @previous_window_proc != nil && @previous_window_proc.to_i != 0
        @call_window_proc.call(@previous_window_proc, window, message, wparam, lparam)
      else
        @def_window_proc.call(window, message, wparam, lparam)
      end
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

module Input
  LEFT = 0x25
  UP = 0x26
  RIGHT = 0x27
  DOWN = 0x28
  A = 0x10
  B = 0x1B
  C = 0x0D
  CTRL = 0x11

  class << self
    def update
      true
    end

    def trigger?(key)
      defined?(EltenAPI::KeyboardState) && EltenAPI::KeyboardState.pressed?(key)
    end

    def repeat?(key)
      return true if EltenWindow.keyboard_key_held?(key)
      defined?(EltenAPI::KeyboardState) && EltenAPI::KeyboardState.held?(key)
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
