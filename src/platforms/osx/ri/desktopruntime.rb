# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

unless defined?(Fiddle)
  verbose = $VERBOSE
  $VERBOSE = nil
  begin
    require "fiddle"
    require "fiddle/closure"
    require "thread"
  ensure
    $VERBOSE = verbose
  end
end

module OSXWindowNative
  NS_WINDOW_STYLE_TITLED = 1 << 0
  NS_WINDOW_STYLE_CLOSABLE = 1 << 1
  NS_WINDOW_STYLE_MINIATURIZABLE = 1 << 2
  NS_WINDOW_STYLE_RESIZABLE = 1 << 3
  NS_BACKING_STORE_BUFFERED = 2
  NS_APPLICATION_ACTIVATION_POLICY_REGULAR = 0
  NS_ANY_EVENT_MASK = 0xffffffffffffffff
  NS_WINDOW_OCCLUSION_STATE_VISIBLE = 2
  NS_WINDOW_COLLECTION_BEHAVIOR_CAN_JOIN_ALL_SPACES = 1 << 0
  NS_WINDOW_COLLECTION_BEHAVIOR_MOVE_TO_ACTIVE_SPACE = 1 << 1
  NS_EVENT_MASK_KEY_DOWN = 1 << 10
  NS_EVENT_MASK_KEY_UP = 1 << 11
  NS_EVENT_MASK_FLAGS_CHANGED = 1 << 12
  NS_EVENT_MODIFIER_FLAG_CONTROL = 1 << 18
  NS_EVENT_MODIFIER_FLAG_OPTION = 1 << 19
  NS_EVENT_MODIFIER_FLAG_COMMAND = 1 << 20
  NS_EVENT_MODIFIER_FLAG_FUNCTION = 1 << 23
  NS_EVENT_TYPE_KEY_DOWN = 10
  TIMER_INTERVAL_SECONDS = 1.0 / 30.0
  TIMER_STATE_REFRESH_SECONDS = 0.05
  TIMER_FOCUS_REPAIR_SECONDS = 0.10
  TIMER_KEY_RECONCILE_SECONDS = 0.10
  MAX_KEY_EVENT_QUEUE = 1024
  MAC_KEY_Q = 12
  MAC_KEY_FN = 63
  NX_DEVICE_LEFT_CONTROL_MASK = 0x00000001
  NX_DEVICE_RIGHT_CONTROL_MASK = 0x00002000
  NX_DEVICE_LEFT_OPTION_MASK = 0x00000020
  NX_DEVICE_RIGHT_OPTION_MASK = 0x00000040
  TEXT_VIRTUAL_KEYS = [0x20, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE]
  BLOCK_IS_GLOBAL = 1 << 28
  BLOCK_HAS_SIGNATURE = 1 << 30

  class << self
    def create(title, hidden = false)
      return 0 unless available?
      ensure_application
      hwnd = create_direct_window(title, hidden)
      debug("direct window result hwnd=#{hwnd} visible=#{visible?(hwnd)} onscreen=#{onscreen?(hwnd)} active_space=#{active_space?(hwnd)} frame=#{window_saved_frame(hwnd)}") if hwnd.to_i != 0
      hwnd
    rescue Exception
      0
    end

    def create_direct_window(title, hidden)
      style =
        NS_WINDOW_STYLE_TITLED |
        NS_WINDOW_STYLE_CLOSABLE |
        NS_WINDOW_STYLE_MINIATURIZABLE |
        NS_WINDOW_STYLE_RESIZABLE
      hwnd = @msg_id.call(cls("NSWindow"), sel("alloc"))
      hwnd = init_window(hwnd, 100.0, 100.0, 640.0, 360.0, style, NS_BACKING_STORE_BUFFERED, 0)
      return 0 if hwnd.to_i == 0
      @main_window = hwnd
      @msg_void_bool.call(hwnd, sel("setReleasedWhenClosed:"), 0)
      @msg_void_int.call(hwnd, sel("setCollectionBehavior:"), active_space_collection_behavior)
      debug("direct window frame=#{window_saved_frame(hwnd)}")
      @msg_void.call(hwnd, sel("center"))
      set_title(hwnd, title)
      install_content_view(hwnd)
      install_window_focus_delegate(hwnd)
      show(hwnd) if hidden != true
      hwnd
    rescue Exception => e
      debug("direct window failed: #{e.class}: #{e.message}")
      0
    end

    def create_alert_window(title, hidden)
      alert = @msg_id.call(cls("NSAlert"), sel("alloc"))
      alert = @msg_id.call(alert, sel("init"))
      return 0 if alert.to_i == 0
      @retained_objects ||= []
      @retained_objects << alert
      title_string = ns_string(title)
      @msg_void_ptr.call(alert, sel("setMessageText:"), title_string) if title_string.to_i != 0
      info_string = ns_string("")
      @msg_void_ptr.call(alert, sel("setInformativeText:"), info_string) if info_string.to_i != 0
      hwnd = @msg_id.call(alert, sel("window"))
      return 0 if hwnd.to_i == 0
      @msg_void_bool.call(hwnd, sel("setReleasedWhenClosed:"), 0)
      set_title(hwnd, title)
      show(hwnd) if hidden != true
      hwnd
    rescue Exception
      0
    end

    def show(hwnd)
      return perform_on_app_thread(true) { show(hwnd) } unless app_thread?
      return false if hwnd.to_i == 0 || !available?
      ensure_application
      promote_to_foreground_process(true)
      @msg_void_ptr.call(@application, sel("unhide:"), nil)
      @msg_void.call(hwnd, sel("center"))
      finish_launching
      @msg_void_ptr.call(hwnd, sel("makeKeyAndOrderFront:"), nil)
      @msg_void_bool.call(@application, sel("activateIgnoringOtherApps:"), 1)
      activate_running_application
      focus_key_sink(hwnd)
      12.times do
        pump
        break if onscreen?(hwnd)
        sleep(0.01)
      end
      result = onscreen?(hwnd)
      refresh_window_cache(hwnd)
      debug("show hwnd=#{hwnd} visible=#{visible?(hwnd)} onscreen=#{result} active=#{active?(hwnd)} active_space=#{active_space?(hwnd)} frontmost=#{frontmost?} occlusion=#{occlusion_state(hwnd)} window_number=#{window_number(hwnd)} frame=#{window_saved_frame(hwnd)}")
      result
    rescue Exception
      false
    end

    def hide(hwnd)
      return perform_on_app_thread(true) { hide(hwnd) } unless app_thread?
      return false if hwnd.to_i == 0 || !available?
      @msg_void_ptr.call(hwnd, sel("orderOut:"), nil)
      refresh_window_cache(hwnd)
      true
    rescue Exception
      false
    end

    def message_box(text, caption = "Elten")
      return perform_on_app_thread(true) { message_box(text, caption) } unless app_thread?
      return false unless available?
      ensure_application
      finish_launching
      alert = @msg_id.call(cls("NSAlert"), sel("alloc"))
      alert = @msg_id.call(alert, sel("init"))
      return false if alert.to_i == 0
      @msg_void_ptr.call(alert, sel("setMessageText:"), ns_string(caption))
      @msg_void_ptr.call(alert, sel("setInformativeText:"), ns_string(text))
      @msg_id_ptr.call(alert, sel("addButtonWithTitle:"), ns_string("OK"))
      @msg_int.call(alert, sel("runModal"))
      true
    rescue Exception => e
      debug("message box failed: #{e.class}: #{e.message}")
      false
    ensure
      @msg_void.call(alert, sel("release")) if defined?(alert) && alert.to_i != 0 rescue nil
    end

    def visible?(hwnd)
      return cached_visible? if !app_thread?
      return false if hwnd.to_i == 0 || !available?
      @msg_bool.call(hwnd, sel("isVisible")).to_i != 0
    rescue Exception
      false
    end

    def onscreen?(hwnd)
      return cached_onscreen? if !app_thread?
      return false if hwnd.to_i == 0 || !visible?(hwnd)
      return false if window_number(hwnd) <= 0
      state = occlusion_state(hwnd)
      return true if state < 0
      (state & NS_WINDOW_OCCLUSION_STATE_VISIBLE) != 0
    rescue Exception
      false
    end

    def active?(hwnd)
      return @cached_active == true if !app_thread?
      return false if hwnd.to_i == 0 || !onscreen?(hwnd)
      @msg_bool.call(hwnd, sel("isKeyWindow")).to_i != 0 || @msg_bool.call(hwnd, sel("isMainWindow")).to_i != 0
    rescue Exception
      false
    end

    def keyboard_active?(hwnd)
      return @keyboard_allowed == true if @app_thread != nil && Thread.current != @app_thread
      keyboard_focus_active?(hwnd)
    rescue Exception
      false
    end

    def active_space?(hwnd)
      return @cached_active_space == true if !app_thread?
      return false if hwnd.to_i == 0 || !available?
      @msg_bool.call(hwnd, sel("isOnActiveSpace")).to_i != 0
    rescue Exception
      false
    end

    def frontmost?
      return @cached_frontmost == true if !app_thread?
      return false unless available?
      current = Process.pid.to_i
      front = frontmost_process_id
      result = front == current
      if @last_frontmost_result != result
        debug("frontmost=#{result} current_pid=#{current} front_pid=#{front}")
        @last_frontmost_result = result
      end
      result
    rescue Exception
      false
    end

    def pump
      return false unless available?
      ensure_application
      return false if @app_thread != nil && Thread.current != @app_thread
      process_app_thread_actions
      32.times do
        event = @msg_next_event.call(@application, sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), NS_ANY_EVENT_MASK, distant_past, run_loop_mode, 1)
        break if event.to_i == 0
        result = handle_event(event)
        @msg_void_ptr.call(@application, sel("sendEvent:"), event) if result != :consumed
      end
      refresh_keyboard_active
      refresh_window_cache(@main_window) if @main_window.to_i != 0
      maybe_run_application_slice
      @msg_void.call(@application, sel("updateWindows"))
      true
    rescue Exception
      false
    end

    def keyboard_state
      @keyboard_state ||= ("\0" * 256)
      keyboard_state_allowed? ? @keyboard_state.dup : ("\0" * 256)
    rescue Exception
      "\0" * 256
    end

    def consume_key_events
      @key_event_queue ||= []
      events = @key_event_queue
      @key_event_queue = []
      events
    rescue Exception
      []
    end

    def clear_input_state
      clear_keyboard_state(true)
    end

    def consume_keyboard_reset
      serial = @keyboard_reset_serial.to_i
      return false if @keyboard_reset_consumed_serial.to_i == serial
      @keyboard_reset_consumed_serial = serial
      true
    rescue Exception
      false
    end

    def consume_close_request
      requested = @close_requested == true
      @close_requested = false
      requested
    rescue Exception
      false
    end

    def consume_quit_shortcut_request
      requested = @quit_shortcut_requested == true
      @quit_shortcut_requested = false
      requested
    rescue Exception
      false
    end

    def consume_main_menu_request
      requested = @main_menu_requested == true
      @main_menu_requested = false
      requested
    rescue Exception
      false
    end

    def translated_character_for_key(key)
      @translated_key_chars ||= {}
      @translated_key_chars[key.to_i & 0xff].to_s
    rescue Exception
      ""
    end

    def run_main_loop(worker_thread = nil)
      ensure_application
      @app_thread = Thread.current
      @worker_thread = worker_thread
      install_timer
      install_key_event_monitor
      finish_launching
      show(@main_window) if @main_window.to_i != 0 && !visible?(@main_window)
      debug("main Cocoa run started")
      @msg_void.call(@application, sel("run"))
      debug("main Cocoa run stopped")
      true
    rescue Exception => e
      debug("main Cocoa loop failed: #{e.class}: #{e.message}")
      false
    end

    def request_exit
      if app_thread?
        @exit_requested = true
      else
        perform_on_app_thread(false) { @exit_requested = true }
      end
      true
    end

    def available?
      initialize_api
    end

    def app_thread?
      @app_thread == nil || Thread.current == @app_thread
    end

    def perform_on_app_thread(wait = false, &block)
      return block.call if app_thread?
      item = {
        block: block,
        wait: wait,
        done: false,
        result: nil,
        error: nil,
        mutex: Mutex.new,
        condition: ConditionVariable.new
      }
      action_queue << item
      return true unless wait
      item[:mutex].synchronize do
        item[:condition].wait(item[:mutex], 2.0) until item[:done] == true
      end
      raise item[:error] if item[:error] != nil
      item[:result]
    rescue Exception => e
      debug("app thread action failed: #{e.class}: #{e.message}")
      false
    end

    private

    def initialize_api
      return @available if defined?(@available)
      @available = false
      Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
      objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
      @objc_get_class = Fiddle::Function.new(objc["objc_getClass"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @sel_register_name = Fiddle::Function.new(objc["sel_registerName"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @objc_allocate_class_pair = Fiddle::Function.new(objc["objc_allocateClassPair"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T], Fiddle::TYPE_VOIDP)
      @objc_register_class_pair = Fiddle::Function.new(objc["objc_registerClassPair"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
      @class_add_method = Fiddle::Function.new(objc["class_addMethod"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR)
      @class_replace_method = Fiddle::Function.new(objc["class_replaceMethod"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      msg = objc["objc_msgSend"]
      @msg_id = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @msg_bool = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @msg_void = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
      @msg_void_ptr = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
      @msg_void_bool = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
      native_int = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
      @msg_void_int = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, native_int], Fiddle::TYPE_VOID)
      @msg_bool_int = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, native_int], Fiddle::TYPE_INT)
      @msg_bool_ptr = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @msg_int = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @msg_ulong = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_ULONG_LONG)
      @msg_id_cstr = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @msg_id_ptr = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @msg_id_id_sel_id = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @msg_id_ulong_ptr = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_ULONG_LONG, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      @msg_id_double = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_DOUBLE], Fiddle::TYPE_VOIDP)
      @msg_id_timer = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
      @msg_void_sel_ptr_double = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_DOUBLE], Fiddle::TYPE_VOID)
      @msg_void_ptr_int = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, native_int], Fiddle::TYPE_VOID)
      @msg_bool_ptr_ptr = Fiddle::Function.new(msg, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      @msg_init_window = Fiddle::Function.new(
        msg,
        [
          Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
          Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE,
          native_int,
          native_int,
          Fiddle::TYPE_INT
        ],
        Fiddle::TYPE_VOIDP
      )
      @msg_next_event = Fiddle::Function.new(
        msg,
        [
          Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
          Fiddle::TYPE_LONG_LONG,
          Fiddle::TYPE_VOIDP,
          Fiddle::TYPE_VOIDP,
          Fiddle::TYPE_INT
        ],
        Fiddle::TYPE_VOIDP
      )
      @available = true
    rescue Exception
      @available = false
    end

    def debug(message)
      ::Log.debug("OSX window: #{message}")
    rescue Exception
    end

    def ensure_application
      return @application if @application.to_i != 0
      @pool = @msg_id.call(cls("NSAutoreleasePool"), sel("new"))
      @application = @msg_id.call(cls("NSApplication"), sel("sharedApplication"))
      @app_thread = Thread.current
      clear_keyboard_state
      refresh_window_cache(0)
      @msg_bool_int.call(@application, sel("setActivationPolicy:"), NS_APPLICATION_ACTIVATION_POLICY_REGULAR)
      install_application_terminate_hook
      install_main_menu_open_hook
      install_main_menu
      @application
    end

    def finish_launching
      return true if @finished_launching == true
      @msg_void.call(@application, sel("finishLaunching"))
      @finished_launching = true
      true
    rescue Exception => e
      debug("finishLaunching failed: #{e.class}: #{e.message}")
      false
    end

    def install_main_menu
      return true if @main_menu_installed == true
      main_menu = new_obj("NSMenu")
      app_menu_item = new_obj("NSMenuItem")
      @msg_void_ptr.call(main_menu, sel("addItem:"), app_menu_item)
      app_menu = new_obj("NSMenu")
      @msg_void_bool.call(app_menu, sel("setAutoenablesItems:"), 0)
      open_menu_item = @msg_id_id_sel_id.call(alloc("NSMenuItem"), sel("initWithTitle:action:keyEquivalent:"), ns_string("Open Elten Menu (ALT)"), sel("eltenOpenMainMenu:"), ns_string(""))
      @msg_void_ptr.call(open_menu_item, sel("setTarget:"), @application)
      @msg_void_bool.call(open_menu_item, sel("setEnabled:"), 1)
      @msg_void_ptr.call(app_menu, sel("addItem:"), open_menu_item)
      quit_item = @msg_id_id_sel_id.call(alloc("NSMenuItem"), sel("initWithTitle:action:keyEquivalent:"), ns_string("Quit Elten"), sel("terminate:"), ns_string("q"))
      @msg_void_ptr.call(quit_item, sel("setTarget:"), @application)
      @msg_void_bool.call(quit_item, sel("setEnabled:"), 1)
      @msg_void_ptr.call(app_menu, sel("addItem:"), quit_item)
      @msg_void_ptr.call(app_menu_item, sel("setSubmenu:"), app_menu)
      @msg_void_ptr.call(@application, sel("setMainMenu:"), main_menu)
      @retained_objects ||= []
      @retained_objects.concat([main_menu, app_menu_item, app_menu, open_menu_item, quit_item])
      @main_menu_installed = true
      true
    rescue Exception => e
      debug("main menu failed: #{e.class}: #{e.message}")
      false
    end

    def install_application_terminate_hook
      return true if @application_terminate_hook_installed == true
      @application_terminate_hook = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |_self, _cmd, _sender|
        OSXWindowNative.send(:request_close, true)
      end
      @class_replace_method.call(cls("NSApplication"), sel("terminate:"), @application_terminate_hook, "v@:@".b + "\0".b)
      @application_terminate_hook_installed = true
      true
    rescue Exception => e
      debug("application terminate hook failed: #{e.class}: #{e.message}")
      false
    end

    def install_main_menu_open_hook
      return true if @main_menu_open_hook_installed == true
      @main_menu_open_hook = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |_self, _cmd, _sender|
        OSXWindowNative.send(:request_main_menu)
      end
      @class_replace_method.call(cls("NSApplication"), sel("eltenOpenMainMenu:"), @main_menu_open_hook, "v@:@".b + "\0".b)
      @main_menu_open_hook_installed = true
      true
    rescue Exception => e
      debug("main menu open hook failed: #{e.class}: #{e.message}")
      false
    end

    def promote_to_foreground_process(force = false)
      @foreground_promoted = true
    end

    def set_title(hwnd, title)
      ns_title = ns_string(title)
      return false if ns_title.to_i == 0
      @msg_void_ptr.call(hwnd, sel("setTitle:"), ns_title)
      true
    end

    def install_content_view(hwnd)
      content_view = create_key_sink_view
      return false if content_view.to_i == 0
      @key_sink_view = content_view
      @msg_void_ptr.call(hwnd, sel("setContentView:"), content_view)
      configure_key_sink_view(content_view)
      @retained_objects ||= []
      @retained_objects << content_view
      true
    rescue Exception => e
      debug("content view failed: #{e.class}: #{e.message}")
      false
    end

    def install_window_focus_delegate(hwnd)
      return false if hwnd.to_i == 0
      klass = window_focus_delegate_class
      delegate = @msg_id.call(klass, sel("new"))
      return false if delegate.to_i == 0
      @msg_void_ptr.call(hwnd, sel("setDelegate:"), delegate)
      @window_focus_delegate = delegate
      @retained_objects ||= []
      @retained_objects << delegate
      true
    rescue Exception => e
      debug("window focus delegate failed: #{e.class}: #{e.message}")
      false
    end

    def window_focus_delegate_class
      return @window_focus_delegate_class if @window_focus_delegate_class.to_i != 0
      klass_name = "EltenWindowFocusDelegate_#{Process.pid}_#{object_id}"
      klass = @objc_allocate_class_pair.call(cls("NSObject"), klass_name.b + "\0".b, 0)
      raise "objc_allocateClassPair failed" if klass.to_i == 0
      @window_focus_delegate_closures ||= []
      @window_focus_delegate_closures << add_objc_method(klass, "windowDidResignKey:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") do |_self, _cmd, _notification|
        OSXWindowNative.send(:window_focus_changed, false)
      end
      @window_focus_delegate_closures << add_objc_method(klass, "windowDidBecomeKey:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") do |_self, _cmd, _notification|
        OSXWindowNative.send(:window_focus_changed, true)
      end
      @window_focus_delegate_closures << add_objc_method(klass, "windowDidMiniaturize:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") do |_self, _cmd, _notification|
        OSXWindowNative.send(:window_focus_changed, false)
      end
      @objc_register_class_pair.call(klass)
      @window_focus_delegate_class = klass
    end

    def create_key_sink_view
      klass = key_sink_view_class
      view = @msg_id.call(klass, sel("alloc"))
      invoke_init_view(view, 0.0, 0.0, 640.0, 360.0)
    end

    def key_sink_view_class
      return @key_sink_view_class if @key_sink_view_class.to_i != 0
      klass_name = "EltenKeySinkView_#{Process.pid}_#{object_id}"
      klass = @objc_allocate_class_pair.call(cls("NSView"), klass_name.b + "\0".b, 0)
      raise "objc_allocateClassPair failed" if klass.to_i == 0
      @key_sink_closures ||= []
      @key_sink_closures << add_objc_method(klass, "acceptsFirstResponder", Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "B@:") { |_self, _cmd| 1 }
      @key_sink_closures << add_objc_method(klass, "canBecomeKeyView", Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "B@:") { |_self, _cmd| 1 }
      @key_sink_closures << add_objc_method(klass, "isOpaque", Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "B@:") { |_self, _cmd| 1 }
      @key_sink_closures << add_objc_method(klass, "keyDown:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") { |_self, _cmd, event| OSXWindowNative.send(:handle_event, event) }
      @key_sink_closures << add_objc_method(klass, "keyUp:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") { |_self, _cmd, event| OSXWindowNative.send(:handle_event, event) }
      @key_sink_closures << add_objc_method(klass, "flagsChanged:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") { |_self, _cmd, event| OSXWindowNative.send(:handle_event, event) }
      @key_sink_closures << add_objc_method(klass, "performKeyEquivalent:", Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "B@:@") { |_self, _cmd, event| OSXWindowNative.send(:handle_event, event); 1 }
      @key_sink_closures << add_objc_method(klass, "doCommandBySelector:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@::") { |_self, _cmd, _selector| nil }
      @key_sink_closures << add_objc_method(klass, "noResponderFor:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@::") { |_self, _cmd, _selector| nil }
      @key_sink_closures << add_objc_method(klass, "insertText:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") { |_self, _cmd, _text| nil }
      @key_sink_closures << add_objc_method(klass, "interpretKeyEvents:", Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], "v@:@") { |_self, _cmd, _events| nil }
      @objc_register_class_pair.call(klass)
      @key_sink_view_class = klass
    end

    def configure_key_sink_view(view)
      safe_void_bool(view, "setWantsLayer:", true)
      safe_void_bool(view, "setAccessibilityElement:", true)
      safe_void_ptr(view, "setAccessibilityRole:", ns_string("AXGroup"))
      safe_void_ptr(view, "setAccessibilityLabel:", ns_string("Elten"))
      safe_void_ptr(view, "setAccessibilityValue:", ns_string("Elten"))
      safe_void_bool(view, "setAccessibilityFocused:", true)
      true
    rescue Exception => e
      debug("key sink config failed: #{e.class}: #{e.message}")
      false
    end

    def focus_key_sink(hwnd = @main_window)
      return false if hwnd.to_i == 0 || @key_sink_view == nil || @key_sink_view.to_i == 0
      result = @msg_bool_ptr.call(hwnd, sel("makeFirstResponder:"), @key_sink_view).to_i != 0
      @key_sink_focused = result && first_responder(hwnd).to_i == @key_sink_view.to_i
      result
    rescue Exception => e
      debug("key sink focus failed: #{e.class}: #{e.message}")
      false
    end

    def add_objc_method(klass, selector_name, rettype, argtypes, encoding, &block)
      closure = Fiddle::Closure::BlockCaller.new(rettype, argtypes, &block)
      ok = @class_add_method.call(klass, sel(selector_name), closure, encoding.b + "\0".b)
      raise "class_addMethod failed for #{selector_name}" if ok.to_i == 0
      closure
    end

    def safe_void_bool(object, selector_name, value)
      selector = sel(selector_name)
      return false unless responds_to_selector?(object, selector)
      @msg_void_bool.call(object, selector, value ? 1 : 0)
      true
    rescue Exception
      false
    end

    def safe_void_ptr(object, selector_name, value)
      selector = sel(selector_name)
      return false unless responds_to_selector?(object, selector)
      @msg_void_ptr.call(object, selector, value)
      true
    rescue Exception
      false
    end

    def responds_to_selector?(object, selector)
      object.to_i != 0 && @msg_bool_ptr.call(object, sel("respondsToSelector:"), selector).to_i != 0
    rescue Exception
      false
    end

    def run_application_slice
      return false if @application.to_i == 0 || @running_slice == true
      return false if @app_thread != nil && Thread.current != @app_thread
      @running_slice = true
      debug("run slice start")
      @msg_void_sel_ptr_double.call(@application, sel("performSelector:withObject:afterDelay:"), sel("stop:"), 0, 0.005)
      @msg_void.call(@application, sel("run"))
      debug("run slice stop")
      true
    rescue Exception => e
      debug("run slice failed: #{e.class}: #{e.message}")
      false
    ensure
      @running_slice = false
    end

    def install_timer
      return true if defined?(@timer) && @timer.to_i != 0
      klass_name = "EltenCocoaTimer_#{Process.pid}_#{object_id}"
      klass = @objc_allocate_class_pair.call(cls("NSObject"), klass_name.b + "\0".b, 0)
      raise "objc_allocateClassPair failed" if klass.to_i == 0
      @timer_closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |_self, _cmd, _timer|
        begin
          OSXWindowNative.send(:timer_tick)
        rescue Exception => e
          OSXWindowNative.send(:debug, "timer tick failed: #{e.class}: #{e.message}")
        end
      end
      ok = @class_add_method.call(klass, sel("eltenTick:"), @timer_closure, "v@:@".b + "\0".b)
      raise "class_addMethod failed" if ok.to_i == 0
      @objc_register_class_pair.call(klass)
      @timer_target = @msg_id.call(klass, sel("new"))
      @timer = @msg_id_timer.call(cls("NSTimer"), sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"), TIMER_INTERVAL_SECONDS, @timer_target, sel("eltenTick:"), 0, 1)
      @retained_objects ||= []
      @retained_objects.concat([klass, @timer_target, @timer])
      debug("Cocoa timer installed")
      true
    rescue Exception => e
      debug("Cocoa timer failed: #{e.class}: #{e.message}")
      false
    end

    def install_key_event_monitor
      return true if defined?(@key_event_monitor) && @key_event_monitor.to_i != 0
      @key_monitor_closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOIDP, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |_block, event|
        begin
          result = OSXWindowNative.send(:handle_event, event)
          result == :consumed ? 0 : event
        rescue Exception => e
          OSXWindowNative.send(:debug, "key monitor failed: #{e.class}: #{e.message}")
          event
        end
      end
      @key_monitor_signature = c_string("@@?@")
      @key_monitor_descriptor = block_descriptor(32, @key_monitor_signature)
      @key_monitor_block = block_literal(@key_monitor_closure, @key_monitor_descriptor)
      mask = NS_EVENT_MASK_KEY_DOWN | NS_EVENT_MASK_KEY_UP | NS_EVENT_MASK_FLAGS_CHANGED
      @key_event_monitor = @msg_id_ulong_ptr.call(cls("NSEvent"), sel("addLocalMonitorForEventsMatchingMask:handler:"), mask, @key_monitor_block)
      @retained_objects ||= []
      @retained_objects.concat([@key_monitor_signature, @key_monitor_descriptor, @key_monitor_block, @key_event_monitor])
      debug("key event monitor installed")
      true
    rescue Exception => e
      debug("key event monitor failed: #{e.class}: #{e.message}")
      false
    end

    def timer_tick
      process_app_thread_actions
      now = monotonic_time
      if timer_due?(:state_refresh, TIMER_STATE_REFRESH_SECONDS, now)
        refresh_window_cache(@main_window) if @main_window.to_i != 0
        refresh_keyboard_active
      end
      reconcile_option_control_state if @keyboard_allowed == true
      reconcile_stale_keyboard_state(now) if @keyboard_allowed == true && timer_due?(:key_reconcile, TIMER_KEY_RECONCILE_SECONDS, now)
      refresh_key_sink_focus if timer_due?(:focus_repair, TIMER_FOCUS_REPAIR_SECONDS, now)
      if @exit_requested == true || (@worker_thread != nil && !@worker_thread.alive?)
        clear_keyboard_state
        @msg_void_ptr.call(@application, sel("stop:"), nil) if @application.to_i != 0
      end
      true
    rescue Exception => e
      debug("timer tick failed: #{e.class}: #{e.message}")
      false
    end

    def timer_due?(key, interval, now = nil)
      now ||= monotonic_time
      @timer_last ||= {}
      last = @timer_last[key]
      return false if last != nil && now - last.to_f < interval.to_f
      @timer_last[key] = now
      true
    rescue Exception
      true
    end

    def refresh_key_sink_focus
      return false if @main_window.to_i == 0 || @key_sink_view == nil || @key_sink_view.to_i == 0
      @key_sink_focused = first_responder(@main_window).to_i == @key_sink_view.to_i
      if @keyboard_allowed == true && @key_sink_focused != true
        focus_key_sink(@main_window)
        refresh_keyboard_active
      end
      true
    rescue Exception
      false
    end

    def maybe_run_application_slice
      now = monotonic_time
      if @finished_launching == true && (now - @last_run_slice.to_f) >= 0.25
        @last_run_slice = now
        run_application_slice
      else
        run_once
      end
    end

    def application_active?
      return false if @application.to_i == 0
      @msg_bool.call(@application, sel("isActive")).to_i != 0
    rescue Exception
      false
    end

    def key_window
      return 0 if !app_thread?
      return 0 if @application.to_i == 0
      @msg_id.call(@application, sel("keyWindow"))
    rescue Exception
      0
    end

    def main_window
      return 0 if !app_thread?
      return 0 if @application.to_i == 0
      @msg_id.call(@application, sel("mainWindow"))
    rescue Exception
      0
    end

    def first_responder(hwnd = @main_window)
      return 0 if !app_thread? || hwnd.to_i == 0
      @msg_id.call(hwnd, sel("firstResponder"))
    rescue Exception
      0
    end

    def handle_event(event)
      return true if keyboard_state_allowed? != true
      type = @msg_int.call(event, sel("type")).to_i
      case type
      when NS_EVENT_TYPE_KEY_DOWN
        if quit_shortcut_event?(event)
          request_close(true)
          return :consumed
        end
        set_event_key(event, true)
        return :consumed
      when 11
        set_event_key(event, false)
        return :consumed
      when 12
        update_modifier_keys(@msg_ulong.call(event, sel("modifierFlags")).to_i)
        return :consumed
      end
      true
    rescue Exception
      false
    end

    def quit_shortcut_event?(event)
      return false if @msg_int.call(event, sel("keyCode")).to_i != MAC_KEY_Q
      (@msg_ulong.call(event, sel("modifierFlags")).to_i & NS_EVENT_MODIFIER_FLAG_COMMAND) != 0
    rescue Exception
      false
    end

    def request_close(quit_shortcut = false)
      @close_requested = true
      @quit_shortcut_requested = true if quit_shortcut
      true
    rescue Exception
      false
    end

    def request_main_menu
      @main_menu_requested = true
      true
    rescue Exception
      false
    end

    def block_literal(invoke, descriptor)
      pointer_size = Fiddle::SIZEOF_VOIDP
      block = Fiddle::Pointer.malloc(pointer_size * 4)
      block[0, pointer_size] = [ns_concrete_global_block].pack(pointer_pack)
      block[pointer_size, 4] = [BLOCK_IS_GLOBAL | BLOCK_HAS_SIGNATURE].pack("l")
      block[pointer_size + 4, 4] = [0].pack("l")
      block[pointer_size * 2, pointer_size] = [invoke.to_i].pack(pointer_pack)
      block[pointer_size * 3, pointer_size] = [descriptor.to_i].pack(pointer_pack)
      block
    end

    def block_descriptor(block_size, signature)
      pointer_size = Fiddle::SIZEOF_VOIDP
      descriptor = Fiddle::Pointer.malloc(pointer_size * 3)
      descriptor[0, pointer_size] = [0].pack(pointer_pack)
      descriptor[pointer_size, pointer_size] = [block_size].pack(pointer_pack)
      descriptor[pointer_size * 2, pointer_size] = [signature.to_i].pack(pointer_pack)
      descriptor
    end

    def ns_concrete_global_block
      return @ns_concrete_global_block if defined?(@ns_concrete_global_block)
      @ns_concrete_global_block = Fiddle.dlopen("/usr/lib/libSystem.B.dylib")["_NSConcreteGlobalBlock"]
    end

    def c_string(text)
      bytes = text.to_s.b + "\0".b
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def process_app_thread_actions
      32.times do
        item = nil
        begin
          item = action_queue.pop(true)
        rescue ThreadError
          break
        end
        begin
          item[:result] = item[:block].call
        rescue Exception => e
          item[:error] = e
        ensure
          if item[:wait]
            item[:mutex].synchronize do
              item[:done] = true
              item[:condition].signal
            end
          end
        end
      end
      true
    end

    def action_queue
      @action_queue ||= Queue.new
    end

    def refresh_window_cache(hwnd)
      if hwnd.to_i == 0 || !app_thread?
        @cached_visible = false if hwnd.to_i == 0
        @cached_onscreen = false if hwnd.to_i == 0
        @cached_active = false if hwnd.to_i == 0
        @cached_active_space = false if hwnd.to_i == 0
        @cached_frontmost = false if hwnd.to_i == 0
        return false
      end
      @cached_visible = visible?(hwnd)
      @cached_onscreen = @cached_visible && window_number(hwnd) > 0 && ((occlusion_state(hwnd) & NS_WINDOW_OCCLUSION_STATE_VISIBLE) != 0)
      @cached_active = @cached_onscreen && (@msg_bool.call(hwnd, sel("isKeyWindow")).to_i != 0 || @msg_bool.call(hwnd, sel("isMainWindow")).to_i != 0)
      @cached_active_space = @msg_bool.call(hwnd, sel("isOnActiveSpace")).to_i != 0
      @cached_frontmost = frontmost?
      true
    rescue Exception
      false
    end

    def cached_visible?
      @cached_visible == true
    end

    def cached_onscreen?
      @cached_onscreen == true
    end

    def set_event_key(event, down)
      key_code = @msg_int.call(event, sel("keyCode")).to_i
      return false if key_code == MAC_KEY_FN
      vk = ::EltenKeyboard::MAC_TO_VK[key_code]
      return false if vk == nil
      update_translated_key_character(vk, event, down)
      set_keyboard_key(vk, down, down && event_repeat?(event))
      true
    rescue Exception
      false
    end

    def update_modifier_keys(flags)
      set_keyboard_key(::EltenKeyboard::VK_SHIFT, (flags & (1 << 17)) != 0)
      control_down = control_modifier_down?(flags)
      command_down = (flags & NS_EVENT_MODIFIER_FLAG_COMMAND) != 0
      left_control = ::EltenKeyboard.physical_key_down?(::EltenKeyboard::VK_CONTROL_LEFT) == true
      right_control = ::EltenKeyboard.physical_key_down?(::EltenKeyboard::VK_CONTROL_RIGHT) == true
      left_command = ::EltenKeyboard.physical_key_down?(::EltenKeyboard::VK_COMMAND_LEFT) == true
      right_command = ::EltenKeyboard.physical_key_down?(::EltenKeyboard::VK_COMMAND_RIGHT) == true
      left_control = true if control_down && !left_control && !right_control
      left_command = true if command_down && !left_command && !right_command
      set_keyboard_key(::EltenKeyboard::VK_CONTROL_LEFT, left_control)
      set_keyboard_key(::EltenKeyboard::VK_CONTROL_RIGHT, right_control)
      set_keyboard_key(::EltenKeyboard::VK_COMMAND_LEFT, left_command)
      set_keyboard_key(::EltenKeyboard::VK_COMMAND_RIGHT, right_command)
      set_keyboard_key(::EltenKeyboard::VK_CONTROL, control_down || command_down)
      set_keyboard_key(::EltenKeyboard::VK_OPTION, left_option_modifier_down?(flags))
      true
    end

    def control_modifier_down?(flags)
      (flags & NS_EVENT_MODIFIER_FLAG_CONTROL) != 0 ||
        (flags & NX_DEVICE_LEFT_CONTROL_MASK) != 0 ||
        (flags & NX_DEVICE_RIGHT_CONTROL_MASK) != 0
    end

    def left_option_modifier_down?(flags)
      return false if (flags & NS_EVENT_MODIFIER_FLAG_FUNCTION) != 0
      left_option = (flags & NX_DEVICE_LEFT_OPTION_MASK) != 0
      right_option = (flags & NX_DEVICE_RIGHT_OPTION_MASK) != 0
      return left_option if left_option || right_option
      (flags & NS_EVENT_MODIFIER_FLAG_OPTION) != 0
    end

    def reconcile_option_control_state
      return false if @keyboard_state == nil || (@keyboard_state.getbyte(::EltenKeyboard::VK_OPTION).to_i & 0x80) == 0
      left_control = ::EltenKeyboard.physical_key_down?(::EltenKeyboard::VK_CONTROL_LEFT)
      right_control = ::EltenKeyboard.physical_key_down?(::EltenKeyboard::VK_CONTROL_RIGHT)
      return false if left_control == nil && right_control == nil
      set_keyboard_key(::EltenKeyboard::VK_CONTROL_LEFT, left_control == true)
      set_keyboard_key(::EltenKeyboard::VK_CONTROL_RIGHT, right_control == true)
      command_down = (@keyboard_state.getbyte(::EltenKeyboard::VK_COMMAND_LEFT).to_i & 0x80) != 0 ||
        (@keyboard_state.getbyte(::EltenKeyboard::VK_COMMAND_RIGHT).to_i & 0x80) != 0
      set_keyboard_key(::EltenKeyboard::VK_CONTROL, left_control == true || right_control == true || command_down)
      true
    rescue Exception
      false
    end

    def update_translated_key_character(key, event, down)
      @translated_key_chars ||= {}
      key = key.to_i & 0xff
      if down != true || !text_virtual_key?(key)
        @translated_key_chars.delete(key)
        return true
      end
      if translated_character_event_allowed?(event)
        text = sanitize_translated_character_text(objc_string(@msg_id.call(event, sel("characters"))))
        text == "" ? @translated_key_chars.delete(key) : @translated_key_chars[key] = text
      else
        @translated_key_chars.delete(key)
      end
      true
    rescue Exception
      false
    end

    def translated_character_event_allowed?(event)
      flags = @msg_ulong.call(event, sel("modifierFlags")).to_i
      return false if (flags & (1 << 18)) != 0
      return false if (flags & (1 << 20)) != 0
      return false if (flags & NS_EVENT_MODIFIER_FLAG_FUNCTION) != 0
      return false if left_option_modifier_down?(flags)
      true
    rescue Exception
      false
    end

    def text_virtual_key?(key)
      key = key.to_i
      return true if key >= 0x30 && key <= 0x5A
      TEXT_VIRTUAL_KEYS.include?(key)
    end

    def sanitize_translated_character_text(text)
      text.to_s.each_char.select do |char|
        code = char.ord
        code >= 32 && !(code >= 0x7f && code <= 0x9f) && !(code >= 0xf700 && code <= 0xf8ff)
      end.join
    rescue Exception
      ""
    end

    def set_keyboard_key(key, down, repeat = false)
      @keyboard_state ||= ("\0" * 256)
      @keyboard_allowed = true
      @key_down_since ||= {}
      key = key.to_i & 0xff
      previous = (@keyboard_state.getbyte(key).to_i & 0x80) != 0
      return false if down == true && repeat == true && previous != true
      @keyboard_state.setbyte(key, down ? 0x80 : 0)
      if down == true
        @key_down_since[key] = monotonic_time if previous != true
      else
        @key_down_since.delete(key)
      end
      queue_key_event(key, down) if !repeat && previous != (down == true)
      true
    end

    def event_repeat?(event)
      @msg_bool.call(event, sel("isARepeat")).to_i != 0
    rescue Exception
      false
    end

    def queue_key_event(key, state)
      @key_event_queue ||= []
      @key_event_queue << [key.to_i & 0xff, state]
      @key_event_queue = @key_event_queue.last(MAX_KEY_EVENT_QUEUE) if @key_event_queue.size > MAX_KEY_EVENT_QUEUE
      true
    end

    def clear_keyboard_state(notify = false)
      @keyboard_reset_serial = @keyboard_reset_serial.to_i + 1 if notify == true
      @keyboard_state = "\0" * 256
      @key_event_queue ||= []
      @key_event_queue.clear
      @key_down_since ||= {}
      @key_down_since.clear
      @translated_key_chars ||= {}
      @translated_key_chars.clear
      @keyboard_allowed = false
      true
    end

    def keyboard_state_allowed?
      return @keyboard_allowed == true if @app_thread != nil && Thread.current != @app_thread
      keyboard_focus_active?(@main_window)
    rescue Exception
      false
    end

    def refresh_keyboard_active
      hwnd = @main_window
      was_allowed = @keyboard_allowed == true
      allowed = keyboard_focus_active?(hwnd)
      if allowed
        @keyboard_allowed = true
      else
        clear_keyboard_state(was_allowed)
      end
      @keyboard_allowed
    rescue Exception
      @keyboard_allowed = false
    end

    def keyboard_focus_active?(hwnd)
      return false if hwnd.to_i == 0 || !visible?(hwnd) || !onscreen?(hwnd)
      return false unless application_active?
      return false unless active_space?(hwnd)
      return false unless frontmost?
      key_window.to_i == hwnd.to_i
    rescue Exception
      false
    end

    def window_focus_changed(active)
      if active == true
        refresh_keyboard_active
      else
        clear_keyboard_state(true)
      end
      true
    rescue Exception
      false
    end

    def reconcile_stale_keyboard_state(now = nil)
      return false if @keyboard_allowed != true
      @keyboard_state ||= ("\0" * 256)
      @key_down_since ||= {}
      now ||= monotonic_time
      @key_down_since.to_a.each do |key, since|
        if (@keyboard_state.getbyte(key).to_i & 0x80) == 0
          @key_down_since.delete(key)
          next
        end
        next if now - since.to_f <= stale_key_timeout(key)
        physical = ::EltenKeyboard.physical_key_down?(key)
        next if physical != false
        set_keyboard_key(key, false)
        Log.debug("Keyboard stale key released: #{key}") if defined?(Log)
      end
      true
    rescue Exception => e
      Log.warning("Keyboard state reconciliation failed: #{e.class}: #{e.message}") if defined?(Log)
      false
    end

    def stale_key_timeout(key)
      if ::EltenKeyboard::MODIFIER_KEYS.include?(key.to_i)
        ::EltenKeyboard::STALE_MODIFIER_KEY_SECONDS
      else
        ::EltenKeyboard::STALE_REPEATABLE_KEY_SECONDS
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue Exception
      Time.now.to_f
    end

    def run_loop_mode
      @run_loop_mode ||= ns_string("kCFRunLoopDefaultMode")
    end

    def distant_past
      @distant_past ||= @msg_id.call(cls("NSDate"), sel("distantPast"))
    end

    def near_future
      @msg_id_double.call(cls("NSDate"), sel("dateWithTimeIntervalSinceNow:"), 0.001)
    rescue Exception
      distant_past
    end

    def init_window(hwnd, x, y, width, height, style, backing, defer)
      invoke_init_window(hwnd, x, y, width, height, style, backing, defer)
    rescue Exception => e
      debug("initWithContentRect via invocation failed: #{e.class}: #{e.message}")
      fallback_init_window(hwnd, x, y, width, height, style)
    end

    def invoke_init_window(hwnd, x, y, width, height, style, backing, defer)
      selector = sel("initWithContentRect:styleMask:backing:defer:")
      signature = @msg_id_ptr.call(hwnd, sel("methodSignatureForSelector:"), selector)
      raise "missing NSWindow init signature" if signature.to_i == 0
      invocation = @msg_id_ptr.call(cls("NSInvocation"), sel("invocationWithMethodSignature:"), signature)
      raise "cannot create NSInvocation" if invocation.to_i == 0
      @msg_void_ptr.call(invocation, sel("setTarget:"), hwnd)
      @msg_void_ptr.call(invocation, sel("setSelector:"), selector)
      keepalive = []
      rect = nsrect_buf(x, y, width, height)
      style_value = ulong_buf(style)
      backing_value = ulong_buf(backing)
      defer_value = bool_buf(defer.to_i != 0)
      keepalive.concat([rect, style_value, backing_value, defer_value])
      @msg_void_ptr_int.call(invocation, sel("setArgument:atIndex:"), rect, 2)
      @msg_void_ptr_int.call(invocation, sel("setArgument:atIndex:"), style_value, 3)
      @msg_void_ptr_int.call(invocation, sel("setArgument:atIndex:"), backing_value, 4)
      @msg_void_ptr_int.call(invocation, sel("setArgument:atIndex:"), defer_value, 5)
      @msg_void.call(invocation, sel("invoke"))
      result = ptr_buf(0)
      @msg_void_ptr.call(invocation, sel("getReturnValue:"), result)
      result[0, Fiddle::SIZEOF_VOIDP].unpack1(pointer_pack).to_i
    end

    def invoke_init_view(view, x, y, width, height)
      selector = sel("initWithFrame:")
      signature = @msg_id_ptr.call(view, sel("methodSignatureForSelector:"), selector)
      raise "missing NSView init signature" if signature.to_i == 0
      invocation = @msg_id_ptr.call(cls("NSInvocation"), sel("invocationWithMethodSignature:"), signature)
      raise "cannot create NSInvocation" if invocation.to_i == 0
      @msg_void_ptr.call(invocation, sel("setTarget:"), view)
      @msg_void_ptr.call(invocation, sel("setSelector:"), selector)
      rect = nsrect_buf(x, y, width, height)
      @msg_void_ptr_int.call(invocation, sel("setArgument:atIndex:"), rect, 2)
      @msg_void.call(invocation, sel("invoke"))
      result = ptr_buf(0)
      @msg_void_ptr.call(invocation, sel("getReturnValue:"), result)
      result[0, Fiddle::SIZEOF_VOIDP].unpack1(pointer_pack).to_i
    end

    def fallback_init_window(hwnd, x, y, width, height, style)
      hwnd = @msg_id.call(hwnd, sel("init"))
      return 0 if hwnd.to_i == 0
      @msg_void_int.call(hwnd, sel("setStyleMask:"), style)
      frame = ns_string(window_frame_descriptor(x, y, width, height))
      @msg_void_ptr.call(hwnd, sel("setFrameFromString:"), frame) if frame.to_i != 0
      hwnd
    end

    def current_run_loop
      @msg_id.call(cls("NSRunLoop"), sel("currentRunLoop"))
    end

    def run_once
      loop = current_run_loop
      return false if loop.to_i == 0
      @msg_bool_ptr_ptr.call(loop, sel("runMode:beforeDate:"), run_loop_mode, near_future)
      true
    rescue Exception
      false
    end

    def activate_running_application
      running = @msg_id.call(cls("NSRunningApplication"), sel("currentApplication"))
      return false if running.to_i == 0
      @msg_bool_int.call(running, sel("activateWithOptions:"), 3)
      true
    rescue Exception
      false
    end

    def frontmost_process_id
      workspace = @msg_id.call(cls("NSWorkspace"), sel("sharedWorkspace"))
      return -1 if workspace.to_i == 0
      application = @msg_id.call(workspace, sel("frontmostApplication"))
      return -1 if application.to_i == 0
      @msg_int.call(application, sel("processIdentifier")).to_i
    rescue Exception
      -1
    end

    def window_number(hwnd)
      return 0 if hwnd.to_i == 0
      @msg_int.call(hwnd, sel("windowNumber")).to_i
    rescue Exception
      0
    end

    def occlusion_state(hwnd)
      return -1 if hwnd.to_i == 0
      @msg_int.call(hwnd, sel("occlusionState")).to_i
    rescue Exception
      -1
    end

    def ns_string(text)
      @msg_id_cstr.call(cls("NSString"), sel("stringWithUTF8String:"), text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).b + "\0".b)
    end

    def new_obj(class_name)
      @msg_id.call(cls(class_name), sel("new"))
    end

    def alloc(class_name)
      @msg_id.call(cls(class_name), sel("alloc"))
    end

    def pointer_pack
      Fiddle::SIZEOF_VOIDP == 8 ? "Q" : "L!"
    end

    def ptr_buf(value = 0)
      bytes = [value.to_i].pack(pointer_pack)
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def ulong_buf(value)
      bytes = [value.to_i].pack("L!")
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def bool_buf(value)
      pointer = Fiddle::Pointer.malloc(1)
      pointer[0, 1] = [value ? 1 : 0].pack("C")
      pointer
    end

    def nsrect_buf(x, y, width, height)
      bytes = [x.to_f, y.to_f, width.to_f, height.to_f].pack("d4")
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def window_frame_descriptor(x, y, width, height)
      screen_width, screen_height = main_display_size
      "#{x.to_i} #{y.to_i} #{width.to_i} #{height.to_i} 0 0 #{screen_width} #{screen_height}"
    end

    def main_display_size
      return @main_display_size if defined?(@main_display_size)
      core_graphics = Fiddle.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
      main_display_id = Fiddle::Function.new(core_graphics["CGMainDisplayID"], [], Fiddle::TYPE_UINT).call
      pixels_wide = Fiddle::Function.new(core_graphics["CGDisplayPixelsWide"], [Fiddle::TYPE_UINT], Fiddle::TYPE_SIZE_T).call(main_display_id).to_i
      pixels_high = Fiddle::Function.new(core_graphics["CGDisplayPixelsHigh"], [Fiddle::TYPE_UINT], Fiddle::TYPE_SIZE_T).call(main_display_id).to_i
      @main_display_size = [pixels_wide > 0 ? pixels_wide : 1440, pixels_high > 0 ? pixels_high : 900]
    rescue Exception
      @main_display_size = [1440, 900]
    end

    def window_saved_frame(hwnd)
      string = @msg_id.call(hwnd, sel("stringWithSavedFrame"))
      objc_string(string)
    rescue Exception
      ""
    end

    def objc_string(object)
      return "" if object.to_i == 0
      pointer = @msg_id.call(object, sel("UTF8String"))
      return "" if pointer.to_i == 0
      bytes = +""
      memory = Fiddle::Pointer.new(pointer)
      index = 0
      while index < 4096
        byte = memory[index, 1].getbyte(0).to_i
        break if byte == 0
        bytes << byte.chr
        index += 1
      end
      bytes.force_encoding("UTF-8")
    rescue Exception
      ""
    end

    def active_space_collection_behavior
      NS_WINDOW_COLLECTION_BEHAVIOR_CAN_JOIN_ALL_SPACES
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

