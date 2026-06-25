# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Admins
  def main(cat=0, subcat=0)
    @indexes||=[]
    @selt=[]
    @users=[]
    @subcats=[]
    begin
        case cat
    when 0
        @selt=[p_("Admins", "Council of elders"), p_("Admins", "Developers"), p_("Admins", "Translators"), p_("Admins", "Community Administrators"), p_("Admins", "Recommended groups Moderators"), p_("Admins", "Sponsors")]
    @users=[]
    when 1
      @users = EltenLink::Admins.users(elten_link, "elders")
    @selt=@users.deep_dup
    when 2
@users = EltenLink::Admins.users(elten_link, "developers")
    @selt=@users.deep_dup
    when 3
      if subcat==0
        ld=loadedlanguages
        i=0
      for lo in ld
        l=lo.mo
        lang=Lists.langs[lo.realcode[0..1].downcase]['name']
                            @selt.push(lang)
                            @subcats.push(i+1)
                            i+=1
                            end
                          else
                            ld=loadedlanguages
                            f=ld[subcat-1].mo
                            @users=[]
                            if (/Language-Team: ([^\n]+)\n/=~f)!=nil
                              @users=$1.delete(" \t").split(",")
                              end
      @selt=@users.deep_dup
            end
    when 4
      EltenLink::Admins.administrators(elten_link).each do |user, label|
        @users.push(user)
        @selt.push(user+" ("+label+")")
        end
    when 5
      if subcat==0
        @groups={}
        EltenLink::Admins.moderator_groups(elten_link).each do |group|
          @groups[group[:id]] = group[:users]
          @selt.push(group[:name])
          @subcats.push(group[:id])
        end
      else
        @users=@groups[subcat]
        @selt=@users.deep_dup
      end
      when 6
        @users = EltenLink::Admins.users(elten_link, "sponsors")
    @selt=@users.deep_dup
      end
    rescue EltenLink::Error => e
      Log.warning("Admins list failed: #{e.message}")
      alert(_("Error"))
      $scene = Scene_Main.new if cat == 0
      return main(0) if cat > 0
      return
    end
      for i in 0...@users.size
        @selt[i]=user_with_status(@users[i], true, true, "\r\n")
        end
    h=""
    h=p_("Admins", "Administrators and authors") if cat==0
    ind=@indexes[cat]||0
    ind=0 if subcat>0
    @sel=ListBox.new(@selt,header: h,index: ind, flags: 0, quiet: false)
    apply_user_status_states(@sel, @users) if @users.size>0
    loop do
      loop_update
      @sel.update
      if @sel.selected? or (@sel.expanded? and @sel.index>=@users.size && @sel.options.size>0) or (key_pressed?(:key_alt) and @sel.index<@users.size)
        if cat==0
          @indexes={0=>@sel.index}
          return main(@sel.index+1)
          else
        if @sel.index>=@users.size
          @indexes[cat]=@sel.index
          return main(cat,@subcats[@sel.index])
                  else
          usermenu(@users[@sel.index])
          loop_update
          end
          end
        end
      if key_pressed?(:key_escape) or (key_pressed?(:key_left) and cat>0)
        if subcat>0
          return main(cat)
        elsif cat>0
          return main(0)
        else
          break
          end
        end
    end
    $scene=Scene_Main.new
  end
  end
