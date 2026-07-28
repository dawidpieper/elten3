# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2024 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Account
  WHATSNEW_DISABLE_LIST = 1
  WHATSNEW_DISABLE_PC = 2
  WHATSNEW_DISABLE_MOBILE = 4
  WHATSNEW_DELIVERY_BITS = [WHATSNEW_DISABLE_LIST, WHATSNEW_DISABLE_PC, WHATSNEW_DISABLE_MOBILE]

  def initialize
    @settings=[]
  end
  def getconfig
    @values={}
    @values=EltenLink::Accounts.config(elten_link)
  rescue EltenLink::Error
    @values={}
    end
  def currentconfig(key)
    getconfig if @values==nil
    return @values[key]
  end
  def setcurrentconfig(key,val)
@values[key]=val.to_s
end
  def setting_category(cat)
    @settings.push([cat, nil])
    @form.fields[0].options.push(cat)
  end
  def on_load(&func)
    return if @settings.size==0
    @settings.last[1]=func
    end
def make_setting(label, type, key, mapping=nil, multi=false)
  return if @settings.size==0
  mapping=mapping.map{|x|x.to_s} if mapping!=nil
  @settings.last.push([label, type, key, mapping, multi])
end
def save_category
  for i in 2...@settings[@category].size
    setting=@settings[@category][i]
    next if setting==nil || setting[1]==:custom
    index=i-1
    field=@form.fields[index]
    next if field==nil
    if setting[1]==:whatsnew_delivery
      val=whatsnew_delivery_value(field.multiselections)
    elsif setting[4]==false || !setting[1].is_a?(Array)
    val=field.value
    val=val.to_i if setting[1]==:number
    val=val ? 1 : 0 if setting[1]==:bool
    val=setting[3][val] if setting[3]!=nil
  else
    vals=[]
    for v in field.multiselections
      v=setting[3][v] if setting[3]!=nil
      vals.push(v)
    end
    val=vals.join(",")
    end
    setcurrentconfig(setting[2], val)
    end
  end
def show_category(id)
  return if @form==nil or @settings[id]==nil
  save_category if @category!=nil
  @category=id
  @form.show_all
  @form.fields[1...-3]=[]
  f=[]
for s in @settings[id][2..-1]
  label, type, key, mapping, multi = s
  field=nil
  case type
  when :text
    field=EditBox.new(label, type: 0, text: currentconfig(key),quiet: true)
    when :longtext
      field=EditBox.new(label, type: EditBox::Flags::MultiLine, text: currentconfig(key),quiet: true)
    when :number
    field=EditBox.new(label, type: EditBox::Flags::Numbers, text: currentconfig(key),quiet: true)
    when :bool
      field=CheckBox.new(label, checked: currentconfig(key).to_i!=0)
    when :whatsnew_delivery
      field=ListBox.new(whatsnew_delivery_options, header: label, index: 0, flags: ListBox::Flags::MultiSelection)
      whatsnew_delivery_selection(currentconfig(key).to_i).each { |selected_index| field.selected[selected_index]=true }
      when :custom
        field=Button.new(label)
        proc=key
        field.on(:press, 0, true, &proc)
    else
      index=currentconfig(key)
      index=mapping.find_index(index)||0 if mapping!=nil
      flags=0
      flags|=ListBox::Flags::MultiSelection if multi==true
      field=ListBox.new(type, header: label, index: index.to_i, flags: flags)
      if multi==true
        for e in currentconfig(key).to_s.split(",")
index=e
      index=mapping.find_index(index)||0 if mapping!=nil
      field.selected[index.to_i]=true
          end
        end
    end
@form.fields.insert(@form.fields.size-3, field)
end
@settings[id][1].call if @settings[id][1]!=nil
end
def apply_settings
  save_category
  j={}
  for k in @values.keys
    v=@values[k]
    j[k]=v
    Session.fullname=v if k=="fullname"
    Session.gender=v.to_i if k=="gender"
    Session.languages=v if k=="languages"
  end
  EltenLink::Accounts.update_config(elten_link, j)
rescue EltenLink::Error
  end
def make_window
  @form=Form.new
  @form.fields[0] = ListBox.new([], header: p_("Account", "Category"))
  @form.fields[1]=Button.new(_("Apply"))
  @form.fields[2]=Button.new(_("Save"))
  @form.fields[3]=Button.new(_("Cancel"))
