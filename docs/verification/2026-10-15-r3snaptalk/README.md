# Snap & Talk: added Snaps in capture order, Capture area kept

Branch `claude/snaptalk-added-order-and-area`, stacked on the 15 October release train (`claude/train-1015`). Refs #358 and #63. The checks below ran on the branch's final source. Synthetic data only: temporary Snap stores, synthetic sessions and PNGs, isolated preferences suites, a fixed Screen Recording answer and the surface gallery's isolated home. No installed app, real Snap, microphone, screen capture or privacy setting was used.

## What changed

1. **Added Snaps join in the order they were captured.** History lists Snaps newest first, and Use selected › Add to Snap & Talk passed that order straight into the session, so five steps taken in order arrived as a deck running backwards. `ReadbackModel.importSnapSnapshots` now sorts the batch by capture time (ties by id) before `SnapReadback` appends it. The first added Snap opens for narration, as the earliest one did by accident before; keeping the old "review the last section" line after sorting would have opened the last step instead. The notice counts in the singular where it should: "Added 1 Snap.", "1 already present was skipped." and, when the one Snap added is already there, "This Snap is already in this session". Unchanged: Hand off's saved-history order (`SnapModel.handoffSnapshots`), and `SnapReadback` keeping the order it is given.
2. **The page keeps its Capture area after you leave it.** The choice lived in the page's view state, so Add from Snap History…, or any visit to another page, put it back on Screen. The next Capture & narrate then took the whole display, and Replace screenshot… replaced a section with a full-screen capture. The choice now lives on `ReadbackModel` as `captureArea`, in memory only. It lasts for the run, through leaving the page, closing the window and switching sessions; a relaunch starts on Screen, and no preference was added. Toolbar, shortcut and panel captures still pass their own source and never change it.
3. **docs/snap.md** says both: added Snaps join the end of the session in capture order with the first opening for narration, and the page keeps its Capture area while Workbench runs.

## Renders

`before/` comes from the gallery rendered on `main` before tonight's streams, and `after/` from this branch, light and dark:

- `page-readback-screen-access-off-*`: the full gallery's one Snap & Talk state that shows the Capture area, with Screen selected.
- `page-readback-default-*`: the page with no session open.

They are byte-identical before and after, as they should be: a fresh model starts on Screen. So are `page-readback-narrow-*`. The desktop-only gallery pass also renders session states (`page-readback-session-*`) that show the Capture area; they were not rendered for this record, and each builds a fresh model, so they start on Screen too. Of the gallery's other renders, the ones that differ from the before set are outside Snap & Talk's page; the one inspected, Home's Snap & Talk card, differs only in a date the gallery takes from when it runs.

After the review fixes, the gallery was rendered twice more on the final source. The four renders kept here matched both times, and so did every other Snap & Talk, Snap, Snap panel and Snap & Talk toolbar render (38 files), with two exceptions, neither in code this branch touches:

- In the first rerun (`SURFACE_GALLERY_OK`, 360 renders, 0 flags), `page-snap-default-light` drew its three thumbnails as placeholders. Its dark twin matched, and in the second rerun it matched too.
- The second rerun drew every render but stopped with a toolbar step: "A copied cue appearing under a stationary pointer holds its time … the actual cue missed the resting pointer". That step reads the real pointer, and it passed in the first rerun.

Neither change has a gallery state of its own. An added batch looks like any other set of sections, and the kept area shows only after leaving and returning, which the check below does with the real page instead.

## Checks

