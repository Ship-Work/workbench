import Carbon
import Foundation

enum ReadbackChecks {
    /// Safe to run from an extracted app: no app lifecycle, permissions, models,
    /// or user preferences. This exercises the actual new-session resource path.
    static func runPackagedResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-packaged-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = try ReadbackResources.deckPayload()
        let session = try ReadbackStore.create(at: root, title: "Synthetic packaged session")
        for (path, bytes) in expected {
            guard try Data(contentsOf: root.appendingPathComponent(path)) == bytes else {
                throw ReadbackError.message("Packaged Snap & Talk companion differs: \(path)")
            }
        }
        let reopened = try ReadbackStore.load(from: root)
        guard reopened.id == session.id,
              FileManager.default.fileExists(atPath: root.appendingPathComponent("README.md").path) else {
            throw ReadbackError.message("Packaged Snap & Talk session creation did not preserve its companion files.")
        }
        print("READBACK_PACKAGED_RESOURCES_OK: new session, exact complete skill payload, README and reopened manifest")
    }

    /// Resolve disposable bundle fixtures only; no LaunchServices lookup or app launch.
    static func runHandoffApplicationChecks() throws -> Int {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw ReadbackError.message("READBACK_HANDOFF_APP_CHECK_FAILED: \(message)") }
            passed += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-handoff-app-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func app(_ filename: String, displayName: Any? = nil, bundleName: Any? = nil) throws -> URL {
            let url = root.appendingPathComponent(filename + ".app")
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": "example.handoff.\(UUID().uuidString)", "CFBundlePackageType": "APPL"]
            info["CFBundleDisplayName"] = displayName
            info["CFBundleName"] = bundleName
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        let claude = try app("Claude current", displayName: "Claude")
        let legacyClaude = try app("Claude legacy", displayName: "Claude Legacy")
        let chatGPT = try app("ChatGPT", displayName: "ChatGPT")
        let codex = try app("Codex", displayName: "Codex")
        let installed = ["com.anthropic.claudefordesktop": claude, "com.anthropic.claude": legacyClaude,
                         "com.openai.chat": chatGPT, "com.openai.codex": codex]
        let cases: [(ReadbackHandoffTarget, String, String)] = [
            (.claude, "com.anthropic.claudefordesktop", "com.anthropic.claude"),
            (.chatGPT, "com.openai.chat", "com.openai.codex"),
            (.codex, "com.openai.codex", "com.openai.chat"),
        ]
        let launchError = NSError(domain: "SyntheticLaunch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic failure"])
        for (target, primary, alternate) in cases {
            let preferred = target.resolveApplication { $0 == primary ? installed[$0] : nil }
            try check(preferred?.url == installed[primary], "\(target.title) resolves its preferred installed app")
            var lookups: [String] = []
            let both = target.resolveApplication { identifier in
                lookups.append(identifier)
                return installed[identifier]
            }
            try check(both?.url == installed[primary] && lookups == [primary], "\(target.title) prefers its own identity when both are installed")
            guard let fallback = target.resolveApplication(using: { $0 == alternate ? installed[$0] : nil }) else {
                throw ReadbackError.message("READBACK_HANDOFF_APP_CHECK_FAILED: \(target.title) lost its installed fallback")
            }
            try check(fallback.url == installed[alternate], "\(target.title) retains its installed fallback")
            let actualName = alternate == "com.anthropic.claude" ? "Claude Legacy" : (alternate == "com.openai.chat" ? "ChatGPT" : "Codex")
            try check(fallback.openingNotice.contains("\(actualName) is opening.") && fallback.openingNotice.contains("Nothing was uploaded."),
                      "\(target.title) opening notice names the resolved app without claiming delivery")
            try check(fallback.failureNotice(launchError).hasPrefix("\(actualName) could not open: Synthetic failure")
                      && fallback.failureNotice(launchError).contains("Nothing was uploaded."),
                      "\(target.title) failure names the same resolved app")
            lookups = []
            let absent = target.resolveApplication { identifier in lookups.append(identifier); return nil }
            try check(absent == nil && lookups == [primary, alternate], "\(target.title) reports neither installed without inventing an app")
        }
        let display = try app("Disk name", displayName: "  Friendly Assistant  ", bundleName: "Internal name")
        try check(ReadbackHandoffApplication(url: display).title == "Friendly Assistant", "bundle display name takes precedence and trims whitespace")
        let named = try app("Different disk name", bundleName: "Bundle Assistant")
        try check(ReadbackHandoffApplication(url: named).title == "Bundle Assistant", "bundle name is used without a display name")
        let blank = try app("Renamed Assistant", displayName: " \n", bundleName: "\t")
        try check(ReadbackHandoffApplication(url: blank).title == "Renamed Assistant", "blank metadata falls back to the app filename")
        let invalid = try app("Untyped Assistant", displayName: 42)
        try check(ReadbackHandoffApplication(url: invalid).title == "Untyped Assistant", "non-string metadata falls back to the app filename")
        try check(ReadbackHandoffApplication(url: root.appendingPathComponent("Unavailable Assistant.app")).title == "Unavailable Assistant",
                  "an unreadable bundle keeps its own filename rather than the requested product name")
        return passed
    }

    static func run() throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw ReadbackError.message("READBACK_CHECK_FAILED: \(message)") }
            passed += 1
        }
        func rejects(_ message: String, _ work: () throws -> Void) throws {
            do { try work() }
            catch { passed += 1; return }
            throw ReadbackError.message("READBACK_CHECK_FAILED: \(message)")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-readback-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var manifest = try ReadbackStore.create(at: root, title: "Synthetic review")
        try check(FileManager.default.fileExists(atPath: root.appendingPathComponent("README.md").path), "new session includes a portable README")
        try check(FileManager.default.fileExists(atPath: root.appendingPathComponent("SKILL.md").path), "new session includes the deck-building skill")
        let rootMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        let manifestMode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(ReadbackStore.manifestName).path)[.posixPermissions] as? NSNumber
        try check(rootMode?.intValue == 0o700 && manifestMode?.intValue == 0o600, "new session metadata is private to the user")
        let skill = try String(contentsOf: root.appendingPathComponent("SKILL.md"), encoding: .utf8)
        try check(skill.hasPrefix("---\nname: build-snap-and-talk-deck\n"), "portable skill retains its discoverable identity")
        try check(skill.contains("template.pptx") && skill.contains("visible title") && skill.contains("supporting copy"), "neutral skill retains the optional-template route and narration-grounded copy")
        let payload = try ReadbackResources.deckPayload()
        let copiesMatch = try payload.allSatisfy { path, bytes in
            try Data(contentsOf: root.appendingPathComponent(path)) == bytes
        }
        try check(copiesMatch && manifest.skillPack == .neutral, "new session defaults to the complete, exact neutral payload")
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        try check(readme.contains("complete edited narration verbatim") && readme.contains("does not upload or submit"), "portable README explains slide copy and local handoff")
        try check(manifest.skillPack?.version == "1.1.0" && skill.contains("Neutral skill version 1.1.0"), "new neutral payload and immutable receipt identify the contained contract version")
        try check(skill.contains("Look only for `template.pptx` inside this session folder") && !skill.contains("then in the parent folder")
            && skill.contains("ask the user whether") && skill.contains("make the plain deck"), "template is in-session, optional and deliberately chosen")
        try check(skill.contains("Create `outputs/` inside this session") && skill.contains("Never overwrite an existing file")
            && !skill.contains("Write a new `.pptx` beside this folder") && readme.contains("under outputs/ in this folder"), "skill and README agree on a contained unique output without overwriting")
        try check(skill.contains("notes verbatim, unmodified") && skill.contains("manifest SHA-256") && skill.contains("render and inspect")
            && skill.contains("exact output path") && skill.contains("identify it as unverified"), "deck review retains exact narration, input identity, rendered verification and honest file return")
        let handoffRoot = root.appendingPathComponent("Folder with spaces", isDirectory: true)
        for target in ReadbackHandoffTarget.allCases {
            let prompt = target.prompt(for: handoffRoot)
            try check(prompt.contains("SKILL.md") && prompt.contains("session.json") && prompt.contains(handoffRoot.path), "\(target.title) handoff identifies the portable session")
            try check(prompt.contains("Keep the original session") && prompt.contains("Keep the work local"), "\(target.title) handoff preserves originals and external-service consent")
            let current = target.prompt(for: handoffRoot, brief: .snapTalkDeck(pack: manifest.skillPack))
            try check(current.contains("Follow this session's `SKILL.md` for template choice, output destination and verification")
                && !current.contains("`outputs/`") && current.contains("grants no upload permission"), "\(target.title) new neutral copied instructions defer output details to the actual frozen or customised skill")
            for pack in [nil, ReadbackSkillPackReference(id: "workbench-neutral", version: "1.0.0", name: "Neutral"),
                         ReadbackSkillPackReference(id: "private-custom", version: "1.1.0", name: "Private")] {
                try check(target.prompt(for: handoffRoot, brief: .snapTalkDeck(pack: pack)) == prompt,
                          "\(target.title) legacy and custom handoff prompts retain their existing contract")
            }
        }
        passed += try runHandoffApplicationChecks()
        try check(manifest.formatVersion == 1 && manifest.title == "Synthetic review" && manifest.sections.isEmpty, "new manifest is versioned and empty")

        let firstID = UUID(), secondID = UUID()
        let firstDirectory = "items/\(firstID.uuidString.lowercased())"
        let secondDirectory = "items/\(secondID.uuidString.lowercased())"
        try FileManager.default.createDirectory(at: root.appendingPathComponent(firstDirectory), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(secondDirectory), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: root.appendingPathComponent(firstDirectory + "/screen.png"))
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: root.appendingPathComponent(secondDirectory + "/screen.png"))
        manifest.sections = [
            ReadbackSection(id: firstID, capturedAt: Date(timeIntervalSince1970: 10), displayName: "Display 1", directory: firstDirectory,
                screenshot: firstDirectory + "/screen.png", audio: nil, originalTranscript: nil, transcript: nil, status: .needsNarration, failure: nil, deletedAt: nil),
            ReadbackSection(id: secondID, capturedAt: Date(timeIntervalSince1970: 20), displayName: "Display 2", directory: secondDirectory,
                screenshot: secondDirectory + "/screen.png", audio: nil, originalTranscript: nil, transcript: nil, status: .ready, failure: nil, deletedAt: nil)
        ]
        try ReadbackStore.save(manifest, at: root)
        let loaded = try ReadbackStore.load(from: root)
        try check(loaded.sections.map(\.id) == [firstID, secondID], "manifest round-trip preserves slide order")
        try check(loaded.sections[0].status == .needsNarration && loaded.sections[1].status == .ready, "unfinished and ready states remain distinct")
        var future = loaded
        future.formatVersion = 999
        try ReadbackStore.save(future, at: root)
        do {
            _ = try ReadbackStore.load(from: root)
            throw ReadbackError.message("READBACK_CHECK_FAILED: future manifests are rejected")
        } catch {
            try check(error.localizedDescription.contains("999") && error.localizedDescription.contains("1"), "unsupported format errors identify both versions")
        }
        try ReadbackStore.save(loaded, at: root)

        // Malformed portable manifests must be rejected before deletion can touch a parent or sibling.
        func writeUnchecked(_ value: ReadbackManifest) throws {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: root.appendingPathComponent(ReadbackStore.manifestName))
        }
        func rejectsManifest(_ message: String, _ edit: (inout ReadbackManifest) -> Void) throws {
            var invalid = loaded; edit(&invalid)
            try writeUnchecked(invalid)
            try rejects(message) { _ = try ReadbackStore.load(from: root) }
            try rejects(message + " on save") { try ReadbackStore.save(invalid, at: root) }
            try ReadbackStore.save(loaded, at: root)
        }
        for directory in ["items", "trash", ".", "items/" + secondID.uuidString.lowercased(), firstDirectory + "/nested"] {
            try rejectsManifest("section directory must belong to its UUID: \(directory)") { $0.sections[0].directory = directory }
        }
        try rejectsManifest("deleted sections cannot reference active directories") { $0.sections[0].deletedAt = Date() }
        try rejectsManifest("duplicate IDs are rejected before draft dictionaries or deletion") { $0.sections.append($0.sections[0]) }
        try rejectsManifest("screenshots cannot reference sibling files") { $0.sections[0].screenshot = secondDirectory + "/screen.png" }
        try rejectsManifest("audio cannot reference sibling files") { $0.sections[0].audio = secondDirectory + "/narration.wav" }
        try rejectsManifest("original transcripts cannot reference session metadata") { $0.sections[0].originalTranscript = "session.json" }
        try rejectsManifest("editable transcripts cannot reference sibling files") { $0.sections[0].transcript = secondDirectory + "/narration.txt" }
        try rejectsManifest("linked files cannot be the section directory itself") { $0.sections[0].screenshot = firstDirectory }
        try rejectsManifest("linked paths cannot traverse to another section") { $0.sections[0].screenshot = firstDirectory + "/../" + secondID.uuidString.lowercased() + "/screen.png" }
        let firstScreenshot = try Data(contentsOf: root.appendingPathComponent(firstDirectory + "/screen.png"))
        let secondScreenshot = try Data(contentsOf: root.appendingPathComponent(secondDirectory + "/screen.png"))
        try check(firstScreenshot == secondScreenshot && firstScreenshot.count == 4, "rejected manifests leave both synthetic screenshots untouched")

        let aliasID = UUID(), aliasDirectory = "items/\(aliasID.uuidString.lowercased())"
        let directoryAlias = root.appendingPathComponent(aliasDirectory)
        try FileManager.default.createSymbolicLink(at: directoryAlias, withDestinationURL: root.appendingPathComponent(secondDirectory))
        try rejectsManifest("section directories cannot alias a sibling") {
            $0.sections[0] = ReadbackSection(id: aliasID, capturedAt: Date(), displayName: "Alias", directory: aliasDirectory,
                screenshot: aliasDirectory + "/screen.png", audio: nil, originalTranscript: nil, transcript: nil,
                status: .needsNarration, failure: nil, deletedAt: nil)
        }
        try FileManager.default.removeItem(at: directoryAlias)
        let alias = root.appendingPathComponent(firstDirectory + "/alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent(secondDirectory))
        try rejectsManifest("internal links cannot alias a sibling's files") { $0.sections[0].screenshot = firstDirectory + "/alias/screen.png" }
        try rejects("archive folders cannot alias siblings") { _ = try ReadbackStore.safeURL(root: root, relative: firstDirectory + "/alias/history") }
        try FileManager.default.removeItem(at: alias)
        let missing = root.appendingPathComponent(firstDirectory + "/missing")
        try FileManager.default.createSymbolicLink(at: missing, withDestinationURL: root.appendingPathComponent("not-created"))
        try rejects("dangling symbolic links are rejected before writing") { _ = try ReadbackStore.safeURL(root: root, relative: firstDirectory + "/missing/narration.txt") }
        try FileManager.default.removeItem(at: missing)

        // Reproduce transcription finishing during the asynchronous screen capture.
        var completed = loaded
        completed.sections[0].audio = firstDirectory + "/narration.wav"
        completed.sections[0].originalTranscript = firstDirectory + "/narration-original.txt"
        completed.sections[0].transcript = firstDirectory + "/narration.txt"
        completed.sections[0].status = .ready
        let audioBytes = Data("synthetic saved audio".utf8)
        try audioBytes.write(to: root.appendingPathComponent(completed.sections[0].audio!))
        try Data("Original words".utf8).write(to: root.appendingPathComponent(completed.sections[0].originalTranscript!))
        try Data("Edited words".utf8).write(to: root.appendingPathComponent(completed.sections[0].transcript!))
        try ReadbackStore.save(completed, at: root)
        let thirdID = UUID(), thirdDirectory = "items/\(thirdID.uuidString.lowercased())"
        let appendedSection = ReadbackSection(id: thirdID, capturedAt: Date(), displayName: "Display 3", directory: thirdDirectory,
            screenshot: thirdDirectory + "/screen.png", audio: nil, originalTranscript: nil, transcript: nil, status: .needsNarration, failure: nil, deletedAt: nil)
        _ = try ReadbackStore.append(appendedSection, at: root)
        let appended = try ReadbackStore.load(from: root)
        try check(appended.sections.map(\.id) == [firstID, secondID, thirdID], "capture appends to the latest committed section order")
        try check(appended.sections[0] == completed.sections[0], "capture retains transcription completed after its initial snapshot")
        try check(ReadbackStore.readText(root: root, relative: appended.sections[0].transcript) == "Edited words", "capture retains the completed transcript file")

        // Beginning a rerecord changes only status; cancellation must restore that status and prior error.
        for previousStatus in [ReadbackSectionStatus.ready, .failed, .needsNarration] {
            var before = appended
            before.sections[0].status = previousStatus
            before.sections[0].failure = previousStatus == .failed ? "Original recognition failure" : nil
            var recording = before
            recording.sections[0].status = .recording; recording.sections[0].failure = nil
            try ReadbackStore.save(recording, at: root)
            let restored = try ReadbackStore.restoreNarrationState(before.sections[0], at: root)
            try check(restored.sections[0] == before.sections[0], "cancel rerecord restores previous \(previousStatus.rawValue) state and file links")
            let savedAudio = try Data(contentsOf: root.appendingPathComponent(restored.sections[0].audio!))
            try check(savedAudio == audioBytes, "cancel rerecord preserves original audio bytes")
            try check(ReadbackStore.readText(root: root, relative: restored.sections[0].originalTranscript) == "Original words"
                && ReadbackStore.readText(root: root, relative: restored.sections[0].transcript) == "Edited words", "cancel rerecord preserves original and edited transcripts")
            try check(restored.sections.dropFirst() == appended.sections.dropFirst(), "cancel rerecord preserves other sections")
        }
        var trashed = loaded
        trashed.sections[0].moveFiles(from: firstDirectory, to: "trash/\(firstID.uuidString.lowercased())")
        trashed.sections[0].deletedAt = Date()
        try ReadbackStore.save(trashed, at: root)
        let reloadedTrash = try ReadbackStore.load(from: root)
        try check(reloadedTrash.sections[0].directory.hasPrefix("trash/"), "valid recoverable-deletion paths still load")
        try ReadbackStore.save(loaded, at: root)
        try rejects("parent traversal is rejected") { _ = try ReadbackStore.safeURL(root: root, relative: "../outside") }
        try rejects("absolute paths are rejected") { _ = try ReadbackStore.safeURL(root: root, relative: "/tmp/outside") }
        let outside = root.deletingLastPathComponent().appendingPathComponent("Workbench-readback-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("items/escape"), withDestinationURL: outside)
        try rejects("symbolic-link escapes are rejected") { _ = try ReadbackStore.safeURL(root: root, relative: "items/escape/private.txt") }
        try rejects("non-empty folders are never replaced") { _ = try ReadbackStore.create(at: root, title: "Replacement") }

        var moved = loaded.sections[0]
        moved.moveFiles(from: firstDirectory, to: "trash/\(firstID.uuidString.lowercased())")
        try check(moved.screenshot.hasPrefix("trash/") && moved.directory.hasPrefix("trash/"), "recoverable deletion keeps linked paths together")
        try check(VoicePreferences().shortcut(5) == VoiceShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey)) && VoicePreferences().shortcut(5) != VoicePreferences().shortcut(1), "Snap & Talk defaults to Option-C")
        var legacyPreferences = VoicePreferences()
        legacyPreferences.readbackShortcut = VoicePreferences.legacyReadbackShortcut
        try check(VoicePreferences.migratingLegacyDefaults(legacyPreferences).shortcut(5) == VoicePreferences.defaultReadbackShortcut, "the conflicting legacy Control-Option-R default migrates")
        // The engine line beside Record narration (#134 follow-up): the readiness line's words while
        // ready or preparing, the reason with Retry model once preparation stopped.
        let readyEngine = ReadbackView.NarrationEngine(name: RecognitionConfiguration().summary, ready: true)
        try check(readyEngine.line == "Parakeet v2 · English · on this Mac" && !readyEngine.needsAttention && !readyEngine.preparing, "a ready engine shows the one readiness line")
        let preparingEngine = ReadbackView.NarrationEngine(name: "Downloading Parakeet · 42%", ready: false, preparing: true)
        try check(preparingEngine.line == "Downloading Parakeet · 42%" && preparingEngine.preparing && !preparingEngine.needsAttention, "a preparing engine shows its progress without Retry")
        let applying = ReadbackView.NarrationEngine(name: "Preparing Parakeet · first setup may take a few minutes", ready: false, preparing: true)
        try check(applying.preparing && !applying.needsAttention, "Settings › Models' own Use or Download is preparing too, never a failure with a second Retry")
        let failedEngine = ReadbackView.NarrationEngine(name: "The speech model couldn’t be prepared", ready: false, failure: "Check your connection.")
        try check(failedEngine.line == "The speech model couldn’t be prepared" && failedEngine.needsAttention && !failedEngine.preparing, "a failed preparation keeps the authoritative line without duplicating its failure")
        let keptEngine = ReadbackView.NarrationEngine(name: RecognitionConfiguration().summary, ready: true, failure: "The local server could not be reached.")
        try check(keptEngine.line == "Parakeet v2 · English · on this Mac" && !keptEngine.needsAttention && !keptEngine.preparing, "a failed switch beside a ready engine shows that engine's name, with no Retry model to press")
        print("READBACK_CHECKS_OK: \(passed) checks")
    }

    @MainActor
    static func runAdmissionChecks() async throws {
        var passed = try await ReadbackHandoffDeliveryChecks.run()
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw ReadbackError.message("READBACK_ADMISSION_CHECK_FAILED: \(message)") }
            passed += 1
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Workbench-readback-admission-\(UUID().uuidString)")
        let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.ReadbackAdmissionChecks.\(UUID().uuidString)").path
        guard let defaults = UserDefaults(suiteName: domain) else { throw ReadbackError.message("Unable to isolate check preferences") }
        defer { defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: root) }
        var manifest = try ReadbackStore.create(at: root, title: "Synthetic admission")
        let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
        try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory))
        let section = ReadbackSection(id: id, capturedAt: Date(timeIntervalSince1970: 10), displayName: "Synthetic display", directory: directory,
            screenshot: directory + "/screen.png", audio: directory + "/narration.wav", originalTranscript: directory + "/narration-original.txt",
            transcript: directory + "/narration.txt", status: .ready, failure: nil, deletedAt: nil)
        for path in [section.screenshot, section.audio!, section.originalTranscript!, section.transcript!] {
            try ReadbackStore.writePrivate(Data("Original synthetic \(path)".utf8), to: root.appendingPathComponent(path))
        }
        manifest.sections = [section]; try ReadbackStore.save(manifest, at: root)
        func snapshot() throws -> [String: Data] {
            var files: [String: Data] = [:]
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
                throw ReadbackError.message("Unable to enumerate synthetic session")
            }
            for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files[url.path] = try Data(contentsOf: url)
            }
            return files
        }
        let before = try snapshot()
        defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
        var denial: String? = "Synthetic ordinary dictation is active"
        var captureCount = 0
        var duringCapture: (() -> Void)?
        // Redo needs both permissions before it captures; fixed answers keep these checks off this Mac's settings.
        let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults, captureDisplay: {
            captureCount += 1
            await Task.yield()
            duringCapture?()
            return ReadbackScreenshot(data: Data("Replacement synthetic screenshot".utf8), displayName: "Synthetic capture", screenFrame: .zero)
        }, screenAccess: .fixed(true), microphoneAccess: { .authorized },
            makeNarrationRecorder: { _, _ in throw ReadbackError.message("Admission checks never record.") })
        defer { duringCapture = nil; model.shutdown() }
        model.mayBeginCapture = { denial }
        try check(model.manifest?.sections.first == section, "isolated model loads the ready synthetic section without permission prompts")
        await model.redoBoth(id)
        model.startNarration(for: id)
        await model.captureNewSection(fromEditor: true)
        let earlyDenied = try snapshot()
        try check(captureCount == 0, "busy admission blocks redo and new capture before invoking the capture service")
        try check(!model.isRecording && !model.isCapturing, "busy admission never starts a recorder")
        try check(earlyDenied == before, "early denial preserves manifest, original screenshot, audio and both transcripts byte for byte")
        try check(model.notice == denial, "early denial explains the owning operation")

        denial = nil
        var dictationBlockedDuringCapture = false
        duringCapture = {
            dictationBlockedDuringCapture = model.blocksDictation
            denial = "Synthetic reading started while capture awaited"
        }
        await model.redoBoth(id)
        let lateDenied = try snapshot()
        try check(captureCount == 1 && dictationBlockedDuringCapture, "in-flight screenshot capture reserves ordinary dictation admission")
        try check(lateDenied == before, "late admission denial occurs before archiving or replacing any previous section files")
        try check(model.manifest?.sections.first == section && !model.isRecording && !model.blocksDictation, "late denial retains ready state and releases the capture gate")
        try check(model.notice?.contains(denial!) == true, "late denial gives the busy reason")

        denial = nil
        duringCapture = { model.closeSession() }
        await model.redoBoth(id)
        let switched = try snapshot()
        try check(captureCount == 2 && switched == before, "closing the session during redo never modifies the previous session")
        try check(model.sessionURL == nil && !model.isRecording && !model.blocksDictation, "session change leaves no hidden recorder or capture reservation")
        print("READBACK_ADMISSION_CHECKS_OK: \(passed) checks")
        try await runTypedNoteChecks()
        try await ReadbackCaptureChoiceChecks.run()
        try await ReadbackCaptureAccessChecks.run()
    }

    @MainActor
    static func runAvailabilityChecks() async throws {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw ReadbackError.message("READBACK_AVAILABILITY_CHECK_FAILED: \(message)") }
            passed += 1
        }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-session-availability-\(UUID().uuidString)")
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        let root = fixture.appendingPathComponent("Original"), moved = fixture.appendingPathComponent("Moved")
        let other = fixture.appendingPathComponent("Different")
        let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.SessionAvailability.\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: fixture) }
        let original = try ReadbackStore.create(at: root, title: "Synthetic session")
        _ = try ReadbackStore.create(at: other, title: "Different session")
        defaults.set([root.path, other.path], forKey: "readback.recentSessionPaths.v1")
        var captures = 0
        let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults) {
            captures += 1
            return ReadbackScreenshot(data: Data(), displayName: "Synthetic", screenFrame: .zero)
        }
        defer { model.shutdown() }
        try check(model.currentSessionProblem == nil && model.manifest?.id == original.id, "existing session starts available")
        let originalBytes = try Data(contentsOf: root.appendingPathComponent("session.json"))
        try fm.moveItem(at: root, to: moved)
        model.refreshSessionAvailability()
        try check(model.currentSessionProblem != nil, "moving the open folder is reflected in current UI state")
        try check(model.unavailableSessions[root.standardizedFileURL.path] != nil, "missing recent gets an unavailable badge regardless of URL directory hint")
        try check(model.manifest?.id == original.id && model.recentSessionURLs.count == 2, "missing paths retain session identity and recents for recovery")
        await model.captureNewSection(fromEditor: false)
        try check(captures == 0 && !fm.fileExists(atPath: root.path), "capture refuses before permission/capture and never recreates the folder")
        do {
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent("items/\(UUID().uuidString)"), includingParents: false)
            throw ReadbackError.message("READBACK_AVAILABILITY_CHECK_FAILED: missing parents were recreated")
        } catch {
            try check(!fm.fileExists(atPath: root.path), "section creation cannot recreate parents even if the folder disappears after validation")
        }
        model.handOff(to: .claude)
        try check(model.notice?.contains("Locate") == true, "missing session cannot hand off stale paths")
        try check(!model.relinkSession(root, to: other), "locating cannot substitute a different active session")
        try check(model.sessionURL?.path == root.standardizedFileURL.path, "failed locate preserves the old selection")
        try fm.moveItem(at: moved, to: root)
        model.refreshSessionAvailability()
        try check(model.currentSessionProblem == nil, "restoring a folder clears its unavailable state")
        let manifestURL = root.appendingPathComponent("session.json"), held = fixture.appendingPathComponent("held.json")
        try fm.moveItem(at: manifestURL, to: held)
        model.refreshSessionAvailability()
        try check(model.currentSessionProblem != nil, "missing manifest also marks the session unavailable")
        try fm.moveItem(at: held, to: manifestURL)
        model.refreshSessionAvailability()
        try check(model.currentSessionProblem == nil, "manifest restoration recovers without restarting")
        try fm.moveItem(at: root, to: moved)
        model.refreshSessionAvailability()
        try check(model.relinkSession(root, to: moved), "locating the moved session succeeds")
        try check(model.sessionURL?.path == moved.standardizedFileURL.path && !model.recentSessionURLs.contains(where: { $0.path == root.path }), "relink replaces the stale path without duplicates")
        let movedBytes = try Data(contentsOf: moved.appendingPathComponent("session.json"))
        try check(movedBytes == originalBytes && !fm.fileExists(atPath: root.path), "locating does not rewrite or recreate session files")
        model.forgetRecentSession(moved)
        try check(model.sessionURL == nil && model.manifest == nil, "forgetting the current entry clears the editor")
        try check(fm.fileExists(atPath: moved.appendingPathComponent("session.json").path), "forgetting never deletes the user's session")
        try check(defaults.stringArray(forKey: "readback.recentSessionPaths.v1") == [other.path], "forgetting persists and preserves other recents")
        let reopened = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults)
        defer { reopened.shutdown() }
        try check(reopened.recentSessionURLs.map(\.path) == [other.standardizedFileURL.path], "forgotten entry stays removed after reopening")
        print("READBACK_AVAILABILITY_CHECKS_OK: \(passed) checks")
        try await runRecoveryChecks()
        try ReadbackPackChecks.run()
    }

    @MainActor
    private static func runRecoveryChecks() async throws {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw ReadbackError.message("READBACK_RECOVERY_CHECK_FAILED: \(message)") }
            passed += 1
        }
        func waitFor(_ message: String, _ ready: () -> Bool) async throws {
            for _ in 0..<500 {
                if ready() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw ReadbackError.message("READBACK_RECOVERY_CHECK_FAILED: timed out waiting for \(message)")
        }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-session-recovery-\(UUID().uuidString)")
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        var domains: [String] = []
        defer {
            for domain in domains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
            try? fm.removeItem(at: fixture)
        }
        func preferences(_ root: URL) -> UserDefaults {
            let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.SessionRecovery.\(UUID().uuidString)").path
            domains.append(domain)
            let defaults = UserDefaults(suiteName: domain)!
            defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
            return defaults
        }
        func session(_ name: String, statuses: [ReadbackSectionStatus] = []) throws -> (URL, ReadbackManifest) {
            let root = fixture.appendingPathComponent(name)
            var value = try ReadbackStore.create(at: root, title: name)
            for status in statuses {
                let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
                try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory), includingParents: false)
                try ReadbackStore.writePrivate(Data("Synthetic original audio".utf8), to: root.appendingPathComponent(directory + "/narration.wav"))
                value.sections.append(ReadbackSection(id: id, capturedAt: Date(), displayName: "Synthetic", directory: directory,
                    screenshot: directory + "/screen.png", audio: directory + "/narration.wav", originalTranscript: nil,
                    transcript: nil, status: status, failure: nil, deletedAt: nil))
            }
            try ReadbackStore.save(value, at: root)
            return (root, value)
        }

        // No refresh observes the missing interval: availability still has to
        // compare identity before handoff or showing the cached session's grid.
        do {
            let (root, original) = try session("Original identity")
            let (other, replacement) = try session("Replacement identity")
            let defaults = preferences(root)
            let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults)
            defer { model.shutdown() }
            let held = fixture.appendingPathComponent("Original held")
            let replacementBytes = try Data(contentsOf: other.appendingPathComponent("session.json"))
            try fm.moveItem(at: root, to: held); try fm.moveItem(at: other, to: root)
            model.refreshSessionAvailability()
            try check(model.currentSessionProblem?.contains("different session") == true, "same-path replacement is unavailable even when no poll observed absence")
            try check(model.manifest?.id == original.id, "replacement never adopts a different UUID implicitly")
            model.handOff(to: .claude)
            try check(model.notice?.contains("Locate") == true, "handoff refuses a replacement session before copying or opening an app")
            let unchanged = try Data(contentsOf: root.appendingPathComponent("session.json"))
            let stillReplacement = try ReadbackStore.load(from: root)
            try check(unchanged == replacementBytes && stillReplacement.id == replacement.id, "rejecting replacement preserves its manifest bytes")
            try fm.moveItem(at: root, to: other); try fm.moveItem(at: held, to: root)
            model.refreshSessionAvailability()
            try check(model.currentSessionProblem == nil && model.manifest?.id == original.id, "returning the original identity clears the problem")
        }

        // Lose one active and one queued job while the destination is absent.
        // Returning the folder must restart both from saved audio exactly once.
        do {
            let (root, original) = try session("Disconnected work", statuses: [.queued, .queued])
            let defaults = preferences(root), transcriber = ControlledTranscriber()
            let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
                transcribeAudio: { try await transcriber.transcribe($0) })
            defer { model.shutdown(); transcriber.cancel() }
            try await waitFor("first recognition") { transcriber.calls == 1 }
            let held = fixture.appendingPathComponent("Disconnected work held")
            try fm.moveItem(at: root, to: held); model.refreshSessionAvailability()
            try check(model.currentSessionProblem != nil, "an active job's missing folder is visible")
            transcriber.complete("Result completed while folder was absent")
            try await waitFor("missing jobs to leave the worker") { !model.hasPendingTranscriptions }
            let interrupted = try ReadbackStore.load(from: held)
            try check(interrupted.sections.map(\.status) == [.transcribing, .queued], "the saved folder retains active and queued work during absence")
            try fm.moveItem(at: held, to: root); model.refreshSessionAvailability()
            try await waitFor("first recovered recognition") { transcriber.calls == 2 }
            try check(model.currentSessionProblem == nil && model.pendingTranscriptionCount == 2, "reconnection schedules the orphaned active and queued jobs")
            transcriber.complete("Recovered first narration")
            try await waitFor("second recovered recognition") { transcriber.calls == 3 }
            transcriber.complete("Recovered second narration")
            try await waitFor("recovered jobs to finish") { !model.hasPendingTranscriptions }
            let completed = try ReadbackStore.load(from: root)
            try check(completed.sections.allSatisfy { $0.status == .ready }, "all recovered work reaches ready")
            try check(ReadbackStore.readText(root: root, relative: completed.sections[0].transcript) == "Recovered first narration"
                && ReadbackStore.readText(root: root, relative: completed.sections[1].transcript) == "Recovered second narration", "recovered results commit to their original sections")
            let originalAudio = try original.sections.map { try Data(contentsOf: root.appendingPathComponent($0.audio!)) }
            try check(originalAudio.allSatisfy { $0 == Data("Synthetic original audio".utf8) }, "recovery preserves original audio bytes")
            try check(transcriber.calls == 3, "recovery does not duplicate either completed job")
        }

        // A slow worker still owns its section when the folder reconnects.
        // Repeated refreshes, path normalization and forgetting are not restarts.
        do {
            let (root, _) = try session("Still running", statuses: [.queued])
            let defaults = preferences(root), transcriber = ControlledTranscriber()
            let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
                transcribeAudio: { try await transcriber.transcribe($0) })
            defer { model.shutdown(); transcriber.cancel() }
            try await waitFor("still-running recognition") { transcriber.calls == 1 }
            let held = fixture.appendingPathComponent("Still running held")
            try fm.moveItem(at: root, to: held); model.refreshSessionAvailability()
            try fm.moveItem(at: held, to: root); model.refreshSessionAvailability(); model.refreshSessionAvailability()
            let active = try ReadbackStore.load(from: root)
            try check(active.sections[0].status == .transcribing, "reconnection preserves a live worker's status")
            try check(model.pendingTranscriptionCount == 1 && transcriber.calls == 1, "reconnection never queues a duplicate for a live worker")
            model.forgetRecentSession(root)
            try check(model.sessionURL == nil && model.hasPendingTranscriptions, "forgetting clears only the editor while recognition continues")
            transcriber.complete("Completed after forgetting")
            try await waitFor("forgotten job to finish") { !model.hasPendingTranscriptions }
            let completed = try ReadbackStore.load(from: root)
            try check(completed.sections[0].status == .ready && transcriber.calls == 1, "independent recognition commits once after forgetting")
        }

        // Recording ownership is tested without opening the microphone.
        let (_, recording) = try session("Recording ownership", statuses: [.recording, .recording, .transcribing])
        let reconciled = ReadbackRecovery.reconcile(recording, activeTranscription: recording.sections[2].id, activeRecording: recording.sections[0].id)
        try check(reconciled.sections[0] == recording.sections[0] && reconciled.sections[2] == recording.sections[2], "live recording and recognition retain every saved field")
        try check(reconciled.sections[1].status == .needsNarration && reconciled.sections[1].failure?.contains("interrupted") == true, "only an orphaned recording is marked interrupted")
        print("READBACK_RECOVERY_CHECKS_OK: \(passed) checks")
        try await runQuitChecks()
        try await runRetakeChecks()
        try await runCancelChecks()
    }

    /// With the microphone off, a section that needs narration is finished by typing a note.
    /// Only that state changes; whitespace, other statuses and a failed save leave it as it was.
    @MainActor
    private static func runTypedNoteChecks() async throws {
        var passed = 0
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw ReadbackError.message("READBACK_TYPED_NOTE_CHECK_FAILED: \(message)") }
            passed += 1
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Workbench-typed-note-\(UUID().uuidString)")
        let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.TypedNote.\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: root) }
        var manifest = try ReadbackStore.create(at: root, title: "Synthetic typed notes")
        func section(_ status: ReadbackSectionStatus, audio: Bool, failure: String? = nil) throws -> ReadbackSection {
            let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory), includingParents: false)
            try ReadbackStore.writePrivate(Data("Synthetic screenshot".utf8), to: root.appendingPathComponent(directory + "/screen.png"))
            if audio { try ReadbackStore.writePrivate(Data("Synthetic audio".utf8), to: root.appendingPathComponent(directory + "/narration.wav")) }
            return ReadbackSection(id: id, capturedAt: Date(), displayName: "Synthetic", directory: directory, screenshot: directory + "/screen.png",
                audio: audio ? directory + "/narration.wav" : nil, originalTranscript: nil, transcript: nil, status: status, failure: failure, deletedAt: nil)
        }
        let unfinished = try section(.needsNarration, audio: false, failure: "The microphone could not start. Check that an input device is connected.")
        let others = [try section(.ready, audio: false), try section(.failed, audio: true, failure: "Synthetic recognition failure"),
                      try section(.needsNarration, audio: true), try section(.queued, audio: true)]
        let refused = try section(.needsNarration, audio: false)
        manifest.sections = [unfinished] + others + [refused]
        try ReadbackStore.save(manifest, at: root)
        defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
        let transcriber = ControlledTranscriber()
        let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
            transcribeAudio: { try await transcriber.transcribe($0) }, microphoneAccess: { .denied })
        defer { model.shutdown(); transcriber.cancel() }
        for _ in 0..<500 where transcriber.calls == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        func saved(_ id: UUID) throws -> ReadbackSection { try ReadbackStore.load(from: root).sections.first { $0.id == id }! }
        try check(transcriber.calls == 1, "the queued section is held in recognition while notes are typed")

        model.updateTranscript("  \n ", for: unfinished.id)
        try check(try saved(unfinished.id).status == .needsNarration, "whitespace leaves a section that needs narration unfinished")
        model.updateTranscript("Typed note", for: unfinished.id)
        let typed = try saved(unfinished.id)
        try check(typed.status == .ready && typed.failure == nil && typed.audio == nil && typed.originalTranscript == nil,
            "a typed note makes the section ready with no invented audio or original transcript")
        try check(typed.transcript == unfinished.directory + "/narration.txt"
            && (try? Data(contentsOf: root.appendingPathComponent(unfinished.directory + "/narration.txt"))) == Data("Typed note".utf8),
            "the note is saved as the section's narration text")
        try check(model.activeSections.first { $0.id == unfinished.id }?.status == .ready, "the page shows the finished section")
        model.updateTranscript("", for: unfinished.id)
        try check(try saved(unfinished.id).status == .ready, "clearing the note later never demotes the section")
        for other in others {
            let before = try saved(other.id).status
            model.updateTranscript("Typed beside \(other.status.rawValue)", for: other.id)
            try check(try saved(other.id).status == before, "a note leaves a \(other.status.rawValue) section's status alone")
        }

        model.transcriptManifestWriter = { _, _ in throw ReadbackError.message("The session folder is temporarily read-only.") }
        model.updateTranscript("Note kept while saving fails", for: refused.id)
        try check(try saved(refused.id).status == .needsNarration && model.transcriptSaveFailures[refused.id] != nil
            && model.transcriptDrafts[refused.id] == "Note kept while saving fails", "a failed save keeps the note and leaves the section unfinished")
        model.transcriptManifestWriter = nil
        model.retryTranscriptSave(refused.id)
        try check(try saved(refused.id).status == .ready && model.transcriptSaveFailures[refused.id] == nil, "Retry save finishes the section")
        print("READBACK_TYPED_NOTE_CHECKS_OK: \(passed) checks")
    }

    /// Writes a synthetic mono 16 kHz take where the real recorder would, and meters it.
    @MainActor
    private final class SyntheticNarrationRecorder: NarrationRecording {
        let url: URL, seconds: Double, peak: Float
        private(set) var written: Data?
        /// The meter's elapsed time, when a check moves the take along without writing longer audio.
        var reportedTime: TimeInterval?
        init(url: URL, seconds: Double, peak: Float) { self.url = url; self.seconds = seconds; self.peak = peak }
        var currentTime: TimeInterval { reportedTime ?? (written == nil ? 0 : seconds) }
        func prepareToRecord() -> Bool { true }
        func record() -> Bool {
            let rate = 16_000, count = Int(Double(rate) * seconds), amplitude = Double(Int16.max) * pow(10, Double(peak) / 20)
            var samples = Data(capacity: count * 2)
            for index in 0..<count {
                let value = Int16(amplitude * sin(2 * Double.pi * 440 * Double(index) / Double(rate)))
                withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
            }
            func field<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
            var wav = Data("RIFF".utf8) + field(UInt32(36 + samples.count)) + Data("WAVEfmt ".utf8)
            wav += field(UInt32(16)) + field(UInt16(1)) + field(UInt16(1)) + field(UInt32(rate)) + field(UInt32(rate * 2))
            wav += field(UInt16(2)) + field(UInt16(16)) + Data("data".utf8) + field(UInt32(samples.count)) + samples
            guard (try? wav.write(to: url)) != nil else { return false }
            written = wav
            return true
        }
        func stop() {}
        func updateMeters() {}
        func peakPower(forChannel channelNumber: Int) -> Float { peak }
        func averagePower(forChannel channelNumber: Int) -> Float { peak - 3 }
    }

    /// Quit keeps a narration in progress as Stop does: the take becomes the section's
    /// narration, queued for the next launch, and a short or quiet take is discarded the same way.
    @MainActor
    private static func runQuitChecks() async throws {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw ReadbackError.message("READBACK_QUIT_CHECK_FAILED: \(message)") }
            passed += 1
        }
        func waitFor(_ message: String, _ ready: () -> Bool) async throws {
            for _ in 0..<500 {
                if ready() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw ReadbackError.message("READBACK_QUIT_CHECK_FAILED: timed out waiting for \(message)")
        }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-quit-narration-\(UUID().uuidString)")
        var domains: [String] = []
        defer {
            for domain in domains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
            try? fm.removeItem(at: fixture)
        }
        for (name, seconds, peak, quit) in [("kept", 1.0, Float(-10), true), ("short", 0.2, -10, true), ("quiet", 1.0, -60, true), ("quiet-stop", 1.0, -60, false)] {
            let root = fixture.appendingPathComponent(name)
            var manifest = try ReadbackStore.create(at: root, title: "Synthetic quit")
            let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory), includingParents: false)
            try ReadbackStore.writePrivate(Data("Synthetic screenshot".utf8), to: root.appendingPathComponent(directory + "/screen.png"))
            let section = ReadbackSection(id: id, capturedAt: Date(), displayName: "Synthetic", directory: directory, screenshot: directory + "/screen.png",
                audio: nil, originalTranscript: nil, transcript: nil, status: .needsNarration, failure: nil, deletedAt: nil)
            manifest.sections = [section]; try ReadbackStore.save(manifest, at: root)
            let before = try ReadbackStore.load(from: root).sections[0]
            let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.QuitNarration.\(UUID().uuidString)").path
            domains.append(domain)
            let defaults = UserDefaults(suiteName: domain)!
            defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
            var take: SyntheticNarrationRecorder?
            let unused = ControlledTranscriber()
            let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
                transcribeAudio: { try await unused.transcribe($0) }, microphoneAccess: { .authorized },
                makeNarrationRecorder: { url, _ in
                    let recorder = SyntheticNarrationRecorder(url: url, seconds: seconds, peak: peak); take = recorder; return recorder
                })
            defer { model.shutdown() }
            var cues = 0
            model.onNarrationNotHeard = { cues += 1 }
            model.startNarration(for: id)
            try check(model.isRecording && take?.written != nil, "\(name): narration starts on the synthetic recorder")
            try await waitFor("\(name) meter tick") { model.recordingElapsed > 0 }
            if quit { model.shutdown() } else { model.stopNarration() }
            let pending = try fm.contentsOfDirectory(atPath: root.appendingPathComponent(directory).path).filter { $0.hasPrefix("narration-pending-") }
            let saved = try ReadbackStore.load(from: root).sections[0]
            try check(pending.isEmpty && !model.isRecording, "\(name): no pending take remains after \(quit ? "quitting" : "Stop")")
            try check(unused.calls == 0, "\(name): nothing is transcribed while quitting")
            if name == "kept" {
                try check(saved.audio == directory + "/narration.wav" && saved.status == .queued && saved.failure == nil,
                    "quitting keeps the take as the section's queued narration")
                let narration = try Data(contentsOf: root.appendingPathComponent(directory + "/narration.wav"))
                try check(narration == take?.written, "the kept narration has the recorded bytes")
                try check(cues == 0, "quitting with a kept take fires no cue")
                let transcriber = ControlledTranscriber()
                let relaunched = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
                    transcribeAudio: { try await transcriber.transcribe($0) })
                defer { relaunched.shutdown(); transcriber.cancel() }
                try await waitFor("the next launch to transcribe the kept take") { transcriber.calls == 1 }
                transcriber.complete("Narration kept through quit")
                try await waitFor("the kept take to be ready") { (try? ReadbackStore.load(from: root).sections[0].status) == .ready }
                let ready = try ReadbackStore.load(from: root).sections[0]
                try check(ReadbackStore.readText(root: root, relative: ready.transcript) == "Narration kept through quit" && transcriber.calls == 1
                    && unused.calls == 0, "the next launch transcribes the kept take once")
            } else {
                try check(saved == before, "\(name): a take too short or quiet to keep restores the section as Stop does")
                try check(cues == (quit ? 0 : 1), "\(name): only Stop gives the no-speech cue")
            }
        }
        passed += try await runWaitForSpeechChecks()
        print("READBACK_QUIT_CHECKS_OK: \(passed) checks")
    }

    /// A retake that passes Stop's quiet screen but transcribes to no words keeps the section's
    /// earlier notes or narration and offers no retry (#342); words replace them, and a real
    /// engine failure keeps Retry transcription with the earlier text still on disk.
    @MainActor
    private static func runRetakeChecks() async throws {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw ReadbackError.message("READBACK_RETAKE_CHECK_FAILED: \(message)") }
            passed += 1
        }
        func waitFor(_ message: String, _ ready: () -> Bool) async throws {
            for _ in 0..<500 {
                if ready() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw ReadbackError.message("READBACK_RETAKE_CHECK_FAILED: timed out waiting for \(message)")
        }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-retake-\(UUID().uuidString)")
        var domains: [String] = []
        defer {
            for domain in domains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
            try? fm.removeItem(at: fixture)
        }
        struct Outcome { let root: URL; let directory: String; let section: ReadbackSection; let notice: String?; let draft: String?; let history: [String] }
        /// Records a clear synthetic take over a section, stops it and ends recognition with `finish`.
        func retake(_ name: String, status: ReadbackSectionStatus, audio: Bool, original: String?, edited: String?,
                    finish: (ControlledTranscriber) -> Void) async throws -> Outcome {
            let root = fixture.appendingPathComponent(name)
            var manifest = try ReadbackStore.create(at: root, title: "Synthetic retake")
            let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory), includingParents: false)
            try ReadbackStore.writePrivate(Data("Synthetic screenshot".utf8), to: root.appendingPathComponent(directory + "/screen.png"))
            if audio { try ReadbackStore.writePrivate(Data("Synthetic earlier audio".utf8), to: root.appendingPathComponent(directory + "/narration.wav")) }
            if let original { try ReadbackStore.writePrivate(Data(original.utf8), to: root.appendingPathComponent(directory + "/narration-original.txt")) }
            if let edited { try ReadbackStore.writePrivate(Data(edited.utf8), to: root.appendingPathComponent(directory + "/narration.txt")) }
            manifest.sections = [ReadbackSection(id: id, capturedAt: Date(), displayName: "Synthetic", directory: directory, screenshot: directory + "/screen.png",
                audio: audio ? directory + "/narration.wav" : nil, originalTranscript: original == nil ? nil : directory + "/narration-original.txt",
                transcript: edited == nil ? nil : directory + "/narration.txt", status: status, failure: nil, deletedAt: nil)]
            try ReadbackStore.save(manifest, at: root)
            let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.Retake.\(UUID().uuidString)").path
            domains.append(domain)
            let defaults = UserDefaults(suiteName: domain)!
            defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
            let transcriber = ControlledTranscriber()
            let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
                transcribeAudio: { try await transcriber.transcribe($0) }, microphoneAccess: { .authorized },
                makeNarrationRecorder: { url, _ in SyntheticNarrationRecorder(url: url, seconds: 1.0, peak: -10) })
            defer { model.shutdown(); transcriber.cancel() }
            model.startNarration(for: id)
            try check(model.isRecording, "\(name): the retake starts on the synthetic recorder")
            try await waitFor("\(name) meter tick") { model.recordingElapsed > 0 }
            model.stopNarration()
            try await waitFor("\(name) recognition") { transcriber.calls == 1 }
            let queued = try ReadbackStore.load(from: root).sections[0]
            try check(queued.audio == directory + "/narration.wav" && queued.originalTranscript == nil,
                "\(name): Stop sets aside only the earlier audio and its original")
            if let edited {
                try check(queued.transcript == directory + "/narration.txt"
                    && ReadbackStore.readText(root: root, relative: queued.transcript) == edited
                    && (model.transcriptDrafts[id] ?? "") == edited,
                    "\(name): Stop keeps the earlier text linked and in the page's draft while the take transcribes")
            }
            finish(transcriber)
            try await waitFor("\(name) recognition to end") {
                (try? ReadbackStore.load(from: root).sections[0].status).map { ![.queued, .transcribing].contains($0) } ?? false
            }
            let history = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(directory + "/history").path)) ?? []
            return Outcome(root: root, directory: directory, section: try ReadbackStore.load(from: root).sections[0],
                           notice: model.notice, draft: model.transcriptDrafts[id], history: history)
        }
        func offersNoRetry(_ outcome: Outcome) -> Bool {
            outcome.section.status != .failed && outcome.notice?.localizedCaseInsensitiveContains("retry") != true
                && outcome.section.failure?.localizedCaseInsensitiveContains("retry") != true
        }
        let kept = "No speech heard. The screenshot and any earlier narration were kept."

        // 1. Imported notes: the notes stay, the silent take goes to history, and nothing offers a retry.
        let notes = try await retake("notes", status: .ready, audio: false, original: nil, edited: "My notes") { $0.complete("") }
        try check(notes.section.status == .ready && notes.section.failure == nil && notes.section.audio == nil,
            "notes: an empty result leaves the section ready with no audio to retry")
        try check(ReadbackStore.readText(root: notes.root, relative: notes.section.transcript) == "My notes" && notes.draft == "My notes",
            "notes: the notes stay on disk and in the page")
        try check(notes.history.filter { $0.hasSuffix("-audio.wav") }.count == 1, "notes: the silent take is kept in history, never deleted")
        try check(offersNoRetry(notes) && notes.notice == kept, "notes: no retry is offered and the notice says what was kept")

        // 2. Narrated section: the edited narration stays; the earlier audio and original are in history.
        let narrated = try await retake("narrated", status: .ready, audio: true, original: "Earlier words", edited: "Earlier words, edited") { $0.complete("") }
        try check(narrated.section.status == .ready && narrated.section.audio == nil && offersNoRetry(narrated)
            && ReadbackStore.readText(root: narrated.root, relative: narrated.section.transcript) == "Earlier words, edited",
            "narrated: an empty result keeps the edited narration, ready")
        try check(narrated.history.filter { $0.hasSuffix("-audio.wav") }.count == 2 && narrated.history.contains { $0.hasSuffix("-original-transcript.txt") },
            "narrated: the earlier audio and original, and the silent take, are in history")

        // 3. Fresh capture: its empty linked note keeps it ready, not stranded at a retry.
        let fresh = try await retake("fresh", status: .ready, audio: false, original: nil, edited: "") { $0.complete(" \n") }
        try check(fresh.section.status == .ready && fresh.section.audio == nil && offersNoRetry(fresh), "fresh: an empty result leaves a fresh capture ready")

        // 4. Nothing linked: the section still needs narration and says to record again.
        let bare = try await retake("bare", status: .needsNarration, audio: false, original: nil, edited: nil) { $0.complete("") }
        try check(bare.section.status == .needsNarration && bare.section.failure == "No speech was heard. Record the narration again."
            && bare.section.audio == nil && offersNoRetry(bare), "bare: an empty result asks to record again, not to retry")

        // 5. A real engine failure keeps Retry transcription; the earlier notes stay linked on disk.
        let failed = try await retake("engine-failure", status: .ready, audio: false, original: nil, edited: "My notes") {
            $0.fail(ReadbackError.message("Synthetic engine failure."))
        }
        try check(failed.section.status == .failed && failed.section.audio != nil && failed.notice?.contains("kept for retry") == true,
            "engine failure: the take fails with its audio kept for Retry transcription")
        try check(ReadbackStore.readText(root: failed.root, relative: failed.section.transcript) == "My notes",
            "engine failure: the earlier notes are still on disk and linked")

        // 6. Words replace the earlier text, which moves to history.
        let words = try await retake("words", status: .ready, audio: true, original: "Earlier words", edited: "Earlier words, edited") { $0.complete("New words") }
        try check(words.section.status == .ready && words.section.audio == words.directory + "/narration.wav"
            && ReadbackStore.readText(root: words.root, relative: words.section.transcript) == "New words"
            && ReadbackStore.readText(root: words.root, relative: words.section.originalTranscript) == "New words",
            "words: the new narration is the section's text and original")
        let archived = try words.history.filter { $0.hasSuffix("-edited-transcript.txt") }
            .map { try String(contentsOf: words.root.appendingPathComponent(words.directory + "/history/" + $0), encoding: .utf8) }
        try check(archived == ["Earlier words, edited"], "words: the earlier edited narration is archived, not overwritten")
        print("READBACK_RETAKE_CHECKS_OK: \(passed) checks")
    }

    /// Cancel follows one rule from the page and the toolbar: a long take asks the page's
    /// question and keeps recording, Discard answers only for that take, and the question
    /// ends with the take, including at the 300 s auto-stop.
    @MainActor
    private static func runCancelChecks() async throws {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw ReadbackError.message("READBACK_CANCEL_CHECK_FAILED: \(message)") }
            passed += 1
        }
        func waitFor(_ message: String, _ ready: () -> Bool) async throws {
            for _ in 0..<500 {
                if ready() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw ReadbackError.message("READBACK_CANCEL_CHECK_FAILED: timed out waiting for \(message)")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Workbench-cancel-narration-\(UUID().uuidString)")
        let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.CancelNarration.\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain); try? fm.removeItem(at: root) }
        var manifest = try ReadbackStore.create(at: root, title: "Synthetic cancel")
        let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
        try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory), includingParents: false)
        try ReadbackStore.writePrivate(Data("Synthetic screenshot".utf8), to: root.appendingPathComponent(directory + "/screen.png"))
        manifest.sections = [ReadbackSection(id: id, capturedAt: Date(), displayName: "Synthetic", directory: directory, screenshot: directory + "/screen.png",
            audio: nil, originalTranscript: nil, transcript: nil, status: .needsNarration, failure: nil, deletedAt: nil)]
        try ReadbackStore.save(manifest, at: root)
        defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
        var take: SyntheticNarrationRecorder?
        let transcriber = ControlledTranscriber()
        let model = ReadbackModel(engine: RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults)), defaults: defaults,
            transcribeAudio: { try await transcriber.transcribe($0) }, microphoneAccess: { .authorized },
            makeNarrationRecorder: { url, _ in
                let recorder = SyntheticNarrationRecorder(url: url, seconds: 1.0, peak: -10); take = recorder; return recorder
            })
        defer { model.shutdown(); transcriber.cancel() }
        /// Starts a take and lets the meter read `seconds`; returns its identity and pending file.
        func record(for seconds: Double) async throws -> (String, URL) {
            model.startNarration(for: id)
            try check(model.isRecording, "a take starts on the synthetic recorder")
            take?.reportedTime = seconds
            try await waitFor("the meter to read \(seconds) s") { model.recordingElapsed == seconds }
            let identity = model.narrationIdentity ?? ""
            return (identity, URL(string: identity)!)
        }

        try check(!ReadbackModel.cancelAsksFirst(elapsed: 10) && ReadbackModel.cancelAsksFirst(elapsed: 10.1), "one rule: Cancel asks first past ten seconds")

        // A long take asks, keeps recording and keeps its audio; Keep recording carries on.
        let (long, longFile) = try await record(for: 74)
        try check(model.requestCancelNarration() && model.pendingCancelNarration == long && model.isRecording && fm.fileExists(atPath: longFile.path),
            "at 74 s Cancel asks about this take and keeps the file")
        model.pendingCancelNarration = nil
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(model.isRecording && model.narrationIdentity == long && fm.fileExists(atPath: longFile.path), "Keep recording keeps the take running")

        // Discard answers only for the take it asked about.
        try check(model.requestCancelNarration(), "the question can be asked again")
        model.confirmCancelNarration("file:///synthetic/narration-pending-stale.wav")
        try check(model.isRecording && fm.fileExists(atPath: longFile.path) && model.pendingCancelNarration == nil, "a stale Discard leaves the take recording")
        try check(model.requestCancelNarration(), "the question is asked once more")
        model.confirmCancelNarration(long)
        try check(!model.isRecording && !fm.fileExists(atPath: longFile.path) && model.pendingCancelNarration == nil
            && (try? ReadbackStore.load(from: root))?.sections[0].status == .needsNarration, "Discard removes the take it asked about and restores the section")

        // A short take is discarded at once, as before.
        let (_, shortFile) = try await record(for: 5)
        try check(!model.requestCancelNarration() && !model.isRecording && !fm.fileExists(atPath: shortFile.path) && model.pendingCancelNarration == nil,
            "at 5 s Cancel discards at once without asking")

        // Stop ends the question with the take it kept.
        _ = try await record(for: 74)
        try check(model.requestCancelNarration() && model.pendingCancelNarration != nil, "a long take asks before Stop")
        model.stopNarration()
        try check(!model.isRecording && model.pendingCancelNarration == nil, "Stop clears the question")
        try await waitFor("the kept take to transcribe") { transcriber.calls == 1 }
        transcriber.complete("Synthetic kept words")
        try await waitFor("the kept take to be ready") { (try? ReadbackStore.load(from: root).sections[0].status) == .ready }

        // So does the 300 s auto-stop.
        _ = try await record(for: 74)
        try check(model.requestCancelNarration() && model.pendingCancelNarration != nil, "a long take asks before the auto-stop")
        take?.reportedTime = 300
        try await waitFor("the auto-stop") { !model.isRecording }
        try check(model.pendingCancelNarration == nil, "the 300 s auto-stop clears the question")
        print("READBACK_CANCEL_CHECKS_OK: \(passed) checks")
    }

    /// The next launch meets the real engine while Parakeet still loads: its admission refuses
    /// until preparation finishes. A kept take waits queued and then transcribes; a model that
    /// could not be prepared, or that nothing is preparing, still fails it with that reason.
    @MainActor
    private static func runWaitForSpeechChecks() async throws -> Int {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw ReadbackError.message("READBACK_QUIT_CHECK_FAILED: \(message)") }
            passed += 1
        }
        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-quit-speech-\(UUID().uuidString)")
        var domains: [String] = []
        defer {
            for domain in domains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
            try? fm.removeItem(at: fixture)
        }
        func saved(_ root: URL) -> ReadbackSection? { try? ReadbackStore.load(from: root).sections.first }
        func waitFor(_ message: String, _ ready: () async -> Bool) async throws {
            for _ in 0..<500 {
                if await ready() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw ReadbackError.message("READBACK_QUIT_CHECK_FAILED: timed out waiting for \(message)")
        }
        func launch(_ name: String) throws -> (URL, UserDefaults) {
            let root = fixture.appendingPathComponent("speech-\(name)")
            var manifest = try ReadbackStore.create(at: root, title: "Synthetic relaunch")
            let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory), includingParents: false)
            try ReadbackStore.writePrivate(Data("Synthetic screenshot".utf8), to: root.appendingPathComponent(directory + "/screen.png"))
            try ReadbackStore.writePrivate(Data("Synthetic kept narration".utf8), to: root.appendingPathComponent(directory + "/narration.wav"))
            manifest.sections = [ReadbackSection(id: id, capturedAt: Date(), displayName: "Synthetic", directory: directory, screenshot: directory + "/screen.png",
                audio: directory + "/narration.wav", originalTranscript: nil, transcript: nil, status: .queued, failure: nil, deletedAt: nil)]
            try ReadbackStore.save(manifest, at: root)
            let domain = fm.temporaryDirectory.appendingPathComponent("Workbench.QuitSpeech.\(UUID().uuidString)").path
            domains.append(domain)
            let defaults = UserDefaults(suiteName: domain)!
            defaults.set([root.path], forKey: "readback.recentSessionPaths.v1")
            return (root, defaults)
        }
        func engine(_ held: HeldSpeechPreparation, _ defaults: UserDefaults) -> RecognitionEngine {
            RecognitionEngine(store: .init(defaults: defaults), services: .init(prepareCached: { _ in
                try await held.prepare()
                return .init(backend: RecognitionBackend(transcribe: { _ in "Synthetic words" }, transcribeLive: { _ in [] }))
            }, acquire: { _ in throw CancellationError() }, send: { _ in throw URLError(.cannotConnectToHost) }))
        }

        // As at launch: AppModel starts preparing, then Snap & Talk resumes the kept take.
        for (name, beforeQueue) in [("launch", true), ("mid-take", false)] {
            let (root, defaults) = try launch(name)
            let held = HeldSpeechPreparation(fails: false), speech = engine(held, defaults)
            var preparing: Task<Void, Error>?
            if beforeQueue { preparing = Task { try await speech.prepareCached() } }
            // mid-take: preparation starts after the queue looked and before the take reaches the engine.
            var midTake: (@MainActor (URL) async throws -> String)?
            if !beforeQueue {
                midTake = { (url: URL) async throws -> String in
                    if preparing == nil {
                        preparing = Task { try await speech.prepareCached() }
                        try await waitFor("\(name): preparation to start") { await held.started }
                    }
                    return try await speech.transcribe(url)
                }
            }
            let model = ReadbackModel(engine: speech, defaults: defaults, transcribeAudio: midTake)
            defer { model.shutdown() }
            try await Task.sleep(nanoseconds: 1_500_000_000)
            let waiting = saved(root), heldOpen = await held.started
            try check(heldOpen && waiting?.status == .queued && waiting?.failure == nil && model.hasPendingTranscriptions
                && model.notice?.contains("Transcription failed") != true, "\(name): the kept take waits queued while speech prepares")
            await held.release()
            try await waitFor("\(name): the kept take to be ready") { saved(root)?.status == .ready }
            try check(ReadbackStore.readText(root: root, relative: saved(root)?.transcript) == "Synthetic words" && !model.hasPendingTranscriptions,
                "\(name): the kept take transcribes once speech is ready")
            _ = try await preparing?.value
        }

        // Preparation stops with a reason: the take fails with that reason and Retry transcription.
        do {
            let (root, defaults) = try launch("failed")
            let held = HeldSpeechPreparation(fails: true), speech = engine(held, defaults)
            let preparing = Task { try await speech.prepareCached() }
            let model = ReadbackModel(engine: speech, defaults: defaults)
            defer { model.shutdown() }
            try await waitFor("failed: preparation to start") { await held.started }
            await held.release()
            try await waitFor("failed: the take to fail") { saved(root)?.status == .failed }
            try check(saved(root)?.failure?.contains("Synthetic saved model could not be read.") == true
                && model.notice?.contains("Transcription failed") == true, "failed: the take fails with the model's reason")
            _ = try? await preparing.value
        }

        // Nothing is preparing: the take fails at once, never a silent queue.
        do {
            let (root, defaults) = try launch("idle")
            let model = ReadbackModel(engine: engine(HeldSpeechPreparation(fails: false), defaults), defaults: defaults)
            defer { model.shutdown() }
            try await waitFor("idle: the take to fail") { saved(root)?.status == .failed }
            try check(saved(root)?.failure?.contains("Open Models to prepare speech first") == true, "idle: with nothing preparing the take fails as before")
        }
        return passed
    }

    /// A cached Parakeet load held open until the check releases it.
    private actor HeldSpeechPreparation {
        private(set) var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        private let fails: Bool
        init(fails: Bool) { self.fails = fails }
        func prepare() async throws {
            await withCheckedContinuation { continuation = $0; started = true }
            if fails { throw RecognitionFailure(kind: .invalidCache, message: "Synthetic saved model could not be read.") }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    @MainActor
    private final class ControlledTranscriber {
        private(set) var calls = 0
        private var pending: [CheckedContinuation<String, Error>] = []

        func transcribe(_ url: URL) async throws -> String {
            calls += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }

        func complete(_ result: String) { pending.removeFirst().resume(returning: result) }
        func fail(_ error: Error) { pending.removeFirst().resume(throwing: error) }
        func cancel() {
            let continuations = pending; pending = []
            for continuation in continuations { continuation.resume(throwing: CancellationError()) }
        }
    }
}
