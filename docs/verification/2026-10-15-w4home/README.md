# Home: speech setup and the sample deck cover · 15 October 2026

Branch `claude/home-speech-row-deck-cover`, stacked on the 15 October train (`claude/train-1015` at 9ea3acf). Refs #15, #360. Every change is Quality: no entry point, setting or capability is added, and `docs/surfaces.json` is unchanged.

`before/` holds renders from the train head and `after/` the same renders from this branch, in light and dark. The one exception is `before/page-home-state-task-without-speech-*`: that state is new, so its before is this branch's gallery with the train's banner rule put back (see below). Everything shown is synthetic gallery data.

## What changed

| # | Change | Renders |
| --- | --- | --- |
| 1 | One rule, `HomeJourney.speechSetupIsCurrentWork`, decides both whether speech setup counts as Current work and whether its banner shows: only while speech prepares, or while the banner carries the writing model's line, and never while the guide shows it. On the train the banner showed whenever speech was not ready and the guide was hidden, so someone who skipped the guide and only draws, presents or hands off a task got "Download Parakeet… About 450 MB to download." beside that work. Not now shows only inside the guide, where it hides something; outside it, it re-saved a state already in effect. The banner's look and the writing-model row are unchanged. `docs/desktop.md` § Current work says when speech setup shows there. | `page-home-state-task-without-speech-*` (new), `page-home-state-speech-preparing-*` (pixel-identical to the train) |
| 2 | Your decks' cover keeps its slot's width by 10/16 of it. Home's content is framed to the window's height, so beside the train's taller Your meetings tile and open Permissions the sample cover drew at about 117 × 73 pt in its 190 pt slot, leaving a clickable hole before its text. The newest deck's 140 pt thumbnail is protected the same way. | `page-home-state-results-*`, `page-home-state-work-mac-*` |
| 3 | The first-speech gallery pass renders Dictate at the minimum window while Parakeet downloads ("Downloading Parakeet · 42%" beside Cancel setup) and while a cancelled load finishes (the setup-cancelled sentence on one line). These are the shots the Dictate stream left owed for its progress caption. No view changed. | `speech-dictate-download-*`, `speech-dictate-cancelled-load-*` (new) |

Items already on the train and not changed here: Dictate's progress caption (#15 item 1, with its page check), Dictate's hint alignment, the first dictation's hairline box and the Settings section summaries with their page check (#360 items 1 to 3), all from the Dictate and Home polish stream.

## Checks run on this branch

| Check | Result | Fails on the train? |
| --- | --- | --- |
| `swift build --product LocalVoice` (debug) | Pass | n/a |
| `LocalVoice --check-core` | Pass (HOME_JOURNEY_CHECKS_OK: 134 checks, WORKBENCH_PAGE_CHECKS_OK: 117) | See the next row |
| HomeJourneyChecks on `speechSetupIsCurrentWork`: false for someone who skipped the guide and is drawing (not ready, not preparing, no writing line); true while preparing; true while the writing model counts and the guide is hidden; false whenever the guide shows or speech is ready | Pass | Yes. The helper does not exist on the train; with its body set to the train's banner rule (`!speechReady && !guideShows`), `--check-core` failed with "someone who skipped the guide and is drawing gets no download offer beside it". |
| Gallery: guide skipped, Parakeet not downloaded, a Hand off task running (its own handoff model and folder, the synthetic provider, stopped afterwards): Current work reports the task row and no speech banner | Pass | Yes. With the train's banner condition (`!model.ready && !journey.showsGuide`) put back, the Home gallery failed with "With speech not downloaded and the guide skipped, Home's Current work showed the speech download beside a running task, or no task". That run's render is `before/page-home-state-task-without-speech-*`. |
| Gallery: the speech-preparing state reports the speech banner (with Cancel setup and Models…) | Pass | No: the banner shows there on the train too; this guards the rule. |
| Gallery: in every Home state the cover reports 190 pt (sample) or 140 pt (newest deck, all-allowed) wide, height width/1.6, within 1 pt | Pass | Yes. Without the `fixedSize`, the gallery failed at the first squeezed state: "Home's deck cover in state results is 116.8 × 73.0, not 190.0 points wide at 16:10". The gallery stops at its first failure, so work-mac was not reached; the probe below measures it. |
| `python3 scripts/check-surfaces.py` | Pass, 688 entries | n/a |
| `WORKBENCH_HOME_GALLERY_ONLY=1 LocalVoice --render-surfaces`, train head and branch | Train: 60 renders, 0 flags. Branch: 62 renders, 0 flags | See below |
| `WORKBENCH_SPEECH_GALLERY_ONLY=1 LocalVoice --render-surfaces`, train head and branch | Train: 16 renders, 0 flags. Branch: 20 renders, 0 flags. The 16 shared renders, including the guide's download offer on Home, are pixel-identical | n/a |
| Full `LocalVoice --render-surfaces` on the branch | All renders written; it exited 1 at the floating toolbar's "A copied cue appearing under a stationary pointer holds its time" step, light and dark. That step reads the real pointer, other streams tonight hit it on the train, and this branch does not touch the toolbar | n/a |

### Render probes

A PIL probe of the sample cover's dark teal (2x renders), acceptance evidence rather than a suite test:

- `page-home-state-results` and `page-home-state-work-mac`: train 233 × 146 px light (232 px wide dark); branch 380 × 238 px light (378 px wide dark), the same as `page-home-default` on the train.
- `main` (edc15df) draws these two states with the full cover too; the squeeze arrived with the train's taller Your meetings tile.

### Other Home renders that differ from the train

Every render the Home gallery wrote was compared with the train's. Apart from the changes above:

- The results and work-mac decks tile is 46 pt taller, and nothing below it moves.
- Clock stamps on the synthetic Snap & Talk session, whether the sample's thumbnail had loaded in the narrow window (the placeholder is the same size), and the History list's scroll position differ between any two gallery runs.

## Not verified natively

- The installed app was not opened, and no running Workbench was seen.
- The task-without-speech state is drawn from Home's page view without the sidebar, as the larger-text state is, because Home's window reads the app's own handoff model and a task there would reach History's renders.
- Drawing, presenting, Persona and the timer are not rendered in the gallery; they reach the same Current work rule as the Hand off task.
