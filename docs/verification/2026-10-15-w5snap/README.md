# Snap and Snap & Talk: ⌘Z in a text field, and a narration whose recorder stops by itself

Branch `claude/snap-undo-and-narration`, stacked on the 15 October release train (`d7cea35`). Refs #380, #63.

## What changed

1. **Snap editor.** ⌘Z in Title, Tags or Notes no longer removes marks from the image. While one of those fields has focus, the Undo and Redo buttons drop their ⌘Z and ⇧⌘Z shortcuts, so the keys reach Edit › Undo and Redo for that field. The canvas and the Text on image caption keep the image's Undo, as the caption's coalesced steps (#331) decided. The buttons, their help and their enabled state are unchanged. `docs/snap.md` says so in one sentence.
2. **Snap & Talk narration.** A take whose recorder stops by itself is kept as Stop keeps it. `ReadbackModel` now handles the recorder's end and encode-error callbacks for the current take only, with the notice "The microphone stopped, so narration ended. What was recorded was kept." The meter never lowers a take's length, and Stop reads the longer of the meter and the recorder. A stopped recorder reads 0 s, which used to make Stop delete the take ("No clear speech was captured") and Cancel discard it without asking. A callback after Stop, Cancel or Quit, or once a newer take has begun, changes nothing.

Neither change adds a control, setting or entry point. The surface registry is unchanged.

## Checks run

Debug build of this branch on macOS 26.5 (Apple Silicon), synthetic data only.

| Check | Result here | On the train head |
| --- | --- | --- |
| `swift build --product LocalVoice` | Passes | — |
| `LocalVoice --check-image-workspace` (run 3 times) | `IMAGE_WORKSPACE_CHECKS_OK: 101 checks`, 12 of them new | Fails (twice): "⌘Z in Title goes to the field and leaves the image's marks and steps alone". The check before it, that Title takes focus, passes. |
| `LocalVoice --check-readback` (run 4 times) | New `READBACK_SELF_STOP_CHECKS_OK: 14 checks`. Quit, retake, cancel and every other group pass unchanged. | Fails with the train's model plus an empty `narrationRecorderEnded`, which is what the train's delegate did: "meter ticks after the recorder stopped leave the take at 1.0 s". A throwaway probe that skipped that assertion then failed at "Stop after the recorder ended keeps the take"; the meter read 0.0 s. |
| `LocalVoice --check-snap-capture` | `SNAP_CAPTURE_CHECKS_OK: 189 checks` | Not a new check |
| `LocalVoice --check-capture-preview` | `CAPTURE_PREVIEW_CHECKS_OK: 60 checks` | Not a new check |
| `LocalVoice --render-surfaces` | `SURFACE_GALLERY_OK: 376 renders, 161 entries, 0 flags`, including the gallery's toolbar Cancel-narration checks | Not a new check |
| `bash scripts/test.sh harnesses` | Passes | Not a new check |
| `python3 scripts/check-surfaces.py` | `Surface registry OK: 687 entries` | Not a new check |

### What the new checks do

- **Image workspace.** In the live editor panel, with image steps to undo and to redo, each of Title, Tags and Notes is made first responder. ⌘Z and ⇧⌘Z are then sent through the panel. The panel must not claim either key, and the marks and both undo stacks must stay unchanged. Then ⌘Z on the canvas, after a field had focus, must take exactly one image step, and ⌘Z in a new caption must still undo the image.
- **Snap & Talk.** A synthetic take reads 1 s, then its recorder drops to 0 s while the meter keeps ticking.
  - The take keeps its length.
  - The end callback keeps it as `narration.wav`, queued, with no pending file left. The no-speech cue does not fire, and the notice names the microphone.
  - With no callback, Stop keeps the take.
  - A 74 s take whose recorder ended still asks before Cancel discards it.
  - A late callback leaves both a stopped take and a newer take alone.

## Renders

There is no visible change. The Snap editor's gallery renders are byte-identical before and after, light and dark (`before-snap-editor-*.png`, `after-snap-editor-*.png`). The Snap & Talk page, session panel and Snap toolbar renders are pixel-identical too.

## Not verified natively

- **Real keys in the installed app.** The checks send synthetic key events to the live editor panel. A synthetic event does not let SwiftUI tell ⌘Z from ⇧⌘Z: either one triggered whichever of Undo or Redo was enabled. So the canvas check sends ⌘Z with Redo empty, and the field check proves only that neither key is claimed. A native check is still owed: type in Title and press ⌘Z, then click the canvas and check that ⌘Z undoes and ⇧⌘Z redoes.
- **Whether a field's own undo reaches the saved Snap.** On macOS 26.5, the review found that a SwiftUI text binding may not follow a TextKit 2 undo. That is a separate finding and is not changed here.
- **How often macOS ends a recording on its own.** This was not reproduced, for example by unplugging a USB or Bluetooth microphone mid-take or by filling the disk. The callback path was driven directly with a synthetic recorder. A take that ended on a write error may hold damaged audio; it then ends in the existing Retry transcription state.
