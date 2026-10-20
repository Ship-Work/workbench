# Meetings: live words without the call's echo, whole turns, each speaker's words together, and publishing on change

Branch `claude/meetings-live-words`, from the integrated release candidate (`main`, the 15 October train #353 and Meetings #374, head `2ff25df`). Refs #377, #280. Grammar: Quality for every change; no entry point, setting or saved format was added or changed. Synthetic data only: injected recognisers, fixture audio and a generated `say` fixture. No microphone, tap, call app, installed app or privacy setting was used.

## What changed

1. **P2 · A meeting saved from its live pass now drops the microphone's copy of the call.** On laptop speakers the microphone hears the other side. The saved-audio path dropped that echo; a meeting whose live pass completed saved it as You, interleaved word by word with the real words. Live words carry their times, so `LiveVoiceTurns.group` drops the echo word by word (`SpeakerEcho.echoed`): a microphone word is an echo when the app said the same word (its letters and digits) 0 to 0.4 s before it, with 0.1 s either side for where two recognisers place a word, and each app word accounts for one microphone word at most. Every other word is yours: a "Yes" that starts the moment they finish, a few words of your own inside their sentence, and, with headphones, a word of theirs you repeat a moment later. The echo goes however their pauses fall. The remaining words are cut into utterances as the saved-audio path cuts a track (0.6 s of silence, at most 25 s), and yours also where they move into or out of one of their utterances, by which one they fall in, so your words take their places around theirs. Every caller of `group` gets this: the saved conversation and original wording (`LiveVoiceCheckpoint`), the live snapshot, and the turns `MeetingModel` and `AppModel` show at finish. The live journal still keeps every recognised word; the echo drop is a projection, so an existing journal reads the same way.
2. **P2 · Live snapshots publish on change, and the view rewrites only what changed.** The live loop passes ten times a second and published a snapshot on every pass. Each one rebuilt the turns and, on the main thread, built the whole transcript's attributed text and compared it with the text view's. `LiveVoiceService` now rebuilds turns only when words change and publishes when something a page shows changes (words, phase, a source's health or note, the delayed and incomplete flags), and the meter level and elapsed time at most once a second; no page shows either from the snapshot, since each model keeps its own clock. New words and the final state are published at once. `LiveTranscriptText.Coordinator` keeps the turns it shows and where each ends in the text, and rewrites only from the first turn that changed; an update that changes nothing (the page's clock ticks it twice a second, and Dictate's meter about twelve times) touches nothing. The turn rebuild on the service's thread is still a pass over the whole transcript, but only when words change, about once a second per source, never on the main thread. Making it incremental would not hold up: words settle only once both sources have committed past them, and a silent app track never commits.
3. **P3 · A continuous speaker stays one turn.** Turns split at any same-source gap over 0.8 s, so a speaker who paused between sentences got a new "You:" paragraph each time, live and saved. A source's utterances now stay one turn until the other source speaks or it pauses for two seconds (`LiveVoiceTurns.pauseSeconds`). Why two seconds: people pause for a second or more inside one turn, two seconds is twice the silence a conversation usually leaves unremarked, and it is the saved-audio path's own join (`MeetingConversation.conversation`, which now uses the same constant), so a meeting reads the same whichever path saved it. A real turn change still splits at once, because the other source's words come between. In the live view a speaker's provisional words also continue their confirmed turn, quieter, instead of opening a second speaker line at every eight-second commit (`LiveTranscriptText.continues`).
4. **P3 · The saved-audio echo drop catches a fragment inside a long remote utterance.** It compared word sets both ways (Jaccard), so "the budget needs to go" inside a 20-second remote utterance scored about 0.2 and was saved as You. `SpeakerEcho.isEcho` keeps that test unchanged and adds a containment test for the short side: a microphone utterance of three words or more, and no longer than the app's, is an echo when the app said at least three quarters of its words in the same order close to the same time. A saved clip has no word times, so the app's words are spread evenly over its utterance and only those within a second, or a tenth of the utterance if that is longer, count. A reply of one or two words is judged only by the unchanged test, so "Okay", "Friday?" or "Sam, yes" over the other side's long turn is kept even when they said that word nearby.
5. **P3 · The format-2 original wording keeps each speaker's words together.** `LiveVoiceCheckpoint.text`, saved as a live meeting's original wording (`MeetingManifest.liveText`, the History record's `rawText`), sorted both speakers' words by start time, so two people talking at once came out zipped together ("Thanks so No much problem everyone"). It is now the conversation's words without labels, one turn at a time ("Thanks so much everyone No problem"). That also keeps `HandoffJobStore.originalAddsWording` true to its contract: a handoff carries a two-sided meeting once.

Files: `LiveVoiceSession.swift` (`LiveVoiceCheckpoint.text`, `.turns`, `.conversation`; `LiveVoiceTurns`; new `SpeakerEcho`), `LiveVoiceService.swift` (the loop's rebuild and publish), `MeetingConversation.swift` (`withoutEchoes` through `SpeakerEcho`, the shared constants), `LiveVoiceTranscriptView.swift` (`LiveTranscriptText`). `SpeakerEcho` lives in `LiveVoiceSession.swift` because `scripts/test-capture-persistence.py` compiles that file on its own; it uses only Foundation. Outside those: one fixture line in `HandoffJobsChecks.swift` (below) and the live voice contract in `docs/live-voice.md`.

## Checks

Every check in the first table failed on the base sources and passes on this branch. To show that, the four source files were put back to `2ff25df` with this branch's checks, the three check files were changed to print a failure and carry on instead of stopping, and `--check-meetings` was run; the files were then restored from the branch.

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

An independent review of `8a3c7fa` found that its first echo rule, which judged live microphone utterances whole and allowed 0.3 s past the other side's speech, lost real words: a reply's first word joined the echo ("Yes" and "No" vanished, "yes I will" saved as "I will"), a word of theirs repeated with headphones was dropped on both paths, an echo leaked as You across a 0.65 to 0.8 s pause of theirs when the microphone's timing shifted by a frame, and an interjection inside an echo was lost. The live rule is now word-level and the saved-audio containment needs three words in a tighter window, as above. Each reproduction is a check; all five fail on `8a3c7fa`'s echo code with this branch's checks and pass now. On `2ff25df` the saved-audio headphone check passes, because the base kept those replies, and the four live ones fail, because the base interleaved the echo into the turns.

| Check (in `--check-meetings`) | On `8a3c7fa` | On this branch |
| --- | --- | --- |
| Live voice · "a reply 0 to 0.15 s after the other side finishes is kept whole and their echo is not" ("Yes" at 0 and 0.05 s, "No not this week" at 0.1 s, "No" at 0.15 s) | Fails: all four lost or cut | Passes |
| Live voice · "an "okay" 1.5 s after theirs and a "Friday" answering "Friday or Monday" are kept" | Fails | Passes |
| Live voice · "an echo across a 0.65 or 0.8 s pause of theirs is dropped at any microphone timing" (shifts of 0, 0.08, 0.16 and 0.4 s) | Fails: leaked at four of eight | Passes |
| Live voice · "an interjection inside the echo of their sentence is kept, and the echo around it is not" | Fails | Passes |
| Meetings · "short replies over a long turn are kept when the other side said the same word nearby" (saved-audio, headphones) | Fails | Passes |

The reviewer's own probes, run against the final `LiveVoiceSession.swift`, give the same answers, including a quick reply 0.2 s after an echo ("yes I will" kept whole) and an echo across a 1.0 s pause. `group()` on a two-hour two-source call (18,000 words, every microphone word an echo) takes 6 ms in an optimised build.

The existing check "separate identical replies survive in their actual turn order" and the existing saved-audio echo check pass unchanged. One existing fixture changed: the hour-long call in `HandoffJobsChecks.swift` relied on the old 0.8 s split to repeat its labels (same-side segments one second apart). Its same-side gaps are now three seconds, so its labels still repeat and every assertion is unchanged.

Commands, all on this branch's final source unless marked, through the shared build slot:

| Command | Result |
| --- | --- |
| `swift build --disable-sandbox` | Passed |
| `.build/debug/LocalVoice --check-meetings` | Meeting checks 386 (382 on `2ff25df`), removal 34, live voice 37 (27), live voice experience 31 (27). Each commit also built and passed `--check-meetings` on its own. |
| `.build/debug/LocalVoice --check-handoff-jobs` | 223 checks |
| `.build/debug/LocalVoice --check-transcript-handoff` | 54 checks |
| `bash scripts/test.sh harnesses` | Exit 0; surface registry 688 entries; `CAPTURE_PERSISTENCE_CHECKS_OK: 231 checks` (it compiles `LiveVoiceSession.swift`) |
| `WORKBENCH_MEETINGS_GALLERY_ONLY=1 .build/debug/LocalVoice --render-surfaces` | 18 renders, 0 flags |
| `.build/debug/LocalVoice --render-live-voice` | 12 renders; before and after below |
| `.build/debug/LocalVoice --check-live-voice-model FIXTURE` with the cached Parakeet v2 model and an 8.3 s `say` fixture | One lane: first words 2.33 s, Stop flush 0.18 s, complete, the fixture's words exactly. With `--two-sources` (the same audio on both lanes, a perfect echo): first words 2.36 s, flush 0.49 s, complete, the words once (2.45 s and 0.43 s with `8a3c7fa`'s utterance rule). On `2ff25df` the two-lane text repeated every word ("Let's Let's review review the the…"). CoreML printed its usual shape-inference diagnostic. |

## Renders

`--render-live-voice`, light and dark. The fixture changed with this branch so it shows the change: your second sentence follows a 1.2 s pause and is still provisional. `before/` is the base view and turn code with that fixture, `after/` is this branch.

- `listening`: before, a second "You · 0:20" paragraph for the provisional sentence, and the four paragraphs push the page title out of the 470 pt frame. After, the provisional sentence continues your paragraph in the quieter colour.
- `completed`: before, two "You" paragraphs 1.2 s apart. After, one.
- `silent-app`: the same change on the microphone-only transcript under the silent-app hint.

The paused, reconnecting and finishing renders differ from the base in the same way as `listening` and are not copied here.

## Limits and what was not changed

- Nothing knows whether the Mac is playing through speakers or headphones; the rule is the same either way. Live: a word you say 0 to 0.4 s after the other side says the same word is taken for its echo, so saying "thanks" together drops your "thanks" (headphones or not). On the saved-audio path a reply of three words or more that repeats the words the other side was saying at that moment can be dropped.
- Live: a word the microphone's recogniser hears differently from the app's ("sent" for "send") is not matched, so a misheard echo can leave a stray word or two as You.
- The saved-audio path has no word times, so it cannot cut a microphone utterance where the other side stops. A reply within 0.6 s of an echo still joins the echo's utterance there and can be dropped with it, as before. An echoed fragment of one or two words inside a long remote utterance is still saved as You there; only the unchanged word-overlap test sees it.
- The thresholds (0.4 s and 0.1 s for live words; half the utterance overlapping, word-set overlap of one half, or three quarters of three words or more in order for saved audio) are from synthetic fixtures, not a real call.
- Overlapping speakers alternate by utterance, each utterance placed at its start, so an interjection can split the other speaker's longer turn around it. Words are never interleaved.
- One long turn is still rewritten whole at each commit: the view rewrites from the first turn that changed, and while one speaker talks without a two-second pause that turn is the whole transcript (the review measured about 36 ms at 122,000 characters for the rewrite and layout). Turns with breaks between them are unaffected.

## Needs a real call on the installed Preview

- A two-sided call on laptop speakers, no headphones: the live transcript shows the other side once, the saved transcript has no echoed "You" lines, quick replies are kept, and Copy transcript's text matches.
- The same call with headphones: nothing you said is missing, including words that repeat theirs.
- A long call (30 minutes or more) with live words: the Meetings page stays responsive while words arrive; a `sample` of the app shows no whole-transcript text rebuild per update.
- A speaker who talks for a minute with natural pauses reads as one paragraph; two people talking over each other read in a sensible order.
