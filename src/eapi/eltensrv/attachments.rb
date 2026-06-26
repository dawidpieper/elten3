# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def name_attachments(attachments, names = [])
      EltenLink::Attachments.names(elten_link, attachments, names: names)
    rescue EltenLink::Error => e
      Log.warning("Attachment name lookup failed: #{e.message}")
      names || []
    end

    def send_attachment(file)
      EltenLink::Attachments.send_file(elten_link, file)
    rescue EltenLink::Error => e
      Log.warning("Attachment upload failed: #{e.message}")
      alert(_("Error"))
      nil
    end

    def process_attachment(at)
      name=EltenLink::Attachments.name(elten_link, at)
      if name==nil
        alert(_("Error"))
        $scene=Scene_Main.new
        return
      end
      id=at
      ac=0
      if [".mp3",".wav",".ogg",".mid",".mod",".m4a",".flac",".wma",".opus",".aac",".aiff"].include?(File.extname(name).downcase)
        ac=selector([p_("EAPI_Common", "Save"),p_("EAPI_Common", "Play"),_("Cancel")],header: name,start_index: 0,cancel_index: 2,flags: 1)
      end
      case ac
      when 0
        loc=get_file(p_("EAPI_Common", "Where do you want to save this file?"), path: EltenPath.join(Dirs.user, "Documents"), save: true)
        if loc!=nil
          waiting {
            download_file(EltenLink::Attachments.download_url(id),EltenPath.join(loc, name))
            speak(p_("EAPI_Common", "The attachment has been downloaded."))
          }
        else
          loop_update
        end
      when 1
        player(EltenLink::Attachments.download_url(id))
      end
    end
  end
end
