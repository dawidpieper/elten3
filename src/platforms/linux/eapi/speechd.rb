# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper, Arkadiusz Koziol
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "socket"
require "monitor"

# Pure-Ruby Speech Dispatcher (SSIP) client.
#
# libspeechd's threaded callbacks are invoked from an internal pthread, which
# crashes Ruby ("rb_thread_call_with_gvl() is called by non-ruby thread").
# Instead we speak the SSIP line protocol over the Unix socket directly and
# drain index-mark notifications on the main thread (where `index` is polled),
# mirroring how macOS polls its bookmark on the main thread.
module SpeechdBridge
  NOTIFICATION_CODES = %w[700 701 702 703 704 705].freeze
  # SSIP notification reply codes (see speech-dispatcher protocol).
  CODE_INDEX_MARK = "700"
  CODE_BEGIN = "701"
  CODE_END = "702"
  CODE_CANCEL = "703"

  # Raised when the daemon goes away. A local socket does not become closed?
  # when the peer dies - we only find out on the next read (EOF) or write
  # (EPIPE), so this is what turns that into something we can act on.
  class Disconnected < StandardError; end

  DISCONNECT_ERRORS = [Disconnected, Errno::EPIPE, Errno::ECONNRESET, Errno::ENOTCONN,
                       Errno::ECONNREFUSED, Errno::EBADF, EOFError, IOError].freeze

  # Elten runs parallel scene threads, and speech can be driven from more than
  # one of them. Without this, two threads writing commands and both draining
  # replies out of the shared @buffer would scramble the protocol while every
  # call still looked successful on our side. Monitor rather than Mutex because
  # the paths nest: send_speech -> speak_data -> command.
  LOCK = Monitor.new

  # How long a blocking read waits for the next piece of a reply. The socket is
  # local and replies come back in microseconds, so this only ever matters when
  # the daemon stops answering - and then the UI loop, which polls index and
  # speaking? every frame, must not sit here waiting.
  REPLY_TIMEOUT = 0.5

  class << self
    def available?
      connection != nil
    rescue Exception
      false
    end

    def modules
      return [] unless available?
      reply = command("LIST OUTPUT_MODULES")
      continuation_values(reply)
    rescue Exception
      []
    end

    def voices(mod = nil)
      return [] unless available?
      set_output_module(mod) if mod.to_s != ""
      reply = command("LIST SYNTHESIS_VOICES")
      continuation_values(reply).map { |line| line.split("\t") }.map { |parts| [parts[0].to_s, parts[1].to_s, parts[2].to_s] }
    rescue Exception
      []
    end

    def set_output_module(mod)
      return false if mod.to_s == "" || !available?
      apply_setting(:output_module, "OUTPUT_MODULE #{mod}")
    rescue Exception
      false
    end

    def set_synthesis_voice(name)
      return false if name.to_s == "" || !available?
      apply_setting(:synthesis_voice, "SYNTHESIS_VOICE #{name}")
    rescue Exception
      false
    end

    def set_rate(rate)
      return false unless available?
      apply_setting(:rate, "RATE #{clamp(rate)}")
    rescue Exception
      false
    end

    def set_pitch(pitch)
      return false unless available?
      apply_setting(:pitch, "PITCH #{clamp(pitch)}")
    rescue Exception
      false
    end

    def set_volume(volume)
      return false unless available?
      apply_setting(:volume, "VOLUME #{clamp(volume)}")
    rescue Exception
      false
    end

    def say(text)
      send_speech(text.to_s, false)
    end

    def say_ssml(ssml)
      send_speech(ssml.to_s, true)
    end

    # Spelling goes through SSIP CHAR rather than SPEAK: a CHAR message is
    # processed at the highest symbol level regardless of the punctuation
    # setting, which is what makes the daemon name "." or ":" instead of
    # silently dropping them.
    def say_chars(chars)
      chars = Array(chars).map { |ch| ch.to_s }
      return false if chars.empty?
      send_chars(chars)
    end

    def stop
      return false unless available?
      command("STOP self")
      @speaking = false
      true
    rescue Exception
      false
    end

    def pause
      return false unless available?
      command("PAUSE self")
      true
    rescue Exception
      false
    end

    def resume
      return false unless available?
      command("RESUME self")
      true
    rescue Exception
      false
    end

    def last_index
      pump_events
      @last_index
    rescue Exception
      @last_index
    end

    def reset_index
      @last_index = nil
      @speaking = true
    end

    def speaking?
      pump_events
      @speaking == true
    rescue Exception
      false
    end

    private

    def send_speech(data, ssml)
      deliver do
        command("SET self SSML_MODE #{ssml ? "on" : "off"}")
        speak_data(data)
      end
    end

    # SSML_MODE has to be settled before BLOCK BEGIN - inside a block SSIP only
    # accepts the message commands and a handful of SET SELF parameters.
    def send_chars(chars)
      deliver do
        command("SET self SSML_MODE off")
        spell_data(chars)
      end
    end

    # Sends one utterance, reconnecting once if the daemon died in the meantime.
    # speech-dispatcher can be restarted (or crash) under a long-running Elten,
    # and without this the client would keep writing into a dead socket forever.
    # Held across the whole utterance so the SSML_MODE switch cannot be undone by
    # another thread between setting it and sending the text it applies to.
    def deliver
      LOCK.synchronize do
        attempted_reconnect = false
        begin
          return false if connection == nil
          reset_index
          yield
        rescue *DISCONNECT_ERRORS => e
          drop_connection("speak", e)
          unless attempted_reconnect
            attempted_reconnect = true
            retry if connection != nil
          end
          false
        rescue Exception => e
          note_failure("speak", e)
          false
        end
      end
    end

    def connection
      return @socket if defined?(@socket) && @socket != nil && !@socket.closed?
      @socket = open_connection
    rescue Exception
      @socket = nil
    end

    def open_connection
      path = socket_path
      return nil if path == nil
      spawn_daemon(path) unless File.socket?(path)
      return nil unless File.socket?(path)
      sock = UNIXSocket.new(path)
      @buffer = +"".b
      @event_fields = []
      @last_index = nil
      @speaking = false
      @socket = sock
      command("SET self CLIENT_NAME elten:elten:main")
      command("SET self NOTIFICATION ALL on")
      # Covers every way we get here, not just the explicit retry in send_speech:
      # a no-op on the very first connection, a restore on any later one.
      reapply_settings
      note_recovery
      sock
    rescue Exception
      nil
    end

    # A reconnected client starts with the daemon's defaults, so the first
    # utterance after a restart would otherwise come out in the wrong voice.
    def apply_setting(key, argument)
      (@settings ||= {})[key] = argument
      ok?(command("SET self #{argument}"))
    end

    def reapply_settings
      (@settings || {}).each_value { |argument| command("SET self #{argument}") }
      true
    rescue Exception
      false
    end

    def drop_connection(context, error)
      note_failure(context, error)
      @socket.close if @socket != nil && !@socket.closed?
    rescue Exception
    ensure
      @socket = nil
      @buffer = +"".b
      @event_fields = []
      @speaking = false
    end

    # One warning per outage, not one per utterance: a dead daemon would
    # otherwise flood the log with a line for every spoken string.
    def note_failure(context, error)
      return if @failure_logged == true
      @failure_logged = true
      return unless defined?(Log)
      Log.warning("Speech Dispatcher #{context} failed: #{error.class}: #{error.message}")
    rescue Exception
    end

    def note_recovery
      return unless @failure_logged == true
      @failure_logged = false
      Log.info("Speech Dispatcher connection restored") if defined?(Log)
    rescue Exception
    end

    def socket_path
      candidates = []
      runtime = ENV["XDG_RUNTIME_DIR"].to_s
      candidates << File.join(runtime, "speech-dispatcher", "speechd.sock") if runtime != ""
      uid = Process.uid
      candidates << File.join("/run/user", uid.to_s, "speech-dispatcher", "speechd.sock")
      candidates << File.join(Dir.home, ".cache", "speech-dispatcher", "speechd.sock")
      candidates.find { |path| File.socket?(path) } || candidates.first
    rescue Exception
      nil
    end

    def spawn_daemon(_path)
      pid = Process.spawn("speech-dispatcher", "--spawn", [:out, :err] => File::NULL)
      Process.detach(pid)
      20.times do
        break if File.socket?(socket_path)
        sleep 0.1
      end
    rescue Exception
    end

    # Disconnect errors propagate to deliver, which retries once; anything
    # else is a local fault and just fails the utterance.
    # SPEAK and the data block that follows it are one indivisible exchange -
    # anything squeezed in between would be swallowed as part of the message
    # text. Monitor is reentrant, so the nested command("SPEAK") is fine.
    def speak_data(data)
      LOCK.synchronize do
        socket = connection
        return false if socket == nil
        return false unless ok?(command("SPEAK"))
        socket.write(escape_data(data) + "\r\n.\r\n")
        read_reply
        true
      rescue *DISCONNECT_ERRORS
        raise
      rescue Exception => e
        note_failure("speak", e)
        false
      end
    end

    def escape_data(data)
      lines = data.to_s.gsub("\r\n", "\n").split("\n", -1)
      lines = lines.map { |line| line.start_with?(".") ? ".#{line}" : line }
      lines.join("\r\n")
    end

    # A block keeps the whole spelling one message for the priority system and
    # for STOP; without it the characters would be separate messages and the
    # daemon's default priority would drop all but the last one.
    def spell_data(chars)
      LOCK.synchronize do
        return false if connection == nil
        return ok?(command("CHAR #{char_argument(chars[0])}")) if chars.size == 1
        return false unless ok?(command("BLOCK BEGIN"))
        chars.each { |ch| command("CHAR #{char_argument(ch)}") }
        ok?(command("BLOCK END"))
      rescue *DISCONNECT_ERRORS
        raise
      rescue Exception => e
        note_failure("spell", e)
        false
      end
    end

    # SSIP takes the character verbatim on the command line, with space as the
    # one exception it cannot represent.
    def char_argument(ch)
      ch == " " ? "space" : ch
    end

    # Locked as a unit: the write and the read of the reply it belongs to must
    # not be split by another thread, or two callers end up reading each other's
    # replies out of the shared buffer.
    def command(line)
      LOCK.synchronize do
        return [] unless @socket != nil && !@socket.closed?
        @socket.write(line.to_s + "\r\n")
        read_reply
      rescue *DISCONNECT_ERRORS => e
        drop_connection("command", e)
        []
      rescue Exception => e
        note_failure("command", e)
        []
      end
    end

    def read_reply
      reply = []
      loop do
        line = next_line(true)
        return reply if line == nil
        if NOTIFICATION_CODES.include?(line[0, 3])
          handle_notification_line(line)
          next
        end
        reply << line
        return reply if line[3, 1] == " "
      end
    end

    # Polled from the UI loop, so this is usually where a dead daemon is noticed
    # first; dropping the connection here lets the next utterance reconnect.
    # Drains pending notifications. Called from the UI loop through speaking? and
    # last_index, so it reads non-blocking and never waits on the socket; the
    # lock is still needed because it consumes from the same buffer as command.
    def pump_events
      LOCK.synchronize do
        return unless @socket != nil && !@socket.closed?
        loop do
          line = next_line(false)
          break if line == nil
          if NOTIFICATION_CODES.include?(line[0, 3])
            handle_notification_line(line)
          end
        end
      rescue *DISCONNECT_ERRORS => e
        drop_connection("notification", e)
      rescue Exception
      end
    end

    def handle_notification_line(line)
      code = line[0, 3]
      separator = line[3, 1]
      rest = line[4..-1].to_s
      if separator == "-"
        @event_fields << rest
      else
        finalize_event(code, @event_fields)
        @event_fields = []
      end
    rescue Exception
      @event_fields = []
    end

    def finalize_event(code, fields)
      case code
      when CODE_INDEX_MARK
        @last_index = fields[2].to_s
      when CODE_BEGIN
        @speaking = true
      when CODE_END, CODE_CANCEL
        @speaking = false
      end
    rescue Exception
    end

    def next_line(blocking)
      loop do
        if (index = @buffer.index("\n"))
          line = @buffer.slice!(0, index + 1)
          return line.chomp
        end
        chunk = @socket.read_nonblock(8192, exception: false)
        # nil means EOF - the daemon is gone. It must NOT be treated like
        # :wait_readable: an EOF socket always selects as readable, so the
        # blocking branch below would spin at 100% CPU forever.
        raise Disconnected, "speech-dispatcher closed the connection" if chunk == nil
        if chunk == :wait_readable
          return nil unless blocking
          return nil unless IO.select([@socket], nil, nil, REPLY_TIMEOUT)
          next
        end
        @buffer << chunk.b
      end
    rescue *DISCONNECT_ERRORS
      raise
    rescue Exception
      nil
    end

    def continuation_values(reply)
      reply.select { |line| line[3, 1] == "-" }.map { |line| line[4..-1].to_s }
    end

    def ok?(reply)
      last = reply.last.to_s
      last[0, 1] == "2"
    end

    def clamp(value)
      [[value.to_i, -100].max, 100].min
    end
  end
end
