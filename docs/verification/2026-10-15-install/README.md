# Install, update, Report a Problem and Prompts · 15 October 2026

Branch `claude/install-update-report-prompts`, based on `main` at `edc15df`. Refs #287, #296, #159 and #225. These are source checks and gallery renders with synthetic data. Native acceptance is listed at the end and is still owed.

## What changed

1. **Site, guide and README (#287).**
   - The trust strip says *Notarized by Apple*, and no page promises setup in a minute.
   - A first install goes Finder › Go › Home into the Applications folder there. A replacement stays in the same Applications folder, including /Applications.
   - Dictate, Meetings and Snap & Talk narration use the one-time ~450 MB speech download; everything else works without it.
   - Snap & Talk asks for access when you choose *Request capture access*.
   - Updates point to the sidebar's *Update to* and to Settings › General › Updates. The old *Settings → Workbench updates* heading is named as the place to update before 2.5.0.
   - The guide describes the current Home and drops the *In Preview* labels on History review and Resources. Its update help reads quit, move, reopen, retry.
   - The signed feed notes (`site/updates/*.xml`) are untouched.
2. **Update failures (#287).** A copy running from Downloads or a read-only location says to quit, move it into Applications, open that copy and check again. A cancelled installer authorization says *Update not installed* and that nothing changed. Sparkle's raw `SUSparkleErrorDomain error 4007` no longer shows. A connection or certificate cause nested inside Sparkle's download error gets one sentence each. Anything else keeps its description and recovery suggestion.
3. **Sentry 429 (#296).** A 429 whose only rate limit is `attachment` or `attachment_item` reads *Sent · words only* and is not re-sent on its own. Relay queues the words and still answers 429 when it drops any item.
4. **Prompt speed (#159).** Insertion writes 2 Characters first, then each confirmed write doubles the next, up to 256. The doubling stops at 256, so a prompt at the 50,000-Character Library limit lands in 202 writes. Every write is still checked before and after.
5. **Prompt delivery cue (#159).** A refused, unconfirmed or partial insertion, or a paste fallback, now records dictation's delivery cue once the picker has closed. A confirmed insertion or paste stays quiet. *Paste unconfirmed* names the prompt rather than a transcript.
6. **Held Space (#225).** The next action, the capture choices and next persona ignore repeated activation keys, as the launcher and accessory already do.
7. **Report a Problem placement (#296).** A screenshot problem shows under *Add screenshot* and a voice note problem under the voice row. Anything else shows with the form.
8. **Prompts picker (#159).** The category pop-up's right edge sits on the inset shared by the list and the footer button.

## Renders

All renders come from the surface gallery (`LocalVoice --render-surfaces`) with synthetic data. The *before* renders are from `main` at `edc15df`, and the *after* renders are from this branch, in both themes.

- `before-/after-report-screen-off-{light,dark}.png`: the Screen Recording card has moved from below *Record voice note* to directly under *Add screenshot*, above the divider. `report-microphone-off` is pixel-identical before and after.
- `before-/after-picker-host-open-{light,dark}.png`: the *All prompts* pop-up now ends on the *Copy prompt* button's right edge. `measure-picker-popup.py` measures that edge in the picker renders:

  | States | Gap before | Gap after |
  | --- | --- | --- |
  | host-open, grouped and filtered, light and dark | 21.5 pt | 0.0 pt |
  | long-names | 0 pt | 0 pt (pixel-identical) |

- `after-floating-receipt-prompt-stopped-{light,dark}.png`: a new gallery state showing *Delivery stopped · Insertion could not be confirmed.* in the existing two-line cue. `reference-floating-receipt-copied-*` shows the unchanged copied cue for comparison.
- `after-site-download-390.png` and `after-site-guide-setup-390.png`: the built site (`node site/build.mjs`, production 2.5.0 record) in a 390-pixel frame, captured in headless Chrome. The longer install step wraps without horizontal overflow.

Other differences in the full gallery against `main` are timestamps, random report IDs and History thumbnail and scroll timing in surfaces this branch does not touch. The full run produced 352 renders + 2 new, 0 flags.

## Checks run

Each check below passed on this branch. "Fails on main" says how the new assertion was shown to fail without the change.

| Check | Result | Fails on main |
| --- | --- | --- |
| `node --test site/tests/*.test.mjs` | 23 pass | Yes. The new install/update test fails on main's pages ("index (v2.1.0) still says Signed by Apple"). |
| `node site/build.mjs` | builds production v2.5.0 | n/a |
| `LocalVoice --check-updates` | `WORKBENCH_UPDATE_CHECKS_OK` | Yes. Restoring the old `Update check: <description>` line fails the cancelled-authorization case. |
| `LocalVoice --check-bug-report docs/bug-reporting-schema.md` | `BUG_REPORT_CHECK_OK: 7 groups` | Yes. Main's envelope fails the 429 parser case. Main's transport, with the fixed envelope, fails the 429 words-only case. The placement assertions need the new property, so main does not compile them. |
| `LocalVoice --check-floating-toolbar` (prompt insertion) | `PROMPT_INSERTION_CHECKS_OK: 31 checks` | Yes. Main's two-Character plan fails "a 2,000-Character prompt lands exactly in at most 14 confirmed writes". The cue checks need the new mapping, so main does not compile them. The 50,000-Character check traps (exit 133, negative prefix) on this branch's first sizing, which shifted without a cap. |
| `LocalVoice --check-feedback` (clipboard receipts) | `CLIPBOARD_RECEIPT_CHECKS_OK: 33 checks` | Yes. Main's receipt fails "an unconfirmed prompt paste names the prompt, not a transcript". |
| `LocalVoice --check-core` | exit 0 | Includes all of the above that it runs. |
| `swift test --filter ToolbarKitTests` | 116 tests, 0 failures, 2 skipped | Yes. On main the new test fails: one Space plus five repeats acts 6 times instead of once on each button. |
| `scripts/test.sh harnesses` | exit 0 | n/a |
| `python3 scripts/check-surfaces.py` | 682 entries OK | n/a. No entry point was added or renamed. |
| `LocalVoice --render-surfaces` | 354 renders, 0 flags | See Renders. |

## Independent review

One finding, P1, fixed. The first sizing, `min(256, 2 << confirmedWrites)`, kept shifting after the size reached 256. At the 63rd write `2 << 62` is `Int.min`, so any prompt longer than 14,334 Characters stopped Workbench partway through insertion. The exponent now stops at 7. A new check inserts a prompt at the Library's 50,000-Character limit, which traps on the old expression and passes now.

## Integration review

A cross-stream review of the integrated branch found three copy slips, all fixed in `2aaba1d`: the home page now says Snap & Talk narration also needs the speech model; the Prompts contract no longer promises a long prompt in about a second (a 50,000-Character prompt takes 202 checked writes); and the old update heading is named for every version before 2.5.0, not only 2.4.1.

## Not verified natively

- A real translocated launch, a read-only launch and a cancelled installer authorization on a signed build (I1, I2 and U2 acceptance).
- A real Sentry attachment quota answering 429.
- A real prompt insertion into TextEdit, Chrome or an Electron field. That includes how fast the larger confirmed writes go, and the cue appearing at the toolbar.
- A held Space on a live Persona toolbar.
- The site on a physical phone, and after deployment.
