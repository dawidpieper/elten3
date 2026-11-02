# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "fiddle/import"

class SteamAudio
  class Error < StandardError; end

  module Native
    extend Fiddle::Importer

    Coordinates = struct(["float right[3]", "float up[3]", "float ahead[3]", "float origin[3]"])
    SceneSettings = struct(["int type", "void* closest", "void* any", "void* batched_closest", "void* batched_any", "void* user", "void* embree", "void* radeon"])
    MeshSettings = struct(["int vertices_count", "int triangles_count", "int materials_count", "void* vertices", "void* triangles", "void* indices", "void* materials"])
    InstanceSettings = struct(["void* scene", "float transform[16]"])
    DistanceModel = struct(["int type", "float minimum", "void* callback", "void* user", "int dirty"])
    AirModel = struct(["int type", "float coefficients[3]", "void* callback", "void* user", "int dirty"])
    Directivity = struct(["float weight", "float power", "void* callback", "void* user"])
    BakedIdentifier = struct(["int type", "int variation", "float sphere[4]"])
    SimulationSettings = struct(["int flags", "int scene_type", "int reflection_type", "int occlusion_samples", "int rays", "int diffuse_samples", "float duration", "int order", "int sources", "int threads", "int ray_batch", "int visibility_samples", "int sample_rate", "int frame_size", "void* opencl", "void* radeon", "void* tan"])
    SimulationInputs = struct(["int flags", "int direct_flags", {"source" => Coordinates}, {"distance" => DistanceModel}, {"air" => AirModel}, {"directivity" => Directivity}, "int occlusion_type", "float radius", "int occlusion_samples", "float reverb_scale[3]", "float transition", "float overlap", "int baked", {"baked_identifier" => BakedIdentifier}, "void* probes", "float visibility_radius", "float visibility_threshold", "float visibility_range", "int pathing_order", "int validation", "int alternate_paths", "int transmission_rays", "void* deviation"])
    SharedInputs = struct([{"listener" => Coordinates}, "int rays", "int bounces", "float duration", "int order", "float minimum_distance", "void* callback", "void* user"])
    DirectParams = struct(["int flags", "int transmission_type", "float attenuation", "float air[3]", "float directivity", "float occlusion", "float transmission[3]"])
    ReflectionParams = struct(["int type", "void* ir", "float times[3]", "float eq[3]", "int delay", "int channels", "int samples", "void* tan", "int slot"])
    PathParams = struct(["float eq[3]", "void* coefficients", "int order", "int binaural", "void* hrtf", {"listener" => Coordinates}, "int normalise"])
    Outputs = struct([{"direct" => DirectParams}, {"reflections" => ReflectionParams}, {"pathing" => PathParams}])
    ReflectionSettings = struct(["int type", "int samples", "int channels"])
    SpeakerLayout = struct(["int type", "int speakers_count", "void* speakers"])
    DecodeSettings = struct([{"layout" => SpeakerLayout}, "void* hrtf", "int order"])
    DecodeParams = struct(["int order", "void* hrtf", {"listener" => Coordinates}, "int binaural"])
    BinauralParams = struct(["float direction[3]", "int interpolation", "float blend", "void* hrtf", "void* delays"])

    SIGNATURES = {
      SceneCreate: ["ppp", :int], SceneCommit: ["p", :void], SceneRelease: ["p", :void],
      StaticMeshCreate: ["ppp", :int], StaticMeshAdd: ["pp", :void], StaticMeshRemove: ["pp", :void], StaticMeshRelease: ["p", :void],
      InstancedMeshCreate: ["ppp", :int], InstancedMeshAdd: ["pp", :void], InstancedMeshRemove: ["pp", :void], InstancedMeshRelease: ["p", :void],
      SimulatorCreate: ["ppp", :int], SimulatorSetScene: ["pp", :void], SimulatorCommit: ["p", :void], SimulatorRelease: ["p", :void],
      SimulatorSetSharedInputs: ["pip", :void], SimulatorRunDirect: ["p", :void], SimulatorRunReflections: ["p", :void],
      SourceCreate: ["ppp", :int], SourceAdd: ["pp", :void], SourceRemove: ["pp", :void], SourceRelease: ["p", :void],
      SourceSetInputs: ["pip", :void], SourceGetOutputs: ["pip", :void],
      HRTFCreate: ["pppp", :int], HRTFRelease: ["p", :void],
      AudioBufferAllocate: ["piip", :int], AudioBufferFree: ["pp", :void], AudioBufferDeinterleave: ["ppp", :void], AudioBufferInterleave: ["ppp", :void], AudioBufferDownmix: ["ppp", :void], AudioBufferMix: ["ppp", :void]
    }.freeze

    class << self
      def build(type)
        value = type.malloc(Fiddle::RUBY_FREE)
        value.to_ptr[0, type.size] = "\0".b * type.size
        value
      end

      def function(name)
        @functions ||= {}
        @functions[name] ||= begin
          arguments, result = SIGNATURES[name] || effect_signature(name.to_s)
          SteamAudio.native_function("ipl#{name}", arguments.chars.map { |type| type == "p" ? Fiddle::TYPE_VOIDP : Fiddle::TYPE_INT }, result == :int ? Fiddle::TYPE_INT : Fiddle::TYPE_VOID)
        end
      end

      def call(name, *arguments)
        function(name).call(*arguments)
      end

      def reset
        @functions = {}
      end

      def create(type, *arguments)
        handle = Handle.new(type)
        result = call(:"#{type}Create", *arguments, handle.storage)
        if result != 0 || handle.to_i == 0
          handle.close
          raise Error, "Steam Audio #{type} creation failed: #{result}"
        end
        handle
      end

      def coordinates(target, pose)
        target.right = pose[:right]
        target.up = pose[:up]
        target.ahead = pose[:forward]
        target.origin = pose[:position]
        target
      end

      private

      def effect_signature(name)
        raise ArgumentError, "Unknown Steam Audio function #{name}" unless name.match?(/\A(?:Binaural|Direct|Reflection|AmbisonicsDecode)Effect/)
        case name
        when /Create\z/ then ["pppp", :int]
        when /Release\z/, /Reset\z/ then ["p", :void]
        when /GetTailSize\z/ then ["p", :int]
        when /GetTail\z/ then [name.start_with?("Reflection") ? "ppp" : "pp", :int]
        when /Apply\z/ then [name.start_with?("Reflection") ? "ppppp" : "pppp", :int]
        else raise ArgumentError, "Unknown Steam Audio function #{name}"
        end
      end
    end

    class Handle
      attr_reader :storage, :type

      def initialize(type)
        @type = type
        @storage = SteamAudio.pointer_buffer
      end

      def to_i
        SteamAudio.pointer_value(@storage)
      end

      def to_ptr
        @pointer ||= Fiddle::Pointer.new(to_i)
      end

      def close
        Native.call(:"#{@type}Release", @storage) if to_i != 0
        @pointer = nil
      end
    end

    class Buffer
      attr_reader :storage, :channels, :samples

      def initialize(channels, samples)
        @channels, @samples = channels, samples
        @storage = SteamAudio.audio_buffer
        result = Native.call(:AudioBufferAllocate, SteamAudio.context, channels, samples, @storage)
        raise Error, "Steam Audio buffer allocation failed: #{result}" if result != 0
        pointers = Fiddle::Pointer.new(SteamAudio.pointer_value(@storage, 8))
        @planes = channels.times.map { |i| Fiddle::Pointer.new(SteamAudio.pointer_value(pointers, i * POINTER_SIZE)) }
        @silence = "\0".b * (samples * 4)
        @interleaved = "\0".b * (samples * channels * 4)
      end

      def read(audio)
        Native.call(:AudioBufferDeinterleave, SteamAudio.context, audio, @storage)
      end

      def write
        Native.call(:AudioBufferInterleave, SteamAudio.context, @storage, @interleaved)
        @interleaved
      end

      def clear
        @planes.each { |plane| plane[0, @silence.bytesize] = @silence }
      end

      def close
        Native.call(:AudioBufferFree, SteamAudio.context, @storage) if @planes != nil
        @planes = nil
      end
    end
  end
end
