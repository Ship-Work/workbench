# Persona: an unsaved Arrange overlays layout survives leaving the page

Checked **15 October 2026** on branch `claude/persona-arrange-draft`, stacked on the 15 October train `claude/train-1015` at `9ea3acf` (main `edc15df` plus the night's merged streams). Refs [#340](https://github.com/Ship-Work/workbench/issues/340). Synthetic libraries and images only.

Items 1 and 2 of #340 (a truthful empty Show, and Remove group… asking first) were already on the train from `claude/persona-empty-show-remove-group`; see [their record](../2026-10-15-persona2/README.md). This branch is item 3.

## What changed

Arrange overlays kept its draft in view state only. Moving, resizing or hiding overlays, or editing the public group label, and then clicking another sidebar page (or any door that changes page) lost every edit without a word: Persona came back on its ordinary page. Only the page's own Back, Done, Escape and Manage groups asked "Discard the unsaved layout?". The product contract says navigating preserves drafts.

Now the library keeps a memory-only snapshot of the draft (group, the group as it was, overlays, public label and selection) while it differs from its group. The snapshot is not published, so editing never republishes the library, and it is never written to disk, so quitting discards it.

- Persona still opens on its own page, with its camera, shown and live panels (the integration review below changed this from reopening Arrange overlays). Choosing **Arrange overlays…** brings the edits back, with Revert and Save layout enabled.
- Save layout, Revert, the group-change discard, and **Discard changes** in the existing confirmation clear it. It is written as edits happen, never on disappearing, so Done then Discard cannot keep it again.
- A removed group's draft is dropped. When its group's members changed while it waited, it follows them if its overlays are all still members and the saved layout is unchanged; otherwise it is dropped with a notice.
- Save still passes the group as it was, so a draft that went stale while away is refused by the existing changed-layout check instead of overwriting.

No control, Option, entry point or copy was added; the integration review below adds one notice. `docs/personas.md` gains one sentence under Prepare several overlays.

## Checks

| Check | Result | Fails without the change? |
| --- | --- | --- |
| `scripts/test-stage.sh --persona-workspace-only` | 9 tests · 288 assertions · 0 failures | Yes. With the train's two Persona views and only the new library members (so the tests compile), the new workspace test failed 6 assertions: coming back showed the ordinary page, so there was no label field, the typed label was not kept, and the removed group's draft was not dropped. With only Discard changes' clear removed, it failed 1 assertion ("Discard changes discards the kept layout too"). On the train itself neither new test compiles, because `presentationDraft` is absent. |
| `scripts/test-stage.sh --ci` | 339 tests · 6653 assertions · 0 failures; both new tests pass. Three steps skipped as usual: the live menu-bar popover in CI mode, and two shortcut checks because Workbench Preview holds the Option keys on this Mac. | — |
| `scripts/test-stage.sh --persona-one-card-only` | 23 tests · 370 assertions · 0 failures | — |
| `WORKBENCH_LAYOUT_EVIDENCE=… scripts/test-stage.sh --persona-layout-only` | 1 test · 17 assertions · 0 failures; wrote the renders below | — |
| `swift build --disable-sandbox --product LocalVoice` | Built at the final head | — |
| `LocalVoice --render-surfaces` | Run at `6f7878a`; the later commits change only tests and this record. 370 renders. Every Persona render is byte-identical to main's baseline. The run exited 1 at the floating toolbar's "A copied cue appearing under a stationary pointer holds its time" step, light and dark, which reads the real pointer; earlier records today hit the same step, and this branch does not touch the toolbar. | — |
| `python3 scripts/check-surfaces.py` | Surface registry OK: 688 entries | — |

The new tests:

- **PersonaWorkspaceTests · `testChangingPageKeepsAnUnsavedArrangement`** hosts a new workspace `PersonaLibraryView` for each visit, as the sidebar builds one per route. With a kept draft, the visit reopens Arrange overlays: the public group label field shows the edit, and typing into it updates what is kept. The next visit shows the typed label, with the moved and hidden overlays and the same selection. Typing the saved label back leaves nothing kept, so the next visit opens the ordinary page. Nothing is written. After the group is removed, Persona opens as usual and the draft is gone. The Discard question cannot be answered offscreen, so the test also reads the Discard changes action and checks that it clears the kept layout.
- **PersonaSessionTests · `testUnsavedArrangementIsKeptInMemoryUntilItsGroupGoes`** checks the following. A kept draft comes back unchanged on every read and writes nothing. A relaunched library has none. Saving it after another save changed the group throws the changed-layout error and leaves the newer layout on disk. Removing its group drops it and leaves other groups alone.

## Renders

| State | Before | After |
| --- | --- | --- |
| Persona revisited with an unsaved layout: one copy moved, the other hidden, label "Edited set" | [light](persona-arrange-kept-before-light.png) · [dark](persona-arrange-kept-before-dark.png) | [light](persona-arrange-kept-after-light.png) · [dark](persona-arrange-kept-after-dark.png) |
| Persona with nothing kept (surface gallery) | [light](page-personas-default-before-light.png) · [dark](page-personas-default-before-dark.png) | [light](page-personas-default-after-light.png) · [dark](page-personas-default-after-dark.png) |

The kept-layout renders come from the optional offscreen workspace evidence (`--persona-layout-only`), which renders the production `PersonaLibraryView` in workspace mode with the same seeded draft. Before uses the train's two Persona views and shows the ordinary page, where the edits are gone. After shows Arrange overlays with them. The offscreen renderer does not apply the app's accent colour, so buttons there are grey. The surface gallery has no persona saved, so it cannot show Arrange overlays; its Persona renders are unchanged.

## Not verified natively

No app was installed, launched or shown. These native checks are still owed:

- In Persona, choose Arrange overlays…, move an overlay and edit the label without saving, then click Present and come back. Persona should open on its own page; Arrange overlays… should then show both edits.
- From there, Done › Discard changes, then leave and come back. Persona should open on its ordinary page.
- Leave with an unsaved layout, then quit and reopen Workbench. Persona should open on its ordinary page.

- With an unsaved layout waiting, add a persona pack from Library › Packs, and press the toolbar's Show persona with an empty group active. Both should now open Persona's ordinary page, and Arrange overlays… should still bring the layout back.

Accepted behaviour, as the review noted: the Persona library sheet, where it still opens, shares the library, so its Arrange overlays resumes the same draft, and its Done still asks before discarding it.

## Integration review · 15 October 2026

The cross-PR review of the 15 October train (at `59753fc`) raised two findings on this branch. Both are fixed here, on top of the train.

- **P3-6: an unsaved layout took over every visit.** Persona reopened Arrange overlays on every visit while a layout waited, hiding the camera, shown and live panels until it was saved, reverted or discarded. A panel notice's Open Persona… then landed where that notice's recovery was hidden, against the product contract's rule that a door opens the page showing the problem with its recovery. Now a visit always opens Persona's own page. The layout waits in memory and comes back only when the person chooses Arrange overlays….
- **P3-5: a kept layout was never checked against its group's members.** Members can change on other pages: Draw's and Present's libraries add to the active group, and removing a persona strips it from groups and saved layouts. A kept layout then came back with overlays for a removed persona, and Save refused it with "…changed during the demo" though no demo ran; reopening offered the same layout again. Now, when Arrange overlays… brings a layout back, the library compares the group as it was with the group now. If only the members changed, the saved layout is unchanged and every kept overlay is still a member, the layout follows the new members, so Save works. Otherwise it is dropped, nothing is written, and the Persona page and panel say "The unsaved overlay layout was discarded because its group's members changed." A saved layout that changed with the same members (a live session's Save layout) still comes back so Revert or Discard can resolve it, as before.

| Check | Result | Fails without the change? |
| --- | --- | --- |
| `scripts/test-stage.sh --persona-workspace-only` | 10 tests · 304 assertions · 0 failures | Yes. With `PersonaLibraryView.swift` and `Persona.swift` as on the train at `59753fc` (tests unchanged): 10 tests · 295 assertions · 4 failures. The workspace test fails "An unsaved layout leaves Persona on its own page, where a notice's recovery is" and "The next visit opens on Persona's own page too". |
| `scripts/test-stage.sh --persona-one-card-only` | 23 tests · 370 assertions · 0 failures | — |
| `scripts/test-stage.sh` (full StageKit suite) | 342 tests · 6,750 assertions · 0 failures; 2 skipped because Workbench Preview holds the Option keys on this Mac (CI checks them) | Yes, in the same run at `59753fc`: the members test fails "Reordered members carry the kept layout along", then Save layout refuses the stale layout with the changed-layout error. |
| `swift build --disable-sandbox --product LocalVoice` | Built | — |
| `python3 scripts/check-surfaces.py` | Surface registry OK: 689 entries | — |
| `WORKBENCH_LAYOUT_EVIDENCE=… scripts/test-stage.sh --persona-layout-only` | 1 test · 19 assertions · 0 failures; wrote the renders below | — |

Renders, light and dark, with the same seeded layout (one copy moved, the other hidden, label "Edited set"):

- A visit with the layout waiting is byte-identical to the ordinary page in [light](persona-arrange-kept-before-light.png) and [dark](persona-arrange-kept-before-dark.png). The earlier "after" renders above show the reopening this review removed.
- Arrange overlays… then brings it back: [light](persona-arrange-kept-review-open-light.png) · [dark](persona-arrange-kept-review-open-dark.png). It shows the hidden second overlay, the edited label, and Revert and Save layout enabled. It is rendered on its own, without the page's header, because the page cannot be opened on Arrange overlays offscreen.

The tests:

- **PersonaWorkspaceTests · `testChangingPageKeepsAnUnsavedArrangement`** now checks that each visit with a layout waiting opens Persona's own page and leaves the layout kept, and that the Arrange overlays view brings it back with the typed label, the moved and hidden overlays and the same selection.
- **PersonaSessionTests · `testKeptArrangementFollowsItsGroupsMembersOrIsDropped`** reorders a group's members under a kept layout: it follows them and Save layout keeps it. Removing a member only the kept layout uses drops it with the notice, as a problem, and writes nothing. Removing a persona its overlays show drops it too.

Native checks owed for these fixes, on installed Preview:

- With an unsaved layout waiting, open Persona from the sidebar and from a panel notice's Open Persona…. Both should show Persona's own page with its camera, shown and live panels; Arrange overlays… should then bring the layout back.
- With an unsaved layout waiting, use Members… to remove a persona that one of its overlays shows, then choose Arrange overlays…. The notice should say the layout was discarded, and Arrange overlays should open on a saved layout.
