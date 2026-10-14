# CI and build hygiene · 15 October 2026

Branch `claude/ci-and-warnings`, from the 15 October train (`claude/train-1015` at 2a0d200, on `main` at edc15df). Synthetic data only. Refs #361, #225.

## What changed

1. **Surface gallery has CI headroom** (#361). Its `timeout-minutes` goes from 25 to 30. Over the last 200 CI runs (6 to 14 October) it took a median of 15.6 minutes and at most 19.9, which was 80% of the old limit. Release checks (at most 17.4) and Toolbar gallery and package (at most 17.2) keep 25. The workflow comment now gives the measured length of a run, about 16 minutes, instead of the 13 measured on 5 October. The renderer's own per-page deadlines still stop a hung page well before the job limit.
2. **The opt-in key-window Tab check asserts the row it draws** (#225). Retiring Read renamed the loop's row to Snap but left the assertion on Read, so `TOOLBAR_KEY_WINDOW_TESTS=1` always compared nil. The offscreen check's comment had the same stale name. StageKit's `--ci` skip line now names `bash scripts/test-stage.sh` (no arguments), which runs the skipped popover regression; `scripts/test.zsh` no longer exists.
3. **Nine build warnings are gone** (#361). Each fix is the one the compiler names and keeps behaviour: Meetings' completion handler uses the two-parameter `onChange`; the toolbar reads `revealsResult` in `body` beside `state`, not inside the Sendable geometry transform; `TextDelivery.copiedMessage` is a `nonisolated` constant; the presenter check's weak reference is a `weak let`; three tests drop a no-op `try` or `await` or discard an unused result; the readback resources harness drops an unused flag.

Warnings left on purpose:
- `PackCredentials.swift:36`, a deliberate deprecation.
- `PhoneLink.swift:591` and `:592`. The wake and activate observers keep their main-queue `Task` hop, because changing it changes Present's timing.
- `HandoffManualChecks.swift:218`. The handoff review render keeps its run-loop wait.
- `WorkbenchHome.swift:236`, `:237`, `:628`, `:629` and `:630`, which a separate change clears.

## Renders

`before/` is `--render-surfaces` from `main`. `after/` is this branch. File names match, in light and dark: Meetings' default, completed and live states, and the revealed toolbar in Dictate, Snap, Draw and Snap & Talk.

They are byte-identical. The whole after gallery (`SURFACE_GALLERY_OK: 360 renders, 162 entries, 0 flags`) is pixel-identical to the same render from the train head, all 360. It is also identical to main's 350, plus the train's 10 new renders.

## Checks run (debug build unless stated, this Mac)

| Check | Result | Fails before? |
|---|---|---|
| Read-only script over the last 200 CI runs' job steps (`gh api`, GET only): each native job's worst passing step span against its `timeout-minutes` parsed from `ci.yml`, and the comment's minutes against the median longest job | passes. Package tests 7.0/20 = 0.35, Harnesses and StageKit 13.1/20 = 0.65, Release checks 17.4/25 = 0.70, Toolbar gallery and package 17.2/25 = 0.69, Surface gallery 19.9/30 = 0.66. The comment says about 16; the longest job's median over 41 full runs is 16.1 | Yes, on main's `ci.yml`: Surface gallery 19.9/25 = 0.80, and the comment says 13 |
| `python3 scripts/test-ci-scope.py` | 32 tests pass | — |
| `ci.yml` parses as YAML | passes | — |
| Every `runs["…"]` key the key-window check asserts is a row its loop draws | passes | Yes, on main and the train head: `Read, no accessory` is never set |
| `grep -rn 'test\.zsh' Tests scripts Sources` | finds nothing | Yes: the StageKit skip line |
| `swift test --filter 'ToolbarKeyboardTraversalTests\|PackStoreTests'` | 20 tests, 0 failures | — |
| Clean `swift build --build-tests` | warns only at the sites kept above | Yes, the train head's clean build also warns at the six sites fixed in package sources and tests, 16 sites in all |
| Clean `swift build -c release` | warns only at the sites kept above | not run on the train head |
| `bash scripts/test-stage.sh --ci` | 337 tests, 0 failures. Two skips: Workbench Preview held the global shortcuts, as CONTRIBUTING describes. It prints the new skip line. It warns only at `PhoneLink.swift:591` and `:592` | Yes, the train head's runner also warns at `PersonaCameraTests.swift:1277` and `PhoneOwnerTests.swift:331` |
| `python3 scripts/test-readback-resources.py` | 9 checks pass and the generated check has no warning | Yes, the train head warns about the unused `optionalMissing` |
| `bash scripts/test.sh harnesses` | passes | — |
| `LocalVoice --check-core`, `--check-floating-toolbar`, `--check-presenter`, `--check-handoff-jobs` | all pass (`HANDOFF_JOBS_CHECKS_OK: 218 checks`, `PRESENTER_CHECKS_OK: 27`, `BROWSER_PAUSE_CHECKS_OK: 43`, `WORKBENCH_CONTROL_CHECKS_OK: 221`) | — |
| `LocalVoice --render-surfaces` | 360 renders, 0 flags. All 360 are pixel-identical to the train head's | — |

## Not verified

- I did not run the opt-in `TOOLBAR_KEY_WINDOW_TESTS=1 swift test --filter ToolbarKeyWindowTraversalTests`. It takes the keyboard and makes a panel key, and other sessions were running window checks on this Mac. The static check above shows the assertion now names a row the loop draws.
- No app was launched. The toolbar's size report is covered by `--check-floating-toolbar` and the identical renders, not by a hand check on screen.
- The new Surface gallery limit takes effect from the next native CI run.
