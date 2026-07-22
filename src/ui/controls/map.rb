# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Controls
    private
  class Timer
    attr_accessor :offset, :repeat
    def initialize(offset, repeat: false, autostart: true, &block)
      @scene=$scene
      @offset, @repeat = offset, repeat
      @block=block
      start if autostart
    end
    def reset
      @used=false
      end
    def start
      return if @used==true and @repeat==true
      @stopped=false
      @h=Thread.new {
      loop {
      o=@offset
      o=rand*(o.end-o.begin)+o.begin if @offset.is_a?(Range)
      sleep(o)
      begin
      @block.call
    rescue Exception
      p $!
      p $@
      end
      if @repeat==false
      @used=true
      break
      end
      }
      }
    end
        def stop
      @stopped=true
      @h.kill if @h!=nil
      @h=nil
      end
    end

  class MapObject
    attr_accessor :x, :y
    attr_accessor :range, :sound, :sound_range, :move_type, :move_delay
    def initialize(x,y, scene=nil, &block)
      @scene=$scene if scene==nil
      @x, @y = x, y
      @move_type = :fixed
      @move_delay = 0.5
      @laststep=0
      @range=0
      @sound_range=5
          if block_given?
        if block.arity<=0
          instance_eval(&block)
        else
          block.call(self)
        end
        end
    end
        def on(event, time=0, &block)
      @events||=[]
      @events.push([event,time,0,block])
    end
def trigger(event, *params)
      return if @events==nil
      @events.each {|e|
if e[0]==event and e[2]<=Time.now.to_f-e[1]
e[2]=Time.now.to_f
e[3].call
end
}
    end
    def path(x,y,ox,oy,walls,width,height)
            return [[x,y]] if x==ox&&y==oy
            mat=[]
            for i in 0...width
              mat[i]=[]
              for j in 0...height
                s=true
                s=false if walls.include?([i,j])
                mat[i][j]=s
                end
              end
              b=bfs(mat,x,y,ox,oy)
              b=[[x,y]] if b==nil
              return b
            end
def play(sound,x=nil,y=nil)
  x,y=@px,@py if x==nil||y==nil
  return if x==nil||y==nil
  d=Math::sqrt((@x-x)**2+(@y-y)**2)
  dx=(@x-x)/@sound_range.to_f
         dy=(@y-y)/@sound_range.to_f
         s=Sound.new(sound)
        s.pan=dx
        #s.frequency=@sound_handle.basefrequency*(1.0-dy.abs*0.2)
        s.volume=(@sound_range-d.to_f)/@sound_range
        s.play
        Thread.new {
        sleep(s.length)
        s.close
        }
  end
    def update(x, y, walls, width, height)
                d=Math::sqrt((@x-x)**2+(@y-y)**2)
      @px,@py=x,y
            if @laststep+@move_delay<Time.now.to_f
        @laststep=Time.now.to_f
        mx,my=@x,@y
        case @move_type
        when :follow
          mx,my=path(@x,@y,x,y,walls,width,height)[0]
                    when :random
            5.times {
                        mx=rand(3)-1
            my=rand(3)-1
            walls.each {|w| break if w[0]!=mx&&w[1]!=my }
            }
          end
          suc=true
          walls.each {|w| suc=false if w[0]==mx&&w[1]==my}
          @x,@y=mx,my if suc
                  end
      if @sound!=nil
        if @sound_handle==nil
          @sound_handle=Sound.new(@sound, sample: true, loop: true)
        end
       if d<=@sound_range
         dx=(@x-x)/@sound_range.to_f
         dy=(@y-y)/@sound_range.to_f
        @sound_handle.pan=dx
        @sound_handle.frequency=@sound_handle.basefrequency*(1.0-dy.abs*0.2)
        v=(@sound_range-d.to_f)/@sound_range/2.0
        v+=0.5 if dy>=0
        @sound_handle.volume=v
        @sound_handle.play
      else
        @sound_handle.pause
        end
      end
      if d<@range
          keyevents.each {|a| trigger(a[0], raw_key_held?(:key_shift), modifier_held?(:main_modifier), modifier_held?(:option))}
          trigger(:range)
        end
        trigger(:touch) if x==@x&&y==@y
      end
      def dispose
        @sound_handle.close if @sound_handle!=nil
        @sound_handle=nil
        end
    end

  class Map
    attr_reader :width, :height, :direction, :objects
    attr_accessor :x, :y
    attr_accessor :move_sound, :border_sound, :wall_sound, :move_delay, :direction_sound, :direction_delay
    def initialize(width, height, &block)
      @scene=$scene
            @width, @height = width, height
            @direction=[0,0]
      @actions=[]
      @objects=[]
      @walls=[]
      @move_sound="list_focus"
      @x=0
      @y=0
      @move_delay=0.2
      @direction_delay=false
      @timers=[]
      if block_given?
        if block.arity<=0
          instance_eval(&block)
        else
          block.call(self)
        end
        end
    end
