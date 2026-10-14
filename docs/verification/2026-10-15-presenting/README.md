# Presenting: quiet successes, one name per Draw key, a selection-only Present chooser — 15 October 2026

Branch `claude/presenting-quiet-and-names`, from `main` at `edc15df`. Source checks and offscreen renders with synthetic data only. Nothing here was installed, and no claim of installed or native acceptance is made.

## What changed

1. **Timer** (Refs #334, #174). A running countdown assigned `timerRunning` and `timerProgress` on every 0.2 s tick, so the stage and every view, menu and status icon watching it refreshed about eleven times a second. They are now assigned only when they change, and the bar follows the shown second, so a countdown publishes about once a second. The Timer window's bar now steps once a second with the digits.
2. **Notices** (Refs #333, #134). StageKit notices carry a tone recorded where they are raised. Successes (board copied or saved, Screenshot closed, My device saved, scene and backdrop saved, scene copy imported or exported, persona removed, group removed, Live Camera ended) no longer become the menu-bar panel's orange problem row with a page door, and a stale success no longer hides a later problem. Pages still show every notice as before. The panel itself is unchanged.
3. **Names** (Refs #76). The ⌥D, ⌥S and ⌥X presenter keys are Draw, Shape and Clear in Settings › Keyboard, the panel's Draw shortcut editor, Home's key popovers and every conflict message. Draw's tool list still says Pen and Rectangle; its Clear item now says Clear. Saved shortcut ids are unchanged.
4. **Present chooser** (Refs #276). Add persona… and Change persona… open a chooser listing every saved card whatever group Persona has prepared. It offers Use in scene, Cancel and Open Persona…, and writes nothing to Persona's selection, group or cards. The embedded full library and its `onChoose` mode are gone.
5. **Board export** (Refs #31). While a board is up, Draw's menus (the toolbar's Draw Tools, the panel's Draw options, the app's Draw menu) offer Copy Board and Save Board PNG…. They have the same admission as other menu actions and recheck it when clicked.

## Renders

| Surface | Before (main `edc15df`) | After |
| --- | --- | --- |
| Settings › Keyboard, light | `before/page-shortcuts-default-light.png` | `after/page-shortcuts-default-light.png` |
| Settings › Keyboard, dark | `before/page-shortcuts-default-dark.png` | `after/page-shortcuts-default-dark.png` |
| Present › Add persona…, light | the whole Persona library sheet (no separate render on main) | `after/present-persona-chooser-light.png` |
| Present › Add persona…, dark | as above | `after/present-persona-chooser-dark.png` |

The Keyboard renders come from `LocalVoice --render-surfaces` (350 renders, 163 entries, 0 flags, including the gallery's Draw's Tools check). The rows read Pen, Clear & return to demo and Rectangle before, and Draw, Clear and Shape after. The other gallery renders that differ from the main set differ only in the synthetic History and report timestamps that the gallery draws from the clock. The chooser renders come from the optional layout evidence in `PersonaWorkspaceTests` (`WORKBENCH_LAYOUT_EVIDENCE=<dir> scripts/test-stage.sh --persona-layout-only`). The fixture has three saved cards, and Persona is preparing a group that holds only the first.

## Checks run

| Check | Result | Fails without the change |
| --- | --- | --- |
| `scripts/test-stage.sh --timer-transport-only` (new: timer publishes once per shown second) | 8 tests, 0 failures | Yes: on main, 12 publications in a frozen second and 3 at the boundary |
| `scripts/test-stage.sh --notice-owners-only` (new: successes stay on their page) | 4 tests, 0 failures | Yes: 5 failures on main; the same 5 when the problem filter in `StageKitController.notice`/`noticePage` is removed |
| `scripts/test-stage.sh --shortcut-settings-only` and `--annotation-menu-only` (key names) | 9 and 6 tests, 0 failures | Yes: 2 and 1 failures on main |
| `python3 scripts/test-check-surfaces.py` (new fixture: an Action's own label beats its tool's) | 59 tests OK | Yes: the fixture fails with main's checker |
| `scripts/test-stage.sh --persona-workspace-only` (new: Present chooser lists every card and only selects) | 7 tests, 0 failures | The test needs the new chooser, so it cannot compile on main. A mutation that lists only the prepared group's cards fails it |
| `scripts/test-stage.sh --annotation-menu-only` (new: open board offers Copy Board and Save Board PNG) | 7 tests, 0 failures | Yes: 10 failures with only the pasteboard seam and no menu items; 1 failure when the click-time recheck is removed |
| `scripts/test-stage.sh --persona-one-card-only` | 19 tests, 0 failures | n/a (regression) |
| `scripts/test-stage.sh --ci` (all of StageKit) | 335 tests, 6,590 assertions, 0 failures (the live menu-bar popover check is skipped in `--ci`, as always) | n/a |
| `python3 scripts/check-surfaces.py` | Registry OK, 686 entries | n/a |
| `scripts/test.sh harnesses` | passed | n/a |
| `swift test --filter ToolbarKitTests` | 115 tests, 2 skipped, 0 failures | n/a |
| `LocalVoice --check-core`, `--check-presenter`, `--check-shortcut-migration` | passed | n/a |
| `swift build --product LocalVoice` (debug) | built | n/a |

## Not verified natively

- Board export from the toolbar's Draw Tools or the panel's Draw options with a full-screen board on a single display, by pointer. Save Board PNG… is never chosen in checks because it opens a real save panel.
- The Present chooser by pointer and keyboard in the installed app, including Return for Use in scene, Escape for Cancel, and Open Persona… landing on the Persona page with the chooser closed.
- The Timer window's bar stepping once a second, and the panel's quieter state after a real Screenshot handoff or board copy.
- `DemoScenes.usePersona`'s "Persona saved as an independent scene copy." was outside this change's list and still reaches the panel as a problem.
