# Contributing to Elten 3

[Back to the project README](../readme.md).

Thank you for considering a contribution to Elten. This guide covers the contribution workflow, project history and compatibility context, interface and localisation conventions, testing and pull requests. Instructions for running and packaging the client are in [Building Elten 3](building.md), while the runtime model and source layout are described in [Elten 3 architecture](architecture.md).

Elten 3.0 is currently a release candidate. Server API contracts, Ruby interfaces, configuration keys and packaging details may change while the architecture settles.

## Reading a long-lived codebase

Elten began in 2014 as the work of a fourteen-year-old developer, at an age when reliably distinguishing a merely questionable idea from a spectacularly ill-advised one was still a skill to be acquired. The codebase grew as its author gained experience, with lessons incorporated gradually rather than through a single clean rewrite. Traces of that learning remain visible today: early structures, later corrections and newer conventions often meet within the same workflow, and a few youthful decisions have enjoyed remarkably long maintenance windows.

During that process, Elten passed through several technical eras: the original RGSS and Ruby 1.8 foundations, Elten 2, and Elten 3's own launcher, modern Ruby runtime and multi-platform structure. Elten 3 substantially revised the client, but it did not erase every earlier design layer. Its present structure is consequently a cumulative record of those eras rather than the product of one uniform architectural generation.

The project prefers evolution over revolution. Working code is normally modernised when a useful feature, redesign or fix already requires that area to change, not merely to make it look newer. This restraint must not be read as approval of every pattern found in the tree. Some historically shaped contracts remain deliberate and current, most notably `$scene` and `insert_scene` for top-level navigation. Others, such as feature-owned `loop_update` loops and local workarounds superseded by `Form#wait`, `Tasks` or `Runner`, may remain only because their workflows have not yet been redesigned.

Treat existing code as evidence of how Elten reached its present state, not as a specification by itself. New work should follow the [architecture guide](architecture.md), established shared interfaces and relevant current call sites. Before copying an older pattern, determine whether it is a supported compatibility contract or incidental legacy. Modernise a bounded area when substantive work gives that change a purpose; otherwise preserve the working flow and keep the contribution focused.

## Where to begin

