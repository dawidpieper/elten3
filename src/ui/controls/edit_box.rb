# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
  class EditBox < FormField
    BRAILLE_CONTEXT_CHARS = 25_000
    READ_TEXT_BREAK_PATTERN = /\n|[!?\.,] /.freeze
    WORD_NAVIGATION_SCAN_CHARS = 3_000
    @@customactions=[]
    @@lastedits=[]
    attr_accessor :index
        attr_accessor :flags
    attr_reader :origtext
    attr_accessor :silent
    attr_accessor :audiotext
    attr_accessor :check
    attr_accessor :max_length
    attr_accessor :header
    attr_accessor :audiostream
    attr_reader :permitted_characters, :denied_characters
        def initialize(header="", type: 0, text: "", quiet: true, init: false, silent: false, max_length: -1)
      if type.is_a?(String)
        Log.warning("Text flags are no longer supported: "+Kernel.caller.join(" "))
        end
            @header=header
@flags=0
@flags=type if type.is_a?(Integer)
@silent=silent
@max_length=max_length
      @index=@check=0
        set_text(text)
                @origtext=text
      @sounds=[]
@redo=[]
@undo=[]
@formats=[]
@@lastedits.push(self) if (@flags&Flags::MultiLine)>0 && (@flags&Flags::ReadOnly)==0
@@lastedits.delete_at(0) while @@lastedits.size>20
@permitted_characters=[]
@denied_characters=[]
focus if quiet==false
end
    def update
super
focus if @audioplayer==nil and @audiotext!="" and @audiotext!=nil
if @selected==true
play_sound("editbox_textselected")
@selected=false
end
      oldindex=@index
      oldtext=@text      if @audioplayer!=nil and key_pressed?(:key_escape)
                if @audioplayer != nil and key_pressed?(:key_escape)
          blur
      elsif @audioplayer!=nil && key_first_pressed?(0x20)
        if @audioplayer.paused?
          Programs.emit_event(:player_play)
          dialog_mute
          @audioplayer.play
          @audioplayed=true
        else
          @audioplayer.pause
        end
        return
      elsif @audioplayer!=nil and @audioplayed==false
      if speech_output_nvda? or !speech_actived
        if Configuration.autoplay==0 || (Configuration.autoplay==1 && (@flags&Flags::Transcripted)==0)
        Programs.emit_event(:player_play)
      dialog_mute
      @audioplayer.play
      @audioplayed=true
      end
    end
        end
      if @audioplayer!=nil && !@audioplayer.paused? && @audioplayer.completed == false
          @audioplayer.update
          return
                  end
navupdate
      editupdate
      ctrlupdate
      if oldindex!=@index or oldtext!=@text
          nvda_braille_text if defined?(NVDA) && NVDA.check
        end
            esay
        end
def editupdate
  return readupdate if (@flags&Flags::ReadOnly)!=0
      if (c=getkeychar)!="" and (c.to_i.to_s==c or (@flags&Flags::Numbers)==0) and (@flags&Flags::ReadOnly)==0
                speech_stop if Configuration.typingecho>0 and !(speech_output_nvda? and defined?(NVDA) && NVDA.check)
        einsert(c)
                               if ((wordendings=" ,./;'\\\[\]-=<>?:\"|\{\}_+`!@\#$%^&*()_+").include?(c)) and ((Configuration.typingecho == 1 or Configuration.typingecho == 2))
                 s=text_range_exclusive((@index>50?@index-50:0), @index)
                                  w=(s[(0 ... s.length).find_all { |i| wordendings.include?(s[i..i]) or s[i..i]=="\n"}.sort[-2]||0..(s.length-1)])
if (w=~/([a-zA-Z0-9ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]+)/)!=nil
  espeech(w)
  play_sound("editbox_space") if c==" "
else
  espeech(c) if @interface_typingecho!=1
  end
elsif Configuration.typingecho==0 or Configuration.typingecho==2
         espeech(c)
      end
    elsif c!=""
            play_sound("border") if c!=" "
      end
    if key_pressed?(:key_enter)
      speech_stop
          if (@flags&Flags::MultiLine)>0 and key_held?(0x11)==false and (@flags&Flags::ReadOnly)==0
      einsert("\n")
      play_sound("editbox_endofline")
    elsif ((@flags&Flags::MultiLine)==0 or key_held?(0x11)) and (@flags&Flags::ReadOnly)==0
      play_sound("listbox_select")
      trigger(:select, @index)
            end
          end
          if key_pressed?(0x2e) and (@index<text_len or @check<text_len) and (@flags&Flags::ReadOnly)==0
            play_sound("editbox_delete")
            c=selected_range || selected_or_current_range
                                                                                                        edelete(c[0],c[1])
                                                                          espeech(text_char(@index))
          end
          if key_pressed?(0x08) and (@index>0 or @check>0) and (@flags&Flags::ReadOnly)==0
if key_held?(0x11) && @index==@check && @index>0
  from=@index-1
    to=@index-1
      from-=1 while from>0 && (text_char(from)=="\n" || text_char(from)==" ")
  from-=1 while from>0 && text_char(from-1)!=" " && text_char(from-1)!="\n"
  if from<=to
  espeech(text_range(from,to))
  edelete(from, to)
  play_sound("editbox_delete")
  end
else
            play_sound("editbox_delete")
c=[]
if (range=selected_range)
c=range
else
  oind=ind=@index-1
  ind=char_borders(ind)[0]
  c=[ind,oind]
end
                                                                                                                                espeech(text_range(c[0],c[1]).split("")[0])
            edelete(c[0],c[1])
end
                                                end
                    end
def readupdate
            if key_pressed?(:key_enter)
url=nil
@elements.each {|e| url=e.param[1] if (e.from<=@index and e.to>=@index) and (e.type==Element::Link || e.type==Element::Frame)}
@elements.each {|e| url=e.param[1] if (e.from>=line_beginning and e.to<=line_ending) and (e.type==Element::Link || e.type==Element::Frame)} if url==nil
              if url!=nil
                speak(p_("EAPI_Form", "Opening a link..."))
        process_url(url)
        loop_update
        end
      end
      if key_held?(0x10) && key_held?(0x11)
        if key_pressed?(67)
          copy
        elsif key_pressed?(88)
          cut
        elsif key_pressed?(86)
          paste
          end
        end
              e=nil
      if key_pressed?(72)
      e=find_element(Element::Header,nil,key_held?(0x10),@index)
    elsif (0x31..0x36).any? { |key| key_pressed?(key) }
      k=1
      (1..6).each {|i| k=i if key_pressed?(0x30+i)}
        e=find_element(Element::Header,k,key_held?(0x10),@index)
      elsif key_pressed?(75)
        e=find_element([Element::Link,Element::Frame],nil,key_held?(0x10),@index)
        elsif key_pressed?(73)
        e=find_element(Element::ListItem,nil,key_held?(0x10),@index)
        end
  if e!=nil
    @index=e.from
    espeech(text_range(e.from,e.to))
    elsif getkeychar!=""
    play_sound("border")
    end
  end
                    def navupdate
            @vindex=key_held?(0x10)?@check:@index
            prvindex=@vindex
            last=@vindex
            @ch=false
          if key_pressed?(:key_right)
                                  @vindex=char_borders(@vindex)[1]
          if @vindex>=text_len
            if Configuration.soundthemeactivation == 1
            play_sound("border")
          else
