# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

class SteamAudio
  class Simulation
    attr_reader :settings, :hrtf

    def initialize(settings, profile)
      @settings = settings
      @meshes = {}
      @sources = {}
      @hrtf = SteamAudio.new(settings[:frequency], 20, hrtf: profile)
      @scene = Native.create(:Scene, SteamAudio.context, Native.build(Native::SceneSettings))
      config = Native.build(Native::SimulationSettings)
      config.flags = settings[:reflections] ? 3 : 1
      config.occlusion_samples = settings[:occlusion_samples]
      config.rays = settings[:rays]
      config.diffuse_samples = 32
      config.duration = settings[:duration]
      config.order = settings[:order]
      config.sources = settings[:max_sources]
      config.threads = settings[:threads]
      config.ray_batch = 1
      config.visibility_samples = 1
      config.sample_rate = settings[:frequency]
      config.frame_size = settings[:frequency] / 50
      @simulator = Native.create(:Simulator, SteamAudio.context, config)
      Native.call(:SimulatorSetScene, @simulator, @scene)
      @shared = Native.build(Native::SharedInputs)
      @shared.rays = settings[:rays]
      @shared.bounces = settings[:bounces]
      @shared.duration = settings[:duration]
      @shared.order = settings[:order]
      @shared.minimum_distance = 0.1
    rescue Exception
      close
      raise
    end

    def add(emitter)
      remove_closed
      flags = @settings[:reflections] ? 3 : 1
      source = Native.create(:Source, @simulator, [flags].pack("i"))
      Native.call(:SourceAdd, source, @simulator)
      @sources[emitter] = {handle: source, inputs: Native.build(Native::SimulationInputs), outputs: Native.build(Native::Outputs)}
      Native.call(:SimulatorCommit, @simulator)
    end

    def update(geometry, listener, reflections:)
      changed = false
      @meshes.delete_if do |mesh, entry|
        next false if !mesh.closed?
        release_mesh(entry)
        changed = true
      end
      geometry.each do |mesh|
        next if mesh.closed?
        state = mesh.snapshot
        entry = @meshes[mesh]
        if entry == nil || entry[:materials] != state[:materials]
          replacement = build_mesh(mesh, state)
          release_mesh(entry) if entry != nil
          @meshes[mesh] = replacement
          changed = true
        elsif entry[:transform] != state[:transform]
          # Updating a transform by value is not portable through Fiddle; reuse the mesh in a new instance.
          replacement = create_instance(entry[:scene], state[:transform])
          Native.call(:InstancedMeshRemove, entry[:instance], @scene)
          entry[:instance].close
          entry[:instance] = replacement
          entry[:transform] = state[:transform]
          changed = true
        end
      end
      Native.call(:SceneCommit, @scene) if changed
      removed = remove_closed
      Native.call(:SimulatorCommit, @simulator) if changed || removed
      return if @sources.empty?
      flags = reflections && @settings[:reflections] ? 3 : 1
      Native.coordinates(@shared.listener, listener)
      Native.call(:SimulatorSetSharedInputs, @simulator, flags, @shared)
      @sources.each do |emitter, entry|
        options = emitter.options
        input = entry[:inputs]
        input.flags = options[:reflections] && @settings[:reflections] ? 3 : 1
        input.direct_flags = 1 | 2 | 4
        input.direct_flags |= 8 if [:raycast, :volumetric].include?(options[:occlusion])
        input.direct_flags |= 16 if options[:transmission] == true
        Native.coordinates(input.source, emitter.pose.snapshot)
        input.distance.type = 1
        input.distance.minimum = options[:min_distance]
        input.directivity.weight, input.directivity.power = options[:directivity]
        input.occlusion_type = options[:occlusion] == :volumetric ? 1 : 0
        input.radius = options[:radius]
        input.occlusion_samples = @settings[:occlusion_samples]
        input.transmission_rays = 8
        input.reverb_scale = [1, 1, 1]
        Native.call(:SourceSetInputs, entry[:handle], flags, input)
      end
      Native.call(:SimulatorRunDirect, @simulator)
      @sources.each do |emitter, entry|
        Native.call(:SourceGetOutputs, entry[:handle], 1, entry[:outputs])
        emitter.publish(entry[:outputs], reflections: false)
      end
      if flags == 3
        Native.call(:SimulatorRunReflections, @simulator)
        @sources.each do |emitter, entry|
          Native.call(:SourceGetOutputs, entry[:handle], 2, entry[:outputs])
          emitter.publish(entry[:outputs], reflections: true)
        end
      end
    end

    def remove_closed
      removed = false
      @sources.delete_if do |emitter, entry|
        next false if !emitter.closed?
        Native.call(:SourceRemove, entry[:handle], @simulator)
        entry[:handle].close
        removed = true
      end
      removed
    end

    def close
      @sources&.each_value { |entry| entry[:handle].close }
      @sources&.clear
      @simulator&.close
      @meshes&.each_value { |entry| release_mesh(entry) }
      @meshes&.clear
      @scene&.close
      @hrtf&.free
    end

    private

    def build_mesh(mesh, state)
      entry = {materials: state[:materials], transform: state[:transform]}
      entry[:scene] = Native.create(:Scene, SteamAudio.context, Native.build(Native::SceneSettings))
      vertices = mesh.vertices.flatten.pack("f*")
      triangles = mesh.triangles.flatten.pack("i*")
      indices = mesh.material_indices.pack("i*")
      materials = state[:materials].flat_map(&:to_a).pack("f*")
      config = Native.build(Native::MeshSettings)
      config.vertices_count = mesh.vertices.size
      config.triangles_count = mesh.triangles.size
      config.materials_count = state[:materials].size
      config.vertices = Fiddle::Pointer[vertices]
      config.triangles = Fiddle::Pointer[triangles]
      config.indices = Fiddle::Pointer[indices]
      config.materials = Fiddle::Pointer[materials]
      entry[:mesh] = Native.create(:StaticMesh, entry[:scene], config)
      Native.call(:StaticMeshAdd, entry[:mesh], entry[:scene])
      Native.call(:SceneCommit, entry[:scene])
      entry[:instance] = create_instance(entry[:scene], state[:transform])
      entry
    rescue Exception
      release_mesh(entry)
      raise
    end

    def create_instance(scene, transform)
      config = Native.build(Native::InstanceSettings)
      config.scene = scene.to_i
      config.transform = transform
      instance = Native.create(:InstancedMesh, @scene, config)
      Native.call(:InstancedMeshAdd, instance, @scene)
      instance
    end

    def release_mesh(entry)
      return if entry == nil
      if entry[:instance] != nil
        Native.call(:InstancedMeshRemove, entry[:instance], @scene)
        entry[:instance].close
      end
      entry[:mesh]&.close
      entry[:scene]&.close
    end
  end
end
