# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Main
  include NotificationGroups

  @@acselindex=nil
  @@notification_index=0
  @@notifications_last_visible_time=0
  @@feed_id=-1
  @@focus=:actions
  @@specials=[]

  def main
    if @@feed_id==-1
      @@feed_id = LocalConfig['MainFeedId', type: :numeric]
    end
    if Session.name==nil||Session.name==""
      $scene=Scene_Loading.new
      return
    end
    NVDA.braille("") if defined?(NVDA) && NVDA.check
    if $restart==true
      $restart=false
      $scene=Scene_Loading.new
    end
    dialog_close if dialog_opened
    waiting_end if $waitingopened
    $silentstart=false
    if Thread::current != $mainthread
      t = Thread::current
      loop_update
      t.exit
    end
    $preinitialized = true if $preinitialized!=true
    $thr1=Thread.new{thr1} if $thr1.alive? == false
    $thr2=Thread.new{thr2} if $thr2.alive? == false
    $speech_lasttext = ""
    $ctrldisable = false
    key_update
    ci = 0
    plsinfo = false
    ci += 1 if ci < 20

    notifications_load(false, focus_if_new: true)
    acsel_load(false)
    feeds_load(false)
    focus_current_control
    if current_main_section == :notifications
      Session.notifications_updated?
      $main_notifications_changed = false
    end

    loop do
      loop_update
      notifications_changed = Session.notifications_updated?
      if $main_notifications_changed == true || notifications_changed
        $main_notifications_changed = false
        previous_section = current_main_section
        focused_notifications = previous_section == :notifications
        had_notifications = notifications_visible?
        active = main_window_active?
        notifications_load(false)
        @focus_notifications_when_active = true if !had_notifications && notifications_visible? && !active
        if focused_notifications
          if @skip_next_notifications_change_say == true
            @skip_next_notifications_change_say = false
          else
            announce_after_notifications_reload(previous_section)
          end
        end
      end
      focus_deferred_notifications_if_active
      feeds_load if Session.feeds_updated?
      update_current_main_control
      if key_pressed?(0x9)
        if key_held?(0x10)
          retreat_main_focus
        else
          advance_main_focus
        end
      end
      case current_main_section
      when :notifications
        notifications_update
      when :actions
        quick_actions_update
      when :feed
        feed_update
      end
      if key_pressed?(:key_escape)
        quit
      end
      break if $scene != self
    end
    @@notification_index=@notifications_sel.index if @notifications_sel!=nil
    @@acselindex=@acsel.index if @acsel!=nil
    @@feed_id = @feeds[@feedsel.index].id if @feeds.size>0
    LocalConfig['MainFeedId'] = @@feed_id
  end
def self.register_specialaction(id, name, &proc)
  unregister_specialaction(id)
  @@specials.push([id, name, proc])
end
def self.unregister_specialaction(id)
  d=@@specials.find{|s|s[0]==id}
  @@specials.delete(d) if d!=nil
end
def main_sections
  sections=[]
  sections << :notifications if notifications_visible?
  sections << :actions
  sections << :feed
  sections
end

def notifications_visible?
  @notification_groups.is_a?(Array) && @notification_groups.size>0
end

def normalize_main_focus
  if @@focus.is_a?(Integer)
    @@focus = @@focus == 1 ? :feed : :actions
  end
  @@focus = :actions if @@focus == nil
  @@focus = :actions if @@focus == :notifications && !notifications_visible?
  sections = main_sections
  @@focus = sections.first if !sections.include?(@@focus)
end

def current_main_section
  normalize_main_focus
  @@focus
end

def advance_main_focus
  sections = main_sections
  current = current_main_section
  index = sections.index(current) || 0
  @@focus = sections[(index + 1) % sections.size]
  focus_current_control
end

def retreat_main_focus
  sections = main_sections
  current = current_main_section
  index = sections.index(current) || 0
  @@focus = sections[(index - 1) % sections.size]
  focus_current_control
end

def focus_current_control
  case current_main_section
  when :notifications
    @notifications_sel.focus if @notifications_sel!=nil
  when :actions
    @acsel.focus if @acsel!=nil
  when :feed
    @feedsel.focus if @feedsel!=nil
  end
