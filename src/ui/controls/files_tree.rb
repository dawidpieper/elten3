# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
      class FilesTree < FormField
        # @param header [String] a window caption
        attr_accessor :header
        # @return [String] selected file name
                attr_accessor :file
                                attr_reader :cpath
                                # @return [Array] file extensions to show
                attr_accessor :exts

                def tree_root_path(path)
                  value = EltenPath.normalize(path)
                  match = /\A([A-Za-z]):(?:\.?\/?)?\z/.match(value)
                  return "#{match[1]}:/" if match
                  value
                end

                def tree_root_path?(path)
                  value = tree_root_path(path)
                  value == "/" || value.match?(/\A[A-Za-z]:\/\z/)
                end

                def tree_path_with_separator(path)
                  value = tree_root_path(path)
                  return "" if value == ""
                  EltenPath.with_separator(value)
                end

                # Creates a files tree
                # @param header [String] a window caption
                # @param path [String] an initial path
                # @param hide_files [Boolean] hide files
        # @param quiet [Boolean] don't write the caption at creation
                # @param extensions [Array] an array of file extensions to show
                # @param use_sounds [Boolean] play file type sounds while navigating
                def initialize(header="", path: "", hide_files: false, quiet: true, extensions: nil, use_sounds: true)
                            $filestrees||={}
                            original_path=EltenPath.normalize(path)
                            path=tree_path_with_separator(path) if path!=""
                            if original_path!="" && !tree_root_path?(original_path) && !File.directory?(original_path)
                              file=EltenPath.basename(original_path)
                              base_path=tree_path_with_separator(EltenPath.dirname(original_path))
                            else
                              file=""
                              base_path=path
                            end
                            @id=base_path+"/"+file+":"+((extensions||[]).join(""))+":::"+header
                @hidefiles=hide_files
        @header=header
        @specialvoices=use_sounds
        @exts=extensions
        @editmenus=[]
        @filemenus=[]
        @createmenus=[]
        @menus=[]
          if $filestrees[@id]!=nil
            f=$filestrees[@id]
            @file=f[1]
            @path=tree_path_with_separator(f[0])
                        #@file=nil if !FileTest.exists?(@path+"/"+@file)
          else
                    @path=base_path
        @file=""
                          @file=file if file!=""
                        end
                        focus if quiet==false
        end

        # Updates a files tree
      def update(init=false)
super
        if @sel == nil or @refresh == true
              if @path == ""
          @disks=EltenSystemHelpers.logical_drives
drive_files=@disks.map{|drive|tree_root_path(drive)}
@adds=[p_("EAPI_Form", "Desktop"),p_("EAPI_Form", "Documents"),p_("EAPI_Form", "Music")]
@addfiles=[Dirs.desktop,Dirs.documents,Dirs.music]
ind=drive_files.find_index(tree_root_path(@file))
ind=0 if ind==nil
                h=""
h=@header if init==true
@sel=ListBox.new(@disks+@adds, header: h, index: ind, flags: 0, quiet: false)
@sel.on(:move) {|arg|trigger(:move, arg)}
      @sel.silent=true if @specialvoices
      @files=drive_files+@addfiles
else
  dirs=[]
  fls=[]
  allowed_exts=nil
  allowed_exts=@exts.map{|e|e.to_s.downcase} if @exts!=nil
  Dir.each_child(@path) do |entry|
    full=EltenPath.join(@path, entry)
    begin
      if File.directory?(full)
        dirs.push(entry)
      elsif @hidefiles!=true && (allowed_exts==nil || allowed_exts.include?(File.extname(entry).downcase))
        fls.push(entry)
      end
    rescue Exception
    end
  end
  fls=dirs.polsort+fls.polsort
  ind=0
  ind=@sel.index if @sel!=nil
