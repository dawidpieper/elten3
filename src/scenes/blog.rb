# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2023 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Blog
  def initialize(index=0)
    index=0 if index==6
    @index=index
    end
  def main
        @sel = ListBox.new([p_("Blog", "Managed blogs"),p_("Blog", "Recently updated blogs"),p_("Blog", "Frequently updated blogs"),p_("Blog", "Frequently commented blogs"),p_("Blog", "Followed blogs"), p_("Blog", "Blogs popular with my friends"), p_("Blog", "Open external wordpress blog"), p_("Blog", "Followed blog posts"), p_("Blog", "Received mentions"), p_("Blog", "Blogs library")],header: p_("Blog", "Blogs"),index: @index)
  if Session.name=="guest"
    @sel.disable_item(0)
    @sel.index=1
    @sel.disable_item(4)
    @sel.disable_item(5)
    @sel.disable_item(7)
    @sel.disable_item(8)
  @sel.disable_item(9)
    end
    @sel.focus
    loop do
    loop_update
    @sel.update
    update
    break if $scene != self
    end
  end
  def update
    if key_pressed?(:key_escape)
            $scene = Scene_Main.new
    end
    if key_pressed?(:key_enter) or key_pressed?(:key_right)
     case @sel.index
     when 0
       $bloglistindex=0
      $scene = Scene_Blog_List.new(Session.name)
      when 1
        $bloglistindex=0        
        $scene = Scene_Blog_List.new
        when 2
        $bloglistindex=0        
        $scene = Scene_Blog_List.new(1)
        when 3
        $bloglistindex=0        
        $scene = Scene_Blog_List.new(2)
        when 4
          $bloglistindex=0
        $scene = Scene_Blog_List.new(3)
        when 5
                    $bloglistindex=0
        $scene = Scene_Blog_List.new(4)
        when 6
          u=input_text(p_("Blog", "Type blog address"), flags: 0, text: "", escapable: true)
          if u!=nil
            u.gsub!(/http(s?)\:\/\//, "")
            u.delete!("/")
                        r="[*"+u+"]"
         $bloglistindex=0
                        $scene = Scene_Blog_List.new(5, self, r)
                      end
        when 7
          if requires_premiumpackage("courier")
          $scene = Scene_Blog_Posts.new(Session.name,"FOLLOWED")
          end
          when 8
          if requires_premiumpackage("courier")
            $scene = Scene_Blog_Posts.new(Session.name,"MENTIONED")
            end
          when 9
            $bloglistindex=0        
        $scene = Scene_Blog_List.new(8, nil, :library)
   end
   end
    end
end

class Scene_Blog_Main
  def initialize(owner=Session.name,categoryselindex=0,scene=nil,check=false)
    @owner=owner
    @categoryselindex = categoryselindex
    @postselindex = 0
    @isowner=(blogowners(owner)||"").include?(Session.name)
    @check=check
    $blogreturnscene=scene
    end
  def main
    if @check==true    
begin
exist = EltenLink::Blog.exists?(elten_link, blog: @owner)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = Scene_Main.new
  return
end
if !exist
    if @owner==Session.name
    $scene = Scene_Blog_Create.new
  else
    alert(p_("Blog", "The blog cannot be found."))
    $scene=$blogreturnscene
    $scene=Scene_Main.new if $scene==nil
    end
  return
end
end
begin
blogtemp = EltenLink::Blog.categories(elten_link, blog: @owner)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = Scene_Main.new
  return
end
@blogname=blogname=blogtemp.name
@categories = []
for c in blogtemp.categories
  @categories.push(c)  if @isowner or c.posts>0
end
sel = [[p_("Blog", "All posts"), nil]] + @categories.map{|c|[c.name, c.posts.to_s]}
@sel = TableBox.new([nil, p_("Blog", "Posts")], sel, index: @categoryselindex, header: blogname, quiet: false)
  @sel.bind_context{|menu|context(menu)}
loop do
  loop_update
  @sel.update
  update
  break if $scene != self
  end
end
def update
  if key_pressed?(:key_escape) or (key_pressed?(:key_left) and !key_held?(0x10))
    $scene=$blogreturnscene    
    $scene = Scene_Main.new if $scene==nil
  end
  if key_pressed?(:key_enter) or (key_pressed?(:key_right) and !key_held?(0x10))
    bopen
            end
            end
            def bopen
              c=0
              c=@categories[@sel.index-1].id if @sel.index>0
      $scene = Scene_Blog_Posts.new(@owner,c,@sel.index)
                end
  def categorynew
                          name = ""
      name = input_text(p_("Blog", "Category name"),flags: 0,text: "",escapable: true)         while name == ""
    if name != nil
begin
            category_id = EltenLink::Blog.create_category(elten_link, blog: @owner, name: name)
rescue EltenLink::Error
  alert(_("Error"))
else
  alert(p_("Blog", "The category has been created."))
  @sel.rows.push([name,"0"])
  @sel.reload
  c=Struct_Blog_Category.new
  c.name=name
  c.id=category_id.to_i
    @categories.push(c)
end
speech_wait
end
@sel.focus
end
def categoryrename
                          name = ""
      name = input_text(p_("Blog", "Category name"), flags: 0, text: @categories[@sel.index-1].name, escapable: true)         while name == ""
    if name != nil
begin
      EltenLink::Blog.rename_category(elten_link, blog: @owner, category_id: @categories[@sel.index-1].id, name: name)
rescue EltenLink::Error
  alert(_("Error"))
else
  alert(p_("Blog", "The category has been renamed."))
  @sel.rows[@sel.index][0]=name
  @sel.reload
  @categories[@sel.index-1].name=name
end
speech_wait
end
@sel.focus
end
def categorydelete
          confirm(p_("Blog", "Are you sure you want to delete this category?")) {
            begin
              EltenLink::Blog.delete_category(elten_link, blog: @owner, category_id: @categories[@sel.index-1].id)
            rescue EltenLink::Error
        alert(_("Error"))
else
      alert(p_("Blog", "Category deleted"))
      @categories.delete_at(@sel.index-1)
      @sel.rows.delete_at(@sel.index)
      @sel.reload
          @sel.focus
      end
    }
  end
def context(menu)
    menu.option(p_("Blog", "Select")) {
    bopen
    }
    if @isowner and @sel.index>0
    menu.option(p_("Blog", "Rename"), nil, "e") {
          categoryrename
    }
    menu.option(_("Delete"), nil, :del) {
    categorydelete
    }
  end
  if @sel.index>0
  menu.option(p_("Blog", "Copy category URL")) {
  Clipboard.text=@categories[@sel.index-1].url
  alert(p_("Blog", "Category URL copied to clipboard"))
  }
  end
  if @isowner
    menu.option(p_("Blog", "New category"), nil, "n") {
    categorynew
    }
    end
            end
          end

class Scene_Blog_Create
  def initialize(shared=false, scene=nil)
    @shared=shared
    @scene=scene
    @scene=Scene_Blog.new if @scene==nil
    end
  def main
    if @shared==false
if !confirm(p_("Blog", "You do not have any blog. Do you want to create one?"))
  $scene = @scene
  return
end
end
name = input_text(p_("Blog", "Type a blog name"),flags: 0,text: "",escapable: true)
if name == nil
    $scene = @scene
  return
end
alert(p_("Blog", "Please wait..."))
speech_wait
$blogownerstime=0
begin
blog_id = EltenLink::Blog.create_blog(elten_link, name: name, shared: @shared)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = @scene
  return
end
alert(p_("Blog", "The blog has been created."))
speech_wait
$scene=Scene_Blog_Options.new(blog_id, @scene)
  end
end

class Scene_Blog_Posts
  SORT_POSTS_BY_BLOG = 0
  SORT_POSTS_BY_DATE = 1
  def initialize(owner,id,categoryselindex=0,postselindex=0,search=nil,page=0)
    @owner=owner
    @id = id
    @categoryselindex = categoryselindex
    @postselindex = postselindex
    @search=search
    @topage=page
    @isowner=(@id.is_a?(Integer)&&(blogowners(owner)||"").include?(Session.name))
    end
  def main
    @mentions=[]
    if @id=="MENTIONED" or @id=="NEWMENTIONED"
      begin
      mnts = EltenLink::Blog.list_mentions(elten_link, all: @id=="MENTIONED")
      rescue EltenLink::Error
        mnts=[]
      end
        for source in mnts
          mention=Struct_Blog_Mention.new
          mention.id=source.id
          mention.blog=source.blog
          mention.postid=source.post
          mention.author=source.author
                    mention.time=source.time
                    mention.message=source.message
                    @mentions.push(mention)
                  end
      end
        id = @id
        id=0 if @id==-1
        @page=1
        @post = []
        @sel = TableBox.new(["", p_("Blog", "Author"), p_("Blog", "Comments")], [], index: 0, header: "")
if @topage==0
        load_posts(@page)
      else
        for i in 1..@topage
          load_posts(i)
        end
        @page=@topage
        end
if @post.size==0 and @id=="NEW"
  alert(p_("Blog", "No new comments on your blog."))
  $scene=Scene_Notifications.new
  return
  elsif @post.size==0 and @id=="NEWFOLLOWED"
  alert(p_("Blog", "No new comments to followed blog posts."))
  $scene=Scene_Notifications.new
  return
  elsif @post.size==0 and @id=="NEWFOLLOWEDBLOGS"
  alert(p_("Blog", "No new posts on followed blogs."))
  $scene=Scene_Notifications.new
  return
  elsif @post.size==0 and @id=="NEWMENTIONED"
  alert(p_("Blog", "No new blog mentions."))
  $scene=Scene_Notifications.new
  return
end
@sel.index=@postselindex
@sel.focus
@sel.on(:move) {play_sound("file_audio", volume: 50, pitch: 50, pan: @sel.lpos) if @post[@sel.index]!=nil && (@post[@sel.index].audio || @post[@sel.index].audio_url.to_s!="")}
@sel.trigger(:move)
@sel.bind_context{|menu|context(menu)}
loop do
  loop_update
  @sel.update
  update
  break if $scene != self
  end
end
def update
  if key_pressed?(:key_escape) or (key_pressed?(:key_left) and !key_held?(0x10))
    if @id!=-1
    if @id == "NEW" or @id == "NEWFOLLOWED" or @id=="NEWFOLLOWEDBLOGS"
      $scene = Scene_Notifications.new
      elsif @id == "FOLLOWED"
      $scene = Scene_Blog.new(7)
      elsif @id == "MENTIONED"
      $scene = Scene_Blog.new(8)
      else
    $scene = Scene_Blog_Main.new(@owner,@categoryselindex,$blogreturnscene)
  end
else
  $scene=Scene_Blog_List.new
  end
  end
  if key_pressed?(:key_enter) or (key_pressed?(:key_right) and !key_held?(0x10))
      bopen
    end
  end
  def load_posts(page)
    id=@id
    id=0 if @id==-1
    @owner=Session.name if id.to_i.to_s!=id.to_s
    begin
    blogtemp = EltenLink::Blog.posts(elten_link, blog: @owner, category_id: id, page: page, search: @search)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = Scene_Main.new
  return
end
post=nil
@post = [] if @id == "NEWFOLLOWEDBLOGS"
for source in blogtemp.posts
  post=Struct_Blog_Post.new(source.id)
  post.name = source.name
    post.unread=source.unread
    post.owner=source.owner
    post.audio=source.audio
    post.audio_url=source.audio_url if source.respond_to?(:audio_url)
  post.date=source.date
  post.url=source.url
  post.author=source.author
  post.comments=source.comments
  post.followed=source.followed
  if @id=="MENTIONED" or @id=="NEWMENTIONED"
    for mention in @mentions
      if mention.blog==post.owner && mention.postid==post.id
        post.mention=mention
        @post.push(post.clone)
        end
      end
    else
  @post.push(post)
  end
end
if @id == "NEWFOLLOWEDBLOGS" and LocalConfig["BlogPostsSortBy"] == SORT_POSTS_BY_DATE
  @post = @post.sort_by { |p| p.date * -1 }
end
@sel.rows=@post.map{|s|
tmp=""
tmp+=s.name
if s.mention!=nil
  tmp += " . #{p_("Blog", "Mentioned by")}: #{s.mention.author} (#{s.mention.message})"
end
tmp = EltenAPI::SpeechSequence.new(tmp, EltenAPI::SpeechCommands::SoundCommand.new("listbox_itemfuture", " "+p_("EAPI_Speech", "Future")+" ", "", immediate: true)) if s.date>Time.now.to_i
[tmp,
s.author,
s.comments.to_s
]
}
if blogtemp.more
  @sel.rows.push([p_("Blog", "Load more"), nil, nil])
end
@sel.setcolumn(@sel.column)
@sel.clear_row_states
new_status=ListBox.item_status("listbox_itemnew", p_("Blog", "New"), p_("Blog", "New"))
@post.each_with_index do |post, i|
  @sel.set_row_state(i, new_status) if post.unread
end
end
def bopen
  if @sel.index<@post.size
  $scene = Scene_Blog_Read.new(@post[@sel.index],@id,@categoryselindex,@sel.index, nil,@page, @search)
else
  @page+=1
  load_posts(@page)
  @sel.say_option
  end
  end
  def postdelete
    confirm(p_("Blog", "Are you sure you want to delete this post?")) {
    begin
    EltenLink::Blog.delete_post(elten_link, blog: @owner, post_id: @post[@sel.index].id)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(p_("Blog", "Post deleted"))
      @post.delete_at(@sel.index)
      @sel.rows.delete_at(@sel.index)
      @sel.reload
    end
    speech_wait
    @sel.focus
    }
    end
  def context(menu)
    menu.option(p_("Blog", "Select")) {
      bopen
    }
    if @post.size>0 && @sel.index < @post.size
      if @isowner
    menu.option(p_("Blog", "Edit"), nil, "e") {
      $scene = Scene_Blog_PostEditor.new(@owner,@post[@sel.index].id,@id,@categoryselindex,@sel.index)
    }
    menu.option(p_("Blog", "Move to another blog")) {
      $scene = Scene_Blog_Post_Move.new(@owner,@id,@post[@sel.index].id,@categoryselindex,@sel.index)
    }
    menu.option(_("Delete"), nil, :del) {
      postdelete
    }
  end
  if @id == "NEWFOLLOWEDBLOGS"
    if LocalConfig["BlogPostsSortBy"] == SORT_POSTS_BY_BLOG
      opt = p_("Blog", "Sort posts by date")
    else
      opt = p_("Blog", "Sort posts by blog")
    end
    menu.option(opt) {
    if LocalConfig["BlogPostsSortBy"] == SORT_POSTS_BY_BLOG
      LocalConfig["BlogPostsSortBy"] = SORT_POSTS_BY_DATE
      info = p_("Blog", "Posts sorted by date.")
    else
      LocalConfig["BlogPostsSortBy"] = SORT_POSTS_BY_BLOG
      info = p_("Blog", "Posts sorted by blog.")
    end
    load_posts(@page)
    alert(info)
    }
    end # if @id=="NEWFOLLOWEDBLOGS"
  menu.option(p_("Blog", "Mention post"), nil, "w") {
        users = []
        begin
          users = EltenLink::Contacts.added_me(elten_link)
        rescue EltenLink::Error
          alert(_("Error"))
          next
        end
        if users.size == 0
          alert(p_("Blog", "Nobody added you to their contact list."))
          next
        end
        form = Form.new([ListBox.new(users, header: p_("Blog", "User to mention")), EditBox.new(p_("Blog", "Message"), type: 0, text: "", quiet: true), Button.new(p_("Blog", "Mention post")), Button.new(_("Cancel"))])
        loop do
          loop_update
          form.update
          if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index == 3)
            loop_update
            @sel.focus
            break
          end
          if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index == 2
            begin
              EltenLink::Blog.send_mention(elten_link, user: users[form.fields[0].index], message: form.fields[1].text, blog: @post[@sel.index].owner, post_id: @post[@sel.index].id)
            rescue EltenLink::Error
              alert(_("Error"))
            else
              alert(p_("Blog", "The mention has been sent."))
              @sel.focus
              break
            end
          end
        end
      }
  opt=""
      if @post[@sel.index].followed==false
    opt=p_("Blog", "Follow this post")
  else
    opt=p_("Blog", "Unfollow this post")
  end
  menu.option(opt, nil, "l") {
  if requires_premiumpackage("courier")
  begin
    if @post[@sel.index].followed==false
      EltenLink::Blog.follow_post(elten_link, blog: @post[@sel.index].owner, post_id: @post[@sel.index].id)
    else
      EltenLink::Blog.unfollow_post(elten_link, blog: @post[@sel.index].owner, post_id: @post[@sel.index].id)
    end
  rescue EltenLink::Error
    alert(_("Error"))
  else
        if @post[@sel.index].followed==false
      @post[@sel.index].followed=true
      alert(p_("Blog", "Post followed"))
    else
      @post[@sel.index].followed=false
      alert(p_("Blog", "Post unfollowed"))
      end
  end
  end
  }
  menu.option(p_("Blog", "Copy post URL")) {
  Clipboard.text=@post[@sel.index].url
  alert(p_("Blog", "Post URL copied to clipboard"))
  }
  end
