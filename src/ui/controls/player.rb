# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
         class Player < FormField
           attr_reader :sound
           attr_reader :pause
           attr_accessor :label
                        def initialize(file, label: "", autoplay: true, quiet: true, stream: nil, lazy: false)
                          Programs.emit_event(:player_init)
                          file=EltenLink::Client.absolute_api_url(file) if file!=nil && FileTest.exists?(file)==false && file[0..0]=="/"
                          @label=label
                                                      focus if quiet==false
                                                      @file=file
                                                      @stream=stream
                                                                                                            @sound=nil
                                                                                                            if file.is_a?(Sound)
                                                         @sound=file
  @file=@sound.file
elsif !lazy
                                                       get_sound
  end
  if autoplay==true and @sound!=nil
    @pause=false
    play
    else
      @pause=true
    end
    end
def setsound(file)
@sound = Sound.new(file)
@basefrequency=@sound.frequency
@file=file
@sound.volume=0.8
rescue Exception
  @sound=nil
  @file=nil
  alert(p_("EAPI_Common", "This file cannot be played."))
end
def setstream(stream)
@sound = Sound.new(stream: stream)
@basefrequency=@sound.frequency
@file=nil
@sound.volume=0.8
rescue Exception
  @sound=nil
  @file=nil
  alert(p_("EAPI_Common", "This file cannot be played."))
end

def get_sound
  return @sound if @sound!=nil
  if @file.is_a?(String)
setsound(@file)
elsif @file==nil
  setstream(@stream)
  end
return @sound
  end

def update
super
  return if @sound!=nil && @sound.closed?
    boundary_action=keyboard_action_pressed?(:player_start, :player_end)
    if boundary_action==:player_start && get_sound!=nil
      get_sound.position=0
    elsif boundary_action==:player_end && get_sound!=nil
      get_sound.position=get_sound.length-1
    elsif raw_key_held?(:key_shift)==false && !modifier_held?(:main_modifier)
      if get_sound!=nil
      if key_pressed?(0x21)
        chapters=get_sound.chapters
        ch=chapters.sort{|a,b|b.time<=>a.time}.find{|c|c.time<get_sound.position-5}
        if ch!=nil
          get_sound.position=ch.time
          speak(ch.name)
          end
      elsif key_pressed?(0x22)
        chapters=get_sound.chapters
ch=chapters.sort{|a,b|a.time<=>b.time}.find{|c|c.time>get_sound.position}
if ch!=nil
          get_sound.position=ch.time
          speak(ch.name)
          end
        end
        end
            if key_pressed?(:key_right)
                get_sound.position+=5
                              end
      if key_pressed?(:key_left)
                get_sound.position-=5
                      end
            if key_pressed?(:key_up, repeat: true)
              pl=0.01
              pl=0.1 if get_sound.volume>=1
              get_sound.volume += pl
get_sound.volume = 10 if get_sound.volume > 10
      end
      if key_pressed?(:key_down, repeat: true)
        pl=0.01
              pl=0.1 if get_sound.volume>=1.1
        get_sound.volume -= pl
get_sound.volume = 0.05 if get_sound.volume < 0.05
end
elsif modifier_held?(:main_modifier) && raw_key_held?(:key_shift)==false
  if key_pressed?(:key_up, repeat: true)
                      get_sound.tempo += 2
get_sound.tempo = 100 if get_sound.tempo > 100
play_sound("listbox_focus") if get_sound.tempo==0
      end
      if key_pressed?(:key_down, repeat: true)
        get_sound.tempo -= 2
get_sound.tempo = -50 if get_sound.tempo < -50
play_sound("listbox_focus") if get_sound.tempo==0
end
elsif raw_key_held?(:key_shift) && !modifier_held?(:main_modifier)
  if key_pressed?(:key_right, repeat: true)
        get_sound.pan += 0.02
        get_sound.pan = 1 if get_sound.pan > 1
        play_sound("listbox_focus") if get_sound.pan==0
      end
      if key_pressed?(:key_left, repeat: true)
        get_sound.pan -= 0.02
        get_sound.pan = -1 if get_sound.pan < -1
        play_sound("listbox_focus") if get_sound.pan==0
      end
            if key_pressed?(:key_up, repeat: true)
        get_sound.frequency += @basefrequency.to_f/500.0*2.0
      get_sound.frequency=@basefrequency*2 if get_sound.frequency>@basefrequency*2
      play_sound("listbox_focus") if get_sound.frequency==get_sound.basefrequency
        end
      if key_pressed?(:key_down, repeat: true)
        get_sound.frequency -= @basefrequency.to_f/500.0*2.0
      get_sound.frequency=@basefrequency/2 if get_sound.frequency<@basefrequency/2
      play_sound("listbox_focus") if get_sound.frequency==get_sound.basefrequency
