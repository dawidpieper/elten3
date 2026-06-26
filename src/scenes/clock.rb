# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Clock
    def main
        @field=[]
              @field[0]=ListBox.new([],header: p_("Clock", "Alarms"))
              @field[1]=Button.new(_("Save"))
              @field[2]=Button.new(_("Cancel"))
              @alarms=EltenAPI::Alarms.load.map{|alarm| alarm.dup}
              sel=[]
              @alarms.each do |a|
                  sel.push("#{p_("Clock","Hour")}: #{sprintf("%02d:%02d",a[0],a[1])}, #{p_("Clock","Type")}: #{if a[2]==0;p_("Clock", "One time");else;p_("Clock", "repeated");end}")
                end
                @field[0].options=sel
                @form=Form.new(@field)
                @form.bind_context{|menu|context(menu)}
                loop do
                    loop_update
                      @form.update
                        if key_pressed?(:key_escape) or @form.fields[2].pressed?
                              $scene=Scene_Main.new
                                      return
                                              break
                                            end
                                            if key_pressed?(:key_enter) and @form.index==0
                                              editalarm(@form.fields[0].index)
                                              end
                                                                           if @form.fields[1].pressed?
                                                                                 EltenAPI::Alarms.replace(@alarms, true)
                                                                                   alert(_("Saved"))
                                                                                     $scene=Scene_Main.new
                                                                                       break
                                                                                     end
                                                                                   end
                                                                                 end
                                                                                 def context(menu)
                                                                                   if @alarms.size>0
                                                                                     menu.option(p_("Clock", "Edit alarm")) {
                                                                                     editalarm(@form.fields[0].index)
                                                                                     }
                                                                                                                                                                          menu.option(p_("Clock", "Delete alarm"), nil, :del) {
                                                                                     deletealarm(@form.fields[0].index)
                                                                                     }
                                                                                     end
                                                                                   menu.option(p_("Clock", "New alarm"), nil, "n") {
                                                                                   editalarm
                                                                                   }
                                                                                   end
                                                                                 def editalarm(alarmindex=nil)
                                                                                   self.class.editalarm(alarmindex, @alarms)
                                                                                   refresh
                                                                                   @form.fields[0].focus
                                                                                   end
                                                                                   def self.editalarm(alarmindex=nil, alarms=nil)
                                                                                     save=false
                                                                                     if alarms==nil
                                                                                       alarms=EltenAPI::Alarms.load.map{|alarm| alarm.dup}
                                                                                       save=true
                                                                                       end
                                                                                                                                                                        alarmindex=alarms.size if alarmindex==nil
                                                                                                                                   a=[Time.now.hour,Time.now.min,0]
                                                a=alarms[alarmindex] if alarmindex.is_a?(Numeric) && alarms[alarmindex]!=nil
                                                c=(0..59).to_a.map{|i|i.to_s}
                                                  form=Form.new([ListBox.new(c[0..23],header: p_("Clock", "Hour"),index: a[0]),ListBox.new(c[0..59],header: p_("Clock", "Minute"),index: a[1]),ListBox.new([p_("Clock", "One time"),p_("Clock", "Repeated")],header: p_("Clock", "Type"),index: a[2]),EditBox.new(p_("Clock", "Alarm description"), type: 0, text: a[3], quiet: true),Button.new(_("Save")),Button.new(_("Cancel"))])
                                                  loop do
                                                    loop_update
                                                      form.update
                                                        break if key_pressed?(:key_escape) or form.fields[5].pressed?
                                                              if form.fields[4].pressed?
                                                                    a=[form.fields[0].index,form.fields[1].index,form.fields[2].index,form.fields[3].text]
                                                                        alarms[alarmindex]=a
                                                                        if save
                                                                        EltenAPI::Alarms.replace(alarms, true)
                                                                        alert(_("Saved"))
                                                                        end
                                                                             break
                                                                           end
                                                                         end
                                                                         loop_update
                                                                                                                                                    end
                                                                         def deletealarm(alarmindex)
                                                                                                                                                      @alarms.delete_at(alarmindex)
refresh
                                                                             play_sound("editbox_delete")
                                                                             loop_update
                                                                             @field[0].say_option
                                                                           end
                                                                           def refresh
                                                                                                                                                        sel=[]
                                                                           @alarms.each do |a|
                                                                               sel.push("#{p_("Clock","Hour")}: #{sprintf("%02d:%02d",a[0],a[1])}, #{p_("Clock","Type")}: #{if a[2]==0;p_("Clock", "One time");else;p_("Clock", "Repeated");end}: #{(a[3]!=nil)?a[3]:""}")
                                                                             end
                                                                             @field[0].options=sel 
                                                                             end
                                                                                 end
