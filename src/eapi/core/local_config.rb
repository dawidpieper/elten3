# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  private
def writeconfig(group, key, val)
  Log.debug("Changing configuration: (#{group}:#{key}): #{val.to_s}")
  val=val.to_s if val!=nil
  writeini(EltenPath.join(Dirs.eltendata, "elten.ini"), group, key, val)
end

module LocalConfig
  LCCache={}
  LOCache={}
  class <<self
    def [](k, default=0)
      return 0 if !k.is_a?(String)
      if LCCache[k]!=nil
        return unformat(LCCache[k])
        else
            v=readconfig("Local", k, format(default))
            un=unformat(v)
            return default if default.class.name!=un.class.name
            LCCache[k]=v
            LOCache[k]=v
            return un
            end
          end
          def unformat(t)
            if t.is_a?(Integer)
              return t
            elsif t[0..0]=="["
              return t[1...-1].split(",").map{|o|unformat(o)}
            else
              return t.to_i
              end
            end
            def format(t)
              if t.is_a?(Integer)
                return t.to_s
              elsif t.is_a?(Array)
                return "["+t.find_all{|l|l.is_a?(Integer)}.join(",")+"]"
                end
              end
    def []=(k,v)
            return 0 if !k.is_a?(String) || (!v.is_a?(Integer) && !v.is_a?(Array))
            if v.is_a?(Array)
                            v="["+v.find_all{|l|l.is_a?(Integer)}.join(",")+"]"
              end
            LCCache[k]=v
            writeconfig("local", k, v) if v!=LOCache[k]
LOCache[k] = v
          end
          def save
            for k in LCCache.keys
              v=LCCache[k]
              writeconfig("local", k, v) if v!=LOCache[k]
LOCache[k] = v
              end
            end
    end
  end
end
