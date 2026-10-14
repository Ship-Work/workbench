# Keyboard doors, Home and the menu-bar panel · 15 October 2026

Branch `claude/keyboard-home-panel`, from `main` at edc15df. Refs #15, #76, #335, #336. All seven changes are Quality: no entry point, setting or capability is added, and one control (Show cue) is removed.

`before/` holds the surface gallery from `main` and `after/` the same gallery from this branch, under the same filenames, in light and dark. Files only in `after/` are new gallery states. Everything shown is synthetic gallery data.

## What changed

| # | Change | Renders |
| --- | --- | --- |
| 1 | Each door that names a shortcut opens Settings › Keyboard with that shortcut selected and idle: the Dictate keycap selects Dictate, Snap & Talk's Change shortcut… selects Snap & Talk, and Draw's failing-shortcut banner selects the first failing Draw key. The list scrolls the selected row into view when the page appears and when a door reveals it, never on a row click. The keycap's tooltip now reads "Opens Settings › Keyboard with this shortcut selected". | `page-shortcuts-default-*` and `page-shortcuts-narrow-*`: Snap was selected below the fold on `main` and is now in view. |
| 2 | Home's first-dictation guide offers "or choose Dictate in the menu bar" when the Dictate shortcut is off or macOS could not register it, instead of "or press Off in any text field" or a key another app holds. With the shortcut off, Dictate settings' Activation hint says it is off and points at the keycap above it, instead of "Press Off…" or "Hold Off…". | None: every gallery fixture keeps the default shortcut on, so the guide still reads "or press ⌥V in any text field" (visible in the Home renders). |
| 3 | The clipboard receipt's Show cue is gone from the panel and Home. Review text and the ⌘V hint stay; an unfinished delivery keeps Copy again and Dismiss. The uncalled `revealHUD`, its two checks, the registry entry and the gallery action are removed. | `panel-clipboard-*` |
| 4 | With speech ready, Home's Current work shows a writing model's download (line, progress, Models…) or its failure (attention symbol, reason, Models…). Cancel and Download again stay in Models. While the first-dictation guide shows over speech that is not ready, the guide's banner keeps the line and Current work stays hidden. | `page-home-state-writing-model-download-*`; new `page-home-state-writing-model-failure-*` |
| 5 | The panel's shortcut editor shows Cancel while it waits for keys and Change once it stops, both in one leading slot, so Turn off keeps its place. | `panel-shortcut-editor-*`; new `panel-shortcut-editor-stopped-*` |
| 6 | The panel's attention line and the shortcut editor's error use the kit's note: an orange triangle beside primary text, instead of orange words. Non-warning lines stay secondary. | `panel-microphone-denied-*` |
| 7 | Home Permissions names wrap whole instead of truncating, and the badge moves under the name when the two do not fit side by side. | `page-home-narrow-*` ("Call au…" before); new `page-home-state-work-mac-narrow-*` |

At the default window on macOS 15 and later, a row whose name and badge no longer fit on one line now shows the badge under a one-line name. Example: Screen & System Audio Recording with "Off".

## Checks run on this branch

