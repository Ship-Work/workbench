# Meetings: live words without the call's echo, whole turns, each speaker's words together, and publishing on change

Branch `claude/meetings-live-words`, from the integrated release candidate (`main`, the 15 October train #353 and Meetings #374, head `2ff25df`). Refs #377, #280. Grammar: Quality for every change; no entry point, setting or saved format was added or changed. Synthetic data only: injected recognisers, fixture audio and a generated `say` fixture. No microphone, tap, call app, installed app or privacy setting was used.

## What changed

1. **P2 · A meeting saved from its live pass now drops the microphone's copy of the call.** On laptop speakers the microphone hears the other side. The saved-audio path dropped that echo; a meeting whose live pass completed saved it as You, interleaved word by word with the real words. `LiveVoiceTurns.group` now cuts each source's words into utterances as the saved-audio path cuts a track (0.6 s of silence, at most 25 s) and applies the same echo rule (`SpeakerEcho`) before building turns. Live words know their times, so the microphone's are also cut where the other side starts or stops speaking (with 0.3 s for the speaker-to-microphone delay and loose word boundaries): a quick reply right after the other side finishes is judged on its own words, not dropped with the echo before it. Every caller of `group` gets this: the saved conversation and original wording (`LiveVoiceCheckpoint`), the live snapshot, and the turns `MeetingModel` and `AppModel` show at finish. The live journal still keeps every recognised word; the echo drop is a projection, so an existing journal reads the same way.
2. **P2 · Live snapshots publish on change, and the view rewrites only what changed.** The live loop passes ten times a second and published a snapshot on every pass. Each one rebuilt the turns and, on the main thread, built the whole transcript's attributed text and compared it with the text view's. `LiveVoiceService` now rebuilds turns only when words change and publishes when something a page shows changes (words, phase, a source's health or note, the delayed and incomplete flags), and the meter level and elapsed time at most once a second; no page shows either from the snapshot, since each model keeps its own clock. New words and the final state are published at once. `LiveTranscriptText.Coordinator` keeps the turns it shows and where each ends in the text, and rewrites only from the first turn that changed; an update that changes nothing (the page's clock ticks it twice a second, and Dictate's meter about twelve times) touches nothing. The turn rebuild on the service's thread is still a pass over the whole transcript, but only when words change, about once a second per source, never on the main thread. Making it incremental would not hold up: words settle only once both sources have committed past them, and a silent app track never commits.
3. **P3 · A continuous speaker stays one turn.** Turns split at any same-source gap over 0.8 s, so a speaker who paused between sentences got a new "You:" paragraph each time, live and saved. A source's utterances now stay one turn until the other source speaks or it pauses for two seconds (`LiveVoiceTurns.pauseSeconds`). Why two seconds: people pause for a second or more inside one turn, two seconds is twice the silence a conversation usually leaves unremarked, and it is the saved-audio path's own join (`MeetingConversation.conversation`, which now uses the same constant), so a meeting reads the same whichever path saved it. A real turn change still splits at once, because the other source's words come between. In the live view a speaker's provisional words also continue their confirmed turn, quieter, instead of opening a second speaker line at every eight-second commit (`LiveTranscriptText.continues`).
4. **P3 · The saved-audio echo drop catches a short fragment inside a long remote utterance.** It compared word sets both ways (Jaccard), so "the budget needs to go" inside a 20-second remote utterance scored about 0.2 and was saved as You. `SpeakerEcho.isEcho` keeps that test and adds a containment test for the short side: a microphone utterance no longer than the app's is an echo when the app said at least three quarters of its words in the same order within a few seconds of it (the app's words are spread evenly over its utterance, because a saved clip has no word times; the window is two seconds or a fifth of the utterance, whichever is longer). A reply such as "Yes" is kept unless the other side said it then, including when they said it at the start of the same long turn.
5. **P3 · The format-2 original wording keeps each speaker's words together.** `LiveVoiceCheckpoint.text`, saved as a live meeting's original wording (`MeetingManifest.liveText`, the History record's `rawText`), sorted both speakers' words by start time, so two people talking at once came out zipped together ("Thanks so No much problem everyone"). It is now the conversation's words without labels, one turn at a time ("Thanks so much everyone No problem"). That also keeps `HandoffJobStore.originalAddsWording` true to its contract: a handoff carries a two-sided meeting once.

Files: `LiveVoiceSession.swift` (`LiveVoiceCheckpoint.text`, `.turns`, `.conversation`; `LiveVoiceTurns`; new `SpeakerEcho`), `LiveVoiceService.swift` (the loop's rebuild and publish), `MeetingConversation.swift` (`withoutEchoes` through `SpeakerEcho`, the shared constants), `LiveVoiceTranscriptView.swift` (`LiveTranscriptText`). `SpeakerEcho` lives in `LiveVoiceSession.swift` because `scripts/test-capture-persistence.py` compiles that file on its own; it uses only Foundation. Outside those: one fixture line in `HandoffJobsChecks.swift` (below) and the live voice contract in `docs/live-voice.md`.

## Checks

Every new check below failed on the base sources and passes on this branch. To show that, the four source files were put back to `2ff25df` with this branch's checks, the three check files were changed to print a failure and carry on instead of stopping, and `--check-meetings` was run; the files were then restored from the branch.

| Check (in `--check-meetings`) | On `2ff25df` | On this branch |
| --- | --- | --- |
| Meetings · "an echoed fragment of a long utterance is dropped and a reply the other side did not say then is kept" (#4) | Fails | Passes |
| Meetings · "a live meeting on laptop speakers saves the other side once and your reply as You" (#1, through `MeetingProcessor` and a real live journal) | Fails | Passes |
| Meetings · "its original wording keeps each speaker's words together, so a handoff carries the meeting once" (#5) | Fails | Passes |
| Live voice · "a 1.2 s pause keeps one turn and a 2.6 s pause starts the next" (#3) | Fails | Passes |
| Live voice · "overlapping speakers keep their own words together in the original wording and the conversation" (#5) | Fails | Passes |
| Live voice · "the microphone's copy of the call is not saved as You, and your own words are" (#1, through the real service) | Fails | Passes |
| Live voice · "the live transcript shows the call once and your own words as You" (#1) | Fails | Passes |
| Live voice · "2.5 s of streamed audio publishes N snapshots, words among them, not one per 100 ms pass" (#2, at most 10) | Fails: 26 | Passes: 4, in each of three runs |
| Experience · "new live words rewrite only the end of a 1,200-turn transcript" (#2) | Fails: edited from character 0 of 108,788 | Passes: edited from 108,788 |
| Experience · "a speaker's provisional words continue their confirmed turn, with no second speaker line" (#3) | Fails | Passes |
| Live voice · "the final state is published with every word"; Experience · "a clock tick leaves a 1,200-turn transcript's text untouched" and "an update from an earlier turn matches a fresh rendering of the same turns, attributes included" | Pass | Pass (guards on the new code) |

The existing check "separate identical replies survive in their actual turn order" and the existing saved-audio echo check pass unchanged. One existing fixture changed: the hour-long call in `HandoffJobsChecks.swift` relied on the old 0.8 s split to repeat its labels (same-side segments one second apart). Its same-side gaps are now three seconds, so its labels still repeat and every assertion is unchanged.

Commands, all on this branch's final source unless marked, through the shared build slot:

| Command | Result |
| --- | --- |
| `swift build --disable-sandbox` | Passed |
| `.build/debug/LocalVoice --check-meetings` | Meeting checks 385 (382 on `2ff25df`), removal 34, live voice 33 (27), live voice experience 31 (27). Each of the three commits also built and passed `--check-meetings` on its own. |
| `.build/debug/LocalVoice --check-handoff-jobs` | 223 checks |
| `.build/debug/LocalVoice --check-transcript-handoff` | 54 checks |
| `bash scripts/test.sh harnesses` | Exit 0; surface registry 688 entries; `CAPTURE_PERSISTENCE_CHECKS_OK: 231 checks` (it compiles `LiveVoiceSession.swift`) |
| `WORKBENCH_MEETINGS_GALLERY_ONLY=1 .build/debug/LocalVoice --render-surfaces` | 18 renders, 0 flags |
| `.build/debug/LocalVoice --render-live-voice` | 12 renders; before and after below |
| `.build/debug/LocalVoice --check-live-voice-model FIXTURE` with the cached Parakeet v2 model and an 8.3 s `say` fixture | One lane: first words 2.33 s, Stop flush 0.18 s, complete, the fixture's words exactly. With `--two-sources` (the same audio on both lanes, a perfect echo): first words 2.45 s, flush 0.43 s, complete, the words once. On `2ff25df` the two-lane text repeated every word ("Let's Let's review review the the…"). CoreML printed its usual shape-inference diagnostic. |

## Renders

`--render-live-voice`, light and dark. The fixture changed with this branch so it shows the change: your second sentence follows a 1.2 s pause and is still provisional. `before/` is the base view and turn code with that fixture, `after/` is this branch.

- `listening`: before, a second "You · 0:20" paragraph for the provisional sentence, and the four paragraphs push the page title out of the 470 pt frame. After, the provisional sentence continues your paragraph in the quieter colour.
- `completed`: before, two "You" paragraphs 1.2 s apart. After, one.
- `silent-app`: the same change on the microphone-only transcript under the silent-app hint.

The paused, reconnecting and finishing renders differ from the base in the same way as `listening` and are not copied here.

## Limits and what was not changed

- The saved-audio path has no word times, so it cannot cut a microphone utterance where the other side stops. A reply within 0.6 s of an echo still joins the echo's utterance there and can be dropped with it, as before. The live path cuts at the other side's speech.
- On laptop speakers, a reply spoken over the other side while they say the same words at the same moment is indistinguishable from the echo and is dropped. With headphones there is no echo, and nothing should be dropped.
- The echo thresholds (half the utterance overlapping; word-set overlap of one half, or three quarters of the shorter side's words in order) are from synthetic fixtures, not a real call.
- Overlapping speakers alternate by utterance, each utterance placed at its start, so an interjection can split the other speaker's longer turn around it. Words are never interleaved.

## Needs a real call on the installed Preview

- A two-sided call on laptop speakers, no headphones: the live transcript shows the other side once, the saved transcript has no echoed "You" lines, quick replies are kept, and Copy transcript's text matches.
- The same call with headphones: nothing you said is missing.
- A long call (30 minutes or more) with live words: the Meetings page stays responsive while words arrive; a `sample` of the app shows no whole-transcript text rebuild per update.
- A speaker who talks for a minute with natural pauses reads as one paragraph; two people talking over each other read in a sensible order.
