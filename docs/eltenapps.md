# Elten applications

[Back to the project README](../readme.md). See also [Elten 3 architecture](architecture.md), [Building Elten 3](building.md), [Contributing to Elten 3](contributing.md) and the [development roadmap](roadmap.md).

This document describes applications hosted by the Elten desktop client: how their code is loaded, what the runtime does and does not isolate, how an application participates in the interface, and how development packages are built. It is an orientation guide for contributors, not a complete or stable API reference.

> [!IMPORTANT]
> The application system in Elten 3.0 should be treated as experimental. Elten 3.1 is planned as the release in which Elten applications reach their intended full shape and stability, including concrete, published rules for package signing and verification. Current manifests, lifecycle hooks, certificates, trust roots, package details and helper APIs may therefore change before that point.
>
> This status is not intended to discourage writing applications, testing the runtime or proposing improvements. Practical experiments during Elten 3.0 are welcome and are valuable to the design. The warning defines the present compatibility boundary and the planned stabilisation point; it does not ask developers to wait for Elten 3.1 before trying the platform.

## Runtime model

An Elten application is Ruby code loaded into the same process and Ruby runtime as the client. It can use Elten's audio-first controls, speech and sound interfaces, navigation, tasks, EltenLink services and selected extension points without starting a separate executable or communicating with a second UI process.

For each loaded application, `Programs::Runtime` provides:

- a module namespace derived from the application's UUID;
- virtual paths for Ruby files embedded in an `.eltenapp` bundle;
- application-aware `require` and `require_relative` resolution;
- separate persistent data and disposable cache directories;
- access to packaged sounds, translations and platform-native components;
- a registry for resources whose lifetime belongs to the application; and
- attribution of classes and many exceptions to the application which supplied them.

These facilities prevent ordinary name and path collisions and make an application unloadable as a unit. They are not an operating-system security boundary.

### Namespacing is not a sandbox

Application code executes in-process and can see the Ruby environment available to Elten. The generated `EltenPrograms::P<uuid>` namespace isolates constants created normally by the application, but it cannot prevent deliberate access to global constants, monkey-patching, native libraries, process state or other in-process facilities.

A valid package signature authenticates the packaged bytes through a trusted certificate chain. It does not prove that the program is safe, does not grant a sandbox, and does not restrict what the code can do after loading. Treat an Elten application as code executed with the user's Elten process privileges.

Do not store secrets on the assumption that another application cannot reach them. Do not load an application from an untrusted source merely because it uses the expected file extension. A suspected security defect in the runtime or verification process should be reported through the [Security Policy](security.md).

## A minimal source application

A development directory normally starts with `__app.rb`. The file contains exactly one `Elten3AppInfo` block followed by the application code:

```ruby
=begin Elten3AppInfo
{
  "id": "67b1132e-f2ac-4d0a-b329-42fc1dc2a490",
  "name": "Example application",
  "version": "0.1.0",
  "build_id": "1",
  "EltenAPIVersion": "3.0",
  "author": "Example author",
  "main": "__app.rb",
  "main_class": "ExampleApplication",
  "platforms": ["all"],
  "menu": {
    "main": "Example application"
  }
}
=end Elten3AppInfo

class ExampleApplication < Program
  def main
    information = EditBox.new(
      _("Example application"),
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
      text: _("This application is running inside Elten.")
    )
    close_button = Button.new(_("Close"))
    form = Form.new([information, close_button], quiet: true)
    form.accept_button = close_button
    form.cancel_button = close_button
    close_button.on(:press) { form.resume }
    form.wait
    finish
  end
end
```

Do not add the generated `EltenPrograms` namespace yourself. The runtime evaluates the file inside the namespace assigned to the manifest UUID, then resolves `main_class` relative to it. The resolved class must inherit from `Program`.

