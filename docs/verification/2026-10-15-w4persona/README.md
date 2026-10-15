# Persona: an unsaved Arrange overlays layout survives leaving the page

Checked **15 October 2026** on branch `claude/persona-arrange-draft`, stacked on the 15 October train `claude/train-1015` at `9ea3acf` (main `edc15df` plus the night's merged streams). Refs [#340](https://github.com/Ship-Work/workbench/issues/340). Synthetic libraries and images only.

Items 1 and 2 of #340 (a truthful empty Show, and Remove group… asking first) were already on the train from `claude/persona-empty-show-remove-group`; see [their record](../2026-10-15-persona2/README.md). This branch is item 3.

## What changed

Arrange overlays kept its draft in view state only. Moving, resizing or hiding overlays, or editing the public group label, and then clicking another sidebar page (or any door that changes page) lost every edit without a word: Persona came back on its ordinary page. Only the page's own Back, Done, Escape and Manage groups asked "Discard the unsaved layout?". The product contract says navigating preserves drafts.

Now the library keeps a memory-only snapshot of the draft (group, the group as it was, overlays, public label and selection) while it differs from its group. The snapshot is not published, so editing never republishes the library, and it is never written to disk, so quitting discards it.

- Returning to Persona reopens **Arrange overlays** with the edits, Revert and Save layout enabled.
- Save layout, Revert, the group-change discard, and **Discard changes** in the existing confirmation clear it. It is written as edits happen, never on disappearing, so Done then Discard cannot keep it again.
- A removed group's draft is dropped, and Persona opens as usual.
- Save still passes the group as it was, so a draft that went stale while away is refused by the existing changed-layout check instead of overwriting.

No control, Option, entry point or copy was added. `docs/personas.md` gains one sentence under Prepare several overlays.

## Checks

| Check | Result | Fails without the change? |
| --- | --- | --- |
| `scripts/test-stage.sh --persona-workspace-only` | 9 tests · 287 assertions · 0 failures | Yes. With the train's two Persona views and only the new library members (so the tests compile), the new workspace test failed 6 assertions: coming back showed the ordinary page, so there was no label field, the typed label was not kept, and the removed group's draft was not dropped. On the train itself neither new test compiles, because `presentationDraft` is absent. |
| `scripts/test-stage.sh --ci` | 339 tests · 6652 assertions · 0 failures; both new tests pass. Three steps skipped as usual: the live menu-bar popover in CI mode, and two shortcut checks because Workbench Preview holds the Option keys on this Mac. | — |
| `scripts/test-stage.sh --persona-one-card-only` | 23 tests · 370 assertions · 0 failures | — |
| `WORKBENCH_LAYOUT_EVIDENCE=… scripts/test-stage.sh --persona-layout-only` | 1 test · 17 assertions · 0 failures; wrote the renders below | — |
| `swift build --disable-sandbox --product LocalVoice` | Built | — |
| `LocalVoice --render-surfaces` | 370 renders. Every Persona render is byte-identical to main's baseline. The run exited 1 at the floating toolbar's "A copied cue appearing under a stationary pointer holds its time" step, light and dark, which reads the real pointer; earlier records today hit the same step, and this branch does not touch the toolbar. | — |
| `python3 scripts/check-surfaces.py` | Surface registry OK: 688 entries | — |

The new tests:

- **PersonaWorkspaceTests · `testChangingPageKeepsAnUnsavedArrangement`** hosts a new workspace `PersonaLibraryView` for each visit, as the sidebar builds one per route. With a kept draft, the visit reopens Arrange overlays: the public group label field shows the edit, and typing into it updates what is kept. The next visit shows the typed label, with the moved and hidden overlays and the same selection. Typing the saved label back leaves nothing kept, so the next visit opens the ordinary page. Nothing is written. After the group is removed, Persona opens as usual and the draft is gone.
- **PersonaSessionTests · `testUnsavedArrangementIsKeptInMemoryUntilItsGroupGoes`** checks the following. A kept draft comes back unchanged on every read and writes nothing. A relaunched library has none. Saving it after another save changed the group throws the changed-layout error and leaves the newer layout on disk. Removing its group drops it and leaves other groups alone.

## Renders

| State | Before | After |
| --- | --- | --- |
| Persona revisited with an unsaved layout: one copy moved, the other hidden, label "Edited set" | [light](persona-arrange-kept-before-light.png) · [dark](persona-arrange-kept-before-dark.png) | [light](persona-arrange-kept-after-light.png) · [dark](persona-arrange-kept-after-dark.png) |
| Persona with nothing kept (surface gallery) | [light](page-personas-default-before-light.png) · [dark](page-personas-default-before-dark.png) | [light](page-personas-default-after-light.png) · [dark](page-personas-default-after-dark.png) |

The kept-layout renders come from the optional offscreen workspace evidence (`--persona-layout-only`), which renders the production `PersonaLibraryView` in workspace mode with the same seeded draft. Before uses the train's two Persona views and shows the ordinary page, where the edits are gone. After shows Arrange overlays with them. The offscreen renderer does not apply the app's accent colour, so buttons there are grey. The surface gallery has no persona saved, so it cannot show Arrange overlays; its Persona renders are unchanged.

## Not verified natively

No app was installed, launched or shown. These native checks are still owed:

- In Persona, choose Arrange overlays…, move an overlay and edit the label without saving, then click Present and come back. Arrange overlays should reopen with both edits.
- From there, Done › Discard changes, then leave and come back. Persona should open on its ordinary page.
- Leave with an unsaved layout, then quit and reopen Workbench. Persona should open on its ordinary page.

Accepted behaviour, as the review noted: the Persona library sheet, where it still opens, shares the library, so its Arrange overlays resumes the same draft, and its Done still asks before discarding it.
