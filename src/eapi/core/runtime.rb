# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module ExceptionRecovery
    @mutex = Mutex.new

    class << self
      def ready!
        @mutex.synchronize do
          @ready = true
          @retry_after = nil unless @reporting
        end
      end

      def report
        started = false
        @mutex.synchronize do
          return false unless @ready
          return false if @reporting || Process.clock_gettime(Process::CLOCK_MONOTONIC) < @retry_after.to_f
          @reporting = true
          started = true
        end
        yield
        true
      ensure
        if started
          @mutex.synchronize do
            @retry_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
            @reporting = false
          end
        end
      end
    end
  end

  private

def recover_elten_error(error, scene)
  return false if defined?(Programs) && Programs.runtime_from_error(error, scene) != nil
  ExceptionRecovery.report do
    Log.error("Elten failed: #{error.class}: #{error.message}\n#{Array(error.backtrace).join("\n")}")
    trace = Programs.clean_program_backtrace(error)
    details = "#{error.class}: #{error.message}"
    details += "\n\n#{p_("Program", "Backtrace:")}\n#{trace.join("\n")}" unless trace.empty?
    input_text(
      p_("Elten", "Error in Elten"),
      flags: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly,
      text: details,
      escapable: true
    )
  end
end
def execute_scene_main(scene)
  with_scene_context(scene) do
    if defined?(Program) && scene.is_a?(Program) && scene.respond_to?(:program_main, true)
      begin
        result = scene.__send__(:program_main)
      rescue StandardError
        scene.finalize(reason: :error)
        raise
      else
        scene.finalize(result, reason: :normal)
      end
    else
      scene.main
    end
  end
end

def with_scene_context(scene)
  previous = Thread.current.thread_variable_get(:elten_scene)
  Thread.current.thread_variable_set(:elten_scene, scene)
  yield
ensure
  Thread.current.thread_variable_set(:elten_scene, previous)
end

def insert_scene(scene, must=false, return_to_main: false)
  return if (($scenes[0]!=nil and $scenes[0].is_a?(scene.class)) or $scene.is_a?(scene.class)) and !must
  scene.instance_variable_set(:@insert_scene_return_to_main, true) if return_to_main && scene != nil
      if $scene.is_a?(Scene_Main) and $scenes.size==0
    return $scene=scene
  end
  $subthreads||=[]
  $scenes||=[]
  Log.info("Inserting new parallel scenes thread #{($subthreads.size+$scenes.size+1).to_s}")
  $scenes.insert(0,scene)
  t=Time.now.to_f
  loop_update(false) while Time.now.to_f-t<0.2
end
      def crypt(data,code=nil)
        return "".b if !EltenSystemHelpers.autologin_key_encryption_supported?
        EltenSystemHelpers.protect_data(data, code)
        end

        def decrypt(data,code=nil)
        return nil if !EltenSystemHelpers.autologin_key_encryption_supported?
        m=EltenSystemHelpers.unprotect_data(data, code)
        Log.warning("Failed to decrypt data") if m==nil
        m
end

          def bfs(mat, x, y, ox, oy)
rowNum = [-1, 0, 0, 1]
colNum = [0, -1, 1, 0]
return nil if(mat[x][y]==false or mat[ox][oy]==false)
visited=[]
for i in 0...mat.size
visited[i]=[]
for j in 0...mat[i].size
visited[i][j]=false
end
end
visited[x][y] = true
q = [[[x,y], []]]
while !q.empty?
curr = q[0]
if(curr[0][0] == ox && curr[0][1] == oy)
return curr[1]
end
q.delete_at(0)
for i in 0...4
  row = curr[0][0] + rowNum[i]
col = curr[0][1] + colNum[i]
if row>=0 && col>=0 && row<mat.size && col<mat[row].size && mat[row][col]==true && !visited[row][col]
visited[row][col]=true
adjcell = [[row, col], curr[1]+[[row,col]]]
q.push(adjcell)
end
end
end
return nil
end

class Reset < Exception
end

class Hangup < Exception
end

    def current_executable_path
      if defined?(EltenEmbedded)
        launcher_executable = ENV["ELTEN_LAUNCHER_EXECUTABLE_PATH"].to_s
        return File.expand_path(launcher_executable) if launcher_executable != ""
        if Process.respond_to?(:execpath)
          executable=Process.execpath.to_s
          expanded = File.expand_path(executable) if executable != ""
          return expanded if expanded.to_s != "" && File.executable?(expanded)
        end
        if defined?(EltenRuntimePaths)
          return EltenSystemHelpers.embedded_executable_path(EltenRuntimePaths.root, EltenRuntimePaths.architecture)
        end
      end
      File.expand_path(RbConfig.ruby)
    rescue Exception
      File.expand_path($PROGRAM_NAME.to_s)
    end

    def restart_to_developer_mode
      command = developer_restart_command
      if command.to_s == ""
        Log.error("Developer restart failed: empty restart command")
        return false
      end
      Log.info("Restarting Elten in developer mode: #{command}")
      $exit_runproc = command
      $exit_runproc_path = Dir.pwd
      $exit = true
      $scene = nil
      true
    rescue Exception => e
      Log.error("Developer restart failed: #{e.class}: #{e.message}")
      false
    end

    def developer_restart_command
      parts = restart_command_parts
      parts << "/developer"
      EltenSystemHelpers.command_line_join(parts)
    end

    def restart_to_normal_mode
      command = normal_restart_command
      if command.to_s == ""
        Log.error("Normal restart failed: empty restart command")
        return false
      end
      Log.info("Restarting Elten in normal mode: #{command}")
      $exit_runproc = command
      $exit_runproc_path = Dir.pwd
      $exit = true
      $scene = nil
      true
    rescue Exception => e
      Log.error("Normal restart failed: #{e.class}: #{e.message}")
      false
    end

    def normal_restart_command
      parts = restart_command_parts.reject { |part| EltenBoot::DEVELOPER_FLAGS.include?(part.to_s.downcase) }
      EltenSystemHelpers.command_line_join(parts)
    end

    def restart_command_parts
      parts = original_process_arguments
      if parts.size > 0
        parts = parts.dup
        parts[0] = current_executable_path if defined?(EltenEmbedded)
        return parts
      end
      fallback_restart_command_parts
    end

    def original_process_arguments
      if defined?(::ELTEN_LAUNCHER_ARGV) && ::ELTEN_LAUNCHER_ARGV.is_a?(Array) && ::ELTEN_LAUNCHER_ARGV.size > 0
        return ::ELTEN_LAUNCHER_ARGV.map(&:to_s)
      end
      if defined?(EltenSystemHelpers) && EltenSystemHelpers.respond_to?(:original_process_arguments)
        args = EltenSystemHelpers.original_process_arguments
        return args.map(&:to_s) if args.is_a?(Array) && args.size > 0
      end
      []
    rescue Exception
      []
    end

    def fallback_restart_command_parts
      executable = current_executable_path
      parts = [executable]
      parts << $PROGRAM_NAME.to_s if !defined?(EltenEmbedded) && $PROGRAM_NAME.to_s != "" && $PROGRAM_NAME.to_s != "-e"
      parts + ARGV.map(&:to_s)
    end
end
