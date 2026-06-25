# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Update_Confirmation
  def initialize(toscene=nil, version_string=nil)
    @toscene = toscene
    @toscene=Scene_Loading.new if @toscene==nil
    @version_string=version_string
    end
  def main
    version=@version_string.to_s
    version=$update_version_string.to_s if version==""
    msg = if version!=""
      p_("Update", "A new version of Elten is available: %{version}. Do you want to download and install it?")%{:version=>version}
    else
      p_("Update", "A new version of this program is available. Do you want to download and instal it?")
    end
                           if !confirm(msg)
          if $preinitialized != true
          $denyupdate = true
          $scene                  =@toscene
          else
          $denyupdate = true
                              $scene = Scene_Main.new
          end
          else
                                $scene = Scene_Update.new
        end
      end
  end

class Scene_Update
  def main
        $updating = true
        if $downloadstarted != true
        $started = true
    loop_update
  end
  speak(p_("Update", "Please wait while files are downloaded."))
            download_file(EltenLink::System.installer_url(branch: get_updatesbranch, os: platform_os),platform_installer_path,use_waiting: true,can_cancel: false, override: true)
    speech_wait
    if Session.name!="" and Session.name!=nil
    alert(p_("Update", "The update has been downloaded. To install it, the program must be restarted.  Press enter to continue or escape to cancel."))
    cn=true
    deadline = Time.now.to_f + 30
    while Time.now.to_f < deadline
      loop_update
      break if key_pressed?(:key_enter)
      if key_pressed?(:key_escape)
        cn=false
        $scene=Scene_Main.new
                break
        end
      end
    else
      cn=true
      alert(p_("Update", "Now, the update will be installed. The program will restart."))
      end
      if cn == true                      
      $exit=true  
                                        $scene=nil
    $exitupdate=true
    end
    end
      end
  
  class Scene_ReInstall
  def main
        $updating = true
        speak(p_("Update", "Please wait while files are downloaded."))
                $downloadstarted = true
        speak(p_("Update", "Please wait while files are downloaded."))
            download_file(EltenLink::System.installer_url(branch: get_updatesbranch, os: platform_os),platform_installer_path,use_waiting: true,can_cancel: false, override: true)
    speech_wait
    alert(p_("Update", "The program will be now reverted to the latest stable version. Elten will restart.  It may take several minutes."))
      $exit=true  
                                        $scene=nil
    $exitupdate=true
    end
  end
