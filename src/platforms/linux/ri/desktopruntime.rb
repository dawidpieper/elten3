# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module LinuxWindowNative
  PTR_SIZE = Fiddle::SIZEOF_VOIDP

  # SDL scancode -> Windows VK. Letters/digits/F-keys/keypad are filled in build_scancode_map.
  SCANCODE_TO_VK = {
    40 => 0x0D, 41 => 0x1B, 42 => 0x08, 43 => 0x09, 44 => 0x20,
    45 => 0xBD, 46 => 0xBB, 47 => 0xDB, 48 => 0xDD, 49 => 0xDC,
    51 => 0xBA, 52 => 0xDE, 53 => 0xC0, 54 => 0xBC, 55 => 0xBE, 56 => 0xBF,
    57 => 0x14, 71 => 0x91, 72 => 0x13,
    73 => 0x2D, 74 => 0x24, 75 => 0x21, 76 => 0x2E, 77 => 0x23, 78 => 0x22,
    79 => 0x27, 80 => 0x25, 81 => 0x28, 82 => 0x26, 83 => 0x90,
    84 => 0x6F, 85 => 0x6A, 86 => 0x6D, 87 => 0x6B, 88 => 0x0D, 99 => 0x6E,
    101 => 0x5D,
    # NB: SDL scancode 230 (right Alt / AltGr) is deliberately NOT mapped. On a
    # PL/EU layout AltGr is the level-3 shift used to type accented characters, so
    # it must act purely as a character composer, never as VK_MENU (0x12). Were it
    # 0x12 it would open the menu and block translate_virtual_key (which drops any
    # character while Alt is down); the composed character instead arrives via the
    # SDL_TEXTINPUT event. This mirrors osx, which keeps right Option out of 0x12.
    224 => 0x11, 225 => 0x10, 226 => 0x12, 227 => 0x5B,
    228 => 0x11, 229 => 0x10, 231 => 0x5C
  }

  # Virtual keys that can produce an inserted character; only these get a
  # translated character attached from SDL_TEXTINPUT (mirrors osx TEXT_VIRTUAL_KEYS).
  TEXT_VIRTUAL_KEYS = [0x20, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE]

  class << self
    def available?
      SDL2.available?
    rescue Exception
      false
    end

    def create(title, hidden = false)
      unless available?
        Log.warning("SDL window: SDL2 unavailable") if defined?(Log)
        return 0
      end
      ensure_initialized
      flags = hidden ? SDL2::SDL_WINDOW_HIDDEN : 0
      window = SDL2::SDL_CreateWindow.call(
        SDL2.cstring(title.to_s),
        SDL2::SDL_WINDOWPOS_UNDEFINED, SDL2::SDL_WINDOWPOS_UNDEFINED,
        480, 320, flags
      )
      @window = window.to_i
      Log.warning("SDL_CreateWindow failed: #{SDL2.last_error}") if @window == 0 && defined?(Log)
      SDL2::SDL_StartTextInput.call if @window != 0
      @window
    rescue Exception => e
      Log.warning("SDL window create raised: #{e.class}: #{e.message}") if defined?(Log)
      0
    end

    def show(hwnd)
      SDL2::SDL_ShowWindow.call(pointer(hwnd))
      SDL2::SDL_RaiseWindow.call(pointer(hwnd))
      true
    rescue Exception
      false
    end

    def hide(hwnd)
      SDL2::SDL_HideWindow.call(pointer(hwnd))
      true
    rescue Exception
      false
    end

    # Shows a modal dialog and returns a Windows MessageBox-style id (IDOK=1,
    # IDCANCEL=2, IDABORT=3, IDRETRY=4, IDIGNORE=5, IDYES=6, IDNO=7) so the shared
    # callers (loading.rb, ui/loop.rb) keep working unchanged.
    #
    # We prefer zenity: it draws a real GTK dialog that AT-SPI/Orca can read, which
    # the built-in SDL message box (custom-drawn X11 window) cannot. SDL is only the
    # fallback when no desktop helper is present; it shows a single OK button, so it
    # returns the dialog's safe/closing choice (the last Windows button).
    def message_box(text, caption = "Elten", flags = 0)
      flags = flags.to_i
      buttons = button_set(flags)
      cancel_id = buttons.last[1]
      kind = dialog_kind(flags)
      result = zenity_message_box(text.to_s, caption.to_s, buttons, kind)
      return result if result != nil
      sdl_message_box(text.to_s, caption.to_s, kind, cancel_id)
    rescue Exception
      buttons ? buttons.last[1] : 0
    end

    def visible?(hwnd)
      flags = SDL2::SDL_GetWindowFlags.call(pointer(hwnd)).to_i
      (flags & SDL2::SDL_WINDOW_HIDDEN) == 0 && (flags & SDL2::SDL_WINDOW_MINIMIZED) == 0
    rescue Exception
      true
    end

    def keyboard_active?(hwnd)
      flags = SDL2::SDL_GetWindowFlags.call(pointer(hwnd)).to_i
      (flags & SDL2::SDL_WINDOW_INPUT_FOCUS) != 0
    rescue Exception
      false
    end

    def pump
      return false unless available?
      SDL2::SDL_PumpEvents.call
      buffer = event_buffer
      while SDL2::SDL_PollEvent.call(buffer).to_i != 0
        handle_event(buffer)
      end
      true
    rescue Exception
      false
    end

    def keyboard_state
      (@kbstate ||= ("\0" * 256).b).dup
    rescue Exception
      "\0" * 256
    end

    def consume_key_events
      events = @key_events || []
      @key_events = []
      events
    rescue Exception
      []
    end

    def consume_close_request
      requested = @close_requested == true
      @close_requested = false
      requested
    end

    def consume_quit_shortcut_request
      false
    end

    def consume_minimize_request
      requested = @minimize_requested == true
      @minimize_requested = false
      requested
    end

    def translated_character_for_key(key)
      (@translated_chars ||= {})[key.to_i & 0xff].to_s
    rescue Exception
      ""
    end

    # Characters composed by SDL - including AltGr and IME results - are queued in
    # typing order and drained here. The per-virtual-key map above cannot do that
    # job: it is keyed by the key rather than by the keystroke, so it keeps only
    # the last character typed for a given key and carries no order at all.
    def take_character(multi = false)
      @char_queue ||= []
      @char_frame_consumed = true
      return "" if @char_queue.empty?
      return @char_queue.shift.to_s if multi != true
      text = @char_queue.join
      @char_queue = []
      text
    rescue Exception
      ""
    end

    # Called once per input frame. Characters that nobody read for a whole frame
    # are dropped, so keystrokes made outside an edit control cannot pile up and
    # then flood the next one that opens.
    def begin_character_frame
      @char_queue ||= []
      @char_queue.shift(@char_frame_prefix.to_i) if @char_frame_consumed != true
      @char_frame_prefix = @char_queue.size
      @char_frame_consumed = false
      true
    rescue Exception
      true
    end

    def clear_character_queue
      @char_queue = []
      @char_frame_prefix = 0
      @char_frame_consumed = false
      true
    end

    private

    def ensure_initialized
      return true if @initialized == true
      SDL2::SDL_Init.call(SDL2::SDL_INIT_VIDEO | SDL2::SDL_INIT_EVENTS)
      @kbstate = ("\0" * 256).b
      @key_events = []
      @translated_chars = {}
      @last_text_vk = nil
      @initialized = true
    rescue Exception
      false
    end

    def event_buffer
      @event_buffer ||= Fiddle::Pointer.malloc(SDL2::EVENT_SIZE)
    end

    def handle_event(buffer)
      type = read_u32(buffer, 0)
      case type
      when SDL2::SDL_KEYDOWN
        scancode = read_s32(buffer, 16)
        repeat = read_u8(buffer, 13)
        vk = scancode_to_vk(scancode)
        return if vk == nil
        # The composed character (incl. AltGr / dead-key results) arrives in the
        # FOLLOWING SDL_TEXTINPUT event, which carries no scancode. Remember the VK
        # that opened this keystroke so we can attach the text to it, and drop any
        # stale character for this VK (TEXTINPUT will repopulate it if one is due).
        @last_text_vk = text_virtual_key?(vk) ? vk : nil
        (@translated_chars ||= {}).delete(vk)
        set_key(vk, true)
        queue_key_event(vk, repeat.to_i != 0 ? :repeat : true)
      when SDL2::SDL_KEYUP
        scancode = read_s32(buffer, 16)
        vk = scancode_to_vk(scancode)
        return if vk == nil
        (@translated_chars ||= {}).delete(vk)
        set_key(vk, false)
        queue_key_event(vk, false)
      when SDL2::SDL_TEXTINPUT
        store_text_input(read_event_text(buffer, 12, 32))
      when SDL2::SDL_WINDOWEVENT
        handle_window_event(read_u8(buffer, 12))
      when SDL2::SDL_QUIT
        @close_requested = true
      end
    rescue Exception
    end

    def handle_window_event(event_id)
      case event_id
      when SDL2::SDL_WINDOWEVENT_FOCUS_LOST
        # Also our only cure for a modifier whose KEYUP never arrived, which
        # happens when the window manager grabs a shortcut (Ctrl+Alt+something,
        # VT switching) - focus is normally lost in exactly those cases, so it
        # covers them in practice. macOS instead asks the hardware whether the
        # modifier is really still down (reconcile_option_control_state); the
        # equivalent here would be SDL_GetKeyboardState, which is not bound in
        # sdl2.rb yet. Symptom to watch for: Ctrl or Alt behaving as if held -
        # characters stop reaching edit fields, or shortcuts fire on their own.
        clear_keyboard_state
      when SDL2::SDL_WINDOWEVENT_MINIMIZED
        @minimize_requested = true
      when SDL2::SDL_WINDOWEVENT_CLOSE
        @close_requested = true
      end
    rescue Exception
    end

    def scancode_to_vk(scancode)
      build_scancode_map[scancode.to_i]
    end

    def build_scancode_map
      @scancode_map ||= begin
        map = SCANCODE_TO_VK.dup
        (0..25).each { |i| map[4 + i] = 0x41 + i } # A-Z
        (1..9).each { |i| map[29 + i] = 0x30 + i } # 1-9
        map[39] = 0x30 # 0
        (0..11).each { |i| map[58 + i] = 0x70 + i } # F1-F12
        map[97] = 0x60 # keypad 0  (SDL kp_0 = 98) handled below
        (0..8).each { |i| map[89 + i] = 0x61 + i } # keypad 1-9
        map[98] = 0x60 # keypad 0
        map
      end
    end

    def set_key(vk, down)
      @kbstate ||= ("\0" * 256).b
      byte = @kbstate.getbyte(vk).to_i
      @kbstate.setbyte(vk, down ? (byte | 0x80) : (byte & 0x7f))
    rescue Exception
    end

    def queue_key_event(vk, state)
      @key_events ||= []
      @key_events << [vk, state]
    end

    def clear_keyboard_state
      @kbstate = ("\0" * 256).b
      @key_events = []
      @translated_chars = {}
      @last_text_vk = nil
      clear_character_queue
    end

    def text_virtual_key?(key)
      key = key.to_i
      return true if key >= 0x30 && key <= 0x5A
      TEXT_VIRTUAL_KEYS.include?(key)
    end

    def store_text_input(text)
      text = sanitize_text(text)
      queue_characters(text)
      return if @last_text_vk == nil
      @translated_chars ||= {}
      if text == ""
        @translated_chars.delete(@last_text_vk)
      else
        @translated_chars[@last_text_vk] = text
      end
    rescue Exception
    end

    def queue_characters(text)
      return if text == ""
      @char_queue ||= []
      text.each_char { |char| @char_queue << char }
    rescue Exception
    end

    # Drop control characters; keep printable Unicode (letters, AltGr results).
    def sanitize_text(text)
      text.to_s.each_char.select do |char|
        code = char.ord
        code >= 32 && !(code >= 0x7f && code <= 0x9f)
      end.join
    rescue Exception
      ""
    end

    def read_event_text(buffer, offset, max)
      bytes = buffer[offset, max].to_s
      nul = bytes.index("\x00")
      bytes = bytes[0, nul] if nul
      bytes.force_encoding(Encoding::UTF_8)
    rescue Exception
      ""
    end

    def pointer(hwnd)
      Fiddle::Pointer.new(hwnd.to_i)
    end

    def read_u32(buffer, offset)
      buffer[offset, 4].unpack("L").first
    end

    def read_s32(buffer, offset)
      buffer[offset, 4].unpack("l").first
    end

    def read_u8(buffer, offset)
      buffer[offset, 1].unpack("C").first
    end

    # Maps the low nibble of the Windows MB_* flags to an ordered button list of
    # [label, id]. The FIRST entry is the affirmative/default button (OK on close
    # via zenity exit 0); the LAST entry is the cancel/close target.
    def button_set(flags)
      case flags.to_i & 0x0F
      when 1 then [["OK", 1], ["Cancel", 2]]                  # MB_OKCANCEL
      when 2 then [["Abort", 3], ["Retry", 4], ["Ignore", 5]] # MB_ABORTRETRYIGNORE
      when 3 then [["Yes", 6], ["No", 7], ["Cancel", 2]]      # MB_YESNOCANCEL
      when 4 then [["Yes", 6], ["No", 7]]                     # MB_YESNO
      when 5 then [["Retry", 4], ["Cancel", 2]]               # MB_RETRYCANCEL
      else [["OK", 1]]                                        # MB_OK
      end
    end

    # Maps the icon nibble of the Windows MB_* flags to a zenity dialog kind.
    def dialog_kind(flags)
      case flags.to_i & 0xF0
      when 0x10 then "error"
      when 0x30 then "warning"
      when 0x20 then "question"
      else "info"
      end
    end

    def zenity_message_box(text, caption, buttons, kind)
      return nil unless command_available?("zenity")
      if buttons.size <= 1
        single = kind == "question" ? "info" : kind
        result = run_dialog(["zenity", "--#{single}", "--title=#{caption}", "--text=#{text}", "--no-wrap"])
        return nil if result == nil
        return buttons.first[1]
      end
      ok_label, ok_id = buttons.first
      cancel_label, cancel_button_id = buttons.last
      extras = buttons[1..-2] || []
      argv = ["zenity", "--question", "--title=#{caption}", "--text=#{text}", "--no-wrap",
              "--ok-label=#{ok_label}", "--cancel-label=#{cancel_label}"]
      extras.each { |label, _id| argv << "--extra-button=#{label}" }
      result = run_dialog(argv)
      return nil if result == nil
      out, status = result
      return ok_id if status == 0
      pressed = out.to_s.strip
      extras.each { |label, id| return id if label == pressed }
      cancel_button_id
    end

    def sdl_message_box(text, caption, kind, cancel_id)
      return cancel_id unless available?
      flag = case kind
             when "error" then SDL2::SDL_MESSAGEBOX_ERROR
             when "warning" then SDL2::SDL_MESSAGEBOX_WARNING
             else SDL2::SDL_MESSAGEBOX_INFORMATION
             end
      SDL2::SDL_ShowSimpleMessageBox.call(flag, SDL2.cstring(caption.to_s), SDL2.cstring(text.to_s), pointer(@window))
      cancel_id
    rescue Exception
      cancel_id
    end

    # Runs a dialog helper to completion (blocking — the dialog is modal) and
    # returns [stdout, exit_status], or nil if the helper is missing or failed.
    def run_dialog(argv)
      require "open3"
      out, status = Open3.capture2(*argv)
      [out.to_s, status.exitstatus.to_i]
    rescue Exception
      nil
    end

    def command_available?(command)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
        next false if dir.to_s == ""
        path = File.join(dir, command)
        File.file?(path) && File.executable?(path)
      end
    rescue Exception
      false
    end
  end
