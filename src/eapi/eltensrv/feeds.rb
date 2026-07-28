# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module EltenSRV
    private
    def feed(message, response = 0)
      EltenLink::Feeds.publish(elten_link, message, response: response)
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
      form=Form.new([
        edt_message = EditBox.new(p_("EAPI_Common", "Message"), type: EditBox::Flags::ReadOnly, text: feed.message, quiet: true),
        lst_likes = ListBox.new(likes, header: p_("EAPI_Common", "Users liking this message")),
        btn_close = Button.new(p_("EAPI_Common", "Close"))
        ], index: 0, silent: false, quiet: true)
      btn_close.on(:press) {form.resume}
      edt_message.bind_context{|menu|menu.useroption(feed.user)}
      lst_likes.bind_context{|menu|
        if likes.size>0
          menu.useroption(likes[lst_likes.index])
        end
      }
      form.cancel_button=btn_close
      dialog_open
      form.wait
      dialog_close
    end
  end
end
