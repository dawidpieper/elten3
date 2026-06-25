# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2025 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require "fileutils"

class Scene_Sounds
  def initialize(file=nil)
    @file=file
        end
  def main
    @theme=load_soundtheme(@file)
@soundnames={
'cancel' => p_("Sounds", "Operation cancelled"),
'dialog_background' => p_("Sounds", "Background of dialog windows"),
'dialog_open' => p_("Sounds", "Dialog window opened"),
'dialog_close' => p_("Sounds", "Dialog window closed"),
'menu_background' => p_("Sounds", "Menu Background"),
'menu_open' => p_("Sounds", "Menu opened"),
'menu_close' => p_("Sounds", "Menu closed"),
'form_marker' => p_("Sounds", "Marker of a form"),
'listbox_marker' => p_("Sounds", "Marker of a listbox"),
'listbox_multimarker' => p_("Sounds", "Marker of a multiselect listbox"),
'listbox_focus' => p_("Sounds", "Focus move on a listbox"),
'border' => p_("Sounds", "Border of a listbox"),
'listbox_itemsubmenu' => p_("Sounds", "Expandable item on a listbox"),
'listbox_treeexpand' => p_("Sounds", "Item expanded"),
'listbox_treecollapse' => p_("Sounds", "Item collapsed"),
'listbox_select' => p_("Sounds", "Item selected"),
'listbox_statechecked' => p_("Sounds", "Ticked item on a listbox"),
'listbox_stateunchecked' => p_("Sounds", "Unticked item on a listbox"),
'listbox_itemnew' => p_("Sounds", "New or updated item on a listbox"),
'listbox_itemattachment' => p_("Sounds", "Item with attachment on a listbox"),
'listbox_itemclosed' => p_("Sounds", "Closed item on a listbox"),
'listbox_itemcontaining' => p_("Sounds", "Item containing other items on a listbox"),
'listbox_itemfuture' => p_("Sounds", "Future item on a listbox"),
'listbox_itemliked' => p_("Sounds", "Liked item on a listbox"),
'listbox_itempinned' => p_("Sounds", "Pinned item on a listbox"),
'listbox_itemrestricted' => p_("Sounds", "Item with restricted access on a listbox"),
'user_online' => p_("Sounds", "Online user"),
'user_sponsor' => p_("Sounds", "User being a sponsor"),
'file_archive' => p_("Sounds", "Compressed file on a files tree"),
'file_audio' => p_("Sounds", "Audio file on a files tree"),
'file_dir' => p_("Sounds", "Directory on a files tree"),
'file_document' => p_("Sounds", "Document on a files tree"),
'file_text' => p_("Sounds", "Text file on a files tree"),
'editbox_audiomarker' => p_("Sounds", "Marker of an editbox with audio in a form"),
'editbox_marker' => p_("Sounds", "Marker of an editbox in a form"),
'editbox_textselected' => p_("Sounds", "A piece of text in an editbox has beenselected"),
'editbox_textunselected' => p_("Sounds", "A piece of text in an editbox has been unselected"),
'editbox_bigletter' => p_("Sounds", "Capitalized letter in an editbox"),
'editbox_delete' => p_("Sounds", "Delete of a text in an editbox"),
'editbox_endofline' => p_("Sounds", "End of line in an editbox"),
'editbox_passwordchar' => p_("Sounds", "Password character in an editbox"),
'editbox_space' => p_("Sounds", "Space in an editbox"),
'button_marker' => p_("Sounds", "Marker of a button in a form"),
'checkbox_marker' => p_("Sounds", "Marker of a checkbox in a form"),
'feed_update' => p_("Sounds", "Feed updated"),
'feed_mention' => p_("Sounds", "Mentioned in a feed"),
'login' => p_("Sounds", "User signed in or Elten window focused"),
'logout' => p_("Sounds", "User signed out or Elten closed"),
'minimize' => p_("Sounds", "Elten minimized into tray"),
'messages_update' => p_("Sounds", "Messages window updated"),
'new' => p_("Sounds", "New event"),
'notification_birthday' => p_("Sounds", "Notification: birthday of a friend"),
'notification_blogcomment' => p_("Sounds", "Notification: new comment on your blog"),
'notification_blogfollower' => p_("Sounds", "Notification: new follower of your blog"),
'notification_blogmention' => p_("Sounds", "Notification: new blog mention"),
'notification_followedblog' => p_("Sounds", "Notification: new post on a followed blog"),
'notification_followedblogpost' => p_("Sounds", "Notification: new comment to a followed blog post"),
'notification_followedforum' => p_("Sounds", "Notification: new thread on a followed forum"),
'notification_followedforumpost' => p_("Sounds", "Notification: new post on a followed forum"),
'notification_followedthread' => p_("Sounds", "Notification: new post in a followed thread"),
'notification_friend' => p_("Sounds", "Notification: new friend"),
'notification_groupinvitation' => p_("Sounds", "Notification: new invitation to a group"),
'notification_mention' => p_("Sounds", "Notification: new mention"),
'notification_message' => p_("Sounds", "Notification: new message"),
'notification_monitor' => p_("Sounds", "Notification: online monitor"),
'notification_userjoin' => p_("Sounds", "Notification: new user joined followed conference channel"),
'conference_userjoin' => p_("Sounds", "New user joined conference"),
'conference_userleave' => p_("Sounds", "User left conference"),
'conference_userknock' => p_("Sounds", "User knocking to the conference"),
'conference_message' => p_("Sounds", "New chat message"),
'conference_diceroll' => p_("Sounds", "Dice rolled in conference"),
#'conference_cardpick' => p_("Sounds", "Card picked in conference"),
#'conference_cardchange' => p_("Sounds", "Card replaced in conference"),
#'conference_cardshuffle' => p_("Sounds", "Shuffled a deck in conference"),
#'conference_cardplace' => p_("Sounds", "Card placed in conference"),
'conference_whisper' => p_("Sounds", "Whisper in the conference"),
'conference_pushin' => p_("Sounds", "Push To Talk enabled in conferences"),
'conference_pushout' => p_("Sounds", "Push To Talk disabled in conferences"),
'conference_speechrequest' => p_("Sounds", "Speech requested in conferences"),
'conference_speechallow' => p_("Sounds", "Speech allowed in conferences"),
'conference_speechdeny' => p_("Sounds", "Speech denied in conferences"),
'calling' => p_("Sounds", "Calling user"),
'ringing' => p_("Sounds", "Incoming voice call"),
'recording_start' => p_("Sounds", "Recording started"),
'recording_stop' => p_("Sounds", "Recording stopped"),
'recording_nearlimit' => p_("Sounds", "Only five seconds of recording left"),
'right' => p_("Sounds", "Error"),
'clock' => p_("Sounds", "Clock sound"),
'alarm' => p_("Sounds", "Alarm Sound"),
'waiting' => p_("Sounds", "Waiting for an action to be completed"),
'signal' => p_("Sounds", "Signal"),
}
    if @file!=nil
      if @file!=""
        @name=@theme.name
        @changed=false
      else
        @name=input_text(p_("Sounds", "Type name of the sound theme"), flags: 0, text: "by #{Session.name}", escapable: true)
        path=""
                return $scene=Scene_SoundThemes.new if @name==nil
                        @name=@name[0..255] if @name.size>255
        n=@name.split(" ")
        ind=n.size
        for i in 0...n.size
          ind=i if n[i].downcase=='by'
          end
        for i in 0...n.size
                    break if i==ind
                    s=n[i]
                              t=s.split("")[0].upcase+s.split("")[1..-1].join.downcase
                              path+=t
          end
        @file=EltenPath.join(Dirs.soundthemes, path.delspecial+".elsnd")
        @theme=SoundTheme.new(@name, @file)
        @changed=true
                end
      end
        @snd=[]
    for file in @soundnames.keys.sort
          @snd.push(Struct_Sounds_Sound.new(file,@soundnames[file],@theme))
    end
    return $scene=Scene_Main.new if @snd.size==0
    h=p_("Sounds", "Sounds guide, press space to play")
    h=p_("Sounds", "Editing sound theme %{theme}")%{:theme=>@name} if @theme!=nil
    @fields = [
    @sel=ListBox.new(@snd.map{|o| o.description}, header: h, index: 0, flags: ListBox::Flags::Silent),
    @btn_play = Button.new(p_("Sounds", "Play")),
    @btn_playorig = Button.new(p_("Sounds", "Play original sound")),
    @btn_stop = Button.new(p_("Sounds", "Stop")),
    @btn_extract = Button.new(p_("Sounds", "Extract")),
    @btn_change = Button.new(p_("Sounds", "Change")),
    @btn_rename = Button.new(p_("Sounds", "Change sound theme name")),
    @btn_save = Button.new(p_("Sounds", "Save")),
     @btn_export = Button.new(p_("Sounds", "Export")),
        @btn_upload = Button.new(p_("Sounds", "Upload to server")),
        @btn_close = Button.new(p_("Sounds", "Close"))
    ]
          a=nil
    @form=Form.new(@fields, index: 0, silent: false, quiet: true)
    if @theme==nil
      @form.hide(@btn_playorig)
      @form.hide(@btn_change)
      @form.hide(@btn_save)
      @form.hide(@btn_export)
      @form.hide(@btn_rename)
   @form.hide(@btn_upload)
      end
    @btn_play.on(:press) {
              a.close if a!=nil
              snd=@snd[@sel.index].sound
              if snd!=nil
              a=Sound.new(stream: snd)
              a.volume=0.01*Configuration.volume
                a.play
                end
    }
    @btn_playorig.on(:press) {
              a.close if a!=nil
              snd=@snd[@sel.index].original
              if snd!=nil
              a=Sound.new(stream: snd)
              a.volume=0.01*Configuration.volume
                a.play
                end
    }
    @sel.on(:key_space) {|prm|
    key_shift = prm[0]
    if !key_shift
    @btn_play.press
  else
    @btn_playorig.press
    end
    }
    @btn_stop.on(:press) {
    if a!=nil
                  a.close
                  a=nil
                end
    }
    @btn_extract.on(:press) {extract}
    @btn_rename.on(:press) {
    newname=input_text(p_("Sounds", "Type name of the sound theme"), flags: 0, text: @name, escapable: true)
    loop_update
    if newname!=nil
      @name=newname
      @theme.name=@name
@changed=true
      end
    @form.focus
    }
    @btn_change.on(:press) {
                    file=get_file(p_("Sounds", "Select new sound"), path: "", save: false, extensions: [".ogg", ".mp3", ".wav", ".opus", ".aac", ".wma", ".m4a",".flac",".aiff"])
                loop_update
if file!=nil
  snd=Sound.new(file)
  if snd.length>0 && snd.length<300
  @snd[@sel.index].newfile=file
else
  alert(p_("Sounds", "The sound must not last longer than 5 minutes"))
  end
    snd.close
  @form.hide(@btn_export)
  @changed=true
end
@form.focus
    }
    @btn_save.on(:press) {
save
  @changed=false
  @form.show(@btn_export)
  @form.focus
    }
    @btn_export.on(:press) {
    loc=get_file(p_("Sounds", "Where to save this theme"), path: EltenPath.join(Dirs.user, "Documents"), save: true)
  if loc!=nil
    export_theme_zip(EltenPath.join(loc, File.basename(@theme.file, ".elsnd")+".zip"))
  end
  @form.fields[@form.index].focus
    }
    @btn_upload.on(:press) {upload}
    @btn_close.on(:press) {
    @form.resume
    }
    @form.cancel_button = @btn_close
    @form.wait  
              if @changed and @theme!=nil
                confirm(p_("Sounds", "Do you want to save this sound theme?")) {save}
                end
    a.close if a!=nil
    if @theme==nil
    $scene=Scene_Main.new
  else
    $scene=Scene_SoundThemes.new
    end
  end

  def export_theme_zip(destination)
    require "zip"
    FileUtils.rm_f(destination)
    Zip::File.open(destination, create: true) do |zip|
      zip.get_output_stream(File.basename(@theme.file)) do |io|
        io.write(File.binread(@theme.file))
      end
    end
  rescue Zip::Error, SystemCallError => e
    Log.warning("Sound theme export failed: #{e.class}: #{e.message}")
    alert(p_("Sounds", "Unable to export sound theme."))
  end
  
  def extract
  form = Form.new([
  edt_filename = EditBox.new(p_("Sounds", "File name"), type: 0, text: @snd[@sel.index].file+".ogg"),
  tr_path = FilesTree.new(p_("Sounds", "Destination"), path: EltenPath.join(Dirs.user, "Music"), hide_files: true, quiet: true),
  btn_extract = Button.new(p_("Sounds", "Extract")),
  btn_cancel = Button.new(_("Cancel"))
  ])
  form.cancel_button=btn_cancel
  form.accept_button=btn_extract
  btn_cancel.on(:press) {form.resume}
  btn_extract.on(:press) {
pth=EltenPath.join(tr_path.selected, edt_filename.text)  
cnt=@snd[@sel.index].sound
File.binwrite(pth, cnt)
alert(_("Saved"))
form.resume
  }
  form.wait
  @form.focus
    end
  
    def save
    failed=false
    waiting {
    magic="EltenSoundThemePackageFileCMPSMC"
cnt=""
    for s in @snd
            begin
            snd=s.sound(true)
            rescue Exception => e
              Log.error("Sound theme save failed for #{s.file}: #{e.class}: #{e.message}")
              alert(_("Error"))
              failed=true
              break
            end
            next if snd==getsound(s.file, true)
      cnt+=[s.file.bytesize, s.file, snd.bytesize, snd].pack("Ca*Ia*")
    end
    next if failed
    zcnt = Zlib::Deflate.deflate(cnt, Zlib::BEST_COMPRESSION)
    fcnt=[magic, Time.now.to_i, @theme.name.bytesize, @theme.name, zcnt.bytesize, zcnt].pack("a*QCa*Ia*")
              File.binwrite(@file, fcnt)
              @theme.file=@file if @theme.file==nil
  }
  return if failed
  use_soundtheme(@file) if @file!=nil and File.basename(@file, ".elsnd")==Configuration.soundtheme
    end
  
    def upload
      if @changed && !confirm(p_("Sounds", "This sound theme contains unsaved changes. Do you want to upload it anyway?"))
        @form.focus
        return
      end