end

def say_current_option
  case current_main_section
  when :notifications
    @notifications_sel.sayoption if @notifications_sel!=nil
  when :actions
    @acsel.sayoption if @acsel!=nil
  when :feed
    @feedsel.sayoption if @feedsel!=nil
  end
end

def announce_after_notifications_reload(previous_section)
  if current_main_section != previous_section
    focus_current_control
  else
    say_current_option
  end
end

def main_window_active?
  EltenWindow.active_or_child?
rescue Exception
  true
end

def focus_deferred_notifications_if_active
  return if @focus_notifications_when_active != true
  return if !notifications_visible? || @notifications_sel == nil
  return if !main_window_active?

  @focus_notifications_when_active = false
  @@focus = :notifications
  @notifications_sel.focus
end
def update_current_main_control
  case current_main_section
  when :notifications
    if @notifications_sel!=nil
      @notifications_sel.update
    else
      @@focus = :actions
      @acsel.focus if @acsel!=nil
    end
  when :actions
    @acsel.update if @acsel!=nil
  when :feed
    @feedsel.update if @feedsel!=nil
  end
end

def notifications_load(fc=false, focus_if_new: false)
  old_focus = @@focus
  previous_visible_time = @@notifications_last_visible_time.to_i
  @@notification_index=@notifications_sel.index if @notifications_sel!=nil
  notifications = fetch_main_notifications
  groups = build_notification_groups(notifications, include_revoked: false)
  append_virtual_notification_groups(groups, collect_virtual_notification_groups, include_revoked: false)
  @notification_groups = sort_notification_groups(groups)
  latest_time = latest_notification_group_time(@notification_groups)
  jump_to_notifications = focus_if_new == true && @notification_groups.size > 0 && (previous_visible_time <= 0 || latest_time > previous_visible_time)
  @@notifications_last_visible_time = [previous_visible_time, notification_visibility_time(latest_time), latest_time].max
  if @notification_groups.empty?
    @notifications_sel = nil
    @@focus = :actions if old_focus == :notifications || @@focus == :notifications
    @acsel.focus if fc && @acsel!=nil
    return
  end
  @@notification_index = [[@@notification_index.to_i, 0].max, [@notification_groups.size - 1, 0].max].min
  @notifications_sel = TableBox.new(notification_columns, notification_rows(@notification_groups), index: @@notification_index, header: p_("Notifications", "Notifications"), quiet: true)
  apply_notification_group_states(@notifications_sel, @notification_groups)
  @notifications_sel.bind_context { |menu| notifications_context(menu) }
  if jump_to_notifications
    @@focus = :notifications
    @notifications_sel.focus if fc
  elsif fc
    @notifications_sel.focus
  end
end

def latest_notification_group_time(groups)
  groups.to_a.map { |group| group.date.to_i }.max.to_i
end

def notification_visibility_time(latest_time=0)
  server_time = EltenAPI::NotificationService.server_time.to_i rescue 0
  [server_time, Time.now.to_i, latest_time.to_i].max
end

def fetch_main_notifications
  EltenLink::Notifications.list(elten_link, all: false)
rescue EltenLink::Error => e
  Log.warning("Main notifications list failed: #{e.message}")
  []
end

def current_notification_group
  return nil if @notification_groups==nil || @notification_groups.empty? || @notifications_sel==nil
  @notification_groups[@notifications_sel.index]
end

def notifications_update
  return if @notifications_sel==nil
  if @notifications_sel.selected? || @notifications_sel.expanded?
    notifications_open
  end
end

def notifications_open
  group = current_notification_group
  return if group==nil
  old_index = @notifications_sel.index
  if open_notification_group(group)
    @@notification_index = old_index
    if $scene == self
      previous_section = current_main_section
      notifications_load(false)
      announce_after_notifications_reload(previous_section)
      @skip_next_notifications_change_say = true
    end
  end
end

def notifications_revoke_current
  group = current_notification_group
  return if group==nil
  old_index = @notifications_sel.index
  if revoke_notification_group(group)
    @@notification_index = old_index
    if $scene == self
      previous_section = current_main_section
      notifications_load(false)
      announce_after_notifications_reload(previous_section)
      @skip_next_notifications_change_say = true
    end
  end
