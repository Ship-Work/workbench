# Persona: truthful empty Show, and Remove group… asks first

Checked **15 October 2026** on branch `claude/persona-empty-show-remove-group`, from main `edc15df`. Refs [#340](https://github.com/Ship-Work/workbench/issues/340). Synthetic libraries and images only.

## What changed

1. **Show with nothing to show says why.** When Show selected, the toolbar's Show persona, the panel's Persona row, Option-F or Option-R had no card to show, Persona said "This persona image is missing or unreadable. Import the finished image again." Nothing was missing. Now:
   - with nothing saved: "Nothing to show yet. Add a persona first."
   - with a group prepared that has no members: "This group has no personas yet. Choose its members first." It never names the group, because the panel line can be seen by others.

   Real image failures keep the unreadable wording. The doors, and where each one leads, are unchanged.
2. **Remove group… asks first.** Edit group › Remove group used to remove the group in one click. It is now **Remove group…** and opens a confirmation titled with the group's name, with Cancel and Remove. Its message lists what goes: the member list, plus the saved layout and public label only when the group has them. It says that the group's personas, images and scenes stay. When a card or prepared set from that group is on screen, it also says that what is shown from the group ends. Removal itself, and its notice, are unchanged.

## Renders

The new lines appear only after a door is pressed, so the surface gallery does not show them. For before and after, a throwaway harness rendered the production `PersonaLibraryView` (workspace mode, 900 pt wide) offscreen in both themes. It used main's StageKit sources and then this branch's, after one Show on each disposable library.

| State | Before (main) | After |
| --- | --- | --- |
| Nothing saved, Show pressed | [light](persona-show-nothing-saved-before-light.png) · [dark](persona-show-nothing-saved-before-dark.png) | [light](persona-show-nothing-saved-after-light.png) · [dark](persona-show-nothing-saved-after-dark.png) |
| Empty group prepared, Show pressed | [light](persona-show-empty-group-before-light.png) · [dark](persona-show-empty-group-before-dark.png) | [light](persona-show-empty-group-after-light.png) · [dark](persona-show-empty-group-after-dark.png) |

Before, the line under the empty state blames an image. After, it agrees with the empty state above it. The offscreen harness does not apply the app's accent colour, so buttons there are grey.

The full surface gallery (`LocalVoice --render-surfaces`) after the change gave 350 renders, 163 entries and 0 flags. Every Persona render is byte-identical to main's: the page at default and narrow width, voice refused, the panel's hidden-busy state, My Profile, and the toolbar resting and revealed. [Before light](page-personas-default-before-light.png) · [before dark](page-personas-default-before-dark.png) · [after light](page-personas-default-after-light.png) · [after dark](page-personas-default-after-dark.png). The only gallery differences anywhere were timestamps and random report IDs, on Home, History and report pages that this change does not touch.

The Remove group confirmation is a SwiftUI alert, which the offscreen renderer cannot capture, so it has no render. Its message is covered by the unit test below.

## Checks run

| Check | Result | Fails on main? |
| --- | --- | --- |
| `scripts/test-stage.sh --persona-one-card-only` | 22 tests · 344 assertions · 0 failures | Yes. With main's `Persona.swift`, the two new one-card tests gave 15 failures: every door reported the unreadable-image text. |
| Same runner with main's `PersonaLibraryView.swift` only | 2 failures: the menu item does not ask first, and removal is not in the confirmation | Yes |
| Same runner with main's `Persona.swift` and `PersonaLibraryView.swift` | Does not compile: `groupRemovalMessage` is absent | Yes |
| Full `scripts/test-stage.sh` | 335 tests · 6,579 assertions · 0 failures | n/a (suite) |
| `swift build --disable-sandbox --product LocalVoice` (debug) | Passes | n/a |
| `python3 scripts/check-surfaces.py` | Registry OK, 682 entries, unchanged. Remove group is page content, not an entry point. | n/a |

The new tests:

- `PersonaOneCardTests.testShowingWithNothingSavedSaysSo`. On an empty disposable library, Show, the toolbar and panel toggle, Option-F and Option-R each leave the nothing-saved line as both `notice` and `cardFeedback`. None blames an image, no card shows, and nothing is written to the library folder.
- `PersonaOneCardTests.testShowingAnEmptyGroupSaysSoWithoutItsName`. With an empty group prepared, Show and Option-F give the empty-group line without the group's name. After All saved, Show shows a card.
- `PersonaTests.testRemoveGroupAsksFirstAndSaysWhatGoes` checks the following:
  - A members-only group's message names only the member list.
  - After a saved layout with a public label, the message names all three.
  - "ends" appears only while a card from that group, or a prepared set running from it, is on screen.
  - Asking changes no group, live selection or saved byte.
  - The menu item only asks, and the confirmation's Remove is the one place that removes a group.

The existing missing-image tests, such as `testUnavailableRequestedCardKeepsTheShownCardAndCyclingContinues`, still pass with the unreadable wording.

## Not verified natively

These are owed on an installed Preview:

- On a fresh profile with no saved personas, Option-F shows nothing and leaves "Nothing to show yet. Add a persona first." on the menu panel's Persona line. The toolbar's Show persona opens Persona with the same line under the empty state.
- With an empty group prepared, the same doors say the group has no personas yet, without its name.
- Persona › Edit group › **Remove group…** asks first. Cancel keeps the group. Remove removes it, and the message's layout and "ends" lines match the group.
