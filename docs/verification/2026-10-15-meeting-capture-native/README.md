# Meetings: the real capture pipeline, checked by an agent · 15 October 2026

Refs [#280](https://github.com/Ship-Work/workbench/issues/280). Based on the release-train head `59753fc`. The reasoning and the decisions are in [the meetings category record](../../research/2026-10-15-meetings-category.md).

## What the check does

`LocalVoice --check-meeting-capture-native NEW_FOLDER [--self-end]` is the first check that runs Meetings the way the app runs it: a scratch player app with its own bundle identifier plays a synthetic two-voice fixture (74 words, 26.7 s, macOS's Daniel and Samantha voices), the production `MeetingSystemProcessSource` lists it, the production `MeetingSystemCapture` taps it through Core Audio, the cached Parakeet v2 model recognises it live through the real `RecognitionEngine`, and the real `MeetingModel` starts, finishes and commits it. The receipt records first sound, first live words, the saved manifest, the live journal and the word error rate against the fixture. With `--self-end` the player quits instead, so the meeting ends itself through source loss, which is the path #343 added.

It needs no human, microphone or call app; it downloads nothing, requests no permission and never reads saved work. It needs the Xcode command line tools (`xcrun swiftc` compiles the thirty-line player) and `/usr/bin/say`.

## Results on this Mac

MacBook Air, Apple M5, macOS 26.5.1 (25F80). Receipts beside this file.

| Run | Identity | Result |
| --- | --- | --- |
| Debug binary (`swift build`) | unbundled | Fixture 26.7 s; player compiled in 0.7 s and listed by the picker through LaunchServices; admission "Ready to record"; Start reached recording in 0.29 s; Parakeet from cache in 19.4 s. The tap then delivered silence for 10 s: the honest permission result for an unbundled binary. |
| Signed scratch Preview 2.5.0 (20261015062021), source `59753fc`, Developer ID team GHVAAH9P5Z, run with `open -n -W -a … --args` | `com.ethdawg.workbench.preview` | Same mechanics, faster (model ready in 0.3 s, player listed in 0.6 s, recording in 0.06 s). The tap again delivered silence for 10 s. |

**What the silence means.** A process tap that macOS refuses is created without error and delivers zeros; the code has relied on that since `CallAudioEvidence` (it writes Allowed only from the first real sound). So the second run says that **System Audio Recording is not currently allowed for Workbench Preview on this Mac**, or that its first-use prompt was never answered. Neither edition has an Allowed record in its own permission memory. The installed Stable edition did capture real sound on 6 October (a QuickTime test with live words), so Stable's identity has the permission and Preview's does not. Nothing in this session changed a privacy setting; that switch is the person's.

The check now records, from Core Audio's own metadata, whether the player was producing output while the tap was silent, so a silent run is attributed to the permission rather than to a player that never played.

## What is still owed

- Allow Workbench Preview under System Settings › Privacy & Security › Screen & System Audio Recording (macOS 26 offers "System Audio Recording Only"), then rerun from the signed Preview with a new folder. Expected: first live words within a few seconds of the first sound, a committed meeting of about 27 s or more, a complete live journal, and a word error rate well under 0.30 on these voices.
- The same run with `--self-end`.
- A real call: FaceTime or Phone to the maintainer's own iPhone, a WhatsApp or Slack call, or Google Meet in Chrome, with the microphone included; headphones switched mid-call; Pause and Resume; Finish; Copy transcript pasted into the next task. That is M1 in [the foundation brief](../../mac-foundation.md); this check does not replace it, it makes the pipeline provable before it.

## Source checks on this branch

- `swift build --product LocalVoice` (debug): passes.
- `LocalVoice --check-meeting-capture-native` from the debug binary: the mechanics up to the tap pass and the permission result is reported, as recorded above.
- The check is not part of `scripts/test.sh`: it needs the signed app's permission, a compiler and about forty seconds of audio playback on the Mac that runs it.
