# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
# gets a key pressed by user
#
# @param keys [Array] a keyboard state
# @param multi [Boolean] support multikeys
# @return [String] returns pressed key or keys, if nothing pressed, the return value is an empty string
# @example read the pressed keys
#  loop do
  #   speak(getkeychar)
  #   break if escape
  #  end
def getkeychar(keybd=nil,multi=false)
  default_keyboard = keybd == nil
  serial = $input_frame_serial || $key_update_serial || 0
  if default_keyboard && $getkeychar_cache_serial == serial
    return $getkeychar_cache.to_s
  end
if default_keyboard && EltenWindow.character_input_supported?
    ret = EltenWindow.take_character(multi)
    if ret != ""
      $getkeychar_cache_serial = serial
      $getkeychar_cache = ret.to_s
      $lastkeychar=[ret,Time.now.to_i*1000000+Time.now.usec.to_i]
      return ret.to_s
    end
  end
  akey = default_keyboard && defined?(EltenAPI::KeyboardState) ? EltenAPI::KeyboardState.current.pressed : nil
  akey=keybd if keybd!=nil
  keybd=EltenAPI::KeyboardState.current.state if keybd==nil && defined?(EltenAPI::KeyboardState)
  akey ||= Array.new(256, false)
  keybd ||= "\0"*256
  keybd=keybd.map{|k|((k)?(255):(0))}.pack("C*") if keybd.is_a?(Array)
  akey=akey.unpack("c*").map{|k|k<0} if !akey.is_a?(Array)
    ret=""
          for i in 32..255
    if akey[i]
      re = EltenKeyboard.translate_virtual_key(i, keybd)

 if re!="" and re.getbyte(0)>=32
   ret += re
   break if multi!=true
 end
end
end
  $lastkeychar=[ret,Time.now.to_i*1000000+Time.now.usec.to_i] if ret!=""
  if default_keyboard
    $getkeychar_cache_serial = serial
    $getkeychar_cache = ret.to_s
  end
          return ret
        end
  end
end
