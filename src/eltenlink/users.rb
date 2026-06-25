# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  UserStatus = Struct.new(:text, :online, :sponsor, keyword_init: true)

  module Users
    @status_time = 0
    @status_users = []
    @status_texts = []
    @online = []
    @sponsors = []

    class << self
      def status(client, name, online: true, sponsor: true)
        status_info(client, name, online: online, sponsor: sponsor).text
      end

      def status_info(client, name, online: true, sponsor: true)
        refresh_status_cache(client) if Time.now.to_i - 15 > @status_time
        return UserStatus.new(text: "", online: false, sponsor: false) if @status_users == nil || @online == nil
        text = ""
        @status_users.each_with_index do |user, index|
          text = @status_texts[index] if name == user
        end
        UserStatus.new(
          text: text,
          online: online && @online.include?(name),
          sponsor: sponsor && @sponsors.include?(name)
        )
      end

      def set_status(client, text)
        client.api_data("PATCH", "/api/v1/users/me/status", { "text" => text })
        true
      end

      def info(client, user, stateonly: false)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}", { "stateonly" => bool_int(stateonly) })
        response = [
          "0\r\n",
          "#{int_value(data["last_seen"])}\r\n",
          "#{bool_int(data["has_blog"])}\r\n",
          "#{int_value(data["knows"])}\r\n",
          "#{int_value(data["known_by"])}\r\n",
          "#{data["version"]}\r\n",
          "#{int_value(data["registered"])}\r\n",
          "#{int_value(data["polls"])}\r\n",
          "#{int_value(data["forum_posts"])}\r\n",
          "#{bool_int(data["in_contacts"])}\r\n",
          "#{bool_int(data["has_avatar"])}\r\n",
          "#{bool_int(data["banned"])}\r\n",
          "#{int_value(data["honors"])}\r\n",
          "#{bool_int(data["callable"])}\r\n",
          "#{bool_int(data["feed_followed"])}\r\n",
          "#{bool_int(data["monitored"])}\r\n",
          "#{bool_int(data["archived"])}\r\n"
        ]
        parse_info(response)
      end

      def exists?(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/exists")
        bool_value(data["exists"])
      end

      def signature(client, user)
        data = client.api_data("GET", "/api/v1/users/#{user.to_s.urlenc}/signature")
        data["signature"].to_s
      end

      def set_signature(client, text)
        client.api_data("PATCH", "/api/v1/users/me/signature", { "text" => text })
        true
      end

      def banned?(client, user)
        payload = client.api_payload("GET", "/api/v1/users/#{user.to_s.urlenc}/ban")
        return false unless payload.is_a?(Hash) && Client.truthy?(payload["success"])
        bool_value((payload["data"] || {})["banned"])
      end

      def search(client, query)
        data = client.api_data("GET", "/api/v1/users/search", { "query" => query })
        data["users"].to_a.map(&:to_s)
      end

      def list(client)
        users = client.api_data("GET", "/api/v1/users")["users"].to_a.map(&:to_s)
        users.polsort!
        users
      end

      def online(client, period: nil)
        params = {}
        params["period"] = period if period != nil
        users = client.api_data("GET", "/api/v1/users/online", params)["users"].to_a.map(&:to_s)
        users.polsort!
        users
      end

      def recently_registered(client, limit: nil)
        params = {}
        params["limit"] = limit if limit != nil
        users = client.api_data("GET", "/api/v1/users/recently-registered", params)["users"].to_a.map(&:to_s)
        limit == nil ? users : users[0...limit.to_i]
      end

      def recently_active(client)
        online(client, period: "86400")
      end

      private

      def refresh_status_cache(client)
        @status_time = Time.now.to_i
        statuses = client.api_data("GET", "/api/v1/users/statuses")["statuses"].to_a
        online = client.api_data("GET", "/api/v1/users/online")["users"].to_a
        sponsors = client.api_data("GET", "/api/v1/admins", { "category" => "sponsors" })["users"].to_a

        @online = online.map(&:to_s).select { |line| line.size > 0 }
        @sponsors = sponsors.map(&:to_s)
        @status_users = []
        @status_texts = []
        statuses.each_with_index do |row, index|
          @status_users[index] = row["name"].to_s
          @status_texts[index] = row["status"].to_s
        end
      end

      def bool_value(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end

      def int_value(value)
        return 0 if value == false || value == nil
        value.to_i
      end

      def bool_int(value)
        bool_value(value) ? 1 : 0
      end

      def parse_statuses(statuses)
        @status_users = []
        @status_texts = []
        index = 0
        line = 1
        user_line = true
        while line < statuses.size
          if user_line
            @status_users[index] = statuses[line]
            user_line = false
          elsif !EltenLink.legacy_end?(statuses[line])
            @status_texts[index] ||= ""
            @status_texts[index] += statuses[line]
          else
            index += 1
            user_line = true
          end
          line += 1
        end
      end

      def parse_info(lines)
        info = []
        if lines[1].to_i > 1_000_000_000 && lines[1].to_i < 2_000_000_000
          info[0] = format_info_date(Time.at(lines[1].to_i))
        else
          info[0] = ""
        end
        info[1] = lines[2].to_b
        info[2] = lines[3].to_i
        info[3] = lines[4].to_i
        info[4] = lines[8].to_i
        info[5] = EltenLink.clean_line(lines[5])
        info[6] = lines[6].to_i == 0 || lines[6] == nil ? "" : format_info_date(Time.at(lines[6].to_i))
        info[7] = lines[7]
        info[8] = lines[9].to_b
        info[9] = lines[10].to_b
        info[10] = lines[11].to_b
        info[11] = lines[12].to_i
        info[12] = lines[13].to_b
        info[13] = lines[14].to_b
        info[14] = lines[15].to_b
        info[15] = lines[16].to_b
        info
      end

      def format_info_date(time)
        if Object.respond_to?(:format_date)
          Object.__send__(:format_date, time, false, false)
        else
          time.strftime("%Y-%m-%d")
        end
      end
    end
  end
end
