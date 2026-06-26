# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
  @@hrtf_loaded=false
  def load_hrtf(*)
    return true if @@hrtf_loaded==true

    require_relative "../audio/steamaudio" unless defined?(::SteamAudio)
    loaded = SteamAudio.load(steamaudio_library_path)
    @@hrtf_loaded=true if loaded
    Log.error("SteamAudio HRTF library not available") if !loaded
    loaded
  rescue Exception
    Log.error("SteamAudio HRTF load failed: #{$!.class}: #{$!.message}")
    false
  end

  def steamaudio_library_path
    defined?(EltenRuntimePaths) ? EltenRuntimePaths.absolute_library_file("phonon") : "phonon"
  end
  end
end
