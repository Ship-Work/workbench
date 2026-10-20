import AppKit
import AVFoundation
import CoreAudio
import FluidAudio
import Foundation

/// The real Meetings pipeline on this Mac, for maintainers and agents, with no human, no
/// microphone and no call app: a scratch app with its own bundle identifier plays a synthetic
/// two-voice fixture, the production Core Audio process tap captures it, the cached Parakeet model
/// recognises it live, and `MeetingModel` finishes and saves it exactly as the Meetings page does.
///
/// Run it from the signed Preview so macOS applies that app's Audio Recording permission:
///
///     open -n -W -a "Workbench Preview.app" --args --check-meeting-capture-native NEW_FOLDER [--self-end]
///
/// A refused tap delivers silence rather than an error, so a debug binary without that permission
/// reports the silence as the permission result, not as a transcription failure. `--self-end` lets
/// the player quit instead of pressing Finish, so the meeting ends itself through source loss.
/// Nothing here downloads a model, requests a permission, reads saved work, or writes outside its
/// temporary folder and NEW_FOLDER. The fixture voices are macOS's own, and every name is synthetic.
@MainActor
enum MeetingCaptureNativeCheck {
    static let playerBundleID = "dev.workbench.meeting-fixture-player"
    static let fixtureParts: [String] = [
        "Thanks for joining, Sam. Maya will send the revised agenda before Thursday, and Sam will confirm the room by Friday morning. We agreed to move the launch review to the following week, so quality assurance can sign off first.",
        "Sounds good. The Orchard budget stays where it is, and Avery owns the vendor update. I will share the draft notes after lunch. Any questions before we wrap up? No, that covers everything. Thanks, everyone."
    ]
    static let preferredVoices = ["Daniel", "Samantha", "Karen", "Moira", "Tessa", "Rishi"]
    /// Synthetic voices through a real tap: the limit is a guard against a broken pipeline, not an
    /// accuracy claim. The measured rate is in the receipt either way.
    static let maximumWordErrorRate = 0.30
    static let firstWordsBudgetSeconds = 8.0