id=File.basename(@file, ".elsnd")
id=input_text(p_("Sounds", "Sound theme ID. This ID will be used to track updates of this sound theme. Keep the current ID if you want to update existing sound theme."), flags: 0, text: id, escapable: true)
if id==nil || id==""
@form.focus
return
end
id=id.delspecial
      begin
        std = EltenLink::SoundThemes.list(elten_link)
      rescue EltenLink::Error => e
        Log.warning("Sound themes list failed before upload: #{e.message}")
        alert(_("Error"))
@form.focus
        return
      end
      for st in std
        if st.file.downcase==id.downcase+".elsnd" && st.user!=Session.name
alert(p_("Sounds", "Sound theme with that ID already exists."))
@form.focus
return
  end
    end
if id.downcase!=File.basename(@file, ".elsnd").downcase
  if FileTest.exists?(EltenPath.join(Dirs.soundthemes, "#{id}.elsnd"))
    alert(p_("Sounds", "Sound theme with that ID already exists."))
@form.focus
return
else
  FileUtils.mv(@file, EltenPath.join(Dirs.soundthemes, "#{id}.elsnd"))
  @file=EltenPath.join(Dirs.soundthemes, id+".elsnd")
end
end
fl=File.binread(@file)
begin
  EltenLink::SoundThemes.upload(elten_link, id, fl)
rescue EltenLink::Error => e
  Log.warning("Sound theme upload failed: #{e.message}")
      alert(_("Error"))
@form.focus
return
else
  alert(p_("Sounds", "Uploaded"))
  return
    end
      
      end
    
end

class Struct_Sounds_Sound
  attr_reader :description, :file
  attr_accessor :newfile
  def initialize(f, d, t=nil)
    @description=d
    @file=f
    @newfile=nil
    @theme=t
  end
  def original
        getsound(@file,true)
        end
  def sound(mustVorbis=false)
    if @newfile==nil
    sound=nil
    sound=@theme.getsound(@file) if @theme!=nil
    sound=getsound(@file,@theme!=nil) if sound==nil
    sound
  else
    if mustVorbis==false || (File.extname(@newfile).downcase==".ogg" && File.open(@newfile, "rb") { |io| io.read(4) }=="OggS")
    return File.binread(@newfile)
  else
    return Recorder.get_vorbis_data(@newfile, 192)
    end
  end
  end
  end
