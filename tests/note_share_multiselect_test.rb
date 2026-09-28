require "minitest/autorun"
require "ostruct"
require_relative "../src/eltenlink/error"
require_relative "../src/eltenlink/notes"
require_relative "../src/eapi/tasks"
require_relative "../src/scenes/notes"

module Log
  def self.warning(*); end
end
module EltenAPI
  def loop_update
    raise "UI pumped on worker" unless Thread.current == $note_test_owner
    $note_test_pumps += 1
    Thread.pass
  end
end

module EltenLink
  class Client
    class << self; attr_accessor :calls, :existing, :behaviour, :get_error; end
    def initialize(context = nil)
      raise "Worker must not own a UI context" unless context == nil
    end
    def api_data(method, path, params = nil, cancellation_token: nil)
      raise "Network request on UI thread" if Thread.current == $note_test_owner
      self.class.calls << [method, params && params["user"], cancellation_token]
      if method == "GET"
        raise self.class.get_error if self.class.get_error
        return { "users" => self.class.existing.dup }
      end
      user = params.fetch("user")
      outcome = self.class.behaviour[user]
      outcome.call(cancellation_token) if outcome.respond_to?(:call)
      raise outcome if outcome.is_a?(Exception)
      self.class.existing << user
      {}
    end
  end
  module Contacts
    class << self; attr_accessor :values, :error; end
    def self.list(*)
      raise error if error
      values.dup
    end
  end
  module Users
    class << self; attr_accessor :values; end
    def self.search(*); values.dup; end
  end
end

class NoteControl
  def initialize(*); @events = {}; end
  def on(event, &block); @events[event] = block; end
  def trigger(event); @events[event]&.call; end
  def focus
    raise "UI on worker" unless Thread.current == $note_test_owner
  end
end
class Button < NoteControl
  attr_reader :label
  def initialize(label); super(); @label = label; end
end
class ListBox < NoteControl
  module Flags; MultiSelection = 1; end
  attr_reader :options, :selected
  attr_accessor :index
  def initialize(options, **)
    super()
    self.options = options
    @index = 0
  end
  def options=(value)
    raise "UI on worker" unless Thread.current == $note_test_owner
    @options = value
    @selected = Array.new(value.size, false)
  end
  def multiselections; selected.each_index.select { |i| selected[i] }; end
end
class Form
  class << self; attr_accessor :script, :last; end
  attr_accessor :accept_button, :cancel_button, :index
  attr_reader :fields, :resumed, :hidden
  def initialize(fields)
    @fields, @hidden = fields, []
    self.class.last = self
  end
  def hide(field); @hidden << field unless @hidden.include?(field); end
  def show(field); @hidden.delete(field); end
  def resume; @resumed = true; end
  def wait; self.class.script.call(self); end
end
class NoteShareScene < Scene_Notes
  attr_reader :alerts
  attr_accessor :name_input
  def initialize; @alerts = []; end
  def _(text); text; end
  def p_(_, text); text; end
  def alert(text)
    raise "UI on worker" unless Thread.current == $note_test_owner
    @alerts << text
  end
  def input_text(*, **); name_input; end
end