    static func run(output: URL, selfEnd: Bool) async throws -> String {
        guard MeetingCoreAudio.isProcessMetadataAvailable else { throw VoiceError.message(MeetingCoreAudio.unavailableReason) }
        guard AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v2), version: .v2) else {
            throw VoiceError.message("The cached Parakeet v2 model is required for this check. No download was started.")
        }
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw VoiceError.message("Use a new output folder: \(output.path) already exists.")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"), FileManager.default.isExecutableFile(atPath: "/usr/bin/say") else {
            throw VoiceError.message("This check compiles its fixture player with the Xcode command line tools and speaks its fixture with /usr/bin/say.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let run = Run(output: output, selfEnd: selfEnd)
        do { try await run.perform() } catch { run.failures.append(error.localizedDescription) }
        await run.cleanUp()
        try run.writeReceipt()
        let summary = run.summary.joined(separator: "\n")
        try summary.write(to: output.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        guard run.failures.isEmpty else {
            throw VoiceError.message("meeting capture native check failed: " + run.failures.joined(separator: "; ") + "\nReceipt: \(output.path)")
        }
        return summary
    }

    /// The whole fixture as the words a transcript should contain, in order.
    static var expectedWords: [String] { words(fixtureParts.joined(separator: " ")) }

    /// Lower case, letters, digits and apostrophes only: punctuation and capitalisation are the
    /// model's choices, not transcription errors.
    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init).filter { !$0.isEmpty }
    }

    /// Word error rate: substitutions, insertions and deletions over the reference length.
    static func wordErrorRate(reference: [String], hypothesis: [String]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        var previous = Array(0...hypothesis.count)
        for (i, word) in reference.enumerated() {
            var current = [i + 1] + [Int](repeating: 0, count: hypothesis.count)
            for (j, candidate) in hypothesis.enumerated() {
                let substitution = previous[j] + (word == candidate ? 0 : 1)
                current[j + 1] = min(substitution, previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        return Double(previous[hypothesis.count]) / Double(reference.count)
    }

    static let playerSource = """
    import AppKit
    import AVFoundation
    import Foundation
    // Workbench meeting fixture player: a scratch app with its own bundle identifier. It prepares the
    // given files, waits for the go file, plays them in order, writes the done file and exits.
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 3 else { exit(2) }
    let goURL = URL(fileURLWithPath: arguments[0]), doneURL = URL(fileURLWithPath: arguments[1])
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let players = try arguments.dropFirst(2).map { try AVAudioPlayer(contentsOf: URL(fileURLWithPath: $0)) }
    for player in players { player.volume = 0.25; player.prepareToPlay() }
    var waited = 0.0
    while !FileManager.default.fileExists(atPath: goURL.path) {
        Thread.sleep(forTimeInterval: 0.1); waited += 0.1
        if waited > 120 { exit(3) }
    }
    for player in players {
        player.play()
        while player.isPlaying { Thread.sleep(forTimeInterval: 0.05) }
        Thread.sleep(forTimeInterval: 0.7)
    }
    try? Data("done".utf8).write(to: doneURL)
    Thread.sleep(forTimeInterval: 0.5)
    exit(0)
    """

    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = RecognitionSnapshot()
        var current: RecognitionSnapshot { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ snapshot: RecognitionSnapshot) { lock.lock(); value = snapshot; lock.unlock() }
    }

    @MainActor private final class Run {
        let output: URL
        let selfEnd: Bool
        let root: URL
        var receipt: [String: Any] = [:]
        var summary: [String] = []
        var failures: [String] = []
        var player: NSRunningApplication?
        var playerProcess: Process?
        var model: MeetingModel?
        var saved: [UUID: Transcript] = [:]
        let started = Date()

        init(output: URL, selfEnd: Bool) {
            self.output = output; self.selfEnd = selfEnd
            // /private/tmp, as the other meeting checks use: the store refuses symbolic links in
            // its paths, and the user temporary folder sits under the /var link.
            root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
                .appendingPathComponent("MeetingCaptureNative-" + UUID().uuidString, isDirectory: true)
        }

        func since(_ date: Date) -> Double { (Date().timeIntervalSince(date) * 1000).rounded() / 1000 }
        func note(_ line: String) { summary.append(line); print(line) }
        func expect(_ condition: Bool, _ label: String) { if !condition { failures.append(label) } ; receipt["check: " + label] = condition }

        func perform() async throws {
            try MeetingStore.createPrivateDirectory(root)
            let build = WorkbenchBuild()
            receipt["build"] = build.details
            receipt["identity"] = Bundle.main.bundleIdentifier ?? "unbundled binary"
            receipt["selfEnd"] = selfEnd
            receipt["macOS"] = ProcessInfo.processInfo.operatingSystemVersionString
            note("Meeting capture native check · \(build.edition) \(build.version) (\(build.number)) · source \(build.revision) · identity \(Bundle.main.bundleIdentifier ?? "unbundled binary")")

            // 1. The fixture: two macOS voices, one file each, spoken at a conversational rate.
            let voices = availableVoices()
            var files: [URL] = []
            for (index, part) in fixtureParts.enumerated() {
                let file = root.appendingPathComponent("fixture-\(index + 1).aiff")
                var arguments = ["-r", "175", "-o", file.path]
                if voices.count > index { arguments = ["-v", voices[index]] + arguments }
                try runTool("/usr/bin/say", arguments + [part])
                files.append(file)
            }
            let fixtureSeconds = try files.reduce(0.0) { total, url in
                let audio = try AVAudioFile(forReading: url)
                return total + Double(audio.length) / audio.fileFormat.sampleRate
            }
            try fixtureParts.joined(separator: "\n\n").write(to: output.appendingPathComponent("fixture.txt"), atomically: true, encoding: .utf8)
            receipt["fixtureVoices"] = voices
            receipt["fixtureSeconds"] = fixtureSeconds
            receipt["fixtureWords"] = expectedWords.count
            note(String(format: "Fixture: %d words, %.1f s, voices %@", expectedWords.count, fixtureSeconds, voices.joined(separator: " and ")))

            // 2. The real recognition engine on an isolated store: cached files only.
            let suite = "dev.workbench.meeting-capture-native." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults))
            let box = SnapshotBox()
            await engine.observe { box.set($0) }
            let preparing = Date()
            try await engine.prepareCached()
            receipt["modelPrepareSeconds"] = since(preparing)
            guard box.current.canTranscribe else { throw VoiceError.message("Parakeet did not become ready from its cache: " + box.current.line) }
            note(String(format: "Parakeet ready from cache in %.1f s", since(preparing)))

            // 3. The player app, compiled here so the process has its own bundle identifier.
            let playerApp = root.appendingPathComponent("MeetingFixturePlayer.app", isDirectory: true)
            let macOS = playerApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("player.swift")
            try playerSource.write(to: source, atomically: true, encoding: .utf8)
            let compiled = Date()
            try runTool("/usr/bin/xcrun", ["swiftc", "-O", source.path, "-o", macOS.appendingPathComponent("MeetingFixturePlayer").path])
            let info: [String: Any] = ["CFBundleIdentifier": playerBundleID, "CFBundleName": "MeetingFixturePlayer",
                                       "CFBundleExecutable": "MeetingFixturePlayer", "CFBundlePackageType": "APPL",
                                       "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "LSUIElement": true,
                                       "NSPrincipalClass": "NSApplication"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: playerApp.appendingPathComponent("Contents/Info.plist"))
            receipt["playerCompileSeconds"] = since(compiled)
            let goURL = root.appendingPathComponent("go"), doneURL = root.appendingPathComponent("done")
            let arguments = [goURL.path, doneURL.path] + files.map(\.path)
            let launched = Date()
            let pid = try await launchPlayer(playerApp, arguments: arguments)
            receipt["playerPID"] = Int(pid)
            note("Fixture player launched: pid \(pid), bundle \(playerBundleID), \(receipt["playerLaunch"] ?? "")")

            // 4. The production meeting owner with its real process source and system capture.
            let meetings = root.appendingPathComponent("Meetings", isDirectory: true)
            let model = MeetingModel(engine: engine, directory: meetings, defaults: defaults)
            self.model = model
            model.hostAdmission = { MeetingHostAdmission(recognition: box.current) }
            model.saveTranscript = { [weak self] transcript, _ in self?.saved[transcript.id] = transcript }
            model.loadSavedTranscript = { [weak self] id in self?.saved[id].map { ($0, []) } }
            var app: MeetingAudioApp?
            let listing = Date()
            while app == nil, since(listing) < 15 {
                model.refreshApps()
                app = model.apps.first { $0.bundleID == playerBundleID && $0.id == pid }
                if app == nil { try await Task.sleep(nanoseconds: 250_000_000) }
            }
            receipt["playerListedSeconds"] = since(launched)
            guard let app else {
                throw VoiceError.message("The fixture player never appeared in Audio source. Apps listed: " + model.apps.map { "\($0.name) (\($0.bundleID))" }.joined(separator: ", ") + ". Enumeration: \(model.appEnumeration)")
            }
            model.selectAudioSource(app.id)
            model.useAppAudioOnly()
            expect(!model.includeMicrophone && model.selectedAppID == app.id, "app audio only is the prepared source")
            expect(model.admission.canStart, "admission allows Start: \(model.admission.title) \(model.admission.captureProblem?.message ?? "")")

            // 5. Start, then let the player speak once the tap is attached.
            let starting = Date()
            await model.start()
            receipt["startSeconds"] = since(starting)
            guard model.isRecording else {
                throw VoiceError.message("Start did not reach recording: " + (model.problem?.message ?? model.error ?? model.notice))
            }
            note(String(format: "Recording after %.2f s · %@", since(starting), model.notice))
            try Data("go".utf8).write(to: goURL)
            let go = Date()
            var firstSound: Double?, firstWords: Double?, phases: [String] = []
            var lastPhase = "", playerOutputSeen = false
            let processSource = MeetingSystemProcessSource()
            func observe() {
                // Core Audio's own metadata says whether the player is producing output, so a silent tap
                // is attributed to the permission and not to a player that never played.
                if !playerOutputSeen, let processes = try? processSource.snapshot(),
                   processes.contains(where: { $0.pid == pid && $0.isRunningOutput }) {
                    playerOutputSeen = true; receipt["playerOutputRunningSeconds"] = since(go)
                }
                let phase = model.voiceSession.phase.rawValue
                if phase != lastPhase { phases.append(String(format: "%.1f %@", since(go), phase)); lastPhase = phase }
                if firstSound == nil, model.voiceSession.sources.contains(where: { $0.source == .app && $0.health == .receiving }) { firstSound = since(go) }
                if firstWords == nil, !model.voiceSession.text.isEmpty { firstWords = since(go) }
            }
            while !FileManager.default.fileExists(atPath: doneURL.path), since(go) < fixtureSeconds + 30 {
                observe()
                if firstSound == nil, since(go) > 10 {
                    // Silence from a tap that was created without error is how macOS refuses capture.
                    await model.cancel()
                    let identity = Bundle.main.bundleIdentifier ?? "unbundled binary"
                    guard playerOutputSeen else {
                        throw VoiceError.message("The fixture player never reported audio output, so the tap could not be judged. Check the player compile and launch in the receipt.")
                    }
                    throw VoiceError.message("The tap delivered only silence for 10 s while the player was producing output. System Audio Recording is not allowed for \(identity): allow it in System Settings › Privacy & Security › Screen & System Audio Recording, or run the check from a signed app that is allowed: open -n -W -a \"Workbench Preview.app\" --args --check-meeting-capture-native NEW_FOLDER")
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            observe()
            receipt["playerDoneSeconds"] = since(go)
            receipt["firstSoundSeconds"] = firstSound ?? -1
            receipt["firstWordsSeconds"] = firstWords ?? -1
            receipt["liveWordsAtDone"] = model.voiceSession.text
            expect(firstSound != nil, "the tap heard the fixture")
            expect(firstWords != nil && (firstWords ?? .infinity) - (firstSound ?? 0) <= firstWordsBudgetSeconds,
                   "live words appeared within \(Int(firstWordsBudgetSeconds)) s of the first sound (first sound \(firstSound ?? -1) s, first words \(firstWords ?? -1) s)")
            note(String(format: "First sound %.2f s after go, first live words %.2f s, player done %.1f s", firstSound ?? -1, firstWords ?? -1, since(go)))

            // 6. End the meeting: Finish, or let the player's exit end it through source loss.
            let ending = Date()
            if selfEnd {
                note("Waiting for the meeting to end itself after the player quits…")
                while model.isBusy, since(ending) < 60 { observe(); try await Task.sleep(nanoseconds: 250_000_000) }
                receipt["selfEndSeconds"] = since(ending)
                expect(!model.isBusy, "a meeting whose source quit ends by itself within 60 s")
            } else {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                await model.stop()
                receipt["finishSeconds"] = since(ending)
            }
            observe()
            receipt["phases"] = phases
            receipt["notice"] = model.notice
            receipt["problem"] = model.problem?.message ?? ""
            receipt["error"] = model.error ?? ""

            // 7. What was saved, judged the way History and Copy transcript would see it.
            guard let id = model.completedTranscriptID else {
                throw VoiceError.message("No completed transcript. Notice: \(model.notice). Problem: \(model.problem?.message ?? "none"). Error: \(model.error ?? "none")")
            }
            guard let transcript = saved[id] else { throw VoiceError.message("History was not asked to save transcript \(id).") }
            let session = MeetingStore.sessionURL(root: meetings, id: id)
            let manifest = try MeetingStore.load(from: session)
            let journal = try? LiveVoiceJournal.load(from: session.appendingPathComponent("live-transcript.json"), sessionID: id)
            let hypothesis = words(transcript.text)
            let rate = wordErrorRate(reference: expectedWords, hypothesis: hypothesis)
            receipt["transcript"] = transcript.text
            receipt["transcriptWords"] = hypothesis.count
            receipt["wordErrorRate"] = rate
            receipt["manifestState"] = manifest.state.rawValue
            receipt["manifestSeconds"] = manifest.seconds
            receipt["manifestFormat"] = manifest.formatVersion
            receipt["tracks"] = manifest.tracks.map { ["source": $0.source.rawValue, "seconds": $0.seconds, "peak": $0.peak, "droppedSeconds": $0.droppedSeconds] }
            receipt["gaps"] = manifest.gaps
            receipt["notes"] = model.pendingTranscriptNotes
            receipt["liveJournalComplete"] = journal?.complete ?? false
            receipt["liveJournalNotes"] = journal?.notes ?? []
            receipt["liveJournalSegments"] = journal?.segments.count ?? 0
            expect(manifest.state == .committed, "the saved meeting is committed")
            expect(manifest.purpose == "meeting", "the saved purpose is meeting")
            expect(manifest.seconds >= fixtureSeconds - 1, "the recording covers the whole fixture (\(manifest.seconds) s recorded for a \(fixtureSeconds) s fixture)")
            expect(manifest.tracks.contains { $0.source == .remote && $0.peak > 0.01 }, "the app track carries sound")
            expect(journal?.complete == true, "the live pass completed without saved-audio fallback (notes: \((journal?.notes ?? []).joined(separator: " | ")))")
            expect(transcript.text == model.completedTranscriptText, "Copy transcript's text is the saved text")
            expect(rate <= maximumWordErrorRate, String(format: "word error rate %.3f is at most %.2f", rate, maximumWordErrorRate))
            if selfEnd {
                expect(model.pendingTranscriptNotes.contains { $0.localizedCaseInsensitiveContains("reconnect") },
                       "the self-ended meeting notes the lost source (notes: \(model.pendingTranscriptNotes.joined(separator: " | ")))")
            }
            note(String(format: "Saved: %@, %.1f s, %d tracks, format %d · live journal complete: %@", manifest.state.rawValue, manifest.seconds, manifest.tracks.count, manifest.formatVersion, journal?.complete == true ? "yes" : "no"))
            note(String(format: "Transcript: %d words, word error rate %.3f (limit %.2f)", hypothesis.count, rate, maximumWordErrorRate))
            note("Transcript text: " + transcript.text)
            if !model.pendingTranscriptNotes.isEmpty { note("Notes: " + model.pendingTranscriptNotes.joined(separator: " | ")) }
            note(failures.isEmpty ? "MEETING_CAPTURE_NATIVE_OK" : "MEETING_CAPTURE_NATIVE_FAILED: " + failures.joined(separator: "; "))
        }

        func cleanUp() async {
            if let model { await model.prepareForShutdown() }
            if let player, !player.isTerminated { _ = player.forceTerminate() }
            if let playerProcess, playerProcess.isRunning { playerProcess.terminate() }
            receipt["elapsedSeconds"] = since(started)
            try? FileManager.default.removeItem(at: root)
        }

        func writeReceipt() throws {
            receipt["failures"] = failures
            receipt["summary"] = summary
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("receipt.json"))
        }

        /// LaunchServices first, so the player is a user-facing app the picker lists; a plain
        /// process otherwise, which the receipt records.
        func launchPlayer(_ app: URL, arguments: [String]) async throws -> Int32 {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = arguments
                configuration.activates = false
                configuration.createsNewApplicationInstance = true
                configuration.promptsUserIfNeeded = false
                let running = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                player = running
                receipt["playerLaunch"] = "LaunchServices"
                return running.processIdentifier
            } catch {
                receipt["playerLaunch"] = "Process (LaunchServices refused: \(error.localizedDescription))"
                let process = Process()
                process.executableURL = app.appendingPathComponent("Contents/MacOS/MeetingFixturePlayer")
                process.arguments = arguments
                try process.run()
                playerProcess = process
                return process.processIdentifier
            }
        }

        func runTool(_ path: String, _ arguments: [String]) throws {
            let process = Process(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw VoiceError.message("\(path) \(arguments.prefix(2).joined(separator: " ")) failed (\(process.terminationStatus)): " + (String(data: stderr, encoding: .utf8) ?? ""))
            }
        }

        func availableVoices() -> [String] {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", "?"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let installed = Set((String(data: data, encoding: .utf8) ?? "").split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) })
            return Array(preferredVoices.filter(installed.contains).prefix(2))
        }
    }
}
