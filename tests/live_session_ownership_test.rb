# Run with: ruby tests/live_session_ownership_test.rb
# Contract-level client tests. No connection to a running Elten or server.
require "minitest/autorun"
require_relative "../src/eltenlink/error"
require_relative "../src/eltenlink/client"
require_relative "../src/eltenlink/apps"
require_relative "../src/eapi/tasks"
require_relative "../src/eapi/live_sessions"

class LiveSessionOwnershipTest < Minitest::Test
  LS = EltenAPI::LiveSessions

  class Client
    attr_accessor :handler
    attr_reader :calls, :threads

    def initialize
      @calls, @threads = [], []
    end

    def e_json_request(method, path, params, cancellation_token: nil)
      @threads << Thread.current
      @calls << [method, URI.parse(path).path, params]
      response = @handler.call(params)
      yield JSON.generate(response), nil if response
    end

    def api_data(method, path, params, **)
      @calls << [method, path, params]
      {}
    end
  end

  # Pump the actual request queue without Elten's UI or unrelated control RPCs.
  class Endpoint < LS::Endpoint
    attr_accessor :before_pump

    def wait_step(cancellation_token: nil)
      cancellation_token&.raise_if_cancelled!
      @before_pump&.call
      __send__(:tick_stack_requests)
      Thread.pass
      cancellation_token&.raise_if_cancelled!
    end
  end

  def setup
    @client = Client.new
    @endpoint = Endpoint.new(app_id: "12345678-1234-4123-8123-123456789abc", client: @client, user: "alice", token: "test-only")
    @session = @endpoint.__send__(:store_session, snapshot)
    @client.handler = ->(params) { { "success" => true, "data" => confirmation(params) } }
  end

  def teardown
    @endpoint.close
    LS.unregister(@endpoint)
    @client.threads.uniq.each { |thread| thread.join(1) }
    assert @client.threads.all? { |thread| !thread.alive? }, "request worker leaked"
  end

  def snapshot(owner: "a", revision: 1, local: "a", members: %w[a b c], capability: true)
    {
      "id" => "room-1", "participant_id" => local, "owner_id" => owner,
      "revision" => revision, "capacity" => 4, "metadata" => { "game" => "example" },
      "limits" => { "ownership_transfer" => capability },
      "participants" => members.map { |id| { "id" => id, "user" => { "a" => "alice", "b" => "bob", "c" => "carol" }[id] } }
    }
  end

  def successor
    @session.participant("b")
  end

  def confirmation(params)
    snapshot(owner: params.fetch("new_owner_id"), revision: 2,
      members: params["leave"] ? %w[b c] : %w[a b c]).merge(
      "request_id" => params.fetch("request_id"), "previous_owner_id" => "a", "left" => params.fetch("leave"))
  end

  def owner_event(id, seq)
    { "type" => "owner_changed", "seq" => seq, "owner_id" => id,
      "owner" => { "id" => id, "user" => id == "b" ? "bob" : "carol", "metadata" => { "role" => "player" } } }
  end

  def envelope(owner: "b", revision: 2, events: [], members: %w[a b c])
    snapshot(owner: owner, revision: revision, members: members).merge("events" => events,
      "cursor" => events.map { |event| event.fetch("seq") }.max || 0)
  end

  def test_transfer_waits_for_confirmation_and_keeps_membership
    @client.handler = lambda do |params|
      assert @session.owner?, "must not optimistically change owner"
      { "success" => true, "data" => confirmation(params) }
    end
    assert @session.ownership_transfer?
    assert @session.transfer_ownership(successor)
    refute @session.owner?
    assert_equal "bob", @session.owner.user
    refute @session.closed?
    assert_equal %w[a b c], @session.participants.map(&:id)
    method, path, params = @client.calls.fetch(0)
    assert_equal ["POST", "/api/v1/apps/live-sessions/room-1/ownership"], [method, path]
    assert_equal "a", params["participant_id"]
    assert_equal "b", params["new_owner_id"]
    assert_equal false, params["leave"]
    assert_match(/\A[\da-f-]{36}\z/, params["request_id"])
    refute_equal Thread.current, @client.threads.fetch(0)
    assert_empty @endpoint.instance_variable_get(:@departures)
  end

  def test_atomic_transfer_and_leave_sends_no_second_departure
    closed = []
    @session.on_closed { |reason| closed << reason }
    assert @session.transfer_ownership(successor, leave: true)
    assert @session.closed?
    assert_equal "b", @session.owner_id
    assert_equal %w[b c], @session.participants.map(&:id)
    assert_equal 1, @client.calls.length
    assert_equal true, @client.calls[0][2]["leave"]
    assert_empty @endpoint.instance_variable_get(:@departures)
    @endpoint.dispatch_events
    assert_equal [:left], closed
  end

  def test_unsupported_server_does_not_send_anything
    [nil, false, "true"].each do |flag|
      @session.__send__(:apply_snapshot, snapshot(capability: flag))
      refute @session.ownership_transfer?
      assert_raises(LS::OwnershipTransferUnsupported) { @session.transfer_ownership(successor, leave: true) }
      refute @session.closed?
    end
    assert_empty @client.calls
  end

  def test_only_current_owner_can_transfer
    @session.__send__(:apply_snapshot, snapshot(owner: "b", revision: 2))
    assert_raises(LS::NotOwner) { @session.transfer_ownership(@session.participant("c")) }
    assert_empty @client.calls
  end

  def test_successor_must_be_same_session_participant_not_name_id_or_copy
    another = LS::Session.new(@endpoint, snapshot.merge("id" => "room-2"))
    [nil, "b", @session.owner, LS::Participant.new("id" => "b"), another.participant("b")].each do |target|
      assert_raises(ArgumentError) { @session.transfer_ownership(target) }
    end
    assert_empty @client.calls
  end

  def test_closed_session_and_invalid_leave_are_rejected
    target = successor
    assert_raises(ArgumentError) { @session.transfer_ownership(target, leave: "true") }
    @session.close_local(:closed, confirmed: true)
    assert_raises(LS::SessionClosed) { @session.transfer_ownership(target) }
    assert_empty @client.calls
  end

  def test_successor_who_left_while_queued_is_rejected_before_send
    @endpoint.before_pump = -> { @session.__send__(:apply_snapshot, snapshot(revision: 2, members: %w[a c])) }
    assert_raises(ArgumentError) { @session.transfer_ownership(successor, leave: true) }
    assert_empty @client.calls
    refute @session.closed?
  end

  def test_owner_change_while_queued_is_rejected_before_send
    @endpoint.before_pump = -> { @session.__send__(:apply_snapshot, snapshot(owner: "c", revision: 2)) }
    assert_raises(LS::NotOwner) { @session.transfer_ownership(successor) }
    assert_empty @client.calls
  end

  def test_server_rejection_and_retryable_error_never_retry_or_close
    ["apps.live_sessions.not_owner", "apps.live_sessions.participant_not_found", "rate_limits.exceeded", "timeout"].each do |code|
      @client.handler = ->(_) { { "success" => false, "error" => { "code" => code } } }
      error = assert_raises(EltenLink::Error) { @session.transfer_ownership(successor, leave: true) }
      assert_equal code, error.code
      assert @session.owner?
      refute @session.closed?
    end
    assert_equal 4, @client.calls.length
    assert_empty @endpoint.instance_variable_get(:@departures)
  end

  def test_confirmation_is_checked_before_changing_local_state
    mutations = [
      ->(data) { data["id"] = "wrong-room" },
      ->(data) { data["participant_id"] = "c" },
      ->(data) { data["previous_owner_id"] = "c" },
      ->(data) { data["owner_id"] = "c" },
      ->(data) { data["request_id"] = "wrong-request" },
      ->(data) { data["left"] = true },
      ->(data) { data.delete("revision") },
      ->(data) { data["participants"] = [] },
      ->(data) { data["participants"] << data["participants"].first }
    ]
    mutations.each do |mutate|
      @client.handler = lambda do |params|
        data = confirmation(params)
        mutate.call(data)
        { "success" => true, "data" => data }
      end
      error = assert_raises(EltenLink::Error) { @session.transfer_ownership(successor) }
      assert_equal "invalid_json", error.code
      assert @session.owner?
      refute @session.closed?
    end
  end

  def test_unconfirmed_departure_does_not_close_locally
    @client.handler = lambda do |params|
      { "success" => true, "data" => confirmation(params).merge("left" => false) }
    end
    assert_raises(EltenLink::Error) { @session.transfer_ownership(successor, leave: true) }
    refute @session.closed?
    assert_empty @endpoint.instance_variable_get(:@departures)
  end

  def test_departure_receipt_must_exclude_the_old_membership
    @client.handler = lambda do |params|
      data = confirmation(params)
      data["participants"] = snapshot["participants"]
      { "success" => true, "data" => data }
    end
    assert_raises(EltenLink::Error) { @session.transfer_ownership(successor, leave: true) }
    refute @session.closed?
    assert @session.owner?
    assert_empty @endpoint.instance_variable_get(:@departures)
  end

  def test_invalid_timeout_never_sends_a_request
    [0, -1, Float::NAN, Float::INFINITY].each do |timeout|
      assert_raises(ArgumentError) { @session.transfer_ownership(successor, timeout: timeout) }
    end
    assert_empty @client.calls
  end

  def test_timeout_keeps_membership_and_late_confirmation_is_not_replayed
    late = nil
    @client.handler = ->(params) { late = confirmation(params); nil }
    assert_raises(LS::TimeoutError) { @session.transfer_ownership(successor, leave: true, timeout: 0.05) }
    refute_nil late
    refute @session.closed?
    assert @session.owner?
    assert_equal 1, @client.calls.length
    assert_empty @endpoint.instance_variable_get(:@departures)
    # Normal recovery can still reveal a committed ownership change.
    @session.apply_envelope(envelope(events: [owner_event("b", 1)], members: %w[b c]))
    assert_equal "b", @session.owner_id
  end

  def test_cancellation_before_submission
    token = EltenAPI::Tasks::CancellationToken.new
    token.cancel
    assert_raises(EltenAPI::Tasks::Cancelled) { @session.transfer_ownership(successor, leave: true, cancellation_token: token) }
    assert_empty @client.calls
    refute @session.closed?
  end

  def test_cancellation_after_submission_does_not_depart
    token = EltenAPI::Tasks::CancellationToken.new
    @client.handler = ->(_) { token.cancel; nil }
    assert_raises(EltenAPI::Tasks::Cancelled) { @session.transfer_ownership(successor, leave: true, cancellation_token: token) }
    assert_equal 1, @client.calls.length
    refute @session.closed?
    assert_empty @endpoint.instance_variable_get(:@departures)
  end

  def test_owner_callback_uses_ordered_deduplicated_events_not_snapshots
    changes = []
    @session.on_owner_changed { |owner| changes << owner }
    @session.transfer_ownership(successor)
    @endpoint.dispatch_events
    assert_empty changes, "HTTP confirmation must not duplicate the stream event"
    update = envelope(events: [owner_event("b", 1)])
    2.times { @session.apply_envelope(update) }
    @endpoint.dispatch_events
    assert_equal ["b"], changes.map(&:id)
    assert changes[0].frozen?
    assert changes[0].metadata.frozen?
    assert_raises(FrozenError) { changes[0].update("id" => "c") }
    assert_equal "b", @session.owner_id
  end

  def test_backlog_does_not_roll_back_current_owner
    changes = []
    @session.on_owner_changed { |owner| changes << owner.id }
    @session.apply_envelope(envelope(owner: "c", revision: 3, events: []))
    @session.apply_envelope(envelope(owner: "b", revision: 2, events: [owner_event("b", 1)]))
    @session.apply_envelope(envelope(owner: "c", revision: 3, events: [owner_event("c", 2)]))
    @endpoint.dispatch_events
    assert_equal %w[b c], changes
    assert_equal "c", @session.owner_id
  end

  def test_malformed_owner_event_is_not_acknowledged
    event = owner_event("b", 1)
    event["owner"]["id"] = "c"
    changes = []
    @session.on_owner_changed { |owner| changes << owner }
    error = assert_raises(EltenLink::Error) { @session.apply_envelope(envelope(events: [event])) }
    assert_equal "invalid_json", error.code
    assert_equal 0, @session.control_entry["ack"]
    @endpoint.dispatch_events
    assert_empty changes
  end

  def test_gap_recovers_current_owner_without_fabricating_events
    changes, gaps = [], []
    @session.on_owner_changed { |owner| changes << owner.id }
    @session.on_gap { |from, to| gaps << [from, to] }
    @session.apply_envelope(envelope(owner: "c", revision: 9,
      events: [{ "type" => "gap", "seq" => 8, "from" => 1, "to" => 7 }]))
    @endpoint.dispatch_events
    assert_equal "c", @session.owner_id
    assert_empty changes
    assert_equal [[1, 7]], gaps
  end

  def test_event_keeps_owner_identity_after_later_departure
    changes, order = [], []
    @session.on_owner_changed { |owner| changes << owner.user; order << :owner }
    @session.on_participant_left { |*| order << :left }
    @session.apply_envelope(envelope(owner: "c", revision: 4, members: %w[a c], events: [
      owner_event("b", 1), { "type" => "participant_left", "seq" => 2, "participant" => { "id" => "b" } }
    ]))
    @endpoint.dispatch_events
    assert_equal ["bob"], changes
    assert_equal [:owner, :left], order
    assert_equal "c", @session.owner_id
  end

  def test_new_owner_sees_privileges_before_callback
    @session.__send__(:apply_snapshot, snapshot(local: "b"))
    roles = []
    @session.on_owner_changed { |_| roles << @session.owner? }
    update = envelope(events: [owner_event("b", 1)]).merge("participant_id" => "b")
    @session.apply_envelope(update)
    @endpoint.dispatch_events
    assert_equal [true], roles
  end

  def test_application_message_cannot_transfer_ownership
    changes, messages = [], []
    @session.on_owner_changed { |owner| changes << owner }
    @session.on_message { |_sender, packet| messages << packet }
    packet = { "type" => "owner_changed", "owner_id" => "b" }
    @session.apply_envelope(envelope(owner: "a", events: [
      { "type" => "message", "seq" => 1, "sender_id" => "b", "packet" => packet, "message_id" => "one" }
    ]))
    @endpoint.dispatch_events
    assert @session.owner?
    assert_empty changes
    assert_equal [packet], messages
  end

  def test_older_confirmation_cannot_overwrite_later_handover
    @client.handler = lambda do |params|
      @session.apply_envelope(envelope(owner: "c", revision: 3, events: [owner_event("c", 2)]))
      { "success" => true, "data" => confirmation(params) }
    end
    assert @session.transfer_ownership(successor)
    assert_equal "c", @session.owner_id
  end

  def test_legacy_leave_and_close_still_use_existing_operations
    assert @session.leave
    assert_equal "/api/v1/apps/live-sessions/room-1/leave", @client.calls.last[1]
    @session = @endpoint.__send__(:store_session, snapshot)
    assert @session.close
    assert_equal "/api/v1/apps/live-sessions/room-1/close", @client.calls.last[1]
  end

  def test_request_path_is_escaped_and_identity_cannot_be_overridden
    params = { "new_owner_id" => "b", "participant_id" => "spoofed" }
    request = EltenLink::Apps.live_session_ownership_request("room/1", "a", params)
    assert_equal "/api/v1/apps/live-sessions/room%2F1/ownership", request[1]
    assert_equal "a", request[2]["participant_id"]
    assert_equal "spoofed", params["participant_id"]
  end
end