end

def whatsnew_delivery_options
  [
    p_("Account", "Show in what's new"),
    p_("Account", "Alert on PC"),
    p_("Account", "Notify on mobile devices")
  ]
end

def whatsnew_delivery_selection(value)
  value=value.to_i
  selected=[]
  WHATSNEW_DELIVERY_BITS.each_with_index do |bit, index|
    selected.push(index) if (value&bit)==0
  end
  selected
end

def whatsnew_delivery_value(selected)
  selected=selected.map(&:to_i)
  value=0
  WHATSNEW_DELIVERY_BITS.each_with_index do |bit, index|
    value|=bit if !selected.include?(index)
  end
  value
end

def load_profile
  setting_category(p_("Account", "Profile"))
  make_setting(p_("Account", "Full name"), :text, "fullname")
  make_setting(p_("Account", "Gender"), [_("Female"), _("Male")], "gender")
  years=(1900..Time.now.year).to_a
  monthsmapping=(1..12)
  months=[_("January"), _("February"), _("March"), _("April"), _("May"), _("June"), _("July"), _("August"), _("September"), _("October"), _("November"), _("December")]
  days = (1..31).to_a
  make_setting(p_("Account", "Birth date: year"),[p_("Account", "Don't specify")] + years.map{|y|y.to_s}, "birthdateyear", [0]+years)
  make_setting(p_("Account", "Birth date: month"), months, "birthdatemonth", monthsmapping)
  make_setting(p_("Account", "Birth date: day"), days.map{|y|y.to_s}, "birthdateday", days)
  make_setting(p_("Account", "Country"), [""], "LocationCountry")
  make_setting(p_("Account", "State / Province"), [""], "LocationState")
  make_setting(p_("Account", "City"), [""], "LocationCity")
  on_load {
  @form.fields[3].on(:move) {
  if @form.fields[3].index==0
    @form.hide(4)
    @form.hide(5)
  else
    @form.show(4)
    @form.show(5)
    end
  }
  @form.fields[3].trigger(:move)
  @form.fields[4].on(:move) {
  m=@form.fields[4].index+1
  if m==1 or m==3 or m==5 or m==7 or m==8 or m==10 or m==12
    @form.fields[5].enable_item(-1+29)
    @form.fields[5].enable_item(-1+30)
    @form.fields[5].enable_item(-1+31)
  elsif m==2
    @form.fields[5].disable_item(-1+30)
    @form.fields[5].disable_item(-1+31)
  if @form.fields[3].index%4==0 && @form.fields[3].index!=100
    @form.fields[5].enable_item(-1+29)
  else
    @form.fields[5].disable_item(-1+29)
  end
else
  @form.fields[5].enable_item(-1+29)
  @form.fields[5].enable_item(-1+30)
  @form.fields[5].disable_item(-1+31)
end
}
@form.fields[3].on(:move) {@form.fields[4].trigger(:move)}
@form.fields[4].trigger(:move)
location=currentconfig("location")
location_a={}
countries=[""]+Lists.locations.map {|c| location_a=c if c['geonameid']==location.to_i;c['country']}.uniq.polsort
subcountries=[]
cities=[]
ind=[-1, -1, -1]
@form.fields[6].options=countries
if ind[0]==-1
  ind[0]=countries.find_index(location_a['country'])||0
  @form.fields[6].index=ind[0]
  end
@form.fields[6].on(:move) {
            subcountries=[""]+Lists.locations.map {|c| (c['country']==countries[@form.fields[6].index])?(c['subcountry']):(nil)}.uniq
            subcountries.delete(nil)
            subcountries.polsort!
                        @form.fields[7].options = subcountries
            if ind[1]==-1
              ind[1]=subcountries.find_index(location_a['subcountry'])||0
              @form.fields[7].index=ind[1]
              else
            @form.fields[7].index=0
            end
            @form.fields[7].trigger(:move)
}
@form.fields[7].on(:move) {
cities=[""]+Lists.locations.map {|c| (c['country']==countries[@form.fields[6].index]&&c['subcountry']==subcountries[@form.fields[7].index])?(c['name']):(nil)}.uniq
cities.delete(nil)
cities.polsort!
@form.fields[8].options = cities
if ind[2]==-1
  ind[2]=cities.find_index(location_a['name'])||0
  @form.fields[8].index=ind[2]
  else
@form.fields[8].index=0
end
@form.fields[8].trigger(:move)
}
@form.fields[8].on(:move) {
loc=0
Lists.locations.each {|l| loc=l['geonameid'] if l['country']==countries[@form.fields[6].index] and l['subcountry']==subcountries[@form.fields[7].index] and l['name']==cities[@form.fields[8].index]}
setcurrentconfig("location", loc)
}
@form.fields[6].trigger(:move)
  }
