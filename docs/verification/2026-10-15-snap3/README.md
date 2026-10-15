# Snap & Talk: a silent retake keeps the earlier words, the toolbar's Cancel asks first, the notice names a working key

Source checked **15 October 2026** on branch `claude/snaptalk-retake-and-cancel`, stacked on the 15 October release train `claude/train-1015` (main `edc15df` plus that night's nine PRs). Refs #342. These are source checks and offscreen renders with synthetic data only. Native acceptance on the installed Preview is listed at the end and is still owed.

## What changed

1. **A retake that hears no words keeps the earlier words.** Stop now sets aside only the earlier audio and its original transcript. The notes or edited narration (`narration.txt`) stay linked, and stay in the page, while the new take transcribes. When the take has words, the still-linked text moves to `history/` before the new files are written. When it has none, the silent WAV moves to `history/` and the section's audio is cleared. A section that still has text stays Ready with no failure. A section with nothing linked goes back to Needs narration with "No speech was heard. Record the narration again." The notice reads "No speech heard. The screenshot and any earlier narration were kept." So the page no longer shows Transcription stopped, Retry transcription or "1 needs a retry" for a take that can only fail again. Real engine failures keep `.failed` and Retry transcription, as before, and the earlier text stays on disk. If the next section is already recording when an empty result lands, the page keeps that take's narrating notice, which says how to stop it, and the earlier section shows what it kept. `docs/snap.md` has one new sentence, which names the on-device model: a local server reports no speech as an error, so its take still ends with Retry transcription.
2. **The toolbar's Cancel narration asks first, as the page does.** ReadbackModel now holds one rule for both doors: `cancelAsksFirst(elapsed:)` (more than ten seconds), `requestCancelNarration()`, the published `pendingCancelNarration` (the take's identity) and `confirmCancelNarration(_:)`, which acts only on the take it asked about. The page's existing "Discard this narration?" dialog binds to that question. The toolbar chooser's Cancel narration discards a short take at once, as before. For a longer take it opens Snap & Talk with the page's question showing, so it no longer deletes up to five minutes without asking. The question clears whenever recording ends, including the 300 s auto-stop. There is no alert, so the narration timer keeps running. `docs/floating-toolbar.md` says so in one clause. The surface gallery now runs the chooser's own Cancel narration command against a synthetic take.
3. **The narration notice names its key only when the key works.** `usableShortcutLabel` reads the model's own preferences and is nil when the Snap & Talk shortcut is off or failed to register. Without a usable key, the notice ends "Use Stop narration to finish." instead of "Use Off again to stop.", and the Capture & narrate help leaves out the key. The options sheet shows the registration failure, or "No shortcut is set. Capture & narrate on the page still works." With a working key, every sentence reads as before.

No control, label, setting or entry point was added. `python3 scripts/check-surfaces.py` reports the registry unchanged.

## Checks run

All checks ran on the debug build of the final source.

| Check | Result | Fails without the change |
| --- | --- | --- |
| `LocalVoice --check-readback` | Passed: 117 store, 25 admission, 12 typed-note, 73 capture-choice, 72 capture-access, 19 availability, 18 recovery, 28 quit, **32 retake**, **16 cancel**, **9 shortcut-notice**, 33 pack and 44 ordering checks | Yes, see below |
| `swift test --filter ToolbarActivityChooserTests` | Passed: 7 tests | Regression only |
| `LocalVoice --check-core`, `--check-capture-preview` (60), `--check-readback-pack`, `--check-snap-capture` (182) | Passed | Regression only |
| `bash scripts/test-snap.sh` | Passed: 195 Snap checks and 25 refresh checks | Regression only |
| `bash scripts/test.sh harnesses` | Passed | Regression only |
| `LocalVoice --render-surfaces` with `WORKBENCH_SNAPTALK_GALLERY_ONLY=1` | 12 renders. Only the new options-with-shortcut-off pair differs from the train's | Visual |
| `LocalVoice --render-surfaces` with the desktop pass, which holds the Snap & Talk session states | 194 renders, 0 flags. The new state's pair is byte-identical to the after images below | Visual |
| `LocalVoice --render-surfaces` (full gallery, as CI runs it), with the new toolbar step "Snap & Talk's Cancel narration in the chooser" in light and dark | Passed: 360 renders, 162 entries, 0 flags; the new step is OK in light and dark | Yes, see below |

Each new check was confirmed to fail without its change:

- **Retake.** The new checks were run against the train's `ReadbackModel.swift`, with only the checks added. They fail "notes: Stop keeps the earlier text linked and in the page's draft while the take transcribes". With Stop's change kept but the no-words branch replaced by the old throw, they fail "notes: an empty result leaves the section ready with no audio to retry". The checks stop at the first failure, so the narrated, fresh and nothing-linked cases were not run separately under that mutation. They assert the same branch.
- **Cancel.** `requestCancelNarration()` discarding at once, as the toolbar door did, fails "at 74 s Cancel asks about this take and keeps the file". Removing the clear when recording ends fails "Stop clears the question".
- **Shortcut notice.** Returning the label unconditionally fails "a disabled shortcut has no usable label". Dropping only the registration guard fails "a shortcut that failed to register has no usable label".
- **The chooser's Cancel narration.** With the chooser line put back to the train's direct `cancelNarration()`, `WORKBENCH_TOOLBAR_GALLERY_ONLY=1 LocalVoice --render-surfaces` fails the run in light and dark: "at 74 s Cancel narration did not keep the take and ask about it; at 74 s Cancel narration did not open Snap & Talk". The 5 s step passes either way, as it should.
- **The late notice.** With the guard removed, so an empty result always sets "No speech heard…", the retake checks fail "next section: section 1's empty result leaves section 2's narrating notice". This case was not run against the train, whose model lacks the other new checks' APIs. There, the empty result ends Transcription stopped, and its notice replaces the narrating one.

The retake checks use the synthetic recorder from #330 and a controlled transcriber. The cases cover imported notes, an earlier narration, a fresh capture's empty note, nothing linked, an engine failure, words, and an empty result that lands while the next section records. The cancel checks move the synthetic take's meter to 74 s, 5 s and 300 s, so they need no microphone. The gallery's chooser step builds the real floating toolbar on a recording model with the same synthetic recorder, chooses Cancel narration at 74 s and at 5 s, and records which page the toolbar asked to open.

## Renders

The new `settings-shortcut-off` gallery state opens Snap & Talk's options with the shortcut turned off. The before images were drawn from the train's view in the same state. On the train, the options read a different preferences store from the model's, so for the before image only, the state also wrote the same preference there. That temporary line is not committed.

| | Light | Dark |
| --- | --- | --- |
| Before | ![Before, light](before-options-shortcut-off-light.png) | ![Before, dark](before-options-shortcut-off-dark.png) |
| After | ![After, light](after-options-shortcut-off-light.png) | ![After, dark](after-options-shortcut-off-dark.png) |

Before, the Keyboard shortcut line says "Off captures the display under your pointer and starts narration." After, it says "No shortcut is set. Capture & narrate on the page still works." In the same gallery, the review, access-off, access-pending and default options renders are byte-identical to the train's.

Item 1 changes no view code. A section that comes back from an empty retake is drawn by the existing Ready branch with its notes, as the gallery's review state already shows. The dialog in item 2 is a native confirmation that the offscreen gallery does not draw.

## Not verified natively

These need the installed Preview, a microphone and a person:

- Re-record over a section with notes while the input is muted. The notes should stay, and no Retry should appear.
- Narrate past 10 s, then choose Cancel narration in the toolbar chooser. Snap & Talk should open with "Discard this narration?" showing, and Keep recording should continue the take. Whether the dialog appears when the page mounts with the question already set can only be seen natively.
- With ⌥C off, choose Capture & narrate. The notice should end "Use Stop narration to finish."

## Known limits

- **A local server's "no speech".** The local-server provider reports an empty transcription as an error, so a silent retake with that provider still ends Transcription stopped with Retry transcription. The earlier text stays linked on disk but is hidden until the section is recorded again. Changing what the provider returns would also change Dictate, so it is left for a separate decision.
- **A take queued here and transcribed by an older build.** Stop now leaves the earlier `narration.txt` linked until words arrive, and only this build archives it before writing. An older build that transcribed such a take would overwrite it without a copy in `history/`. That needs the same session folder open in both editions with a take queued across the switch; each edition keeps its own preferences, recent sessions and support folder, so it is not expected in use.
- **Shapes that change on purpose.** A previously narrated section whose retake comes back empty becomes audio-less, so its text shows under Notes with Record narration; that is the shape an imported Snap has, and the earlier audio is in `history/`. While a take is queued or failed, the manifest links the earlier `narration.txt` beside the new audio; the editor is hidden in those states.