espeech(p_("EAPI_Form", "End of line"))
            end
                                      elsif @vindex==text_len-1
                    @vindex=text_len
                    if Configuration.soundthemeactivation == 1
                    play_sound("editbox_endofline")
                  else
                    espeech(p_("EAPI_Form", "End of line"))
                    end
                  else
                    if key_held?(0x11)==false
                              ind=char_borders(@vindex)[1]+1
        oi=ind
        e=char_borders(ind)[1]
                        espeech(text_range(oi,e))
                @vindex=oi
              else
                scan_to=[@vindex+WORD_NAVIGATION_SCAN_CHARS,text_len].min
                fallback=key_held?(0x10)?scan_to:scan_to-1
                @vindex=((@vindex+(key_held?(0x10)?((@vindex>=(text_len-1))?1:2):1) ... scan_to).find_all { |i| text_char(i)==" " or text_char(i)=="\n"}.sort[0]||fallback)
                                @vindex+=(key_held?(0x10) ? 0 : 1)
                                                                                                (@vindex==text_len)?play_sound("editbox_endofline"):espeech(text_range((key_held?(0x10)?((0 .. @vindex).find_all { |i| text_char(i)==" " or text_char(i)=="\n"}.sort.last||0):@vindex),(@vindex+1 .. text_len).find_all { |i| text_char(i)==" " or text_char(i)=="\n"}.sort[0]||text_len-1))
                                                                                              end
                              end
                                              elsif key_pressed?(:key_left)
        if @vindex<=0
          if Configuration.soundthemeactivation == 1
          play_sound("border")
        else
          if text_len>0
          c=char_borders(0)
          espeech(text_range(c[0],c[1]))
            else
            espeech(p_("EAPI_Form", "End of line"))
            end
          end
                  else
        if key_held?(0x11)==false
                    ind=@vindex-1
                  ind=char_borders(ind)[0]
                                            espeech(text_range(ind,@vindex-1))
                @vindex=ind
              else
                                scan_from=[@vindex-WORD_NAVIGATION_SCAN_CHARS,0].max
                @vindex=((scan_from ... @vindex-1).find_all { |i| text_char(i)==" " or text_char(i)=="\n"}.sort.last||(scan_from-1))+1
                espeech(text_range(@vindex,(@vindex+1 ... text_len).find_all { |i| text_char(i)==" " or text_char(i)=="\n"}.sort[0]||text_len-1))
                end
              end
            elsif key_pressed?(:key_up) and !key_held?(0x2d)
              b=line_beginning
              e=line_ending
                            if b==0
                play_sound("border")
                espeech(e>0?(text_range(0,e-1)):"")
              else
                                l=@vindex-b
                em=line_ending(b-1)
                bm=line_beginning(b-1)
                l=em-bm if em-bm<l
                l=0 if e-b<=1
                l=line_ending(bm-1)-bm-1 if key_held?(0x10)
                                @vindex=bm+l
                espeech(em>0?(text_range(bm,em-1)):"")
                end
            elsif key_pressed?(:key_down) and !key_held?(0x2D)
              b=line_beginning
              e=line_ending
              if e==text_len
                play_sound("border")
                espeech(text_range(b,e-1))
              else
                l=@vindex-b
                ep=line_ending(e+1)
                bp=line_beginning(e+1)
                l=ep-bp if ep-bp<l
                l=0 if e-b<=1
                l=line_ending(@vindex+1)-bp if key_held?(0x10)
                                @vindex=bp+l
                espeech(text_range(bp,ep-1))
                end
        end
        if key_pressed?(0x24)  && !key_held?(0x5B) && !key_held?(0x5C)
                    @ch=@vindex=key_held?(0x11)?0:line_beginning
                            espeech(key_held?(0x11)?text_range(line_beginning,line_ending):text_range(@vindex,text_len-1).split("")[0]) if @vindex<text_len
                          elsif key_pressed?(0x23) && !key_held?(0x5B) && !key_held?(0x5C)
                            if !key_held?(0x10)
          @ch=@vindex=key_held?(0x11)?(text_len):line_ending
          espeech(key_held?(0x11)?text_range(line_beginning,line_ending):(((t=text_char(line_ending))=="")?"\n":t))
        else
          @ch=@vindex=key_held?(0x11)?(text_len):line_ending(@vindex+1)
          espeech(key_held?(0x11)?text_range(line_beginning,line_ending):(((t=text_char(line_ending))=="")?"\n":t))
          end
                                                end
                                                        if key_pressed?(0x21)  && !key_held?(0x5B) && !key_held?(0x5C)
                    if line_beginning==0
                play_sound("border")
                espeech(text_range(0,line_ending-1))
              else
                @vindex=move_page_lines(-15)
                espeech(text_range(line_beginning,line_ending-1))
                end
            elsif key_pressed?(0x22)  && !key_held?(0x5B) && !key_held?(0x5C)
              if line_ending==text_len
                play_sound("border")
                                espeech(text_range(line_beginning,line_ending-1))
              else
                @vindex=move_page_lines(15)
                espeech(text_range(line_beginning,line_ending-1))
                end
              end
              lastcheck=get_check(true)
              checked=false
                    if key_held?(0x10)==false and (@index!=@vindex or @ch!=false)
                      checked=true if @check!=@index
                      @check=@index=@vindex
                    elsif (key_held?(0x10)==true and @check!=@vindex) or (key_held?(0x11) and key_pressed?(65) and !key_held?(0x12))
                      checked=true
            if key_held?(0x11) and key_pressed?(65) and !key_held?(0x12)
                        @index=0
            @check=text_len
          else
            @check=@vindex
          end
        end
        if (lastcheck!="" || checked) && lastcheck!=get_check
                                    if @index!=@check
                                      chk=get_check
                                      if chk.include?(lastcheck)
                                        play_sound("editbox_textselected")
                                      if chk[0...lastcheck.length]==lastcheck
                                        chk[0...lastcheck.length]=""
                                      elsif chk[-1*lastcheck.length..-1]==lastcheck
                                        chk[-1*lastcheck.length..-1]=""
                                      end
                                    elsif lastcheck.include?(chk)
                                      play_sound("editbox_textunselected")
                                      if lastcheck[0...chk.length]==chk
                                        chk=lastcheck[chk.length..-1]
                                      elsif lastcheck[-1*chk.length..-1]==chk
                                        chk=lastcheck[0...-chk.length]
                                      end
                                    else
                                      play_sound("editbox_textselected")
                                      end
                                      @tosay=chk
                                    end
          end
          if last!=@vindex
          for e in @elements
            if last<e.from || last>e.to
              if @vindex>=e.from && @vindex<=e.to
                d=e.description
                @tosay=d+": "+@tosay
                end
              end
            end
          end
            esay
          end
          def ctrlupdate

  read_text(@index) if @index<text_len and (((key_held?(0x2d) and key_pressed?(:key_down)))) and (@audiotext==nil or @index>0)
  espeech(text_range(line_beginning,line_ending)) if key_held?(0x2d) and key_pressed?(:key_up)
  esay