end
def load_visitingcard
  setting_category(p_("Account", "Visiting card"))
  make_setting(p_("Account", "Visiting card"), :longtext, 'visitingcard')
end
def load_languages
  setting_category(p_("Account", "Languages"))
  langs=[]
  langsmapping=[]
  for lk in Lists.langs.keys.sort{|a,b|polsorter(Lists.langs[a]['name'],Lists.langs[b]['name'])}
    langsmapping.push(lk)
    l=Lists.langs[lk]
    langs.push(l['name']+"( "+l['nativeName']+")")
    end
  make_setting(p_("Account", "Languages"), langs, "languages", langsmapping, true)
  make_setting(p_("account", "First language"), [], "mainlanguage", [])
  on_load {
  @form.fields[1].on(:multiselection_changed) {
  mainlangs=[]
  mainlangsmapping=[]
  langslabel, langstype, langskey, langsmapping, langsmulti = @settings[@category][2]
    index=0
  l=currentconfig("mainlanguage")
  for e in @form.fields[1].multiselections
    mainlangs.push(langstype[e])
    mainlangsmapping.push(langsmapping[e])
    index = mainlangs.size-1 if langsmapping[e]==l
    end
  label, type, key, mapping, multi = @settings[@category][3]
  @settings[@category][3] = [label, mainlangs, key, mainlangsmapping, multi]
  @form.fields[2].options = mainlangs
  @form.fields[2].index=index
  }
  @form.fields[1].trigger(:multiselection_changed)
  }
  end
def load_privacy
  setting_category(p_("Account", "Privacy"))
  make_setting(p_("Account", "Hide my profile for strangers"), :bool, "publicprofile")
  make_setting(p_("Account", "Prevent banned users from writing me private messages"), :bool, "preventbanned")
  make_setting(p_("Account", "Accept incoming voice calls"), [p_("Account", "Never"), p_("Account", "Only from my friends"), p_("Account", "From all users")], "calls")
  make_setting(p_("Account", "Black list"), :custom, Proc.new{insert_scene(Scene_Account_BlackList.new)})
  end
def load_signs
  setting_category(p_("Account", "Status and signature"))
  make_setting(p_("Account", "Status displayed after your name on all lists of users"), :text, 'status')
  make_setting(p_("Account", "Signature placed below all your forum posts"), :text, 'signature')
  make_setting(p_("Account", "Greeting read after you log in to Elten"), :text, 'greeting')