if @isowner and @id != "NEW" and @id != "FOLLOWED" and @id != "NEWFOLLOWED"
  menu.option(p_("Blog", "New post"), nil, "n") {
$scene = Scene_Blog_PostEditor.new(@owner,0,@id,@categoryselindex)
}
end
        end
end
  
class Scene_Blog_Read
  def initialize(post,category,categoryselindex=0,postselindex=0,scene=nil,page=0,search=nil)
    @post=post
    @category = category
        @categoryselindex = categoryselindex
    @postselindex = postselindex
    @scene=scene
@page=page
@search=search
    @isowner=(blogowners(post.owner)||"").include?(Session.name)
          end
  def main
begin
blogtemp = EltenLink::Blog.read_post(elten_link, blog: @post.owner, post_id: @post.id)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = Scene_Blog_Main.new(@post.owner)
  return
end
if @post.mention!=nil
  EltenLink::Blog.read_mention(elten_link, mention_id: @post.mention.id)
  end
@knownposts=blogtemp.known_posts
@comments=blogtemp.comments_open ? 1 : 0
@iseltenblog=blogtemp.is_elten_blog
@comments=0 if @iseltenblog==false
text = ""
@posts = []
blogtemp.entries.each_with_index do |source, i|
  @posts[i] = Struct_Blog_Post.new
  @posts[i].id = source.id
  @posts[i].iseltenuser = source.iseltenuser
  @posts[i].author = source.author
  @posts[i].date = source.date
  @posts[i].moddate = source.moddate
  @posts[i].audio_url = source.audio_url
  @posts[i].excerpt = source.excerpt
  @posts[i].text = source.text
end
@postcur = 0
@fields = []
fdate=""
for i in 0..@posts.size-1
field_index=(i==0?i:(i+2))
@fields[field_index] = EditBox.new(@posts[i].author,type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::HTML,text: format(@posts[i]),quiet: true)
@fields[field_index].audio_url=@posts[i].audio_url if @posts[i].audio_url.to_s!="" && @posts[i].text.to_s.delete(" \r\n")==""
if i==0
  date = Time.now
  begin
date = Time.at(@posts[0].date)
    rescue Exception
  end
  fdate = format_date(date)
  end
end
@fields[1]=nil
@fields[2]=nil
if @posts[0]!=nil
if post_has_text?(@posts[0]) && @posts[0].audio_url!=""
  @fields[2] = EditBox.new(@posts[0].author,type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly|EditBox::Flags::HTML,text: "",quiet: true)
  @fields[2].audio_url = @posts[0].audio_url
elsif @posts[0].audio_url!=""
  @fields[0].audio_url = @posts[0].audio_url
  end
@medias=nil
if @posts.size>0 and MediaFinders.possible_media?(@posts[0].text)
  @fields[1] = Button.new(p_("Blog", "Show attached media"))
  @fields[1].on(:press) {
  @medias=MediaFinders.get_media(@posts[0].text)
if @medias.size>0
  @fields[1]=ListBox.new(@medias.map{|m|m.title},header: p_("Blog", "Media"))
else
  @fields[1]=nil
  @medias=nil
  end
  @form.focus
  loop_update
  }
end
else
  if @scene == nil
    $scene = Scene_Blog_Posts.new(@post.owner,@category,@categoryselindex,@postselindex, @search, @page)
  else
    $scene = @scene
    end
end
if Session.name!="guest"
@fields.push(EditBox.new(p_("Blog", "Your comment"),type: EditBox::Flags::MultiLine,text: "",quiet: true))
else
  @fields.push(nil)
  end
@fields.push(nil)
if @isowner
@fields.push(Button.new(p_("Blog", "Edit your post")))
else
  @fields.push(nil)
  end
@fields.push(Button.new(p_("Blog", "Return")))
@form = Form.new(@fields)
if @comments==0
  @form.fields[-3]=nil
  @form.fields[-4]=nil
end
@form.bind_context(p_("Blog", "Blogs")){|menu|context(menu)}
loop do
  loop_update
  @form.update
  update
  if @form.fields[@form.fields.size-4]!=nil and @form.fields[@form.fields.size-4].text!="" and @form.fields[@form.fields.size-3]==nil
    @form.fields[@form.fields.size-3]=Button.new(p_("Blog", "Send"))
  elsif @form.fields[@form.fields.size-4]!=nil and @form.fields[@form.fields.size-4].text=="" and @form.fields[@form.fields.size-3]!=nil
    @form.fields[@form.fields.size-3]=nil
    end
  break if $scene != self
  end