| Task | Start with |
| --- | --- |
| Run Elten directly from source | [Quick start from source](building.md#quick-start-from-source) |
| Produce a packaged build | [Packaged build overview](building.md#packaged-build-overview) |
| Understand the runtime, source tree or loading order | [Elten 3 architecture](architecture.md) |
| Review cross-cutting development directions | [Development roadmap](roadmap.md) |
| Develop an application hosted by Elten | [Elten applications](eltenapps.md) |
| Plan and implement a change | [Planning a change](#planning-a-change), then [Making changes](#making-changes) |
| Change a form or user interaction | [Elten interface conventions](#elten-interface-conventions) |
| Report a suspected vulnerability | [Security Policy](security.md) |

## Planning a change

GitHub Issues are intentionally disabled. Development discussion, bug triage and milestone work take place in the dedicated EltenLink beta-testing groups:

- [Polish beta testing](https://elten.link/forum/group/110)
- [English beta testing](https://elten.link/forum/group/111)

Contributions are welcome, and the great majority of proposed changes are accepted. Small fixes and contained improvements can normally proceed directly to a pull request.

Before investing substantial work, however, presenting the idea in the appropriate beta-testing group is strongly recommended. Early discussion can reveal an existing implementation constraint, refine the expected behaviour, or show that the feature would fit better as an application hosted by Elten than as part of the core client. It can also establish that a proposal is unlikely to be accepted into the core before considerable implementation time is spent.

This recommendation is not an approval gate. A pull request will not be rejected merely because it was not discussed on the forum first. The purpose is to reduce the risk of avoidable or misdirected work when a change is broad, introduces a public interface, affects application packages or requires a significant redesign. The Polish group currently has the more complete tagging, triage and milestone history; the English group remains the correct place for discussion in English.

## Making changes

Keep changes focused and explain the user-visible effect as well as the implementation. Consult the [architecture guide](architecture.md) before adding a source area, changing loading order or introducing platform-specific behaviour.

### Pull request scope and migrations

A pull request should have one coherent purpose. Do not collect unrelated fixes, clean-ups, refactors and features into an omnibus submission merely because they were developed at the same time. Independent changes should normally be submitted independently so that each can be understood, tested, reviewed and, if necessary, reverted on its own.

Keep a small change correspondingly small. Correcting one behaviour, adding a minor option or inserting a single menu command is not a reason to rewrite the surrounding workflow with `Form#wait`, `Tasks`, `Runner` or another newer interface. Such a rewrite increases the review surface and regression risk without being necessary to deliver the requested change. Avoid opportunistic modernisation of neighbouring code for the same reason.

Migration to a newer API is welcome when the affected area is already undergoing a substantial change: for example, a redesigned workflow, a significant feature or a modification which materially changes interaction ownership, navigation or lifetime management. In that case the migration can clarify the new implementation and remove workarounds which the larger change has made obsolete. Keep it bounded to the workflow genuinely being redesigned and explain the migration as part of the pull request.

This follows the project's [evolution and migration policy](architecture.md#evolution-and-migration-policy): modernise code when useful development gives the modernisation a concrete purpose, not merely to make working code look newer.

### AI-assisted contributions

AI-assisted development, including workflows sometimes described as "vibe coding", is allowed. Elten does not judge a contribution merely by whether a model helped to produce it. Used with care, these tools can save considerable time on small, repetitive and well-defined tasks, and can help technically minded contributors without extensive programming experience complete useful, well-scoped work. The same approach is taken during internal development, and AI has even had a hand in drafting this documentation, so taking a purist line would be a bit rich.

The contributor remains responsible for everything submitted, though. Read the entire diff, understand the resulting behaviour and be able to explain the design decisions. Generated output is not evidence that a change is correct, and an AI tool is not a substitute for testing. Do not submit code which you cannot assess merely in the hope that review will repair it.

Every pull request is reviewed manually. Unverified or low-quality generated code transfers the cost of understanding, debugging and rewriting it to the review process. A change which is incoherent, unnecessarily broad or based on invented assumptions will normally be rejected rather than completed during review.

AI assistance is most reliable when the task has narrow boundaries and an observable result. Risk rises sharply for large redesigns, platform-specific changes, native or launcher integration, concurrency and lifetime management, security or signing code, binary and text boundaries, server contracts and other low-level interfaces. In these areas a model may silently miss failure states, choose deprecated interfaces, add needless dependencies, erase important platform distinctions or produce a locally plausible design which conflicts with the rest of the application.

As a practical rule, if you are unsure whether a task is too complex to entrust to AI, it probably is.

Before submitting AI-assisted code:

- inspect every change and remove unrelated edits;
- compare the implementation with current call sites and the architecture guide rather than trusting a generated API choice;
- if you cannot yet assess a change unaided, at minimum ask the model to explain what it changed, why and which assumptions it made; consider the answer critically and use it to guide further checks rather than treating it as proof of correctness;
- reject unnecessary dependencies, compatibility layers and speculative abstractions;
- test successful, failing and cancellation paths appropriate to the change; and
- state the actual verification performed.

For changes with broad impact or difficult-to-detect failure modes, carefully reasoned and manually written code remains the safer default. This is not a ban on AI assistance: it means that the required human understanding, restraint and verification increase with the consequences of getting the change wrong.

### Elten interface conventions

A new interaction should feel like part of Elten rather than a separate utility embedded in it. Before designing a form or handling keys directly, inspect neighbouring scenes, the controls in `src/ui/controls/` and the helpers in `src/ui/dialogs.rb`. Match established behaviour for navigation, activation, cancellation, focus restoration, speech and sound.

Prefer the existing building blocks. `Form`, `ListBox`, `EditBox`, `Button`, `CheckBox`, `ChoiceListBox`, `TableBox`, `Tree`, `CalendarGrid` and `Player` already cover common interaction models. Short, conventional workflows should normally use helpers such as `alert`, `confirm`, `selector`, `select_action`, `input_text`, `display_text` and `display_table`. A multi-field workflow should normally use a `Form`; assign its `accept_button` and `cancel_button` so that Enter and Escape retain their usual meaning, and use `Form#wait` for a newly owned, contained interaction as described in the [architecture guide](architecture.md#owning-an-interaction).

Reusing these interfaces preserves more than naming. It brings the established key handling, focus behaviour, control markers, events, boundaries and user configuration with it. Attach secondary actions with `bind_context` and `Menu` where that is the established pattern instead of inventing unrelated shortcuts. Do not reproduce a list, editor, selector or dialogue with scene-owned key polling merely because the first version appears shorter. If a generally useful capability is missing, prefer a focused addition to the appropriate control or helper over a private workaround in one scene.

A genuinely different interaction may need controls or gestures beyond the usual pattern. Such exceptions must remain discoverable. Attach a short, translated tip to the affected control with `control.add_tip(p_("Feature", "Use ..."))`. Instance tips are combined with the control's own `#tips` and made available through Elten's Tips action for the currently active control. If the behaviour belongs to every instance of a reusable control, implement or extend that control's `#tips` method instead of repeating `add_tip` in each scene.

A tip should identify the gesture and its effect directly. It is supplementary guidance, not a way to excuse a surprising interaction or an unclear label. First consider whether the operation can follow an existing convention; add the tip when the exception is justified. Keep tips focused on behaviour which users would not reasonably infer from the control itself.

Keep the user-facing surface task-oriented and restrained. Do not mirror a server payload, object model or collection of internal flags in a form. Expose decisions which are meaningful to the user, use familiar language, give each dialogue a clear purpose and keep secondary operations out of the main path. Raw identifiers, protocol terminology and diagnostic detail belong in the interface only when users genuinely need them; otherwise keep them in logs or developer output. A complex implementation does not require a complex interaction.

Labels, announcements and errors should be concise and should begin with the information which distinguishes the current item, action or result. Speech is consumed sequentially, so repeated introductory wording slows navigation. Use existing sound cues to make recurring navigation and state changes quick to recognise. When a cue alone cannot communicate the necessary meaning reliably, provide concise speech as well, without obscuring more important output.

When extending an established workflow, preserve its terminology, key actions, context-menu structure and return focus unless changing one of them is the purpose of the work. Test the complete interaction rather than only the underlying operation: activation, cancellation, empty data, invalid input, errors, delayed completion and returning to the previous control are all part of the interface contract.

### Localisation

Elten uses Gettext, but translation artefacts are deliberately updated separately from ordinary code changes. When a feature or fix adds or changes translatable source strings, change the source only: do not regenerate `locale/elten.pot` and do not add the corresponding translations to `.po` files in the same commit or pull request.

The POT template is regenerated as a single coordinated update during release preparation. Batching extraction avoids repeated changes across a large generated file and reduces unnecessary merge conflicts between otherwise unrelated contributions.

A commit whose sole purpose is maintaining a translation may update the relevant `.po` files. Keep such work separate from source-code changes so that translation work and later merges have a clear boundary. The POT template should still be left to the scheduled release extraction unless the change is explicitly the coordinated template refresh itself.

When writing or translating localised text:

- preserve format placeholders and translation contexts;
- prefer complete, meaningful source strings over fragments assembled at runtime;
- keep translation-only changes separate from functional changes; and
- never edit generated POT entries by hand.

Localisation remains part of the feature even though its generated and translated files are updated later. Elten serves several language communities, so a clear source message and stable context are as important as the code path that displays it.

### Checks before submission

For most contributions, verification in the direct Ruby environment is sufficient. Running the client with `bundle exec ruby elten.rb` exercises the complete Ruby application, so building the C++ launcher or release binaries is not a routine pull request requirement.

A packaged build is useful when the change actually crosses that boundary: bootstrap and `filelist` loading, embedded source or assets, launcher behaviour, integrity metadata, native runtime integration, CMake or release packaging. Test the relevant package when practical and clearly state when it was not built or tested.

Before opening a pull request:

- run the client through the direct Ruby path described in the [building guide](building.md);
- exercise error, cancellation and slow-operation paths, not only the successful path;
- check the platforms affected by the change and clearly state those not tested;
- update `filelist` when adding Ruby source files;
- leave `locale/elten.pot` unchanged and do not edit `.po` files unless the contribution is solely a translation update;
- test a packaged launcher only when the changed boundary makes that verification relevant; and
- exclude generated `build/` or `dist/` output, local configuration, private keys and signing credentials.

## Reporting problems

### Security reports

Do not post a suspected vulnerability to a public forum. Follow the private reporting process in the [security policy](security.md), which provides direct email contacts for the project.

### Ordinary defects

Report an ordinary defect in the appropriate beta-testing forum listed under [Planning a change](#planning-a-change). Follow the current reporting form and instructions published there.

Do not include tokens, credentials or private message content in a public report. If the defect may have a security impact, stop and use the [private security process](security.md) instead.

## Submitting a pull request

In the pull request description, include the motivation, the approach taken, the affected elements and the checks performed.

Review may identify compatibility or interface-consistency concerns that are not visible from the changed code alone. Be prepared to adjust public interfaces while Elten 3 remains a release candidate.

By submitting a pull request, you confirm that you have the right to contribute its contents and agree that the contribution may be used in EltenLink, applications which depend on it, and other projects developed by the Prowadnica Foundation and Dawid Pieper.

Elten is distributed under the [GNU General Public License, version 3](../license). Thank you for investing your time and expertise in the project.
