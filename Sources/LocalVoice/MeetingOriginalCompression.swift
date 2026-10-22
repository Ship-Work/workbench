import AVFoundation
import Foundation

/// A meeting's original tracks are recorded as 16-bit PCM at the device's rate: about 350 MB an
/// hour each at 48 kHz, so a two-sided hour costs about 700 MB, kept until the person removes
/// the meeting. Once its transcript has committed, each track is rewritten in the same file as
/// Apple Lossless. Every sample is kept: the copy is decoded and compared with the original
/// before it replaces it, and nothing replaces a track that does not match. Review recording,
/// Reveal and the saved-audio path read the file through AVFoundation as before. The 16 kHz
/// recognition segments the saved-audio path writes are working copies; nothing reads them
/// once the transcript has committed, so they go too.
enum MeetingOriginalCompression {
    struct Outcome: Equatable {
        var tracks = 0
        var savedBytes: Int64 = 0
    }
    /// One compressor at a time, at background priority: a meeting just committed and the launch
    /// sweep never work on the same file at once, and a pass can clear a quit's leftovers safely.
    private static let queue = DispatchQueue(label: "dev.workbench.meeting-original-compression", qos: .background)
    /// Free space a track must leave beyond its own size, so compressing never brings a recording
    /// near its low-disk stop (MeetingDiskBudget.stopFloorBytes).
    static let spareBytes: Int64 = 512 * 1024 * 1024

    /// The app's entry points: after a meeting commits, and once per launch.
    static func schedule(session: URL) { queue.async { _ = try? tidy(session: session) } }
    static func scheduleSweep(root: URL) { queue.async { sweep(root: root) } }

    /// Compresses the committed meeting's uncompressed tracks and removes its recognition
    /// segments. A meeting that is not committed, or a track that is already compressed,
    /// is left as it is.
    @discardableResult
    static func tidy(session: URL) throws -> Outcome {
        let manifest = try MeetingStore.load(from: session)
        guard manifest.state == .committed else { return Outcome() }
        var outcome = Outcome()
        // A pass that Quit interrupted leaves its unproven copy; the original is still in place.
        let tracks = session.appendingPathComponent(MeetingStore.tracksDirectory, isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: tracks, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix(".lossless-") { try? FileManager.default.removeItem(at: file) }
        for track in manifest.tracks {
            // One unreadable or missing track (a committed meeting may have lost its audio) does not
            // keep the other track or the segments from being tidied.
            guard let url = try? MeetingStore.safeURL(session: session, relative: track.file),
                  let size = try? size(url), (MeetingDiskBudget.availableBytes(at: session) ?? 0) >= size + spareBytes,
                  let saved = try? compress(url) else { continue }
            outcome.tracks += 1; outcome.savedBytes += saved
        }
        let segments = session.appendingPathComponent(MeetingStore.segmentsDirectory, isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: segments, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        where file.pathExtension == "wav" {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let bytes = try size(file)
            try FileManager.default.removeItem(at: file)
            outcome.savedBytes += bytes
        }
        return outcome
    }

    /// Every committed meeting under `root`, for recordings saved before this existed.
    @discardableResult
    static func sweep(root: URL) -> Outcome {
        var total = Outcome()
        for session in MeetingStore.sessions(in: root) {
            guard !Task.isCancelled else { break }
            if let outcome = try? tidy(session: session) {
                total.tracks += outcome.tracks; total.savedBytes += outcome.savedBytes
            }
        }
        return total
    }

    /// Rewrites one PCM track as Apple Lossless in place; returns the bytes saved, or nil when it
    /// was already compressed or the copy did not match. The original stays until the copy is
    /// proven sample for sample.
    static func compress(_ url: URL) throws -> Int64? {
        let original = try AVAudioFile(forReading: url)
        guard formatID(original) == kAudioFormatLinearPCM, original.length > 0 else { return nil }
        let bitDepth = original.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 0
        guard bitDepth == 16 || bitDepth == 24 else { return nil }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".lossless-" + UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return nil }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: original.fileFormat.sampleRate,
                                       AVNumberOfChannelsKey: original.fileFormat.channelCount, AVEncoderBitDepthHintKey: bitDepth]
        let block: AVAudioFrameCount = 65_536
        do {
            let copy = try AVAudioFile(forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: original.processingFormat, frameCapacity: block) else { return nil }
            while original.framePosition < original.length {
                try Task.checkCancellation()
                try original.read(into: buffer, frameCount: min(block, AVAudioFrameCount(original.length - original.framePosition)))
                if buffer.frameLength == 0 { break }
                try copy.write(from: buffer)
            }
        }
        // On disk before it is compared and before it can stand in for the only original.
        try synchronize(temporary)
        guard try matches(url, temporary) else { return nil }
        // Sizes from the file system, not URL resource values, which a URL keeps from its first read.
        let before = try size(url), after = try size(temporary)
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try synchronize(url.deletingLastPathComponent())
        return before - after
    }

    /// Flushes a file, or a folder's entries, through to the disk.
    private static func synchronize(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        if fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func size(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// The file's encoding, read from its settings rather than a pointer into its format.
    static func formatID(_ file: AVAudioFile) -> AudioFormatID {
        (file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value ?? 0
    }

    /// The same frames and the same samples, decoded from both files.
    static func matches(_ first: URL, _ second: URL) throws -> Bool {
        let a = try AVAudioFile(forReading: first), b = try AVAudioFile(forReading: second)
        guard a.length == b.length, a.processingFormat == b.processingFormat,
              let left = AVAudioPCMBuffer(pcmFormat: a.processingFormat, frameCapacity: 65_536),
              let right = AVAudioPCMBuffer(pcmFormat: b.processingFormat, frameCapacity: 65_536) else { return false }
        while a.framePosition < a.length {
            try Task.checkCancellation()
            try a.read(into: left, frameCount: 65_536); try b.read(into: right, frameCount: 65_536)
            guard left.frameLength == right.frameLength, left.frameLength > 0 else { return false }
            for channel in 0..<Int(a.processingFormat.channelCount) {
                guard let l = left.floatChannelData?[channel], let r = right.floatChannelData?[channel],
                      memcmp(l, r, Int(left.frameLength) * MemoryLayout<Float>.size) == 0 else { return false }
            }
        }
        return true
    }
}
