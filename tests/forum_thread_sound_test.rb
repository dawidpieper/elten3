require "minitest/autorun"
require "ostruct"
require "tempfile"
require_relative "../src/eltenlink/error"
require_relative "../src/scenes/forum"

class Button
  def initialize(*); @events = {}; end
  def on(name, &block); @events[name] = block; end
  def trigger(name); @events[name]&.call; end
  def pressed?; false; end
end
class EditBox < Button
  module Flags; MultiLine = 1; end
  attr_accessor :text
  def initialize(*args, text:, **); super(*args); @text = text; end
  def set_text(value); @text = value; end
end
class CheckBox < Button
  def checked; false; end
end
class ListBox < Button
  attr_accessor :index, :options
  def initialize(options, index: 0, **)
    super()
    @options, @index = options, index
  end
end
class OpusRecordButton < Button
  class << self; attr_accessor :path; end
  attr_accessor :timelimit
  def empty?; false; end
  def get_recording_file(*); self.class.path; end
  def delete_audio(*); true; end
end
module Dirs
  def self.temp; Dir.tmpdir; end
end
module EltenPath
  def self.join(*parts); File.join(*parts); end
end
class Form
  class << self; attr_accessor :activation; end
  attr_accessor :fields, :index
  def initialize(fields); @fields, @index, @updates = fields, 0, 0; end
  def hide(*); end
  def show(*); end
  def focus; end
  def update
    @updates += 1
    throw :cancelled if @updates > 1
    @index = fields.size - 2
    fields[0].text = "Topic"
    fields[1].text = "Content" if fields[1].is_a?(EditBox)
    fields[-2] ||= Button.new
    fields[-2].define_singleton_method(:pressed?) { Form.activation == :button }
  end
end
module EltenLink::Forum
  class << self; attr_accessor :sent; end
  def self.create_thread(*, **); self.sent = true; end
  def self.create_audio_thread(*, **); self.sent = true; end
end

class ThreadSoundScene < Scene_Forum
  attr_reader :sounds
  def initialize(type, tags, closed, accepted)
    @forumtype, @forum = type, 1
    group = OpenStruct.new(id: 1, name: "Group", role: 2)
    @groups = [group]
    @forums = [OpenStruct.new(id: 1, type: type, fullname: "Forum", closed: closed, group: group)]
    @tags, @accepted, @sounds = tags, accepted, []
  end
  def forum_group_moderator?(*); true; end
  def forumtags(*); @tags ? [[1, "Tag", "Value"]] : []; end
  def p_(_, text); text; end
  def _(text); text; end
  def loop_update; end
  def key_pressed?(key); Form.activation == :shortcut && key == :key_enter; end
  def key_held?(*); Form.activation == :shortcut; end
  def play_sound(name); @sounds << name; end
  def confirm(*)
    play_sound("listbox_select") # the confirmation list owns this cue
    @accepted
  end
  def elten_link; :client; end
  def alert(*); end
end

class ForumThreadSoundTest < Minitest::Test
  def test_text_send_has_one_cue_without_duplicate_after_confirmation
    [:button, :shortcut].each do |activation|
      [[false, false, 1], [true, false, 1], [false, true, 1], [true, true, 2]].each do |tags, closed, count|
        Form.activation = activation
        EltenLink::Forum.sent = false
        scene = ThreadSoundScene.new(0, tags, closed, true)
        scene.newthread
        assert EltenLink::Forum.sent
        assert_equal ["listbox_select"] * count, scene.sounds, [activation, tags, closed].inspect
      end
    end
  end

  def test_declining_a_confirmation_does_not_send
    Form.activation = :button
    [[true, false], [false, true]].each do |tags, closed|
      EltenLink::Forum.sent = false
      scene = ThreadSoundScene.new(0, tags, closed, false)
      catch(:cancelled) { scene.newthread }
      refute EltenLink::Forum.sent
      assert_equal ["listbox_select"], scene.sounds
    end
  end

  def test_audio_keeps_existing_confirmation_cues
    Form.activation = :button
    Tempfile.create do |file|
      file.binmode
      file.write("OggSfixture")
      file.flush
      OpusRecordButton.path = file.path
      [false, true].each do |tags|
        EltenLink::Forum.sent = false
        scene = ThreadSoundScene.new(1, tags, false, true)
        scene.newthread
        assert EltenLink::Forum.sent
        assert_equal tags ? ["listbox_select"] : [], scene.sounds
      end
    end
  end
end