end
def load_notifications_settings
  setting_category(p_("Account", "Notifications"))
  cats=[p_("Account", "New messages"),p_("Account", "New posts in followed threads"),p_("Account", "New posts on the followed blogs"),p_("Account", "New comments on your blog"),p_("Account", "New threads on followed forums"),p_("Account", "New posts on followed forums"),p_("Account", "New friends"),p_("Account", "Friends' birthday"),p_("Account", "Mentions"),p_("Account", "Followed blog posts"), p_("Account", "Blog followers"), p_("Account", "Blog mentions"), p_("Account", "Awaiting group invitations")]
  sets = ["wn_messages", "wn_followedthreads", "wn_followedblogs", "wn_blogcomments", "wn_followedforums", "wn_followedforumsthreads", "wn_friends", "wn_birthday", "wn_mentions", "wn_followedblogposts", "wn_blogfollowers","wn_blogmentions", "wn_groupinvitations"]
  for i in 0...sets.size
    make_setting(cats[i], :whatsnew_delivery, sets[i])
    end
  end
  def load_security
    setting_category(p_("Account", "Account security"))
    make_setting(p_("Account", "Change e-mail"), :custom, Proc.new{insert_scene(Scene_Account_Mail.new)})
    make_setting(p_("Account", "Change password"), :custom, Proc.new{insert_scene(Scene_Account_Password.new)})
    make_setting(p_("Account", "Forgot password"), :custom, Proc.new { insert_scene(Scene_ForgotPassword.new) })
    make_setting(p_("Account", "Manage Two-Factor authentication"), :custom, Proc.new{insert_scene(Scene_Authentication.new)})
    make_setting(p_("Account", "Manage mail events-reporting"), :custom, Proc.new{insert_scene(Scene_Account_MailEvents.new)})
    make_setting(p_("Account", "Manage auto-login tokens"), :custom, Proc.new{insert_scene(Scene_Account_AutoLogins.new)})
    make_setting(p_("Account", "Show last logins"), :custom, Proc.new{insert_scene(Scene_Account_Logins.new)})
  end
  def load_others
    setting_category(p_("Account", "Others"))
    make_setting(p_("Account", "Premium packages"), :custom, Proc.new{insert_scene(Scene_PremiumPackages.new)})
    make_setting(p_("Account", "Export user data"), :custom, Proc.new{insert_scene(Scene_Account_Export.new)})
    make_setting(p_("Account", "Archive this account"), :custom, Proc.new{insert_scene(Scene_Account_Archive.new)})
    end
      def main
        make_window
        load_profile
        load_visitingcard
                        load_languages
        load_signs
        load_notifications_settings
        load_privacy
        load_security
        load_others
        @form.focus
        loop do
          loop_update
          @form.update
          show_category(@form.fields[0].index) if @category!=@form.fields[0].index
          if @form.fields[-3].pressed?
            apply_settings
            speak(_("Saved"))
          end
                    if @form.fields[-2].pressed? or (key_pressed?(:key_enter) and !@form.fields[@form.index].is_a?(Button) and !(@form.fields[@form.index].is_a?(EditBox) && (@form.fields[@form.index].flags&EditBox::Flags::MultiLine)>0))
            apply_settings
            alert(_("Saved"))
            $scene=Scene_Main.new
          end
          if key_pressed?(:key_escape) or @form.fields[-1].pressed?
            $scene=Scene_Main.new
          end
          break if $scene!=self or $restart==true
        end
      end
    end
    
    
    
    class Scene_Account_Password
  def main
      oldpassword = ""
  password = ""
  repeatpassword = ""
  while oldpassword == ""
    oldpassword = input_text(p_("Account", "Enter your old password."),flags: EditBox::Flags::Password, text: "", escapable: true)
  end
  if oldpassword == nil
        $scene = Scene_Main.new
    return
  end
    while password == ""
    password = input_text(p_("Account", "Enter your new password."),flags: EditBox::Flags::Password,text: "",escapable: true)
  end
  if oldpassword == nil
    $scene = Scene_Main.new
    return
  end
    while repeatpassword == ""

      repeatpassword = input_text(p_("Account", "Repeat new password."),flags: EditBox::Flags::Password,text: "",escapable: true)
  end
  if repeatpassword == nil
        $scene = Scene_Main.new
    return
  end
  if password != repeatpassword
    alert(p_("Account", "Fields: New Password and Repeat New Password have different values."))
    main
  end
  begin
    EltenLink::Accounts.change_password(elten_link, old_password: oldpassword, new_password: password)
    alert(p_("Account", "Your password has been changed."))
        $scene = Scene_Main.new
  rescue EltenLink::Error => e
    if e.code.to_s == "auth.invalid_password"
      alert(p_("Account", "The old password is incorrect."))
    else
      alert(e.message)
    end
    $scene = Scene_Main.new
  end
    end
end

class Scene_Account_Mail
  def main
      password = ""
  mail = ""
  while password == ""
    password = input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
  end
  if password == nil
    $scene = Scene_Main.new
    return
  end
    while mail == ""
    mail = input_text(p_("Account", "Enter a new e-mail address."),flags: 0,text: "",escapable: true)
  end
  if mail == nil
        $scene = Scene_Main.new
    return
  end
  begin
    EltenLink::Accounts.change_mail(elten_link, password: password, mail: mail)
    alert(p_("Account", "E-mail has been changed."))
    $scene = Scene_Main.new
  rescue EltenLink::Error => e
    if e.code.to_s == "auth.invalid_password"
      alert(p_("Account", "The old password is incorrect."))
    elsif e.code.to_s == "accounts.mail_events_enabled"
      alert(p_("Account", "Error, you must disable mail events reporting first."))
      speech_wait
    else
      alert(e.message)
    end
    $scene = Scene_Main.new
  end
    end
