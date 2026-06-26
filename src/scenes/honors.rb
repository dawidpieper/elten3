# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Honors
  def initialize(user=nil,toscene=nil, honor=nil)
    @user=user
    @toscene=toscene
    @honor=honor
    end
  def main
    begin
      @honors=EltenLink::Honors.list(elten_link, user: @user)
    rescue EltenLink::Error
      alert(_("Error"))
      $scene=Scene_Main.new
      return
    end
    selt=[]
    ind=0
    @honors.each do |h|
      ind=selt.size if h.id==@honor
      selt.push(makeselt(h))
    end
    selt.push(p_("Honors", "A new badge"))
    header=""
    if @user==nil
      header=p_("Honors", "Badges")
    else
      header=p_("Honors", "Badges of %{user}")%{:user=>@user}
    end
    if @user!=nil and @honors==[]
      alert(p_("Honors", "The user has been given no badges."))
      $scene=Scene_Main.new
      return
      end
    @sel=ListBox.new(selt,header: header,index: ind,flags: 0,quiet: false)
@sel.disable_item(selt.size-1) if Session.moderator==0 or @user != nil
@sel.bind_context{|menu|context(menu)}
        loop do
      loop_update
      @sel.update
      if key_pressed?(:key_enter) and @sel.index==@sel.options.size-1
                $scene=Scene_Honors_New.new
              elsif (key_pressed?(:key_enter) or key_pressed?(:key_right)) and @sel.index<@honors.size
$scene=Scene_Honors_Users.new(@honors[@sel.index].id, @user, @toscene)
              end
              if key_pressed?(:key_escape)
                if @toscene==nil
                  $scene=Scene_Main.new
                else
                  $scene=@toscene
                end
                end
              break if $scene!=self
    end
  end
  def makeselt(h)
    selt=""
    if Configuration.language=="pl-PL"
        selt=h.name
              else
                selt=h.enname
              end
              if h.levels.size>1 and @user!=nil
                selt+=" ("+p_("Honors", "Level")+" "+(h.level+1).to_s+")"
                end
              if Configuration.language=="pl-PL"
        selt+=":\r\n"+h.description+"\r\n"
else
                selt+=":\r\n"+h.endescription+"\r\n"
              end
              if h.levels.size==1
                if Configuration.language=="pl-PL"
                  selt+=h.levels[0]
                else
                  selt+=h.enlevels[0]
                end
              elsif h.levels.size>1
                h.level...h.levels.size.each do |i|
                  selt+=p_("Honors", "Level")+(i+1).to_s+": "
                  if Configuration.language=="pl-PL"
                    selt+=h.levels[i]
                  else
                    selt+=h.enlevels[i]
                    end
                  selt+="\r\n"
                  end
                end
              return selt
    end
  def context(menu)
    if @sel.index!=@sel.options.size-1
   menu.option(p_("Honors", "Set as main honor")) {
                  begin
                    EltenLink::Honors.set_main(elten_link, @honors[@sel.index])
                  rescue EltenLink::Error
                    alert(_("Error"))
                  else
                    alert(p_("Honors", "The badge has been set as default."))
                    end
   }
if Session.moderator==1
   menu.option(p_("Honors", "Grant a badge")) {
                            user=input_user(p_("Honors", "Who should be granted this badge?"))
                          if user!=nil
                              begin
                                EltenLink::Honors.award(elten_link, user: user, honor: @honors[@sel.index])
                              rescue EltenLink::Error
                                alert(_("Error"))
                              else
                                alert(p_("Honors", "The badge has been granted"))
                              end
                              end
   }
   menu.option(p_("Honors", "Edit challenges")) {
                                 loop_update
                             editchallenges(@honors[@sel.index])
                             @sel.options[@sel.index]=makeselt(@honors[@sel.index])
                             loop_update
   }
   menu.option(p_("Honors", "Delete")) {
                                 confirm(p_("Honors", "Are you sure you want to delete this badge? All users granted with this badge will loose it.")) {
                              begin
                                EltenLink::Honors.delete(elten_link, @honors[@sel.index])
                              rescue EltenLink::Error
                                alert(_("Error"))
                              else
                                alert(p_("Honors", "Honor deleted"))
                              end
                              main
                              }
   }
 end
 end
    menu.option(_("Refresh")) {
                $scene=Scene_Honors.new(@user)
   }
  end
  def editchallenges(honor)
    levels=honor.levels.deep_dup
    enlevels=honor.enlevels.deep_dup
    selt=[]
    (0..levels.size-1).each do |i|
      selt.push("#{i+1}: #{levels[i]}, #{enlevels[i]}")
      end
    selt+=[p_("Honors", "Add challenge")]
    form=Form.new([ListBox.new(selt,header: p_("Honors", "Challenges")),Button.new(_("Save")),Button.new(_("Cancel"))])
    loop do
      loop_update
      form.update
      break if key_pressed?(:key_escape) or form.fields[2].pressed?
      if form.index==0 and form.fields[0].index<levels.size and key_pressed?(0x2e)
        levels.delete_at(form.fields[0].index)
        enlevels.delete_at(form.fields[0].index)
        selt=[]
    (0..levels.size-1).each do |i|
      selt.push("#{i+1}: #{levels[i]}, #{enlevels[i]}")
      end
    selt+=[p_("Honors", "Add challenge")]
    form.fields[0].options=selt
    play_sound("editbox_delete")
    form.fields[0].focus
  end
  if form.fields[1].pressed?
    honor.levels=levels
    honor.enlevels=enlevels
    begin
      EltenLink::Honors.set_levels(elten_link, honor, levels, enlevels)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(_("Saved"))
      break
      end
    end
  if key_pressed?(:key_enter) and form.index==0
        l=form.fields[0].index
    subform=Form.new([
    EditBox.new(p_("Honors","Level"),text: levels[l]||"",quiet: true),
    EditBox.new(p_("Honors","English level"),text: enlevels[l]||"",quiet: true),
    Button.new(_("Save")),
    Button.new(_("Cancel"))])
