# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
def json_load_ext(str)
          Log.debug("JSON Load Ext")
return JSON.load(str)
rescue Exception
return nil
end

def process_url(url)
  Log.debug("Opening URL #{url}")
  return if !url.is_a?(String)
  if url[0...8].downcase!="elten://"
    platform_open_url(url)
  return true
end
bu=url[8..-1]
q=bu.split("/")
case q[0]
when "forum"
  case q[1]
  when "group"
    insert_scene(Scene_Forum.new(nil, q[2].to_i))
    when "forum"
      insert_scene(Scene_Forum.new(nil, q[2]))
      when "thread"
        t=q[3].to_i
        t=nil if q[3]==nil
        insert_scene(Scene_Forum_Thread.new(q[2].to_i, -13, 0, t, nil, Scene_Main.new))
else
  return false
  end
  when "blog"

else
  return false
end
  end
  end
end
