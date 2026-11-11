# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

require "fiddle"

# Exercises the Windows child-process implementation without replacing the
# implementation loaded by a running Elten instance. The source is evaluated
# in an isolated module and uses a private process registry for the stress run.
# Run `ruby tools/process-handle-stress.rb 100` from a Windows source checkout.
module EltenProcessHandleStress
  WINAPI_ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
  KERNEL32 = Fiddle.dlopen("kernel32.dll")
  GET_CURRENT_PROCESS = Fiddle::Function.new(KERNEL32["GetCurrentProcess"], [], Fiddle::TYPE_VOIDP, WINAPI_ABI)
  GET_CURRENT_PROCESS_ID = Fiddle::Function.new(KERNEL32["GetCurrentProcessId"], [], Fiddle::TYPE_LONG, WINAPI_ABI)
  GET_PROCESS_HANDLE_COUNT = Fiddle::Function.new(KERNEL32["GetProcessHandleCount"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, WINAPI_ABI)
  GET_PROCESS_MEMORY_INFO = Fiddle::Function.new(KERNEL32["K32GetProcessMemoryInfo"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG], Fiddle::TYPE_INT, WINAPI_ABI)
  CREATE_TOOLHELP32_SNAPSHOT = Fiddle::Function.new(KERNEL32["CreateToolhelp32Snapshot"], [Fiddle::TYPE_LONG, Fiddle::TYPE_LONG], Fiddle::TYPE_VOIDP, WINAPI_ABI)
  THREAD32_FIRST = Fiddle::Function.new(KERNEL32["Thread32First"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, WINAPI_ABI)
  THREAD32_NEXT = Fiddle::Function.new(KERNEL32["Thread32Next"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, WINAPI_ABI)
  CLOSE_HANDLE = Fiddle::Function.new(KERNEL32["CloseHandle"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, WINAPI_ABI)
  TH32CS_SNAPTHREAD = 0x00000004

  class << self
    def run(iterations: 100, repository_root: nil)
      raise "This stress test is Windows-only" unless Gem.win_platform?
      iterations = iterations.to_i
      raise ArgumentError, "iterations must be positive" if iterations <= 0
      repository_root ||= File.expand_path("..", __dir__)
      target = load_target(repository_root)
      runner = Object.new
      runner.extend(EltenAPI) if defined?(EltenAPI)
      runner.extend(target)
      install_standalone_helpers(runner)

      $elten_process_stress_procs = []
      command = "\"#{ENV.fetch("ComSpec", "C:\\Windows\\System32\\cmd.exe")}\" /d /c exit 0"
      working_directory = File.expand_path(repository_root)
      3.times { runner.send(:executeprocess, command, true, 10, false, working_directory) }
      GC.start
      before = snapshot
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      failures = 0

      iterations.times do
        result = runner.send(:executeprocess, command, true, 10, false, working_directory)
        failures += 1 if result == -1
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      GC.start
      after = snapshot
      registry_size = $elten_process_stress_procs.size
      report = {
        iterations: iterations,
        failures: failures,
        elapsed_seconds: elapsed.round(3),
        launches_per_second: (iterations / elapsed).round(2),
        before: before,
        after: after,
        delta: {
          handles: after[:handles] - before[:handles],
          working_set_bytes: after[:working_set_bytes] - before[:working_set_bytes],
          os_threads: after[:os_threads] - before[:os_threads],
          cpu_seconds: (after[:cpu_seconds] - before[:cpu_seconds]).round(3),
          process_registry: registry_size
        }
      }
      report[:passed] = failures == 0 && registry_size == 0 && report[:delta][:handles].abs <= 2 && report[:delta][:os_threads].abs <= 1
      report
    ensure
      cleanup_test_registry(target) if defined?(target) && target != nil
      $elten_process_stress_procs = nil
    end

    def snapshot
      times = Process.times
      {
        handles: process_handle_count,
        working_set_bytes: working_set_size,
        os_threads: process_thread_count,
        cpu_seconds: (times.utime + times.stime).round(3)
      }
    end

    private

    def load_target(repository_root)
      ensure_win32_structs(repository_root)
      path = File.join(repository_root, "src", "platforms", "windows", "eapi", "childprocess.rb")
      source = File.binread(path)
      source = source.sub("module EltenAPI", "module EltenProcessHandleStress::Target")
      source = source.gsub("$procs", "$elten_process_stress_procs")
      remove_const(:Target) if const_defined?(:Target, false)
      const_set(:Target, Module.new)
      eval(source, TOPLEVEL_BINDING, path)
      const_get(:Target)
    end

    def ensure_win32_structs(repository_root)
      return if defined?(EltenWin32) && EltenWin32.respond_to?(:startup_info)
      load File.join(repository_root, "src", "platforms", "windows", "ri", "win32structs.rb")
    end

    def install_standalone_helpers(runner)
      runner.define_singleton_method(:unicode) do |value|
        wide = value.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace)
        (wide + [0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
      end unless runner.respond_to?(:unicode, true)
      runner.define_singleton_method(:loop_update) {} unless runner.respond_to?(:loop_update, true)
      define_standalone_log unless defined?(Log)
    end

    def define_standalone_log
      Object.const_set(:Log, Module.new)
      Log.define_singleton_method(:debug) { |_message| }
      Log.define_singleton_method(:warning) { |_message| }
    end

    def process_handle_count
      value = [0].pack("L")
      raise "GetProcessHandleCount failed" if GET_PROCESS_HANDLE_COUNT.call(GET_CURRENT_PROCESS.call, value) == 0
      value.unpack1("L")
    end

    def working_set_size
      pointer_size = [nil].pack("p").size
      size = pointer_size == 8 ? 72 : 40
      working_set_offset = pointer_size == 8 ? 16 : 12
      counters = "\0" * size
      counters[0, 4] = [size].pack("L")
      raise "K32GetProcessMemoryInfo failed" if GET_PROCESS_MEMORY_INFO.call(GET_CURRENT_PROCESS.call, counters, size) == 0
      EltenWin32.pointer_value(counters, working_set_offset)
    end

    def process_thread_count
      snapshot = CREATE_TOOLHELP32_SNAPSHOT.call(TH32CS_SNAPTHREAD, 0)
      raise "CreateToolhelp32Snapshot failed" if snapshot == 0 || snapshot == -1
      entry = "\0" * 28
      entry[0, 4] = [28].pack("L")
      process_id = GET_CURRENT_PROCESS_ID.call
      count = 0
      if THREAD32_FIRST.call(snapshot, entry) != 0
        loop do
          count += 1 if entry[12, 4].unpack1("L") == process_id
          break if THREAD32_NEXT.call(snapshot, entry) == 0
        end
      end
      count
    ensure
      CLOSE_HANDLE.call(snapshot) if defined?(snapshot) && snapshot != nil && snapshot != 0 && snapshot != -1
    end

    def cleanup_test_registry(target)
      handles = $elten_process_stress_procs
      return unless handles.is_a?(Array)
      handles.each do |handle|
        next if handle == nil || handle == 0 || handle == -1
        target::TERMINATE_PROCESS.call(handle, 0) rescue nil
        target::CLOSE_HANDLE.call(handle) rescue nil
      end
      handles.clear
    end
  end
end

if $PROGRAM_NAME == __FILE__
  iterations = Integer(ARGV[0] || ENV.fetch("ELTEN_PROCESS_STRESS_ITERATIONS", "100"))
  repository_root = File.expand_path("..", __dir__)
  report = EltenProcessHandleStress.run(iterations: iterations, repository_root: repository_root)
  report.each { |key, value| puts "#{key}: #{value.inspect}" }
  exit(report[:passed] ? 0 : 1)
end
