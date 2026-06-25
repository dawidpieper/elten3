# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require "digest/sha1"
require "fileutils"

module EltenAPI
  private
# EltenAPI functions

# Reads an ini value
#
# @param file [String] a file to read
# @param group [String] an INI group
# @param key [String] an INI key
# @param default [String] this string will be returned if the specified key or file doesn't exist
# @return [String] the ini value of a specified key
            def readini(file,group,key,default="\0")
        default = default.to_s if default.is_a?(Integer)
        return default.to_s if !File.file?(file.to_s)
        current_group=nil
        elten_read_ini_lines(file).each do |line|
          text=line.to_s.strip
          if text =~ /^\[(.+?)\]\s*$/
            current_group=$1.to_s
          elsif current_group!=nil && current_group.casecmp(group.to_s)==0 && text =~ /^([^=]+?)\s*=\s*(.*)$/
            return $2.to_s if $1.to_s.strip.casecmp(key.to_s)==0
          end
        end
        return default.to_s
  end
  
  # Writes a specified value to an INI file
  #
  # @param file [String] a file to write
  # @param group [String] an INI group to write
  # @param key [String] an INI key to write
  # @param value [String] a value to write
  def writeini(file,group,key,value)
    text_value=value.to_s.delete("\r\n") if value!=nil
    file=file.to_s
    group=group.to_s
    key=key.to_s
    lines=File.file?(file) ? elten_read_ini_lines(file) : []
    current_group=nil
    section_found=false
    section_start=nil
    section_end=nil
    key_index=nil
    lines.each_with_index do |line,index|
      text=line.to_s.strip
      if text =~ /^\[(.+?)\]\s*$/
        if section_found && section_end==nil
          section_end=index
        end
        current_group=$1.to_s
        if current_group.casecmp(group)==0
          section_found=true
          section_start=index
        end
      elsif section_found && section_end==nil && current_group!=nil && current_group.casecmp(group)==0 && text =~ /^([^=]+?)\s*=/
        key_index=index if $1.to_s.strip.casecmp(key)==0
      end
    end
    section_end=lines.size if section_found && section_end==nil
    if value==nil
      lines.delete_at(key_index) if key_index!=nil
    elsif key_index!=nil
      lines[key_index]="#{key}=#{text_value}"
    elsif section_found
      lines.insert(section_end, "#{key}=#{text_value}")
    else
      lines << "" if lines.size>0 && lines[-1].to_s.strip!=""
      lines << "[#{group}]"
      lines << "#{key}=#{text_value}"
    end
    FileUtils.mkdir_p(File.dirname(file)) if File.dirname(file)!="."
    File.binwrite(file, lines.join("\r\n")+"\r\n")
    true
              end
              
              

  def unicode(str)
    return nil if str==nil
    str=str.to_s
    str=str.dup.force_encoding(Encoding::UTF_8) if str.encoding==Encoding::ASCII_8BIT
    wide=str.encode("UTF-16LE", invalid: :replace, undef: :replace)
