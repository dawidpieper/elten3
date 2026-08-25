# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    AUDIO_ATTACHMENT_EXTENSIONS = %w[.mp3 .wav .ogg .mid .mod .m4a .flac .wma .opus .aac .aiff].freeze
    TEXT_ATTACHMENT_EXTENSIONS = %w[.txt .log .md].freeze
    TEXT_ATTACHMENT_VIEW_LIMIT = 2 * 1024 * 1024

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
      info=EltenLink::Attachments.info(elten_link, at)
      if info==nil
        alert(_("Error"))
        $scene=Scene_Main.new
        return
      end
      case attachment_action(info)
      when :save
        save_attachment(info)
      when :play
        player(info.url)
      when :view
        view_text_attachment(info)
      end
    end

    def attachment_action(info)
      extension=EltenPath.extname(info.name).downcase
      actions=if AUDIO_ATTACHMENT_EXTENSIONS.include?(extension)
        [[:save, p_("EAPI_Common", "Save")], [:play, p_("EAPI_Common", "Play")]]
      elsif TEXT_ATTACHMENT_EXTENSIONS.include?(extension) && info.size!=nil && info.size<=TEXT_ATTACHMENT_VIEW_LIMIT
        [[:save, p_("EAPI_Common", "Save")], [:view, p_("EAPI_Common", "View")]]
      else
        return :save
      end
      index=selector(actions.map { |action| action[1] }+[_("Cancel")], header: info.name, start_index: 0, cancel_index: actions.size, flags: 1)
      actions[index]&.first
    end

    def save_attachment(info)
      loc=get_file(p_("EAPI_Common", "Where do you want to save this file?"), path: EltenPath.join(Dirs.user, "Documents"), save: true)
      if loc!=nil
        waiting {
          downloaded=download_file(info.url, EltenPath.join(loc, info.name))
          speak(p_("EAPI_Common", "The attachment has been downloaded.")) if downloaded
        }
      else
        loop_update
      end
    end

    def view_text_attachment(info)
      data=read_url(info.url)
      if data==nil
        alert(_("Error"))
        return
      end
      if data.bytesize>TEXT_ATTACHMENT_VIEW_LIMIT
        alert(p_("EAPI_Common", "This attachment is too large to display."))
        return
      end
      flags=EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly
      flags|=EditBox::Flags::MarkDown if EltenPath.extname(info.name).downcase==".md"
      input_text(info.name, flags: flags, text: decode_attachment_text(data), escapable: true)
    end

    def decode_attachment_text(data)
      if data.start_with?("\xFF\xFE".b)
        data.byteslice(2..).to_s.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      elsif data.start_with?("\xFE\xFF".b)
        data.byteslice(2..).to_s.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      else
        data.delete_prefix("\xEF\xBB\xBF".b).force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
    end
  end
end
