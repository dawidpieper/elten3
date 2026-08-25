# Elten 3 architecture

[Back to the project README](../readme.md). See also [Building Elten 3](building.md), [Contributing to Elten 3](contributing.md), [Elten applications](eltenapps.md) and the [development roadmap](roadmap.md).

This document provides a technical map of the desktop client: its runtime model, navigation and interaction patterns, major source areas, loading order and platform boundaries. It is intended as an orientation point rather than a complete API reference.

## Runtime and process model

Most of Elten is written in Ruby. Packaged releases use a C++ launcher to initialise the bundled runtime, load embedded assets and start the application; the client can also be run directly through an external Ruby installation during development.

Elten 3 is an in-process application. The interface, EltenLink client and long-running services such as notifications, audio, calls and conferences share one Ruby runtime. This replaces the Elten 2 arrangement in which the RGSS interface and a background agent ran as separate processes. Separation in Elten 3 is primarily expressed through Ruby modules, service interfaces and platform adapters rather than process boundaries.

Platform integration is implemented through Ruby adapters, Fiddle bindings and focused bundled native libraries where necessary.

### Cross-architecture SAPI on Windows

SAPI voice and output discovery remains in Ruby through the native Windows API. Because a COM voice engine must match its host process architecture, an x64 Elten uses `bin/ext/windows/EltenSapiBridge32.exe` for x86 voices, while ARM64 may use both `EltenSapiBridge64.exe` and `EltenSapiBridge32.exe`. A bridge is started only after native voice activation fails and is closed when SAPI is no longer the active output; a missing executable silently disables only that compatibility path.

### Threads and interaction ownership

Elten has several distinct thread roles which should not be confused:

- On Windows and macOS, the native window is created on the process-start thread and the operating-system message loop remains there. `src/main.rb` is deliberately deferred and loaded on a separate Ruby application thread. On Linux, `src/main.rb` normally continues on the bootstrap thread.
- `$mainthread` names Elten's primary application and scene thread. On Windows and macOS this is not the native window-loop thread.
- The compatibility implementation of `insert_scene` may create temporary scene threads. `$currentthread` identifies the scene thread which currently owns the interactive pump; inactive scene threads wait until the controller restores them.
- Service and task workers perform bounded background work. They do not own the current form or navigation state.

The result is an ownership rule rather than a claim that every interaction runs on one physical thread. Code which creates a form owns that form on its current interaction thread. A worker may calculate, download or parse data, but should pass the result back to that owner before changing controls, `$scene` or other interaction state. `EltenAPI::Tasks.run` implements this explicitly: its task block runs on a worker, while `progress.ui { ... }` dispatches a callback to the thread which called `Tasks.run`.

Long-running services use the same pattern at a larger scale. For example, the notification service places events in a `Queue`; `loop_update` drains that queue and applies changes to `Session`, scenes and controls from the active interaction. Do not treat Ruby's shared runtime as permission for a worker to update UI state directly.

Native window ownership is a separate boundary. Portable code should call `EltenWindow` rather than invoke an operating-system window API itself. The platform adapter performs any required message pumping or cross-thread dispatch; on Windows, operations which must run on the window thread are marshalled by `EltenWindow.post_window_action`.

## UI flow and scene compatibility

Elten uses the scene dispatcher for top-level navigation and has two generations of code for the interaction inside a scene. The dispatcher is an RGSS-era compatibility design which remains the supported navigation contract. Older scene bodies often drive the UI pump themselves; newer code gives a form, task or runner explicit ownership of each local interaction.

### The `$scene` dispatcher

The outer loop in `src/main.rb` repeatedly calls `$scene.main`. A scene therefore has a behavioural contract rather than requiring a common base class: it must provide `main` and eventually replace `$scene`, return after another component has replaced it, or end the application flow.

This global dispatcher is an RGSS legacy deliberately retained so that the large body of existing scene code remains compatible. It is still valid to add scenes and to use this mechanism in new files. A more structured navigation layer may be considered in the future, but until a replacement is proposed and accepted, new scenes should follow the existing `$scene` and `insert_scene` contract rather than inventing a parallel router.

Assigning a new object to `$scene` replaces the current top-level flow; it is not a push operation and does not create an automatic history entry. Use it when the current scene has finished and the destination should become the new top-level flow. Scenes which need an explicit return destination commonly receive it through their constructor or assign it directly:

```ruby
$scene = Scene_Account_Export.new
```

The following shape is still common. The deprecated part is the manually owned `loop_update` loop, not the use of `$scene` for the final navigation decision. New code should not copy the loop merely because neighbouring scenes use it:

```ruby
loop do
  loop_update
  @form.update
  break if $scene != self
  $scene = Scene_Main.new if key_pressed?(:key_escape)
end
```

