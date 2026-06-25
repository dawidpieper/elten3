# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module MediaFinders
  @@finders=[]
  class <<self
    include EltenAPI
    def register(cls)
      return if !cls.is_a?(Class)
        EltenAPI::Log.debug("Registering media finder #{cls.to_s}")
      @@finders.push(cls)
    end
    def unregister(cls)
      Log.debug("Unregistering media finder #{cls}")
            @@finders.delete(cls)
    end
    def delete_all
      Log.info("Flushing media finders")
      c=@@finders.size
            unregister @@finders[0] while @@finders.size>0
            return c
      end
      def list
        return @@finders
      end
      def possible_media?(text)
        @@finders.each{|m|
        return true if m.possible_media?(text)
        }
        return false
        end
      def get_media(text)
        medias=[]
        @@finders.each{|m|
        begin
          medias+=m.get_media(text)
        rescue Exception
          Log.error("Failed to get media: "+$!.to_s+" "+$@.to_s)
          end
        }
        return medias
        end
  end
  end

class MediaFinder
  def initialize
    raise("Abstract class cannot be initialized")
  end
  def self.possible_media?(text)
    return false
    end
  def self.get_media(text)
    return []
    end
  end
  
  class MediaExtractor
  def initialize
    raise("Abstract class cannot be initialized")
  end
  def title
    return ""
    end
  def proceed
    return
    end
  end