end
def clear_sounds
  @sounds.clear
end
def add_sound(snd)
  @sounds.push(snd)
end
def select_all
  return if text_len==0
  @index=0
            @check=text_len
            @selected=true
            end
def setformatting(type, params=nil)
  range=selected_range
                              if range!=nil
                                from,to=range
                                s=false
                                for e in @elements
                                  next if e.type!=type
                                  s=true if e.from>=from && e.from<=to
                                  s=true if e.to>=from && e.to<=to
                                  s=true if e.from<from && e.to>to
                                end
                                if s==true
                                  del=[]
                                  ins=[]
                                  for e in @elements
                                    next if e.type!=type
                                    if e.from>=from && e.to<=to
                                      del.push(e)
                                    elsif e.from<from && e.to>from
                                      if e.to<to
                                        e.to=from-1
                                      else
                                        el=Element.new(to+1, e.to, type)
                                        del.push(e)
                                        ins.push(el)
                                                                                e.to=from-1
                                        end
                                        elsif e.from<to && e.to>to
                                      if e.from>from
                                        e.from=to+1
                                      else
                                        el=Element.new(e.from, from-1, type)
                                        ins.push(el)
                                                                                                                        e.from=to+1
                                      end
                                    end
                                  end
                                  del.each{|e| @elements.delete(e)}
                                  ins.each{|el| @elements.push(el)}
                                  play_sound("editbox_delete")
                                  else
                                    el=Element.new(from, to, type)
                                    @elements.push(el)
                                    play_sound("editbox_bigletter")
                                  end
                                                                  else
  if @formats.include?(type)
    @formats.delete(type)
    play_sound("editbox_delete")
  else
    @formats.push(type)
    espeech(Element.description(type))
  end
  end
  end
def context(menu, submenu=false)
  c=Proc.new {|menu|
  if (@flags&Flags::Formattable)>0
    menu.submenu(p_("EAPI_Form", "Format")) {|m|
    m.option(p_("EAPI_Form", "Bold"), nil, "b") {
    if requires_premiumpackage("scribe")
    setformatting(Element::Bold)
    end
    }
    m.option(p_("EAPI_Form", "Italic"), nil, "i") {
    if requires_premiumpackage("scribe")
    setformatting(Element::Italic)
    end
    }
    m.option(p_("EAPI_Form", "Underline"), nil, "u") {
    if requires_premiumpackage("scribe")
    setformatting(Element::Underline)
    end
    }
    m.submenu(p_("EAPI_Form", "Heading")) {|n|
        for i in 1..6
      n.option(p_("EAPI_Form", "Heading level %{level}")%{:level=>i}, i, i.to_s) {|level|
      if requires_premiumpackage("scribe")
      a=line_beginning(@vindex, true)
      b=line_ending(@vindex, true)
      del=[]
      s=false
      for e in @elements
        if e.type==Element::Header && ((e.from>=a && e.from<=b) || (e.to>=a && e.to<=b))
          s=true if e.param==level
          del.push(e)
          end
      end
      del.each{|e| @elements.delete(e)}
      if s==false
      el=Element.new(a, b, Element::Header, level)
      @elements.push(el)
      play_sound("editbox_bigletter")
    elsif s==true
      play_sound("editbox_delete")
      end
      end
      }
      end
    }
    }
    menu.submenu(p_("EAPI_Form", "Insert")) {|m|
    m.option(p_("EAPI_Form", "Link")) {
      if requires_premiumpackage("scribe")
    form=Form.new([
    EditBox.new(p_("EAPI_Form", "URL"), type: 0, text: "", quiet: true),
    EditBox.new(p_("EAPI_Form", "Label"), type: 0, text: "", quiet: true),
    Button.new(p_("EAPI_Form", "Add")),
    Button.new(_("Cancel"))
    ])
    loop do
      loop_update
      form.update
      break if key_pressed?(:key_escape) or form.fields[3].pressed?
      if form.fields[2].pressed?
        url=form.fields[0].text
        label=form.fields[1].text
        ind=@index
        einsert(label)
                el=Element.new(ind, ind+label.length-1, Element::Link, url)
        @elements.push(el)
        break
        end
    end
    loop_update
    speak(text_range(line_beginning,line_ending))
    end
    }
    }
  end
  menu.option(p_("EAPI_Form", "Read from cursor"), nil, "A") {
  read_text(@index) if @index<text_len
  }
  menu.option(p_("EAPI_Form", "Read line"), nil, "L") {
  espeech(text_range(line_beginning,line_ending))
  }
  if defined?(SpeechToFile) && SpeechToFile.available?
    menu.option(p_("EAPI_Form", "Read to file")) {
      SpeechToFile.from_edit_box(self)
    }
  end
  menu.option(p_("EAPI_Form", "Copy"), nil, "c") {
copy
  }
  if (@flags&Flags::ReadOnly)==0
    menu.option(p_("EAPI_Form", "Cut"), nil, "x") {
cut
  }
  menu.option(p_("EAPI_Form", "Paste"), nil, "v") {
paste
  }
  menu.option(p_("EAPI_Form", "Undo"), nil, "z") {
eundo
  }
  menu.option(p_("EAPI_Form", "Redo"), nil, "y") {
eredo
  }
  if defined?(SpellCheck) && (!SpellCheck.respond_to?(:available?) || SpellCheck.available?)
    menu.option(p_("EAPI_Form", "Spell check"), nil, "S") {
    if requires_premiumpackage("scribe")
  espellcheck
  end
  }
  end
  menu.submenu(p_("EAPI_Form", "Load last text")) {|m|
  for e in @@lastedits
    next if e==self
    t=(e.header+": "+e.text)[0...200]
    m.option(t, e) {|e|
    @@lastedits.push(self.deep_dup) if @text!=""
    set_text(e.text)
    }
    end
  }
  end
  menu.option(p_("EAPI_Form", "Find"), nil, "f") {
search
  }
  menu.option(p_("EAPI_Form", "Quick translation"), nil, "t") {
  if requires_premiumpackage("scribe")
  espeech(translatetext(0,Configuration.language,get_check_or_all))
  end
  }
    menu.option(p_("EAPI_Form", "Translate"), nil, "T") {
    if requires_premiumpackage("scribe")
  translator(get_check_or_all)
  end
  }
  for a in @@customactions
      menu.option(a[0]) {
    a[1].call(self)
  }
    end
  }
    s=@header+" - "+p_("EAPI_Form", "Edit box")+" ("+_("Context menu")+")"
  s=p_("EAPI_Form", "Edit") if submenu==false
    menu.submenu(s) {|m|c.call(m)}
  super(menu, submenu)
