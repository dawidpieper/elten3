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
             focus if quiet == false
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
             play_sound("listbox_marker", volume: 100, pitch: 100, pan: pos) if spk && !@silent && Configuration.controlspresentation != 2
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
             elsif key_pressed?(:key_enter) || key_pressed?(:key_space)
               trigger(:select, @x, @y)
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
             return true if [:left, :right, :up, :down].include?(k)
             return true if k == :enter || k == :space
             false
           end
         end


  end
end
