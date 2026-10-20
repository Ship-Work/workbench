import AVFoundation
import Foundation

/// Turns a two-track meeting into a conversation: "You" from the microphone and
/// "Others" from the chosen app's audio. Each track is split into utterances by
/// loudness, each utterance is recognised on its own, and the microphone's copy
/// of the other side (laptop speakers) is dropped when it repeats their words
/// at the same time. Best effort only: the mixed transcript stays the original
/// wording, and any failure keeps it as the saved text.
enum MeetingConversation {
    enum Speaker: String, Sendable { case you = "You", others = "Others" }

    struct Utterance: Equatable, Sendable {
        var speaker: Speaker
        var start: Double
        var end: Double
        var text: String
    }

    struct UtteranceFile: Sendable {
        var speaker: Speaker
        var start: Double
        var end: Double
        var url: URL
    }

    static let frameSeconds = 0.03
    static let minimumSpeechSeconds = 0.4
    /// Live words are cut into utterances by the same two values, so both paths order turns alike.
    static let joinSilenceSeconds = SpeakerEcho.pauseSeconds
    static let maximumUtteranceSeconds = SpeakerEcho.longestSeconds
    static let maximumUtterances = 2_000
    static let preRollFrames = 8
    /// Short utterances are padded so every recogniser gets a usable clip.
    static let minimumFileSeconds = 1.0

    /// Streams one preserved track on the shared meeting timeline and writes each
    /// utterance as a private 16 kHz mono WAV. Memory holds one utterance at most.
    static func writeUtterances(track: MeetingTrack, session: URL, speaker: Speaker, directory: URL) throws -> [UtteranceFile] {
        let rate = MeetingSegmentPlan.sampleRate
        let frame = Int(rate * frameSeconds)
        let source = try MeetingStore.safeURL(session: session, relative: track.file)
        let reader = try MeetingTrackReader(url: source, startSeconds: track.startSeconds, blockFrames: 8_192)
        var remaining = Int(((track.startSeconds + track.seconds) * rate).rounded())
        var samples = [Float](repeating: 0, count: frame)
        var preRoll: [[Float]] = [], current: [Float] = [], speechFrames = 0, silentRun = 0
        var frameIndex = 0, startFrame = 0, files: [UtteranceFile] = []
        var floor: Float = -60

        func finish() throws {
            defer { current.removeAll(keepingCapacity: true); speechFrames = 0; silentRun = 0 }
            let kept = current.count - silentRun * frame
            guard Double(speechFrames) * frameSeconds >= minimumSpeechSeconds, kept > 0 else { return }
            guard files.count < maximumUtterances else {
                throw MeetingError.message("This recording has too many separate utterances to label speakers.")
            }
            let start = Double(startFrame) * frameSeconds
            let end = start + Double(kept) / rate
            let url = directory.appendingPathComponent(String(format: "%@-%07d.wav", speaker.rawValue.lowercased(), Int(start * 1_000)))
            try write(Array(current.prefix(kept)), to: url)
            files.append(UtteranceFile(speaker: speaker, start: start, end: end, url: url))
        }

        while remaining > 0 {
            let count = min(frame, remaining)
            try reader.read(count, into: &samples)
            remaining -= count
            var sum: Float = 0
            for index in 0..<count { sum += samples[index] * samples[index] }
            let level = 20 * log10(max((sum / Float(max(count, 1))).squareRoot(), 1e-9))
            // An adaptive floor follows the track's own quiet level, so speech
            // stands out on a hot headset or a distant laptop microphone alike.
            floor = level < floor ? level : floor + (level - floor) * 0.001
            let speech = level > max(floor + 12, -50)
            let chunk = Array(samples.prefix(count))
            if current.isEmpty {
                if speech {
                    startFrame = frameIndex - preRoll.count
                    current = preRoll.flatMap { $0 } + chunk
                    speechFrames = 1; silentRun = 0
                }
            } else {
                current += chunk
                if speech { speechFrames += 1; silentRun = 0 } else { silentRun += 1 }
                if Double(silentRun) * frameSeconds >= joinSilenceSeconds || Double(current.count) / rate >= maximumUtteranceSeconds {
                    try finish()
                }
            }
            preRoll.append(chunk)
            if preRoll.count > preRollFrames { preRoll.removeFirst() }
            frameIndex += 1
        }
        if !current.isEmpty { try finish() }
        return files
    }

    private static func write(_ samples: [Float], to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw MeetingError.message("A private speaker clip could not be created.")
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: MeetingSegmentPlan.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let length = max(samples.count, Int(minimumFileSeconds * MeetingSegmentPlan.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(length)),
              let channel = buffer.floatChannelData?[0] else {
            throw MeetingError.message("A speaker clip buffer could not be allocated.")
        }
        buffer.frameLength = AVAudioFrameCount(length)
        for index in 0..<length { channel[index] = index < samples.count ? samples[index] : 0 }
        try file.write(from: buffer)
    }

    /// On laptop speakers the microphone also hears the other side. Drop a "You" utterance
    /// that mostly overlaps an "Others" utterance and repeats its words (SpeakerEcho.isEcho):
    /// a fragment of three words or more inside a long utterance is dropped as well (#377).
    static func withoutEchoes(_ utterances: [Utterance]) -> [Utterance] {
        func heard(_ utterance: Utterance) -> SpeakerEcho.Utterance { .init(start: utterance.start, end: utterance.end, text: utterance.text) }
        let mine = utterances.indices.filter { utterances[$0].speaker == .you }
        let echoes = SpeakerEcho.echoes(mine.map { heard(utterances[$0]) }, of: utterances.filter { $0.speaker == .others }.map(heard))
        let dropped = Set(zip(mine, echoes).compactMap { $1 ? $0 : nil })
        return utterances.indices.filter { !dropped.contains($0) }.map { utterances[$0] }
    }

    /// Chronological turns; a speaker's consecutive utterances join into one turn across any
    /// pause shorter than the one live turns use (LiveVoiceTurns.pauseSeconds).
    static func conversation(_ utterances: [Utterance]) -> String {
        var turns: [(speaker: Speaker, text: String, end: Double)] = []
        let ordered = withoutEchoes(utterances).sorted { ($0.start, $0.speaker.rawValue) < ($1.start, $1.speaker.rawValue) }
        for utterance in ordered {
            let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = turns.last, last.speaker == utterance.speaker, utterance.start - last.end < LiveVoiceTurns.pauseSeconds {
                turns[turns.count - 1] = (last.speaker, last.text + " " + text, utterance.end)
            } else {
                turns.append((utterance.speaker, text, utterance.end))
            }
        }
        return turns.map { "\($0.speaker.rawValue): \($0.text)" }.joined(separator: "\n\n")
    }
}
