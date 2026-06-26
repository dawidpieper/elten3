# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
class Menu
  attr_accessor :header
  @@menubg=nil
  def initialize(header="", type=:default, &block)
    @lasttime=0
    @type=type
    @options=[]
    @header=header
    @closed=true
    @on_close=[]
    @on_open=[]
    @on_action=[]
    @instance=0
    if block_given?
          @caller=$scene
        if block.arity<=0
          @instance=1
          instance_eval(&block)
        else
          block.call(self)
        end
        end
    end
  def option(opt, v=nil, key="", &block)
    @options.push([opt, block, v, key])
  end
  def scene(opt, scene, *args)
    @options.push([opt, :scene, [scene]+args])
  end
  def quickaction(opt, action)
    @options.push([opt, :quickaction, action])
    end
  def customoption(opt, &block)
    @options.push([opt, :custom, block])
  end
  def useroption(user)
    @options.push([user, :user, user])
    end

  def submenu(opt, &block)
    @options.push(opt)
    if block_given?
        if block.arity<=0
          @instance=1
          instance_eval(&block)
        else
          block.call(self)
        end
        end
    @options.push(nil)
  end
  def size
    @options.size
    end
    def on_close(&block)
    @on_close.push(block)
  end
  def on_open(&block)
    @on_open.push(block)
  end
  def on_action(&block)
    @on_action.push(block)
    end
  def open
    @closed=false
    if @on_open.size==0
    if @type==(:menubar) || @type==(:menu)
    play_sound("menu_open")
    if Configuration.bgsounds==1 && Configuration.soundthemeactivation==1
      self.class.menubg_play
      end
    end
        show(0)
              else
        @on_open.each {|c| c.call}
        end
  end
  def show(index=0)
    h=""
        h=@header if index==0 and @type!=:menubar or @first==nil
        @first=true
    opts=[]
    acs=[]
    s=0
    inds=[]
    depth=0
    for i in 0...index
      depth+=1 if @options[i].is_a?(String)
      depth-=1 if @options[i]==nil
      end
    for i in index...@options.size
      c=@options[i]
      if s==0
        break if c==nil
        inds.push(nil)
        o=c
        o=c[0] if c.is_a?(Array)
        if c.is_a?(Array) and c[3]!="" and c[3]!=nil
          k=(c[3].is_a?(Symbol))?(c[3].to_s):(get_character_name(c[3]))
          k="SHIFT+"+k.to_s if k.to_s.downcase!=k
          o+=(c[3].is_a?(Symbol))?(" "+k.gsub("_","+")):(" (CTRL+"+k.to_s+")")
          end
        opts.push(o)
                acs.push(c)
              end
        if c.is_a?(String)
          inds[-1]||=i
          s+=1
        elsif c==nil
          s-=1
        end
      end
      return if opts.size==0
      flags = ListBox::Flags::Silent|ListBox::Flags::HotKeys
      flags|=ListBox::Flags::LeftRight if (@type==:menubar)&&index==0
    sel=ListBox.new(opts, header: h, index: 0, flags: flags, quiet: false)
    sel.on(:border) {play_sound("border", volume: 100, pitch: 100, pan: sel.lpos)}
    sel.on(:move) {
    opt=acs[sel.index]
    if opt[1]==:user or opt[1]==:custom or opt.is_a?(String)
      play_sound("listbox_itemsubmenu", volume: 100, pitch: 100, pan: sel.lpos)
    else
      play_sound("listbox_focus", volume: 100, pitch: 100, pan: sel.lpos)
      end
    }
    sel.on(:select) {
        opt=acs[sel.index]
    if opt[1]!=:user and opt[1]!=:custom and !opt.is_a?(String)
      play_sound("listbox_select", volume: 100, pitch: 100, pan: sel.lpos)
      end
    }
    @lasttime=Time.now.to_f
    loop {
    loop_update
    @lasttime=Time.now.to_f
    return if depth==1 and @type==:menubar and sel.index==0 and key_pressed?(:key_up)
    sel.update if !@closing
        return -1 if key_pressed?(:key_left) and @type==:menubar and depth==1
        return 1 if key_pressed?(:key_right) and @type==:menubar and depth>0 and (acs[sel.index].is_a?(Array) and (acs[sel.index][1]!=:user and acs[sel.index][1]!=:custom))
    if ((key_pressed?(:key_escape) and depth==0) or (key_pressed?(:key_alt) and (@type==:menubar or @type==:menu)))
      if @on_close.size==0
        close
      else
        @on_close.each {|c| c.call}
        end
      end
    break if @closing
    return if ((key_pressed?(:key_escape) or (sel.collapsed? and (depth>1 or (depth==1 and @type!=:menubar)))) and index>0) and depth>0
        if sel.expanded? or sel.selected?
      opt=acs[sel.index]
      if opt[1]==:user
        play_sound("listbox_treeexpand", volume: 100, pitch: 100, pan: sel.lpos)
                u=usermenu(opt[2], true, true)
        if u=="ALT"
          close
        else
          play_sound("listbox_treecollapse", volume: 100, pitch: 100, pan: sel.lpos)
          sel.focus
        end
        elsif opt[1]==:custom
        play_sound("listbox_treeexpand", volume: 100, pitch: 100, pan: sel.lpos)
                u=opt[2].call
        if u==true
          close
        else
          play_sound("listbox_treecollapse", volume: 100, pitch: 100, pan: sel.lpos)
          sel.trigger(:move, sel.index)
          sel.focus
          end
        elsif opt.is_a?(String)
          play_sound("listbox_treeexpand", volume: 100, pitch: 100, pan: sel.lpos)
      a=show(inds[sel.index]+1)
      if a==nil
      sel.header="" if @type==:menubar
      play_sound("listbox_treecollapse", volume: 100, pitch: 100, pan: sel.lpos) if !@closing
      sel.focus if !@closing
      loop_update
    else
      return a if depth>0
      sel.index=(sel.index+a)%acs.size
      sel.request_select if acs[sel.index].is_a?(String) && sel.respond_to?(:request_select)
      end
    elsif sel.selected?
      close if @type!=:returning and opt[1]!=:user
      loop_update(false)
      if opt[1]==:scene
        @on_action.each {|c| c.call}
        insert_scene(opt[2][0].new(*opt[2][1..-1]), true)
      elsif opt[1]==:quickaction
        @on_action.each {|c| c.call}
        opt[2].call
      else
        @on_action.each {|c| c.call}
      if opt[2]!=nil or @instance==0
      opt[1].call(opt[2])
    else
      @caller.instance_eval(&opt[1])
      end
    end
    end
      end
    }
  end
  def close
    if @type==:menubar || @type==:menu
    play_sound("menu_close")
