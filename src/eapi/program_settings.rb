# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "monitor"

module Programs
  module ProgramSettings
    SETTINGS_FILE = "settings.json".freeze
    UNSET = Object.new.freeze

    BoundSetting = Struct.new(:label, :type, :key, :getter, :setter, :mapping, :multi)
    ActionSetting = Struct.new(:label, :callback)

    class Context
      attr_reader :runtime, :name

      def initialize(runtime)
        @runtime = runtime
        @name = "settings_form"
      end

      def invoke(callback, *arguments)
        Programs.with_runtime(@runtime) { callback.call(*arguments) }
      end
    end

    class Store
      def initialize(runtime, file = SETTINGS_FILE)
        @runtime = runtime
        @file = file.to_s
        @monitor = Monitor.new
        @data = nil
        @dirty = false
      end

      def get(key, default)
        @monitor.synchronize do
          load_data
          @data.key?(key.to_s) ? @data[key.to_s] : duplicate_default(default)
        end
      end

      def set(key, value)
        @monitor.synchronize do
          load_data
          @data[key.to_s] = value
          @dirty = true
        end
        value
      end

      def transaction
        @monitor.synchronize do
          load_data
          previous = @data.dup
          previous_dirty = @dirty
          begin
            yield
            flush
          rescue Exception
            @data = previous
            @dirty = previous_dirty
            raise
          end
        end
      end

      private

      def load_data
        return if @data != nil
        value = @runtime.read_json(@file, :default => {})
        @data = value.is_a?(Hash) ? value.each_with_object({}) { |(key, item), result| result[key.to_s] = item } : {}
      end

      def flush
        return true if !@dirty
        written = @runtime.write_json(@file, @data)
        raise Programs::ProgramError, "Cannot save program settings" if !written
        @dirty = false
        true
      end

      def duplicate_default(value)
        value.is_a?(Array) || value.is_a?(Hash) ? value.dup : value
      end
    end

    class Collector
      attr_reader :entries

      def initialize
        @entries = []
      end

      def setting_category(_label)
      end

      def make_bound_setting(label, type, key, getter, setter, mapping = nil, multi = false)
        @entries << BoundSetting.new(label, type, key, getter, setter, mapping, multi)
      end

      def make_setting(label, type, callback)
        raise Programs::ProgramError, "Unsupported quick-settings entry" if type != :custom
        @entries << ActionSetting.new(label, callback)
      end
    end

    class Builder
      def initialize(builder, store)
        @builder = builder
        @store = store
      end

      def boolean(key, label:, default: false, get: nil, set: nil)
        getter, setter = binding_for(key, default, get, set)
        @builder.boolean(key, :label => label, :get => getter, :set => setter)
      end

      def integer(key, label:, default: UNSET, range: nil, get: nil, set: nil)
        default = range.begin if default.equal?(UNSET) && range.is_a?(Range)
        default = 0 if default.equal?(UNSET)
        getter, setter = binding_for(key, default, get, set)
        @builder.integer(key, :label => label, :range => range, :get => getter, :set => setter)
      end

      def text(key, label:, default: "", get: nil, set: nil)
        getter, setter = binding_for(key, default, get, set)
        @builder.text(key, :label => label, :get => getter, :set => setter)
      end

      def choice(key, label:, choices:, default: UNSET, get: nil, set: nil)
        default = first_choice_value(choices) if default.equal?(UNSET)
        getter, setter = binding_for(key, default, get, set)
        @builder.choice(key, :label => label, :choices => choices, :get => getter, :set => setter)
      end

      def multi_choice(key, label:, choices:, default: [], get: nil, set: nil)
        getter, setter = binding_for(key, default, get, set)
        @builder.multi_choice(key, :label => label, :choices => choices, :get => getter, :set => setter)
      end

      def action(key, label:, &callback)
        @builder.action(key, :label => label, &callback)
      end

      private

      def binding_for(key, default, getter, setter)
        custom_getter = getter != nil
        custom_setter = setter != nil
        if custom_getter != custom_setter
          raise Programs::ProgramError, "Quick setting #{key} must provide both get and set or neither"
        end
        return [getter, setter] if custom_getter
        [
          proc { @store.get(key, default) },
          proc { |value| @store.set(key, value) }
        ]
      end

      def first_choice_value(choices)
        return choices.values.first if choices.is_a?(Hash)
        first = Array(choices).first
        first.is_a?(Array) && first.size == 2 ? first[1] : first
      end
    end

    class Dialog
      include EltenAPI

      def initialize(runtime, title, entries, store)
        @runtime = runtime
        @title = title.to_s
        @entries = entries
        @store = store
        @controls = []
        @result = :cancel
      end

      def show
        opened = false
        raise Programs::ProgramError, "Program settings form cannot be empty" if @entries.empty?
        fields = []
        fields << Static.new(@title) if @title != ""
        @entries.each do |entry|
          if entry.is_a?(BoundSetting)
            control = make_control(entry)
            @controls << [entry, control]
            fields << control
          else
            fields << make_action_button(entry)
          end
        end
        apply_button = Button.new(_("Apply"))
        ok_button = Button.new(_("OK"))
        cancel_button = Button.new(_("Cancel"))
        fields.push(apply_button, ok_button, cancel_button)
        dialog_open
        opened = true
        form = Form.new(fields, :quiet => true)
        form.header = @title
        form.accept_button = ok_button
        form.cancel_button = cancel_button

        apply_button.on(:press) { speak(_("Saved")) if apply_values }
        ok_button.on(:press) do
          if apply_values
            @result = :ok
            form.resume
          end
        end
        cancel_button.on(:press) do
          @result = :cancel
          form.resume
        end

        form.wait
        @result
      ensure
        dialog_close if opened
      end

      private

      def make_control(setting)
        current = setting.getter.call.to_s
        case setting.type
        when :bool
          CheckBox.new(setting.label, :checked => current == "true")
        when :number
          EditBox.new(setting.label, :type => EditBox::Flags::Numbers, :text => current, :quiet => true)
        when :text
          EditBox.new(setting.label, :type => 0, :text => current, :quiet => true)
        else
          make_choice_control(setting, current)
        end
      rescue Exception => error
        Log.error("Cannot read program setting #{setting.key}: #{error.class}: #{error.message}")
        raise
      end

      def make_choice_control(setting, current)
        mapping = Array(setting.mapping)
        index = setting.multi ? 0 : (mapping.find_index(current) || 0)
        flags = setting.multi ? ListBox::Flags::MultiSelection : 0
        control = ListBox.new(setting.type, :header => setting.label, :index => index, :flags => flags)
        if setting.multi
          selected = current.split(",")
          mapping.each_with_index { |value, index_value| control.selected[index_value] = true if selected.include?(value) }
        end
        control
      end

      def make_action_button(setting)
        button = Button.new(setting.label)
        button.on(:press) do
          begin
            setting.callback.call
          rescue Exception => error
            report_error(error)
          end
        end
        button
      end

      def apply_values
        @store.transaction do
          @controls.each do |setting, control|
            setting.setter.call(serialized_value(setting, control))
          end
        end
        true
      rescue Exception => error
        report_error(error)
        false
      end

      def serialized_value(setting, control)
        return control.value ? "true" : "false" if setting.type == :bool
        return control.value.to_i if setting.type == :number
        return control.value.to_s if setting.type == :text
        mapping = Array(setting.mapping)
        return mapping[control.value] if !setting.multi
        values = []
        mapping.each_with_index { |value, index| values << value if control.selected[index] }
        values.join(",")
      end

      def report_error(error)
        Log.error("Cannot apply program settings: #{error.class}: #{error.message}")
        alert(p_("Program", "Cannot save settings: %{error}") % { :error => error.message.to_s })
      end
    end

    class << self
      def show(runtime, title: "", &definition)
        raise Programs::ProgramError, "Program settings require a loaded application runtime" if runtime == nil || !Programs.runtime_registered?(runtime)
        raise Programs::ProgramError, "Program settings definition is required" if !definition.is_a?(Proc)
        owner = $currentthread if defined?($currentthread)
        owner ||= $mainthread if defined?($mainthread)
        if owner != nil && Thread.current != owner
          raise Programs::ProgramError, "Program settings can be shown only on Elten's active interaction thread"
        end

        store = Store.new(runtime)
        collector = Collector.new
        context = Context.new(runtime)
        internal_builder = Programs::Extensions::SettingsBuilder.new(collector, context)
        internal_builder.category(title.to_s == "" ? "Settings" : title.to_s)
        builder = Builder.new(internal_builder, store)
        Programs.with_runtime(runtime) { definition.call(builder) }
        internal_builder.render
        Dialog.new(runtime, title, collector.entries, store).show
      end
    end
  end
end

class Program
  class << self
    # Opens a flat modal settings form owned by this program.
    #
    # Fields without get/set callbacks are persisted in the program's
    # settings.json file. Supplying both callbacks binds a field to custom
    # program state instead.
    #
    #   show_settings("Player") do |settings|
    #     settings.boolean(:autoplay, :label => "Autoplay", :default => true)
    #     settings.integer(:volume, :label => "Volume", :range => 0..100, :default => 80)
    #   end
    #
    # Returns :ok or :cancel. Apply persists without closing the form.
    def show_settings(title = nil, **options, &definition)
      title = options[:title] if options.key?(:title)
      title = name.to_s if title == nil || title.to_s == ""
      Programs::ProgramSettings.show(@app_runtime, :title => title, &definition)
    end
  end

  def show_settings(title = nil, **options, &definition)
    self.class.show_settings(title, **options, &definition)
  end
end
