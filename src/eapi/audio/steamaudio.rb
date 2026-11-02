# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "fiddle"

class SteamAudio
  class SAEffect
    attr_accessor :handle, :effect, :in_buffer, :out_buffer, :channels, :samples, :bilinear
  end

  API_VERSION = 0x040300
  DEFAULT_HRTF = 0
  HRTF_NORM_NONE = 0
  HRTF_INTERPOLATION_NEAREST = 0
  HRTF_INTERPOLATION_BILINEAR = 1

  POINTER_SIZE = Fiddle::SIZEOF_VOIDP
  POINTER_PACK = POINTER_SIZE == 8 ? "Q" : "L"
  NULL_POINTER = 0

  @@lib = nil
  @@context_handle = nil
  @@context = 0
  @@instances = []
  @@mutex = Mutex.new
  @@hrtf_mutex = Mutex.new
  @@resources_mutex = Mutex.new
  @@resources = []
  @@simd = 0

  def self.pointer_buffer(value = 0)
    [value.to_i].pack(POINTER_PACK)
  end

  def self.pointer_value(buffer, offset = 0)
    chunk = buffer[offset, POINTER_SIZE] || ""
    chunk += "\0" * (POINTER_SIZE - chunk.bytesize)
    chunk.unpack1(POINTER_PACK).to_i
  end

  def self.context
    @@context
  end

  def self.register(resource)
    @@resources_mutex.synchronize { @@resources << resource }
    resource
  end

  def self.unregister(resource)
    @@resources_mutex.synchronize { @@resources.delete(resource) }
  end

  def self.native_function(name, arguments, result)
    windows_x86 = RUBY_PLATFORM.match?(/mingw|mswin/) && POINTER_SIZE == 4
    abi = windows_x86 ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
    address = begin
      @@lib[name]
    rescue Fiddle::DLError
      raise unless windows_x86
      @@lib["_#{name}@#{arguments.size * 4}"]
    end
    Fiddle::Function.new(address, arguments, result, abi)
  end

  def self.context_settings
    if POINTER_SIZE == 8
      [API_VERSION, NULL_POINTER, NULL_POINTER, NULL_POINTER, @@simd, 0].pack("Lx4QQQll")
    else
      [API_VERSION, NULL_POINTER, NULL_POINTER, NULL_POINTER, @@simd, 0].pack("LLLLll")
    end
  end

  def self.audio_settings(frequency, samples)
    [frequency.to_i, samples.to_i].pack("ll")
  end

  def self.hrtf_settings(profile = nil)
    data = profile&.data
    type = data == nil ? DEFAULT_HRTF : 1
    pointer = data == nil ? NULL_POINTER : Fiddle::Pointer[data].to_i
    size = data == nil ? 0 : data.bytesize
    volume = profile == nil ? 1.0 : profile.volume
    normalisation = profile != nil && profile.normalisation == :rms ? 1 : HRTF_NORM_NONE
    if POINTER_SIZE == 8
      [type, NULL_POINTER, pointer, size, volume, normalisation].pack("lx4QQlflx4")
    else
      [type, NULL_POINTER, pointer, size, volume, normalisation].pack("lLLlfl")
    end
  end

  def self.effect_settings(hrtf)
    pointer_buffer(hrtf)
  end

  def self.effect_params(x, y, z, hrtf, bilinear, blend = 1.0)
    interpolation = bilinear ? HRTF_INTERPOLATION_BILINEAR : HRTF_INTERPOLATION_NEAREST
    if POINTER_SIZE == 8
      [x.to_f, y.to_f, z.to_f, interpolation, blend, hrtf.to_i, NULL_POINTER].pack("ffflfx4QQ")
    else
      [x.to_f, y.to_f, z.to_f, interpolation, blend, hrtf.to_i, NULL_POINTER].pack("ffflfLL")
    end
  end

  def self.audio_buffer
    "\0".b * (POINTER_SIZE == 8 ? 16 : 12)
  end

  def self.load(file = nil, simd: :auto)
    return true if @@lib != nil
    file = "phonon" if file == nil || file.to_s == ""
    @@mutex.synchronize do
      return true if @@lib != nil
      @@lib = EltenRuntimePaths.dlopen(file)
      @@simd = if simd == :auto
        RUBY_PLATFORM.match?(/arm|aarch64/) ? 0 : 4
      else
        {sse2: 0, sse4: 1, avx: 2, avx2: 3, avx512: 4, neon: 0}.fetch(simd)
      end
      bind_functions
      @@context_handle = pointer_buffer
      result = @@iplContextCreate.call(context_settings, @@context_handle)
      @@context = pointer_value(@@context_handle)
      fail("SteamAudio context create failed: #{result}") if result != 0 || @@context == 0
    end
    true
  rescue Exception
    close_library
    false
  end

  def self.bind_functions
    @@iplContextCreate = native_function("iplContextCreate", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplContextRelease = native_function("iplContextRelease", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplHRTFCreate = native_function("iplHRTFCreate", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplHRTFRelease = native_function("iplHRTFRelease", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplBinauralEffectCreate = native_function("iplBinauralEffectCreate", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplBinauralEffectRelease = native_function("iplBinauralEffectRelease", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplBinauralEffectApply = native_function("iplBinauralEffectApply", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplAudioBufferAllocate = native_function("iplAudioBufferAllocate", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplAudioBufferFree = native_function("iplAudioBufferFree", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplAudioBufferDeinterleave = native_function("iplAudioBufferDeinterleave", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplAudioBufferInterleave = native_function("iplAudioBufferInterleave", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
  end

  def self.close_resources
    @@resources_mutex.synchronize { @@resources.dup }.each(&:close)
  end

  def self.free
    close_resources
    @@mutex.synchronize do
      @@instances.dup.each { |instance| instance.free }
      @@instances.clear
      close_library
    end
  end

  def self.close_library
    Native.reset if defined?(Native)
    if @@context_handle != nil && @@context != 0 && defined?(@@iplContextRelease)
      @@iplContextRelease.call(@@context_handle)
    end
    @@context_handle = nil
    @@context = 0
    @@lib.close if @@lib != nil
    @@lib = nil
  rescue Exception
    @@context_handle = nil
    @@context = 0
    @@lib = nil
  end

  def self.loaded?
    @@lib != nil && @@context != 0
  end

  def initialize(frequency, framesize, hrtf: nil)
    fail(RuntimeError, "SteamAudio not loaded") if !SteamAudio.loaded?
    @profile = hrtf
    @frequency = frequency.to_i
    @samples = (@frequency * framesize.to_f / 1000.0).to_i
    @samples = 1 if @samples <= 0
    @effects = []
    @mutex = Mutex.new
    @loaded = false
    init
    @@instances << self
  end

  def init
    @audio_settings = SteamAudio.audio_settings(@frequency, @samples)
    @hrtf_handle = SteamAudio.pointer_buffer
    result = @@hrtf_mutex.synchronize { @@iplHRTFCreate.call(@@context, @audio_settings, SteamAudio.hrtf_settings(@profile), @hrtf_handle) }
    @hrtf = SteamAudio.pointer_value(@hrtf_handle)
    fail("SteamAudio HRTF create failed: #{result}") if result != 0 || @hrtf == 0
    @loaded = true
  end

  def add_effect(channels = 2)
    return -1 if !@loaded
    channels = [[channels.to_i, 1].max, 2].min
    @mutex.synchronize do
      effect_handle = SteamAudio.pointer_buffer
      result = @@iplBinauralEffectCreate.call(@@context, @audio_settings, SteamAudio.effect_settings(@hrtf), effect_handle)
      effect = SteamAudio.pointer_value(effect_handle)
      return -1 if result != 0 || effect == 0

      sa = SAEffect.new
      sa.handle = effect_handle
      sa.effect = effect
      sa.channels = channels
      sa.samples = @samples
      sa.bilinear = false
      sa.in_buffer = allocate_audio_buffer(channels, @samples)
      sa.out_buffer = allocate_audio_buffer(2, @samples)
      @effects << sa
      @effects.index(sa)
    end
  end

  def remove_effect(index)
    @mutex.synchronize do
      sa = @effects[index] if index.is_a?(Integer)
      return if sa == nil
      free_effect(sa)
      @effects[index] = nil
    end
  end

  def free
    @mutex.synchronize do
      return if !@loaded
      @effects.each { |sa| free_effect(sa) if sa != nil }
      @effects.clear
      @@iplHRTFRelease.call(@hrtf_handle) if @hrtf_handle != nil && @hrtf != 0
      @hrtf_handle = nil
      @hrtf = 0
      @loaded = false
    end
    @@instances.delete(self)
  rescue Exception
    @loaded = false
    @@instances.delete(self)
  end

  def set_bilinear(effect, bilinear)
    @mutex.synchronize do
      sa = @effects[effect] if @loaded && effect.is_a?(Integer)
      sa.bilinear = (bilinear == true) if sa != nil
    end
  end

  def process(effect, audio, x, y, z, spatial_blend: 1.0)
    audio = audio.to_s.b
    @mutex.synchronize do
      return audio if !@loaded || !effect.is_a?(Integer)
      sa = @effects[effect]
      return audio if sa == nil
      frame_bytes = sa.samples * sa.channels * 4
      return audio if audio.bytesize < frame_bytes

      source = audio.byteslice(0, frame_bytes)
      out = "\0".b * (sa.samples * 2 * 4)
      params = SteamAudio.effect_params(x, y, z, @hrtf, sa.bilinear, spatial_blend)
      @@iplAudioBufferDeinterleave.call(@@context, source, sa.in_buffer)
      @@iplBinauralEffectApply.call(sa.effect, params, sa.in_buffer, sa.out_buffer)
      @@iplAudioBufferInterleave.call(@@context, sa.out_buffer, out)
      out
    end
  end

  def reset_effect(effect)
    @mutex.synchronize do
      sa = @effects[effect] if @loaded && effect.is_a?(Integer)
      Native.call(:BinauralEffectReset, sa.effect) if sa != nil
    end
  end

  def tail(effect)
    @mutex.synchronize do
      sa = @effects[effect] if @loaded && effect.is_a?(Integer)
      return "".b if sa == nil
      count = Native.call(:BinauralEffectGetTailSize, sa.effect)
      return "".b if count <= 0
      Native.call(:BinauralEffectGetTail, sa.effect, sa.out_buffer)
      output = "\0".b * (sa.samples * 2 * 4)
      @@iplAudioBufferInterleave.call(@@context, sa.out_buffer, output)
      output.byteslice(0, [count, sa.samples].min * 2 * 4)
    end
  end

  def hrtf_handle
    @hrtf
  end

  private

  def allocate_audio_buffer(channels, samples)
    buffer = SteamAudio.audio_buffer
    result = @@iplAudioBufferAllocate.call(@@context, channels.to_i, samples.to_i, buffer)
    fail("SteamAudio audio buffer allocate failed: #{result}") if result != 0
    buffer
  end

  def free_effect(sa)
    @@iplAudioBufferFree.call(@@context, sa.in_buffer) if sa.in_buffer != nil
    @@iplAudioBufferFree.call(@@context, sa.out_buffer) if sa.out_buffer != nil
    @@iplBinauralEffectRelease.call(sa.handle) if sa.handle != nil && sa.effect.to_i != 0
    sa.in_buffer = nil
    sa.out_buffer = nil
    sa.handle = nil
    sa.effect = 0
  end
end