| Check | Result | Fails on `main`? |
| --- | --- | --- |
| `swift build --product LocalVoice` (debug) | Pass | n/a |
| `LocalVoice --check-core`, including the new `KeyboardCoachChecks.checkReveal`: after the panel edits Pen, a door to Snap & Talk selects it idle with no suspend; an unknown id changes nothing; a door during recording ends idle with exactly one resume; Draw's failure banner names its first failing action, and nothing when none fails. The doors take their row from the same `AppDelegate.keyboardSelection` helpers the check uses. HomeJourneyChecks adds the shortcut-hint asserts (on, off, failed), the Activation hint while off, and the four writing-model current-work cases. | Pass (HOME_JOURNEY_CHECKS_OK: 121 checks) | Yes. `reveal`, `keyboardSelection`, `shortcutHint`, `activationHint` and `writingModelIsCurrentWork` do not exist on `main`, so the checks do not compile there. On `main` the guide renders "or press Off in any text field" for a disabled shortcut. |
| `LocalVoice --check-feedback` (ClipboardReceiptChecks without the two reveal checks) | Pass (30 checks) | n/a (removal) |
| `LocalVoice --check-refinement` | Pass | n/a |
| Every other debug `--check-*` mode the checks phase runs: read-retirement (and `scripts/test-read-retirement.py --binary`), shortcut-migration, readback, snap-capture, presenter, providers, transcript-handoff, readback-pack, capture-preview, image-workspace, history-library, history-journey, handoff-jobs, subscription-cli, meetings, bug-report and input, all at the final head | Pass | n/a |
| `git grep -n -E 'showCue\|Show cue\|revealHUD' -- Sources docs/surfaces.json` (this README names them, so it is left out) | No matches | Yes: `main` has 10, all in those paths |
| `python3 scripts/check-surfaces.py` (registry hand-edited; Home's second Models… door and the panel's WorkbenchNote rows registered) | Pass, 684 entries | n/a |
| `python3 scripts/test-check-surfaces.py` | Pass | n/a |
| `scripts/test.sh harnesses` | Pass | n/a |
| `LocalVoice --render-surfaces` (full gallery, final head) | 356 renders, 162 entries, 0 flags | See the next five rows |
| `WORKBENCH_HOME_GALLERY_ONLY=1 LocalVoice --render-surfaces` (final head) | 58 renders, 159 entries, 0 flags | See the row for change 7 |
| Gallery check (change 1): after a door reveals Snap, its row frame lies inside the Keyboard list's visible frame, at both window sizes | Pass | Yes. A build with the scroll removed failed: the row was at y 689 below a list that ends at 602. |
| Gallery check (change 1): the Dictate settings sheet's Shortcut keycap closes the sheet and opens Keyboard on Dictate, idle | Pass | No. The sheet already closed on `main`. This confirms it rather than fixing it. |
| Gallery check (change 4): Home shows the download row with Models… while speech is ready and the guide shows, then the failure row | Pass | Yes. A build without the row failed with "Home did not show the writing model's download line…". |
| Gallery check (change 5): the waiting editor shows only Cancel and Turn off, the stopped editor only Change and Turn off, and Turn off moves no more than 8 pt between them | Pass | Yes. `main`'s layout failed: it showed Cancel, Change and Turn off together. |
| Gallery check (change 6): in the denied-microphone panel, the attention line's own row draws an orange symbol and no more than a symbol's width (24 pt) of orange. Other rows are not measured, so a shortcut label that is orange for its own reason cannot fail it. | Pass. A run with Dictate's and Snap's shortcut labels made orange also passed. | Yes. `main`'s row failed with 120 pt of orange. |
| Gallery check (change 7): at the minimum window, no permission name needs more height than its frame or has a word wider than its frame, for the gallery's permissions and a work Mac's | Pass | Yes. `main`'s row failed with "Call audio in 26 × 29 pt". |

Each "fails on `main`" gallery result came from a build of this branch with only that change's view reverted to `main`'s layout. The view was instrumented to report the same frames, so the new assertion had something to read.

Not run: the `package-tests` and `stage` phases, because no test target depends on LocalVoice and no StageKit source changed. Also not run: the release build of the `checks` phase and `scripts/test-snap.sh`.

## Not verified natively

- The real click path of each door in the installed app. Nobody has clicked these in the installed app: the Dictate settings keycap, Snap & Talk's Change shortcut… (sheet and failure row), and Draw's failing-shortcut banner, each landing on Keyboard with the named row selected and in view. The model checks and gallery cover the mapping and the scroll.
- Draw's banner door with a real registration failure. `--check-core` covers which row a failure set names, but the gallery has no StageKit failure fixture, so the banner's click reaching that helper rests on code review.
- A real Ollama download or failure reaching Home. The gallery presents both states synthetically through the same manager properties.
- The shortcut editor's error line (change 6) has no gallery fixture. It rests on code review.
- VoiceOver reading of the new Home row, the panel note and the wrapped permission names.
