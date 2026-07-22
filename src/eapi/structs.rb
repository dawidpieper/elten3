# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2021 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  module Structs
  module Session
    @@languages=""
    @@feeds_updated=false
    @@notifications_updated=false
    class <<self
      attr_accessor :name, :token, :gender, :fullname, :moderator, :greeting
      def languages
        @@languages
      end
      def languages=(l)
        @@languages=l
      end
      def logged?
        return @name!="" && @name!=nil && @token!="" && @token!=nil
      end
      def feeds
        @feeds||={}
        @feeds
      end
      def feeds_clear
        @feeds={}
        feeds_update
      end
      def feeds_update
        @@feeds_updated=true
      end
      def feeds_updated?
        u=@@feeds_updated==true
        @@feeds_updated=false
        return u
      end
      def notifications_update
        @@notifications_updated=true
      end
      def notifications_updated?
        u=@@notifications_updated==true
        @@notifications_updated=false
        return u
      end
    end
  end
    module Configuration
      class <<self
        attr_accessor :listtype, :usepan, :soundcard, :microphone, :controlspresentation, :contextmenubar, :soundthemeactivation, :typingecho, :linewrapping, :hidewindow, :synctime, :registeractivity, :voice, :language, :voicerate, :voicevolume, :soundtheme, :volume, :usefx, :bgsounds, :voicepitch, :usedenoising, :autologin, :roundupforms, :checkupdates, :enablebraille, :useechocancellation, :usevoicedictionary, :disablefeednotifications, :iimodifiers, :iicards, :usebilinearhrtf, :sessiontime, :disablehttp2, :tcpconferences, :udppacketsize, :conferencesaudiobuffer , :conferencesaudiobuffercutoff, :disableconferencemiconrecord, :enableaudiobuffering, :saytimeperiod, :saytimetype, :autoplay, :branch, :keyboardscheme, :macoscharacternavigation
        def to_h
          h={}
          for v in instance_variables
            h[v[1..-1]]=instance_variable_get(v)
            end
          return h
          end
      end
      end
    module Lists
      class <<self
        attr_accessor :locations, :langs
        end
      end
      module Dirs
        @@eltendata=nil
        class <<self
          include EltenAPI
          attr_accessor :appsdata, :apps, :soundthemes, :extras, :temp
          def appdata
            EltenPath.normalize(EltenSystemHelpers.appdata_dir)
          end
          def user
            EltenPath.normalize(EltenSystemHelpers.user_dir)
          end
          def documents
            EltenPath.normalize(EltenSystemHelpers.documents_dir)
          end
          def desktop
            EltenPath.normalize(EltenSystemHelpers.desktop_dir)
          end
          def music
            EltenPath.normalize(EltenSystemHelpers.music_dir)
          end
          def tmp
            d=Dir.tmpdir
            d=EltenPath.normalize(d)
            d.chop! if d[-1..-1]=="/"
            return d
            end
          def eltendata
            if @@eltendata==nil
              $portable=readini("./elten.ini","Elten","Portable","0").to_i
if $portable == 0
@@eltendata = EltenPath.join(Dirs.appdata, "elten")
else
  @@eltendata = EltenPath.join(".", "eltendata")
end
end
return @@eltendata
end
def eltendata=(value)
  @@eltendata=EltenPath.normalize(value)
end
end
        end
      end
      include Structs
      end