end
def espellcheck
  return if !defined?(SpellCheck) || (SpellCheck.respond_to?(:available?) && !SpellCheck.available?)
  sclangs=SpellCheck.languages
  return if sclangs.size==0
  langs=[]
  langnames=[]
  lnindex=0
  for lk in Lists.langs.keys
    next if !sclangs.map{|l|l[0..1].downcase}.include?(lk[0..1].downcase)
    langs.push(lk)
    l=Lists.langs[lk]
    langnames.push(l['name']+" ("+l['nativeName']+")")
    lnindex=langs.size-1 if lk[0..1].downcase==Configuration.language[0..1].downcase
    end
  splt=@text+""
      form = Form.new([
  lst_languages = ListBox.new(langnames, header: p_("EAPI_Form", "Language"), index: lnindex),
  btn_replace = Button.new(p_("EAPI_Form", "Replace")),
  btn_cancel = Button.new(_("Cancel"))
  ], index: 0, silent: false, quiet: true)
  errors=[]
  lst_languages.on(:move) {
  form.fields[1...-2]=[]
  form.show_all
  errors=SpellCheck.check(langs[lst_languages.index], @text)
  for error in errors
        phr=splt[error.index...(error.index+error.length)]
        frgb=-1
        frge=0
        pfrgb=error.index-60
        pfrgb=0 if pfrgb<0
        pfrge=error.index+error.length+60
        pfrge=splt.length-1 if pfrge>=splt.length
                for i in pfrgb..pfrge
          if i<error.index&& frgb==-1
          frgb=i if splt[i-1..i-1]==" " || i==0
          elsif i>error.index+error.length
          frge=i if splt[i+1..i+1]==" " || i+1==splt.length
          end
        end
            frg=splt[frgb..frge]||""
    letphr="("+phr.split("").join(", ")+")"
    options=[]
    for sug in error.suggestions
      letsug="("+sug.split("").join(", ")+")"
      opt=sug+" "+letsug
      options.push(opt)
    end
    label=phr+" "+letphr+": "+frg
    lst = ListBox.new([p_("EAPI_Form", "Ignore")]+options+[p_("EAPI_Form", "Use custom text")], header: label)
edt = EditBox.new(label, type: 0, text: phr)
lst.on(:move) {
for i in 0...errors.size
  l=form.fields[1+i*2]
  e=form.fields[1+i*2+1]
  next if l==nil || e==nil
  if l.index<l.options.size-1
    form.hide(e)
  else
    form.show(e)
    end
  end
}
        form.insert_before(btn_replace, lst)
    form.insert_before(btn_replace, edt)
    form.hide(edt)
    end
  }
  lst_languages.trigger(:move)
  btn_cancel.on(:press) {form.resume}
  form.cancel_button=btn_cancel
  btn_replace.on(:press) {
  chindex=0
  repls=0
  for i in 0...errors.size
    if form.fields[1+i*2].index>0
      corr=""
      if form.fields[1+i*2].index<form.fields[1+i*2].options.size-1
      corr=errors[i].suggestions[form.fields[1+i*2].index-1]
    else
      corr=form.fields[1+i*2+1].text
      end
      csize=corr.length
      splt[(errors[i].index+chindex)...(errors[i].index+errors[i].length+chindex)]=corr
            chindex+=csize-errors[i].length
      repls+=1
      end
    end
    set_text(splt)
    alert(np_("EAPI_Form", "%{count} word replaced", "%{count} words replaced", repls)%{:count=>repls.to_s})
    form.resume
  }
  form.accept_button = btn_replace
  form.wait
  focus
  loop_update
  end
def copy
      Clipboard.text = get_check.gsub("\n","\r\n")
    alert(p_("EAPI_Form", "copied"), false)
  end
  def cut
        Clipboard.text=get_check.gsub("\n","\r\n")
    if (range=selected_range)
      edelete(range[0],range[1])
    end
    alert(p_("EAPI_Form", "Cut out"), false)

  end
  def paste
        einsert(text_utf8(Clipboard.text).delete("\r"))
    alert(p_("EAPI_Form", "pasted"), false)
  end
  def eundo
    return if @undo.size==0
          u=@undo.last
        @undo.delete_at(@undo.size-1)
u[0]==1?delete_inserted_undo(u[1],u[2]):einsert(u[2],u[1],false)
                    @redo.push(u)
          alert(p_("EAPI_Form", "undone"), false)
        end
        def eredo
          return if @redo.size==0
                r=@redo.last
        @redo.delete_at(@redo.size-1)
                r[0]==2?delete_inserted_undo(r[1],r[2]):einsert(r[2],r[1],false)
                    @undo.push(r)
          alert(p_("EAPI_Form", "Repeated"), false)
        end
        def search
                search=input_text(p_("EAPI_Form", "Enter a phrase to look for"),flags: 0,text: @lastsearch||"",escapable: true, permitted_characters: [], denied_characters: [], max_length: 0, move_to_end: false, select_all: true)
      if search!=nil
        @lastsearch=search
            ind=@index<text_len-1?text_range(@index+1,text_len-1).downcase.index(search.downcase):0
      ind+=@index+1 if ind!=nil
  ind=text_range(0,@index).downcase.index(search.downcase) if ind==nil
    if ind==nil
  alert(p_("EAPI_Form", "No match found."), false)