loop do
  loop_update
  subform.update
  break if key_pressed?(:key_escape) or subform.fields[3].pressed?
  if subform.fields[2].pressed?
    levels[l]=subform.fields[0].text
    enlevels[l]=subform.fields[1].text
    break
    end
  end
  selt=[]
    (0..levels.size-1).each do |i|
      selt.push("#{i+1}: #{levels[i]}, #{enlevels[i]}")
      end
    selt+=[p_("Honors", "Add challenge")]
    form.fields[0].options=selt
    form.fields[0].focus
      end
    end
    @sel.focus if @sel!=nil
        end
  end
  
  class Scene_Honors_Users
  def initialize(honor, user=nil, toscene=nil)
    @honor=honor
    @user=user
    @toscene=toscene
    end
  def main
    begin
      honor_users = EltenLink::Honors.users(elten_link, @honor)
    rescue EltenLink::Error
      alert(_("Error"))
      $scene = Scene_Honors.new(@user, @toscene, @honor)
      return
    end
    @tusers=[]
    @tselt=[]
            honor_users.each do |honor_user|
              l=honor_user.level
              o=honor_user.name
              @tusers[l]||=[]
              @tselt[l]||=[]
      @tusers[l].push(o)
            @tselt[l].push(@tusers[l].last+" ("+p_("Honors", "level")+(l.to_i+1).to_s+")")
          end
          @selt=[]
          @users=[]
          (@tusers.size-1).downto(0) {|i|
          if @tusers[i]!=nil
    @tusers[i].polsort!
    @tselt[i].polsort!
    @users+=@tusers[i]
    @selt+=@tselt[i]
    end
    }
                selt = []
    (0...@selt.size).each do |i|
      u=@selt[i]
      selt.push(user_with_status(u, false))
      end
    @sel = ListBox.new(selt,header: "",index: 0,flags: 0,quiet: false)
    apply_user_status_states(@sel, @users, false)
    @sel.bind_context{|menu|context(menu)}
            loop do
loop_update
      @sel.update
      if key_pressed?(:key_escape) or key_pressed?(:key_left)
        $scene = Scene_Honors.new(@user, @toscene, @honor)
      end
      if key_pressed?(:key_enter)
                usermenu(@users[@sel.index],false)
        end
      break if $scene != self
      end
    end
    def context(menu)
menu.useroption(@users[@sel.index])
menu.option(_("Refresh")) {
main
}
end
end

  class Scene_Honors_New
    def main
      @form=Form.new([EditBox.new(p_("Honors", "Badge name"),text: "",quiet: true),EditBox.new(p_("Honors", "Badge description"),text: "",quiet: true),EditBox.new(p_("Honors", "Badge name in English"),text: "",quiet: true),EditBox.new(p_("Honors", "Badge description in English"),text: "",quiet: true),Button.new(p_("Honors", "Add")),Button.new(_("Cancel"))])
      loop do
        loop_update
        @form.update
        break if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==5)
          if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index==4
            honorname=@form.fields[0].text
            honordescription=@form.fields[1].text
                        honorenname=@form.fields[2].text
            honorendescription=@form.fields[3].text
            begin
              EltenLink::Honors.add(elten_link, name: honorname, description: honordescription, enname: honorenname, endescription: honorendescription)
            rescue EltenLink::Error
                            alert(_("Error"))
            else
              alert(p_("Honors", "The badge has been added"))
            end
            speech_wait
            break
            end
      end
      $scene=Scene_Honors.new
    end
  end
  
class Struct_Honor < EltenLink::Honor
end
