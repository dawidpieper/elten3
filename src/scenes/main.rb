# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Main
  include NotificationGroups
  include FeedNavigation

  NOTIFICATION_FOCUS_POLICIES = [:configured, :keep_current, :new_notifications, :unread_notifications].freeze

  @@acselindex=nil
  @@notification_index=0
  @@notifications_last_visible_time=0
  FeedSelection = Struct.new(:id, :generation)
  private_constant :FeedSelection
  @@feed_id=-1
  @@return_feed_selection=nil
  @@focus=:actions
  @@specials=[]

  def initialize(notification_focus: :configured)
    raise ArgumentError, "Invalid notification focus policy: #{notification_focus}" if !NOTIFICATION_FOCUS_POLICIES.include?(notification_focus)
    @notification_focus = notification_focus
  end

  def main
    if @@feed_id==-1
      @@feed_id = LocalConfig['MainFeedId', type: :numeric]
    end
    if @@return_feed_selection
      @requested_feed_selection = @@return_feed_selection
      @@return_feed_selection = nil
    end
    if !Session.logged? && $preinitialized!=true
      $scene=Scene_Loading.new
      return
    end
    NVDA.braille("") if defined?(NVDA) && NVDA.check
    if $restart==true
      $restart=false
      $scene=Scene_Loading.new
      return
    end
    if Session.logged?
      welcome_wizard_mode = EltenAPI::WelcomeWizardLaunch.consume
      if welcome_wizard_mode != nil
        Log.info("Starting welcome wizard in #{welcome_wizard_mode} mode")
        $scene = Scene_WelcomeWizard.new(welcome_wizard_mode == :first_run)
        return
      end
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
    return if show_beta_testing_group_notice
    ci = 0
    plsinfo = false
    ci += 1 if ci < 20

    Session.notifications_updated?
    $main_notifications_changed = false
    notifications_load(false, focus_policy: entry_notification_focus_policy)
    acsel_load(false)
    @program_ui_revision = program_ui_revision
    focus_current_control
    @from_feed = false

    loop do
      loop_update
      Scene_Programs.finish_login_update_check if $scene == self
      refresh_program_ui_if_needed
      notifications_changed = Session.notifications_updated?
      if $main_notifications_changed == true || notifications_changed
        $main_notifications_changed = false
        previous_section = current_main_section
        minimized = main_window_minimized?
        notifications_load(false, focus_policy: Configuration.mainnotificationfocus)
        if minimized
          current_section = current_main_section
          if previous_section != :notifications && current_section == :notifications
            @announce_notifications_after_restore = true
          elsif previous_section == :notifications && current_section != :notifications
            @announce_notifications_after_restore = false
          end
        end
      end
      announce_notifications_after_restore_if_active
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
      EltenAPI::ExceptionRecovery.ready!
      break if $scene != self
    end
    @@notification_index=@notifications_sel.index if @notifications_sel!=nil
    @@acselindex=@acsel.index if @acsel!=nil
    unless @@return_feed_selection
      @@feed_id = pending_feed_selection&.id || (@feedsel && @feeds[@feedsel.index]&.id) || @@feed_id
    end
    LocalConfig['MainFeedId'] = @@feed_id
  end

  def show_beta_testing_group_notice
    return false unless Session.logged? && %w[beta rc].include?(Elten.branch.to_s.downcase)

    group_id = EltenAPI::ServerData[:beta_testing_group_id]
    return false unless group_id.is_a?(Integer) && group_id.positive?
    return false if LocalConfig["BetaTestingGroupNoticeShown", type: :bool]

    open_group = confirm(p_("Main", "Since 22 October 2026, beta testing for Elten has taken place in a single English-speaking group.\n\nWe know that English-speaking users have had very limited contact with the developer for a long time. We are also aware of the many bugs still present in Elten, as well as your many ideas and suggestions.\n\nPlease visit the new group and join the discussion. Help us shape Elten and report any bugs you find.\n\nWould you like to visit this group now?"))
    LocalConfig["BetaTestingGroupNoticeShown"] = true
    $scene = Scene_Forum.new(nil, group_id) if open_group
    open_group
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
  sections << :actions if main_tab_enabled?(:actions)
  sections << :feed if main_tab_enabled?(:feed)
  sections.concat(program_main_tabs.map { |tab| tab.section_id })
  sections << :empty if sections.empty?
  sections
end

def main_tab_enabled?(tab)
  Configuration.maintabs.to_a.include?(tab)
end

def program_main_tabs
  return [] if !defined?(Programs::Extensions)
  Programs::Extensions.main_tabs
end

def program_main_tab(section)
  return nil if !defined?(Programs::Extensions)
  Programs::Extensions.main_tab(section)
end

