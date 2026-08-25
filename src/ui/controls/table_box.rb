# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
       class TableBox < FormField
         include WaitForItem
         attr_accessor :columns, :rows
         attr_reader :sel
         attr_reader :row_states
         attr_reader :row_audio_urls
         attr_reader :row_audio_autoplay_values
         attr_reader :row_audio_completion_labels
         attr_accessor :header
         attr_reader :column
                           def initialize(columns=[], rows=[], index: 0, header: "", quiet: true, flags: 0, empty_label: nil)
           @columns, @rows = columns, rows
           @flags=flags
           @column=0
           @row_states=[]
           @row_audio_urls=[]
           @row_audio_sources=[]
           @row_audio_autoplay_values=[]
           @row_audio_completion_labels=[]
           @header=text_utf8(header)
           @wait_for_item_quiet=quiet
           @sel = ListBox.new(format_rows(@column), header: @header, index: index, flags: @flags, quiet: quiet, empty_label: empty_label)
           @sel.on(:move) {|arg|trigger(:move, arg)}
          end
           def empty_label
             @sel.empty_label
           end
           def empty_label=(label)
             @sel.empty_label=label
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
         # See ListBox#set_item_audio for supported sources and ownership.
         def set_row_audio(id, source=nil, data: nil, autoplay: true, completion_label: nil)
           return if id==nil || id<0
           @sel.set_item_audio(id, source, data: data, autoplay: autoplay, completion_label: completion_label)
           descriptor=@sel.item_audio_source_descriptor(id)
           return clear_row_audio(id) if descriptor==nil
           @row_audio_sources||=[]
           @row_audio_autoplay_values||=[]
           @row_audio_completion_labels||=[]
           @row_audio_sources[id]=descriptor
           url=@sel.item_audio_url(id)
           @row_audio_urls[id]=url=="" ? nil : url
           @row_audio_autoplay_values[id]=autoplay!=false
           @row_audio_completion_labels[id]=completion_label==nil ? nil : text_utf8(completion_label)
         end
         alias set_row_audio_url set_row_audio
         def row_audio_source(id=index)
           return nil if id==nil || id<0 || @row_audio_sources==nil || @row_audio_sources[id]==nil
           @row_audio_sources[id].value
         end
         def row_audio_sources
           (@row_audio_sources||[]).map{|source|source==nil ? nil : source.value}
         end
         def clear_row_audio(id=nil)
           @row_audio_urls||=[]
           @row_audio_sources||=[]
           @row_audio_autoplay_values||=[]
           @row_audio_completion_labels||=[]
           if id==nil
             @row_audio_urls=[]
             @row_audio_sources=[]
             @row_audio_autoplay_values=[]
             @row_audio_completion_labels=[]
             @sel.clear_item_audio if @sel!=nil
           else
             @row_audio_urls[id]=nil
             @row_audio_sources[id]=nil
             @row_audio_autoplay_values[id]=nil
             @row_audio_completion_labels[id]=nil
             @sel.clear_item_audio(id) if @sel!=nil
           end
         end
         def apply_row_audio
           return if @row_audio_sources==nil
           for i in 0...@row_audio_sources.size
             @sel.set_item_audio(
               i,
               @row_audio_sources[i],
               autoplay: @row_audio_autoplay_values[i]!=false,
               completion_label: @row_audio_completion_labels[i]
             ) if @row_audio_sources[i]!=nil
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

         private

         def wait_item_available?(id)
           id>=0 && id<@rows.size && !@sel.hidden?(id)
         end

         def wait_item_at(id)
           @rows[id]
         end

         public

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
             tips.push(p_("EAPI_Form", "Use Shift+Left/Right Arrow to select the column you want to navigate by"))
             return tips
             end
         end


  end
end
