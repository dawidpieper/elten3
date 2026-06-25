# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
module Log  
class Entry
    attr_reader :level, :message, :time
    attr_accessor:first_occurrence, :occurrences
    def initialize(level, message, time, occurrences=1)
      @level=level
      @message=message
      @time=time
    @occurrences=occurrences
      end
    def to_s(dsplevel=true, dspdate=true)
w=""
if @occurrences>1
  w+="#{@occurrences}x: "
  end
if dsplevel
  case self.level
  when -1
    w+="D: "
    when 0
     w+="I: "
     when 1
       w+="W: "
       when 2
         w+="E: "
       end
     end
     w+=self.message
     if @first_occurrence!=nil
       t=sprintf("%02d:%02d:%02d", self.first_occurrence.hour, self.first_occurrence.min, self.first_occurrence.sec)
    w+=" (#{t} -" if dspdate==true
       end
       t=sprintf("%02d:%02d:%02d", self.time.hour, self.time.min, self.time.sec)
    w+=" "
    w+="(" if @first_occurrence==nil && dspdate==true
       w+="#{t})" if dspdate==true
  return w
      end
  end
  Events=[]
  @@logfile=nil
    class <<self
      include EltenAPI
      def add(level,msg, tm=nil)
        if @@logfile==nil
          path=EltenPath.join(Dirs.eltendata, "elten.log")
          oldpath=EltenPath.join(Dirs.eltendata, "elten.old.log")
          begin
            File.binwrite(oldpath, File.binread(path)) if File.file?(path)
            @@logfile=File.open(path, "wb")
            @@logfile.sync=true
          rescue
            @@logfile=false
          end
          end
                  tm=Time.now if tm==nil
                  e=Entry.new(level, msg, tm)
                Events.push(e)
                                if @@logfile!=false && @@logfile!=nil
tx=e.to_s+"\n"
@@logfile.write(tx)
end
      end
      def debug(msg)
        add(-1,msg)
      end
      def info(msg)
        add(0,msg)
      end
      def warning(msg)
        add(1,msg)
      end
      def error(msg)
        add(2,msg)
      end
      def head(msg)
        add(nil,msg)
      end
      def get(limit=100, level=0, dsplevel=true, dspdate=true)
        lg=[]
        lgh=[]
last=nil
        for i in 0...Events.size
  l=Events[i]
  txt=l.to_s(dsplevel, dspdate)
  if l.level==nil
    lgh.push(txt)
  elsif l.level>=level
if last!=nil && last.message==l.message && last.level==l.level
  lg.delete_at(lg.size-1)
l.occurrences=last.occurrences+1
l.first_occurrence=last.first_occurrence||last.time
txt=l.to_s(dsplevel, dspdate)
  end
    lg.push(txt)
  last=l
        end
  end
  li=0
  li=lg.size-limit if lg.size>limit
return lgh.join("\r\n")+"\r\n"+lg[li..-1].join("\r\n")
       
        end
     end 
   end

   end