def program_main_tab_control(section=current_main_section)
  contribution = program_main_tab(section)
  return nil if contribution == nil
  @program_main_tab_entries ||= {}
  entry = @program_main_tab_entries[contribution.section_id]
  if entry == nil || !entry[:contribution].equal?(contribution)
    entry = { :contribution => contribution, :control => nil, :state => {} }
    @program_main_tab_entries[contribution.section_id] = entry
  end
  control = contribution.build_control(self, entry[:control], entry[:state])
  entry[:control] = control if control != nil
  entry[:control]
end

def program_ui_revision
  return 0 if !defined?(Programs::Extensions)
  Programs::Extensions.ui_revision
end

def refresh_program_ui_if_needed
  revision = program_ui_revision
  return if @program_ui_revision == revision
  previous_section = @@focus
  @program_ui_revision = revision
  prune_program_main_tab_entries
  acsel_load(false) if @acsel != nil
  normalize_main_focus
  focus_current_control if @@focus != previous_section
end

def prune_program_main_tab_entries
  return if @program_main_tab_entries == nil
  contributions = if defined?(Programs::Extensions)
                    Programs::Extensions.all_main_tabs
                  else
                    []
                  end
  active = {}
  contributions.each { |tab| active[tab.section_id] = tab }
  @program_main_tab_entries.delete_if do |section, entry|
    contribution = active[section]
    contribution == nil || !entry[:contribution].equal?(contribution)
  end
end

def entry_notification_focus_policy
  return Configuration.mainnotificationfocus if @notification_focus == :configured
  @notification_focus
end

def notifications_visible?
  return false if !main_tab_enabled?(:notifications)
  Configuration.showemptynotifications == true || (@notification_groups.is_a?(Array) && @notification_groups.size>0)
end

def empty_main_control
  @empty_main_control ||= ListBox.new([], header: p_("Main", "Main window"))
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
    refresh_feed_list
    if @from_feed
      @feedsel&.focus(announce_header: false)
    else
      @feedsel&.focus
    end
  when :empty
    empty_main_control.focus
  else
    control = program_main_tab_control
    control.focus if control != nil
  end
end

def say_current_option
  case current_main_section
  when :notifications
    @notifications_sel.sayoption if @notifications_sel!=nil
  when :actions
    @acsel.sayoption if @acsel!=nil
  when :feed
    refresh_feed_list
    @feedsel.sayoption
  when :empty
    empty_main_control.sayoption
  else
    control = program_main_tab_control
    control.sayoption if control != nil
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

def main_window_minimized?
  EltenWindow.minimized?
rescue Exception
  false
end

def announce_notifications_after_restore_if_active
  return if @announce_notifications_after_restore != true
  return if main_window_minimized?
  return if !main_window_active?

  @announce_notifications_after_restore = false
  return if current_main_section != :notifications || @notifications_sel == nil

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
    refresh_feed_list
    @feedsel.update
  when :empty
    empty_main_control.update
  else
    control = program_main_tab_control
    control.update if control != nil
  end
end

def notifications_load(fc=false, focus_policy: :keep_current)
  previous_visible_time = @@notifications_last_visible_time.to_i
  selected_notification_key = current_notification_group&.key
  @@notification_index=@notifications_sel.index if @notifications_sel!=nil
  if !main_tab_enabled?(:notifications)
    @notification_groups = []
    @notifications_sel = nil
    normalize_main_focus
    focus_current_control if fc
    return
  end
  notifications = fetch_main_notifications
  @notification_groups = build_active_main_notification_groups(notifications)
  latest_time = latest_notification_group_time(@notification_groups)
  jump_to_notifications = focus_notifications_on_entry?(focus_policy, latest_time, previous_visible_time)
  @@notifications_last_visible_time = [previous_visible_time, notification_visibility_time(latest_time), latest_time].max
  if !notifications_visible?
    @notifications_sel = nil
    normalize_main_focus
    focus_current_control if fc
    return
  end
  @@notification_index = notification_reload_index(@notification_groups, selected_notification_key, @@notification_index)
  @notifications_sel = TableBox.new(notification_columns, notification_rows(@notification_groups), index: @@notification_index, header: p_("Notifications", "Notifications"), quiet: true)
  @notifications_sel.bind_context { |menu| notifications_context(menu) }
  if jump_to_notifications
    @@focus = :notifications
    @notifications_sel.focus if fc
  elsif fc
    @notifications_sel.focus
  end
end

def focus_notifications_on_entry?(policy, latest_time, previous_visible_time)
  return false if @notification_groups.empty?
  case policy
  when :new_notifications
    previous_visible_time <= 0 || latest_time > previous_visible_time
  when :unread_notifications
    true
  else
    false
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
  return [] unless Session.logged?
  EltenAPI::NotificationService.active_notifications
