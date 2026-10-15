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
| `LocalVoice --check-image-workspace` (run 8 times on the final check) | `IMAGE_WORKSPACE_CHECKS_OK: 109 checks`, 20 of them new | Fails (3 of 3 runs): "⌘Z in Title goes to the field and leaves the image's marks and steps alone". The checks before it pass: Title takes focus, and ⌘Z and ⇧⌘Z on the canvas undo and redo one step. |
| `LocalVoice --check-readback` (run 9 times) | New `READBACK_SELF_STOP_CHECKS_OK: 14 checks`. Quit, retake, cancel and every other group pass unchanged. | Fails with the train's model plus an empty `narrationRecorderEnded`, which is what the train's delegate did: "meter ticks after the recorder stopped leave the take at 1.0 s". A throwaway probe that skipped that assertion then failed at "Stop after the recorder ended keeps the take"; the meter read 0.0 s. |
| `LocalVoice --check-snap-capture` | `SNAP_CAPTURE_CHECKS_OK: 189 checks` | Not a new check |
| `LocalVoice --check-capture-preview` | `CAPTURE_PREVIEW_CHECKS_OK: 60 checks` | Not a new check |
| `LocalVoice --render-surfaces` (final head) | `SURFACE_GALLERY_OK: 376 renders, 161 entries, 0 flags`, including the gallery's toolbar Cancel-narration checks | Not a new check |
| `bash scripts/test.sh harnesses` | Passes | Not a new check |
| `python3 scripts/check-surfaces.py` | `Surface registry OK: 687 entries` | Not a new check |

### What the new checks do

- **Image workspace.** In the live editor panel, with image steps to undo and to redo, each of Title, Tags and Notes is made first responder, starting each time from the canvas. ⌘Z and ⇧⌘Z are then sent through the panel. The panel must not claim either key, and the marks and both undo stacks must stay unchanged. Before each field takes focus, and after Notes, ⌘Z on the canvas must take exactly one image step and ⇧⌘Z must put it back, with both stacks live. ⌘Z in a new caption must still undo the image.
  - The keys are built from CGEvents, which carry the keyboard layout. A key built with `NSEvent.keyEvent` has none, and SwiftUI then matched ⌘Z to Redo as often as to Undo. The check first asserts that its ⌘Z reads as Z on the current layout.
- **Snap & Talk.** A synthetic take reads 1 s, then its recorder drops to 0 s while the meter keeps ticking.
  - The take keeps its length.
  - The end callback keeps it as `narration.wav`, queued, with no pending file left. The no-speech cue does not fire, and the notice names the microphone.
  - With no callback, Stop keeps the take.
  - A 74 s take whose recorder ended still asks before Cancel discards it.
  - A late callback leaves both a stopped take and a newer take alone.

## Renders

There is no visible change, so no PNGs are kept here. A full `--render-surfaces` run of the final branch head was compared with the same renders from the train, light and dark:

- Byte-identical: `page-snap-workspace-{compact,crop,text}`, `page-readback-{default,narrow,screen-access-off}`, `panel-snap-session`, and every `toolbar-snap-*` and `toolbar-snapAndTalk-*` render (left, centre and right; resting and revealed). `page-snap-workspace-text` is the editor with Title, Tags and Notes showing.
- Pixel-identical, different bytes: `page-home-hint-readback-*` and `panel-shortcut-editor-*`.

## Not verified natively

- **Real keys in the installed app.** The checks build keys from CGEvents and hand them to the live editor panel; nothing is posted to the system. A native check is still owed: type in Title and press ⌘Z, then click the canvas and check that ⌘Z undoes and ⇧⌘Z redoes.
- **A caption's typing and Edit › Undo.** Owed with the step above: choose Text, type "Hello" in the caption, click Title, type a letter and press ⌘Z twice. The letter goes, and the caption and the image keep "Hello".
- **Whether a field's own undo reaches the saved Snap.** On macOS 26.5, the review found that a SwiftUI text binding may not follow a TextKit 2 undo. That is a separate finding and is not changed here.
- **How often macOS ends a recording on its own.** This was not reproduced, for example by unplugging a USB or Bluetooth microphone mid-take or by filling the disk. The callback path was driven directly with a synthetic recorder. A take that ended on a write error may hold damaged audio; it then ends in the existing Retry transcription state.

## Integration review, 16 October

The cross-stream review of the integrated train (`31c4da7`) routed two findings here. This branch was brought up to that head by merge before fixing.

1. **P2, fixed. ⌘Z in Title, Tags or Notes could reach a caption's typing.** With the image's shortcuts stepping aside in those fields, ⌘Z reached Edit › Undo and the panel's shared undo stack, which held the Text on image caption's own typing. On the train head, the new check types "Hello" into a caption, clicks Title and sends Edit › Undo: the caption box went back to "Your text" while its mark kept "Hello". The final check fails there 2 of 2 runs. The caption's text view no longer keeps its own typing undo; a caption's typing stays one step on the image's Undo (#331). The hook that already finds that text view for Text's focus request turns the undo off when the caption appears and again before it takes focus. `--check-image-workspace` types into a caption in two keystrokes with an update between them, then gives Title, Tags and Notes focus in turn and sends `undo:` up each field's responder chain whenever its undo manager has something to undo, as Edit › Undo does. The caption, its mark, the selection and both image stacks must stay unchanged. Each field must also take focus beside the selected caption. Result: `IMAGE_WORKSPACE_CHECKS_OK: 116 checks` (4 of 4 runs), 7 of them new. `--check-snap-capture` (189) and `--check-capture-preview` (60) pass, and `--render-surfaces` reports 376 renders, 161 entries and 0 flags.
2. **P3, not changed. A take recorded before speech is downloaded fails at once.** It does: the page says "You can record for later", and the take then ends as Failed with "Open Models to prepare speech first" and Retry transcription. The suggested fix keeps the take queued until speech is ready. A queued take counts as a pending transcription, though, and Settings › Models disables Download Parakeet while one is pending ("Model changes are available when recording and processing finish"). Models is the door Snap & Talk names, so the take would wait on a download that it blocks. It would also block Dictate, keep the toolbar's "Transcribing narration" up, and lock that section's own controls until the download. #330 chose failure with a reason over a silent queue for this case, and `--check-readback` asserts it ("idle"). A take that waits for a download needs a kept-for-later state that is not a pending transcription; that is a separate design change, not a fix for this branch.

