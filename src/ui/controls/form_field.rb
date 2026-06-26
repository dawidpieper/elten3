# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
  class FormField < FormBase
    def text_utf8(value)
      str = value.to_s
      if str.encoding == Encoding::UTF_8
        return str if str.valid_encoding?
      else
        str = str.dup
        str.force_encoding(Encoding::UTF_8) if str.encoding == Encoding::ASCII_8BIT
      end
      str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end
    private :text_utf8

    def focus(index=nil,count=nil)
      end
    def subindex
      return 0
    end
    def maxsubindex
      return 0
    end
    def update(*arg)
      super
            if $focus==true
        $focus=false
        focus
      end
        end
      end


  end
end
