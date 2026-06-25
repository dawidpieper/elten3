# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Object
  def deep_dup
        dup if self!=nil
      end
      def elten_text_utf8(value)
        str=value.to_s
        return str if str.encoding==Encoding::UTF_8 && str.valid_encoding?
        str=str.dup
        str.force_encoding(Encoding::UTF_8) if str.encoding==Encoding::ASCII_8BIT
        str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      rescue Encoding::CompatibilityError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        str.to_s.b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
      private :elten_text_utf8
      private
      def polsorter(a,b)
            if !a.is_a?(String) || !b.is_a?(String)
      a<=>b
    else
      EltenSystemHelpers.locale_compare(a, b)
              end
        end
      def polsort_key(value)
        EltenSystemHelpers.locale_sort_key(value)
      end
end

class Numeric
    def deep_dup
    self
  end
def to_b
  return false if self==0
  return true
  end
  end

class TrueClass
    def deep_dup
    self
  end
  def to_i
    return 1
  end
  def to_b
    return true
    end
end

class FalseClass
    def deep_dup
    self
  end
  def to_i
    return 0
  end
  def to_b
    return false
    end
end

class Array
    alias_method :elten_native_find_index, :find_index unless method_defined?(:elten_native_find_index)
    def find_index(*args, &block)
      if block_given?
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0)" if args.size>0
        return elten_native_find_index(&block)
      end
      return enum_for(:find_index) if args.empty?
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0..2)" if args.size>2
      index=elten_native_find_index(args[0])
      return args[1] if index==nil && args.size==2
      index
    end
      def deep_dup
    return [] if self == []
        map {|x| x.deep_dup}
  end    
  def to_s
    r="["
    for i in 0...self.size
      r+=", " if i>0
      r+=self[i].to_s
      end
    r+="]"
    return r
    end
    def shuffle
t=self+[]      
res=[]
for o in t
  v=-1
  while v==-1 or res[v]!=nil
  v=rand(t.size)
  end
    res[v]=o
  end
  return res  
  end
  def shuffle!
    n=shuffle
    for i in 0..n.size-1
      self[i]=n[i]
      end
    return self
  end
  def sum
    return 0 if self.size==0
    s=self[0]
    self[1..-1].each {|a| s+=a}
    return s
  end
  def polsort
        return self.sort_by {|a| polsort_key(a)} if self.all? {|a| a.is_a?(String)}
        a=self.sort {|a,b|
polsorter(a,b)
    }
    return a
  end
  def polsort!
    a=self.polsort
    for i in 0...self.size
      self[i]=a[i]
      end
    end
  end

class String
  def deutf8
    self.gsub(/#U[A-Fa-f0-9]{4}/) {|z| [z.gsub("#U", "").to_i(16)].pack("U") }
    end
  def chrsize
    str = self
    if str.encoding != Encoding::UTF_8 || !str.valid_encoding?
      str = str.dup
      str.force_encoding(Encoding::UTF_8) if str.encoding == Encoding::ASCII_8BIT
      str = str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    return str.length
  rescue Exception
    Log.warning("Failed to count UTF-8 text length: #{self}")
    return self.to_s.b.bytesize
    end
  def to_b
    self.to_i.to_b
    end
  def delline(lines=1)
    self.gsub!(EltenLink::LEGACY_LINE,"\r\n") if defined?(EltenLink)
    str = ""
foundlines = 1
    for i in 0..self.size - 1
      str += self[i..i]
      foundlines += 1 if self[i..i] == "\n"
    end
    fl = 0
    ret = ""
    for i in 0..str.size - 1
      fl += 1 if str[i..i] == "\r" or (str[i..i] == "\n" and str[i-1..i-1] != "\r")
      if foundlines - lines > fl
        ret += str[i..i]
        end
      end
      return ret.to_s
    end
    def rdelete!(i)
    b = i[0]
  x = 0
  for i in 1..self.size
    if self[self.size - i] == b
      x += 1
    else
      break
    end
       end
  for i in 0..x-1
    chop!
    end
  end
  def maintext
    ind=self.index("\003")||self.size
return self[0...ind]
  end
  def lore
    ind=self.index("\003")
    if ind!=nil
return self[ind+1..-1]
else
    return self+""
    end
  end
  def urlenc(binary=false)
    string = self.to_s.dup
    if binary
      string = string.b
    else
      string.force_encoding(Encoding::UTF_8) if string.encoding == Encoding::ASCII_8BIT
      string = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
            r = string.gsub(/([^ a-zA-Z0-9_.-]+)/) do |m|
      m.bytes.map { |byte| "%" + byte.to_s(16).rjust(2, "0").upcase }.join
    end.tr(' ', '+')
        return r
  end
    def urldec(binary=false)
    string = self.to_s.dup
    r=string
    o=""
    while r != o
      o=r
          r = string.gsub(/%([a-fA-F0-9][a-fA-F0-9])/) do |m|
      [m[1..2].to_i(16)].pack("C")
    end.tr('+', ' ')
string=r
    end
    if !binary
      r.force_encoding(Encoding::UTF_8)
      r=r.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    return    r
  end
  def delspecial
    string = self+""
    from=["ą","ć","ę","ł","ń","ó","ś","ź","ż","Ą","Ć","Ę","Ń","Ó","Ł","Ś","Ź","Ż","-"]
    to=["a","c","e","l","n","o","s","z","z","A","C","E","L","N","O","S","Z","Z","_"]
    for i in 0..to.size-1
      string.gsub!(from[i],to[i])
      end
    r = string.gsub(/([^ a-zA-Z0-9_.-]+)/) do |m|
      ''
    end.tr(' ', '_')
    return r
  end
  def bigletter
    return self!=self.downcase
          return false
    end
  def indices e
    start, result = -1, []
    result << start while start = (self.index e, start + 1)
    result
  end
        end
  
  class NilClass
    def join(v=nil)
      return ""
      end
    def delete(s)
      return ""
    end
    def +(s)
      return s
    end
    def to_s
      return ""
    end
    def to_i
      return 0
      end
    end
  
class Dir
  def self.size(dir)
    return 0 unless File.directory?(dir)
    Dir.entries(dir).reject { |entry| entry == "." || entry == ".." }.sum do |entry|
      path = File.join(dir, entry)
      File.directory?(path) ? size(path) : File.size(path)
    end
  rescue
    0
  end
end

module FileTest
  def self.exists?(file)
    exist?(file)
  end
end unless FileTest.respond_to?(:exists?)
