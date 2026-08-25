# Building Elten 3

[Back to the project README](../readme.md).

This guide covers running Elten directly from a source checkout and producing packaged launcher builds. For the runtime and source layout, see [Elten 3 architecture](architecture.md); for localisation and pull request guidance, see [Contributing to Elten 3](contributing.md).

Elten 3.0 is currently a release candidate. Build requirements, runtime versions, packaging details and CMake options may still change.

## Quick start from source

Running directly from a source checkout is the preferred workflow when working on the Ruby application code. It executes the complete current codebase and preserves the application functionality of a packaged build. Ruby changes are picked up on the next start, so the usual edit-test cycle does not require rebuilding the launcher or re-embedding the source payload.

Use a compatible Ruby installation with Bundler and a native build toolchain suitable for gems such as Nokogiri, SQLite and Zstandard. A packaged launcher is not required for ordinary source development.

Ruby 4.x is the recommended development environment. The current CMake configuration pins Ruby 4.0.x for the principal targets, while deprecated Windows x86 builds use Ruby 3.4.x. Future runtime and target changes are tracked in the [development roadmap](roadmap.md).

From the repository root:

```sh
bundle install
bundle exec ruby elten.rb
```

### The first `bundle install`

The first dependency installation can take a surprisingly long time. The project deliberately installs Nokogiri from source, and Nokogiri may in turn build its XML dependencies. On some machines, especially Windows systems or less common architectures, this stage can take half an hour or longer and may appear quiet for extended periods. This is normal as long as the compiler or build process is still active.

This cost is normally paid once for a particular Ruby installation, architecture and bundle location. Later starts use the already installed gems. A full rebuild may be required after changing the pinned gem versions, replacing Ruby or deleting the installed bundle.

The compiler, headers and platform development tools must therefore be available before running `bundle install`.

### The Nokogiri MiniPortile patch

Elten carries a narrow build-time compatibility shim at `patchs/mini_portile_msys_path_patch.rb`. On Windows, Bundler loads it automatically through the `Gemfile` before Nokogiri invokes MiniPortile. The shim translates drive-letter paths such as `C:/...` into the form expected by MSYS tools, repairs generated Makefiles and libtool configuration where necessary, and converts installed configuration scripts back to usable Windows paths.

The aim is to patch the boundary between Windows Ruby and the MSYS build tools, not to maintain a fork of Nokogiri or modify its application behaviour. Do not apply the patch manually and do not edit an installed Nokogiri gem: a normal `bundle install` activates it. The packaged CMake runtime uses the same shim, keeping direct and packaged dependency builds consistent. When changing the Gemfile or Windows runtime preparation, preserve this early-loading mechanism; without it, Nokogiri source builds may fail even though the compiler and libraries are present.

Running from a checkout does not reproduce launcher-specific properties such as asset embedding, runtime isolation, integrity metadata, the launcher stamp, signing or installation behaviour. Use a packaged launcher when testing those areas. Existing accounts can be used during normal source development, but account registration and any server operation explicitly requiring a trusted official launcher stamp must be tested with an official release launcher.

## Packaged build overview

A full build needs CMake 3.24 or newer, a C++17 compiler, network access for preparing Ruby and gems, and the native build tools required by the target. The CMake pipeline:

1. prepares a self-contained Ruby runtime;
2. installs the required gems with Bundler;
3. gathers native dependencies;
4. compresses and embeds the Ruby source payload;
5. builds the launcher;
6. assembles the platform release under `build/release/`.

The first preparation of a packaged target can take the same half-an-hour-or-longer build described above. CMake records and verifies the prepared runtime, so later builds for that target normally reuse the installed gems unless the Ruby version, Gemfile, lockfile, patch or runtime directory changes.

### The private launcher stamp key

The private key mentioned by CMake is specifically the launcher stamp. This mechanism uses a shared HMAC secret as a release seal that lets an official launcher attach verifiable proof to selected requests, especially for registering new accounts.

An authorised release launcher exposes `get_stamp` to Ruby. It combines request material with a timestamp and a platform-derived machine identifier, then authenticates the result with HMAC-SHA256. The EltenLink service can use that stamp to distinguish an official launcher from code started directly or from an ordinary contributor build. This is a trust boundary for selected server operations, not a requirement for executing the client itself.

