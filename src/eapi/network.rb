# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require "digest"

module EltenAPI
  module Network
    private
# The Network related functions
def read_url(url, method: :get, body: nil, headers: nil)
          Log.debug("Read URL #{url}")
                              play_sound("signal") if $netsignal
                      headers={} if headers==nil
                      if body!=nil && body.is_a?(Hash)
                        boundary=""
values = body.values.map { |value| value.to_s.b }
while boundary=="" || values.any? { |value| value.include?(boundary) }
  boundary="----EltBoundary"+rand(36**32).to_s(36)
end
txt="".b
for h in body.keys
txt << ("--"+boundary+"\r\nContent-Disposition: form-data; name=\"#{h}\"\r\n\r\n").b
txt << body[h].to_s.b
txt << "\r\n".b
end
txt << ("--#{boundary}--").b
body=txt
                        headers['Content-Type']="multipart/form-data; boundary=#{boundary}"
                        end
response = nil
done = false
response_headers = {}
elten_link.e_read_url(url, method.to_s, body, headers, nil) do |resp, _data, h|
response = resp == :error ? nil : resp
response_headers = h if h.is_a?(Hash)
done = true
end
            t=Time.now.to_f
            w=false
                while done==false
            loop_update(false)
      if Time.now.to_f-t>2 and w==false
        waiting
        w=true
      elsif Time.now.to_f-t>30
        Log.warning("Session timed out for URL read from #{url}")
        waiting_end
return nil
      end
      if key_pressed?(:key_escape) and w
        play_sound("cancel")
        Log.debug("URL read request from #{url} cancelled by user")
        waiting_end
return nil
      end
      end
      waiting_end if w
if headers!=nil
headers.clear
for k,v in response_headers
headers[k]=v
end
end
return response
end

def download_file(source, destination, use_waiting: true, can_cancel: true, override: false)
  return if override==false and FileTest.exists?(destination) and !confirm(p_("EAPI_Network", "The file already exists. Do you want to override it?"))
          Log.debug("Downloading file #{source}")
                              play_sound("signal") if $netsignal
          result = nil
          progress = nil
          data = {:cancelled=>false}
          elten_link.e_download_file(source, destination, data) do |resp, _data|
            if resp.is_a?(ERDownloadProgress)
              progress = resp.percent
            elsif resp == :error
              result = false
            elsif resp.is_a?(Integer)
              result = true
            else
              result = false
            end
          end
                                    t=Time.now.to_f
            w=false
                while result==nil
            loop_update(false)
            if progress.is_a?(Integer) && use_waiting
              speak(progress.to_s+"%")
              progress=nil
              end
      if Time.now.to_f-t>1 and w==false
        waiting if use_waiting
        w=true
      end
      if key_pressed?(:key_escape) and w and can_cancel
        play_sound("cancel")
        Log.debug("Download of #{source} cancelled by user")
        waiting_end if use_waiting
        data[:cancelled]=true
return false
      end
      end
      waiting_end if w && use_waiting
      return result == true
  end

def installer_sha256_valid?(path, expected_sha256)
  expected = expected_sha256.to_s.downcase
  return false unless expected.match?(/\A[0-9a-f]{64}\z/) && File.file?(path)
  Digest::SHA256.file(path).hexdigest == expected
rescue Exception => e
  Log.error("Installer hash verification failed: #{e.class}: #{e.message}")
  false
end

def download_verified_installer(use_waiting: true, can_cancel: false)
  installer = platform_installer_path
  temporary = installer + ".download"
  $update_installer_sha256 = nil
  File.delete(temporary) if File.file?(temporary)

  metadata = EltenLink::System.installer(elten_link, branch: get_updatesbranch, os: platform_os)
  return false unless download_file(metadata.url, temporary, use_waiting: use_waiting, can_cancel: can_cancel, override: true)
  unless File.size(temporary) == metadata.size && installer_sha256_valid?(temporary, metadata.sha256)
    Log.error("Downloaded installer does not match server metadata")
    return false
  end

  File.delete(installer) if File.file?(installer)
  File.rename(temporary, installer)
  $update_installer_sha256 = metadata.sha256
  true
rescue Exception => e
  Log.error("Verified installer download failed: #{e.class}: #{e.message}")
  false
ensure
  begin
    File.delete(temporary) if temporary != nil && File.file?(temporary)
  rescue Exception => e
    Log.warning("Could not remove temporary installer: #{e.class}: #{e.message}")
  end
end

                  def html_decode(text)
                    EltenAPI::Html.text(text)
                  end

                  def html_encode(text)
                    EltenAPI::Html.escape(text)
                  end
                end
                  include Network
end
