# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Registration
  def main
begin
stamp = get_stamp("")
rescue Exception
alert(p_("Registration", "Accounts registrations are not possible with direct code execution, please use an official Elten launcher."))
$scene=Scene_Loading.new
return
end
    name = ""
    password = ""
    mail = ""
    while name == ""
    name = input_text(p_("Registration", "Enter your username. It will be used for identification.The maximum length of the  username is 64 characters"), flags: 0, text: "", escapable: true, permitted_characters: (("a".."z").to_a+("A".."Z").to_a+("0".."9").to_a+["-","_"]))
    if name!="" && name!=nil
      if user_exists(name)
        alert(p_("Registration", "User with this name already exists."))
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
    password = input_text(p_("Registration", "Enter your password. It is recommended to use a strong password, which consists  of numbers and letters. Maximum length of the password is 256 characters."),flags: EditBox::Flags::Password, text: "", escapable: true)
    break if password==nil
    pswconfirm = input_text(p_("Registration", "Reenter your password"),flags: EditBox::Flags::Password, text: "", escapable: true)
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
    mail = input_text(p_("Registration", "Enter your e-mail address. It will be used in case you forget your password and  to send important information."), flags: 0, text: "", escapable: true)
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
  alert(p_("Registration", "Registration is successful, thank you. You can log in using your username and  password."))
else
  alert(p_("Registration", "Registration is successful, thank you. An activation code has been sent to your e-mail address. You will need to enter it during login."))
end
rescue EltenLink::Error => e
  if e.code.to_s == "accounts.name_unavailable"
    alert(p_("Registration", "Account with the specified username already exists."))
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
  end
