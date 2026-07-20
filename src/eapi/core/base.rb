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

def format_localized_date(date, include_weekday: true)
  return "" if date == nil || !date.respond_to?(:year) || !date.respond_to?(:month) || !date.respond_to?(:day)

  weekdays = [
    p_("EAPI_Date_Weekday", "Monday"),
    p_("EAPI_Date_Weekday", "Tuesday"),
    p_("EAPI_Date_Weekday", "Wednesday"),
    p_("EAPI_Date_Weekday", "Thursday"),
    p_("EAPI_Date_Weekday", "Friday"),
    p_("EAPI_Date_Weekday", "Saturday"),
    p_("EAPI_Date_Weekday", "Sunday")
  ]
  months = [
    p_("EAPI_Date_Month_Genitive", "January"),
    p_("EAPI_Date_Month_Genitive", "February"),
    p_("EAPI_Date_Month_Genitive", "March"),
    p_("EAPI_Date_Month_Genitive", "April"),
    p_("EAPI_Date_Month_Genitive", "May"),
    p_("EAPI_Date_Month_Genitive", "June"),
    p_("EAPI_Date_Month_Genitive", "July"),
    p_("EAPI_Date_Month_Genitive", "August"),
    p_("EAPI_Date_Month_Genitive", "September"),
    p_("EAPI_Date_Month_Genitive", "October"),
    p_("EAPI_Date_Month_Genitive", "November"),
    p_("EAPI_Date_Month_Genitive", "December")
  ]
  day = localized_date_day(date.day)
  weekday_index = if date.respond_to?(:cwday)
                    date.cwday.to_i - 1
                  else
                    (Time.local(date.year, date.month, date.day).wday + 6) % 7
                  end
  values = {
    weekday: weekdays[weekday_index],
    month: months[date.month.to_i - 1],
    day: day,
    year: date.year.to_i
  }
  template = if include_weekday
               p_("EAPI_Date_Format", "%{weekday}, %{month} %{day}, %{year}")
             else
               p_("EAPI_Date_Format", "%{month} %{day}, %{year}")
             end
  template % values
rescue ArgumentError, KeyError, TypeError
  sprintf("%04d-%02d-%02d", date.year.to_i, date.month.to_i, date.day.to_i)
end

def localized_date_day(day)
  number = day.to_i
  template = if (11..13).include?(number % 100)
               p_("EAPI_Date_Day", "%{day}th")
             else
               case number % 10
               when 1 then p_("EAPI_Date_Day", "%{day}st")
               when 2 then p_("EAPI_Date_Day", "%{day}nd")
               when 3 then p_("EAPI_Date_Day", "%{day}rd")
               else p_("EAPI_Date_Day", "%{day}th")
               end
             end
  template % { day: number }
rescue ArgumentError, KeyError, TypeError
  number.to_s
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
end
