# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
       def process_notification(notif)
         play_sound(notif['sound']) if notif['sound']!=nil
        if notif['alert']!=nil
            speak(notif['alert'], stop: false)
        end
       end

       def register_activity(wait: false, final: false)
                  ActivityReports.flush(wait: wait, force: final)
       end

       def set_ringtone(user, file)
         json={}
         ringtone_file=EltenPath.join(Dirs.eltendata, "ringtones.json")
         begin
if FileTest.exists?(ringtone_file)
  json=JSON.load(File.binread(ringtone_file))
  end
           rescue Exception
         end
         if file==nil
           json.delete(user)
         else
           json[user]=file
         end
         File.binwrite(ringtone_file, JSON.generate(json))
         end

       def plum
         play_sound("feed_update")
         "plum"
         end
  end
end