### Temporary flows with `insert_scene`

`insert_scene(scene, must = false, return_to_main: false)` is the companion compatibility mechanism. It queues a scene for the parallel scene controller instead of unconditionally discarding the current one. The controller saves the interrupted scene, runs the inserted scene chain, and normally restores the saved scene afterwards. When the main scene is active and the queue is empty, insertion is optimised to a direct `$scene` replacement.

Existing and new code may use the simple form for a temporary flow which should return to its caller:

```ruby
insert_scene(Scene_Account_Logins.new)
```

By default, an insertion is ignored when the active or next queued scene has the same class. Passing `true` as `must` bypasses that duplicate guard. `return_to_main: true` tells the controller to finish at a fresh `Scene_Main` instead of restoring the interrupted scene; notification actions use this form because the screen beneath them may no longer be a sensible return destination:

```ruby
insert_scene(
  Scene_Update_Confirmation.new(Scene_Main.new, version),
  true,
  return_to_main: true
)
```

Use direct `$scene` assignment for replacement and `insert_scene` when the interrupted scene should normally resume. Both are supported navigation operations, including in newly added scene files. Their compatibility purpose explains their global shape; it does not make their current use deprecated.

### Scene granularity

A scene should represent a meaningful navigation destination or lifetime boundary, not each individual form shown along the way. One scene may display several forms, run a task and return to an earlier form without creating intermediate `Scene_*` classes. For example, the methods below can each own a `Form#wait` or `Tasks.run` interaction while the surrounding scene retains responsibility for the complete workflow:

```ruby
def main
  loop do
    case show_overview_form
    when :edit
      show_editor_form
    when :import
      import_items
    else
      break
    end
  end
  $scene = Scene_Main.new if $scene == self
end
```

Add another scene when the destination genuinely needs an independent navigation lifetime, for example when it must replace the current destination or be inserted and later return to it. Do not split a linear workflow into scenes solely to avoid keeping several form methods in one class.

## Owning an interaction

`loop_update` is the global pump for window and input events, notifications, active controls and other in-process services. It is still essential inside the framework. What is deprecated is feature code owning an open-ended `loop_update` loop and manually coordinating control updates, scene identity and exit conditions.

Choose the smallest component which can own the complete interaction:

| Requirement | Preferred owner |
| --- | --- |
| A contained form or dialogue | `Form#wait` |
| A contained list or table | `ListBox#wait_for_item` or `TableBox#wait_for_item` |
| A finite operation which must keep the UI responsive | `EltenAPI::Tasks.run` |
| A non-form event loop with keys, actions or timers | `Runner#run` |
| A top-level transition between scenes | `$scene` or `insert_scene` |

These interfaces call `loop_update` internally. The architectural improvement is ownership: feature code declares how the interaction ends while one reusable component performs the polling and cleanup.

### What `loop_update` coordinates

One `loop_update` call is an application frame, not merely a keyboard poll. Its current responsibilities include:

- pausing and resuming compatibility scene threads so that only `$currentthread` owns the active interaction;
- ticking loaded application extensions on `$mainthread`;
- beginning the platform input frame, updating keyboard state and processing indexed speech commands;
- draining notification-service events and reflecting them in `Session`, calls, feeds and the visible interface;
- advancing alarms, the clock, conferences, the Invisible Interface and activity reporting;
- servicing the native window, tray transitions and close requests;
- updating incoming-call and missed-call overlays; and
- maintaining the active-control set and issuing focus and blur transitions.

Some work is performed on every frame and some is rate-limited internally. Feature code must not reproduce these responsibilities or replace the pump with `sleep`; doing so can stall notifications, speech, calls, focus handling or window shutdown even when the local control still appears simple. Conversely, a background worker must not call `loop_update` to make itself into another UI owner. It should report through the queue or dispatcher owned by its form, task, runner or service.

This central role is why direct feature-owned loops remain supported but deprecated, while `loop_update` itself is not deprecated. `Form#wait`, `Tasks.run` and `Runner#run` all keep the same application frame alive while giving its lifetime and cleanup to a narrower owner.

### Forms

For a contained screen or dialogue, configure the form's accept and cancel buttons, attach events, and call `wait`. Calling `resume` ends that wait; despite the method name, it is the form's normal exit signal.

```ruby
save = Button.new(_("Save"))
cancel = Button.new(_("Cancel"))
form = Form.new([settings, save, cancel], quiet: true)

form.accept_button = save
form.cancel_button = cancel
save.on(:press) do
  persist(settings)
  form.resume
end
cancel.on(:press) { form.resume }

form.wait
```

`Form#wait` centralises `loop_update` and `form.update`, while `accept_button` and `cancel_button` preserve standard Enter and Escape behaviour. This is preferable to surrounding the same form with a custom loop and inspecting `$scene` after every frame.

