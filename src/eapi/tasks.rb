# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module Tasks
    class Cancelled < StandardError
    end

    class TimedOut < StandardError
    end

    class CancellationRegistration
      def initialize(token=nil, id=nil)
        @mutex = Mutex.new
        @token = token
        @id = id
      end

      def unregister
        token = nil
        id = nil
        @mutex.synchronize do
          token = @token
          id = @id
          @token = nil
          @id = nil
        end
        token == nil ? false : token.__send__(:unregister, id)
      end

      alias close unregister
    end

    class CancellationToken
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @cancelled = false
        @reason = nil
        @callbacks = {}
        @next_callback_id = 0
      end

      def cancelled?
        @mutex.synchronize { @cancelled }
      end

      def reason
        @mutex.synchronize { @reason }
      end

      def raise_if_cancelled!
        error = reason
        raise error if error != nil
        self
      end

      def wait(timeout = nil)
        deadline = timeout == nil ? nil : monotonic_time + [Float(timeout), 0.0].max
        @mutex.synchronize do
          until @cancelled
            remaining = deadline == nil ? nil : deadline - monotonic_time
            return false if remaining != nil && remaining <= 0
            @condition.wait(@mutex, remaining)
          end
          true
        end
      end

      def sleep(duration)
        raise_if_cancelled! if wait(duration)
        self
      end

      def cancel(reason=nil)
        reason = Cancelled.new("Task cancelled") if reason == nil
        reason = Cancelled.new(reason.to_s) unless reason.is_a?(Exception)
        callbacks = nil
        @mutex.synchronize do
          return false if @cancelled
          @cancelled = true
          @reason = reason
          callbacks = @callbacks.values
          @callbacks.clear
          @condition.broadcast
        end
        callbacks.each { |callback| invoke_callback(callback, reason) }
        true
      end

      def on_cancel(&callback)
        raise ArgumentError, "block is required" if callback == nil
        id = nil
        cancelled_reason = nil
        @mutex.synchronize do
          if @cancelled
            cancelled_reason = @reason
          else
            @next_callback_id += 1
            id = @next_callback_id
            @callbacks[id] = callback
          end
        end
        if id == nil
          invoke_callback(callback, cancelled_reason)
          CancellationRegistration.new
        else
          CancellationRegistration.new(self, id)
        end
      end

      private

      def invoke_callback(callback, reason)
        callback.call(reason)
      rescue Exception => error
        Log.error("Cancellation callback error: #{error.class}: #{error.message}") if defined?(Log)
      end

      def unregister(id)
        @mutex.synchronize { @callbacks.delete(id) != nil }
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    class Dispatcher
      Request = Struct.new(:callback, :response)

      def initialize(owner)
        @owner = owner
        @queue = Queue.new
      end

      def call(&callback)
        raise ArgumentError, "block is required" if callback == nil
        return callback.call if Thread.current == @owner
        response = Queue.new
        @queue << Request.new(callback, response)
        status, value = response.pop
        raise value if status == :error
        value
      end

      def drain
        loop do
          request = @queue.pop(true)
          begin
            request.response << [:ok, request.callback.call]
          rescue Exception => error
            request.response << [:error, error]
          end
        end
      rescue ThreadError
        nil
      end
    end

    class Progress
      UNSET = Object.new.freeze
      Snapshot = Struct.new(:value, :total, :message)

      def initialize(dispatcher)
        @dispatcher = dispatcher
        @mutex = Mutex.new
        @value = nil
        @total = nil
        @message = nil
        @version = 0
        @read_version = 0
      end

      def update(value = UNSET, total: UNSET, message: UNSET)
        if value.is_a?(String) && message.equal?(UNSET)
          message = value
          value = UNSET
        end
        @mutex.synchronize do
          @value = value unless value.equal?(UNSET)
          @total = total unless total.equal?(UNSET)
          @message = message unless message.equal?(UNSET)
          @version += 1
        end
        self
      end

      alias call update

      def ui(&callback)
        @dispatcher.call(&callback)
      end

      def consume
        @mutex.synchronize do
          return nil if @read_version == @version
          @read_version = @version
          Snapshot.new(@value, @total, @message)
        end
      end
    end

    class Screen
      include EltenAPI

      def initialize(title, cancellable)
        @cancellable = cancellable
        @cancelled = false
        @content = nil
        @last_spoken_at = nil
        dialog_open
        @opened = true
        type = EltenAPI::Controls::EditBox::Flags::MultiLine | EltenAPI::Controls::EditBox::Flags::ReadOnly
        @info = EltenAPI::Controls::EditBox.new(title.to_s, type: type, text: _("Please wait..."), quiet: true)
        fields = [@info]
        if @cancellable
          @cancel = EltenAPI::Controls::Button.new(_("Cancel"))
          @cancel.on(:press) { @cancelled = true }
          fields << @cancel
        end
        @form = EltenAPI::Controls::Form.new(fields, index: 0, silent: false, quiet: false)
        @form.cancel_button = @cancel if @cancel != nil
      rescue Exception
        close
        raise
      end

      def render(content)
        content = content.to_s
        return if content == @content
        @content = content
        @info.set_text(content, false)
        now = monotonic_time
        if content != "" && (@last_spoken_at == nil || now - @last_spoken_at >= 1.0 || content.match?(/(?:\A|\n)100(?:\.0)?%\z/))
          speak(content)
          @last_spoken_at = now
        end
      end

      def tick
        loop_update
        @form.update
      end

      def cancelled?
        @cancelled
      end

      def cancellation_feedback
        play_sound("cancel")
      end

      def close
        return if @opened != true
        dialog_close
      ensure
        @opened = false
      end

      private

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue Exception
        Time.now.to_f
      end
    end

    class PassiveUI
      include EltenAPI

      def initialize(form=nil)
        @form = form
      end

      def tick
        loop_update
        @form.update if @form != nil
      end
    end

    Outcome = Struct.new(:value, :error)
    private_constant :Dispatcher, :Screen, :PassiveUI, :Outcome

    class << self
      def run(title:, ui: :automatic, show_after: 0.5, cancellable: true, cancellation_token: nil, timeout: nil, &task)
        raise ArgumentError, "block is required" if task == nil
        timeout = normalize_timeout(timeout)
        show_after = normalize_show_after(show_after)
        ui = normalize_ui(ui)
        dispatcher = Dispatcher.new(Thread.current)
        progress = Progress.new(dispatcher)
        token = cancellation_token || CancellationToken.new
        raise ArgumentError, "cancellation_token must be a CancellationToken" unless token.is_a?(CancellationToken)
        token.raise_if_cancelled!
        passive_ui = PassiveUI.new(ui == :none || ui == :automatic ? nil : ui)
        screen = nil
        result = Queue.new
        runtime = current_runtime
        started_at = monotonic_time
        worker = Thread.new do
          Thread.current.report_on_exception = false
          begin
            value = with_runtime(runtime) { task.call(progress, token) }
            result << Outcome.new(value, nil)
          rescue Exception => error
            result << Outcome.new(nil, error)
          end
        end
        deadline = timeout == nil ? nil : monotonic_time + timeout
        interruption = nil

        loop do
          dispatcher.drain
          break if !worker.alive?
          if ui == :automatic && screen == nil && monotonic_time - started_at >= show_after
            screen = build_screen(title, cancellable)
          end
          render_progress(screen, progress) if screen != nil
          (screen || passive_ui).tick
          if interruption == nil && cancellable && screen != nil && screen.cancelled?
            token.cancel(Cancelled.new("Task cancelled"))
            screen.cancellation_feedback
          elsif interruption == nil && deadline != nil && monotonic_time >= deadline
            token.cancel(TimedOut.new("Task timed out after #{timeout} seconds"))
          end
          if interruption == nil && token.cancelled?
            interruption = token.reason || Cancelled.new("Task cancelled")
            interrupt(worker, interruption)
          end
          Thread.pass
        end

        worker.join
        dispatcher.drain
        render_progress(screen, progress) if screen != nil
        outcome = result.pop
        interruption ||= token.reason if token.cancelled?
        raise interruption if interruption != nil
        raise outcome.error if outcome.error != nil
        outcome.value
      ensure
        if defined?(worker) && worker != nil && worker.alive?
          token.cancel(Cancelled.new("Task cancelled")) if defined?(token) && token != nil
          worker.kill
          worker.join(0.2)
        end
        if defined?(screen) && screen != nil
          begin
            screen.close
          rescue Exception
          end
        end
      end

      private

      def build_screen(title, cancellable)
        Screen.new(title, cancellable)
      end

      def current_runtime
        Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
      end

      def format_number(value)
        rounded = value.to_f.round(1)
        rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
      end

      def format_progress(snapshot)
        parts = []
        message = snapshot.message.to_s
        parts << message if message != ""
        if snapshot.value.is_a?(Numeric)
          value = snapshot.value.to_f
          total = snapshot.total
          value = value / total.to_f * 100.0 if total.is_a?(Numeric) && total.to_f > 0
          parts << "#{format_number(value)}%"
        elsif snapshot.value != nil
          parts << snapshot.value.to_s
        end
        parts.join("\n")
      end

      def interrupt(worker, error)
        worker.raise(error.class, error.message) if worker.alive?
      rescue ThreadError
        nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def normalize_timeout(timeout)
        return nil if timeout == nil
        value = Float(timeout)
        raise ArgumentError, "timeout must be a finite number greater than zero" if !value.finite? || value <= 0
        value
      rescue TypeError, ArgumentError
        raise ArgumentError, "timeout must be a finite number greater than zero"
      end

      def normalize_show_after(show_after)
        value = Float(show_after)
        raise ArgumentError, "show_after must be a finite number greater than or equal to zero" if !value.finite? || value < 0
        value
      rescue TypeError, ArgumentError
        raise ArgumentError, "show_after must be a finite number greater than or equal to zero"
      end

      def normalize_ui(ui)
        return ui if ui == :automatic || ui == :none
        return ui if ui.respond_to?(:update)
        raise ArgumentError, "ui must be :automatic, :none or a form"
      end

      def render_progress(screen, progress)
        snapshot = progress.consume
        screen.render(format_progress(snapshot)) if snapshot != nil
      end

      def with_runtime(runtime)
        if runtime != nil && defined?(Programs) && Programs.respond_to?(:with_runtime)
          Programs.with_runtime(runtime) { yield }
        else
          yield
        end
      end
    end
  end

  include Tasks
end
