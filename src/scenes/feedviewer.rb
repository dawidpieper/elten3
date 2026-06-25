class Scene_FeedViewer
  def initialize(n, scene=nil, first=true)
    @ind=-1
    @n=n
    @scene=scene
    @first=first
  end
  def main
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
      $scene=Scene_Main.new
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
ind=0
ind=selt.size-1 if selt.size>0 && @n.is_a?(FeedMessage)
ind=@ind if @ind!=-1
@sel = ListBox.new(selt, header: p_("FeedViewer", "Feed"), index: ind, flags: 0, quiet: false)
@sel.bind_context{|menu|context(menu)}
loop do
  loop_update
  @sel.update
  break if key_pressed?(:key_escape) or (@first!=true && @sel.collapsed?)
  break if $scene!=self
  if @sel.expanded? && @feeds.size>0 && @feeds[@sel.index].responses>0
    feed=@feeds[@sel.index]
$scene = Scene_FeedViewer.new(feed, $scene, false)
end
if @sel.selected? and @feeds.size>0
  feedshow(@feeds[@sel.index])
  loop_update
  end
end
@ind=@sel.index
if $scene==self
if @scene!=nil
  $scene=@scene
else
  $scene=Scene_Main.new
end
end
end
def context(menu)
  if @feeds.size>0
    feed=@feeds[@sel.index]
    menu.useroption(feed.user)
    if feed.responses>0
      menu.option(p_("FeedViewer", "Show responses"), nil, "d") {
      $scene = Scene_FeedViewer.new(feed, $scene, false)
      }
    elsif feed.response>0
      menu.option(p_("FeedViewer", "Show conversation"), nil, "d") {
      $scene = Scene_FeedViewer.new(feed, $scene, false)
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
    confirm(p_("FeedViewer", "Are you sure you want to delete this post?")) {
    delete_feed(feed.id)
    }
    play_sound("editbox_delete")
    @sel.disable_item(@sel.index)
    }
  end
  end
    menu.option(p_("FeedViewer", "Publish to a feed"), nil, "n") {feed_new}
end
def feed_new(users=[], response=0)
  text=users.map{|u|"@"+u}.join(" ")
  text<<" " if text!=""
    inp = input_text(p_("FeedViewer", "Message"), flags: 0, text: text, escapable: true, permitted_characters: [], denied_characters: [], max_length: 300, move_to_end: true)
  feed(inp, response) if inp!=nil
  end
  end
