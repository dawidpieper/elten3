# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
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

module SDL2
  SDL_ABI = Fiddle::Function::DEFAULT
  F_INT = Fiddle::TYPE_INT
  F_UINT = Fiddle::TYPE_UINT
  F_PTR = Fiddle::TYPE_VOIDP
  F_VOID = Fiddle::TYPE_VOID

  # Init flags
  SDL_INIT_VIDEO = 0x00000020
  SDL_INIT_EVENTS = 0x00004000

  # Window creation
  SDL_WINDOWPOS_UNDEFINED = 0x1FFF0000
  SDL_WINDOW_HIDDEN = 0x00000008
  SDL_WINDOW_RESIZABLE = 0x00000020
  SDL_WINDOW_MINIMIZED = 0x00000040
  SDL_WINDOW_INPUT_FOCUS = 0x00000200

  # Event types
  SDL_QUIT = 0x100
  SDL_WINDOWEVENT = 0x200
  SDL_KEYDOWN = 0x300
  SDL_KEYUP = 0x301
  SDL_TEXTINPUT = 0x303

  # Window event ids
  SDL_WINDOWEVENT_MINIMIZED = 7
  SDL_WINDOWEVENT_RESTORED = 9
  SDL_WINDOWEVENT_FOCUS_GAINED = 12
  SDL_WINDOWEVENT_FOCUS_LOST = 13
  SDL_WINDOWEVENT_CLOSE = 14

  # Message box flags
  SDL_MESSAGEBOX_ERROR = 0x00000010
  SDL_MESSAGEBOX_WARNING = 0x00000020
  SDL_MESSAGEBOX_INFORMATION = 0x00000040

  # SDL_Event is a union; 56 bytes is enough on every platform, round to 64.
  EVENT_SIZE = 64

  class << self
    def available?
      handle != nil
    end

    def handle
      return @handle if defined?(@handle)
      @handle = EltenRuntimePaths.dlopen("sdl2")
    rescue Exception => e
      Log.warning("SDL2 dlopen failed: #{e.class}: #{e.message}") if defined?(Log)
      @handle = nil
    end

    def func(name, args, ret)
      Fiddle::Function.new(handle[name], args, ret, SDL_ABI)
    end
  end

  if available?
    SDL_Init = func("SDL_Init", [F_UINT], F_INT)
    SDL_InitSubSystem = func("SDL_InitSubSystem", [F_UINT], F_INT)
    SDL_Quit = func("SDL_Quit", [], F_VOID)
    SDL_GetError = func("SDL_GetError", [], F_PTR)
    SDL_CreateWindow = func("SDL_CreateWindow", [F_PTR, F_INT, F_INT, F_INT, F_INT, F_UINT], F_PTR)
    SDL_DestroyWindow = func("SDL_DestroyWindow", [F_PTR], F_VOID)
    SDL_ShowWindow = func("SDL_ShowWindow", [F_PTR], F_VOID)
    SDL_HideWindow = func("SDL_HideWindow", [F_PTR], F_VOID)
    SDL_MinimizeWindow = func("SDL_MinimizeWindow", [F_PTR], F_VOID)
    SDL_RestoreWindow = func("SDL_RestoreWindow", [F_PTR], F_VOID)
    SDL_RaiseWindow = func("SDL_RaiseWindow", [F_PTR], F_VOID)
    SDL_SetWindowTitle = func("SDL_SetWindowTitle", [F_PTR, F_PTR], F_VOID)
    SDL_GetWindowFlags = func("SDL_GetWindowFlags", [F_PTR], F_UINT)
    SDL_PumpEvents = func("SDL_PumpEvents", [], F_VOID)
    SDL_PollEvent = func("SDL_PollEvent", [F_PTR], F_INT)
    SDL_StartTextInput = func("SDL_StartTextInput", [], F_VOID)
    SDL_StopTextInput = func("SDL_StopTextInput", [], F_VOID)
    SDL_GetClipboardText = func("SDL_GetClipboardText", [], F_PTR)
    SDL_SetClipboardText = func("SDL_SetClipboardText", [F_PTR], F_INT)
    SDL_HasClipboardText = func("SDL_HasClipboardText", [], F_INT)
    SDL_free = func("SDL_free", [F_PTR], F_VOID)
    SDL_ShowSimpleMessageBox = func("SDL_ShowSimpleMessageBox", [F_UINT, F_PTR, F_PTR, F_PTR], F_INT)
  end

  class << self
    def cstring(text)
      bytes = text.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).b + "\0".b
      pointer = Fiddle::Pointer.malloc(bytes.bytesize)
      pointer[0, bytes.bytesize] = bytes
      pointer
    end

    def read_cstring(pointer)
      return "" if pointer.to_i == 0
      Fiddle::Pointer.new(pointer.to_i).to_s.force_encoding(Encoding::UTF_8)
    rescue Exception
      ""
    end

    def last_error
      read_cstring(SDL_GetError.call)
    rescue Exception
      ""
    end
  end
end