end
def update
  if key_pressed?(:key_enter) and @form.index==1 and @medias!=nil
    @medias[@form.fields[1].index].proceed
    speech_wait
    loop_update
    @form.fields[@form.index].focus
    end
  if ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index == @form.fields.size - 3) or (key_pressed?(:key_enter) and key_held?(0x11) and @form.index==@form.fields.size-4)
    @form.fields[@form.fields.size - 4]
    txt = @form.fields[@form.fields.size - 4].text
    if txt.size == 0 or txt == "\r\n"
      alert(_("Error"))
      return
    end
    begin
      EltenLink::Blog.create_comment(elten_link, blog: @post.owner, post_id: @post.id, content: txt)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(p_("Blog", "The comment has been added."))
      main
      return
    end
  end
if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index == @form.fields.size - 2
  @form.fields[0]
  txt = @form.fields[0].text
    $scene = Scene_Blog_PostEditor.new(@post.owner,@post.id,@category,@categoryselindex,@postselindex)
    end
  if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and @form.index == @form.fields.size - 1)
if @scene == nil
    $scene = Scene_Blog_Posts.new(@post.owner,@category,@categoryselindex,@postselindex, @search, @page)
  else
    $scene = @scene
    end
  end
end
def format(post)
   date=Time.now
  begin
    date=Time.at(post.date)
  rescue Exception
  end 
  text=post.text
  if text.delete(" \r\n")=="" && post.audio_url!=""
    text=p_("EAPI_Form", "Media")
    end
  text+"\n\n"+format_date(date)
  end
def post_has_text?(post)
  post!=nil && post.text.to_s.delete(" \r\n")!=""