end
      
      class Scene_Account_AutoLogins
  def main
        al=[]
    loop do
      password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
      if password==nil
        return $scene=Scene_Main.new
        break
      else
        begin
          al=EltenLink::Accounts.auto_logins(elten_link, password)
        rescue EltenLink::Error
          alert(p_("Account", "An error occurred while authenticating the account. You might have provided an  incorrect password."))
        else
          break
          end
        end
    end
    als=al.map { |entry| [format_date(entry.created_at, false, false), entry.ip, entry.computer] }
selh=[p_("Account", "Computer"),p_("Account", "Creation IP Address"),p_("Account", "Generation date")]
selt=[]
for s in als
  selt.push([s[2],s[1],s[0]])
end
@sel=TableBox.new(selh,selt,index: 0,header: p_("Account", "Auto log in tokens"), quiet: false)
@sel.bind_context{|menu|
    menu.option(p_("Account", "Log out all sessions"), nil, :del) {
          globallogout
    }
    menu.option(_("Refresh"), nil, "r") {
    main
    }
        }
loop do
  loop_update
  @sel.update
  break if key_pressed?(:key_escape)
  break if $scene!=self
  end
$scene=Scene_Main.new
  end
def globallogout
  confirm(p_("Account", "Are you sure you want to remove all auto log in tokens and log out all sessions?  You will be logged off immediately.")) do
        loop do
      password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
      if password==nil
        @sel.focus
        return
        break
      else
        register_activity(wait: true, final: true)
        begin
          EltenLink::Accounts.global_logout(elten_link, password)
        rescue EltenLink::Error
          alert(p_("Account", "An error occurred while authenticating the account. You might have provided an  incorrect password."))
        else
          Session.name=""
          Session.token=""
          File.delete(EltenPath.join(Dirs.eltendata, "login.dat")) if FileTest.exists?(EltenPath.join(Dirs.eltendata, "login.dat"))
          $restart=true
          $scene=Scene_Main.new
          break
          return
          end
        end
    end
    end
  end
end

class Scene_Account_BlackList
  def main
            begin
              @blacklist = EltenLink::Accounts.blacklist(elten_link)
            rescue EltenLink::Error
          alert(_("Error"))
      $scene = Scene_Main.new
      return
      end
                    @blacklist.polsort!
selt = @blacklist.map{|u|user_with_status(u)}
header=p_("Account", "Black list")
              @sel = ListBox.new(selt,header: header,index: 0,flags: 0,quiet: false)
              apply_user_status_states(@sel, @blacklist)
              @sel.bind_context{|menu|context(menu)}
                              loop do
loop_update
        @sel.update
        update
        if $scene != self
          break
          end
                  end
      end
      def update
        $scene = Scene_Main.new if key_pressed?(:key_escape)
        usermenu(@blacklist[@sel.index],false) if key_pressed?(:key_enter) and @blacklist.size > 0
                                      end
        def context(menu)
          if @blacklist.size>0
            menu.useroption(@blacklist[@sel.index])
            end
          menu.option(p_("Account", "Add"), nil, "n") {
                            user=input_user(p_("Account", "User you want to add to the blacklist."))
                  if user!=nil
                  confirm(p_("Account", "The users added to your black list cannot send you private messages. Are you sure  you want to continue?")) do
                    begin
                      EltenLink::Accounts.add_to_blacklist(elten_link, user)
                      speak(p_("Account", "User %{user} has been added to your blacklist")%{:user=>user})
                      @sel.options.push(user)
                      @blacklist.push(user)
                    rescue EltenLink::Error => e
                      case e.code.to_s
                      when "accounts.blacklist_moderator"
                        alert(p_("Account", "You cannot add an administrator to the black list."))
                      when "accounts.blacklist_exists"
                        alert(p_("Account", "This user is already on your black list."))
                      when "users.not_found"
                        alert(p_("Account", "The user cannot be found."))
                      else
                        alert(e.message)
                      end
                    end
                  speech_wait
                    end
                  end
          }
          if @blacklist.size>0
          menu.option(_("Delete"), nil, :del) {
                                                  confirm(p_("Account", "Are you sure you want to remove this user from the black list?")) do
            begin
              EltenLink::Accounts.delete_from_blacklist(elten_link, @blacklist[@sel.index])
            rescue EltenLink::Error
              alert(_("Error"))
            else
              play_sound("editbox_delete")
              alert(p_("Account", "A user has been removed from the black list."))
            end
            speech_wait
            @blacklist.delete_at(@sel.index)
            @sel.options.delete_at(@sel.index)
            @sel.focus
            end
          }
          end
          menu.option(_("Refresh"), nil, "r") {
                                $scene=Scene_Account_BlackList.new
          }
                  end
                end
                
                class Scene_Account_Logins
  def main
        lg=[]
    loop do
      password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
      if password==nil
        return $scene=Scene_Main.new
        break
      else
        begin
          lg=EltenLink::Accounts.last_logins(elten_link, password)
        rescue EltenLink::Error
          alert(p_("Account", "An error occurred while authenticating the account. You might have provided an  incorrect password."))
        else
          break
          end
        end
    end
    lgs=lg.map { |entry| [format_date(entry.created_at, false, false), entry.ip] }
