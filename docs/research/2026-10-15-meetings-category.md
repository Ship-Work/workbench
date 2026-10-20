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

## 2a. What this session built, in [#374](https://github.com/Ship-Work/workbench/pull/374)

Each item is a Quality change at its owner with a check that fails without it, reviewed by an independent adversarial reader whose findings are fixed in the branch. Every count is from the branch head on this Mac.

| Item | Why it comes first | Owner |
| --- | --- | --- |
| The real-capture check (section 2) | Nothing else can be believed until the pipeline is provable without a human | `MeetingCaptureNativeCheck` |
| Silence from the chosen app is explained during the call and in the saved notes | The first thing a refused permission does is record a silent call and blame the other side; this Mac's Preview is in that state today | `MeetingSilenceHint`, `MeetingSummary.gaps` |
| A device change restarts only the source it affects, a change on the other route joins a running recovery, and each recovery tick is one checked rule | The maintainer's own ask: switching headphones must not stop the transcription; before, it gapped both tracks | `MeetingRouteRecovery`, `MeetingSystemCapture` |
| Live words outlast a boundary the next decode cannot match, and a backlog; a pass that dies says so | One re-decoded word at a commit boundary ended live words for the rest of a long call | `LiveVoiceWindow`, `LiveVoiceService`, the caption |
| A recording keeps its controls with the toolbar hidden; Quit asks first | The contract promised the first; a ⌘Q meant for the call app lost the live words to Kept for later | `FloatingToolbarSurface.resolve`, `MeetingQuitChoice` |
| Prepare follow-up… offers the bundled Meeting notes and follow-up skill | The skill written for exactly this job was unreachable from the meeting's own door | `MeetingFollowUp.reviewSkills` |
| The offer reaches a full-screen call and other Spaces | One-click Start for every meeting type was not true for a full-screen Teams or Zoom | `MeetingOfferPanelController.configure` |
| The site describes Meetings as it works and names the permission as macOS does | Public claims must match the accepted artifact | `site/` |

Checks on the branch head: `--check-meetings` 326 meeting, 34 removal, 27 live voice and 27 experience checks (292, 34, 21 and 19 on the train head); `--check-floating-toolbar` 223; `--check-core` clean; `--check-handoff-jobs` 223; `--render-live-voice` 12 renders including the silent-app state; the surface registry 689 entries, unchanged; site tests 23. Hardware acceptance for the device-change work, the real-call acceptance in #280, and the permission-dependent run of the real-capture check are owed and listed in the PR.

## 3. Figma on Codex: what it is and whether it helps here

The Codex app on this Mac has Figma's plugin cached (`~/.codex/plugins/cache/openai-curated-remote/figma/15.0.0`, fourteen skills) but not enabled: `config.toml` lists no `figma` plugin, and the plugin requires the Figma connector (an OAuth sign-in to Figma from the Codex app). No Figma desktop app is installed. Finishing the setup is a Codex-app action the maintainer takes: Plugins → Figma → enable, then connect the Figma account. Nothing in a repository can do that.

What the plugin would let an agent do, from its own skill files and Figma's documentation (checked 15 October 2026):

- **Design to code** (`figma-design-to-code`, `figma-swiftui`): read a Figma frame as structure and a screenshot, then implement it in SwiftUI. Useful only once a Figma design exists.
- **Code to design** (`figma-generate-design`, `figma-use`): build Figma screens from code through the Plugin API, using a published design system's components. The pixel-capture tool that makes this fast ("live UI from your browser") is browser-only; a native Mac window cannot be captured, so Workbench screens would be rebuilt by hand from code, component by component.
- **Code Connect** maps Figma components to code snippets; its SwiftUI route is the legacy integration, and the plugin's own skill states an Organization or Enterprise plan is required.
- Figma's remote MCP server works on Starter and Professional plans; writing outside drafts needs a Full seat. The desktop server needs a Dev or Full seat on Professional or above.

