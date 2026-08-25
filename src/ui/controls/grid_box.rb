# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
         class GridBox < FormField
           attr_accessor :x, :y, :width, :height, :header, :silent, :border_sound, :speech
           attr_reader :labels

           ACTION_KEY_ALIASES = {
             "esc" => "escape",
             "return" => "enter",
             "arrow_left" => "left",
             "arrow_right" => "right",
             "arrow_up" => "up",
             "arrow_down" => "down",
             "pageup" => "page_up",
             "pagedown" => "page_down",
             "del" => "delete",
             "ins" => "insert",
             "comma" => ",",
             "minus" => "-",
             "period" => "."
           }.freeze
           ACTION_MODIFIERS = [:shift, :control, :option, :command, :main_modifier, :word_modifier].freeze
           NAVIGATION_KEYS = [:left, :right, :up, :down].freeze

           def initialize(width, height, header: "", x: 0, y: 0, quiet: true)
             @width = [width.to_i, 1].max
             @height = [height.to_i, 1].max
             @x = [[x.to_i, 0].max, @width - 1].min
             @y = [[y.to_i, 0].max, @height - 1].min
             @header = text_utf8(header)
             @silent = false
             @border_sound = true
             @speech = true
             @labels = Array.new(@height) { Array.new(@width, "") }
             reset_action_bindings
             focus if quiet == false
           end

           # Binds an input source to an action reported through the :action event.
           # A source may be a key or a key followed by modifiers, for example
           # :space or [:f, :shift]. The event receives [name, source, x, y].
           def bind_action(name, key:)
             raise ArgumentError, "action name must be convertible to a symbol" if !name.respond_to?(:to_sym)
             action = name.to_sym
             source = normalize_action_source(key)
             @action_bindings[source] = action
             self
           end

           def unbind_action(key)
             @action_bindings.delete(normalize_action_source(key))
             self
           end

           def reset_action_bindings
             @action_bindings = {}
             bind_action(:select, key: :enter)
             bind_action(:select, key: :space)
             self
           end

           def action_bindings
             @action_bindings.each_with_object({}) do |(source, action), bindings|
               bindings[source.is_a?(Array) ? source.dup : source] = action
             end
           end

           def resize(width, height)
             old = @labels
             @width = [width.to_i, 1].max
             @height = [height.to_i, 1].max
             @x = [[@x.to_i, 0].max, @width - 1].min
             @y = [[@y.to_i, 0].max, @height - 1].min
             @labels = Array.new(@height) { Array.new(@width, "") }
             for row in 0...[@height, old.size].min
               for col in 0...[@width, old[row].to_a.size].min
                 @labels[row][col] = old[row][col]
               end
             end
           end

           def set_cell(x, y, label)
             return if x == nil || y == nil
             return if x.to_i < 0 || y.to_i < 0 || x.to_i >= @width || y.to_i >= @height
             @labels[y.to_i][x.to_i] = text_utf8(label)
           end

           def cell_label(x=@x, y=@y)
             return "" if x == nil || y == nil
             return "" if x.to_i < 0 || y.to_i < 0 || x.to_i >= @width || y.to_i >= @height
             text_utf8(@labels[y.to_i][x.to_i])
           end

           def coordinate_label(x=@x, y=@y)
             col = x.to_i
             letters = ""
             loop do
               letters = (65 + (col % 26)).chr + letters
               col = col / 26 - 1
               break if col < 0
             end
             "#{letters}#{y.to_i + 1}"
           end

           def value
             [@x, @y]
           end

           def lpos
             return 50 if @width <= 1
             @x.to_f / (@width - 1).to_f * 100.0
           end

           def focus(index=nil, count=nil, spk=true, include_header: true)
             pos = lpos
             play_sound("listbox_marker", volume: 100, pitch: 100, pan: pos) if spk && !@silent && Configuration.controlspresentation != :voice_only
             return if !@speech
             text = ""
             if include_header && @header != nil && @header != ""
               text = @header.dup
               text += ": " if !" .:?!,".include?(text[-1..-1] || "")
             end
             label = cell_label
             text += label == "" ? coordinate_label : "#{label}, #{coordinate_label}"
             speak(text, pan: pos) if spk
             NVDA.braille(text) if defined?(NVDA) && NVDA.check
           end

           def update
             super
             oldx = @x
             oldy = @y
             if key_pressed?(:key_left)
               move_by(-1, 0)
             elsif key_pressed?(:key_right)
               move_by(1, 0)
             elsif key_pressed?(:key_up)
               move_by(0, -1)
             elsif key_pressed?(:key_down)
               move_by(0, 1)
             elsif (binding = pressed_action_binding) != nil
               source, action = binding
               x = @x
               y = @y
               trigger(:select, x, y) if action == :select
               trigger(:action, action, source, x, y)
             end
             if oldx != @x || oldy != @y
               play_sound("listbox_focus", volume: 100, pitch: 100, pan: lpos) if !@silent
               trigger(:move, @x, @y)
               focus(nil, nil, true, include_header: false)
             end
           end

           def move_by(dx, dy)
             nx = [[@x + dx.to_i, 0].max, @width - 1].min
             ny = [[@y + dy.to_i, 0].max, @height - 1].min
             if nx == @x && ny == @y
               play_sound("border", volume: 100, pitch: 100, pan: lpos) if @border_sound && !@silent
               trigger(:border, @x, @y, border_direction(dx, dy), dx.to_i, dy.to_i)
             else
               @x = nx
               @y = ny
             end
           end

           def border_direction(dx, dy)
             return :left if dx.to_i < 0
             return :right if dx.to_i > 0
             return :up if dy.to_i < 0
             return :down if dy.to_i > 0
             nil
           end

           def key_processed(k)
             return true if NAVIGATION_KEYS.include?(k)
             return false if !k.is_a?(Integer) && !k.respond_to?(:to_sym)
             key = normalize_action_key(k)
             @action_bindings.keys.any? do |source|
               action_source_key(source) == key && (!source.is_a?(Array) || action_source_pressed?(source))
             end
           end

           private

           def pressed_action_binding
             bindings = @action_bindings.to_a
             bindings.find { |source, _action| source.is_a?(Array) && action_source_pressed?(source) } ||
               bindings.find { |source, _action| !source.is_a?(Array) && action_source_pressed?(source) }
           end

           def action_source_pressed?(source)
             if source.is_a?(Array)
               binding = source.dup
               binding[0] = action_key_value(binding[0])
               binding[1..-1] = binding[1..-1].map { |modifier| resolve_action_modifier(modifier) }
               keyboard_binding_pressed?(binding)
             else
               key_pressed?(action_key_value(source))
             end
           end

           def action_source_key(source)
             source.is_a?(Array) ? source[0] : source
           end

           def normalize_action_source(source)
             if source.is_a?(Array)
               raise ArgumentError, "action input source cannot be empty" if source.empty?
               key = normalize_action_key(source[0])
               modifiers = source[1..-1].map { |modifier| normalize_action_modifier(modifier) }
               raise ArgumentError, "action input source contains duplicate modifiers" if modifiers.uniq.size != modifiers.size
               modifiers.sort_by! { |modifier| ACTION_MODIFIERS.index(modifier) }
               normalized = [key, *modifiers].freeze
             else
               normalized = normalize_action_key(source)
             end
             if NAVIGATION_KEYS.include?(action_source_key(normalized))
               raise ArgumentError, "arrow keys are reserved for GridBox navigation"
             end
             validate_action_key(action_source_key(normalized))
             normalized
           end

           def normalize_action_key(key)
             return key.to_i & 0xff if key.is_a?(Integer)
             raise ArgumentError, "action key must be a key name or numeric key code" if !key.respond_to?(:to_sym)
             name = key.to_sym.to_s.downcase
             name = name.sub(/\Akey_/, "")
             ACTION_KEY_ALIASES.fetch(name, name).to_sym
           end

           def normalize_action_modifier(modifier)
             raise ArgumentError, "action modifier must be a name" if !modifier.respond_to?(:to_sym)
             modifier = modifier.to_sym
             modifier = modifier.to_s.sub(/\Akey_/, "").to_sym
             modifier = :control if modifier == :ctrl
             modifier = :option if modifier == :alt
             raise ArgumentError, "unsupported action modifier: #{modifier.inspect}" if !ACTION_MODIFIERS.include?(modifier)
             modifier
           end

           def resolve_action_modifier(modifier)
             return EltenAPI::KeyboardScheme.main_modifier if modifier == :main_modifier
             return EltenAPI::KeyboardScheme.word_modifier if modifier == :word_modifier
             modifier
           end

           def action_key_value(key)
             match = /\Af([1-9]|1\d|2[0-4])\z/.match(key.to_s)
             match == nil ? key : 0x6F + match[1].to_i
           end

           def validate_action_key(key)
             code, = keyboard_code(action_key_value(key))
             raise ArgumentError, "unsupported action key: #{key.inspect}" if code == nil || code == 0
           end
         end


  end
end