The release secret is intentionally absent from the public repository. By default, CMake looks for `private/stamp_key.hex`, containing 32 secret bytes encoded as 64 hexadecimal characters. An ordinary contributor should leave this file absent. Do not request, copy, publish or commit the official secret, and do not create a placeholder at the default path: an arbitrary local key may exercise the code path in isolation, but its stamps are not trusted by the service and it does not turn a local package into an official build.

When the key is absent, the CMake warning is expected and no action is required. Configuration and compilation continue, `get_stamp` is omitted and developer mode is forced. The resulting launcher still runs the complete application code; only operations deliberately gated by an official launcher stamp, most notably account registration, remain unavailable. Platform package signing and macOS notarisation are separate release steps with separate credentials.

## Windows

The supplied presets use the Visual Studio 2026 generator and its CMake component. Build one architecture with the corresponding wrapper:

```bat
tools\build-windows-x64.bat
tools\build-windows-arm64.bat
tools\build-windows-x86.bat
```

The x64 and x86 builds also produce `EltenSapiBridge64.exe` and `EltenSapiBridge32.exe` respectively. CMake writes them to `bin\ext\windows\` for source runs and copies them to `build\release\windows\bin\ext\windows\`. Build x86 for an x64 source run, and both x64 and x86 for ARM64; `tools\build-windows.bat` builds the complete set.

The helpers are optional when running directly from source. Without compiling them, Elten still starts normally; the only resulting constraint is that SAPI voices requiring another process architecture are unavailable.

The x86 target is deprecated. `tools\build-windows.bat` is the multi-architecture release helper. Individual launchers are written to `build\release\windows\`.

Additional CMake arguments may be passed to the per-architecture scripts. Release builds may also provide `--build-id`; ordinary contributor builds may leave it unset.


## Linux

Build on a matching host, or with a correctly configured cross-toolchain, using one of:

```sh
./tools/build-linux-x64.sh --jobs 4
./tools/build-linux-arm64.sh --jobs 4
./tools/build-linux-x86.sh --jobs 4
```

These scripts require `cmake`, `file`, a working C/C++ toolchain and the development dependencies needed to compile Ruby and native gems. They validate the resulting executable architecture and place the release under `build/release/linux/`. The x86 target is deprecated.

`tools/build-linux.sh` assembles the broader Linux release and installer workflow once the required architecture-specific releases are available.

Linux ARM32 is expected to be buildable from source, but no official binary or ready-made build wrapper is supplied. Builders must provide an appropriate toolchain and architecture-matched native libraries.

## macOS

The maintained preset targets Apple Silicon. CMake, the Xcode Command Line Tools and `ruby-install` are required for a fresh runtime build.

```sh
./tools/build-osx-arm64.sh
./tools/build-osx-arm64.sh --app
./tools/build-osx-arm64.sh --pkg
```

The first command builds the launcher, `--app` assembles an application bundle, and `--pkg` also creates the installer package. Builds are unsigned by default. The `--sign` and notarisation-related options require appropriate Apple identities and credentials and are for release use.

macOS x86 and x64 are source-buildable targets rather than maintained presets. Expect to provide architecture-correct Ruby and native libraries and to adjust the configuration locally.

## Source-buildable targets

In the Readme's support matrix, **Buildable from source** means that the code is expected to compile with a suitable toolchain and architecture-matched third-party libraries. It does not promise that an existing wrapper will perform a complete cross-build or that the resulting package receives official support.

When working on such a target, expect to provide or adapt:

- the compiler and target sysroot;
- a compatible Ruby runtime;
- native gems and the libraries under `bin/`;
- CMake architecture settings and packaging rules;
- any platform-specific signing or installation metadata.

## Build outputs

Generated files belong under `build/` and `dist/`; both locations are excluded from version control. Do not add generated packages, downloaded runtimes, private keys or signing credentials to a pull request.

If a newly added Ruby source file works during an ad-hoc test but is missing from the packaged application, check that it has been added to the ordered `filelist` manifest. See the [architecture guide](architecture.md#source-loading-and-filelist) for details.