def wall(x1, y1, x2=nil, y2=nil)
  x2, y2 = x1, y1 if x2==nil||y2==nil
  x1,x2=x2,x1 if x1>x2
  y1,y2=y2,y1 if y1>y2
  x,y=x1,y1
    loop do
        @walls.push([x,y])
        break if x>=x2 && y>=y2
    x+=1 if x2>x1
    y+=1 if y2>y1
    end
  end
  def action(x,y,&block)
    @actions.push([x,y,block])
  end
  def object(x,y,&block)
    @objects.push(MapObject.new(x,y,@scene,&block))
  end
  def delete_object(o)
    o.dispose
    @objects.delete(o)
    end
  def timer(offset, repeat=false, &block)
    t=Timer.new(offset,repeat: repeat, autostart: false, &block)
    @timers.push(t)
    t
  end
  def distance(x,y)
    return Math::sqrt((@x-x)**2+(@y-y)**2)
  end
  def random_position(d=0)
    x,y=nil,nil
    while x==nil||y==nil||distance(x,y)<d
      x,y=rand(@width),rand(@height)
    end
    return [x,y]
    end
  def empty?(x,y)
    return !@walls.include?([x,y])
    end
  def directs?(x,y)
    d=[0,0]
      d[0]=-1 if x<@x
      d[0]=1 if x>@x
      d[1]=-1 if y<@y
      d[1]=1 if y>@y
      return d==@direction || d==[0,0]
    end
  def go(x,y)
        if x<0||x>=@width||y<0||y>=@height
      trigger(:border)
      play_sound(@border_sound) if @border_sound!=nil
    else
      ld=@direction
      d=[0,0]
      d[0]=-1 if x<@x
      d[0]=1 if x>@x
      d[1]=-1 if y<@y
      d[1]=1 if y>@y
      if @direction!=d
      @direction=d
      play_sound(@direction_sound) if @direction_sound!=nil
      return if @direction_delay
      end
      for w in @walls
        if w[0]==x&&w[1]==y
          play_sound(@wall_sound) if @wall_sound!=nil
          trigger(:wall)
          return
          end
      end
      play_sound(@move_sound) if @move_sound!=nil
      @x,@y=x,y
      for ac in @actions
        ac[2].call if ac[0]==x and ac[1]==y
      end
            trigger(:move)
            end
          end
          def on(event, time=0, &block)
      @events||=[]
      @events.push([event,time,0,block])
    end
def trigger(event, *params)
      return if @events==nil
      @events.each {|e|
if e[0]==event and e[2]<=Time.now.to_f-e[1]
e[2]=Time.now.to_f
@scene.instance_eval(&e[3])
end
}
    end
  def show(x=nil, y=nil)
    @x=x if x!=nil
    @y=y if y!=nil
    @disposed=false
    @timers.each {|t| t.start}
        laststep=0
        loop do
      loop_update
      keyevents.each {|a| trigger(a[0], raw_key_held?(:key_shift), modifier_held?(:main_modifier), modifier_held?(:option))}
      if (laststep+@move_delay)<Time.now.to_f
      if key_pressed?(:key_down, repeat: true)
        laststep=Time.now.to_f
go(@x, @y-1)
end
if key_pressed?(:key_up, repeat: true)
  laststep=Time.now.to_f
go(@x, @y+1)
end
if key_pressed?(:key_left, repeat: true)
  laststep=Time.now.to_f
go(@x-1, @y)
end
if key_pressed?(:key_right, repeat: true)
  laststep=Time.now.to_f
go(@x+1, @y)
end
end
@objects.each {|o| o.update(@x,@y,@walls, @width, @height)} if !@disposed
      break if @disposed
      end
  end
  def dispose
    @objects.each {|o| o.dispose}
    @timers.each {|t| t.stop}
    @disposed=true
    end
  end


  end
end