end
def context(menu)
  ind=-1
  if @form.index<@posts.size+2 && (@form.index!=1 || @posts.size!=1)
      ind=@form.index-2
    ind=0 if ind<0
    pst=@posts[ind]
    if @iseltenblog && pst.iseltenuser
    menu.useroption(pst.author)
    end
  end
  if @post.mention!=nil
      menu.submenu(p_("Blog", "Received mention")) {|m|
      m.option(p_("Blog", "Show mention"), nil, "/") {
      input_text(p_("Blog", "Mention by %{user}")%{:user=>@post.mention.author}, flags: EditBox::Flags::ReadOnly, text: @post.mention.message, escapable: true)
      }
      m.option(p_("Blog", "Send reply to mentioner"), nil, "?") {
      to=@post.mention.author
      subj="RE: "+@post.mention.message.to_s+" ("+@post.name+")"
      insert_scene(Scene_Messages_New.new(to, subj, "", Scene_Main.new))
      }
      }
    end
    if @iseltenblog && Session.name!="guest"
      menu.option(p_("Blog", "Mention post"), nil, "w") {
        mention
      }
    end
    if @iseltenblog
        opt=""
      if @post.followed==false
    opt=p_("Blog", "Follow this post")
  else
    opt=p_("Blog", "Unfollow this post")
  end
  menu.option(opt, nil, "l") {
  if requires_premiumpackage("courier")
  begin
    if @post.followed==false
      EltenLink::Blog.follow_post(elten_link, blog: @post.owner, post_id: @post.id)
    else
      EltenLink::Blog.unfollow_post(elten_link, blog: @post.owner, post_id: @post.id)
    end
  rescue EltenLink::Error
    alert(_("Error"))
  else
        if @post.followed==false
      @post.followed=true
      alert(p_("Blog", "Post followed"))
    else
      @post.followed=false
      alert(p_("Blog", "Post unfollowed"))
      end
  end
  end
  }
      end
    menu.submenu(p_("Blog", "Navigation")) {|m|
    m.option(p_("Blog", "Go to post"), nil, ",") {
          @form.index=@postcur=0
      @form.focus
    }
    m.option(p_("Blog", "Go to last comment"), nil, ".") {
      @form.index=@postcur=@form.fields.size-5
      @form.focus
    }
    if @knownposts<@posts.size
        m.option(p_("Blog", "Go to first unread comment"), nil, "u") {
      @form.index=@postcur=@knownposts+2
      @form.focus
    }
    end
    }
    if @comments!=0
      menu.option(p_("Blog", "Write a comment"), nil, "n") {
      @form.index=@postcur=@form.fields.size-4
      @form.focus
      }
      end
    if ind>0 and @isowner
    menu.option(p_("Blog", "Delete this comment")) {
         confirm(p_("Blog", "Are you sure you want to delete this comment?")) {
         EltenLink::Blog.comment_delete(elten_link, blog: @post.owner, comment_id: @posts[ind].id)
         main
         }
    }
    end
  end
  def mention
    users = []
    begin
      users = EltenLink::Contacts.added_me(elten_link)
    rescue EltenLink::Error
      alert(_("Error"))
      return
    end
    if users.size == 0
      alert(p_("Blog", "Nobody added you to their contact list."))
      return
    end
    form = Form.new([ListBox.new(users, header: p_("Blog", "User to mention")), EditBox.new(p_("Blog", "Message"), type: 0, text: "", quiet: true), Button.new(p_("Blog", "Mention post")), Button.new(_("Cancel"))])
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) or ((key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index == 3)
        loop_update
        @form.focus
        break
      end
      if (key_pressed?(:key_enter) or key_pressed?(:key_space)) and form.index == 2
        begin
          EltenLink::Blog.send_mention(elten_link, user: users[form.fields[0].index], message: form.fields[1].text, blog: @post.owner, post_id: @post.id)
        rescue EltenLink::Error
          alert(_("Error"))
        else
          alert(p_("Blog", "The mention has been sent."))
          @form.focus
          break
        end
      end
    end
  end
end
  




class Scene_Blog_List
  def initialize(type=0, scene=nil, blog=nil)
    @type=type
    @scene=scene
    @blog=blog
    end
  def main
@sel = TableBox.new([nil,nil,p_("Blog", "Author"), p_("Blog", "Posts"), p_("Blog", "Comments"), p_("Blog", "Last post")],[],index: 0,header: p_("Blog", "Blogs list"))
@sel.bind_context{|menu|context(menu)}
refresh
@sel.index=$bloglistindex||0
@sel.index=0 if @sel.index>=@sel.options.size
@sel.focus
$bloglistindex=0
loop do
  loop_update
  @sel.update
  update
  break if $scene != self
  end
end
def update
  if key_pressed?(:key_escape) or (!key_held?(0x10)&&key_pressed?(:key_left))
    if @scene==nil
    t=0
    t=@type+1 if @type.is_a?(Integer)
    $scene = Scene_Blog.new(t)
  else
    $scene=@scene
    end
  end
      if (key_pressed?(:key_enter) or key_pressed?(:key_right)) && !key_held?(0x10) and @blogs.size>0
     $bloglistindex = @sel.index
        $scene = Scene_Blog_Main.new(@blogs[@sel.index].id,0,$scene)
      end
    end
def blogfollowers
  $bloglistindex = @sel.index
             $scene = Scene_Blog_Followers.new(@blogs[@sel.index].id,$scene)
end
def blogcoworkers
    owners=blogowners(@blogs[@sel.index].id)
  selt=owners
  sel=ListBox.new(selt,header: p_("Blog", "Coworkers"), index: 0, flags: 0, quiet: false)
  sel.bind_context{|menu|
  menu.useroption(owners[sel.index])
  if blogowners(@blogs[@sel.index].id)[0]==Session.name   and @blogs[@sel.index].id[0..0]=="["
  menu.option(p_("Blog", "Add coworker"), nil, "n") {
                cow=input_user(p_("Blog", "What user you want to add to this blog?"))
              if cow!=nil
                  EltenLink::Blog.add_coworker(elten_link, blog: @blogs[@sel.index].id, user: cow)
                  $blogownerstime=0
                  owners=blogowners(@blogs[@sel.index].id)
                  sel.options=selt=owners
                  sel.focus
                end
  }
  if sel.index>0
    menu.option(p_("Blog", "Delete coworker"), nil, :del) {
                    confirm(p_("Blog", "Are you sure you want to release this coworker?")) {
EltenLink::Blog.remove_coworker(elten_link, blog: @blogs[@sel.index].id, user: owners[sel.index])                
$blogownerstime=0
owners=blogowners(@blogs[@sel.index].id)
                  sel.options=selt=owners
                  sel.focus
                }
  }
    end
  end
  }
  loop do
    loop_update
    sel.update
    break if key_pressed?(:key_escape) or key_pressed?(:key_left)
  end
  @sel.focus
  loop_update
end
def blogdelete
    confirm(p_("Blog", "Are you sure you want to delete blog %{name}?")%{:name=>@blogs[@sel.index].name}) {
    confirm(p_("Blog", "All posts written on this blog will be lost. Are you sure you want to continue?")) {
  begin
  EltenLink::Blog.delete_blog(elten_link, blog: @blogs[@sel.index].id)
  rescue EltenLink::Error
    alert(_("Error"))
    return
  end
  alert(p_("Blog", "Blog deleted"))
  return main
  }
  } 
end
def refresh
@blogs=[]
  sel = []
  if @blog==:library
    begin
    bt=EltenLink::Blog.library_list(elten_link)
    rescue EltenLink::Error
      return
    end
    for source in bt
      b=Struct_Blog_Blog.new
      b.id=source.id
      b.library_user = source.library_user
b.lang=source.lang
b.name=source.name
b.description=source.user_description+"\n"+source.description
b.url=source.url
b.followed=false
b.library=true
b.owners=[]
  b.elten=false
  b.lastpost=0
    b.cnt_posts=0
  b.cnt_comments=0
  @blogs.push(b)
sel.push([b.name, b.description, b.id[2..-2], nil, nil, nil])
      end
  elsif @blog.is_a?(String)
    begin
    bt = EltenLink::Blog.details(elten_link, blog: @blog)
    rescue EltenLink::Error
      return
    end
    b=Struct_Blog_Blog.new
  b.id=@blog
  b.name=bt.name
  b.cnt_posts=0
  b.cnt_comments=0
  b.url=bt.url
  b.lastpost=0
  b.description=bt.description
  b.followed=false
  b.lang=""
  b.owners=[]
  b.elten=false
  b.library=bt.library
  @blogs.push(b)
    sel.push([b.name, b.description, @blog[2..-2], nil, nil, nil])
    else
          owner = nil
          orderby = nil
    if @type.is_a?(String)
      owner=@type
    else
      orderby=@type
    end
          begin
          blogtemp = EltenLink::Blog.list(elten_link, owner: owner, orderby: orderby)
          rescue EltenLink::Error
     alert(_("Error"))
     $scene = Scene_Blog.new
     return
   end
   knownlanguages = Session.languages.split(",").map{|lg|lg.upcase}
items=blogtemp.size
if @scene!=nil && items==0
  alert(p_("Blog", "No blogs found"))
  $scene=@scene
  return
  end
for source in blogtemp
  b=Struct_Blog_Blog.new
  b.id=source.id
  b.name=source.name
  b.cnt_posts=source.cnt_posts
  b.cnt_comments=source.cnt_comments
  b.url=source.url
  b.lastpost=source.lastpost
  b.description=source.description
  b.followed=source.followed
  b.lang=source.lang
  b.elten=true
    @blogs.push(b) if LocalConfig["BlogShowUnknownLanguages",1]==1 || knownlanguages.size==0 || knownlanguages.include?(b.lang[0..1].upcase) || (@type.is_a?(String) || @type==3)
end
for b in @blogs
  bo=blogowners(b.id)
  bo=[bo] if bo.is_a?(String)
  b.owners=bo
    o=b.owners.join(", ")
  tm=Time.at(b.lastpost)
  date=format_date(tm, false, true)
  sel.push([b.name, b.description, o, b.cnt_posts.to_s, b.cnt_comments.to_s, date])
end
end
@sel.rows=sel
@sel.reload
end
def addlib(blog)
    langs=[]
  langsmapping=[]
  lnindex=0
  for lk in Lists.langs.keys.sort{|a,b|polsorter(Lists.langs[a]['name'],Lists.langs[b]['name'])}
    langsmapping.push(lk)
    l=Lists.langs[lk]
    langs.push(l['name']+"( "+l['nativeName']+")")
    lnindex=langs.size-1 if lk[0..1].downcase==Configuration.language[0..1].downcase
    end
  form = Form.new([
  edt_description = EditBox.new(p_("Blog", "Blog description"), type: 0, text: "", quiet: true),
  lst_lang = ListBox.new(langs, header: p_("Blog", "Blog language"), index: lnindex),
  btn_add = Button.new(p_("Blog", "Add")),
  btn_cancel = Button.new(_("Cancel"))
  ], index: 0, silent: false, quiet: true)
  btn_cancel.on(:press) {form.resume}
  btn_add.on(:press) {
  langid = lst_lang.index
  if langid>=0
    l=langsmapping[langid]
    begin
      EltenLink::Blog.library_add(elten_link, blog: blog.id, lang: l, description: edt_description.text)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(p_("Blog", "Blog added to library"))
      blog.library=true
      end
    end
    form.resume
    }
    form.wait
  end
      def context(menu)
        if @blogs.size>0
b=@blogs[@sel.index].owners
blog=@blogs[@sel.index]
if blog.elten
b.each{|u| menu.useroption(u)}
end
menu.option(p_("Blog", "Open")) {
  $bloglistindex = @sel.index
        $scene = Scene_Blog_Main.new(@blogs[@sel.index].id,0,$scene)
}
menu.option(p_("Blog", "Show all posts"), nil, :shift_enter) {
$bloglistindex = @sel.index
$scene = Scene_Blog_Posts.new(@blogs[@sel.index].id,-1,0,0)
}
menu.option(p_("Blog", "Search"), nil, "f") {
phrase = input_text(p_("Blog", "Enter text to search"), flags: 0, text: "", escapable: true)
if phrase!=nil
$bloglistindex = @sel.index
$scene = Scene_Blog_Posts.new(@blogs[@sel.index].id,-1,0,0,phrase)
end
}
if blog.elten
if b.include?(Session.name)
  menu.option(p_("Blog", "Blog options"), nil, "e") {
  $scene=Scene_Blog_Options.new(@blogs[@sel.index].id, $scene)
  }
  menu.option(p_("Blog", "Followers")) {
  blogfollowers
  }
  menu.option(p_("Blog", "Coworkers")) {
  blogcoworkers
  }
    if b[0]!=Session.name && b!=Session.name
    menu.option(p_("Blog", "Leave")) {
    confirm(p_("Blog", "Are you sure you want to stop co-creating this blog?")) {
    begin
      EltenLink::Blog.leave_coworkers(elten_link, blog: @blogs[@sel.index].id)
    rescue EltenLink::Error
      alert(_("Error"))
    else
    alert(p_("Blog", "Blog left"))
  end
  $scene=Scene_Blog_List.new(@type, @scene)
    }
    }
    end
      menu.option(p_("Blog", "Recategorize")) {
  $bloglistindex = @sel.index
  $scene = Scene_Blog_Recategorize.new(@blogs[@sel.index].id,$scene)
  }
  if b[0]==Session.name
  menu.option(p_("Blog", "Delete this blog")) {
  blogdelete
  }
  end
  end
isf = @blogs[@sel.index].followed
s=""
if isf == true
  s=p_("Blog", "Remove from the followed blogs")
else
  s=p_("Blog", "Add to followed blogs")
end
menu.option(s, nil, "l") {
if isf == false
begin
EltenLink::Blog.follow(elten_link, blog: @blogs[@sel.index].id)
rescue EltenLink::Error
  alert(_("Error"))
else
    @blogs[@sel.index].followed=true
  confirm(p_("Blog", "This blog has been added to followed blogs. Do you want to mark all the posts published so far on it as read so that you don't see them in \"What's New\"?")) do
    begin
      EltenLink::Blog.mark_as_read(elten_link, blog: @blogs[@sel.index].id)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(p_("Blog", "The blog has been marked as read."))
      end
    end
end
else
begin
  EltenLink::Blog.unfollow(elten_link, blog: @blogs[@sel.index].id)
rescue EltenLink::Error
  alert(_("Error"))
else
  alert(p_("Blog", "Removed from the followed blogs."))
  @blogs[@sel.index].followed=false
end
end
}
end
if !blog.library
  menu.option(p_("Blog", "Add to Elten library")) {
  addlib(blog)
  @sel.focus
  }
elsif blog.library && (blog.library_user==Session.name)
  menu.option(p_("Blog", "Delete from Elten library")) {
  confirm(p_("Blog", "Are you sure you want to delete this blog from Elten library?")) {
  EltenLink::Blog.library_delete(elten_link, blog: blog.id)
  }
  refresh
  @sel.focus
  }
  end
menu.option(p_("Blog", "Add this blog to quick actions"), nil, "q") {
if QuickActions.create(Scene_Blog_Main, @blogs[@sel.index].name+" (#{p_("Blog", "Blog")})", [@blogs[@sel.index].id])
alert(p_("Blog", "Blog added to quick actions"), false)
else
alert(_("Error"))
end
}
menu.option(p_("Blog", "Copy blog URL")) {
Clipboard.text=@blogs[@sel.index].url
alert(p_("Blog", "Blog URL copied to clipboard"))
}
if blog.elten
menu.option(p_("Blog", "Mark the blog as read"), nil, "w") {
confirm(p_("Blog", "All posts on this blog will be marked as read. Do you want to continue?")) do
    begin
      EltenLink::Blog.mark_as_read(elten_link, blog: @blogs[@sel.index].id)
    rescue EltenLink::Error
      alert(_("Error"))
    else
      alert(p_("Blog", "The blog has been marked as read."))
    end
    end
}
end
end
menu.option(p_("Blog", "Create new blog"), nil, "n") {
can=true
begin
b=EltenLink::Blog.managed(elten_link)
rescue EltenLink::Error
      alert(_("Error"))
      $scene=Scene_Main.new
      can=false
    else
      can=false if b.size>0 && !requires_premiumpackage("scribe")
    end
    if can==true
$bloglistindex = @sel.index
$scene=Scene_Blog_Create.new(true, $scene)
else
  alert(p_("Blog", "You cannot create more blogs"))
  end
}
if !@type.is_a?(String)
if Session.languages.size>0
         s=p_("Blog", "Show blogs in unknown languages")
      s=p_("Blog", "Hide blogs in unknown languages") if LocalConfig['BlogShowUnknownLanguages',1]==1
      menu.option(s) {
      l=1
      l=0 if LocalConfig['BlogShowUnknownLanguages',1]==1
      LocalConfig['BlogShowUnknownLanguages']=l
refresh
@sel.focus
      }
    end
    end
menu.option(_("Refresh"), nil, "r") {
refresh
@sel.focus
}
end
end

class Scene_Blog_Profile
  def initialize(scene=nil)
    @scene=scene
    end
  def main
    begin
    profile = EltenLink::Blog.profile_get(elten_link)
    rescue EltenLink::Error
      alert(_("Error"))
      $scene=Scene_Main.new
      return
    end
    @form = Form.new([
    EditBox.new(p_("Blog", "Wordpress user login"), type: EditBox::Flags::ReadOnly, text: profile['user_login'], quiet: true),
    Button.new(p_("Blog", "Set new Wordpress password")),
    EditBox.new(p_("Blog", "First name"), type: 0, text: profile['first_name'], quiet: true),
    EditBox.new(p_("Blog", "Last name"), type: 0, text: profile['last_name'], quiet: true),
    EditBox.new(p_("Blog", "Nick"), type: 0, text: profile['nickname'], quiet: true),
    EditBox.new(p_("Blog", "Display name"), type: 0, text: profile['display_name'], quiet: true),
    EditBox.new(p_("Blog", "User description"), type: EditBox::Flags::MultiLine, text: profile['description'], quiet: true),
    Button.new(_("Save")),
    Button.new(_("Cancel"))
    ])
    loop do
      loop_update
      @form.update
      break if key_pressed?(:key_escape) or @form.fields[8].pressed?
      if @form.fields[7].pressed?
        j={}
        j['first_name']=@form.fields[2].text
        j['last_name']=@form.fields[3].text
        j['nickname']=@form.fields[4].text
        j['display_name']=@form.fields[5].text
        j['description']=@form.fields[6].text
        if j['display_name']!=""
        begin
        EltenLink::Blog.profile_set(elten_link, profile: j)
        rescue EltenLink::Error
          alert(_("Error"))
        else
          alert(_("Saved"))
                            speech_wait
        break
        end
        end
      end
      if @form.fields[1].pressed?
        ps=input_text(p_("Blog", "Your Elten Password"), flags: EditBox::Flags::Password,text: "",escapable: true)
        if ps!=nil
          nps=""
          rps=""
          m=nil
          suc=false
          until suc
            t=p_("Blog", "New Wordpress password")
            t=m+"\r\n"+t if m!=nil
          nps=input_text(p_("Blog", t), flags: EditBox::Flags::Password,text: "",escapable: true)
          rps=input_text(p_("Blog", "Repeat new Wordpress password"), flags: EditBox::Flags::Password,text: "",escapable: true) if nps!=nil
          break if nps==nil or rps==nil
          if rps==nps
            if rps.size<6
              m=p_("Blog", "Wordpress password must be at least 6 characters long.")
            else
              suc=true
              end
          else
            m=p_("Blog", "Entered passwords are different.")
            end
        end
        if nps!=nil and rps!=nil
begin
EltenLink::Blog.profile_change_password(elten_link, elten_password: ps, wordpress_password: rps)
rescue EltenLink::Error
  alert(_("Error"))
else
  alert(_("Saved"))
end
speech_wait
          end
        end
                @form.focus
        end
    end
    if @scene==nil
      $scene=Scene_Main.new
    else
      $scene=@scene
      end
    end
  end

class Scene_Blog_Recategorize
  def initialize(searchname,scene=nil)
    @searchname=searchname
    @scene=scene
    @scene||=Scene_Blog.new
    end
  def main
begin
    blogtemp = EltenLink::Blog.categories(elten_link, blog: @searchname)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = @scene
  return
end
categoryids = []
categorynames = []
blogtemp.categories.each_with_index do |category, i|
  categoryids[i] = category.id
  categorynames[i] = category.name
end
begin
blogtemp = EltenLink::Blog.posts(elten_link, blog: @searchname, category_id: 0)
rescue EltenLink::Error
  alert(_("Error"))
  $scene = @scene
  return
end
@postname = []
@postid = []
@postmaxid = 0
@postnew=[]
@postcategories=[]
blogtemp.posts.each_with_index do |post, i|
  @postid[i] = post.id
  @postmaxid = post.id if post.id > @postmaxid
  @postname[i] = post.name
    @postnew[i] = post.unread ? 1 : 0
  @postname[i]=p_("Blog", "New")+": "+@postname[i] if @postnew[i]>0
  @postcategories[i]=post.categories.to_a
end
@fields=[]
for i in 0..@postid.size-1
  f=ListBox.new(categorynames,header: @postname[i],index: 0,flags: ListBox::Flags::MultiSelection)
  for c in @postcategories[i]
    ind=categoryids.find_index(c)
    f.selected[ind]=true if ind!=nil
    end
  @fields.push(f)
    end
@fields+=[Button.new(_("Save")),Button.new(_("Cancel"))]
@form=Form.new(@fields)
loop do
  loop_update
  @form.update
  break if key_pressed?(:key_escape) or ((key_pressed?(:key_space) or key_pressed?(:key_enter)) and @form.index==@form.fields.size-1)
  if (key_pressed?(:key_space) or key_pressed?(:key_enter)) and (@form.index==@form.fields.size-2 or key_held?(0x11))
    ou=""
for i in 0..@postid.size-1
  ch=[]
  for j in 0..@form.fields[i].selected.size-1
    ch.push(categoryids[j]) if @form.fields[i].selected[j]==true
  end
  ou+=@postid[i].to_s+":"+ch.join(",")+"|" if ch.size>0
end
begin
  for i in 0..@postid.size-1
    ch=[]
    for j in 0..@form.fields[i].selected.size-1
      ch.push(categoryids[j]) if @form.fields[i].selected[j]==true
    end
    EltenLink::Blog.update_post(elten_link, blog: @searchname, post_id: @postid[i], categories: ch)
  end
rescue EltenLink::Error
  alert(_("Error"))
  else
  alert(p_("Blog", "Recategorized"))
end
speech_wait
break
    end
  end
$scene=@scene
end
end

class Scene_Blog_Post_Move
  def initialize(owner,category,post,categoryselindex=0,postselindex=0)
    @owner=owner
    @category=category
    @post=post
    @categoryselindex=categoryselindex
    @postselindex=postselindex
  end
  def main
    @blogids=[]
    @blognames=[]
    begin
    b=EltenLink::Blog.managed(elten_link)
    rescue EltenLink::Error
      alert(_("Error"))
      $scene=Scene_Main.new
      return
      end
            for blog in b
        @blogids.push(blog.id)
        @blognames.push(blog.name)
      end
      @form=Form.new([ListBox.new(@blognames,header: p_("Blog", "Post destination"),index: @blogids.index(@owner)||0), ListBox.new([p_("Blog", "Move this post and all comments"),p_("Blog", "Move only this post, delete all comments"), p_("Blog", "Copy this post and all comments")],header: p_("Blog", "Move type")), Button.new(p_("Blog", "Move")), Button.new(_("Cancel"))])
      loop do
        loop_update
        @form.update
        if @form.fields[2].pressed?
begin
EltenLink::Blog.move_post(elten_link, blog: @owner, post_id: @post, destination: @blogids[@form.fields[0].index], move_type: @form.fields[1].index)
rescue EltenLink::Error
  alert(_("Error"))
else
  alert(p_("Blog", "The post has been moved."))
end
speech_wait
break
          end
        break if key_pressed?(:key_escape) or @form.fields[3].pressed?
                  end
    $scene = Scene_Blog_Posts.new(@owner,@category,@categoryselindex,@postselindex)
  end
end

class Scene_Blog_Options
  def initialize(blog=nil, scene=nil)
    blog=Session.name if blog==nil
    @blog=blog
    @domain=""
    begin
      bt=EltenLink::Blog.domain_info(elten_link, blog: @blog)
      @domain=bt.domain
    rescue EltenLink::Error
    end
    @settings=[]
    @scene=scene
  end
  def getconfig
    @values={}
    @languages = {}
    @timezones={}
    begin
      a=EltenLink::Blog.options_get(elten_link, blog: @blog)
      @values=a.options
      @languages = a.languages
      @timezones = a.timezones
    rescue EltenLink::Error
    end
    end
  def currentconfig(key)
    getconfig if @values==nil
    return @values[key]
  end
  def setcurrentconfig(key,val)
@changed=true if @values[key]!=val.to_s
    @values[key]=val.to_s
end
  def setting_category(cat)
    @settings.push([cat, nil])
    @form.fields[0].options.push(cat)
  end
  def on_load(&func)
    return if @settings.size==0
    @settings.last[1]=func
    end
def make_setting(label, type, key, mapping=nil)
  return if @settings.size==0
  mapping=mapping.map{|x|x.to_s} if mapping!=nil
  @settings.last.push([label, type, key, mapping])
end
def save_category
  for i in 2...@settings[@category].size
    setting=@settings[@category][i]
    next if setting==nil || setting[1]==:custom
    index=i-1
    field=@form.fields[index]
    next if field==nil
    val=field.value
    val=val.to_i if setting[1]==:number
    val=val ? 1 : 0 if setting[1]==:bool
    val=setting[3][val] if setting[3]!=nil
    setcurrentconfig(setting[2], val)
    end
  end
def show_category(id)
  return if @form==nil or @settings[id]==nil
  save_category if @category!=nil
  @category=id
  @form.show_all
  @form.fields[1...-3]=[]
  f=[]
for s in @settings[id][2..-1]
  label, type, key, mapping = s
  field=nil
  case type
  when :text
    field=EditBox.new(label, text: currentconfig(key).to_s, quiet: true)
    when :longtext
      field=EditBox.new(label, type: EditBox::Flags::MultiLine, text: currentconfig(key).to_s, quiet: true)
    when :number
    field=EditBox.new(label, type: EditBox::Flags::Numbers, text: currentconfig(key).to_i.to_s, quiet: true)
    when :bool
      field=CheckBox.new(label, checked: currentconfig(key).to_i!=0)
      when :custom
        field=Button.new(label)
        proc=key
        field.on(:press, 0, true, &proc)
    else
      index=currentconfig(key)
      index=mapping.find_index(index)||0 if mapping!=nil
      field=ListBox.new(type, header: label, index: index.to_i)
    end
@form.fields.insert(@form.fields.size-3, field)
end
@settings[id][1].call if @settings[id][1]!=nil
end
def apply_settings
  save_category
  j={}
  for k in @values.keys
    v=@values[k]
    j[k]=v
  end
  begin
    EltenLink::Blog.options_set(elten_link, blog: @blog, options: j)
    @changed=false
  rescue EltenLink::Error
    alert(_("Error"))
  end
  end
def make_window
  @form=Form.new
  @form.fields[0] = ListBox.new([], header: p_("Blog", "Category"))
  @form.fields[1]=Button.new(_("Apply"))
  @form.fields[2]=Button.new(_("Save"))
  @form.fields[3]=Button.new(_("Cancel"))
end
def load_general
  setting_category(p_("Blog", "General"))
  make_setting(p_("Blog", "Blog name"), :text, "blogname")
  make_setting(p_("Blog", "Blog description"), :text, "blogdescription")
  langs=[]
  langsmapping=[]
  getconfig if @languages==nil
  for lang in @languages.keys
    l=@languages[lang]
    langsmapping.push(lang)
    langs.push(l['english_name']+"("+l['native_name']+")")
  end
  make_setting(p_("Blog", "Language"), langs, 'WPLANG', langsmapping)
  make_setting(p_("Blog", "Mark this blog as public. Blogs that are not marked public request search engines such as Google not to show them in search results (some search engines may not respect this setting)"), :bool, "blog_public")
end
def load_comments
  setting_category(p_("Blog", "Comments"))
  make_setting(p_("Blog", "Comments can be written"), [p_("Blog", "By all visitors"), p_("Blog", "By all visitors, but I must commit first comment of the specific person"), p_("Blog", "By all visitors, but I must commit all of them"), p_("Blog", "By Elten users only")], "^commentingtype")
  make_setting(p_("Blog", "Disable commenting of older posts"), :bool, "close_comments_old_posts")
  make_setting(p_("Blog", "Days after commenting of a post will be disabled"), :number, "close_comments_days_old")
  make_setting(p_("Blog", "Allow comments threading"), :bool, "thread_comments")
  make_setting(p_("Blog", "Max comments thread depth"), :number, "thread_comments_depth")
  make_setting(p_("Blog", "Order comments on the website"), [p_("Blog", "Ascending"), p_("Blog", "Descending")], "order_comments", ["asc", "desc"])
  make_setting(p_("Blog", "Split comments on the website into pages"), :bool, "page_comments")
  make_setting(p_("Blog", "Comments per page"), :number, "comments_per_page")
  make_setting(p_("Blog", "Firstly display"), [p_("Blog", "Newest comments"), p_("Blog", "Oldest comments")], "default_comments_page", ["newest", "oldest"])
  make_setting(p_("Blog", "Pending comments"), :custom, Proc.new{insert_scene(Scene_Blog_Comments.new(@blog))})
  on_load {
  if currentconfig("comment_registration").to_i==1
    @form.fields[1].index=3
  elsif currentconfig("comment_moderation").to_i==1
    @form.fields[1].index=2
  elsif currentconfig("comment_whitelist").to_i==1
    @form.fields[1].index=1
  end
  @form.fields[1].on(:move) {
  case @form.fields[1].index
  when 0
    setcurrentconfig("comment_whitelist", 0)
    setcurrentconfig("comment_moderation", 0)
    setcurrentconfig("comment_registration", 0)
  when 1
    setcurrentconfig("comment_whitelist", 1)
    setcurrentconfig("comment_moderation", 0)
    setcurrentconfig("comment_registration", 0)
  when 2
    setcurrentconfig("comment_whitelist", 0)
    setcurrentconfig("comment_moderation", 1)
    setcurrentconfig("comment_registration", 0)
  when 3
    setcurrentconfig("comment_whitelist", 0)
    setcurrentconfig("comment_moderation", 0)
    setcurrentconfig("comment_registration", 1)
  end
  }
  @form.fields[2].on(:change) {
  if @form.fields[2].checked
    @form.show(3)
  else
    @form.hide(3)
    end
  }
  @form.fields[2].trigger(:change)
  @form.fields[4].on(:change) {
  if @form.fields[4].checked
    @form.show(5)
  else
    @form.hide(5)
    end
  }
  @form.fields[4].trigger(:change)
  @form.fields[7].on(:change) {
  if @form.fields[7].checked
    @form.show(8)
    @form.show(9)
  else
    @form.hide(8)
    @form.hide(9)
    end
  }
  @form.fields[7].trigger(:change)
  }
end
def load_posts
  setting_category(p_("Blog", "Posts"))
  make_setting(p_("Blog", "Posts displayed per page on the website"), :number, "posts_per_page")
  make_setting(p_("Blog", "Use emoticons"), :bool, "use_smilies")
  links = [p_("Blog", "Simple (https://example.com/?p=123)"), p_("Blog", "Full date and post name (https://example.com/2020/01/01/example-post)"), p_("Blog", "Month and post name (https://example.com/2020/01/example-post)"), p_("Blog", "Just a post id (https://example.com/posts/123/)"), p_("Blog", "Just a post name (https://example.com/example-post/)")]
  linksmapping = ["", "/%year%/%monthnum%/%day%/%postname%/", "/%year%/%monthnum%/%postname%/", "/post/%post_id%", "/%postname%/"]
  if !linksmapping.include?(currentconfig("permalink_structure"))
    linksmapping.push(currentconfig("permalink_structure"))
    links.push(p_("Blog", "Custom"))
  end
  make_setting(p_("Blog", "Links format"), links, "permalink_structure", linksmapping)
    make_setting(p_("Blog", "Posts in RSS"), :number, "posts_per_rss")
  make_setting(p_("Blog", "Use excerpts in RSS"), :bool, "rss_use_excerpt")
end
def load_date
  setting_category(p_("blog", "Date and time"))
  datesmapping = ["j F Y", "Y-m-d", "m/d/Y", "d/m/Y", "F j, Y", "d.m.Y"]
  dates = [p_("Blog", "31 January 2020"), "2020-01-31", "01/31/2020", "31/01/2020", p_("Blog", "January 31, 2020"), "31.01.2020"]
  make_setting(p_("Blog", "Date format"), dates, "date_format", datesmapping)
  timesmapping = ["H:i", "g:i A", "H:i:s", "g:i:s A"]
  times=["14:54", "02:54 PM", "14:54:34", "02:54:34 PM",]
  make_setting(p_("Blog", "Time format"), times, "time_format", timesmapping)
    timezones=[]
  timezonesmapping=[]
  getconfig if @timezones==nil
for k in @timezones.keys
  timezones.push(@timezones[k])
  timezonesmapping.push(k)
end
timezones.push("UTC")
timezonesmapping.push("UTC")
if currentconfig("timezone_string")==""
  timezones.push(p_("Blog", "Custom"))
  timezonesmapping.push("")
end
make_setting(p_("Blog", "Timezone city"), timezones, "timezone_string", timezonesmapping)
days=[p_("Blog", "Sunday"), p_("Blog", "Monday"), p_("Blog", "Tuesday"), p_("Blog", "Wednesday"), p_("Blog", "Thursday"), p_("Blog", "Friday"), p_("Blog", "Saturday")]
make_setting(p_("Blog", "First day of the week"), days, "start_of_week")
end
def load_others
  setting_category(p_("Blog", "Others"))
  if holds_premiumpackage("scribe")
  blogs=get_blogs
  b=[p_("Blog", "Do not set")]
  bm=[""]
    for bl in blogs
    if bl.url!="https://"+@domain+"/"
    b.push(bl.name+" ("+bl.url+")")
    bm.push(bl.url)
    end
  end
  u=currentconfig("blog_redirect")
  if !bm.include?(u)
    b.push(u)
    bm.push(u)
    end
  make_setting(p_("Blog", "If you want to redirect all browsers visiting this blog to another site, select it here"), b, "blog_redirect", bm)
  end
  make_setting(p_("Blog", "My Wordpress account"), :custom, Proc.new{insert_scene(Scene_Blog_Profile.new)})
  make_setting(p_("Blog", "Open Wordpress admin panel in my browser"), :custom, Proc.new{
begin
bt=EltenLink::Blog.domain_info(elten_link, blog: @blog)
rescue EltenLink::Error
      alert(_("Error"))
      return $scene=Scene_Main.new
else
  d="https://"+bt.domain+"/wp-admin"
      process_url(d)
  end
  })
  make_setting(p_("Blog", "Manage tags"), :custom, Proc.new{insert_scene(Scene_Blog_Tags.new(@blog))})
  make_setting(p_("Blog", "Manage blog domain"), :custom, Proc.new{
  c=false
  if @changed
    confirm(p_("Blog", "Blog settings have been changed. If you continue to domain change, mades you changed will be lost. Do you want to continue anyway? If you want to store new settings, select No and then Apply them before proceeding with domain change.")) {c=true}
  else
    c=true
    end
  $scene = Scene_Blog_Domain.new(@blog, @scene) if c
  })
  end
  def get_blogs
          begin
          blogtemp = EltenLink::Blog.list(elten_link, owner: Session.name)
          rescue EltenLink::Error
            return []
          end
blogs=[]
for source in blogtemp
  b=Struct_Blog_Blog.new
  b.id=source.id
  b.name=source.name
  b.cnt_posts=source.cnt_posts
  b.cnt_comments=source.cnt_comments
  b.url=source.url
  b.lastpost=source.lastpost
  b.description=source.description
  b.followed=source.followed
  b.lang=source.lang
  blogs.push(b)
end
return blogs
    end
  def main
    @changed=false    
    make_window
        load_general
        load_comments
        load_posts
        load_date
        load_others
        @form.focus
        loop do
          loop_update
          @form.update
          show_category(@form.fields[0].index) if @category!=@form.fields[0].index
          if @form.fields[-3].pressed?
            apply_settings
            speak(_("Saved"))
          end
                    if @form.fields[-2].pressed? or (key_pressed?(:key_enter) and !@form.fields[@form.index].is_a?(Button) and !(@form.fields[@form.index].is_a?(EditBox) && (@form.fields[@form.index].flags&EditBox::Flags::MultiLine)>0))
            apply_settings
            alert(_("Saved"))
            if @scene==nil
            $scene=Scene_Main.new
          else
            $scene=@scene
            end
          end
          if key_pressed?(:key_escape) or @form.fields[-1].pressed?
            if @scene==nil
            $scene=Scene_Main.new
          else
            $scene=@scene
            end
          end
          break if $scene!=self
        end
      end
    end
    
    class Struct_Blog_Blog
      attr_accessor :id, :name, :description, :cnt_posts, :cnt_comments, :url, :lastpost, :followed, :lang, :owners, :elten, :library, :library_user
      def initialize
        @id=""
        @name=""
        @description=""
        @cnt_posts=0
        @cnt_comments=0
        @url=""
        @lastpost=0
        @followed=false
        @lang=""
        @owners=[]
        @elten=false
        @library=false
        @library_user = nil
      end
    end
    
class Struct_Blog_Post
  attr_accessor :owner
  attr_accessor :id
  attr_accessor :name
  attr_accessor :unread
  attr_accessor :audio
  attr_accessor :audio_url
  attr_accessor :excerpt
  attr_accessor :author
  attr_accessor :text
  attr_accessor :date
  attr_accessor :moddate
  attr_accessor :url
  attr_accessor :comments
  attr_accessor :followed
  attr_accessor :mention
  attr_accessor :iseltenuser
  def initialize(id=0)
    @id=id
    @audio=false
    @unread=false
    @name=""
    @owner=Session.name
    @author=""
    @text=""
    @date=0
    @moddate=0
    @iseltenuser=false
    @audio_url=""
    @excerpt=""
    @url=""
    @comments=0
    @followed=false
  end
end

class Scene_Blog_Tags
  def initialize(owner, scene=nil)
    @owner=owner
    @scene=scene
  end
  def main
    begin
    bt=EltenLink::Blog.tags_list(elten_link, blog: @owner)
    rescue EltenLink::Error
      alert(_("Error"))
      return $scene=Scene_Main.new
    end
    @tags=[]
    for source in bt
      @tags.push(Struct_Blog_Tag.new(source.id))
      @tags.last.name=source.name
    end
    @sel=ListBox.new(@tags.map{|t|t.name}, header: p_("Blog", "Tags"), index: 0, flags: 0, quiet: false)
    @sel.bind_context{|menu|
    menu.option(p_("Blog", "New tag"), nil, "n") {
    tagname = input_text(p_("Blog", "Tag name"), flags: 0, text: "", escapable: true)
    if tagname!=nil
      begin
      tagid=EltenLink::Blog.tag_create(elten_link, blog: @owner, name: tagname)
      rescue EltenLink::Error
        alert(_("Error"))
      else
        @tags.push(Struct_Blog_Tag.new(tagid.to_i))
        @tags.last.name=tagname
        @sel.options.push(tagname)
        @sel.focus
        end
      end
    }
    if @tags.size>0
    menu.option(p_("Blog", "Delete tag"), nil, :del) {
    begin
    EltenLink::Blog.tag_delete(elten_link, blog: @owner, tag_id: @tags[@sel.index].id)
    rescue EltenLink::Error
      alert(_("error"))
    else
      @tags.delete_at(@sel.index)
      @sel.options.delete_at(@sel.index)
      play_sound("editbox_delete")
      @sel.say_option
      end
    }
    end
    }
    loop do
      loop_update
      @sel.update
      break if key_pressed?(:key_escape)
      end
        if @scene!=nil
      $scene=@scene
    else
      $scene=Scene_Main.new
      end
    end
  end

  class Struct_Blog_Tag
    attr_accessor :id, :name
    def initialize(id=0)
      @id=id
      @name=""
    end
    end
  
class Scene_Blog_PostEditor
  def initialize(owner,post=0,category=0,categoryselindex=0,postselindex=0)
  @owner=owner
  @post=post
  @category = category
@categoryselindex = categoryselindex
@postselindex = postselindex
  end
  def main
    resetdate=false
    begin
    bt = EltenLink::Blog.categories(elten_link, blog: @owner)
    rescue EltenLink::Error
      alert(_("Error"))
      speech_wait
      return $scene=Scene_Main.new
    end
    @categories = []
    for source in bt.categories
      c=Struct_Blog_Category.new
      c.id=source.id
      c.name=source.name
      @categories.push(c)
    end
        begin
        bt = EltenLink::Blog.tags_list(elten_link, blog: @owner)
    rescue EltenLink::Error
      alert(_("Error"))
      speech_wait
      return $scene=Scene_Main.new
    end
    @tags= []
    for source in bt
      t=Struct_Blog_Tag.new
      t.id=source.id
      t.name=source.name
      @tags.push(t)
    end
    @fields = [
edt_title = EditBox.new(p_("Blog", "Post title"),text: "",quiet: true),
lst_editor = ListBox.new([p_("Blog", "Formattable editor"), p_("Blog", "Source Editor (HTML and Wordpress Shortcodes)")], header: p_("Blog", "Editor")),
edt_post = EditBox.new(p_("Blog", "Post"), type: EditBox::Flags::MultiLine|EditBox::Flags::HTML|EditBox::Flags::Formattable,text: "",quiet: true),
btn_audio = OpusRecordButton.new(p_("Blog", "Audio content"), EltenPath.join(Dirs.temp, "audioblogpost.opus"), max_bitrate: 128),
lst_categories = ListBox.new(@categories.map{|c|c.name},header: p_("Blog", "Post categories"),index: 0,flags: ListBox::Flags::MultiSelection),
lst_tags = ListBox.new([],header: p_("Blog", "Post tags")),
lst_visibility = ListBox.new([p_("Blog", "Show to everyone"),p_("Blog", "Show to Elten users only")],header: p_("Blog", "Visibility")),
edt_excerpt = EditBox.new(p_("Blog", "Excerpt"), type: EditBox::Flags::MultiLine,text: "",quiet: true),
chk_schedule = CheckBox.new(p_("Blog", "Schedule this post to be published in the future")),
btn_scheduledate = DateButton.new(p_("Blog", "Publication date"), (Time.now.year..(Time.now.year+3)), include_hour: true),
chk_comments = CheckBox.new(p_("Blog", "Allow users to comment this post"), checked: true),
btn_send = Button.new(p_("Blog", "Send")),
btn_cancel = Button.new(_("Cancel"))
]
@tagids=[]
lst_tags.bind_context{|menu|
      menu.option(p_("Blog", "Add existing tag to this post"), nil, "e") {
          dialog_open
        tag = selecttag
          dialog_close
          for t in @tags
            if tag != nil and t.name.downcase == tag.name.downcase
              tagid = t.id
              break
            end
          end
          if tag != nil and tagid > 0
            @tagids.push(tagid)
            lst_tags.options.push(tag.name)
            lst_tags.focus
          end
      }
menu.option(p_("Blog", "Add tag to this post"), nil, "n") {
tagname=input_text(p_("Blog", "Tag to add"), flags: 0, text: "", escapable: true)
if tagname!=nil
tagid=-1
for t in @tags
  if t.name.downcase==tagname.downcase
    tagid=t.id
    break
    end
end
if tagid==-1 and confirm(p_("Blog", "This tag does not exist, do you want to create it now?"))
  begin
    tagid=EltenLink::Blog.tag_create(elten_link, blog: @owner, name: tagname).to_i
  rescue EltenLink::Error
    tagid=-1
  end
end
if tagid>0
  @tagids.push(tagid)
  lst_tags.options.push(tagname)
  lst_tags.focus
  end
end
}
if @tagids.size>0
  menu.option(p_("Blog", "Remove tag from this post"), nil, :del) {
  @tagids.delete_at(lst_tags.index)
  lst_tags.options.delete_at(lst_tags.index)
  play_sound("editbox_delete")
  lst_tags.say_option
}
end
}
changed=false
edt_post.on(:delete) {changed=true}
edt_post.on(:insert) {changed=true}
for i in 0...@categories.size
  lst_categories.selected[i] = true if @categories[i].id == @category
end
if @post>0
  begin
  bt=EltenLink::Blog.post_details(elten_link, blog: @owner, post_id: @post)
  rescue EltenLink::Error
    alert(_("Error"))
      speech_wait
      return $scene=Scene_Main.new
    end
    title=bt.title
    privacy=bt.private ? 1 : 0
    comments=bt.comments ? 1 : 0
        cats=bt.categories
    tags=bt.tags
    time=bt.date
    if time.to_i>Time.now.to_i+60
      resetdate=true
      chk_schedule.checked=true
      tim=Time.at(time.to_i)
      btn_scheduledate.setdate(tim.year, tim.month, tim.day, tim.hour, tim.min, tim.sec)
      end
    post=bt.content.to_s
excerpt=bt.excerpt.to_s
       post.gsub!(/\[audio[^\]]*src\=(([^\" ]+)|(\"[^\"]+\"))[^\]]*\]\[\/audio\]/) {
ph=$1
ph[0..0]="" if ph[0..0]=="\""
ph.chop! if ph[-1..-1]=="\""
ph = EltenLink::Client.absolute_api_url(ph)
    btn_audio.set_source(ph)
    ""
    }
    edt_title.set_text(title)
    edt_post.set_text(post)
    edt_excerpt.set_text(excerpt)
    chk_comments.checked=comments
    lst_visibility.index=privacy
    for i in 0...@categories.size
      lst_categories.selected[i]=(cats.include?(@categories[i].id))
    end
    for tagid in tags
      for tag in @tags
        if tag.id==tagid
          @tagids.push(tagid)
          lst_tags.options.push(tag.name)
          end
        end
      end
    end
    @lasteditor=0
    lst_editor.on(:move) {
if @lasteditor==0
  text=edt_post.text_html
else
  text=edt_post.text
end
flags=EditBox::Flags::MultiLine
if lst_editor.index==0
  flags|=EditBox::Flags::HTML|EditBox::Flags::Formattable
  end
    edt_post.flags=flags
    edt_post.set_text(text)
    @lasteditor=lst_editor.index
    }
@form = Form.new(@fields)
@form.hide(btn_scheduledate) if !chk_schedule.checked
@form.hide(chk_schedule) if !chk_schedule.checked && !holds_premiumpackage("scribe")
chk_schedule.on(:change) {
if chk_schedule.checked
  @form.show(btn_scheduledate)
else
 @form.hide(btn_scheduledate) 
end
}
loop do
  loop_update
  #if btn_audio.empty?
    #@form.show(lst_editor)
    #@form.show(edt_post)
  #else
    #@form.hide(lst_editor)
    #@form.hide(edt_post)
    #end
  @form.update
  if key_pressed?(:key_escape) or btn_cancel.pressed?
    if !changed or confirm(p_("Blog", "Are you sure you want to cancel creating this post?"))
      break if btn_audio.delete_audio==true
  end
  end
  if btn_send.pressed? || (key_held?(0x11) && key_pressed?(:key_enter))
    date=0
    suc=true
    if chk_schedule.checked
      if btn_scheduledate.year==0
        alert(p_("Blog", "Publication date not set"))
        else
            tim=Time.local(btn_scheduledate.year, btn_scheduledate.month, btn_scheduledate.day, btn_scheduledate.hour, btn_scheduledate.min, btn_scheduledate.sec)
            if tim.to_i<=Time.now.to_i
              alert(p_("Blog", "Selected publication date that is in the past"))
              suc=false
            else
             date=tim.to_i 
              end
            end
end
    case lst_editor.index
    when 0
      text = edt_post.text_html
      when 1
        text = edt_post.text
        end
cats=[]
for i in 0...@categories.size
  cats.push(@categories[i].id) if lst_categories.selected[i]==true
end
if suc
  date_value = nil
  date_value=date if date!=0
  date_value=Time.now.to_i if date_value==nil && resetdate
  excerpt = nil
  excerpt = edt_excerpt.text if edt_excerpt.text!="" || @post>0
  audio=btn_audio.get_recording_file(true)
  if audio==nil
    content = changed ? text : nil
    begin
      if @post>0
        EltenLink::Blog.update_post(elten_link, blog: @owner, post_id: @post, title: edt_title.text, content: content, excerpt: excerpt, categories: cats, tags: @tagids, private: lst_visibility.index, comments: chk_comments.checked, date: date_value)
      else
        EltenLink::Blog.create_post(elten_link, blog: @owner, title: edt_title.text, content: content, excerpt: excerpt, categories: cats, tags: @tagids, private: lst_visibility.index, comments: chk_comments.checked, date: date_value)
      end
    rescue EltenLink::Error
      alert(_("Error"))
      next
    end
  else
   alert(p_("Blog", "Please wait..."))
        fl=File.binread(audio).to_s.b
        if fl.byteslice(0, 4)!='OggS'
          alert(_("Error"))
          return $scene=Scene_Main.new
        end
    begin
      audio_url = EltenLink::Blog.upload_audio(elten_link, blog: @owner, data: fl)
      if audio_url.to_s == ""
        alert(_("Error"))
        next
      end
      audio_content = %Q([audio src="#{audio_url}"][/audio])
      content = [text.to_s, audio_content].reject { |part| part.to_s.strip == "" }.join("\n\n")
      if @post>0
        EltenLink::Blog.update_post(elten_link, blog: @owner, post_id: @post, title: edt_title.text, content: content, excerpt: excerpt, categories: cats, tags: @tagids, private: lst_visibility.index, comments: chk_comments.checked, date: date_value)
      else
        EltenLink::Blog.create_post(elten_link, blog: @owner, title: edt_title.text, content: content, excerpt: excerpt, categories: cats, tags: @tagids, private: lst_visibility.index, comments: chk_comments.checked, date: date_value)
      end
    rescue EltenLink::Error
      alert(_("Error"))
      next
    end
      end
        alert(p_("Blog", "The post has been added."))
        btn_audio.delete_audio(true)
        break
      end
      end
  end
    $scene = Scene_Blog_Posts.new(@owner,@category,@categoryselindex,@postselindex)
  end
    def selecttag
      if @tags.size < 1
      alert(p_("Blog", "There are currently no tags created, please add a new one."))
      return nil
    end
    sel = ListBox.new(@tags.map { |t| t.name}, header: p_("Blog", "Select tag"), index: 0, flags: 0, quiet: false)
      loop do
      loop_update
      sel.update if @tags.size > 0
        if key_pressed?(:key_escape)
        loop_update
        return(nil)
      end
      if key_pressed?(:key_enter) and @tags.size > 0
        loop_update
        play_sound("listbox_select")
        return(@tags[sel.index])
      end
    end
  end
  end
  
  class Struct_Blog_Category
    attr_accessor :id
   attr_accessor :posts
   attr_accessor :url
   attr_accessor :name
   attr_accessor :parent
   def initialize
     @id=0
     @name=""
     @parent=0
     @url=""
     @posts=0
   end
 end
 
 class Scene_Blog_Comments
  def initialize(blog=nil, status="hold", scene=nil)
    @blog=blog
    @blog=Session.name if blog==nil
    @status=status
    @scene=scene
  end
  def main
    @comments=[]
    @sel = TableBox.new([nil, p_("Blog", "Post"), p_("Blog", "Comment")], [], index: 0, header: p_("Blog", "Comments"))
    @sel.bind_context{|menu|context(menu)}
    refresh
    @sel.focus
    loop do
      loop_update
      @sel.update
      break if key_pressed?(:key_escape)
    end
    if @scene==nil
    $scene=Scene_Main.new
  else
    $scene=@scene
    end
  end
  def context(menu)
    if @comments.size>0
            menu.option(p_("Blog", "Approve"), nil, "r") {
      assign(@comments[@sel.index], "approve")
      }
      if @status!="spam"
      menu.option(p_("Blog", "Assign as spam"), nil, "m") {
      assign(@comments[@sel.index], "spam")
      }
      end
      menu.option(p_("Blog", "Delete"), nil, :del) {
      confirm(p_("Blog", "Are you sure you want to delete this comment?")) {
      deletecomment(@comments[@sel.index])
      }
      }
    end
    menu.submenu(p_("Blog", "Show")) {|m|
    if @status!="hold"
    m.option(p_("Blog", "Pending comments")) {
    @status="hold"
    refresh
    @sel.focus
    }
  end
  if @status!="spam"
    m.option(p_("Blog", "Comments assigned as spam")) {
    @status="spam"
    refresh
    @sel.focus
    }
    end
    }
    end
    def assign(comment, status)
      begin
      EltenLink::Blog.comment_assign(elten_link, blog: @blog, comment_id: comment.id, status: status)
      rescue EltenLink::Error
        alert(_("Error"))
      end
    refresh
    @sel.say_option
  end
      def deletecomment(comment)
      begin
      EltenLink::Blog.comment_delete(elten_link, blog: @blog, comment_id: comment.id)
      rescue EltenLink::Error
        alert(_("Error"))
      end
    refresh
    play_sound("editbox_delete")
    @sel.say_option
    end
    def refresh
      begin
            ct=EltenLink::Blog.comments_list(elten_link, blog: @blog, status: @status)
      rescue EltenLink::Error
        alert(_("Error"))
        return
      end
        @comments.clear
        for source in ct
            @comments.push(Struct_Blog_Comment.new)
            @comments.last.id=source.id
              @comments.last.author=source.author
                @comments.last.postname=source.postname
                  @comments.last.content=source.content
            end
            @sel.rows=nil
            r=[]
            for c in @comments
              r.push([c.author, c.postname, c.content])
            end
            @sel.rows=r
            @sel.reload
      end
    end
    
    class Struct_Blog_Comment
      attr_accessor :id, :postname, :author, :content
      def initialize
        @id=0
        @postname=""
        @author=""
        @content=""
        end
      end
      
      class Scene_Blog_Followers
        def initialize(owner=Session.name,scene=nil)
    @owner=owner
    @scene=scene
    end
def main
begin
if @owner!=nil
  b=EltenLink::Blog.followers(elten_link, blog: @owner)
else
  b=EltenLink::Blog.new_followers(elten_link)
  end
rescue EltenLink::Error
  alert(_("Error"))
  $scene=@scene
  $scene = Scene_Main.new if $scene==nil
  return
end
  users=[]
  blogs=[]
  blognames=[]
  for source in b
    blogs.push(source.blog)
    blognames.push(source.blog_name)
    users.push(source.user)
    end
  if users.size==0
    alert(p_("Blog", "This blog is not followed by any user"))
  else
    rows=[]
    for i in 0...b.size
      rows.push([users[i], blognames[i]])
    end
    head=p_("Blog", "Followers")
    head="" if @owner==nil
        @sel=TableBox.new([nil, p_("Blog", "Blog")], rows, index: 0, header: head, quiet: false)
        @sel.bind_context{|menu|
        if blogs.size>0
          menu.useroption(users[@sel.index])
          menu.option(p_("Blog", "Open blog")) {insert_scene(Scene_Blog_Main.new(blogs[@sel.index], 0, Scene_Main.new))}
          end
        }
    loop do
      loop_update
      @sel.update
      usermenu(users[@sel.index]) if key_pressed?(:key_enter) and users.size>0
            break if key_pressed?(:key_escape) or key_pressed?(:key_left) or $scene!=self
      end
    end
$scene=@scene    
    $scene = Scene_Main.new if $scene==nil
end
end

class Struct_Blog_Mention
  attr_accessor :id, :blog, :postid, :author, :message, :time
end

class Scene_Blog_Domain
  def initialize(blog=nil, scene=nil)
    blog=Session.name if blog==nil
    @blog=blog
    @scene=scene
  end
  
  def main
    begin
    bt=EltenLink::Blog.domain_info(elten_link, blog: @blog)
    rescue EltenLink::Error
      alert(_("Error"))
      return $scene=Scene_Main.new
    end
    @trname=bt.suggested
    @form=Form.new ([
    @txt_olddomain = EditBox.new(p_("Blog", "Current blog domain"), type: EditBox::Flags::ReadOnly, text: bt.domain, quiet: true),
    @btn_change = Button.new(p_("Blog", "Change")),
    nil, nil, nil,nil,nil,
    @btn_cancel = Button.new(_("Cancel"))
    ])
    @btn_change.on(:press) {changer}
    @done=false
    loop do
      loop_update
      @form.update
      break if key_pressed?(:key_escape) or @btn_cancel.pressed? or @done
      end
    if @scene==nil
  $scene=Scene_Main.new
else
  $scene=@scene
end
  end
  def changer
    @lst_domaintype = @form.fields[2] = ListBox.new([
    p_("Blog", "Personal Elten blog domain (%{username}.elten.blog)")%{:username=>Session.name},
    p_("Blog", "Shared Elten blog domain (selectedname.s.elten.blog)"),
    p_("Blog", "External domain")
    ], header: p_("Blog", "Domain type"))
    @lst_domaintype.disable_item(2) if !holds_premiumpackage("scribe")
    @txt_domaininstructions = @form.fields[3] = EditBox.new(p_("Blog", "Buying your own domain"), type: EditBox::Flags::ReadOnly, text: p_("Blog", "To continue, you should point your domain to Elten Blogging server.\nYou can buy your own domain from domain providers, such as ovh.com, domain.com, godaddy.com or bluehost.com."), quiet: true)
        @edt_domain = @form.fields[4] = EditBox.new("", type: 0, text: "", quiet: true)
    @txt_fulldomain = @form.fields[5] = EditBox.new(p_("Blog", "Final new blog address"), type: EditBox::Flags::ReadOnly, text: "", quiet: true)
    @btn_next = @form.fields[6] = Button.new(p_("Blog", "Proceed with domain change"))
    @edt_domain.on(:change) {
    case @lst_domaintype.index
    when 0
      @txt_fulldomain.set_text((@trname+".elten.blog").downcase)
      when 1
        @txt_fulldomain.set_text((@edt_domain.text+".s.elten.blog").downcase)
        when 2
          @txt_fulldomain.set_text((@edt_domain.text).downcase)
    end
}
    @lst_domaintype.on(:move) {
    case @lst_domaintype.index
    when 0
      @form.hide(@edt_domain)
      @form.hide(@txt_domaininstructions)
      when 1
        @form.show(@edt_domain)
        @form.hide(@txt_domaininstructions)
        @edt_domain.header= p_("Blog", "Domain prefix (prefix.s.elten.blog)")
        when 2
          @form.show(@edt_domain)
          @form.show(@txt_domaininstructions)
          @edt_domain.header= p_("Blog", "Domain (like example.com)")
        end
        @edt_domain.trigger(:change)
    }
    @lst_domaintype.trigger(:move)
    @btn_next.on(:press) {@done=changeproceed}
    @form.hide(@btn_change)
    @form.index=@lst_domaintype
    @form.focus
  end
  def changevalidate
    if @txt_fulldomain.text==@txt_olddomain.text
      alert(p_("Blog", "The new domain is the same as a previous one"))
      return false
    end
    if @lst_domaintype.index==0 && EltenLink::Blog.exists?(elten_link, blog: Session.name)
      alert(p_("Blog", "You already have one blog associated with your Elten profile. Please change its type and then proceed."))
      return false
    end
    if @lst_domaintype.index==1 && @edt_domain.text.include?(".")
      alert(p_("Blog", "Only first level subdomains are allowed"))
      return false
    end
    if @lst_domaintype.index==1 && @edt_domain.text.size<3
      alert(p_("Blog", "Blog subdomain must be at least 3 characters long"))
      return false
      end
    dom=@txt_fulldomain.text
    if (/[^a-z0-9\.\-]/=~dom)!=nil
      alert(p_("Blog", "The entered domain contains invalid characters"))
      return false
      end
    if dom[0..0]=="." || dom[0..0]=="-" || dom.include?("-.") || dom.include?(".-") || dom[-1..-1]=="." || dom[-1..-1]=="-" || !dom.include?(".") || dom.split(".").last.size<2 || dom=="elten.blog"
      alert(p_("Blog", "The entered domain is not valid"))
      return false
      end
    end
  def changeproceed
    return false if changevalidate==false
    return false if !confirm(p_("Blog", "Warning! If you change your blog URL, some links may stop working. If you directly linked posts or other resources on your blog, they would no longer be available at previous URLs. In such case you will be required to fix them manually. Are you sure you want to continue?"))
    dom=@txt_fulldomain.text
    d=".elten.blog"
    if dom[-1*d.size..-1]!=d
if externalchangecheck(dom)==false
    @form.focus
    return false
  end
end
begin
EltenLink::Blog.domain_change(elten_link, blog: @blog, domain: dom)
rescue EltenLink::Error
  alert(_("Error"))
  return false
else
  alert(p_("Blog", "Blog domain changed"))
  return true
  end
    end
    def externalchangecheck(domain)
      begin
      dt=EltenLink::Blog.domain_proper_targets(elten_link)
      rescue EltenLink::Error
        return false
      end
        host=dt.host
      ip=dt.ip
      text=p_("Blog", "You should now configure your purchased domain to redirect to Elten blogging server. Below are the necessary details. If you have any problems, please feel free to ask questions in the forum.
      
      Wherever possible, we recommend that you use the CNAME record, as it does not need to be edited if the IP address of the server hosting your blog changes. Your blog's IP address may change, for example, due to a Elten Blogging Server migration. By configuring your domain's CNAME record, you don't need to do anything else.
      To do this, please point your cname record to destination \"%{host}.\"
      
      Unfortunately, many domain registrars do not support the CNAME record for top-level domains, so you may want to use the A record instead.
      In such a case, please point the A record to IP address:
%{ip}
.

Please note that redirecting your domain is not aliasing and setting aliases or HTTP 301/ 3xx redirections will not work.

You can get detailed description from your domain provider, for example at:
https://support.us.ovhcloud.com/hc/en-us/articles/115001994890-Getting-Familiar-with-DNS

Once completed, please continue.")%{:ip=>ip,:host=>host}
      form=Form.new([
      txt=EditBox.new(p_("Blog", "Setting the domain"), type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: text, quiet: true),
      btn_next = Button.new(p_("Blog", "Ready, take me next")),
      btn_cancel = Button.new(_("Cancel"))
      ])
      r=true
      btn_cancel.on(:press) {
      r=false
      form.resume
      }
      form.cancel_button = btn_cancel
      btn_next.on(:press) {
      begin
      ch=EltenLink::Blog.domain_check(elten_link, domain: domain)
      rescue EltenLink::Error
        alert(_("Error"))
        next
      end
      if ch.status==0
        alert(p_("Blog", "Your domain is not pointing to Elten Blogs, please try again or wait a while to refresh DNS. It may take up to 24 hours to perform full DNS update."))
      elsif ch.status==1
        alert(p_("Blog", "Your domain is pointing to Elten blogs, but www prefix is not. Please fix it."))
      else
        return true
        end
      }
      form.wait
      return r
      end
  end
