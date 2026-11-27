# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class NVDA < SpeechOutput
  FIDDLE_ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
  F_INT = Fiddle::TYPE_INT
  F_HANDLE = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
  F_PTR = Fiddle::TYPE_VOIDP
  KERNEL32 = Fiddle.dlopen("kernel32.dll")
  ADVAPI32 = Fiddle.dlopen("advapi32.dll")
  CreateNamedPipe=Fiddle::Function.new(KERNEL32["CreateNamedPipeA"], [F_PTR, F_INT, F_INT, F_INT, F_INT, F_INT, F_INT, F_PTR], F_HANDLE, FIDDLE_ABI)
  InitializeSecurityDescriptor = Fiddle::Function.new(ADVAPI32["InitializeSecurityDescriptor"], [F_PTR, F_INT], F_INT, FIDDLE_ABI)
  SetSecurityDescriptorDacl = Fiddle::Function.new(ADVAPI32["SetSecurityDescriptorDacl"], [F_PTR, F_INT, F_PTR, F_INT], F_INT, FIDDLE_ABI)
  SetSecurityInfo = Fiddle::Function.new(ADVAPI32["SetSecurityInfo"], [F_HANDLE, F_INT, F_INT, F_PTR, F_PTR, F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  InitializeAcl = Fiddle::Function.new(ADVAPI32["InitializeAcl"], [F_PTR, F_INT, F_INT], F_INT, FIDDLE_ABI)
  AddAccessAllowedAce = Fiddle::Function.new(ADVAPI32["AddAccessAllowedAce"], [F_PTR, F_INT, F_INT, F_PTR], F_INT, FIDDLE_ABI)
  GetUserNameW = Fiddle::Function.new(ADVAPI32["GetUserNameW"], [F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  LookupAccountNameW = Fiddle::Function.new(ADVAPI32["LookupAccountNameW"], [F_PTR, F_PTR, F_PTR, F_PTR, F_PTR, F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  CloseHandle = Fiddle::Function.new(KERNEL32["CloseHandle"], [F_HANDLE], F_INT, FIDDLE_ABI)
  WriteFile = Fiddle::Function.new(KERNEL32["WriteFile"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  CancelIoEx = Fiddle::Function.new(KERNEL32["CancelIoEx"], [F_HANDLE, F_PTR], F_INT, FIDDLE_ABI)
  # The NVDA bridge polls both input pipes every 25 ms. PeekNamedPipe returns
  # immediately, so releasing the GVL here only adds Ruby thread contention.
  PeekNamedPipe=Fiddle::Function.new(KERNEL32["PeekNamedPipe"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR, F_PTR], F_INT, FIDDLE_ABI, need_gvl: true)
  ReadFile = Fiddle::Function.new(KERNEL32["ReadFile"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  GetCurrentProcessId = Fiddle::Function.new(KERNEL32["GetCurrentProcessId"], [], F_INT, FIDDLE_ABI)
  PIPE_POLL_INTERVAL = 0.025
  MAX_UNACKNOWLEDGED = 10
  @write_mutex = Mutex.new
  @write_ready = ConditionVariable.new
  @lifecycle_mutex = Mutex.new
  @writes = []
  @queued_stops = 0
  @reads = {}

  class <<self
    @@lastid=0

    def init
      @lifecycle_mutex.synchronize { start_pipes }
    end

    private def start_pipes
      close_pipes if @initialized
      @in_flight = []
      @checked = nil
      @prepared = false
      @gestures = []
      @checktime = 0
      @cbckindexing = false
      @index = nil
      @indid = nil
      @iswaiting = true
      @exiting = nil
      @initialized = true
      @pipename="elten"+rand(36**48).to_s(36)
      
     us = [0].pack("I")
      GetUserNameW.call(nil, us)
      usernamew="\0"*us.unpack("I").first*2
      GetUserNameW.call(usernamew, us)

us=[0].pack("I")
      ud=[0].pack("I")
      use = [0].pack("I")
            LookupAccountNameW.call(nil, usernamew, nil, us, nil, ud, use)
            did="\0"*ud.unpack("I").first*2            
            sid="\0"*us.unpack("I").first*2
            LookupAccountNameW.call(nil, usernamew, sid, us, did, ud, use)

                        
      sd = "\0"*20
      InitializeSecurityDescriptor.call(sd, 1)
    acl = "\0"*1024
InitializeAcl.call(acl, 1024, 2)
AddAccessAllowedAce.call(acl, 2, 0x10000000, sid)
SetSecurityDescriptorDacl.call(sd, 1, acl, 0)
      
      sa = EltenWin32.security_attributes(false, sd)
      
      @pipein=CreateNamedPipe.call("\\\\.\\pipe\\"+@pipename+"in", 1, 8, 255, 16*1024**2, 16*1024**2, 1, sa) while @pipein==nil||@pipein==-1
      @pipest=CreateNamedPipe.call("\\\\.\\pipe\\"+@pipename+"st", 1, 8, 255, 16*1024**2, 16*1024**2, 1, sa) while @pipest==nil||@pipest==-1
      @pipeout=CreateNamedPipe.call("\\\\.\\pipe\\"+@pipename+"out", 2, 8, 255, 16*1024**2, 16*1024**2, 1, sa) while @pipeout==nil||@pipeout==-1
      pipefile=EltenPath.join(Dirs.temp, "nvda.pipe")
      if FileTest.exists?(pipefile)
        File.delete(pipefile)
        sleep(0.25)
      end
      
      [@pipein, @pipeout, @pipest].each{|pipe|
      #SetSecurityInfo.call(pipe, 6, 4, nil, nil, nil, nil)
      }
      
      File.binwrite(pipefile, @pipename)
      Log.debug("NVDA pipes registered: #{@pipein}, #{@pipeout}")
      @starttime = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @pipethread = Thread.new { run_pipes(pipefile) }
    end

    private def run_pipes(pipefile)
      pid = GetCurrentProcessId.call
      written = [0].pack("i")
      replies = +""
      statuses = +""
      next_poll = 0
      write_failed = false
      sent_since_poll = false
      frame_command = nil
      frame = nil
      partially_written = false
      loop do
        break if @exiting == :close
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now >= next_poll
          unless File.exist?(pipefile)
            unless @exiting
              play_sound("right")
              worker = Thread.current
              Thread.new do
                @lifecycle_mutex.synchronize { start_pipes if @pipethread == worker && !@exiting }
              end
            end
            break
          end

          @iswaiting = false if @iswaiting && now - @starttime > 1
          if (size = avail) > 0
            each_pipe_message(replies, read(size)) do |reply|
              @reads[reply["id"]] = reply if acknowledge(reply["id"])
            end
          end
          if (size = availst) > 0
            each_pipe_message(statuses, readst(size)) { |status| receive_status(status, pid) }
          end
          next_poll = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PIPE_POLL_INTERVAL
          write_failed = false
          sent_since_poll = false
        end

        while !write_failed && @in_flight.size < MAX_UNACKNOWLEDGED && @exiting != :close
          command = partially_written ? frame_command : next_pipe_write
          break unless command
          unless frame_command.equal?(command)
            frame = JSON.generate(command) + "\n"
            frame_command = command
          end
          ok = WriteFile.call(@pipeout, frame, frame.bytesize, written, 0)
          count = written.unpack1("I")
          if ok == 0 || count == 0
            # The add-on may not have opened its end of the pipe yet.
            write_failed = true
          elsif count < frame.bytesize
            partially_written = true
            frame = frame.byteslice(count..)
          else
            partially_written = false
            frame_command = frame = nil
            @write_mutex.synchronize { shift_pipe_write }
            @in_flight << command["id"]
            sent_since_poll = true
          end
        end
        break if @exiting

        @write_mutex.synchronize do
          if !@writes.empty? && @in_flight.size == MAX_UNACKNOWLEDGED && sent_since_poll
            # Check for ACKs once on filling the window. An unanswered poll waits normally.
            next_poll = 0
          elsif !@exiting && (@writes.empty? || write_failed || @in_flight.size == MAX_UNACKNOWLEDGED)
            remaining = next_poll - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @write_ready.wait(@write_mutex, remaining) if remaining > 0
          end
        end
      end
    rescue StandardError => e
      Log.error("NVDA: #{e.class}: #{e.message}, #{e.backtrace}")
    end

    private def next_pipe_write
      @write_mutex.synchronize do
        while (command = @writes.first)
          action = command["ac"]
          break command unless action == "speak" || action == "stop"
          # Only a later stop followed by another command supersedes this one.
          later_stops = @queued_stops - (action == "stop" ? 1 : 0)
          break command if later_stops == 0 || (later_stops == 1 && @writes.last["ac"] == "stop")
          shift_pipe_write
        end
      end
    end

    # Called with @write_mutex held.
    private def shift_pipe_write
      @queued_stops -= 1 if @writes.shift["ac"] == "stop"
    end

    private def acknowledge(id)
      index = @in_flight.index(id)
      @in_flight.delete_at(index) if index
    end

    private def each_pipe_message(buffer, chunk)
      # Keep a split JSON line for the next poll so it cannot block outbound speech.
      buffer << chunk
      last_newline = buffer.rindex("\n")
      return unless last_newline
      @checktime = Time.now.to_f
      buffer.slice!(0..last_newline).each_line { |line| yield JSON.parse(line) }
    end

    private def receive_status(status, pid)
      @prepared = true
      case status["msgtype"]
      when 1
        acknowledge(status["id"])
      when 2
        @gestures.concat(status["gestures"])
      when 3
        last = status["indexes"].last
        @index = last["index"]
        @indid = last["indid"]
      when 4
        write({ "ac" => "init", "pid" => pid }, nil, true) if status["statuses"].include?("connected")
        @cbckindexing = true if status["statuses"].include?("cbckindexing")
      end
    end

    def initialized?
              @initialized==true
            end
    def braille(text, pos=nil, push=false, type=0, index=nil, cursor=nil)
      return if Configuration.enablebraille==false
                        text=text+""
                        realtext=""
                        @oldbraille="" if @oldbraille==nil
                                                                        case type
                        when -1
                          return if index>=@oldbraille.length
                                                    indexb=index
                          realtext=@oldbraille[0...index].to_s+@oldbraille[(indexb+1)..-1].to_s
                                                    index=realtext[0...index].length
                          @oldrawbraille=""
                                                when 1
                                                  return if index>@oldbraille.length
                                                                                                    realtext=@oldbraille[0...index].to_s+text+@oldbraille[index..-1].to_s
                          index=realtext[0...index].length
                          @oldrawbraille=""
                          when 0
            if @oldrawbraille!=text or @oldrawpos!=pos or push
        @oldrawbraille=text
        @oldrawpos=pos
      else
        return
      end
                                                                                                                                                                              realtext=text
                                                                                                                                                  end
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         if pos!=nil
                          pos=realtext[0...pos].length+1
                          pos=0 if pos<0
                          pos=realtext.length-1 if pos>=realtext.length
                        else
                          pos=0
                        end
                        if cursor!=nil
                          cursor=realtext[0...cursor].length
                        end
                                                                                                                                                  if @oldbraille!=realtext or push
        @oldpos=pos
        @oldcursor=cursor
                              ac={'ac'=>'braille', 'text'=>text}
      ac['pos']=pos if pos!=nil
      ac['cursor']=cursor
      ac['index']=index if index!=nil
      ac['type']=type if type!=nil
      if realtext==""
        ac['type']=0
        ac['text']=""
        ac['pos']=0
      end
      write(ac,nil,true) if @braille_alert==nil
      @oldbraille=realtext
    elsif (pos!=nil and @oldpos!=pos) or @oldcursor!=cursor
                        @oldpos=pos
                        @oldcursor=cursor
      write({'ac'=>'braillepos', 'pos'=>pos,'cursor'=>cursor},nil,true) if @braille_alert==nil
    end
  end
  def braille_alert(text)
    return if Configuration.enablebraille==false
    return if text==@braillealert
    @braillealertthr.exit if @braillealertthr!=nil
    @braille_alert=text
    ac={'ac'=>'braille', 'text'=>text}
              write(ac,nil,true)
              @braillealertthr=Thread.new {
              s=text.length/16.0
              s=1 if s<1
              s=5 if s>5
              sleep(s)
              @braille_alert=nil
                            braille(@oldrawbraille||"", @oldrawpos, true)
                            @braillealertthr=nil
              }
    end
            def speak(text)
              text=text[0...16384] if text.length>16384
              @stopped=false
              @index=nil
            @indid=nil
                                          #sleep(0.01)
      write({'ac'=>'speak', 'text'=>text},nil,true)!=nil
    end
    def speakspelling(text)
              text=text[0...16384] if text.length>16384
              @stopped=false
              @index=nil
            @indid=nil
                                          #sleep(0.01)
      write({'ac'=>'speakspelling', 'text'=>text},nil,true)!=nil
    end
    def speakindexed(texts, indexes, indid=nil)
      if indexes.size>texts.size
        texts=texts.dup
        texts.push("") while texts.size<indexes.size
        end
      s=0
i=0
cur=0
while i<texts.size
  texts[i]=EltenLink.legacy_line_to_text(texts[i])
  if texts[i].length>10000 && texts[i].chrsize>10000
    spl=texts[i].split("")
    texts.insert(i, spl[0...10000].join)
    indexes.insert(i, indexes[i])
    texts[i+1]=spl[10000..-1].join
    end
  cur+=texts[i].length
  if cur>100000
      texts[i..-1]=[]
      indexes[i..-1]=[]
    break
  end
  if texts[i].include?("\n")
texts.insert(i, "\n")
indexes.insert(i, indexes[i])
i+=1
    end
  i+=1
end
      @stopped=false
      @index=nil
            @indid=nil
              #sleep(0.01)
      write({'ac'=>'speakindexed', 'texts'=>texts, 'indexes'=>indexes, 'indid'=>indid}, nil, true)
      end
    def getindex(id=true)
      if @cbckindexing
        if id==false
          return @index
        else
          return [@index,@indid]
          end
        end
            a=write({'ac'=>'getindex'})
            index=nil
            indid=nil
            index=a['index'] if a!=nil
            indid=a['indid'] if a!=nil
                        if id==false
                        return index
                      else
                        return [index,indid]
                        end
          end
              def getversion
            a=write({'ac'=>'getversion'})
            version=nil
            version=a['version'] if a!=nil
            return version
          end
          def getnvdaversion
            a=write({'ac'=>'getnvdaversion'})
            version=nil
            version=a['version'] if a!=nil
            return version
          end
          def getgestures
            return [] if @gestures.size==0 or !@initialized or @checked==false
            g=@gestures.deep_dup
            @gestures.clear
            return g
            end
          def prepared?
            @prepared==true
            end
          def check
            @checked=((Time.now.to_f-(@checktime||0))<=3)
                        return @checked
          end
          def sleepmode
            a=write({'ac'=>'sleepmode'})
            if a==nil
              return nil
            else
              return a['st']
              end
            end
          def sleepmode=(st)
                        write({'ac'=>'sleepmode', 'st'=>st})
            end
          def stop
            if !check
              return 1 if !remote_running?
              return remote_cancel_speech.call
            end
            return if @stopped==true
            @index=nil
            @indid=nil
            @stopped=true
                                                            write({'ac'=>'stop'},nil,true)!=nil
                                    end
        def avail
          dtotal = [0].pack("I")
          PeekNamedPipe.call(@pipein, nil, 0, nil, dtotal, nil)
          dtotal.unpack1("I")
        end
        def read(size=nil)
            size=avail if size==nil
            return "" if size==0
        dread = [0].pack("i")
      buf="\0"*size
        ReadFile.call(@pipein, buf, size, dread, nil)        
        buf.byteslice(0, dread.unpack1("I"))
      end
    def write(ac, timelimit=nil, async=false)
      unless async
        return unless @initialized && ac.is_a?(Hash) && check
        if timelimit.nil?
          size = ac.each_value.sum { |value| value.to_s.size }
          timelimit = size < 1000 ? 1 : 8
        end
      end

      @write_mutex.synchronize do
        ac["tp"] = 1
        ac["id"] ||= @@lastid + 1
        @@lastid = ac["id"]
        ac["async"] = true if async
        wake_sender = @writes.empty?
        @writes << ac
        @queued_stops += 1 if ac["ac"] == "stop"
        @write_ready.signal if wake_sender
      end
      return if async

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timelimit
      loop do
        sleep(0.001)
        break if @reads.key?(ac["id"]) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end
      sleep(0.01) unless @reads.key?(ac["id"])
      reply = @reads.delete(ac["id"])
      Log.warning("NVDA is not responding...") unless reply
      reply
    end

            def availst
              dtotal = [0].pack("I")
              PeekNamedPipe.call(@pipest, nil, 0, nil, dtotal, nil)
              dtotal.unpack1("I")
        end
        def readst(size=nil)
            size=availst if size==nil
            return "" if size==0
        dread = [0].pack("i")
      buf="\0"*size
        ReadFile.call(@pipest, buf, size, dread, nil)        
        buf.byteslice(0, dread.unpack1("I"))
      end
    def waiting?
      return (@iswaiting==true)
    end
    def destroy
      @lifecycle_mutex.synchronize { close_pipes }
    end

    private def request_pipe_stop(mode)
      @write_mutex.synchronize do
        @exiting = mode
        @write_ready.signal
      end
    end

    # Called with the lifecycle mutex held so these handles belong to this worker.
    private def stop_pipe_worker
      request_pipe_stop(:close)
      while @pipethread&.alive?
        # A synchronous write may start just after an earlier cancellation attempt.
        CancelIoEx.call(@pipeout, nil) if @pipeout
        @pipethread.join(PIPE_POLL_INTERVAL)
      end
    end

    private def close_pipes
      return unless @initialized
      stop_pipe_worker
      @pipethread = nil
      pipefile = EltenPath.join(Dirs.temp, "nvda.pipe")
      File.delete(pipefile) if File.exist?(pipefile)
      @initialized = false
      CloseHandle.call(@pipein) if @pipein
      CloseHandle.call(@pipeout) if @pipeout
      CloseHandle.call(@pipest) if @pipest
      @pipein = @pipeout = @pipest = nil
    end

    def join
      worker = @lifecycle_mutex.synchronize do
        request_pipe_stop(:drain) if @pipethread && @exiting != :close
        @pipethread
      end
      return unless worker

      # Give the last queued commands time to reach a responsive add-on.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25
      while worker.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        loop_update
      end
      @lifecycle_mutex.synchronize do
        if @pipethread == worker
          stop_pipe_worker if worker.alive?
          if Dirs.temp
            pipefile = EltenPath.join(Dirs.temp, "nvda.pipe")
            File.delete(pipefile) if File.exist?(pipefile)
          end
        end
      end
      delay(0.1)
    end

    def available?
      true
    end

    def usable?
      check || remote_running?
    end

    def controller_running?
      remote_running?
    end

    def install_addon(path)
      return false if path.to_s == ""
      remote_install_addon.call(wide(path)) == 0
    rescue Exception
      false
    end

    def default?
      usable?
    end

    def voices
      [SpeechOutput::Voice.new(id: "NVDA", name: "NVDA", output: self)]
    end

    def braille_supported?
      true
    end

    def indexed_supported?
      check
    end

    def spelling_supported?
      true
    end

    def speak_text(text, method: 1, spelling: false, interrupt: true, pitch: 50)
      if check
        stop if interrupt
        if spelling
          speakspelling(text.to_s)
        else
          speak(text.to_s)
        end
        return 0
      end
      return 1 if !remote_running?
      remote_speak_text.call(wide(text), method.to_i)
    rescue Exception
      1
    end

    def speak_sequence(seq)
      if check
        seq.reset
        speakindexed(seq.texts, seq.indexes, seq.id)
        return 0
      end
      speak_text(seq.text, method: 1)
    end

    def speak_indexed(texts, indexes, id=nil)
      return 1 if !check
      speakindexed(texts, indexes, id)
      0
    rescue Exception
      1
    end

    def index
      return [nil, nil] if !check
      getindex(true)
    rescue Exception
      [nil, nil]
    end

    private

    def remote_handle
      @remote_handle ||= Fiddle.dlopen(EltenRuntimePaths.find_library("nvdaHelperRemote"))
    end

    def remote_test_running
      @remote_test_running ||= Fiddle::Function.new(remote_handle["nvdaController_testIfRunning"], [], F_INT, FIDDLE_ABI)
    end

    def remote_speak_text
      @remote_speak_text ||= Fiddle::Function.new(remote_handle["nvdaController_speakText"], [F_PTR, F_INT], F_INT, FIDDLE_ABI)
    end

    def remote_cancel_speech
      @remote_cancel_speech ||= Fiddle::Function.new(remote_handle["nvdaController_cancelSpeech"], [], F_INT, FIDDLE_ABI)
    end

    def remote_install_addon
      @remote_install_addon ||= Fiddle::Function.new(remote_handle["nvdaControllerInternal_installAddonPackageFromPath"], [F_PTR], F_INT, FIDDLE_ABI)
    end

    def remote_running?
      remote_test_running.call == 0
    rescue Exception
      false
    end

    def wide(text)
      (text.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace) + [0].pack("S").force_encoding("UTF-16LE")).b
    end
  end
end
