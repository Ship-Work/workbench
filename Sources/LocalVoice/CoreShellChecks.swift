import Foundation
import AVFoundation

/// Exercises the production opt-in owner against a saved session without touching user data.
enum CoreShellChecks {
    @MainActor static func run() async throws {
        func check(_ condition: @autoclosure () throws -> Bool, _ why: String) throws {
            guard try condition() else { throw VoiceError.message("CORE_SHELL_CHECK_FAILED: " + why) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-shell-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let domain = root.appendingPathComponent("Preferences").path
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let session = root.appendingPathComponent("Saved session")
        _ = try ReadbackStore.create(at: session, title: "Synthetic retained session")
        let manifest = session.appendingPathComponent("session.json")
        let before = try Data(contentsOf: manifest)
        defaults.set([session.path], forKey: "readback.recentSessionPaths.v1")
        var reads = 0, requests = 0, captures = 0
        let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), enabled: false, defaults: defaults,
            captureDisplay: { captures += 1; throw VoiceError.message("No capture expected") },
            transcribeAudio: { _ in throw VoiceError.message("No transcription expected") },
            skillPacks: ReadbackSkillPackStore(root: root.appendingPathComponent("Packs")),
            screenAccess: .init(isGranted: { reads += 1; return false }, request: { requests += 1; return false }),
            microphoneAccess: { reads += 1; return .notDetermined }, requestMicrophoneAccess: { requests += 1; return false })
        defer { model.shutdown() }
        model.refreshPermissionState(); model.returnedToWorkbench()
        await model.requestCaptureAccess(); await model.toggleCapture()
        for _ in 0..<5 { await Task.yield() }
        try check(!model.isEnabled && model.sessionURL == nil && !model.hasPendingTranscriptions, "disabled upgrade does not open or resume saved sessions")
        try check(reads == 0 && requests == 0 && captures == 0, "disabled owner does not inspect permissions, ask access or capture")
        try check(try Data(contentsOf: manifest) == before, "disabled owner preserves the saved manifest exactly")
        model.activate()
        try check(model.isEnabled && model.sessionURL?.standardizedFileURL.path == session.standardizedFileURL.path && reads > 0, "explicit opt-in restores the existing session")
        try check(requests == 0 && captures == 0, "enabling never requests capture permissions or records")
        try check(model.deactivate() && !model.isEnabled, "idle feature can turn off")
        let oldReads = reads
        model.refreshPermissionState(); model.returnedToWorkbench(); await model.toggleCapture()
        try check(reads == oldReads && captures == 0, "stale refresh and capture callbacks remain inactive after disabling")
        try check(try Data(contentsOf: manifest) == before, "turning off preserves original sessions")
        try check(MacPermission.allCases.map(\.rawValue) == ["microphone", "accessibility", "screenRecording", "camera"], "Workbench never offers standalone Meetings audio permission")
        try check(!WorkbenchHome.navItems.contains { $0.id == "meeting" || $0.id == "personas" }, "Meetings is removed and Persona belongs to Present")
        try check(WorkbenchHome.destination("meeting").page == "history" && WorkbenchHome.destination("personas").page == "present", "old routes preserve useful destinations")
        // While capture awaits a frame, turning off must retain its owner and visible recovery.
        var releaseCapture: CheckedContinuation<ReadbackScreenshot, Error>?
        let capturing = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), enabled: true, defaults: defaults,
            captureDisplay: { try await withCheckedThrowingContinuation { releaseCapture = $0 } },
            transcribeAudio: { _ in throw VoiceError.message("No transcription expected") },
            skillPacks: ReadbackSkillPackStore(root: root.appendingPathComponent("Packs")),
            screenAccess: .init(isGranted: { true }, request: { false }), microphoneAccess: { .authorized }, requestMicrophoneAccess: { false },
            makeNarrationRecorder: { _, _ in throw VoiceError.message("No microphone expected") })
        let capture = Task { await capturing.captureNewSection(fromEditor: false) }
        for _ in 0..<100 where releaseCapture == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(releaseCapture != nil && capturing.isCapturing, "synthetic capture reached the suspended owner")
        try check(!capturing.deactivate() && capturing.isEnabled, "disabling during capture refuses without discarding the operation")
        releaseCapture?.resume(throwing: VoiceError.message("Synthetic capture cancelled")); releaseCapture = nil
        await capture.value
        try check(capturing.deactivate() && !capturing.isCapturing, "after capture recovery the feature can turn off")
        capturing.shutdown()
        let archive = LegacyMeetingArchive(directory: root.appendingPathComponent("Meetings"))
        let oldID = UUID(), pending = archive.directory.appendingPathComponent(".transcript-removals").appendingPathComponent(oldID.uuidString)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let original = pending.appendingPathComponent("microphone.caf"), originalBytes = Data("Original retained audio".utf8)
        try originalBytes.write(to: original)
        try check(archive.hasSavedRecordings && archive.hasRecording(for: oldID) && archive.recordings(for: oldID).map(\.standardizedFileURL.path) == [pending.standardizedFileURL.path], "interrupted old removals remain discoverable")
        try check(try Data(contentsOf: original) == originalBytes, "passive recovery never alters staged originals")
        print("CORE_SHELL_CHECKS_OK: disabled launch, explicit enable, stale callbacks, preserved session, permissions and route migration")
    }
}
