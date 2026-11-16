# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module Audio
  class SpatialScene
    attr_reader :listener, :settings, :error

    def initialize(reflections: true, frequency: 48_000, rays: 512, bounces: 8, duration: 1.0,
      order: 1, max_sources: 32, threads: [Etc.nprocessors, 2].min, occlusion_samples: 16,
      update_rate: 30, reflection_rate: 5, automatic: true, hrtf: nil)
      raise ArgumentError, "Expected an Audio::HRTF profile" if hrtf != nil && !hrtf.is_a?(HRTF)
      raise ArgumentError, "Reflections and automatic must be true or false" if ![true, false].include?(reflections) || ![true, false].include?(automatic)
      @settings = {
        reflections: reflections, frequency: integer(frequency, "Frequency", 44_100, 48_000),
        rays: integer(rays, "Ray count", 1, 65_536), bounces: integer(bounces, "Bounce count", 1, 128),
        duration: SpatialMath.scalar(duration, "Reflection duration", min: 0.02, max: 10),
        order: integer(order, "Ambisonics order", 0, 3), max_sources: integer(max_sources, "Source count", 1, 256),
        threads: integer(threads, "Thread count", 1, 64), occlusion_samples: integer(occlusion_samples, "Occlusion samples", 1, 256)
      }.freeze
      raise ArgumentError, "Frequency must be 44100 or 48000 Hz" if ![44_100, 48_000].include?(frequency)
      @interval = 1.0 / SpatialMath.scalar(update_rate, "Update rate", min: 1, max: 120)
      @reflection_interval = 1.0 / SpatialMath.scalar(reflection_rate, "Reflection rate", min: 0.1, max: 60)
      @mutex = Mutex.new
      @simulation_mutex = Mutex.new
      @condition = ConditionVariable.new
      @closed = false
      @geometry = []
      @emitters = []
      @last_reflections = -Float::INFINITY
      @listener = SpatialPose.new { wake }
      raise SteamAudio::Error, "Steam Audio is unavailable" if !SteamAudio.load
      @simulation = SteamAudio::Simulation.new(@settings, hrtf)
      SteamAudio.register(self)
      @worker = Thread.new { run } if automatic
      @worker.report_on_exception = false if @worker != nil
    rescue Exception
      @simulation&.close
      SteamAudio.unregister(self) if defined?(SteamAudio)
      raise
    end

    def add_mesh(**options)
      mesh = SpatialGeometry.new(self, **options)
      @mutex.synchronize do
        check_open
        @geometry << mesh
        @condition.signal
      end
      mesh
    end

    def add_box(min:, max:, material: AcousticMaterial.new, inward: false)
      minimum = SpatialMath.vector(min, "Minimum bounds")
      maximum = SpatialMath.vector(max, "Maximum bounds")
      raise ArgumentError, "Box bounds must have positive volume" if minimum.zip(maximum).any? { |a, b| a >= b }
      vertices = [[0,0,0], [1,0,0], [1,1,0], [0,1,0], [0,0,1], [1,0,1], [1,1,1], [0,1,1]].map do |corner|
        corner.each_with_index.map { |value, axis| value == 0 ? minimum[axis] : maximum[axis] }
      end
      triangles = [[0,2,1], [0,3,2], [4,5,6], [4,6,7], [0,1,5], [0,5,4], [3,7,6], [3,6,2], [0,4,7], [0,7,3], [1,2,6], [1,6,5]]
      triangles = triangles.map(&:reverse) if inward
      add_mesh(vertices: vertices, triangles: triangles, materials: [material])
    end

    def add_room(min:, max:, material: AcousticMaterial.new)
      add_box(min: min, max: max, material: material, inward: true)
    end

    def create_emitter(**options)
      @simulation_mutex.synchronize do
        @mutex.synchronize do
          check_open
          @emitters.reject!(&:closed?)
          raise ArgumentError, "Spatial source limit exceeded" if @emitters.size >= @settings[:max_sources]
        end
        renderer = SteamAudio::SpatialRenderer.new(@simulation)
        emitter = SpatialEmitter.new(self, renderer, **options)
        @simulation.add(emitter)
        @simulation.update(@mutex.synchronize { @geometry.dup }, @listener.snapshot, reflections: false)
        @mutex.synchronize { @emitters << emitter; @condition.signal }
        emitter
      rescue Exception
        emitter&.close
        renderer&.close
        raise
      end
    end

    def add_sound(sound, **options)
      raise ArgumentError, "Expected a Sound" if !sound.is_a?(Sound)
      raise IOError, "Sound is not open" if !sound.opened?
      if sound.spatial_effect != nil || sound.effects.any? { |effect| effect.is_a?(SpatialEmitter) }
        raise ArgumentError, "Sound already has a spatial effect"
      end
      emitter = create_emitter(**options)
      sound.effect_add(emitter)
      emitter
    rescue Exception
      emitter&.close
      raise
    end

    def update(reflections: true)
      @simulation_mutex.synchronize do
        geometry = @mutex.synchronize { check_open; @geometry.reject!(&:closed?); @geometry.dup }
        @simulation.update(geometry, @listener.snapshot, reflections: reflections)
        @mutex.synchronize { @emitters.reject!(&:closed?) }
      end
      self
    end

    def wake(reflections: false)
      @mutex.synchronize do
        @reflection_dirty = true if reflections
        @condition.signal
      end
      self
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    def close
      @mutex.synchronize do
        return if @closed
        @closed = true
        @condition.broadcast
      end
      @worker.join if @worker != nil && @worker != Thread.current
      @simulation_mutex.synchronize do
        @emitters.each(&:close)
        @geometry.each(&:close)
        @simulation.close
        @emitters.clear
        @geometry.clear
      end
      SteamAudio.unregister(self)
    end

    private

    def integer(value, name, minimum, maximum)
      raise ArgumentError, "#{name} must be an integer between #{minimum} and #{maximum}" if !value.is_a?(Integer) || !value.between?(minimum, maximum)
      value
    end

    def check_open
      raise IOError, "Spatial scene is closed" if @closed
      raise @error if @error != nil
    end

    def run
      deadline = 0.0
      loop do
        active = @mutex.synchronize do
          loop do
            break false if @closed
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if @emitters.empty?
              @condition.wait(@mutex)
            elsif now < deadline
              @condition.wait(@mutex, deadline - now)
            else
              break true
            end
          end
        end
        break if !active
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        dirty = @mutex.synchronize { value = @reflection_dirty; @reflection_dirty = false; value }
        reflections = dirty || now - @last_reflections >= @reflection_interval
        update(reflections: reflections)
        @last_reflections = now if reflections
        deadline = now + @interval
      end
    rescue StandardError => error
      if !closed?
        @error = error
        Log.error("Spatial scene simulation: #{error.class}: #{error.message}")
      end
    end
  end
end
