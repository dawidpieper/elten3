# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

unless defined?(Fiddle)
  verbose = $VERBOSE
  $VERBOSE = nil
  begin
    require "fiddle"
  ensure
    $VERBOSE = verbose
  end
end

class Sapi < SpeechOutput
  Voice = Struct.new(:id, :name, :language, :age, :gender, :vendor, :backend, :bitness) do
    def voiceid
      return "" if id == nil
      id.split(/[\\\/]/).last
    end
  end

  SPF_ASYNC = 1
  SPF_PURGEBEFORESPEAK = 2
  SPF_IS_XML = 8
  SPF_IS_NOT_XML = 16
  SPVPRI_NORMAL = 0
  STREAM_FORMAT_48KHZ_16BIT_MONO = 38
  STREAM_FREQUENCY = 48000
  STREAM_CHANNELS = 1
  FIDDLE_ABI = defined?(Fiddle::Function::STDCALL) ? Fiddle::Function::STDCALL : Fiddle::Function::DEFAULT
  KERNEL32 = Fiddle.dlopen("kernel32.dll")
  GET_USER_DEFAULT_LCID = Fiddle::Function.new(KERNEL32["GetUserDefaultLCID"], [], Fiddle::TYPE_INT, FIDDLE_ABI)

  class << self
    def available?
      ensure_win32ole
    end

    def voice
      return nil unless available?
      @voice ||= begin
        instance = WIN32OLE.new("SAPI.SpVoice")
        instance.Priority = SPVPRI_NORMAL rescue nil
        negotiate_native_audio_format(instance)
        @voice_id = instance.Voice.Id.to_s rescue nil
        instance
      end
    rescue Exception
      nil
    end

    def speak(text)
      speak_with_flags(text.to_s, SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML)
    end

    def speak_ssml(text, interrupt: true)
      flags = SPF_ASYNC | SPF_IS_XML
      flags |= SPF_PURGEBEFORESPEAK if interrupt
      speak_with_flags(text.to_s, flags)
    end

    def stop
      if @voice_backend == :bridge
        @paused = false
        return SapiBridge.stop ? 0 : 1
      end
      return 1 if voice == nil
      @paused = false
      voice.Speak("", SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML)
      0
    rescue Exception
      1
    end

    def reset
      if @voice_backend != :bridge
        begin
          @voice.Speak("", SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML) if @voice != nil
        rescue Exception
        end
      end
      @voice = nil
      if defined?(SapiBridge) && @voice_backend == :bridge
        SapiBridge.release
      end
      @paused = false
      @voice_backend = nil
      native_voice = voice
      @voice_backend = :native if native_voice != nil
      @voice_id = native_voice.Voice.Id.to_s rescue nil if native_voice != nil
      return 1 if native_voice == nil
      reapply_device
      set_rate(@rate) if @rate != nil
      set_volume(@volume) if @volume != nil
      0
    rescue Exception
      1
    end

    def set_paused(paused)
      if @voice_backend == :bridge
        result = paused ? SapiBridge.pause : SapiBridge.resume
        @paused = paused if result
        return result ? 0 : 1
      end
      return 1 if voice == nil
      if paused
        voice.Pause
        @paused = true
      else
        voice.Resume
        @paused = false
      end
      0
    rescue Exception
      1
    end

    alias pause set_paused

    def paused?
      @paused == true
    end

    def speaking?
      if @voice_backend == :bridge
        status = SapiBridge.status
        return status != nil && status[:speaking] == true
      end
      return false if voice == nil
      status = voice.Status
      status != nil && status.RunningState.to_i == 2
    rescue Exception
      false
    end

    def set_rate(rate)
      @rate = rate.to_i
      voice.Rate = (rate.to_i / 5 - 10) if @voice_backend != :bridge && voice != nil
      SapiBridge.set_rate(rate.to_i / 5 - 10) if defined?(SapiBridge) && @voice_backend == :bridge
      rate.to_i
    rescue Exception
      rate.to_i
    end

    def rate=(rate)
      set_rate(rate)
    end

    def set_volume(volume)
      @volume = volume.to_i
      voice.Volume = volume.to_i if @voice_backend != :bridge && voice != nil
      SapiBridge.set_volume(volume.to_i) if defined?(SapiBridge) && @voice_backend == :bridge
      volume.to_i
    rescue Exception
      volume.to_i
    end

    def volume=(volume)
      set_volume(volume)
    end

    def set_voice(index)
      available = available_voices
      return 1 if voice == nil || index.to_i < 0 || index.to_i >= available.size
      selected = available[index.to_i]
      previous = voice.Voice rescue nil
      if @voice_backend == :bridge
        SapiBridge.stop
      else
        voice.Speak("", SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML) rescue nil
      end
      if selected.backend == :bridge
        return 1 unless defined?(SapiBridge) && SapiBridge.set_voice(selected.id.to_s)
        @voice_backend = :bridge
        Log.debug("Queued #{selected.bitness}-bit SAPI bridge activation for #{selected.id}") if defined?(Log)
      else
        token = voice_tokens.find { |candidate| candidate.Id.to_s.casecmp?(selected.id.to_s) }
        return 1 if token == nil
        begin
          voice.Voice = token
          negotiate_native_audio_format
          voice.Speak("", SPF_IS_NOT_XML)
        rescue Exception
          unless defined?(SapiBridge) && SapiBridge.set_voice(selected.id.to_s)
            voice.Voice = previous rescue nil if previous != nil
            return 1
          end
          @voice_backend = :bridge
          Log.debug("Queued SAPI bridge activation for #{selected.id}") if defined?(Log)
        else
          SapiBridge.release if defined?(SapiBridge)
          @voice_backend = :native
        end
      end
      @voice_index = index.to_i
      @voice_id = selected.id.to_s
      reapply_device
      set_rate(@rate) if @rate != nil
      set_volume(@volume) if @volume != nil
      0
    rescue Exception
      1
    end

    def set_device(index)
      @device_index = index.to_i
      outputs = audio_outputs
      return 2 if index.to_i >= outputs.size
      native_ok = false
      bridge_ok = false
      if index.to_i < 0
        if @voice_backend != :bridge
          begin
            voice.SetOutput(nil, false) if voice != nil
            native_ok = voice != nil
          rescue Exception
            begin
              voice.AudioOutput = nil if voice != nil
              native_ok = voice != nil
            rescue Exception
            end
          end
        end
        bridge_ok = SapiBridge.set_output(nil) if defined?(SapiBridge) && @voice_backend == :bridge
      else
        output = outputs[index.to_i]
        if @voice_backend != :bridge && voice != nil && output != nil
          begin
            voice.SetOutput(output, true)
            native_ok = true
          rescue Exception
            begin
              voice.AudioOutput = output
              native_ok = true
            rescue Exception
            end
          end
        end
        bridge_ok = SapiBridge.set_output(output.Id.to_s) if defined?(SapiBridge) && @voice_backend == :bridge && output != nil
      end
      negotiate_native_audio_format if @voice_backend != :bridge
      (@voice_backend == :bridge ? bridge_ok : native_ok) ? 0 : 1
    rescue Exception
      1
    end

    def reapply_device
      set_device(@device_index) if @device_index != nil
    end

    def bookmark
      if @voice_backend == :bridge
        status = SapiBridge.status
        return status == nil ? "" : status[:bookmark].to_s
      end
      return "" if voice == nil
      voice.Status.LastBookmark.to_s
    rescue Exception
      ""
    end

    def voice_tokens
      return [] if voice == nil
      tokens = voice.GetVoices
      (0...tokens.Count.to_i).map { |index| tokens.Item(index) }
    rescue Exception
      []
    end

    def audio_outputs
      return [] if voice == nil
      tokens = voice.GetAudioOutputs
      (0...tokens.Count.to_i).map { |index| tokens.Item(index) }
    rescue Exception
      []
    end

    def native_voices
      voice_tokens.map do |token|
        Voice.new(
          token.Id.to_s,
          token.GetDescription.to_s,
          token.GetAttribute("Language").to_s,
          token.GetAttribute("Age").to_s,
          token.GetAttribute("Gender").to_s,
          token.GetAttribute("Vendor").to_s,
          :native,
          nil
        )
      rescue Exception
        nil
      end.compact
    end

    def bridge_voices
      @bridge_voices ||= if defined?(SapiBridge)
        SapiBridge.voices.map do |voice|
          Voice.new(
            voice.id,
            voice.name,
            voice.language,
            voice.age,
            voice.gender,
            voice.vendor,
            :bridge,
            voice.bitness
          )
        end
      else
        []
      end
    rescue Exception => e
      Log.warning("Could not load bridged SAPI voices: #{e.class}: #{e.message}") if defined?(Log)
      []
    end

    def available_voices
      seen = {}
      (native_voices + bridge_voices).each_with_object([]) do |voice, result|
        id = voice.id.to_s.downcase
        next if id == "" || seen[id]
        seen[id] = true
        result << voice
      end
    end

    def voices
      available_voices.map do |voice|
        SpeechOutput::Voice.new(id: voice.voiceid, name: voice.name, output: self, native: voice)
      end
    end

    def stream_voices
      native_voices.map do |voice|
        SpeechOutput::Voice.new(id: voice.voiceid, name: voice.name, output: self, native: voice)
      end
    end

    def devices
      audio_outputs.map { |token| token.GetDescription.to_s rescue nil }.compact
    end

    def usable?
      voice != nil
    end

    def rate_supported?
      true
    end

    def volume_supported?
      true
    end

    def pitch_supported?
      true
    end

    def pause_supported?
      true
    end

    def indexed_supported?
      true
    end

    def stream_output_supported?
      ensure_win32ole && voice != nil
    end

    def render_to_stream(text, voice: nil, rate: nil, volume: nil, pitch: nil)
      raise RuntimeError, "SAPI5 is unavailable" unless ensure_win32ole
      render_voice = WIN32OLE.new("SAPI.SpVoice")
      render_stream = WIN32OLE.new("SAPI.SpMemoryStream")
      render_format = WIN32OLE.new("SAPI.SpAudioFormat")
      render_format.Type = STREAM_FORMAT_48KHZ_16BIT_MONO
      render_stream.Format = render_format
      token = voice_token_for(voice)
      render_voice.Voice = token if token != nil
      render_voice.Rate = ((rate == nil ? (@rate || 50) : rate).to_i / 5 - 10)
      render_voice.Volume = [[(volume == nil ? (@volume || 100) : volume).to_i, 0].max, 100].min
      render_voice.AudioOutputStream = render_stream
      render_voice.Speak(ssml_for(text.to_s, false, pitch || 50), SPF_IS_XML)
      pcm = ole_byte_data(render_stream.GetData)
      raise RuntimeError, "SAPI5 returned an empty audio stream" if pcm.bytesize == 0
      SpeechOutput::AudioStream.new(:pcm => pcm, :frequency => STREAM_FREQUENCY, :channels => STREAM_CHANNELS, :bits => 16)
    rescue Exception => e
      Log.warning("SAPI stream render failed: #{e.class}: #{e.message}")
      raise
    end

    def ensure_win32ole
      return true if defined?(WIN32OLE)
      verbose = $VERBOSE
      $VERBOSE = nil
      begin
        require "win32ole"
        defined?(WIN32OLE) != nil
      rescue LoadError
        false
      ensure
        $VERBOSE = verbose
      end
    end

    def apply_voice(voice)
      voice = voice.to_s
      reset
      available_voices.each_with_index do |sapi_voice, index|
        if sapi_voice.voiceid == voice
          set_voice(index)
          return true
        end
      end
      false
    end

    def apply_default_voice(lcid = current_lcid)
      available_voices.each_with_index do |sapi_voice, index|
        if sapi_voice.language.to_i(16) == lcid.to_i
          set_voice(index)
          return true
        end
      end
      false
    end

    def speak_text(text, method: 1, spelling: false, interrupt: true, pitch: 50)
      speak_ssml(ssml_for(text, spelling, pitch), interrupt: interrupt)
    end

    def speak_sequence(seq)
      seq.reset
      speak_indexed(seq.texts, seq.indexes, seq.id)
    end

    def speak_indexed(texts, indexes, id=nil)
      speak_ssml(ssml_for_indexed(texts, indexes, id))
    end

    def index
      bookmark = bookmark()
      return [nil, nil] if bookmark == nil || bookmark == ""
      bookmark = bookmark.to_s
      if bookmark.start_with?(":")
        id, index = bookmark[1..-1].to_s.split(":", 2).map { |part| part.to_i }
        [index, id]
      else
        [bookmark.to_i, $speechid]
      end
    rescue Exception
      [nil, nil]
    end

    def shutdown
      SapiBridge.shutdown if defined?(SapiBridge)
      @voice = nil
      @voice_id = nil
      @voice_backend = nil
      @paused = false
    rescue Exception
    end

    def deactivate
      SapiBridge.release if defined?(SapiBridge)
      if @voice_backend != :bridge
        begin
          @voice.Speak("", SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML) if @voice != nil
        rescue Exception
        end
      end
      @voice_backend = nil
      @paused = false
    end

    private

    def negotiate_native_audio_format(target=voice)
      return if target == nil
      target.AllowAudioOutputFormatChangesOnNextSet = true
      target.AudioOutputStream = target.AudioOutputStream
    rescue Exception
    end

    def speak_with_flags(text, flags)
      @paused = false
      if @voice_backend == :bridge
        return 0 if SapiBridge.speak(text, flags)
        return 1 if SapiBridge.failed?
        return 1 unless activate_bridge(RuntimeError.new("SAPI bridge stopped"))
        return SapiBridge.speak(text, flags) ? 0 : 1
      end
      return 1 if voice == nil
      voice.Speak(text, flags)
      0
    rescue Exception => error
      return 1 unless activate_bridge(error)
      SapiBridge.speak(text, flags) ? 0 : 1
    end

    def activate_bridge(native_error)
      return false unless defined?(SapiBridge) && @voice_id.to_s != ""
      return false unless SapiBridge.set_voice(@voice_id)
      @voice_backend = :bridge
      reapply_device
      set_rate(@rate) if @rate != nil
      set_volume(@volume) if @volume != nil
      Log.debug("Native SAPI failed, queued bridge activation for #{@voice_id}: #{native_error.class}: #{native_error.message}") if defined?(Log)
      true
    end

    def current_lcid
      GET_USER_DEFAULT_LCID.call
    rescue Exception
      0
    end

    def voice_token_for(voice)
      id = voice.respond_to?(:voiceid) ? voice.voiceid.to_s : voice.to_s
      id = configured_voice if id == "" || id == "?"
      voice_tokens.each do |token|
        native = Voice.new(
          token.Id.to_s,
          token.GetDescription.to_s,
          token.GetAttribute("Language").to_s,
          token.GetAttribute("Age").to_s,
          token.GetAttribute("Gender").to_s,
          token.GetAttribute("Vendor").to_s
        )
        return token if native.voiceid == id
      rescue Exception
      end
      nil
    end

    def ole_byte_data(data)
      return data.b if data.is_a?(String)
      return data.map { |byte| byte.to_i & 0xff }.pack("C*").b if data.is_a?(Array)
      data.to_s.b
    end

    def ssml_for(text, spelling, pitch)
      body = ssml_escape(text.to_s)
      body = "<spell>#{body}</spell>" if spelling
      "<pitch absmiddle=\"#{(((pitch || 50).to_i / 5.0) - 10.0).to_i}\"/>#{body}"
    end

    def ssml_for_indexed(texts, indexes, id)
      ssml = "<pitch absmiddle=\"#{(((Configuration.voicepitch || 50).to_i / 5.0) - 10.0).to_i}\"/>"
      texts.each_with_index do |text, index|
        ssml += "<bookmark mark=\"#{ssml_escape(bookmark_for(indexes[index], id))}\"/>"
        ssml += ssml_escape(text.to_s)
      end
      if indexes.size > texts.size
        ssml += "<bookmark mark=\"#{ssml_escape(bookmark_for(indexes[texts.size], id))}\"/>"
      end
      ssml
    end

    def bookmark_for(index, id)
      mark = ""
      mark = ":#{id}:" if id != nil
      mark + (index || "").to_s
    end

    def ssml_escape(text)
      text.gsub("<", "&lt;").gsub(">", "&gt;").gsub("\\", "\\\\")
    end
  end
end

SapiVoice = Sapi::Voice unless defined?(SapiVoice)
