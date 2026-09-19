require "minitest/autorun"
require_relative "../src/platforms/osx/ri/desktopruntime"

# No Cocoa library is invoked. The production event handler and pump run
# against a fake native message boundary; a Mac is still needed for OS testing.
class MacOSQuitShortcutTest < Minitest::Test
  COMMAND = 1 << 20
  CONTROL = 1 << 18
  OPTION = 1 << 19
  SHIFT = 1 << 17
  CAPS_LOCK = 1 << 16

  def setup
    @native = OSXWindowNative
    @native.singleton_class.send(:public, :handle_event, :quit_shortcut_event?)
    @keys, @forwarded = [], []
    keys = @keys
    @native.define_singleton_method(:sel) { |name| name }
    @native.define_singleton_method(:keyboard_state_allowed?) { true }
    @native.define_singleton_method(:set_event_key) { |event, down| keys << [event, down]; true }
    @native.instance_variable_set(:@close_requested, false)
    @native.instance_variable_set(:@quit_shortcut_requested, false)
    reader = ->(event, field) { event.fetch(field) }
    @native.instance_variable_set(:@msg_int, reader)
    @native.instance_variable_set(:@msg_ulong, reader)
  end

  def event(flags, type = 10, key = 12)
    value = {"modifierFlags" => flags, "keyCode" => key, "type" => type}
    def value.to_i; 1; end
    value
  end

  def test_only_unmodified_command_q_requests_quit
    [COMMAND, COMMAND | CAPS_LOCK].each do |flags|
      assert @native.quit_shortcut_event?(event(flags))
    end
    [0, CONTROL, COMMAND | CONTROL, COMMAND | SHIFT, COMMAND | OPTION,
     COMMAND | CONTROL | CAPS_LOCK, COMMAND | 0x1, COMMAND | 0x2000].each do |flags|
      refute @native.quit_shortcut_event?(event(flags)), "flags=#{flags}"
    end
    refute @native.quit_shortcut_event?(event(COMMAND, 10, 13))
    assert_equal :consumed, @native.handle_event(event(COMMAND))
    assert @native.consume_quit_shortcut_request
  end

  def test_modified_command_q_is_not_consumed_by_either_key_handler
    [CONTROL, OPTION, SHIFT].each do |modifier|
      [10, 11].each do |type|
        assert_equal true, @native.handle_event(event(COMMAND | modifier, type))
        refute @native.consume_quit_shortcut_request
      end
    end
    assert_empty @keys
    assert_equal :consumed, @native.handle_event(event(0, 10, 13))
    assert_equal 1, @keys.size
  end

  def test_pump_passes_lock_shortcut_to_cocoa
    lock = event(COMMAND | CONTROL)
    pending = [lock, 0]
    forwarded = @forwarded
    @native.define_singleton_method(:available?) { true }
    %i[ensure_application process_app_thread_actions refresh_keyboard_active maybe_run_application_slice].each do |name|
      @native.define_singleton_method(name) {}
    end
    @native.define_singleton_method(:distant_past) { 0 }
    @native.define_singleton_method(:run_loop_mode) { 0 }
    @native.instance_variable_set(:@app_thread, Thread.current)
    @native.instance_variable_set(:@main_window, 0)
    @native.instance_variable_set(:@msg_next_event, ->(*) { pending.shift })
    @native.instance_variable_set(:@msg_void_ptr, ->(_app, name, value) { forwarded << value if name == "sendEvent:" })
    @native.instance_variable_set(:@msg_void, ->(*) {})
    assert @native.pump
    assert_equal [lock], forwarded
    assert_empty @keys
    refute @native.consume_quit_shortcut_request
  end
end
