# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  private
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
