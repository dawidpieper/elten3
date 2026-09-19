require "minitest/autorun"
require "ostruct"
require_relative "../src/eltenlink/error"
require_relative "../src/eapi/notificationgroups"
require_relative "../src/scenes/blog"

class Scene_Main; end
class TableBox
  attr_reader :rows
  def initialize(_columns, rows, **); @rows = rows; end
  def bind_context; end
  def update; end
end
module EltenLink::Blog
  class << self; attr_accessor :requests, :rows, :error; end
  def self.followers(_client, blog:)
    requests << [:all, blog]
    raise error if error
    rows
  end
  def self.new_followers(_client)
    requests << [:new]
    rows
  end
end

class BlogFollowerNotificationTest < Minitest::Test
  def setup
    @helper = Object.new.extend(NotificationGroups)
    def @helper.insert_scene(scene, *args, **options); @opened = scene; end
    EltenLink::Blog.requests = []
    EltenLink::Blog.rows = []
    EltenLink::Blog.error = nil
  end

  def open_notification(payload)
    @helper.action_for("blogfollower", payload).call
    scene = @helper.instance_variable_get(:@opened)
    scene.instance_variable_set(:@alerts, [])
    def scene.elten_link; :client; end
    def scene.p_(_, text); text; end
    def scene._(text); text; end
    def scene.alert(text); @alerts << text; end
    def scene.loop_update; end
    def scene.key_pressed?(key); key == :key_escape; end
    $scene = scene
    scene.main
    scene
  end

  def test_opens_followers_of_exact_blog_not_unread_only_feed
    ["author", "second-blog"].each do |blog|
      EltenLink::Blog.rows = [OpenStruct.new(blog: blog, blog_name: "Name", user: "Alice")]
      scene = open_notification({"blog" => blog})
      assert_equal [:all, blog], EltenLink::Blog.requests.last
      assert_equal [["Alice", "Name"]], scene.instance_variable_get(:@sel).rows
      assert_empty scene.instance_variable_get(:@alerts)
    end
  end

  def test_missing_blog_uses_new_follower_view_and_honest_empty_message
    [nil, {}, {"blog" => ""}].each do |payload|
      scene = open_notification(payload)
      assert_equal [:new], EltenLink::Blog.requests.last
      assert_equal ["No new followers."], scene.instance_variable_get(:@alerts)
      assert_instance_of Scene_Main, $scene
    end
  end

  def test_known_empty_blog_keeps_existing_message
    scene = open_notification({"blog" => "author"})
    assert_equal ["This blog is not followed by any user"], scene.instance_variable_get(:@alerts)
  end

  def test_deleted_or_inaccessible_blog_is_still_an_error
    EltenLink::Blog.error = EltenLink::Error.new(code: "not_found")
    scene = open_notification({"blog" => "deleted"})
    assert_equal ["Error"], scene.instance_variable_get(:@alerts)
    assert_equal [[:all, "deleted"]], EltenLink::Blog.requests
    assert_instance_of Scene_Main, $scene
  end
end
