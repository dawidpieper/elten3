require "minitest/autorun"
require "ostruct"
require_relative "../src/eapi/structs"
require_relative "../src/eapi/core/configuration"
require_relative "../src/platforms/windows/invisibleinterface/service"
require_relative "../src/scenes/settings"

Configuration = EltenAPI::Structs::Configuration
Session = EltenAPI::Structs::Session
module Log
  class << self
    attr_accessor :errors
    def info(*); end
    def warning(*); end
    def error(text); (self.errors ||= []) << text; end
  end
end
module LocalConfig
  def self.load; end
end
module NotificationGroups
  def self.default_notification_type_order; []; end
end

class SubjectConfigurationLoader
  include EltenAPI
  attr_reader :values
  def initialize; @values = {}; end
  def migrate_configuration; end
  def readconfig(group, key, default = "")
    # Stop before unrelated audio/platform initialization, after II is loaded.
    throw :configuration_loaded if [group, key] == ["Interface", "RoundUpForms"]
    values.fetch([group, key], default)
  end
  def writeconfig(group, key, value); values[[group, key]] = value; end
  def reload; catch(:configuration_loaded) { load_configuration }; end
end

class SubjectSettings < Scene_Settings
  attr_reader :declarations
  def initialize
    super
    @declarations = []
  end
  def setting_category(*); end
  def make_setting(*args); declarations << args; end
  def p_(_, text); text; end
end

class InvisibleMessageSubjectsTest < Minitest::Test
  def setup
    @interface = EltenAPI::InvisibleInterface
    @spoken, @played = [], []
    spoken, played = @spoken, @played
    @interface.define_singleton_method(:speak) { |text| spoken << text }
    @interface.define_singleton_method(:play_move) { played << :move }
    @interface.define_singleton_method(:play_border) { played << :border }
    @interface.define_singleton_method(:quick_audio_stop) { played << :stop }
    @interface.define_singleton_method(:quick_audio_play) { |url| played << url }
    @interface.define_singleton_method(:p_) { |_, text| text }
    Session.name = "Alice"
    Configuration.instance_variable_set(:@iireadmessagesubjects, false)
    Log.errors = []
  end

  def message_record(**overrides)
    OpenStruct.new({ id: 1, sender: "Bob", receiver: "Alice", group_name: "",
      subject: "Meeting", text: "Yes", audio_url: "", forwardedfrom: "" }.merge(overrides))
  end

  def read(**values)
    @interface.send(:handle_message, message_record(**values))
    assert_empty Log.errors
    @spoken.last
  end

  def test_disabled_preserves_existing_announcement
    assert_equal "Bob: Yes", read
    assert_equal "Meeting", @interface.instance_variable_get(:@message_lastsubject)
    assert_equal "Bob", @interface.instance_variable_get(:@message_lastrecipient)
  end

  def test_enabled_reads_subject_with_each_message
    Configuration.instance_variable_set(:@iireadmessagesubjects, true)
    assert_equal "Bob: Meeting: Yes", read
    assert_equal "Bob: Meeting: Tomorrow", read(id: 2, text: "Tomorrow")
    assert_equal "Bob: Another topic: No", read(id: 3, subject: "Another topic", text: "No")
  end

  def test_empty_subject_is_not_announced
    Configuration.instance_variable_set(:@iireadmessagesubjects, true)
    ["", " \r\n", nil].each { |subject| assert_equal "Bob: Yes", read(subject: subject) }
  end

  def test_outgoing_group_forwarded_and_audio_messages_keep_context
    Configuration.instance_variable_set(:@iireadmessagesubjects, true)
    assert_equal "To Bob: Meeting: Yes", read(sender: "Alice", receiver: "Bob")
    assert_equal "Bob To Our group: Meeting: Yes", read(group_name: "Our group")
    assert_equal "Bob: Meeting:\r\nForwarded from Carol: Yes", read(forwardedfrom: "Carol", audio_url: "audio.ogg")
    assert_includes @played, "audio.ogg"
  end

  def test_unicode_and_repeat_at_boundary
    Configuration.instance_variable_set(:@iireadmessagesubjects, true)
    expected = "Żaneta: Zażółć 🐈: Tak"
    assert_equal expected, read(sender: "Żaneta", subject: "Zażółć 🐈", text: "Tak")
    @interface.send(:handle_message, nil)
    assert_equal expected, @spoken.last
    assert_equal :border, @played.last
  end

  def test_configuration_default_persistence_and_invalid_value
    loader = SubjectConfigurationLoader.new
    loader.reload
    assert_equal false, Configuration.iireadmessagesubjects
    loader.values[["InvisibleInterface", "ReadMessageSubjects"]] = "true"
    loader.reload
    assert_equal true, Configuration.iireadmessagesubjects
    loader.values[["InvisibleInterface", "ReadMessageSubjects"]] = "invalid"
    loader.reload
    assert_equal false, Configuration.iireadmessagesubjects
    assert_equal "false", loader.values[["InvisibleInterface", "ReadMessageSubjects"]]
  end

  def test_setting_uses_the_same_boolean_key
    settings = SubjectSettings.new
    settings.load_ii
    assert_includes settings.declarations,
      ["Read message subjects", :bool, "InvisibleInterface", "ReadMessageSubjects"]
  end
end
