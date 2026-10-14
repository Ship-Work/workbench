# Meetings: long calls stay responsive and always save

Refs [#280](https://github.com/Ship-Work/workbench/issues/280) (items 1-4) and [#134](https://github.com/Ship-Work/workbench/issues/134) (item 5). Based on `main` at `edc15df`. Synthetic data only; no microphone, call app, model or saved user data was used. This record covers source checks and offscreen production views, not installed Preview acceptance.

## What changed

1. **The live transcript measures only up to its 360 pt clamp.** The page's clock relayouts it every second, and each pass rebuilt and measured the whole meeting. Sizing now measures a doubling prefix of turns (or of saved text) until it is whole or reaches the clamp. A short transcript is still measured whole, and the text shown is unchanged.
2. **Pauses and reconnections fold into bounded History notes.** History accepts at most 32 notes of 500 characters, and every gap on every track became one, so about sixteen pauses or reconnections on a call made the transcript unsaveable for good. Every processor outcome now projects its notes. Gaps become one count-and-length line per named source, and the person's own Stop & keep note is left out. Notes are deduplicated, kept to one line and 500 characters, and anything past 32 folds into a final line. The manifest, timing records and capture caps keep every gap.
3. **A meeting that ends itself finishes with a transcript.** The two-hour limit, a source that could not reconnect and microphone access being removed now finish like Finish meeting, with the reason as a note. Low disk still keeps the recording for later, and a failed transcription falls back to Kept for later with its audio.
4. **Returning to Workbench rechecks the audio apps.** While idle, the Meetings page rereads the audio apps (CoreAudio metadata only, no permission or capture) when Workbench becomes active. A newly opened call app appears, and a quit one no longer reads Ready to record. During a start or recording it only rechecks admission, as before.
5. **Hide Workbench (⌘H) pauses recording review** and closes the Library preview, as closing and minimizing do. Unhiding resumes nothing.

## Renders

`before/` is from `main`; `after/` is from this branch, with the same filenames. `live-transcript-*` comes from `LocalVoice --render-live-voice`, and `page-meeting-state-*` from `LocalVoice --render-surfaces`. All ten pairs are byte-identical, as intended: short transcripts are measured exactly as before, and no other item changes these views.

Across the full surface gallery (350 renders, 0 flags), the only differing files lie outside Meetings: History's list (thumbnail loading and scroll position), a Home timestamp and report IDs. These vary from run to run, and no commit here touches those views.

## Checks run on the final branch

| Check | Result |
| --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed; only existing warnings remain. |
| `LocalVoice --check-meetings` | 288 Meetings, 34 removal, 21 live-voice and 19 experience checks passed. |
| `LocalVoice --check-history-library` | 63 checks passed. |
| `LocalVoice --check-handoff-jobs NEW_DIR` | 203 checks passed. |
| `LocalVoice --check-history-journey NEW_DIR` | 20 steps passed. |
| `LocalVoice --check-core` | Passed. |
| `LocalVoice --render-live-voice NEW_DIR` | 10 renders, byte-identical to `main`. |
| `LocalVoice --render-surfaces NEW_DIR` | 350 renders, 163 entries, 0 flags. |
| `bash scripts/test.sh harnesses` | Passed, including capture continuity and library recall. |

## Each new check fails without its change

Each behaviour was confirmed failing by building the branch's checks against the old code for that item only:

- **Item 1:** with `main`'s measurement, a 1,200-turn clock relayout took a median of 19,589 ms in a debug build. The budget is 250 ms. The fixed debug build takes 42 ms live and about 100 ms with saved text, held at 360 pt.
- **Item 2:** with `main`'s raw notes, the 40-gap recording fails to save to History, and so does the missing-originals path. The pure check also shows History refusing the raw list with "too many capture notes".
- **Item 3:** with `main`'s kept-for-later stop, both the lost-source and the two-hour cases end without a transcript.
- **Item 4:** with `main`'s admission-only return, the newly opened app, the quit app and the failed read are all missed. Without the busy guard, the parked-start case rereads the apps.
- **Item 5:** without the observer, the hide notification leaves the recording playing.
- **Harness:** without the added member, the capture continuity harness fails to compile.

## Not verified natively

These are owed on the installed Preview:

- a real call longer than 30 minutes with the Meetings page visible;
- headphone, device or call-app loss mid-call;
- microphone access being switched off during a recording;
- ⌘H during real recording review.

The timing budget was measured offscreen, not on a live call.
