# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "json"
require "digest"
require "fileutils"

module EltenAPI
  module Common
    class Draft
      include EltenAPI

      MODES = %w[disabled local server].freeze

      def initialize(key, config_key:, collection:, empty: nil)
        @key, @config_key, @collection = key, config_key, collection
        @empty = empty || proc { |data| data["text"].to_s == "" }
        @auth = EltenLink::Client.session_auth_params.transform_values { |value| value.to_s.dup.freeze }.freeze
        account = Digest::SHA256.hexdigest(@auth.fetch("name", "").downcase)
        @directory = EltenPath.join(Dirs.eltendata, "drafts", account, @collection)
        @saved = {}
        @known = {}
        @bindings = Controls::FormBindings.new
        @next_autosave = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
      end

      def restore(data, editor: false, fallback_key: nil)
        @editor = editor
        return data if @loaded
        @loaded = true
        target = mode
        return data if target == "disabled" && !editor
        targets = target == "disabled" ? %w[local server] : [target]
        keys = [entry_key(data), fallback_key].compact.map(&:to_s).uniq
        copies = {}
        targets.each do |backend|
          begin
            keys.each do |key|
              ensure_session!
              stored = backend == "server" ? server.read(key) : read_local(key)
              next if stored == nil
              raise TypeError, "Invalid draft" unless stored.is_a?(Hash) && stored["text"].is_a?(String)
              next if block_given? && !yield(stored)
              copies[backend] = [key, stored]
              break
            end
          rescue StandardError => error
            Log.warning("Cannot restore draft: #{error.class}: #{error.message}")
            alert(p_("Drafts", "The draft could not be restored."))
          end
        end
        return data if copies.empty?
        prompt = target == "disabled"
        if prompt
          selected = selector([p_("Drafts", "Load"), p_("Drafts", "Ignore"), p_("Drafts", "Discard")],
            header: p_("Drafts", "A saved draft is available. Would you like to load it?"),
            cancel_index: 1, flags: Controls::ListBox::Flags::AnyDir)
          return data if selected == 1
          if selected == 2
            copies.each { |backend, (key, _)| @known[[backend, key]] = true }
            discard(detach: false)
            return data
          end
          target = copies.keys.first
          if copies.size > 1
            selected = selector([p_("Drafts", "Local draft"), p_("Drafts", "Server draft")],
              header: p_("Drafts", "Select a draft"), cancel_index: -1, flags: Controls::ListBox::Flags::AnyDir)
            return data if selected < 0
            target = copies.keys[selected]
          end
        end
        key, stored = copies[target]
        @known[[target, key]] = true
        @saved[[target, key]] = stored
        return data unless prompt || empty?(data)
        @autoload = target == "server" && stored["text"] != ""
        @restored = true
        data.merge(stored)
      end

      def bind(form, field, context: true, &snapshot)
        @bindings.clear
        @snapshot = snapshot
        field.params[:draft] = self
        if @restored
          field.index = field.check = field.text_len
          @restored = false
        end
        @bindings.on(field, :focus) do
          if @autoload
            @autoload = false
            play_sound("editbox_autoload")
          end
        end
        if context
          @bindings.context(form, p_("Drafts", "Drafts")) do |menu|
            self.context(menu) if !context.respond_to?(:call) || context.call
          end
        end
        @bindings.timer(form, 1, repeat: true) do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if now >= @next_autosave
            @next_autosave = now + 60
            autosave
          end
        end
        self
      end

      def context(menu)
        menu.option(p_("Drafts", "Remember drafts")) do
          selected = selector(mode_labels, header: p_("Drafts", "Remember drafts"),
            start_index: MODES.index(mode), cancel_index: -1, flags: Controls::ListBox::Flags::AnyDir)
          LocalConfig[@config_key] = MODES[selected] if selected >= 0
        end
      end

      def close(detach: true, editor: @editor)
        data = snapshot
        target = mode
        if !empty?(data) && target == "disabled" && editor
          selected = selector([p_("Drafts", "Discard"), p_("Drafts", "Return to editing"),
            p_("Drafts", "Save locally"), p_("Drafts", "Save on the server")],
            header: p_("Drafts", "What would you like to do with the draft?"),
            start_index: 1, cancel_index: 1, flags: Controls::ListBox::Flags::AnyDir)
          return discard(detach: detach) if selected == 0
          return false unless [2, 3].include?(selected)
          target = MODES[selected - 1]
          LocalConfig[@config_key] = target
        elsif !empty?(data) && target == "disabled"
          selected = selector([p_("Drafts", "Discard"), p_("Drafts", "Return to editing"), p_("Drafts", "Remember")],
            header: p_("Drafts", "What would you like to do with the draft?"), start_index: 1, cancel_index: 1, flags: Controls::ListBox::Flags::AnyDir)
          case selected
          when 0
            return discard(detach: detach)
          when 2
            target = selector([p_("Drafts", "Remember locally"), p_("Drafts", "Remember on the server"), _("Cancel")],
              header: p_("Drafts", "Remember drafts"), cancel_index: 2, flags: Controls::ListBox::Flags::AnyDir)
            return false unless [0, 1].include?(target)
            target = MODES[target + 1]
            LocalConfig[@config_key] = target
          else
            return false
          end
        end
        return discard(detach: detach) if empty?(data)
        return false unless save(data, target: target, wait: true)
        self.detach if detach
        true
      end

      def sent
        discard(detach: false)
      end

      def detach
        @bindings.clear
      end

      def autosave
        return if @waiting
        save(snapshot)
      end

      private

      def mode
        value = LocalConfig[@config_key, "disabled", type: :string]
        MODES.include?(value) ? value : "disabled"
      end

      def mode_labels
        [p_("Drafts", "Do not remember"), p_("Drafts", "Remember locally"), p_("Drafts", "Remember on the server")]
      end

      def snapshot
        JSON.parse(JSON.generate(@snapshot.call))
      end

      def ensure_session!
        return if !@auth.empty? && @auth == EltenLink::Client.session_auth_params
        raise EltenLink::Error.new("The user session has changed", code: "auth.session_changed")
      end

      def server
        @server ||= EltenLink::UserState.new(EltenLink::Client.new(self), collection: @collection)
      end

      def empty?(data)
        @empty.call(data)
      end

      def entry_key(data)
        (@key.respond_to?(:call) ? @key.call(data) : @key).to_s
      end

      def save(data, target: mode, wait: false)
        @waiting = wait
        finish_pending(wait)
        return true if @pending != nil || target == "disabled"
        key = entry_key(data)
        value = empty?(data) ? nil : data
        if value == nil
          previous = @known.find { |(backend, _), known| known && backend == target }
          return true unless previous
          key = previous[0][1]
        end
        address = [target, key]
        return true if value == @saved[address] && !(@known[address] && value == nil)
        ensure_session!
        store = server if target == "server"
        obsolete = @known.select { |(backend, old_key), known| known && backend == target && old_key != key }.keys
        @known[address] = true
        @pending_address, @pending_value, @pending_removed = address, value, obsolete
        @pending = Tasks.start do |token|
          ensure_session!
          write_record(target, key, value, store, token)
          obsolete.each { |backend, old_key| write_record(backend, old_key, nil, store, token) }
          true
        end
        return true unless wait
        success = finish_pending(true)
        alert(p_("Drafts", "The draft could not be saved. Your text is still in the editor.")) unless success
        success
      rescue StandardError => error
        report_error(error, wait)
        false
      ensure
        @waiting = false
      end

      def finish_pending(wait)
        return true if @pending == nil
        while wait && !@pending.done?
          loop_update
          sleep(0.01)
        end
        return false unless @pending.done?
        result = @pending.take
        @pending = nil
        if result.error
          report_error(result.error, false)
          return false
        end
        @saved[@pending_address] = @pending_value
        @known[@pending_address] = @pending_value != nil
        @pending_removed.each do |address|
          @saved.delete(address)
          @known.delete(address)
        end
        true
      end

      def discard(detach: true)
        @waiting = true
        finish_pending(true)
        targets = @known.select { |_, known| known }.keys
        targets.each do |target, key|
          ensure_session!
          store = server if target == "server"
          @pending_address, @pending_value, @pending_removed = [target, key], nil, []
          @pending = Tasks.start do |token|
            ensure_session!
            write_record(target, key, nil, store, token)
            true
          end
          unless finish_pending(true)
            alert(p_("Drafts", "The draft could not be deleted."))
            return false
          end
        end
        @autoload = false
        self.detach if detach
        true
      rescue StandardError => error
        report_error(error, true)
        false
      ensure
        @waiting = false
      end

      def write_record(target, key, value, store, token)
        if target == "server"
          if value == nil
            store.delete(key, cancellation_token: token)
          else
            store.write(key, value, override: true, evict_oldest: true, ttl: 0, cancellation_token: token)
          end
        else
          write_local(key, value)
        end
      end

      def report_error(error, show)
        Log.warning("Cannot save draft: #{error.class}: #{error.message}")
        alert(p_("Drafts", "The draft could not be saved. Your text is still in the editor.")) if show
      end

      def local_path(key)
        EltenPath.join(@directory, "#{Digest::SHA256.hexdigest(key)}.json")
      end

      def read_local(key)
        path = local_path(key)
        File.file?(path) ? JSON.parse(File.binread(path)) : nil
      end

      def write_local(key, value)
        path = local_path(key)
        if value == nil
          File.delete(path) if File.file?(path)
          return
        end
        FileUtils.mkdir_p(File.dirname(path))
        temporary = "#{path}.tmp-#{$$}-#{Thread.current.object_id}"
        File.binwrite(temporary, JSON.generate(value))
        File.rename(temporary, path)
      ensure
        File.delete(temporary) if temporary != nil && File.file?(temporary)
      end
    end
  end
end