end

module EltenKeyboard
  VK_SHIFT = 0x10
  VK_CONTROL = 0x11
  VK_MENU = 0x12

  CHAR_BY_VK = {
    0x20 => [" ", " "], 0x30 => ["0", ")"], 0x31 => ["1", "!"], 0x32 => ["2", "@"],
    0x33 => ["3", "#"], 0x34 => ["4", "$"], 0x35 => ["5", "%"], 0x36 => ["6", "^"],
    0x37 => ["7", "&"], 0x38 => ["8", "*"], 0x39 => ["9", "("], 0xBA => [";", ":"],
    0xBB => ["=", "+"], 0xBC => [",", "<"], 0xBD => ["-", "_"], 0xBE => [".", ">"],
    0xBF => ["/", "?"], 0xC0 => ["`", "~"], 0xDB => ["[", "{"], 0xDC => ["\\", "|"],
    0xDD => ["]", "}"], 0xDE => ["'", "\""]
  }

  class << self
    def clear_state
      true
    end

    def raw_state
      keyboard_state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
    rescue Exception
      "\0" * 256
    end

    def active_pressed_keys
      state = raw_state
      keys = Array.new(256, false)
      for key in 0..255
        keys[key] = key_down?(state, key)
      end
      keys
    rescue Exception
      Array.new(256, false)
    end

    def translate_virtual_key(key, state = nil, _flags = 4)
      key = key.to_i
      state = normalize_keyboard_state(state)
      return "" if key_down?(state, VK_CONTROL) || key_down?(state, VK_MENU)
      native = translated_character_for_key(key)
      return native if native != ""
      shift = key_down?(state, VK_SHIFT)
      if key >= 0x41 && key <= 0x5A
        char = key.chr
        return shift ? char : char.downcase
      end
      chars = CHAR_BY_VK[key]
      chars ? chars[shift ? 1 : 0] : ""
    rescue Exception
      ""
    end

    private

    def keyboard_state
      return EltenWindow.keyboard_state.to_s
    rescue Exception
      "\0" * 256
    end

    def key_down?(state, key)
      (state.to_s.getbyte(key.to_i).to_i & 0x80) != 0
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

    def translated_character_for_key(key)
      return LinuxWindowNative.translated_character_for_key(key) if defined?(LinuxWindowNative) && LinuxWindowNative.respond_to?(:translated_character_for_key)
      ""
    rescue Exception
      ""
    end

  end
