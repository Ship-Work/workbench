# Meetings as a category-leading capability · 15 October 2026

The maintainer's brief for this session: make Workbench's meeting capability category-leading and well sanded, as a whole capability rather than a surface, and leave behind the PR or build-ready setup that gets it there. This record holds the evidence, the bar, the decisions, and what was deliberately not built, with the trigger that would bring each item back. It is grounded on the release-train head `59753fc` (PR [#353](https://github.com/Ship-Work/workbench/pull/353)), not on `main`, because that train carries the Meetings work of 14–15 October ([#343](https://github.com/Ship-Work/workbench/pull/343), [#349](https://github.com/Ship-Work/workbench/pull/349), [#369](https://github.com/Ship-Work/workbench/pull/369)).

**Status:** research and the first slice. Nothing here is installed acceptance or a release claim.

## 1. The single most important fact

Workbench Meetings has never recorded a real meeting. Counting the metadata of every recording folder on the maintainer's Mac (no transcript text was read):

| Edition | Recordings | Longest | Real calls | Apps used |
| --- | --- | --- | --- | --- |
| Workbench (Stable) | 5 | 39 s (QuickTime test) | 2 relayed phone calls through `com.apple.avconferenced`, 30 s and 28 s | QuickTime Player, Mac calling service, microphone only |
| Workbench Preview | 7 | 54 s (QuickTime test) | 0 | QuickTime Player, microphone only |

The capability behind those twelve folders has 288 Meetings checks, 21 live-voice checks and 19 experience checks, a dozen merged PRs and a product contract that reads well. Every entry in `MeetingAppCatalogue` is still marked `remoteAudioVerified: false`, and no check exercised the real Core Audio process tap. The 5 October live-voice evidence fed a fixture to the recognition adapter; nothing fed real sound through the tap that production uses.

The maintainer's own asks line up with that gap, in order: *"should meeting detection and offer to transcribe including phone calls"* (26 September); *"Meeting: failed but I only got through to voice mail"* (27 September, the one real attempt); *"Transcribe a meeting call feels completely covered up hard to find"* (30 September); *"the start stop, plus switch between headphones or mac should not stop the transcription"* and *"one-click Start across all meetings types is key… you can see the meeting you are in as live transcriptions are showing"* (5 October); *"Meetings feel hard to use with poor UI/UX, e.g. simple copy paste, or useful and simple degradation when security settings is missing"* (6 October). Since then the page gained a sidebar destination, Copy transcript, typed readiness, live words, reconnect, long-call fixes and a truthful recap. What never happened is a loop closed on a real call. The 6 October brief said it plainly: *"For Meetings include whether copied words serve the next real task."*

So the first category-leading move is not another feature. It is making the real pipeline provable by an agent, on this Mac, in a minute, and then making it true on the maintainer's calls.

## 2. An agent-runnable real-capture check

`LocalVoice --check-meeting-capture-native NEW_FOLDER [--self-end]` runs the production pipeline with no human, microphone or call app:

1. speaks a 74-word, two-voice fixture with `/usr/bin/say` (Daniel and Samantha where installed; the text is synthetic and in `fixture.txt`);
2. compiles a scratch player app with its own bundle identifier, `dev.workbench.meeting-fixture-player`, and launches it through LaunchServices so the Meetings picker lists it like any other audio app;
3. prepares the cached Parakeet v2 model through the real `RecognitionEngine` on an isolated defaults suite (it never downloads);
4. drives the real `MeetingModel` with `MeetingSystemProcessSource` and `MeetingSystemCapture`: select the player, app audio only, Start, then release the player's audio once the tap is attached;
5. watches the live session for the first sound and the first words, finishes (or, with `--self-end`, lets the player quit so the meeting ends itself through source loss), and reads the committed manifest, the live journal and the text History was asked to save;
6. writes `receipt.json` and `summary.txt` with timings, the word error rate against the fixture and every pass or fail.

What it establishes that no existing check does: the tap, aggregate device and IO proc on real Core Audio; the picker on real process metadata; live recognition on real captured audio with its real timing; Finish, commit and Copy transcript's text on that result; and, with `--self-end`, #343's self-ending path on a real lost source.

**The permission finding.** A refused process tap does not fail; it delivers silence (the code at `MeetingModel.swift` `CallAudioEvidence` already relies on this). Run from a bare debug binary, the probe created a tap without error and received zeros for the whole fixture. The check therefore reports ten seconds of silence as the permission result, names the identity, and says to run through the signed app: `open -n -W -a "Workbench Preview.app" --args --check-meeting-capture-native NEW_FOLDER`, which is how `--check-persona-voice-native` and `--persona-check` already run. From the debug binary on this Mac the mechanics passed up to that point: fixture 26.7 s, player listed, admission "Ready to record", Start in 0.29 s, Parakeet from cache in 19.4 s, then the honest permission failure.

Results from the signed Preview identity are in [the verification record](../verification/2026-10-15-meeting-capture-native/README.md).

## 3. Figma on Codex: what it is and whether it helps here

The Codex app on this Mac has Figma's plugin cached (`~/.codex/plugins/cache/openai-curated-remote/figma/15.0.0`, fourteen skills) but not enabled: `config.toml` lists no `figma` plugin, and the plugin requires the Figma connector (an OAuth sign-in to Figma from the Codex app). No Figma desktop app is installed. Finishing the setup is a Codex-app action the maintainer takes: Plugins → Figma → enable, then connect the Figma account. Nothing in a repository can do that.

What the plugin would let an agent do, from its own skill files and Figma's documentation (checked 15 October 2026):

- **Design to code** (`figma-design-to-code`, `figma-swiftui`): read a Figma frame as structure and a screenshot, then implement it in SwiftUI. Useful only once a Figma design exists.
- **Code to design** (`figma-generate-design`, `figma-use`): build Figma screens from code through the Plugin API, using a published design system's components. The pixel-capture tool that makes this fast ("live UI from your browser") is browser-only; a native Mac window cannot be captured, so Workbench screens would be rebuilt by hand from code, component by component.
- **Code Connect** maps Figma components to code snippets; its SwiftUI route is the legacy integration, and the plugin's own skill states an Organization or Enterprise plan is required.
- Figma's remote MCP server works on Starter and Professional plans; writing outside drafts needs a Full seat. The desktop server needs a Dev or Full seat on Professional or above.

**Decision for Meetings: not now.** Workbench already renders every Meetings state from real code (`--render-surfaces`, 350 renders with byte-identical before/after pairs on #343), keeps interactive studies in `docs/experience/`, and has a design-studio artifact of real renders. A Figma source of truth would be a second description of the same screens, maintained by hand, that drifts the moment a view changes, and the capability's problem is unverified behaviour on real calls, not a lack of design exploration. **What would change it:** a design pass that needs component-level exploration a renderer cannot give (for example a new live-meeting surface in the pill with several candidate layouts to compare), a Figma account on a plan with a Full seat, and the connector enabled in Codex. The durable way for an agent to then contribute: build the candidate screens in Figma from `MeetingWorkspaceView.swift` and `LiveVoiceTranscriptView.swift` with `figma-generate-design`, compare them in Figma, and implement the chosen one with `figma-swiftui`'s design-to-code reference against the surface gallery as the acceptance renderer. Without that trigger, the renderer is the design tool.

## 4. The bar, the map and the decisions

Filled in from the two review workflows run in this session: a subsystem map with adversarially verified defects, and a survey of Granola, ChatGPT Record, Apple's own call and Notes transcription, local Mac tools, bot-based leaders, platform AI, on-device speech models and managed-Mac policy. See the sections below once they land; until then this record carries only what was verified first-hand above.
