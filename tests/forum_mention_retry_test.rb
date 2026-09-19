require "minitest/autorun"
require_relative "../src/eltenlink/error"
require_relative "../src/scenes/forum"

# Only the controls and network boundary are replaced; mention and its error
# handler are loaded from the production scene.
class Button
  def initialize(*)
    @events = {}
  end
  def on(event, &block); @events[event] = block; end
  def press; @events.fetch(:press).call; end
end
class ListBox < Button
  module Flags
    MultiSelection = 1
  end
  attr_accessor :multiselections
  def initialize(*)
    super
    @multiselections = []
  end
end
class EditBox < Button
  attr_accessor :text
  def initialize(*args, text:, **)
    super(*args)
    @text = text
  end
end
class Form
  class << self; attr_accessor :scenario; end
  attr_accessor :accept_button, :cancel_button
  attr_reader :resume_count, :fields
  def initialize(fields)
    @fields, @resume_count = fields, 0
  end
  def hide(*); end
  def show(*); end
  def resume; @resume_count += 1; end
  def wait; self.class.scenario.call(self); end
end
module EltenLink::Contacts
  def self.added_me(*); ["Alice", "Bob"]; end
end
module EltenLink::Forum
  class << self; attr_accessor :error, :requests; end
  def self.create_mentions(_client, **request)
    self.requests << request
    raise error if error
  end
end

class ForumMentionRetryTest < Minitest::Test
  def setup
    @scene = Scene_Forum_Thread.allocate
    def @scene.p_(_context, text); text; end
    def @scene._(text); text; end
    def @scene.np_(_context, one, many, count); count == 1 ? one : many; end
    def @scene.elten_link; :client; end
    def @scene.alert(*); end
    def @scene.log_forum_error(*); end
    EltenLink::Forum.requests = []
    EltenLink::Forum.error = nil
  end

  def test_failure_preserves_draft_and_selection_then_success_closes
    Form.scenario = lambda do |form|
      users, message = form.fields
      users.multiselections = [0, 1]
      message.text = "A draft worth keeping"
      EltenLink::Forum.error = EltenLink::Error.new(code: "access_denied")
      form.accept_button.press
      assert_equal 0, form.resume_count
      assert_equal [0, 1], users.multiselections
      assert_equal "A draft worth keeping", message.text
      assert_equal 1, EltenLink::Forum.requests.size # no automatic retry
      users.multiselections = [0]
      EltenLink::Forum.error = nil
      form.accept_button.press
      assert_equal 1, form.resume_count
      assert_equal ["Alice"], EltenLink::Forum.requests.last[:users]
      assert_equal message.text, EltenLink::Forum.requests.last[:message]
    end
    @scene.mention(123, 456)
  end

  def test_no_selection_does_not_send_and_cancel_always_exits
    Form.scenario = lambda do |form|
      form.accept_button.press
      assert_empty EltenLink::Forum.requests
      assert_equal 0, form.resume_count
      form.cancel_button.press
      assert_equal 1, form.resume_count
    end
    @scene.mention(123, 456)
  end
end