end

module EltenWindow
  SW_HIDE = 0
  SW_SHOW = 5
  SW_RESTORE = 9

  class << self
    attr_reader :hwnd

    def app_window_title
      defined?(Elten) && Elten.respond_to?(:window_title) ? Elten.window_title : "Elten"
    end

    def ensure_window
      if @window_created != true
        @window_created = true
        hidden = $elten_start_hidden == true
        native = LinuxWindowNative.create(app_window_title, hidden)
        @native_window = native.to_i != 0
        @hwnd = @native_window ? native.to_i : 1
        @visible = !hidden
      end
      $wnd = @hwnd
      @hwnd
    end

    def show(_command = SW_SHOW)
      ensure_window
      LinuxWindowNative.show(@hwnd) if @native_window == true
      @visible = true
      @minimized = false
      clear_input_state
      true
    end

    def hide
      hide_window
    end

    def show_window(_hwnd = nil, command = SW_SHOW)
      command.to_i == SW_HIDE ? hide_window : show(command)
    end

    def hide_window(_hwnd = nil)
      ensure_window
      LinuxWindowNative.hide(@hwnd) if @native_window == true
      @visible = false
      true
    end

    def focus(_hwnd = nil)
      show
      true
    end

    def message_box(text, caption = "Elten", flags = 0, _owner = nil)
      ensure_window
      LinuxWindowNative.message_box(text, caption, flags.to_i)
    rescue Exception
      0
    end

    def foreground_window
      keyboard_active? ? ensure_window : 0
    end

    def active_or_child?(_hwnd = nil)
      keyboard_active?
    end

    def minimized?
      return @minimized == true if @native_window != true
      !LinuxWindowNative.visible?(@hwnd)
    end

    def tray_supported?
      false
    end

    def hide_to_tray
      return false unless tray_supported?
      ensure_window
      hide_window
      clear_input_state
      true
    end

    def restore_from_tray
      show(SW_RESTORE)
      true
    end

    def keyboard_active?
      ensure_window
      return false if @visible == false
      return LinuxWindowNative.keyboard_active?(@hwnd) if @native_window == true
      false
    end

    def pump_messages
      if @native_window == true
        LinuxWindowNative.pump
      else
        @keyboard_state = "\0" * 256
      end
      true
    end

    def activation_input_blocked?
      false
    end

    def close_requested?
      @close_requested == true
    end

    def consume_close_request
      requested = @close_requested == true
      @close_requested = false
      native_requested = @native_window == true && defined?(LinuxWindowNative) && LinuxWindowNative.respond_to?(:consume_close_request) && LinuxWindowNative.consume_close_request
      requested || native_requested
    end

    def consume_quit_shortcut_request
      return false unless @native_window == true && defined?(LinuxWindowNative) && LinuxWindowNative.respond_to?(:consume_quit_shortcut_request)
      LinuxWindowNative.consume_quit_shortcut_request
    rescue Exception
      false
    end

    def consume_minimize_request
      requested = @minimize_requested == true
      @minimize_requested = false
      native_requested = @native_window == true && defined?(LinuxWindowNative) && LinuxWindowNative.respond_to?(:consume_minimize_request) && LinuxWindowNative.consume_minimize_request
      requested || native_requested
    end

    def update_messages
      pump_messages
      true
    end

    def service_window_update
      update_messages
    end

    def keyboard_state
      return LinuxWindowNative.keyboard_state.to_s if @native_window == true && defined?(LinuxWindowNative)
      @keyboard_state ||= ("\0" * 256)
    end

    def clear_input_state
      @keyboard_state = "\0" * 256
      LinuxWindowNative.clear_character_queue if @native_window == true && defined?(LinuxWindowNative)
      EltenKeyboard.clear_state
      true
    end

    def post_window_action(_wait = false, &block)
      block == nil ? false : block.call
    end

    def begin_input_frame
      if @native_window == true
        LinuxWindowNative.begin_character_frame if defined?(LinuxWindowNative)
        return true
      end
      update_messages
      true
    end

    def character_input_supported?
      @native_window == true
    end

    def keyboard_flags_driven?
      false
    end

    def keyboard_key_held?(_key)
      false
    end

    def keyboard_event_driven?
      true
    end

    def keyboard_pressed_implies_held?
      false
    end

    def take_character(multi = false)
      return LinuxWindowNative.take_character(multi) if @native_window == true && defined?(LinuxWindowNative)
      ""
    rescue Exception
      ""
    end

    def consume_key_events
      return LinuxWindowNative.consume_key_events if @native_window == true && defined?(LinuxWindowNative) && LinuxWindowNative.respond_to?(:consume_key_events)
      []
    rescue Exception
      []
    end

  end
end

module EltenTray
  class << self
    def supported?
      false
    end

    def show(_hwnd = nil)
      0
    end

    def hide
      true
    end

    def handle_message?(_message)
      false
    end

    def restore_hotkey_pressed?
      false
    end

    def request_restore(_source = nil)
      false
    end

    def handle_callback(*_args)
      false
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