**Decision for Meetings: not now.** Workbench already renders every Meetings state from real code (`--render-surfaces`, 350 renders with byte-identical before/after pairs on #343), keeps interactive studies in `docs/experience/`, and has a design-studio artifact of real renders. A Figma source of truth would be a second description of the same screens, maintained by hand, that drifts the moment a view changes, and the capability's problem is unverified behaviour on real calls, not a lack of design exploration. **What would change it:** a design pass that needs component-level exploration a renderer cannot give (for example a new live-meeting surface in the pill with several candidate layouts to compare), a Figma account on a plan with a Full seat, and the connector enabled in Codex. The durable way for an agent to then contribute: build the candidate screens in Figma from `MeetingWorkspaceView.swift` and `LiveVoiceTranscriptView.swift` with `figma-generate-design`, compare them in Figma, and implement the chosen one with `figma-swiftui`'s design-to-code reference against the surface gallery as the acceptance renderer. Without that trigger, the renderer is the design tool.

## 4. The bar

Eight research clusters were surveyed on 15 October 2026 (Granola and the no-bot Mac tools, ChatGPT Record and the assistant apps, Apple's own call and Notes transcription and the macOS 26 speech and tap APIs, local Mac tools, the bot-based leaders, platform AI in Zoom/Teams/Meet, on-device models and diarization, managed Macs and consent law) and synthesised into a bar for a local, private, no-bot Mac meeting capability whose output feeds the person's own agents. Vendor claims were separated from observed behaviour; a run limitation is recorded at the end. The rows that decide work are below; the full synthesis stays with this session's workflow transcript and can be regenerated. **The Workbench column is the contract and the source at the train head, not observed behaviour: no Workbench claim in it has been seen on a real call** (section 1). An independent critic re-fetched the dated vendor claims on the same day; its corrections are folded in below and listed after the table.

| Dimension | Table stakes in the field | Workbench at the train head | Gap |
| --- | --- | --- | --- |
| Starting | One click, no bot, nothing transcribed before the click; Granola's detection prompt names the app and offers one button | Explicit Start on a chosen app plus microphone; opt-in detection offers one Start | small: the offer must reach a full-screen call (fixed in #374) and be announced |
| Ending | Explicit Stop plus honest automatic ending: stop when the app releases audio, nudge after minutes of silence, stop on sleep, cap that still saves (ChatGPT Meetings, Granola) | Finish; guarded automatic finish on supported apps after 20 s of no audio activity; the two-hour cap and a lost source now end with a transcript (#343) | large on the field's terms, small in practice: sleep and lid-close behaviour unverified; a silence nudge is unbuilt |
| Consent and visible state | A visible recording state; a plain statement that the reminder is visible to you and does not notify others; a region-varies warning | Visible state, silent after opt-in by the maintainer's decision; no written consent line | small: write the line, as ChatGPT's docs do |
| Live view | A live transcript with pause, resume and copy while the call runs; a floating indicator when another app is in front | Live words on the page; the pill shows a red dot and Finish (and, after the live stream here, keeps them with the toolbar hidden) | small; a stay-on-top transcript conflicts with the pill contract and stays declined |
| Speakers | At least a deterministic Me/Them from microphone and system audio; every diarizer in the field is reported splitting or swapping speakers | You/Others from two tracks; no diarization by decision | none: the deterministic split is the stronger promise |
| Accuracy and names | An editor, a custom vocabulary, a verify-names warning; names and numbers are the universal complaint | Original and current wording, original audio kept; no vocabulary for meetings | small: the person's Dictate dictionary is not applied to meetings |
| Languages | 16 to 32 languages, one per meeting; local tools pair a fast English path with a multilingual model | Parakeet v2, English only | large; Parakeet v3 (24 languages) is already cached on this Mac from the 1 October measurements |
| Device switching | Capture continues across headphones; an Auto microphone; written Bluetooth caveats; no vendor documents a guarantee | Reconnect on device change; at the train head a change restarted both sources (addressed in the audio stream here); hardware acceptance owed | small, and an edge once proven |
| Long calls | Two hours is the floor: ChatGPT 240 min, Meetings 4 h, Granola unbounded; silent failure is the worst-rated behaviour | Two hours, the shortest cap in the field; long calls stay responsive and always save (#343); silence from a refused tap was unexplained (addressed here) | large on the cap, small on reliability |
| Saving and recovery | Saved automatically at the end; quitting keeps what exists; discard is a deliberate second step | Kept for later, same-UUID retry, quit recovery; ⌘Q during a recording did not ask (addressed in the live stream here) | small |
| Review and click-to-play | Click a word to seek where audio is kept (Voice Memos, Otter, Krisp); the cloud leaders delete audio and carry that as their top complaint | Review recording with play and seek; Review transcript; the two are separate sheets | small, and the clearest unique edge |
| Search and finding later | Search across transcripts; find within one | History search; no in-transcript find | small |
| Titles and context | Calendar titles and attendees; without a calendar, app plus time | App plus time; on-device name suggestions; calendar declined | small by decision |
| In-meeting typed notes | Every leader keeps the person's own typed notes beside the transcript, distinguishable from anything generated; reviewers choose Granola for it | None | large; not a non-goal (automatic notes are) |
| Notes and action items | A summary with action items within a minute, templates, regenerate | Hand off to the person's own agent with a bundled skill; result returns to History | deliberate non-goal in the app; the handoff is the answer |
| Follow-up outputs | Copy, export, a follow-up draft, share without the transcript | Copy transcript, Export text, Prepare follow-up | small: copy the follow-up message alone |
| Destinations | Clipboard and text everywhere; local tools add Shortcuts, CLI, watched folders or an MCP surface; the universal agent destination is a plain file in a known folder | Copy, Export, Claude Code and Codex | small |
| Privacy and data, managed Macs, cost | On-device, no account, the narrowest grant (the tap route), free | All of these | none |

**Edges to make true, none of them unique.** The synthesis first called six behaviours unique; the critic disproved each as a claim and they stand instead as strengths Workbench can publish once proven: the recording you can replay (Otter keeps audio and seeks by word on its free plan; Workbench keeps the file but has no word-to-seek yet); one-click Start on a Phone or FaceTime call through the Mac calling service (Granola detects FaceTime through system audio and Audio Hijack lists both apps; Workbench's route is first-hand evidence from two relayed calls, not a daemon map); You/Others from two tracks (Granola's Me/Them is the same table stake; Workbench's version is only a guarantee once speaker-mode leakage is handled, which the live path does not do today); nothing outside the Mac after a one-time 443 MB model download (Anarlog, Meetily and MacWhisper are local too); hand-off to the person's own agent with a bundled skill (Anarlog ships a CLI, an MCP server and a skill); and device switching as a tested promise (Jamie and Audio Hijack publish one; nobody publishes a test, which is what the real-capture check and the audio stream here are for).

**Traps the field shows, which the contract already avoids:** calendar as the primary trigger; default-on detection; deleting audio as privacy; ScreenCaptureKit as the price of app audio; a system-wide tap; mixing microphone and app audio before recognition; a single key that discards a recording; in-app chat, templates and share links; virtual audio devices; action items that run without approval; transparency features that are off by default and fragile; Speaker 1/Speaker 2 guesses.

**Corrections the critic made to the synthesis** (each re-fetched on 15 October 2026): Granola's MCP is on every plan, limited to 30 days of personal notes on Basic; Granola documents only the Bluetooth headset quality drop, and its mid-call stops are network failures; Jamie's AutoStop is a changelog entry of 16 August 2026 and its auto-start is off by default; MacWhisper 15.2's behaviours are vendor claims relayed by press; the SpeechAnalyzer accuracy figures are a read-speech benchmark from a site that links a transcription product; Apple staff pointed one developer to the Core Audio taps documentation without comparing APIs; Apple's regional availability for call recording is unsourced and dropped; Superwhisper's Parakeet v3 is a paid tier; three OpenAI and Krisp help pages could not be re-fetched (HTTP 403) and keep their earlier reading. Workbench's own IT record (`docs/it/README.md`) already answers the managed-Mac question: a profile can neither allow nor deny system-audio capture.

**Dimensions the bar does not yet hold**, each worth a row when the next pass runs with search available: speaker-mode leakage when the far side plays through the Mac speakers (a precondition of the You/Others claim); microphone-only and in-person meetings; the first-run and permission journey as the person sees it, including a refused tap; the resource cost of a two-hour on-device session beside Zoom or Teams; start-from-anywhere entry points, which the maintainer's 30 September complaint was about; retention and deletion controls; portability of History across his two Macs and backups; Australian-English accent robustness; VoiceOver and keyboard-only operation; interruptions (a second call, lock, sleep, the app quitting, a restart); measured live-word latency; and the jurisdiction-specific legal posture the consent cluster collected (NSW Surveillance Devices Act s7, the TIA Act, US all-party states).

## 5. Decisions: not now, and what would change each

| Idea | Source | Why not now | What would change it | Where the switch lives |
| --- | --- | --- | --- | --- |
| Figma as a design source for Meetings surfaces | the maintainer's prompt | A second, hand-maintained description of screens the renderer already draws from real code; the capability's problem is unverified behaviour, not design exploration; the plugin is not enabled and native windows cannot be captured | A design pass needing component-level comparison of several candidate layouts, a Figma plan with a Full seat, and the connector enabled in Codex | section 3 above; `docs/experience/` and `--render-surfaces` remain the design tools |
| Languages beyond English (Parakeet v3) | the bar: the first complaint to expect | A new recognition engine is a #280 non-goal; v3's accuracy and speed on this Mac were measured on 1 October ([model providers](../model-providers.md)) and not adopted for English | A real non-English meeting the maintainer needs, or a colleague's; then a Models choice per the Grammar ("engines are chosen once, by job") | Settings › Models; `RecognitionLocalModels` |
| A typed scratchpad during the meeting, kept beside the transcript | the bar: every leader; the strongest input for the follow-up agent | New control on the live page and new persisted text; automatic notes are a non-goal and this is adjacent; no ask yet | The maintainer writing notes elsewhere during calls (count it in ask history), then an Option of Meetings: one text field, saved with the transcript, passed to Prepare follow-up as "your notes" | `MeetingWorkspaceView` live card; `Transcript` metadata |
| Raise or soften the two-hour cap | the bar: the shortest cap in the field | Decided ceiling tied to the recogniser's segment plan and disk budget; no meeting here has exceeded one minute | A real call that hits the cap, or the maintainer's calendar showing regular meetings over two hours; then a continuation recording with paused time excluded | `MeetingSegmentPlan.maximumMeetingSeconds`; `MeetingModel.watch` |
| Click a transcript turn to hear that moment | the bar: the clearest unique edge | Two sheets today; needs the live journal's word times and the batch path's segment times joined to the player | After the real-call acceptance, as a Quality change inside Review transcript with Review recording | `TranscriptReview`, `MeetingRecordingReview` |
| A silence nudge and sleep handling at the end of a call | the bar: ChatGPT Meetings | Guarded automatic finish already ends supported apps after 20 s of no activity; sleep behaviour is unverified rather than wrong | A real call left running overnight, or a lid-close test on the installed Preview | `MeetingAutoFinish`; `MeetingModel.watch` |
| Echo handling on the live path (a microphone utterance that repeats the app track) | the recognition map; the critic's missing dimension | The batch path drops echoes; the live path, which now produces most saved transcripts, does not, so a laptop-speaker call saves the other side's words as You | A real laptop-speaker call shows duplicated turns; then the batch rule applied at live commit, with the identical-reply guard kept | `LiveVoiceTurns`, `MeetingConversation.withoutEchoes` |
| Apply the person's Dictate dictionary to meeting transcripts | the recognition map | Parakeet offers no vocabulary boost; a post-pass replacement would alter original wording | A measured misheard-name rate on real calls; then a current-wording pass that keeps the original | `MeetingConversation`; the dictionary owner in Dictate |
| Copy the follow-up message alone | the handoff map | Needs the skill's output sections to be reliable first; the result is already copyable whole | A second real follow-up where only the message was wanted | `HistoryView` result actions |
| A written consent line and a region-varies note | the bar: ChatGPT's wording; the Otter and Granola suits | The maintainer decided silent after opt-in; a line of documentation is not a feature | Write it in the guide and privacy page with the next site change; revisit if a ruling establishes participant-side notice | `site/privacy.html`, `site/guide` |
| Safari calls through the shared WebKit audio service | the detection map (verified) | Tapping `com.apple.WebKit.GPU` captures every WebKit app's audio; the maintainer uses Chrome | A Safari-based call the maintainer takes; then a labelled "WebKit audio (shared)" offer rather than a Safari entry | `MeetingAppCatalogue` |
| The offer as a system notification with Focus honoured | the detection map | A notification is a new entry point and a new permission; the panel now reaches full-screen calls | The panel still being missed in real use | `MeetingOfferPanelController` |
| An on-disk transcript folder, Shortcuts action or MCP surface for other agents | the bar: destinations | A second place for captured work; Copy and the Claude Code/Codex hand-off cover the maintainer's agents | A repeated need to feed another tool; then export to a chosen folder, not a new store | `History` export |
| Registry entry for the Meetings page's Sound Settings… button | the registry map | A page-local control that opens System Settings; the checker treats page-local controls as out of scope and passes today | A rule that external-settings openers are entry points | `docs/surfaces.json` |

A research-run limitation: the shared web-search budget ran out part way through the bot-leaders cluster, and three clusters (local Mac tools, speech models and diarization, managed Macs and consent) came from the second run; the synthesis names what it could not confirm.

## 6. Verified defects

Eight readers mapped the subsystems; every defect they claimed was judged by two skeptics (correctness and reachability) and kept only when both found it real. 49 survived, 9 were dropped, and a completeness critic then read the joins between subsystems. Status names what [#374](https://github.com/Ship-Work/workbench/pull/374) built; everything marked open is build-ready with its file and line, and [#377](https://github.com/Ship-Work/workbench/issues/377) carries the same list for the next agent.

| Severity | Area | Defect | Where | Cost | Status |
| --- | --- | --- | --- | --- | --- |
| P1 | recognition-live | One ambiguous or re-decoded word at an 8 s commit boundary ends live words for the rest of the meeting | `LiveVoiceService.swift:105` | M | #374 |
| P2 | audio-capture | A refused Audio Recording permission is never reported: the meeting records silence and History blames the other people | `MeetingAudio.swift:653` | M | #374 (silence explained; a refusal is still not provable from code) |
| P2 | detection-admission | Offer panel never appears over a full-screen call and is gone after 20 s with no other surface | `MeetingWorkspaceView.swift:426` | S | #374 (full-screen and Spaces; the 20 s window stays) |
| P2 | detection-admission | Safari calls are never offered: the catalogue's Safari entry cannot match the WebKit audio process | `MeetingModels.swift:58` | M | open |
| P2 | handoff-followup | Copy instructions route can never return a result: Home says "no result yet" forever and loses Prepare follow-up… | `HandoffJobs.swift:843` | M | open |
| P2 | recognition-live | After live recognition dies mid-recording the caption says 'Words are catching up' forever | `LiveVoiceTranscriptView.swift:21` | S | #374 |
| P2 | recognition-live | Live-completed two-source meetings never drop microphone echoes; on laptop speakers the other side's words are saved as You | `LiveVoiceSession.swift:68` | M | open |
| P2 | recognition-live | Snapshots publish at ≥10 Hz and every publish rebuilds and remeasures the whole transcript on the main thread | `LiveVoiceService.swift:232` | M | open |
| P2 | ui-surfaces | Hide toolbar on: a recording meeting shows no pill, dot or Finish anywhere on screen | `CapturePanel.swift:423` | S | #374 |
| P2 | ui-surfaces | An app source that never delivers audio reads 'Quiet' for the whole call; a refused tap is indistinguishable from silence on every surface | `LiveVoiceService.swift:195` | M | #374 |
| P3 | audio-capture | Any default-output change (headphones, AirPods, display audio) tears down both sources, so the microphone track loses audio on every switch and mic-only Dictate reports 'The microphone device changed' | `MeetingAudio.swift:1000` | M | #374 (per-route restart; hardware owed) |
| P3 | audio-capture | When the chosen app quits or crashes mid-meeting the microphone is also cut for the 15 s recovery window before the recording ends | `MeetingAudio.swift:874` | S | #374 (per-route restart) |
| P3 | audio-capture | Hitting the two-hour ceiling (or an overlap stop) also reports 'could not be written and are missing' for the rejected packet | `MeetingAudio.swift:273` | S | open |
| P3 | audio-capture | FaceTime, Phone and Safari picker entries tap a bundle whose call/media audio plays in a service the tap excludes | `MeetingModels.swift:55` | S | open |
| P3 | detection-admission | Snooze, Not now and Change source suppress offers invisibly; switching detection off and on does not clear a snooze | `MeetingDetection.swift:152` | S | open |
| P3 | detection-admission | A running app reads as 'no longer available' when its representative process changes | `MeetingDetection.swift:121` | M | open |
| P3 | detection-admission | Source caption asserts headphone voices are recorded; the written unverified-app caution is dead code | `MeetingWorkspaceView.swift:275` | S | open |
| P3 | detection-admission | 'Finish when call audio ends' caption says only microphone-only recordings finish manually; any unrecognised app never auto-finishes | `MeetingDetection.swift:105` | S | open |
| P3 | detection-admission | A stale metadata error is re-raised every 3 s as the page's problem, replacing other problems, until a successful refresh | `MeetingModel.swift:720` | S | open |
| P3 | docs-site-registry | Site hero art names a remote speaker and shows participant avatars; the app labels only You/Others | `index.html:115` | S | #374 |
| P3 | docs-site-registry | Site says “Turn on Meetings” and the guide says “Start on the detected call” without the off-by-default opt-in | `index.html:121` | S | #374 |
| P3 | docs-site-registry | Prepare follow-up offers only the generic follow-up skill; the bundled Meeting notes and follow-up skill is unreachable from Meetings and Home | `WorkbenchHome.swift:249` | S | #374 |
| P3 | handoff-followup | Prepare follow-up… offers only the generic skill; Meeting notes and follow-up and Coach are unreachable from the meeting's own door | `WorkbenchHome.swift:249` | S | #374 |
| P3 | handoff-followup | Prepare follow-up… → Start task loops on an error when the meeting's earlier follow-up failed, was stopped or was interrupted | `HandoffJobs.swift:792` | S | open |
| P3 | handoff-followup | A long meeting hits the 100,000-character connected limit with a message that cannot be followed for one transcript | `HandoffRunReadiness.swift:47` | M | open |
| P3 | lifecycle-recovery-storage | "Free about 500 MB" promises a safe meeting; two PCM tracks exhaust that budget in roughly half an hour | `MeetingModels.swift:306` | S | open |
| P3 | lifecycle-recovery-storage | After History commits but the final `.committed` journal write fails, Meetings says saving could not finish and offers Transcribe again | `MeetingRecovery.swift:267` | S | open |
| P3 | lifecycle-recovery-storage | Automatic finish saves the meeting with no note that Workbench ended it | `MeetingModel.swift:668` | S | open |
| P3 | lifecycle-recovery-storage | The two-hour cut arrives with no warning and counts paused and reconnecting time | `MeetingModel.swift:651` | M | open |
| P3 | recognition-live | A continuous speaker is split into a new 'You:' paragraph at every pause over 0.8 s, in the live view and the saved transcript | `LiveVoiceSession.swift:71` | S | open |
| P3 | recognition-live | Batch echo drop uses symmetric Jaccard, so a short microphone fragment inside a long remote utterance is never dropped | `MeetingConversation.swift:121` | S | open |
| P3 | recognition-live | Format-2 'original wording' zips both speakers' words together by start time | `LiveVoiceSession.swift:56` | S | open |
| P3 | ui-surfaces | Keep recording is not offered on the menu-bar panel or Home during the auto-finish countdown | `MeetingWorkspaceView.swift:9` | S | open |
| P3 | ui-surfaces | Panel and Home row read 'Meetings · finishing' with 'Stop processing' while a meeting is starting | `MeetingWorkspaceView.swift:11` | S | open |
| P3 | ui-surfaces | Live transcript labels every turn 'You' (or 'Others') for single-source recordings; the saved text has no labels | `MeetingWorkspaceView.swift:143` | S | open |
| P3 | ui-surfaces | History row and Review transcript claim 'Original recording' from the transcript's purpose alone; Review recording then fails | `CaptureHistoryView.swift:93` | S | open |
| P3 | ui-surfaces | The proactive offer panel is pointer-only: not announced, no keyboard focus, no Escape | `MeetingWorkspaceView.swift:426` | M | open |
| P3 | ui-surfaces | No warning before the two-hour limit on any surface; the meeting ends itself | `MeetingModel.swift:651` | S | open |
| P4 | docs-site-registry | Registry omits the meeting page's Sound Settings… opener while registering Dictate's | `surfaces.json:294` | S | open |
| P4 | docs-site-registry | README never mentions Meetings | `README.md:10` | S | open |
| P4 | docs-site-registry | Site names the call-audio permission “Audio Recording”, which macOS 15+ lists as Screen & System Audio Recording | `privacy.html:109` | S | #374 |
| P4 | lifecycle-recovery-storage | Derived segment WAVs are never removed after a meeting commits | `MeetingRecovery.swift:266` | S | open |
| P4 | lifecycle-recovery-storage | Every recovery refresh fully inspects every session, including reading and decoding each committed meeting's live journal twice | `MeetingRecovery.swift:31` | S | open |
| P4 | recognition-live | Details receipt says 'Apple Intelligence' even when both Apple Intelligence calls failed or timed out | `LocalDetailSuggestions.swift:44` | S | open |
| P4 | ui-surfaces | Menu-bar panel shows two 'Finish meeting' controls: the Dictate row relabels itself and the Meetings row repeats it | `WorkbenchControlTool.swift:201` | S | open |
| P4 | ui-surfaces | Outside the window a meeting has no elapsed time: the pill hint, chooser row and panel row omit it | `FloatingToolbar.swift:211` | S | open |
| P4 | ui-surfaces | New recording… leaves the previous meeting's full transcript on the page under Start recording | `MeetingWorkspaceView.swift:141` | S | open |
| P4 | ui-surfaces | Home's Current work meeting row lacks the red record symbol, elapsed time and row style the other recordings use | `WorkbenchHome.swift:726` | S | open |
| P4 | ui-surfaces | Recording review says 'Finish the current capture or reading' although Read is retired | `MeetingRecordingReview.swift:232` | S | open |

**What the critic found between the subsystems**, with file and line:

- **P2** Start on the floating offer panel pulls Workbench's window over the call and activates the app (`MeetingWorkspaceView.swift:396`).
- **P2** The route watchdog ends a recording whose chosen app stops delivering buffers, pre-empting the guarded Finish and tearing the microphone down every 2 s meanwhile (`MeetingAudio.swift:1009`).
- **P2** ⌘Q during a recording stops it silently, discards the live words and leaves a batch Transcribe for later; unsaved narration gets a confirmation but a meeting does not (`main.swift:751`).
- **P3** A long two-track meeting on the batch path silently loses its You/Others labels past 2,000 utterances on one track (`MeetingConversation.swift:53`).

**Cross-subsystem risks** the critic traced: Audio-capture watchdog versus the guarded auto-finish: the two mechanisms are mutually exclusive by an unverified tap behaviour; Detection offer → shell navigation: the offer's Start ends in Workbench's window, not in the call; Shell quit → Meetings and Handoff: termination cancels a recording and a running follow-up with no confirmation; Recognition-live failure → recovery → History: an incomplete live pass turns a long meeting into a long, speaker-unlabelled batch save; Recovery success is a conjunction over both recorders, so the microphone's reconnection is hostage to the app lane; Checks that enshrine the behaviours above or pass without exercising the production path.

**The maintainer's decided requirements, as the code stands at the train head** (the critic's reading; #374 moves one-click Start, live words and device switching forward and does not change the silent-recording decision, which three contract lines forbid and which needs the maintainer's call before code):

| Requirement | Status | Evidence |
| --- | --- | --- |
| One-click Start for every meeting type | Partial | Catalogue apps and the Mac calling service get an offer with Start (MeetingDetection.swift:150-187; MeetingWorkspaceView.swift:424-441), but that Start fronts Workbench over the call (MeetingWorkspaceView.swift:393-398; main.swift:388, 714-716), lives in a 20  |
| Silent recording after opt-in with a visible recording state | Not implemented; blocked by the contract | Every recording needs a click on the offer or page: refreshDetection only publishes `offer` (MeetingModel.swift:711-718) and the contract forbids self-start (workbench.md:103 rule 5 'A recording always starts from the person's choice'; live-voice.md:25 'never  |
| Live words while in the meeting | Partial | Implemented for Parakeet (MeetingModel.swift:348-357; LiveVoiceService.swift:171-257) and shown on the Meetings page only (MeetingWorkspaceView.swift:141-145); live-voice.md:21 forbids a transcript on the pill, so nothing shows words while the call app is in f |
| Headphone/device switching must not stop a transcription | Partial; a self-end path exists and is checked as a feature | A default-device change begins recovery rather than a stop (MeetingAudio.swift:1000-1005) and the session identity survives (MeetingModel.swift:644-646), but recovery rebuilds both sources with a gap on both tracks (956-963, 1047-1055), requires a buffer from  |
| Copy transcript always works | Holds | MeetingTranscriptCopy.copy resolves the committed UUID in History and refuses only a removed or empty record (MeetingCompletion.swift:6-14); AppModel.copyMeetingTranscript → copyTextWithReceipt has no phase, model or assistant guard and always sets `status` to |
| Hand off once | Holds for the connected route; the journey fails around it | Identical task + inputs + skill reuse the earlier job by fingerprint (HandoffJobs.swift:281-293), `activeID` refuses a second start while one runs (786), a completed job returns a notice instead of a new run (792-793), and Meetings and Home pass the same task  |

The critic's single highest-value next step is the same as this record's: one native run of a real call app leaving a call while Workbench records, with a headphone switch during it. It settles whether a tap-only aggregate keeps delivering while the tapped app has no running audio, which decides whether the route watchdog or the guarded Finish ends such a call, and it is cheaper than any fix it would direct.

