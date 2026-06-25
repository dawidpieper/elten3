# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  LEGACY_SEPARATOR = 4.chr
  LEGACY_LINE = "#{LEGACY_SEPARATOR}LINE#{LEGACY_SEPARATOR}"
  LEGACY_END = "#{LEGACY_SEPARATOR}END#{LEGACY_SEPARATOR}"

  class << self
    def client(context)
      if context != nil && context.respond_to?(:elten_link, true)
        context.__send__(:elten_link)
      else
        Client.new(context)
      end
    end

    def clean_line(value)
      value.to_s.delete("\r\n")
    end

    def legacy_line_to_text(value, eol: "\r\n")
      value.to_s.gsub(LEGACY_LINE, eol)
    end

    def text_to_legacy_line(value)
      value.to_s.gsub("\r\n", LEGACY_LINE).gsub("\n", LEGACY_LINE)
    end

    def legacy_end?(value)
      clean_line(value) == LEGACY_END
    end

    def close
      ::EltenAPI::HTTPClient.close if defined?(::EltenAPI::HTTPClient)
    end
  end
end
