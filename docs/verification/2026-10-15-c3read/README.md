# Read's leftovers, unused Meetings helpers and the old handoff folder route · 15 October 2026

Branch `claude/retire-read-meetings-handoff-leftovers`, stacked on the 15 October train (`claude/train-1015` at 59753fc). It lands after #353 ships. Synthetic data only. Refs #280, #281, #284.

## What changed

1. **Read's leftovers** (#284).
   - `CancellableProcess`, Read's process runner, had no caller since Read was retired. It is deleted.
   - Recording review's playback line said "Finish the current capture or reading to play this recording." It now says "Finish Dictate, the meeting or Snap & Talk to play this recording.", the three things its gate checks.
   - Persona's Show help on Home and in the panel said "Finish the current input operation…". It now says "Finish Dictate, Snap & Talk or the shortcut change before showing the set again.", matching its admission.
   - The meetings check message, the surface check's scope paragraph and one doc comment no longer name Read admission, a toolbar More menu or reading controls. The gallery caption that says "reading" keeps the word, because it names Read's preserved text, which the render still checks is unchanged.
2. **Meetings helpers nothing called** (#280). `sourceCaution`, `offerText`, `processObjects()`, `disableOffers`, the `remoteAudioVerified` field and the disabled-apps defaults key and its read are gone. No commit ever called `disableOffers`, the key's only writer, so no saved choice is lost. The rule the field carried is now one comment on the supported catalogue. `MeetingDetector.disable`, its filters and their checks stay. No user-facing string changes.
3. **One Hand off route** (#281). The Create Handoff Folder route was reached only from its checks. Its request and selection types, the store's validate, create and README, the transcript brief and `TranscriptHandoffRunner` are gone. The manifest, records, evidence reading, `safeURL`, the skill types and the skill check stay. The review's Choose a session… now uses a plain chooser with the same title, prompt and message, and hands the folder to the review's own reader. A folder that isn't a Snap & Talk session now shows its reason in the review. Before, the runner put the reason where nothing read it, so the pick did nothing.
4. **Old History search helper** (#281). `TranscriptHistory.matching` and its two core checks are gone. `WorkbenchHistoryChecks` already covers original wording, case-insensitive search and clearing the search.

Not done here: the two behaviour items in the same issues, a call offer's purpose returning to Meeting (#280) and the Suggest details title (#281), are already on the train from `claude/meeting-handoff-labels`.

## Checks

Debug build on this Mac at the branch head.

| Check | Result | Fails without the change |
| --- | --- | --- |
| `--check-core` | exit 0; Workbench controls 222 | Yes. With the train's `WorkbenchControlTool.swift`: "a refused Show personas names each kind of work that holds it", exit 1 |
| `python3 scripts/test-read-retirement.py` (also `--binary`) | 5 tests OK; 13 retired commands refused | Yes. With the train's sources, `test_blocker_lines_name_retained_work_only` fails on `MeetingRecordingReview.swift: capture or reading` |
| `--check-transcript-handoff` | 53 checks (train: 129, runner 11) | No. The new case, a folder that isn't a session gets a readable reason, holds on the train too; the train's bug was the runner in front of it |
| `--check-meetings` | 292 Meeting checks, live voice 21, live voice experience 19 | Not new |
| `--check-handoff-jobs` | 223 checks | Not new |
| `--check-history-library`, `--check-history-journey` | History page 63; 20 steps | Not new |
| Every other checks-phase mode: read-retirement, shortcut-migration, readback, snap-capture, presenter, providers, refinement, readback-pack, capture-preview, image-workspace, subscription-cli, bug-report | exit 0 each | Not new |
| `scripts/test.sh harnesses` | exit 0; node tests fail 0 | Not new |
| `python3 scripts/check-surfaces.py` | 689 entries OK, registry unchanged | Not new |
| debug build | no new warnings; the two it reports are on the train too | Not applicable |
| `rg` for every deleted name in Sources, Tests and scripts | nothing | Not applicable |

The `rg` in #284's acceptance also matches "More menu" in `CaptureHistoryView.swift` and `SurfaceGallery.swift`. Both name History's row More menu, which exists, so they stay.

## Renders

`before/` holds `--render-surfaces` from main and `after/` holds this branch, in light and dark. The panel with personas hidden while Dictate is busy is the state where Persona's new help applies. The help is a tooltip, so the render is pixel-identical; it shows the tooltip's state, not the words.

Every one of the branch's 376 renders was compared with a render of the train head. 35 PNG files differ in bytes, and all 35 are pixel-identical.

## Not verified

- No gallery state shows recording review with playback held, or the Hand off review after Choose a session…, so neither change appears in a render. The playback line is checked in source by the read-retirement harness. The chooser route is read from source: Choose a session… passes the folder to `useEvidence`, which puts any refusal in the review's `problem` note.
- Nothing was checked natively: no installed Preview, open panel, hover or VoiceOver pass.
