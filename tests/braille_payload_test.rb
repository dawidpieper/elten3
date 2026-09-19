require "minitest/autorun"

# Exercise the real text controls without starting the native UI or speech.
module EltenAPI
  module Controls
    class FormBase; end
  end
end
module EltenLink
  def self.legacy_line_to_text(text, eol:)
    text
  end
end
require_relative "../src/ui/controls/form_field"
require_relative "../src/ui/controls/edit_box"

class BraillePayloadTest < Minitest::Test
  def editor(header, body, index = 2)
    box = EltenAPI::Controls::EditBox.allocate
    box.header = header
    box.flags = 0
    box.index = 0
    box.set_text(body, reset_speak_callbacks: false)
    box.index = index
    box
  end

  def test_binary_translated_header_and_body
    ["Header", "Zażółć gęślą", "🙂 nagłówek"].each do |heading|
      [heading, heading.b].each do |header|
        header.freeze
        ["Treść 🙂", "Treść 🙂".b].each do |body|
          text, cursor = editor(header, body).braille_payload(true)
          assert_equal "#{heading}\nTreść 🙂", text
          assert_equal heading.length + 3, cursor
          assert_equal true, text.valid_encoding?
          assert_equal heading.b, header.b
        end
      end
    end
  end

  def test_header_is_optional_and_not_mutated
    header = "Żółw".b.freeze
    assert_equal ["Treść", 2], editor(header, "Treść").braille_payload(false)
    assert_equal ["\nTreść", 3], editor(nil, "Treść").braille_payload(true)
    assert_equal Encoding::BINARY, header.encoding
  end

  def test_legacy_and_invalid_headers
    assert_equal "Zażółć\nTreść", editor("Zażółć".encode("Windows-1250"), "Treść").braille_payload(true).first
    assert_equal "a�\nTreść", editor("a\xff".b, "Treść").braille_payload(true).first
  end

  def test_long_read_only_body_keeps_character_cursor
    box = editor("Żółw".b, "ą" * 26_000, 13_000)
    box.flags = EltenAPI::Controls::EditBox::Flags::ReadOnly
    text, cursor = box.braille_payload(true)
    assert_equal "Żółw\n...\n" + "ą" * 25_000 + "\n...", text
    assert_equal 5 + 4 + 12_500, cursor
    assert_equal "ą", text[cursor]
  end
end
