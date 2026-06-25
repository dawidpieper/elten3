# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

class Runner
  include EltenAPI

  class Timer
    attr_reader :interval, :repeat, :phase

    def initialize(interval, repeat: false, immediate: false, phase: :timer, dynamic: false, &block)
      raise ArgumentError, "block is required" if block == nil
      @interval = interval
      @repeat = repeat == true
      @phase = normalize_phase(phase)
      @dynamic = dynamic == true
      @block = block
      @cancelled = false
      @pending = false
      @next_at = monotonic_time + (immediate == true ? 0.0 : interval_seconds)
    end

    def cancel
      @cancelled = true
      @pending = false
    end

    def cancelled?
      @cancelled == true
    end

    def due?(time)
      !cancelled? && @pending != true && time.to_f >= @next_at.to_f
    end

    def fire(runner, time)
      return if cancelled?
      if @phase == :next_tick
        @pending = true
        runner.__send__(:queue_next_tick_callback, self, @block)
      else
        reschedule_after(runner.__send__(:invoke_callback, @block, time), time)
      end
    end

    def reschedule_after(result, time)
      return if cancelled?
      @pending = false
      if @dynamic == true
        cancel if result == nil || result == false
        @next_at = time.to_f + interval_seconds(result) if !cancelled?
      elsif @repeat == true
        @next_at = time.to_f + interval_seconds
      else
        cancel
      end
    end

    private

    def interval_seconds(interval = @interval)
      if interval.is_a?(Range)
        range_start = interval.begin.to_f
        range_end = interval.end.to_f
        range_end -= Float::EPSILON if interval.exclude_end?
        return range_start if range_end <= range_start
        return rand * (range_end - range_start) + range_start
      end
      interval.to_f
    end

    def normalize_phase(phase)
      phase = phase.to_sym if phase.respond_to?(:to_sym)
      return :timer if phase == nil || phase == :timer
      return :next_tick if phase == :next_tick
      raise ArgumentError, "unsupported timer phase: #{phase.inspect}"
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class Action
    attr_reader :name, :hold_keys, :press_keys

    def initialize(name, hold: [], press: [], keys: nil)
      @name = name.to_sym
      @hold_keys = normalize_keys(hold)
      @press_keys = normalize_keys(keys == nil ? press : keys)
    end

    def held?(runner)
      @hold_keys.any? { |key| runner.__send__(:key_held?, key) } || @press_keys.any? { |key| runner.__send__(:key_held?, key) }
    end

    def pressed?(runner)
      @press_keys.any? { |key| runner.__send__(:key_first_pressed?, key) } || @hold_keys.any? { |key| runner.__send__(:key_first_pressed?, key) }
    end

    private

    def normalize_keys(keys)
      Array(keys).flatten.compact.map { |key| normalize_key(key) }
    end

    def normalize_key(key)
      return key if key.is_a?(Integer)
      symbol = key.to_sym
      name = symbol.to_s
      return symbol if name.start_with?("key_")
      return "key_#{name}".to_sym if name.length != 1
      name.upcase.ord
    end
  end

  class Cooldown
    attr_accessor :interval

    def initialize(interval = 0.0)
      @interval = interval.to_f
      @last_at = nil
      @blocked_until = 0.0
    end

    def ready?(time = monotonic_time)
      time = time.to_f
      return false if time < @blocked_until.to_f
      @last_at == nil || time >= @last_at.to_f + @interval.to_f
    end

    def use(time = monotonic_time)
      return false if !ready?(time)
      @last_at = time.to_f
      true
    end

    def reset
      @last_at = nil
      @blocked_until = 0.0
      self
    end

    def block_for(seconds, time = monotonic_time)
      @blocked_until = [@blocked_until.to_f, time.to_f + seconds.to_f].max
      self
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  class TimedFlag
    def initialize
      @active_until = 0.0
    end

    def enable_for(seconds, time = monotonic_time)
      @active_until = [@active_until.to_f, time.to_f + seconds.to_f].max
      self
    end

    def disable
      @active_until = 0.0
      self
    end

    def active?(time = monotonic_time)
      time.to_f < @active_until.to_f
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  attr_reader :result
  attr_accessor :frame_interval

  def initialize(frame_interval: 0.0)
    @frame_interval = frame_interval.to_f
    @timers = []
    @key_handlers = []
    @action_handlers = []
    @actions = {}
    @cooldowns = {}
    @timed_flags = {}
    @tick_handlers = []
    @next_tick_callbacks = []
    @running = false
    @result = nil
    @next_tick_at = nil
  end

  def after(delay, phase: :timer, &block)
    add_timer(delay, repeat: false, phase: phase, &block)
  end

  def every(interval, immediate: false, phase: :timer, &block)
    add_timer(interval, repeat: true, immediate: immediate, phase: phase, &block)
  end

  def schedule(delay, phase: :timer, &block)
    add_timer(delay, repeat: false, phase: phase, dynamic: true, &block)
  end

  def on_key(key, repeat: false, &block)
    raise ArgumentError, "block is required" if block == nil
    @key_handlers << { :key => key, :repeat => repeat == true, :block => block }
    self
  end

  def action(name, hold: [], press: [], keys: nil)
    @actions[name.to_sym] = Action.new(name, hold: hold, press: press, keys: keys)
    self
  end

  def on_action(name, repeat: false, &block)
    raise ArgumentError, "block is required" if block == nil
    @action_handlers << { :name => name.to_sym, :repeat => repeat == true, :block => block }
    self
  end

  def action_held?(name)
    action = @actions[name.to_sym]
    action != nil && action.held?(self)
  end

  def action_pressed?(name)
    action = @actions[name.to_sym]
    action != nil && action.pressed?(self)
  end

  def cooldown(name, interval = nil)
    key = name.to_sym
    @cooldowns[key] ||= Cooldown.new(interval || 0.0)
    @cooldowns[key].interval = interval.to_f if interval != nil
    @cooldowns[key]
  end

  def timed_flag(name)
    @timed_flags[name.to_sym] ||= TimedFlag.new
  end

  def on_tick(&block)
    raise ArgumentError, "block is required" if block == nil
    @tick_handlers << block
    self
  end

  def next_tick(&block)
    raise ArgumentError, "block is required" if block == nil
    queue_next_tick_callback(nil, block)
    self
  end

  def run(&block)
    on_tick(&block) if block != nil
    raise RuntimeError, "Runner has no handlers" if @tick_handlers.empty? && @timers.empty? && @key_handlers.empty? && @action_handlers.empty?
    @running = true
    @result = nil
    @next_tick_at = monotonic_time
    while @running == true
      loop_update
      time = monotonic_time
      process_key_handlers(time)
      process_action_handlers(time) if @running == true
      process_timers(time) if @running == true
      process_tick(time) if @running == true
    end
    @result
  end

  def stop(result = nil)
    @result = result
    @running = false
    result
  end

  def running?
    @running == true
  end

  private

  def add_timer(interval, repeat:, immediate: false, phase: :timer, dynamic: false, &block)
    timer = Timer.new(interval, repeat: repeat, immediate: immediate, phase: phase, dynamic: dynamic, &block)
    @timers << timer
    timer
  end

  def queue_next_tick_callback(timer, block)
    @next_tick_callbacks << { :timer => timer, :block => block }
    self
  end

  def process_key_handlers(time)
    @key_handlers.each do |handler|
      key = handler[:key]
      pressed = handler[:repeat] == true ? key_pressed?(key) : key_first_pressed?(key)
      next if pressed != true
      invoke_callback(handler[:block], time, key)
      break if @running != true
    end
  end

  def process_action_handlers(time)
    @action_handlers.each do |handler|
      action = @actions[handler[:name]]
      next if action == nil
      pressed = handler[:repeat] == true ? action.held?(self) : action.pressed?(self)
      next if pressed != true
      invoke_callback(handler[:block], time, handler[:name])
      break if @running != true
    end
  end

  def process_timers(time)
    @timers.delete_if(&:cancelled?)
    @timers.each do |timer|
      next if !timer.due?(time)
      timer.fire(self, time)
      break if @running != true
    end
    @timers.delete_if(&:cancelled?)
  end

  def process_tick(time)
    return if @tick_handlers.empty? && @next_tick_callbacks.empty?
    return if @frame_interval > 0.0 && time.to_f < @next_tick_at.to_f
    @next_tick_at = time.to_f + @frame_interval
    callbacks = @next_tick_callbacks
    @next_tick_callbacks = []
    @tick_handlers.each do |handler|
      invoke_callback(handler, time)
      break if @running != true
    end
    return if @running != true
    callbacks.each do |handler|
      result = invoke_callback(handler[:block], time)
      handler[:timer].reschedule_after(result, time) if handler[:timer] != nil
      break if @running != true
    end
  end

  def invoke_callback(callback, time, *args)
    if callback.arity == 0
      callback.call
    elsif callback.arity == 1
      callback.call(self)
    elsif args.empty?
      callback.call(self, time)
    else
      callback.call(self, time, *args)
    end
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
