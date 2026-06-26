# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
  class OpusRecordButton < Button
attr_accessor :label, :timelimit
attr_reader :file
  def initialize(label, filename, max_bitrate: 320, bitrate: 64, time_limit: 0)
super(label)
@file = nil
    @filename=filename
    @tags=nil
    @max_bitrate=max_bitrate
    @bitrate = bitrate
    @bitrate = @max_bitrate if @bitrate>@max_bitrate
    @timelimit=time_limit
    @framesize = 60
    @framesize = 40 if @bitrate>40
    @framesize = 20 if @bitrate>80
    @application = 2048
    @application = 2049 if @bitrate>=64
    @usevbr = 1
    @recorder=nil
    @status = 0
    @current_filename=@filename
    @form = Form.new([
    @btn_record = Button.new(p_("EAPI_Form", "record")),
    @btn_pause = Button.new(p_("EAPI_Form", "Pause recording")),
    @btn_stop = Button.new(p_("EAPI_Form", "Stop recording")),
    @btn_usefile = Button.new(p_("EAPI_Form", "Use existing file")),
    @btn_encoder = Button.new(p_("EAPI_Form", "Opus encoder settings")),
    @btn_tags = Button.new(p_("Conference", "Edit metadata and chapters")),
    @btn_play = Button.new(p_("EAPI_Form", "Play")),
    @btn_encodeplay = Button.new(p_("EAPI_Form", "Encode and play")),
    @btn_delete = Button.new(p_("EAPI_Form", "Delete recording")),
    @btn_select = Button.new(p_("EAPI_Form", "Ready"))
    ], index: 0, silent: false, quiet: true)
    @form.hide(@btn_pause)
    @form.hide(@btn_stop)
    @form.hide(@btn_tags)
    @form.hide(@btn_play)
    @form.hide(@btn_encodeplay)
    @form.hide(@btn_delete)
    @btn_record.on(:press) {
        if @status==0 or confirm(p_("EAPI_Form", "Are you sure you want to delete the previous recording and create a new one?"))
          @current_filename = @filename
    play_sound("recording_start")
    @status = 1
    @recorder = Recorder.opus_recording(@filename, @bitrate, @framesize, @application, @usevbr, @timelimit)
    @form.hide(@btn_record)
    @form.hide(@btn_usefile)
    @form.hide(@btn_tags)
    @form.hide(@btn_play)
    @form.hide(@btn_encoder)
    @form.hide(@btn_encodeplay)
    @form.hide(@btn_delete)
    @form.show(@btn_pause)
    @form.show(@btn_stop)
    if @timelimit>5
      @form.add_timer(@recinfotimer = FormTimer.new(@timelimit-5) {
        play_sound("recording_nearlimit")
        })
        end
    if @timelimit>0
        @form.add_timer(@recstoptimer = FormTimer.new(@timelimit) {
@btn_stop.press
})
end
  end
      }
    @btn_stop.on(:press) {
    @recorder.stop
    @form.delete_timer(@recinfotimer) if @recinfotimer!=nil
    @form.delete_timer(@recstoptimer) if @recstoptimer!=nil
    play_sound("recording_stop")
    @recorder=nil
    @status = 2
    @form.show(@btn_record)
    @form.show(@btn_tags) if holds_premiumpackage("audiophile")
    @form.show(@btn_play)
    @form.hide(@btn_encodeplay)
    @form.hide(@btn_pause)
    @form.hide(@btn_stop)
    @form.show(@btn_encoder)
    @form.show(@btn_usefile)
    @form.show(@btn_delete)
    @btn_record.label = p_("EAPI_Form", "Record again")
    @btn_pause.label = p_("EAPI_Form", "Pause recording")
    @form.index=0
    @form.focus
    }
    @btn_usefile.on(:press) {
    if @status==0 or confirm(p_("EAPI_Form", "Are you sure you want to delete the previous recording and create a new one?"))
      file=get_file(p_("EAPI_Form", "Select audio file"), path: EltenPath.with_separator(Dirs.documents), save: false, extensions: [".mp3",".wav",".ogg",".mid",".mod",".m4a",".flac",".wma",".opus",".aac",".aiff",".w64"])
      if file!=nil
set_source(file)
        alert(p_("EAPI_Form", "File selected"))
        end
      end
      loop_update
    }
    @btn_tags.on(:press) {
    edit_tags
    @form.focus
    }
    @btn_play.on(:press) {
    player(@current_filename, label: p_("EAPI_Form", "Recording preview"))
    @form.focus
    }
    @btn_encodeplay.on(:press) {
    get_file
    @form.index=@btn_play
    @btn_play.press
    }
    @btn_pause.on(:press) {
    if @recorder.paused
      @btn_pause.label = p_("EAPI_Form", "Pause recording")
      @recorder.resume
      play_sound("recording_start")
    else
      @btn_pause.label = p_("EAPI_Form", "Resume recording")
      @recorder.pause
      play_sound("recording_stop")
      end
    }
    @btn_encoder.on(:press) {
    if @status==0 or @current_filename!=@filename or confirm(p_("EAPI_Form", "The encoder settings will not apply to the current record. Are you sure you want to continue?"))
      show_encodersettings
      @form.focus
      end
    }
    @btn_delete.on(:press) {
delete_audio
@form.index=0
        @form.focus
    }
    @btn_select.on(:press) {
    @btn_stop.press if @recorder!=nil
    @form.resume
    }
        @form.cancel_button = @btn_select
      end
      def delete_audio(force=false)
        return true if @status==0
            if @filename!=@current_filename or force or confirm(p_("EAPI_Form", "Are you sure you want to delete recorded audio?"))
              @btn_stop.press if @recorder!=nil
        File.delete(@filename) if FileTest.exists?(@filename)
        @form.hide(@btn_delete)
        @form.hide(@btn_tags)
        @form.hide(@btn_play)
        @status=0
                return true
      else
        return false
      end
        end
      def update
