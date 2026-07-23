# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "cgi"

module EltenAPI
  module InvisibleInterface
    class CustomCategory
      attr_accessor :name, :available_proc, :onetimer

      def initialize(name="")
        @name = name
        @available_proc = Proc.new { true }
        @onetimer = true
        @options = []
        @index = 0
      end

      def add_option(label, &block)
        @options << [label, block]
      end

      def select_option(change, repeat=true)
        new_index = if change.is_a?(Numeric)
          @index + change
        elsif change == :first
          0
        elsif change == :last
          @options.size - 1
        else
          @index
        end
        if new_index < 0 || new_index >= @options.size
          InvisibleInterface.play_border
          select_option(0, false) if repeat && @options.size > 0
        else
          @index = new_index
          InvisibleInterface.play_move
          option = @options[@index]
          InvisibleInterface.say(option[0].respond_to?(:call) ? option[0].call : option[0])
        end
      end

      def call(action)
        case action
        when :up
          select_option(-1)
        when :down
          select_option(1)
        when :say
          select_option(0)
        when :first
          select_option(:first)
        when :last
          select_option(:last)
        when :select
          option = @options[@index]
          option[1].call if option != nil && option[1] != nil
        end
      end
    end

    class << self
      include EltenAPI

      def available?
        true
      end

      KEY_ACTIONS = {
        0x25 => :left,
        0x26 => :up,
        0x27 => :right,
        0x28 => :down,
        0x23 => :first,
        0x24 => :last,
        0x21 => :pageup,
        0x22 => :pagedown,
        0x20 => :say,
        0x08 => :stop,
        0x0d => :select,
        77 => :message,
        70 => :feed,
        75 => :like,
        82 => :reply
      }.freeze
      MESSAGE_REQUEST_TIMEOUT = 5

      def start
        ensure_state
        return true if @worker != nil && @worker.alive?
        @stopped = false
        @worker = Thread.new { worker_loop }
        @worker.report_on_exception = false
        refresh_configuration(true)
        true
      end

      def stop
        ensure_state
        @stopped = true
        Hotkeys.stop
        NativeDialogs.close_all
        @jobs << [:stop]
      rescue Exception
      end

      def tick
        start
        refresh_configuration
        drain_ui_events
      rescue Exception => e
        Log.error("InvisibleInterface tick: #{e.class}: #{e.message}")
      end

      def session_changed
        ensure_state
        reset_session
      end

      def reset_for_loading
        ensure_state
        reset_session
        @categories = default_categories
        @category = nil
        @conference_index = 0
      end

      def reset_feeds
        ensure_state
        @feed_id = nil
        @feed_lasttext = nil
      end

      def set_feed_id(id)
        ensure_state
        @feed_id = id.to_i
      end

      def play_border
        play_sound("border") rescue nil
      end

      def play_move
        play_sound("listbox_focus") rescue nil
      end

      def say(text)
        speak(text.to_s) rescue nil
      end

      private

      def ensure_state
        return if @state_ready == true
        @state_ready = true
        @jobs = Queue.new
        @ui_events = Queue.new
        @categories = default_categories
        @category = nil
        @message_id = 0
        @message_id_pending = false
        @message_request_pending = false
        @message_request_token = 0
        @message_lasttext = nil
        @message_lastsubject = nil
        @message_lastrecipient = nil
        @feed_id = nil
        @feed_lasttext = nil
        @conference_index = 0
        @last_dice_roll = 6
        @quick_audio = nil
      end

      def worker_loop
        loop do
          job = @jobs.pop
          break if @stopped == true || job[0] == :stop
          handle_job(job)
        rescue Exception => e
          Log.error("InvisibleInterface worker: #{e.class}: #{e.message}\r\n#{Array(e.backtrace).join("\r\n")}")
        end
      end

      def handle_job(job)
        case job[0]
        when :hotkey
          action = KEY_ACTIONS[job[1].to_i]
          navigate(action) if action != nil
        when :session_changed
          reset_session
        when :message_result
          handle_message_result(job[1], job[2], job[3])
        when :message_submit
          submit_message(job[1])
        when :feed_submit
          submit_feed(job[1], job[2])
        when :chat_submit
          submit_chat(job[1])
        when :conference_stream_file
          conference.set_stream(job[1]) if conference != nil && job[1] != nil
        when :hotkey_modifiers_selected
          profile = ConfigurationValues.invisible_interface_modifier_profile(job[1])
          Configuration.iimodifiers = profile
          writeconfig("InvisibleInterface", "IIModifiers", profile) rescue nil
          @configuration_signature = [profile, @cards || config_cards]
          @ui_events << [:modifiers_selected, profile]
        when :hotkey_errors
          @ui_events << [:hotkey_errors, job[1].to_i]
        when :hotkey_error
          Log.error("InvisibleInterface hotkeys: #{job[1].class}: #{job[1].message}")
        end
      end

      def refresh_configuration(force=false)
        cards = config_cards
        profile = Configuration.iimodifiers
        signature = [profile, cards]
        return if force != true && @configuration_signature == signature && Hotkeys.running?
        @configuration_signature = signature
        @cards = cards
        Hotkeys.configure(ConfigurationValues.invisible_interface_modifier_mask(profile), @jobs)
      end

      def drain_ui_events
        loop do
          event = @ui_events.pop(true)
          case event[0]
          when :hotkey_errors
            Log.error("#{event[1]} errors while registering Invisible Interface hotkeys")
            alert(p_("EAPI_UI", "Errors occurred while trying to register keys for invisible interface. Please make sure that other apps do not use the keys specified. You can change modifier keys of invisible interface using settings window.")) rescue nil
          when :modifiers_selected
            Log.info("Invisible Interface modifiers selected: #{event[1]}")
          end
        rescue ThreadError
          break
        end
      end

      def reset_session
        @message_request_token = @message_request_token.to_i + 1
        @message_request_pending = false
        @message_id = 0
        @message_id_pending = false
        @message_lasttext = nil
        @message_lastsubject = nil
        @message_lastrecipient = nil
        @feed_id = nil
        @feed_lasttext = nil
      end

      def default_categories
        ["messages", "feed", "conference"]
      end

      def navigate(action)
        return if action == nil
        set_category(0, true) if !category_available?
        case @category
        when "messages"
          navigate_messages(action)
        when "feed"
          navigate_feed(action)
        when "conference"
          navigate_conference(action)
        else
          @category.call(action) if @category.is_a?(CustomCategory)
        end
        case action
        when :left
          set_category(-1)
        when :right
          set_category(1)
        when :message
          open_message_dialog
        when :feed
          open_feed_dialog
        when :stop
          quick_audio_stop
        end
      end

      def set_category(change, quiet=false, origin=nil)
        index = @categories.find_index(@category)
        if index == nil
          index = @categories.find_index { |category| @cards.include?(category.to_s) } || 0
        end
        index = (index + change.to_i) % @categories.size
        @category = @categories[index]
        if !category_available?
          if origin == index
            play_border
            return
          end
          return set_category(change == 0 ? 1 : change, quiet, origin || index)
        end
        return if quiet
        case @category
        when "messages"
          say(p_("Messages", "Messages"))
        when "feed"
          say(p_("FeedViewer", "Feed"))
        when "conference"
          say(p_("Conference", "Conference"))
        else
          say(@category.name) if @category.is_a?(CustomCategory)
        end
      end

      def category_available?
        set_category(0, true) if @category == nil
        if @category.is_a?(CustomCategory)
          available = @category.available_proc.call
          @categories.delete(@category) if @category.onetimer
          return available
        end
        @cards.include?(@category.to_s) && (@category != "conference" || conference != nil)
      rescue Exception
        false
      end

      def navigate_messages(action)
        case action
        when :up
          read_message(:next)
        when :down
          read_message(:prev)
        when :pageup
          read_message(:next, true)
        when :pagedown
          read_message(:prev, true)
        when :last
          read_message(:last)
        when :first
          read_message(:first)
        when :say
          speak(@message_lasttext) if @message_lasttext.is_a?(String)
        when :reply
          subject = @message_lastsubject
          subject = "RE: " + subject if subject.is_a?(String) && subject[0...4] != "RE: "
          open_message_dialog(@message_lastrecipient, subject, nil, p_("Messages", "Reply"))
        end
      end

      def read_message(direction, not_subject=false)
        return if !logged_in?
        if @message_request_pending == true
          play_border
          return
        end
        @message_request_pending = true
        token = @message_request_token.to_i + 1
        @message_request_token = token
        current_id = @message_id.to_i
        last_subject = @message_lastsubject
        last_recipient = @message_lastrecipient
        Thread.new do
          Thread.current.report_on_exception = false
          message = nil
          error = nil
          begin
            message = fetch_quick_message(direction, not_subject, current_id, last_subject, last_recipient)
          rescue Exception => e
            error = e
          ensure
            @jobs << [:message_result, token, message, error]
          end
        end
      rescue Exception => e
        Log.error("InvisibleInterface message read: #{e.class}: #{e.message}")
        @message_request_pending = false
        play_border
      end

      def fetch_quick_message(direction, not_subject, current_id, last_subject, last_recipient)
        client = EltenLink::Client.new
        id = current_id.to_i
        action = direction == :prev ? "prev" : "next"
        if direction == :first
          id = 0
          action = "next"
        elsif direction == :last
          id = 2**32
          action = "prev"
        elsif id == 0
          begin
            id = EltenLink::Messages.quick_last_id(client, timeout: MESSAGE_REQUEST_TIMEOUT)
          rescue Exception => e
            Log.error("InvisibleInterface message last id: #{e.class}: #{e.message}")
            id = 0
          end
          if id == 0 && direction == :prev
            id = 2**32
            action = "prev"
          end
        end
        Log.debug("InvisibleInterface message quick-read request: direction=#{direction} action=#{action} id=#{id} skip=#{not_subject == true}")
        message = EltenLink::Messages.quick_message(
          client,
          current_id: id,
          direction: action == "next" ? :next : :previous,
          skip_subject: not_subject ? last_subject : nil,
          skip_user: not_subject ? last_recipient : nil,
          timeout: MESSAGE_REQUEST_TIMEOUT
        )
        Log.debug("InvisibleInterface message quick-read result: #{message == nil ? "not_found" : "id=#{message.id.to_i}"}")
        message
      end

      def handle_message_result(token, message, error)
        return if token.to_i != @message_request_token.to_i
        @message_request_pending = false
        if error != nil
          Log.error("InvisibleInterface message read: #{error.class}: #{error.message}")
          play_border
          return
        end
        handle_message(message)
      end

      def handle_message(message)
        quick_audio_stop
        if message == nil || message.id.to_i == 0
          play_border
          speak(@message_lasttext) if @message_lasttext.is_a?(String)
          return
        end
        play_move
        @message_id = message.id.to_i
        from = message.sender.to_s
        to = message.receiver.to_s
        name = message.group_name.to_s
        subject = message.subject.to_s
        body = message.text.to_s
        audio_url = message.respond_to?(:audio_url) ? message.audio_url.to_s : ""
        @message_lastsubject = subject
        @message_lastrecipient = from
        @message_lastrecipient = to if from == session_name || name != ""
        text = from
        text = p_("Messages", "To") + " " + to if from == session_name && name == ""
        text += " " + p_("Messages", "To") + " " + name if name != ""
        text += ": " + body
        quick_audio_play(audio_url) if audio_url != ""
        @message_lasttext = text
        speak(text)
      rescue Exception => e
        Log.error("InvisibleInterface message read: #{e.class}: #{e.message}")
      end

      def navigate_feed(action)
        case action
        when :up
          read_feed(:next)
        when :down
          read_feed(:prev)
        when :last
          read_feed(:last)
        when :first
          read_feed(:first)
        when :say
          say(feed_lasttext) if feed_lasttext != nil
        when :like
          like_current_feed
        when :reply
          reply_current_feed
        end
      end

      def read_feed(action)
        feeds = feed_values
        if feeds.empty?
          play_border
          return
        end
        @feed_id = feeds.last.id if @feed_id == nil || @feed_id.to_i == 0
        feed = case action
        when :prev
          feeds.select { |f| f.id < @feed_id.to_i && f.message.to_s != "" }.max_by { |f| f.id }
        when :next
          feeds.select { |f| f.id > @feed_id.to_i && f.message.to_s != "" }.min_by { |f| f.id }
        when :first
          feeds.select { |f| f.message.to_s != "" }.min_by { |f| f.id }
        when :last
          feeds.select { |f| f.message.to_s != "" }.max_by { |f| f.id }
        end
        if feed != nil
          @feed_id = feed.id
          Scene_Main.feed_id = feed.id if defined?(Scene_Main)
          @feed_lasttext = feed.user.to_s + ": " + feed.message.to_s
          play_move
          say(@feed_lasttext)
        else
          play_border
          say(feed_lasttext) if feed_lasttext != nil
        end
      end

      def like_current_feed
        feed = current_feed
        return if feed == nil
        liked = !feed.liked
        EltenLink::Feeds.set_liked(elten_link, feed.id, liked)
        status = liked ? p_("FeedViewer", "Message liked") : p_("FeedViewer", "Message disliked")
        feed.likes = [feed.likes.to_i + (liked ? 1 : -1), 0].max if feed.respond_to?(:likes=)
        feed.liked = liked
        say(status)
      rescue Exception => e
        Log.error("InvisibleInterface feed like: #{e.class}: #{e.message}")
        play_border
      end

      def reply_current_feed
        feed = current_feed
        return if feed == nil
        users = [feed.user]
        users += feed.message.to_s.scan(/\@([a-zA-Z0-9\.\-\_]+)/).map { |r| r[0] }
        users = users.compact.map(&:to_s)
        users.delete_if { |user| user.downcase == session_name.to_s.downcase }
        users = users.each_with_object([]) { |user, out| out << user if !out.map(&:downcase).include?(user.downcase) }
        response = feed.response.to_i != 0 ? feed.response : feed.id
        open_feed_dialog(users.map { |u| "@" + u }.join(" ") + (users.empty? ? "" : " "), p_("Main", "Reply"), response)
      end

      def feed_values
        Session.feeds.values.compact.select { |feed| feed.respond_to?(:id) }.sort_by { |feed| feed.id.to_i }
      rescue Exception
        []
      end

      def current_feed
        return nil if @feed_id == nil
        feed_values.find { |feed| feed.id.to_i == @feed_id.to_i }
      end

      def feed_lasttext
        return @feed_lasttext if @feed_id == nil
        feed = current_feed
        feed == nil ? nil : feed.user.to_s + ": " + feed.message.to_s
      end

      def navigate_conference(action)
        case action
        when :up
          read_conference(:prev)
        when :down
          read_conference(:next)
        when :last
          read_conference(:first)
        when :first
          read_conference(:last)
        when :say
          read_conference(:say)
        when :select
          select_conference
        end
      end

      def conference_options
        return [] if conference == nil
        opts = [
          [conference.muted == true ? p_("Conference", "Unmute microphone") : p_("Conference", "Mute microphone"), Proc.new {
            conference.muted = !conference.muted
            say(conference.muted ? p_("Conference", "Microphone muted") : p_("Conference", "Microphone unmuted"))
          }],
          [p_("Conference", "Roll a 6-sided dice"), Proc.new { conference.diceroll(6) }],
          [p_("Conference", "Roll a custom dice"), Proc.new { open_dice_category }]
        ]
        if !conference.streaming?
          opts << [p_("Conference", "Stream audio file"), Proc.new {
            NativeDialogs.open_file(
              :title => p_("Conference", "Select audio file"),
              :filters => [["Audio", "*.wav", "*.ogg", "*.mp3", "*.opus", "*.aac", "*.m4a", "*.flac", "*.aiff"]]
            ) do |file|
              @jobs << [:conference_stream_file, file] if file != nil
            end
          }]
        else
          opts << [p_("Conference", "Remove audio stream"), Proc.new { conference.remove_stream }]
        end
        opts << [conference.pushtotalk == true ? p_("Conference", "Disable push to talk") : p_("Conference", "Enable push to talk"), Proc.new { conference.pushtotalk = !conference.pushtotalk }]
        opts << [p_("Conference", "Show chat history"), Proc.new { open_chat_history }]
        opts << [p_("Conference", "Post in chat"), Proc.new { open_chat_dialog }]
        conference.transmitters.each { |id, transmitter| opts << [transmitter.username, Proc.new { open_user_category(id, transmitter) }] }
        opts
      end

      def read_conference(action)
        opts = conference_options
        return if opts.empty?
        @conference_index = opts.size - 1 if @conference_index >= opts.size
        case action
        when :prev
          if @conference_index > 0
            @conference_index -= 1
            play_move
          else
            play_border
          end
          say(opts[@conference_index][0])
        when :next
          if @conference_index < opts.size - 1
            @conference_index += 1
            play_move
          else
            play_border
          end
          say(opts[@conference_index][0])
        when :first
          @conference_index = 0
          play_move
          say(opts[@conference_index][0])
        when :last
          @conference_index = opts.size - 1
          play_move
          say(opts[@conference_index][0])
        when :say
          say(opts[@conference_index][0])
        end
      end

      def select_conference
        opts = conference_options
        return if opts.empty? || @conference_index >= opts.size
        opts[@conference_index][1].call
      end

      def open_dice_category
        category = CustomCategory.new(p_("Conference", "Which dice do you want to roll?"))
        category.available_proc = Proc.new { conference != nil }
        1.upto(100) do |sides|
          label = p_("Conference", "%{count}-sided") % {:count => sides.to_s}
          category.add_option(label) do
            @last_dice_roll = sides
            conference.diceroll(sides) if conference != nil
          end
        end
        @categories << category
        @category = category
        category.select_option(@last_dice_roll.to_i - 1)
      end

      def open_chat_history
        category = CustomCategory.new(p_("Conference", "Chat"))
        category.available_proc = Proc.new { conference != nil }
        conference.chat.reverse.each { |entry| category.add_option(entry.username.to_s + ": " + entry.message.to_s) }
        @categories << category
        @category = category
        category.select_option(0)
      end

      def open_user_category(userid, transmitter)
        category = CustomCategory.new(transmitter.username)
        category.available_proc = Proc.new { conference != nil }
        category.add_option(Proc.new { conference.whisper != userid ? p_("Conference", "Whisper") : p_("Conference", "End whispering") }) do
          conference.whisper = conference.whisper != userid ? userid : 0
        end
        category.add_option(Proc.new { !conference.is_muted_user(transmitter.username) ? p_("Conference", "Mute user") : p_("Conference", "Unmute user") }) do
          if conference.toggle_muted_user(transmitter.username)
            play_sound("recording_stop")
          else
            play_sound("recording_start")
          end
        end
        category.add_option(p_("Conference", "Go to user")) { conference.goto(userid) }
        @categories << category
        @category = category
        category.select_option(0)
      end

      def open_message_dialog(recipient=nil, subject=nil, text=nil, title=nil)
        return if !logged_in?
        NativeDialogs.open_message(
          :title => (title || p_("Messages", "Send a new message")) + " - ELTEN",
          :recipient_label => p_("Messages", "Recipient"),
          :subject_label => p_("Messages", "Subject:"),
          :text_label => p_("Messages", "Message:"),
          :send_label => p_("Messages", "Send"),
          :cancel_label => _("Cancel"),
          :recipient => recipient,
          :subject => subject,
          :text => text
        ) do |result, values|
          @jobs << [:message_submit, values] if result == :submit
        end
        play_sound("signal")
      end

      def open_feed_dialog(text=nil, title=nil, response=0)
        return if !logged_in?
        NativeDialogs.open_writer(
          :title => (title || p_("Main", "Publish to a feed")) + " - ELTEN",
          :text_label => p_("Main", "Message"),
          :send_label => p_("Messages", "Send"),
          :cancel_label => _("Cancel"),
          :text => text,
          :max_length => 300
        ) do |result, values|
          @jobs << [:feed_submit, values[:text], response] if result == :submit
        end
        play_sound("signal")
      end

      def open_chat_dialog(text=nil, title=nil)
        return if !logged_in?
        NativeDialogs.open_writer(
          :title => (title || p_("Conference", "Chat message")) + " - ELTEN",
          :text_label => p_("Main", "Message"),
          :send_label => p_("Messages", "Send"),
          :cancel_label => _("Cancel"),
          :text => text,
          :max_length => 500
        ) do |result, values|
          @jobs << [:chat_submit, values[:text]] if result == :submit
        end
        play_sound("signal")
      end

      def submit_message(values)
        EltenLink::Messages.send_text(
          elten_link,
          to: values[:recipient].to_s,
          subject: values[:subject].to_s,
          text: values[:text].to_s
        )
        play_sound("messages_update")
      rescue Exception => e
        Log.error("InvisibleInterface message submit: #{e.class}: #{e.message}")
        open_message_dialog(values[:recipient], values[:subject], values[:text], p_("Messages", "Failed to send message"))
      end

      def submit_feed(text, response=0)
        ok = EltenLink::Feeds.publish(elten_link, text.to_s, response: response.to_i)
        open_feed_dialog(text, p_("Messages", "Failed to send message"), response) if !ok
      rescue Exception => e
        Log.error("InvisibleInterface feed submit: #{e.class}: #{e.message}")
        open_feed_dialog(text, p_("Messages", "Failed to send message"), response)
      end

      def submit_chat(text)
        conference.send_text(text.to_s) if conference != nil
      end

      def quick_audio_play(url)
        quick_audio_stop
        url = EltenLink::Client.absolute_api_url(url)
        @quick_audio = Sound.new(url)
        @quick_audio.volume = 0.5
        @quick_audio.play
      rescue Exception => e
        Log.error("InvisibleInterface audio: #{e.class}: #{e.message}")
      end

      def quick_audio_stop
        speech_stop rescue nil
        if @quick_audio != nil
          @quick_audio.close rescue nil
          @quick_audio = nil
        end
      end

      def logged_in?
        Session.name != nil && Session.name != "" && Session.name != "guest" && Session.token != nil && Session.token != ""
      end

      def session_name
        Session.name.to_s
      end

      def conference
        $conference
      end

      def config_cards
        value = Configuration.iicards

        return value.map { |entry| entry.to_s } if value.is_a?(Array)
        value.to_s.split(",")
      end
    end
  end
end
