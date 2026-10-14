import AppKit
import AVFoundation

/// The real new-section path with synthetic images and denied microphone before recorder
/// construction. No screen, audio device, live session, clipboard or permission prompt is used.
enum ReadbackCaptureChoiceChecks {
    @MainActor private final class Source: SnapImageSource {
        var settleDelay: UInt64 = 0
        var modes: [SnapCapture.Mode] = []
        var cancellations = 0
        var acquire: () throws -> Data? = { nil }
        func capture(_ mode: SnapCapture.Mode) async throws -> Data? {
            modes.append(mode)
            await Task.yield()
            return try acquire()
        }
        func cancel() { cancellations += 1 }
    }

    @MainActor static func run() async throws {
        var passed = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw ReadbackError.message("READBACK_CAPTURE_CHOICE_CHECK_FAILED: " + message) }
            passed += 1
        }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-capture-choices-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: fixture) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = bitmap.representation(using: .png, properties: [:])!

        // Replace screenshot and Redo use the page's Capture area on a section with known files.
        let corrections = ["replace-region", "replace-escape", "replace-close", "replace-no-screen", "replace-screen", "redo-escape", "redo-mic-denied", "redo-recorder-fails"]
        let originalScreen = Data("Original synthetic screen".utf8)
        for scenario in ["cancel", "permission", "late-denial", "close", "replace", "shutdown", "shutdown-settle", "task-cancel", "commit"] + corrections {
            let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.CaptureChoices.\(UUID().uuidString)").path
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            let directory = fixture.appendingPathComponent(scenario)
            let root = directory.appendingPathComponent("Session")
            var session = try ReadbackStore.create(at: root, title: "Synthetic capture choices")
            let sectionID = UUID(), sectionDirectory = "items/\(sectionID.uuidString.lowercased())"
            if corrections.contains(scenario) {
                try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(sectionDirectory), includingParents: false)
                try ReadbackStore.writePrivate(originalScreen, to: root.appendingPathComponent(sectionDirectory + "/screen.png"))
                for name in ["narration.wav", "narration-original.txt", "narration.txt"] {
                    try ReadbackStore.writePrivate(Data("Original synthetic \(name)".utf8), to: root.appendingPathComponent(sectionDirectory + "/" + name))
                }
                session.sections = [ReadbackSection(id: sectionID, capturedAt: Date(timeIntervalSince1970: 10), displayName: "Synthetic display",
                    directory: sectionDirectory, screenshot: sectionDirectory + "/screen.png", audio: sectionDirectory + "/narration.wav",
                    originalTranscript: sectionDirectory + "/narration-original.txt", transcript: sectionDirectory + "/narration.txt",
                    status: .ready, failure: nil, deletedAt: nil)]
                try ReadbackStore.save(session, at: root)
            }
            func files() throws -> [String: Data] {
                var found: [String: Data] = [:]
                for case let url as URL in fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
                    where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    found[url.path] = try Data(contentsOf: url)
                }
                return found
            }
            let history = root.appendingPathComponent(sectionDirectory + "/history")
            var before: [String: Data] = [:]
            func unchanged() -> Bool { (try? files()) == before }
            defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
            let source = Source()
            var microphone: AVAuthorizationStatus = .authorized
            var screenGranted = true, screenCalls = 0, saves = 0, hides = 0, restores = 0
            var denial: String?
            let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
                captureDisplay: { screenCalls += 1; return ReadbackScreenshot(data: image, displayName: "Synthetic display", screenFrame: .zero) },
                skillPacks: ReadbackSkillPackStore(root: directory.appendingPathComponent("Packs")),
                screenAccess: .init(isGranted: { screenGranted }, request: { fatalError("No permission request in checks") }),
                captureSelection: source, microphoneAccess: { microphone },
                makeNarrationRecorder: { _, _ in throw ReadbackError.message("Capture choice checks never record.") })
            defer { model.shutdown() }
            model.mayBeginCapture = { denial }
            model.onHideForEditorCapture = { hides += 1 }
            model.onRestoreAfterEditorCapture = { restores += 1 }
            let store = SnapStore(root: directory.appendingPathComponent("Snaps"))
            model.onSaveCapturedSnap = { [weak model] bytes, title in
                saves += 1
                let item = try store.insert(originalPNG: bytes, width: 8, height: 6, title: title, source: .narrated)
                // Exercise the real save/import path, then refuse recorder construction.
                microphone = .denied; model?.refreshPermissionState()
                return SnapHandoffSnapshot(id: item.id, title: item.title, createdAt: item.createdAt,
                    originalPNG: bytes, renderedPNG: nil, note: "", tags: [])
            }
            let manifestURL = root.appendingPathComponent("session.json")
            var expected = try Data(contentsOf: manifestURL)
            before = try files()
            source.acquire = { image }

            switch scenario {
            case "cancel":
                source.acquire = { nil }
                for mode in [SnapCapture.Mode.region, .window] { await model.captureNewSection(fromEditor: true, mode: mode) }
                try check(source.modes == [.region, .window] && hides == 2 && restores == 2, "selectors and editor restoration pair on Escape")
                try check(model.notice == nil, "Escape returns to ordinary controls without a failure")
            case "permission":
                screenGranted = false; model.refreshPermissionState()
                await model.captureNewSection(fromEditor: true, mode: .region)
                try check(source.modes.isEmpty && hides == 0, "permission refusal precedes capture and hiding")
            case "late-denial":
                source.acquire = { denial = "Synthetic input owner took over"; return image }
                await model.captureNewSection(fromEditor: true, mode: .window)
                try check(model.notice?.contains(denial!) == true, "late admission is checked before saving")
            case "close":
                source.acquire = { [weak model] in model?.closeSession(); return image }
                await model.captureNewSection(fromEditor: true, mode: .window)
                try check(model.sessionURL == nil && source.cancellations == 1, "closing cancels the owned selector and invalidates its result")
            case "replace":
                source.acquire = {
                    var changed = try ReadbackStore.load(from: root)
                    changed.id = UUID()
                    try ReadbackStore.save(changed, at: root)
                    expected = try Data(contentsOf: manifestURL)
                    return image
                }
                await model.captureNewSection(fromEditor: true, mode: .region)
                try check(model.notice?.contains("session folder changed") == true, "a replacement at the same path is rejected")
            case "shutdown":
                source.acquire = { [weak model] in model?.shutdown(); return image }
                await model.captureNewSection(fromEditor: true, mode: .window)
                try check(source.cancellations == 1, "shutdown cancels the selector and discards its late image")
            case "task-cancel":
                source.settleDelay = 1_000_000_000
                var task: Task<Void, Never>?
                model.onHideForEditorCapture = { hides += 1; task?.cancel() }
                task = Task { await model.captureNewSection(fromEditor: true, mode: .region) }
                await task?.value
                try check(source.modes.isEmpty && restores == 1, "cancellation during settling still restores the editor")
                model.onHideForEditorCapture = nil
            case "shutdown-settle":
                source.settleDelay = 1_000_000
                model.onHideForEditorCapture = { [weak model] in hides += 1; model?.shutdown() }
                await model.captureNewSection(fromEditor: true, mode: .region)
                try check(source.modes.isEmpty && restores == 1, "shutdown during settling never opens a selector afterwards")
            case "replace-region":
                await model.replaceScreenshot(sectionID, mode: .region)
                let replaced = try Data(contentsOf: root.appendingPathComponent(sectionDirectory + "/screen.png"))
                let archived = try fm.contentsOfDirectory(at: history, includingPropertiesForKeys: nil).map { try Data(contentsOf: $0) }
                try check(source.modes == [.region] && screenCalls == 0 && replaced == image && archived == [originalScreen],
                    "Replace uses the chosen region's selector and archives the earlier screenshot")
                try check(model.manifest?.sections.first?.audio == sectionDirectory + "/narration.wav" && model.manifest?.sections.first?.status == .ready,
                    "Replace keeps the section's narration")
            case "replace-escape":
                source.acquire = { nil }
                await model.replaceScreenshot(sectionID, mode: .window)
                try check(source.modes == [.window] && unchanged() && !fm.fileExists(atPath: history.path) && model.notice == nil,
                    "Escape in Replace's selector leaves every session file as it was")
            case "replace-close":
                source.acquire = { [weak model] in model?.closeSession(); return image }
                await model.replaceScreenshot(sectionID, mode: .region)
                try check(source.cancellations == 1 && unchanged(), "closing the session cancels Replace's selector and discards its image")
            case "replace-no-screen":
                screenGranted = false; model.refreshPermissionState()
                await model.replaceScreenshot(sectionID, mode: .region)
                try check(source.modes.isEmpty && hides == 0 && unchanged() && model.notice == model.permissionsProblem,
                    "Replace without Screen Recording explains before hiding or capturing")
            case "replace-screen":
                microphone = .denied; model.refreshPermissionState()
                await model.replaceScreenshot(sectionID)
                let replaced = try Data(contentsOf: root.appendingPathComponent(sectionDirectory + "/screen.png"))
                try check(screenCalls == 1 && source.modes.isEmpty && replaced == image, "Screen keeps its display capture, and Replace works with the microphone off")
            case "redo-escape":
                source.acquire = { nil }
                await model.redoBoth(sectionID, mode: .region)
                try check(source.modes == [.region] && unchanged() && model.notice == nil, "Escape in Redo's selector changes nothing and starts no microphone")
            case "redo-mic-denied":
                microphone = .denied; model.refreshPermissionState()
                await model.redoBoth(sectionID, mode: .window)
                try check(source.modes.isEmpty && hides == 0 && unchanged() && model.notice == model.permissionsProblem,
                    "Redo without the microphone explains before opening a selector it could not narrate")
            case "redo-recorder-fails":
                // The microphone is allowed but the recorder cannot start, as with no input device.
                await model.redoBoth(sectionID, mode: .region)
                let replaced = try Data(contentsOf: root.appendingPathComponent(sectionDirectory + "/screen.png"))
                let archived = try fm.contentsOfDirectory(at: history, includingPropertiesForKeys: nil).map { try Data(contentsOf: $0) }
                try check(source.modes == [.region] && replaced == image && archived == [originalScreen]
                    && model.manifest?.sections.first?.audio == sectionDirectory + "/narration.wav" && model.manifest?.sections.first?.status == .ready,
                    "Redo whose recorder cannot start keeps the new screenshot and the earlier narration")
                try check(model.notice?.hasPrefix("The screenshot was replaced and its narration was kept, but recording could not start.") == true,
                    "Redo whose recorder cannot start says the screenshot was replaced, not that nothing changed")
            default:
                for mode in [SnapCapture.Mode.region, .window] {
                    microphone = .authorized; model.refreshPermissionState()
                    await model.captureNewSection(fromEditor: true, mode: mode)
                }
                microphone = .authorized; model.refreshPermissionState()
                await model.captureNewSection(fromEditor: true)
                try check(source.modes == [.region, .window] && screenCalls == 1, "Screen retains its original service; selections use Snap's selectors")
                try check(saves == 3 && model.activeSections.count == 3, "each chosen image enters History and exactly one session section")
                try check(model.activeSections[0].displayName.contains("Region") && model.activeSections[1].displayName.contains("Window"),
                    "source labels describe the selected image")
                for section in model.activeSections {
                    let saved = try Data(contentsOf: ReadbackStore.safeURL(root: root, relative: section.screenshot))
                    try check(saved == image && section.audio == nil && section.status == .needsNarration,
                        "the exact image survives microphone refusal and remains available for narration")
                }
                // Without a microphone, typing a note is how the capture is finished (#63).
                let first = model.activeSections[0].id
                model.updateTranscript("Note", for: first)
                let noted = try ReadbackStore.load(from: root).sections.first { $0.id == first }
                try check(noted?.status == .ready && noted?.audio == nil, "a typed note makes the refused capture ready without audio")
            }
            try check(!model.isCapturing && !model.isRecording && !model.blocksDictation, "\(scenario) releases capture without starting a recorder")
            try check(hides == restores, "\(scenario) restores every hidden editor")
            if !["commit", "replace-region", "replace-screen", "redo-recorder-fails"].contains(scenario) {
                let after = try Data(contentsOf: manifestURL)
                try check(after == expected && saves == 0, "\(scenario) preserves session bytes and saves no new Snap")
            }
            source.acquire = { nil }
        }
        print("READBACK_CAPTURE_CHOICE_CHECKS_OK: \(passed) checks")
    }
}
