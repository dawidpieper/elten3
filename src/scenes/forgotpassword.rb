# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_ForgotPassword
  def main
    @user=""
    loop do    
    @user=input_text(p_("ForgotPassword", "If you lose your password, you can still reset it via the E-mail address provided  during the registration process. This way you shall generate the password reset  code which will be used to verify your identity. The code will be sent to your e- mail address. Warning! Two-factor authentication will be disabled on your  account. To continue, enter your username"),flags: 0,text: "",escapable: true)
    return $scene=Scene_Loading.new if @user==nil
    @user=finduser(@user) if finduser(@user).downcase==@user.downcase
          break
      end
@mail=""
    loop do    
    @mail=input_text(p_("ForgotPassword", "Enter the E-mail address used during the registration process"),flags: 0,text: "",escapable: true)
    return $scene=Scene_Loading.new if @mail==nil
      begin
        mail_ok=EltenLink::Accounts.user_mail_matches?(elten_link, user: @user, mail: @mail)
      rescue EltenLink::Error => e
        Log.warning("Password reset user/mail check failed: #{e.message}")
        alert(_("Error"))
        return $scene=Scene_Loading.new
      end
      break if mail_ok
      alert(p_("ForgotPassword", "The typed E-mail address is not associated with the entered username."))
    end
@sel=ListBox.new([p_("ForgotPassword", "Generate password reset code"),p_("ForgotPassword", "Enter password reset code"),_("Exit")],header: p_("ForgotPassword", "Password reset"), index: 0, flags: 0, quiet: false)
loop do
  loop_update
  @sel.update
  return $scene=Scene_Loading.new if key_pressed?(:key_escape)
  if key_pressed?(:key_enter)
    case @sel.index
    when 0
      request
      @sel.focus
      when 1
    proceed
    @sel.focus
        when 2
      return $scene=Scene_Loading.new
    end
    end
  end
    end
  def request
        alert(p_("ForgotPassword", "Please wait while the password reset key is being generated."))
    begin
      EltenLink::Accounts.request_password_reset(elten_link, user: @user, mail: @mail)
      ok=true
    rescue EltenLink::Error => e
      Log.warning("Password reset request failed: #{e.message}")
      ok=false
    end
    speech_wait
    if !ok
      alert(p_("ForgotPassword", "An unexpected error"))
    else
      alert(p_("ForgotPassword", "Password reset key has been sent to your specified E-mail address. To continue,  select the option for entering key."))
    end
    speech_wait
  end
  def proceed
    key=""
    loop do
    key=input_text(p_("ForgotPassword", "Enter the generated password reset code"),flags: 0,text: "",escapable: true)
    return if key==nil
begin
  EltenLink::Accounts.verify_password_reset(elten_link, user: @user, mail: @mail, key: key)
  ok=true
rescue EltenLink::Error
  ok=false
end
if ok
  break
else
  alert(p_("ForgotPassword", "The entered code is invalid."))
end
end
newpassword=""
loop do
  newpassword=input_text(p_("ForgotPassword", "Type a new password"), flags: EditBox::Flags::Password, escapable: true)
  return if newpassword==nil
  confirmpassword=input_text(p_("ForgotPassword", "Type a new password again"), flags: EditBox::Flags::Password, escapable: true)
  return if confirmpassword==nil
  if confirmpassword!=newpassword
    alert(p_("ForgotPassword", "The entered passwords are different."))
  elsif newpassword==""
    alert(p_("ForgotPassword", "Empty password provided."))
    else
    break
    end
end
speak(p_("ForgotPassword", "Please wait while the password is being changed"))
begin
  EltenLink::Accounts.change_password_with_reset(elten_link, user: @user, mail: @mail, key: key, new_password: newpassword)
  ok=true
rescue EltenLink::Error => e
  Log.warning("Password reset change failed: #{e.message}")
  ok=false
end
speech_wait
if !ok
  alert(p_("ForgotPassword", "An unexpected error"))
else
  alert(p_("ForgotPassword", "The password has been changed. You can log in to your account using the new data."))
end
speech_wait
return
end
end