selh=["",""]
selt=[]
for s in lgs
  selt.push([s[0],s[1]])
end
@sel=TableBox.new(selh,selt,index: 0,header: p_("Account", "Last logins"), quiet: false)
loop do
  loop_update
  @sel.update
  break if key_pressed?(:key_escape)
  end
$scene=Scene_Main.new
  end
end

class Scene_Account_MailEvents
  def main
    @password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true) if @password==nil
    return $scene=Scene_Main.new if @password==nil
          begin
            state=EltenLink::Accounts.mail_events_state(elten_link, @password)
          rescue EltenLink::Error
            alert(_("Error"))
            return $scene=Scene_Main.new
          end
if !state.verified
  confirm(p_("Account", "If you wish, you can configure Elten to report any changes and logins  on your account from new devices to you by E-mail. To do this, you must verify your E-mail address. Do you want to do it now?")) {
  begin
    EltenLink::Accounts.verify_mail_events(elten_link, @password)
  rescue EltenLink::Error
    alert(_("Error"))
    return $scene=Scene_Main.new
  end
  code=input_text(p_("Account", "The verification code has been sent to you via E-mail. Please type it here."))
  begin
    EltenLink::Accounts.verify_mail_events(elten_link, @password, code: code)
  rescue EltenLink::Error
    alert(_("Error"))
    return $scene=Scene_Main.new
  else
    return main
  end
  }
  $scene=Scene_Main.new if $scene==self
else
enb=state.enabled ? 1 : 0
opt=(enb==0)?p_("Account", "Enable mail events reporting"):p_("Account", "Disable mail events reporting")
h=(enb==0)?p_("Account", "Mail events reporting is disabled. If you wish, you can enable it to receive information about changes made on your account and logins from new devices via E-mail"):p_("Account", "Mail events reporting is enabled.")
@sel=ListBox.new([opt,_("Exit")],header: h,index: 0,flags: ListBox::Flags::AnyDir,quiet: false)
loop do
  loop_update
  @sel.update
  if key_pressed?(:key_enter)
    case @sel.index
    when 0
e=0
e=1 if enb==0
begin
  EltenLink::Accounts.set_mail_events(elten_link, @password, enabled: e == 1)
  if e==0
    code=input_text(p_("Account", "The verification code has been sent to you via E-mail. Please type it here."))
    EltenLink::Accounts.set_mail_events(elten_link, @password, enabled: false, code: code)
  end
rescue EltenLink::Error
  alert(_("Error"))
  end
return main
      when 1
        $scene=Scene_Main.new
      end
      end
  break if $scene!=self
