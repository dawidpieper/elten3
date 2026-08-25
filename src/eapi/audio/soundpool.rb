# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class SoundPool
  DEFAULT_MAX_VOICES = 16
  DEFAULT_REAP_INTERVAL = 0.05

  attr_reader :max_voices

  def initialize(max_voices: DEFAULT_MAX_VOICES, reap_interval: DEFAULT_REAP_INTERVAL)
    @max_voices = normalize_max_voices(max_voices)
    @reap_interval = normalize_reap_interval(reap_interval)
    @sounds = []
    @mutex = Mutex.new
    @condition = ConditionVariable.new
    @closed = false
    @reaper = nil
  end

  def max_voices=(value)
    removed = []
    @mutex.synchronize do
      @max_voices = normalize_max_voices(value)
      removed = trim_locked
    end
    close_sounds(removed)
    @max_voices
  end

  def play(sound)
    raise ArgumentError, "sound must respond to #play, #finished?, and #close" if !managed_sound?(sound)
    raise RuntimeError, "sound pool is closed" if closed?
    sound.play
    removed = []
    @mutex.synchronize do
      raise RuntimeError, "sound pool is closed" if @closed
      @sounds << sound
      removed = trim_locked
      start_reaper_locked
      @condition.signal
    end
    close_sounds(removed)
    sound
  rescue Exception
    sound.close rescue nil
    raise
  end

  def update
    snapshot = @mutex.synchronize { @sounds.dup }
    finished = snapshot.select { |sound| sound.finished? rescue true }
    return 0 if finished.empty?
    @mutex.synchronize { finished.each { |sound| @sounds.delete(sound) } }
    close_sounds(finished)
    finished.size
  end

  def remove(sound, close: false)
    removed = @mutex.synchronize { @sounds.delete(sound) }
    sound.close if removed != nil && close == true
    removed != nil
  rescue Exception
    removed != nil
  end

  def sounds
    @mutex.synchronize { @sounds.dup }
  end

  def size
    @mutex.synchronize { @sounds.size }
  end

  def close
    thread = nil
    sounds = []
    @mutex.synchronize do
      return if @closed
      @closed = true
      sounds = @sounds
      @sounds = []
      thread = @reaper
      @condition.broadcast
    end
    thread.join if thread != nil && thread != Thread.current
    close_sounds(sounds)
    nil
  end

  def closed?
    @mutex.synchronize { @closed == true }
  end

  private

  def start_reaper_locked
    return if @reaper != nil && @reaper.alive?
    @reaper = Thread.new { reap_loop }
    @reaper.report_on_exception = false
  end

  def reap_loop
    loop do
      stopped = @mutex.synchronize do
        if !@closed
          @condition.wait(@mutex, @reap_interval)
        end
        @closed
      end
      break if stopped
      update
    end
  rescue Exception => e
    Log.warning("Sound pool reaper failed: #{e.class}: #{e.message}") if defined?(Log)
  end

  def trim_locked
    removed = []
    removed << @sounds.shift while @sounds.size > @max_voices
    removed
  end

  def close_sounds(sounds)
    sounds.each { |sound| sound.close rescue nil }
  end

  def managed_sound?(sound)
    sound != nil && sound.respond_to?(:play) && sound.respond_to?(:finished?) && sound.respond_to?(:close)
  end

  def normalize_max_voices(value)
    voices = value.to_i
    raise ArgumentError, "max_voices must be positive" if voices <= 0
    voices
  end

  def normalize_reap_interval(value)
    interval = value.to_f
    raise ArgumentError, "reap_interval must be positive" if !interval.finite? || interval <= 0.0
    interval
  end
end
