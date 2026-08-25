# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module EltenAPI
  module WelcomeWizardLaunch
    class << self
      def capture_initial_state(path)
        return @pending if @initial_state_captured

        @initial_state_captured = true
        if !File.file?(path)
          @pending = :first_run
          Log.info("Welcome wizard queued for a new installation") if defined?(Log)
        end
        @pending
      end

      def upgrade_detected
        @pending = :upgrade
        Log.info("Welcome wizard queued after configuration upgrade") if defined?(Log)
        @pending
      end

      def consume
        pending = @pending
        @pending = nil
        pending
      end
    end
  end

  module ConfigurationMigrations
    CURRENT_VERSION = 3

    BOOLEAN_KEYS = [
      ["Interface", "DisableFeedNotifications"],
      ["Interface", "RoundUpForms"],
      ["Interface", "UsePan"],
      ["Interface", "ContextMenuBar"],
      ["Interface", "SoundThemeActivation"],
      ["Interface", "BGSounds"],
      ["Interface", "LineWrapping"],
      ["Interface", "HideWindow"],
      ["Interface", "EnableBraille"],
      ["Advanced", "SyncTime"],
      ["Advanced", "UseEchoCancellation"],
      ["Advanced", "UseBilinearHRTF"],
      ["Advanced", "DisableConferenceMicOnRecord"],
      ["Advanced", "EnableAudioBuffering"],
      ["Advanced", "DisableHTTP2"],
      ["Advanced", "ConferencesTCPOnly"],
      ["Updates", "CheckAtStartup"],
      ["Login", "EnableAutoLogin"],
      ["System", "AutoStart"],
      ["Voice", "UseVoiceDictionary"]
    ].freeze

    VALUE_MAPPINGS = {
      ["Interface", "ListType"] => {
        "0" => "linear",
        "1" => "circular"
      },
      ["Interface", "ControlsPresentation"] => {
        "0" => "voice_and_sound",
        "1" => "sound_only",
        "2" => "voice_only"
      },
      ["Interface", "TypingEcho"] => {
        "0" => "characters",
        "1" => "words",
        "2" => "characters_and_words",
        "3" => "none"
      },
      ["Interface", "AutoPlay"] => {
        "0" => "always",
        "1" => "without_transcription",
        "2" => "never"
      },
      ["Clock", "SayTimePeriod"] => {
        "1" => "hourly",
        "2" => "half_hourly",
        "3" => "quarter_hourly"
      },
      ["Clock", "SayTimeType"] => {
        "0" => "none",
        "1" => "voice_and_sound",
        "2" => "voice_only",
        "3" => "sound_only"
      },
      ["Advanced", "UseDenoising"] => {
        "0" => "never",
        "1" => "conferences",
        "2" => "conferences_and_recording"
      },
      ["Advanced", "UseFX"] => {
        "-1" => "auto",
        "0" => "false",
        "1" => "true"
      },
      ["Privacy", "RegisterActivity"] => {
        "-1" => "unset",
        "0" => "false",
        "1" => "true"
      },
      ["InvisibleInterface", "IIModifiers"] => {
        "0" => "automatic",
        "3" => "alt_ctrl",
        "5" => "alt_shift",
        "7" => "alt_ctrl_shift",
        "11" => "alt_ctrl_windows",
        "13" => "alt_shift_windows"
      },
      ["Updates", "Branch"] => {
        "" => "auto"
      }
    }.freeze

    private

    def migrate_configuration
      path = EltenPath.join(Dirs.eltendata, "elten.ini")
      version = readini(path, "Elten", "ConfigurationVersion", "0").to_i
      return false if version >= CURRENT_VERSION

      migrate_configuration_to_version_1(path) if version < 1
      migrate_configuration_to_version_2(path) if version < 2
      migrate_configuration_to_version_3(path) if version < 3
      writeini(path, "Elten", "ConfigurationVersion", CURRENT_VERSION)
      true
    end

    def migrate_configuration_to_version_1(path)
      BOOLEAN_KEYS.each do |group, key|
        migrate_configuration_value(path, group, key, { "0" => "false", "1" => "true" })
      end
      VALUE_MAPPINGS.each do |(group, key), mapping|
        migrate_configuration_value(path, group, key, mapping)
      end
    end

    def migrate_configuration_to_version_2(path)
      current = readini(path, "Advanced", "AgentSessionTime", "$DEFAULT")
      return if current == "$DEFAULT"

      writeini(path, "Advanced", "SessionRefreshInterval", current)
      writeini(path, "Advanced", "AgentSessionTime", nil)
      WelcomeWizardLaunch.upgrade_detected
    end

    def migrate_configuration_to_version_3(path)
      migrate_configuration_value(
        path,
        "System",
        "AutoStart",
        { "0" => "disabled", "false" => "disabled", "1" => "hidden", "true" => "hidden" }
      )
    end

    def migrate_configuration_value(path, group, key, mapping)
      current = readini(path, group, key, "$DEFAULT")
      return if current == "$DEFAULT" || !mapping.key?(current)

      writeini(path, group, key, mapping[current])
    end
  end

  include ConfigurationMigrations
end