end  
end
    end
  end
  
  class Scene_Account_Archive
    def main
      notification = p_("Account", "Archiving your account will have the following effects:
* An indication that the account is archived will be placed next to all posts on the forum.
* The account will not be displayed in the users lists.
* The account will be removed from all contact lists.
* Users will not be able to send private messages to this account.
* The profile (including status, visiting card and signature) will be removed from the server
* You will be opted out off all groups you are not moderating or banned in
* You will be opted out of all messages conversations
* All information about threads followed by you, your pinned groups or marked threads will be removed

Attention.
Archiving an account does not mean deleting or hiding associated blogs or notes, this must be done manually before archiving.

The account will be automatically unarchived the next time you log in, but removed data will not be restored..")

form = Form.new([
txt_info = EditBox.new(p_("Account", "Information"), type: EditBox::Flags::ReadOnly, text: notification),
btn_continue = Button.new(p_("Account", "Continue")),
btn_cancel = Button.new(_("Cancel"))
])
btn_cancel.on(:press) {form.resume}
btn_continue.on(:press) {
@password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
if @password==nil
  form.resume
else
  confirm(p_("Account", "Are you sure you want to archive this account?")) {
  begin
    EltenLink::Accounts.archive(elten_link, @password)
  rescue EltenLink::Error
    alert(_("Error"))
    form.resume
    next
  end
  alert(p_("Account", "Account archived"))
  Session.name=""
  Session.token=""
  $scene = Scene_Loading.new
  form.resume
  }
  end
}
form.wait
$scene = Scene_Main.new if $scene==self
    end
  end
  
  class Scene_Account_Export
    def main
begin
  st = EltenLink::Accounts.export_status(elten_link)
rescue EltenLink::Error
  alert(_("Error"))
$scene = Scene_Main.new
return
  end
  notification = p_("Account", "No data export is available")
  if !st.ready and st.pending
    notification = p_("Account", "The export of your account data is currently being prepared. This may take up to some hours. Please return here later.")
  elsif st.ready
    notification = p_("Account", "The export of your account data is ready.")+"\n"+p_("Account", "Export date")+": "+format_date(Time.at(st.export_time))+"\n"+p_("Account", "Next export available")+": "+format_date(Time.at(st.next_time))
    end
    form = Form.new([
    txt_notification = EditBox.new(p_("Account", "Export status"), type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: notification),
    btn_download = Button.new(p_("Account", "Download data export")),
    btn_generate = Button.new(p_("Account", "Generate data export")),
    btn_close = Button.new(p_("Account", "Close"))
    ])
    form.hide(btn_download) if !st.ready
    form.hide(btn_generate) if st.ready && st.next_time>Time.now.to_i
    form.hide(btn_generate) if !st.ready && st.pending
  form.cancel_button = btn_close
  btn_close.on(:press) {form.resume}
  btn_generate.on(:press) {
  password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
if password!=nil
  begin
    EltenLink::Accounts.enqueue_export(elten_link, password)
  rescue EltenLink::Error
    alert(_("Error"))
  else
    alert(p_("Account", "Data export enqueued"))
  end
  $scene = Scene_Account_Export.new
  form.resume
else
  loop_update
  form.focus
  end
  }
    btn_download.on(:press) {
  password=input_text(p_("Account", "Enter your password."),flags: EditBox::Flags::Password,text: "",escapable: true)
if password!=nil
  begin
    et = EltenLink::Accounts.export_file(elten_link, password)
  rescue EltenLink::Error
    alert(_("Error"))
    form.focus
  else
  save(et)
  form.focus
  end
else
  loop_update
  form.focus
  end
  }
form.wait
$scene=Scene_Main.new if $scene==self
end
def save(export_file)
time = export_file.time
tm=Time.at(time.to_i)
nm=sprintf(Session.name+"_%04d%02d%02d%02d%02d.zip", tm.year, tm.month, tm.day, tm.hour, tm.min)
            dialog_open
        form=Form.new([
        tr_path = FilesTree.new(p_("Account", "Destination"), path: EltenPath.join(Dirs.user, "Downloads"), hide_files: true, quiet: true),
        edt_filename = EditBox.new(p_("Account", "File name"),type: 0,text: nm,quiet: true),
        btn_save = Button.new(_("Save")),
        btn_cancel = Button.new(_("Cancel"))
        ],index: 0,silent: false,quiet: true)
        form.cancel_button=btn_cancel
        btn_cancel.on(:press) {form.resume}
        btn_save.on(:press) {
fl=EltenPath.join(tr_path.selected, edt_filename.text)
fl+=".zip" if File.extname(fl).downcase!=".zip"
url = EltenLink::Accounts.export_download_url(export_file)
download_file(url, fl, use_waiting: true, can_cancel: true, override: false) 
alert(p_("Account", "Data export saved"))
        form.resume
        }
form.wait
          dialog_close
end
    end
