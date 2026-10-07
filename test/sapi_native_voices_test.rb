# Run on Windows: ruby test/sapi_native_voices_test.rb (requires minitest).
# Loads the real SAPI implementation, but does not speak or create COM objects.
require "minitest/autorun"
require_relative "../src/eapi/speechoutput"
require_relative "../src/platforms/windows/eapi/sapi"

class SapiNativeVoicesTest < Minitest::Test
  class Token
    attr_reader :releases

    def initialize(name, fail_on: nil)
      @name, @fail_on, @releases = name, fail_on, 0
    end

    def Id
      read("Id", "HKEY_LOCAL_MACHINE\\Voices\\#{@name}")
    end

    def GetDescription
      read("Description", @name)
    end

    def GetAttribute(attribute)
      read(attribute, {"Language" => "409", "Age" => "Adult",
        "Gender" => "Female", "Vendor" => "Test"}.fetch(attribute))
    end

    def ole_free
      raise "Token released twice" unless @releases == 0
      @releases += 1
    end

    private

    def read(field, value)
      raise "Token used after release" unless @releases == 0
      raise "Cannot read #{field}" if @fail_on == field
      value
    end
  end

  class Collection
    attr_reader :releases, :items

    def initialize(items, fail_count: false, fail_item: nil)
      @items, @fail_count, @fail_item, @releases = items, fail_count, fail_item, 0
    end

    def Count
      raise "Cannot read count" if @fail_count
      @items.size
    end

    def Item(index)
      raise "Cannot read item" if @fail_item == index
      @items.fetch(index)
    end

    def ole_free
      raise "Collection released twice" unless @releases == 0
      @releases += 1
    end
  end

  def with_voice(speaker)
    original = Sapi.method(:voice)
    Sapi.define_singleton_method(:voice) { speaker }
    yield
  ensure
    Sapi.define_singleton_method(:voice, original)
  end

  def enumerate(collection)
    calls = []
    speaker = Object.new
    speaker.define_singleton_method(:GetVoices) { calls << :GetVoices; collection }
    speaker.define_singleton_method(:ole_free) { calls << :ole_free }
    result = with_voice(speaker) { yield }
    assert_equal [:GetVoices], calls # Do not release the active speaker.
    result
  end

  def assert_released(collection)
    assert_equal 1, collection.releases
    collection.items.each { |token| assert_equal 1, token.releases }
  end

  def test_copies_voice_metadata_and_releases_all_enumeration_objects
    collection = Collection.new([Token.new("First"), Token.new("Second")])
    voices = enumerate(collection) { Sapi.native_voices }
    assert_equal ["First", "Second"], voices.map(&:voiceid)
    assert_equal ["HKEY_LOCAL_MACHINE\\Voices\\First", "First", "409", "Adult",
      "Female", "Test", :native, nil], voices.first.to_a
    assert_released(collection)
  end

  def test_unreadable_voice_is_skipped_but_still_released
    %w[Id Description Language Age Gender Vendor].each do |field|
      collection = Collection.new([Token.new("Broken", fail_on: field), Token.new("Valid")])
      assert_equal ["Valid"], enumerate(collection) { Sapi.native_voices }.map(&:name)
      assert_released(collection)
    end
  end

  def test_empty_collection_is_released
    collection = Collection.new([])
    assert_empty enumerate(collection) { Sapi.native_voices }
    assert_released(collection)
  end

  def test_count_failure_releases_collection
    collection = Collection.new([], fail_count: true)
    assert_empty enumerate(collection) { Sapi.native_voices }
    assert_released(collection)
  end

  def test_item_failure_releases_collection_and_previously_read_tokens
    first, unread = Token.new("First"), Token.new("Unread")
    collection = Collection.new([first, unread], fail_item: 1)
    assert_empty enumerate(collection) { Sapi.native_voices }
    assert_equal 1, collection.releases
    assert_equal 1, first.releases
    assert_equal 0, unread.releases
  end

  def test_missing_sapi_returns_empty_list
    with_voice(nil) { assert_empty Sapi.native_voices }
  end

  def test_get_voices_failure_returns_empty_list
    speaker = Object.new
    def speaker.GetVoices
      raise "Cannot enumerate voices"
    end
    with_voice(speaker) { assert_empty Sapi.native_voices }
  end

  def test_repeated_stream_voice_queries_keep_valid_ruby_metadata
    results = 3.times.map do |index|
      collection = Collection.new([Token.new("Voice#{index}")])
      voices = enumerate(collection) { Sapi.stream_voices }
      assert_released(collection)
      voices
    end
    results.each_with_index do |voices, index|
      assert_equal "Voice#{index}", voices.first.id
      assert_equal "Voice#{index}", voices.first.native.name
      assert_same Sapi, voices.first.output
    end
  end
end
