# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module KeyboardState
    Result = Struct.new(:pressed, :held, :released, :first_pressed, :repeated, :state, keyword_init: true)

    MODIFIER_KEYS = [0x10, 0x11, 0x12, 0x14, 0x5B, 0x5C, 0x5D]
    DEFAULT_REPEAT_DELAY = 0.45
    DEFAULT_REPEAT_INTERVAL = 1.0 / 30.0

    class << self
      def update(raw_state:, events: [], synthetic_keys: [], active: true, now: nil, pressed_implies_held: true)
        initialize_state
        return reset_result if active != true

        @tick_serial += 1
        current_tick = @tick_serial
        now ||= monotonic_time
        down = normalize_state(raw_state)
        event_pressed = Array.new(256, false)
        event_released = Array.new(256, false)
        event_repeated = Array.new(256, false)

        Array(events).each do |event|
          key, state = event
          key = key.to_i
          next if key < 0 || key > 255
          case state
          when true
            down[key] = true
            event_pressed[key] = true
          when :repeat
            down[key] = true
            event_repeated[key] = true
          when :held
            down[key] = true
          else
            down[key] = false
            event_released[key] = true
          end
        end

        Array(synthetic_keys).each do |key|
          key = key.to_i
          next if key < 0 || key > 255
          down[key] = true
          event_pressed[key] = true
        end

        pressed = Array.new(256, false)
        held = Array.new(256, false)
        released = Array.new(256, false)
        first_pressed = Array.new(256, false)
        repeated = Array.new(256, false)
        frame_active = false

        for key in 0..255
          was_down = @held[key] == true
          is_down = down[key] == true
          held[key] = is_down

          if event_released[key] || (was_down && !is_down)
            released[key] = true
            @next_repeat[key] = 0.0
          end

          if event_pressed[key] && !was_down
            pressed[key] = true
            first_pressed[key] = true
            @next_repeat[key] = is_down ? now + @repeat_delay : 0.0
          elsif is_down && !was_down
            pressed[key] = true
            first_pressed[key] = true
            @next_repeat[key] = now + @repeat_delay
          elsif is_down && repeatable_key?(key)
            if event_repeated[key] || now >= @next_repeat[key].to_f
              repeated[key] = true
              @next_repeat[key] = next_repeat_time(now, @next_repeat[key].to_f)
            end
          elsif !is_down
            @next_repeat[key] = 0.0
          end
        end

        action_pressed = Array.new(256, false)
        for key in 0..255
          action_pressed[key] = pressed[key] == true || repeated[key] == true
          if action_pressed[key] == true
            if @last_pressed_tick[key].to_i == current_tick - 1
              action_pressed[key] = false
              pressed[key] = false
              first_pressed[key] = false
              repeated[key] = false
            else
              @last_pressed_tick[key] = current_tick
            end
          end
          held[key] = true if pressed_implies_held == true && action_pressed[key] == true
          frame_active = true if action_pressed[key] == true || released[key] == true || first_pressed[key] == true || repeated[key] == true
        end

        @held = held.dup
        @held_any = held.include?(true)
        @current_active = frame_active
        @current = Result.new(
          pressed: action_pressed,
          held: held,
          released: released,
          first_pressed: first_pressed,
          repeated: repeated,
          state: state_string(held)
        )
      rescue Exception => e
        Log.error("Keyboard state update failed: #{e.class}: #{e.message}")
        reset_result
      end

      def current
        initialize_state
        @current ||= reset_result
      end

      def pressed?(key)
        code = key.to_i & 0xff
        current.pressed[code] == true
      rescue Exception
        false
      end

      def held?(key)
        current.held[key.to_i & 0xff] == true
      rescue Exception
        false
      end

      def released?(key)
        current.released[key.to_i & 0xff] == true
      rescue Exception
        false
      end

      def first_pressed?(key)
        current.first_pressed[key.to_i & 0xff] == true
      rescue Exception
        false
      end

      def repeated?(key)
        current.repeated[key.to_i & 0xff] == true
      rescue Exception
        false
      end

      def any_pressed?
        current.pressed.include?(true)
      rescue Exception
        false
      end

      def any_held?
        initialize_state
        @held_any == true
      rescue Exception
        false
      end

      def idle?
        initialize_state
        state = current
        state.held.include?(true) != true &&
          state.pressed.include?(true) != true &&
          state.released.include?(true) != true &&
          state.first_pressed.include?(true) != true &&
          state.repeated.include?(true) != true
      rescue Exception
        false
      end

      def clear_current_frame
        initialize_state
        empty = Array.new(256, false)
        held = @held.dup
        @held_any = held.include?(true)
        @current_active = false
        @current = Result.new(
          pressed: empty.dup,
          held: held,
          released: empty.dup,
          first_pressed: empty.dup,
          repeated: empty.dup,
          state: state_string(held)
        )
        true
      end

      def reset
        initialize_state
        @held = Array.new(256, false)
        @next_repeat = Array.new(256, 0.0)
        @last_pressed_tick = Array.new(256, -1000)
        @tick_serial = 0
        @held_any = false
        @current_active = false
        @current = nil
        true
      end

      private

      def initialize_state
        @held ||= Array.new(256, false)
        @next_repeat ||= Array.new(256, 0.0)
        @last_pressed_tick ||= Array.new(256, -1000)
        @tick_serial ||= 0
        @held_any = @held.include?(true) if @held_any == nil
        @current_active = false if @current_active == nil
        @repeat_delay ||= DEFAULT_REPEAT_DELAY
        @repeat_interval ||= DEFAULT_REPEAT_INTERVAL
      end

      def reset_result
        reset
        empty = Array.new(256, false)
        @held_any = false
        @current_active = false
        Result.new(
          pressed: empty.dup,
          held: empty.dup,
          released: empty.dup,
          first_pressed: empty.dup,
          repeated: empty.dup,
          state: "\0" * 256
        )
      end

      def normalize_state(raw_state)
        bytes = raw_state.to_s.byteslice(0, 256).to_s.ljust(256, "\0")
        state = Array.new(256, false)
        for key in 0..255
          state[key] = (bytes.getbyte(key).to_i & 0x80) != 0
        end
        state
      end

      def state_string(held)
        bytes = "\0" * 256
        for key in 0..255
          bytes.setbyte(key, held[key] ? 0x80 : 0)
        end
        bytes
      end

      def repeatable_key?(key)
        !MODIFIER_KEYS.include?(key.to_i)
      end

      def next_repeat_time(now, previous)
        target = previous.to_f
        target = now if target <= 0.0 || target < now - 1.0
        target += @repeat_interval while target <= now
        target
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue Exception
        Time.now.to_f
      end
    end
  end
end
