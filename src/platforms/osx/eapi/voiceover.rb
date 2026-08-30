# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

# VoiceOver bridge for macOS.
# Uses ApplicationServices AXPostNotification with AXAnnouncementRequested
# so that VoiceOver speaks the text and mirrors it on any connected Braille display.

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

    # Send text to VoiceOver. VoiceOver speaks it and mirrors it on Braille displays.
    # Priority 90 (NSAccessibilityPriorityHigh) interrupts the current VoiceOver output.
    def announce(text, priority: 90)
      return false unless voiceover_running?
      app_el = ax_ui_element_create_application.call(Process.pid)
      return false if app_el.to_i == 0
      info = build_announcement_dict(text.to_s, priority)
      ax_post_notification.call(app_el, nsstring("AXAnnouncementRequested"), info)
      true
    rescue Exception => e
      log_warning("announce failed: #{e.class}: #{e.message}")
      false
    end

    private

    def app_services
      return @app_services if defined?(@app_services)
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

    def build_announcement_dict(text, priority)
      keys   = ns_mutable_array([nsstring("AXAnnouncement"), nsstring("AXPriority")])
      values = ns_mutable_array([nsstring(text), nsnumber_int(priority)])
      send_id(cls("NSDictionary"), "dictionaryWithObjects:forKeys:count:",
              values, keys, 2, [PTR, PTR, PTR])
    end

    def ns_mutable_array(items)
      array = send_id(cls("NSMutableArray"), "array")
      items.each { |item| send_void(array, "addObject:", item, [PTR]) }
      array
    end


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

    # Simulate a Control key press+release via CoreGraphics to interrupt VoiceOver.
    # VoiceOver treats the Control key as its universal "stop speaking" command.
    # kCGSessionEventTap scopes the event to the current login session rather than
    # the raw HID stream, so it cannot reach apps in other user sessions.
    def stop_speech
      return false unless voiceover_running?
      cg = core_graphics
      return false if cg == nil
      kVK_Control          = 0x3B
      kCGSessionEventTap   = 1
      key_down = cg_create_kb_event.call(0, kVK_Control, 1)
      key_up   = cg_create_kb_event.call(0, kVK_Control, 0)
      cg_post_event.call(kCGSessionEventTap, key_down)
      cg_post_event.call(kCGSessionEventTap, key_up)
      cf_release.call(key_down)
      cf_release.call(key_up)
      true
    rescue Exception => e
      log_warning("stop_speech failed: #{e.class}: #{e.message}")
      false
    end

    def core_graphics
      return @core_graphics if defined?(@core_graphics)
      @core_graphics = Fiddle.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    rescue Exception
      @core_graphics = nil
    end

    def cg_create_kb_event
      @cg_create_kb_event ||= Fiddle::Function.new(core_graphics["CGEventCreateKeyboardEvent"], [PTR, INT, INT], PTR)
    end

    def cg_post_event
      @cg_post_event ||= Fiddle::Function.new(core_graphics["CGEventPost"], [INT, PTR], VOID)
    end

    def cf_release
      @cf_release ||= Fiddle::Function.new(
        Fiddle.dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")["CFRelease"],
        [PTR], VOID
      )
    end

    def log_warning(msg)
      Log.warning("OSXVoiceOverBridge: #{msg}") if defined?(Log)
    rescue Exception
    end
  end
end

# SpeechOutput that routes speech through VoiceOver via the Accessibility API.
# When selected, VoiceOver speaks the text with its own voice and simultaneously
# shows it on any connected Braille display — no separate Braille configuration needed.
class OSXVoiceOverOutput < SpeechOutput
  VOICE_ID   = "voiceover://system"
  VOICE_NAME = "VoiceOver"


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

    # Never selected automatically — user must choose it explicitly.
    def default?
      false
    end

    def voices
      return [] unless available?
      [SpeechOutput::Voice.new(
        id:     VOICE_ID,
        name:   VOICE_NAME,
        output: self,
        native: nil
      )]
    end

    def apply_voice(_voice)
      true
    end

    def speak_text(text, method: 1, spelling: false, _interrupt: true, _pitch: 50)
      return 1 unless usable?
      text = text.to_s.chars.join(" ") if spelling
      OSXVoiceOverBridge.announce(text.to_s)
      0
    rescue Exception => e
      Log.warning("OSXVoiceOverOutput.speak_text: #{e.class}: #{e.message}") if defined?(Log)
      1
    end

    def stop
      OSXVoiceOverBridge.stop_speech if usable?
      0
    rescue Exception
      1
    end

    # VoiceOver manages its own speaking state; we cannot query it externally.
    def speaking?
      false
    end

    def braille_supported?
      true
    end

    # Braille output is automatic: VoiceOver mirrors speech to Braille displays.
    def braille(text, _pos = nil, _push = false, _type = 0, _index = nil, _cursor = nil)
      return unless Configuration.enablebraille && usable?
      OSXVoiceOverBridge.announce(text.to_s)
    rescue Exception => e
      Log.warning("OSXVoiceOverOutput.braille: #{e.class}: #{e.message}") if defined?(Log)
    end

    def braille_alert(text)
      return unless Configuration.enablebraille && usable?
      OSXVoiceOverBridge.announce(text.to_s)
    rescue Exception => e
      Log.warning("OSXVoiceOverOutput.braille_alert: #{e.class}: #{e.message}") if defined?(Log)
    end

    # VoiceOver controls rate, volume, and pitch through its own settings.
    def rate_supported?
      false
    end

    def volume_supported?
      false
    end

    def pitch_supported?
      false
    end

    def pause_supported?
      false
    end

    def indexed_supported?
      false
    end

    def spelling_supported?
      true
    end
  end
end