end
end
if key_pressed?(0x08) == true
  reset=10
  get_sound.volume=0.8
  get_sound.pan=0
  get_sound.tempo=0
  get_sound.frequency=@basefrequency
  end
end

def getposition(pos, len)
  form=Form.new([
  lst_hour=ListBox.new([], header: p_("EAPI_Form", "Hour")),
  lst_min=ListBox.new((0..59).to_a.map{|t|t.to_s}, header: p_("EAPI_Form", "Minute")),
  lst_sec=ListBox.new((0..59).to_a.map{|t|t.to_s}, header: p_("EAPI_Form", "Second")),
  btn_ok=Button.new(p_("EAPI_Form", "Jump")),
  btn_cancel=Button.new(_("Cancel"))
  ], index: 0, silent: false, quiet: true)
  hours=len/3600
  (0..hours).each{|h|lst_hour.options.push(h.to_s)}
  lst_hour.on(:move) {
  t=(len-lst_hour.index*3600)/60
  for i in 0..59
    if t<=i
      lst_min.disable_item(i)
    else
      lst_min.enable_item(i)
      end
    end
    lst_min.trigger(:move, lst_min.index)
  }
  lst_min.on(:move) {
    t=(len-lst_hour.index*3600-lst_min.index*60)
  for i in 0..59
    if t<=i
      lst_sec.disable_item(i)
    else
      lst_sec.enable_item(i)
      end
    end
  }
  lst_hour.trigger(:move, lst_hour.index)
  lst_hour.index=(pos/3600).to_i
  lst_min.index=((pos/60)%60).to_i
  lst_sec.index=(pos%60).to_i
  btn_cancel.on(:press) {form.resume}
  btn_ok.on(:press) {
  t=lst_sec.index+lst_min.index*60+lst_hour.index*3600
  form.resume
  return t
  }
    form.cancel_button=btn_cancel
    form.accept_button=btn_ok
  form.wait
  return nil
  end

def savefile

    tf=EltenPath.normalize(@file)
    fs=tf.split("/")
    nm=fs.last.split("?")[0]
    nm=@label.delete("\r\n\\/:!@\#*?<>\'\"|+=`") if @label!="" and @label!=nil
        nm+=".opus"
        encoders=[]
        for e in MediaEncoders.list
          encoders.push(e) if e::Type==:audio
          end
        formats=[]
        for e in encoders
          f=e::Name+" ("+e::Extension+")"
          if e::Extension.downcase==".opus" && is_opus?
            f+= " ("+p_("EAPI_Form", "Copy original stream")+")"
            end
          formats.push(f)
          end
            dialog_open
        form=Form.new([
        tr_path = FilesTree.new(p_("EAPI_Form", "Destination"), path: EltenPath.join(Dirs.user, "Music"), hide_files: true, quiet: true),
        lst_format = ListBox.new(formats, header: p_("EAPI_Form", "File format")),
        edt_filename = EditBox.new(p_("EAPI_Form", "File name"),type: 0,text: nm,quiet: true),
        btn_save = Button.new(_("Save")),
        btn_cancel = Button.new(_("Cancel"))
        ])
        form.cancel_button=btn_cancel
        lst_format.on(:move) {
        eext=encoders[lst_format.index]::Extension
        fl=edt_filename.text
        ext=File.extname(fl)
        fb=(fl.reverse.sub(ext.reverse,"")).reverse
        edt_filename.set_text(fb+eext)
        }
        edt_filename.on(:change) {
        ext=File.extname(edt_filename.text)
        for i in 0...encoders.size
          if encoders[i]::Extension.downcase==ext.downcase
            lst_format.index=i
            break
            end
          end
        }
        btn_cancel.on(:press) {form.resume}
        btn_save.on(:press) {
        encoder = encoders[lst_format.index]
        pth=EltenPath.join(tr_path.selected, edt_filename.text)
                r=true
        waiting {
        if encoder::Extension.downcase==".opus" && is_opus?
          r=download_file(@file, pth)
          else
        encoder.encode_file(@file, pth)
        end
        }
        alert(_("Saved")) if r
        form.resume
        }
form.wait
          dialog_close
        end

        def is_opus?
          EltenLink::Client.api_audio_url?(@file)
          end

          def position
            return 0 if get_sound==nil
            return get_sound.position
          end

                    def duration
            return 0 if get_sound==nil
            return get_sound.length
          end

def play
  @pause=false
  Programs.emit_event(:player_play)
  get_sound.play if get_sound!=nil
end

def stop
  Programs.emit_event(:player_stop)
  get_sound.stop if get_sound!=nil
  @pause=true
end

def pause
  Programs.emit_event(:player_pause)
  get_sound.pause if get_sound!=nil
  @pause=true
end

def paused?
  @pause==true
  end

def completed
  return true if get_sound==nil
  get_sound.length>0 && get_sound.position>=get_sound.length-0.05
  end