ind-=1 if ind>fls.size-1
ind=fls.find_index(@file,ind)
h=""
h=@header if init==true
@sel=ListBox.new(fls, header: h, index: ind)
@sel.on(:move) {|arg|trigger(:move, arg)}
@sel.silent=true if @specialvoices
@sel.focus if @refresh != true
@files=fls
@refresh=false
end
end
@sel.update
@file=@files[@sel.index]
@file="" if @sel.options.size==0
if cfile!=nil
if @file!=@lastfile and @specialvoices
  @lastfile=@file
          if filetype==0
            play_sound("file_dir", volume: 100, pitch: 100, pan: @sel.lpos)
            elsif filetype==1
  play_sound("file_audio", volume: 100, pitch: 100, pan: @sel.lpos)
elsif filetype==2
  play_sound("file_text", volume: 100, pitch: 100, pan: @sel.lpos)
elsif filetype==3
  play_sound("file_archive", volume: 100, pitch: 100, pan: @sel.lpos)
elsif filetype==4
  play_sound("file_document", volume: 100, pitch: 100, pan: @sel.lpos)
  end
end
  end
  if key_held?(0x10)==false
if (key_pressed?(:key_right) or @go == true) and File.directory?(cfile(true))
  @lastfile=nil
  @go = false
    s=true
        begin
    Dir.entries(cfile(true)) if s == true
  rescue Exception
    s=false
    retry
      end
  if s == true
        @path=tree_path_with_separator(cfile(true))
  @file=""
        @sel=nil
  end
    end
if key_pressed?(:key_left) and @path.size>0
  p=tree_path_with_separator(@path)
  if tree_root_path?(p)
    @file=tree_root_path(p)
    @path=""
  else
    p=EltenPath.normalize(p)
    p=p[0...-1] if p.end_with?("/")
    @file=EltenPath.basename(p)
    parent=EltenPath.dirname(p)
    @path=parent=="." ? "" : tree_path_with_separator(parent)
  end
@sel=nil
end
end
$filestrees[@id]=[@path,@file]
end

def bind_editmenu(&m)
    @editmenus.push(m)
end

def bind_filesmenu(&m)
  @filemenus.push(m)
end

def bind_createmenu(&m)
  @createmenus.push(m)
end

def bind_menu(&m)
  @menus.push(m)
end

def context(menu, submenu=false)
    filepr=Proc.new {|menu|
    @filemenus.each{|f| f.call(menu)}
    menu.option(p_("EAPI_Form", "Rename")) {
    rename
    }
    menu.option(_("Delete"), nil, :del) {
    fdelete
    }
            }
                editpr=Proc.new {|menu|
  menu.option(p_("EAPI_Form", "Copy"), nil, "c") {
copy
  }
  menu.option(p_("EAPI_Form", "Paste"), nil, "v") {
paste
  }
                  @editmenus.each{|f| f.call(menu)}
    }
    createpr=Proc.new {|menu|
    menu.option(p_("EAPI_Form", "New folder"), nil, "n") {
        name=""
while name==""
      name=input_text(p_("EAPI_Form", "Folder name"),flags: 0,text: "", escapable: true)
      end
    if name != nil
      FileUtils.mkdir_p(EltenPath.join(self.path, name))
      alert(p_("EAPI_Form", "The folder has been created."))
    end
    refresh
    }
    @createmenus.each{|f| f.call(menu)}
    }
  if submenu==false
  s=p_("EAPI_Form", "File")
      menu.submenu(s) {|m|filepr.call(m)}
        s=p_("EAPI_Form", "Edit")
    menu.submenu(s) {|m|editpr.call(m)}
    s=p_("EAPI_Form", "Create")
    menu.submenu(s) {|m|createpr.call(m)}
    else
  s=@header+" - "+p_("EAPI_Form", "Files Tree")+" ("+_("Context menu")+")"
  menu.submenu(s){|m|
  filepr.call(m)
  editpr.call(m)
  createpr.call(m)
    }
  end
  @menus.each{|m| m.call(menu)}
  super(menu, submenu)
