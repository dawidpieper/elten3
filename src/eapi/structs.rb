# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  module Structs
  module Session
    @@languages=""
    @feed_mutex = Mutex.new
    @feeds = {}
    $feeds = {}
    @feed_generation = 0
    @feed_revision = 0
    @feed_like_revision = 0
    @confirmed_feed_likes = {}
    @feed_changes_from = 0
    @feed_changed_ids = {}
    @feed_changes_read = false
    @feeds_updated = false
    @@notifications_updated=false
    class <<self
      attr_reader :name, :token, :feeds, :feed_generation, :feed_like_revision
      attr_accessor :gender, :fullname, :moderator, :greeting

      def name=(name)
        @feed_mutex.synchronize do
          clear_feed_model if @name != name
          @name = name
        end
      end

      def token=(token)
        @feed_mutex.synchronize do
          clear_feed_model if @token != token
          @token = token
        end
      end

      def languages
        @@languages
      end
      def languages=(l)
        @@languages=l
      end
      def user_state(collection: "")
        EltenLink::UserState.new(EltenLink::Client.new(self), collection: collection)
      end

      def logged?
        return @name!="" && @name!=nil && @token!="" && @token!=nil
      end
      def feed_generation_for(key)
        @feed_mutex.synchronize do
          @feed_generation if key && key[0] == @name && key[1] == @token && logged?
        end
      end

      # Legacy readers use the service snapshot separately from the UI's mutable records.
      def publish_feed_snapshot(generation, snapshot)
        @feed_mutex.synchronize do
          return false unless generation == @feed_generation
          $feeds = snapshot
          true
        end
      end

      def pending_feed_likes
        @feed_mutex.synchronize { @confirmed_feed_likes.dup }
      end

      def feeds_clear
        @feed_mutex.synchronize { clear_feed_model }
      end

      def feeds_update(ids=nil)
        @feed_mutex.synchronize { record_feed_changes(ids) }
      end

      def feeds_updated?
        @feed_mutex.synchronize do
          updated = @feeds_updated
          @feeds_updated = false
          updated
        end
      end

      def take_feed_changes(previous_revision)
        @feed_mutex.synchronize do
          next if previous_revision == @feed_revision
          @feed_changes_read = true
          changes = previous_revision == @feed_changes_from ? @feed_changed_ids.keys : :reset
          [@feed_revision, changes]
        end
      end

      def apply_feed_event(event)
        generation = event["feed_generation"]
        return false unless generation == @feed_generation
        rows = event["changed"]
        rows = JSON.parse(rows) if rows.is_a?(String)
        updates = Array(rows).each_with_object({}) do |row, result|
          feed = EltenLink::Feeds.message_from_row(row, EltenAPI::Common::FeedMessage)
          result[feed.id] = feed if feed.id > 0
        end
        @feed_mutex.synchronize do
          return false unless generation == @feed_generation
          # Older GETs can still supply fresh text and other people's votes.
          # Preserve only the current user's PUT/DELETE when it completed later.
          started_at = event.fetch("like_revision", @feed_like_revision)
          updates.each do |id, feed|
            confirmation = @confirmed_feed_likes[id]
            next unless confirmation
            if started_at < confirmation.first && (!feed.message.empty? || !feed.audio_url.empty?)
              EltenLink::Feeds.apply_liked(feed, confirmation.last)
            else
              @confirmed_feed_likes.delete(id)
            end
          end
          if event["reset"]
            @confirmed_feed_likes.keep_if { |id, _| updates.key?(id) }
            @feeds = updates
            record_feed_changes(nil)
          else
            updates.delete_if { |id, feed| EltenLink::Feeds.same_message?(@feeds[id], feed) }
            unless updates.empty?
              @feeds.merge!(updates)
              record_feed_changes(updates.keys)
            end
          end
          true
        end
      end

      def confirm_feed_like(feed, liked, generation: nil)
        @feed_mutex.synchronize do
          current = @feeds[feed.id]
          return false unless generation.nil? ? current.equal?(feed) : generation == @feed_generation
          return false unless current && (!current.message.empty? || !current.audio_url.empty?)

          @feed_like_revision += 1
          @confirmed_feed_likes[feed.id] = [@feed_like_revision, liked]
          return false unless EltenLink::Feeds.apply_liked(current, liked)
          record_feed_changes([current.id])
          true
        end
      end

      private def clear_feed_model
        @feeds = {}
        $feeds = {}
        @feed_generation += 1
        @confirmed_feed_likes.clear
        record_feed_changes(nil)
      end

      private def record_feed_changes(ids)
        return if ids && ids.empty?
        # Retain a consumed batch until the next change, so another view can read it.
        if ids.nil? || @feed_changes_read
          @feed_changed_ids.clear
          @feed_changes_from = @feed_revision
          @feed_changes_read = false
        end
        @feed_revision += 1
        if ids
          ids.each { |id| @feed_changed_ids[id] = true }
        else
          @feed_changes_from = @feed_revision
        end
        @feeds_updated = true
      end

      attr_reader :notifications_changed_at
      def notifications_update
        @notifications_changed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
        attr_accessor :iireadmessagesubjects, :notifynewprograms
        attr_accessor :listtype, :usepan, :soundcard, :microphone, :controlspresentation, :contextmenubar, :soundthemeactivation, :typingecho, :linewrapping, :hidewindow, :synctime, :registeractivity, :voice, :language, :voicerate, :voicevolume, :soundtheme, :volume, :usefx, :bgsounds, :voicepitch, :usedenoising, :autologin, :autostart, :roundupforms, :checkupdates, :enablebraille, :useechocancellation, :usevoicedictionary, :disablefeednotifications, :maintabs, :showemptynotifications, :mainnotificationfocus, :mainnotificationsort, :mainnotificationtypeorder, :iimodifiers, :iicards, :usebilinearhrtf, :disablehttp2, :tcpconferences, :udppacketsize, :conferencesaudiobuffer , :conferencesaudiobuffercutoff, :disableconferencemiconrecord, :enableaudiobuffering, :saytimeperiod, :saytimetype, :autoplay, :branch, :keyboardscheme, :macoscharacternavigation, :requestresponsecachemode, :allowp2p
        def to_h
          h={}
          instance_variables.each do |v|
            h[v[1..-1]]=instance_variable_get(v)
            end
          return h
          end
      end
      end
    module Lists
      class <<self
        attr_accessor :locations, :location_subdivisions, :langs
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