return (wide+[0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
end
  
  def deunicode(str,nulled=false)
    return nil if str==nil
                    str=str.to_s.dup.force_encoding(Encoding::BINARY)
                    str=str.byteslice(0, str.bytesize-1) if str.bytesize.odd?
        if nulled
          nul=nil
          i=0
          while i<str.bytesize-1
            if str.getbyte(i)==0 && str.getbyte(i+1)==0
              nul=i
              break
            end
            i+=2
          end
          str=str.byteslice(0, nul) if nul!=nil
        end
                    text=str.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
                                                                    nul=text.index("\0")
                                                                    return (nul==nil ? text : text[0...nul]).force_encoding("UTF-8")
                                                                  end

  def elten_read_ini_lines(file)
    data=File.binread(file.to_s)
    if data.start_with?("\xFF\xFE".b)
      text=data.byteslice(2..-1).to_s.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    elsif data.start_with?("\xFE\xFF".b)
      text=data.byteslice(2..-1).to_s.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace)
    else
      text=data
      text=text.byteslice(3..-1) if text.start_with?("\xEF\xBB\xBF".b)
      text=text.force_encoding("UTF-8")
      text=text.encode("UTF-8", invalid: :replace, undef: :replace) unless text.valid_encoding?
    end
    text.split(/\r\n|\n|\r/, -1).tap { |lines| lines.pop if lines[-1]=="" }
  rescue Errno::ENOENT
    []
  end
                                                                  
                                                                  def char_to_code(str)
                                                                    unicode(str).unpack("s").first
                                                                  end
                                                                  
                                                                  def code_to_char(code)
                                                                    deunicode([code].pack("s"))
                                                                    end

def format_date(date, justdate=false, secs=true)
  return "" if !date.is_a?(Time)
  str=sprintf("%04d-%02d-%02d", date.year, date.month, date.day)
  if !justdate  
  str+=sprintf(" %02d:%02d", date.hour, date.min)
  str+=sprintf(":%02d", date.sec) if secs
  end
  return str
  end

# Wait for a specified time
#
# @param time [Float] a time to delay, in seconds
# @param breakOnEscape [Boolean] whether function should break if escape was pressed
#
# returns whether delay has been broken
def delay(time=0, breakOnEscape=false, &breakProc)
  deadline = Time.now.to_f + time.to_f
  while Time.now.to_f < deadline
    loop_update
    if (breakOnEscape && key_pressed?(:key_escape)) || (breakProc!=nil && breakProc.call==true)
      loop_update
      return true
      end
    end
  return false   
  end
     
     def delay_precise(time)
       t=Time.now.to_f
       fin=t+time
       cs=defined?(EltenAPI::TICK_SECONDS) ? EltenAPI::TICK_SECONDS : 0.01
       loop_update while fin-Time.now.to_f>cs*2
         sleep((fin-Time.now.to_f)*0.8) while fin-Time.now.to_f>0
         return time
       end

       def secure_wait(timeout=0, &b)
         raise(ArgumentError, "No block given") if b==nil
         raise(ArgumentError, "timeout must be numeric") if !timeout.is_a?(Numeric)
st=nil
         th=Thread.new{st=b.call}
tim=sttim=Time.now.to_f
         while th.status!=false && th.status!=nil
           if Time.now.to_f-tim>1
             loop_update
             tim=Time.now.to_f
             end
  if Time.now.to_f-sttim>timeout && timeout>0
    th.exit
    return nil
    end
             end
return st
  end

         def readconfig(group, key, val="")
  r=readini(EltenPath.join(Dirs.eltendata, "elten.ini"), group, key, "$DEFAULT")
  if r=="$DEFAULT"
    writeconfig(group, key, val)
    r=val
    end
  return r.to_i if val.is_a?(Integer)
  return r
end

def writeconfig(group, key, val)
  Log.debug("Changing configuration: (#{group}:#{key}): #{val.to_s}")
  val=val.to_s if val!=nil
  writeini(EltenPath.join(Dirs.eltendata, "elten.ini"), group, key, val)
end

module LocalConfig
  LCCache={}
  LOCache={}
  class <<self
    def [](k, default=0)
      return 0 if !k.is_a?(String)
      if LCCache[k]!=nil
        return unformat(LCCache[k])
        else
            v=readconfig("Local", k, format(default))
            un=unformat(v)
            return default if default.class.name!=un.class.name
            LCCache[k]=v
            LOCache[k]=v
            return un
            end
          end
          def unformat(t)
            if t.is_a?(Integer)
              return t
            elsif t[0..0]=="["
              return t[1...-1].split(",").map{|o|unformat(o)}
            else
              return t.to_i
              end
            end
            def format(t)
              if t.is_a?(Integer)
                return t.to_s
              elsif t.is_a?(Array)
                return "["+t.find_all{|l|l.is_a?(Integer)}.join(",")+"]"
                end
              end
    def []=(k,v)
            return 0 if !k.is_a?(String) || (!v.is_a?(Integer) && !v.is_a?(Array))
            if v.is_a?(Array)
                            v="["+v.find_all{|l|l.is_a?(Integer)}.join(",")+"]"
              end
            LCCache[k]=v
            writeconfig("local", k, v) if v!=LOCache[k]
LOCache[k] = v
          end
          def save
            for k in LCCache.keys
              v=LCCache[k]
              writeconfig("local", k, v) if v!=LOCache[k]
LOCache[k] = v
              end
            end
    end
  end

def insert_scene(scene, must=false, return_to_main: false)
  return if (($scenes[0]!=nil and $scenes[0].is_a?(scene.class)) or $scene.is_a?(scene.class)) and !must
  scene.instance_variable_set(:@insert_scene_return_to_main, true) if return_to_main && scene != nil
      if $scene.is_a?(Scene_Main) and $scenes.size==0
    return $scene=scene
  end
  $subthreads||=[]
  $scenes||=[]
  Log.info("Inserting new parallel scenes thread #{($subthreads.size+$scenes.size+1).to_s}")
  $scenes.insert(0,scene)
  t=Time.now.to_f
  loop_update(false) while Time.now.to_f-t<0.2
end
      def crypt(data,code=nil)
        return "".b if !EltenSystemHelpers.autologin_key_encryption_supported?
        EltenSystemHelpers.protect_data(data, code)
        end
        
        def decrypt(data,code=nil)
        return nil if !EltenSystemHelpers.autologin_key_encryption_supported?
        m=EltenSystemHelpers.unprotect_data(data, code)
        Log.warning("Failed to decrypt data") if m==nil
        m
end

          def bfs(mat, x, y, ox, oy) 
rowNum = [-1, 0, 0, 1]
colNum = [0, -1, 1, 0]
return nil if(mat[x][y]==false or mat[ox][oy]==false)
visited=[]
for i in 0...mat.size
visited[i]=[]
for j in 0...mat[i].size
visited[i][j]=false
end
end
visited[x][y] = true
q = [[[x,y], []]]
while !q.empty?
curr = q[0]
if(curr[0][0] == ox && curr[0][1] == oy)
return curr[1]
end
q.delete_at(0)
for i in 0...4
  row = curr[0][0] + rowNum[i]
col = curr[0][1] + colNum[i]
if row>=0 && col>=0 && row<mat.size && col<mat[row].size && mat[row][col]==true && !visited[row][col]
visited[row][col]=true
adjcell = [[row, col], curr[1]+[[row,col]]]
q.push(adjcell)
end
end
end
return nil
end

class Reset < Exception
end

class Hangup < Exception
end
      
    def current_executable_path
      if defined?(EltenEmbedded)
        launcher_executable = ENV["ELTEN_LAUNCHER_EXECUTABLE_PATH"].to_s
        return File.expand_path(launcher_executable) if launcher_executable != ""
        if Process.respond_to?(:execpath)
          executable=Process.execpath.to_s
          expanded = File.expand_path(executable) if executable != ""
          return expanded if expanded.to_s != "" && File.executable?(expanded)
        end
        if defined?(EltenRuntimePaths)
          return EltenSystemHelpers.embedded_executable_path(EltenRuntimePaths.root, EltenRuntimePaths.architecture)
        end
      end
      File.expand_path(RbConfig.ruby)
    rescue Exception
      File.expand_path($PROGRAM_NAME.to_s)
    end

    def restart_to_developer_mode
      command = developer_restart_command
      if command.to_s == ""
        Log.error("Developer restart failed: empty restart command")
        return false
      end
      Log.info("Restarting Elten in developer mode: #{command}")
      $exit_runproc = command
      $exit_runproc_path = Dir.pwd
      $exit = true
      $scene = nil
      true
    rescue Exception => e
      Log.error("Developer restart failed: #{e.class}: #{e.message}")
      false
    end

    def developer_restart_command
      parts = restart_command_parts
      parts << "/developer"
      EltenSystemHelpers.command_line_join(parts)
    end

    def restart_command_parts
      parts = original_process_arguments
      if parts.size > 0
        parts = parts.dup
        parts[0] = current_executable_path if defined?(EltenEmbedded)
        return parts
      end
      fallback_restart_command_parts
    end

    def original_process_arguments
      if defined?(::ELTEN_LAUNCHER_ARGV) && ::ELTEN_LAUNCHER_ARGV.is_a?(Array) && ::ELTEN_LAUNCHER_ARGV.size > 0
        return ::ELTEN_LAUNCHER_ARGV.map(&:to_s)
      end
      if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:original_process_arguments)
        args = EltenSystemHelpers.original_process_arguments
        return args.map(&:to_s) if args.is_a?(Array) && args.size > 0
      end
      []
    rescue Exception
      []
    end

    def fallback_restart_command_parts
      executable = current_executable_path
      parts = [executable]
      parts << $PROGRAM_NAME.to_s if !defined?(EltenEmbedded) && $PROGRAM_NAME.to_s != "" && $PROGRAM_NAME.to_s != "-e"
      parts + ARGV.map(&:to_s)
    end

    def load_configuration
        Log.info("Loading configuration")
        lang=Configuration.language
  Configuration.listtype = readconfig("Interface", "ListType", 0)
  Configuration.disablefeednotifications = readconfig("Interface", "DisableFeedNotifications", 0)
  Configuration.iimodifiers = readconfig("InvisibleInterface", "IIModifiers", 0)
  Configuration.iicards = readconfig("InvisibleInterface", "Cards", "messages,feed,conference")
  Configuration.roundupforms = readconfig("Interface", "RoundUpForms", 0)
  Configuration.usepan = readconfig("Interface", "UsePan", 1)
  Configuration.soundcard = readconfig("SoundCard", "SoundCard", "")
  if Configuration.soundcard==""
                Sapi.set_device(-1) if defined?(Sapi)
                  Bass.setdevice(-1)
                else
    sc=Bass.soundcards
  for i in 0...sc.size
    if sc[i].name==Configuration.soundcard
    Bass.setdevice(i)
    end
  end
    devices=defined?(Sapi) ? Sapi.devices : []
    for i in 0...devices.size
            if Configuration.soundcard==devices[i]
                Sapi.set_device(i)
        end
      end
      end
