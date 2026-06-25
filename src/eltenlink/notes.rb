# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module EltenLink
  class Note
    attr_accessor :id, :name, :text, :author, :modified, :created

    def initialize(id: 0, name: "", text: "", author: nil, modified: nil, created: nil)
      @id = id.to_i
      @name = name.to_s
      @text = text.to_s
      @author = author || (Session.name)
      @created = created || Time.now
      @modified = modified || Time.now
    end
  end

  module Notes
    class << self
      def list(client)
        data = client.api_data("GET", "/api/v1/notes")
        data["notes"].to_a.map do |row|
          Note.new(
            id: row["id"],
            name: row["name"],
            text: row["text"],
            author: row["author"],
            created: Time.at(row["created"].to_i),
            modified: Time.at(row["modified"].to_i)
          )
        end
      end

      def shares(client, note)
        data = client.api_data("GET", "/api/v1/notes/#{note_id(note)}/shares")
        data["users"].to_a.map(&:to_s)
      end

      def add_share(client, note, user)
        client.api_data("POST", "/api/v1/notes/#{note_id(note)}/shares", { "user" => user })
        true
      end

      def delete_share(client, note, user)
        client.api_data("DELETE", "/api/v1/notes/#{note_id(note)}/shares/#{user.to_s.urlenc}")
        true
      end

      def update(client, note, text)
        client.api_data("PATCH", "/api/v1/notes/#{note_id(note)}", { "text" => text })
        true
      end

      def delete(client, note)
        client.api_data("DELETE", "/api/v1/notes/#{note_id(note)}")
        true
      end

      def rename(client, note, name)
        client.api_data("PATCH", "/api/v1/notes/#{note_id(note)}", { "name" => name })
        true
      end

      def create(client, name, text)
        client.api_data("POST", "/api/v1/notes", { "name" => name, "text" => text })
        true
      end

      private

      def parse_list(lines)
        notes = []
        state = 0
        current = nil
        lines[2..-1].to_a.each do |line|
          clean = EltenLink.clean_line(line)
          case state
          when 0
            current = Note.new(id: clean.to_i)
            notes.push(current)
            state = 1
          when 1
            current.name = clean
            state = 2
          when 2
            current.author = clean
            state = 3
          when 3
            current.created = Time.at(clean.to_i)
            state = 4
          when 4
            current.modified = Time.at(clean.to_i)
            state = 5
          when 5
            if EltenLink.legacy_end?(clean)
              state = 0
            else
              current.text += line
            end
          end
        end
        notes
      end

      def note_id(note)
        note.respond_to?(:id) ? note.id : note
      end
    end
  end
end
