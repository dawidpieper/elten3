# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def feed(message, response = 0, audio: nil, message_max_length: EltenLink::Feeds::DEFAULT_MESSAGE_MAX_LENGTH)
      EltenLink::Feeds.publish(elten_link, message, response: response, audio: audio, message_max_length: message_max_length)
    end

    def feed_limits
      EltenLink::Feeds.limits(elten_link)
    rescue StandardError => error
      Log.warning("Feed limits could not be retrieved: #{error.class}: #{error.message}")
      EltenLink::Feeds.default_limits
    end

    def feed_audio_url(feed)
      return "" if feed==nil || !feed.respond_to?(:audio_url)
      feed.audio_url.to_s
    end

    def feed_audio_status
      ListBox.item_status("file_audio", p_("FeedViewer", "Audio content")+":", p_("FeedViewer", "Audio content"))
    end

    def configure_feed_list_audio(list, feeds)
      return if list==nil
      list.item_audio_autoplay=false
      list.item_audio_space_mode=:stop
      feeds.to_a.each_with_index do |feed, index|
        url=feed_audio_url(feed)
        next if url==""
        list.set_item_state(index, feed_audio_status)
        list.set_item_audio(index, url)
      end
    end

    def compose_feed(users=[], response=0)
      limits=feed_limits
      message_max_length=limits["message_max_length"].to_i
      audio_max_duration=limits["audio_max_duration_seconds"].to_i
      text=users.map{|user|"@"+user.to_s}.join(" ")
      text<<" " if text!=""
      message_header=p_("FeedViewer", "Message")
      edit=EditBox.new(message_header, type: 0, text: text, max_length: message_max_length)
      edit.index=edit.check=text.length
      update_message_header=lambda do
        count=edit.text.to_s.chrsize
        edit.header = if count>0
          message_header+": "+(p_("EAPI_Form", "%{count} of %{maximum} characters") % {:count=>count, :maximum=>message_max_length})
        else
          message_header
        end
      end
      edit.on(:change) {update_message_header.call}
      update_message_header.call
      recorder=nil
      fields=[edit]
      if holds_premiumpackage("audiophile")
        filename=EltenPath.join(Dirs.temp, "feed_#{rand(36**16).to_s(36)}.opus")
        recorder=OpusRecordButton.new(p_("FeedViewer", "Attach audio"), filename, max_bitrate: 128, bitrate: 64, time_limit: audio_max_duration)
        fields << recorder
      end
      send_button=Button.new(p_("Messages", "Send"))
      cancel_button=Button.new(_("Cancel"))
      fields.push(send_button, cancel_button)
      form=Form.new(fields, index: 0)
      action=nil
      send_button.on(:press) do
        if edit.text.to_s.strip==""
          alert(p_("FeedViewer", "A feed entry must contain text."))
          form.focus
        else
          action=:send
          form.resume
        end
      end
      cancel_button.on(:press) do
        action=:cancel
        form.resume
      end
      form.accept_button=send_button
      form.cancel_button=cancel_button
      dialog_open
      loop do
        action=nil
        form.wait
        if action==:cancel
          if recorder==nil || recorder.delete_audio
            return false
          end
          form.focus
          next
        end

        begin
          audio=nil
          if recorder!=nil && !recorder.empty?
            duration=recorder.source_duration
            if duration!=nil && duration>audio_max_duration+1
              choice=selector(
                [
                  p_("FeedViewer", "Shorten the audio to %{limit} seconds") % {:limit=>audio_max_duration},
                  p_("FeedViewer", "Return to the editor")
                ],
                header: p_("FeedViewer", "The attached audio is %{duration} seconds long. The maximum is %{limit} seconds.") % {:duration=>duration.ceil, :limit=>audio_max_duration},
                cancel_index: 1,
                flags: ListBox::Flags::LeftRight
              )
              if choice!=0
                form.focus
                next
              end
            end
            recording=recorder.get_recording_file(true)
            raise p_("FeedViewer", "The audio recording could not be prepared.") if recording==nil || !File.file?(recording)
            audio=File.binread(recording)
          end
          published=feed(edit.text.to_s, response, audio: audio, message_max_length: message_max_length)
          raise p_("FeedViewer", "The server did not accept the feed entry.") if published!=true
          recorder.delete_audio(true) if recorder!=nil
          return true
        rescue EltenLink::Error => error
          Log.warning("Feed publish failed: EltenLink::Error code=#{error.code}: #{error.message}")
          alert(feed_publish_error(error, audio_max_duration))
        rescue Exception => error
          Log.warning("Feed publish failed: #{error.class}: #{error.message}")
          alert(error.message.to_s=="" ? _("Error") : error.message.to_s)
        end
        form.focus
      end
    ensure
      dialog_close
    end

    def feed_publish_error(error, audio_max_duration=EltenLink::Feeds::DEFAULT_AUDIO_MAX_DURATION_SECONDS)
      case error.code.to_s
      when "audio.too_long"
        p_("FeedViewer", "The audio recording cannot be longer than %{limit} seconds.") % {:limit=>audio_max_duration}
      when "premium.required"
        p_("FeedViewer", "The Audiophile package is required to attach audio to a feed entry.")
      else
        error.message
      end
    end

    def delete_feed(id)
      EltenLink::Feeds.delete(elten_link, id)
    end

    def set_feed_follow(user, follow:)
      EltenLink::Feeds.follow(elten_link, user, follow: follow)
      NotificationService.reset_feeds
      EltenAPI::InvisibleInterface.reset_feeds if defined?(EltenAPI::InvisibleInterface)
      Session.feeds_clear
      true
    rescue EltenLink::Error => e
      Log.warning("Feed follow toggle failed: #{e.message}")
      alert(_("Error"))
      false
    end

    def feedshow(feed)
      return if feed==nil
      likes=[]
      begin
        likes=EltenLink::Feeds.likes(elten_link, feed.id)
      rescue EltenLink::Error => e
        Log.warning("Feed likes failed: #{e.message}")
      end
      fields=[
        edt_message = EditBox.new(p_("EAPI_Common", "Message"), type: EditBox::Flags::ReadOnly, text: feed.message, quiet: true)
      ]
      audio_player=nil
      if feed_audio_url(feed)!=""
        audio_player=Player.new(feed_audio_url(feed), label: p_("FeedViewer", "Audio content"), autoplay: false, quiet: true, lazy: true)
        audio_player.on(:key_space) do
          audio_player.paused? ? audio_player.play : audio_player.pause
        end
        fields << audio_player
      end
      fields << (lst_likes = ListBox.new(likes, header: p_("EAPI_Common", "Users liking this message")))
      fields << (btn_close = Button.new(p_("EAPI_Common", "Close")))
      form=Form.new(fields, index: 0, silent: false, quiet: true)
      btn_close.on(:press) {form.resume}
      edt_message.bind_context{|menu|menu.useroption(feed.user)}
      lst_likes.bind_context{|menu|
        if likes.size>0
          menu.useroption(likes[lst_likes.index])
        end
      }
      form.cancel_button=btn_close
      dialog_open
      begin
        form.wait
      ensure
        audio_player.close rescue nil if audio_player!=nil && audio_player.sound!=nil
        dialog_close
      end
    end
  end
end
