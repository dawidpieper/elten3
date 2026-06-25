# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

require "json"
require "nokogiri"

module EltenLink
  BlogCategory = Struct.new(:id, :name, :parent, :posts, :url, keyword_init: true)
  BlogPostSummary = Struct.new(:id, :name, :unread, :owner, :audio, :audio_url, :date, :url, :author, :comments, :followed, :categories, :mention, keyword_init: true)
  BlogPostsResult = Struct.new(:posts, :more, keyword_init: true)
  BlogReadEntry = Struct.new(:id, :iseltenuser, :author, :date, :moddate, :audio_url, :excerpt, :text, keyword_init: true)
  BlogReadResult = Struct.new(:entries, :known_posts, :comments_open, :is_elten_blog, keyword_init: true)
  BlogLibraryEntry = Struct.new(:id, :library_user, :lang, :name, :user_description, :description, :url, keyword_init: true)
  BlogManagedEntry = Struct.new(:id, :name, keyword_init: true)
  BlogItem = Struct.new(:id, :name, :cnt_posts, :cnt_comments, :url, :lastpost, :description, :followed, :lang, :owners, :elten, :library, :library_user, keyword_init: true)
  BlogDetails = Struct.new(:name, :description, :url, :library, keyword_init: true)
  BlogDomainInfo = Struct.new(:domain, :suggested, keyword_init: true)
  BlogDomainCheck = Struct.new(:status, :ip, keyword_init: true)
  BlogDomainTargets = Struct.new(:host, :ip, keyword_init: true)
  BlogTag = Struct.new(:id, :name, keyword_init: true)
  BlogPostDetails = Struct.new(:title, :private, :comments, :categories, :tags, :date, :content, :excerpt, keyword_init: true)
  BlogComment = Struct.new(:id, :author, :postname, :content, keyword_init: true)
  BlogFollower = Struct.new(:blog, :blog_name, :user, keyword_init: true)
  BlogMention = Struct.new(:id, :blog, :post, :author, :time, :message, keyword_init: true)
  BlogOptions = Struct.new(:options, :languages, :timezones, keyword_init: true)
  BlogPostFollow = Struct.new(:blog, :post_id, keyword_init: true)

  module Blog
    AUDIO_URL_REGEXP = %r{(https?://[^\s"'<>]+\.(?:opus|ogg|mp3|wav|m4a|aac|flac)(?:\?[^\s"'<>]*)?)}i

    class << self
      def exists?(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/exists")
        truthy?(data["exists"])
      end

      def categories(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/categories")
        Struct.new(:name, :categories, keyword_init: true).new(
          name: data["name"].to_s.empty? ? blog.to_s : data["name"].to_s,
          categories: data["categories"].to_a.map { |row| build_category(row) }
        )
      end

      def create_category(client, blog:, name:)
        data = client.api_data("POST", "/api/v1/blogs/#{blog.to_s.urlenc}/categories", { "name" => name })
        data["id"].to_i
      end

      def rename_category(client, blog:, category_id:, name:)
        client.api_data("PATCH", "/api/v1/blogs/#{blog.to_s.urlenc}/categories/#{category_id.to_i}", { "name" => name })
        true
      end

      def delete_category(client, blog:, category_id:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/categories/#{category_id.to_i}")
        true
      end

      def create_blog(client, name:, shared: false, description: nil)
        data = client.api_data("POST", "/api/v1/blogs", clean_hash(
          "blogname" => name,
          "shared" => truth_param(shared),
          "description" => description
        ))
        data["blog"].to_s
      end

      def list_mentions(client, all: false)
        data = client.api_data("GET", "/api/v1/blogs/mentions", { "all" => truth_param(all) })
        data["mentions"].to_a.map { |row| build_mention(row) }
      end

      def read_mention(client, mention_id:)
        client.api_data("PATCH", "/api/v1/blogs/mention/#{mention_id.to_i}/read")
        true
      end

      def send_mention(client, user:, blog:, post_id:, message:)
        client.api_data("POST", "/api/v1/blogs/mentions", { "user" => user, "blog" => blog, "post" => post_id, "message" => message })
        true
      end

      def posts(client, blog:, category_id: nil, page: nil, search: nil)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/posts", clean_hash(
          "category" => category_id,
          "page" => page,
          "search" => search
        ))
        BlogPostsResult.new(posts: parse_post_summaries(data["posts"]), more: truthy?(data["more"]))
      end

      def create_post(client, blog:, title:, content: nil, excerpt: nil, categories: nil, tags: nil, private: false, comments: true, date: 0)
        data = client.api_data("POST", "/api/v1/blogs/#{blog.to_s.urlenc}/posts", post_payload(
          title: title,
          content: content,
          excerpt: excerpt,
          categories: categories,
          tags: tags,
          private: private,
          comments: comments,
          date: date
        ))
        data["id"].to_i
      end

      def update_post(client, blog:, post_id:, title: nil, content: nil, excerpt: nil, categories: nil, tags: nil, private: nil, comments: nil, date: nil)
        client.api_data("PATCH", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}", post_payload(
          title: title,
          content: content,
          excerpt: excerpt,
          categories: categories,
          tags: tags,
          private: private,
          comments: comments,
          date: date
        ))
        true
      end

      def upload_audio(client, blog:, data:)
        payload = client.api_binary_data(
          "POST",
          "/api/v1/blogs/#{blog.to_s.urlenc}/posts/audio",
          data.to_s.b,
          { "Content-Type" => "application/octet-stream" },
          { "datasize" => data.to_s.b.bytesize }
        )
        audio = payload["audio"]
        return "" unless audio.is_a?(Hash)

        Client.absolute_api_url(audio["url"].to_s)
      end

      def delete_post(client, blog:, post_id:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}")
        true
      end

      def read_post(client, blog:, post_id:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}")
        BlogReadResult.new(
          entries: data["entries"].to_a.map { |row| build_read_entry(row) },
          known_posts: data["known_posts"].to_i,
          comments_open: truthy?(data["comments_open"]),
          is_elten_blog: truthy?(data["is_elten_blog"])
        )
      end

      def create_comment(client, blog:, post_id:, content:)
        client.api_data("POST", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}/comments", { "content" => content })
        true
      end

      def followed_posts(client)
        data = client.api_data("GET", "/api/v1/blogs/post-follows")
        data["posts"].to_a.map { |row| BlogPostFollow.new(blog: row["blog"].to_s, post_id: row["post_id"].to_i) }
      end

      def post_followed?(client, blog:, post_id:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}/follow")
        truthy?(data["followed"])
      end

      def follow_post(client, blog:, post_id:)
        client.api_data("POST", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}/follow")
        true
      end

      def unfollow_post(client, blog:, post_id:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}/follow")
        true
      end

      def add_coworker(client, blog:, user:)
        client.api_data("PUT", "/api/v1/blogs/#{blog.to_s.urlenc}/coworkers/#{user.to_s.urlenc}")
        clear_owners_cache
        true
      end

      def remove_coworker(client, blog:, user:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/coworkers/#{user.to_s.urlenc}")
        clear_owners_cache
        true
      end

      def leave_coworkers(client, blog:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/coworkers/membership")
        clear_owners_cache
        true
      end

      def delete_blog(client, blog:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}")
        true
      end

      def library_list(client)
        data = client.api_data("GET", "/api/v1/blogs/library")
        data["blogs"].to_a.map { |row| build_library_entry(row) }
      end

      def library_add(client, blog:, lang:, description: nil)
        client.api_data("POST", "/api/v1/blogs/library", clean_hash(
          "blog" => blog,
          "lang" => lang,
          "description" => description
        ))
        true
      end

      def library_delete(client, blog:)
        client.api_data("DELETE", "/api/v1/blogs/library/#{blog.to_s.urlenc}")
        true
      end

      def details(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/details")
        BlogDetails.new(name: data["name"].to_s, description: data["description"].to_s, url: data["url"].to_s, library: truthy?(data["library"]))
      end

      def list(client, owner: nil, orderby: nil)
        data = client.api_data("GET", "/api/v1/blogs", clean_hash("user" => owner, "orderby" => orderby))
        data["blogs"].to_a.map { |row| build_blog_item(row) }
      end

      def follow(client, blog:)
        client.api_data("POST", "/api/v1/blogs/follows", { "blog" => blog })
        true
      end

      def unfollow(client, blog:)
        client.api_data("DELETE", "/api/v1/blogs/follow/#{blog.to_s.urlenc}")
        true
      end

      def mark_as_read(client, blog:)
        client.api_data("PATCH", "/api/v1/blogs/#{blog.to_s.urlenc}/read")
        true
      end

      def managed(client)
        data = client.api_data("GET", "/api/v1/blogs/managed")
        data["blogs"].to_a.map { |row| BlogManagedEntry.new(id: row["id"].to_s, name: row["name"].to_s) }
      end

      def profile_get(client)
        client.api_data("GET", "/api/v1/blogs/profile")
      end

      def profile_set(client, profile:)
        client.api_data("PATCH", "/api/v1/blogs/profile", { "profile" => profile })
        true
      end

      def profile_change_password(client, elten_password:, wordpress_password:)
        client.api_data("PATCH", "/api/v1/blogs/profile/password", { "eltenpassword" => elten_password, "wppassword" => wordpress_password })
        true
      end

      def move_post(client, blog:, post_id:, destination:, move_type:)
        client.api_data("POST", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}/move", { "destination" => destination, "movetype" => move_type })
        true
      end

      def domain_info(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/domain")
        BlogDomainInfo.new(domain: data["domain"].to_s, suggested: data["suggested"].to_s)
      end

      def domain_change(client, blog:, domain:)
        client.api_data("PATCH", "/api/v1/blogs/#{blog.to_s.urlenc}/domain", { "domain" => domain })
        true
      end

      def domain_proper_targets(client)
        data = client.api_data("GET", "/api/v1/blogs/domains/proper-targets")
        BlogDomainTargets.new(host: data["host"].to_s, ip: data["ip"].to_s)
      end

      def domain_check(client, domain:)
        data = client.api_data("GET", "/api/v1/blogs/domains/check", { "domain" => domain })
        BlogDomainCheck.new(status: data["status"].to_i, ip: data["ip"].to_s)
      end

      def options_get(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/options")
        BlogOptions.new(options: data["options"] || {}, languages: data["languages"] || {}, timezones: data["timezones"] || {})
      end

      def options_set(client, blog:, options:)
        client.api_data("PATCH", "/api/v1/blogs/#{blog.to_s.urlenc}/options", { "options" => options })
        true
      end

      def tags_list(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/tags")
        data["tags"].to_a.map { |row| BlogTag.new(id: row["id"].to_i, name: row["name"].to_s) }
      end

      def tag_create(client, blog:, name:)
        data = client.api_data("POST", "/api/v1/blogs/#{blog.to_s.urlenc}/tags", { "name" => name })
        data["id"].to_i
      end

      def tag_delete(client, blog:, tag_id:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/tags/#{tag_id.to_i}")
        true
      end

      def post_details(client, blog:, post_id:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/posts/#{post_id.to_i}/details")
        BlogPostDetails.new(
          title: data["title"].to_s,
          private: truthy?(data["private"]),
          comments: truthy?(data["comments"]),
          categories: data["categories"].to_a.map(&:to_i),
          tags: data["tags"].to_a.map(&:to_i),
          date: data["date"].to_i,
          content: data["content"].to_s,
          excerpt: data["excerpt"].to_s
        )
      end

      def comments_list(client, blog:, status: nil)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/comments", clean_hash("status" => status))
        data["comments"].to_a.map { |row| BlogComment.new(id: row["id"].to_i, author: row["author"].to_s, postname: row["post_title"].to_s, content: row["content"].to_s) }
      end

      def comment_assign(client, blog:, comment_id:, status:)
        client.api_data("PATCH", "/api/v1/blogs/#{blog.to_s.urlenc}/comments/#{comment_id.to_i}", { "status" => status })
        true
      end

      def comment_delete(client, blog:, comment_id:)
        client.api_data("DELETE", "/api/v1/blogs/#{blog.to_s.urlenc}/comments/#{comment_id.to_i}")
        true
      end

      def followers(client, blog:)
        data = client.api_data("GET", "/api/v1/blogs/#{blog.to_s.urlenc}/followers")
        build_followers(data["followers"])
      end

      def new_followers(client)
        data = client.api_data("GET", "/api/v1/blogs/followers", { "new" => "1" })
        build_followers(data["followers"])
      end

      def owners(client, blog:)
        if ($blogownerstime || 0) < Time.now.to_i - 10
          data = client.api_data("GET", "/api/v1/blogs/owners")
          $blogowners = {}
          data["owners"].to_a.each do |row|
            blog_id = row["blog"].to_s
            $blogowners[blog_id] ||= []
            $blogowners[blog_id].push(row["user"].to_s)
          end
          $blogowners[blog] = [blog] if $blogowners[blog] == nil && Users.exists?(client, blog)
          $blogownerstime = Time.now.to_i
        end
        result = $blogowners[blog]
        result = [blog] if result == nil && Users.exists?(client, blog)
        result || []
      end

      private

      def build_category(row)
        BlogCategory.new(
          id: row["id"].to_i,
          name: row["name"].to_s,
          parent: row["parent"].to_i,
          posts: row["count"].to_i,
          url: row["url"].to_s
        )
      end

      def build_mention(row)
        BlogMention.new(id: row["id"].to_i, blog: row["blog"].to_s, post: row["post"].to_i, author: row["author"].to_s, time: row["time"].to_i, message: row["message"].to_s)
      end

      def build_read_entry(row)
        text, audio_url = normalize_read_content(row["content"].to_s, row["audio_url"].to_s)
        BlogReadEntry.new(
          id: row["id"].to_i,
          iseltenuser: truthy?(row["elten_user"]),
          author: row["author"].to_s,
          date: row["date"].to_i,
          moddate: row["modified"].to_i,
          audio_url: audio_url,
          excerpt: row["excerpt"].to_s,
          text: text
        )
      end

      def normalize_read_content(content, audio_url)
        text = content.to_s.dup
        audio = audio_url.to_s
        audio = first_audio_url(text) if audio.empty?
        text = strip_audio_content(text, audio)
        [text, audio]
      end

def first_audio_url(text)
  source=text.to_s
  fragment=Nokogiri::HTML.fragment(source)
  html_audio_url(fragment).to_s.tap do |url|
    return url if url!=""
  end
  match=source.match(/\[audio[^\]]*src=["']?([^"'\] ]+)/i) || source.match(AUDIO_URL_REGEXP)
  match ? match[1].to_s : ""
end

def strip_audio_content(text, audio_url)
  fragment=Nokogiri::HTML.fragment(text.to_s)
  audio=audio_url.to_s
  audio=html_audio_url(fragment).to_s if audio==""

  fragment.css("audio").each(&:remove)
  fragment.css("source").each do |node|
    src=node["src"].to_s
    node.remove if node["type"].to_s.match?(/audio/i) || src.match?(AUDIO_URL_REGEXP)
  end
  fragment.css("a[href]").each do |node|
    href=node["href"].to_s
    node.remove if href==audio || href.match?(AUDIO_URL_REGEXP)
  end
  fragment.css("p").each do |node|
    node.remove if node.text.to_s.strip=="" && node.element_children.empty?
  end

  result=fragment.to_html
  result.gsub!(%r{\[audio[^\]]*\].*?\[/audio\]}im, "")
  result.gsub!(%r{\[audio[^\]]*\]}im, "")
  result.gsub!(audio, "") if audio!=""
  result.gsub!(AUDIO_URL_REGEXP, "")
  result.gsub(/[ \t\r\f]+/, " ").gsub(/\n{3,}/, "\n\n").strip
end

def html_audio_url(fragment)
  fragment.css("audio[src]").each do |node|
    url=node["src"].to_s
    return url if url.match?(AUDIO_URL_REGEXP)
  end
  fragment.css("source[src]").each do |node|
    url=node["src"].to_s
    return url if node["type"].to_s.match?(/audio/i) || url.match?(AUDIO_URL_REGEXP)
  end
  fragment.css("a[href]").each do |node|
    url=node["href"].to_s
    return url if url.match?(AUDIO_URL_REGEXP)
  end
  ""
end

      def build_library_entry(row)
        BlogLibraryEntry.new(
          id: row["blog"].to_s,
          library_user: row["user"].to_s,
          lang: row["lang"].to_s,
          name: row["name"].to_s,
          user_description: row["user_description"].to_s,
          description: row["description"].to_s,
          url: row["url"].to_s
        )
      end

      def build_blog_item(row)
        BlogItem.new(
          id: row["id"].to_s,
          name: row["name"].to_s,
          cnt_posts: row["posts"].to_i,
          cnt_comments: row["comments"].to_i,
          url: row["url"].to_s,
          lastpost: row["last_post"].to_i,
          description: row["description"].to_s,
          followed: truthy?(row["followed"]),
          lang: row["language"].to_s,
          owners: row["owners"].to_a.map(&:to_s),
          elten: truthy?(row["elten"]),
          library: truthy?(row["library"]),
          library_user: row["library_user"].to_s
        )
      end

      def build_followers(rows)
        rows.to_a.map do |row|
          blog = row["blog"].to_s
          BlogFollower.new(blog: blog, blog_name: row["blog_name"].to_s.empty? ? blog : row["blog_name"].to_s, user: row["user"].to_s)
        end
      end

      def parse_post_summaries(rows)
        rows.to_a.map do |row|
          BlogPostSummary.new(
            id: row["id"].to_i,
            name: row["title"].to_s,
            unread: truthy?(row["unread"]),
            owner: row["blog"].to_s,
            audio: truthy?(row["audio"]),
            audio_url: row["audio_url"].to_s,
            date: row["date"].to_i,
            url: row["link"].to_s,
            author: row["author"].to_s,
            comments: row["comments"].to_i,
            followed: truthy?(row["followed"]),
            categories: row["categories"].to_a.map(&:to_i),
            mention: row["mention"]
          )
        end
      end

      def post_payload(title: nil, content: nil, excerpt: nil, categories: nil, tags: nil, private: nil, comments: nil, date: nil)
        clean_hash(
          "postname" => title,
          "content" => content,
          "excerpt" => excerpt,
          "categoryid" => csv_value(categories),
          "tags" => csv_value(tags),
          "private" => private.nil? ? nil : truth_param(private),
          "comments" => comments.nil? ? nil : truth_param(comments),
          "date" => date
        )
      end

      def clean_hash(hash)
        hash.each_with_object({}) { |(key, value), result| result[key] = value unless value.nil? }
      end

      def csv_value(value)
        return nil if value.nil?
        return value.map(&:to_s).join(",") if value.is_a?(Array)

        value.to_s
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
