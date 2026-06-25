# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module SpeechToFile
  class Job
    attr_reader :error

    def initialize(text, output_path, voice, rate, encoder_class, bitrate)
      @text = text.to_s
      @output_path = output_path.to_s
      @voice = voice
      @rate = rate.to_i
      @encoder_class = encoder_class
      @bitrate = bitrate
      @status = p_("EAPI_SpeechToFile", "Preparing")
      @mutex = Mutex.new
      @cancelled = false
      @done = false
    end

    def start
      @thread = Thread.new { run }
      @thread.report_on_exception = false
      self
    end

    def cancel
      @mutex.synchronize { @cancelled = true }
    end

    def cancelled?
      @mutex.synchronize { @cancelled == true }
    end

    def done?
      @mutex.synchronize { @done == true }
    end

    def status
      @mutex.synchronize { @status.to_s }
    end

    private

    def run
      output = @voice.output
      set_status(p_("EAPI_SpeechToFile", "Rendering speech"))
      stream = output.render_to_stream(
        @text,
        :voice => @voice,
        :rate => @rate,
        :volume => Configuration.voicevolume,
        :pitch => Configuration.voicepitch
      )
      raise Interrupt if cancelled?
      set_status(p_("EAPI_SpeechToFile", "Encoding audio"))
      encoder = @encoder_class.audio_encoder(@bitrate)
      raise RuntimeError, "Encoder #{@encoder_class} does not support PCM streams" if encoder == nil
      Recorder.encode_pcm_file(
        stream.pcm,
        @output_path,
        encoder,
        :frequency => stream.frequency,
        :channels => stream.channels,
        :interactive => false
      )
      set_status(p_("EAPI_SpeechToFile", "Finished"))
    rescue Interrupt
      File.delete(@output_path) rescue nil
      set_status(p_("EAPI_SpeechToFile", "Cancelled"))
    rescue Exception => e
      File.delete(@output_path) rescue nil
      @mutex.synchronize { @error = e }
      set_status("#{e.class}: #{e.message}")
      Log.error("Speech to file failed: #{e.class}: #{e.message} #{e.backtrace}")
    ensure
      @mutex.synchronize { @done = true }
    end

    def set_status(value)
      @mutex.synchronize { @status = value.to_s }
    end
  end

  class << self
    def available?
      voices.size > 0 && encoders.size > 0
    end

    def voices
      SpeechOutput.outputs.select { |output| output.stream_output_supported? }.flat_map { |output| output.stream_voices }
    rescue Exception
      []
    end

    def encoders
      MediaEncoders.list.select { |encoder| encoder::Type == :audio && encoder.const_defined?(:SupportsPcmStream) && encoder::SupportsPcmStream == true }
    rescue Exception
      []
    end

    def from_edit_box(edit)
      text = edit.get_check_or_all rescue edit.text
      prompt(text, edit.header)
    end

    def prompt(text, title = "")
      text = text.to_s
      if text.strip == ""
        alert(p_("EAPI_SpeechToFile", "There is no text to read."))
        return false
      end
      available_voices = voices
      available_encoders = encoders
      if available_voices.empty?
        alert(p_("EAPI_SpeechToFile", "No speech output can render audio to a file."))
        return false
      end
      if available_encoders.empty?
        alert(p_("EAPI_SpeechToFile", "No audio encoder is available."))
        return false
      end
      show_dialog(text, title.to_s, available_voices, available_encoders)
    end

    private

    def show_dialog(text, title, available_voices, available_encoders)
      rates = (0..100).map { |rate| "#{rate}%" }
      bitrates = [16, 24, 32, 48, 64, 96, 128, 160, 192, 256, 320]
      default_voice_index = default_voice_index(available_voices)
      default_encoder_index = default_encoder_index(available_encoders)
      filename = safe_filename(title)
      filename = p_("EAPI_SpeechToFile", "Text") if filename == ""
      filename += available_encoders[default_encoder_index]::Extension
      dialog_open
      form = EltenAPI::Controls::Form.new([
        edt_title = EltenAPI::Controls::EditBox.new(p_("EAPI_SpeechToFile", "File name"), type: 0, text: filename, quiet: true),
        lst_voice = EltenAPI::Controls::ListBox.new(available_voices.map { |voice| voice.name.to_s }, header: p_("EAPI_SpeechToFile", "Voice"), index: default_voice_index),
        lst_rate = EltenAPI::Controls::ListBox.new(rates, header: p_("EAPI_SpeechToFile", "Rate"), index: [[Configuration.voicerate.to_i, 0].max, 100].min),
        tr_path = EltenAPI::Controls::FilesTree.new(p_("EAPI_SpeechToFile", "Destination"), path: EltenPath.join(Dirs.user, "Music"), hide_files: true, quiet: true),
        lst_format = EltenAPI::Controls::ListBox.new(available_encoders.map { |encoder| "#{encoder::Name} (#{encoder::Extension})" }, header: p_("EAPI_SpeechToFile", "File format"), index: default_encoder_index),
        lst_bitrate = EltenAPI::Controls::ListBox.new(bitrates.map { |bitrate| "#{bitrate} kbps" }, header: p_("EAPI_SpeechToFile", "Bitrate"), index: bitrates.index(64) || 0),
        btn_save = EltenAPI::Controls::Button.new(_("Save")),
        btn_cancel = EltenAPI::Controls::Button.new(_("Cancel"))
      ])
      form.cancel_button = btn_cancel
      lst_format.on(:move) { apply_extension(edt_title, available_encoders[lst_format.index]::Extension) }
      edt_title.on(:change) { sync_encoder_from_extension(edt_title, lst_format, available_encoders) }
      btn_cancel.on(:press) { form.resume }
      btn_save.on(:press) do
        if edt_title.text.strip == ""
          alert(p_("EAPI_SpeechToFile", "Type a file name"))
          next
        end
        if !File.directory?(tr_path.selected(false))
          alert(p_("EAPI_SpeechToFile", "Select file location"))
          next
        end
        output_path = EltenPath.join(tr_path.selected(false), edt_title.text)
        job = Job.new(text, output_path, available_voices[lst_voice.index], lst_rate.index, available_encoders[lst_format.index], bitrates[lst_bitrate.index])
        run_job_dialog(job.start)
        alert(_("Saved")) if job.error == nil && File.file?(output_path)
        form.resume if job.error == nil
      end
      form.wait
    ensure
      dialog_close
    end

    def run_job_dialog(job)
      info = EltenAPI::Controls::EditBox.new(p_("EAPI_SpeechToFile", "Progress"), type: EltenAPI::Controls::EditBox::Flags::MultiLine | EltenAPI::Controls::EditBox::Flags::ReadOnly, text: job.status, quiet: true)
      btn_cancel = EltenAPI::Controls::Button.new(_("Cancel"))
      form = EltenAPI::Controls::Form.new([info, btn_cancel], index: 0, silent: false, quiet: true)
      form.cancel_button = btn_cancel
      btn_cancel.on(:press) do
        job.cancel
        form.resume
      end
      last_status = nil
      until job.done?
        loop_update
        form.update
        status = job.status
        if status != last_status
          info.set_text(status, false)
          last_status = status
        end
        break if key_pressed?(:key_escape)
        sleep(0.03)
      end
      job.cancel if key_pressed?(:key_escape)
      raise job.error if job.error != nil
    rescue Exception => e
      alert("#{p_("EAPI_SpeechToFile", "Reading to file failed")}: #{e.message}")
    end

    def default_voice_index(available_voices)
      configured = SpeechOutput.configured_voice
      index = available_voices.find_index { |voice| voice.voiceid == configured }
      index || 0
    end

    def default_encoder_index(available_encoders)
      available_encoders.find_index { |encoder| encoder::Extension.downcase == ".opus" } || 0
    end

    def safe_filename(title)
      title.to_s.delete("\r\n\\/:!@\#*?<>\'\"|+=`").strip.gsub(/\s+/, "_")
    end

    def apply_extension(edit, extension)
      filename = edit.text.to_s
      base = filename[0...filename.length - File.extname(filename).length]
      edit.set_text(base + extension.to_s, false)
    end

    def sync_encoder_from_extension(edit, list, available_encoders)
      extension = File.extname(edit.text.to_s).downcase
      index = available_encoders.find_index { |encoder| encoder::Extension.downcase == extension }
      list.index = index if index != nil
    end
  end
end
