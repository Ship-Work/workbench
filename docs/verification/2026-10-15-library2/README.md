# Library: Quit asks before discarding the editor; transcript skill choice confirms

Checked **15 October 2026** on source `08f260d`, branched from `main` at `edc15df`. Refs [#341](https://github.com/Ship-Work/workbench/issues/341). Synthetic data only.

## What changed

**Quit with an open Library editor.** The resource editor reports each edit to an unpublished working copy on `DemoLibraryModel`, so typing never re-renders Library. When that copy differs from the draft, `applicationShouldTerminate` asks "Discard your changes to this prompt?" (or link or file) with **Keep editing** and **Discard**. The body says "It has not been saved to Library." for a new resource and "The saved version in Library stays unchanged." for an existing one. Keep editing cancels Quit and shows Library again. Neither answer clears the draft, so if a later guard cancels Quit, nothing is lost. This follows the Snap draft's question (`CaptureImagePreview.canTerminate`). An unchanged editor, Cancel and Save never ask.

The `main.swift` change is one line in `applicationShouldTerminate`, straight after `guard CaptureImagePreview.shared.canTerminate()` and before the `guard let model, model.meetings.isBusy …` line that returns `.terminateNow`. It does not depend on the other quit guards, so an integrator can move it as a unit.

**Packs › Use skill for transcripts.** Choosing a transcripts skill now opens History on **Transcripts**, not All. History's existing Hand off caption then reads "<skill> is chosen for Hand off. Select transcripts, then Hand off…", naming the skill as the Hand off picker does (for example "Meeting notes (Workshop starters)"). The choice is still not stored. A refused choice and a Snap & Talk choice set no caption, and Snap & Talk's own notice is unchanged.

## Checks run

| Check | Result | Fails without the change? |
| --- | --- | --- |
| `swift build --product LocalVoice` (debug) | passed | n/a |
| `LocalVoice --check-library` | passed; `DEMO_LIBRARY_MODEL_CHECKS_OK` now covers: no editor, an unchanged editor, Keep, Discard, an edit for another resource, Cancel and Save | Yes. With `canTerminate` returning true as on `main` (Quit never asks), it exits 1 at "Keep editing did not refuse Quit with the typed prompt intact". |
| `LocalVoice --check-readback-pack` | passed; 33 frozen-pack checks and 44 Pack owner checks (was 43) | Yes. With the caption line removed, it exits 1 at `PACK_LIBRARY_CHECK_FAILED: History says which skill is chosen for Hand off and what to do next`. |
| `LocalVoice --check-core` | passed (runs the Library model checks too) | n/a |
| `scripts/test.sh harnesses` | passed, including `LIBRARY_RECALL_CHECKS_OK`, which compiles the real Library model and view, and the surface registry | n/a |
| `LocalVoice --render-surfaces` | 350 renders, 163 entries, 0 flags | n/a |

Both new checks call members that do not exist on `main`, so they cannot compile there. Each "fails without the change" result above comes from putting back `main`'s behaviour in the new code, rebuilding and running the same check. The real code was then restored, rebuilt, and passed again.

## Renders

`before/` is from `main` at `edc15df` and `after/` is from this branch. Both use the gallery's fixed synthetic states in light and dark. The pairs are byte-identical: the gallery has no state with an open editor during Quit, or with a pack choice's caption. These pairs show that the touched pages are unchanged. They do not show the new question or caption.

- `page-library-default-*`: Library, whose editor sheet now reports edits.
- `page-packs-default-*`: Packs, where Use skill starts.
- `page-history-state-transcripts-*`: History on Transcripts, the door a transcripts skill now opens.

Across the whole gallery, 34 other renders differ from the `main` set: Home, the report sheets, and History "from home" and "from meeting". This branch's code is not reachable from those renders. Their differences come from data that changes on each run:
- Home: the synthetic deck's time is the time of the render.
- Report sheets: each run gets a random report ID.
- History "from home" and "from meeting": Snap thumbnails loaded in one run and not the other, so the revealed row sits at a different scroll position.

## Not verified natively

- ⌘Q, and Quit in the menu-bar panel, with a changed prompt open in Library. Checks needed: the question appears, Keep editing leaves the typed text in the sheet, and Discard quits.
- Log out or restart with a changed prompt open. The question is expected to cancel an unattended restart, as the Snap draft already does.
- Packs › Use skill on a transcripts-only skill. Checks needed: History opens on Transcripts with the caption, and the Hand off picker starts on that skill.
- The editor's `onChange` link to the model is one line, and the model checks do not exercise it. If it broke, Quit would silently go back to not asking.
