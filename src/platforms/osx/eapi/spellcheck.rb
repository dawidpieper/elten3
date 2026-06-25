# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class SpellCheck
  class Result
    attr_accessor :index, :length
    attr_reader :suggestions

    def initialize
      @suggestions = []
    end
  end

  class << self
    def available?
      false
    end

    def languages
      []
    end

    def check(_language, _text)
      []
    end
  end
end
