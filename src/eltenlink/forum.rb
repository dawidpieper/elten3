# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

require "digest"
require "json"

module EltenLink
  class ForumStructure
    attr_reader :groups, :forums, :threads, :ident, :raw_cache, :loaded_at

    def initialize(groups:, forums:, threads:, ident:, raw_cache:, loaded_at: Time.now.to_f)
      @groups = groups
      @forums = forums
      @threads = threads
      @ident = ident
      @raw_cache = raw_cache
      @loaded_at = loaded_at
    end

    def to_h
      { "groups" => @groups, "forums" => @forums, "threads" => @threads }
    end
  end

  ForumThreadPage = Struct.new(:time, :count, :read_posts, :followed, :posts, keyword_init: true)
  ForumThreadStats = Struct.new(:followers, :mentions, :authors, :readers, :readers_below_half, :readers_above_90, :readers_all, keyword_init: true)
  ForumSearchResult = Struct.new(:thread, :count, keyword_init: true)
  ForumMember = Struct.new(:user, :role, :inherit, keyword_init: true)
  ForumTag = Struct.new(:id, :label, :taglist, keyword_init: true)

  module Forum
    class << self
      def structure(client, last_ident: nil, last_cache: nil, old_groups: [], old_forums: [], old_threads: [])
        params = {}
        if last_ident.to_s != "" && last_cache.to_s != ""
          params["ident"] = last_ident.to_s
          params["increment"] = 1
        end
        data = client.api_data("GET", "/api/v1/forum", params)
        cached_data = cached_structure_data(last_cache)
        if truthy?(data["unchanged"])
          data = if cached_data != nil
            cached_data.merge("ident" => data["ident"].to_s.empty? ? last_ident.to_s : data["ident"].to_s)
          else
            client.api_data("GET", "/api/v1/forum")
          end
        elsif truthy?(data["incremental"])
          expanded = expand_incremental_structure(data, cached_data)
          data = expanded || client.api_data("GET", "/api/v1/forum")
        end

        groups = build_groups(data["groups"])
        forums = build_forums(data["forums"], groups)
        threads = build_threads(data["threads"], forums)
        raw_cache_data = raw_structure_data(data)
        raw_cache = JSON.generate(raw_cache_data)
        ident = data["ident"].to_s
        ident = Digest::SHA256.hexdigest(raw_cache)[0, 40] if ident.empty?
        ForumStructure.new(groups: groups, forums: forums, threads: threads, ident: ident, raw_cache: raw_cache)
      end

      def thread(client, thread_id:)
        data = client.api_data("GET", "/api/v1/forum/#{thread_id.to_i}")
        ForumThreadPage.new(
          time: data["time"].to_i,
          count: data["count"].to_i,
          read_posts: data["read_posts"].to_i,
          followed: truthy?(data["followed"]),
          posts: data["posts"].to_a.map { |row| build_post(row) }
        )
      end

      def search(client, query:, type: nil, transcriptions: false)
        data = client.api_data("GET", "/api/v1/forum", clean_hash(
          "query" => query,
          "type" => type,
          "transcriptions" => truth_param(transcriptions)
        ))
        data["results"].to_a.map { |row| ForumSearchResult.new(thread: row["thread"].to_i, count: row["count"].to_i) }
      end

      def popular_threads(client)
        data = client.api_data("GET", "/api/v1/forum", { "popular" => "1" })
        data["threads"].to_a.map { |row| row["thread"].to_i }
      end

      def popular_groups(client)
        []
      end

      def mark_forum_as_read(client, forum:)
        client.api_data("PATCH", "/api/v1/forum", { "forum" => forum })
        true
      end

      def mark_group_as_read(client, group_id:)
        client.api_data("PATCH", "/api/v1/forum", { "group_id" => group_id })
        true
      end

      def follow_thread(client, thread_id:, forum: nil)
        client.api_data("POST", "/api/v1/forum/followed-threads", clean_hash("thread" => thread_id, "forum" => forum))
        true
      end

      def unfollow_thread(client, thread_id:)
        client.api_data("DELETE", "/api/v1/forum/followed-thread/#{thread_id.to_i}", {})
        true
      end

      def follow_forum(client, forum:)
        client.api_data("POST", "/api/v1/forum/followed-forums", { "forum" => forum })
        true
      end

      def unfollow_forum(client, forum:)
        client.api_data("DELETE", "/api/v1/forum/followed-forum/#{forum.to_s.urlenc}", {})
        true
      end

      def thread_stats(client, thread_id:)
        data = client.api_data("GET", "/api/v1/forum/#{thread_id.to_i}/stats")
        ForumThreadStats.new(
          followers: data["followers"].to_i,
          mentions: data["mentions"].to_i,
          authors: data["authors"].to_i,
          readers: data["readers"].to_i,
          readers_below_half: data["readers_below_half"].to_i,
          readers_above_90: data["readers_above_90"].to_i,
          readers_all: data["readers_all"].to_i
        )
      end

      def set_thread_marked(client, thread_id:, marked:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "marked" => truth_param(marked) })
        true
      end

      def move_thread(client, thread_id:, forum:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "forum" => forum })
        true
      end

      def rename_thread(client, thread_id:, name:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "name" => name })
        true
      end

      def delete_thread(client, thread_id:)
        client.api_data("DELETE", "/api/v1/forum/#{thread_id.to_i}", {})
        true
      end

      def set_thread_closed(client, thread_id:, closed:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "closed" => truth_param(closed) })
        true
      end

      def set_thread_pinned(client, thread_id:, pinned:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "pinned" => truth_param(pinned) })
        true
      end

      def offer_thread(client, thread_id:, group_id:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "offered" => group_id })
        true
      end

      def accept_thread_offer(client, thread_id:, forum:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "forum" => forum })
        true
      end

      def refuse_thread_offer(client, thread_id:)
        client.api_data("PATCH", "/api/v1/forum/#{thread_id.to_i}", { "offered" => 0 })
        true
      end

      def create_thread(client, forum:, name:, text:, follow: false, polls: nil, attachments: nil, format: 0)
        data = client.api_data("POST", "/api/v1/forum", clean_hash(
          "forum" => forum,
          "thread_name" => name,
          "text" => text,
          "follow" => truth_param(follow),
          "polls" => csv_value(polls),
          "attachments" => csv_value(attachments),
          "format" => format
        ))
        data["thread"].to_i
      end

      def create_audio_thread(client, forum:, name:, audio:, follow: false)
        data = client.api_binary_data(
          "POST",
          "/api/v1/forum",
          audio.to_s.b,
          { "Content-Type" => "application/octet-stream" },
          clean_hash("forum" => forum, "thread_name" => name, "audio" => 1, "follow" => truth_param(follow))
        )
        data["thread"].to_i
      end

      def create_post(client, thread_id:, text:, attachments: nil, format: 0)
        data = client.api_data("POST", "/api/v1/forum/#{thread_id.to_i}", clean_hash(
          "text" => text,
          "attachments" => csv_value(attachments),
          "format" => format
        ))
        data["id"].to_i
      end

      def create_audio_post(client, thread_id:, audio:)
        data = client.api_binary_data(
          "POST",
          "/api/v1/forum/#{thread_id.to_i}",
          audio.to_s.b,
          { "Content-Type" => "application/octet-stream" },
          { "audio" => 1 }
        )
        data["id"].to_i
      end

      def edit_post(client, post_id:, text:, attachments: nil, format: 0)
        client.api_data("PATCH", "/api/v1/forum/post/#{post_id.to_i}", clean_hash(
          "text" => text,
          "attachments" => csv_value(attachments),
          "format" => format
        ))
        true
      end

      def delete_post(client, post_id:)
        client.api_data("DELETE", "/api/v1/forum/post/#{post_id.to_i}", {})
        true
      end

      def move_post(client, post_id:, thread_id:)
        client.api_data("PATCH", "/api/v1/forum/post/#{post_id.to_i}/move", { "destination_thread" => thread_id })
        true
      end

      def reorder_post(client, post_id:, before_post_id:)
        client.api_data("PATCH", "/api/v1/forum/post/#{post_id.to_i}/move", { "destination_post" => before_post_id.to_i })
        true
      end

      def set_post_locked(client, post_id:, locked:)
        client.api_data("PATCH", "/api/v1/forum/post/#{post_id.to_i}/locked", { "locked" => truth_param(locked) })
        true
      end

      def like_post(client, post_id:)
        client.api_data("PUT", "/api/v1/forum/post/#{post_id.to_i}/like", {})
        true
      end

      def unlike_post(client, post_id:)
        client.api_data("DELETE", "/api/v1/forum/post/#{post_id.to_i}/like", {})
        true
      end

      def post_likes(client, post_id:)
        data = client.api_data("GET", "/api/v1/forum/post/#{post_id.to_i}/likes")
        data["users"].to_a.map(&:to_s)
      end

      def original_post(client, post_id:)
        data = client.api_data("GET", "/api/v1/forum/post/#{post_id.to_i}/original")
        data["original"].to_s
      end

      def report_post(client, post_id:, comment:)
        client.api_data("POST", "/api/v1/forum/post/#{post_id.to_i}/reports", { "comment" => comment })
        true
      end

      def list_bookmarks(client, thread_id: nil)
        data = client.api_data("GET", "/api/v1/forum/bookmarks", clean_hash("thread" => thread_id))
        data["bookmarks"].to_a.map { |row| build_bookmark(row) }
      end

      def create_bookmark(client, thread_id:, post_id:, description:)
        data = client.api_data("POST", "/api/v1/forum/bookmarks", { "thread" => thread_id, "post" => post_id, "description" => description })
        data["id"].to_i
      end

      def delete_bookmark(client, bookmark_id:)
        client.api_data("DELETE", "/api/v1/forum/bookmark/#{bookmark_id.to_i}", {})
        true
      end

      def list_mentions(client, all: false)
        data = client.api_data("GET", "/api/v1/forum/mentions", { "all" => truth_param(all) })
        data["mentions"].to_a.map { |row| build_mention(row) }
      end

      def create_mention(client, user:, thread_id:, post_id:, message:)
        data = client.api_data("POST", "/api/v1/forum/mentions", { "user" => user, "thread" => thread_id, "post" => post_id, "message" => message })
        data["id"].to_i
      end

      def notice_mention(client, mention_id:)
        client.api_data("PATCH", "/api/v1/forum/mention/#{mention_id.to_i}/noticed", {})
        true
      end

      def list_forum_tags(client, forum:)
        data = client.api_data("GET", "/api/v1/forum/forum/#{forum.to_s.urlenc}/tags")
        data["tags"].to_a.map { |row| build_tag(row) }
      end

      def create_forum_tag(client, forum:, label:, taglist:)
        data = client.api_data("POST", "/api/v1/forum/forum/#{forum.to_s.urlenc}/tags", clean_hash(
          "label" => label,
          "taglist" => taglist
        ))
        data["id"].to_i
      end

      def delete_forum_tag(client, forum:, tag_id:)
        client.api_data("DELETE", "/api/v1/forum/forum/#{forum.to_s.urlenc}/tags/#{tag_id.to_i}", {})
        true
      end

      def group_members(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/members")
        data["members"].to_a.map { |row| ForumMember.new(user: row["user"].to_s, role: row["role"].to_i, inherit: truthy?(row["inherit"])) }
      end

      def group_most_active_members(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/most-active-members")
        data["members"].to_a.map { |row| row.is_a?(Hash) ? row["user"].to_s : row.to_s }
      end

      def group_size(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/size")
        [data["audio_size"].to_i, data["attachments_size"].to_i, data["text_size"].to_i]
      end

      def join_group(client, group_id:)
        data = client.api_data("POST", "/api/v1/forum/group/#{group_id.to_i}/membership", {})
        data["role"].to_i
      end

      def leave_group(client, group_id:)
        client.api_data("DELETE", "/api/v1/forum/group/#{group_id.to_i}/membership", {})
        true
      end

      def create_group(client, name:, description:, lang:, public:, open:)
        data = client.api_data("POST", "/api/v1/forum/groups", clean_hash(
          "name" => name,
          "description" => description,
          "lang" => lang,
          "public" => truth_param(public),
          "open" => truth_param(open)
        ))
        data["id"].to_i
      end

      def update_group(client, group_id:, name: nil, description: nil, public: nil, open: nil)
        client.api_data("PATCH", "/api/v1/forum/group/#{group_id.to_i}", clean_hash(
          "name" => name,
          "description" => description,
          "public" => public.nil? ? nil : truth_param(public),
          "open" => open.nil? ? nil : truth_param(open)
        ))
        true
      end

      def delete_group(client, group_id:)
        client.api_data("DELETE", "/api/v1/forum/group/#{group_id.to_i}", {})
        true
      end

      def invite_user(client, group_id:, user:)
        data = client.api_data("POST", "/api/v1/forum/group/#{group_id.to_i}/invitations", { "user" => user })
        data["role"].to_i
      end

      def update_member(client, group_id:, user:, action:, inherit: nil)
        client.api_data("PATCH", "/api/v1/forum/group/#{group_id.to_i}/members/#{user.to_s.urlenc}", clean_hash(
          "action" => action,
          "inherit" => inherit.nil? ? nil : truth_param(inherit)
        ))
        true
      end

      def group_motd(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/motd")
        data["text"].to_s
      end

      def update_group_motd(client, group_id:, text:)
        client.api_data("PATCH", "/api/v1/forum/group/#{group_id.to_i}/motd", { "text" => text })
        true
      end

      def group_regulations(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/regulations")
        data["text"].to_s
      end

      def update_group_regulations(client, group_id:, text:)
        client.api_data("PATCH", "/api/v1/forum/group/#{group_id.to_i}/regulations", { "text" => text })
        true
      end

      def group_reports(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/reports")
        data["reports"].to_a.map { |row| build_report(row) }
      end

      def resolve_report(client, group_id:, report_id:, status:, reason: nil)
        client.api_data("PATCH", "/api/v1/forum/group/#{group_id.to_i}/reports/#{report_id.to_i}", clean_hash(
          "status" => status,
          "reason" => reason
        ))
        true
      end

      def group_log(client, group_id:)
        data = client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/log")
        data["entries"].to_a.map { |row| build_log_entry(row) }
      end

      def get_group_settings(client, group_id:)
        client.api_data("GET", "/api/v1/forum/group/#{group_id.to_i}/settings")
      end

      def update_group_settings(client, group_id:, settings:)
        client.api_data("PATCH", "/api/v1/forum/group/#{group_id.to_i}/settings", settings.to_h)
        true
      end

      def create_forum(client, group_id:, name:, description: nil, type: 0)
        data = client.api_data("POST", "/api/v1/forum/group/#{group_id.to_i}/forums", clean_hash(
          "name" => name,
          "description" => description,
          "type" => type
        ))
        data["id"].to_s
      end

      def update_forum(client, forum:, name: nil, description: nil, type: nil)
        client.api_data("PATCH", "/api/v1/forum/forum/#{forum.to_s.urlenc}", clean_hash(
          "name" => name,
          "description" => description,
          "type" => type
        ))
        true
      end

      def set_forum_closed(client, forum:, closed:)
        client.api_data("PATCH", "/api/v1/forum/forum/#{forum.to_s.urlenc}", { "closed" => truth_param(closed) })
        true
      end

      def move_forum(client, forum:, position:)
        client.api_data("PATCH", "/api/v1/forum/forum/#{forum.to_s.urlenc}", { "position" => position.to_i })
        true
      end

      def delete_forum(client, forum:)
        client.api_data("DELETE", "/api/v1/forum/forum/#{forum.to_s.urlenc}", {})
        true
      end

      private

      def cached_structure_data(raw_cache)
        data = JSON.parse(raw_cache.to_s)
        return nil unless data.is_a?(Hash)
        return nil unless data["groups"].is_a?(Array) && data["forums"].is_a?(Array) && data["threads"].is_a?(Array)

        raw_structure_data(data)
      rescue JSON::ParserError
        nil
      end

      def raw_structure_data(data)
        {
          "groups" => data["groups"].to_a,
          "forums" => data["forums"].to_a,
          "threads" => data["threads"].to_a
        }
      end

      def expand_incremental_structure(data, cached_data)
        return nil if cached_data == nil

        groups = expand_incremental_rows(data["groups"], cached_data["groups"], "id")
        forums = expand_incremental_rows(data["forums"], cached_data["forums"], "id")
        threads = expand_incremental_rows(data["threads"], cached_data["threads"], "id")
        return nil if groups == nil || forums == nil || threads == nil

        {
          "ident" => data["ident"].to_s,
          "groups" => groups,
          "forums" => forums,
          "threads" => threads
        }
      end

      def expand_incremental_rows(rows, old_rows, id_key)
        old_by_id = old_rows.to_a.each_with_object({}) do |row, result|
          result[row[id_key].to_s] = row if row.is_a?(Hash)
        end
        missing = false
        expanded = rows.to_a.map do |row|
          if reference_row?(row)
            cached = old_by_id[row["ref"].to_s]
            missing = true if cached == nil
            cached
          else
            row
          end
        end
        missing ? nil : expanded
      end

      def reference_row?(row)
        row.is_a?(Hash) && row.length == 1 && row.key?("ref")
      end

      def build_groups(rows)
        rows.to_a.map do |row|
          group = Struct_Forum_Group.new(row["id"].to_i)
          group.name = row["name"].to_s
          group.founder = row["founder"].to_s
          group.description = row["description"].to_s
          group.lang = row["lang"].to_s
          group.recommended = truthy?(row["recommended"])
          group.open = truthy?(row["open"])
          group.public = truthy?(row["public"])
          group.role = row["role"].to_i
          group.forums = row["forums"].to_i
          group.threads = row["threads"].to_i
          group.posts = row["posts"].to_i
          group.readposts = row["readposts"].to_i
          group.acmembers = row["acmembers"].to_i
          group.created = row["created"].to_i
          group.hasregulations = truthy?(row["hasregulations"])
          group.hasmotd = truthy?(row["hasmotd"])
          group.hasnewmotd = truthy?(row["hasnewmotd"])
          group.preventpolls = truthy?(row["preventpolls"])
          group.preventattachments = truthy?(row["preventattachments"])
          group.allowpostreporting = truthy?(row["allowpostreporting"])
          group.audiolimit = row["audiolimit"].to_i
          group.blog = row["blog"].to_s
          group.showpostreports = row["showpostreports"].to_i
          group.parent = row["parent"].to_i
          group.applyglobalbans = truthy?(row["applyglobalbans"])
          group.hidden = truthy?(row["hidden"])
          group
        end
      end

      def build_forums(rows, groups)
        group_by_id = groups.each_with_object({}) { |group, result| result[group.id] = group }
        rows.to_a.map do |row|
          forum = Struct_Forum_Forum.new(row["id"].to_s)
          forum.fullname = row["name"].to_s
          forum.type = row["type"].to_i
          forum.group = group_by_id[row["group_id"].to_i] || Struct_Forum_Group.new(0)
          forum.description = row["description"].to_s
          forum.closed = truthy?(row["closed"])
          forum.followed = truthy?(row["followed"])
          forum.threads = row["threads"].to_i
          forum.posts = row["posts"].to_i
          forum.readposts = row["readposts"].to_i
          forum
        end
      end

      def build_threads(rows, forums)
        forum_by_id = forums.each_with_object({}) { |forum, result| result[forum.id] = forum }
        rows.to_a.map do |row|
          thread = Struct_Forum_Thread.new(row["id"].to_i)
          thread.name = row["name"].to_s
          thread.author = row["author"].to_s
          thread.forum = forum_by_id[row["forum"].to_s]
          thread.pinned = truthy?(row["pinned"])
          thread.closed = truthy?(row["closed"])
          thread.followed = truthy?(row["followed"])
          thread.marked = truthy?(row["marked"])
          thread.lastupdate = row["last_update"].to_i
          thread.posts = row["posts"].to_i
          thread.readposts = row["readposts"].to_i
          thread.offered = row["offered"].to_i
          thread
        end
      end

      def build_post(row)
        post = Struct_Forum_Post.new(row["id"].to_i)
        author = row["author"].to_s
        post.author = author.respond_to?(:maintext) ? author.maintext : author
        post.authorname = author.respond_to?(:lore) ? author.lore : ""
        post.post = content_text(row, "text")
        post.signature = row["signature"].to_s
        post.audio_url = content_audio_url(row) if post.respond_to?(:audio_url=)
        post.date = forum_post_date(row["date"])
        post.polls = csv_list(row["polls"]).map(&:to_i)
        post.attachments = csv_list(row["attachments"])
        post.liked = truthy?(row["liked"])
        post.edited = truthy?(row["edited"])
        post.locked = truthy?(row["locked"])
        post.likes = row["likes"].to_i
        post.format = row["format"].to_i
        post.transcription = row["transcription"].to_s
        post
      end

      def forum_post_date(value)
        text = value.to_s
        return "" if text.empty?
        return text unless text.match?(/\A\d+\z/)

        timestamp = text.to_i
        return "" if timestamp <= 0

        format_date(Time.at(timestamp))
      rescue StandardError
        Time.at(timestamp).strftime("%Y-%m-%d %H:%M:%S")
      end

      def build_bookmark(row)
        bookmark = Struct_Forum_Bookmark.new(row["id"].to_i)
        bookmark.description = row["description"].to_s
        bookmark.thread = row["thread"].to_i
        bookmark.post = row["post"].to_i
        bookmark
      end

      def build_mention(row)
        mention = Struct_Forum_Mention.new(row["id"].to_i)
        mention.author = row["author"].to_s
        mention.thread = row["thread"].to_i
        mention.post = row["post"].to_i
        mention.message = row["message"].to_s
        mention.time = Time.at(row["time"].to_i)
        mention
      end

      def build_tag(row)
        ForumTag.new(id: row["id"].to_i, label: row["label"].to_s, taglist: row["taglist"].to_s)
      end

      def build_report(row)
        report = Struct_Forum_Report.new
        report.id = row["id"].to_i
        report.user = row["user"].to_s
        report.thread = row["thread"].to_i
        report.post = row["post"].to_i
        report.postvalue = row["post_value"].to_s
        report.content = row["content"].to_s
        report.creationtime = Time.at(row["creation_time"].to_i) if row["creation_time"].to_i.positive?
        report.solved = truthy?(row["solved"])
        report.status = row["status"].to_i
        report.reason = row["reason"].to_s
        report.solutiontime = Time.at(row["solution_time"].to_i) if row["solution_time"].to_i.positive?
        report
      end

      def build_log_entry(row)
        entry = Struct_Forum_LogEntry.new
        entry.id = row["id"].to_i
        entry.user = row["user"].to_s
        entry.action = row["action"].to_s
        entry.time = row["time"].to_i
        entry.group1 = row["group1"].to_i
        entry.forum1 = row["forum1"].to_s
        entry.thread1 = row["thread1"].to_i
        entry.post1 = row["post1"].to_i
        entry.group2 = row["group2"].to_i
        entry.forum2 = row["forum2"].to_s
        entry.thread2 = row["thread2"].to_i
        entry.post2 = row["post2"].to_i
        entry.oldcontent = row["oldcontent"].to_s
        entry.newcontent = row["newcontent"].to_s
        entry
      end

      def content_text(row, key)
        row[key].to_s
      end

      def content_audio_url(row)
        audio = row["audio"]
        return "" unless audio.is_a?(Hash) && audio["url"].to_s != ""

        Client.absolute_api_url(audio["url"])
      end

      def clean_hash(hash)
        hash.each_with_object({}) { |(key, value), result| result[key] = value unless value.nil? }
      end

      def csv_value(value)
        return nil if value.nil?
        return value.map(&:to_s).reject(&:empty?).join(",") if value.is_a?(Array)

        value.to_s
      end

      def csv_list(value)
        value.to_s.split(",").reject(&:empty?)
      end

      def truth_param(value)
        truthy?(value) ? 1 : 0
      end

      def truthy?(value)
        value == true || value.to_s == "1" || value.to_s.downcase == "true"
      end
    end
  end
end
