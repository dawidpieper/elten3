# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "open3"
require "io/wait"
require "shellwords"

module EltenAPI
  private

  def run(file, _hide = false, path = nil, addToProcs = true)
    Log.debug("Running process: #{file}")
    if native_open_command?(file)
      target = file[1].to_s
      raise Errno::ENOENT, target if target == "" || !EltenSystemHelpers.open_url(target)
      return 0
    end
    path ||= File.dirname($path.to_s)
    argv = child_process_arguments(file)
    raise Errno::ENOENT, file.to_s if argv.empty?
    pid = Process.spawn(*argv, chdir: path.to_s == "" ? Dir.pwd : path.to_s)
    if addToProcs
      $procs ||= []
      $procs << pid
    else
      Process.detach(pid) rescue nil
    end
    pid
  end

  def executeprocess(cmdline, _hide = false, tmax = 0, update = true, path = nil)
    pid = run(cmdline, false, path)
    started = Time.now.to_f
    loop do
      done = Process.waitpid(pid, Process::WNOHANG)
      break if done != nil
      if tmax.to_f > 0 && Time.now.to_f - started > tmax.to_f
        Process.kill("TERM", pid) rescue nil
        return -1
      end
      update ? loop_update : sleep(0.1)
    end
    status = $?
    [status ? status.exitstatus.to_i : 0].pack("I")
  rescue Exception
    -1
  end

  def terminate_process_handle(handle)
    Process.kill("TERM", handle.to_i) if handle.to_i > 0
  rescue Exception
  end

  def exit_process(code = 0)
    exit(code.to_i)
  end

  class ChildProc
    attr_reader :pid, :process_id

    def initialize(file, path = nil)
      path ||= Dir.pwd
      argv = EltenAPI.send(:child_process_arguments, file)
      raise Errno::ENOENT, file.to_s if argv.empty?
      @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*argv, chdir: path)
      @pid = @wait_thread.pid
      @process_id = @pid
      @stdout_buffer = +"".b
      @stderr_buffer = +"".b
    end

    def running?
      return false if @wait_thread == nil
      @wait_thread.alive?
    end

    def exitstatus
      return nil if @wait_thread == nil || @wait_thread.alive?
      @wait_thread.value.exitstatus
    rescue Exception
      nil
    end

    def terminate
      Process.kill("TERM", @pid) if @pid.to_i > 0
    rescue Exception
    end

    def avail
      fill_buffer(@stdout, @stdout_buffer)
      @stdout_buffer.bytesize
    end

    def read(size = nil)
      fill_buffer(@stdout, @stdout_buffer)
      size ||= @stdout_buffer.bytesize
      return "" if size.to_i <= 0 || @stdout_buffer.empty?
      @stdout_buffer.slice!(0, size.to_i).to_s
    end

    def avail_err
      fill_buffer(@stderr, @stderr_buffer)
      @stderr_buffer.bytesize
    end

    def read_err(size = nil)
      fill_buffer(@stderr, @stderr_buffer)
      size ||= @stderr_buffer.bytesize
      return "" if size.to_i <= 0 || @stderr_buffer.empty?
      @stderr_buffer.slice!(0, size.to_i).to_s
    end

    def write(text)
      return 0 if @stdin == nil || @stdin.closed?
      @stdin.write(text.to_s)
    rescue Exception
      0
    end

    def close
      @stdin.close rescue nil
      @stdout.close rescue nil
      @stderr.close rescue nil
      @wait_thread.kill rescue nil
      @pid = 0
      true
    end

    private

    def fill_buffer(io, buffer)
      return if io == nil || io.closed?
      loop do
        chunk = io.read_nonblock(4096, exception: false)
        break if chunk == :wait_readable || chunk == nil
        buffer << chunk.to_s.b
      end
    rescue Exception
    end
  end

  def native_open_command?(command)
    command.is_a?(Array) && defined?(EltenSystemHelpers) && command[0].to_s == EltenSystemHelpers::NATIVE_OPEN_COMMAND
  rescue Exception
    false
  end

  def child_process_arguments(command)
    return command.map(&:to_s) if command.is_a?(Array)
    text = command.to_s
    return [] if text == ""
    return [text] if File.exist?(text) || File.executable?(text)
    Shellwords.split(text)
  rescue Exception
    [text]
  end
  module_function :child_process_arguments
end
