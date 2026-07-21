# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "fiddle"

module EltenAPI
  WINAPI_ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT unless const_defined?(:WINAPI_ABI)
  F_INT = Fiddle::TYPE_INT unless const_defined?(:F_INT)
  F_PTR = Fiddle::TYPE_VOIDP unless const_defined?(:F_PTR)
  F_HANDLE = EltenWin32::POINTER_SIZE == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT unless const_defined?(:F_HANDLE)
  PROCESS_KERNEL32 = Fiddle.dlopen("kernel32.dll") unless const_defined?(:PROCESS_KERNEL32)
  CREATE_PROCESS_W = Fiddle::Function.new(PROCESS_KERNEL32["CreateProcessW"], [F_PTR, F_PTR, F_PTR, F_PTR, F_INT, F_INT, F_PTR, F_PTR, F_PTR, F_PTR], F_INT, WINAPI_ABI) unless const_defined?(:CREATE_PROCESS_W)
  GET_EXIT_CODE_PROCESS = Fiddle::Function.new(PROCESS_KERNEL32["GetExitCodeProcess"], [F_HANDLE, F_PTR], F_INT, WINAPI_ABI) unless const_defined?(:GET_EXIT_CODE_PROCESS)
  TERMINATE_PROCESS = Fiddle::Function.new(PROCESS_KERNEL32["TerminateProcess"], [F_HANDLE, F_INT], F_INT, WINAPI_ABI) unless const_defined?(:TERMINATE_PROCESS)
  EXIT_PROCESS = Fiddle::Function.new(PROCESS_KERNEL32["ExitProcess"], [F_INT], Fiddle::TYPE_VOID, WINAPI_ABI) unless const_defined?(:EXIT_PROCESS)
  CREATE_PIPE = Fiddle::Function.new(PROCESS_KERNEL32["CreatePipe"], [F_PTR, F_PTR, F_PTR, F_INT], F_INT, WINAPI_ABI) unless const_defined?(:CREATE_PIPE)
  SET_HANDLE_INFORMATION = Fiddle::Function.new(PROCESS_KERNEL32["SetHandleInformation"], [F_HANDLE, F_INT, F_INT], F_INT, WINAPI_ABI) unless const_defined?(:SET_HANDLE_INFORMATION)
  CLOSE_HANDLE = Fiddle::Function.new(PROCESS_KERNEL32["CloseHandle"], [F_HANDLE], F_INT, WINAPI_ABI) unless const_defined?(:CLOSE_HANDLE)
  PEEK_NAMED_PIPE = Fiddle::Function.new(PROCESS_KERNEL32["PeekNamedPipe"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR, F_PTR], F_INT, WINAPI_ABI) unless const_defined?(:PEEK_NAMED_PIPE)
  READ_FILE = Fiddle::Function.new(PROCESS_KERNEL32["ReadFile"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR], F_INT, WINAPI_ABI) unless const_defined?(:READ_FILE)
  WRITE_FILE = Fiddle::Function.new(PROCESS_KERNEL32["WriteFile"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR], F_INT, WINAPI_ABI) unless const_defined?(:WRITE_FILE)
  CREATE_NO_WINDOW = 0x08000000 unless const_defined?(:CREATE_NO_WINDOW)

  private

  # Runs a binary file.
  #
  # @param file [String] a command line to run
  # @param hide [Boolean] if true, the new process's window is hidden
  # @param path [String] working directory
  # @param addToProcs [Boolean] whether to terminate the process on Elten shutdown
  # @return [Numeric] process handle for WinAPI launches or pid for detached native launches
  def run(file, hide=false, path=nil, addToProcs=true)
    Log.debug("Running process: #{file}")
    path=EltenPath.dirname($path) if path==nil
    if hide!=true && addToProcs!=true
      begin
        pid=Process.spawn(file.to_s, chdir: path)
        Process.detach(pid) rescue nil
        return pid
      rescue Exception
        Log.warning("Native Process.spawn failed, falling back to CreateProcessW: #{$!.class}: #{$!.message}")
      end
    end
    startinfo = EltenWin32.startup_info(hide ? 0 : nil)
    procinfo  = EltenWin32.process_information_buffer
    CREATE_PROCESS_W.call(0, unicode(file), 0, 0, 0, 0, 0, unicode(path), startinfo, procinfo)
    process_info = EltenWin32.process_information(procinfo)
    if addToProcs
      $procs=[] if $procs==nil
      $procs.push(process_info[:process_handle])
    end
    process_info[:process_handle]
  end

  # Executes a process and waits for it to close.
  #
  # @param cmdline [String] a command line to execute
  # @param hide [Boolean] hide a process window
  # @param tmax [Numeric] maximum execution time, 0 = infinity
  # @param update [Boolean] refresh application loop while waiting
  # @param path [String] working directory
  # @return [String, Numeric] process exit code as legacy binary string, or -1 on timeout
  def executeprocess(cmdline, hide=false, tmax=0, update=true, path=nil)
    h=run(cmdline, hide, path)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f
    loop do
      if update
        loop_update
      else
        sleep(0.1)
      end
      x="\0"*1024
      GET_EXIT_CODE_PROCESS.call(h,x)
      x.delete!("\0")
      break if x != "\003\001"
      t = (Process.clock_gettime(Process::CLOCK_MONOTONIC) rescue Time.now.to_f) - started_at
      if t > tmax && tmax!=0
        return -1
      end
    end
    x="\0"*1024
    GET_EXIT_CODE_PROCESS.call(h,x)
    x.delete!("\0")
    x
  end

  def terminate_process_handle(handle)
    return if handle==nil || handle==0 || handle==-1
    TERMINATE_PROCESS.call(handle, 0)
  end

  def exit_process(code=0)
    EXIT_PROCESS.call(code.to_i)
  end

  class ChildProc
    attr_reader :pid, :process_id

    def initialize(file, l_path=nil, path: nil, show_window: false)
      path ||= l_path
      path ||= Dir.pwd
      @stdin_rd = EltenWin32.pointer_buffer
      @stdin_wr = EltenWin32.pointer_buffer
      @stdout_rd = EltenWin32.pointer_buffer
      @stdout_wr = EltenWin32.pointer_buffer
      @stderr_rd = EltenWin32.pointer_buffer
      @stderr_wr = EltenWin32.pointer_buffer
      saAttr=EltenWin32.security_attributes(true)
      CREATE_PIPE.call(@stdout_rd, @stdout_wr, saAttr, 1048576*32)
      SET_HANDLE_INFORMATION.call(EltenWin32.pointer_value(@stdout_rd), 1, 0)
      CREATE_PIPE.call(@stderr_rd, @stderr_wr, saAttr, 1048576*32)
      SET_HANDLE_INFORMATION.call(EltenWin32.pointer_value(@stderr_rd), 1, 0)
      CREATE_PIPE.call(@stdin_rd, @stdin_wr, saAttr, 1048576*32)
      SET_HANDLE_INFORMATION.call(EltenWin32.pointer_value(@stdin_wr), 1, 0)

      startinfo = EltenWin32.startup_info(show_window ? nil : 0, EltenWin32.pointer_value(@stdin_rd), EltenWin32.pointer_value(@stdout_wr), EltenWin32.pointer_value(@stderr_wr), true)
      @procinfo = EltenWin32.process_information_buffer
      creation_flags = show_window ? 0 : CREATE_NO_WINDOW
      pr = CREATE_PROCESS_W.call(0, wide(file), nil, nil, 1, creation_flags, 0, wide(path), startinfo, @procinfo)
      if pr==0
        close_handle_buffer(@stdin_rd)
        close_handle_buffer(@stdin_wr)
        close_handle_buffer(@stdout_rd)
        close_handle_buffer(@stdout_wr)
        close_handle_buffer(@stderr_rd)
        close_handle_buffer(@stderr_wr)
        @pid=0
        @process_id=0
        raise "CreateProcessW failed: #{file}"
      end
      info = EltenWin32.process_information(@procinfo)
      @pid = info[:process_handle]
      @process_id = info[:process_id]
      @thread_handle = info[:thread_handle]
      close_handle(@thread_handle)
      close_handle_buffer(@stdin_rd)
      close_handle_buffer(@stdout_wr)
      close_handle_buffer(@stderr_wr)
    end

    def close_handle(handle)
      return if handle==nil || handle==0 || handle==-1
      CLOSE_HANDLE.call(handle)
    end

    def close_handle_buffer(buffer)
      handle=EltenWin32.pointer_value(buffer)
      close_handle(handle)
      EltenWin32.set_pointer(buffer, 0, 0)
    end

    def running?
      return false if @pid==nil || @pid==0
      x="\0"*4
      GET_EXIT_CODE_PROCESS.call(@pid,x)
      x.unpack("I").first==259
    end

    def terminate
      TERMINATE_PROCESS.call(@pid,0)
    end

    def avail
      dread=[0].pack("I")
      dleft=[0].pack("I")
      dtotal=[0].pack("I")
      buf=""
      PEEK_NAMED_PIPE.call(EltenWin32.pointer_value(@stdout_rd),buf,0,dread,dtotal,dleft)
      dtotal.unpack("I").first
    end

    def read(size=nil)
      size=avail if size==nil
      return "" if size==0
      dread = [0].pack("i")
      buf="\0"*size
      READ_FILE.call(EltenWin32.pointer_value(@stdout_rd), buf, size, dread, nil)
      return "" if dread.unpack("i").first==0
      buf[0..dread.unpack("i").first-1]
    end

    def avail_err
      dread=[0].pack("I")
      dleft=[0].pack("I")
      dtotal=[0].pack("I")
      buf=""
      PEEK_NAMED_PIPE.call(EltenWin32.pointer_value(@stderr_rd),buf,0,dread,dtotal,dleft)
      dtotal.unpack("I").first
    end

    def read_err(size=nil)
      size=avail_err if size==nil
      return "" if size==0
      dread = [0].pack("i")
      buf="\0"*size
      READ_FILE.call(EltenWin32.pointer_value(@stderr_rd), buf, size, dread, nil)
      return "" if dread.unpack("i").first==0
      buf[0..dread.unpack("i").first-1]
    end

    def write(text)
      return 0 if EltenWin32.pointer_value(@stdin_wr)==0
      dwritten = [0].pack("i")
      WRITE_FILE.call(EltenWin32.pointer_value(@stdin_wr), text, text.bytesize, dwritten, 0)
      dwritten.unpack("i").first
    end

    def close
      close_handle_buffer(@stdin_wr)
      close_handle_buffer(@stdout_rd)
      close_handle_buffer(@stderr_rd)
      close_handle(@pid)
      @pid=0
    end

    private

    def wide(value)
      (value.to_s.encode("UTF-16LE") + [0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
    end
  end
end