super
if @pressed
  show
  focus
  end
end
def show_encodersettings
  profiles = [
  [p_("EAPI_Form", "Low"), 24, 60, 0],
  [p_("EAPI_Form", "Lower"), 32, 60, 0],
  [p_("EAPI_Form", "Standard"), 48, 40, 0],
[p_("EAPI_Form", "Higher"), 64, 40, 1],
[p_("EAPI_Form", "High"), 96, 20, 1],
[p_("EAPI_Form", "Max"), @max_bitrate, ((@max_bitrate>80)?20:40), 1]
  ]
  for pr in profiles
    profiles.delete(pr) if pr[1]>@max_bitrate
    end
  appind=@application==2048?0:1
  form = Form.new([
  lst_profile = ListBox.new(profiles.map{|pr|pr[0]}+[p_("EAPI_Form", "Custom")], header: p_("EAPI_Form", "Quality")),
    lst_bitrate = ListBox.new(bitrates_available.map{|b|b.to_s+" kbps"}, header: p_("EAPI_Form", "Bitrate"), index: bitrates_available.find_index(@bitrate)||0),
  lst_framesize = ListBox.new(framesizes_available.map{|f|f.to_s+" ms"}, header: p_("EAPI_Form", "Frame size"), index: framesizes_available.find_index(@framesize)||0),
  lst_application = ListBox.new([p_("EAPI_Form", "Speech profile"), p_("EAPI_Form", "Music profile")], header: p_("EAPI_Form", "Encoder profile"), index: appind),
  chk_usevbr = CheckBox.new(p_("EAPI_Form", "Use variable bitrate"), checked: @usevbr.to_i!=0),
  btn_save = Button.new(_("Save")),
  btn_cancel = Button.new(_("Cancel"))
  ], index: 0, silent: false, quiet: true)
  lst_profile.on(:move) {
  if lst_profile.index<profiles.size
  pr=profiles[lst_profile.index]
  lst_bitrate.index = bitrates_available.find_index(pr[1])||0
  lst_framesize.index = framesizes_available.find_index(pr[2])||0
  lst_application.index=0
  chk_usevbr.checked=true
  form.hide(lst_bitrate)
  form.hide(lst_framesize)
  form.hide(lst_application)
  form.hide(chk_usevbr)
else
  form.show(lst_bitrate)
  form.show(lst_framesize)
  form.show(lst_application)
  form.show(chk_usevbr)
  end
  }
  suc=false
  for i in 0...profiles.size
    pr=profiles[i]
    bitrate = bitrates_available[lst_bitrate.index]
    framesize = framesizes_available[lst_framesize.index]
    if bitrate==pr[1] && framesize==pr[2] && lst_application.index==0 && chk_usevbr.checked
