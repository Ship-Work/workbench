# Core utilities and independent Meetings

Checked 26 October 2026 against main `fcd64fe`. [#401](https://github.com/Ship-Work/workbench/issues/401) owns implementation; [#7](https://github.com/Ship-Work/workbench/issues/7) owns release acceptance. This records the decision and platform constraints, not completed native acceptance.

The chosen scope is four familiar tools, an explicit experimental switch and an independent meeting recorder. Existing capture, recognition, image, presentation and recovery owners are reused. A broad rewrite, new Workbench identity, account requirement and App Store adaptation were declined: none is needed to simplify these workflows. Reconsider only for a demonstrated limitation of the retained owner.

## Platform checks

Workbench retains macOS 14 and Apple Silicon as its supported baseline. The release Mac runs macOS 26.5.1 (25F80). Xcode reports 26.6 (17F113), while `xcrun --sdk macosx --show-sdk-version` and the selected SDK path identify **macOS 26.5**. Record the SDK actually used; do not infer it from the Xcode marketing version. No announced or beta-only API is required.

- [Apple capture authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media) requires per-app camera and microphone grants, purpose strings and the applicable entitlements. Check status first; ask when the person chooses the relevant action. Meetings has a separate identity and cannot inherit Workbench's approvals.
- The selected SDK's `AVCaptureDevice.h` declares `.external` and `.continuityCamera` from macOS 14. Camera authorization APIs predate the deployment minimum. Keep the existing Continuity Camera opt-in and selected-device lifecycle. [Apple's macOS camera sample](https://developer.apple.com/documentation/avfoundation/supporting-continuity-camera-in-your-macos-app) and [WWDC22 session 10018](https://developer.apple.com/videos/play/wwdc2022/10018/) describe iPhone camera input; that is distinct from showing the phone's screen over USB. Neither establishes that a specific attached phone works.
- [macOS 26.6 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-26_6-release-notes) were checked for relevant changes. They do not establish behavior on this 26.5.1 runtime. Physical camera/phone reconnection, older supported macOS, multiple displays and a remote meeting receiver retain their own acceptance limits.
- [Developer ID distribution](https://developer.apple.com/developer-id/) and [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) remain the distribution route. Reuse the existing signer, hardened runtime, notary profile and Workbench updater. Inspect the exact final archive, not a prior build. Meetings is signed and notarized separately.

## Native alternatives and decisions

Apple Screenshot and Preview provide a capable baseline for still capture and markup. Snap's useful difference is a fast capture-to-copy/drag path with a preserved original and searchable history. Add native image/file-promise drag to the existing image workspace; do not build another export manager.

macOS Dictation remains the baseline for speech input. Workbench retains its saved original wording, controlled paste fallback and existing local model choice. Automatic paste is already the default; preserve deliberate user choices and the original-target checks.

QuickTime Player, iPhone Mirroring and call apps retain their existing roles. Present composes the phone into a scene and exposes the existing profile, camera and voice-wave controls. Independent overlays retain separate Show/Hide/End ownership; a window share cannot be claimed to include other windows. No camera extension, driver, phone audio route or remote meeting bot is added.

Meetings imports explicitly from either Workbench edition. Copy validated recording folders and matching transcripts, retain original UUIDs and metadata, and never modify the source or overwrite later destination edits. Interrupted or repeated import must be safe. Existing Workbench meeting originals remain available even if the separate app is absent.
