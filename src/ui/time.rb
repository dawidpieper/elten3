# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  TICK_MS = 10
  TICK_SECONDS = TICK_MS / 1000.0
  TICK_BACKGROUND_MS = 50
  TICK_BACKGROUND_SECONDS = TICK_BACKGROUND_MS / 1000.0
  PERIODIC_FAST_SECONDS = 0.25
  PERIODIC_MEDIUM_SECONDS = 0.5
  PERIODIC_SLOW_SECONDS = 1.0

  module TimeSource
    class << self
      def current_time
        tm = nil
        tm = NotificationService.server_time
        tm = $wnlasttime if tm == nil && $wnlasttime != nil
        tm = Time.now.to_i if Configuration.synctime == false || tm == nil
        Time.at(tm)
      rescue Exception
        Time.now
      end
    end
  end

  module Alarms
    class << self
      def load(force=false)
        current_path = path
        if force || @alarms == nil || @path != current_path
          @path = current_path
          @alarms = read_file(current_path)
        end
        @alarms
      end

      def replace(alarms, save_file=true)
        @path = path
        @alarms = normalize(alarms)
        save if save_file
        @alarms
      end

      def save
        write_file(path, load)
        true
      rescue Exception => e
        Log.error("Alarm save: #{e.class}: #{e.message}")
        false
      end

      def migrate_legacy_file
        old_path = legacy_path
        new_path = path
        return false if !FileTest.exist?(old_path) || FileTest.exist?(new_path)
        alarms = normalize(File.open(old_path, "rb") { |f| Marshal.load(f) })
        return false if !write_file(new_path, alarms)
        File.delete(old_path)
        @path = new_path
        @alarms = alarms
        Log.info("Migrated alarms.dat to alarms.json")
        true
      rescue Exception => e
        Log.error("Alarm migration: #{e.class}: #{e.message}")
        false
      end

      def update(now=nil)
        now ||= TimeSource.current_time
        minute = now.hour * 60 + now.min
        return if @last_checked_minute == minute
        @last_checked_minute = minute
        alarms = load
        due_index = nil
        alarms.each_with_index do |alarm, index|
          due_index = index if alarm[0].to_i == now.hour && alarm[1].to_i == now.min
        end
        return if due_index == nil
        alarm = alarms[due_index]
        if alarm[2].to_i == 0
          alarms.delete_at(due_index)
          save
        end
        Log.info("Alarm#{alarm[3].nil? ? "" : alarm[3]}")
        $agalarm = true
        $agalarmdescription = alarm[3]
      rescue Exception => e
        Log.error("Alarm update: #{e.class}: #{e.message}")
      end

      private

      def path
        EltenPath.join(Dirs.eltendata, "alarms.json")
      end

      def legacy_path
        EltenPath.join(Dirs.eltendata, "alarms.dat")
      end

      def read_file(file)
        return [] if !FileTest.exist?(file)
        data = JSON.parse(File.binread(file).to_s)
        normalize(data)
      rescue Exception => e
        Log.error("Alarm load: #{e.class}: #{e.message}")
        []
      end

      def write_file(file, alarms)
        payload = normalize(alarms).map { |alarm| alarm_to_hash(alarm) }
        tmp = "#{file}.tmp-#{$$}-#{Thread.current.object_id}"
        File.binwrite(tmp, JSON.pretty_generate(payload))
        File.delete(file) if FileTest.exist?(file)
        File.rename(tmp, file)
        true
      rescue Exception => e
        Log.error("Alarm write: #{e.class}: #{e.message}")
        false
      ensure
        File.delete(tmp) if tmp != nil && FileTest.exist?(tmp) rescue nil
      end

      def normalize(alarms)
        Array(alarms).map do |alarm|
          values = alarm_values(alarm)
          next nil if values == nil
          hour = [[values[0].to_i, 0].max, 23].min
          minute = [[values[1].to_i, 0].max, 59].min
          type = values[2].to_i == 0 ? 0 : 1
          [hour, minute, type, values[3]]
        end.compact
      end

      def alarm_values(alarm)
        if alarm.is_a?(Array) && alarm.size >= 3
          alarm
        elsif alarm.is_a?(Hash)
          repeat = alarm.key?("repeat") ? alarm["repeat"] : alarm["repeated"]
          type = alarm.key?("type") ? alarm_type(alarm["type"]) : (repeat == true ? 1 : 0)
          [
            alarm["hour"],
            alarm["minute"],
            type,
            alarm["description"] || alarm["text"]
          ]
        end
      end

      def alarm_type(value)
        text = value.to_s.downcase
        return 1 if text == "repeat" || text == "repeated" || text == "1"
        0
      end

      def alarm_to_hash(alarm)
        {
          "hour" => alarm[0].to_i,
          "minute" => alarm[1].to_i,
          "type" => alarm[2].to_i == 0 ? "once" : "repeat",
          "repeat" => alarm[2].to_i != 0,
          "description" => alarm[3] == nil ? nil : alarm[3].to_s
        }
      end

    end
  end

  module Clock
    class << self
      def update(now=nil)
        now ||= TimeSource.current_time
        minute = now.hour * 60 + now.min
        return nil if @last_announced_minute == minute
        @last_announced_minute = minute
        period = Configuration.saytimeperiod
        type = Configuration.saytimetype
        return nil if type == :none
        m = now.min
        due = case period
              when :hourly
                m == 0
              when :half_hourly
                m == 0 || m == 30
              when :quarter_hourly
                [0, 15, 30, 45].include?(m)
              else
                false
              end
        return nil if due != true || $donotdisturb == true
        [
          type == :voice_and_sound || type == :sound_only,
          (type == :voice_and_sound || type == :voice_only) ? sprintf("%02d:%02d", now.hour, now.min) : nil
        ]
      rescue Exception => e
        Log.error("Clock update: #{e.class}: #{e.message}")
        nil
      end
    end
  end

end