end

def current_notification_group
  return nil if @notification_groups==nil || @notification_groups.empty? || @notifications_sel==nil
  @notification_groups[@notifications_sel.index]
end

def notification_reload_index(groups, selected_key, fallback_index)
  matched_index = groups.to_a.index { |group| selected_key != nil && group.key == selected_key }
  index = matched_index == nil ? fallback_index.to_i : matched_index
  [[index, 0].max, [groups.to_a.size - 1, 0].max].min
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
    EltenAPI::NotificationService.refresh_active_notifications
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
      if $scene == self
        refresh_feed_list
        @feedsel.focus
      end
      loop_update
    end
    if @feedsel.expanded?
      feed=@feeds[@feedsel.index]
      if feed && feed.responses>0
        open_feed_responses(feed)
      end
    end
  end
end
def open_feed_responses(feed)
  @notification_focus = :keep_current
  $scene = Scene_FeedViewer.new(feed, feed_parent: self)
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
  if defined?(Programs::Extensions)
    Programs::Extensions.main_actions.each do |action|
      @specials << [action.id, action.label, proc { action.call }]
    end
  end
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
  menu.option(p_("Main", "Change keyboard shortcut"), nil, "k") {
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
  sel = ListBox.new(s, header: p_("Main", "Keyboard shortcut for action %{label}")%{:label=>@actions[qacindex].label}, index: ind, flags: 0, quiet: false)
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
  alert(p_("Main", "This keyboard shortcut is already used by action %{action}")%{:action=>c.label}, false)
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
      ac=confirm(p_("Main", "Are you sure you want to delete the quick action %{action}?")%{ :action => @actions[qacindex].label}) ? 1 : 0
    else
      ac=selector([_("Cancel"), p_("Main", "Delete"), p_("Main", "Hide this action")], header: p_("Main", "If you delete the action %{action}, you will also delete the keyboard shortcut assigned to it. If you want to keep the keyboard shortcut, you can hide this action. You can show or remove hidden actions at any time.")%{ :action => @actions[qacindex].label}, start_index: 0, cancel_index: 0, flags: 1)
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
  refresh_feed_list(force: true)
  @feedsel.focus if fc
end

def refresh_feed_list(force: false)
  batch = Session.take_feed_changes(@feed_revision)
  generation = Session.feed_generation
  request = pending_feed_selection
  if request && @feed_generation == generation && (index = @feed_positions[request.id])
    # If this batch removes the requested entry, restore focus from that entry.
    @feedsel.index = index
    @applied_feed_selection = request
    request = nil
  end
  language = Configuration.language
  soundtheme = Configuration.soundthemeactivation == true
  refresh_all = force || !@feedsel || @feed_generation != generation || @feed_language != language || @feed_soundtheme != soundtheme
  if batch || refresh_all
    revision, changes = batch
    records = Session.feeds
    selected_id = @feedsel && @feeds[@feedsel.index]&.id
    if @feed_generation != generation
      if @feedsel
        unless @feed_owner_name == Session.name && @feed_owner_token == Session.token
          selected_id = nil
          @@feed_id = -1
        end
        @feedsel.clear_options
        @feedsel = nil
        @feed_audio_status = nil
      end
      @feed_owner_name = Session.name.dup
      @feed_owner_token = Session.token.dup
    end
    @@feed_id = selected_id if selected_id
    selected_id ||= @@feed_id
    if refresh_all || changes == :reset
      rows = records.values.select { |feed| feed && feed.message != "" }.sort_by!(&:id).reverse!
      set_feed_rows(rows, rows.map { |feed| feed_option(feed) }, records, selected_id)
      @feed_audio_status = configure_feed_list_audio(@feedsel, @feeds, previous_status: @feed_audio_status)
      @feed_language = language.dup
      @feed_soundtheme = soundtheme
    else
      update_feed_rows(changes, records, selected_id)
    end
    @feed_generation = generation
    @feed_revision = revision if batch
  end

  if request && !@feeds.empty?
    # The invisible interface picks the lowest visible ID at or above its target.
    newer_count = @feeds.bsearch_index { |feed| feed.id < request.id } || @feeds.size
    @feedsel.index = newer_count - 1 if newer_count > 0
    @applied_feed_selection = request
  end
end

def update_feed_rows(changes, records, selected_id)
  additions = []
  removals = {}
  changes.each do |id|
    index = @feed_positions[id]
    feed = records[id]
    if feed && feed.message != ""
      if index
        @feeds[index] = feed
        @feedsel.replace_option(index, feed_option(feed))
      else
        additions << feed
      end
    elsif index
      removals[id] = true
    end
  end

  unless additions.empty? && removals.empty?
    additions.sort_by!(&:id)
    rows = []
    @feeds.each do |feed|
      rows << additions.pop while !additions.empty? && additions.last.id > feed.id
      rows << feed unless removals.key?(feed.id)
    end
    rows.concat(additions.reverse)
    options = rows.map do |feed|
      previous = @feed_positions[feed.id]
      previous ? @feedsel.options[previous] : feed_option(feed)
    end
    set_feed_rows(rows, options, records, selected_id)
  end
  changes.each do |id|
    index = @feed_positions[id]
    configure_feed_item_audio(@feedsel, index, @feeds[index], status: @feed_audio_status) if index
  end
end

def set_feed_rows(rows, options, records, selected_id)
  @feeds = rows
  ids = rows.map(&:id)
  @feed_positions = {}
  ids.each_with_index { |id, index| @feed_positions[id] = index }
  index = feed_restore_index(selected_id, records)
  if @feedsel
    @feedsel.header = p_("Main", "Feed")
    @feedsel.update_options(options, keys: ids)
    @feedsel.index = index
  else
    @feedsel = ListBox.new(options, header: p_("Main", "Feed"), keys: ids, index: index)
    @feedsel.bind_context { |menu| feeds_context(menu) }
    @feedsel.on(:move) do
      feed = @feeds[@feedsel.index]
      EltenAPI::InvisibleInterface.set_feed_id(feed.id) if feed && defined?(EltenAPI::InvisibleInterface)
    end
  end
end

def feed_restore_index(id, records)
  return 0 unless id && id > 0
  return @feed_positions[id] if @feed_positions.key?(id)

  # The old list visits empty messages when restoring focus. A deleted entry
  # therefore selects the visible entry just above it, if one exists.
  target = nil
  records.each_key { |key| target = key if key <= id && (!target || key > target) }
  return 0 unless target
  return @feed_positions[target] if @feed_positions.key?(target)

  older = @feeds.bsearch_index { |feed| feed.id < target } || @feeds.size
  [older - 1, 0].max
end

def feed_option(feed)
  parts = [utf8(feed.user)]
  parts << EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemliked", " " + p_("EAPI_Speech", "Liked") + ": ", "(like)", immediate: true) if feed.liked
  parts << ": " + utf8(feed.message) + " "
  parts << "(" + utf8(np_("Main", "%{count} user likes it", "%{count} users like it", feed.likes) % { count: feed.likes }) + ") " if feed.likes > 0
  begin
    parts << utf8(format_date(Time.at(feed.time)))
  rescue StandardError
    # Keep entries with timestamps outside the supported range.
  end
  parts << EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemcontaining", " " + p_("EAPI_Speech", "Containing") + ": ", "->", immediate: true) if feed.responses > 0
  EltenAPI::SpeechSequence.new(parts)
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
      open_feed_responses(feed)
      }
      elsif feed.response>0
      menu.option(p_("Main", "Show conversation"), nil, "d") {
      open_feed_responses(feed)
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
    if Session.logged?
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
    feed_generation = @feed_generation
    liked = !feed.liked
    label = liked ? p_("Main", "Like this message") : p_("Main", "Dislike this message")
    menu.option(label, nil, "k") {
      next unless feed_generation == Session.feed_generation
      begin
        EltenLink::Feeds.set_liked(elten_link, feed.id, liked)
      rescue EltenLink::Error => e
        Log.warning("Feed like toggle failed: #{e.message}")
        alert(_("Error"))
      else
        Session.confirm_feed_like(feed, liked, generation: feed_generation)
        alert(liked ? p_("Main", "Message liked") : p_("Main", "Message disliked"))
      end
    }
    if feed.user==Session.name
    menu.option(_("Delete"), nil, :del) {
    if confirm(p_("Main", "Are you sure you want to delete this post?"))
      begin
        delete_feed(feed.id)
      rescue EltenLink::Error => e
        Log.warning("Feed deletion failed: #{e.message}")
        alert(_("Error"))
      else
        play_sound("editbox_delete")
      end
    end
    }
    end
  end
  menu.option(p_("Main", "Publish to a feed"), nil, "n") {feed_new}
  end
  end
def feed_new(users=[], response=0)
  compose_feed(users, response)
end
def pending_feed_selection
  request = @requested_feed_selection
  request if request && !request.equal?(@applied_feed_selection) && request.generation == Session.feed_generation
end

def feed_id=(id)
  @requested_feed_selection = FeedSelection.new(id, Session.feed_generation)
  refresh_feed_list if Thread.current == $mainthread && current_main_section == :feed
end

def self.feed_id=(id)
  @@feed_id = id
  scene = $scene
  if scene.is_a?(Scene_Main)
    scene.feed_id = id
  else
    @@return_feed_selection = FeedSelection.new(id, Session.feed_generation)
  end
end
end