else
  @index=ind
  read_text(@index)
  end
  end

  end

  def text_len(value=@text)
    return @text_length if value.equal?(@text) && @text_length!=nil
    value.to_s.length
  end

  def text_byte_offset(index)
    index = clamp_text_index(index)
    return 0 if index <= 0
    return @text.bytesize if index >= text_len
    @text[0...index].to_s.bytesize
  end

  def clamp_text_index(index, allow_end=true)
    max = text_len
    max -= 1 unless allow_end
    max = 0 if max < 0
    index = index.to_i
    index = 0 if index < 0
    index = max if index > max
    index
  end

  def text_char(index)
    index = index.to_i
    return "" if index < 0 || index >= text_len
    @text[index] || ""
  end

  def text_range(from, to)
    from = clamp_text_index(from)
    to = clamp_text_index(to)
    return "" if to < from
    @text[from..to] || ""
  end

  def text_range_exclusive(from, to)
    from = clamp_text_index(from)
    to = clamp_text_index(to)
    return "" if to <= from
    @text[from...to] || ""
  end

  def text_replace!(from, to, value, exclusive=false)
    from = clamp_text_index(from)
    to = clamp_text_index(to)
    old_length = text_len
    value = value.to_s
    if exclusive
      return if to < from
      removed = to - from
      @text[from...to] = value
    else
      return if to < from
      removed = to - from + 1
      @text[from..to] = value
    end
    @text_length = old_length - removed + character_length(value)
  end

  def selected_range
    return nil if @index == @check
    from, to = [@index, @check].map { |i| clamp_text_index(i) }.sort
    to -= 1
    return nil if to < from
    [from, to]
  end

  def selected_or_current_range
    selected_range || [clamp_text_index(@index, false), clamp_text_index(@index, false)]
  end

  def character_length(value)
    value.to_s.length
  end

  def delete_inserted_undo(index, text)
    len = character_length(text)
    return if len == 0
    edelete(index, index + len - 1, false)
  end

  def line_beginning(index=@vindex, absolute=false)
    index = clamp_text_index(index)
                  return 0 if index==0
    return 0 if text_len==0
l=((((index>3000?index-3000:0) ... index).find_all { |i| text_char(i)=="\n"}[-1])||-1)+1
  r=((index ... (index<text_len-3000?index+3000:text_len)).find_all { |i| text_char(i)=="\n"}[0])||text_len
  ls=get_vlines(l,r, absolute)
  ind=l
  for n in ls
    ind=n if n<=index
  end
      return ind
end
def line_ending(index=@vindex, absolute=false)
  index = clamp_text_index(index)
              return 0 if text_len==0
  l=((((index>3000?index-3000:0) ... index).find_all { |i| text_char(i)=="\n"}[-1])||-1)+1
  r=((index ... (index<text_len-3000?index+3000:text_len)).find_all { |i| text_char(i)=="\n"}[0])||text_len
        ls=get_vlines(l,r, absolute)
      ln=0
    for i in 0...ls.size-1
    ln=i if ls[i]<=index
  end
  ind=ls[ln+1]-1
    return ind
  end
  def char_borders(ind)
    ind = clamp_text_index(ind)
    return [ind, ind]
    end
def get_vlines(l,r, absolute=false)
    return [l,r+1] if r-l<120 or (@flags&Flags::MultiLine)==0 or (@flags&Flags::DisableLineWrapping)>0 or Configuration.linewrapping==0 or absolute==true
  ls=[l]
    for c in l...r
           if text_char(c)==" " and c-ls[-1]>120 and c!=r-1
                        for oc in c..r
if text_char(oc)!=" "
              ls.push(oc)
              break if oc>=r
              break
              end
      end
          end
    end
    ls.delete_at(-1) if ls[-1]>=r
    ls.push(r+1) if ls[-1]!=r+1
                  return ls
  end
  def get_lines
        return [0] if text_len==0
        ns=(0...text_len).find_all {|c| text_char(c)=="\n"}
        ns.push(text_len-1)
        lines=[]
        for i in 0..ns.size-1
                    prior=-1
          prior=ns[i-1] if i>0
          lines+=get_vlines(prior+1,ns[i])
          lines.delete_at(-1)
          end
              return lines
          end
  def move_page_lines(delta)
    current_begin=line_beginning
    current_end=line_ending
    inlineindex=@vindex-current_begin
    target_begin=current_begin
    target_end=current_end
    delta.abs.times do
      if delta<0
        break if target_begin<=0
        probe=target_begin-1
        target_begin=line_beginning(probe)
        target_end=line_ending(probe)
      else
        break if target_end>=text_len
        probe=target_end+1
        target_begin=line_beginning(probe)
        target_end=line_ending(probe)
      end
    end
    line_width=target_end-target_begin
    inlineindex=line_width if inlineindex>line_width
    target_begin+inlineindex
  end
  def get_check(checkOnly=false)
  return @text if @index==@check && !checkOnly
  return "" if @index==@check && checkOnly
  range = selected_range
  return "" if range == nil
  return text_range(range[0], range[1])
end
def get_check_or_all
  c=get_check
  c=@text if c.length<=2
  return c
  end
  def einsert(text,index=@index,toundo=true)
    text=text.to_s.dup
    text.force_encoding(Encoding::UTF_8) if text.encoding!=Encoding::UTF_8
    text=text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    if @denied_characters.size>0 && @denied_characters.include?(text.split(""))
      play_sound("border")
      return
    end
    if @permitted_characters.size>0
      for c in text.split("")
        if !@permitted_characters.include?(c)
                play_sound("border")
      return
          end
      end
    end
    if toundo==true && (range = selected_range)
      index = range[0]
      edelete(range[0], range[1])
    end
                              index=clamp_text_index(index)
    text.delete!("\n") if (@flags&Flags::ReadOnly)!=0
    if (@flags&EditBox::Flags::Numbers)>0
    text=text.to_i.to_s
    text="" if text!="0" and text.to_i==0
  end
  text_length = character_length(text)
          if @max_length>=0 and text_len+text_length>@max_length
            play_sound("border")
            return
            end
  @undo.push([1,index,text]) if toundo==true
