# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module InvisibleInterface
    module NativeDialogs
      PTR = Fiddle::SIZEOF_VOIDP == 8 ? Fiddle::TYPE_LONG_LONG : Fiddle::TYPE_INT
      GWL_WNDPROC = -4
      WS_OVERLAPPED = 0x00000000
      WS_CAPTION = 0x00C00000
      WS_SYSMENU = 0x00080000
      WS_VISIBLE = 0x10000000
      WS_CHILD = 0x40000000
      WS_TABSTOP = 0x00010000
      WS_VSCROLL = 0x00200000
      WS_EX_DLGMODALFRAME = 0x00000001
      SS_LEFT = 0x00000000
      ES_LEFT = 0x00000000
      ES_MULTILINE = 0x0004
      ES_AUTOVSCROLL = 0x0040
      BS_DEFPUSHBUTTON = 0x00000001
      SW_MAXIMIZE = 3
      SWP_NOSIZE = 0x0001
      SWP_NOMOVE = 0x0002
      SWP_SHOWWINDOW = 0x0040
      HWND_TOPMOST = -1
      HWND_NOTOPMOST = -2
      WM_COMMAND = 0x0111
      WM_CLOSE = 0x0010
      WM_DESTROY = 0x0002
      WM_QUIT = 0x0012
      WM_SETFOCUS = 0x0007
      WM_KEYDOWN = 0x0100
      WM_GETDLGCODE = 0x0087
      VK_ESCAPE = 0x1B
      VK_RETURN = 0x0D
      VK_TAB = 0x09
      VK_SHIFT = 0x10
      DLGC_WANTARROWS = 0x0001
      DLGC_WANTTAB = 0x0002
      DLGC_WANTALLKEYS = 0x0004
      DLGC_HASSETSEL = 0x0008
      DLGC_WANTCHARS = 0x0080
      EM_SETLIMITTEXT = 0x00C5
      EM_SETSEL = 0x00B1
      IDC_ARROW = 32512
      IDI_APPLICATION = 32512
      COLOR_WINDOW = 5
      WNDCLASS_SIZE = Fiddle::SIZEOF_VOIDP == 8 ? 80 : 48
      OPENFILENAME_SIZE = Fiddle::SIZEOF_VOIDP == 8 ? 160 : 88
      OFN_FILEMUSTEXIST = 0x00001000
      OFN_HIDEREADONLY = 0x00000004
      OFN_EXPLORER = 0x00080000

      class << self
        def open_message(title:, recipient_label:, subject_label:, text_label:, send_label:, cancel_label:, recipient: nil, subject: nil, text: nil, &block)
          fields = [
            {:id => :recipient, :label => recipient_label, :value => recipient, :required => true, :multiline => false, :max_length => 255},
            {:id => :subject, :label => subject_label, :value => subject, :required => false, :multiline => false, :max_length => 1023},
            {:id => :text, :label => text_label, :value => text, :required => true, :multiline => true, :max_length => 65_535}
          ]
          TextWindow.new(:message, title, fields, send_label, cancel_label, &block).show
        end

        def open_writer(title:, text_label:, send_label:, cancel_label:, text: nil, max_length: 500, &block)
          fields = [
            {:id => :text, :label => text_label, :value => text, :required => true, :multiline => true, :max_length => max_length.to_i}
          ]
          TextWindow.new(:writer, title, fields, send_label, cancel_label, &block).show
        end

        def open_file(title:, filters:, &block)
          thread = Thread.new do
            Thread.current.report_on_exception = false
            selected = nil
            begin
              selected = run_open_file_dialog(title, filters)
            rescue Exception => e
              Log.error("InvisibleInterface file dialog: #{e.class}: #{e.message}")
            end
            block.call(selected) if block != nil
          end
          thread.report_on_exception = false
          thread
        end

        def register(window)
          registry_mutex.synchronize { registry[window.object_id] = window }
        end

        def unregister(window)
          registry_mutex.synchronize { registry.delete(window.object_id) }
        end

        def by_hwnd(hwnd)
          hwnd = hwnd.to_i
          registry_mutex.synchronize { registry.values.find { |window| window.owns?(hwnd) } }
        end

        def dispatch(hwnd, message, wparam, lparam)
          window = by_hwnd(hwnd)
          return default_window_proc(hwnd, message, wparam, lparam) if window == nil
          window.window_proc(hwnd, message.to_i, wparam, lparam)
        end

        def dispatch_edit(hwnd, message, wparam, lparam)
          window = by_hwnd(hwnd)
          return default_window_proc(hwnd, message, wparam, lparam) if window == nil
          window.edit_proc(hwnd, message.to_i, wparam, lparam)
        end

        def ensure_api
          return if @api_ready == true
          @api_ready = true
          kernel32 = Fiddle.dlopen("kernel32")
          user32 = Fiddle.dlopen("user32")
          @get_module_handle = Fiddle::Function.new(kernel32["GetModuleHandleW"], [Fiddle::TYPE_VOIDP], PTR)
          @get_last_error = Fiddle::Function.new(kernel32["GetLastError"], [], Fiddle::TYPE_INT)
          @get_current_thread_id = Fiddle::Function.new(kernel32["GetCurrentThreadId"], [], Fiddle::TYPE_INT)
          @create_window = Fiddle::Function.new(user32["CreateWindowExW"], [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, PTR, PTR, PTR, Fiddle::TYPE_VOIDP], PTR)
          @destroy_window = Fiddle::Function.new(user32["DestroyWindow"], [PTR], Fiddle::TYPE_INT)
          @show_window = Fiddle::Function.new(user32["ShowWindow"], [PTR, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @set_window_pos = Fiddle::Function.new(user32["SetWindowPos"], [PTR, PTR, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @set_foreground_window = Fiddle::Function.new(user32["SetForegroundWindow"], [PTR], Fiddle::TYPE_INT)
          @set_active_window = Fiddle::Function.new(user32["SetActiveWindow"], [PTR], PTR)
          @set_focus = Fiddle::Function.new(user32["SetFocus"], [PTR], PTR)
          @post_message = Fiddle::Function.new(user32["PostMessageW"], [PTR, Fiddle::TYPE_INT, PTR, PTR], Fiddle::TYPE_INT)
          @post_thread_message = Fiddle::Function.new(user32["PostThreadMessageW"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, PTR, PTR], Fiddle::TYPE_INT)
          @get_foreground_window = Fiddle::Function.new(user32["GetForegroundWindow"], [], PTR)
          @get_window_thread_process_id = Fiddle::Function.new(user32["GetWindowThreadProcessId"], [PTR, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @attach_thread_input = Fiddle::Function.new(user32["AttachThreadInput"], [Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @get_message = Fiddle::Function.new(user32["GetMessageW"], [Fiddle::TYPE_VOIDP, PTR, Fiddle::TYPE_INT, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @translate_message = Fiddle::Function.new(user32["TranslateMessage"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @dispatch_message = Fiddle::Function.new(user32["DispatchMessageW"], [Fiddle::TYPE_VOIDP], PTR)
          @is_dialog_message = Fiddle::Function.new(user32["IsDialogMessageW"], [PTR, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @post_quit_message = Fiddle::Function.new(user32["PostQuitMessage"], [Fiddle::TYPE_INT], Fiddle::TYPE_VOID)
          @send_message = Fiddle::Function.new(user32["SendMessageW"], [PTR, Fiddle::TYPE_INT, PTR, PTR], PTR)
          @get_window_text = Fiddle::Function.new(user32["GetWindowTextW"], [PTR, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT)
          @get_window_text_length = Fiddle::Function.new(user32["GetWindowTextLengthW"], [PTR], Fiddle::TYPE_INT)
          @get_key_state = Fiddle::Function.new(user32["GetKeyState"], [Fiddle::TYPE_INT], Fiddle::TYPE_SHORT)
          @get_next_tab_item = Fiddle::Function.new(user32["GetNextDlgTabItem"], [PTR, PTR, Fiddle::TYPE_INT], PTR)
          @call_window_proc = Fiddle::Function.new(user32["CallWindowProcW"], [PTR, PTR, Fiddle::TYPE_INT, PTR, PTR], PTR)
          @def_window_proc = Fiddle::Function.new(user32["DefWindowProcW"], [PTR, Fiddle::TYPE_INT, PTR, PTR], PTR)
          @load_cursor = Fiddle::Function.new(user32["LoadCursorW"], [PTR, PTR], PTR)
          @load_icon = Fiddle::Function.new(user32["LoadIconW"], [PTR, PTR], PTR)
          @register_class = Fiddle::Function.new(user32["RegisterClassExW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SHORT)
          @get_open_file_name = Fiddle::Function.new(Fiddle.dlopen("comdlg32")["GetOpenFileNameW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          @set_window_long_ptr = begin
            Fiddle::Function.new(user32["SetWindowLongPtrW"], [PTR, Fiddle::TYPE_INT, PTR], PTR)
          rescue Fiddle::DLError
            Fiddle::Function.new(user32["SetWindowLongW"], [PTR, Fiddle::TYPE_INT, PTR], PTR)
          end
          @window_proc ||= Fiddle::Closure::BlockCaller.new(PTR, [PTR, Fiddle::TYPE_INT, PTR, PTR]) { |hwnd, msg, wp, lp| dispatch(hwnd, msg, wp, lp) }
          @edit_proc ||= Fiddle::Closure::BlockCaller.new(PTR, [PTR, Fiddle::TYPE_INT, PTR, PTR]) { |hwnd, msg, wp, lp| dispatch_edit(hwnd, msg, wp, lp) }
        end

        def api
          ensure_api
          self
        end

        attr_reader :get_module_handle, :create_window, :destroy_window, :show_window, :set_window_pos, :set_foreground_window,
          :set_active_window, :set_focus, :post_message, :post_thread_message, :get_foreground_window, :get_window_thread_process_id, :attach_thread_input,
          :get_current_thread_id, :get_message, :translate_message, :dispatch_message, :is_dialog_message,
          :post_quit_message, :send_message, :get_window_text, :get_window_text_length, :get_key_state,
          :get_next_tab_item, :call_window_proc, :def_window_proc, :set_window_long_ptr, :window_proc, :edit_proc,
          :get_open_file_name

        def last_error
          ensure_api
          @get_last_error.call
        rescue Exception
          0
        end

        def default_window_proc(hwnd, message, wparam, lparam)
          ensure_api
          @def_window_proc.call(hwnd, message, wparam, lparam)
        end

        def wide(text)
          (text.to_s.encode("UTF-16LE", invalid: :replace, undef: :replace) + [0].pack("S").force_encoding("UTF-16LE")).b
        end

        def read_wide_buffer(buffer)
          nul = buffer.index("\0\0")
          nul += 1 if nul != nil && nul.odd?
          bytes = nul == nil ? buffer : buffer.byteslice(0, nul)
          bytes.to_s.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
        rescue Exception
          ""
        end

        def register_dialog_class
          ensure_api
          return true if @class_registered == true
          @class_name = wide("EltenInvisibleInterfaceDialog")
          wc = "\0" * WNDCLASS_SIZE
          EltenWin32.set_dword(wc, 0, WNDCLASS_SIZE)
          EltenWin32.set_pointer(wc, Fiddle::SIZEOF_VOIDP == 8 ? 8 : 8, @window_proc)
          if Fiddle::SIZEOF_VOIDP == 8
            EltenWin32.set_pointer(wc, 24, @get_module_handle.call(nil))
            EltenWin32.set_pointer(wc, 32, @load_icon.call(0, IDI_APPLICATION))
            EltenWin32.set_pointer(wc, 40, @load_cursor.call(0, IDC_ARROW))
            EltenWin32.set_pointer(wc, 48, COLOR_WINDOW + 1)
            EltenWin32.set_pointer(wc, 64, @class_name)
            EltenWin32.set_pointer(wc, 72, @load_icon.call(0, IDI_APPLICATION))
          else
            EltenWin32.set_pointer(wc, 20, @get_module_handle.call(nil))
            EltenWin32.set_pointer(wc, 24, @load_icon.call(0, IDI_APPLICATION))
            EltenWin32.set_pointer(wc, 28, @load_cursor.call(0, IDC_ARROW))
            EltenWin32.set_pointer(wc, 32, COLOR_WINDOW + 1)
            EltenWin32.set_pointer(wc, 40, @class_name)
            EltenWin32.set_pointer(wc, 44, @load_icon.call(0, IDI_APPLICATION))
          end
          @register_class.call(wc)
          @class_registered = true
        end

        def class_name
          register_dialog_class
          @class_name
        end

        def run_open_file_dialog(title, filters)
          ensure_api
          file_buffer = "\0" * (32_768 * 2)
          filter_buffer = file_filter(filters)
          title_buffer = wide(title)
          ofn = "\0" * OPENFILENAME_SIZE
          EltenWin32.set_dword(ofn, 0, OPENFILENAME_SIZE)
          if Fiddle::SIZEOF_VOIDP == 8
            EltenWin32.set_pointer(ofn, 8, ($wnd != nil) ? $wnd : 0)
            EltenWin32.set_pointer(ofn, 24, filter_buffer)
            EltenWin32.set_pointer(ofn, 48, file_buffer)
            EltenWin32.set_dword(ofn, 56, 32_768)
            EltenWin32.set_pointer(ofn, 88, title_buffer)
            EltenWin32.set_dword(ofn, 96, OFN_FILEMUSTEXIST | OFN_HIDEREADONLY | OFN_EXPLORER)
          else
            EltenWin32.set_pointer(ofn, 4, ($wnd != nil) ? $wnd : 0)
            EltenWin32.set_pointer(ofn, 12, filter_buffer)
            EltenWin32.set_pointer(ofn, 28, file_buffer)
            EltenWin32.set_dword(ofn, 32, 32_768)
            EltenWin32.set_pointer(ofn, 48, title_buffer)
            EltenWin32.set_dword(ofn, 52, OFN_FILEMUSTEXIST | OFN_HIDEREADONLY | OFN_EXPLORER)
          end
          return nil if @get_open_file_name.call(ofn) == 0
          read_wide_buffer(file_buffer)
        end

        def file_filter(filters)
          entries = []
          filters.each do |filter|
            entries << filter[0].to_s
            entries << filter[1..-1].flatten.map(&:to_s).join(";")
          end
          entries << "All files" << "*.*"
          (entries.join("\0").encode("UTF-16LE", invalid: :replace, undef: :replace) + [0, 0].pack("SS").force_encoding("UTF-16LE")).b
        end

        def close_all
          windows = registry_mutex.synchronize { registry.values.dup }
          windows.each { |window| window.close_async rescue nil }
          windows.each { |window| window.wait_closed(0.2) rescue nil }
          windows.each { |window| window.force_close rescue nil }
        end

        private

        def registry
          @registry ||= {}
        end

        def registry_mutex
          @registry_mutex ||= Mutex.new
        end
      end

      class TextWindow
        def initialize(kind, title, fields, send_label, cancel_label, &block)
          @kind = kind
          @title = title.to_s
          @fields = fields
          @send_label = send_label.to_s
          @cancel_label = cancel_label.to_s
          @callback = block
          @hwnds = []
          @edit_previous = {}
          @accepted = false
          @closed = false
          @edit_restored = false
        end

        def show
          NativeDialogs.register(self)
          @thread = Thread.new { run }
          @thread.report_on_exception = false
          self
        end

        def close_async
          hwnd = @hwnd == nil ? 0 : @hwnd.to_i
          tid = thread_id
          if hwnd != 0
            NativeDialogs.api.post_message.call(hwnd, WM_CLOSE, 0, 0)
          elsif tid != 0
            NativeDialogs.api.post_thread_message.call(tid, WM_QUIT, 0, 0)
          end
        rescue Exception
        end

        def force_close
          close_async
          tid = thread_id
          NativeDialogs.api.post_thread_message.call(tid, WM_QUIT, 0, 0) if tid != 0
          @thread.kill if @thread != nil && @thread.alive?
        rescue Exception
        end

        def wait_closed(timeout=0.2)
          return true if @thread == nil || @thread == Thread.current || !@thread.alive?
          @thread.join(timeout)
          !@thread.alive?
        rescue Exception
          false
        end

        def owns?(hwnd)
          hwnd = hwnd.to_i
          current = @hwnd == nil ? 0 : @hwnd.to_i
          current == hwnd || @hwnds.include?(hwnd)
        end

        def window_proc(hwnd, message, wparam, lparam)
          case message
          when WM_SETFOCUS
            NativeDialogs.api.set_focus.call(@focus_hwnd.to_i != 0 ? @focus_hwnd : first_edit)
            0
          when WM_COMMAND
            source = lparam.to_i
            if source == @cancel_button.to_i
              close(false)
              0
            elsif source == @send_button.to_i
              submit
              0
            else
              NativeDialogs.default_window_proc(hwnd, message, wparam, lparam)
            end
          when WM_CLOSE
            close(false)
            0
          when WM_DESTROY
            finish_destroy
            0
          else
            NativeDialogs.default_window_proc(hwnd, message, wparam, lparam)
          end
        rescue Exception
          0
        end

        def edit_proc(hwnd, message, wparam, lparam)
          case message
          when WM_GETDLGCODE
            DLGC_WANTCHARS | DLGC_HASSETSEL | DLGC_WANTALLKEYS | DLGC_WANTARROWS | DLGC_WANTTAB
          when WM_SETFOCUS
            @focus_hwnd = hwnd.to_i
            call_previous(hwnd, message, wparam, lparam)
          when WM_KEYDOWN
            key = wparam.to_i
            if key == VK_ESCAPE
              close(false)
              return 0
            elsif key == VK_TAB
              reverse = (NativeDialogs.api.get_key_state.call(VK_SHIFT) & 0x8000) != 0
              next_hwnd = NativeDialogs.api.get_next_tab_item.call(@hwnd, hwnd, reverse ? 1 : 0)
              NativeDialogs.api.set_focus.call(next_hwnd) if next_hwnd.to_i != 0
              return 0
            elsif key == VK_RETURN && (NativeDialogs.api.get_key_state.call(VK_SHIFT) & 0x8000) == 0
              submit
              return 0
            end
            call_previous(hwnd, message, wparam, lparam)
          else
            call_previous(hwnd, message, wparam, lparam)
          end
        rescue Exception
          0
        end

        private

        def thread_id
          @thread_id == nil ? 0 : @thread_id.to_i
        rescue Exception
          0
        end

        def run
          api = NativeDialogs.api
          @thread_id = api.get_current_thread_id.call
          api.class_name
          return if create_controls(api) != true
          focus_window(api)
          message_loop(api)
        rescue Exception => e
          @callback.call(:error, e) if @callback != nil
        ensure
          cleanup_window
          NativeDialogs.unregister(self)
        end

        def create_controls(api)
          @hwnd = api.create_window.call(WS_EX_DLGMODALFRAME, api.class_name, NativeDialogs.wide(@title), WS_VISIBLE | WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, -2147483648, -2147483648, 640, 480, 0, 0, api.get_module_handle.call(nil), nil)
          if @hwnd.to_i == 0
            Log.error("InvisibleInterface dialog create failed: #{@title} error=#{api.last_error}")
            @callback.call(:error, RuntimeError.new("Cannot create dialog window")) if @callback != nil
            return false
          end
          y = 20
          @field_hwnds = {}
          @fields.each do |field|
            label_height = field[:multiline] ? 36 : 28
            edit_height = field[:multiline] ? (@fields.size == 1 ? 350 : 210) : 28
            label = api.create_window.call(0, NativeDialogs.wide("STATIC"), NativeDialogs.wide(field[:label]), WS_CHILD | WS_VISIBLE | SS_LEFT, 20, y, 190, label_height, @hwnd, 0, api.get_module_handle.call(nil), nil)
            edit_style = WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_LEFT
            edit_style |= ES_MULTILINE | ES_AUTOVSCROLL | WS_VSCROLL if field[:multiline]
            edit = api.create_window.call(0, NativeDialogs.wide("EDIT"), NativeDialogs.wide(field[:value].to_s), edit_style, 220, y, 400, edit_height, @hwnd, 0, api.get_module_handle.call(nil), nil)
            @hwnds.push(label.to_i, edit.to_i)
            @field_hwnds[field[:id]] = edit
            api.send_message.call(edit, EM_SETLIMITTEXT, field[:max_length].to_i, 0) if field[:max_length].to_i > 0
            if field[:value].to_s != ""
              len = field[:value].to_s.length
              api.send_message.call(edit, EM_SETSEL, len, len)
            end
            previous = api.set_window_long_ptr.call(edit, GWL_WNDPROC, api.edit_proc.to_i)
            @edit_previous[edit.to_i] = previous if previous.to_i != 0
            y += edit_height + 18
          end
          @send_button = api.create_window.call(0, NativeDialogs.wide("BUTTON"), NativeDialogs.wide(@send_label), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON, 20, 410, 300, 42, @hwnd, 0, api.get_module_handle.call(nil), nil)
          @cancel_button = api.create_window.call(0, NativeDialogs.wide("BUTTON"), NativeDialogs.wide(@cancel_label), WS_CHILD | WS_VISIBLE | WS_TABSTOP, 320, 410, 300, 42, @hwnd, 0, api.get_module_handle.call(nil), nil)
          @hwnds.push(@send_button.to_i, @cancel_button.to_i)
          @focus_hwnd = @fields.any? { |field| field[:value].to_s != "" } ? @field_hwnds[@fields.last[:id]] : first_edit
          api.show_window.call(@hwnd, SW_MAXIMIZE)
          api.set_focus.call(@focus_hwnd)
          true
        end

        def focus_window(api)
          return if @hwnd.to_i == 0
          current = api.get_foreground_window.call
          current_thread = api.get_window_thread_process_id.call(current, nil)
          my_thread = api.get_current_thread_id.call
          api.attach_thread_input.call(current_thread, my_thread, 1) if current_thread.to_i != 0
          api.set_window_pos.call(@hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE)
          api.set_window_pos.call(@hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE)
          api.set_foreground_window.call(@hwnd)
          api.set_active_window.call(@hwnd)
          api.set_focus.call(@focus_hwnd || first_edit)
          api.attach_thread_input.call(current_thread, my_thread, 0) if current_thread.to_i != 0
        rescue Exception
        end

        def message_loop(api)
          return if @hwnd.to_i == 0
          msg = "\0" * (Fiddle::SIZEOF_VOIDP == 8 ? 48 : 28)
          while @closed != true && api.get_message.call(msg, 0, 0, 0).to_i > 0
            if api.is_dialog_message.call(@hwnd, msg) == 0
              api.translate_message.call(msg)
              api.dispatch_message.call(msg)
            end
          end
        end

        def submit
          values = values_hash
          return if @fields.any? { |field| field[:required] && values[field[:id]].to_s.strip == "" }
          @accepted = true
          @callback.call(:submit, values) if @callback != nil
          close(true)
        end

        def close(accepted)
          return if @closed == true
          @closed = true
          @callback.call(:cancel, {}) if accepted != true && @callback != nil
          cleanup_window
          NativeDialogs.api.post_quit_message.call(0) rescue nil
        end

        def finish_destroy
          @closed = true
          @hwnd = 0
          NativeDialogs.api.post_quit_message.call(0) rescue nil
        end

        def cleanup_window
          restore_edit_procs
          hwnd = @hwnd == nil ? 0 : @hwnd.to_i
          NativeDialogs.api.destroy_window.call(hwnd) if hwnd != 0 rescue nil
          @hwnd = 0
        end

        def restore_edit_procs
          return if @edit_restored == true
          @edit_restored = true
          api = NativeDialogs.api
          @edit_previous.each do |hwnd, previous|
            api.set_window_long_ptr.call(hwnd, GWL_WNDPROC, previous) if hwnd.to_i != 0 && previous.to_i != 0
          end
        rescue Exception
        end

        def values_hash
          values = {}
          @field_hwnds.each { |id, hwnd| values[id] = window_text(hwnd) }
          values
        end

        def window_text(hwnd)
          api = NativeDialogs.api
          len = api.get_window_text_length.call(hwnd).to_i
          buffer = "\0" * ((len + 2) * 2)
          api.get_window_text.call(hwnd, buffer, len + 2)
          NativeDialogs.read_wide_buffer(buffer)
        end

        def first_edit
          @field_hwnds[@fields.first[:id]]
        end

        def call_previous(hwnd, message, wparam, lparam)
          previous = @edit_previous[hwnd.to_i]
          return NativeDialogs.default_window_proc(hwnd, message, wparam, lparam) if previous == nil || previous.to_i == 0
          NativeDialogs.api.call_window_proc.call(previous, hwnd, message, wparam, lparam)
        end
      end
    end
  end
end
