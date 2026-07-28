# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
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
  PeekNamedPipe=Fiddle::Function.new(KERNEL32["PeekNamedPipe"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  ReadFile = Fiddle::Function.new(KERNEL32["ReadFile"], [F_HANDLE, F_PTR, F_INT, F_PTR, F_PTR], F_INT, FIDDLE_ABI)
  GetCurrentProcessId = Fiddle::Function.new(KERNEL32["GetCurrentProcessId"], [], F_INT, FIDDLE_ABI)
  class <<self
    @@lastid=0
    def init
      @waiting=0
                  @lastwrite=""
      @checked=nil
      @prepared=false
      @gestures=[]
            @checktime=0
            @cbckindexing=false
            @index=nil
            @indid=nil
            @iswaiting=true
      destroy if @initialized==true
      @initialized=true        
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
                  Log.debug("NVDA pipes registered: #{@pipein.to_s}, #{@pipeout.to_s}")
                                    @writes||=[]
                                    @reads||={}
            @starttime=Time.now.to_f
            @pipethread=Thread.new {
            pid = GetCurrentProcessId.call
      begin
              dwritten=[0].pack("i")
      loop {
      if !FileTest.exists?(pipefile)
        play_sound('right')
        Thread.new {init}
        break
        end
      if Time.now.to_f-@starttime>1 && @iswaiting
@iswaiting=false
          end
            while @writes.size>0 and @pipeout!=nil and @waiting<10
              if !(@writes.size>1 && (@writes[0]['ac']=="speak" || @writes[0]['ac']=="stop") && @writes[1...-1].map{|x|x['ac']}.include?("stop"))
                              w=JSON.generate(@writes.first)+"\n"
                                                WriteFile.call(@pipeout, w, w.bytesize, dwritten, 0)
                                                                    @waiting+=1
                                                                    end
                                  @writes.delete_at(0)
                                end
                                if @exiting==true
                                  @exited=true
                                  break
                                  end
                                        if @pipein!=nil and (lv=avail)>0
                    r=read(lv)
                    while r[-1..-1]!="\n"
                      sleep(0.001)
                      r+=read(avail)
                    end
                    @checktime=Time.now.to_f
                      b=r.split("\n")
                      for l in b
              j=JSON.load(l)
              @waiting-=1
                                         @reads[j['id']]=j
                                         end
                                       end
            if @pipest!=nil and (lv=availst)>0
                    r=readst(lv)
                    while r[-1..-1]!="\n"
                      sleep(0.001)
                      r+=readst(availst)
                    end
                    @checktime=Time.now.to_f
                                        if !@prepared
                                  @prepared=true
                                  end
                    b=r.split("\n")
                      for l in b
              j=JSON.load(l)
if j['msgtype']==1
  @waiting-=1
              elsif j['msgtype']==2
  @gestures+=j['gestures']
elsif j['msgtype']==3
  @index=j['indexes'][-1]['index']
  @indid=j['indexes'][-1]['indid']
elsif j['msgtype']==4
  write({'ac'=>'init', 'pid'=>pid},nil,true) if j['statuses'].include?("connected")
  @cbckindexing=true if j['statuses'].include?("cbckindexing")
  end
                                         end
                                       end
                        sleep(0.025)
      }
    rescue Exception
      Log.error("NVDA: #{$!.to_s}, #{$@.to_s}")
      end
      }
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
              dread=[0].pack("I")
      dleft=[0].pack("I")
      dtotal=[0].pack("I")
      buf=""
      PeekNamedPipe.call(@pipein,buf,0,dread,dtotal,dleft)
          return dtotal.unpack("I").first
        end
        def read(size=nil)
            size=avail if size==nil
            return "" if size==0
        dread = [0].pack("i")
      buf="\0"*size
        ReadFile.call(@pipein, buf, size, dread, nil)        
        return "" if dread.unpack("i").first==0
        return buf[0..dread.unpack("i").first-1]
      end
    def write(ac, timelimit=nil, async=false)
                              if timelimit==nil
              s=0
              ac.values.each {|x| s+=x.to_s.size}
              if s<1000
                timelimit=1
              else
                timelimit=8
                end
        end
            return if async==false and (!@initialized or !ac.is_a?(Hash) or check==false)
      st=nil
                                                                                                                                                                              ac['tp']=1
      ac['id']=(@@lastid||0)+1 if ac['id']==nil
      @@lastid=ac['id']
      ac['async']=true if async
                                                                                                                                                                                                @writes.push(ac)
                                                                                                                                                                                                return if async
                                                tm=Time.now.to_f
                        loop {
                sleep(0.001)
                        break if @reads[ac['id']]!=nil or Time.now.to_f-tm>timelimit
                  }
                  sleep(0.01) if @reads[ac['id']]==nil
                                                                                                          if @reads[ac['id']]!=nil
                                                  r=@reads[ac['id']]
                                                  @reads.delete(ac['id'])
                                                  st=r
                                                else
                                                                                                                                                          Log.warning("NVDA is not responding...")
              end
              return st
            end
            def availst
              dread=[0].pack("I")
      dleft=[0].pack("I")
      dtotal=[0].pack("I")
      buf=""
      PeekNamedPipe.call(@pipest,buf,0,dread,dtotal,dleft)
          return dtotal.unpack("I").first
        end
        def readst(size=nil)
            size=avail_st if size==nil
            return "" if size==0
        dread = [0].pack("i")
      buf="\0"*size
        ReadFile.call(@pipest, buf, size, dread, nil)        
        return "" if dread.unpack("i").first==0
        return buf[0..dread.unpack("i").first-1]
      end
    def waiting?
      return (@iswaiting==true)
    end
    def destroy
      pipefile=EltenPath.join(Dirs.temp, "nvda.pipe")
      File.delete(pipefile) if FileTest.exists?(pipefile)
              @pipethread.exit if @pipethread!=nil
        @pipethread=nil
              @initialized=false
        CloseHandle.call(@pipein) if @pipein!=nil
        CloseHandle.call(@pipeout) if @pipeout!=nil
        CloseHandle.call(@pipest) if @pipest!=nil
        @pipein=nil
        @pipeout=nil
        @pipest=nil
      end
    def join
      @exiting=true
      loop_update while !@exited
            pipefile=EltenPath.join(Dirs.temp, "nvda.pipe") if Dirs.temp!=nil
            File.delete(pipefile) if pipefile!=nil && FileTest.exists?(pipefile)
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
