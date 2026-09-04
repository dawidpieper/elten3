# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper, Arkadiusz Koziol
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class SpeechDispatcher < SpeechOutput
  NativeVoice = Struct.new(:id, :name, :language, :backend, :variant)
  DEFAULT_VOICE_ID = "default (Linux)"
  DEFAULT_VOICE_NAME = "default (Linux)"

  # Output modules that accept SSML and then never report back.
  #
  # The failure is total and unrecoverable: the message begins (701 BEGIN), no
  # index mark and no end notification ever follow, the module holds it forever,
  # and CANCEL does not tear it down - the daemon answers 213 OK while the
  # message stays stuck. Everything sent afterwards queues behind it, by every
  # client on the machine, so the user's screen reader goes silent too. Only
  # restarting speech-dispatcher clears it.
  #
  # That is also why this is a fixed list and not autodetection: probing a module
  # to find out whether it copes would be the very thing that wedges speech, with
  # no way back. We can only avoid the modules we already know about.
  #
  # Verified on rhvoice with speech-dispatcher 0.12.1: the exact same words sent
  # as plain text begin and end normally (701 + 702), while the SSML form with
  # <mark> elements begins and never ends. ~600 B with 25 marks was enough; the
  # size does not appear to matter, the markup does.
  #
  # THIS LIST WILL LIKELY NEED EXTENDING. If speech dies on one particular voice
  # and only where Elten reads with index marks - forum posts, documents, the
  # licence screen - suspect that module. tools/ssml_probe.py reproduces it in
  # isolation and shows exactly what the module reports. Add the module here, and
  # report it upstream: this is a bug in the module, we are only routing around
  # it, and the workaround costs the user index tracking on that voice.
  NO_SSML_MODULES = ["rhvoice"].freeze

  class << self
    def available?
      SpeechdBridge.available?
    end

    def usable?
      available? && voices.size > 0
    end

    def native_voices
      result = []
      SpeechdBridge.modules.each do |mod|
        SpeechdBridge.voices(mod).each do |name, language, variant|
          result << NativeVoice.new("#{mod}\t#{name}", name, language, mod, variant)
        end
      end
      result
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
          label = voice.language.to_s == "" ? "#{voice.name} (#{voice.backend})" : "#{voice.name} (#{voice.backend}, #{voice.language})"
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
        @module = ""
        @voice_name = ""
      else
        @module = selected.native.backend.to_s
        @voice_name = synthesis_voice_name(selected.native)
      end
      apply_synth_settings
      true
    end

    # Builds the SET SYNTHESIS_VOICE argument that output modules actually honour.
    #
    # Why this is such a mess: the name returned by `LIST SYNTHESIS_VOICES` does
    # NOT reliably round-trip back into `SET SYNTHESIS_VOICE`, and it differs per
    # module. Worse, `SET SYNTHESIS_VOICE` answers `209 OK` for ANY string (even
    # garbage), so the reply tells you nothing - the voice is only resolved later,
    # inside the (shared, single-process) output module. Everything below was
    # nailed down empirically from the espeak-ng module debug log and by ear on
    # rhvoice, not from any spec.
    #
    #  - espeak-ng: LIST advertises "<LanguageName>+<Variant>", e.g. "Polish+Robert".
    #    Sending that verbatim FAILS - the module ignores the variant and drops to
    #    the plain language voice ("set_language_and_voice pl -1"). Reason: the
    #    variant files on disk are lowercase ("robert") while LIST capitalises the
    #    name field ("Robert"), so the cased name does not match the file. The
    #    language CODE + variant form ("pl+Robert") works for EVERY variant
    #    regardless of case ("set synthesis voice to pl+robert"). Note Adam happens
    #    to match either way - the inconsistency is exactly why we avoid the name.
    #  - rhvoice: voices are plain names ("Natan", variant "none"); there is no
    #    "+variant" concept, so we just send the name and it works.
    #
    # And we NEVER send `SET LANGUAGE` separately: on rhvoice it overrides the
    # voice we just picked and snaps it back to the language default (audibly
    # confirmed: with LANGUAGE -> espeak fallback in Polish, without -> real Natan).
    # The voice argument already encodes the language, so LANGUAGE is pure downside.
    def synthesis_voice_name(native)
      variant = native.variant.to_s
      lang = native.language.to_s
      if variant != "" && variant.casecmp("none") != 0 && lang != ""
        "#{lang}+#{variant}"
      else
        native.name.to_s
      end
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

    def set_pitch(pitch)
      @pitch = pitch.to_i
      apply_synth_settings
      @pitch
    end

    def set_paused(paused)
      return 1 unless available?
      @paused = paused == true
      @paused ? SpeechdBridge.pause : SpeechdBridge.resume
      0
    rescue Exception
      1
    end

    def paused?
      @paused == true
    end

    def stop
      SpeechdBridge.stop
      @paused = false
      0
    rescue Exception
      1
    end

    def speaking?
      available? && SpeechdBridge.speaking?
    rescue Exception
      false
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

    # Per module, not per platform: espeak-ng handles marks correctly and keeps
    # full cursor tracking, rhvoice would hang the whole speech stack (see
    # NO_SSML_MODULES).
    def indexed_supported?
      !NO_SSML_MODULES.include?(active_module)
    end

    def spelling_supported?
      true
    end

    def stream_output_supported?
      false
    end

    def speak_text(text, method: 1, spelling: false, interrupt: true, pitch: 50)
      stop if interrupt
      @bookmark_id = nil
      apply_synth_settings
      text = text.to_s
      return SpeechdBridge.say_chars(text.chars) ? 0 : 1 if spelling && spellable?(text)
      text = text.chars.join(" ") if spelling
      # The bridge reports a dead daemon by returning false rather than raising,
      # so returning 0 unconditionally would claim success while being mute.
      SpeechdBridge.say(text) ? 0 : 1
    rescue Exception => e
      Log.warning("Linux speech failed: #{e.class}: #{e.message}") if defined?(Log)
      1
    end

    def speak_sequence(seq)
      seq.reset
      speak_indexed(seq.texts, seq.indexes, seq.id)
    end

    def speak_indexed(texts, indexes, id=nil)
      stop
      return 1 unless available?
      @bookmark_id = id
      apply_synth_settings
      # Same words, no markup. The cursor will not follow the voice on such a
      # module and embedded sounds lose their timing, but speech keeps working -
      # which beats taking the user's screen reader down with us.
      unless indexed_supported?
        @bookmark_id = nil
        return SpeechdBridge.say(texts.join(" ")) ? 0 : 1
      end
      SpeechdBridge.say_ssml(ssml_for_indexed(texts, indexes, id)) ? 0 : 1
    rescue Exception => e
      Log.warning("Linux indexed speech failed: #{e.class}: #{e.message}") if defined?(Log)
      1
    end

    def index
      normalized_index(SpeechdBridge.last_index, @bookmark_id)
    end

    private

    # CR and LF would break the framing of the CHAR command line, so those fall
    # back to being read as ordinary text.
    def spellable?(text)
      text != "" && !text.include?("\r") && !text.include?("\n")
    end

    def apply_synth_settings
      return false unless available?
      # Before any voice has been chosen - notably the first-run licence screen,
      # which runs before there is a configuration to load one from - @module is
      # empty and every message would go to whichever module the daemon picks by
      # itself ("Didn't find preferred output module, using default" in its log).
      mod = @module.to_s
      mod = default_module if mod == ""
      SpeechdBridge.set_output_module(mod) if mod != ""
      # NB: no SET LANGUAGE here on purpose (see synthesis_voice_name). The voice
      # argument encodes the language; sending LANGUAGE breaks rhvoice voice choice.
      SpeechdBridge.set_synthesis_voice(@voice_name) if @voice_name.to_s != ""
      SpeechdBridge.set_rate(spd_rate)
      SpeechdBridge.set_pitch(spd_pitch)
      SpeechdBridge.set_volume(spd_volume)
      true
    rescue Exception
      false
    end

    # The module actually in effect: the one a voice selected, or the fallback
    # used before any voice has been chosen.
    def active_module
      mod = @module.to_s
      mod = default_module if mod == ""
      mod.downcase
    rescue Exception
      ""
    end

    # Cached: resolving it costs a LIST OUTPUT_MODULES round trip and this runs
    # before every utterance.
    def default_module
      return @default_module if defined?(@default_module)
      @default_module = SpeechdBridge.modules.first.to_s
    rescue Exception
      @default_module = ""
    end

    def spd_rate
      [[@rate || 50, 0].max, 100].min * 2 - 100
    end

    def spd_pitch
      [[@pitch || 50, 0].max, 100].min * 2 - 100
    end

    def spd_volume
      [[@volume || 100, 0].max, 100].min * 2 - 100
    end

    def ssml_for_indexed(texts, indexes, id)
      ssml = +""
      texts.each_with_index do |text, index|
        ssml << "<mark name=\"#{ssml_escape(bookmark_for(indexes[index], id))}\"/>"
        ssml << ssml_escape(text.to_s)
      end
      if indexes.size > texts.size
        ssml << "<mark name=\"#{ssml_escape(bookmark_for(indexes[texts.size], id))}\"/>"
      end
      ssml
    end

    def bookmark_for(index, id)
      mark = ""
      mark = ":#{id}:" if id != nil
      mark + (index || "").to_s
    end

    def ssml_escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;")
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
  end
end
