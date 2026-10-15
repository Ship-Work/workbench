# Dictate and Home polish · 15 October 2026

Branch `claude/dictate-home-polish`, stacked on the 15 October train (`claude/train-1015` at 2a0d200). Refs #15, #356, #360, #361. Every change is Quality: no entry point, setting or capability is added.

`before/` holds the surface gallery from the train head and `after/` the same gallery from this branch's final head, under the same filenames, in light and dark. Everything shown is synthetic gallery data.

## What changed

| # | Change | Renders |
| --- | --- | --- |
| 1 | Light cleanup, the default text style, keeps acronyms and hyphenated replies. Fillers now match only their spoken forms (um, uh, erm, hmm and drawn-out versions, lowercase or capitalised) standing alone, so "review the ERM framework", "Train an HMM", "The UM campus and UH staff" and "Uh-huh" keep every word. The repeat, opening-Okay and rockmelon rules are unchanged. | None: no gallery state runs cleanup. |
| 2 | While speech prepares, Dictate's caption shows the speech model's own line, such as "Downloading Parakeet · 42%", as Home and the panel do, instead of "Preparing your speech engine". The caption wraps, so the longer setup-cancelled sentence is not clipped. Cancelling, delivering and processing captions are unchanged. | None: no gallery state sets `preparing` on Dictate. |
| 3 | Dictate's empty-transcript hint uses the editor's own origin and line spacing (14 pt padding plus NSTextView's 5 pt line-fragment padding), so it sits where typed or imported text starts. | `page-dictate-state-first-run-*` |
| 4 | Home's first-dictation words sit in a box with the kit's hairline, as every surface container does. The box was the card's own colour, so the words read as a 16 pt misalignment. | `page-home-state-first-result-*` |
| 5 | General, Models and Connections each have a one-line summary in the Settings header, as Keyboard does, so the switcher no longer moves 20 pt when Keyboard is chosen. Models reads "Speech and writing models, all running on this Mac.", reworded after review so it does not echo the Text style card's own lead. The stale comment on `sectionedHeader` now says where summaries sit. | `page-settings-default-*`, `page-shortcuts-default-*` (unchanged), `page-models-default-*`, `page-connections-default-*` |
| 6 | Home's five `onChange(of:perform:)` calls use the zero-parameter form with the same bodies. | None |

## Checks run on this branch

| Check | Result | Fails on the train? |
| --- | --- | --- |
| `swift build --product LocalVoice` (debug) | Pass | n/a |
| `LocalVoice --check-core` | Pass (WORKBENCH_PAGE_CHECKS_OK: 117 checks, CLEANUP_CHECKS_OK: 31, REFINEMENT_CHECKS_OK: 50) | See the next three rows |
| CleanupChecks: "We need to review the ERM framework.", "Train an HMM on the data.", "The UM campus and UH staff met.", "Uh-huh, sounds good." and "Mm-hmm, that works." come back unchanged; "Umm, I'll uh call you. Hmmm, erm, yes." gives "I'll call you. Yes."; the fixture, the filler check and CleanupStyle.light.example still pass | Pass | Yes. With the checks added and the train's rule, `--check-cleanup` failed on the ERM case. The train's filler rule, run alone through NSRegularExpression, turns the five sentences into "…review the framework.", "Train an on the data.", "The campus and staff met.", "-huh, sounds good." and "Mm-that works.". The drawn-out filler case passes on both and guards against losing fillers. |
| WorkbenchPageChecks: every `WorkbenchHome.sections` id has a non-empty, one-line summary, and the failure names the section | Pass | Yes. It failed with "settings has a one-line summary above the switcher". |
| WorkbenchPageChecks: the Dictate caption is the speech model's line while preparing, and today's strings while cancelling, delivering and processing | Pass | Yes. With the caption extracted unchanged, it failed with "Dictate's setup caption shows the speech download's progress". |
| `LocalVoice --check-cleanup` (with Natural) and `--check-refinement` | Pass (LocalRefinementChecks unchanged: 50, 23 and 18 checks) | n/a |
| `git grep "Preparing your speech engine"` in Sources, scripts, Tests and site | No matches. Under docs, only this README quotes the old caption. | Yes: the train has one, in Views.swift |
| Build warnings for WorkbenchHome.swift, with the file recompiled | None | Yes: the train's build warns five times, at lines 236, 237, 628, 629 and 630 |
| `python3 scripts/check-surfaces.py` | Pass, 688 entries | n/a |
| `scripts/test.sh harnesses` | Pass | n/a |
| `LocalVoice --render-surfaces`, train head and this branch | 360 renders, 162 entries, 0 flags each. After the Models summary was reworded, the gallery was rendered again. Every `page-models-*` render changed only in its summary line, the other differences were the run-to-run ones listed below, and every file in `after/` apart from the two Models renders is byte-identical | See below |

### Render probes

A PIL probe, run on both galleries (2x renders, reported in points). It is acceptance evidence, not a suite test.

- **Hint alignment.** The topmost and leftmost ink inside the editor (pixels more than 60 summed RGB from the editor's fill), on `page-dictate-state-first-run` against `page-dictate-default`. Train: the hint's top is 6.0 pt below the typed text's and 1.5 pt to its right, in both themes. Branch: 0.0 pt apart vertically and 0.5 pt horizontally, in both themes. The remaining 0.5 pt is the different first glyphs ("P" and "S"). The hint is one line of ink in both.
- **First result.** A row through the words and a column beside them on `page-home-state-first-result`. Train: the only edge is the card's own hairline (Δ luminance −17 light, +15 dark), and nothing surrounds the words. Branch: a hairline at the box's left edge, top and bottom with the same Δ as the card's own, in both themes.
- **Switcher.** The first row under the title that the segmented control fills. Train: 98 pt for General, Models and Connections, and 118 pt for Keyboard, at both window sizes and in both themes. Branch: 118 pt for all four, at both sizes and in both themes, so each new summary is one line at the narrow window. The same holds with the reworded Models summary.

### Other renders that differ from the train

Every changed render was listed against the train gallery, and each difference was read.

- The first-dictation box also appears in `page-home-state-writing-model-download-*` and `page-home-state-writing-model-failure-*`, which show the guide with words. This is the same change.
- `page-settings-*`, `page-models-*` and `page-connections-*` move down 20 pt under their new summary. This is change 5.
- Other Home, History and problem-report renders differ in a clock time, the History list's scroll position or whether the Sample deck's thumbnail had loaded. These differ between any two gallery runs.

## Not verified natively

- The installed app was not opened. Nothing here was seen on a running Workbench.
- No gallery state shows Dictate while speech prepares or after a setup cancel, so the progress caption and its wrapping are proven only by the page check, which tests the caption function rather than the drawn view. Gallery states belong to another stream tonight; the shot still owed is Dictate at the minimum window with speech preparing, first at "Downloading Parakeet · 42%" and then with the setup-cancelled sentence beside Cancel setup.
- The narrow Dictate render shows a transcript, not the hint, so the hint's single line at the narrow window is inferred: the hint gains 2 pt of width over the train and is one line at the default window.
- Cleanup was checked on synthetic sentences, not on recognised speech.
