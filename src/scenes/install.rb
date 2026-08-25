# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Install
  def main
    confirm(p_("Install", "The Elten installer will be downloaded from the server and launched after Elten closes. Continue?")) do
      begin
        if !download_verified_installer(use_waiting: true, can_cancel: false)
          alert(p_("Install", "Installer download failed."))
          $scene = Scene_Main.new
          return
        end
        alert(p_("Install", "The installer has been downloaded. Elten will close and launch the installer."))
        $exitupdate_donotsilent = true
        $exitupdate = true
        $exit = true
        $scene = nil
      rescue Exception => e
        Log.error("Install Elten failed: #{e.class}: #{e.message}")
        alert(p_("Install", "Installer download failed."))
        $scene = Scene_Main.new
      end
      return
    end
    $scene = Scene_Main.new
  end
end
