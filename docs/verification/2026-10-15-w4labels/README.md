# Meetings and Hand off labels · 15 October 2026

Branch `claude/meeting-handoff-labels`, stacked on the 15 October train (`claude/train-1015` at 9ea3acf). Synthetic data only. Refs #280, #281.

## What changed

1. **A call on this Mac no longer makes later meetings Calls** (#280). Starting from a "Possible call on this Mac" offer set Save as to Call, and nothing set it back. The next Zoom or Teams meeting in the same app run was saved, listed and handed off as a Call, and a History search for "meeting" missed it. `MeetingModel` now remembers which calling-service source chose Call:
   - another app's offer, or choosing another app in Audio source, returns to Meeting;
   - Microphone only, including the recovery offered when a call's app audio fails, keeps Call;
   - a Call the person chose in Save as stays a Call.

   `docs/product-spec.md` states the rule.
2. **An assistant's details suggestion is titled Suggest details** (#281). History › Details… › Suggest details › Ask an assistant… made a task titled "Prepare follow-up", the follow-up skill's name. Its History card, VoiceOver label and both running bars said so, and a meeting with a real follow-up showed two identical cards. The task is now titled **Suggest details** when it is exactly the details task on one transcript. That is the same test that offers Review suggested details…. A follow-up, or a task the person edited, keeps the skill's name. History's card, its earlier-task label, its action labels and both running bars read the title through the model, so a details suggestion saved earlier under the old name also shows as Suggest details. Saved receipts are not rewritten. The fingerprint and the assistant-facing manifest are unchanged.

## Checks

Each new assertion was confirmed to fail without its change.

| Check | Result | Fails without the change |
| --- | --- | --- |
| `--check-meetings` | passed (292) | Yes. With the train's `MeetingModel.swift`: "another app's offer after a call offer is saved as a Meeting". The lifecycle save no longer resets the purpose by hand, so its `selectAudioSource(789)` must restore Meeting. |
| `--check-handoff-jobs` | 223 checks | Yes. Without the store's title: "an assistant's details suggestion is titled Suggest details". With the store's title but without the model's fallback: "a details suggestion saved as Prepare follow-up shows as Suggest details; a real follow-up keeps its name". |
| `--check-history-library`, `--check-history-journey`, `--check-transcript-handoff`, `--check-core` | passed | Not new |
| `scripts/test.sh harnesses` | passed | Not new |
| `python3 scripts/check-surfaces.py` | 688 entries OK | Not new |
| debug build | no warnings from the changed files | Not applicable |

## Renders

`before/` holds `--render-surfaces` from main and `after/` holds this branch. The file names match, in light and dark. Both the History Results state (the running bar and task card headers, now read through the model) and the Meetings Kept-for-later state are byte-identical to main. The gallery's tasks are follow-ups, which keep their name.

Every render from this branch was compared with a render of the train head. The 34 that differ show only clock times and random report IDs, plus History's reveal scroll stopping at a different offset. Both runs reported the same toolbar step, "A copied cue appearing under a stationary pointer holds its time", so it does not come from this branch.

## Not verified

- No gallery state holds a details suggestion or a call followed by another app, so neither new label appears in a render. The checks cover both.
- Nothing was checked natively: there was no installed Preview, real call offer or assistant run.
- History search still matches a task's saved title. A details suggestion saved before this change is found by "Prepare follow-up", not "Suggest details".
