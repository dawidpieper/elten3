# Elten 3

Elten is the desktop client for [EltenLink](https://elten.link), a social networking for the blind, active since 2014.

The project maintainer is [Dawid Pieper](mailto:dawidpieper@o2.pl).

> [!WARNING]
> Elten 3.0 is currently a release candidate. Documentation is still being written, and API contracts, interfaces, configuration keys, certificates, packaging details and other elements may change without prior notice. Treat the current code as evolving software, especially if you are building an application or integration on top of it.

This README provides technical information on the sources and development. General information, downloads and user-facing documentation can be found on the [EltenLink website](https://elten.link).

## What is Elten?

EltenLink, with its forums, blogs, private messages, conferences and so on, was initiated as a place for the integration for a worldwide blind community. Elten is its full desktop client for PC-class systems.

The client is self-voicing: it implements a keyboard-driven interface, speech output, audio cues and its own set of controls instead of presenting a conventional visual GUI. The same foundation is used both by Elten itself and by additional programs hosted inside the Elten environment. Accessibility is therefore not a compatibility layer added at the end of development; it shapes navigation, focus, timing, feedback and error handling throughout the application.

**Elten intentionally lacks graphical user interface.**
This is a deliberate, specialised design choice, not a claim that every application intended for blind users should create a custom interface. Standard frameworks and native controls are often the best option because modern screen readers can expose them well. Elten maintains its own interface as an audio-first interaction model, consistent behaviour and a shared application API offer capabilities that a conventional GUI would not provide as effectively.

Eltenger is a separate native client aimed primarily at smartphones but not limited to them. It follows a different product idea and serves a different purpose. Its source code is expected to be published separately.

## Prowadnica Foundation

EltenLink is operated by the [Prowadnica Foundation](https://prowadnica.org), a Polish foundation created by blind people and guided by first-hand experience of blindness. Its wider mission is to support independence through modern technology, practical knowledge, consultation, education and work on genuinely accessible tools and spaces.

The network is one part of that work: a place where visual noise is not the price of participation, sound is treated as a first-class medium, and people from different countries can exchange knowledge and build lasting communities.

## From Elten 2.x to Elten 3.x

The legacy client remains available in the [Elten 2 repository](https://github.com/dawidpieper/elten2). Its RGSS foundation was inherited from the earliest versions of Elten and ultimately tied a growing application to an ageing, Windows-centred runtime.

Elten 3 is the long-planned break with that technical debt:

| Area | Elten 2.x | Elten 3.x |
| --- | --- | --- |
| Runtime | RGSS-based engine with a legacy Ruby lineage | Purpose-built C++ launcher hosting a modern Ruby runtime |
| Ruby | Constraints inherited from an ecosystem originating with Ruby 1.8.1 | Ruby 4.x for primary targets |
| Process model | An RGSS front end accompanied by a separate background agent, a split forced by the engine | One process combines the interface and long-running background services |
| Background work | The agent maintained the network session, notifications, tray integration, audio, calls and conferences, exchanging commands and events with the RGSS process | These responsibilities run inside the main Ruby runtime and use the same application services directly |
| Native integration | A large Windows DLL bridged gaps in RGSS and its Ruby version, providing facilities such as speech, keyboard hooks, tray and dialog support, spell checking and audio processing | Platform-specific runtime adapters and focused native libraries are exposed through shared Ruby interfaces |
| Platforms | Closely coupled to Windows and RGSS | Cross-platform design for Windows, Linux and macOS |
| Server communication | Legacy client and server interfaces | New JSON API and a dedicated `EltenLink` client layer |
| Application structure | Social features, controls and runtime concerns closely connected | Clearer boundaries between API, UI controls, scenes, platform code and server resources, all deliberately kept in-process |
| Distribution | RGSS-oriented build process | CMake, a C++ launcher, embedded assets and platform release tooling |

Elten 3 deliberately remains an in-process application. Its internal boundaries continue to improve incrementally, reflecting the project's preference for evolution over revolution. The background to retained compatibility code is summarised in [Reading a long-lived codebase](docs/contributing.md#reading-a-long-lived-codebase), while the rules for changing it are documented in the [evolution and migration policy](docs/architecture.md#evolution-and-migration-policy).

## Supported operating systems

| Operating system | x86 | ARM32 | x64 | ARM64 |
| --- | --- | --- | --- | --- |
| Windows | Deprecated | No target | Supported | Supported |
| Linux | Deprecated | Buildable from source | Supported | Supported |
| macOS | Buildable from source | No target | Buildable from source | Supported |

- **Supported**: official binaries are published and the target receives normal support.
- **Deprecated**: the target is still built, but support is expected to end in the foreseeable future. New work should not rely on its continued availability.
- **Buildable from source**: official binaries are not published, but the code is expected to compile with a suitable toolchain and architecture-matched third-party libraries. Some CMake or dependency preparation may be required as no ready-made preset is supplied.
- **No target**: this operating-system and architecture combination is outside the Elten build matrix; no compatible build, official binary or support commitment is provided.

## Developer documentation

- [Building Elten 3](docs/building.md) covers the Ruby quick start, build requirements and pipeline.
- [Elten 3 architecture](docs/architecture.md) covers the process model, source tree, loading order and platform boundaries.
- [Development roadmap](docs/roadmap.md) records cross-cutting architectural directions and committed runtime changes.
- [Elten applications](docs/eltenapps.md) covers the experimental hosted application runtime, lifecycle and packaging.
- [Contributing to Elten 3](docs/contributing.md) covers planning changes, updating localisation and sending pull requests.
- [Security Policy](docs/security.md) explains how to report a suspected vulnerability.

## Reporting bugs and following development

GitHub Issues are disabled. Official issue tracking, discussion and milestone work take place in dedicated EltenLink forums:

- [Polish beta testing](https://elten.link/forum/group/110)
- [English beta testing](https://elten.link/forum/group/111)

Both groups are active, but, frankly, the Polish group is substantially busier and has the more complete tagging, triage and milestone history, so it is the best reference for an overview of current development. The English group remains the correct place for reports and discussion in English.

Details regarding bug-reporting are provided in the mentioned forums.

Do not post suspected vulnerabilities to either group. Report them privately by following the [Security Policy](docs/security.md).

## Official binaries and updates

Official installers for all supported targets are available from the [EltenLink website](https://elten.link).

Each supported platform has an integrated updater. If the aim is to use Elten rather than modify it, an official build is the recommended route: it includes the appropriate Ruby runtime, native libraries, launcher metadata and platform packaging.

## Licence

Elten is free software distributed under the [GNU General Public License, version 3](license).

Copyright (C) 2014-2026 Dawid Pieper.