self.class.menubg_close
    end
    @closing=true
    @closed=true
  end
  def opened?
    close if @lasttime-Time.now.to_f>5
          !@closed
  end
  def scenes
    sc=[]
    @options.each{|o|
    sc.push([o[0].delete("&"),o[2]]) if o.is_a?(Array) && o[1]==:scene
    }
    return sc
    end
  def items
    it=[]
    @options.each{|o|
    if o.is_a?(Array) && o[1].is_a?(Proc)
    it.push(o)
    end
    }
    return it
  end
  def self.menubg_close
    @@menubg_generation ||= 0
    @@menubg_generation += 1
    if @@menubg!=nil
      @@menubg.close
      @@menubg=nil
      end
    end
    def self.menubg_play
      self.menubg_close if @@menubg!=nil
      snd=getsound("menu_background")
      if snd!=nil
      @@menubg_generation ||= 0
      generation = (@@menubg_generation += 1)
      Thread.new do
        Thread.current.report_on_exception = false
        begin
          sound = Sound.new(loop: true, stream: snd)
          sound.volume=Configuration.volume/100.0
          if @@menubg_generation == generation
            @@menubg = sound
            @@menubg.play
          else
            sound.close
          end
        rescue Exception => e
          Log.warning("Menu background sound failed: #{e.class}: #{e.message}")
        end
      end
      end
      end
  end


  end
end
