# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2020 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  module External
    private
# Functions using external APIs
   
   # Translates a string to another language using Google Translate
    #
    # @param from [String] source language code (if 0, the language autodetection is used)
    # @param to [String] destination language code
    # @param text [String] a text to translate
    # @param api [Int] deprecated, ignored
    # @return [String] the translation result
def translatetext(from,to,text,_api=0)
  return gtranslate(from,to,text)
end

def gtranslate(from, to, text)
  return "" if text==""||text==nil
  text=text.to_s
  from="auto" if from==0 || from==nil || from==""
rest=text[5001..-1]
text=text[0..5000]
  url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=#{from}&tl=#{to}&dt=t&q=#{text.urlenc}"
  j=read_url(url).to_s
  if j!=""
  h=JSON.load(j)
  return "" if !h[0].is_a?(Array)
  t=""
  h[0].each do |a|
    return "" if !a[0].is_a?(String)
    t+=a[0]
  end
  t+=gtranslate(from, to, rest) if rest!=nil && rest!=""
  return t
  else
  return ""
  end
  end

# Opens a translator dialog
#
# @param text [String] a text to translate
     def translator(text)
  langs={}
  Lists.langs.keys.each do |lk|
    lname=Lists.langs[lk]['nativeName']+" ("+Lists.langs[lk]['name']+")"
    langs[lk]=lname
    end
       dialog_open
  from=ListBox.new([p_("EAPI_External", "recognize automatically")]+langs.values,header: p_("EAPI_External", "source language"))
 ind=0
 (0..langs.keys.size-1).each do |i|
   ind=i if Configuration.language[0..1].downcase==langs.keys[i].downcase
   end
 to=ListBox.new(langs.values,header: p_("EAPI_External", "destination language"),index: ind)
 submit=Button.new(p_("EAPI_External", "Translate"))
 cancel=Button.new(_("Cancel"))
 form=Form.new([from,to,submit,cancel])
loop do
  loop_update
  form.update
  if key_pressed?(:key_escape) or ((key_pressed?(:key_space) or key_pressed?(:key_enter)) and form.index==3)
    dialog_close
    loop_update
    return -1
  end
  if (key_pressed?(:key_space) or key_pressed?(:key_enter)) and form.index == 2
        break
    end
  end
  lfrom=0
  if from.index==0
      lfrom=0
    else
        lfrom=langs.keys[from.index-1]
      end
      lto=langs.keys[to.index]
      ef = translatetext(lfrom,lto,text)
      lfrom = "AUTO" if lfrom==0
      input_text("#{lfrom} - #{lto}",flags: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly,text: ef)
      loop_update
    dialog_close
  end
end
include External
end
