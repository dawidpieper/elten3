# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

class Runner
  include EltenAPI

  ACTION_PHASES = [:start, :update, :finish].freeze

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

    def released?(runner)
      @press_keys.any? { |key| runner.__send__(:key_released?, key) } || @hold_keys.any? { |key| runner.__send__(:key_released?, key) }
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

  class Stopwatch
    attr_reader :state

    def initialize(clock: nil, autostart: false)
      @clock = clock || lambda { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @elapsed = 0.0
      @started_at = nil
      @state = :stopped
      start if autostart == true
    end

    def start
      return self if running? || paused?
      @elapsed = 0.0
      @started_at = current_time
      @state = :running
      self
    end

    def pause
      return self if !running?
      @elapsed = elapsed_at(current_time)
      @started_at = nil
      @state = :paused
      self
    end

    def resume
      return self if !paused?
      @started_at = current_time
      @state = :running
      self
    end

    def stop
      if running?
        @elapsed = elapsed_at(current_time)
        @started_at = nil
      end
      @state = :stopped
      self
    end

    def elapsed
      running? ? elapsed_at(current_time) : @elapsed
    end

    def running?
      @state == :running
    end

    def paused?
      @state == :paused
    end

    def stopped?
      @state == :stopped
    end

    private

    def current_time
      @clock.call.to_f
    end

    def elapsed_at(time)
      @elapsed + [time.to_f - @started_at.to_f, 0.0].max
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
    @action_states = {}
    @phased_action_names = []
    @cooldowns = {}
    @timed_flags = {}
    @stopwatches = []
    @tick_handlers = []
    @next_tick_callbacks = []
    @stop_handlers = []
    @managed_resources = EltenAPI::Resources::Registry.new
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
    @key_handlers << { :key => key, :event => :down, :repeat => repeat == true, :block => block }
    self
  end

  def on_key_down(key, repeat: false, &block)
    on_key(key, repeat: repeat, &block)
  end

  def on_key_released(key, &block)
    raise ArgumentError, "block is required" if block == nil
    @key_handlers << { :key => key, :event => :released, :repeat => false, :block => block }
    self
  end

  alias on_key_up on_key_released

  def action(name, hold: [], press: [], keys: nil)
    key = name.to_sym
    @action_states.delete(key)
    @actions[key] = Action.new(name, hold: hold, press: press, keys: keys)
    self
  end

  def on_action(name, repeat: false, phase: nil, guard: nil, cooldown: nil, initially_blocked_for: 0.0, &block)
    raise ArgumentError, "block is required" if block == nil
    phase = normalize_action_phase(phase)
    raise ArgumentError, "repeat cannot be used with an action phase" if phase != nil && repeat == true
    limiter = action_limiter(cooldown)
    if limiter == nil && guard != nil && guard.respond_to?(:use)
      limiter = guard
      guard = nil
    end
    validate_action_guard(guard)
    initial_delay = initially_blocked_for.to_f
    raise ArgumentError, "initially_blocked_for must be a non-negative finite number" if !initial_delay.finite? || initial_delay < 0.0
    if initial_delay > 0.0
      limiter ||= Cooldown.new
      raise ArgumentError, "action limiter cannot be blocked initially" if !limiter.respond_to?(:block_for)
      limiter.block_for(initial_delay)
    end
    @action_handlers << {
      :name => name.to_sym,
      :repeat => repeat == true,
      :phase => phase,
      :guard => guard,
      :limiter => limiter,
      :block => block
    }
    @phased_action_names << name.to_sym if phase != nil && !@phased_action_names.include?(name.to_sym)
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

  def stopwatch(autostart: false, pause_on_dialogs: false)
    clock = if pause_on_dialogs == true
      lambda { modal_interaction_adjusted_time }
    else
      lambda { monotonic_time }
    end
    stopwatch = Stopwatch.new(clock: clock, autostart: autostart)
    @stopwatches << stopwatch
    stopwatch
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

  def on_stop(&block)
    raise ArgumentError, "block is required" if block == nil
    @stop_handlers << block
    self
  end

  def manage(resource, release: :close, &block)
    @managed_resources = EltenAPI::Resources::Registry.new if @managed_resources.closed?
    @managed_resources.manage(resource, release: release, &block)
  end

  def release(resource, close: false)
    @managed_resources.release(resource, close: close)
  end

  def run(&block)
    on_tick(&block) if block != nil
    raise RuntimeError, "Runner has no handlers" if @tick_handlers.empty? && @timers.empty? && @key_handlers.empty? && @action_handlers.empty?
    @running = true
    @result = nil
    @next_tick_at = monotonic_time
    begin
      while @running == true
        loop_update
        time = monotonic_time
        process_key_handlers(time)
        process_action_handlers(time) if @running == true
        process_timers(time) if @running == true
        process_tick(time) if @running == true
      end
      @result
    ensure
      @running = false
      finish_run
    end
  end

  def stop(result = nil)
    stop_stopwatches
    @result = result
    @running = false
    result
  end

  def running?
    @running == true
  end

  private

  def action_limiter(value)
    return nil if value == nil
    return self.cooldown(value) if value.is_a?(Symbol) || value.is_a?(String)
    if value.is_a?(Numeric)
      interval = value.to_f
      raise ArgumentError, "cooldown must be a non-negative finite number" if !interval.finite? || interval < 0.0
      return Cooldown.new(interval)
    end
    return value if value.respond_to?(:use)
    raise ArgumentError, "cooldown must be a number, name, or limiter"
  end

  def validate_action_guard(guard)
    return if guard == nil || guard.respond_to?(:call) || guard.respond_to?(:allow?)
    raise ArgumentError, "guard must be callable or respond to #allow?"
  end

  def normalize_action_phase(phase)
    return nil if phase == nil
    phase = phase.to_sym if phase.respond_to?(:to_sym)
    return phase if ACTION_PHASES.include?(phase)
    raise ArgumentError, "unsupported action phase: #{phase.inspect}"
  end

  def action_guard_allows?(guard, time, name)
    return true if guard == nil
    callable = guard.respond_to?(:allow?) ? guard.method(:allow?) : guard
    result = case callable.arity
    when 0
      callable.call
    when 1
      callable.call(self)
    when 2
      callable.call(self, time)
    else
      callable.call(self, time, name)
    end
    result != nil && result != false
  end

  def finish_run
    stop_stopwatches
    time = monotonic_time
    finish_active_actions(time)
    @stop_handlers.each do |handler|
      invoke_callback(handler, time)
    rescue Exception => e
      Log.warning("Runner stop handler failed: #{e.class}: #{e.message}") if defined?(Log)
    end
    @managed_resources.close
  end

  def stop_stopwatches
    @stopwatches.each(&:stop)
  end

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
      triggered = if handler[:event] == :released
        key_released?(key)
      else
        handler[:repeat] == true ? key_pressed?(key) : key_first_pressed?(key)
      end
      next if triggered != true
      invoke_callback(handler[:block], time, key)
      break if @running != true
    end
  end

  def process_action_handlers(time)
    if !@phased_action_names.empty?
      states = update_action_states(@phased_action_names)
      phases_completed = process_action_phase_handlers(@action_handlers, states, time)
      settle_finished_action_states(states) if phases_completed == true
      return if @running != true
    end

    @action_handlers.each do |handler|
      next if handler[:phase] != nil
      action = @actions[handler[:name]]
      next if action == nil
      pressed = handler[:repeat] == true ? action.held?(self) : action.pressed?(self)
      next if pressed != true
      invoke_action_handler(handler, time)
      break if @running != true
    end
  end

  def update_action_states(names)
    names.each_with_object({}) do |name, states|
      action = @actions[name]
      next if action == nil
      was_active = @action_states[name] == true
      pressed = action.pressed?(self)
      held = action.held?(self)
      released = action.released?(self)
      started = !was_active && (pressed || held)
      finished = (was_active || started) && !held && (released || was_active)
      states[name] = {
        :start => started,
        :update => held || started,
        :finish => finished
      }
      @action_states[name] = held || started
    end
  end

  def process_action_phase_handlers(handlers, states, time)
    ACTION_PHASES.each do |phase|
      handlers.each do |handler|
        next if handler[:phase] != phase
        next if states.dig(handler[:name], phase) != true
        invoke_action_handler(handler, time)
        return false if @running != true && phase != :finish
      end
    end
    true
  end

  def settle_finished_action_states(states)
    states.each do |name, phases|
      @action_states[name] = false if phases[:finish] == true
    end
  end

  def finish_active_actions(time)
    active = @action_states.select { |_name, state| state == true }.keys
    active.each do |name|
      @action_handlers.each do |handler|
        next if handler[:name] != name || handler[:phase] != :finish
        begin
          invoke_action_handler(handler, time)
        rescue Exception => e
          Log.warning("Runner action finish handler failed: #{e.class}: #{e.message}") if defined?(Log)
        end
      end
      @action_states[name] = false
    end
  end

  def invoke_action_handler(handler, time)
    return if !action_guard_allows?(handler[:guard], time, handler[:name])
    return if handler[:limiter] != nil && !handler[:limiter].use(time)
    invoke_callback(handler[:block], time, handler[:name])
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
