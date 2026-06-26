# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

unless defined?(Fiddle)
  verbose = $VERBOSE
  $VERBOSE = nil
  begin
    require "fiddle"
    require "fiddle/closure"
  ensure
    $VERBOSE = verbose
  end
end

module OSXSpeechBridge
  PTR = Fiddle::TYPE_VOIDP
  INT = Fiddle::TYPE_INT
  UINT = Fiddle::TYPE_UINT
  FLOAT = Fiddle::TYPE_FLOAT
  DOUBLE = Fiddle::TYPE_DOUBLE
  SIZE_T = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
  PTR_SIZE = Fiddle::SIZEOF_VOIDP
  PTR_PACK = PTR_SIZE == 8 ? "Q" : "L!"
  BLOCK_HAS_SIGNATURE = 1 << 30
  BLOCK_IS_GLOBAL = 1 << 28
  AV_AUDIO_PCM_FORMAT_FLOAT32 = 1
  AV_AUDIO_PCM_FORMAT_INT16 = 3
  AV_AUDIO_PCM_FORMAT_INT32 = 4

  class << self
    def available?
      objc != nil && cls("NSSpeechSynthesizer").to_i != 0
    rescue Exception
      false
    end

    def voices
      return [] unless available?
      array = send_id(cls("NSSpeechSynthesizer"), "availableVoices")
      count = send_size(array, "count")
      result = []
      (0...count).each do |index|
        voice_id = string(send_id(array, "objectAtIndex:", index, [SIZE_T]))
        attrs = send_id(cls("NSSpeechSynthesizer"), "attributesForVoice:", nsstring(voice_id), [PTR])
        name = dict_string(attrs, "NSVoiceName", "VoiceName")
        locale = dict_string(attrs, "NSVoiceLocaleIdentifier", "VoiceLocaleIdentifier")
        name = voice_id.split(".").last.to_s if name.to_s == ""
        result << OSXSpeech::NativeVoice.new(voice_id, name, locale, :native)
      end
      result
    rescue Exception
      []
    end

    def create_synth(voice_id = nil)
      return 0 unless available?
      object = send_id(cls("NSSpeechSynthesizer"), "alloc")
      if voice_id.to_s != ""
        object = send_id(object, "initWithVoice:", nsstring(voice_id), [PTR])
      else
        object = send_id(object, "init")
      end
      install_delegate(object)
      object
    rescue Exception
      0
    end

    def set_voice(synth, voice_id)
      return false if synth.to_i == 0 || voice_id.to_s == ""
      send_bool(synth, "setVoice:", nsstring(voice_id), [PTR])
    rescue Exception
      false
    end

    def set_rate(synth, words_per_minute)
      return false if synth.to_i == 0
      send_void(synth, "setRate:", words_per_minute.to_f, [FLOAT])
      true
    rescue Exception
      false
    end

    def set_volume(synth, volume)
      return false if synth.to_i == 0
      send_void(synth, "setVolume:", volume.to_f, [FLOAT])
      true
    rescue Exception
      false
    end

    def start(synth, text)
      return false if synth.to_i == 0
      reset_events(synth)
      send_bool(synth, "startSpeakingString:", nsstring(text), [PTR])
    rescue Exception
      false
    end

    def stop(synth)
      send_void(synth, "stopSpeaking") if synth.to_i != 0
      true
    rescue Exception
      false
    end

    def pause(synth)
      return false if synth.to_i == 0
      # NSSpeechImmediateBoundary
      send_bool(synth, "pauseSpeakingAtBoundary:", 0, [INT])
    rescue Exception
      false
    end

    def resume(synth)
      return false if synth.to_i == 0
      send_bool(synth, "continueSpeaking")
    rescue Exception
      false
    end

    def speaking?(synth)
      return false if synth.to_i == 0
      send_bool(synth, "isSpeaking")
    rescue Exception
      false
    end

    def word_position(synth)
      return nil if synth.to_i == 0
      @word_positions ||= {}
      @word_positions[synth.to_i]
    rescue Exception
      nil
    end

    def finished?(synth)
      return false if synth.to_i == 0
      @finished ||= {}
      @finished[synth.to_i] == true
    rescue Exception
      false
    end

    def stream_available?
      avfoundation != nil && cls("AVSpeechSynthesizer").to_i != 0 && cls("AVSpeechUtterance").to_i != 0
    rescue Exception
      false
    end

    def render_to_stream(voice_id, text, rate, volume)
      raise RuntimeError, "AVFoundation speech synthesis is unavailable" unless stream_available?
      mutex = Mutex.new
      condition = ConditionVariable.new
      state = {
        :done => false,
        :error => nil,
        :pcm => "".b,
        :frequency => 0,
        :channels => 0
      }
      callback = make_audio_buffer_block do |buffer|
        begin
          chunk, frequency, channels, done = pcm_from_audio_buffer(buffer)
          mutex.synchronize do
            state[:done] = true if done
            if chunk != nil && chunk.bytesize > 0
              state[:frequency] = frequency if state[:frequency].to_i <= 0
              state[:channels] = channels if state[:channels].to_i <= 0
              state[:pcm] << chunk
            end
            condition.signal if done
          end
        rescue Exception => e
          mutex.synchronize do
            state[:error] = e
            state[:done] = true
            condition.signal
          end
        end
      end
      synth = send_id(cls("AVSpeechSynthesizer"), "new")
      utterance = send_id(cls("AVSpeechUtterance"), "speechUtteranceWithString:", nsstring(text.to_s), [PTR])
      if voice_id.to_s != ""
        voice = send_id(cls("AVSpeechSynthesisVoice"), "voiceWithIdentifier:", nsstring(voice_id.to_s), [PTR])
        send_void(utterance, "setVoice:", voice, [PTR]) if voice.to_i != 0
      end
      send_void(utterance, "setRate:", av_speech_rate(rate), [FLOAT])
      send_void(utterance, "setVolume:", [[volume.to_f, 0.0].max, 1.0].min, [FLOAT])
      send_void(synth, "writeUtterance:toBufferCallback:", utterance, callback[:block], [PTR, PTR])
      deadline = Time.now + render_timeout(text)
      mutex.synchronize do
        until state[:done]
          raise RuntimeError, "AVFoundation speech stream timed out" if Time.now > deadline
          condition.wait(mutex, 0.1)
        end
      end
      raise state[:error] if state[:error] != nil
      raise RuntimeError, "AVFoundation returned an empty audio stream" if state[:pcm].bytesize == 0
      SpeechOutput::AudioStream.new(
        :pcm => state[:pcm],
        :frequency => state[:frequency].to_i > 0 ? state[:frequency].to_i : 48000,
        :channels => state[:channels].to_i > 0 ? state[:channels].to_i : 1,
        :bits => 16
      )
    ensure
      @stream_keepalive ||= []
      @stream_keepalive.delete(callback) if callback != nil
    end

    private

    def objc
      return @objc if defined?(@objc)
      @appkit = Fiddle.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit")
      @objc = Fiddle.dlopen("/usr/lib/libobjc.A.dylib")
    rescue Exception
      @objc = nil
    end

    def avfoundation
      return @avfoundation if defined?(@avfoundation)
      @avfoundation = Fiddle.dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation")
    rescue Exception
      @avfoundation = nil
    end

    def objc_get_class
      @objc_get_class ||= Fiddle::Function.new(objc["objc_getClass"], [PTR], PTR)
    end

    def sel_register_name
      @sel_register_name ||= Fiddle::Function.new(objc["sel_registerName"], [PTR], PTR)
    end

    def objc_allocate_class_pair
      @objc_allocate_class_pair ||= Fiddle::Function.new(objc["objc_allocateClassPair"], [PTR, PTR, SIZE_T], PTR)
    end

    def objc_register_class_pair
      @objc_register_class_pair ||= Fiddle::Function.new(objc["objc_registerClassPair"], [PTR], Fiddle::TYPE_VOID)
    end

    def class_add_method
      @class_add_method ||= Fiddle::Function.new(objc["class_addMethod"], [PTR, PTR, PTR, PTR], INT)
    end

    def objc_msg_send(types, ret)
      @objc_msg_send ||= {}
      key = [types, ret]
      @objc_msg_send[key] ||= Fiddle::Function.new(objc["objc_msgSend"], [PTR, PTR] + types, ret)
    end

    def cls(name)
      return 0 if objc == nil
      objc_get_class.call(name.to_s)
    rescue Exception
      0
    end

    def sel(name)
      sel_register_name.call(name.to_s)
    end

    def send_id(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, PTR).call(receiver, sel(selector), *args)
    end

    def send_void(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, Fiddle::TYPE_VOID).call(receiver, sel(selector), *args)
    end

    def send_bool(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, INT).call(receiver, sel(selector), *args).to_i != 0
    end

    def send_size(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, SIZE_T).call(receiver, sel(selector), *args).to_i
    end

    def send_uint(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, UINT).call(receiver, sel(selector), *args).to_i
    end

    def send_int(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, INT).call(receiver, sel(selector), *args).to_i
    end

    def send_double(receiver, selector, *args)
      types = args.last.is_a?(Array) ? args.pop : Array.new(args.size, PTR)
      objc_msg_send(types, DOUBLE).call(receiver, sel(selector), *args).to_f
    end

    def install_delegate(synth)
      return false if synth == nil || synth.to_i == 0
      send_void(synth, "setDelegate:", speech_delegate, [PTR])
      true
    rescue Exception
      false
    end

    def speech_delegate
      return @speech_delegate if @speech_delegate != nil && @speech_delegate.to_i != 0
      klass = speech_delegate_class
      @speech_delegate = send_id(klass, "new")
      @retained_objects ||= []
      @retained_objects << @speech_delegate
      @speech_delegate
    end

    def speech_delegate_class
      return @speech_delegate_class if @speech_delegate_class != nil && @speech_delegate_class.to_i != 0
      name = "EltenSpeechDelegate_#{Process.pid}_#{object_id}"
      klass = objc_allocate_class_pair.call(cls("NSObject"), name.b + "\0", 0)
      raise "objc_allocateClassPair failed" if klass.to_i == 0
      @delegate_closures ||= []
      @delegate_closures << add_objc_method(
        klass,
        "speechSynthesizer:willSpeakWord:ofString:",
        Fiddle::TYPE_VOID,
        [PTR, PTR, PTR, SIZE_T, SIZE_T, PTR],
        "v@:@#{range_encoding}@"
      ) do |_self, _cmd, synth, location, _length, _string|
        OSXSpeechBridge.send(:record_word_position, synth, location)
      end
      @delegate_closures << add_objc_method(
        klass,
        "speechSynthesizer:didFinishSpeaking:",
        Fiddle::TYPE_VOID,
        [PTR, PTR, PTR, INT],
        "v@:@B"
      ) do |_self, _cmd, synth, finished|
        OSXSpeechBridge.send(:record_finished, synth, finished)
      end
      @delegate_closures << add_objc_method(
        klass,
        "speechSynthesizer:didEncounterErrorAtIndex:ofString:message:",
        Fiddle::TYPE_VOID,
        [PTR, PTR, PTR, SIZE_T, PTR, PTR],
        "v@:@Q@@"
      ) do |_self, _cmd, synth, index, _string, message|
        OSXSpeechBridge.send(:warning, "didEncounterError synth=#{synth.to_i} index=#{index.to_i} message=#{OSXSpeechBridge.send(:string, message)}")
      end
      objc_register_class_pair.call(klass)
      @speech_delegate_class = klass
    rescue Exception
      0
    end

    def range_encoding
      Fiddle::SIZEOF_VOIDP == 8 ? "{_NSRange=QQ}" : "{_NSRange=II}"
    end

    def add_objc_method(klass, selector_name, rettype, argtypes, encoding, &block)
      closure = Fiddle::Closure::BlockCaller.new(rettype, argtypes, &block)
      ok = class_add_method.call(klass, sel(selector_name), closure, encoding.b + "\0")
      raise "class_addMethod failed for #{selector_name}" if ok.to_i == 0
      closure
    end

    def record_word_position(synth, location)
      @word_positions ||= {}
      @word_positions[synth.to_i] = location.to_i
    rescue Exception
    end

    def record_finished(synth, finished)
      @finished ||= {}
      @finished[synth.to_i] = finished.to_i != 0
    rescue Exception
    end

    def reset_events(synth)
      @word_positions ||= {}
      @finished ||= {}
      @word_positions.delete(synth.to_i)
      @finished.delete(synth.to_i)
      true
    rescue Exception
      false
    end

    def nsstring(text)
      utf8 = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
      send_id(cls("NSString"), "stringWithUTF8String:", utf8.b + "\0", [PTR])
    end

    def make_audio_buffer_block(&block)
      closure = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_VOID, [PTR, PTR]) do |_block, buffer|
        block.call(buffer)
      end
      signature = cstring("v@?@")
      descriptor = pointer_buffer(0, block_literal_size, signature.to_i)
      literal = block_literal_buffer(ns_concrete_global_block, BLOCK_HAS_SIGNATURE | BLOCK_IS_GLOBAL, closure.to_i, descriptor.to_i)
      callback = {
        :block => literal,
        :closure => closure,
        :descriptor => descriptor,
        :signature => signature
      }
      @stream_keepalive ||= []
      @stream_keepalive << callback
      callback
    end

    def block_literal_size
      PTR_SIZE + 4 + 4 + PTR_SIZE + PTR_SIZE
    end

    def block_literal_buffer(isa, flags, invoke, descriptor)
      pointer = Fiddle::Pointer.malloc(block_literal_size)
      offset = 0
      pointer[offset, PTR_SIZE] = [isa.to_i].pack(PTR_PACK)
      offset += PTR_SIZE
      pointer[offset, 4] = [flags.to_i].pack("l")
      offset += 4
      pointer[offset, 4] = [0].pack("l")
      offset += 4
      pointer[offset, PTR_SIZE] = [invoke.to_i].pack(PTR_PACK)
      offset += PTR_SIZE
      pointer[offset, PTR_SIZE] = [descriptor.to_i].pack(PTR_PACK)
      pointer
    end

    def ns_concrete_global_block
      return @ns_concrete_global_block if @ns_concrete_global_block != nil
      handle = Fiddle.dlopen(nil)
      @ns_concrete_global_block = handle["_NSConcreteGlobalBlock"]
    rescue Exception
      @ns_concrete_global_block = Fiddle.dlopen("/usr/lib/libSystem.B.dylib")["_NSConcreteGlobalBlock"]
    end

    def cstring(text)
      bytes = text.to_s.b + "\0"
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def pointer_buffer(*values)
      size = values.size * PTR_SIZE
      pointer = Fiddle::Pointer.malloc(size)
      values.each_with_index do |value, index|
        pointer[index * PTR_SIZE, PTR_SIZE] = [value.to_i].pack(PTR_PACK)
      end
      pointer
    end

    def pcm_from_audio_buffer(buffer)
      return [nil, 0, 0, true] if buffer == nil || buffer.to_i == 0
      frames = send_uint(buffer, "frameLength")
      return [nil, 0, 0, true] if frames <= 0
      format = send_id(buffer, "format")
      frequency = send_double(format, "sampleRate").round
      channels = [[send_uint(format, "channelCount"), 1].max, 2].min
      common_format = send_int(format, "commonFormat")
      interleaved = send_bool(format, "isInterleaved")
      case common_format
      when AV_AUDIO_PCM_FORMAT_INT16
        [pcm_from_int16_buffer(buffer, frames, channels, interleaved), frequency, channels, false]
      when AV_AUDIO_PCM_FORMAT_FLOAT32
        [pcm_from_float32_buffer(buffer, frames, channels, interleaved), frequency, channels, false]
      when AV_AUDIO_PCM_FORMAT_INT32
        [pcm_from_int32_buffer(buffer, frames, channels, interleaved), frequency, channels, false]
      else
        raise RuntimeError, "Unsupported AVAudioPCMBuffer format #{common_format}"
      end
    end

    def pcm_from_int16_buffer(buffer, frames, channels, interleaved)
      table = send_id(buffer, "int16ChannelData")
      raise RuntimeError, "AVAudioPCMBuffer has no int16 channel data" if table.to_i == 0
      return Fiddle::Pointer.new(pointer_value(table, 0)).to_s(frames * channels * 2).b if interleaved
      samples = channel_samples(table, frames, channels, 2, "s<*")
      interleave_samples(samples, frames, channels) { |value| [value.to_i].pack("s<") }
    end

    def pcm_from_int32_buffer(buffer, frames, channels, interleaved)
      table = send_id(buffer, "int32ChannelData")
      raise RuntimeError, "AVAudioPCMBuffer has no int32 channel data" if table.to_i == 0
      if interleaved
        samples = Fiddle::Pointer.new(pointer_value(table, 0)).to_s(frames * channels * 4).unpack("l<*")
        return samples.map { |sample| [[sample.to_i / 65536, -32768].max, 32767].min }.pack("s<*")
      end
      samples = channel_samples(table, frames, channels, 4, "l<*")
      interleave_samples(samples, frames, channels) { |value| [[[value.to_i / 65536, -32768].max, 32767].min].pack("s<") }
    end

    def pcm_from_float32_buffer(buffer, frames, channels, interleaved)
      table = send_id(buffer, "floatChannelData")
      raise RuntimeError, "AVAudioPCMBuffer has no float channel data" if table.to_i == 0
      if interleaved
        samples = Fiddle::Pointer.new(pointer_value(table, 0)).to_s(frames * channels * 4).unpack("e*")
        return samples.map { |sample| float_to_s16(sample) }.pack("s<*")
      end
      samples = channel_samples(table, frames, channels, 4, "e*")
      interleave_samples(samples, frames, channels) { |value| [float_to_s16(value)].pack("s<") }
    end

    def channel_samples(table, frames, channels, bytes_per_sample, unpack)
      (0...channels).map do |channel|
        pointer = pointer_value(table, channel)
        Fiddle::Pointer.new(pointer).to_s(frames * bytes_per_sample).unpack(unpack)
      end
    end

    def interleave_samples(samples, frames, channels)
      pcm = +"".b
      (0...frames).each do |frame|
        (0...channels).each do |channel|
          pcm << yield(samples[channel][frame] || 0)
        end
      end
      pcm
    end

    def pointer_value(table, index)
      Fiddle::Pointer.new(table.to_i)[index * PTR_SIZE, PTR_SIZE].unpack(PTR_PACK).first.to_i
    end

    def float_to_s16(value)
      value = [[value.to_f, -1.0].max, 1.0].min
      (value * 32767.0).round
    end

    def av_speech_rate(rate)
      value = [[rate.to_i, 0].max, 100].min
      0.1 + value / 100.0 * 0.8
    end

    def render_timeout(text)
      [120.0, text.to_s.length / 15.0].max
    end

    def string(object)
      return "" if object == nil || object.to_i == 0
      pointer = send_id(object, "UTF8String")
      return "" if pointer == nil || pointer.to_i == 0
      Fiddle::Pointer.new(pointer.to_i).to_s.encode("UTF-8", invalid: :replace, undef: :replace)
    rescue Exception
      ""
    end

    def dict_string(dict, *keys)
      keys.each do |key|
        value = string(send_id(dict, "objectForKey:", nsstring(key), [PTR]))
        return value if value.to_s != ""
      end
      ""
    rescue Exception
      ""
    end

  end
