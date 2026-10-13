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

      def shares(client, note, cancellation_token: nil)
        data = client.api_data("GET", "/api/v1/notes/#{note_id(note)}/shares", cancellation_token: cancellation_token)
        data["users"].to_a.map(&:to_s)
      end

      def add_share(client, note, user, cancellation_token: nil)
        client.api_data("POST", "/api/v1/notes/#{note_id(note)}/shares", { "user" => user }, cancellation_token: cancellation_token)
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

      def note_id(note)
        note.respond_to?(:id) ? note.id : note
      end
    end
  end
end
