# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
       class TableBox < FormField
         attr_accessor :columns, :rows
         attr_reader :sel
         attr_reader :row_states
         attr_reader :row_audio_urls
         attr_accessor :header
         attr_reader :column
                           def initialize(columns=[], rows=[], index: 0, header: "", quiet: true, flags: 0)
           @columns, @rows = columns, rows
           @flags=flags
           @column=0
           @row_states=[]
           @row_audio_urls=[]
           @header=text_utf8(header)
           @sel = ListBox.new(format_rows(@column), header: @header, index: index, flags: @flags, quiet: quiet)
           @sel.on(:move) {|arg|trigger(:move, arg)}
          end
           def autosayoption
             @sel.autosayoption
           end
           def autosayoption=(a)
             @sel.autosayoption=a
         end
         def tag
           @sel.tag
         end
         def tag=(t)
           @sel.tag=t
           end
         def options
           @sel.options
         end
         def rows=(rows)
           @rows=rows
           clear_row_states if @sel!=nil
           clear_row_audio if @sel!=nil
         end
         def set_row_state(id, state, value=true)
           return if id==nil || id<0
           @sel.set_item_state(id, state, value)
           @row_states[id]=@sel.item_states_for(id).values
         end
         def set_row_status(id, sound, speech_prefix, braille_prefix)
           return if id==nil || id<0
           @sel.set_item_status(id, sound, speech_prefix, braille_prefix)
           @row_states[id]=@sel.item_states_for(id).values
         end
         def set_row_states(id, states)
           return if id==nil || id<0
           @sel.set_item_states(id, states)
           @row_states[id]=@sel.item_states_for(id).values
         end
         def clear_row_state(id, state=nil)
           return if id==nil || id<0 || @row_states[id]==nil
           @sel.clear_item_state(id, state)
           @row_states[id]=@sel.item_states_for(id).values
         end
         def clear_row_states
           @row_states=[]
           @sel.item_states.clear if @sel.item_states!=nil
         end
         def set_row_audio(id, url)
           return if id==nil || id<0
           @row_audio_urls[id]=url.to_s
           @sel.set_item_audio(id, url)
         end
         alias set_row_audio_url set_row_audio
         def clear_row_audio(id=nil)
           @row_audio_urls||=[]
           if id==nil
             @row_audio_urls=[]
             @sel.clear_item_audio if @sel!=nil
           else
             @row_audio_urls[id]=nil
             @sel.clear_item_audio(id) if @sel!=nil
           end
         end
         def apply_row_audio
           return if @row_audio_urls==nil
           for i in 0...@row_audio_urls.size
             @sel.set_item_audio(i, @row_audio_urls[i]) if @row_audio_urls[i]!=nil && @row_audio_urls[i].to_s!=""
           end
         end
         def apply_row_states
           return if @row_states==nil
           for i in 0...@row_states.size
             @sel.set_item_states(i, @row_states[i]) if @row_states[i]!=nil
           end
         end

         def row_speech_value(value)
           value.is_a?(SpeechSequence) ? value : text_utf8(value)
         end

         def row_speech_append(value, part)
           if value.is_a?(SpeechSequence) || part.is_a?(SpeechSequence)
             SpeechSequence.new(value, part)
           else
             value.to_s+part.to_s
           end
         end

         def say_option
           @sel.say_option
           end
alias sayoption say_option
           def format_rows(col=0)
           opts=[]
           for r in @rows
             if r==nil or r.count(nil)==r.size
               o=nil
                              else
             o=""
                          o=row_speech_value(r[col]) if r[col]!=nil
             for c in 0...@columns.size
               if c!=col&&r[c]!=nil
               plain=o.to_s
               o=row_speech_append(o, ((c==0)?":":((plain[-1..-1]!=":"&&plain[-1..-1]!=".")?",":""))+" ")
               o=row_speech_append(o, text_utf8(@columns[c])+": ")
               o=row_speech_append(o, row_speech_value(r[c]))
               end
             end
             end
             opts.push(o)
           end
                                 return opts
         end
         def index
           return @sel.index
         end
         def index=(ind)
           @sel.index=(ind)
         end
         def column=(c)
           setcolumn(c)
         end
         def setcolumn(c)
@sel.options=format_rows(c)
           apply_row_states
           apply_row_audio
           @column=c
         end
         def reload
           @sel.options=format_rows(@column)
           apply_row_states
           apply_row_audio
           end
         def update
super
           if key_held?(0x10)&&@rows.size>0
             if key_pressed?(:key_right)
               c=@column
                           setcolumn((@column+1)%(@columns.size))
                              setcolumn((@column+1)%(@columns.size)) while (@rows[index][@column]==nil||@rows[index][@column]=="") and c!=@column
                                                                           speak(text_utf8(@rows[@sel.index][@column])+" ("+text_utf8(@columns[@column])+")", pan: @sel.lpos)
                                                          elsif key_pressed?(:key_left)
               c=@column
                           setcolumn((@column-1)%(@columns.size))
                           setcolumn((@column-1)%(@columns.size)) while (@rows[index][@column]==nil||@rows[index][@column]=="") and c!=@column
                                                      speak(text_utf8(@rows[@sel.index][@column])+" ("+text_utf8(@columns[@column])+")", pan: @sel.lpos)
                                                        end
             end
           @sel.update
         end
         def focus(index=nil,count=nil)
           @sel.focus(index, count)
         end

         def selected?
           @sel.selected?
         end
         def collapsed?
           @sel.collapsed?
         end
         def expanded?
           @sel.expanded?
           end

         def lpos
           @sel.lpos
           end
         def foplay(voice)
  play_sound(voice, volume: 100, pitch: 100, pan: lpos)
  end


         def key_processed(k)
           if key_held?(0x10) && (k==:left || k==:right)
             return true
           else
             return @sel.key_processed(k)
             end
           end
         def tips
             tips=[]
             tips.push(p_("EAPI_Form", "Use SHIFT with left/right arrows to select the column you want to navigate by"))
             return tips
             end
         end


  end
end
