# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Registration
  USERNAME_PATTERN = /\A[a-zA-Z0-9._-]{3,32}\z/.freeze
  USERNAME_LETTER_PATTERN = /[a-zA-Z]/.freeze

  def main
begin
stamp = get_stamp("")
rescue Exception
alert(p_("Registration", "Account registration is not available when running the code directly. Please use an official Elten launcher."))
$scene=Scene_Loading.new
return
end
    name = ""
    password = ""
    mail = ""
    while name == ""
    name = input_text(p_("Registration", "Enter your username. It must contain between 3 and 32 characters, including at least one letter. You may use letters, numbers, dots, hyphens, and underscores."), flags: 0, text: "", escapable: true, permitted_characters: (("a".."z").to_a+("A".."Z").to_a+("0".."9").to_a+[".","-","_"]), max_length: 32)
    if name!="" && name!=nil
      if !registration_username_valid?(name)
        alert(p_("Registration", "This username is forbidden."))
        name=""
        next
      end
      begin
        availability = EltenLink::Accounts.registration_name_availability(elten_link, name: name)
      rescue EltenLink::Error => e
        Log.warning("Registration name availability failed: #{e.message}")
        alert(p_("Registration", "An error occurred while connecting to the server."))
        name=""
        next
      end
      if availability == :forbidden
        alert(p_("Registration", "This username is forbidden."))
        name=""
      elsif availability == :exists
        alert(p_("Registration", "A user with this name already exists."))
        name=""
      elsif availability != :available
        alert(_("Error"))
        name=""
      end
    end
  end
  if name==nil
    $scene=Scene_Main.new
    return
    end
  pswconfirm = ""
  while password == "" or password != pswconfirm
    password = input_text(p_("Registration", "Enter your password. We recommend using a strong password consisting of letters and numbers. The maximum password length is 256 characters."),flags: EditBox::Flags::Password, text: "", escapable: true)
    break if password==nil
    pswconfirm = input_text(p_("Registration", "Re-enter your password"),flags: EditBox::Flags::Password, text: "", escapable: true)
    break if pswconfirm==nil
    if pswconfirm != password
      alert(p_("Registration", "The entered passwords differ"))
      end
    end
    if password==nil || pswconfirm==nil
    $scene=Scene_Main.new
    return
    end
  while mail.include?("@")==false || mail.include?(".")==false
    mail = input_text(p_("Registration", "Enter your email address. It will be used to reset a forgotten password and to send you important information."), flags: 0, text: "", escapable: true)
    break if mail==nil
  end
  if mail==nil
    $scene=Scene_Main.new
    return
    end
stamp=nil
begin
stamp = get_stamp(name)
rescue Exception
end
begin
result = EltenLink::Accounts.register(elten_link, name: name, password: password, mail: mail, stamp: stamp)
if result.respond_to?(:activated?) && result.activated?
  alert(p_("Registration", "Registration was successful. Thank you. You can log in using your username and password."))
else
  alert(p_("Registration", "Registration was successful. Thank you. An activation code has been sent to your email address. You will need to enter it when logging in."))
end
rescue EltenLink::Error => e
  if e.code.to_s == "accounts.name_forbidden"
    alert(p_("Registration", "This username is forbidden."))
  elsif e.code.to_s == "accounts.name_exists"
    alert(p_("Registration", "An account with the specified username already exists."))
  elsif e.code.to_s == "accounts.disposable_email"
    alert(p_("Registration", "Disposable e-mail addresses cannot be used for registration. Please use a permanent e-mail address."))
  elsif e.code.to_s == "network_error"
    alert(p_("Registration", "An error occurred while connecting to the server."))
  else
    alert(e.message)
  end
  speech_wait
  $scene = Scene_Loading.new
  main
else
  speech_wait
  $scene = Scene_Loading.new
end
  end

  private

  def registration_username_valid?(name)
    name.to_s.match?(USERNAME_PATTERN) && name.to_s.match?(USERNAME_LETTER_PATTERN)
  end
  end
