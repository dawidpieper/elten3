require "minitest/autorun"
require "ostruct"
require_relative "../src/eltenlink/error"
require_relative "../src/scenes/forum"

class Scene_Main; end
module Session
  def self.logged?; true; end
end
module Log
  def self.error(*); end
end
module EltenLink::Forum
  class << self; attr_accessor :error, :structure_result, :page; end
  def self.structure(*, **); raise error if error; structure_result; end
  def self.thread(*, **); raise error if error; page; end
  def self.list_mentions(*, **); raise error if error; []; end
  def self.popular_threads(*); raise error if error; []; end
end
module EltenLink
  def self.client(*); :client; end
end
module ForumTestContext
  def alerts; @alerts ||= []; end
  def alert(text); alerts << text; end
  def _(text); text; end
  def p_(_, text); text; end
  def elten_link; :client; end
end
Scene_Forum.include(ForumTestContext)
Scene_Forum.extend(ForumTestContext)
Scene_Forum_Thread.include(ForumTestContext)

class ForumLoadCancellationTest < Minitest::Test
  def setup
    Scene_Forum.alerts.clear
    @old = OpenStruct.new(groups: [:group], forums: [:forum], threads: [:thread],
      raw_cache: "cached", ident: "old", loaded_at: 10)
    EltenLink::Forum.error = nil
    EltenLink::Forum.structure_result = @old
    Scene_Forum.getcache(:client)
    @scene = Scene_Forum.allocate
    @scene.getcache
    EltenLink::Forum.error = EltenLink::Error.cancelled
  end

  def test_cancelled_cache_load_keeps_all_previous_data
    refute @scene.getcache
    assert_same @old.threads, @scene.instance_variable_get(:@threads)
    assert_same @old.threads, Scene_Forum.getstruct["threads"]
    assert_equal "cached", Scene_Forum.class_variable_get(:@@lastCache)
    assert_equal "old", Scene_Forum.class_variable_get(:@@lastCacheIdent)
    assert_empty Scene_Forum.alerts
  end

  def test_initial_load_returns_to_parent_without_error
    parent = Object.new
    @scene.instance_variable_set(:@return_scene, parent)
    $scene = @scene
    @scene.main
    assert_same parent, $scene
    assert_empty Scene_Forum.alerts
  end

  def test_notification_cancel_does_not_claim_thread_was_deleted
    parent = Object.new
    thread = Scene_Forum_Thread.new(123, nil, 0, "", nil, parent)
    thread.main
    assert_same parent, $scene
    assert_empty thread.alerts
    assert_empty Scene_Forum.alerts
  end

  def test_new_scene_can_still_read_existing_cache_after_cancellation
    fresh_scene = Scene_Forum.allocate
    assert_same @old.threads, fresh_scene.getstruct["threads"]
    assert_empty fresh_scene.alerts
  end

  def test_cancelled_post_load_returns_to_supplied_parent
    parent = Object.new
    group = OpenStruct.new(role: 1, open: true)
    record = OpenStruct.new(id: 123, closed: false, forum: OpenStruct.new(group: group))
    thread = Scene_Forum_Thread.new(record, nil, 0, "", nil, parent)
    thread.main
    assert_same parent, $scene
    assert_empty thread.alerts
  end

  def test_refresh_keeps_form_position_and_reply_without_further_requests
    thread = Scene_Forum_Thread.allocate
    old_form = OpenStruct.new(index: 7)
    old_posts = [:post]
    thread.instance_variable_set(:@form, old_form)
    thread.instance_variable_set(:@textfields, [OpenStruct.new(text: "Draft")])
    thread.instance_variable_set(:@posts, old_posts)
    thread.refresh
    assert_same old_form, thread.instance_variable_get(:@form)
    assert_equal 7, old_form.index
    assert_same old_posts, thread.instance_variable_get(:@posts)
    assert_empty thread.alerts
  end

  def test_helper_cancellation_is_silent_but_failure_is_reported
    assert_equal :keep, @scene.forum_fetch(:keep) { raise EltenLink::Error.cancelled }
    assert_empty @scene.alerts
    assert_equal :keep, @scene.forum_fetch(:keep) { raise EltenLink::Error.timeout }
    assert_equal ["Error"], @scene.alerts
  end

  def test_real_cache_failure_keeps_data_but_is_not_silent
    EltenLink::Forum.error = EltenLink::Error.timeout
    refute @scene.getcache
    assert_equal ["Error"], Scene_Forum.alerts
    assert_same @old.threads, @scene.instance_variable_get(:@threads)
  end

  def test_special_thread_list_cancel_keeps_current_list
    old_list = OpenStruct.new(index: 3)
    @scene.instance_variable_set(:@thrsel, old_list)
    @scene.instance_variable_set(:@sthreads, [:old_thread])
    [-7, -8, -11].each do |id|
      @scene.threadsmain(id)
      assert_same old_list, @scene.instance_variable_get(:@thrsel)
      assert_equal [:old_thread], @scene.instance_variable_get(:@sthreads)
    end
  end

  def test_success_updates_cache_and_missing_thread_is_still_reported
    EltenLink::Forum.error = nil
    EltenLink::Forum.structure_result = OpenStruct.new(groups: [], forums: [], threads: [],
      raw_cache: "fresh", ident: "new", loaded_at: 20)
    assert @scene.getcache
    assert_empty @scene.instance_variable_get(:@threads)
    thread = Scene_Forum_Thread.new(123)
    thread.main
    assert_match(/unavailable/, thread.alerts.first)
  end
end
