# Meetings: detection and admission defects from #377 · 20 October 2026

Branch `claude/meetings-detection`, cut from the integrated release candidate (`main`, the 15 October train [#353](https://github.com/Ship-Work/workbench/pull/353) and Meetings [#374](https://github.com/Ship-Work/workbench/pull/374), at `2ff25df`). Refs [#377](https://github.com/Ship-Work/workbench/issues/377), [#280](https://github.com/Ship-Work/workbench/issues/280). Six of #377's verified defects, each a **Quality** change under the Grammar: no new entry point, setting, store or saved-data format. The surface registry is unchanged (688 entries). Old manifests read as before.

Everything below ran on this Mac against synthetic process metadata, a synthetic capture and temporary folders. No check enumerated a real audio process, opened a tap or the microphone, played or recorded a sound, or touched an installed app or privacy setting. **Nothing here is a verified two-sided recording**: every catalogue app is still unverified on real hardware, and the acceptance owed is listed at the end.

## The defects and their fixes

| # | Defect | Fix | Owner |
| --- | --- | --- | --- |
| P2 | Safari calls were never offered: Safari's audio and microphone run in WebKit's media process (`com.apple.WebKit.GPU`), which the Safari entry could not match | Safari lists two **hosted helpers**, `com.apple.WebKit.GPU` and `com.apple.WebKit.WebContent`. A helper process belongs to Safari only when macOS holds Safari responsible for it. Detection then offers "Possible call in Safari", the picker lists Safari once, the automatic-finish activity read counts the helper, and the tap includes it. Every other app's WebKit audio stays the manual "WebKit audio service (shared)", which no longer includes Safari's | `MeetingKnownApp.hostedHelpers`, `MeetingAppCatalogue.known(_:responsibleBundleID:)`, `.owner`, `.taps`; `MeetingProcessSnapshot.responsibleBundleID`; `MeetingResponsibleApp`; `MeetingCoreAudio.owner(of:)`, `.isTapped` |
| P3 | FaceTime, Phone and Safari entries tapped a bundle whose call or media audio plays in a service the tap excluded | FaceTime and Phone list the Mac calling service (`com.apple.avconferenced`) as their **call audio service**: recording either taps it too, and their activity read counts it, so the guarded finish can see the call end. The service is never merged into an app. It stays its own source and its own "Possible call on this Mac" offer. Safari is covered by the row above | `MeetingKnownApp.callAudioServices`, `MeetingAppCatalogue.taps`; `MeetingProcessTap.init` and `MeetingSystemCapture.currentApp` (the only change in `MeetingAudio.swift`: three predicates now ask the catalogue's ownership) |
| P3 | Snooze, Not now and Change source held offers with nothing on screen, and switching detection off and on did not clear a snooze | Turning detection off now forgets the snooze and every Not now cooldown, and an ended snooze is cleared. The detector gives the page one caption line, "Call offers are snoozed until 3:45 pm." (the time in the person's format), nil when detection is off or the snooze has ended | `MeetingDetector.isEnabled`, `.evaluate`, `.snoozeLine` |
| P3 | A running app read as "no longer available" when its representative process changed | Meetings holds the chosen source by one number. The detector now keeps the number a source was first listed with while any of its audio processes is listed, so a helper restarting, or the main process joining or leaving Core Audio's list, keeps the choice. Capture already resolves the app's current processes by bundle. A new app whose process reuses a kept number is listed by the negated number, which no process holds, so a choice never silently becomes another app. An app that quits still reads as gone, and a failed read forgets nothing | `MeetingDetector.representatives`, `.availableApps(in:covering:)`, `.read` |
| P3 | "Finish when call audio ends" said only microphone-only recordings finish manually, but any app the catalogue does not know never finishes by itself either | The rule is one function, and the caption is written from it: "After a supported call app, or a call on this Mac, stops using audio, a short countdown lets you keep recording. Silence, Pause and reconnecting audio never finish a session. Microphone-only recordings and other apps or services finish manually." | `MeetingDetector.finishesAutomatically`, `.automaticFinishCaption` |
| P3 | "Free about 500 MB" promised a safe meeting, but two tracks fill 512 MB in about half an hour | A meeting session needs, for two hours, one track per source its manifest names, plus the 16 kHz transcription segments and the 192 MB low-disk stop floor beneath them. An admitted meeting therefore reaches that stop only if something else fills the disk. The figures are 1.9 GB for both sources and 1.2 GB for one. The refusal names the figure: "Two hours with these sources needs about 1.9 GB free". Dictate's live capture runs the same check from its own folder and keeps the 512 MB floor and wording it had | `MeetingDiskBudget.meetingStartBytes`, `.meetingTracks(at:)`, `.startRefusal`, `.checkStartSpace` |

The disk arithmetic uses the real writer's format. `MeetingTrackRecorder.open` writes 16-bit mono linear PCM at the source's rate, and Mac audio runs at 48 kHz unless a device asks otherwise. That is 96,000 bytes a second per track, or 691.2 MB per track for two hours. The segments add 32,000 bytes a second, 230.4 MB, and the floor is 201.3 MB. Two sources total 1,814,126,592 bytes and one source 1,122,926,592. A device running faster than 48 kHz uses more, and the stop floor still keeps what was recorded.

## What macOS reports for WebKit and call audio, and how it was read

Read on 20 October 2026 on this Mac (macOS 26.5.1, 25F80) with a scratch Swift program outside the repository. It read Core Audio's process object list (`kAudioHardwarePropertyProcessObjectList`) and, for each object, `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunningInput` and `kAudioProcessPropertyIsRunningOutput`. It also read `NSRunningApplication` metadata and the process's responsible process. It ran metadata reads only: no tap, aggregate device, IO proc or microphone, and no app was launched or quit. Only the bundle-identifier facts below are recorded.

- **WebKit's media process.** Core Audio lists it as its own process with bundle `com.apple.WebKit.GPU`. It is an XPC service, not a `.app`, with an accessory activation policy. Its command line and environment name no host. Every app that shows web content runs its own copy. `NSRunningApplication` gives it the display name "*host app* Graphics and Media". That is localised, so it is not used. The **responsible process** names the host app's bundle. This was observed for an app on this Mac that hosts WebKit. Safari was not running and was not launched, so Safari's own copy has not been observed.
- **Calls.** Core Audio lists the Mac calling service (`com.apple.avconferenced`) and the telephony service (`com.apple.TelephonyUtilities`) as their own processes, and each is responsible for itself. Neither can be attributed to FaceTime or Phone. The 15 October record found this Mac's two relayed phone calls running through `com.apple.avconferenced`. That is why FaceTime and Phone tap it. The telephony service has no call-audio evidence and is not tapped.
- **The SDK.** The macOS 26.5 SDK's `AudioHardware.h` gives a process object only its PID, bundle ID, devices and running state, with no responsible process. `CATapDescription.h` adds `bundleIDs` and `processRestoreEnabled` in macOS 26. Those would tap by bundle and restore a restarted process. They are not adopted: the deployment minimum is macOS 14 (taps from 14.2), and a WebKit bundle tap would take every WebKit app's audio.

**The responsible process is read through a libSystem function without a public header** (`responsibility_get_pid_responsible_for_pid`). It returns the process macOS holds responsible for a helper, the app the helper works for, and it is looked up by name at run time, only for the two WebKit helper bundles. If the function is missing, no helper is attributed. Safari is then not offered from WebKit audio, and the shared WebKit service stays a manual choice, exactly as before. Nothing is ever attributed wrongly. The alternative, the localised display name, was rejected as unreliable. The other honest option was a generic "WebKit audio (shared)" offer, the 15 October decision in section 5 of [the research record](../../research/2026-10-15-meetings-category.md). This branch supersedes that decision row. If a maintainer prefers no private function, the fallback is to drop `MeetingResponsibleApp`'s lookup: Safari then reads exactly as before.

## Checks

New checks are in `Sources/LocalVoice/MeetingDetectionChecks.swift`, which runs inside `--check-meetings`. They use fixtures only. Four existing checks recorded the old PID-change behaviour ("offered by its new PID", "known audio helpers remain available …" by the helper's number, "a changed process replaces the panel"). They now hold the new rule, and the panel-replacement check produces its changed offer from a different app.

**Fails on the old code.** The base sources were put back with a variant of these checks that compiles against them, then built and run. Every row failed, and the same variant passes on this branch except the two Safari rows, which need the new attribution field:

| Check (old-code variant) | Base `2ff25df` |
| --- | --- |
| A call in Safari's WebKit media process is offered as Safari | FAIL |
| Safari's activity counts its WebKit media process | FAIL |
| A FaceTime recording sees its call's audio in the calling service | FAIL |
| A Phone recording sees its call's audio in the calling service | FAIL |
| Turning detection off and on clears a snooze | FAIL |
| Turning detection off and on clears Not now | FAIL |
| Chrome's main process joining keeps the chosen source | FAIL |
| Chrome's audio helper restarting keeps the chosen source | FAIL ("The selected audio app is no longer available. …") |
| Starting needs room for a two-hour two-track meeting above the stop floor | FAIL (536,870,912 B admitted; 1,814,126,592 B needed) |

The caption check and the snooze-line check reference new members, so they cannot compile on the old code. The old caption is a literal in the view, and the old snooze state had no line at all.

| Command (on the branch head) | Result |
| --- | --- |
| `swift build --disable-sandbox` | Build complete |
| `.build/debug/LocalVoice --check-meetings` | Meeting checks passed (427; 382 at the base), removal 34, live voice 27, live voice experience 27 |
| `.build/debug/LocalVoice --check-core` | Passed |
| `bash scripts/test.sh harnesses` | Passed. Surface registry OK (688 entries), capture continuity 14 |

Each commit on the branch builds and passes `--check-meetings` on its own: 400, 409, 418, 421 and 427 meeting checks.

## Changes other streams make

Two of these fixes reach the page only through files this stream does not own:

1. **Finish caption** (`MeetingWorkspaceView.swift`, `MeetingFinishSettings`): replace the caption literal with `Text(MeetingDetector.automaticFinishCaption)`, keeping its modifiers.
2. **Snooze line**: `MeetingModel.swift` needs `var offerSnoozeLine: String? { detector.snoozeLine() }`. The view needs `if let line = model.offerSnoozeLine { Text(line).font(.caption).foregroundStyle(.secondary) }`, for example under the caption in `MeetingDetectionSettings`, beside the switch that clears it. The model publishes when Snooze is chosen and when detection is switched. Nothing publishes when a snooze ends, so the line can stay until the next redraw unless the view refreshes it, for example with a once-a-minute `TimelineView`.

## Not changed, and why

- **Firefox, the telephony service and other shared helpers.** These have no evidence of call audio and are not attributed or tapped.
- **A helper that restarts mid-recording.** Its new process is outside a running tap until the route recovery rebuilds the tap. That is unchanged here; macOS 26's `processRestoreEnabled` is the later route (see above).
- **Dictate's refusal wording.** Dictate still says "record a meeting safely. Free about 500 MB". That wording belongs to the Dictate owner.

## Native acceptance owed

On the installed Preview, with real calls:

- A Safari call (for example Google Meet in Safari): the offer reads "Possible call in Safari", Start records the other side, and Finish when call audio ends finishes after the call.
- Mail or another WebKit app playing sound during that call is not offered as Safari.
- A FaceTime call and a relayed iPhone call, each started from the FaceTime or Phone entry: the other side is recorded, and the call ending starts the countdown.
- Turning Detect Meetings & Calls off and on during a snooze, and, once the view adopts it, the snooze line.
- A browser helper restarting while the app is chosen.
- A start on a disk with less than the stated space.