def fade
  return if get_sound==nil
  for i in 1..20
    loop_update
    get_sound.volume-=0.05
    if get_sound.volume<=0.05
    get_sound.volume=0
    loop_update
    break
    end
    end
  end

def close
  Programs.emit_event(:player_close)
  get_sound.close if get_sound!=nil
end

def context(menu, submenu=false)
  if get_sound!=nil && !get_sound.closed?
    menu.option(p_("EAPI_Form", "Play/pause"), nil, :space) {
    if get_sound!=nil
                    if @pause!=true
                  pause
      else
        Programs.emit_event(:player_play)
                        get_sound.play
        @pause=false
      end
      end
    }
    menu.option(p_("EAPI_Form", "Get sound position"), nil, :p) {
    if get_sound!=nil
        d=0
    begin
    d=get_sound.position.to_i
  rescue Exception
    end
h=d/3600
        m=(d-d/3600*3600)/60
  s=d-d/60*60
  speak(sprintf("%0#{(h.to_s.size<=2)?2:d.to_s.size}d:%02d:%02d",h,m,s))
  end
      }
    menu.option(p_("EAPI_Form", "Get sound duration"), nil, :d) {
    if get_sound!=nil
        d=(get_sound.length||0).to_i
    h=d/3600
        m=(d-d/3600*3600)/60
  s=d-d/60*60
  speak(sprintf("%0#{(h.to_s.size<=2)?2:d.to_s.size}d:%02d:%02d",h,m,s))
  end
    }
    menu.option(p_("EAPI_Form", "Track info"), nil, :i) {
    if get_sound!=nil
    ai=get_sound.info
    fields=[
    [p_("EAPI_Form", "Title"), ai.title],
    [p_("EAPI_Form", "Artist"), ai.artist],
    [p_("EAPI_Form", "Album"), ai.album],
    [p_("EAPI_Form", "Track number"), ai.track_number],
    [p_("EAPI_Form", "Copyright"), ai.copyright]
        ]
       for a in fields.deep_dup
                  fields.delete(a) if a[1]==nil || a[1]==""
       end
       sel=TableBox.new(["",""], fields, index: 0, header: "", quiet: false)
       loop do
         loop_update
         sel.update
         break if key_pressed?(:key_escape)
       end
       end
    }
    if get_sound!=nil && get_sound.chapters.size>0
            menu.option(p_("EAPI_Form", "Show chapters"), nil, :c) {
      chapters = get_sound.chapters
      sel = ListBox.new(chapters.map{|c|c.name}, header: p_("EAPI_Form", "Chapters"), index: 0, flags: 0, quiet: false)
      play_sound("dialog_open")
      loop do
        loop_update
        sel.update
        ch=chapters[sel.index]
        if ch!=nil
        if key_pressed?(:key_enter)
          get_sound.position=ch.time if get_sound!=nil
          play
          if get_sound.position<ch.time
            speak(p_("EAPI_Form", "This chapter has not been buffered yet"))
            end
        elsif key_pressed?(:key_space)
          speak(ch.time)
        end
        end
        break if key_pressed?(:key_escape)
      end
      play_sound("dialog_close")
      }
      end
    menu.option(p_("EAPI_Form", "Jump to position"), nil, :j) {
                get_sound.pause
      dpos=getposition(get_sound.position, get_sound.length)
      dpos=get_sound.position if get_sound!=nil && dpos==nil
      dpos=dpos.to_i
      dpos=get_sound.length if get_sound!=nil && dpos>get_sound.length
            get_sound.play if get_sound!=nil
      get_sound.position=dpos if get_sound!=nil
      loop_update
    }
    if @file!=nil && (@file.include?("http:") || @file.include?("https:"))
    menu.option(p_("EAPI_Form", "Save file"), nil, "s") {
          savefile
    }
  end

    end
  end
  def focus(index=nil, count=nil)
    speak(@label) if @label!=""
    end
  def tips
    tips=[]
    tips.push(p_("EAPI_Form", "Use spacebar to toggle pause"))
    tips.push(p_("EAPI_Form", "Use left/right arrows to slide"))
    tips.push(p_("EAPI_Form", "Use up/down arrows to change playback volume"))
    tips.push(p_("EAPI_Form", "Use SHIFT with left/right arrows to change panning"))
    tips.push(p_("EAPI_Form", "Use SHIFT with up/down arrows to change pitch"))
    tips.push(p_("EAPI_Form", "Use CTRL with up/down arrows to change tempo").sub(/CTRL/i, main_modifier_name))
    tips.push(p_("EAPI_Form", "Use backspace to return to the default settings"))
    tips.push(p_("EAPI_Form", "Use home or end to move to the beginning or ending of a track"))
    tips.push(p_("EAPI_Form", "Use page up or page down to navigate to the previous or next chapter"))
    return tips
    end
end


  end
end
