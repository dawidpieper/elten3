class Scene_Install
  def main
    confirm(p_("Install", "Elten installer will be downloaded from the server and started after Elten closes. Continue?")) do
      begin
        installer = platform_installer_path
        url = EltenLink::System.installer_url(branch: get_updatesbranch, os: platform_os)
        if !download_file(url, installer, use_waiting: true, can_cancel: false, override: true)
          alert(p_("Install", "Installer download failed."))
          $scene = Scene_Main.new
          return
        end
        alert(p_("Install", "Installer downloaded. Elten will close and start setup."))
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
