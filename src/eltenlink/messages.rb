# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class MessageUser
    attr_accessor :user, :read, :lastdate, :lastuser, :lastsubject, :lastid, :muted, :name

    def initialize(user = "")
      @user = user
      @read = 0
      @lastdate = Time.at(0)
      @lastuser = ""
      @lastsubject = ""
      @lastid = 0
      @muted = false
      @name = ""
    end
  end

  class MessageConversation
    attr_accessor :subject, :read, :lastdate, :lastuser, :lastid

    def initialize(subject = "")
      @subject = subject
      @read = 0
      @lastdate = Time.at(0)
      @lastuser = ""
      @lastid = 0
    end
  end

  class Message
    attr_accessor :id, :receiver, :sender, :subject, :mread, :marked, :date, :attachments,
      :text, :audio_url, :attachments_names, :protected, :polls, :polls_names

    def initialize(id = 0)
      @id = id.to_i
      @receiver = Session.name
      @sender = Session.name
      @subject = ""
      @mread = 0
      @marked = 0
      @date = 0
      @attachments = []
      @attachments_names = []
      @protected = 0
      @polls = []
      @polls_names = []
      @text = ""
      @audio_url = ""
    end
  end

  class QuickMessage
    attr_accessor :id, :sender, :receiver, :group_name, :subject, :text, :audio_url

    def initialize(id: 0, sender: "", receiver: "", group_name: "", subject: "", text: "", audio_url: "")
      @id = id.to_i
      @sender = sender.to_s
      @receiver = receiver.to_s
      @group_name = group_name.to_s
      @subject = subject.to_s
      @text = text.to_s
      @audio_url = audio_url.to_s
    end
  end

  class MessageUsersList
    attr_reader :users, :more

    def initialize(users:, more:)
      @users = users
      @more = more
    end
  end

  class MessageConversationsList
    attr_reader :conversations, :more, :name

    def initialize(conversations:, more:, name:)
      @conversations = conversations
      @more = more
      @name = name
    end
  end

  class MessagesList
    attr_reader :messages, :more, :name, :can_reply

    def initialize(messages:, more:, name:, can_reply:)
      @messages = messages
      @more = more
      @name = name
      @can_reply = can_reply
    end
  end

  module Messages
    @conversation_names = nil
    @conversation_names_time = 0

    class << self
      def conversation_name(client, conversation)
        refresh_conversation_names(client)
        @conversation_names[conversation] || conversation
      end

      def users(client, limit:)
        data = client.api_data("GET", "/api/v1/messages", { "limit" => limit })
        MessageUsersList.new(users: parse_users(data["participants"]), more: truthy?(data["more"]))
      end

      def conversations(client, user:, limit:)
        data = client.api_data("GET", "/api/v1/messages", { "user" => user, "limit" => limit.to_i, "conversations" => "1" })
        parse_conversations(data)
      end

      def special_conversations(client, key)
        data = client.api_data("GET", "/api/v1/messages", { "special" => key.to_s, "limit" => 100 })
        parse_conversations(data)
      end

      def messages(client, user:, subject:, limit:)
        data = client.api_data("GET", "/api/v1/messages", {
          "user" => user,
          "subject" => subject,
          "ignore_subject" => subject == nil ? 1 : 0,
          "limit" => limit.to_s
        })
        parse_messages(client, data, user: user)
      end

      def flagged_messages(client)
        data = client.api_data("GET", "/api/v1/messages", { "flagged" => "1" })
        parse_messages(client, data, user: "")
      end

      def search_messages(client, term)
        data = client.api_data("GET", "/api/v1/messages", { "query" => term })
        parse_messages(client, data, user: "")
      end

      def mark_all_read(client, user: nil)
        params = {}
        params["user"] = user if user != nil
        client.api_data("PATCH", "/api/v1/messages", params)
        true
      end

      def group_users(client, group_id)
        client.api_data("GET", "/api/v1/messages/group/#{group_id.to_s.urlenc}/users")["users"].to_a.map(&:to_s)
      end

      def save_group(client, name:, users:, group_id: nil, addusers: nil)
        if group_id == nil
          client.api_data("POST", "/api/v1/messages/groups", { "name" => name, "users" => users.to_a.join(",") })
        else
          client.api_data("PATCH", "/api/v1/messages/group/#{group_id.to_s.urlenc}", { "name" => name, "add_users" => addusers.to_a.join(",") })
        end
        clear_conversation_names
        true
      end

      def leave_group(client, group_id)
        client.api_data("DELETE", "/api/v1/messages/group/#{group_id.to_s.urlenc}/membership")
        clear_conversation_names
        true
      end

      def mute_group(client, group_id, seconds:)
        until_time = seconds.to_i > 0 ? Time.now.to_i + seconds.to_i : 0
        client.api_data("PUT", "/api/v1/messages/group/#{group_id.to_s.urlenc}/mute", { "until" => until_time })
        true
      end

      def unmute_group(client, group_id)
        client.api_data("DELETE", "/api/v1/messages/group/#{group_id.to_s.urlenc}/mute")
        true
      end

      def delete_user(client, user)
        client.api_data("DELETE", "/api/v1/messages", { "user" => user })
        true
      end

      def delete_conversation(client, user:, subject:)
        client.api_data("DELETE", "/api/v1/messages", { "user" => user, "subject" => subject })
        true
      end

      def delete_message(client, id)
        client.api_data("DELETE", "/api/v1/messages/#{id.to_i}")
        true
      end

      def set_marked(client, id, marked)
        client.api_data("PATCH", "/api/v1/messages/#{id.to_i}", { "marked" => marked ? 1 : 0 })
        true
      end

      def set_protected(client, id, protected_state)
        client.api_data("PATCH", "/api/v1/messages/#{id.to_i}", { "protected" => protected_state ? 1 : 0 })
        true
      end

      def send_text(client, to:, subject:, text:, attachments: [], polls: [], admin: false)
        params = { "to" => to, "subject" => subject }
        attach_payload(client, params, {}, attachments, polls) do |payload|
          payload["text"] = text.to_s
          send_raw(client, params.merge(payload), admin: admin)
        end
      end

      def quick_last_id(client, timeout: Client::DEFAULT_TIMEOUT)
        client.api_data("GET", "/api/v1/messages/quick-read/last-id", nil, timeout: timeout)["id"].to_i
      end

      def quick_message(client, current_id:, direction:, skip_subject: nil, skip_user: nil, timeout: Client::DEFAULT_TIMEOUT)
        segment = direction.to_sym == :next ? "next" : "previous"
        params = {}
        params["skip_subject"] = skip_subject.to_s if skip_subject != nil && skip_subject.to_s != ""
        params["skip_user"] = skip_user.to_s if skip_user != nil && skip_user.to_s != ""
        data = client.api_data("GET", "/api/v1/messages/quick-read/#{current_id.to_i}/#{segment}", params, timeout: timeout)
        return nil unless truthy?(data["found"]) && data["id"].to_i.positive?

        QuickMessage.new(
          id: data["id"],
          sender: utf8(data["sender"]),
          receiver: utf8(data["receiver"]),
          group_name: utf8(data["group_name"]),
          subject: utf8(data["subject"]),
          text: content_text(data, "message"),
          audio_url: content_audio_url(data)
        )
      end

      def send_audio(client, to:, subject:, data:, attachments: [], polls: [])
        params = { "to" => to, "subject" => subject, "audio" => 1, "datasize" => data.bytesize }
        attach_payload(client, params, {}, attachments, polls) do |_payload|
          client.api_binary_data(
            "POST",
            "/api/v1/messages",
            data,
            { "Content-Type" => "application/octet-stream" },
            params
          )
          true
        end
      end

      private

      def refresh_conversation_names(client)
        return if @conversation_names != nil && @conversation_names_time >= Time.now.to_f - 90
        @conversation_names = {}
        payload = client.api_payload("GET", "/api/v1/messages/groups")
        if payload.is_a?(Hash) && Client.truthy?(payload["success"])
          ((payload["data"] || {})["groups"] || []).each do |row|
            @conversation_names[row["id"].to_s] = row["name"].to_s
          end
        end
        @conversation_names_time = Time.now.to_f
      end

      def clear_conversation_names
        @conversation_names_time = 0
      end

      def parse_users(rows)
        rows.to_a.map do |row|
          user = MessageUser.new(utf8(row["user"]))
          user.lastuser = utf8(row["last"])
          user.lastdate = Time.at(row["date"].to_i)
          user.lastsubject = utf8(row["subject"])
          user.read = truthy?(row["read"]) ? 1 : 0
          user.lastid = row["id"].to_i
          user.muted = truthy?(row["muted"])
          user.name = utf8(row["name"])
          user
        end
      end

      def parse_conversations(data)
        conversations = data["conversations"].to_a.map do |row|
          conversation = MessageConversation.new(utf8(row["subject"]))
          conversation.lastuser = utf8(row["last"])
          conversation.lastdate = Time.at(row["date"].to_i)
          conversation.read = truthy?(row["read"]) ? 1 : 0
          conversation.lastid = row["id"].to_i
          conversation
        end
        MessageConversationsList.new(
          conversations: conversations,
          more: truthy?(data["more"]),
          name: utf8(data["name"].to_s)
        )
      end

      def parse_messages(client, data, user:)
        messages = data["messages"].to_a.map do |row|
          message = Message.new(row["id"].to_i)
          message.sender = utf8(row["sender"])
          message.receiver = message.sender == Session.name ? user : Session.name
          message.subject = utf8(row["subject"])
          message.date = Time.at(row["date"].to_i)
          message.mread = truthy?(row["read"]) ? 1 : 0
          message.marked = truthy?(row["marked"]) ? 1 : 0
          message.attachments = row["attachments"].is_a?(Array) ? row["attachments"].map(&:to_s) : row["attachments"].to_s.split(",")
          message.attachments.delete(nil) if message.attachments.size > 0
          message.attachments_names = Attachments.names(client, message.attachments, names: []) if message.attachments.size > 0
          message.protected = truthy?(row["protected"]) ? 1 : 0
          message.polls = row["polls"].is_a?(Array) ? row["polls"].map(&:to_i) : row["polls"].to_s.split(",").map { |id| id.to_i }
          message.polls_names = poll_names(client, message.polls)
          message.text = content_text(row, "message")
          message.audio_url = content_audio_url(row)
          message
        end
        MessagesList.new(
          messages: messages,
          more: truthy?(data["more"]),
          name: utf8(data["name"].to_s),
          can_reply: truthy?(data["can_reply"])
        )
      end

      def poll_names(client, polls)
        polls.map do |id|
          Polls.get(client, id).name
        rescue Error
          ""
        end
      end

      def attach_payload(client, params, post, attachments, polls)
        if attachments != nil && attachments.size > 0
          ids = attachments.map { |file| Attachments.send_file(client, file) }
          post["attachments"] = ids.join(",") if ids.size > 0
        end
        params["polls"] = polls.map { |id| id.to_s }.join(",") if polls != nil && polls.size > 0
        yield(post)
      end

      def send_raw(client, params, admin:)
        params = params.merge("admin" => "1") if admin
        client.api_data("POST", "/api/v1/messages", params)
        true
      end

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end

      def clean(value)
        EltenLink.clean_line(value)
      end

      def utf8(value)
        str = value.to_s.dup
        str.force_encoding(Encoding::UTF_8) if str.encoding != Encoding::UTF_8
        str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      def content_text(row, key)
        utf8(row[key])
      end

      def content_audio_url(row)
        audio = row["audio"]
        return "" unless audio.is_a?(Hash) && audio["url"].to_s != ""

        Client.absolute_api_url(audio["url"])
      end
    end
  end
end
