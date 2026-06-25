# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require_relative "conferencenative"

class SteamAudio
  class SAEffect
    attr_accessor :handle, :effect, :in_buffer, :out_buffer, :channels, :samples, :bilinear
  end

  API_VERSION = 0x040000
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

  def self.pointer_buffer(value = 0)
    [value.to_i].pack(POINTER_PACK)
  end

  def self.pointer_value(buffer, offset = 0)
    chunk = buffer[offset, POINTER_SIZE] || ""
    chunk += "\0" * (POINTER_SIZE - chunk.bytesize)
    chunk.unpack1(POINTER_PACK).to_i
  end

  def self.context_settings
    if POINTER_SIZE == 8
      [API_VERSION, NULL_POINTER, NULL_POINTER, NULL_POINTER, 0, 0].pack("Lx4QQQll")
    else
      [API_VERSION, NULL_POINTER, NULL_POINTER, NULL_POINTER, 0, 0].pack("LLLLll")
    end
  end

  def self.audio_settings(frequency, samples)
    [frequency.to_i, samples.to_i].pack("ll")
  end

  def self.hrtf_settings
    if POINTER_SIZE == 8
      [DEFAULT_HRTF, NULL_POINTER, NULL_POINTER, 0, 1.0, HRTF_NORM_NONE].pack("lx4QQlflx4")
    else
      [DEFAULT_HRTF, NULL_POINTER, NULL_POINTER, 0, 1.0, HRTF_NORM_NONE].pack("lLLlfl")
    end
  end

  def self.effect_settings(hrtf)
    pointer_buffer(hrtf)
  end

  def self.effect_params(x, y, z, hrtf, bilinear)
    interpolation = bilinear ? HRTF_INTERPOLATION_BILINEAR : HRTF_INTERPOLATION_NEAREST
    if POINTER_SIZE == 8
      [x.to_f, y.to_f, z.to_f, interpolation, 1.0, hrtf.to_i, NULL_POINTER].pack("ffflfx4QQ")
    else
      [x.to_f, y.to_f, z.to_f, interpolation, 1.0, hrtf.to_i, NULL_POINTER].pack("ffflfLL")
    end
  end

  def self.audio_buffer
    "\0".b * (POINTER_SIZE == 8 ? 16 : 12)
  end

  def self.load(file = nil)
    return true if @@lib != nil
    file = "phonon" if file == nil || file.to_s == ""
    @@mutex.synchronize do
      return true if @@lib != nil
      @@lib = EltenRuntimePaths.dlopen(file)
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
    @@iplContextCreate = Fiddle::Function.new(@@lib["iplContextCreate"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplContextRelease = Fiddle::Function.new(@@lib["iplContextRelease"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplHRTFCreate = Fiddle::Function.new(@@lib["iplHRTFCreate"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplHRTFRelease = Fiddle::Function.new(@@lib["iplHRTFRelease"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplBinauralEffectCreate = Fiddle::Function.new(@@lib["iplBinauralEffectCreate"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplBinauralEffectRelease = Fiddle::Function.new(@@lib["iplBinauralEffectRelease"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplBinauralEffectApply = Fiddle::Function.new(@@lib["iplBinauralEffectApply"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplAudioBufferAllocate = Fiddle::Function.new(@@lib["iplAudioBufferAllocate"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
    @@iplAudioBufferFree = Fiddle::Function.new(@@lib["iplAudioBufferFree"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplAudioBufferDeinterleave = Fiddle::Function.new(@@lib["iplAudioBufferDeinterleave"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    @@iplAudioBufferInterleave = Fiddle::Function.new(@@lib["iplAudioBufferInterleave"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
  end

  def self.free
    @@mutex.synchronize do
      @@instances.dup.each { |instance| instance.free }
      @@instances.clear
      close_library
    end
  end

  def self.close_library
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

  def initialize(frequency, framesize)
    fail(RuntimeError, "SteamAudio not loaded") if !SteamAudio.loaded?
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
    result = @@iplHRTFCreate.call(@@context, @audio_settings, SteamAudio.hrtf_settings, @hrtf_handle)
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

  def process(effect, audio, x, y, z)
    audio = audio.to_s.b
    @mutex.synchronize do
      return audio if !@loaded || !effect.is_a?(Integer)
      sa = @effects[effect]
      return audio if sa == nil
      frame_bytes = sa.samples * sa.channels * 4
      return audio if audio.bytesize < frame_bytes

      source = audio.byteslice(0, frame_bytes)
      out = "\0".b * (sa.samples * 2 * 4)
      params = SteamAudio.effect_params(x, y, z, @hrtf, sa.bilinear)
      @@iplAudioBufferDeinterleave.call(@@context, source, sa.in_buffer)
      @@iplBinauralEffectApply.call(sa.effect, params, sa.in_buffer, sa.out_buffer)
      @@iplAudioBufferInterleave.call(@@context, sa.out_buffer, out)
      out
    end
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
