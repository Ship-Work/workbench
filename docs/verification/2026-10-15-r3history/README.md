# History copies confirm where pressed · 15 October 2026

Branch `claude/history-copy-confirms`, stacked on the 15 October train `claude/train-1015`. Synthetic data only. Refs #338, #134.

## What changed

1. **History's Copy and Copy result confirm in place, and are heard** (#338). Before, a transcript row's Copy (and the context menu's Copy) and an expanded result's Copy result only issued the toolbar's receipt cue, wherever the toolbar was. History showed nothing and VoiceOver heard nothing, while a Snap's Copy on the same page confirmed in the header.
   - A written copy shows ✓ Copied for four seconds beside the control pressed. In a transcript row it sits after More; in a result, beside Copy result. Every row keeps the space, and the Spacer absorbs it while nothing shows. VoiceOver hears it once.
   - A refused write confirms nothing. Its reason shows under that row or result, and is heard.
   - History owns the one confirmation (`TranscriptReviewFeedback`, as Meetings, Home and Review transcript use), keyed to the transcript or task copied. Rows sit in a lazy list and can leave it, so it is the page's, not a row's. A new copy anywhere in History moves it, and the owner's event-checked expiry stops a stale timer.
   - It is judged by the copy's outcome, never the status line. `copyCapture` and `copySavedResult` now return their outcome, and `copyCapture` returns nil for an empty transcript, which attempts nothing and leaves the status saying the last copy's words. Existing callers are unchanged.
   - The header keeps Snap's slot. The clipboard receipt, the toolbar cue and undelivered-result handling are unchanged.
2. **Settings › Updates: the confirmation sits under its row** (#338). The ✓ Copied kept for Copy build details sat between that button and Release notes and downloads, so the row always read as two buttons, a hole, then a stray link. It now sits under the row and shares that line with the problem note, as Meetings' Copy transcript does (Fit rule 7).
3. `docs/workbench.md` (History) says Copy and Copy result confirm beside the action.

## Renders

`before/` is `--render-surfaces` from `claude/train-1015`, this branch's base. `after/` is this branch. File names match, in light and dark.

- `page-settings-default-*`, `page-settings-narrow-*`: the gap from Copy build details' bezel to the link's first mark, measured at 2x across the bezels' height:

  | Render | Between the buttons | Copy build details → link |
  |---|---|---|
  | before, default and narrow, light and dark | 16 px (8 pt) | 135 px (about 67 pt) |
  | after, default and narrow, light and dark | 16 px (8 pt) | 18 px (9 pt) |

  The limit is the gap between the buttons plus 8 px, so 24 px. Main, before the train added the reserved label, also measures 18 px. The Updates card is one caption line taller, which is the space kept for ✓ Copied.
- `page-settings-state-copied-*` (after only): Settings › General after Copy build details. ✓ Copied sits under the row. Every pixel above it matches the at-rest render of the same window; the only difference is the label itself.
- `page-history-state-transcripts-*`: the at-rest page is pixel-identical to the train, as are History's mixed, results, larger-text and result-reuse renders. The reserved space is invisible at rest.
- `page-history-state-copied-*` and `-copied-larger-text-*` (after only): the newest transcript confirming ✓ Copied, in the minimum window's content column (History's narrowest), at standard and 1.35 times the text size. Copy, Review transcript, Details…, More, ✓ Copied and the trash all fit on one line, with nothing clipped.
- `page-history-state-result-copied-*` and `-result-copied-larger-text-*` (after only): an expanded result confirming ✓ Copied beside Copy result, at both sizes.

The full gallery passed on the final code: `SURFACE_GALLERY_OK: 370 renders, 162 entries, 0 flags`.

## Checks run (debug build, this Mac)

| Check | Result | Fails on the train? |
|---|---|---|
| `swift build --product LocalVoice` | passes | — |
| `--check-feedback` (also in `--check-core`) | 143 checks pass, 11 of them new. They drive the glue History's rows call, with Copy result through `HistoryResultReuse.copy`, a private pasteboard, a synthetic clock and an announcer. A transcript copy writes the exact words and confirms ✓ Copied for that id only, heard once. It is there at 3.9 s and gone at 4.0 s. Copy result two seconds later takes the label, is heard, and is not ended by the first copy's timer. The receipt keeps the result's identity. A refused write confirms nothing and is heard as its reason, beside the item pressed. An empty transcript right after a copy confirms nothing and hears nothing | Yes. The glue does not exist on the train, so the check does not compile. Two mutations of the glue each fail it: confirming before the write fails "a refused write confirms nothing…", and keying on the status text (which only an attempted copy changes, as `AppModel.status` does) fails "an empty transcript right after a copy attempts nothing…" |
| `--check-core` | passes | — |
| `python3 scripts/test-capture-persistence.py` | 202 checks pass, 3 of them new. On the exact `AppModel.copyCapture`: it writes the exact words to the pasteboard it is given and reports the write; an empty transcript returns nil and writes nothing while the status still says the last copy's words; a refused write reports its failure | Yes. Against the train's `AppModel.swift` the new checks do not compile (`copyCapture` takes no pasteboard and returns nothing) |
| `--check-handoff-jobs` | 218 checks pass, including the existing Copy result receipt assertion | — (unchanged) |
| `--check-history-journey`, `--check-history-library` | pass | — (unchanged) |
| `python3 scripts/check-surfaces.py` | 688 entries OK, `docs/surfaces.json` unchanged | — |
| `scripts/test.sh harnesses` | passes | — |
| `--render-surfaces` | `SURFACE_GALLERY_OK`, 0 flags | — |
| Settings gap measurement (above) | 18 px against a 24 px limit | Yes. 135 px on the train |

## Not verified natively

- A VoiceOver listen to History's Copy and Copy result, and to a refused copy, is owed, as #338 records. The checks prove what is announced, not how VoiceOver speaks it.
- Pressing Copy and Copy result in the installed app. The renders and checks cover the layout and the owner, not a pointer pass.
- A refused pasteboard write is simulated. The checks inject it; a real refusal was not produced.
