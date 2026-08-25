# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_FAQ
  def main
load_faq
@v=0
show_cats
end
def show_cats
  @catslist = ListBox.new(@cats, header: p_("FAQ", "Frequently asked questions"))
@catslist.focus
  loop do
  loop_update
  @catslist.update
  if key_pressed?(:key_escape)
    $scene=Scene_Main.new
    return
  end
  if @catslist.expanded? || @catslist.selected?
    show_questions(@catslist.index)
    @catslist.sayoption
    end
end
  end
def show_questions(index)
  qs = @ans[index].map{|a|a[0..a.index("\n")].strip}
  @qslist = ListBox.new(qs, header: "")
@qslist.focus
loop do
  loop_update
  @qslist.update
  break if key_pressed?(:key_escape) || @qslist.collapsed?
  if @qslist.expanded? || @qslist.selected?
    ans = @ans[index][@qslist.index]
    a = ans[(ans.index("\n"))+1..-1]
    input_text(qs[@qslist.index], flags: EditBox::Flags::MarkDown|EditBox::Flags::ReadOnly||EditBox::Flags::MultiLine, text: a, escapable: true)
    @qslist.sayoption
    end
  end
  end
def load_faq
  @faqdoc = _doc("faq")
@faq = @faqdoc.split(/^\# /).map{|f|
a=f.strip.split(/^\#\# /).map{|q|q.strip}
a.delete("")
a
}
@faq.delete([])
@cats = @faq.map{|f|f[0]}
@ans = @faq.map{|f|f[1..-1]}
@faq
  end
  end