end

def notifications_context(menu)
  return if current_notification_group==nil
  menu.option(p_("Notifications", "Open")) { notifications_open }
  menu.option(p_("Notifications", "Mark as read"), nil, "w") { notifications_revoke_current }
  if revocable_notification_groups?(@notification_groups)
    menu.option(p_("Notifications", "Mark all as read"), nil, "W") { notifications_revoke_all }
  end
  menu.option(_("Refresh"), nil, "r") do
    previous_section = current_main_section
    notifications_load(false)
    announce_after_notifications_reload(previous_section)
  end
end

def notifications_revoke_all
  old_index = @notifications_sel.index if @notifications_sel!=nil
  if revoke_all_notification_groups(@notification_groups)
    @@notification_index = old_index.to_i
    if $scene == self
      previous_section = current_main_section
      notifications_load(false)
      announce_after_notifications_reload(previous_section)
      @skip_next_notifications_change_say = true
    end
  end
end

def quick_actions_update
  if qacindex!=nil && @actions.size>0
    if key_held?(0x10)
      if qacindex>0 && key_pressed?(:key_up)
        qacup
      end
      if qacindex<@actions.size-1 and key_pressed?(:key_down)
        qacdown
      end
    end
    if @acsel.selected?
      @actions[qacindex].call
    end
  elsif qacindex==nil && @specials.size>0
    if @acsel.selected?
      @specials[@acsel.index][2].call
    end
  end
end

def feed_update
  if @feeds.size>0
    if @feedsel.selected?
      feedshow(@feeds[@feedsel.index])
      loop_update
    end
    if @feedsel.expanded?
      feed=@feeds[@feedsel.index]
      if feed.responses>0
        $scene = Scene_FeedViewer.new(feed, nil, false)
      end
    end
  end
end
def qacindex
  ind=@acsel.index
  ind-=@specials.size
  return nil if ind<0 || @actions==nil || ind>=@actions.size
  return ind
  end
def qacup
  return if qacindex==nil
            times=1
            index=qacindex-1
            if !@acselshowhidden
            while index>0 && @actions[index].show==false
              times+=1
              index-=1
            end
            end
    times.times {|i|QuickActions.up(qacindex-i)}
    @acsel.index-=times
    acsel_load(false)
    @acsel.say_option
end
def qacdown
  return if qacindex==nil
    times=1
            index=qacindex+1
            if !@acselshowhidden
            while index<@actions.size-1 && @actions[index].show==false
              times+=1
              index+=1
            end
            end
    times.times {|i|QuickActions.down(qacindex+i)}
    @acsel.index+=times
    acsel_load(false)
    @acsel.say_option
end
def acsel_load(fc=true)
  @specials=@@specials.dup
  @acselshowhidden||=false
  @@acselindex=@acsel.index if @acsel!=nil
      @actions = QuickActions.get
      options = @specials.map{|s|s[1]}+@actions.map{|a|a.detail}
      if @acsel==nil
    @acsel = ListBox.new(options, header: p_("Main", "Quick actions"), index: @@acselindex)
    @acsel.add_tip(p_("Main", "Use Shift with up/down arrows to move quick actions"))
    @acsel.bind_context{|menu| accontext(menu)}
  else
    @acsel.options = options
    if @acsel.index>=options.size
      @acsel.index=[options.size-1, 0].max
    end
    @acsel.index=0 if @acsel.index<0
    for i in 0...@actions.size
      @acsel.enable_item(@specials.size+i)
      end
  end
      for i in 0...@actions.size
      @acsel.disable_item(@specials.size+i) if @actions[i].show==false && !@acselshowhidden
    end
        @acsel.focus if fc==true
    end
