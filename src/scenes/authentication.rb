# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Authentication
  def main
    if Session.name=="guest"
      alert(_("This section is unavailable for guests"))
      $scene=Scene_Main.new
      return
      end
    begin
      state=EltenLink::Authentication.state(elten_link)
    rescue EltenLink::Error => e
      Log.warning("Authentication state failed: #{e.message}")
      speak(_("Error"))
      speech_wait
      return $scene=Scene_Main.new
    end
    action=0
    if state==0
      action=selector([_("Enable"),nil,_("Exit")],header: p_("Authentication", "Two-factor authentication enables better account security by requiring the  confirmation of each login with your phone. When activated, a text message with a  verification code will be sent to you each time you log in from a new device.  Entering this code will be required to sign in to the program."),start_index: 0,cancel_index: 2,flags: 1)
    else
      action=selector([_("Disable"),p_("Authentication", "Generate backup codes"),_("Exit")],header: p_("Authentication", "Two-factor authentication is enabled on this account."),start_index: 0,cancel_index: 2,flags: 1)
    end
if action==0
  if state==0
password=""
suc=true
phone=""
  password=input_text(p_("Authentication", "Type your password"),flags: EditBox::Flags::Password,text: "",escapable: true) while password==""
  return main if password==nil
phone=input_text(p_("Authentication", "Type your phone number that will be used during verification. Remember to enter  the country code, for example, +48 for Poland"),flags: 0,text: "",escapable: true) while (phone=="" or (phone[0..0]!="+" and phone[0..1]!="00") or phone.size<11 or (/[a-zA-Z,.\/;'\"\[\]!@\#\$%\^\&\*\(\)\_]/=~phone)!=nil) and phone!=nil
return main if phone==nil
return main if !confirm(p_("Authentication", "Two-factor authentication was introduced in Elten 2.28. After activating it, it  will not be possible to log in from the older versions of the program. DO you  wish to continue anyway?"))
return main if input_text(p_("Authentication", "Is this phone number correct? Press enter to continue or escape to cancel."),flags: EditBox::Flags::ReadOnly,text: phone, escapable: true)==nil
if suc==true
alert(p_("Authentication", "Please wait, connecting to the server ..."))
begin
  EltenLink::Authentication.enable(elten_link, password: password, phone: phone, language: Configuration.language)
  enable_ok=true
rescue EltenLink::Error => e
  Log.warning("Authentication enable failed: #{e.message}")
  enable_ok=false
end
speech_wait
if !enable_ok
  alert(_("Error"))
else
  code=""
  tries=0
  label=p_("Authentication", "On the phone number indicated, you will receive a text message with the code  activating two-factor authentication. Enter this code")
  while tries<3
  code=input_text(label,flags: EditBox::Flags::Numbers).delete("\r\n") while code==""
  begin
    EltenLink::Authentication.verify(elten_link, code: code, appid: $appid)
    verify_ok=true
  rescue EltenLink::Error
    verify_ok=false
  end
  if !verify_ok
        tries+=1
        code=""
        if tries<3
          label=p_("Authentication", "The entered code is not correct. Try again.")
        else
          alert(p_("Authentication", "The entered code is not correct."))
          end
    speech_wait
  else
    alert(p_("Authentication", "Two-factor authentication has been activated on this account."))
    break
  end
end
  end

  end
elsif state==1
  password=""
  password=input_text(p_("Authentication", "Type your password"),flags: EditBox::Flags::Password,text: "",escapable: true) while password==""
  if password!=nil and confirm(p_("Authentication", "Are you sure you want to disable two-factor authentication?"))
    begin
      EltenLink::Authentication.disable(elten_link, password: password)
      dsb_code=0
    rescue EltenLink::Error => e
      Log.warning("Authentication disable failed: #{e.message}")
      dsb_code=e.code.to_i
    end
    if dsb_code==0
      alert(p_("Authentication", "Two-factor authentication has been disabled."))
    elsif dsb_code==-2
      alert(p_("Authentication", "Invalid password"))
      else
      alert(_("Error"))
    end
    speech_wait
    end
    end
  end
  if action==1
if confirm(p_("Authentication", "Do you want to generate backup codes? These can be used to sign in when you have no access to your phone. All previously generated codes will be deleted."))
  password=""
  password=input_text(p_("Authentication", "Type your password"),flags: EditBox::Flags::Password,text: "",escapable: true) while password==""
  return main if password==nil  
  begin
    codes=EltenLink::Authentication.backup_codes(elten_link, password: password)
  rescue EltenLink::Error => e
    Log.warning("Authentication backup codes failed: #{e.message}")
      alert(_("Error"))
    else
      input_text(p_("Authentication", "Generated backup codes"), flags: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: codes.join("\r\n\r\n"), escapable: true)
      end
    end
        end
    $scene=Scene_Main.new if action==2
  end
  end
