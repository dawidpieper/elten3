# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
      # @note this function is reserved for Elten usage
                  def thr1
                                        loop do
            begin
            sleep(0.1)
              nvda = defined?(NVDA) ? NVDA : nil
              if nvda != nil && SpeechOutput.current_output != nvda
                if !nvda.check and nvda.usable?
nvda.stop
end
                      end
              rescue Exception
        fail
      end
      end
    end

# @note this function is reserved for Elten usage
  def thr2
    $subthreads=[] if $subthreads==nil
                                loop do
                              sleep(0.05)
                                    if $scenes.size > 0
                                      if $currentthread != $mainthread
                                                                                  $subthreads.push($currentthread)
                                        end
                                      $currentthread = Thread.new do
                                        stopct=false
                                        sc=$scene
                                        sleep(0.1)
                                        begin
                                          if stopct == false
                                                                                    newsc = $scenes[0]
                                          $scenes.delete_at(0)
                                          return_to_main = newsc.instance_variable_get(:@insert_scene_return_to_main) == true
                                                                $scene = newsc
                                                                  while $scene != nil and $scene.is_a?(Scene_Main) == false and $exit!=true
Log.debug("Loading parallel scene: #{$scene.class.to_s}")
$scene.main
                      end
                      $scene = return_to_main ? Scene_Main.new : sc
$scene=Scene_Main.new if $scene.is_a?(Scene_Main) or $scene == nil
$scene=nil if $exit==true
EltenAPI::KeyboardState.reset if defined?(EltenAPI::KeyboardState)
$focus = true if $scene.is_a?(Scene_Main) == false                     and $scene!=nil
Log.info("Exiting parallel scenes thread")
end
rescue Exception
      stopct=true
                                                                        $scene = sc
$scene=Scene_Main.new if $scene.is_a?(Scene_Main) or $scene == nil
loop_update
$focus = true if $scene.is_a?(Scene_Main) == false
Log.error("Parallel scene: #{$!.to_s} #{$@.to_s}")
  retry
end
sleep(0.1)
end
end
    if $switchthread!=nil
      cr=$switchthread
      $switchthread=nil
      cur=$currentthread
      $subthreads.push(cur) if cur!=nil
      $subthreads.delete(cr)
$currentthread=cr
      end
    if $currentthread != $mainthread
      if $currentthread.status==false or $currentthread.status==nil
        if $subthreads.size > 0
    $currentthread=$subthreads.last
    while $subthreads.last.status==false or $subthreads.last.status==nil
      $subthreads.delete_at($subthreads.size-1)
    end
      $subthreads.delete_at($subthreads.size-1)
    else
      $currentthread=$mainthread
      end
        end
                                                                                                                                                              end
         sleep(0.1)
       end
     rescue Exception
              retry
     end
  end
end