end

class OSXSpeech < SpeechOutput
  NativeVoice = Struct.new(:id, :name, :language, :backend)
  DEFAULT_VOICE_ID = "default (OSX)"
  DEFAULT_VOICE_NAME = "default (OSX)"

  class << self
    def available?
      OSXSpeechBridge.available?
    end

    def usable?
      available? && voices.size > 0
    end

    def native_voices
      OSXSpeechBridge.voices
    rescue Exception
      []
    end

    def voices
      @voices ||= begin
        default_voice = SpeechOutput::Voice.new(
          id: DEFAULT_VOICE_ID,
          name: DEFAULT_VOICE_NAME,
          output: self,
          native: NativeVoice.new("", DEFAULT_VOICE_NAME, "", :default)
        )
        native = native_voices.map do |voice|
          label = voice.language.to_s == "" ? voice.name.to_s : "#{voice.name} (#{voice.language})"
          SpeechOutput::Voice.new(id: voice.id, name: label, output: self, native: voice)
        end
        [default_voice] + native
      end
    end

    def voice_for(voice)
      voice = voice.to_s
      return voices.first if voice == ""
      voices.find do |item|
        item.voiceid == voice || item.name.to_s == voice ||
          (item.native != nil && (item.native.name.to_s == voice || item.native.id.to_s == voice))
      end
    end

    def apply_voice(voice)
      selected = voice_for(voice)
      return false if selected == nil
      if selected.native != nil && selected.native.backend == :default
        @voice_id = ""
        @voice_name = ""
      else
        @voice_id = selected.native.id.to_s
        @voice_name = selected.native.name.to_s
      end
      reset_synth
      true
    end

    def set_rate(rate)
      @rate = rate.to_i
      apply_synth_settings
      @rate
    end

    def set_volume(volume)
      @volume = volume.to_i
      apply_synth_settings
      @volume
    end

    def set_paused(paused)
      return 1 unless bridge_active?
      @paused = paused == true
      @paused ? OSXSpeechBridge.pause(synth) : OSXSpeechBridge.resume(synth)
      0
    rescue Exception
      1
    end

    def paused?
      @paused == true
    end

    def stop
      @stop_requested = true
      if @indexed_thread != nil && @indexed_thread != Thread.current
        @indexed_thread.kill rescue nil
        @indexed_thread = nil
      end
      clear_index_tracking
      stop_current_backend
      @speaking = false
      @paused = false
      0
    rescue Exception
      1
    end

    def speaking?
      return true if @indexed_thread != nil && @indexed_thread.alive?
      bridge_active? && OSXSpeechBridge.speaking?(synth)
    rescue Exception
      false
    end

    def rate_supported?
      true
    end

    def volume_supported?
      OSXSpeechBridge.available?
    end

    def pitch_supported?
      false
    end

    def pause_supported?
      true
    end

    def indexed_supported?
      true
    end

    def spelling_supported?
      true
    end

    def stream_output_supported?
      OSXSpeechBridge.stream_available?
    end

    def render_to_stream(text, voice: nil, rate: nil, volume: nil, pitch: nil)
      selected = voice_for(voice.respond_to?(:voiceid) ? voice.voiceid : voice.to_s)
      voice_id = ""
      if selected != nil && selected.native != nil && selected.native.backend != :default
        voice_id = selected.native.id.to_s
      end
      OSXSpeechBridge.render_to_stream(
        voice_id,
        text.to_s,
        rate == nil ? (@rate || 50) : rate.to_i,
        volume == nil ? volume_float : [[volume.to_i, 0].max, 100].min / 100.0
      )
    end

    def speak_text(text, method: 1, spelling: false, interrupt: true, pitch: 50)
      stop if interrupt
      @stop_requested = false
      @bookmark = nil
      @bookmark_id = nil
      clear_index_tracking
      text = text.to_s.chars.join(" ") if spelling
      speak_async(text)
      0
    rescue Exception => e
      Log.warning("OSX speech failed: #{e.class}: #{e.message}")
      1
    end

    def speak_sequence(seq)
      seq.reset
      speak_indexed(seq.texts, seq.indexes, seq.id)
    end

    def speak_indexed(texts, indexes, id=nil)
      stop
      return 1 unless bridge_active?
      @stop_requested = false
      text = setup_index_tracking(texts, indexes, id)
      @bookmark = nil
      @bookmark_id = id
      speak_async(text, false)
      0
    rescue Exception => e
      Log.warning("OSX indexed speech failed: #{e.class}: #{e.message}")
      1
    end

    def index
      update_index_tracking
      normalized_index(@bookmark, @bookmark_id)
    end

    private

    def synth
      @synth ||= begin
        handle = OSXSpeechBridge.create_synth(@voice_id)
        handle = OSXSpeechBridge.create_synth(nil) if handle.to_i == 0
        apply_synth_settings(handle)
        handle
      end
    end

    def bridge_active?
      OSXSpeechBridge.available? && synth.to_i != 0
    end

    def reset_synth
      stop_current_backend
      @synth = nil
      synth if OSXSpeechBridge.available?
    end

    def apply_synth_settings(handle = nil)
      handle ||= @synth
      return false if handle == nil || handle.to_i == 0
      OSXSpeechBridge.set_voice(handle, @voice_id) if @voice_id.to_s != ""
      OSXSpeechBridge.set_rate(handle, words_per_minute)
      OSXSpeechBridge.set_volume(handle, volume_float)
      true
    rescue Exception
      false
    end

    def speak_async(text, stop_previous = true)
      stop_current_backend if stop_previous
      return false unless bridge_active?
      @paused = false
      apply_synth_settings
      OSXSpeechBridge.start(synth, text.to_s)
      true
    end

    def wait_current
      while @stop_requested != true && speaking_backend?
        sleep(0.02)
      end
    end

    def speaking_backend?
      bridge_active? && OSXSpeechBridge.speaking?(synth)
    rescue Exception
      false
    end

    def stop_current_backend
      OSXSpeechBridge.stop(@synth) if @synth != nil && @synth.to_i != 0
      true
    end

    def setup_index_tracking(texts, indexes, id)
      @indexed_offsets = []
      @indexed_last_position = nil
      @indexed_final_bookmark = nil
      speech = +""
      offset = 0
      texts.each_with_index do |text, index|
        text = text.to_s
        @indexed_offsets << [offset, bookmark_for(indexes[index], id)]
        speech << text
        offset += speech_character_length(text)
      end
      if indexes.size > texts.size
        @indexed_final_bookmark = bookmark_for(indexes[texts.size], id)
      end
      speech
    end

    def update_index_tracking
      return if @indexed_offsets == nil
      if @indexed_offsets.empty?
        @bookmark = @indexed_final_bookmark if @indexed_final_bookmark != nil && OSXSpeechBridge.finished?(synth)
        return
      end
      position = OSXSpeechBridge.word_position(synth)
      if position != nil && position != @indexed_last_position
        @indexed_last_position = position
        @bookmark = bookmark_from_offsets(position)
      elsif @indexed_final_bookmark != nil && OSXSpeechBridge.finished?(synth)
        @bookmark = @indexed_final_bookmark
      end
    rescue Exception
    end

    def clear_index_tracking
      @indexed_offsets = nil
      @indexed_last_position = nil
      @indexed_final_bookmark = nil
    end

    def bookmark_from_offsets(position)
      bookmark = @indexed_offsets.first[1]
      @indexed_offsets.each do |offset, mark|
        break if offset > position.to_i
        bookmark = mark
      end
      bookmark
    end

    def normalized_index(bookmark, fallback_id)
      return [nil, nil] if bookmark == nil || bookmark == ""
      bookmark = bookmark.to_s
      if bookmark[0..0] == ":"
        indid, ind = bookmark[1..-1].split(":").map { |n| n.to_i }
        [ind, indid]
      else
        [bookmark.to_i, fallback_id]
      end
    rescue Exception
      [nil, nil]
    end

    def speech_character_length(text)
      text.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace).bytesize / 2
    rescue Exception
      text.to_s.length
    end

    def words_per_minute
      rate = [[@rate || 50, 0].max, 100].min
      if rate <= 50
        90 + rate * 3.4
      else
        260 + (rate - 50) * 9.6
      end
    end

    def volume_float
      [[@volume || 100, 0].max, 100].min / 100.0
    end

    def bookmark_for(index, id)
      mark = ""
      mark = ":#{id}:" if id != nil
      mark + (index || "").to_s
    end

  end
end