lst_profile.index=i
lst_profile.trigger(:move, lst_profile.index)
suc=true
      end
    end
    if suc==false
      lst_profile.index=profiles.size
      lst_profile.trigger(:move, lst_profile.index)
      end
  btn_cancel.on(:press) {form.resume}
  btn_save.on(:press) {
  @bitrate = bitrates_available[lst_bitrate.index]
  @framesize = framesizes_available[lst_framesize.index]
  @application = lst_application.index==0?2048:2049
  @usevbr = chk_usevbr.checked ? 1 : 0
  form.resume
  }
  form.cancel_button = btn_cancel
  form.accept_button = btn_save
  form.wait
end
def framesizes_available
  [2.5, 5, 10, 20, 40, 60, 80, 100, 120]
end
def bitrates_available
  all = [8, 16, 24, 32, 48, 64, 80, 96, 128, 160, 196, 256, 320]
  m=[]
  for b in all
    m.push(b) if b<=@max_bitrate
  end
  return m
end
def get_tags(default=true)
  if @tags==nil
    return nil if default==false
    snd = Sound.new(@current_filename)
  ai = snd.info
    tgs = ai.like_ogg
    snd.close
    return tgs
  else
      return @tags
  end
    end
def edit_tags
  tgs = get_tags.deep_dup
  editable_tags = ["TITLE", "ARTIST", "ALBUM", "TRACKNUMBER", "COPYRIGHT"]
  form = Form.new([
  lst_tags = ListBox.new([], header: p_("EAPI_Form", "Tags")),
  edt_value = EditBox.new(p_("EAPI_Form", "Tag value")),
  lst_chapters = ListBox.new([], header: p_("EAPI_Form", "Chapters")),
  btn_save = Button.new(_("Save")),
  btn_cancel = Button.new(_("Cancel"))
  ], index: 0, silent: false, quiet: true)
  tbld = Proc.new {
  mapper = {
'TITLE'=>p_("EAPI_Form", "Title"),
'ARTIST' => p_("EAPI_Form", "Artist"),
'ALBUM'=>p_("EAPI_Form", "Album"),
'TRACKNUMBER'=>p_("EAPI_Form", "Track number"),
'COPYRIGHT'=>p_("EAPI_Form", "Copyright"),
}
opts=[]
for k in editable_tags
v = mapper[k]||k
opts.push("#{v}: #{tgs[k]||""}")
  end
lst_tags.options=opts
opts=[]
for i in 0..999
  next if tgs["CHAPTER#{sprintf("%03d", i)}"]==nil
time = tgs["CHAPTER#{sprintf("%03d", i)}"]
  name = tgs["CHAPTER#{sprintf("%03d", i)}NAME"]||""
  opts.push(name+": "+time)
  end
lst_chapters.options = opts
  }
  getchaps = Proc.new {
  chaps=[]
  for i in 0..999
  next if tgs["CHAPTER#{sprintf("%03d", i)}"]==nil
time = tgs["CHAPTER#{sprintf("%03d", i)}"]
  name = tgs["CHAPTER#{sprintf("%03d", i)}NAME"]||""
  chaps.push([time,name])
  tgs.delete("CHAPTER#{sprintf("%03d", i)}")
  tgs.delete("CHAPTER#{sprintf("%03d", i)}NAME")
  end
chaps
  }
  setchaps = Proc.new{|chaps|
chaps=chaps.sort_by{|c|c[0]}
  for i in 0...chaps.size
tgs["CHAPTER#{sprintf("%03d", i)}"]=chaps[i][0]
tgs["CHAPTER#{sprintf("%03d", i)}NAME"] = chaps[i][1]||""
end
tbld.call
  }
  addchap = Proc.new{|time,name|
  chaps=[[time,name]]+getchaps.call
  setchaps.call(chaps)
}
delchap = Proc.new{|index|
chaps=getchaps.call
chaps.delete_at(index)
setchaps.call(chaps)
}
editchap = Proc.new{|index|
chaps=getchaps.call
chap=["00:00:00", ""]
chap=chaps[index] if index.is_a?(Numeric) && index>=0 && index<chaps.size
index=chaps.size if !index.is_a?(Numeric) || index<0 || index>chaps.size
  frm = Form.new([
fedt_name = EditBox.new(p_("EAPI_Form", "Chapter name"), type: 0, text: chap[1]),
fedt_time = EditBox.new(p_("EAPI_Form", "Chapter time (hh:mm:ss.uuu)"), type: 0, text: chap[0]),
fbtn_save = Button.new(_("Save")),
fbtn_cancel = Button.new(_("Cancel")),
], index: 0, silent: false, quiet: true)
fbtn_save.on(:press) {
if (/^\d\d\:[0-5]\d\:[0-5]\d(\.\d\d\d)?$/=~fedt_time.text)!=nil
  fedt_time.settext(fedt_time.text+".000") if !fedt_time.text.include?(".")
chaps[index]=[fedt_time.text, fedt_name.text]
setchaps.call(chaps)
frm.resume
else
  speak(p_("EAPI_Form", "Wrong time format, the proper format is two hours digits, colon, two minutes digits, colon, two seconds digits and, optionally, three milliseconds digits preceeded by dot"))
  end
}
fbtn_cancel.on(:press) {frm.resume}
frm.cancel_button = fbtn_cancel
frm.accept_button = fbtn_save
frm.wait
lst_chapters.focus
}
  lst_tags.on(:move) {
  edt_value.set_text(tgs[editable_tags[lst_tags.index]])
    }
  edt_value.on(:change) {
  tgs[editable_tags[lst_tags.index]] = edt_value.text
  tbld.call
  }
  lst_chapters.bind_context{|menu|
  menu.option(p_("EAPI_Form", "Add new chapter manually"), nil, "n") {editchap.call(-1)}
  menu.option(p_("EAPI_Form", "Add chapters with playback"), nil, "N") {
  frm = Form.new([
  fpl=Player.new(@current_filename,label: p_("EAPI_Form", "Chapters editor, use context menu to add chapters"),autoplay: true,quiet: true),
  fbtn_close = Button.new(_("Close"))
  ], index: 0, silent: false, quiet: true)
  frm.bind_context{|menu|
  menu.option(p_("EAPI_Form", "Add chapter here"), nil, :n) {
  paused=fpl.paused?
  if !paused
    fpl.stop
  end
  name = input_text(p_("EAPI_Form", "Chapter name"), flags: 0, text: "", escapable: true)
  time = fpl.position
  time = sprintf("%02d:%02d:%02d.%03d", time/3600, (time/60)%60, time%60, time-time.to_i)
   if !paused
    fpl.play
  end
  if name!=nil
    chaps=getchaps.call
    chaps.push([time, name])
    setchaps.call(chaps)
    end
  }
  }
  fbtn_close.on(:focus) {fpl.stop}
  fpl.on(:focus) {fpl.play}
  fbtn_close.on(:press) {frm.resume}
  frm.cancel_button=fbtn_close
  frm.accept_button=fbtn_close
  frm.wait
  fpl.close
  lst_chapters.focus
    }
  if lst_chapters.options.size>0
    menu.option(p_("EAPI_Form", "Edit chapter"), nil, "e") {editchap.call(lst_chapters.index)}
    menu.option(_("Delete"), nil, :del) {delchap.call(lst_chapters.index)}
  end
  }
 tbld.call
