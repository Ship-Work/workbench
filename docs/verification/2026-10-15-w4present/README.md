# Presenting polish: the Timer keeps the display awake, Present's footer, error lines and panel Options names

Branch `claude/presenting-polish`, stacked on the 15 October release train (`claude/train-1015`, on top of `main` at `edc15df`). The checks below ran on the branch's final source. Synthetic data only: the timer checks use a test clock and counted keep-awake hooks, and the surface gallery uses its isolated home. No installed app, real power assertion, saved scene, clipboard or privacy setting was used.

## What changed

1. **The Timer keeps the display awake while a countdown is on screen** (#174). A break countdown went dark on stock display-sleep settings before Time is up. The timer now holds one `idleDisplaySleepDisabled` activity, separate from Present's, while its window shows a running countdown and for five minutes after it finishes. Pause, Hide, Stop, closing the window and quitting release it. A hidden or idle timer never holds one, and a refused start takes none. The hold is decided from the current state each time, so a stale re-evaluation cannot end a newer countdown's hold. One re-evaluation ends Time is up's five minutes; Hide, Stop and quitting drop it. The product contract's Timer paragraph says the same.
2. **Present's footer names the entire-display route** (#276). Both footer lines now read "Share the Workbench presentation window in your call; to include Draw, the Timer or a floating persona, share your entire display.", then "Command-/ focuses the floating toolbar." or "Esc ends it.". It uses Draw's own term and does not claim a window share never includes them. Phone presenting's During paragraph says these are separate windows and that a persona placed in the scene is part of the window. The guide's phone-share line is unchanged, since this branch does not deploy the site.
3. **Error lines are primary words beside an orange triangle** (#335). The photo backdrop sheet's notice, the logo browser's errors and Present's missing-logo line use `PersonaNote`, keeping text selection where it was. The founder card's failure in Settings uses `WorkbenchNote`, and its success lines stay secondary text. `scripts/check-attention-text.py`, in the harnesses phase, fails any worded view in Voice or StageKit whose own style is orange, red or `Workbench.attention`. It has three named exceptions: Finish meeting's recording red; the panel's conflicting shortcut keys, a fixed-size key glyph whose conflict is said on hover and in the editor; and the hand line, until hand authoring's retirement takes it.
4. **The panel's Options menus name their tool for VoiceOver** (#335). `NativeControlMenu` takes an optional accessibility name, and each row passes "Dictate options" through "Timer options". The visible Options ⌄ and Home's Timer menu are unchanged.

`WorkbenchNote` in the founder card made `scripts/check-surfaces.py` report the panel's two `WorkbenchNote` status rows as stale. Offers are collected first and each view is collected once, so the founder card claimed the shared note. The check now still collects, for the panel, a view an offer claimed. The derived entries for the train and for this branch are identical to the train's 688, so the registry is unchanged.

## Renders

- `before/page-present-state-no-phone-{light,dark}.png` come from `main`; `after/` from this branch's gallery. The footer wraps to two caption lines on the trailing side, with nothing truncated. Present and Options keep their size, and the preview is the same size. The gallery draws Present with a scene only at the default window size.
- `stagekit-error-lines-{light,dark}.png` come from a scratch offscreen render that was not committed. It shows the three StageKit messages in the old caption styles (`before/`) and as `PersonaNote` (`after/`), at 520 points wide. The gallery has no state for these lines or for the founder card's failure.
- `panel-idle-{light,dark}.png` and `timer-window-{light,dark}.png` are byte-identical to `main`'s, so they are not copied here.

## Checks

| Check | Result | Fails without this change? |
| --- | --- | --- |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passed | |
| `bash scripts/test-stage.sh --timer-transport-only` | 9 tests, 205 assertions, 0 failures | Yes. With the train's `AppCoordinator.swift`, the new test does not compile: `beginTimerKeepAwake` and `endTimerKeepAwake` do not exist. |
| `bash scripts/test.sh stage` (`test-stage.sh --ci`) | 338 tests, 6,686 assertions, 0 failures. The global-shortcut and live popover checks were skipped, because Workbench Preview held the shortcuts on this Mac. | |
| `python3 scripts/check-attention-text.py` | Passed, with 3 named exceptions | Yes. On the train's sources it fails the four lines: `FounderIntroduction.swift:92`, `DemoScenesView.swift:506`, `LogoBrowser.swift:81` and `StageKitController.swift:641`. With `.foregroundStyle(.red)` put back on the logo browser's error, split across two lines, it fails again, naming `LogoBrowser.swift:82`. |
| `python3 scripts/test-check-surfaces.py` | 60 tests passed | Yes. The new case fails against the train's `check-surfaces.py`: the panel's status row from a view an offer embeds is missing. |
| `python3 scripts/check-surfaces.py` | 688 entries OK | |
| `bash scripts/test.sh harnesses` | Passed (exit 0) | |
| `.build/debug/LocalVoice --render-surfaces` | Every render written, including the new check: "The panel's Options menus read Dictate options, Snap options, Snap & Talk options, Draw options, Present options, Persona options, Timer options for VoiceOver, each still showing Options ⌄." The run exits 1 on two toolbar steps outside this change, "A copied cue appearing under a stationary pointer holds its time", light and dark. It did so on both runs. That step reads the real pointer, and other branches recorded the same failure on this Mac tonight, at heads without their changes too. | Yes. With the train's `WorkbenchQuickPanel.swift`, the new check fails: the seven menus read "Options". |

How the timer test covers the bounds: idle and a refused start take nothing. Start takes one hold, and the countdown's updates take no second one. Pause releases it and Resume takes it again. Hide releases it, a hidden running countdown holds nothing, and Show timer takes it again. At Time is up the hold stays. An early re-evaluation keeps it for the time left. Hide at Time is up drops the hold and the re-evaluation, and showing it again within the five minutes takes it again. Five minutes after Time is up it is released, and a later Show does not take it again, while the finished timer itself stays until it is stopped. Restart takes it, and Stop timer releases it. Closing the timer's window releases it, and Show timer after that takes it again. Quitting with a countdown on screen leaves nothing held. Holds never exceed one, and the counter checks that only the token handed out is ended.

## Not verified natively

On a signed Preview, by the integration owner or Ethan:

- **Timer, on a Mac whose display sleeps** (on battery, or with a short Display sleep setting). This Mac never sleeps its display, so it can show neither the defect nor the fix. Start a 3 minute timer and leave the Mac untouched: the display should stay on through Time is up, then sleep about five minutes later. Pause, Hide timer or Stop timer should each let it sleep at its usual time. `pmset -g assertions` should list "Showing a Workbench break timer" only while the window shows a running countdown, and for the five minutes after.
- **Present's footer** at larger text sizes, and what Teams and Zoom actually carry in a window share. That receiver check stays with #276.
- **Error lines in light mode**: Present › Scene options with a missing logo, the logo browser on a blocked link, the photo backdrop sheet with an unreadable photo, and Settings' founder card when no email app is set up.
- **VoiceOver**: the rotor's buttons in the menu-bar panel should list each tool's options by name. The gallery proves the accessibility label, not VoiceOver's speech.