@undo.delete_at(0) if @undo.size>100
@redo=[] if toundo==true
    applied=[]
        for e in @elements
      i=@formats.find_index(e.type)
      if e.from<=index && e.to>=index && (text!="\n" || i!=nil)
        play_sound('signal')
        e.to+=text_length
        applied[i]=true if i!=nil
      elsif i!=nil && applied[i]!=true && e.to==index-1
        play_sound('right')
        e.to+=text_length
        applied[i]=true if i!=nil
      elsif e.from>index
        e.from+=text_length
        e.to+=text_length
        end
      end
    for i in 0...@formats.size
      if applied[i]!=true
        e=Element.new(index, index, @formats[i])
        @elements.push(e)
        end
      end
          @text.insert(index,text)
      @text_length=text_len+text_length
      @index=index+text_length
      NVDA.braille(text, @index, true, 1, index, @index) if defined?(NVDA) && NVDA.check
  @check=@index
  trigger(:insert, index, text)
  trigger(:change)
end
def edelete(from,to,toundo=true)
from=clamp_text_index(from)
to=clamp_text_index(to)
return if to<from || text_len==0
@check=@index=from if @index>from
deleted_text=text_range(from,to)
deleted_length=character_length(deleted_text)
@undo.push([2,from,deleted_text]) if toundo==true
@redo=[] if toundo==true
@undo.delete_at(0) if @undo.size>100
del=[]
for e in @elements
  if e.to<from
    next
  elsif e.from>to
    e.from-=deleted_length
    e.to-=deleted_length
  elsif e.from<from && e.to>to
    e.to-=deleted_length
  elsif e.from<from && e.to>=from
    e.to=from-1
  elsif e.from<=to && e.to>to
    e.from=from
    e.to-=deleted_length
  elsif e.from>=from && e.to<=to
    del.push(e)
    end
  end
  del.each{|e| @elements.delete(e)}
c=deleted_length
if c<20
c.times {
NVDA.braille("", @index, true, -1, from, @index) if defined?(NVDA) && NVDA.check
}
end
begin
text_replace!(from,to,"")
rescue Exception
  end
trigger(:delete, from, to)
trigger(:change)
@check=@index
  end
  def espeech(text)
  @tosay=text
  end
def esay
  if @tosay!="" and @tosay!=nil
        if (@flags&Flags::Password)==0
          speech_stop
    speak(@tosay)
  else
    play_sound("editbox_passwordchar")
  end
  @tosay=""
end
end
def audio?
  return @isaudio==true
