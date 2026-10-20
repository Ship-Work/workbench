# Meetings: detection and admission defects from #377 · 20 October 2026

Branch `claude/meetings-detection`, cut from the integrated release candidate (`main`, the 15 October train [#353](https://github.com/Ship-Work/workbench/pull/353) and Meetings [#374](https://github.com/Ship-Work/workbench/pull/374), at `2ff25df`). Refs [#377](https://github.com/Ship-Work/workbench/issues/377), [#280](https://github.com/Ship-Work/workbench/issues/280). Six of #377's verified defects, each a **Quality** change under the Grammar: no new entry point, setting, store or saved-data format. The surface registry is unchanged (688 entries). Old manifests read as before. An independent review of `2ca9826` found no P1 or P2 issue. Its follow-ups are built here, in the section below the checks.

Everything below ran on this Mac against synthetic process metadata, a synthetic capture and temporary folders. No check listed real audio processes, opened a tap or the microphone, played or recorded a sound, or touched an installed app or privacy setting. One check asks the responsible-app lookup about launchd. **Nothing here is a verified two-sided recording**: every catalogue app is still unverified on real hardware. Safari is offered when macOS attributes the WebKit helper to Safari; this is not yet observed on a real Safari call. The acceptance owed is listed at the end.

## The defects and their fixes

| # | Defect | Fix | Owner |
| --- | --- | --- | --- |
| P2 | Safari calls were never offered: Safari's audio and microphone run in WebKit's media process (`com.apple.WebKit.GPU`), which the Safari entry could not match | Safari lists two **hosted helpers**, `com.apple.WebKit.GPU` and `com.apple.WebKit.WebContent`. A helper process counts as Safari's only when macOS holds Safari responsible for it. In that case detection offers "Possible call in Safari", the picker lists Safari once, the automatic-finish activity read counts the helper, and the tap includes it. Every other app's WebKit audio stays the manual "WebKit audio service (shared)", which no longer includes Safari's. Without attribution, Safari is never offered, its entry reads "Safari (calls not supported on this Mac)" and Start refuses, rather than record silence | `MeetingKnownApp.hostedHelpers`, `MeetingAppCatalogue.known(_:responsibleBundleID:)`, `.owner`, `.taps`, `.unsupportedReason`; `MeetingProcessSnapshot.responsibleBundleID`; `MeetingResponsibleApp` |
| P3 | FaceTime, Phone and Safari entries tapped a bundle whose call or media audio plays in a service the tap excluded | FaceTime and Phone list the Mac calling service (`com.apple.avconferenced`) as their **call audio service**. Recording either taps it too, and their activity read counts it, so the guarded finish can see the call end. The service is never merged into an app: it stays its own source and its own "Possible call on this Mac" offer. Safari is covered by the row above. Which processes a recording binds to and taps is one pure rule over Core Audio's metadata, which capture uses and the checks hold with fixtures | `MeetingKnownApp.callAudioServices`, `MeetingTapScope`, `MeetingCoreAudio.tapProcesses`; `MeetingProcessTap.init` and `MeetingSystemCapture.currentApp` |
| P3 | Snooze, Not now and Change source held offers with nothing on screen, and switching detection off and on did not clear a snooze | Turning detection off now forgets the snooze and every Not now cooldown, and an ended snooze is cleared. The detector gives the page one caption line, "Call offers are snoozed until 3:45 pm." (the time in the person's format), nil when detection is off or the snooze has ended | `MeetingDetector.isEnabled`, `.evaluate`, `.snoozeLine` |
| P3 | A running app read as "no longer available" when its representative process changed | Meetings holds the chosen source by one number. The detector now keeps the number a source was first listed with while any of its audio processes is listed, and for 30 seconds after it leaves the list. A helper restarting, gone for several polls, or the main process joining or leaving Core Audio's list keeps the choice. At Start, capture finds the app's current process by bundle. A new app whose process reuses a kept number is listed by the negated number, which no process holds, so a choice never silently becomes another app. An app gone for over 30 seconds is listed afresh, and a failed read forgets nothing | `MeetingDetector.representatives`, `Options.keepAbsentSeconds`, `.availableApps(in:covering:)`, `.read`; `MeetingProcessSource.uptime`; `MeetingTapScope.representative` |
| P3 | "Finish when call audio ends" said only microphone-only recordings finish manually, but any app the catalogue does not know never finishes by itself either | The rule is one function, and the caption is written from it: "After a supported call app, or a call on this Mac, stops using audio, a short countdown lets you keep recording. Silence, Pause and reconnecting audio never finish a session. Microphone-only recordings and other apps or services finish manually." | `MeetingDetector.finishesAutomatically`, `.automaticFinishCaption` |
| P3 | "Free about 500 MB" promised a safe meeting, but two tracks fill 512 MB in about half an hour | A meeting's capture request names its tracks. The start check reads the default output and input devices' nominal rates, falling back to 48 kHz, and requires each track at its rate for two hours, plus the 16 kHz transcription segments and the 192 MB low-disk stop floor beneath them. An admitted meeting therefore reaches that stop only if something else fills the disk. At 48 kHz that is 1.9 GB for both sources and 1.2 GB for one; a 96 kHz output device makes it 2.6 GB. The refusal names the figure: "Two hours with these sources needs about 1.9 GB free". Dictate's live capture passes no tracks and keeps the 512 MB floor and wording it had | `MeetingCaptureRequest.meetingTracks`; `MeetingDiskBudget.tracks`, `.requiredStartBytes`, `.startRefusal`, `.checkStartSpace`; `MeetingCoreAudio.defaultNominalSampleRate` |

The disk arithmetic uses the real writer's format, checked by writing through it. `MeetingTrackRecorder` writes 16-bit mono linear PCM at the rate its device ran at when the track started, and keeps that rate for the whole recording. At 48 kHz that is 96,000 bytes a second per track, or 691.2 MB per track for two hours; at 96 kHz it is 192,000. The segments add 32,000 bytes a second, 230.4 MB, and the floor is 201.3 MB. At 48 kHz, two sources total 1,814,126,592 bytes and one source 1,122,926,592.

## What macOS reports for WebKit and call audio, and how it was read

Read on 20 October 2026 on this Mac (macOS 26.5.1, 25F80) with a scratch Swift program outside the repository. It read Core Audio's process object list (`kAudioHardwarePropertyProcessObjectList`) and, for each object, `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunningInput` and `kAudioProcessPropertyIsRunningOutput`. It also read `NSRunningApplication` metadata, the process's responsible process, and the default devices' `kAudioDevicePropertyNominalSampleRate`. It ran metadata reads only: no tap, aggregate device, IO proc or microphone, and no app was launched or quit. Only the bundle-identifier facts below are recorded.

- **WebKit's media process.** Core Audio lists it as its own process with bundle `com.apple.WebKit.GPU`. It is an XPC service, not a `.app`, with an accessory activation policy. Its command line and environment name no host. Every app that shows web content runs its own copy. `NSRunningApplication` gives it the display name "*host app* Graphics and Media". That is localised, so it is not used. The **responsible process** names the host app's bundle. This was observed for an app on this Mac that hosts WebKit. Safari was not running and was not launched, so Safari's own copy has not been observed.
- **Calls.** Core Audio lists the Mac calling service (`com.apple.avconferenced`) and the telephony service (`com.apple.TelephonyUtilities`) as their own processes, and each is responsible for itself. Neither can be attributed to FaceTime or Phone. The 15 October record found this Mac's two relayed phone calls running through `com.apple.avconferenced`. That is why FaceTime and Phone tap it. The telephony service has no call-audio evidence and is not tapped.
- **The SDK.** The macOS 26.5 SDK's `AudioHardware.h` gives a process object only its PID, bundle ID, devices and running state, with no responsible process. `CATapDescription.h` adds `bundleIDs` and `processRestoreEnabled` in macOS 26. Those would tap by bundle and restore a restarted process. They are not adopted: the deployment minimum is macOS 14 (taps from 14.2), and a WebKit bundle tap would take every WebKit app's audio.

**The responsible process is read through a libSystem export without a public header**, `responsibility_get_pid_responsible_for_pid`. On this macOS it is exported by `libquarantine`, which libSystem re-exports. It is resolved by name from libSystem's own handle, so the result does not depend on what else is loaded; the process-wide search is used only if that handle is unavailable. It is read only for the two WebKit helper bundles. It returns the responsible process ID, or -1 on error. launchd and daemons are responsible for themselves, so they attribute to no app. The lookup fails closed: if it is missing or fails, no helper is attributed, and Safari behaves as the first table row describes. Nothing is ever attributed wrongly. The decision is recorded in [docs/desktop.md, Decisions](../../desktop.md#decisions), with how it differs from AltTab's private-SPI precedent and what would make us revisit it. It supersedes the 15 October row in section 5 of [the research record](../../research/2026-10-15-meetings-category.md).

## Checks

New checks are in `Sources/LocalVoice/MeetingDetectionChecks.swift`, which runs inside `--check-meetings`. They use fixtures, apart from the lookup check. Four existing checks recorded the old PID-change behaviour: "a changed process is offered by its new PID", "known audio helpers remain available …" and "a browser without its main process is offered by its audio helper", both by the helper's number, and "a changed process replaces the panel". They now hold the new rule. The panel-replacement check produces its changed offer from a different app.

**Fails on the old code.** The base sources were put back with a variant of these checks that compiles against them, then built and run. Every row failed. The same variant passes on this branch, except the two Safari rows, which need the new attribution field:

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

The caption check and the snooze-line check reference new members, so they cannot compile on the old code. The old caption is a literal in the view, and the old snooze state had no line at all. The review follow-ups were proved by mutation on the final source. With the 30-second keep set to zero, "a helper gone for ten seconds, across several polls, comes back as the chosen source" fails. With the device rate ignored, the writer-format and 96 kHz budget checks fail. With the unsupported rule disabled, "only an app whose calls play in shared helpers depends on attribution" fails.

| Command (on the branch head) | Result |
| --- | --- |
| `swift build --disable-sandbox` | Build complete |
| `.build/debug/LocalVoice --check-meetings` | Meeting checks passed (440; 382 at the base), removal 34, live voice 27, live voice experience 27 |
| `.build/debug/LocalVoice --check-core` | Passed |
| `bash scripts/test.sh harnesses` | Passed. Surface registry OK (688 entries), capture continuity 14 |

The first five commits each build and pass `--check-meetings` on their own: 400, 409, 418, 421 and 427 meeting checks.

## Review follow-up (independent review of `2ca9826`)

- **Decision on record.** The attribution is kept and recorded in `docs/desktop.md`'s Decisions table, beside the AltTab precedent. The research row it replaces is marked superseded, with its text kept.
- **Deterministic lookup, and an honest entry without it.** The symbol is resolved from libSystem's handle. When it cannot be resolved, Safari's entry says its calls are not supported on this Mac, Safari is never offered, and Start refuses with "Safari calls can't be recorded on this Mac: …" rather than recording silence.
- **A kept number survives a gap.** Before, a source listed only through a helper was forgotten at the first read without it. It now keeps its number for 30 seconds of absence, measured on the source's monotonic clock (`MeetingProcessSource.uptime`, which checks drive).
- **The budget travels with the request.** `MeetingCaptureRequest.meetingTracks` replaces reading the manifest inside the disk check. Dictate passes none.
- **The budget follows the devices.** It is sized from the default output and input devices' nominal rates, with a 96 kHz check.
- **Cheap checks.** The lookup resolves on this macOS, and launchd attributes to no app. The tap's process choice, `MeetingTapScope`, is pure and tested with fixtures: Safari's own and Mail's WebKit helpers, the calling service, a stale number, Workbench's own process.

## Changes other streams make

**Made here in a file another stream owns:** `MeetingModel.swift` gains one argument in `begin`'s `MeetingCaptureRequest(…)`: `meetingTracks: MeetingDiskBudget.tracks(app: app != nil, microphone: microphone)`.

**Left for integration**, two view lines:

1. **Finish caption** (`MeetingWorkspaceView.swift`, `MeetingFinishSettings`): replace the caption literal with `Text(MeetingDetector.automaticFinishCaption)`, keeping its modifiers.
2. **Snooze line**: `MeetingModel.swift` needs `var offerSnoozeLine: String? { detector.snoozeLine() }`. The view needs `if let line = model.offerSnoozeLine { Text(line).font(.caption).foregroundStyle(.secondary) }`, for example under the caption in `MeetingDetectionSettings`, beside the switch that clears it. The model publishes when Snooze is chosen and when detection is switched. Nothing publishes when a snooze ends, so the line can stay until the next redraw unless the view refreshes it, for example with a once-a-minute `TimelineView`.

## Not changed, and why

- **Firefox, the telephony service and other shared helpers.** These have no evidence of call audio and are not attributed or tapped.
- **A helper that restarts mid-recording.** Its new process is outside a running tap until the route recovery rebuilds the tap. That is unchanged here; macOS 26's `processRestoreEnabled` is the later route (see above).
- **Dictate's refusal wording.** Dictate still says "record a meeting safely. Free about 500 MB". That wording belongs to the Dictate owner.

## Native acceptance owed

On the installed Preview, with real calls:

- A Safari call (for example Google Meet in Safari): the offer reads "Possible call in Safari", Start records the other side, and Finish when call audio ends finishes after the call. Until this is run, Safari is only offered when macOS attributes the WebKit helper to Safari; this is not yet observed on a real Safari call.
- Mail or another WebKit app playing sound during that call is not offered as Safari.
- A FaceTime call and a relayed iPhone call, each started from the FaceTime or Phone entry: the other side is recorded, and the call ending starts the countdown.
- Turning Detect Meetings & Calls off and on during a snooze, and, once the view adopts it, the snooze line.
- A browser helper restarting while the app is chosen.
- A start on a disk with less than the stated space, including with a 96 kHz output device.