Configuration.microphone = readconfig("SoundCard", "Microphone", "")
  s=false
  mc=Bass.microphones
  for i in 0...mc.size
    if mc[i].name==Configuration.microphone
          Bass.setrecorddevice(i)
    s=true
    end
  end
  if s==false
    defl=mc.index(mc.find{|m|m.default?})||-1
  Bass.setrecorddevice(defl)
  end
    Configuration.controlspresentation = readconfig("Interface", "ControlsPresentation", 0)
  Configuration.contextmenubar = readconfig("Interface", "ContextMenuBar", 1)
Configuration.soundthemeactivation = readconfig("Interface", "SoundThemeActivation", 1)
Configuration.typingecho = readconfig("Interface", "TypingEcho", 0)
Configuration.bgsounds = readconfig("Interface", "BGSounds", 1)
Configuration.linewrapping = readconfig("Interface", "LineWrapping", 1)
Configuration.hidewindow = readconfig("Interface", "HideWindow", 0)
Configuration.synctime = readconfig("Advanced", "SyncTime", 1)
Configuration.saytimeperiod = readconfig("Clock", "SayTimePeriod", 1)
Configuration.saytimetype = readconfig("Clock", "SayTimeType", 1)
Configuration.registeractivity = readconfig("Privacy", "RegisterActivity", -1)
Configuration.checkupdates = readconfig("Updates", "CheckAtStartup", 1)
Configuration.autoplay = readconfig("Interface", "AutoPlay", 0)
Configuration.branch = readconfig("Updates", "Branch", "")
if tray_supported?
c_autostart=readconfig("System", "AutoStart", 0)
path=EltenSystemHelpers.autostart_executable_path(current_executable_path)
c_autostart=0 if !EltenSystemHelpers.autostart_executable?(path)
autostart_cmd=EltenSystemHelpers.autostart_command(path)
EltenSystemHelpers.sync_autostart(c_autostart, autostart_cmd)
end
Configuration.voice = readconfig("Voice","Voice","")
if $rvc==nil
      if (/\/voice (-?)(\d+)/=~$commandline) != nil
        $rvc=$1+$2
        Configuration.voice=$rvc.to_s
            end    
          end
          if Configuration.voice.to_i.to_s==Configuration.voice
            if Configuration.voice.to_i==-1
              Configuration.voice=defined?(NVDA) ? "NVDA" : ""
              elsif Configuration.voice.to_i>=0
            voices=defined?(Sapi) ? SpeechOutput.voices.find_all{|voice|voice.output==Sapi} : []
            if Configuration.voice.to_i<voices.size
            Configuration.voice=voices[Configuration.voice.to_i].voiceid
          else
            Configuration.voice=""
          end
        else
          Configuration.voice=""
        end
                  writeconfig("Voice", "Voice", Configuration.voice)
                end
                Configuration.enablebraille = readconfig("Interface", "EnableBraille", 0)
                Configuration.usevoicedictionary = readconfig("Voice", "UseVoiceDictionary", 1)
          Configuration.language = readconfig("Interface", "Language", "")
          if Configuration.language.include?("_")
            Configuration.language.gsub!("_","-")
            writeconfig("Interface", "Language", Configuration.language)
          end
          Configuration.voicerate = readconfig("Voice","Rate",50)
        if $rvcr==nil
      if (/\/voicerate (\d+)/=~$commandline) != nil
        $rvcr=$1
        Configuration.voicerate=$rvcr.to_i
            end    
    end

                  SpeechOutput.list.each{|output| output.set_rate(Configuration.voicerate) if output.rate_supported?}
                      Configuration.voicevolume = readconfig("Voice","Volume",100)
    if $rvcv==nil
      if (/\/voicevolume (\d+)/=~$commandline) != nil
        $rvcv=$1
        Configuration.voicevolume=$rvcv.to_i
            end    
    end
    SpeechOutput.list.each{|output| output.set_volume(Configuration.voicevolume) if output.volume_supported?}
    Configuration.voicepitch = readconfig("Voice","Pitch",50)
    if Configuration.voice!="" && Configuration.voice!="?"
                      output=SpeechOutput.output_for_voice(Configuration.voice)
                      if output!=nil
                        output.apply_voice(Configuration.voice)
                      else
                        Configuration.voice=""
                        writeconfig("Voice", "Voice", Configuration.voice)
                      end
                    end
                    if Configuration.voice==""
                      Sapi.apply_default_voice if defined?(Sapi)
    end
    SpeechOutput.apply_current_settings if defined?(SpeechOutput)
          Configuration.soundtheme = readconfig("Interface","SoundTheme","")
            Configuration.soundtheme=nil if Configuration.soundtheme.size == 0
