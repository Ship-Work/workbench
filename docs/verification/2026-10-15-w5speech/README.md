# First run and saving off: speech offer and Dictate stop · 15–16 October 2026

Branch `claude/fresh-install-speech`, stacked on the 15 October train `claude/train-1015` at d7cea35. Refs #15, #379. Both changes are Quality: no capability, place, setting or entry point is added, and no wording in the product contract changes.

`before/` and `after/` hold the speech gallery's offer shot (`WORKBENCH_SPEECH_GALLERY_ONLY=1 LocalVoice --render-surfaces`) in light and dark, under the same filenames. Everything shown is synthetic gallery data.

## What changed

| # | Change | Renders |
| --- | --- | --- |
| 1 | **A fresh Mac reads as ready to set up.** Launch's cached check found no Parakeet files and stored that as a failure, so Home, Dictate, Meetings and the menu-bar panel read "Parakeet needs a download before speech can be transcribed. Your saved work is available now." Snap & Talk drew the orange triangle, Retry model and "If the model still can't be prepared…" before anything was downloaded. In `RecognitionEngine.prepare(acquire: false)`, missing files now end the check on the offer with no failure. Every surface reads "Download Parakeet to turn speech into text on this Mac." and Snap & Talk shows its neutral "You can record for later" line. An invalid cache, a load, storage or network error, and a Download that yields no files all stay failures. Transcription before the download is still refused, now with the existing "Open Models to prepare speech first. Your recording and saved work are kept." | `before/speech-offer-*` is the train's engine on an empty cache, driven through this branch's gallery path with its guard removed (a one-off, not committed). That is what a fresh Mac showed. `after/speech-offer-*` is this branch. |
| 2 | **The gallery's offer comes from the engine.** The speech gallery's offer and deferred-narration shots used to write the designed state in by hand, so reviewed first-run renders showed a state the shipped app never reached. Both now take the snapshot that an engine's own startup check reaches on an empty cache. The pass fails unless that snapshot is the offer with no failure. | The train's committed speech gallery and this branch's speech gallery are byte-identical in all 20 renders. The difference is that the state now comes from the engine. |
| 3 | **Dictate never hangs when session saving is off.** After "Your saved session could not be opened or backed up. Automatic saving is disabled…", saving a dictation used to return quietly. Dictate stayed on Tidying your words… with no way out, later dictations and Retry were refused until relaunch, and a Transcribe with Workbench Shortcut never returned, even when cancelled. Now the save fails with "Automatic saving is off for this session, so this dictation was not added to History or sent to your app. The words are in Dictate. Copy them, then use Discard recovery… to dictate again, or reopen Workbench." Dictate returns to idle, Shortcuts gets one error, and Retry saving is not offered, because it cannot succeed in this session. | None: no gallery state has saving off. |
| 4 | **After that stop, the next start names the door that is there.** From the independent review. Retry saving is hidden in a saving-off session, but a new dictation was refused with "A previous capture is kept. Use Retry saving before starting another capture." and a second Shortcuts run with "…Use Retry before starting another capture." Both now say "Automatic saving is off for this session, and a dictation is kept in Dictate. Copy its words, then use Discard recovery… to dictate again, or reopen Workbench." With saving on, both refusals are unchanged. The new `dictate.saving_disabled` code is added to the Dictate code list in `docs/bug-reporting.md`. | None: no gallery state has saving off. |

Not changed, deliberately:
- No flag makes Retry saved files report missing files. It now shows the accurate offer line beside Download Parakeet.
- Retry saved files is not hidden on a fresh install. Hiding it would need a decision on `docs/workbench.md`'s Models wording.
- The Home task-without-speech state in the full gallery still sets its line by hand. That shot asserts the speech banner is absent, so the line is never drawn.

## Checks run on this branch

| Check | Result | Fails on the train? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Pass, no warnings in the touched files | n/a |
| `LocalVoice --check-providers`. It runs the real cached loader on an empty cache and checks five things: no throw, no failure, admission unavailable, the offer line, and speech still refused with `.missingAssets`. A Snap & Talk `NarrationEngine` built from that snapshot needs no attention. An invalid vocabulary still records `.invalidCache`. A Download whose load finds no files still records `.missingAssets`. | Pass (RECOGNITION_LIFECYCLE_CHECKS_OK, 52 checks) | Yes. With the train's `RecognitionProviders.swift` it fails at "a fresh Mac's startup check ends on the download offer, not a failed setup". |
| `scripts/test-capture-persistence.py`, with saving off. A Shortcuts run gets exactly one failure reply, the request clears and Dictate is idle. The words stay in Dictate, with no History entry and no state write. A later Cancel in Shortcuts cannot reply again. A second Shortcuts run is refused with a sentence that names Discard recovery… and no Retry. An owned recording says "Automatic saving is off", offers no Retry saving, and keeps recovery with Discard recovery… available. The next start is refused with a sentence that names Discard recovery… and no Retry. | Pass (227 checks) | Yes. With the train's `AppModel.swift` it fails at "With saving off, a Shortcuts run returns one error and Dictate stops: 0 replies, cleaning". It fails without hanging. With the first saving-off commit's `AppModel.swift` (before the review follow-up), the new refusal checks fail at "the next Shortcuts run names Discard recovery…" (it read "A capture still needs saving or transcription. Use Retry before starting another capture.") and, with that check set aside, at "the next start names Discard recovery…" (it read "A previous capture is kept. Use Retry saving before starting another capture."). |
| `WORKBENCH_SPEECH_GALLERY_ONLY=1 LocalVoice --render-surfaces` | 20 renders, 0 flags, FIRST_SPEECH owner and race checks OK | Yes. With the train's engine, the pass stops with "An engine on an empty cache did not end on the download offer. It read: Parakeet needs a download before speech can be transcribed. Your saved work is available now." |
| `LocalVoice --render-surfaces` (full pass), and the same pass from the train's source | 376 renders, 161 entries, 0 flags on both | n/a. The full gallery never runs cached preparation and always has saving on. 342 renders are byte-identical to the train's. The other 34 differ only in run-time content: synthetic session times on Home and Hand off, random report IDs, and how far History had scrolled to the item Home opened when the shot was taken. |
| `LocalVoice --check-readback`, including "the kept take waits queued while speech prepares", "fails with the model's reason" and "with nothing preparing the take fails as before" | Pass, rerun at the final head | n/a |
| `LocalVoice --check-core`, `--check-meetings` | Pass, rerun at the final head | n/a |
| `bash scripts/test.sh harnesses` | Pass at the final head; no settings suites left behind | n/a |
| `python3 scripts/check-surfaces.py` | Pass (687 entries) | n/a |

From reading the source: switching from a local server to Parakeet on an empty cache no longer shows a WorkbenchNote. Models' `apply()` sets a note only when `prepareCached()` throws, and on missing files it now returns normally. No check drives that view method.

## Not verified natively

- A real first run on a fresh account or Mac with no Parakeet files. #15 still owes this. The checks prove the engine's state, not the installed first run.
- The saving-off path on the installed app. It needs an unreadable `state.json` and a backup copy that also fails. Neither was staged here.
- A real Transcribe with Workbench Shortcut while saving is off.

## Independent review

The reviewer's verdict was ship, with two P3 findings. Both are answered on this branch:

- After the saving-off stop, the next Dictate start and the next Shortcuts run told the person to use a Retry that is hidden. They now name Discard recovery… (row 4), with two checks that fail without the change.
- `dictate.saving_disabled` was missing from the Dictate code list in `docs/bug-reporting.md`. It is now listed.