class NoteShareMultiselectTest < Minitest::Test
  def setup
    $note_test_owner = Thread.current
    $note_test_pumps = 0
    EltenLink::Client.calls = []
    EltenLink::Client.existing = ["David"]
    EltenLink::Client.behaviour = {}
    EltenLink::Client.get_error = nil
    EltenLink::Contacts.values = ["Owner", "Alice", "Bob", "ALICE", "David"]
    EltenLink::Contacts.error = nil
    EltenLink::Users.values = []
    Form.last = nil
    @scene = NoteShareScene.new
    @note = EltenLink::Note.new(id: 3, author: "Owner")
    @shares = ["David"]
  end

  def posts; EltenLink::Client.calls.select { |call| call[0] == "POST" }.map { |call| call[1] }; end
  def reject_user
    EltenLink::Error.new(code: "forbidden", response: { "error" => { "status" => 403 } })
  end
  def select_all(form)
    list = form.fields[0]
    list.options.each_index { |i| list.selected[i] = true }
    list.trigger(:multiselection_changed)
  end

  def test_contacts_multiselect_excludes_owner_existing_and_duplicates
    Form.script = proc do |form|
      assert_equal ["Alice", "Bob"], form.fields[0].options
      assert_includes form.hidden, form.accept_button
      select_all(form)
      refute_includes form.hidden, form.accept_button
      form.accept_button.trigger(:press)
      assert form.resumed
    end
    @scene.share(@note, @shares)
    assert_equal ["Alice", "Bob"], posts
    assert_equal ["David", "Alice", "Bob"], @shares
    assert_equal ["Now sharing with Alice, Bob."], @scene.alerts
    assert EltenLink::Client.calls.all? { |c| c[2].is_a?(EltenAPI::Tasks::CancellationToken) }
  end

  def test_partial_failure_keeps_only_failed_selected_and_retry_skips_success
    EltenLink::Client.behaviour["Bob"] = reject_user
    Form.script = proc do |form|
      select_all(form)
      form.accept_button.trigger(:press)
      refute form.resumed
      assert_equal ["Bob"], form.fields[0].options
      assert_equal [0], form.fields[0].multiselections
      assert_equal ["David", "Alice"], @shares
      EltenLink::Client.behaviour.clear
      form.accept_button.trigger(:press)
      assert form.resumed
    end
    @scene.share(@note, @shares)
    assert_equal ["Alice", "Bob", "Bob"], posts
    assert_match(/Could not share with Bob/, @scene.alerts.first)
  end

  def test_unknown_result_is_never_reposted_in_the_same_dialog
    EltenLink::Client.behaviour["Alice"] = EltenLink::Error.timeout
    Form.script = proc do |form|
      select_all(form)
      form.accept_button.trigger(:press)
      assert_equal ["Bob"], form.fields[0].options
      @scene.name_input = "alice"
      EltenLink::Users.values = ["Alice"]
      form.fields[1].trigger(:press)
      assert_match(/Reopen the note/, @scene.alerts.last)
      form.accept_button.trigger(:press)
    end
    @scene.share(@note, @shares)
    assert_equal ["Alice", "Bob"], posts
    assert_equal ["David", "Bob"], @shares
    assert_match(/could not be confirmed for Alice/, @scene.alerts.first)
  end

  def test_successful_server_state_is_rechecked_before_any_retry
    EltenLink::Client.existing << "ALICE"
    result = @scene.share_with_users(@note, ["Alice", "alice", "Owner", "Bob"])
    assert_equal ["Alice", "Bob"], result[:shared]
    assert_equal ["Bob"], posts
  end

  def test_cancelled_write_preserves_completed_shares_and_stops_queue
    EltenLink::Client.behaviour["Bob"] = proc do |token|
      token.cancel
      token.raise_if_cancelled!
    end
    result = @scene.share_with_users(@note, ["Alice", "Bob", "Carol"])
    assert_equal ["Alice"], result[:shared]
    assert_equal ["Bob"], result[:unknown]
    assert_equal ["Alice", "Bob"], posts
  end

  def test_initial_read_failure_never_posts
    EltenLink::Client.get_error = EltenLink::Error.network
    result = @scene.share_with_users(@note, ["Alice", "Bob"])
    assert_equal ["Alice", "Bob"], result[:failed]
    assert_empty result[:unknown]
    assert_empty posts
  end

  def test_add_noncontact_preserves_other_selections_and_canonical_name
    @scene.name_input = " carol "
    EltenLink::Users.values = ["Carol", "Carol2"]
    Form.script = proc do |form|
      form.fields[0].selected[0] = true
      form.fields[1].trigger(:press)
      assert_equal ["Alice", "Bob", "Carol"], form.fields[0].options
      assert_equal [0, 2], form.fields[0].multiselections
      form.fields[1].trigger(:press)
      assert_equal 3, form.fields[0].options.size
      form.accept_button.trigger(:press)
    end
    @scene.share(@note, @shares)
    assert_equal ["Alice", "Carol"], posts
  end

  def test_cancel_empty_selection_and_invalid_other_user_do_not_share
    Form.script = proc do |form|
      form.accept_button.trigger(:press)
      refute form.resumed
      @scene.name_input = "Unknown"
      form.fields[1].trigger(:press)
      assert_equal "The user cannot be found", @scene.alerts.last
      @scene.name_input = nil
      form.fields[1].trigger(:press)
      form.cancel_button.trigger(:press)
      assert form.resumed
    end
    @scene.share(@note, @shares)
    assert_empty posts
    assert_equal ["David"], @shares
  end

  def test_cancelled_contact_load_does_not_open_dialog_or_report_error
    EltenLink::Contacts.error = EltenLink::Error.cancelled
    @scene.share(@note, @shares)
    assert_nil Form.last
    assert_empty @scene.alerts
    assert_empty posts
  end

  def test_slow_network_work_keeps_owner_pumping
    EltenLink::Client.behaviour["Alice"] = proc { |token| token.sleep(0.02) }
    result = @scene.share_with_users(@note, ["Alice"])
    assert_equal ["Alice"], result[:shared]
    assert_operator $note_test_pumps, :>, 0
  end
end
