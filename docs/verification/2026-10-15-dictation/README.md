# Dictation: every outcome copies or explains

Branch `claude/dictation-outcomes` from `main` at `edc15df`; the checks below ran on the source at `d246071`. Synthetic data only: fixture fields and owners, temporary recovery stores, synthetic WAV bytes and the surface gallery's isolated home. No installed app, real field, clipboard, microphone, model download or privacy setting was used.

## What changed

1. **A stopped live writer leaves the words copied** (#328). When the live in-field writer stops before Stop, `LiveDictationDelivery.finish` copies the transcript as dictated whatever Restore clipboard says, as every failed ⌘V return already does. A writer that never wrote ends as an ordinary copy ("Copied. The field changed, so nothing was pasted. Paste with ⌘V when ready."), records no Paste unconfirmed entry and releases its recording. One that wrote and could not confirm keeps Paste unconfirmed, with no Copy again, says the transcript is copied and keeps its audio in Saved recordings. No fallback paste is added; `docs/live-voice.md` says so.
2. **A Cancel that leaves live words says so** (#328). The reason now sets the capture failure and the Dictate attention (`dictate.cancel_live_text_kept`) before the capture's phase ends, so the toolbar shows its Dictation stopped result with Retry transcription and Dismiss, and the Dictate banner and the panel's recovery row explain it. The message is shorter: "Cancelled. Words already written in *app* were left there. The recording is kept."
3. **A download that did not finish says so** (#15). FluidAudio's stalled, refused, rate-limited, HTML, invalid-response and invalid-artifact download errors read "The download did not finish. Your saved work is unchanged; try Download again later." (a rate limit: "The model host is busy. Try Download again in a few minutes."), with FluidAudio's text as Details. A missing model, offline mode, connection errors and Core ML failures are unchanged.
4. **Dictate's banner offers Retry** (#337). A kept capture's Retry transcription or Retry saving sits beside the message that promises it, only on Dictate. Capture recovery is unchanged.
5. **The failure card's door is Open Dictate…** (#337), the name the panel's recovery row and the toolbar chooser give the same door. The registry entry is renamed by hand and belongs to Dictate.
6. **History's problem note can be dismissed** (#337). The note is a card with its own ×; dismissing it clears the panel's recovery row too and retries nothing.

## Renders

`before/` is `main` at `edc15df`; `after/` is this branch. Same file names, light and dark.

| Item | File |
| --- | --- |
| 4 | `page-dictate-problem-door-{light,dark}.png`: Retry transcription beside Report a problem… |
| 5 | `panel-floating-dictation-failure-right-{light,dark}.png`: Open Dictate… in place of Open Workbench |
| 6 | `page-history-state-error-{light,dark}.png`: the note in a card with its × |

Items 1 to 3 change runtime text and state with no gallery fixture.

## Checks

| Check | Result | Fails on `main`? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |
| `python3 scripts/test-live-dictation.py` | 40 checks passed | Yes: with `main`'s `LiveDictationDelivery.swift`, the moved-owner copy check fails; with that check removed, the owner-born-stopped check fails next. |
| `python3 scripts/test-capture-persistence.py` | 193 checks passed | Yes: with `main`'s `AppModel.swift`, "A field never written releases its original audio" fails. With status-only Cancel sites, "Cancel that leaves live words explains it … (recording)" fails. |
| `.build/debug/LocalVoice --check-providers` | `RECOGNITION_LIFECYCLE_CHECKS_OK`: 47 checks | Yes: with `main`'s `RecognitionReadiness.swift`, the stalled-download classification fails. |
| `.build/debug/LocalVoice --check-live-dictation-delivery` | 40 checks passed | |
| `.build/debug/LocalVoice --check-core` | Passed | |
| `python3 scripts/check-surfaces.py` | 682 entries OK | Yes: with `main`'s `CapturePanel.swift` against this registry, it reports the renamed door as unregistered and stale. |
| `python3 scripts/test-check-surfaces.py` | 58 tests OK | |
| `bash scripts/test.sh harnesses` | Passed | |
| `.build/debug/LocalVoice --render-surfaces` | 350 renders, 163 entries, 0 flags | Yes, for items 4 and 6, in a bounded pass: with `main`'s `Views.swift` the Dictate problem render fails ("does not offer Retry transcription"); without the Dictate-only gate it fails on Your dictionary; with `main`'s `HistoryView.swift` the History error pass fails ("no × of its own"). |

The gallery cannot press SwiftUI controls offscreen: the hosting view exposes no accessibility children without an assistive client, and it ignored a synthetic click on the History ×. So the Dictate check compares the banner band with Retry available and unavailable, and the History check reads the note's row for an isolated glyph-sized mark at its right. Neither presses the button; the actions are the existing `retryTranscription()` and `dismissError()`.

## Not verified natively

On a signed Preview, by the integration owner or Ethan:

- ⌥V into TextEdit with Paste automatically, click in another app mid-dictation, then Stop: expect "Copied · The field changed, so nothing was pasted. Paste with ⌘V when ready." and the words on the clipboard.
- Live words written into a real field, then a click in that field and Cancel: expect Dictation stopped with Retry transcription and Dismiss at the toolbar, and the same reason on Dictate and in the panel.
- A real stalled or rate-limited Parakeet download (not reproducible tonight).
- Pressing the Dictate banner's Retry transcription, the failure card's Open Dictate… and History's × with a pointer and with VoiceOver.