stheme=nil
stheme=EltenPath.join(Dirs.soundthemes, Configuration.soundtheme+".elsnd") if Configuration.soundtheme!=nil
use_soundtheme(stheme)
                          Configuration.volume = readconfig("Interface", "MainVolume", 50)
                          Configuration.usefx = readconfig("Advanced", "UseFX", -1)
                          Configuration.usedenoising = readconfig("Advanced", "UseDenoising", 0)
                          Configuration.useechocancellation = readconfig("Advanced", "UseEchoCancellation", 0)
                          Configuration.usebilinearhrtf = readconfig("Advanced", "UseBilinearHRTF", 0)
                          Configuration.disableconferencemiconrecord = readconfig("Advanced", "DisableConferenceMicOnRecord", 0)
                          Configuration.enableaudiobuffering = readconfig("Advanced", "EnableAudioBuffering", 0)
                          Configuration.sessiontime = readconfig("Advanced", "AgentSessionTime", 2)
                          Configuration.disablehttp2 = readconfig("Advanced", "DisableHTTP2", 0)
                      Configuration.tcpconferences = readconfig("Advanced", "ConferencesTCPOnly", 0)
                      Configuration.conferencesaudiobuffer = readconfig("Advanced", "ConferencesAudioBuffer", 0)
                      Configuration.conferencesaudiobuffercutoff = readconfig("Advanced", "ConferencesAudioBufferCutOff", 250)
                      Configuration.udppacketsize = readconfig("Advanced", "UDPMaxPacketSize", 1480)
                          Configuration.autologin = readconfig("Login", "EnableAutoLogin", 1)
                          if lang!=Configuration.language
                            setlocale(Configuration.language)
                            SpeechOutput.apply_current_settings if defined?(SpeechOutput)
                          end
                                if Configuration.registeractivity==-1
  Configuration.registeractivity = (confirm(p_("EAPI_EltenAPI", "Do you want to send reports on how Elten is used? This data does not contain any confidential information and is very helpful in program development. This selection can be changed at any time from the Settings.")) ? 1 : 0)
  writeconfig("Privacy", "RegisterActivity", Configuration.registeractivity)
  end
  if Elten.branch.to_s.downcase!="stable" && Configuration.registeractivity==0
    delay(1)
    alert(p_("EAPI_EltenAPI", "You are currently using a beta version of Elten. In these versions, uploading usage statistics is always enabled. They contain information about the most frequently used functions, configurations and problems with program operation. They do not contain any confidential or private information. If you do not want to send statistics, please use the stable version of Elten."))    
  Configuration.registeractivity = 1
  writeconfig("Privacy", "RegisterActivity", Configuration.registeractivity)
  end             
                        end
              