lst_tags.trigger(:move)
btn_save.on(:press) {
@tags = tgs
alert(_("Saved"))
form.resume
}
    btn_cancel.on(:press) {form.resume}
  form.cancel_button = btn_cancel
    form.wait
  end
      def show
        @form.index=0
        @form.wait
      end
      def empty?
        @status==0
      end
      def set_source(file)
        @btn_stop.press if @recorder!=nil
                @status=2
        @current_filename = file
        @form.show(@btn_tags) if holds_premiumpackage("audiophile")
        @form.show(@btn_play)
        if file[0..4]=="http:" or file[0..5]=="https:"
        @form.hide(@btn_encodeplay)
      else
        @form.show(@btn_encodeplay)
        end
        @form.show(@btn_delete)
        end
      def get_recording_file(force=false)
        @last_tags||=nil
        return nil if @status!=2
        if @current_filename[0..4]=="http:" || @current_filename[0..5]=="https:"
          if force
          tmp=rand(36**16).to_s(36)
          file=EltenPath.join(Dirs.temp, tmp)
          download_file(@current_filename, file)
          @current_filename=@filename=file
        else
          return nil
          end
          end
        if @filename!=@current_filename
          waiting {
          Recorder.encode_opus_file(@current_filename, @filename, @bitrate, @framesize, @application, @usevbr, @timelimit, get_tags(false))
          }
              @current_filename = @filename
              @last_tags = get_tags
    @form.hide(@btn_encodeplay)
  elsif @last_tags!=get_tags
    @tempname = @filename+"_edtags.opus"
    c=Recorder.copy_opus_file(@filename, @tempname, get_tags)
    if c>0
    @last_tags=get_tags
    File.delete(@filename)
    FileUtils.mv(@tempname, @filename)
    end
          end
        return @filename
        end
end


  end
end
