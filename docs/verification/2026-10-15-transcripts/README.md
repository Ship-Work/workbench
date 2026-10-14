# Saved transcripts and follow-ups · 15 October 2026

Branch `claude/transcripts-and-follow-ups`, from `main` at edc15df. Synthetic data only. Refs #332, #280, #281, #338.

## What changed

1. **Review transcript opens long meetings at once** (#332, #280). The review drew the whole saved transcript as one SwiftUI `Text` and rebuilt it on every wording switch. It is now a read-only, selectable text view with non-contiguous layout, with the same font, 3 pt line spacing, 600 pt measure, background and hairline. A wording switch replaces the words in the same view and returns to the top. Capture notes sit above the scrolling words. Return in the focused words is still Done (it beeped before the fix), and Escape already was.
2. **Hand off sends a two-sided meeting once** (#281). A call-plus-microphone meeting's original is its own conversation without the You/Others labels. The prompt now leaves that original out. Cleanups, later edits and separately recognised recordings keep **Original wording**. The frozen selection, the portable original file and the input digest are unchanged.
3. **The handoff review opens on the runner that is set up** (#281). Run with now opens on an enabled runner, preferring the one that ran the newest task, and otherwise on Codex. When no runner is enabled, it opens on the newest task's runner. Coming back from Connections applies the same rule, unless the person has already picked a runner. Nothing is saved and nothing starts on its own.
4. **Home's meeting recap is truthful** (#281).
   - A details suggestion is no longer shown as the meeting's follow-up.
   - A prepared follow-up with no result reads "Follow-up prepared, no result yet".
   - Task files reload when a task's time changes and when Workbench comes back to the front, as History does.
   - `docs/desktop.md` (Your meetings) says so.
5. **Copy confirmations use the shared four-second owner** (#338). Copy build details (Settings and the app menu), Copy permission details and Home's Copy transcript now confirm through the owner Meetings' Copy transcript uses:
   - ✓ Copied shows in space kept for it, is heard once by VoiceOver, and lasts four seconds on its own event.
   - A refused write says so instead of confirming.
   - Copy permission details keeps a stable title. Its registry entry follows the new title.

## Renders

`before/` is `--render-surfaces` from main. `after/` is this branch. File names match, in light and dark.

- `page-history-transcript-review-*`: there is no visible difference. No pixel differs by more than 24 of 255.
- `page-settings-default-*`: **Release notes and downloads** moves right to keep space for ✓ Copied beside **Copy build details**.
- `page-home-state-results-*`: the newest meeting keeps a line under its buttons for ✓ Copied transcript, as Meetings does. Kept beside the buttons, that space truncated all three buttons in the two-column layout, so it moved under them.

The full gallery passed: `SURFACE_GALLERY_OK: 350 renders, 163 entries, 0 flags`.

Some other renders differ from main only because of the clock or timing:
- deck and report timestamps and report IDs;
- in History's from-home and from-meeting states, a thumbnail that finished loading and a scroll offset. Those states render before any code this branch adds to the gallery, and History's view is unchanged.

## Checks run (debug build, this Mac)

| Check | Result | Fails on main? |
|---|---|---|
| `swift build --product LocalVoice` | passes | — |
| `--render-surfaces`, transcript-review pass | passes. 1,200 turns (about 105,000 characters) opened in 0.37 s against 0.39 s for 5 turns. A wording switch took 69 ms and 18 ms, with a copied selection exact and Escape and Return in the focused words closing only the review | Yes. Main has no text view, so the guard fails. With main's view, the same harness timed 2.45 s against 0.38 s, over the baseline + 0.4 s limit. Without the Return fix, Return in the focused words did not close the review |
| `--check-handoff-jobs` | 217 checks pass, 14 of them new | Yes. Main's original rule fails "a two-sided meeting's unlabelled original is not sent a second time". A fixed Codex default fails "the review opens on Claude Code when only Claude Code is enabled". Main's recap rule fails "Home's recap names the meeting's follow-up" |
| `--check-core` | passes. Home journey has 116 checks, 3 of them new | Yes. Reverting each of the exclusion, the wording and the task stamp fails its own check |
| `--check-feedback` | 132 checks pass, 8 of them new | Yes. Confirming before the write, or an expiry that ignores its event, each fails |
| `--check-history-library` | passes | — (unchanged) |
| `--check-transcript-handoff`, `--check-history-journey`, `--check-meetings` | pass | — (unchanged) |
| `python3 scripts/check-surfaces.py` | 682 entries OK | — |
| `scripts/test.sh harnesses` | passes | — |
| Handoff review renders (`WORKBENCH_HANDOFF_GALLERY_OUTPUT`) | still open on Codex | — |

The new functions do not exist on main. The "fails on main" column was therefore confirmed with this branch's checks, after reverting each rule to main's behaviour.

Not run:
- the full `scripts/test.sh`;
- the `package-tests`, `checks` and `stage` phases as wholes;
- the release build.

## Not verified natively

These still need a person on the installed app:

- Reviewing a real one- to two-hour meeting, including scrolling feel.
- VoiceOver reading the review's text area.
- Hearing ✓ Copied announced from Settings, the app menu, Permissions and Home.
- Escape and Return with a real keyboard while the review's words have focus. The check sends key events to the sheet.
- The Connections round trip: open a review with both runners off, switch on Claude Code, come back, and see a Claude Code state. No automated check covers this.
- A follow-up finishing while Home is open in the running app.
