# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2024 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Ban_Ban
  def initialize(user="",scene=nil)
    @user = user
    @scene = scene
  end
  def main
    user = ""
    user = @user if @user != nil
    while user == ""
      user = input_text(p_("Ban", "Enter a username to ban"),flags: 0,text: "",escapable: true)
    end
    if user == nil
      if @scene == nil
        $scene = Scene_Main.new
      else
        $scene = @scene
        end
    end
sel = [p_("Ban", "A day"),p_("Ban", "Three days"),p_("Ban", "A week"),p_("Ban", "2 weeks"),p_("Ban", "30 days"),p_("Ban", "90 days"), p_("Ban", "180 days"),p_("Ban", "A year"), p_("Ban", "5 years")]
@form=Form.new([ListBox.new(sel,header: p_("Ban", "Ban time")),EditBox.new(p_("Ban", "The reason")),EditBox.new(p_("Ban", "An additional message to the user"),type: EditBox::Flags::MultiLine),CheckBox.new(p_("Ban", "Ban IP address")),Button.new(p_("Ban", "Ban")),Button.new(_("Cancel"))])
loop do
  loop_update
  @form.update
  update
  break if $scene != self
end
end
def update
  if key_pressed?(:key_escape) or ((key_pressed?(:key_space) or key_pressed?(:key_enter)) and @form.index==5)
        if @scene == nil
      $scene = Scene_Main.new
    else
      $scene = @scene
      end
    end
    if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==4
            totime = Time.now.to_i
      case @form.fields[0].index
          when 0
                    totime += 24 * 60 * 60
           when 1
             totime += 3 * 24 * 60 * 60
             when 2
               totime += 7 * 24 * 60 * 60
               when 3
                 totime += 2 * 7 * 24 * 60 * 60
                 when 4
                   totime += 30 * 24 * 60 * 60
                   when 5
                     totime += 3 * 30 * 24 * 60 * 60
                     when 6
                       totime += 6 * 30 * 24 * 60 * 60
                     when 7
                       totime += 365 * 24 * 60 * 60
                       when 8
                         totime += 5 * 365 * 24 * 60 * 60
                             end
           info=@form.fields[2].text
           ip = @form.fields[3].checked                  
           begin
             EltenLink::Bans.ban(elten_link, user: @user, totime: totime, reason: @form.fields[1].text, info: info, ip: ip)
             err = 0
           rescue EltenLink::Error => e
             Log.warning("Ban failed: #{e.message}")
             err = e.code.to_i
           end
if err == 0
  alert(p_("Ban", "Banned."))
else
  alert(_("Error"))
end
speech_wait
if @scene == nil
  $scene = Scene_Main.new
else
  $scene = @scene
  end
      end
  end
end

class Scene_Ban_Unban
  def initialize(user="",scene=nil)
    @user = user
    @scene = scene
  end
  def main
    user = ""
    user = @user if @user != nil
    while user == ""
      user = input_text(p_("Ban", "Enter a username to unban."),flags: 0,text: "",escapable: true)
    end
    if user == nil
      if @scene == nil
        $scene = Scene_Main.new
      else
        $scene = @scene
        end
    end
                  begin
                    baninfo = EltenLink::Bans.info(elten_link, @user)
                  rescue EltenLink::Error => e
                    Log.warning("Ban info failed: #{e.message}")
                    alert(_("Error"))
                    $scene=Scene_Main.new
                    return
                  end
                  if baninfo.banned
                    
                    bantotime=""
                    t=Time.at(baninfo.totime)
                    bantotime=format_date(t)
                                      @form=Form.new([EditBox.new(p_("Ban", "The ban reason"),type: EditBox::Flags::ReadOnly,text: baninfo.reason,quiet: true),EditBox.new(p_("Ban", "Ban valid until"),type: EditBox::Flags::ReadOnly,text: bantotime,quiet: true),EditBox.new(p_("Ban", "The ban cancel reason"),text: "",quiet: true),Button.new(p_("Ban", "Unban")),Button.new(_("Cancel"))])
    loop do
      loop_update
      @form.update
      break if ((key_pressed?(:key_space) or key_pressed?(:key_enter)) and @form.index==4) or key_pressed?(:key_escape)
      if (key_pressed?(:key_space) or key_pressed?(:key_enter)) and @form.index==3
      begin
        EltenLink::Bans.unban(elten_link, user: @user, reason: @form.fields[2].text)
        err = 0
      rescue EltenLink::Error => e
        Log.warning("Unban failed: #{e.message}")
        err = e.code.to_i
      end
if err == 0
  alert(p_("Ban", "Unbanned."))
speech_wait
break
  else
  alert(_("Error"))
end
end
end
end
if @scene == nil
  $scene = Scene_Main.new
else
  $scene = @scene
  end
  end
end
