# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper

module ProgramCatalogue
  extend EltenAPI

  LANGUAGE_FILTER_KEY = "ProgramsLanguageFilter"
  LANGUAGE_FILTER_KNOWN_OR_ENGLISH = "known_or_english"
  LANGUAGE_FILTER_KNOWN = "known"
  LANGUAGE_FILTER_ALL = "all"

  class << self
    def language_filter
      mode = LocalConfig[LANGUAGE_FILTER_KEY, LANGUAGE_FILTER_KNOWN_OR_ENGLISH, type: :string]
      [LANGUAGE_FILTER_KNOWN_OR_ENGLISH, LANGUAGE_FILTER_KNOWN, LANGUAGE_FILTER_ALL].include?(mode) ? mode : LANGUAGE_FILTER_KNOWN_OR_ENGLISH
    end

    def filter_by_language(programs)
      mode = language_filter
      return Array(programs) if mode == LANGUAGE_FILTER_ALL
      known = Session.languages.to_s.split(",").filter_map { |language| normalize_language(language) }.uniq
      known.push("en") if mode == LANGUAGE_FILTER_KNOWN_OR_ENGLISH && !known.include?("en")
      Array(programs).select do |program|
        languages = Array(program.supported_languages) + [program.main_language]
        (block_given? && yield(program)) || !(languages.filter_map { |language| normalize_language(language) } & known).empty?
      end
    end

    def platform_compatible?(program)
      !(Array(program.platforms) & ["all", "universal", "*", Programs.platform_family, platform_target]).empty?
    end

    def notifications_enabled?
      Configuration.notifynewprograms == true
    end

    # Catalogue results and acknowledgement are applied by the active interaction thread.
    def accept_snapshot(session, programs)
      return [] unless notifications_enabled? && Session.logged? && session == [Session.name.to_s, Session.token.to_s]
      account = session.first.downcase
      state = notification_state(account)
      programs = programs.uniq { |program| program.id.downcase }
      ids = programs.map { |program| program.id.downcase }.uniq
      pending = state.fetch("pending", {})
      added = []
      if state.key?("known")
        new_ids = ids - state["known"]
        installed = Programs.local_entries.map { |program| program.id.to_s.downcase }
        eligible = programs.select { |program| new_ids.include?(program.id.downcase) && !installed.include?(program.id.downcase) && platform_compatible?(program) }
        filter_by_language(eligible).each do |program|
          uuid = program.id.downcase
          pending[uuid] = { "name" => program.name.to_s, "date" => Time.now.to_i }
          added << pending[uuid]
        end
      end
      state = { "known" => (state.fetch("known", []) | ids), "pending" => pending }
      return [] unless save_notification_state(account, state)
      unless added.empty?
        $main_notifications_changed = true
        Session.notifications_update
      end
      added
    end

    def pending_notifications(account = Session.name.to_s.downcase)
      notification_state(account).fetch("pending", {})
    end

    def acknowledge(account, uuid)
      return false unless Session.logged? && account == Session.name.to_s.downcase
      state = notification_state(account)
      return true unless state.fetch("pending", {}).key?(uuid)
      state["pending"].delete(uuid)
      save_notification_state(account, state)
    end

    private

    def normalize_language(language)
      match = /\A([a-zA-Z]{2})(?:[-_][a-zA-Z]{2})?\z/.match(language.to_s.strip)
      match == nil ? nil : match[1].downcase
    end

    def notification_state(account)
      value = LocalConfig["NewPrograms:#{account}", {}, type: :hash]
      return {} unless value["known"].is_a?(Array) && value["known"].all? { |uuid| uuid.is_a?(String) }
      return {} unless value["pending"].is_a?(Hash) && value["pending"].all? do |uuid, entry|
        uuid.is_a?(String) && entry.is_a?(Hash) && entry["name"].is_a?(String) && entry["date"].is_a?(Integer)
      end
      value
    end

    def save_notification_state(account, state)
      key = "NewPrograms:#{account}"
      previous = LocalConfig[key, {}, type: :hash]
      return true if previous == state
      LocalConfig[key] = state
      return true if LocalConfig.save
      LocalConfig[key] = previous
      Log.warning("Cannot save new program notifications")
      false
    end
  end
end
