# Meetings: idle detection stops redrawing the app every 3 seconds, and the page knows a download is under way

Branch `claude/meetings-idle-and-setup`, stacked on the 15 October release train (`claude/train-1015`, on top of `main` at `edc15df`). Refs #378, #280. The checks below ran on the branch's final source. Synthetic data only: the checks use injected process sources, a fixture capture and isolated defaults, and the gallery uses its isolated home. No real audio process was enumerated by a check, and no microphone, tap, model download, installed app or privacy setting was used.

## What changed

1. **An idle detection poll publishes nothing and reads only the apps it can offer.** With Detect Meetings & Calls on and no call, every 3-second poll set `offer` from nil to nil, and while a metadata error lasted it set `problem` again. Each publish redrew Home and both toolbar views and ran the toolbar host's placement pass. `refreshDetection` and the disabled paths now publish only a change, and a persistent error publishes its problem once.
   Polls and the auto-finish activity read now take `detectionSnapshot()`: catalogue apps and the calling service only. The system source reads each process's bundle identifier first and skips the PID, both activity reads and the AppKit lookup for every other process. One loop serves both snapshots. The audio-source picker keeps the full snapshot. Offers, their order and PIDs, the three-observation rule, cooldowns, snooze, turning an app off and call activity are unchanged, because no other process can become an offer or share a catalogue app's key. **One behaviour difference:** a failed activity read on an unrelated process no longer fails the whole poll or shows an error.
2. **Meetings says speech readiness as Dictate does.** While speech downloaded or loaded, Meetings read "Speech setup needed" and drew an orange-triangle card: "Open Models before starting speech recognition. Downloading Parakeet · 42%". Now the title reads "Preparing speech…" while the engine prepares and "Speech setup needed" otherwise. The caption under it is the speech model's own line: the progress, why it stopped, or the download offer. The engine row keeps only Models… until speech is ready, so the line appears once. The speech refusal is never an attention card and loses its "Open Models before" prefix. A start refused for speech, for example from a call offer, is cleared once speech becomes ready, so no stale card outlives the download. Start recording stays disabled. Cancel setup stays in Models.
   The caption reads the line from the speech refusal in the page's admission, not from the `engineName` label. In the app both carry the same snapshot's line. In the gallery the label comes from the gallery's own ready model, so reading it there would have captioned a download with "Parakeet v2 · English · on this Mac".

## Renders

`before/` comes from the train's view code with this branch's added gallery shot, so `meetings-setup-preparing` has a before. `after/` comes from this branch's final source. Both are the Meetings gallery pass (`WORKBENCH_MEETINGS_GALLERY_ONLY=1 LocalVoice --render-surfaces`), light and dark, at minimum width.

- `meetings-setup-preparing`: before, "Speech setup needed", the default caption and a triangle card asking to open Models beside "Downloading Parakeet · 42%". After, "Preparing speech…" with "Downloading Parakeet · 42%" as the caption, Models… and no card.
- `meetings-setup`: before, the default caption and a triangle card with the download offer. After, "Speech setup needed" with the download offer as the caption, Models… and no card.
- `meetings-complete-text`: the same change above a kept-for-later recording. Its Save transcript action is unchanged.
- `meetings-saved-without-audio`: the stale speech card under a saved transcript is gone.

The microphone, source-failure, app-only and saving-without-audio shots are byte-identical before and after, so they are not copied here. `page-history-state-from-meeting` differs between two runs of the same build: two synthetic meetings share a timestamp, so their order varies. It is not part of this change.

## Checks

| Check | Result | Fails without this change? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |
| `LocalVoice --check-meetings` | Meeting checks passed (350), removal 34, live voice 21, live voice experience 19. Includes the existing offer-panel lifecycle and activity checks, unchanged. | Yes, each confirmed by building and running against a reverted piece. With the train's `MeetingModel.swift`: "five idle detection polls read metadata and publish nothing". With only the problem guard removed: "a metadata failure that persists publishes its problem once, not once per poll". With the train's admission title and `.speech` message: "a running download reads Preparing speech… with its progress as the caption, and asks for no setup". Without the clear on readiness: "speech becoming ready settles the refused start, so no stale card outlives the download". |
| Filtered against full detection (in `--check-meetings`) | 38 synthetic processes (Chrome and its audio helper, Teams and its module host, the calling service in both directions, lowercase Phone, two excluded Workbench IDs, 30 unrelated input apps) through streak, Not now, snooze, turning Phone off, a PID change, the main browser process quitting, a metadata failure and recovery. Offers, PIDs and `activity(for:)` match at every step. | Not on the train: `detectionSnapshot()` is new, so this check is a guard on equivalence. Mutation: with the calling service left out of `considers`, `--check-meetings` fails ("the calling service with two-way audio is the one manual service that raises an offer…"). |
| `LocalVoice --check-bug-report docs/bug-reporting-schema.md`, `--check-core` | Passed | |
| `python3 scripts/check-surfaces.py` | 687 entries OK | |
| `python3 scripts/check-attention-text.py` | Passed, 3 named exceptions | |
| `bash scripts/test.sh harnesses` | Passed (exit 0) | |
| Meetings gallery pass | 18 renders, 0 flags; `MEETINGS_PRODUCTION_OWNER_CHECKS_OK` | |
| `LocalVoice --render-surfaces` (full gallery) | Exit 0, 376 renders, 0 flags. Every `page-meeting-*`, `panel-meeting-recording` and `toolbar-meeting-recording-resting` render is byte-identical to `main`'s, light and dark. Home renders that differ from `main`'s show the train's own changes, such as Finish dictation and the permission rows. | |

No check compares two live Core Audio reads, because processes can start or quit between them. The timing gain is from the brief's scratch benchmark on 36 process objects: about 9.3 ms for a full snapshot and matching against about 3.3 ms for the detection snapshot. It was not measured again here.

## Independent review

An independent review of the whole branch returned "ship" with two P3 findings. It re-ran the build, `--check-meetings`, `--check-bug-report`, `--check-core`, `check-surfaces.py`, `check-attention-text.py` and the Meetings gallery pass, and its fresh renders matched all 8 committed `after/` images byte for byte. After the review the build and those checks were run once more on the final source, with the same results. Two of the failing-without-the-change claims were confirmed again by mutation: the train's `MeetingModel.swift` fails "five idle detection polls read metadata and publish nothing", and removing the "Preparing speech…" title fails "a running download reads Preparing speech… with its progress as the caption, and asks for no setup".

- **"Preparing speech…" while setup is being cancelled.** Left as it is. After Cancel setup, until the model load finishes, the title still reads "Preparing speech…" and the caption reads "Setup cancelled… recording will not start." Dictate shows the same pair ("Preparing dictation…") from the same snapshot, so the two pages keep one form. Changing it is a shared Dictate and Meetings wording decision, not this branch's. The train showed "Speech setup needed" and a triangle card in that state, so this is no regression.
- **The code commits name only #280.** The pushed commits are not rewritten. The pull request names #378 and #280.

## Not verified natively

On a signed Preview, by the integration owner or Ethan:

- With Detect Meetings & Calls on, Home open and no call, `sample` the app for 10 seconds. It should no longer show a SwiftUI transaction through the Home page or `CapturePanelController.update` every 3 seconds, and `refreshDetection` should be short.
- A real call in Zoom, Teams in a browser, or FaceTime on this Mac is still offered after three polls, by the same app and PID as before.
- Meetings during a real first download and in the seconds after launch, while saved speech files are checked: "Preparing speech…" with the live progress line, then "Ready to record" with the engine line back beside Models….