def eltencred(data)
  $eltencred_mutex ||= Mutex.new
  $eltencred_mutex.synchronize do
    $eltencred ||= begin
      pem = EltenAPI::Resources.read("eltencredpub.pem")
      pem.to_s == "" ? nil : OpenSSL::PKey::RSA.new(pem)
    rescue Exception => e
      Log.warning("Credential public key load error: #{e.class}: #{e.message}") if defined?(Log)
      nil
    end
    return data.to_s.b if $eltencred == nil
    $eltencred.public_encrypt(data.to_s.b)
  end
end
            
            def synchsafe(input)
out=0
mask=0x7f
while (mask ^ 0x7FFFFFFF)!=0
out = input & ~mask
out = out << 1;
out = out | (input & mask);
mask = ((mask + 1) << 8) - 1;
input = out;
	end
return out;
end

def unsynchsafe(input)
out=0
mask = mask = 0x7F000000;
while mask!=0
out = out >> 1
out = out | (input & mask)
mask = mask >> 8;
end
return out;
end

class FileCache
  attr_reader :file
@@caches=[]
def self.get_caches
  return @@caches
  end
def initialize(file)
@file=file
a=@@caches.find{|c|c.file==@file}
@current=a.current if a !=nil
@@caches.push(self)
end
    def current
      @current||=nil
      if(@current==nil)
        begin
        if FileTest.exists?(@file)
          @current = Marshal.load(File.binread(@file))
        end
      rescue Exception
      end
      @current={} if @current==nil
    end
    return @current
  end

  def save
    c=current
    for entry in c.keys
      del=(c[entry]['totime']!=0 && c[entry]['totime']<=Time.now.to_i) || c[entry]['lastaccess']<Time.now.to_i-86400*30
      c.delete(entry) if del
      end
    File.binwrite(@file, Marshal.dump(c))
  end
  
  def get(entry, totime=-1, &b)
    v=nil
    c=current
    e=c[entry]
      if e==nil
        v=b.call if b!=nil
        set(entry, v, totime) if v!=nil
        return v
        end
     totime=e['totime']
     if totime<=Time.now.to_i && totime!=0
       v=b.call if b!=nil
        set(entry, v, totime) if v!=nil
        return v
       end