def accontext(menu)
  if @actions.size>0 && qacindex!=nil && !@acsel.hidden?(@acsel.index)
  menu.option(p_("Main", "Rename"), nil, "e") {
  label= input_text(p_("Main", "Action label"), flags: 0, text: @actions[qacindex].label, escapable: true)

  if label!=nil
    QuickActions.rename(qacindex, label)
  acsel_load
  end
  }
  menu.option(p_("Main", "Change hotkey"), nil, "k") {
  s=[p_("Main", "None")]
  k=[0]
  for i in 1..11
    s.push("F"+i.to_s)
    k.push(i)
    s.push("SHIFT+F"+i.to_s)
    k.push(-i)
    s.push(EltenAPI::KeyboardScheme.modifier_name+"+F"+i.to_s)
    k.push(i+12)
    s.push(EltenAPI::KeyboardScheme.modifier_name+"+SHIFT+F"+i.to_s)
    k.push(-(i+12))
  end
  ind=k.find_index(@actions[qacindex].key)||0
  sel = ListBox.new(s, header: p_("Main", "Hotkey for action %{label}")%{:label=>@actions[qacindex].label}, index: ind, flags: 0, quiet: false)
  loop {
  loop_update
  sel.update
  break if key_pressed?(:key_escape)
  if sel.selected?
  key=k[sel.index]
  c=nil
@actions.each{|a| c=a if a.key==key }
if c==nil || c==@actions[qacindex] || key==0
  QuickActions.rekey(qacindex, key)
  acsel_load
  break
else
  alert(p_("Main", "This hotkey is already used by action %{action}")%{:action=>c.label}, false)
  end
end
}
  @acsel.focus
  }
  if qacindex>0
    menu.option(p_("Main", "Move up")) {
qacup
    }
  end
  if qacindex<@actions.size-1
    menu.option(p_("Main", "Move down")) {
qacdown
    }
  end
  s=p_("Main", "Hide this action")
  s=p_("Main", "Show this action") if @actions[qacindex].show==false
  menu.option(s) {
  QuickActions.reshow(qacindex, !@actions[qacindex].show)
    acsel_load
  }
  menu.option(p_("Main", "Delete"), nil, :del) {
  ac=0
  if @actions[qacindex].key==0 || @actions[qacindex].show==false
      ac=confirm(p_("Main", "Are you sure you want to delete this quick action?")) ? 1 : 0
    else
      ac=selector([_("Cancel"), p_("Main", "Delete"), p_("Main", "Hide this action")], header: p_("Main", "If you delete this action, you will also delete the keyboard shortcut assigned to it. If you want to keep the keyboard shortcut, you can hide this action. You can show or remove hidden actions at any time."), start_index: 0, cancel_index: 0, flags: 1)
      end
      if ac==1
          QuickActions.delete(qacindex)
  acsel_load(false)
  @acsel.say_option
elsif ac==2
  QuickActions.reshow(qacindex, false)
    acsel_load
          end
  }
end
s=p_("Main", "Show hidden actions")
s=p_("Main", "Hide hidden actions") if @acselshowhidden
menu.option(s, nil, "h") {
@acselshowhidden=!@acselshowhidden
acsel_load
}
  menu.option(p_("Main", "Add"), nil, "n") {
  action_add
  }
  menu.option(p_("Main", "Restore defaults")) {
  confirm(p_("Main", "Are you sure you want to restore default Quick Actions?")) {
  QuickActions.reset_defaults
  acsel_load
  @acsel.focus
  }
  }
end
def action_add
  actions=[]
  actionlabels=[]
    c=QuickActions.predefined_procs
  for a in c
    actions.push(a[0])
    actionlabels.push(a[1])
  end
    g=GlobalMenu.scenes
  for m in g
    actions.push(m[1])
    actionlabels.push(m[0])
  end
  ind=selector(actionlabels, header: p_("Main", "Select quick action to add"), start_index: 0, cancel_index: -1)
  if ind>=0
    action=actions[ind]
    params=[]
    if action.is_a?(Array)
            params=action[1..-1]
      action=action[0]
      end
    alert(_("Error")) if !QuickActions.create(action, actionlabels[ind], params)
    acsel_load
  else
  @acsel.focus
  end
end
def feeds_load(fc=false)
  @@feed_id = @feeds[@feedsel.index].id if @feeds.is_a?(Array) && @feeds.size>0 && @feedsel!=nil
  @feeds=[]
  ind=-1
  for f in Session.feeds.keys.sort.reverse
    feed=Session.feeds[f]
    @feeds.push(feed) if feed!=nil && feed.message!=""
    ind=@feeds.size-1 if ind==-1 && @@feed_id>0 && feed.id<=@@feed_id
  end
  ind=0 if ind==-1
