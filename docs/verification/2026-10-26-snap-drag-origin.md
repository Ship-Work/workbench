# Snap drag origin and bounded release acceptance

This follow-up starts from main `3e3f8a92567999d444860ad6caf7fb3b8a2764d5`. It retains the initiating mouse-down event and uses its location for both the drag threshold and the initial preview frame. AppKit receives that exact event. Click handling, the four-point threshold, immutable PNG snapshot, file promise and cancellation cleanup stay intact. No temporary diagnostics are included.

Apple’s [drag-session event contract](https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)) was checked on 26 October 2026 against the macOS 26.5 SDK. The parameter specifies the initiating mouse-down event and uses its location for the dragged icon’s offset. The API has been released since macOS 10.7; the file-promise provider requires macOS 10.12, within Workbench’s macOS 14 deployment minimum. This change adds no permission request. It is a conformance correction, not a demonstrated fix for a failed receiver drop.

## Native evidence and limit

The integration owner exercised a temporary signed diagnostic Preview, version 2.8.0 build `20261026123747`, based on `ebe0d0e` with logging only. Its native log showed mouse-down, threshold crossing, a PNG provider, an AppKit drag session with one item, session start and later cancellation with operation zero. No file-promise write was requested. The same app-scoped automation failed to move a synthetic file into a folder within Finder, including after selecting the file. These observations establish a limitation of that acceptance route, not successful receiver delivery or a Snap-specific drag defect. The temporary diagnostic build is not the release candidate.

For 2.8.0, the reviewed S1 policy is `capture-copy-export-and-cancel`. The former `capture-copy-drag-and-cancel` variant is not attested. The public site promotes capture/copy/export; the guide explains drag availability, its unverified delivery and Copy/Export recovery. The final signed, notarized candidate still requires its own source- and artifact-bound native acceptance receipt. Physical Finder or another receiving app’s completed drop remains unverified.

## Focused verification

The existing `scripts/test-snap.sh` runner compiles the production Snap source. Its focused drag checks subclass the native view and intercept only `beginDraggingSession` to examine the original event and preview frame after coalesced pointer movement; they also cover click threshold, cancellation cleanup, failed-image recovery and disabled controls. No OS drag or receiver is simulated as a completed drop.

A debug full-app build unexpectedly invalidated dependency caches and was stopped before completion. It is not recorded as a passing build; required native merge-queue CI and the release owner’s full build remain separate gates.

- `bash scripts/test-snap.sh`: 205 checks passed, including 10 drag-boundary checks and 25 refresh checks.
- The drag regression was compiled against the previous production behavior, with only `final` removed for the test subclass; it failed because AppKit received the dragged event instead of the initiating mouse-down event.
- `python3 scripts/release/test_updates.py`: 42 checks passed.
- `node --test site/tests/*.test.mjs`: 26 checks passed.
- `python3 scripts/check-surfaces.py`: 668 entries passed.
- The regenerated 2400 × 1260 share card was visually inspected; capture/copy/export wording fits without clipping.