end

def filetype
  return 0 if File.directory?(cfile(true))
  ext=File.extname(selected).downcase
  if ext==".mp3" or ext==".ogg" or ext==".wav" or ext==".mid" or ext==".wma" or ext==".flac" or ext==".aac" or ext==".opus" or ext==".m4a" or ext==".mov" or ext==".mp4" or ext==".avi" or ext==".mts" or ext==".aiff" or ext==".m4v" or ext==".mkv" or ext==".vob" or ext==".m2ts" or ext==".w64"
    return 1
  elsif ext==".txt"
    return 2
  elsif ext==".zip"
    return 3
  elsif ext==".doc" or ext==".rtf" or ext==".htm" or ext==".html" or ext==".docx" or ext==".pdf" or ext==".epub"
    return 4
  elsif ext==".eapi"
    return 5
      else
    return -1
    end
  end

# An opened path
# @return [String] an opened path
      def path(c=false)
                return @path if c==false
        return @path
      end

      # Opens a specified path
      #
      # @param pt [String] a path to open
      def path=(pt)
        @path=pt.to_s=="" ? "" : tree_path_with_separator(pt)
        @sel=nil
      end

      # Opens the focused path
        def go
          @go = true
          update
        end

        # Gets the current file
        # @return [String] current file
        def cfile(fulllocation=false)
          return "" if @file==nil
                    tmp=EltenPath.join(@path,@file)
if fulllocation==false
return tree_root_path(tmp) if @path.to_s=="" && tree_root_path?(tmp)
return EltenPath.basename(tmp)
else
  return tree_root_path(tmp)
end
end

          # Refreshes the tree
          def refresh
          @refresh=true
        end

        # Returns the path to the selected file or directory
        #
        # @param c [Boolean] use diacretics shortening
        # @return [String] the absolute path to a focused file or directory
          def selected(c=false)
            return "" if @file==nil
          r=""
          if c == false
            r = EltenPath.join(@path, @file)
          else
            if cfile!=nil
            r = EltenPath.join(@path, cfile)
          else
            return ""
            end
          end
          return r
          end

          def focus(index=nil,count=nil)
          if @sel == nil
          loop_update
            update(true)
          else
                    hin=""
          hin=@header+": \r\n" if @header!=""
                  hin += @file
        speak(hin)
        NVDA.braille(hin) if defined?(NVDA) && NVDA.check
        end
      end

      def paste
        files = Clipboard.files
        return if files.size==0
                waiting {
        for file in files
          src=file
          dst=EltenPath.join(@path, File.basename(file))
          if File.directory?(file)
            FileUtils.mkdir_p(dst)
            FileUtils.cp_r(File.join(src, "."), dst)
          else
            FileUtils.mkdir_p(File.dirname(dst))
            FileUtils.cp(src, dst)
            end
          end
          }
          alert(p_("EAPI_Form", "Pasted"), false)
          refresh
        end

        def copy
          Clipboard.files=[selected]
                    alert(p_("EAPI_Form", "Copied"), false)
        end

        def rename
                name=""
    while name==""
    name=input_text(p_("EAPI_Form", "New file name"),flags: 0, text: self.file, escapable: true)
    end
    if name != nil
    FileUtils.mv(self.selected, EltenPath.join(self.path, name))
    alert(p_("EAPI_Form", "The file name has been changed."))
  end
  refresh
        end

        def fdelete
          afile=self.selected
          confirm(p_("EAPI_Form", "Do you really want to delete %{filename}?")%{:filename=>self.file}) {
    if File.directory?(afile)
      FileUtils.rm_rf(afile)
    else
      File.delete(afile)
    end
    refresh
    alert(p_("EAPI_Form", "Deleted"))
}
end
def key_processed(k)
  if @sel!=nil
  return @sel.key_processed(k)
else
  return false
  end
end
def hascontext
  return true
  end
end


  end
end
