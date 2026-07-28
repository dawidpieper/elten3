# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
       class SoundTheme
         attr_accessor :name, :stamp, :file
         attr_reader :sounds
         def initialize(name, stamp=nil, file=nil)
           @name=name
           @stamp=stamp
           @file=file
           @sounds={}
         end
         def getsound(name)
           return nil if !name.is_a?(String)
             return @sounds[name.downcase]
           end
         end

       class DirectorySoundTheme < SoundTheme
         def initialize(name, directory)
           super(name, nil, directory)
           @directory=directory
           collect_sounds
         end

         def getsound(name)
           return nil if !name.is_a?(String)
           path=@sounds[name.downcase]
           return nil if path==nil || !File.file?(path)
           File.binread(path)
         rescue Exception
           Log.warning("Cannot read directory soundtheme sound #{name}: #{$!.class}: #{$!.message}") if defined?(Log)
           nil
         end

         private

         def collect_sounds
           return if !File.directory?(@directory)
           root=File.expand_path(@directory)
           Dir.children(@directory).each do |entry|
             next if File.extname(entry).downcase!=".ogg"
             path=File.expand_path(File.join(@directory, entry))
             next if path!=root && !path.start_with?(root+File::SEPARATOR)
             next if !File.file?(path)
             @sounds[File.basename(entry, File.extname(entry)).downcase]=path
           end
         rescue Exception
           Log.warning("Cannot collect directory soundtheme sounds from #{@directory}: #{$!.class}: #{$!.message}") if defined?(Log)
         end
       end

       @@defaultsoundtheme=SoundTheme.new("")
         @@soundtheme=nil
       DEFAULT_SOUND_THEME_PACKAGE="data/audio.elsnd"
       DEFAULT_SOUND_THEME_DIRECTORY="audio"

       def load_soundtheme(file, loadSounds=true)
         Log.debug("Loading soundtheme: "+file)
         return nil if !FileTest.exists?(file)
         size=File.size(file)
         return nil if size>64*1024**2 || size<36
         limit=0
         limit=32+8+1+256+4 if !loadSounds
         io=StringIO.new(limit.to_i > 0 ? File.open(file, "rb") { |f| f.read(limit.to_i) } : File.binread(file))
         magic="EltenSoundThemePackageFileCMPSMC"
         return nil if io.read(32)!=magic
         stamp=io.read(8).unpack("Q").first
         sz=io.read(1).unpack("C").first
         st=SoundTheme.new(io.read(sz), stamp, file)
         sz=io.read(4).unpack("I").first
         return nil if size!=sz+32+8+1+st.name.size+4
                                             if loadSounds
                                               zio=StringIO.new(Zlib::Inflate.inflate(io.read(sz)))
         while !zio.eof?
           sz=zio.read(1).unpack("C").first
           file=zio.read(sz)
           sz=zio.read(4).unpack("I").first
           content=zio.read(sz)
             st.sounds[file.downcase]=content
           end
           end
         return st
       rescue Exception
         Log.error("Cannot load soundtheme: "+$!.to_s+" "+$@.to_s)
         return nil
       end

       def load_directory_soundtheme(directory, name="default")
         return nil if !File.directory?(directory)
         st=DirectorySoundTheme.new(name, directory)
         return nil if st.sounds.empty?
         st
       rescue Exception
         Log.error("Cannot load directory soundtheme: "+$!.to_s+" "+$@.to_s)
         nil
       end

       def default_soundtheme_package?(file)
         normalized=file.to_s.tr("\\", "/").downcase
         normalized==DEFAULT_SOUND_THEME_PACKAGE || normalized.end_with?("/"+DEFAULT_SOUND_THEME_PACKAGE)
       end

       def use_soundtheme(file, default=false)
         if default==false && (file==""||file==nil)
           @@soundtheme=@@defaultsoundtheme
           return true
           end
         st=load_soundtheme(file)
         if st==nil && default==true && default_soundtheme_package?(file)
           Log.warning("Default soundtheme package #{file} unavailable; using #{DEFAULT_SOUND_THEME_DIRECTORY} directory fallback") if defined?(Log)
           st=load_directory_soundtheme(DEFAULT_SOUND_THEME_DIRECTORY)
         end
         if st!=nil
           @@soundtheme=st
         @@defaultsoundtheme=st if default
          return true
           end
         false
         end

       def getsound(file, default=false)
         if @@soundtheme!=nil && !default
           sound=@@soundtheme.getsound(file)
           return sound if sound!=nil
end
if @@defaultsoundtheme!=nil
           sound=@@defaultsoundtheme.getsound(file)
           return sound if sound!=nil
end
return nil
end
  end
end
