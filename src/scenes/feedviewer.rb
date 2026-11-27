# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module FeedNavigation
  def return_from_feed
    @from_feed = true
    self
  end
end

class Scene_FeedViewer
  include FeedNavigation

  def initialize(n, scene=nil, first=true, feed_parent: nil)
    @n = n
    @scene = scene
    @first = first && feed_parent.nil?
    @feed_parent = feed_parent
    @from_feed = !feed_parent.nil?
  end

  def main
    previous_index = @sel&.index
    previous_id = @feeds[previous_index]&.id if previous_index
    begin
      @feeds = []
      if @n.is_a?(String)
        @feeds = EltenLink::Feeds.show(elten_link, @n)
      elsif @n.is_a?(FeedMessage)
        if @n.responses>0
          @feeds = EltenLink::Feeds.responses(elten_link, @n.id)
        elsif @n.response>0
          @feeds = EltenLink::Feeds.responses(elten_link, @n.response)
        end
      end
    rescue EltenLink::Error => e
      Log.warning("Feed viewer load failed: #{e.message}")
      alert(_("Error"))
      $scene = @feed_parent || @scene || Scene_Main.new
      return
    end
selt=@feeds.map{|f|
parts=[f.user]
parts << EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemliked", " "+p_("EAPI_Speech", "Liked")+": ", "(like)", immediate: true) if f.liked
parts << ": "+f.message+" "
parts << "("+np_("FeedViewer", "%{count} user likes it", "%{count} users like it", f.likes)%{:count=>f.likes}+") " if f.likes>0
begin
parts << format_date(Time.at(f.time))
rescue Exception
  end
parts << EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemcontaining", " "+p_("EAPI_Speech", "Containing")+": ", "->", immediate: true) if f.responses>0
EltenAPI::SpeechSequence.new(parts)
}
    if previous_index
      index = @feeds.index { |feed| feed.id == previous_id } || previous_index.clamp(0, [@feeds.size - 1, 0].max)
    else
      index = @n.is_a?(FeedMessage) && !@feeds.empty? ? @feeds.size - 1 : 0
    end
    @sel = ListBox.new(selt, header: p_("FeedViewer", "Feed"), index: index, quiet: true)
    configure_feed_list_audio(@sel, @feeds)
    @sel.focus(announce_header: !@from_feed)
    @from_feed = false
    @sel.bind_context { |menu| context(menu) }
    loop do
      loop_update
      break if $scene != self
      @sel.update
      break if $scene != self
      if key_pressed?(:key_escape) || key_pressed?(:key_tab) || (!@first && @sel.collapsed?)
        $scene = @feed_parent&.return_from_feed || @scene || Scene_Main.new
        break
      end
      feed = @feeds[@sel.index]
      if feed && @sel.expanded? && feed.responses > 0 && !responses_shown?(feed)
        open_feed_responses(feed)
        break
      elsif feed && @sel.selected?
        feedshow(feed)
        @sel.focus if $scene == self
        loop_update
      end
    end
  end

  def open_feed_responses(feed)
    $scene = Scene_FeedViewer.new(feed, feed_parent: self)
  end

def responses_shown?(feed)
  return false if !@n.is_a?(FeedMessage)
  feed.id==@n.id || (@n.response>0 && feed.id==@n.response)
end
def context(menu)
  if @feeds.size>0
    feed=@feeds[@sel.index]
    menu.useroption(feed.user)
    if feed.responses>0
      if !responses_shown?(feed)
      menu.option(p_("FeedViewer", "Show responses"), nil, "d") {
        open_feed_responses(feed)
      }
      end
    elsif feed.response>0
      menu.option(p_("FeedViewer", "Show conversation"), nil, "d") {
        open_feed_responses(feed)
      }
    end
    if feed.likes>0
      menu.option(p_("FeedViewer", "Show likes"), nil, "K") {
  likes=[]
  begin
    likes=EltenLink::Feeds.likes(elten_link, feed.id)
  rescue EltenLink::Error => e
    Log.warning("Feed likes failed: #{e.message}")
  end
users=likes
dialog_open
lst=ListBox.new(users, header: p_("FeedViewer", "Users who like this post"), index: 0, flags: 0, quiet: false)
loop do
 loop_update
 lst.update
 break if key_pressed?(:key_escape)
 if (key_pressed?(:key_alt) or key_pressed?(:key_enter)) and users.size>0
   usermenu(users[lst.index])
   end
end
dialog_close
      }
      end
    if Session.logged?
    menu.option(p_("FeedViewer", "Reply"), nil, "r") {
    users=[feed.user]
    users+=feed.message.scan(/\@([a-zA-Z0-9\.\-\_]+)/).map{|r|r[0]}
    todel=[]
    for u in users
      todel.push(u) if u.downcase==Session.name.downcase
    end
    for i in 1...users.size
      todel.push(users[i]) if users[0...i].map{|u|u.downcase}.include?(users[i].downcase)
      end
    todel.each{|u|users.delete(u)}
    response=feed.id
    response=feed.response if feed.response>0
    feed_new(users.uniq, response)
    }
    s=p_("FeedViewer", "Like this message")
    s=p_("FeedViewer", "Dislike this message") if feed.liked
    menu.option(s, nil, "k") {
    begin
      EltenLink::Feeds.set_liked(elten_link, feed.id, !feed.liked)
    rescue EltenLink::Error => e
      Log.warning("Feed like toggle failed: #{e.message}")
    alert(_("Error"))
  else
    st=(feed.liked)?(p_("FeedViewer", "Message disliked")):(p_("FeedViewer", "Message liked"))
    feed.liked=!feed.liked
    alert(st)
    end
    }
  if feed.user==Session.name
    menu.option(_("Delete"), nil, :del) {
    if confirm(p_("FeedViewer", "Are you sure you want to delete this post?"))
      begin
        delete_feed(feed.id)
      rescue EltenLink::Error => e
        Log.warning("Feed deletion failed: #{e.message}")
        alert(_("Error"))
      else
        play_sound("editbox_delete")
        @sel.disable_item(@sel.index)
      end
    end
    }
  end
  end
    menu.option(p_("FeedViewer", "Publish to a feed"), nil, "n") {feed_new}
    end
end
def feed_new(users=[], response=0)
  compose_feed(users, response)
  end
  end