`Program` is scene-compatible: the main menu can use the application class as a destination and instantiate it when selected. Its instance `main` method therefore owns the launched interaction. Use the same `Form#wait`, `Tasks.run`, `Runner`, `$scene` and `insert_scene` rules described in the [architecture guide](architecture.md#owning-an-interaction).

## Manifest

The manifest is JSON, even though it is embedded in a Ruby block comment. JSON keys are strings and the block must be valid before any application code is evaluated.

| Field | Meaning |
| --- | --- |
| `id` | Stable UUID for the application. It determines identity, namespace and persistent storage association. Do not generate a new UUID for each release. |
| `name` | Human-readable application name. |
| `version` | User-facing version string. |
| `build_id` | Non-empty, non-zero build identity used when comparing releases and updates. Change it when publishing a different build. |
| `EltenAPIVersion` | Minimum compatible Elten application API. The current runtime accepts the same major version when its own version is at least this value. |
| `author` | Human-readable author or publisher. |
| `main` | Logical path to the entry Ruby file. Builders infer the manifest file when this is omitted, but an explicit value is clearer. |
| `main_class` | Class to launch, resolved inside the generated application namespace. It must inherit from `Program`. |
| `platforms` | Supported platform families or targets. See below. |
| `menu` | Optional main-menu and user-menu metadata. |
| `gems` | Optional declarations for additional Ruby gems not already supplied by Elten. They are used by the full setup builder. |
| `required_assets` | Optional declaration of resources which must be available before the application is loaded. |

Platform entries are lower-case. The runtime recognises `all`, `universal` and `*`, a family such as `windows`, `linux` or `osx`, or an exact target such as `windows-x64`, `windows-arm64`, `linux-x64`, `linux-arm64` or `osx-arm64`. Prefer the narrowest truthful declaration when an application contains native code.

The menu object currently supports:

```json
{
  "main": "Label in the main menu",
  "hidden": false,
  "user": {}
}
```

Omitting `menu.main` uses the application name. Setting `menu.hidden` to `true` prevents the ordinary main-menu entry, which is useful only when another supported entry point is registered.

## Loading and source resolution

An unpacked development application may consist of several Ruby files. Calls to `require` and `require_relative` made from application code are resolved against the current application runtime before Ruby's ordinary loader is used:

```ruby
# __app.rb
require_relative "lib/library"

class ExampleApplication < Program
  # ...
end
```

Inside an `.eltenapp` file, source locations use the form `eltenapp://<uuid>/<logical-path>`. This allows backtraces, relative loading and error attribution to retain meaningful application paths without extracting every Ruby file to disk.

The current runtime is also carried in thread-local state while application callbacks are invoked. This lets shared loader hooks and error handling identify which application owns an operation. Code which starts its own threads should not assume that arbitrary thread-local runtime state is inherited. Prefer application class helpers and explicitly establish the needed ownership through supported Elten APIs.

Applications loaded as loose Ruby source are allowed only in developer mode. Starting Elten directly from its source checkout enables developer mode automatically. A normal packaged client requires an acceptable application package signature. This difference permits a short edit-run cycle without weakening the normal loading policy.

## Lifecycle

The application class and its launched instances have different lifetimes:

| Stage | Hook or operation | Thread and purpose |
| --- | --- | --- |
| Load | Manifest and package validation | Checks identity, API version, platform, signature policy and required assets before activation. |
| Class registration | `self.activate` | Runs synchronously when the class is registered, with its runtime associated. Use it for short class-level registrations. |
| Background initialisation | `self.init` | Runs on a worker thread after registration. It may prepare non-UI state, but must not mutate forms or navigation directly. Exceptions are logged. |
| Launch | `main` on a new instance | Owns the user interaction when the application is selected from the menu. |
| Instance exit | `finish` | Calls the instance `close` hook, releases instance-managed resources, closes the application sound pool and returns to `Scene_Main`. |
| Runtime unload | `Programs.unregister_runtime` | Closes runtime-managed resources and sound state, stops extensions, removes loader mappings and removes the generated namespace. |

Override `close` for cleanup which belongs to one launched instance. Call `finish` rather than calling `close` directly when the application is leaving its main interaction:

```ruby
class ExampleApplication < Program
  def close
    @subscription.close if @subscription != nil
  end
end
```

The runtime can attribute many exceptions by namespace, virtual path, class or associated runtime. An attributable application error can be logged, cleaned up and returned to the main client instead of becoming an unclassified Elten failure. This is a recovery boundary, not a substitute for handling expected errors inside the application.

## Threads and responsive work

Applications share Elten's thread and event model. In particular:

- the instance which created a form owns that interaction;
- background work must not change that form or `$scene` directly;
- `Tasks.run` should be used for finite cancellable work, with delayed automatic progress UI, optional reuse of an existing form and `progress.ui` for an owner-thread callback;
- `Runner` should own a non-form interaction with timers or repeated actions; and
- an extension `tick` callback runs as part of Elten's main application pump and must return promptly.

The complete ownership model and the responsibilities of `loop_update` are documented under [Threads and interaction ownership](architecture.md#threads-and-interaction-ownership) and [What loop_update coordinates](architecture.md#what-loop_update-coordinates).

## Files, persistent data and cache

Application code has three different path concepts:

| API | Intended content | Lifetime |
| --- | --- | --- |
| `asset_path(relative)` | A read-only supporting file installed with the application. It may not have a physical path when the asset is held only inside an application bundle. |
| `data_path(relative)` | User or application state which should survive restarts and ordinary application upgrades. |
| `cache_path(relative)` | Re-creatable material such as extracted native files or generated media. It may be deleted. |

Both data and cache paths are confined to the application's assigned directory. Parent traversal and paths escaping that root are rejected. The data helpers encode text as UTF-8 and replace a destination through a temporary file:

```ruby
settings = app.read_json("settings.json", default: {})
settings["announcements"] = true
app.write_json("settings.json", settings)

app.write_text("notes/welcome.txt", "Welcome")
raw = app.read_binary("state.bin", default: "".b)
```

Here `app` is the runtime returned by the instance helper. The same read and write helpers are available as application class methods, which is convenient in `self.activate` or `self.init`.

Uninstalling an application normally leaves its data available for a later reinstall. The Programs screen offers a separate operation which removes both the application and its data. An application must not use its cache for anything whose loss would surprise the user.

## Packaged assets

Files below `Audio/` with recognised audio extensions are indexed as named sound assets. The name is the file name without its extension:

```ruby
sound = create_sound_from_asset("success")
manage(sound) if sound != nil
sound.play if sound != nil

play_sound_from_asset("notification", volume: 0.8)
```

`play_sound_from_asset` uses the runtime's managed `SoundPool`, which limits simultaneous voices and closes completed sounds. Use `create_sound_from_asset` when the application needs direct control over the sound lifetime, and register the resulting object with `manage`.

Translations are read from `locale/<language>.mo`, where the package format currently records a two-letter language code. Native entries are selected by the exact platform target and materialised into the application cache before loading.

`required_assets` can make loading fail early with an informative error instead of failing later in the interaction. The recognised groups are `sounds`, `files`, `locales` and `native`:

```json
{
  "required_assets": {
    "sounds": ["success", "notification"],
    "files": ["data/defaults.json"]
  }
}
```

Only declare an asset as required when the application genuinely cannot start without it. Optional content should be detected and handled by the feature which uses it.

## Resource ownership

`manage` attaches an object to a resource registry and normally calls its `close` method when that registry ends. Registries close in last-in, first-out order and make repeated cleanup safe.

Calling `manage` on a `Program` instance gives the resource the lifetime of that launch; `finish` releases it. Calling the class method `manage` gives it the lifetime of the loaded runtime; it is released when the application is unloaded. Choose the narrower lifetime whenever possible:

```ruby
class ExampleApplication < Program
  def main
    sound = create_sound_from_asset("introduction")
    @sound = manage(sound) if sound != nil
    @sound.play if @sound != nil
    # ...
    finish
  end
end
```

You can use `release(resource)` to remove a resource from the registry without closing it, or `release(resource, close: true)` to remove and close it immediately. Garbage collection and native finalisers are also included.

## Extensions

An application extension remains active while its runtime is loaded, even when no application instance is currently open. Register it from `self.activate`:

```ruby
class ExampleApplication < Program
  def self.activate
    extension("background_updates") do |extension|
      extension.start do
        @last_check = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      extension.tick(interval: 30) do
        check_for_updates_without_blocking
      end

      extension.stop do |reason|
        Log.debug("Example extension stopped: #{reason}")
      end

      extension.settings do |settings|
        settings.category(_("Example application"))
        settings.boolean(
          "announcements",
          label: _("Announce updates"),
          get: proc { read_json("settings.json", default: {})["announcements"] == true },
          set: proc do |value|
            state = read_json("settings.json", default: {})
            state["announcements"] = value
            write_json("settings.json", state)
          end
        )
      end
    end
  end
end
```

Extension names and setting keys use lower-case letters, numbers and underscores and must start with a letter. An extension may define at most one `start`, `tick`, `stop` and `settings` callback. Its stop callback receives a reason such as unload, reload rollback or client shutdown. Extensions are stopped in reverse registration order when their runtime is removed.

The tick callback is synchronous and runs from `loop_update` on `$mainthread`. It must not wait for a network response, display a modal interaction or perform substantial parsing. Keep persistent work in an owned worker or service and use the tick only to inspect or apply ready results.

## Other integration points

`Program` currently exposes further integration mechanisms:

- `register_quickaction` adds an application-owned action to Elten's configurable quick actions;
- `on` listens for selected client events such as speech or player state changes;
- user-menu metadata can add application actions for a selected EltenLink user;
- application signals exchange JSON-compatible packets through `EltenLink::Apps`; and
- server-application helpers register metadata and access application tables or resources.

These areas are especially subject to the Elten 3.0 experimental status. Use the existing helpers rather than writing directly into global menu collections, and discuss additions to the event vocabulary or server contract before depending on them.

## Building packages

There are two related formats:

- `.eltenapp` is the executable application bundle understood by `Programs::Runtime`. It contains the manifest and compressed Ruby code and can contain sounds, translations and target-specific native material.
- `.eltsetup` is the user-installable, ZIP-compatible setup container accepted by the Programs screen. It carries an Elten `__manifest.json`, one `.eltenapp` payload and any supporting files which remain outside that payload.

For a small application without additional bundled gems, build a development `.eltenapp` with:

```sh
bundle exec ruby tools/build-eltenapp.rb --unsigned path/to/source build/example.eltenapp
```

For an installable package, use the full setup builder:

```sh
bundle exec ruby tools/build-eltsetup.rb --unsigned path/to/source dist/example.eltsetup
```

### Gems supplied by Elten 3.0

Applications may use the gems which are already part of the Elten 3.0 runtime. As a rule, these direct dependencies can be treated as present wherever a compatible Elten 3.0 client runs. They should be required normally, but must not be repeated in the manifest's `gems` array. The setup builder recognises them as host dependencies and deliberately does not bundle private copies.

Using one of the cross-platform gems below does not by itself make an application platform-specific. Elten prepares the appropriate build as part of each platform runtime, including native gems such as Nokogiri and SQLite. An application can therefore use an SQLite database or parse documents with Nokogiri while continuing to declare all supported Elten platforms.

| Gem | Elten 3.0 version | Typical `require` |
| --- | --- | --- |
| `base62` | 1.0.x | `require "base62"` |
| `base64` | 0.3.x | `require "base64"` |
| `bigdecimal` | 3.3.x | `require "bigdecimal"` |
| `fiddle` | 1.1.x | `require "fiddle"` |
| `http-2` | 1.1.x | `require "http/2"` |
| `net-http` | 0.9.x | `require "net/http"` |
| `nokogiri` | 1.19.x | `require "nokogiri"` |
| `ostruct` | 0.6.x | `require "ostruct"` |
| `ruby-xz` | 1.0.x | `require "xz"` |
| `rubyzip` | 3.2.x | `require "zip"` |
| `sqlite3` | 2.9.x | `require "sqlite3"` |
| `zstd-ruby` | 2.0.x | `require "zstd-ruby"` |

`win32ole` 1.9.x is also supplied by Elten 3.0, but only on Windows. An application which uses it is Windows-specific and must declare that honestly in `platforms`; it still does not list `win32ole` under `gems`.

Availability of `fiddle` is cross-platform, but a Fiddle binding to a Windows DLL, macOS framework or platform-specific shared library is not. Platform compatibility is determined by what the application calls, not merely by whether its Ruby dependency contains native code.

The versions above are the Elten 3.0 pins. Applications may rely on the listed gems being available, but should avoid depending on accidental implementation details of one exact patch release when the public gem API is sufficient. Transitive lockfile entries, such as dependencies used internally to build Nokogiri, are not part of this application guarantee unless they are listed above.

### Additional application gems

The setup builder processes `gems` declarations only for dependencies which are not supplied by Elten. It includes Ruby sources from those gems and collects available native extensions for supported target runtimes. A declaration may be a name or an object with a version requirement:

```json
{
  "gems": [
    { "name": "example-gem", "requirement": "~> 1.2" }
  ]
}
```

The declared gems and their runtime dependencies must already be installed in the Ruby used by the builder. Additional native extensions create target-specific payloads. Provide matching builds for every platform you claim, narrow `platforms` wherever a build is unavailable, and test each target.

### Signing during Elten 3.0

Both builders try to sign by default and accept `--cert` and `--key` for an authorised signing certificate and its private key. Those credentials are not part of the public repository. An ordinary contributor should use `--unsigned` for local development and must not request, copy or invent an official private key.

Developer mode accepts an unsigned or currently unverifiable `.eltenapp` with a warning so that the package path can be tested. A normal packaged client rejects an application whose signature is missing or does not verify against its embedded trust root. Verification currently checks the certificate chain, certificate validity, code-signing purpose and the signature over the exact application payload.

These are the Elten 3.0 implementation rules, not the final public signing programme. The concrete issuance, publisher identity, trust, revocation and verification policy is planned to be defined and stabilised for Elten 3.1. Do not present an experimental certificate or locally signed package as an officially approved Elten application.

## Before sharing an experimental application

- Keep the UUID stable and update both `version` and `build_id` deliberately.
- Test the loose source in developer mode, then test the actual `.eltsetup` installation path.
- Test missing files and unavailable network services
- Test unload procedure
- Keep worker threads away from forms and navigation; close every owned resource.
- Verify that persistent data uses `data_path` and disposable output uses `cache_path`.
- Test every platform named in the manifest when additional gems or native components are included.
- Treat signing keys, session tokens and user content as secrets and keep them out of packages and logs.
- State clearly that the Elten 3.0 application API and package policy are experimental.

Feedback from real applications is one of the inputs needed to make the Elten 3.1 contract useful and stable. When the current API lacks a necessary capability, prefer a focused proposal or pull request to an application-specific workaround which reaches through internal globals.
