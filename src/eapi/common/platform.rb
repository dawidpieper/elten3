# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
# Gets the size of a file or directory
#
# @param location [String] a location to a file or directory
# @param upd [Boolean] window refreshing
# @return [Numeric] a size in bytes
def getsize(location,upd=true)
               if File.file?(location)
    sz= File.size(location)
        sz=0 if sz<0
    return sz
    end
                      return Dir.size(location)
                    end

  def getfileversioninfo(file, verinfo)
EltenSystemHelpers.file_version_info(file, verinfo)
rescue Exception
  return nil
end

  # @note this function is reserved for Elten usage
  def tray_supported?
    if EltenWindow.tray_supported?
      return EltenWindow.tray_supported?
    end
    if defined?(EltenTray) && EltenTray.respond_to?(:supported?)
      return EltenTray.supported?
    end
    defined?(EltenTray)
  rescue Exception
    false
  end

  def tray
    return false unless tray_supported?
    $totray=true
    true
  end

  def platform_os
    EltenSystemHelpers.platform_os
  rescue Exception
    "unknown"
  end

  def platform_target
    return EltenSystemHelpers.platform_target if EltenSystemHelpers.respond_to?(:platform_target)
    cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase
    arch = cpu =~ /arm|aarch64/ ? "arm64" : (cpu.include?("64") ? "x64" : "x86")
    "#{platform_os}-#{arch}"
  rescue Exception
    platform_os
  end

  def beta_version_creation_supported?
    EltenSystemHelpers.beta_version_creation_supported?
  rescue Exception
    true
  end

  def autologin_key_encryption_supported?
    EltenSystemHelpers.autologin_key_encryption_supported?
  rescue Exception
    false
  end

  def platform_installer_path
    EltenSystemHelpers.installer_path(Dirs.eltendata)
  rescue Exception
    EltenPath.join(Dirs.eltendata, "eltenup")
  end

  def platform_update_install_command(installer = platform_installer_path, silent: true)
    EltenSystemHelpers.update_install_command(installer, silent: silent)
  rescue Exception
    command = "\"#{installer}\""
    command += " /tasks=\"\" /silent" if silent
    command
  end

  def platform_open_url(url)
    EltenSystemHelpers.open_url(url)
  rescue Exception
    false
  end
  end
end