end
def set_text(text,reset=true)
  @isaudio=false
  text=text.to_s.dup
  text.force_encoding(Encoding::UTF_8) if text.encoding!=Encoding::UTF_8
  text=text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
          @text=EltenLink.legacy_line_to_text(text.delete("\r"), eol: "\n")
    @text.chop! while @text.end_with?("\n")
    @text_length=nil
    @elements=[]
    if (@flags&Flags::MarkDown)!=0
          @text.gsub!(/(^http(s?)\:\/\/([^\n]+)$)/) {"[#{$1}](#{$1})"}
      md_proceed
    elsif (@flags&Flags::HTML)!=0
      html_proceed
    else
          @text.indices(/http(s?)\:\/\/([^\"\<\>\: \n]+)/).each {|ind|
            tail=text_range(ind,text_len-1)
            len=tail.index(/[ \n]/)||text_len-ind
            @elements.push(Element.new(ind,ind+len-1,Element::Link,[0,text_range_exclusive(ind,ind+len)]))
          } if (@flags&Flags::ReadOnly)>0
    end
    @text_length=@text.length
    @index=0 if reset==true
  @index=text_len if @index>text_len
end
alias settext set_text
def md_proceed
  @elements=[]
  ind=0
            @text.gsub!(/(\[[^\]]+\])(\[[^\]]+\])/) do
                            a=$1
              b=$2
              if ( (/^[\t ]*#{Regexp.escape($2)}\:[\t ]*([^\n]+\n?)/)=~@text)!=nil
                                a+"(#{$1})"
                else
              a+b
              end
            end
            @text.gsub!(/(^[\t ]*(\[[^\]]+\])\:[ %t]*([^\n]+)$)/) do
              if @text.indices($3).size>1
                ""
              else
                $1
              end
            end
            @text.gsub!(/\[\:(\d+)\]/) {"["+$1+"]"}
      ind=0
      while (m=text_range(ind,text_len-1).match(/(^[ \t]*([\#]+)[ \t]*([^\n]*)$)|(^([^\n]+)\n[ \t]*([\=\-]+)$)|(\[([^\]]+)\]\(([^[ \)]]+)([ ]*)((\"[^\"]*\")?)\))|(^([*-])([^\n]+)$)/))!=nil
                                    b=ind+m.begin(0)
    e=ind+m.end(0)
    if m.values_at(1)[0]!=nil
                          cnt=text_range(b,e-2).strip
        level=0
            level=cnt.count("#")
              while " \t\#=-".include?(text_char(b))
                text_replace!(b,b,"")
                e-=1
                end
              @elements.push(Element.new(b,e-1,Element::Header,level))
            elsif m.values_at(4)[0]!=nil
                            text_replace!(ind+m.begin(6),ind+m.end(6),"")
              e-=(m.values_at(6)[0].length+1)
              level=1
              level=2 if m.values_at(6)[0..0]=="-"
              @elements.push(Element.new(b,e,Element::Header,level))
              elsif m.values_at(7)[0]!=nil
                                  label=m.values_at(8)[0]
    url=m.values_at(9)[0]
        text_replace!(b,e-1,label)
    e=b+label.length
                        @elements.push(Element.new(b,e-1,Element::Link,[0,url]))
                      elsif m.values_at(13)!=nil
                        @elements.push(Element.new(b,e,Element::ListItem))
                                            end
                      ind=b+1
                    end
                  end
def html_proceed
  @elements=[]
  fragment=EltenAPI::Html.fragment(@text)
  output=+""
  fragment.children.each { |node| html_append_node(node, output) }
  @text=output.gsub("\u00a0", " ")
end

def html_append_node(node, output)
  if node.text?
    output << node.text
    return
  end
  return if !node.element?

  tag=node.name.to_s.downcase
  return if html_ignored_tag?(tag)

  case tag
  when "br"
    output << "\n"
    return
  when "iframe"
    html_append_frame(node, output)
    return
  when "img"
    label=(node["alt"].to_s.empty? ? node["title"].to_s : node["alt"].to_s)
    output << label if label != ""
    return
  end

  html_append_block_break(tag, output, before: true)
  start=output.length
  node.children.each { |child| html_append_node(child, output) }
  if tag=="a" && output.length==start && node["href"].to_s!=""
    output << node["href"].to_s
  end
  finish=output.length-1
  element=html_element_for_node(tag, node, start, finish)
  @elements << element if element != nil
  html_append_block_break(tag, output, before: false)
end

def html_append_frame(node, output)
  src=node["src"].to_s
  label=node["title"].to_s
  label=src if label==""
  return if label==""

  start=output.length
  output << label
  @elements << Element.new(start, output.length-1, Element::Frame, [label, src])
end

def html_element_for_node(tag, node, start, finish)
  return nil if finish<start

  case tag
  when "b", "strong"
    Element.new(start, finish, Element::Bold)
  when "i", "em"
    Element.new(start, finish, Element::Italic)
  when "u"
    Element.new(start, finish, Element::Underline)
  when "a"
    href=node["href"].to_s
    href=="" ? nil : Element.new(start, finish, Element::Link, [0, href])
  when "ul"
    Element.new(start, finish, Element::List, 0)
  when "ol"
    Element.new(start, finish, Element::List, 1)
  when "li"
    Element.new(start, finish, Element::ListItem)
  else
    if tag.length==2 && tag[0]=="h" && tag[1].to_i.between?(1, 6)
      Element.new(start, finish, Element::Header, tag[1].to_i)
    else
      Element.new(start, finish, Element::HTML, [tag, html_node_attributes(node)])
    end
  end
end

def html_node_attributes(node)
  attrs={}
  node.attribute_nodes.each { |attr| attrs[attr.name.to_s]=attr.value.to_s }
  attrs
end

def html_ignored_tag?(tag)
  ["script", "style", "audio", "source"].include?(tag)
end

def html_block_tag?(tag)
  return true if tag.length==2 && tag[0]=="h" && tag[1].to_i.between?(1, 6)
  ["address", "article", "aside", "blockquote", "div", "dl", "fieldset", "figcaption", "figure", "footer", "form", "header", "hr", "main", "nav", "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul", "li"].include?(tag)
end

def html_append_block_break(tag, output, before:)
  return if !html_block_tag?(tag)
  return if output.empty? || output.end_with?("\n")
  output << "\n"
end
                def find_element(type=0,flags=nil,revdir=false,index=@index)
                  e=Element.new(text_len,-1,0)
                  for el in @elements
                    e=el if (((!type.is_a?(Array) && el.type==type) || (type.is_a?(Array) && type.include?(el.type))) and (flags==nil or el.param==flags)) and (((revdir==false and el.from>index and el.from<e.from) or (revdir==true and el.to<index and el.to>e.to)))
                  end
                  return nil if e.type==0
                  return e
                  end
def finalize
  text_str
  end
  def text_str
    Log.warning("Method EditBox::text_str is deprecated and will be removed soon. Use EditBox::text or EditBox::text_html instead. Callback: "+Kernel.caller.join("   "))
  return @text.gsub("\n",EltenLink::LEGACY_LINE)
end
def text
  return @text.gsub("\n","\r\n")
end
def text_html
  r=""
  objs={}
  for e in @elements
    objs[e.from]||=[]
    objs[e.from].push(e.html_open)
    t=e.to
    t+=1 if text_char(t)!="\n"
    objs[t]||=[]
    objs[t].insert(0, e.html_close)
  end
  l=0
  for k in objs.keys.sort
    o=objs[k]
    r+=html_encode(text_range_exclusive(l,k))
    for b in o
      r+=b
    end
    l=k
  end
  r+=html_encode(text_range(l,text_len-1))
  EltenAPI::Html.fragment(r).to_html
end
def value
  text
  end
  def focus(index=nil,count=nil,spk=true)
    pos=50
    pos=index.to_f/(count-1).to_f*100.0 if index!=nil and count!=nil && count!=0
    if !audio?
    play_sound("editbox_marker", volume: 100, pitch: 100, pan: pos) if spk && Configuration.controlspresentation!=2
  else
    play_sound("editbox_audiomarker", volume: 100, pitch: 100, pan: pos) if spk && Configuration.controlspresentation!=2
    end
      if spk && @sounds!=nil
        for snd in @sounds
          play_sound(snd, volume: 100, pitch: 100, pan: pos)
          end
        end
      tp=p_("EAPI_Form", "Edit box")
      tp=p_("EAPI_Form", "Text") if (@flags&Flags::ReadOnly)>0
      tp=p_("EAPI_Form", "Media") if @audiotext!=nil
      tph=tp+": "
      tph="" if Configuration.controlspresentation==1
      head=@header.to_s + "... " + tph
                              nvda_braille_text(true) if defined?(NVDA) && NVDA.check
                              if @audiotext!=nil
                                                                @audioplayer = Player.new(@audiotext, label: @header, autoplay: false, quiet: true, stream: nil, lazy: true) if @audioplayer==nil
                                @audioplayed=false
                              elsif @audiostream!=nil
                                  @audioplayer = Player.new(nil, label: @header, autoplay: false, quiet: true,stream: @audiostream, lazy: true) if @audioplayer==nil
                                @audioplayed=false
                              end
                              if audio? && (Configuration.autoplay==0 || (Configuration.autoplay!=0 && (@flags&Flags::Transcripted)==0))
                                speak(head)
                                return
                                end
                        read_text(0,head) if spk
                      end
                            def audio?
                              return @audiotext!=nil || @audiostream!=nil || @audioplayer!=nil
                              end
                      def blur
                                                if @audioplayer!=nil && !@audioplayer.paused?
                        @audioplayer.stop
                        end
                        end
    def audio_url
      @audiotext
    end
    def audio_url=(u)
      @audiotext=u
      end
                        def read_text(index=0,head="")
      return speak(head) if @text=="" and head!="" and head!=nil
      return if @text==""

      index = clamp_text_index(index)
      len = text_len
      read_limit = defined?(EltenAPI::Speech::DEFAULT_SPEECH_TEXT_LIMIT) ? EltenAPI::Speech::DEFAULT_SPEECH_TEXT_LIMIT.to_i : 75_000
      limit_end = read_limit>0 ? [index+read_limit, len].min : len
      commands=[]
      start_byte = text_byte_offset(index)
      end_byte = text_byte_offset(limit_end)
      fragment_char = index
      fragment_byte = start_byte
      tail = @text.byteslice(start_byte, end_byte - start_byte).to_s
      tail.force_encoding(@text.encoding)
      tail.to_enum(:scan, READ_TEXT_BREAK_PATTERN).each do
        match = Regexp.last_match
        break_char = index + match.end(0)
        break_byte = start_byte + match.byteoffset(0)[1]
        next if break_char <= fragment_char || break_char >= limit_end
        append_read_text_fragment(commands, fragment_char, fragment_byte, break_byte, head)
        head = ""
        fragment_char = break_char
        fragment_byte = break_byte
      end
      append_read_text_fragment(commands, fragment_char, fragment_byte, end_byte, head)
      cmd = SpeechCommands::CustomCommand.new(limit_end) {|pos|@index=pos}
        commands.push(cmd)

        seq = SpeechSequence.new(commands)
        seq.run
      end

      def append_read_text_fragment(commands, position, byte_from, byte_to, head="")
        fragment = @text.byteslice(byte_from, byte_to - byte_from).to_s
        fragment.force_encoding(@text.encoding)
        fragment = fragment.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        fragment = head.to_s + "\n" + fragment if head!=nil && head!=""
        cmd = SpeechCommands::CustomCommand.new(position) {|pos|@index=pos if pos!=0}
        commands.push(cmd)
        commands.push(fragment)
      end

      def nvda_braille_text(include_header=false)
        text, cursor = braille_payload(include_header)
        NVDA.braille(text, cursor, false, 0, nil, cursor)
      end

      def braille_payload(include_header=false)
        len = text_len
        cursor = clamp_text_index(@index)
        from = 0
        to = len
        if len > BRAILLE_CONTEXT_CHARS
          half = BRAILLE_CONTEXT_CHARS / 2
          from = cursor - half
          from = 0 if from < 0
          to = from + BRAILLE_CONTEXT_CHARS
          if to > len
            to = len
            from = to - BRAILLE_CONTEXT_CHARS
            from = 0 if from < 0
          end
        end
        prefix = from > 0 ? "...\n" : ""
        suffix = to < len ? "\n..." : ""
        body = text_range_exclusive(from, to)
        text = prefix + body + suffix
        cursor_pos = prefix.length + cursor - from
        if include_header
          header = @header.to_s + "\n"
          text = header + text
          cursor_pos += header.length
        end
        [text, cursor_pos]
      end
    class Flags
MultiLine=1
ReadOnly=2
Password=4
  Numbers=8
  DisableLineWrapping=16
  MarkDown=32
  HTML=64
  Formattable=128
  Transcripted=256
end
    class Element
    attr_accessor :from, :to, :type, :param
    Header=1
    Link=2
    List=3
        ListItem=4
    Quote=5
    Bold=11
    Italic=12
        Underline=13
    Frame=14
        HTML=99
    def initialize(from=0,to=0,type=0,param=nil)
      @from,@to,@type,@param=from,to,type,param
            try_html if @type==HTML
    end
    def try_html
      return if !@param.is_a?(Array) || @param.size<2
      tag=@param[0]
      if tag.size==2&&tag[0..0]=="h"&&tag[1..1].to_i>0
        @type=Header
        @param=tag[1..1].to_i
        return
        end
      case tag
      when "b"
        @type=Bold
        @param=""
        when "i"
        @type=Italic
        @param=""
        when "u"
        @type=Underline
        @param=""
        when "a"
          @type=Link
          @param=[0,@param[1]['href']]
          when "ul"
            @type=List
            @param=0
            when "ol"
              @type=List
              @param=1
              when "li"
                @type=ListItem
                when "iframe"
                @type=Frame
                src=@param[1]['src']
                title=@param[1]['title']||src
                @param=[title, src]
      end
    end
    def description
      self.class.description(@type, @param)
    end
def html_open
  case @type
  when Bold
    "<b>"
  when Italic
    "<i>"
  when Underline
    "<u>"
  when Header
    "<h#{@param}>"
  when Link
    href=@param.is_a?(Array) ? @param[1].to_s : ""
    "<a href=\"#{EltenAPI::Html.escape(href)}\">"
  when List
    @param==0 ? "<ul>" : "<ol>"
  when ListItem
    "<li>"
  when HTML
    tag=@param.is_a?(Array) ? @param[0].to_s : ""
    attrs=@param.is_a?(Array) && @param[1].is_a?(Hash) ? @param[1] : {}
    return "" if tag==""
    attributes=attrs.map { |k, v| "#{EltenAPI::Html.escape(k)}=\"#{EltenAPI::Html.escape(v)}\"" }.join(" ")
    attributes=="" ? "<#{tag}>" : "<#{tag} #{attributes}>"
  else
    ""
  end
end

def html_close
  case @type
  when Bold
    "</b>"
  when Italic
    "</i>"
  when Underline
    "</u>"
  when Header
    "</h#{@param}>"
  when Link
    "</a>"
  when List
    @param==0 ? "</ul>" : "</ol>"
  when ListItem
    "</li>"
  when HTML
    tag=@param.is_a?(Array) ? @param[0].to_s : ""
    tag=="" ? "" : "</#{tag}>"
  else
    ""
  end
end
    def ignore?
      excl = ["script", "audio", "source"]
      return @type==HTML && excl.include?(@param[0])
      end
      def self.description(t, param=nil)
      case t
      when Bold
        return p_("EAPI_Form", "Bold")
        when Italic
          return p_("EAPI_Form", "Italic")
          when Underline
            return p_("EAPI_Form", "Underline")
            when Header
              return p_("EAPI_Form", "Heading level %{level}")%{:level=>param}
              when Link
                return p_("EAPI_Form", "Link")
                when List
                  return p_("EAPI_Form", "List")
                  when ListItem
                    return p_("EAPI_Form", "List item")
    when Frame
                    return p_("EAPI_Form", "Frame")
                    else
      return ""
      end
      end
    end
    def key_processed(k)
      return false if k==:enter && (key_held?(0x11) || (@flags&Flags::MultiLine)==0)
     return true
   end
   def self.add_customaction(name, cls, &b)
     @@customactions.push([name, b, cls]) if b!=nil
   end
   def self.unregister_class(cls)
     for a in @@customactions.dup
       @@customactions.delete(a) if a[2]==cls
       end
     end
     def hascontext
       return true
     end
     def tips
                tips=[]
       if (@flags&Flags::HTML)>0 || (@flags&Flags::MarkDown)>0
         tips.push(p_("EAPI_Form", "Use h or numbers from 1 to 6 to navigate to the next header"))
         tips.push(p_("EAPI_Form", "Use k to navigate to the next link"))
         tips.push(p_("EAPI_Form", "Use i to navigate to the next list item"))
         tips.push(p_("EAPI_Form", "Use the above shortcuts with shift to navigate to the previous items"))
       end
       return tips
       end
end

# A listbox class

  end
end
