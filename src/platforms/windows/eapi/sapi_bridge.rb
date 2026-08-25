# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class SapiBridge
  MAGIC = 0xACEDFEED
  VERSION = 1
  HELLO_TIMEOUT = 3.0
  MAX_FRAME_SIZE = 0xFFFFFF
  HELLO = 1
  SET_VOICE = 2
  SET_OUTPUT = 3
  SET_RATE = 4
  SET_VOLUME = 5
  SPEAK = 6
  PAUSE = 7
  RESUME = 8
  STOP = 9
  STATUS = 10
  QUIT = 11
  LIST_VOICES = 12
  PURGE_BEFORE_SPEAK = 2
  STATUS_MAX_AGE = 0.01
  SPEAK_START_GRACE = 0.25
  @manager_mutex = Mutex.new
  @voices_mutex = Mutex.new

  Voice = Struct.new(:id, :name, :language, :age, :gender, :vendor, :bitness, keyword_init: true)

  class Error < StandardError; end
  class CommandError < Error; end

  class Watchdog
    def initialize
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @sequence = 0
      @request = nil
      @stopping = false
      @thread = Thread.new { run }
      @thread.name = "SAPI bridge watchdog" if @thread.respond_to?(:name=)
    end

    def arm(client, timeout)
      @mutex.synchronize do
        @sequence += 1
        @request = [@sequence, client, monotonic_time + timeout.to_f]
        @condition.signal
        @sequence
      end
    end

    def disarm(token)
      @mutex.synchronize do
        @request = nil if @request != nil && @request[0] == token
        @condition.signal
      end
    end

    def close
      @mutex.synchronize do
        @stopping = true
        @request = nil
        @condition.signal
      end
      @thread.join if @thread != Thread.current
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def run
      loop do
        expired = nil
        @mutex.synchronize do
          loop do
            return if @stopping
            if @request == nil
              @condition.wait(@mutex)
            else
              remaining = @request[2] - monotonic_time
              if remaining > 0
                @condition.wait(@mutex, remaining)
              else
                expired = @request
                @request = nil
                break
              end
            end
          end
        end
        expired[1].abort(expired[0]) if expired != nil
      end
    rescue Exception => e
      Log.warning("SAPI bridge watchdog failed: #{e.class}: #{e.message}") if defined?(Log)
    end
  end

  class PayloadReader
    def initialize(data)
      @data = data
      @offset = 0
    end

    def uint32
      raise Error, "Truncated SAPI bridge response" if @offset + 4 > @data.bytesize
      value = @data.byteslice(@offset, 4).unpack1("V")
      @offset += 4
      value
    end

    def string
      size = uint32
      raise Error, "Truncated SAPI bridge string" if size > @data.bytesize - @offset
      value = @data.byteslice(@offset, size)
      @offset += size
      value.force_encoding(Encoding::UTF_8).scrub
    end

    def done?
      @offset == @data.bytesize
    end
  end

  class Client
    attr_reader :bitness

    def initialize(path, bitness, watchdog, &started)
      @bitness = bitness
      @watchdog = watchdog
      @request_mutex = Mutex.new
      @state_mutex = Mutex.new
      @timeout_token = nil
      @process = EltenAPI::ChildProc.new(%Q{"#{path}"}, path: File.dirname(path))
      started.call(self) if started != nil
      body = request(HELLO, "".b, HELLO_TIMEOUT)
      reader = PayloadReader.new(body)
      raise Error, "SAPI bridge is not #{bitness}-bit" if reader.uint32 != bitness || !reader.done?
    rescue Exception
      close
      raise
    end

    def running?
      @process != nil && @process.running?
    rescue Exception
      false
    end

    def set_voice(id)
      request(SET_VOICE, encode_string(id), 5.0)
      true
    end

    def set_output(id=nil)
      request(SET_OUTPUT, encode_string(id.to_s), 5.0)
      true
    end

    def set_rate(rate)
      request(SET_RATE, [rate.to_i].pack("l<"), 2.0)
      true
    end

    def set_volume(volume)
      request(SET_VOLUME, [volume.to_i].pack("V"), 2.0)
      true
    end

    def speak(text, flags)
      request(SPEAK, [flags.to_i].pack("V") + encode_string(text), 5.0)
      true
    end

    def pause
      request(PAUSE, "".b, 2.0)
      true
    end

    def resume
      request(RESUME, "".b, 2.0)
      true
    end

    def stop
      request(STOP, "".b, 2.0)
      true
    end

    def status
      reader = PayloadReader.new(request(STATUS, "".b, 2.0))
      result = { :speaking => reader.uint32 != 0, :bookmark => reader.string }
      raise Error, "Trailing SAPI bridge status data" unless reader.done?
      result
    end

    def voices
      reader = PayloadReader.new(request(LIST_VOICES, "".b, 5.0))
      count = reader.uint32
      raise Error, "Invalid SAPI bridge voice count" if count > 16_384
      result = Array.new(count) do
        Voice.new(
          :id => reader.string,
          :name => reader.string,
          :language => reader.string,
          :age => reader.string,
          :gender => reader.string,
          :vendor => reader.string,
          :bitness => bitness
        )
      end
      raise Error, "Trailing SAPI bridge voice data" unless reader.done?
      result
    end

    def abort(timeout_token=nil)
      process = @state_mutex.synchronize do
        @timeout_token = timeout_token if timeout_token != nil
        @process
      end
      process.terminate rescue nil if process != nil
    end

    def close
      process = @process
      if process != nil
        if running?
          request(QUIT, "".b, 0.25) rescue nil
        end
        process.close rescue nil
      end
      @state_mutex.synchronize { @process = nil if @process == process }
    end

    private

    def encode_string(value)
      value = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).b
      [value.bytesize].pack("V") + value
    end

    def request(command, payload, timeout)
      @request_mutex.synchronize do
        raise Error, "SAPI bridge is not running" unless running?
        raise Error, "SAPI bridge request is too large" if payload.bytesize > MAX_FRAME_SIZE
        control = (VERSION << 4) | command.to_i
        frame = [MAGIC, control].pack("VC") + [payload.bytesize].pack("V").byteslice(0, 3) + payload
        token = @watchdog.arm(self, timeout)
        begin
          write_all(frame)
          header = read_exact(8)
          magic, control = header.unpack("VC")
          version = control >> 4
          response_command = control & 0x0F
          size = (header.byteslice(5, 3) + "\0".b).unpack1("V")
          raise Error, "Invalid SAPI bridge response" if magic != MAGIC || version != VERSION || response_command != command || size < 4 || size > MAX_FRAME_SIZE
          response = read_exact(size)
          status = response.byteslice(0, 4).unpack1("l<")
          raise CommandError, "SAPI bridge command failed: 0x#{(status & 0xffffffff).to_s(16)}" if status < 0
          response.byteslice(4, size - 4)
        rescue Exception
          raise Error, "SAPI bridge timed out" if timed_out?(token)
          raise
        ensure
          @watchdog.disarm(token)
          clear_timeout(token)
        end
      end
    end

    def write_all(data)
      offset = 0
      while offset < data.bytesize
        written = @process.write(data.byteslice(offset, data.bytesize - offset)).to_i
        raise Error, "SAPI bridge pipe was closed" if written <= 0
        offset += written
      end
    end

    def read_exact(size)
      data = "".b
      while data.bytesize < size
        part = @process.read(size - data.bytesize)
        raise Error, "SAPI bridge pipe was closed" if part == nil || part.empty?
        data << part
      end
      data
    end

    def timed_out?(token)
      @state_mutex.synchronize { @timeout_token == token }
    end

    def clear_timeout(token)
      @state_mutex.synchronize { @timeout_token = nil if @timeout_token == token }
    end
  end

  class Worker
    def initialize(candidates)
      @candidates = candidates
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @queue = []
      @watchdog = Watchdog.new
      @client = nil
      @active_voice_id = nil
      @voice_id = nil
      @voice_generation = 0
      @activation_generation = nil
      @failed_voice_id = nil
      @output_id = nil
      @output_set = false
      @rate = nil
      @volume = nil
      @disabled = {}
      @rejected = {}
      @speech_generation = 0
      @awaiting_start_generation = nil
      @speak_start_deadline = 0.0
      @status = { :speaking => false, :bookmark => "" }
      @status_at = monotonic_time
      @status_queued = false
      @status_error_logged = false
      @busy = false
      @stopping = false
      @thread = Thread.new { run }
      @thread.name = "SAPI bridge worker" if @thread.respond_to?(:name=)
    end

    def accepting?
      @mutex.synchronize { !@stopping && @thread.alive? }
    rescue Exception
      false
    end

    def set_voice(id)
      id = id.to_s
      client = @mutex.synchronize do
        return false if @stopping
        @voice_id = id
        @voice_generation += 1
        generation = @voice_generation
        @rejected = {}
        @failed_voice_id = nil
        @speech_generation += 1
        @awaiting_start_generation = nil
        set_status_locked(false, "")
        discard_locked(:set_voice, :speak, :pause, :resume, :stop, :status)
        @queue << [:set_voice, id, generation]
        @condition.signal
        @client if @activation_generation != nil
      end
      client.abort rescue nil if client != nil
      true
    end

    def set_output(id=nil)
      enqueue_setting(:set_output, id) do
        @output_id = id
        @output_set = true
      end
    end

    def set_rate(rate)
      enqueue_setting(:set_rate, rate.to_i) { @rate = rate.to_i }
    end

    def set_volume(volume)
      enqueue_setting(:set_volume, volume.to_i) { @volume = volume.to_i }
    end

    def speak(text, flags)
      @mutex.synchronize do
        return false if @stopping || @voice_id.to_s == "" || @failed_voice_id == @voice_id
        @speech_generation += 1
        generation = @speech_generation
        @awaiting_start_generation = nil
        discard_locked(:speak, :status) if (flags.to_i & PURGE_BEFORE_SPEAK) != 0
        set_status_locked(true, "")
        @queue << [:speak, text.to_s, flags.to_i, generation]
        @condition.signal
        true
      end
    end

    def pause
      enqueue_simple(:pause)
    end

    def resume
      enqueue_simple(:resume)
    end

    def stop
      @mutex.synchronize do
        return false if @stopping
        @speech_generation += 1
        @awaiting_start_generation = nil
        discard_locked(:speak, :pause, :resume, :stop, :status)
        set_status_locked(false, @status[:bookmark])
        @queue.unshift([:stop])
        @condition.signal
        true
      end
    end

    def status
      @mutex.synchronize do
        if !@stopping && !@status_queued && monotonic_time - @status_at >= STATUS_MAX_AGE
          @status_queued = true
          @queue << [:status, @speech_generation]
          @condition.signal
        end
        @status.dup
      end
    end

    def failed?
      @mutex.synchronize { @voice_id.to_s != "" && @failed_voice_id == @voice_id }
    end

    def close
      client = nil
      thread = nil
      @mutex.synchronize do
        unless @stopping
          @stopping = true
          @queue.clear
          @status_queued = false
          set_status_locked(false, @status[:bookmark])
          @queue << [:shutdown]
          client = @client if @busy
          @condition.signal
        end
        thread = @thread
      end
      client.abort rescue nil if client != nil
      thread.join if thread != nil && thread != Thread.current
    end

    private

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def enqueue_setting(command, value)
      @mutex.synchronize do
        return false if @stopping
        yield
        discard_locked(command)
        @queue << [command, value]
        @condition.signal
        true
      end
    end

    def enqueue_simple(command)
      @mutex.synchronize do
        return false if @stopping
        discard_locked(command)
        @queue << [command]
        @condition.signal
        true
      end
    end

    def discard_locked(*commands)
      @queue.delete_if { |item| commands.include?(item[0]) }
      @status_queued = false if commands.include?(:status)
    end

    def set_status_locked(speaking, bookmark)
      @status = { :speaking => speaking == true, :bookmark => bookmark.to_s }
      @status_at = monotonic_time
    end

    def run
      loop do
        command = @mutex.synchronize do
          @condition.wait(@mutex) while @queue.empty?
          @busy = true
          @queue.shift
        end
        break if command[0] == :shutdown
        begin
          perform(command)
        rescue Exception => e
          Log.warning("SAPI bridge worker failed: #{e.class}: #{e.message}") if defined?(Log)
        ensure
          @mutex.synchronize { @busy = false }
        end
      end
    ensure
      close_client
      @watchdog.close
      @mutex.synchronize do
        @busy = false
        @stopping = true
        @status_queued = false
        set_status_locked(false, @status[:bookmark])
      end
    end

    def perform(command)
      case command[0]
      when :set_voice
        perform_set_voice(command[1], command[2])
      when :set_output
        perform_setting { |client| client.set_output(command[1]) }
      when :set_rate
        perform_setting { |client| client.set_rate(command[1]) }
      when :set_volume
        perform_setting { |client| client.set_volume(command[1]) }
      when :speak
        perform_speak(command[1], command[2], command[3])
      when :pause
        perform_setting { |client| client.pause }
      when :resume
        perform_setting { |client| client.resume }
      when :stop
        perform_setting { |client| client.stop }
      when :status
        perform_status(command[1])
      end
    end

    def perform_set_voice(id, generation)
      return if activate_voice(id, generation)
      mark_voice_failed(id, generation)
    end

    def perform_setting
      client = active_client
      return if client == nil
      yield client
    rescue CommandError => e
      Log.warning(e.message) if defined?(Log) && !stopping?
    rescue Exception => e
      fail_client(client, e)
    end

    def perform_speak(text, flags, generation)
      unless ensure_active
        mark_speech_failed(generation)
        return
      end
      client = active_client
      begin
        client.speak(text, flags)
        mark_speech_submitted(generation)
      rescue CommandError => e
        Log.warning(e.message) if defined?(Log) && !stopping?
        mark_speech_failed(generation)
      rescue Exception => e
        fail_client(client, e)
        unless stopping? || !ensure_active
          begin
            active_client.speak(text, flags)
            mark_speech_submitted(generation)
            return
          rescue Exception => retry_error
            fail_client(active_client, retry_error)
          end
        end
        mark_speech_failed(generation)
      end
    end

    def perform_status(generation)
      result = { :speaking => false, :bookmark => "" }
      succeeded = false
      client = active_client
      if client != nil
        begin
          result = client.status
          succeeded = true
        rescue CommandError => e
          log_status_error(e)
        rescue Exception => e
          fail_client(client, e)
        end
      end
      @mutex.synchronize do
        @status_queued = false
        @status_error_logged = false if succeeded
        if generation == @speech_generation
          if result[:speaking]
            @awaiting_start_generation = nil
            set_status_locked(true, result[:bookmark])
          elsif @awaiting_start_generation == generation && monotonic_time < @speak_start_deadline
            @status_at = monotonic_time
          else
            @awaiting_start_generation = nil
            set_status_locked(false, result[:bookmark])
          end
        end
      end
    end

    def mark_speech_submitted(generation)
      @mutex.synchronize do
        if generation == @speech_generation
          @awaiting_start_generation = generation
          @speak_start_deadline = monotonic_time + SPEAK_START_GRACE
        end
      end
    end

    def mark_speech_failed(generation)
      @mutex.synchronize do
        if generation == @speech_generation
          @awaiting_start_generation = nil
          set_status_locked(false, @status[:bookmark])
        end
      end
    end

    def ensure_active
      id, generation, failed = @mutex.synchronize { [@voice_id, @voice_generation, @failed_voice_id == @voice_id] }
      return false if id.to_s == "" || failed
      client = active_client
      active_id = @mutex.synchronize { @active_voice_id }
      return true if client != nil && active_id == id
      unless activate_voice(id, generation)
        mark_voice_failed(id, generation)
        return false
      end
      client = active_client
      apply_configuration(client)
      true
    rescue Exception => e
      fail_client(client, e)
      false
    end

    def activate_voice(id, generation)
      return false unless begin_activation(id, generation)
      client = active_client
      active_id = @mutex.synchronize { @active_voice_id }
      return true if client != nil && active_id == id

      if client != nil
        bitness = client.bitness
        begin
          client.set_voice(id)
          return true if accept_client(client, id, generation)
          close_client(client)
          return false
        rescue CommandError => e
          reject_voice(id, bitness, generation, e)
          close_client(client)
        rescue Exception => e
          disable_client(client, bitness, e, id, generation)
        end
        return false unless activation_current?(id, generation)
      end

      @candidates.each do |bitness, path|
        break unless activation_current?(id, generation)
        next if disabled?(bitness) || rejected?(id, bitness)
        bridge = nil
        accepted = false
        begin
          bridge = Client.new(path, bitness, @watchdog) do |started|
            bridge = started
            publish_client(started, id, generation)
          end
          Log.debug("Started #{bitness}-bit SAPI bridge: #{path}") if defined?(Log)
          break unless activation_current?(id, generation)
          bridge.set_voice(id)
          accepted = accept_client(bridge, id, generation)
          return true if accepted
          break
        rescue CommandError => e
          reject_voice(id, bitness, generation, e)
        rescue Exception => e
          disable_client(bridge, bitness, e, id, generation)
        ensure
          close_client(bridge) if bridge != nil && !accepted
        end
      end
      false
    ensure
      finish_activation(generation)
    end

    def apply_configuration(client)
      return if client == nil
      output_set, output_id, rate, volume = @mutex.synchronize { [@output_set, @output_id, @rate, @volume] }
      apply_configuration_item { client.set_output(output_id) } if output_set
      apply_configuration_item { client.set_rate(rate) } if rate != nil
      apply_configuration_item { client.set_volume(volume) } if volume != nil
    end

    def apply_configuration_item
      yield
    rescue CommandError => e
      Log.warning(e.message) if defined?(Log)
    end

    def active_client
      client = @mutex.synchronize { @client }
      return nil if client == nil
      return client if client.running?
      disable_client(client, client.bitness, Error.new("SAPI bridge process exited"))
      nil
    rescue Exception => e
      fail_client(client, e)
      nil
    end

    def publish_client(client, id, generation)
      abort_client = @mutex.synchronize do
        if activation_current_locked?(id, generation)
          @client = client
          false
        else
          true
        end
      end
      client.abort if abort_client
    end

    def accept_client(client, id, generation)
      accepted = @mutex.synchronize do
        if @client == client && activation_current_locked?(id, generation)
          @active_voice_id = id
          @failed_voice_id = nil
          @status_error_logged = false
          true
        else
          false
        end
      end
      Log.debug("Using #{client.bitness}-bit SAPI bridge for #{id}") if accepted && defined?(Log)
      accepted
    end

    def close_client(client=nil)
      client ||= @mutex.synchronize { @client }
      return if client == nil
      client.close rescue nil
      @mutex.synchronize do
        if @client == client
          @client = nil
          @active_voice_id = nil
        end
      end
    end

    def fail_client(client, error)
      if stopping?
        close_client(client)
      else
        disable_client(client, client == nil ? nil : client.bitness, error)
      end
      @mutex.synchronize { set_status_locked(false, @status[:bookmark]) }
    end

    def disable_client(client, bitness, error, id=nil, generation=nil)
      close_client(client) if client != nil
      disabled = @mutex.synchronize do
        if bitness != nil && (generation == nil || activation_current_locked?(id, generation))
          @disabled[bitness] = true
          true
        else
          false
        end
      end
      Log.warning("#{bitness}-bit SAPI bridge disabled: #{error.class}: #{error.message}") if disabled && defined?(Log)
    end

    def reject_voice(id, bitness, generation, error)
      rejected = @mutex.synchronize do
        if activation_current_locked?(id, generation)
          @rejected[bitness] = true
          true
        else
          false
        end
      end
      Log.debug("#{bitness}-bit SAPI bridge rejected #{id}: #{error.message}") if rejected && defined?(Log)
    end

    def disabled?(bitness)
      @disabled[bitness] == true
    end

    def rejected?(id, bitness)
      @mutex.synchronize { @voice_id == id && @rejected[bitness] == true }
    end

    def begin_activation(id, generation)
      @mutex.synchronize do
        return false unless activation_current_locked?(id, generation)
        @activation_generation = generation
        true
      end
    end

    def finish_activation(generation)
      @mutex.synchronize do
        @activation_generation = nil if @activation_generation == generation
      end
    end

    def activation_current?(id, generation)
      @mutex.synchronize { activation_current_locked?(id, generation) }
    end

    def activation_current_locked?(id, generation)
      !@stopping && @voice_id == id && @voice_generation == generation
    end

    def mark_voice_failed(id, generation)
      failed = @mutex.synchronize do
        if activation_current_locked?(id, generation) && @failed_voice_id != id
          @failed_voice_id = id
          set_status_locked(false, "")
          true
        else
          false
        end
      end
      Log.warning("No SAPI bridge accepted voice #{id}") if failed && defined?(Log)
      failed
    end

    def log_status_error(error)
      log = @mutex.synchronize do
        if @stopping || @status_error_logged
          false
        else
          @status_error_logged = true
        end
      end
      Log.warning(error.message) if log && defined?(Log)
    end

    def stopping?
      @mutex.synchronize { @stopping }
    end
  end

  class << self
    def set_voice(id)
      stale = nil
      worker = manager_mutex.synchronize do
        current = @worker
        unless current != nil && current.accepting?
          stale = current
          candidates = bridge_candidates
          @worker = candidates.empty? ? nil : Worker.new(candidates)
        end
        @worker
      end
      stale.close rescue nil if stale != nil && stale != worker
      worker != nil && worker.set_voice(id)
    end

    def set_output(id=nil)
      call(false) { |worker| worker.set_output(id) }
    end

    def set_rate(rate)
      call(false) { |worker| worker.set_rate(rate) }
    end

    def set_volume(volume)
      call(false) { |worker| worker.set_volume(volume) }
    end

    def speak(text, flags)
      call(false) { |worker| worker.speak(text, flags) }
    end

    def pause
      call(false) { |worker| worker.pause }
    end

    def resume
      call(false) { |worker| worker.resume }
    end

    def stop
      call(false) { |worker| worker.stop }
    end

    def status
      call(nil) { |worker| worker.status }
    end

    def voices
      @voices_mutex.synchronize do
        @voices ||= enumerate_voices.freeze
      end
    end

    def failed?
      call(false) { |worker| worker.failed? }
    end

    def shutdown
      release
    end

    def release
      worker = manager_mutex.synchronize do
        current = @worker
        @worker = nil
        current
      end
      worker.close rescue nil if worker != nil
    end

    private

    def manager_mutex
      @manager_mutex
    end

    def enumerate_voices
      watchdog = Watchdog.new
      bridge_candidates.flat_map do |bitness, path|
        client = nil
        begin
          client = Client.new(path, bitness, watchdog)
          client.voices
        rescue Exception => e
          Log.warning("Could not enumerate #{bitness}-bit SAPI voices: #{e.class}: #{e.message}") if defined?(Log)
          []
        ensure
          client.close rescue nil if client != nil
        end
      end
    ensure
      watchdog.close rescue nil if watchdog != nil
    end

    def bridge_bitnesses
      case EltenRuntimePaths.architecture
      when "arm64"
        [64, 32]
      when "x64"
        [32]
      else
        []
      end
    rescue Exception
      []
    end

    def bridge_candidates
      bridge_bitnesses.map do |bitness|
        path = File.join(EltenRuntimePaths.bin_root, "ext", "windows", "EltenSapiBridge#{bitness}.exe")
        [bitness, path]
      end.select { |_, path| File.file?(path) }
    end

    def call(fallback)
      worker = manager_mutex.synchronize { @worker }
      return fallback if worker == nil || !worker.accepting?
      yield worker
    rescue Exception => e
      Log.warning("SAPI bridge request failed: #{e.class}: #{e.message}") if defined?(Log)
      fallback
    end
  end
end
