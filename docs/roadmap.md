# Elten development roadmap

[Back to the project README](../readme.md). See also [Elten 3 architecture](architecture.md), [Building Elten 3](building.md), [Elten applications](eltenapps.md) and [Contributing to Elten 3](contributing.md).

> [!IMPORTANT]
> This is deliberately not a feature wish list, release checklist or substitute for the project forums. Smaller product decisions, new features and individual ideas are discussed in the EltenLink beta-testing groups. Anyone trying to understand or influence the practical shape of a coming release should follow the [Polish beta-testing group](https://elten.link/forum/group/110) or the [English beta-testing group](https://elten.link/forum/group/111).
>
> This document records only architectural directions and development constraints which are important across multiple changes. An item absent from this file is not rejected or unimportant. Unless a section states that a target is committed, its design, timing and even final implementation remain open to discussion.

## Elten 3.1 application contract (committed for Elten 3.1)

Hosted applications are treated as experimental in Elten 3.0. Elten 3.1 is the committed target for publishing their complete, stable contract. The contract is expected to define the supported package and manifest format, loading and lifecycle rules, public extension points, application-facing client interfaces, compatibility expectations, and the signing and verification model. Signing work includes concrete rules for publisher identity, trust, certificate use, revocation and package verification rather than merely preserving the experimental Elten 3.0 mechanism.

The objective is to let an application depend on documented interfaces instead of incidental client internals. Experiments and real applications written against Elten 3.0 remain welcome because they expose missing capabilities before the contract is fixed. They must, however, continue to assume that current manifests, hooks, helper APIs and trust details may change. The current runtime and packaging model is described in [Elten applications](eltenapps.md).

Best-effort compatibility with applications written for Elten 3.0 is planned wherever it is practical and does not compromise the stable contract. This is a compatibility goal, not a guarantee, though. Applications may still require changes when manifests, lifecycle hooks, trust rules or APIs must be corrected or formalised.

## Audio backend and BASS (under consideration; no backend selected)

BASS is currently the only proprietary library deliberately retained as a core dependency of the GPL-licensed client. BASS remains under its own licence; its presence is not being treated as a permanent architectural guarantee.

Substantial parts of the audio path are already project-controlled, including recording and media-encoder interfaces, container writers, and encoder and decoder paths using open libraries for formats such as Opus, Ogg and Vorbis. BASS still supplies much of the common playback, device, recording, streaming, mixing and effects backend, and legacy code sometimes calls it directly.

A fully project-controlled audio layer is under consideration. PortAudio is one possible foundation for device input and output, but neither PortAudio nor any other replacement has been selected. The work would need to account for normal playback, short interface sounds, recording, remote streams, format decoding, mixing, effects, conferencing, device selection and consistent behaviour on every supported system. No release has been assigned to this investigation.

Contributors should therefore depend on Elten-owned abstractions wherever possible. Classes and interfaces such as `Sound`, `Recorder`, `Player`, `MediaEncoders` and the normal sound helpers exist in part to keep feature code independent of the backend. New feature code should not expose BASS handles, constants or calls unless it is specifically implementing the audio backend. If an abstraction lacks a required operation, extending its contract is preferable to making another feature depend directly on BASS. Existing direct use will be reduced gradually as the surrounding audio code is redesigned.

## Retirement of x86 (expected; no date selected)

The 32-bit x86 targets will eventually be removed. They are already deprecated, and the runtime split makes their long-term maintenance increasingly costly: the principal Windows targets use Ruby 4.0, while Windows x86 remains on Ruby 3.4 because Ruby 4.0 did not receive a Windows x86 build. This creates separate runtime, native-gem, packaging and testing paths for an architecture with a diminishing future.

No removal release or date has been selected. The end of official x86 builds will be announced in advance through the normal release and forum channels. Until then, the published support matrix remains authoritative. New architecture and public contracts should nevertheless avoid assuming that x86 will remain available indefinitely, and new dependencies should not be introduced solely to deepen reliance on it.

## Ruby 4.1 and ZJIT (Ruby 4.1 committed; ZJIT under consideration)

The Elten 3.1 runtime will be based on Ruby 4.1. Build definitions, bundled runtimes and native-gem preparation will move together so that supported systems continue to run the same Ruby generation wherever an upstream runtime exists.

Enabling ZJIT will be considered separately. The decision depends on its stability in real Elten workloads, support across release targets, interaction with native extensions, startup and memory costs, and the reliability of packaging and diagnostics. ZJIT is an optional optimisation candidate, not part of the Elten 3.1 compatibility contract. Correct operation without it must be preserved, and no source or application interface may depend on JIT-specific behaviour.

## Windows NVDA integration (planned after the upstream API stabilises)

On Windows, basic speech and cancellation can already be handled through `NVDAControllerClient` when the Elten NVDA add-on is unavailable. Indexed speech is different: reporting which marker in a speech sequence has been reached currently depends on the add-on and its named-pipe protocol. The add-on is therefore the only present route to `SpeechOutput#indexed_supported?` for NVDA, even though basic controller speech can work without it.

Once the upstream `NVDAControllerClient` interface for indexed speech and index reporting has stabilised, a direct implementation behind the existing speech-output contract is planned. The transition must retain capability detection and compatibility with older NVDA releases; no release will be made dependent on an experimental controller interface merely to remove the current path. The [NVDA Controller Client API documentation](https://github.com/nvaccess/nvda/blob/master/extras/controllerClient/readme.md) describes the upstream boundary for this work.

This does not imply that the Elten add-on will disappear. It will probably remain necessary for Elten's direct Braille integration and may continue to provide other enhanced integration. The intended change is to make it substantially more optional: once the direct route is mature, users who require speech, including indexed speech, should not need the add-on solely for index tracking.

## Incremental redesign of established areas (ongoing)

Older classes and scenes will gradually move towards smaller, clearer contracts as normal development reaches them. Forum, messaging and blog workflows are the principal candidates: they contain substantial established code in which navigation, network requests, state and interface ownership have historically been closely connected.

The intended direction is clearer separation between EltenLink services, feature state and forms; explicit ownership through current interaction interfaces; reuse of shared controls; and narrower objects which can be reasoned about and tested independently. The exact class structure is not fixed in advance and should follow the needs discovered while each workflow is improved.

This is not a plan for a bulk rewrite. In keeping with the project's [evolution and migration policy](architecture.md#evolution-and-migration-policy), an older area should normally adopt a newer contract when a substantial feature, redesign or fix already gives the change a concrete purpose. Small changes should remain small, while a missing shared capability should be added deliberately instead of worked around through another private legacy path.
