import AVFoundation
import FluidAudio
import Foundation

/// Developer check, not part of the default suite: how long Finish takes to a saved transcript.
/// Two recorded lanes stand in for the microphone and the call app, played at 48 kHz, as a call
/// app's tap delivers, at `speed` times real time through the production meeting owner, live pass,
/// cached Parakeet and saved-transcript commit. No device, tap, permission or download is touched,
/// and History is an in-memory stand-in. Each lane may have a `.txt` beside it with what was said,
/// and the saved conversation is then scored against it.
@MainActor
enum MeetingFinishCheck {
    static func run(microphone: URL, app: URL, output: URL, speed: Double) async throws -> [String] {
        guard AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v2), version: .v2) else {
            throw VoiceError.message("The cached Parakeet v2 model is required for this check. No download was started.")
        }
        guard (1...20).contains(speed) else { throw VoiceError.message("Play the lanes at 1 to 20 times real time.") }
        let converter = AudioConverter()
        let lanes = [MeetingTrackSource.local: upsampled(try converter.resampleAudioFile(microphone)),
                     .remote: upsampled(try converter.resampleAudioFile(app))]
        var lines: [String] = []
        // An absolute path keeps the settings in the check's own folder, not ~/Library/Preferences (#128).
        let defaults = UserDefaults(suiteName: output.appendingPathComponent("Preferences").path)!
        let engine = RecognitionEngine(store: RecognitionConfigurationStore(defaults: defaults))
        let preparing = Date()
        try await engine.prepareCached()
        let ready = await engine.snapshot()
        guard ready.canTranscribe else { throw VoiceError.message("Parakeet did not become ready from its cache: " + ready.line) }
        lines.append(String(format: "Parakeet ready from cache in %.1f s", Date().timeIntervalSince(preparing)))

        let process = Processes(), capture = PlaybackCapture(lanes: lanes, speed: speed)
        let meetings = output.appendingPathComponent("Meetings", isDirectory: true)
        let model = MeetingModel(directory: meetings, defaults: defaults, processSource: process,
            transcribe: { try await engine.transcribe($0) }, microphonePermission: { true }, captureFactory: { capture },
            readSpeechSnapshot: { await engine.snapshot() })
        model.liveEngine = engine
        var saved: [UUID: Transcript] = [:]
        model.saveTranscript = { transcript, _ in saved[transcript.id] = transcript }
        model.loadSavedTranscript = { id in saved[id].map { ($0, []) } }
        model.refreshApps()
        model.selectedAppID = Processes.call.pid; model.includeMicrophone = true
        await model.start()
        guard model.isRecording else { throw VoiceError.message("Start did not reach recording: " + (model.problem?.message ?? model.notice)) }
        let seconds = lanes.values.map { Double($0.count) / PlaybackCapture.rate }.max() ?? 0
        while !capture.played { try await Task.sleep(nanoseconds: 100_000_000) }
        lines.append(String(format: "Played %.0f s of meeting at %.0f× real time; live words then: %d", seconds, speed, model.voiceSession.segments.count))

        let finishing = Date()
        await model.stop()
        let finish = Date().timeIntervalSince(finishing)
        guard let id = model.completedTranscriptID, let transcript = saved[id] else {
            throw VoiceError.message("No saved transcript. Notice: \(model.notice). Problem: \(model.problem?.message ?? "none")")
        }
        let session = MeetingStore.sessionURL(root: meetings, id: id)
        let journal = try? LiveVoiceJournal.load(from: session.appendingPathComponent("live-transcript.json"), sessionID: id)
        let manifest = try MeetingStore.load(from: session)
        lines.append(String(format: "Finish to saved transcript: %.2f s · live words used: %@ · %@", finish,
                            manifest.liveText != nil ? "yes" : "no, the saved audio was transcribed again", manifest.state.rawValue))
        if let journal, !journal.notes.isEmpty { lines.append("Live notes: " + journal.notes.joined(separator: " | ")) }
        for (source, speaker) in [(MeetingTrackSource.local, "You"), (.remote, "Others")] {
            let lane = source == .local ? microphone : app
            guard let said = try? String(contentsOf: lane.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8) else { continue }
            let heard = transcript.text.components(separatedBy: "\n\n").filter { $0.hasPrefix(speaker + ": ") }
                .map { String($0.dropFirst(speaker.count + 2)) }.joined(separator: " ")
            let reference = MeetingCaptureNativeCheck.words(said)
            lines.append(String(format: "%@: word error rate %.2f%% over %d words", speaker,
                                MeetingCaptureNativeCheck.wordErrorRate(reference: reference, hypothesis: MeetingCaptureNativeCheck.words(heard)) * 100, reference.count))
        }
        try transcript.text.write(to: output.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        await model.prepareForShutdown()
        return lines
    }

    /// 16 kHz to 48 kHz by straight lines between samples: enough to exercise the resampling a
    /// real tap's audio goes through, without adding sound of its own.
    private static func upsampled(_ samples: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count * 3)
        for index in samples.indices {
            let next = index + 1 < samples.count ? samples[index + 1] : samples[index]
            for step in 0..<3 { result[index * 3 + step] = samples[index] + (next - samples[index]) * Float(step) / 3 }
        }
        return result
    }

    /// One call app for the picker, so Start records both the microphone and the app.
    private final class Processes: MeetingProcessSource {
        static let call = MeetingProcessSnapshot(pid: 4_242, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true)
        var isAvailable: Bool { true }
        var unavailableReason: String { "" }
        var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
        func snapshot() throws -> [MeetingProcessSnapshot] { [Self.call] }
    }

    /// Writes each lane as the original a real capture would (16-bit CAF with its timing record)
    /// while handing the same samples to the live pass, in 100 ms steps of `speed` times real time.
    private final class PlaybackCapture: MeetingCapture, @unchecked Sendable {
        static let rate = 48_000.0
        private let lanes: [MeetingTrackSource: [Float]]
        private let speed: Double
        private let lock = NSLock()
        private var position = 0, stopping = false, done = false
        private var task: Task<MeetingCaptureReport, Never>?
        init(lanes: [MeetingTrackSource: [Float]], speed: Double) { self.lanes = lanes; self.speed = speed }
        var played: Bool { lock.lock(); defer { lock.unlock() }; return done }
        var elapsedSeconds: Double { lock.lock(); defer { lock.unlock() }; return Double(position) / Self.rate }
        var stopReason: String? { nil }
        func requestStop() { lock.lock(); stopping = true; lock.unlock() }

        func start(_ request: MeetingCaptureRequest) async throws {
            try MeetingStore.createPrivateDirectory(request.tracksDirectory)
            let rate = Self.rate
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                           AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
            let files = Files()
            for source in lanes.keys {
                let url = request.tracksDirectory.appendingPathComponent("\(source.rawValue).caf")
                try MeetingStore.writePrivate(JSONEncoder().encode(MeetingTrackTiming(source: source, startSeconds: 0, sampleRate: rate)),
                                              to: url.deletingPathExtension().appendingPathExtension("json"))
                files.open[source] = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            }
            let lanes = lanes, step = Int(rate * 0.1 * speed), total = lanes.values.map(\.count).max() ?? 0
            let onAudio = request.onAudio
            task = Task.detached { [self] in
                var written = 0
                while written < total {
                    lock.lock(); let stop = stopping; lock.unlock()
                    if stop { break }
                    let end = min(total, written + step)
                    for (source, samples) in lanes {
                        let chunk = Array(samples[min(written, samples.count)..<min(end, samples.count)])
                        guard !chunk.isEmpty, let file = files.open[source],
                              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk.count)) else { continue }
                        buffer.frameLength = AVAudioFrameCount(chunk.count)
                        chunk.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: chunk.count) }
                        try? file.write(from: buffer)
                        onAudio?(MeetingAudioChunk(source: source, samples: chunk, sampleRate: rate, startSeconds: Double(written) / rate))
                    }
                    written = end
                    lock.lock(); position = written; lock.unlock()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                lock.lock(); done = true; lock.unlock()
                var tracks: [MeetingTrack] = []
                for (source, samples) in lanes.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    let seconds = Double(min(samples.count, written)) / rate
                    tracks.append(MeetingTrack(source: source, file: MeetingStore.tracksDirectory + "/\(source.rawValue).caf", startSeconds: 0,
                                               seconds: seconds, sampleRate: rate, peak: Double(samples.map { abs($0) }.max() ?? 0), droppedSeconds: 0))
                }
                // Releasing the files writes their headers before Finish reads them.
                files.open.removeAll()
                return MeetingCaptureReport(tracks: tracks, seconds: tracks.map(\.seconds).max() ?? 0)
            }
        }
        func finish() async -> MeetingCaptureReport {
            requestStop()
            return await task?.value ?? MeetingCaptureReport()
        }
        private final class Files: @unchecked Sendable { var open: [MeetingTrackSource: AVAudioFile] = [:] }
    }
}
