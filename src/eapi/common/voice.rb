# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
    def voicecall(channel=nil, channel_password=nil, invite=[])
      invite=[invite] if invite.is_a?(String)
      return unless Session.logged?
      Conference.open if !Conference.opened?
if !Conference.opened?
$scene=Scene_Main.new
return
end
if channel==nil
channel_password = rand(36**32).to_s(36)
chname="VoiceCall_"+Session.name
channel = Conference.create(chname, false, 56, 40, 1, 0, false, true, channel_password, 0, 2, nil, voice_call_grace: true).to_i
else
Conference.join(channel, channel_password)
end
delay(1)
tm=nil
tm=30 if invite.is_a?(Array) && invite.size==1
sc=Scene_Conference.new(tm, 1, expected_peer: tm && invite.first)
if invite.is_a?(Array)
invite.each{|user|sc.invite(user)}
Conference.calling_play(invite.first) if invite.size==1
end
insert_scene(sc)
      end
  end
end