| Check | Result | Fails on the train without this change? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |
| `.build/debug/LocalVoice --check-snap-capture` | `SNAP_CAPTURE_CHECKS_OK`: 189 checks | Yes. With the train's `ReadbackModel.swift`, "added Snaps join the end of the session in the order they were captured" fails, listing Third step, Second step, First step. Sorting but keeping the old review line fails "the first Snap captured, not the last, opens for narration". Sorting with the old notice fails "one added Snap is counted in the singular", showing "Added 1 Snaps.". With only the skipped count left plural, "one Snap already in the session is skipped in the singular" fails. With the old wording for a batch that adds nothing, "one Snap added again is named in the singular" fails, showing "These Snaps are already in this session". "History hands selected Snaps over newest first" passes on the train by design: it pins the cause. |
| `.build/debug/LocalVoice --check-readback` (three runs) | Passed every run; `READBACK_CAPTURE_CHOICE_CHECKS_OK`: 81 checks, `READBACK_ORDER_CHECKS_OK`: 44 | Yes. With the train's `ReadbackView.swift` (Capture area in view state), "choosing Region on the page sets the session page's Capture area" fails. Setting the model directly instead, "returning to the page shows the Region chosen before leaving" fails, because the rebuilt page shows Screen. "a relaunch starts on Screen" guards against adding relaunch persistence; it cannot fail on the train, which has no such value. |
| `bash scripts/test-snap.sh` | `SNAP_CHECKS_OK`: 195 checks, `SNAP_REFRESH_CHECKS_OK`: 25 checks, unchanged (including "selected source order retained") | |
| `python3 scripts/check-surfaces.py` | 688 entries OK | |
| `python3 scripts/test-swift-extract.py` (`ReadbackModel.swift` is a harness source) | 18 tests OK | |
| `python3 scripts/test-readback-resources.py` | `READBACK_RESOURCE_LAYOUTS_OK`: 9 process checks | |
| `grep -n '@State private var captureMode' Sources/LocalVoice/ReadbackView.swift` | No match | |
| `.build/debug/LocalVoice --render-surfaces` | `SURFACE_GALLERY_OK`: 360 renders, 162 entries, 0 flags; Snap & Talk page renders byte-identical to the before set (two reruns after the review fixes: see Renders) | |

How the checks cover the two items:

- **Capture order (`--check-snap-capture`).** Three Snaps are saved a minute apart in a synthetic store and handed over through the real `handoffSnapshots`, which returns them newest first. After `importSnapSnapshots`, the session's earlier section is still first, the three new sections run oldest to newest, the oldest is the one under review, and the notice begins "Added 3 Snaps.". A fourth Snap added alone gives "Added 1 Snap." with no "Snaps". Adding the fourth again with a fifth adds only the fifth and ends "1 already present was skipped.". Adding the fifth again on its own adds nothing and begins "This Snap is already in this session".
- **Capture area (`--check-readback`).** A fresh session page starts on Screen. The real `ReadbackView` is hosted in a window kept off every display; its Capture area control (found by its Region, Window and Screen segments, since its label is hidden) shows Screen. Region is chosen through the control's own action, which sets the model's `captureArea`. The window is closed, a second page is hosted on the same model, and its control shows Region. A second model on the same preferences suite starts on Screen. `replaceScreenshot(_, mode: model.captureArea)` then opens the Region selector and never captures the screen. The hosted page finishes launching AppKit once before its first window, as the Snap capture checks and the gallery do on the CI runners.
- **What the checks do not reach.** The page's Capture & narrate, Replace screenshot… and Redo buttons pass `model.captureArea`, which the diff shows, but no check presses them: SwiftUI draws those buttons itself, so the hosted page has no `NSButton` to click, and it offers no accessibility children without an assistive client. Pressing them would mean synthesising clicks at guessed coordinates. The native steps below cover it.

## Not verified natively

On a signed Preview, by the integration owner or Ethan:

- In History, take or select five screenshots taken in order, then Use selected › Add to Snap & Talk. The new sections should run in capture order, with the first of them open.
- On the Snap & Talk page, choose Region, then Add from Snap History… and come back (or visit any other page). The picker should still show Region, and Capture & narrate should open the region selector. On a section's … menu, Replace screenshot… and Redo screenshot and narration… should open the region selector too. Quit and reopen: the picker should be back on Screen.
- Add one Snap that is already in the session: the notice should begin "This Snap is already in this session".