selt=@feeds.map{|f|
parts=[utf8(f.user)]
parts << EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemliked", " "+p_("EAPI_Speech", "Liked")+": ", "(like)", immediate: true) if f.liked
parts << ": "+utf8(f.message)+" "
parts << "("+utf8(np_("Main", "%{count} user likes it", "%{count} users like it", f.likes)%{:count=>f.likes})+") " if f.likes>0
begin
parts << utf8(format_date(Time.at(f.time)))
rescue Exception
  end
parts << EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemcontaining", " "+p_("EAPI_Speech", "Containing")+": ", "->", immediate: true) if f.responses>0
EltenAPI::SpeechSequence.new(parts)
}
  if @feedsel==nil
  @feedsel = ListBox.new(selt, header: p_("Main", "Feed"), index: ind)
  @feedsel.bind_context{|menu|feeds_context(menu)}
  @feedsel.on(:move) {
  if @feeds.size>0
  feed=@feeds[@feedsel.index]
  if feed!=nil
    EltenAPI::InvisibleInterface.set_feed_id(feed.id) if defined?(EltenAPI::InvisibleInterface)
  end
  end
  }
else
  @feedsel.options = selt
    @feedsel.index = ind
end
@feedsel.focus if fc
end

def utf8(value)
  str=value.to_s.dup
  str.force_encoding(Encoding::UTF_8) if str.encoding!=Encoding::UTF_8
  str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
end
def feeds_context(menu)
  if @feeds.size>0
    feed=@feeds[@feedsel.index]
    menu.useroption(feed.user)
    if feed.responses>0
      menu.option(p_("Main", "Show responses"), nil, "d") {
      $scene = Scene_FeedViewer.new(feed)
      }
      elsif feed.response>0
      menu.option(p_("Main", "Show conversation"), nil, "d") {
      $scene = Scene_FeedViewer.new(feed, nil, false)
      }
    end
    if feed.likes>0
    menu.option(p_("Main", "Show likes"), nil, "K") {
  likes=[]
  begin
    likes=EltenLink::Feeds.likes(elten_link, feed.id)
  rescue EltenLink::Error => e
    Log.warning("Feed likes failed: #{e.message}")
  end
users=likes
dialog_open
lst=ListBox.new(users, header: p_("Main", "Users who like this post"), index: 0, flags: 0, quiet: false)
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
      menu.option(p_("Main", "Reply"), nil, "r") {
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
    s=p_("Main", "Like this message")
    s=p_("Main", "Dislike this message") if feed.liked
    menu.option(s, nil, "k") {
    begin
      EltenLink::Feeds.set_liked(elten_link, feed.id, !feed.liked)
    rescue EltenLink::Error => e
      Log.warning("Feed like toggle failed: #{e.message}")
    alert(_("Error"))
  else
    st=(feed.liked)?(p_("Main", "Message disliked")):(p_("Main", "Message liked"))
    feed.liked=!feed.liked
    alert(st)
    end
    }
    if feed.user==Session.name
    menu.option(_("Delete"), nil, :del) {
    confirm(p_("Main", "Are you sure you want to delete this post?")) {
    delete_feed(feed.id)
    }
    play_sound("editbox_delete")
    }
    end
  end
  menu.option(p_("Main", "Publish to a feed"), nil, "n") {feed_new}
  end
def feed_new(users=[], response=0)
  text=users.map{|u|"@"+u}.join(" ")
  text<<" " if text!=""
    inp = input_text(p_("Main", "Message"), flags: 0, text: text, escapable: true, permitted_characters: [], denied_characters: [], max_length: 300, move_to_end: true)
  feed(inp, response) if inp!=nil
end
def feed_id=(f)
  for i in 0...@feeds.size
    @feedsel.index=i if @feeds[i].id>=f
    end
  end
def self.feed_id=(f)
  @@feed_id=f
  $scene.feed_id=f if $scene.is_a?(Scene_Main)
  end
end
