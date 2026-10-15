# Retire the unopened shortcut recorder and unreferenced declarations · 15 October 2026

Branch `claude/retire-recorder-and-unused`, from the 15 October train (`claude/train-1015`, on `main` at edc15df), with the train merged in again at 88c5e67 so every deletion is checked against the integrated code. It lands after #353; retarget to `main` once #353 merges. Source checks and offscreen renders with synthetic data only. Nothing here was installed, and no claim of installed or native acceptance is made. Refs #76, #362.

## What changed

1. **The in-place Dictate shortcut recorder is gone** (#76). Since every keycap opens Settings › Keyboard on its shortcut, nothing called `AppDelegate.editShortcut`, the only writer of `AppModel.editingShortcut`. Deleted with it: its key monitor and `finishEditing`, ShortcutControl's Cancel and recording hint, ShortcutKeycap's recording style, the unreferenced `VoiceShortcutSettings` view (which still taught "Delete turns a shortcut off"), `onCancelShortcut`, `onResetShortcuts` and `StageKitController.resetShortcuts`. `registerShortcuts` now waits only while shortcuts are suspended. ShortcutKeycap keeps its label, accessibility label and help. StageKit's own recorder and `AppCoordinator.restoreShortcuts`, which Draw's settings use, are unchanged. Settings › Keyboard is now the only recorder.
2. **Declarations nothing references are gone** (#362):
   - StageKitController: `hasOverlaySession` and `areOverlaysPaused` (copies of `hasActivePersonaSession` and `isPersonaSessionPaused`), `canStepOverlays`, `showBoard`, `stepOverlaySet`, `toggleOverlayVisibility`, `performShortcut` and `quickControlsView`. `escape()` stays; the app calls it three times.
   - `ReadbackModel.installServiceNowPack` and `ReadbackResources.installServiceNow`, which always threw, so the success notice could never show. Uninstall stays; the pack checks use it.
   - AppModel's `captureOutputModeLabel` and `captureShortcutInstruction`, written on every capture and read nowhere, and `captureDestinationName`. `CaptureSettings.outputLabel` stays.
   - `PackLimits.maximumPointerBytes` and `maximumCachedFiles`, which nothing enforced although the table says it holds every bound the pack core enforces. PackStore's prune now keeps `PackLimits.maximumRetainedRevisions` instead of a literal 3, and GitHub sign-in uses `GitHubPackClient.jsonAccept` instead of repeating the string. Both are the same values.
   - Strays: `CapturePanelController.chooserOffscreenForChecks`, `SnapSnapshot.sourceReference`, `SubscriptionCLI.claudeImagesVerified`, `TranscriptHandoffSkillCheck.bundledDeckIdentifiers` and `ToolbarShortcut.isUsable`.

No migration, preservation or recovery code is touched, and no saved data is read or written differently. Every name was re-checked on the train head at 88c5e67, after the merge: none gained a caller. Each had only its own declaration in Sources, Tests and scripts, or a use inside the code deleted with it.

### The rest of #76 and #362

- #76's first item, hints that name a key only when it is registered, is already on the train: `VoiceShortcut.usableLabel(failure:)` guards Dictate's hint and placeholder, History's empty state and Library's footer. Its note that `captureShortcutInstruction` is never read is answered here.
- #362's other two parts, Home's Open Home… route with the two Not now buttons that never render, and what the removed More menu and Appearance accessory left behind, are a separate branch, `claude/retire-home-toolbar-leftovers`. Those parts change `docs/surfaces.json` and one toolbar gallery render; this branch changes neither. `git merge-tree` merges the two branches without a conflict.

## Renders

`before/` is `--render-surfaces` from `main`. `after/` is this branch, the same bytes before and after the merge. Dictate settings with the Shortcut row (ShortcutControl and ShortcutKeycap's one live caller), in light and dark. They are byte-identical.

The whole gallery from this branch after the merge (`SURFACE_GALLERY_OK: 376 renders, 162 entries, 0 flags`) matches the train's render at 59753fc: all 376 PNGs are identical (338 byte-identical, 38 pixel-identical), and `index.html` and `manifest.json` are byte-identical. The train's one later change is how a Meetings recording finishes, with its checks; it touches no render. Before the merge, the branch's gallery against main's 350: 206 byte-identical, 144 pixel-identical, none different; the rest are renders the train added.

## Checks run on the merged head (this Mac)

| Check | Result | Fails before? |
|---|---|---|
| `rg -n 'editingShortcut\|shortcutRecordingMessage\|onCancelShortcut\|onResetShortcuts\|VoiceShortcutSettings\|func editShortcut\|resetShortcuts\(' Sources Tests` | no matches | Yes: 24 matching lines on the train head |
| `rg -n 'recorderMonitor\|finishEditing' Sources/LocalVoice/main.swift` (StageKit's recorder and CaptureImagePreview keep their own) | no matches | Yes: 11 on the train head |
| `grep -rnw <name> Sources Tests scripts` for each of the 27 deleted names (7 from the recorder, 20 declarations) | no matches for any | Yes: all 27 found on the train head |
| `swift build --disable-sandbox --product LocalVoice` | passes; the 14 changed files recompiled with no warning | — |
| `swift build -c release --disable-sandbox --product LocalVoice` | passes with no new warnings: the only four are in untouched files, `HandoffManualChecks.swift:218`, `PackCredentials.swift:36` and `PhoneLink.swift:591`, `:592` | — |
| Every `--check-*` the checks phase runs (core, read-retirement, shortcut-migration, readback, snap-capture, presenter, providers, refinement, transcript-handoff, readback-pack, capture-preview, image-workspace, history-library, history-journey, handoff-jobs, subscription-cli, meetings, bug-report), plus floating-toolbar, live-dictation-delivery, insertion-boundary and feedback from `verify-preview.sh`, with the debug build | all 22 pass | — |
| `scripts/test-read-retirement.py --binary` and `scripts/test-snap.sh` (which compiles `SnapStore.swift` alone) | pass | — |
| `bash scripts/test.sh harnesses` (surface registry, Python harnesses that compile AppModel members, browser extension) | passes | — |
| `python3 scripts/check-surfaces.py` | `Surface registry OK: 689 entries.`; `docs/surfaces.json` is the train's | — |
| `python3 scripts/test-check-surfaces.py` | OK | — |
| `swift test --disable-sandbox --filter 'PrivatePackKitTests\|ToolbarCoreTests\|ToolbarKitTests'` (PackStore's prune and install tests included) | 237 tests, 0 failures; 2 opt-in on-screen tests skipped as designed | — |
| `bash scripts/test-stage.sh --ci` | 340 tests, 6,715 assertions, 0 failures. 2 skipped because the installed Preview holds the Draw keys; CI checks them | — |
| `--render-surfaces`, compared PNG by PNG with the train and with main | see Renders | — |

These are deletions and two same-value substitutions, so no new check is added: nothing a person can see or do changes, and the compiler rejects any missed reference. The greps above are the before-and-after evidence.

## Not verified

Nothing was installed and the app was not opened. The deleted recorder had no caller, so there is no native path to exercise; Settings › Keyboard's recorder and the panel's inline editor are unchanged and were not retried by hand. The whole `swift test` (`scripts/test.sh package-tests`) was not run; the package tests named above cover every package target this change touches. The two skipped StageKit shortcut tests run in CI.
