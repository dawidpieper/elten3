# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

# VoiceOver braille bridge for macOS.
# Uses ApplicationServices AXPostNotification with kAXAnnouncementRequestedNotification
# so that VoiceOver speaks and mirrors text on any connected Braille display.

module OSXVoiceOverBridge
  PTR  = Fiddle::TYPE_VOIDP
  INT  = Fiddle::TYPE_INT
  VOID = Fiddle::TYPE_VOID

  class << self
    def available?
      app_services != nil && objc != nil
    rescue Exception
      false
    end

    def voiceover_running?
      return false unless available?
      ax_is_voiceover_enabled.call != 0
    rescue Exception
      false
    end

    # Send text as a VoiceOver announcement.
    # VoiceOver will both speak it and show it on any connected Braille display.
    def announce(text)
      return false unless voiceover_running?
      app_el = ax_ui_element_create_application.call(Process.pid)
      return false if app_el.to_i == 0
      info = build_announcement_dict(text.to_s)
      ax_post_notification.call(app_el, nsstring("AXAnnouncementRequested"), info)
      true
    rescue Exception => e
      log_warning("announce failed: #{e.class}: #{e.message}")
      false
    end

    private

    def app_services
      return @app_services if defined?(@app_services)
      # AppKit must be loaded first so NSObject etc. are available
      Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit") rescue nil
      @app_services = Fiddle.dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
    rescue Exception
      @app_services = nil
    end

    def objc
      return @objc if defined?(@objc)
      @objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    rescue Exception
      @objc = nil
    end

    # --- Objective-C helpers (same pattern as OSXSpeechBridge) ---

    def objc_msg_send(types, ret)
      @objc_msg_send ||= {}
      key = [types, ret]
      @objc_msg_send[key] ||= Fiddle::Function.new(objc["objc_msgSend"], [PTR, PTR] + types, ret)
    end

    def objc_get_class
      @objc_get_class ||= Fiddle::Function.new(objc["objc_getClass"], [PTR], PTR)
    end

    def sel_register_name
      @sel_register_name ||= Fiddle::Function.new(objc["sel_registerName"], [PTR], PTR)
    end

    def cls(name)
      objc_get_class.call(name.to_s)
    end

    def sel(name)
      sel_register_name.call(name.to_s)
    end

    def send_id(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, PTR).call(receiver, sel(selector), *args)
    end

    def send_void(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, VOID).call(receiver, sel(selector), *args)
    end

    def nsstring(text)
      utf8 = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
      send_id(cls("NSString"), "stringWithUTF8String:", utf8.b + "\0", [PTR])
    end

    def nsnumber_int(value)
      send_id(cls("NSNumber"), "numberWithInt:", value.to_i, [INT])
    end

    # Build NSDictionary: { AXAnnouncement => text, AXPriority => 90 }
    # AXPriority 90 = NSAccessibilityPriorityHigh (interrupts current VoiceOver output)
    def build_announcement_dict(text)
      keys   = ns_mutable_array([nsstring("AXAnnouncement"), nsstring("AXPriority")])
      values = ns_mutable_array([nsstring(text), nsnumber_int(90)])
      send_id(cls("NSDictionary"), "dictionaryWithObjects:forKeys:count:",
              values, keys, 2, [PTR, PTR, PTR])
    end

    def ns_mutable_array(items)
      array = send_id(cls("NSMutableArray"), "array")
      items.each do |item|
        send_void(array, "addObject:", item, [PTR])
      end
      array
    end

    # --- ApplicationServices functions ---

    def ax_is_voiceover_enabled
      @ax_is_voiceover_enabled ||= Fiddle::Function.new(
        app_services["AXIsVoiceOverEnabled"], [], INT
      )
    end

    def ax_ui_element_create_application
      @ax_ui_element_create_application ||= Fiddle::Function.new(
        app_services["AXUIElementCreateApplication"], [INT], PTR
      )
    end

    def ax_post_notification
      @ax_post_notification ||= Fiddle::Function.new(
        app_services["AXPostNotification"], [PTR, PTR, PTR], INT
      )
    end

    def log_warning(msg)
      Log.warning("OSXVoiceOverBridge: #{msg}") if defined?(Log)
    rescue Exception
    end
  end
end

# SpeechOutput subclass that provides Braille output via VoiceOver on macOS.
# It has no speech voices – it is purely a Braille channel.
class OSXVoiceOverOutput < SpeechOutput
  class << self
    def available?
      OSXVoiceOverBridge.available?
    rescue Exception
      false
    end

    def usable?
      available? && OSXVoiceOverBridge.voiceover_running?
    rescue Exception
      false
    end

    # Do not auto-select as speech output
    def default?
      false
    end

    # No speech voices – this output only handles Braille
    def voices
      []
    end

    def braille_supported?
      true
    end

    def braille(_text, _pos = nil, _push = false, _type = 0, _index = nil, _cursor = nil)
      return if Configuration.enablebraille == 0
      return unless usable?
      OSXVoiceOverBridge.announce(_text.to_s)
    rescue Exception => e
      Log.warning("OSXVoiceOverOutput.braille: #{e.class}: #{e.message}") if defined?(Log)
    end

    def braille_alert(text)
      return if Configuration.enablebraille == 0
      return unless usable?
      OSXVoiceOverBridge.announce(text.to_s)
    rescue Exception => e
      Log.warning("OSXVoiceOverOutput.braille_alert: #{e.class}: #{e.message}") if defined?(Log)
    end
  end
end