module EltenKeyboard
  VK_SHIFT = 0x10
  VK_CONTROL = 0x11
  VK_OPTION = 0x12
  VK_MENU = VK_OPTION
  VK_COMMAND_LEFT = 0x5B
  VK_COMMAND_RIGHT = 0x5C
  VK_CONTROL_LEFT = 0xA2
  VK_CONTROL_RIGHT = 0xA3
  VK_CONTEXT_MENU = 0x5D
  CG_EVENT_SOURCE_STATE_COMBINED_SESSION_STATE = 0
  STALE_REPEATABLE_KEY_SECONDS = 1.0
  STALE_MODIFIER_KEY_SECONDS = 15.0
  MODIFIER_KEYS = [VK_SHIFT, VK_CONTROL, VK_OPTION, VK_COMMAND_LEFT, VK_COMMAND_RIGHT, VK_CONTROL_LEFT, VK_CONTROL_RIGHT, VK_CONTEXT_MENU]

  MAC_TO_VK = {
    0 => 0x41, 1 => 0x53, 2 => 0x44, 3 => 0x46, 4 => 0x48, 5 => 0x47,
    6 => 0x5A, 7 => 0x58, 8 => 0x43, 9 => 0x56, 11 => 0x42, 12 => 0x51,
    13 => 0x57, 14 => 0x45, 15 => 0x52, 16 => 0x59, 17 => 0x54, 18 => 0x31,
    19 => 0x32, 20 => 0x33, 21 => 0x34, 22 => 0x36, 23 => 0x35, 24 => 0xBB,
    25 => 0x39, 26 => 0x37, 27 => 0xBD, 28 => 0x38, 29 => 0x30, 30 => 0xDD,
    31 => 0x4F, 32 => 0x55, 33 => 0xDB, 34 => 0x49, 35 => 0x50, 36 => 0x0D,
    37 => 0x4C, 38 => 0x4A, 39 => 0xDE, 40 => 0x4B, 41 => 0xBA, 42 => 0xDC,
    43 => 0xBC, 44 => 0xBF, 45 => 0x4E, 46 => 0x4D, 47 => 0xBE, 48 => 0x09,
    49 => 0x20, 50 => 0xC0, 51 => 0x08, 53 => 0x1B, 54 => VK_COMMAND_RIGHT, 55 => VK_COMMAND_LEFT,
    56 => 0x10, 57 => 0x14, 58 => 0x12, 59 => VK_CONTROL_LEFT, 60 => 0x10,
    62 => VK_CONTROL_RIGHT, 96 => 0x74, 97 => 0x75, 98 => 0x76, 99 => 0x72,
    100 => 0x77, 101 => 0x78, 103 => 0x7A, 109 => 0x79, 111 => 0x7B,
    114 => 0x2D, 115 => 0x24, 116 => 0x21, 117 => 0x2E, 118 => 0x73,
    119 => 0x23, 120 => 0x71, 121 => 0x22, 122 => 0x70, 123 => 0x25,
    124 => 0x27, 125 => 0x28, 126 => 0x26
  }

  CHAR_BY_VK = {
    0x20 => [" ", " "], 0x30 => ["0", ")"], 0x31 => ["1", "!"], 0x32 => ["2", "@"],
    0x33 => ["3", "#"], 0x34 => ["4", "$"], 0x35 => ["5", "%"], 0x36 => ["6", "^"],
    0x37 => ["7", "&"], 0x38 => ["8", "*"], 0x39 => ["9", "("], 0xBA => [";", ":"],
    0xBB => ["=", "+"], 0xBC => [",", "<"], 0xBD => ["-", "_"], 0xBE => [".", ">"],
    0xBF => ["/", "?"], 0xC0 => ["`", "~"], 0xDB => ["[", "{"], 0xDC => ["\\", "|"],
    0xDD => ["]", "}"], 0xDE => ["'", "\""]
  }

  class << self
    def fill_flags(buffer)
      initialize_state
      if !EltenWindow.keyboard_active?
        clear_state
        if buffer.respond_to?(:setbyte)
          for key in 0..255
            buffer.setbyte(key, 0)
          end
        end
        return 0
      end
      now = monotonic_time
      state = keyboard_state
      events = key_events
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
      for key in 0..255
        buffer.setbyte(key, flags[key]) if buffer.respond_to?(:setbyte)
      end
      0
    end

    def sync_physical_state
      initialize_state
      if !EltenWindow.keyboard_active?
        clear_state
        return true
      end
      state = keyboard_state
      now = monotonic_time
      for key in 0..255
        down = key_down?(state, key)
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

    def stale_suppressed?(key)
      @stale_suppressed ||= Array.new(256, false)
      @stale_suppressed[key.to_i & 0xff] == true
    rescue Exception
      false
    end

    def physical_key_down?(key)
      mac_keys = mac_keys_for_virtual_key(key)
      return nil if mac_keys.empty?
      mac_keys.any? { |mac_key| cg_event_source_key_state.call(CG_EVENT_SOURCE_STATE_COMBINED_SESSION_STATE, mac_key.to_i).to_i != 0 }
    rescue Exception
      nil
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

    def initialize_state
      @last_down ||= Array.new(256, false)
      @next_repeat ||= Array.new(256, 0.0)
      @last_down_event ||= Array.new(256)
      @stale_suppressed ||= Array.new(256, false)
      @repeat_delay ||= 0.45
      @repeat_interval ||= 1.0 / 30.0
    end

    def keyboard_state
      return EltenWindow.keyboard_state.to_s
      physical = physical_keyboard_state
      return physical if physical != nil
      capture_keyboard_state_raw
    rescue Exception
      "\0" * 256
    end

    def physical_keyboard_state
      state = "\0" * 256
      mac_keys_by_virtual_key.each do |virtual_key, mac_keys|
        next if virtual_key < 0 || virtual_key > 255
        if mac_keys.any? { |mac_key| cg_event_source_key_state.call(CG_EVENT_SOURCE_STATE_COMBINED_SESSION_STATE, mac_key.to_i).to_i != 0 }
          state.setbyte(virtual_key, 0x80)
        end
      end
      state
    rescue Exception
      nil
    end

    def capture_keyboard_state_raw
      return OSXWindowNative.keyboard_state if defined?(OSXWindowNative) && OSXWindowNative.respond_to?(:keyboard_state)
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
          state.setbyte(key, byte | 0x80)
          flags[key] |= 1
          @last_down_event[key] = now
          @stale_suppressed[key] = false
        elsif down == :repeat
          state.setbyte(key, byte | 0x80)
          @last_down_event[key] = now
          @stale_suppressed[key] = false
        else
          state.setbyte(key, byte & 0x7f)
          flags[key] |= 2
          @last_down_event[key] = nil
          @stale_suppressed[key] = false
        end
      end
      flags
    rescue Exception
      Array.new(256, 0)
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
      return OSXWindowNative.translated_character_for_key(key) if defined?(OSXWindowNative) && OSXWindowNative.respond_to?(:translated_character_for_key)
      ""
    rescue Exception
      ""
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue Exception
      Time.now.to_f
    end

    def repeatable_key?(key)
      !MODIFIER_KEYS.include?(key)
    end

    def stale_key_down?(key, now)
      return true if @stale_suppressed[key] == true
      return false if @last_down[key] != true
      last = @last_down_event[key]
      return false if last == nil
      return false if now - last.to_f <= stale_key_timeout(key)
      physical_virtual_key_down?(key) == false
    rescue Exception
      false
    end

    def stale_key_timeout(key)
      repeatable_key?(key) ? STALE_REPEATABLE_KEY_SECONDS : STALE_MODIFIER_KEY_SECONDS
    end

    def physical_virtual_key_down?(key)
      physical_key_down?(key)
    end

    def mac_keys_for_virtual_key(key)
      @mac_keys_by_virtual_key ||= begin
        map = Hash.new { |hash, virtual_key| hash[virtual_key] = [] }
        MAC_TO_VK.each { |mac_key, virtual_key| map[virtual_key.to_i & 0xff] << mac_key.to_i }
        map
      end
      @mac_keys_by_virtual_key[key.to_i & 0xff] || []
    end

    def cg_event_source_key_state
      return @cg_event_source_key_state if defined?(@cg_event_source_key_state) && @cg_event_source_key_state != nil
      @core_graphics ||= Fiddle.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
      bool_type = Fiddle.const_defined?(:TYPE_BOOL) ? Fiddle::TYPE_BOOL : Fiddle::TYPE_CHAR
      @cg_event_source_key_state = Fiddle::Function.new(@core_graphics["CGEventSourceKeyState"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT], bool_type)
    end

    def suppress_stale_key(key)
      @stale_suppressed[key] = true
    rescue Exception
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
      @window_thread ||= Thread.current
      if @window_created != true
        @window_created = true
        hidden = $elten_start_hidden == true
        native = OSXWindowNative.create(app_window_title, hidden)
        @native_window = native.to_i != 0
        @hwnd = @native_window ? native.to_i : 1
        @visible = !hidden
      end
      $wnd = @hwnd
      @hwnd
    end

    def show(_command = SW_SHOW)
      ensure_window
      OSXWindowNative.show(@hwnd) if @native_window == true
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
      OSXWindowNative.hide(@hwnd) if @native_window == true
      @visible = false
      true
    end

    def focus(_hwnd = nil)
      show
      true
    end

    def message_box(text, caption = "Elten", _flags = 0, _owner = nil)
      ensure_window
      return 1 if @native_window == true && OSXWindowNative.message_box(text, caption)
      0
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
      !OSXWindowNative.visible?(@hwnd)
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
      return OSXWindowNative.keyboard_active?(@hwnd) if @native_window == true
      false
    end

    def pump_messages
      if @native_window == true
        OSXWindowNative.pump if OSXWindowNative.app_thread?
      else
        capture_keyboard_state
      end
      true
    end

    def activation_input_blocked?
      return false if @native_window != true || !defined?(OSXWindowNative)
      OSXWindowNative.consume_keyboard_reset
    rescue Exception
      false
    end

    def close_requested?
      @close_requested == true
    end

    def consume_close_request
      requested = @close_requested == true
      @close_requested = false
      native_requested = @native_window == true && defined?(OSXWindowNative) && OSXWindowNative.respond_to?(:consume_close_request) && OSXWindowNative.consume_close_request
      requested || native_requested
    end

    def consume_quit_shortcut_request
      return false unless @native_window == true && defined?(OSXWindowNative) && OSXWindowNative.respond_to?(:consume_quit_shortcut_request)
      OSXWindowNative.consume_quit_shortcut_request
    rescue Exception
      false
    end

    def consume_main_menu_request
      return false unless @native_window == true && defined?(OSXWindowNative) && OSXWindowNative.respond_to?(:consume_main_menu_request)
      OSXWindowNative.consume_main_menu_request
    rescue Exception
      false
    end

    def consume_minimize_request
      requested = @minimize_requested == true
      @minimize_requested = false
      requested
    end

    def update_messages
      pump_messages
      true
    end

    def service_window_update
      update_messages
    end

    def keyboard_state
      return OSXWindowNative.keyboard_state.to_s if @native_window == true && defined?(OSXWindowNative)
      @keyboard_state ||= ("\0" * 256)
    end

    def clear_input_state
      @keyboard_state = "\0" * 256
      OSXWindowNative.clear_input_state if @native_window == true && defined?(OSXWindowNative)
      EltenKeyboard.clear_state
      true
    end

    def post_window_action(_wait = false, &block)
      block == nil ? false : block.call
    end

    def window_thread?
      @window_thread ||= (($mainthread != nil) ? $mainthread : Thread.current)
      Thread.current == @window_thread
    end

    def begin_input_frame
      return true if @native_window == true
      update_messages
      true
    end

    def character_input_supported?
      false
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

    def take_character(_multi = false)
      ""
    end

    def consume_key_events
      return OSXWindowNative.consume_key_events if @native_window == true && defined?(OSXWindowNative) && OSXWindowNative.respond_to?(:consume_key_events)
      []
    rescue Exception
      []
    end

    def run_appkit_main_loop(worker_thread = nil)
      OSXWindowNative.run_main_loop(worker_thread) if @native_window == true
    end

    def request_appkit_exit
      OSXWindowNative.request_exit if defined?(OSXWindowNative)
      true
    end

    private

    def capture_keyboard_state
      if !keyboard_active?
        @keyboard_state = "\0" * 256
        return
      end
      state = EltenKeyboard.send(:capture_keyboard_state_raw)
      @keyboard_state = state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
    rescue Exception
      @keyboard_state = "\0" * 256
    end

    def apple_string(text)
      text.to_s.inspect
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
