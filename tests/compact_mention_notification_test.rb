require "minitest/autorun"
require "ostruct"
require_relative "../src/eapi/notificationgroups"

module EltenAPI
  module Controls
    class FormBase; end
    class SpeechSequence; end
  end
end
require_relative "../src/ui/controls/form_field"
require_relative "../src/ui/controls/table_box"

class MentionNotificationPresenter
  include NotificationGroups
  attr_reader :opened
  def p_(_, text); text; end
  def np_(_, one, many, count); count == 1 ? one : many; end
  def open_forum_thread(payload, category); @opened = [payload, category]; end
end

class CompactMentionNotificationTest < Minitest::Test
  def setup
    @presenter = MentionNotificationPresenter.new
    @payload = { "author" => "Alice", "threadname" => "A topic", "message" => "Please read this.",
      "threadid" => 30, "postid" => 40, "mentionid" => 50 }
  end

  def notification(id: 1, payload: @payload, revoked: false, fallback: "")
    OpenStruct.new(id: id, cat: "mention", payload: payload, revoked: revoked,
      date: 100, update_time: 110, notification: fallback)
  end

  def build(**options)
    @presenter.build_notification_groups([notification(**options)]).first
  end

  def formatted_row(group)
    table = EltenAPI::Controls::TableBox.allocate
    table.instance_variable_set(:@columns, @presenter.notification_columns)
    table.instance_variable_set(:@rows, @presenter.notification_rows([group]))
    table.format_rows.first
  end

  def test_full_label_and_table_read_type_author_thread_message_once
    group = build
    expected = "Mention. Alice. A topic. Please read this."
    assert_equal expected, group.label
    assert_equal expected, @presenter.group_description(group)
    assert_equal expected, formatted_row(group)
    refute_includes formatted_row(group), "Type:"
    assert_equal 1, formatted_row(group).scan("Mention").size
  end

  def test_optional_values_do_not_leave_empty_sentences
    assert_equal "Mention. Alice. A topic", build(payload: @payload.merge("message" => "")).label
    assert_equal "Mention. Alice. Please read this.", build(payload: @payload.merge("threadname" => "")).label
    assert_equal "Mention. A topic. Please read this.", build(payload: @payload.merge("author" => "")).label
    assert_equal "Mention. Alice", build(payload: { "author" => "Alice" }).label
  end

  def test_fallback_and_empty_payload_keep_the_type
    assert_equal "Mention. Legacy text", build(payload: nil, fallback: "Legacy\r\ntext").label
    assert_equal "Mention", build(payload: {}).label
    assert_equal "Mention", formatted_row(build(payload: nil))
  end

  def test_unicode_multiline_text_and_revoked_history
    group = build(payload: @payload.merge("author" => "Żaneta", "message" => "Zażółć\n\t🐈"), revoked: true)
    assert_equal "Mention. Żaneta. A topic. Zażółć 🐈", formatted_row(group)
    assert group.revoked
    assert_equal "Forum mentions", group.category
  end

  def test_ids_grouping_payload_and_action_are_not_changed
    entries = [notification, notification(id: 2)]
    groups = @presenter.build_notification_groups(entries)
    assert_equal 2, groups.size
    group = groups.first
    assert_equal [1], group.ids
    assert_equal "active\u001Fmention\u001Fmention:1", group.key
    assert_equal 110, group.date
    assert_equal "mention", group.cat
    assert_equal "Forum mentions", group.category
    assert_same @payload, group.payload
    group.action.call
    assert_equal [@payload, "mention"], @presenter.opened
    refute group.revoked
  end

  def test_repeated_event_count_is_still_available
    group = build
    group.event_count = 2
    assert_match(/Count: 2/, formatted_row(group))
    refute_match(/Type:/, formatted_row(group))
  end

  def test_other_categories_keep_their_existing_format
    group = NotificationGroups::NotificationGroup.new(cat: "friend", category: "Contacts", payload: { "user" => "Bob" }, ids: [8])
    assert_match(/Type: Contacts/, formatted_row(group))
    assert_match(/\AContacts: /, @presenter.group_label(group))
  end
end
