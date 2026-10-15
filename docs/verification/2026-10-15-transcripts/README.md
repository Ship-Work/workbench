# Saved transcripts and follow-ups · 15 October 2026

Branch `claude/transcripts-and-follow-ups`, from `main` at edc15df. Synthetic data only. Refs #332, #280, #281, #338.

## What changed

1. **Review transcript opens long meetings at once** (#332, #280). The review drew the whole saved transcript as one SwiftUI `Text` and rebuilt it on every wording switch. It is now a read-only, selectable text view with non-contiguous layout, with the same font, 3 pt line spacing, 600 pt measure, background and hairline. A wording switch replaces the words in the same view and returns to the top. Capture notes sit above the scrolling words; past about six lines they scroll in their own space. Return in the focused words is still Done, with or without Caps Lock (it beeped before the fix), and Escape already was.
2. **Hand off sends a two-sided meeting once** (#281). A call-plus-microphone meeting's original is its own conversation without the You/Others labels. The prompt now leaves that original out. Cleanups, later edits and separately recognised recordings keep **Original wording**. The frozen selection, the portable original file and the input digest are unchanged. The comparison walks the words in place, so typing in the review stays light on a long call: about 0.16 ms for 1,200 turns in an optimised build, against about 10 ms for splitting and rejoining.
3. **The handoff review opens on the runner that is set up** (#281). Run with now opens on an enabled runner, preferring the one that ran the newest task, and otherwise on Codex. When no runner is enabled, it opens on the newest task's runner. Coming back from Connections applies the same rule, unless the person has already picked a runner. Nothing is saved and nothing starts on its own.
4. **Home's meeting recap is truthful** (#281).
   - A details suggestion is no longer shown as the meeting's follow-up.
   - A prepared follow-up with no result reads "Follow-up prepared, no result yet".
   - Task files reload when a task's time changes and when Workbench comes back to the front, as History does.
   - `docs/desktop.md` (Your meetings) says so.
5. **Copy confirmations use the shared four-second owner** (#338). Copy build details (Settings and the app menu), Copy permission details and Home's Copy transcript now confirm through the owner Meetings' Copy transcript uses:
   - ✓ Copied shows in space kept for it, is heard once by VoiceOver, and lasts four seconds on its own event.
   - A refused write says so instead of confirming, and is heard, so the app menu's door is not silent. Settings › General drops a reason left from before it appeared.
   - Copy permission details keeps a stable title. Its registry entry follows the new title.

## Renders

`before/` is `--render-surfaces` from main. `after/` is this branch. File names match, in light and dark.

- `page-history-transcript-review-*`: there is no visible difference. No pixel differs by more than 24 of 255.
- `page-history-transcript-review-notes-*` (after only): a meeting saved with a capture note for every gap, 32 of them. The notes scroll in about six lines above the words, and the words, Copy, Export and Review recording keep their places.
- `page-settings-default-*`: **Release notes and downloads** moves right to keep space for ✓ Copied beside **Copy build details**.
- `page-home-state-results-*`: the newest meeting keeps a line under its buttons for ✓ Copied transcript, as Meetings does. Kept beside the buttons, that space truncated all three buttons in the two-column layout, so it moved under them.

The full gallery passed on the final code: `SURFACE_GALLERY_OK: 352 renders, 163 entries, 0 flags`, 350 before the integration review's two notes renders. Its transcript-review, Settings and Home results renders are pixel-identical to `after/`.

Some other renders differ from main only because of the clock or timing:
- deck and report timestamps and report IDs;
- in History's from-home and from-meeting states, a thumbnail that finished loading and a scroll offset. Those states render before any code this branch adds to the gallery, and History's view is unchanged.

## Checks run (debug build, this Mac)

| Check | Result | Fails on main? |
|---|---|---|
| `swift build --product LocalVoice` | passes | — |
| `--render-surfaces`, transcript-review pass | passes. 1,200 turns (about 105,000 characters) opened in 368–386 ms against 378–388 ms for 5 turns, over two runs in both themes. The slower wording switch took 37–40 ms against 9–17 ms for 5 turns. A copied selection is exact, and Escape, Return, and Return with Caps Lock on in the focused words close only the review | Yes. Main has no text view, so the guard fails. With main's view, the same harness timed 2.45 s against 0.38 s, over the baseline + 1.0 s limit (widened from 0.4 s after a shared CI runner took 0.33 s to switch the fixed view). Without the Return fix, Return in the focused words did not close the review. Without the Caps Lock part of it, Return with Caps Lock on did not |
| `--check-handoff-jobs` | 218 checks pass, 15 of them new | Yes. Main's original rule fails "a two-sided meeting's unlabelled original is not sent a second time". A fixed Codex default fails "the review opens on Claude Code when only Claude Code is enabled". Main's recap rule fails "Home's recap names the meeting's follow-up". Reading a label at any word, not only where a paragraph opens, fails the turn-shapes check |
| `--check-core` | passes. Home journey has 116 checks, 3 of them new | Yes. Reverting each of the exclusion, the wording and the task stamp fails its own check |
| `--check-feedback` | 132 checks pass, 8 of them new | Yes. Confirming before the write, an expiry that ignores its event, or a refusal that is not heard each fails |
| `--check-history-library` | passes | — (unchanged) |
| `--check-transcript-handoff`, `--check-history-journey`, `--check-meetings` | pass | — (unchanged) |
| `python3 scripts/check-surfaces.py` | 682 entries OK | — |
| `scripts/test.sh harnesses` | passes | — |
| Handoff review renders (`WORKBENCH_HANDOFF_GALLERY_OUTPUT`) | still open on Codex | — |

The new functions do not exist on main. The "fails on main" column was therefore confirmed with this branch's checks, after reverting each rule to main's behaviour. The review fixes were confirmed the same way, each mutation failing its own check.

## Independent review

An independent review read the whole diff and reran the checks. Its verdict was ship, with five P3 findings. All five are fixed:

1. Return with Caps Lock on fell through to the text view's beep. Caps Lock no longer counts as a held modifier, and the gallery closes the five-turn review with Return under Caps Lock.
2. The Original-wording comparison split and rejoined a long call on every keystroke, about 10 ms each time. It now walks the words in place, about 0.16 ms. A table of turn shapes pins where a label is read.
3. The wording switch had an absolute 150 ms limit, a flake risk on a slow runner. It is now timed against a five-turn switch in the same run, within 300 ms, as opening is. The same-view check stays.
4. A refused Copy build details from the app menu was silent, and its reason waited in Settings. The reason is now heard, and Settings › General drops one left from before it appeared.
5. The copy check had taken the shortcut check's comment. It now sits after that check, under its own heading.

Not run:
- the full `scripts/test.sh`;
- the `package-tests`, `checks` and `stage` phases as wholes;
- the release build.

## Integration review

A cross-stream review of tonight's integrated branch found one P3 here, and it is fixed:

1. Capture notes pinned above the words took their full height. History keeps up to 32 notes, and a meeting saved before #343 folded its gap notes has one note for every gap. At the sheet's 640 × 560 size, 32 gap notes made the notes 960 pt tall. The words' box grew to 976 pt, the words got no height, and the title and the Copy and Export row were clipped. The notes now take their own height up to 96 pt, about six lines, and scroll past that. The gallery opens a meeting with one note and one with 32 through Home's door. The words' box must stay where it is without notes, one note must take under 40 pt and not scroll, and 32 notes must take at most 96 pt and scroll. The notes as this branch first pinned them fail the 32-note check. A first attempt with `ViewThatFits` failed the one-note check, because one note took the full 96 pt. Reviews without notes render byte for byte as before.

## Not verified natively

These still need a person on the installed app:

- Reviewing a real one- to two-hour meeting, including scrolling feel.
- VoiceOver reading the review's text area.
- Hearing ✓ Copied announced from Settings, the app menu, Permissions and Home. A refused copy cannot be forced on a real Mac, so its announcement is checked in source only.
- Escape and Return, also with Caps Lock on, with a real keyboard while the review's words have focus. The check sends key events to the sheet.
- The Connections round trip: open a review with both runners off, switch on Claude Code, come back, and see a Claude Code state. No automated check covers this.
- A follow-up finishing while Home is open in the running app.
- A review of a meeting with many capture notes: that the sheet opens without a visible jump as the notes measure themselves, and that the notes scroll with a trackpad and with VoiceOver.