### Lists and tables

For a contained browser backed by one `ListBox` or `TableBox`, use `wait_for_item`. It centralises `loop_update`, control updates and focus restoration after returning from a nested interaction. Selection and expansion return the current option or row; collapse and Escape return `nil`.

```ruby
while category = categories.wait_for_item
  while question = questions.wait_for_item
    show_question(question)
  end
end
```

The standard action set is `[:select, :expand, :collapse, :escape]`. Pass an explicit subset when a browser has different navigation semantics:

```ruby
item = list.wait_for_item(actions: [:select, :escape])
```

Supported actions omitted from `actions` continue to be processed by the control without completing the wait. Unknown action names raise `ArgumentError`.

### Finite background work

Use `EltenAPI::Tasks.run` for work which may take time but has a definite result. The block runs on a worker thread, while the calling thread retains ownership of UI updates, cancellation, timeout handling and cleanup. Worker exceptions are re-raised to the caller. By default, a cancellable progress screen is opened only if the work lasts at least half a second, so short operations do not flash a dialog.

```ruby
result = EltenAPI::Tasks.run(
  title: _("Importing items"),
  timeout: 60
) do |progress, token|
  items.each_with_index do |item, index|
    token.raise_if_cancelled!
    import(item)
    progress.update(
      index + 1,
      total: items.size,
      message: item.name
    )
  end
  :complete
end
```

Set `show_after: 0` when the owned screen must be shown immediately. Pass `ui: :none` for work which should only keep the application pump responsive, or pass an existing `Form` as `ui:` to update that form without opening or closing another dialog. In the latter case the caller retains the form's complete lifecycle and may connect its controls to an explicit token:

```ruby
token = EltenAPI::Tasks::CancellationToken.new
cancel.on(:press) { token.cancel }
EltenAPI::Tasks.run(
  title: _("Importing items"),
  ui: form,
  cancellation_token: token
) do |progress, task_token|
  import_items(progress, task_token)
end
```

Use `token.sleep(duration)` rather than an ordinary `sleep` when a delay must react promptly to cancellation. Pass the token as `cancellation_token:` to EltenLink requests, file downloads or `ChildProc.new` so cancellation also interrupts the underlying operation. Do not mutate UI controls from the worker; schedule a necessary UI-thread callback through `progress.ui { ... }`.

### Event-driven non-form flows

Use `Runner` when an interaction is not naturally a form or a finite task. A runner owns its loop and provides named actions, key handlers, one-off and repeating timers, cooldowns, tick callbacks and managed-resource cleanup.

```ruby
runner = Runner.new(frame_interval: 0.05)
session_time = runner.stopwatch(pause_on_dialogs: true)
runner.action(:close, press: :escape)
runner.action(:move_left, hold: :left)
runner.on_action(:move_left, phase: :start) do
  session_time.start
  start_moving(:left)
end
runner.on_action(:move_left, phase: :update) { move(:left) }
runner.on_action(:move_left, phase: :finish) { stop_moving }
runner.on_action(:close) { |current| current.stop(:cancelled) }
runner.every(5, immediate: true) { refresh_state }

result = runner.run
elapsed = session_time.elapsed
```

Prefer named actions over scattering raw key checks across tick callbacks. Resources registered with `runner.manage` are released when `run` ends, including exceptional exits, so a runner is also the appropriate owner for a subscription or handle whose lifetime matches the interaction.

A phased action calls `start` once when it becomes active, `update` on every runner iteration while active, including the starting iteration, and `finish` once after its last bound key is released. Active actions are also finished when the runner ends. Existing `on_action` handlers without `phase:` retain their pressed or repeated behaviour. For a raw key lifecycle, use `on_key_down` and `on_key_released`; `on_key_up` is an alias for the latter, while `on_key` remains supported.

A stopwatch created with `runner.stopwatch` uses a monotonic clock and is stopped automatically when the runner ends. Pass `autostart: true` to start it immediately. Otherwise, `start` is idempotent while the stopwatch is running or paused, so an interaction may call it from every relevant action and the first action starts the measurement. Use `pause`, `resume`, `stop` and `elapsed` for explicit control. With `pause_on_dialogs: true`, time spent in nested modal dialogs and blocking alerts is excluded; non-blocking alerts do not pause the stopwatch.

## Evolution and migration policy

The newer interfaces are a direction for active development, not a request for a mechanical rewrite of every working scene. A conversion which changes only code shape has little user-visible value, creates a large review surface and can introduce subtle focus, timing, speech or navigation regressions.

Move an existing flow when a feature redesign, bug fix or substantial improvement already requires its control structure to change. The migration should then simplify ownership and remove obsolete workarounds as a consequence of useful work. Leave unrelated, functioning legacy flows alone.

