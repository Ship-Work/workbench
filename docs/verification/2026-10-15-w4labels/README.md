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

Debug build on this Mac, re-run on the final head after the review's README corrections.

The first assertions for each item fail on the train, as named in the table. The others guard against over-correcting and hold with the train's behaviour too: a call that falls back to the microphone or returns to its own audio stays a Call, a Call chosen in Save as stays a Call, follow-ups and edited tasks keep the skill's name, and the same details task reuses its job.

| Check | Result | Fails without the change |
| --- | --- | --- |
| `--check-meetings` | 292 Meeting checks, plus removal 34, live voice 21 and live voice experience 19 | Yes. With the train's `MeetingModel.swift`: "another app's offer after a call offer is saved as a Meeting". "Choosing another app's audio after a call offer is saved as a Meeting" fails there too. The lifecycle save no longer resets the purpose by hand, so its `selectAudioSource(789)` must restore Meeting. |
| `--check-handoff-jobs` | 223 checks | Yes. Without the store's title: "an assistant's details suggestion is titled Suggest details". With the store's title but without the model's fallback: "a details suggestion saved as Prepare follow-up shows as Suggest details; a real follow-up keeps its name". |
| `--check-history-library` | 87 History and 63 History page checks | Not new |
| `--check-history-journey` | 20 steps | Not new |
| `--check-transcript-handoff` | 129 checks, runner 11 | Not new |
| `--check-core`, `--check-readback` | exit 0; Readback order 44 | Not new |
| `scripts/test.sh harnesses` | exit 0: capture persistence 202, live dictation 40, node tests fail 0 | Not new |
| `python3 scripts/check-surfaces.py` | 688 entries OK | Not new |
| debug build | no warnings from the changed files | Not applicable |

## Renders

`before/` holds `--render-surfaces` from main and `after/` holds this branch. The file names match, in light and dark. Both the History Results state (the running bar and task card headers, now read through the model) and the Meetings Kept-for-later state are byte-identical to main. The gallery's tasks are follow-ups, which keep their name.

Every render from this branch was compared with a render of the train head. The 34 that differ show only clock times and random report IDs, plus History's reveal scroll stopping at a different offset. Both runs reported the same toolbar step, "A copied cue appearing under a stationary pointer holds its time", so it does not come from this branch.

## Not verified

- No gallery state holds a details suggestion or a call followed by another app, so neither new label appears in a render. The checks cover both.
- Nothing was checked natively: there was no installed Preview, real call offer or assistant run.

## Known limits

- History search still matches a task's saved title. A details suggestion saved before this change is also found by "Prepare follow-up", although its card now reads Suggest details. "Suggest details" finds it too, through its task's words.
- After a call offer, choosing FaceTime or Mac telephony service in Audio source saves as a Meeting, the same as choosing either without an offer. Only the Mac calling service counts as a call service, and the catalogue keeps its capture scope separate from FaceTime and Phone. Save as changes it back in one click.
- After a call, a microphone-only in-room recording in the same app run still saves as a Call unless Save as is changed, as on the train. This keeps a call that falls back to the microphone a Call.
