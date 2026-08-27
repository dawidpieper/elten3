# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See <https://www.gnu.org/licenses/>.

require "date"

class Scene_WelcomeWizard
  Page = Struct.new(:id, :title, :builder, keyword_init: true)
  View = Struct.new(:fields, :capture, keyword_init: true)
  BlogSuggestion = Struct.new(:user, :blog, keyword_init: true)

  APP_IDS = {
    ffmpeg: "f2e2661b-f6b2-4b32-8c38-62e890a13c41",
    file_manager: "8c8d86ce-dc24-453f-a388-e9b5e8626c5c",
    mcp: "bf4dbbd4-cadc-4ab2-8738-7340677de1e2"
  }.freeze

  DOWNLOAD_URL = "https://elten.link/download".freeze
  WEBSITE_URL = "https://elten.link".freeze
  SOURCE_URL = "https://github.com/dawidpieper/elten3".freeze

  def initialize(first_run=false, force_all=false)
    @first_run = first_run == true
    @force_all = force_all == true
    @show_irrelevant = true
    @state = {}
    @pages = []
    @page_index = 0
    @applied = []
    @failed = []
  end

  def main
    unless Session.logged?
      alert(p_("WelcomeWizard", "Sign in before starting the setup wizard."))
      $scene = Scene_Main.new
      return
    end

    preload
    build_pages
    if @pages.empty?
      alert(p_("WelcomeWizard", "No setup pages are available for this account."))
      $scene = Scene_Main.new
      return
    end

    show_page
    loop do
      loop_update
      @form.update
      if key_pressed?(:key_escape)
        cancel_wizard
      elsif @back_button != nil && @back_button.pressed?
        previous_page
      elsif @next_button.pressed?
        next_page
      end
      break if $scene != self || $restart == true
    end
  ensure
    waiting_end rescue nil
  end

  private

  def preload
    waiting
    speak(p_("WelcomeWizard", "Preparing the wizard: loading your account and community information."))
    @program_platform_target = defined?(Programs) ? Programs.platform_target : platform_target
    load_wizard_data
  ensure
    waiting_end
  end

  def build_pages
    add_welcome_page
    @first_run ? add_orientation_pages : add_upgrade_information_pages
    add_language_pages
    add_profile_pages
    add_security_page
    add_community_pages
    APP_IDS.each_key { |kind| add_app_page(kind) }
    add_platforms_page if @first_run
    add_open_source_page
    add_support_page
    add_github_star_page
    add_thanks_page
    add_summary_page
  end

  def add_welcome_page
    text = if @first_run
      p_("WelcomeWizard", "Welcome to Elten, and thank you for joining the community. This wizard will help you take your first steps: it shows you how to find your way around the program, helps you complete your account and profile, and introduces you to the community. Use Tab and Shift+Tab to move between the fields and buttons on a page, and the Next and Back buttons to move between pages; skip anything that does not interest you. Nothing is applied until you choose Finish on the last page, and you can leave at any time by pressing Escape.")
    else
      p_("WelcomeWizard", "Welcome to Elten 3.0. Starting with this version, Elten runs on an engine of its own and no longer relies on the old RGSS runtime. That change opened the way to new platforms, resolved many long-standing problems and allowed a thorough rebuild of the program, with dozens of changes and refinements too numerous to list here. The next pages of this wizard walk you through the most important ones. Use Tab and Shift+Tab to move between the fields and buttons on a page, and the Next and Back buttons to move between pages; skip anything that does not interest you. Nothing is applied until you choose Finish on the last page, and you can leave at any time by pressing Escape.")
    end
    add_page(:welcome, p_("WelcomeWizard", "Welcome")) do
      info = information_field(p_("WelcomeWizard", "Welcome"), text)
      if @force_all
        check = CheckBox.new(p_("WelcomeWizard", "Show pages that do not apply to me"), checked: @show_irrelevant)
        view([info, check]) do
          if check.checked != @show_irrelevant
            @show_irrelevant = check.checked
            rebuild_pages
          end
        end
      else
        view([info])
      end
    end
  end

  def rebuild_pages
    @pages.clear
    build_pages
  end

  def add_platforms_page
    add_page(:platforms, p_("WelcomeWizard", "Elten on desktop, mobile and the web")) do
      desktop_text = if @first_run
        p_("WelcomeWizard", "The Elten desktop client runs on Windows, GNU/Linux and macOS on Apple Silicon. Whichever system you choose, you get exactly the same client, with the same interface and the same features.")
      else
        p_("WelcomeWizard", "Until now, Elten was a Windows-only program. Elten 3.0 also runs on GNU/Linux and on macOS on Apple Silicon, and instead of being an x86 program it now runs natively on x64 and arm64 processors. These are not cut-down ports: every system receives exactly the same client, with the same interface and the same features.")
      end
      desktop = information_field(p_("WelcomeWizard", "Desktop computers"), desktop_text)
      mobile_text = if @first_run
        p_("WelcomeWizard", "Eltenger is a separate, native application for iOS and Android, designed to ultimately allow full participation in the community from a smartphone. It is still in early testing, so do not expect it to match the desktop client in features or stability just yet.")
      else
        p_("WelcomeWizard", "The community can now also be reached from a smartphone: Eltenger is a separate, native application for iOS and Android, designed to ultimately allow full integration with Elten. It is still in early testing, so do not expect it to match the desktop client in features or stability just yet.")
      end
      mobile = information_field(p_("WelcomeWizard", "Mobile devices"), mobile_text)
      website_text = if @first_run
        p_("WelcomeWizard", "The project's website allows you to take a full part in the community from an ordinary web browser, and it is being developed step by step. It is also where every client can be downloaded.")
      else
        p_("WelcomeWizard", "If you remember the legacy Elten website, the new one is a different story altogether: completely renewed, it allows fully fledged participation in the community from an ordinary web browser, and it is being developed step by step.")
      end
      website = information_field(p_("WelcomeWizard", "Project website"), website_text)
      downloads_button = Button.new(p_("WelcomeWizard", "Open the downloads page"))
      downloads_button.on(:press) { platform_open_url(DOWNLOAD_URL) }
      website_button = Button.new(p_("WelcomeWizard", "Open the project website"))
      website_button.on(:press) { platform_open_url(WEBSITE_URL) }
      view([desktop, mobile, website, downloads_button, website_button])
    end
  end

  def add_orientation_pages
    add_menus_page
    add_info_page(
      :quick_actions,
      p_("WelcomeWizard", "Quick Actions"),
      p_("WelcomeWizard", "The main window greets you with a list of Quick Actions: shortcuts that take you straight to the places and commands you use most, such as opening Messages, publishing to the feed or entering a conference channel. The default set covers the essentials, but all of it is yours to change: use a Quick Action's context menu to move, rename, hide or delete it, assign a hotkey to it, add further actions or restore the defaults.")
    )
    add_sounds_page
    add_controls_presentation_page
    add_nvda_page if nvda_active?
    add_media_page
    add_autoplay_page
    add_main_window_page
    add_feed_notifications_page if feed_tab_hidden?
    add_tray_page if tray_supported?
    add_invisible_interface_page if invisible_interface_available?
    add_macos_page if platform_os.to_s == "osx"
  end

  def add_controls_presentation_page
    add_page(:controls_presentation, p_("WelcomeWizard", "Announcing controls")) do
      info = information_field(
        p_("WelcomeWizard", "Announcing controls"),
        p_("WelcomeWizard", "As you move around Elten, every control introduces itself: a button, a list, a text field. How it does so is up to you. Elten can name the type in speech, mark it with its sound alone, or do both at once. Voice and sound is the friendlier choice while you are still learning; sound only makes navigation quicker once the sounds feel familiar. The list below shows the current behaviour, and you can change it at any time under Tools, Program settings.")
      )
      values = ["voice_and_sound", "sound_only", "voice_only"]
      current = configuration_choice(:controlspresentation, values)
      list = ListBox.new(
        [p_("WelcomeWizard", "Voice and sound"), p_("WelcomeWizard", "Sound only"), p_("WelcomeWizard", "Voice only")],
        header: p_("WelcomeWizard", "Control types announcement"),
        index: values.index(@state[:controls_presentation] || current) || 0
      )
      view([info, list]) do
        selected = values[list.index]
        selected == current ? @state.delete(:controls_presentation) : @state[:controls_presentation] = selected
      end
    end
  end

  def add_tray_page
    add_page(:tray, p_("WelcomeWizard", "Minimising to the system tray")) do
      current = Configuration.hidewindow == true rescue false
      info = information_field(
        p_("WelcomeWizard", "Minimising to the system tray"),
        p_("WelcomeWizard", "Elten does not have to occupy your taskbar all day. With the option below enabled, minimising the Elten window sends it to the system tray instead, where the program keeps running quietly and continues to receive notifications; the Elten icon in the tray brings the window back. Leave the option unticked if you prefer Elten to behave like an ordinary window.")
      )
      check = CheckBox.new(
        p_("WelcomeWizard", "Automatically minimise the Elten window to the system tray"),
        checked: @state.key?(:hide_window) ? @state[:hide_window] == "true" : current
      )
      view([info, check]) do
        selected = check.checked
        selected == current ? @state.delete(:hide_window) : @state[:hide_window] = selected ? "true" : "false"
      end
    end
  end

  def add_main_window_page
    add_page(:main_window, p_("WelcomeWizard", "Main window")) do
      intro = if @first_run
        p_("WelcomeWizard", "The main window is built of tabs: Notifications, the Feed and Quick Actions. Not everyone needs all three, so you can choose which of them are shown. The notifications tab has two habits of its own that you can adjust as well: by default it appears only while there are notifications to show, and you can decide whether, and when, it takes focus as you return to the main window. All of this can also be changed later under Tools, Program settings, Main window.")
      else
        p_("WelcomeWizard", "In Elten 2.x, the main window had two tabs: Quick Actions and the feed. Elten 3.0 joins them with a third, Notifications, and leaves the whole arrangement to you: choose exactly the tabs you want to see. The notifications tab has two habits of its own that you can adjust as well: by default it appears only while there are notifications to show, and you can decide whether, and when, it takes focus as you return to the main window. All of this can also be changed later under Tools, Program settings, Main window.")
      end
      info = information_field(p_("WelcomeWizard", "The main window"), intro)
      tab_values = ["notifications", "feed", "actions"]
      tabs = ListBox.new(
        [p_("WelcomeWizard", "Notifications"), p_("WelcomeWizard", "Feed"), p_("WelcomeWizard", "Quick actions")],
        header: p_("WelcomeWizard", "Tabs visible in the main window"),
        flags: ListBox::Flags::MultiSelection
      )
      current_tabs = current_main_tabs
      (@state[:main_tabs] || current_tabs).each do |value|
        index = tab_values.index(value)
        tabs.selected[index] = true if index != nil
      end
      current_empty = Configuration.showemptynotifications == true rescue false
      empty_check = CheckBox.new(
        p_("WelcomeWizard", "Show the notifications tab even when there are no new notifications"),
        checked: @state.key?(:show_empty_notifications) ? @state[:show_empty_notifications] == "true" : current_empty
      )
      focus_values = ["keep_current", "new_notifications", "unread_notifications"]
      current_focus = configuration_choice(:mainnotificationfocus, focus_values)
      focus = ListBox.new(
        [p_("WelcomeWizard", "Keep the previously selected tab"), p_("WelcomeWizard", "Switch only when new notifications arrive"), p_("WelcomeWizard", "Switch whenever unread notifications are present")],
        header: p_("WelcomeWizard", "Notification focus after returning to the main window"),
        index: focus_values.index(@state[:notification_focus] || current_focus) || 0
      )
      view([info, tabs, empty_check, focus]) do
        selected_tabs = tabs.multiselections.map { |index| tab_values[index] }.compact
        if selected_tabs.empty?
          alert(p_("WelcomeWizard", "Select at least one tab to show in the main window."))
          next false
        end
        selected_tabs.sort == current_tabs.sort ? @state.delete(:main_tabs) : @state[:main_tabs] = selected_tabs
        selected_empty = empty_check.checked
        selected_empty == current_empty ? @state.delete(:show_empty_notifications) : @state[:show_empty_notifications] = selected_empty ? "true" : "false"
        selected_focus = focus_values[focus.index]
        selected_focus == current_focus ? @state.delete(:notification_focus) : @state[:notification_focus] = selected_focus
        @state.delete(:disable_feed_notifications) unless feed_tab_hidden?
        rebuild_pages if feed_tab_hidden? != @pages.any? { |page| page.id == :feed_notifications }
        true
      end
    end
  end

  def feed_tab_hidden?
    !(@state[:main_tabs] || current_main_tabs).include?("feed")
  end

  def add_feed_notifications_page
    add_page(:feed_notifications, p_("WelcomeWizard", "Feed notifications")) do
      current = Configuration.disablefeednotifications == true rescue false
      info = information_field(
        p_("WelcomeWizard", "Feed notifications"),
        p_("WelcomeWizard", "The Feed tab will not be shown in your main window, so you may also prefer not to be notified about new feed entries. Ticking the option below keeps the feed quiet: you can still open it and follow people whenever you wish, but new entries will no longer announce themselves. Leave it unticked to keep receiving feed notifications as usual.")
      )
      check = CheckBox.new(
        p_("WelcomeWizard", "Disable feed notifications"),
        checked: @state.key?(:disable_feed_notifications) ? @state[:disable_feed_notifications] == "true" : current
      )
      view([info, check]) do
        selected = check.checked
        selected == current ? @state.delete(:disable_feed_notifications) : @state[:disable_feed_notifications] = selected ? "true" : "false"
      end
    end
  end

  def current_main_tabs
    values = Configuration.maintabs.map(&:to_s) & ["notifications", "feed", "actions"]
    values.empty? ? ["notifications", "feed", "actions"] : values
  rescue StandardError
    ["notifications", "feed", "actions"]
  end

  def add_autoplay_page
    add_page(:autoplay, p_("WelcomeWizard", "Automatic audio playback")) do
      info = information_field(
        p_("WelcomeWizard", "Automatic audio playback"),
        p_("WelcomeWizard", "When you reach audio content, such as a voice message or an audio post, Elten can start playing it by itself. Some people find that natural, others prefer to press play themselves, and readers of transcriptions may want audio only when there is no text to fall back on. The list below shows the current behaviour; choose the one that suits you. Like everything in this wizard, the change is applied when you choose Finish, and it can be adjusted at any time under Tools, Program settings.")
      )
      values = ["always", "without_transcription", "never"]
      current = configuration_choice(:autoplay, values)
      list = ListBox.new(
        [p_("WelcomeWizard", "Always"), p_("WelcomeWizard", "Only when no transcription is available"), p_("WelcomeWizard", "Never")],
        header: p_("WelcomeWizard", "Automatically play audio content"),
        index: values.index(@state[:autoplay] || current) || 0
      )
      view([info, list]) do
        selected = values[list.index]
        selected == current ? @state.delete(:autoplay) : @state[:autoplay] = selected
      end
    end
  end

  def nvda_active?
    defined?(NVDA) && NVDA.check ? true : false
  rescue StandardError
    false
  end

  def add_nvda_page
    add_info_page(
      :nvda_addon,
      p_("WelcomeWizard", "Elten and NVDA"),
      p_("WelcomeWizard", "Elten has noticed that you are using the NVDA screen reader. A dedicated add-on lets the two work together more closely: it adds braille-display support, allows the text being read to be scrolled and brings reading shortcuts you know from NVDA, such as Insert+A to read text. Elten offers to install the add-on at startup and lets you know whenever it needs an update, so there is nothing you have to configure here.")
    )
  end

  def add_media_page
    modifier = begin
      main_modifier_name
    rescue StandardError
      "Ctrl"
    end
    text = p_("WelcomeWizard", "Voice messages, audio blog posts and other recordings all share the same player controls. The spacebar pauses and resumes playback, the Left and Right Arrows skip backwards or forwards, and the Up and Down Arrows adjust the playback volume. Holding %{modifier} with the Up and Down Arrows speeds a recording up or slows it down, and Backspace restores the default playback settings.") % { modifier: modifier }
    tips_hotkey = quick_action_hotkey_label(:tips)
    text += " " + p_("WelcomeWizard", "With a player focused, %{hotkey} reads the remaining playback shortcuts.") % { hotkey: tips_hotkey } if tips_hotkey != nil
    add_info_page(:media_playback, p_("WelcomeWizard", "Playing audio"), text)
  end

  def add_menus_page
    text = p_("WelcomeWizard", "Nearly everything in Elten starts from one of two menus. Press Alt on most screens to open the main menu; it leads to the community areas, your account, programs, settings and help. The context menu is different: it lists the actions available for whatever currently has focus, such as a message, a forum post or a list entry.")
    hotkey = quick_action_hotkey_label(:context)
    opening = if context_menu_key_available? && hotkey != nil
      p_("WelcomeWizard", "Open it with the context menu key on your keyboard, or with %{hotkey}, the shortcut of the Open context menu quick action.") % { hotkey: hotkey }
    elsif context_menu_key_available?
      p_("WelcomeWizard", "Open it with the context menu key on your keyboard.")
    elsif hotkey != nil
      p_("WelcomeWizard", "Open it with %{hotkey}, the shortcut of the Open context menu quick action.") % { hotkey: hotkey }
    end
    text += " " + opening if opening != nil
    text += " " + p_("WelcomeWizard", "The context menu can also be placed as the first item of the main menu, so both menus are available after pressing Alt. Use the checkbox below to choose whether it should appear there; you can change this later in the program settings. Whenever an option seems to be missing, check the context menu first; that is usually where it lives.")
    tips_hotkey = quick_action_hotkey_label(:tips)
    if tips_hotkey != nil
      text += " " + p_("WelcomeWizard", "One more shortcut worth remembering is %{hotkey}: wherever you are, it reads the additional keyboard shortcuts and hints available for the control that currently has focus.") % { hotkey: tips_hotkey }
    end
    current = Configuration.contextmenubar == true rescue true
    add_page(:menus, p_("WelcomeWizard", "Finding your way around")) do
      info = information_field(p_("WelcomeWizard", "Finding your way around"), text)
      check = CheckBox.new(
        p_("WelcomeWizard", "Display context menu in menu bar"),
        checked: @state.key?(:context_menu_bar) ? @state[:context_menu_bar] == "true" : current
      )
      view([info, check]) do
        selected = check.checked
        selected == current ? @state.delete(:context_menu_bar) : @state[:context_menu_bar] = selected ? "true" : "false"
      end
    end
  end

  def context_menu_key_available?
    ["windows", "linux"].include?(platform_os.to_s)
  end

  def quick_action_hotkey_label(symbol)
    return nil unless defined?(EltenAPI::QuickActions)

    action = EltenAPI::QuickActions.get.find { |item| item.action == symbol && item.key.to_i != 0 }
    return nil if action == nil

    function_key = action.key.to_i.abs
    return nil unless function_key.between?(1, 11)

    (action.key.to_i < 0 ? "Shift+" : "") + "F#{function_key}"
  rescue StandardError => error
    Log.warning("Welcome wizard quick action hotkey lookup failed for #{symbol}: #{error.class}: #{error.message}")
    nil
  end

  def invisible_interface_available?
    defined?(EltenAPI::InvisibleInterface) && (!EltenAPI::InvisibleInterface.respond_to?(:available?) || EltenAPI::InvisibleInterface.available?)
  end

  def add_invisible_interface_page
    add_page(:invisible_interface, p_("WelcomeWizard", "Invisible Interface")) do
      text = p_("WelcomeWizard", "Elten does not stop being useful when you switch to another program. The Invisible Interface is a set of global hotkeys that work across the whole system while Elten is running, so you can check new messages, browse the feed or control a conference without leaving the application you are in. Its content is arranged into cards, such as Messages, Feed and Conference options: hold the Elten modifier keys and use the arrow keys to move between cards and their items, press Enter to activate one, or add a command key, for example M to write a message or F to publish to the feed. The complete list is available under Help, List of Invisible Interface hotkeys.")
      current_modifiers = invisible_interface_current_modifiers
      if current_modifiers != ""
        text += "\n\n" + p_("WelcomeWizard", "The currently selected modifier combination is %{keys}. If you would rather use a different one, choose it below.") % { keys: current_modifiers }
      else
        text += "\n\n" + p_("WelcomeWizard", "If you would rather use one particular modifier combination, choose it below.")
      end
      info = information_field(p_("WelcomeWizard", "The Invisible Interface"), text)
      modifier_values = ["alt_ctrl_windows", "alt_shift_windows", "alt_ctrl_shift", "alt_ctrl", "alt_shift"]
      modifier_labels = [
        "ALT+CTRL+WINDOWS",
        "ALT+WINDOWS+SHIFT",
        "ALT+CTRL+SHIFT",
        "ALT+CTRL",
        "ALT+SHIFT"
      ]
      current_profile = Configuration.iimodifiers.to_s rescue ""
      no_change_option = !modifier_values.include?(current_profile)
      offset = no_change_option ? 1 : 0
      modifier_labels.unshift(p_("WelcomeWizard", "Do not change")) if no_change_option
      chosen = @state[:ii_modifiers] || (no_change_option ? nil : current_profile)
      chosen_index = chosen == nil ? nil : modifier_values.index(chosen)
      modifiers = ListBox.new(
        modifier_labels,
        header: p_("WelcomeWizard", "Modifier keys"),
        index: chosen_index == nil ? 0 : chosen_index + offset
      )
      view([info, modifiers]) do
        if no_change_option && modifiers.index == 0
          @state.delete(:ii_modifiers)
        else
          value = modifier_values[modifiers.index - offset]
          value == current_profile ? @state.delete(:ii_modifiers) : @state[:ii_modifiers] = value
        end
      end
    end
  end

  def invisible_interface_current_modifiers
    ConfigurationValues.invisible_interface_modifier_names(Configuration.iimodifiers).join("+")
  rescue StandardError
    ""
  end

  def configuration_choice(attribute, values)
    value = Configuration.public_send(attribute).to_s
    values.include?(value) ? value : values.first
  rescue StandardError
    values.first
  end

  def add_sounds_page
    add_page(:sounds, p_("WelcomeWizard", "Sounds and sound themes")) do
      info = information_field(
        p_("WelcomeWizard", "Sounds and sound themes"),
        p_("WelcomeWizard", "Elten deliberately speaks less than it could: much of what happens is signalled by short sounds instead, such as reaching the edge of a list, a new message arriving or someone joining a conference. You will pick most of them up naturally as you go. The Sounds guide lets you listen to each one together with its description and remains available from the Help menu.\n\nIf you would prefer Elten to sound different altogether, the community shares sound themes that replace the whole set. The sound themes manager lets you browse, download and select them and remains available under Sound themes in the Tools menu. Both screens can be opened directly with the buttons below.")
      )
      guide_button = Button.new(p_("WelcomeWizard", "Open the Sounds guide"))
      guide_button.on(:press) { insert_scene(Scene_Sounds.new) }
      themes_button = Button.new(p_("WelcomeWizard", "Manage sound themes"))
      themes_button.on(:press) { insert_scene(Scene_SoundThemes.new) }
      view([info, guide_button, themes_button])
    end
  end

  def add_upgrade_information_pages
    add_platforms_page
    add_info_page(
      :server_api,
      p_("WelcomeWizard", "A rewritten server"),
      p_("WelcomeWizard", "The rebuild does not stop at the client: Elten 3.0 talks to a completely rewritten server API. In practice this should mean noticeably smoother operation, especially when the network is under heavy load, and reliable service for many different clients and platforms working at the same time.")
    )
    add_info_page(
      :program_compatibility,
      p_("WelcomeWizard", "Programs from Elten 2.x"),
      p_("WelcomeWizard", "Programs written for Elten 2.x cannot run in Elten 3.0 and are not carried over during the upgrade. Compatible versions of the official programs are available from Programs management in the Programs menu, and later in this wizard you will be offered a few of the most useful ones. When an installed program has an update available, Elten 3.0 lets you know through a notification.")
    )
    add_info_page(
      :shared_notifications,
      p_("WelcomeWizard", "Notifications instead of What's New"),
      p_("WelcomeWizard", "The What's New screen from Elten 2.x is gone. In its place, Elten 3.0 receives notifications from the server, so the same items, and their read state, are shared by every supported client. New notifications appear in the Notifications section of the main window, and the complete list is kept under Notification history in the Community menu. To decide which kinds of account activity should notify you, open Manage my account and choose Notifications.")
    )
    add_info_page(
      :transcriptions,
      p_("WelcomeWizard", "Voice message transcriptions"),
      p_("WelcomeWizard", "Audio posts on the forum have long been accompanied by text transcriptions, and Elten 3.0 brings the same to private conversations: voice messages can now carry a transcription as well. A transcribed message can simply be read wherever listening would be inconvenient. You can also decide, in the program settings or later in this wizard, whether audio content should play automatically: always, never, or only when no transcription is available.")
    )
    add_info_page(
      :calendar,
      p_("WelcomeWizard", "Calendar"),
      p_("WelcomeWizard", "Elten 3.0 introduces a calendar, which you will find in the Community menu. It is a place to plan your events and keep track of what is coming up, for yourself and with others. Besides your personal calendar, you can create more, share a calendar with another user, or publish a language-specific public calendar for anyone to subscribe to, so it covers everything from private appointments to events for a whole community.")
    )
    add_info_page(
      :tasks,
      p_("WelcomeWizard", "Tasks"),
      p_("WelcomeWizard", "Alongside the calendar, Elten 3.0 also introduces tasks. A task can carry a description, a due date and a person responsible for completing it, and tasks are grouped into projects: besides your personal list, you can create a project and share it with other users, who receive an invitation and can then plan the work together with you. It suits anything from a simple to-do list to a project run jointly with friends.")
    )
    add_info_page(
      :activity_statistics,
      p_("WelcomeWizard", "Activity statistics"),
      p_("WelcomeWizard", "Until now, a summary of the past year's activity was sent out on the first day of each new year, and only some could read it: it reached Polish-speaking users who were active around that time, and it existed only in Polish. Elten 3.0 replaces that tradition with something better. Activity statistics are now available to everyone, for any year and at any time, under Manage my account. You can check how many forum posts, messages, blog posts and comments a year brought, how much time you spent in conferences and how often you signed in; each year can be compared with the one before, and rankings show, among other things, the forums you used most and the people you wrote with most often.")
    )
    add_info_page(
      :feed_audio,
      p_("WelcomeWizard", "Audio on the feed"),
      p_("WelcomeWizard", "Feed entries can now speak: publishing entries with audio is a premium option, described in detail under Premium packages in Manage my account. When composing an entry, the Attach audio button records a clip on the spot, and the recording travels with the text: entries carrying audio are marked on the feed and play straight from the list, with no need to open anything. To everyone who chooses to support Elten's development this way, thank you.")
    )
    add_info_page(
      :honors_revival,
      p_("WelcomeWizard", "Honors are back"),
      p_("WelcomeWizard", "Honors are back. Once among Elten's most cherished features, they quietly died a natural death some years ago; Elten 3.0 hereby restores them, and several entirely new honors arrive alongside the familiar ones. As before, they are awarded automagically as your activity earns them: the Veteran honor grows with every year spent on Elten, a devoted correspondent becomes a Courier, appearing in enough contact lists makes you a Celebrity, and being mentioned all over the forum and blogs earns the title of Talk of the Town. Most honors have levels to climb. The full collection, and everyone who holds each honor, can be browsed from the Users menu, and the honor you are proudest of can be set as your primary one: it is then announced in place of the word User whenever someone opens your visiting card.")
    )
    add_info_page(
      :account_refresh,
      p_("WelcomeWizard", "Now, over to you"),
      p_("WelcomeWizard", "That is the end of the news. From here on, the wizard becomes practical: the following pages will help you review and refresh what Elten knows about you, from your languages and profile details to account security, and adjust a few settings along the way. Wherever everything is already in order, the corresponding page simply will not appear, so this part may turn out pleasantly short.")
    )
    add_autoplay_page
    add_main_window_page
    add_feed_notifications_page if feed_tab_hidden?
    add_macos_page if platform_os.to_s == "osx"
  end

  def add_macos_page
    add_page(:macos_keyboard, p_("WelcomeWizard", "Keyboard behaviour on macOS")) do
      info = information_field(
        p_("WelcomeWizard", "Keyboard behaviour on macOS"),
        p_("WelcomeWizard", "Elten on macOS can follow either the native macOS conventions or the Ctrl-based Windows layout that older Elten versions used. The keyboard style decides which modifier keys Elten shortcuts expect: Command and Option, or Ctrl. Character navigation separately decides whether the Left and Right Arrow keys review text the macOS way or the Windows way. The lists below show the current settings; both can also be adjusted at any time under Tools, Program settings.")
      )
      scheme_values = ["default", "windows", "macos"]
      current_scheme = configuration_choice(:keyboardscheme, scheme_values)
      scheme = ListBox.new(
        [p_("WelcomeWizard", "Use the system default"), p_("WelcomeWizard", "Use the Windows keyboard style"), p_("WelcomeWizard", "Use the macOS keyboard style")],
        header: p_("WelcomeWizard", "Keyboard style"),
        index: scheme_values.index(@state[:keyboard_scheme] || current_scheme) || 0
      )
      navigation_values = ["default", "disabled", "enabled"]
      current_navigation = configuration_choice(:macoscharacternavigation, navigation_values)
      navigation = ListBox.new(
        [p_("WelcomeWizard", "Use the system default"), p_("WelcomeWizard", "Use Windows-style character navigation"), p_("WelcomeWizard", "Use macOS-style character navigation")],
        header: p_("WelcomeWizard", "Character navigation"),
        index: navigation_values.index(@state[:character_navigation] || current_navigation) || 0
      )
      view([info, scheme, navigation]) do
        selected_scheme = scheme_values[scheme.index]
        selected_scheme == current_scheme ? @state.delete(:keyboard_scheme) : @state[:keyboard_scheme] = selected_scheme
        selected_navigation = navigation_values[navigation.index]
        selected_navigation == current_navigation ? @state.delete(:character_navigation) : @state[:character_navigation] = selected_navigation
      end
    end
  end

  def add_language_pages
    current = current_main_language
    interface = interface_language
    if show_when(current == "" || current != interface)
      add_page(:main_language, p_("WelcomeWizard", "Your main language")) do
        configuration_known = data_available?(:account_configuration)
        current_text = if !configuration_known
          p_("WelcomeWizard", "Elten could not load your current main-language setting.")
        elsif current == ""
          p_("WelcomeWizard", "Your account does not have a main language set.")
        else
          p_("WelcomeWizard", "Your current main language is %{language}.") % { language: language_label(current) }
        end
        reason = if !configuration_known
          p_("WelcomeWizard", "Choose a language only if you want to replace the setting that could not be read. Otherwise, select Do not change and review it later in your account settings.")
        elsif current == ""
          p_("WelcomeWizard", "Your main language tells Elten which language community you belong to: it is used to recommend forum groups, deliver language-specific notifications and match you with content you can read. It does not change the language of the Elten interface.")
        elsif current == interface
          p_("WelcomeWizard", "It matches the language of the interface, which is usually exactly right. Change it only if you prefer community content in another language.")
        else
          p_("WelcomeWizard", "The Elten interface is currently set to %{language}. Using different languages for the two is perfectly fine; this page simply asks you to confirm that the difference is intentional.") % { language: language_label(interface) }
        end
        info = information_field(p_("WelcomeWizard", "Your main language"), "#{current_text}\n\n#{reason}")
        ordered = [interface] + (language_codes - [interface])
        no_change_option = !configuration_known || current == ""
        offset = no_change_option ? 1 : 0
        options = ordered.map { |code| language_label(code) }
        options.unshift(p_("WelcomeWizard", "Do not change")) if no_change_option
        chosen = @state[:main_language] || current
        chosen_index = ordered.index(chosen)
        index = chosen_index == nil ? 0 : chosen_index + offset
        list = ListBox.new(options, header: p_("WelcomeWizard", "Main language"), index: index)
        view([info, list]) do
          if no_change_option && list.index == 0
            @state.delete(:main_language)
          else
            selected = ordered[list.index - offset]
            selected == current ? @state.delete(:main_language) : @state[:main_language] = selected
          end
          synchronize_introduction_page
        end
      end
    end

    if show_when(current_languages.empty?)
      add_page(:additional_languages, p_("WelcomeWizard", "Other languages")) do
        languages = current_languages
        info_text = if !data_available?(:account_configuration)
          p_("WelcomeWizard", "Elten could not load your other language settings. Any languages selected here will replace the unread setting. Leave every item unticked to make no change and review it later in your account settings.")
        elsif languages.empty?
          p_("WelcomeWizard", "If you are comfortable in languages besides your main one, you can list them here, and Elten will include community content in those languages as well. This is entirely optional; leave every item unticked to make no change.")
        else
          p_("WelcomeWizard", "The other languages currently stored on your account are selected below. Elten uses this list when including language-specific community content. Leave the selection as it is to make no change.")
        end
        info = information_field(
          p_("WelcomeWizard", "Other languages"),
          info_text
        )
        codes = language_codes
        list = ListBox.new(codes.map { |code| language_label(code) }, header: p_("WelcomeWizard", "Additional languages"), flags: ListBox::Flags::MultiSelection)
        selected = @state[:languages] || languages
        selected.each do |code|
          index = codes.index(code)
          list.selected[index] = true if index != nil
        end
        view([info, list]) do
          values = list.multiselections.map { |index| codes[index] }.compact
          store_selection(:languages, values, languages)
          synchronize_introduction_page
        end
      end
    end
  end

  def add_profile_pages
    if show_when(current_full_name == "")
      add_page(:full_name, p_("WelcomeWizard", "Public name")) do
        initial = current_full_name
        info_text = if !data_available?(:account_configuration, :profile)
          p_("WelcomeWizard", "Elten could not load the public name currently stored on your profile. Enter a name only if you want to replace it. Leave the field empty to make no change and review your profile later.")
        elsif initial == ""
          p_("WelcomeWizard", "Alongside your username, your profile can display a public name. Many people use their real name, but any name the community knows you by will do. It is optional and does not change the name you sign in with. Leave the field empty if you would rather not display one.")
        else
          p_("WelcomeWizard", "The name below is displayed publicly on your profile alongside your username. Edit it if it is out of date, clear it to remove it, or leave it as it is.")
        end
        info = information_field(p_("WelcomeWizard", "Public name"), info_text)
        edit = EditBox.new(p_("WelcomeWizard", "Full name or preferred public name"), text: @state.key?(:full_name) ? @state[:full_name] : initial)
        view([info, edit]) { store_changed_text(:full_name, edit.text, initial) }
      end
    end

    if show_when(current_gender == -1)
      add_page(:gender, p_("WelcomeWizard", "Gender")) do
        initial = current_gender
        shown = gender_label(initial)
        text = if data_available?(:account_configuration, :profile)
          p_("WelcomeWizard", "Gender is an optional profile field. Besides appearing on your profile, it lets Elten choose the correct grammatical forms when referring to you in languages that need them. Your current setting is %{gender}. Choose the appropriate value, or Do not specify if you would rather not share it.") % { gender: shown }
        else
          p_("WelcomeWizard", "Elten could not load your current gender setting. Choose Female or Male only if you want to set it now. Leave Do not specify selected to make no change and review your profile later.")
        end
        info = information_field(
          p_("WelcomeWizard", "Gender"),
          text
        )
        options = [p_("WelcomeWizard", "Do not specify"), _("Female"), _("Male")]
        selected = @state.key?(:gender) ? @state[:gender].to_i : initial
        index = selected.between?(-1, 1) ? selected + 1 : 0
        list = ListBox.new(options, header: p_("WelcomeWizard", "Gender"), index: index)
        view([info, list]) do
          value = list.index - 1
          value == initial ? @state.delete(:gender) : @state[:gender] = value
        end
      end
    end

    birth = current_birthdate
    if show_when(!birthdate_in_expected_range?(birth))
      add_page(:birthdate, p_("WelcomeWizard", "Date of birth")) do
        birthdate_known = data_available?(:account_configuration, :profile)
        initial_text = if !birthdate_known
          p_("WelcomeWizard", "could not be checked")
        elsif birthdate_complete?(birth)
          format_birthdate(birth)
        else
          p_("WelcomeWizard", "not provided")
        end
        warning = if !birthdate_known
          p_("WelcomeWizard", "Enter a date only if you want to replace the value that could not be read. Otherwise, leave it unchanged and review your profile later.")
        elsif birthdate_in_expected_range?(birth)
          p_("WelcomeWizard", "Change this date only if it is incorrect.")
        elsif birthdate_complete?(birth)
          p_("WelcomeWizard", "This date lies outside the range the wizard expects, which is 1900 to 2013. Please check that it is correct before continuing.")
        else
          p_("WelcomeWizard", "A date of birth is optional. If you provide one, Elten will remind your contacts when your birthday approaches.")
        end
        info = information_field(
          p_("WelcomeWizard", "Date of birth"),
          (p_("WelcomeWizard", "The current value is %{date}.") % { date: initial_text }) + "\n\n" + warning
        )
        staged = @state[:birthdate]
        action = ListBox.new(
          [p_("WelcomeWizard", "Leave unchanged"), p_("WelcomeWizard", "Enter a different date")],
          header: p_("WelcomeWizard", "Date of birth action"),
          index: staged == nil ? 0 : 1
        )
        years = (1900..Time.now.year).to_a
        year_value = staged == nil ? birth[:year] : staged[:year]
        month_value = staged == nil ? birth[:month] : staged[:month]
        day_value = staged == nil ? birth[:day] : staged[:day]
        year = ListBox.new(years.map(&:to_s), header: p_("WelcomeWizard", "Year"), index: years.index(year_value.to_i) || 0)
        month = ListBox.new(month_names, header: p_("WelcomeWizard", "Month"), index: [[month_value.to_i - 1, 0].max, 11].min)
        day = ListBox.new((1..31).map(&:to_s), header: p_("WelcomeWizard", "Day"), index: [[day_value.to_i - 1, 0].max, 30].min)
        view([info, action, year, month, day]) do
          if action.index == 0
            @state.delete(:birthdate)
          else
            value = { year: years[year.index], month: month.index + 1, day: day.index + 1 }
            if valid_calendar_birthdate?(value)
              value == birth ? @state.delete(:birthdate) : @state[:birthdate] = value
            else
              alert(p_("WelcomeWizard", "The selected day does not exist in that month. Choose a valid date."))
              false
            end
          end
        end
      end
    end

    add_page(:visiting_card, p_("WelcomeWizard", "Your visiting card")) do
      initial = current_visiting_card
      info_text = if !data_available?(:account_configuration, :visiting_card)
        p_("WelcomeWizard", "Elten could not load your current visiting card. Enter text only if you want to replace it. Leave the field empty to make no change and review your profile later.")
      elsif initial == ""
        p_("WelcomeWizard", "Your visiting card is a short introduction shown to anyone who opens your profile. A few sentences about your interests, the languages you speak or the conversations you enjoy will help others decide to get in touch. Write only what you are happy for every user to read; the field is optional and you can change it at any time.")
      else
        p_("WelcomeWizard", "The text below is your current visiting card, shown publicly on your profile. Read it again with fresh eyes: if it no longer describes you, this is a good moment to bring it up to date. You can also clear it to remove it, or leave it as it is.")
      end
      info = information_field(p_("WelcomeWizard", "Your visiting card"), info_text)
      edit = EditBox.new(p_("WelcomeWizard", "Visiting card"), type: EditBox::Flags::MultiLine, text: @state.key?(:visiting_card) ? @state[:visiting_card] : initial)
      view([info, edit]) { store_changed_text(:visiting_card, edit.text, initial, strip: false) }
    end

    if show_when(current_status == "" || current_signature == "")
      add_page(:status_signature, p_("WelcomeWizard", "Status and signature")) do
        initial_status = current_status
        initial_signature = current_signature
        info_text = if !data_available?(:account_configuration)
          p_("WelcomeWizard", "Elten could not load your current status and signature. Enter text only if you want to replace them. Leave both fields empty to make no change and review them later in your account settings.")
        else
          p_("WelcomeWizard", "Two more short lines can accompany you around Elten, and both are optional. Your status is displayed after your name on user lists, such as the contact list; a favourite quote or a word about your mood are common choices. Your signature is placed below every post you write on the forum. Any text already stored on your account is shown below; leave a field as it is to make no change.")
        end
        info = information_field(p_("WelcomeWizard", "Status and signature"), info_text)
        status_edit = EditBox.new(p_("WelcomeWizard", "Status"), text: @state.key?(:status) ? @state[:status] : initial_status)
        signature_edit = EditBox.new(p_("WelcomeWizard", "Signature"), text: @state.key?(:signature) ? @state[:signature] : initial_signature)
        view([info, status_edit, signature_edit]) do
          store_changed_text(:status, status_edit.text, initial_status)
          store_changed_text(:signature, signature_edit.text, initial_signature)
        end
      end
    end
  end

  def current_status
    config_value("status").to_s
  end

  def current_signature
    config_value("signature").to_s
  end

  def add_security_page
    return unless show_when(@authentication_state == 0)

    add_page(:two_factor_authentication, p_("WelcomeWizard", "Two-factor authentication")) do
      enabled = @authentication_state.to_i == 1
      text = if @authentication_state == nil
        p_("WelcomeWizard", "Elten could not check whether two-factor authentication is enabled. No action is offered here; review it later under Manage my account, Manage Two-Factor authentication.")
      elsif enabled
        p_("WelcomeWizard", "Two-factor authentication is already enabled on this account. There is nothing to change on this page.")
      else
        p_("WelcomeWizard", "A strong password is a good start, but two-factor authentication protects your account even if that password ever leaks. When it is enabled and a sign-in needs confirming, Elten sends a code to your telephone by text message. The button below opens the setup screen, where Elten will ask for your password and telephone number; changes made there take effect immediately and are independent of this wizard.")
      end
      info = information_field(p_("WelcomeWizard", "Two-factor authentication"), text)
      if enabled || @authentication_state == nil
        view([info])
      else
        button = Button.new(p_("WelcomeWizard", "Set up two-factor authentication"))
        button.on(:press) { insert_scene(Scene_Authentication.new) }
        view([info, button])
      end
    end
  end

  def add_community_pages
    if @first_run
      add_info_page(
        :private_messages,
        p_("WelcomeWizard", "Private messages"),
        p_("WelcomeWizard", "Private messages are direct conversations between you and one or more other users; nobody outside a conversation can read it. A conversation can be a simple exchange with one person or a named group with several members. Messages can carry attachments and be recorded as audio messages, which may include a transcription. If a conversation becomes too lively, you can mute it for a while, and the ones you care about most can be added to Quick Actions.")
      )
      add_info_page(
        :forum,
        p_("WelcomeWizard", "Forum"),
        p_("WelcomeWizard", "The forum is where public discussions happen, and it has a simple hierarchy: groups contain forums, forums contain threads, and threads contain the posts themselves. Groups are thematic: each is devoted to something, from broad general groups serving a whole language community to smaller ones about music, technology, cookery or anything else their members care about. Recommended groups are the recognised general starting points for particular languages; all the others are created and run by users, and you can start your own around any subject at any time.\n\nJoining a group makes you a member and lets you take part in its discussions. Following is a separate idea: follow a forum to be notified about its new threads and posts, or follow a single thread to hear only about its replies. The context menu always contains options to start or stop following.")
      )
    end
    add_forum_pages
    if @first_run
      add_info_page(
        :blogs,
        p_("WelcomeWizard", "Blogs"),
        p_("WelcomeWizard", "Blogs are for longer content: written posts, audio recordings or both, with comments underneath. Within Elten you write, read, comment and follow them without leaving the program, but under the surface every blog is a genuine WordPress site. WordPress is the engine behind a large share of the world's websites, and that opens possibilities reaching well beyond Elten: your blog has its own address and can be read in any web browser, you can shape its appearance with any of the countless WordPress themes, publish under your own brand, and even run the blog on a separate domain of your own. For anything the built-in tools do not cover, the full WordPress administration panel is at your disposal. You can create a blog of your own whenever you feel you have something to say.")
      )
    end
    add_blog_pages
    if @first_run
      add_info_page(
        :feed,
        p_("WelcomeWizard", "Feed"),
        p_("WelcomeWizard", "The feed is Elten's space for the small things: short status updates of no more than a few sentences. Your Feed tab collects the entries of the people you follow, and following someone's feed is independent of having them in your contacts. It is the easiest way to stay in touch day to day without writing a whole blog post.")
      )
    end
    add_feed_pages
    if @first_run
      add_info_page(
        :conferences,
        p_("WelcomeWizard", "Conferences"),
        p_("WelcomeWizard", "Conferences are live audio channels where you can talk with others, listen or stream sound, and every channel also has its own text chat. Sound in a channel is positional: each participant occupies a place in the channel space, you move around it with the arrow keys, and you can whisper something to a single person standing nearby. You can also stream an audio file or your whole sound card to a channel, which makes listening to music or watching a film together easy. Channels come in many forms; some are open to everyone, while others are protected by a password or a waiting room. And when you would rather talk to one particular person, simply call them: the invitation can be accepted or declined, and missed calls are kept in the call history. Creating your own channel takes a moment, and a channel you like can be followed or added to Quick Actions.")
      )
      add_info_page(
        :other_areas,
        p_("WelcomeWizard", "And there is more"),
        p_("WelcomeWizard", "The areas described so far are the busiest, but not the only ones. Elten also offers polls, where you can put structured questions to the community and study the answers; notes, where you can keep texts for yourself or share one with another user to work on together; and a calendar for your events, which can also be shared with other users. In the Community menu you will additionally find your contacts, a user search, a list of who is currently online and more. Take your time; none of this needs to be learnt at once.")
      )
    end
  end

  def add_forum_pages
    if show_when(@forum_structure != nil && !joined_recommended_group?)
      add_page(:forum_groups, p_("WelcomeWizard", "Recommended forum groups")) do
        candidates, fallback = recommended_group_candidates
        already_joined = joined_recommended_group?
        info_text = if @forum_structure == nil
          p_("WelcomeWizard", "Elten could not load the forum groups available to your account. Nothing can be selected on this page; open the Forum later to review groups.")
        elsif already_joined
          p_("WelcomeWizard", "You already belong to at least one recommended group. Listed below are other recommended groups matching your languages that you have not joined. Joining a group does not automatically follow its forums or threads. Leave every item unticked to make no change.")
        else
          p_("WelcomeWizard", "These recommended groups match your languages, and you are not yet a member of any of them. Tick the communities you would like to join; Elten will join them when you finish the wizard. Joining a group does not automatically follow its forums or threads, so you remain in charge of what you hear about. Nothing is ticked by default.")
        end
        if fallback && !already_joined
          info_text += "\n\n" + p_("WelcomeWizard", "No recommended group exists yet for your preferred language, so an English-language group is offered instead. If your language community needs its own recommended group, the Council of Elders will be glad to hear from you.")
        end
        info = information_field(p_("WelcomeWizard", "Recommended forum groups"), info_text)
        if candidates.empty?
          availability = if @forum_structure == nil
            p_("WelcomeWizard", "The available groups could not be loaded.")
          elsif already_joined
            p_("WelcomeWizard", "There are no other matching recommended groups available to join.")
          else
            p_("WelcomeWizard", "No matching recommended group is available. You can browse all public and open groups from the Forum later.")
          end
          view([info, information_field(p_("WelcomeWizard", "Availability"), availability)])
        else
          labels = candidates.map do |group|
            description = group.description.to_s.strip
            language = language_label(normalise_language(group.lang))
            description == "" ? "#{group.name} — #{language}" : "#{group.name} — #{language}: #{description}"
          end
          list = ListBox.new(labels, header: p_("WelcomeWizard", "Recommended groups"), flags: ListBox::Flags::MultiSelection)
          selected = @state[:join_group_ids].to_a
          candidates.each_with_index { |group, index| list.selected[index] = true if selected.include?(group.id.to_i) }
          view([info, list]) do
            values = list.multiselections.map { |index| candidates[index]&.id.to_i }.select { |id| id > 0 }
            store_selection(:join_group_ids, values)
          end
        end
      end
    end

    if show_when(introduction_needed?)
      add_page(:forum_introduction, p_("WelcomeWizard", "Post an introduction")) do
        group = preferred_introduction_group
        if group == nil
          view([information_field(p_("WelcomeWizard", "Post an introduction"), p_("WelcomeWizard", "No introductions thread could be selected for your languages. Nothing will be posted from this page; you can choose a suitable forum yourself later."))])
        else
          thread = @forum_structure.threads.to_a.find { |item| item.id.to_i == group.thread_introductions.to_i }
          thread_name = thread == nil ? p_("WelcomeWizard", "the introductions thread") : thread.name
          if introduction_posted?(group)
            text = p_("WelcomeWizard", "You have already posted in %{thread}, the introductions thread of %{group}.") % { thread: thread_name, group: group.name }
            view([information_field(p_("WelcomeWizard", "Post an introduction"), text)])
          else
            introduction_text = if @first_run
              p_("WelcomeWizard", "New members often say hello in %{thread}, the introductions thread of %{group}. If you would like to introduce yourself, write a few words below: where you are from, what brought you here, whatever you would tell a new acquaintance. The post will be published when you finish the wizard; leave the field empty to skip it.") % { thread: thread_name, group: group.name }
            else
              p_("WelcomeWizard", "%{thread} is the introductions thread of %{group}. If you have been away for a while, or suspect that newer members do not know you, this is a good place for a fresh hello. The text will be published when you finish the wizard; leave the field empty to make no post.") % { thread: thread_name, group: group.name }
            end
            info = information_field(
              p_("WelcomeWizard", "Post an introduction"),
              introduction_text
            )
            edit = EditBox.new(p_("WelcomeWizard", "Your introduction"), type: EditBox::Flags::MultiLine, text: @state[:introduction_text].to_s)
            view([info, edit]) do
              store_changed_text(:introduction_text, edit.text, "")
            end
          end
        end
      end
    end
  end

  def add_blog_pages
    if show_when(!@contacts.empty? && !@blog_suggestions.empty?)
      add_page(:follow_blogs, p_("WelcomeWizard", "Blogs from your contacts")) do
        suggestions = @blog_suggestions
        info = information_field(
          p_("WelcomeWizard", "Blogs from your contacts"),
          p_("WelcomeWizard", "Some of your contacts write blogs that you are not following yet. Following a blog simply means being notified whenever it publishes something new. The list below contains your contacts' blogs that have been active within the past year; tick the ones you would like to follow. Nothing is ticked by default.")
        )
        if suggestions.empty?
          availability = if @preload_errors.key?(:contacts)
            p_("WelcomeWizard", "Your contacts could not be checked.")
          elsif @preload_errors.key?(:contact_blogs)
            p_("WelcomeWizard", "Recent blogs belonging to your contacts could not be checked.")
          elsif @contacts.empty?
            p_("WelcomeWizard", "There are no contacts from whom Elten can suggest a blog.")
          else
            p_("WelcomeWizard", "None of your contacts has an active blog that you are not already following.")
          end
          view([info, information_field(p_("WelcomeWizard", "Availability"), availability)])
        else
          labels = suggestions.map { |item| "#{item.blog.name} — #{item.user}" }
          list = ListBox.new(labels, header: p_("WelcomeWizard", "Blogs"), flags: ListBox::Flags::MultiSelection)
          selected = @state[:follow_blog_ids].to_a
          suggestions.each_with_index { |item, index| list.selected[index] = true if selected.include?(item.blog.id.to_s) }
          view([info, list]) do
            values = list.multiselections.map { |index| suggestions[index]&.blog&.id.to_s }.reject(&:empty?)
            store_selection(:follow_blog_ids, values)
          end
        end
      end
    end
  end

  def add_feed_pages
    if show_when(!@contacts.empty? && !@feed_suggestions.empty?)
      add_page(:follow_feeds, p_("WelcomeWizard", "People to follow on the feed")) do
        users = @feed_suggestions
        info = information_field(
          p_("WelcomeWizard", "People to follow on the feed"),
          p_("WelcomeWizard", "The feed is where people post short status updates, separate from their blogs. Listed below are contacts whose feeds you do not follow yet; tick anyone whose updates you would like to see on your Feed tab. Following someone's feed does not add or remove a contact. Leave every item unticked to make no change.")
        )
        if users.empty?
          availability = if @preload_errors.key?(:contacts)
            p_("WelcomeWizard", "Your contacts could not be checked.")
          elsif @preload_errors.key?(:feed_follows)
            p_("WelcomeWizard", "The people you already follow on the feed could not be checked.")
          elsif @contacts.empty?
            p_("WelcomeWizard", "There are no contacts to suggest.")
          else
            p_("WelcomeWizard", "You already follow all of your contacts on the feed.")
          end
          view([info, information_field(p_("WelcomeWizard", "Availability"), availability)])
        else
          list = ListBox.new(users, header: p_("WelcomeWizard", "Contacts"), flags: ListBox::Flags::MultiSelection)
          selected = @state[:follow_feed_users].to_a
          users.each_with_index { |user, index| list.selected[index] = true if selected.include?(user) }
          view([info, list]) do
            values = list.multiselections.map { |index| users[index] }.compact
            store_selection(:follow_feed_users, values)
          end
        end
      end
    end

    feed_page_needed = @own_feed.empty? || latest_feed_time <= Time.now.to_i - 365 * 24 * 60 * 60
    if show_when(!@preload_errors.key?(:own_feed) && feed_page_needed)
      add_page(:feed_greeting, p_("WelcomeWizard", "Post to the feed")) do
        prompt = if @preload_errors.key?(:own_feed)
          p_("WelcomeWizard", "Elten could not load your feed history, so it cannot determine whether a new entry would be useful. Posting is disabled on this page; open the Feed later if you want to write an update.")
        elsif @own_feed.empty?
          p_("WelcomeWizard", "You have not posted anything to the feed yet. If you would like to let others know you have arrived, write a short first entry below; a sentence or two is plenty.")
        elsif feed_page_needed
          p_("WelcomeWizard", "Your most recent feed entry is more than a year old. If you would like your followers to know you are back, write a short update below.")
        else
          p_("WelcomeWizard", "You have posted on the feed within the past year. No new introduction is needed, but you may still write an update if you want to.")
        end
        if !@preload_errors.key?(:own_feed)
          prompt += " " + p_("WelcomeWizard", "It will be published when you finish the wizard; leave the field empty to make no post.")
        end
        info = information_field(p_("WelcomeWizard", "Post to the feed"), prompt)
        if @preload_errors.key?(:own_feed)
          view([info])
        else
          edit = EditBox.new(p_("WelcomeWizard", "Feed entry"), type: EditBox::Flags::MultiLine, text: @state[:feed_greeting].to_s, max_length: 300)
          view([info, edit]) do
            store_changed_text(:feed_greeting, edit.text, "")
          end
        end
      end
    end
  end

  def add_app_page(kind)
    app = available_app(kind)
    installed = @installed_app_ids.include?(APP_IDS[kind].to_s.downcase)
    return unless @force_all || (app != nil && !installed)

    copy = app_copy(kind)
    add_page("app_#{kind}".to_sym, copy[:title]) do
      status = if installed
        p_("WelcomeWizard", "This program is already installed. The wizard will not reinstall it.")
      elsif app == nil
        p_("WelcomeWizard", "The server is not currently offering this program for your operating system. Nothing can be selected here; check Programs management again later.")
      else
        p_("WelcomeWizard", "Available version: %{version}. Author: %{author}. Download size: %{size}.") % {
          version: app.version.to_s,
          author: app.author.to_s,
          size: human_file_size(app.size)
        }
      end
      info = information_field(copy[:title], copy[:text] + "\n\n" + status)
      if installed || app == nil
        view([info])
      else
        check = CheckBox.new(
          p_("WelcomeWizard", "Install %{program} when I finish") % { program: copy[:name] },
          checked: @state.dig(:install_apps, kind) == true
        )
        view([info, check]) do
          @state[:install_apps] ||= {}
          if check.checked
            @state[:install_apps][kind] = true
          else
            @state[:install_apps].delete(kind)
            @state.delete(:install_apps) if @state[:install_apps].empty?
          end
        end
      end
    end
  end

  def app_copy(kind)
    case kind
    when :ffmpeg
      {
        title: p_("WelcomeWizard", "FFmpeg encoders"),
        name: p_("WelcomeWizard", "FFmpeg encoders"),
        text: p_("WelcomeWizard", "FFmpeg encoders extend Elten's recording and media-conversion tools with additional output formats, including MP3, AAC, FLAC, WMA, AVI, MP4, MOV and MPG. Install them if you expect to save recordings or conversions in any of these formats. The program works in the background and adds no menu items of its own.")
      }
    when :file_manager
      {
        title: p_("WelcomeWizard", "File Manager"),
        name: p_("WelcomeWizard", "File Manager"),
        text: p_("WelcomeWizard", "File Manager adds a file browser to the Programs menu, driven with the familiar Elten controls. It can open and preview supported files, play audio, make recordings, rename and copy items, and create or extract ZIP archives. Install it if you would like to manage local files without leaving Elten.")
      }
    when :mcp
      {
        title: p_("WelcomeWizard", "MCP integration for advanced users"),
        name: p_("WelcomeWizard", "MCP"),
        text: p_("WelcomeWizard", "MCP lets you connect Elten with AI assistants and other automation tools. Once set up, such a tool can, with your permission, use selected Elten features on your behalf, bringing your community into the things you already do with an AI assistant. You stay in control throughout: everything works only on this computer, the integration is disabled after installation until you enable it in Program settings, and each connected tool must be granted its permissions explicitly. Setting it up takes a little technical confidence, so treat it as a feature for more advanced users.")
      }
    else
      raise ArgumentError, "Unknown welcome wizard program: #{kind.inspect}"
    end
  end

  def add_open_source_page
    add_action_page(
      :open_source,
      p_("WelcomeWizard", "Source code and contributions"),
      p_("WelcomeWizard", "Elten is free, open-source software released under the GNU General Public License, version 3, and its complete source code and development history are public on GitHub. Contributions are genuinely welcome: well-scoped features, bug fixes and translations are all reviewed and merged when ready. If you ever decide to contribute, thank you in advance for the time and care you put into it."),
      p_("WelcomeWizard", "Open the Elten repository")
    ) do
      platform_open_url(SOURCE_URL)
    end
  end

  def add_support_page
    add_page(:support, p_("WelcomeWizard", "Supporting Elten")) do
      intro = information_field(
        p_("WelcomeWizard", "Supporting Elten"),
        p_("WelcomeWizard", "Elten is free to use, but keeping it running is not free: servers, domains and infrastructure all carry real costs, borne by the Prowadnica Foundation, which supports the project's development. If Elten is valuable to you, there are two easy ways to help. Premium packages add optional conveniences to your account, and the proceeds go towards the upkeep of the service; you will find them under Manage my account. You can also simply make a donation towards Elten's development.")
      )
      transfer_field = if @donation_transfer.is_a?(Hash)
        details = [
          [p_("WelcomeWizard", "Account holder"), "holder"],
          [p_("WelcomeWizard", "Address"), "address"],
          [p_("WelcomeWizard", "Account number (Poland)"), "placcount"],
          [p_("WelcomeWizard", "IBAN"), "iban"],
          [p_("WelcomeWizard", "BIC/SWIFT"), "swift"],
          [p_("WelcomeWizard", "Bank address"), "bankaddress"],
          [p_("WelcomeWizard", "Sort code"), "sortcode"]
        ].filter_map do |label, key|
          value = @donation_transfer[key].to_s.strip
          "#{label}: #{value}" unless value.empty?
        end
        text = p_("WelcomeWizard", "A donation can be made by bank transfer using the details below. Mentioning Elten in the transfer title helps the foundation account for the donation correctly.")
        text += "\n\n" + details.join("\n") unless details.empty?
        information_field(p_("WelcomeWizard", "Donation by bank transfer"), text)
      else
        information_field(
          p_("WelcomeWizard", "Donation by bank transfer"),
          p_("WelcomeWizard", "The transfer details could not be loaded. You will also find them in the Premium packages section under Manage my account.")
        )
      end
      view([intro, transfer_field])
    end
  end

  def add_github_star_page
    add_action_page(
      :github_star,
      p_("WelcomeWizard", "A star on GitHub"),
      p_("WelcomeWizard", "If you have a GitHub account and want to show that this project matters to you, we would be grateful for a star on the Elten repository. It costs nothing and takes a moment, yet it makes the project more visible. The button below opens the repository; the Star button is near the top of the page."),
      p_("WelcomeWizard", "Open the Elten repository on GitHub")
    ) do
      platform_open_url(SOURCE_URL)
    end
  end

  def add_thanks_page
    add_info_page(
      :thanks,
      p_("WelcomeWizard", "Contributors and testers"),
      p_("WelcomeWizard", "Elten 3.0 exists thanks to the people around it: those who contributed, tested the development builds, reported reproducible problems, proposed improvements and patiently helped other users through the changes. To every one of them, thank you.")
    )
  end

  def add_summary_page
    add_page(:summary, p_("WelcomeWizard", "Review and finish")) do
      view([information_field(p_("WelcomeWizard", "Review and finish"), summary_text)])
    end
  end


  def load_wizard_data
    @preload_errors = {}
    @account_config = wizard_fetch(:account_configuration, {}) { EltenLink::Accounts.config(elten_link) }
    unless @account_config.is_a?(Hash) && !@account_config.empty?
      @account_config = {}
      @preload_errors[:account_configuration] ||= "No account configuration was returned"
    end

    @profile = wizard_fetch(:profile, nil) { EltenLink::Profiles.profile(elten_link, Session.name) }
    @preload_errors[:profile] ||= "No profile was returned" if @profile == nil
    @visiting_card = wizard_fetch(:visiting_card, nil) { EltenLink::Profiles.visiting_card(elten_link, Session.name) }
    @authentication_state = wizard_fetch(:two_factor_authentication, nil) { EltenLink::Authentication.state(elten_link) }
    @forum_structure = wizard_fetch(:forum, nil) { EltenLink::Forum.structure(elten_link) }
    load_introduction_posting_statuses
    @contacts = wizard_fetch(:contacts, []) { EltenLink::Contacts.list(elten_link) }
    load_contact_suggestions
    @own_feed = wizard_fetch(:own_feed, []) { EltenLink::Feeds.show(elten_link, Session.name) }
    @donation_transfer = wizard_fetch(:payment_methods, nil) do
      EltenLink::Payments.methods(elten_link, currency: donation_currency, language: Configuration.language).find do |method|
        method.is_a?(Hash) && method["id"] == "transfer" && method["type"] == "transfer"
      end
    end
    load_program_data
  end

  def donation_currency
    currency = LocalConfig["PremiumPackagesCurrency", "unset", type: :string] rescue "unset"
    ["PLN", "EUR", "USD", "GBP"].include?(currency) ? currency : "PLN"
  end

  def load_contact_suggestions
    @blog_suggestions = []
    @feed_suggestions = []
    return if @contacts.empty?

    blogs = wizard_fetch(:contact_blogs, nil) { EltenLink::Blog.list(elten_link) }
    build_blog_suggestions(blogs) if blogs != nil

    followed = wizard_fetch(:feed_follows, nil) do
      EltenLink::Feeds.followed_users(elten_link).to_h { |user| [user.to_s.downcase, true] }
    end
    @feed_suggestions = @contacts.reject { |user| followed[user.to_s.downcase] } if followed != nil
  end

  def build_blog_suggestions(blogs)
    contacts = @contacts.to_h { |user| [user.to_s.downcase, user.to_s] }
    cutoff = Time.now.to_i - 365 * 24 * 60 * 60
    @blog_suggestions = blogs.filter_map do |blog|
      next if blog.followed || blog.lastpost.to_i < cutoff

      owners = blog.owners.to_a.map(&:to_s)
      owners << blog.library_user.to_s if blog.respond_to?(:library_user) && blog.library_user.to_s != ""
      matching = owners.filter_map { |owner| contacts[owner.downcase] }.uniq
      BlogSuggestion.new(user: matching.join(", "), blog: blog) unless matching.empty?
    end
    @blog_suggestions.sort_by! { |item| [-item.blog.lastpost.to_i, item.blog.name.to_s.downcase] }
    @blog_suggestions.uniq! { |item| item.blog.id.to_s }
  end

  def load_program_data
    @remote_apps = wizard_fetch(:programs, []) { EltenLink::Apps.list(elten_link, os: @program_platform_target) }
    entries = defined?(Programs) ? Programs.local_entries : []
    @installed_app_ids = entries.filter_map do |entry|
      id = entry.respond_to?(:id) ? entry.id.to_s.downcase : ""
      id unless id.empty?
    end
  rescue StandardError => error
    Log.warning("Welcome wizard installed programs check failed: #{error.class}: #{error.message}")
    @preload_errors[:installed_programs] = error.message.to_s
    @installed_app_ids = []
  end

  def wizard_fetch(key, default)
    yield
  rescue StandardError => error
    Log.warning("Welcome wizard preload failed for #{key}: #{error.class}: #{error.message}")
    @preload_errors[key] = error.message.to_s
    default
  end

  def available_app(kind)
    uuid = APP_IDS[kind].to_s.downcase
    @remote_apps.find do |app|
      app.respond_to?(:id) && app.id.to_s.downcase == uuid &&
        app.respond_to?(:elten_api_version) && Programs.api_version_compatible?(app.elten_api_version)
    end
  end

  def forum_groups
    @forum_structure == nil ? [] : @forum_structure.groups.to_a
  end

  def load_introduction_posting_statuses
    @introduction_posting_statuses = nil
    thread_ids = forum_groups.filter_map do |group|
      thread_id = group.thread_introductions.to_i
      thread_id if group.recommended && thread_id.positive?
    end.uniq
    return if thread_ids.empty?

    @introduction_posting_statuses = wizard_fetch(:forum_introduction_history, nil) do
      EltenLink::Forum.posted_in_threads(elten_link, threads: thread_ids)
    end
  end

  def joined_recommended_group?
    forum_groups.any? { |group| group.recommended && [1, 2].include?(group.role.to_i) }
  end

  def introduction_needed?
    group = preferred_introduction_group
    introduction_status(group) == false
  end

  def introduction_posted?(group)
    introduction_status(group) == true
  end

  def introduction_status(group)
    return nil if group == nil || !@introduction_posting_statuses.is_a?(Hash)

    @introduction_posting_statuses[group.thread_introductions.to_i]
  end

  def synchronize_introduction_page
    shown = @pages.any? { |page| page.id == :forum_introduction }
    needed = introduction_needed?
    @state.delete(:introduction_text) unless needed
    rebuild_pages if shown != show_when(needed)
    true
  end

  def latest_feed_time
    message = @own_feed.max_by { |item| item.respond_to?(:time) ? item.time.to_i : 0 }
    message == nil ? 0 : message.time.to_i
  end


  def add_page(id, title, &builder)
    @pages.push(Page.new(id: id.to_sym, title: title.to_s, builder: builder))
  end

  def add_info_page(id, title, text)
    add_page(id, title) { view([information_field(title, text)]) }
  end

  def add_action_page(id, title, text, button_label, &action)
    add_page(id, title) do
      button = Button.new(button_label)
      button.on(:press, &action)
      view([information_field(title, text), button])
    end
  end

  def information_field(title, text)
    EditBox.new(
      title,
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine | EditBox::Flags::MarkDown,
      text: text.to_s,
      quiet: true
    )
  end

  def view(fields, &capture)
    View.new(fields: fields, capture: capture)
  end

  def show_when(condition)
    (@force_all && @show_irrelevant) || condition
  end

  def show_page
    page = @pages[@page_index]
    @view = page.builder.call
    fields = @view.fields.to_a.dup
    @back_button = @page_index == 0 ? nil : Button.new(_("Back"))
    @next_button = Button.new(@page_index == @pages.size - 1 ? _("Finish") : _("Next"))
    fields.push(@back_button) if @back_button != nil
    fields.push(@next_button)
    @form = Form.new(fields)
    @form.header = p_("WelcomeWizard", "%{title}, page %{current} of %{total}") % {
      title: page.title,
      current: @page_index + 1,
      total: @pages.size
    }
    @form.accept_button = @next_button
  end

  def capture_current_page
    return true if @view == nil || @view.capture == nil

    @view.capture.call != false
  rescue Exception => error
    Log.warning("Welcome wizard page capture failed: #{error.class}: #{error.message}")
    alert(p_("WelcomeWizard", "Elten could not read the choices on this page. Review them and try again. Details: %{error}") % { error: error.message.to_s })
    false
  end

  def previous_page
    return alert(p_("WelcomeWizard", "You are already on the first page."), false) if @page_index == 0
    return unless capture_current_page

    @page_index -= 1
    show_page
  end

  def next_page
    return unless capture_current_page

    if @page_index == @pages.size - 1
      finish_wizard
    else
      @page_index += 1
      show_page
    end
  end

  def cancel_wizard
    confirm(p_("WelcomeWizard", "Exit the setup wizard? Selections waiting for Finish will be discarded. Changes made in a separate screen opened from the wizard, such as the two-factor authentication setup, are not part of these selections and will not be undone.")) do
      @state.clear
      $scene = Scene_Main.new
    end
  end

  def config_value(key)
    @account_config[key.to_s]
  end

  def data_available?(*keys)
    keys.any? { |key| !@preload_errors.to_h.key?(key) }
  end

  def current_full_name
    value = config_value("fullname").to_s
    value = @profile.fullname.to_s if value == "" && @profile != nil
    value
  end

  def current_gender
    value = config_value("gender")
    return value.to_i if value != nil && value.to_s != ""
    return @profile.gender.to_i if @profile != nil

    -1
  end

  def current_birthdate
    profile_birthdate = @profile&.birthdate
    {
      year: present_integer(config_value("birthdateyear"), profile_birthdate&.year),
      month: present_integer(config_value("birthdatemonth"), profile_birthdate&.month),
      day: present_integer(config_value("birthdateday"), profile_birthdate&.day)
    }
  end

  def current_visiting_card
    value = config_value("visitingcard")
    value == nil ? @visiting_card.to_s : value.to_s
  end

  def current_main_language
    normalise_language(config_value("mainlanguage"))
  end

  def current_languages
    config_value("languages").to_s.split(",").map { |value| normalise_language(value) }.reject(&:empty?).uniq
  end

  def present_integer(primary, fallback)
    primary.to_s.empty? ? fallback.to_i : primary.to_i
  end

  def normalise_language(code)
    code.to_s.strip[0, 2].to_s.downcase
  end

  def interface_language
    code = normalise_language(Configuration.language)
    code = "en" if code == "" || !language_codes.include?(code)
    code
  end

  def language_codes
    @language_codes ||= begin
      codes = Lists.langs.is_a?(Hash) ? Lists.langs.keys.map { |code| normalise_language(code) }.uniq : []
      codes.push("en") if !codes.include?("en")
      codes.sort_by { |code| language_label(code).downcase }
    end
  end

  def language_label(code)
    normalised = normalise_language(code)
    data = Lists.langs.is_a?(Hash) ? Lists.langs[normalised] : nil
    return normalised.upcase if !data.is_a?(Hash)

    name = data["name"].to_s
    native = data["nativeName"].to_s
    return native if name == ""
    return name if native == "" || native.casecmp(name) == 0

    "#{name} (#{native})"
  end

  def month_names
    [_("January"), _("February"), _("March"), _("April"), _("May"), _("June"), _("July"), _("August"), _("September"), _("October"), _("November"), _("December")]
  end

  def birthdate_complete?(birthdate)
    birthdate[:year].to_i > 0 && birthdate[:month].to_i.between?(1, 12) && birthdate[:day].to_i.between?(1, 31)
  end

  def birthdate_in_expected_range?(birthdate)
    valid_calendar_birthdate?(birthdate) && birthdate[:year].to_i.between?(1900, 2013)
  end

  def valid_calendar_birthdate?(birthdate)
    year = birthdate[:year].to_i
    month = birthdate[:month].to_i
    day = birthdate[:day].to_i
    year >= 1900 && Date.valid_date?(year, month, day)
  end

  def format_birthdate(birthdate)
    "%04d-%02d-%02d" % [birthdate[:year].to_i, birthdate[:month].to_i, birthdate[:day].to_i]
  end

  def human_file_size(value)
    size = value.to_f
    return p_("WelcomeWizard", "%{size} bytes") % { size: size.to_i } if size < 1024
    return p_("WelcomeWizard", "%{size} KB") % { size: (size / 1024.0).round(1) } if size < 1024 * 1024

    p_("WelcomeWizard", "%{size} MB") % { size: (size / 1024.0 / 1024.0).round(1) }
  end

  def store_changed_text(key, value, initial, strip: true)
    value = value.to_s
    value = value.strip if strip
    initial = initial.to_s
    initial = initial.strip if strip
    value == initial ? @state.delete(key) : @state[key] = value
  end

  def store_selection(key, values, unchanged=[])
    values.empty? || values == unchanged ? @state.delete(key) : @state[key] = values
  end

  def gender_label(value)
    return _("Female") if value.to_i == 0
    return _("Male") if value.to_i == 1

    p_("WelcomeWizard", "not specified")
  end

  def language_priority
    main = normalise_language(@state[:main_language] || current_main_language)
    main = "" if !language_codes.include?(main)
    primary = main == "" ? interface_language : main
    additional = (@state[:languages] || current_languages).map { |code| normalise_language(code) }
    ([primary] + additional + ["en"]).select { |code| language_codes.include?(code) }.uniq
  end

  def recommended_group_candidates
    groups = forum_groups.select { |group| group.recommended && group.role.to_i == 0 && (group.public || group.open) }
    priority = language_priority
    primary = priority.first || interface_language
    fallback = !groups.any? { |group| normalise_language(group.lang) == primary }
    wanted = priority.dup
    wanted.push("en") if fallback
    candidates = groups.select { |group| wanted.include?(normalise_language(group.lang)) }
    candidates.sort_by! do |group|
      language_index = wanted.index(normalise_language(group.lang)) || wanted.size
      [language_index, group.name.to_s.downcase]
    end
    [candidates, fallback]
  end

  def preferred_introduction_group
    priority = language_priority
    forum_groups.select { |group| group.recommended && group.thread_introductions.to_i > 0 }.min_by do |group|
      [priority.index(normalise_language(group.lang)) || priority.size, group.name.to_s.downcase]
    end
  end

  def summary_text
    changes = change_summary_lines
    lines = if changes.empty?
      [p_("WelcomeWizard", "Nothing has been selected. Choose Finish to close the wizard without changing account, community or keyboard settings.")]
    else
      [p_("WelcomeWizard", "Choose Finish to apply the following selections:"), ""] + changes.map { |line| "• #{line}" }
    end
    deferred = deferred_information_lines
    if !deferred.empty?
      lines += ["", p_("WelcomeWizard", "Elten could not check the following information. The wizard will make no changes based on it:"), ""]
      lines += deferred.map { |line| "• #{line}" }
    end
    lines.push("", p_("WelcomeWizard", "Use Back to review a page, Finish to apply the selections above, or Escape to leave without applying them."))
    lines.join("\n")
  end

  def change_summary_lines
    lines = []
    if @state.key?(:full_name)
      if @state[:full_name].to_s.empty?
        lines.push(p_("WelcomeWizard", "Remove the public name from the profile"))
      else
        lines.push(p_("WelcomeWizard", "Set the public name to %{name}") % { name: @state[:full_name] })
      end
    end
    if @state.key?(:gender)
      if @state[:gender].to_i == -1
        lines.push(p_("WelcomeWizard", "Do not specify a gender on the profile"))
      else
        lines.push(p_("WelcomeWizard", "Set the profile gender to %{gender}") % { gender: gender_label(@state[:gender]) })
      end
    end
    lines.push(p_("WelcomeWizard", "Set the date of birth to %{date}") % { date: format_birthdate(@state[:birthdate]) }) if @state[:birthdate]
    if @state.key?(:visiting_card)
      if @state[:visiting_card].to_s.empty?
        lines.push(p_("WelcomeWizard", "Remove the visiting card"))
      else
        lines.push(p_("WelcomeWizard", "Replace the visiting card"))
      end
    end
    if @state.key?(:status)
      if @state[:status].to_s.empty?
        lines.push(p_("WelcomeWizard", "Remove the status"))
      else
        lines.push(p_("WelcomeWizard", "Set the status to %{status}") % { status: @state[:status] })
      end
    end
    if @state.key?(:signature)
      if @state[:signature].to_s.empty?
        lines.push(p_("WelcomeWizard", "Remove the forum signature"))
      else
        lines.push(p_("WelcomeWizard", "Set the forum signature to %{signature}") % { signature: @state[:signature] })
      end
    end
    lines.push(p_("WelcomeWizard", "Set the main language to %{language}") % { language: language_label(@state[:main_language]) }) if @state[:main_language]
    if @state[:languages]
      lines.push(p_("WelcomeWizard", "Set additional languages to %{languages}") % { languages: @state[:languages].map { |code| language_label(code) }.join(", ") })
    end
    if @state[:join_group_ids]
      names = forum_groups.select { |group| @state[:join_group_ids].include?(group.id.to_i) }.map(&:name)
      lines.push(p_("WelcomeWizard", "Join forum groups: %{groups}") % { groups: names.join(", ") })
    end
    lines.push(p_("WelcomeWizard", "Publish a post in the introductions thread")) if @state[:introduction_text]
    if @state[:follow_blog_ids]
      count = @state[:follow_blog_ids].to_a.size
      lines.push(np_("WelcomeWizard", "Follow %{count} blog", "Follow %{count} blogs", count) % { count: count })
    end
    if @state[:follow_feed_users]
      count = @state[:follow_feed_users].to_a.size
      lines.push(np_("WelcomeWizard", "Follow %{count} person on the feed", "Follow %{count} people on the feed", count) % { count: count })
    end
    lines.push(p_("WelcomeWizard", "Publish a feed entry")) if @state[:feed_greeting]
    lines.push(p_("WelcomeWizard", "Change the macOS keyboard style")) if @state[:keyboard_scheme]
    lines.push(p_("WelcomeWizard", "Change character navigation behaviour")) if @state[:character_navigation]
    lines.push(p_("WelcomeWizard", "Change the Invisible Interface modifier keys")) if @state[:ii_modifiers]
    lines.push(p_("WelcomeWizard", "Change when audio content plays automatically")) if @state[:autoplay]
    lines.push(p_("WelcomeWizard", "Change the tabs shown in the main window")) if @state[:main_tabs]
    if @state[:show_empty_notifications]
      if @state[:show_empty_notifications] == "true"
        lines.push(p_("WelcomeWizard", "Always show the notifications tab"))
      else
        lines.push(p_("WelcomeWizard", "Hide the notifications tab when it is empty"))
      end
    end
    lines.push(p_("WelcomeWizard", "Change how the notifications tab takes focus")) if @state[:notification_focus]
    lines.push(p_("WelcomeWizard", "Change how control types are announced")) if @state[:controls_presentation]
    if @state[:context_menu_bar]
      if @state[:context_menu_bar] == "true"
        lines.push(p_("WelcomeWizard", "Show the context menu in the menu bar"))
      else
        lines.push(p_("WelcomeWizard", "Hide the context menu from the menu bar"))
      end
    end
    if @state[:hide_window]
      if @state[:hide_window] == "true"
        lines.push(p_("WelcomeWizard", "Enable minimising to the system tray"))
      else
        lines.push(p_("WelcomeWizard", "Disable minimising to the system tray"))
      end
    end
    if @state[:disable_feed_notifications]
      if @state[:disable_feed_notifications] == "true"
        lines.push(p_("WelcomeWizard", "Disable feed notifications"))
      else
        lines.push(p_("WelcomeWizard", "Enable feed notifications"))
      end
    end
    @state[:install_apps].to_h.each_key { |kind| lines.push(p_("WelcomeWizard", "Install %{program}") % { program: app_copy(kind)[:name] }) }
    lines
  end

  def deferred_information_lines
    labels = {
      account_configuration: p_("WelcomeWizard", "account language and configuration"),
      profile: p_("WelcomeWizard", "profile information"),
      visiting_card: p_("WelcomeWizard", "visiting card"),
      two_factor_authentication: p_("WelcomeWizard", "two-factor authentication status"),
      forum: p_("WelcomeWizard", "forum groups and introduction thread"),
      forum_introduction_history: p_("WelcomeWizard", "your posting history in introduction threads"),
      contacts: p_("WelcomeWizard", "contacts"),
      contact_blogs: p_("WelcomeWizard", "recent blogs belonging to your contacts"),
      feed_follows: p_("WelcomeWizard", "followed feed users"),
      own_feed: p_("WelcomeWizard", "your feed history"),
      payment_methods: p_("WelcomeWizard", "donation transfer details"),
      programs: p_("WelcomeWizard", "programs available on the server"),
      installed_programs: p_("WelcomeWizard", "installed program status")
    }
    @preload_errors.keys.map { |key| labels[key] || key.to_s.tr("_", " ") }
  end


  def finish_wizard
    @applied.clear
    @failed.clear
    waiting
    apply_account_changes
    apply_local_changes
    apply_forum_changes
    apply_social_changes
    waiting_end
    apply_program_changes
    show_completion_report
    $scene = Scene_Main.new
  rescue Exception => error
    waiting_end rescue nil
    Log.error("Welcome wizard finish failed: #{error.class}: #{error.message}")
    alert(p_("WelcomeWizard", "The wizard stopped unexpectedly. Some earlier operations may already have completed. Review your settings before trying again. Details: %{error}") % { error: error.message.to_s })
    $scene = Scene_Main.new
  end

  def account_changes
    values = {}
    values["fullname"] = @state[:full_name] if @state.key?(:full_name)
    values["gender"] = @state[:gender] if @state.key?(:gender)
    if @state[:birthdate]
      values["birthdateyear"] = @state[:birthdate][:year]
      values["birthdatemonth"] = @state[:birthdate][:month]
      values["birthdateday"] = @state[:birthdate][:day]
    end
    values["visitingcard"] = @state[:visiting_card] if @state.key?(:visiting_card)
    values["status"] = @state[:status] if @state.key?(:status)
    values["signature"] = @state[:signature] if @state.key?(:signature)
    values["mainlanguage"] = @state[:main_language] if @state[:main_language]

    languages = @state[:languages] == nil ? current_languages.dup : @state[:languages].dup
    main = @state[:main_language] || current_main_language
    languages.unshift(main) if main != "" && !languages.include?(main)
    if @state[:languages] != nil || (@state[:main_language] != nil && languages != current_languages)
      values["languages"] = languages.uniq.join(",")
    end
    values
  end

  def apply_account_changes
    values = account_changes
    return if values.empty?

    perform(p_("WelcomeWizard", "Account and profile settings")) do
      EltenLink::Accounts.update_config(elten_link, values)
      Session.fullname = values["fullname"].to_s if values.key?("fullname")
      Session.gender = values["gender"].to_i if values.key?("gender")
      Session.languages = values["languages"].to_s if values.key?("languages")
      true
    end
  end

  def apply_local_changes
    changes = []
    changes.push(["Interface", "KeyboardScheme", @state[:keyboard_scheme]]) if @state[:keyboard_scheme]
    changes.push(["Interface", "MacOSCharacterNavigation", @state[:character_navigation]]) if @state[:character_navigation]
    changes.push(["InvisibleInterface", "IIModifiers", @state[:ii_modifiers]]) if @state[:ii_modifiers]
    changes.push(["Interface", "AutoPlay", @state[:autoplay]]) if @state[:autoplay]
    changes.push(["MainWindow", "Tabs", @state[:main_tabs].join(",")]) if @state[:main_tabs]
    changes.push(["MainWindow", "ShowNotificationsWhenEmpty", @state[:show_empty_notifications]]) if @state[:show_empty_notifications]
    changes.push(["MainWindow", "NotificationFocus", @state[:notification_focus]]) if @state[:notification_focus]
    changes.push(["Interface", "ControlsPresentation", @state[:controls_presentation]]) if @state[:controls_presentation]
    changes.push(["Interface", "ContextMenuBar", @state[:context_menu_bar]]) if @state[:context_menu_bar]
    changes.push(["Interface", "HideWindow", @state[:hide_window]]) if @state[:hide_window]
    changes.push(["Interface", "DisableFeedNotifications", @state[:disable_feed_notifications]]) if @state[:disable_feed_notifications]
    return if changes.empty?

    perform(p_("WelcomeWizard", "Local program settings")) do
      changes.each { |group, key, value| writeconfig(group, key, value) }
      load_configuration
      true
    end
  end

  def apply_forum_changes
    @state[:join_group_ids].to_a.each do |group_id|
      group = forum_groups.find { |item| item.id.to_i == group_id.to_i }
      name = group == nil ? group_id.to_s : group.name.to_s
      perform(p_("WelcomeWizard", "Join forum group %{group}") % { group: name }) do
        EltenLink::Forum.join_group(elten_link, group_id: group_id)
        group.role = 1 if group != nil
        true
      end
    end

    if @state[:introduction_text]
      group = preferred_introduction_group
      if group == nil
        @failed.push([p_("WelcomeWizard", "Forum introduction"), p_("WelcomeWizard", "No introduction thread is available")])
      else
        perform(p_("WelcomeWizard", "Forum introduction")) do
          EltenLink::Forum.create_post(elten_link, thread_id: group.thread_introductions.to_i, text: @state[:introduction_text])
          true
        end
      end
    end
  end

  def apply_social_changes
    @state[:follow_blog_ids].to_a.each do |blog_id|
      suggestion = @blog_suggestions.find { |item| item.blog.id.to_s == blog_id.to_s }
      blog_name = suggestion == nil ? blog_id.to_s : suggestion.blog.name.to_s
      perform(p_("WelcomeWizard", "Follow blog %{blog}") % { blog: blog_name }) do
        EltenLink::Blog.follow(elten_link, blog: blog_id)
        true
      end
    end
    @state[:follow_feed_users].to_a.each do |user|
      perform(p_("WelcomeWizard", "Follow %{user} on the feed") % { user: user }) do
        EltenLink::Feeds.follow(elten_link, user, follow: true)
        true
      end
    end
    if @state[:feed_greeting]
      perform(p_("WelcomeWizard", "Publish a feed entry")) do
        result = EltenLink::Feeds.publish(elten_link, @state[:feed_greeting])
        raise p_("WelcomeWizard", "The server did not accept the feed entry") if result != true
        true
      end
    end
    Session.feeds_clear if (@state[:follow_feed_users] || @state[:feed_greeting]) && Session.respond_to?(:feeds_clear)
  end

  def apply_program_changes
    selected = @state[:install_apps].to_h.keys
    return if selected.empty?

    helper = Scene_Programs.new
    selected.each do |kind|
      app = available_app(kind)
      label = app_copy(kind)[:name]
      if app == nil
        @failed.push([p_("WelcomeWizard", "Install %{program}") % { program: label }, p_("WelcomeWizard", "The server no longer offers this program for your operating system")])
        next
      end
      perform(p_("WelcomeWizard", "Install %{program}") % { program: label }) do
        result = helper.send(:install_remote_program, app, ask: false)
        raise p_("WelcomeWizard", "The program installer did not report success") if result != true
        true
      end
    end
  end

  def perform(label)
    result = yield
    raise p_("WelcomeWizard", "The server did not confirm the operation") if result == false
    @applied.push(label)
    true
  rescue Exception => error
    Log.warning("Welcome wizard operation failed (#{label}): #{error.class}: #{error.message}")
    @failed.push([label, error.message.to_s])
    false
  end

  def show_completion_report
    lines = [p_("WelcomeWizard", "Setup is complete.")]
    if @applied.empty?
      lines.push("", p_("WelcomeWizard", "No wizard selections were applied."))
    else
      lines.push("", p_("WelcomeWizard", "Applied successfully:"))
      lines.concat(@applied.map { |label| "• #{label}" })
    end
    if !@failed.empty?
      lines.push("", p_("WelcomeWizard", "Not completed:"))
      lines.concat(@failed.map { |label, error| "• #{label}: #{error}" })
    end
    deferred = deferred_information_lines
    if !deferred.empty?
      lines.push("", p_("WelcomeWizard", "Not checked during setup:"))
      lines.concat(deferred.map { |label| "• #{label}" })
    end
    lines.push("", p_("WelcomeWizard", "You can review these settings and actions later from their respective Elten menus."))
    alert(lines.join("\n"))
  end

end