New scenes remain welcome where they express a genuine navigation boundary, and they should use `$scene` and `insert_scene` until the project adopts a replacement. Inside those scenes, new code should not fall back to manual `loop_update` loops merely because a newer abstraction lacks one capability. First consider a focused pull request which adds that capability to `Form`, `Tasks`, `Runner` or another appropriate shared interface. This allows subsequent features to remain on the newer interaction path and makes the architectural improvement incremental: evolution rather than revolution.

## EltenLink communication layers

Server-facing feature code follows a layered path:

```text
scene or service
    -> EltenLink domain module
        -> EltenLink::Client
            -> EltenAPI::HTTPClient and TLS transport
                -> EltenLink JSON API
```

Modules under `src/eltenlink/` define operations and values in EltenLink terms. `EltenLink::Messages`, for example, knows how to list conversations, send messages and translate response hashes into message objects. A scene should normally call such a domain operation rather than construct a URL or interpret an API envelope itself:

```ruby
begin
  result = EltenLink::Messages.users(elten_link, limit: 50)
rescue EltenLink::Error => error
  Log.warning("Cannot load message users: #{error.code}: #{error.message}")
  alert(_("The messages could not be loaded."))
end
```

`EltenLink::Client` owns the common protocol contract. It adds session authentication, redacts credentials in diagnostic paths, submits JSON or binary requests, validates the `success` envelope, raises `EltenLink::Error`, handles timeout and cancellation, and can recover a cached response to a timed-out mutating request by its request ID. When the client has an Elten context, its synchronous wait continues to pump that context so that the interface remains responsive.

The private `elten_link` helper supplied by `EltenAPI::EltenSRV` memoises one client for its owning scene or service. `EltenLink.client(context)` uses that helper when available and otherwise constructs a client for the supplied context. Pass an existing client into domain methods; do not create a new transport object for each small operation.

`src/eapi/eltensrv/` is a compatibility and presentation facade, not another server backend. Its helpers preserve established Elten-facing method names and may add speech, alerts, default values or updates to local UI state around `EltenLink` operations. New protocol behaviour belongs in the appropriate `src/eltenlink/` domain module; shared HTTP and TLS behaviour belongs below `EltenLink::Client`; a scene-specific message or focus decision remains in the scene. Not every domain needs an `eltensrv` wrapper.

Low-level `EltenAPI::HTTPClient` entry points remain necessary for the client implementation, downloads and genuinely generic URLs. Calling them directly from an ordinary social feature would bypass the shared API error, authentication and response semantics, and should therefore be avoided.

## Repository map

| Path | Purpose |
| --- | --- |
| `elten.rb` | Top-level entry point, platform bootstrap and version information. |
| `filelist` | Ordered Ruby source manifest used by direct startup and packaged builds. |
| `src/eltenlink/` | JSON API client and resource-specific EltenLink operations. |
| `src/eapi/` | Shared configuration, networking, speech, audio, tasks, resources, application packages and extensions. |
| `src/ui/` | Audio-first forms, controls, input handling, dialogs and the main UI loop. |
| `src/scenes/` | User-facing workflows such as authentication, forums, messages, conferences, settings and updates. |
| `src/platforms/` | Windows, Linux and macOS implementations of platform-dependent services. |
| `src/ri/` | Runtime-interface helpers and native structures shared across platforms. |
| `launcher/` | C++ launcher, platform facades, integrity support and embedded-asset generator. |
| `cmake/` and `CMakeLists.txt` | Runtime preparation, embedding, packaging and release assembly. |
| `bin/` | Architecture-specific native libraries shipped with Elten. |
| `audio/` and `resources/` | Interface sounds and application resources. |
| `locale/` | Gettext template and localised user documentation. |
| `tools/` | Contributor and release utilities. |

## Source loading and `filelist`

The order in `filelist` is significant. Adding a Ruby file under `src/` is not sufficient on its own: add it to `filelist` in the correct dependency order. Entries may carry platform tags such as `:windows`, `:linux` or `:osx`; use one when a source file is not portable.

A missing or misplaced entry may remain unnoticed during an ad-hoc test yet fail in an embedded release. Check both the direct Ruby path and the packaged launcher path whenever a change affects bootstrap or loading.

## Platform boundaries

Portable application behaviour belongs in the shared `src/eltenlink/`, `src/eapi/`, `src/ui/` and `src/scenes/` layers. Operating-system-specific implementations belong under `src/platforms/`; common runtime structures and helpers shared by those implementations belong under `src/ri/`.

Keep platform checks close to the boundary they describe. When a shared interface needs different implementations, expose one stable Ruby-facing contract and load the appropriate adapter through `filelist`. Native code or Fiddle bindings should remain focused on facilities that cannot be expressed safely or practically in portable Ruby.
