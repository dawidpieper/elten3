# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module MediaFinders
  @@finders = []
  @@owners = {}
  @@mutex = Mutex.new

  class << self
    def register(finder_class)
      return false if !finder_class.is_a?(Class)
      owner = current_owner
      added = false
      @@mutex.synchronize do
        if !@@finders.include?(finder_class)
          @@finders << finder_class
          added = true
        end
        @@owners[finder_class] = owner if owner != nil
      end
      log(:debug, "Registering media finder #{finder_class}") if added
      added
    rescue StandardError => error
      log(:error, "Cannot register media finder #{finder_class}: #{error.class}: #{error.message}")
      false
    end

    def unregister(finder_class)
      removed = false
      @@mutex.synchronize do
        removed = @@finders.delete(finder_class) != nil
        @@owners.delete(finder_class)
      end
      log(:debug, "Unregistering media finder #{finder_class}") if removed
      removed
    rescue StandardError => error
      log(:error, "Cannot unregister media finder #{finder_class}: #{error.class}: #{error.message}")
      false
    end

    def unregister_owner(owner)
      return 0 if owner == nil
      classes = @@mutex.synchronize { @@owners.select { |_finder, value| value.equal?(owner) }.keys }
      classes.count { |finder_class| unregister(finder_class) }
    end

    def delete_all
      classes = @@mutex.synchronize { @@finders.dup }
      classes.each { |finder_class| unregister(finder_class) }
      classes.size
    end

    def list
      @@mutex.synchronize { @@finders.dup }
    end

    def possible_media?(text)
      list.each do |finder_class|
        return true if finder_class.possible_media?(text)
      end
      false
    end

    def get_media(text)
      medias = []
      list.each do |finder_class|
        begin
          medias += finder_class.get_media(text)
        rescue Exception => error
          log(:error, "Failed to get media: #{error} #{error.backtrace}")
        end
      end
      medias
    end

    private

    def current_owner
      return nil if !defined?(Programs) || !Programs.respond_to?(:current_runtime)
      Programs.current_runtime
    rescue StandardError
      nil
    end

    def log(level, message)
      logger = defined?(Log) ? Log : (defined?(EltenAPI::Log) ? EltenAPI::Log : nil)
      logger.__send__(level, message) if logger != nil && logger.respond_to?(level)
    rescue StandardError
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