e['lastaccess']=Time.now.to_i
     return e['value']
    rescue Exception
      v=nil
      v=b.call if b!=nil
        set(entry, v, totime) if v!=nil
        return v
    end

    def exists?(entry)
c=current
    e=c[entry]
      return false if e==nil
     totime=e['totime']
     return false if totime<=Time.now.to_i && totime!=0
e['lastaccess']=Time.now.to_i
     return true
    rescue Exception
return false      
      end
    
    def delete(entry)
      c=current
      c.delete(entry) if c[entry]!=nil
      end
    
    def set(entry, value, totime=-1)
      totime=Time.now.to_i+86400 if totime==-1
      totime=Time.at(totime) if totime.is_a?(Time)
      c=current
      c[entry] = {'value'=>value, 'totime'=>totime, 'lastaccess'=>totime}
      return value
    end
    
def [](entry)
  return get(entry)
end

def []=(entry,value)
  set(entry, value)
  end
end

module Cache
  class <<self
    def get_cache
      @cache||=nil
      @cache=FileCache.new(EltenPath.join(Dirs.eltendata, "cache.dat")) if @cache==nil
      return @cache
    end
   def current
     return get_cache.current
   end
   def save
     return get_cache.save
   end
   def exists?(*a)
     return get_cache.exists?(*a)
     end
   def get(*a, &b)
     return get_cache.get(*a, &b)
   end
   def set(*a)
     return get_cache.set(*a)
   end
   def delete(*a)
     return get_cache.delete(*a)
   end
   def [](a)
     return get_cache[a]
   end
   def []=(a,b)
     return get_cache[a]=b
     end
  end
  end
  
  def get_updatesbranch
    if Configuration.branch==""
      return Elten.branch
    else
      return Configuration.branch
      end
    end
end
