# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenLink
  class ForumTemplate
    attr_reader :definition

    def initialize(definition)
      @definition = definition
    end

    def fields
      @definition.fetch("fields")
    end

    def missing_field(answers)
      fields.find do |field|
        next false unless field["required"]
        value = answers[field["id"]]
        case field["type"]
        when "checkbox"
          value != true
        when "select", "multiselect"
          selected_options(field, value).empty?
        else
          value.to_s.strip.empty?
        end
      end
    end

    def invalid_tag_field(answers)
      fields.find do |field|
        field["mode"] == "tag" && values(field, answers[field["id"]]).any? { |value|
          value.length > 128 || value.match?(/[\[\]\r\n]/)
        }
      end
    end

    def render(title, answers)
      body = []
      prefix = @definition.fetch("post_prefix", "")
      body << prefix unless prefix.empty?
      tags = @definition.fetch("automatic_tags", []).map(&:strip).reject(&:empty?)
      fields.each do |field|
        parts = values(field, answers[field["id"]]).reject { |value| value.strip.empty? }
        next if parts.empty?
        if field["mode"] == "tag"
          tags.concat(parts.map(&:strip))
        elsif field.fetch("mode", "default") == "default" && field["type"] != "checkbox"
          body << heading(field) + "\r\n" + parts.join("\r\n")
        else
          body << parts.join("\r\n")
        end
      end
      { "title" => title, "text" => body.join("\r\n\r\n"), "template_tags" => tags.uniq }
    end

    private

    def heading(field)
      field.fetch("heading", field["label"]).to_s
    end

    def selected_options(field, value)
      ids = Array(value)
      field.fetch("options").select { |option| ids.include?(option["id"]) }
    end

    def values(field, value)
      default = field.fetch("mode", "default") == "default"
      case field["type"]
      when "checkbox"
        if value == true
          [default ? heading(field) : field.fetch("checked")]
        else
          [field.fetch("unchecked", "")]
        end
      when "select", "multiselect"
        selected_options(field, value).map { |option| default ? option["label"] : option.fetch("output") }
      else
        value.to_s.strip.empty? ? [] : [(default ? "" : field.fetch("prefix", "")) + value.to_s]
      end
    end
  end
end
