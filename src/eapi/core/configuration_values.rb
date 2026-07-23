# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3.

module EltenAPI
  module ConfigurationValues
    INVISIBLE_INTERFACE_MODIFIER_MASKS = {
      automatic: 0,
      alt_ctrl: 0x1 | 0x2,
      alt_shift: 0x1 | 0x4,
      alt_ctrl_shift: 0x1 | 0x2 | 0x4,
      alt_ctrl_windows: 0x1 | 0x2 | 0x8,
      alt_shift_windows: 0x1 | 0x4 | 0x8
    }.freeze

    DENOISING_MODE_CODES = {
      never: 0,
      conferences: 1,
      conferences_and_recording: 2
    }.freeze

    BOOLEAN_CODES = {
      false => 0,
      true => 1
    }.freeze

    class << self
      def invisible_interface_modifier_mask(value)
        INVISIBLE_INTERFACE_MODIFIER_MASKS.fetch(value)
      end

      def invisible_interface_modifier_profile(mask)
        INVISIBLE_INTERFACE_MODIFIER_MASKS.key(mask.to_i) || raise(ArgumentError, "Unknown modifier mask: #{mask.inspect}")
      end

      def invisible_interface_modifier_names(value)
        INVISIBLE_INTERFACE_MODIFIER_MASKS.fetch(value)
        value.to_s.split("_").filter_map do |name|
          next if name == "automatic"

          name == "ctrl" ? "CTRL" : name.upcase
        end
      end

      def boolean_code(value)
        BOOLEAN_CODES.fetch(value)
      end

      def denoising_mode_code(value)
        DENOISING_MODE_CODES.fetch(value)
      end
    end
  end
end
