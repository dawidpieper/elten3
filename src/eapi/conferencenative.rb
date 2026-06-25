# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

ELTEN_INTPTR = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT unless defined?(::ELTEN_INTPTR)
ELTEN_SIZE_T = ELTEN_INTPTR unless defined?(::ELTEN_SIZE_T)

class EltenRubyFunction
  def initialize(&block)
    @block = block || proc { 0 }
  end

  def call(*args)
    @block.call(*args)
  end
end unless defined?(::EltenRubyFunction)
