# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class SpeechOutput
  Voice = Struct.new(:id, :name, :output, :native, keyword_init: true) do
    def voiceid
      id.to_s
    end

    def to_s
      name.to_s
    end
  end

  AudioStream = Struct.new(:pcm, :frequency, :channels, :bits, keyword_init: true) do
    def initialize(pcm:, frequency: 48000, channels: 1, bits: 16)
      super(:pcm => pcm.to_s.b, :frequency => frequency.to_i, :channels => channels.to_i, :bits => bits.to_i)
    end

    def empty?
      pcm == nil || pcm.bytesize == 0
    end
  end

  class << self
    def inherited(cls)
      SpeechOutput.outputs.push(cls) if cls != SpeechOutput && !SpeechOutput.outputs.include?(cls)
    end

    def outputs
      @outputs ||= []
    end

    def list
      outputs
    end

    def voices
      return outputs.flat_map(&:voices) if self == SpeechOutput
      []
    end

    def output_for_voice(voice)
      voice = voice.to_s
      outputs.find { |output| output.matches_voice?(voice) }
    end

    def voice_for(voice)
      voice = voice.to_s
      if self == SpeechOutput
        output = output_for_voice(voice)
        return output.voice_for(voice) if output != nil
        return nil
      end
      voices.find { |v| v.voiceid == voice }
    end

    def current_output
      output_for_voice(configured_voice) || default_output
    end

    def default_output
      outputs.find { |output| output.default? && output.voices.size > 0 } ||
        outputs.find { |output| output.voices.size > 0 }
    end

    def default_voice
      output = default_output
      output == nil ? nil : output.voices.first
    end

    def default_voice_id
      voice = default_voice
      voice == nil ? "" : voice.voiceid
    end

    def configured_voice
      Configuration.voice.to_s
    end

    def apply_current_voice
      output = current_output
      apply_configured_voice(output)
      apply_output_settings(output)
      output
    end

    def apply_current_settings
      outputs.each { |output| apply_output_settings(output) }
      apply_current_voice
    end

    def apply_output_settings(output)
      return output if output == nil
      output.set_rate(Configuration.voicerate) if output.rate_supported?
      output.set_volume(Configuration.voicevolume) if output.volume_supported?
      output.set_pitch(Configuration.voicepitch) if output.pitch_supported?
      output
    end

    def apply_configured_voice(output)
      return false if output == nil
      voice = configured_voice
      return output.apply_voice(voice) if voice != "" && voice != "?"
      return output.apply_voice(voice) if output.voice_for(voice) != nil
      return output.apply_default_voice if output.respond_to?(:apply_default_voice)
      true
    rescue Exception
      false
    end

    def available?
      true
    end

    def usable?
      available?
    end

    def default?
      usable?
    end

    def matches_voice?(voice)
      voice_for(voice) != nil
    end

    def apply_voice(_voice)
      true
    end

    def rate_supported?
      false
    end

    def volume_supported?
      false
    end

    def pitch_supported?
      false
    end

    def pause_supported?
      false
    end

    def indexed_supported?
      false
    end

    def spelling_supported?
      false
    end

    def braille_supported?
      false
    end

    def voice_dictionary_supported?
      true
    end

    def stream_output_supported?
      false
    end

    def stream_voices
      voices
    end

    def render_to_stream(_text, voice: nil, rate: nil, volume: nil, pitch: nil)
      raise NotImplementedError, "#{self} does not support speech stream output"
    end

    def set_rate(rate)
      rate.to_i
    end

    def set_volume(volume)
      volume.to_i
    end

    def set_pitch(pitch)
      pitch.to_i
    end

    def set_paused(_paused)
      1
    end

    def paused?
      false
    end

    def speaking?
      false
    end

    def stop
      1
    end

    def speak_text(_text, method: 1, spelling: false, interrupt: true, pitch: 50)
      1
    end

    def speak_sequence(seq)
      speak_text(seq.text, method: 1)
    end

    def speak_indexed(texts, indexes, id=nil)
      speak_text(texts.join, method: 1)
    end

    def index
      [nil, nil]
    end
  end
end
