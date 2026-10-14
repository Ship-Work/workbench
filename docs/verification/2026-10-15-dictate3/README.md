# Dictate: Record again delivers to the field; Import audio says why a file can't be read

Branch `claude/dictate-record-again-import`, stacked on the 15 October release train (`claude/train-1015`, which holds #345 and #347 on top of `main` at `edc15df`). The checks below ran on the branch's final source. Synthetic data only: fixture fields and targets, temporary recovery stores, synthetic WAV, CAF and byte files, and the surface gallery's isolated home. No installed app, real field, clipboard, microphone, model download or privacy setting was used.

## What changed

1. **Record again delivers where the toolbar's Record again does** (#337, item 4). The failure card's and the chooser's Record again called `recordAgain()` with no target. The new dictation therefore had no destination: live words did not stream into the field, delivery was copy only, and while presenting with Paste these two doors refused with "…or focus a Mac text field" even with a field focused. Both doors now pass `CaptureHUDControls.dictationTarget`, which the toolbar host wires to `targetForDictation()`, the same field read as the toolbar's own start. `recordAgain(target:)` stays start-only (#211). It reads the field only after its idle guard, so a stale press neither starts nor moves the keyboard. No label, control or entry point changed.
2. **Import audio says plainly why a file can't be read** (#337, item 5). Import audio and the Transcribe shortcut open the file through `ImportedAudio.open`. A file macOS can't open as audio now reads: "Workbench can’t read this file as audio. It may be incomplete or in a format macOS can’t open, such as WMA. Try an M4A, MP3 or WAV recording." That replaces Core Audio's error number, which appeared after "Could not read this audio file." in Import audio and on its own in Shortcuts. A readable recording over 30 minutes now says only "Choose an audio file between 1 second and 30 minutes long." Before, that sentence came after the false "Could not read this audio file.". Unchanged: the open panel's file filter, the 30-minute limit, Retry for the current recovery, and the `dictate.audio_unreadable` code.

## Renders

`before/` and `after/` hold one scratch render each, light and dark: `page-dictate-import-unreadable-{light,dark}.png`. To make them, the gallery's existing Dictate problem state was rebuilt with only its message replaced. `before/` uses the old message exactly as the train's harness produced it for an unreadable file. `after/` uses the new sentence. That temporary edit was reverted and is not committed. It shows the new message wrapping to two lines beside Retry transcription and Report a problem…. That pairing really happens: an unreadable import leaves a kept recording's Retry in place.

The gallery has no state for the failure card with Record again, which needs kept audio, so item 4 has no render. It changes no drawn label or layout. The committed gallery ran in full after both changes: 360 renders, 162 entries, 0 flags. That run includes its Record again start-only check, which now also requires that the field is never read.

## Checks

| Check | Result | Fails on the train without this change? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |
| `python3 scripts/test-capture-persistence.py` | 198 checks passed | Yes. Run against the train's sources, the new call-site inventory fails, naming `CapturePanel.swift` and `ToolbarActivityActions.swift` with `recordAgain()`. With `recordAgain(target:)` ignoring its target, the check "Record again starts toward the field the toolbar reads" fails with `nil`. Reading the field before the guard fails the check "Record again while requesting neither reads the field nor changes the request". With the train's `AppModel.swift`, "An unreadable import says why in words" fails, showing the old WMA text. With that check skipped, "A recording over 30 minutes is refused as too long, not unreadable" fails, showing "Could not read this audio file. Choose an audio file between 1 second and 30 minutes long." |
| `.build/debug/LocalVoice --check-integrations` | 26 checks passed | Yes: with `ImportedAudio.open` returning Core Audio's error unmapped, "an unreadable .m4a says why in words, with formats to try" fails. On the train itself, `ImportedAudio` does not exist. |
| `.build/debug/LocalVoice --check-core` | Passed (exit 0), including the integration checks above | |
| `.build/debug/LocalVoice --check-floating-toolbar` | `WORKBENCH_CONTROL_CHECKS_OK`: 221 checks | |
| `python3 scripts/check-surfaces.py` | 688 entries OK | |
| `bash scripts/test.sh harnesses` | Passed (exit 0) | |
| `.build/debug/LocalVoice --render-surfaces` | 360 renders, 162 entries, 0 flags | On the train, the updated gallery check does not compile, because `recordAgain` takes no target there. |

How the harness covers the two items:

- **Record again (`test-capture-persistence.py`).** The harness compiles AppModel's real `recordAgain` and `toggleRecording` beside a fixture target. Idle and ready, Record again gives the field to the start's admission and to the destination, and the phase is requesting. While requesting, and again while recording, it reads no field and leaves the phase and destination unchanged. A static inventory requires that every `recordAgain(` call outside AppModel and the gallery passes `target: controls.dictationTarget`, and that the toolbar host supplies `targetForDictation()`.
- **Import audio (harness and `--check-integrations`).** The harness runs AppModel's real `importAudio(_:)` on an invalid WAV and on a synthetic 1,801-second WAV. Each must raise exactly one plain sentence under `dictate.audio_unreadable`, leaving the kept recovery and recognizer untouched. `--check-integrations` checks that 4 KB of non-audio bytes saved as `.m4a`, and an empty `.wav`, give the plain sentence, with no "com.apple" and no "couldn’t be completed", naming M4A. It also checks that a two-second CAF still opens.

## Not verified natively

On a signed Preview, by the integration owner or Ethan:

- Dictate into a TextEdit document with Paste automatically. End it with a failure that keeps the audio, for example by unplugging the input device mid-recording. Choose Record again on the floating failure card, then again from the Dictate chooser. Each time the new words should go into the TextEdit document, not only onto the clipboard.
- The same with Present running and Paste automatically: Record again should start rather than ask for a Mac text field.
- Dictate › Import audio… on a truncated `.m4a`, a `.wma`, and a recording over 30 minutes. Each banner, the Home attention line and the menu-bar panel's row should show the plain wording, with no error number.
- The Transcribe with Workbench shortcut given an unreadable file should report the same sentence.
