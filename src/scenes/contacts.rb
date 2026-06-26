# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Contacts
  def initialize(type=0)
    @type=type
  end
      def main
      if Session.name=="guest"
      alert(_("This section is unavailable for guests"))
      $scene=Scene_Main.new
      return
      end
      begin
        @contact = EltenLink::Contacts.list(elten_link, birthday: @type == 1)
        err = 0
      rescue EltenLink::Error => e
        Log.warning("Contacts list failed: #{e.message}")
        @contact = []
        err = e.code.to_i
      end
    case err
    when -1
      alert(_("Database Error"))
      $scene = Scene_Main.new
      return
      when -2
        alert(_("Token expired"))
        $scene = Scene_Loading.new
        return
      end
      if @contact.size < 1
        alert(p_("Contacts", "Empty list"))
              end
      selt = []
      (0..@contact.size - 1).each do |i|
        selt[i] = user_with_status(@contact[i])
        end
      header=p_("Contacts", "Contacts")
      header="" if @type>0
              @sel = ListBox.new(selt,header: header, index: 0, flags: 0, quiet: false)
              apply_user_status_states(@sel, @contact)
              @sel.bind_context{|menu|context(menu)}
            loop do
loop_update
        @sel.update if @contact.size > 0
        update
        if $scene != self
          break
          end
                  end
      end
      def update
        if key_pressed?(:key_escape) or (@type==1 && key_pressed?(:key_left))
          case @type
          when 0
          $scene = Scene_Main.new
          when 1
            begin
              EltenLink::Contacts.acknowledge_birthdays(elten_link)
            rescue EltenLink::Error => e
              Log.warning("Contact birthday acknowledgement failed: #{e.message}")
            end
            $scene=Scene_Notifications.new
            end
        end
        if key_pressed?(0x2e) and @type==0
          if @contact.size >= 1
          if confirm(p_("Contacts", "Are you sure you want to delete this contact?"))
            $scene = Scene_Contacts_Delete.new(@contact[@sel.index],self)
            @sel.disable_item(@sel.index)
loop_update            
            end
          end
          end
        if key_pressed?(:key_enter) and @contact.size > 0
                    usermenu(@contact[@sel.index],false)
          end
        end
            

        def context(menu)
                  if @contact.size>0
          menu.useroption(@contact[@sel.index])
        end
        if @type==0
          menu.option(p_("Contacts", "New contact"), nil, "n") {
                          $scene = Scene_Contacts_Insert.new
          }
          end
          end
        end
        
        class Scene_Contacts_Insert
          def initialize(user="",scene=nil)
            @user = user
            @scene = scene
          end
          def main
                        user = @user
            while user==""
              user = input_text(p_("Contacts", "Enter the name of the user you want to add to your contacts' list."), flags: 0, text: "", escapable: true)
            end
            if user==nil
              $scene=Scene_Contacts.new
              return
              end
            user=finduser(user) if user.upcase==finduser(user).upcase
            if user_exists(user)
              begin
                EltenLink::Contacts.add(elten_link, user)
                err = 0
              rescue EltenLink::Error => e
                Log.warning("Contact add failed: #{e.message}")
                err = e.code.to_i
              end
          else
            err=-5
            end
            case err
            when 0
              alert(p_("Contacts", "Contact was added."))
              $scene = @scene
              when -1
                alert(_("Database Error"))
                $scene = Scene_Main.new
                when -2
                  alert(_("Token expired"))
                  $scene = Scene_Loading.new
                  when -3
                    alert(p_("Contacts", "This user is already added to your contacts' list."))
                    $scene = @scene
                    when -5
                      alert(p_("Contacts", "This user does not exist."))
                      $scene = Scene_Contacts.new
                    end
                                      $scene = Scene_Contacts.new if $scene == nil
                                end
          end
          
                  class Scene_Contacts_Delete
          def initialize(user="",scene=nil)
            @user = user
            @scene = scene
          end
          def main
            user = @user
            while user==""
              user = input_text(p_("Contacts", "Type a username which you want to remove from your contact list."))
            end
                        begin
                          EltenLink::Contacts.delete(elten_link, user)
                          err = 0
                        rescue EltenLink::Error => e
                          Log.warning("Contact delete failed: #{e.message}")
                          err = e.code.to_i
                        end
            case err
            when 0
              alert(p_("Contacts", "Contact has been deleted."))
              $scene = @scene
              when -1
                alert(_("Database Error"))
                $scene = Scene_Main.new
                when -2
                  alert(_("Token expired"))
                  $scene = Scene_Loading.new
                  when -3
                    alert(p_("Contacts", "This user is not added to your contacts' list."))
                    $scene = @scene
                    when -5
                      alert(p_("Contacts", "This user does not exist."))
                      $scene = Scene_Contacts.new
                    end
                    $scene = Scene_Contacts.new if $scene == nil
            end
          end
