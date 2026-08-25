# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
# Opens an audio player
#
# @param file [String] a location or URL of a media to play
# @param label [String] player window caption
# @param wait [Boolean] close a player after audio is played
# @param control [Boolean] allow user to control the played audio, by for example scrolling it
# @param try_download [Boolean] download a file if the codec doesn't support streaming
# @param is_stream [Boolean] whether file is already a stream URL/source
def player(file, label: "", wait: false, control: true, try_download: false, is_stream: false)
  snd=nil
  dialog_opened=false
  begin
  soundfont=EltenPath.join(Dirs.extras, "soundfont.sf2")
  if File.extname(file).downcase==".mid" and FileTest.exists?(soundfont) == false
    if confirm(p_("EAPI_Common", "You are trying to play a MIDI file. Elten needs an external instrument sound bank to play MIDI files. Do you want to download it from the server now? This may take several minutes."))
      alert(p_("EAPI_Common", "Please wait, the soundfont is being downloaded. It may take a while."))
    download_file(soundfont_url,soundfont)
    alert(p_("EAPI_Common", "SoundFont downloaded successfully."))
    Bass::BASS_SetConfigPtr.call(0x10403,soundfont)
  else
    return
    end
      end
    if label != ""
  if wait==false
    dialog_open
    dialog_opened=true
  end
dialog_mute
end
snd=Player.new(file,label: label,autoplay: true,quiet: false)
delay(0.1)
    loop do
                    loop_update
                    snd.update if control
  if wait == true
    if snd.sound!=nil
  if !snd.paused?
    if snd.sound.length>0 && snd.sound.position>=snd.sound.length-0.05
      return
            end
          end
          end
  end
  if (key_pressed?(:key_enter) and !key_held?(0x10)) or key_pressed?(:key_escape) or snd.sound==nil
    snd.fade
    break
    end
  end
ensure
  snd.close if snd!=nil
  dialog_close if dialog_opened
end
end
  end
end
