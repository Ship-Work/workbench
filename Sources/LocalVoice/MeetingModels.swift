import Darwin
import Foundation

/// One audio-producing application the person can explicitly choose. A browser
/// entry covers that browser's whole audio output, including every tab in it.
struct MeetingAudioApp: Identifiable, Hashable {
    /// The process identifier. It is stable only while the app keeps running.
    var id: Int32
    var name: String
    var bundleID: String
}

enum MeetingAppKind: String, Codable {
    case communication, browser
}

/// Only apps in this catalogue are considered by detection. Nothing
/// here inspects window titles, page contents or the browser's automation API.
struct MeetingKnownApp {
    let bundleID: String
    let name: String
    let kind: MeetingAppKind
    /// The app's own audio processes that are not named `<bundle>.helper`, such
    /// as new Teams' module host.
    var audioProcesses: [String] = []
    /// Shared helpers that play this app's sound for it: Safari's page and call audio plays in
    /// WebKit's media process, not in Safari. A helper belongs to the app only when macOS holds
    /// the app responsible for it (MeetingResponsibleApp), so Mail's or another app's WebKit
    /// audio never reads as Safari's (#377).
    var hostedHelpers: [String] = []
    /// The system service that plays this app's call audio: FaceTime and Phone calls play in the
    /// Mac calling service. Recording the app taps that service too. It carries any call on this
    /// Mac, so it is never merged into the app and stays its own source in the picker (#377).
    var callAudioServices: [String] = []

    /// Bundle identifiers compare without case: macOS reports each app's
    /// declared spelling, and the Phone app declares `com.apple.mobilephone`.
    func owns(_ processBundleID: String) -> Bool {
        let process = processBundleID.lowercased()
        return ([bundleID] + audioProcesses).contains { owner in
            let owner = owner.lowercased()
            return process == owner || process.hasPrefix(owner + ".helper")
        }
    }
}

enum MeetingAppCatalogue {
    /// Remote-stream capture from these apps has not been verified on real hardware;
    /// nothing here may claim a verified two-sided recording.
    static let supported: [MeetingKnownApp] = [
        MeetingKnownApp(bundleID: "us.zoom.xos", name: "Zoom", kind: .communication),
        MeetingKnownApp(bundleID: "com.microsoft.teams", name: "Microsoft Teams", kind: .communication),
        MeetingKnownApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams", kind: .communication,
                        audioProcesses: ["com.microsoft.teams2.modulehost"]),
        MeetingKnownApp(bundleID: "com.cisco.webexmeetingsapp", name: "Webex", kind: .communication),
        MeetingKnownApp(bundleID: "com.webex.meetingmanager", name: "Webex Meetings", kind: .communication),
        MeetingKnownApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", kind: .communication),
        MeetingKnownApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", kind: .communication),
        MeetingKnownApp(bundleID: "com.hnc.Discord", name: "Discord", kind: .communication),
        MeetingKnownApp(bundleID: "com.skype.skype", name: "Skype", kind: .communication),
        MeetingKnownApp(bundleID: "com.ringcentral.glip", name: "RingCentral", kind: .communication),
        MeetingKnownApp(bundleID: "com.gotomeeting.GoToMeeting", name: "GoTo Meeting", kind: .communication),
        MeetingKnownApp(bundleID: "com.apple.FaceTime", name: "FaceTime", kind: .communication,
                        callAudioServices: ["com.apple.avconferenced"]),
        MeetingKnownApp(bundleID: "com.apple.mobilephone", name: "Phone", kind: .communication,
                        callAudioServices: ["com.apple.avconferenced"]),
        MeetingKnownApp(bundleID: "com.google.Chrome", name: "Google Chrome", kind: .browser),
        MeetingKnownApp(bundleID: "com.apple.Safari", name: "Safari", kind: .browser,
                        hostedHelpers: ["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"]),
        MeetingKnownApp(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", kind: .browser),
        MeetingKnownApp(bundleID: "company.thebrowser.Browser", name: "Arc", kind: .browser),
        MeetingKnownApp(bundleID: "org.mozilla.firefox", name: "Firefox", kind: .browser),
        MeetingKnownApp(bundleID: "com.brave.Browser", name: "Brave", kind: .browser),
        MeetingKnownApp(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", kind: .browser),
        MeetingKnownApp(bundleID: "com.operasoftware.Opera", name: "Opera", kind: .browser)
    ]

    /// Never list, tap or detect Workbench itself, in any edition.
    static let excludedBundleIDs: Set<String> = [
        "com.ethdawg.workbench", "com.ethdawg.workbench.preview",
        "com.ethdawg.localvoice", "com.ethdawg.stagemark"
    ]

    /// Existing Mac audio-service sources stay manually selectable by their own
    /// PID and bundle. These labels never enable detection or become an app's
    /// choice. FaceTime and Phone also tap the calling service, where their calls
    /// play; Safari takes only the WebKit helpers macOS holds it responsible for,
    /// and every other app's WebKit audio stays here as the shared service (#377).
    /// Receiver support needs testing.
    static let manualServiceNames = [
        "com.apple.avconferenced": "Mac calling service",
        "com.apple.TelephonyUtilities": "Mac telephony service",
        "com.apple.WebKit.GPU": "WebKit audio service (shared)"
    ]

    /// Observed call activity on this Mac ran through this exact service.
    /// Two-way activity can offer a possible call, not prove its type or that
    /// both sides are recordable. Its capture scope stays separate from apps.
    static let callServiceBundleIDs: Set<String> = ["com.apple.avconferenced"]

    static func known(_ bundleID: String) -> MeetingKnownApp? {
        supported.first { $0.owns(bundleID) }
    }

    /// The catalogue app a process belongs to: its own process or helper, or a shared helper
    /// macOS holds that app responsible for. Without a responsible app a shared helper belongs
    /// to no app, so the honest result when attribution is unavailable is the shared service.
    static func known(_ bundleID: String, responsibleBundleID: String?) -> MeetingKnownApp? {
        if let app = known(bundleID) { return app }
        guard let responsibleBundleID, let host = known(responsibleBundleID),
              host.hostedHelpers.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) else { return nil }
        return host
    }

    /// The source a process is listed, offered and captured under: its app, else its own bundle.
    static func owner(_ bundleID: String, responsibleBundleID: String?) -> String {
        known(bundleID, responsibleBundleID: responsibleBundleID)?.bundleID ?? bundleID
    }

    /// Only these processes need their responsible app read; every other process costs nothing more.
    static func isHostedHelper(_ bundleID: String) -> Bool {
        supported.contains { $0.hostedHelpers.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame } }
    }

    /// Whether recording `appBundleID` taps this process: everything listed under that source,
    /// and the service that plays its calls (#377). FaceTime and Phone tapped only their own
    /// processes before, which hold none of a call's audio.
    static func taps(_ bundleID: String, responsibleBundleID: String?, for appBundleID: String) -> Bool {
        if owner(bundleID, responsibleBundleID: responsibleBundleID) == appBundleID { return true }
        return known(appBundleID)?.callAudioServices.contains(bundleID) == true
    }

    static func isExcluded(_ bundleID: String) -> Bool {
        if excludedBundleIDs.contains(bundleID) { return true }
        return bundleID == Bundle.main.bundleIdentifier || excludedBundleIDs.contains(where: { bundleID.hasPrefix($0 + ".") })
    }
}

enum MeetingError: LocalizedError {
    case message(String)
    case futureFormat(Int)
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .futureFormat(let version):
            return "This meeting recording uses format \(version); this Workbench supports format \(MeetingManifest.currentFormat). Its folder was left unchanged."
        case .unsafePath:
            return "The meeting folder contains an unsafe path or a symbolic link. It was left unchanged."
        }
    }
}

enum MeetingTrackSource: String, Codable, Hashable, Sendable {
    case remote, local
}

/// One preserved original track, written straight through during capture.
struct MeetingTrack: Codable, Equatable, Sendable {
    var source: MeetingTrackSource
    var file: String
    /// Seconds between the session's host-clock reference and this track's first
    /// sample. Mixing uses it so neither side is shifted onto the other.
    var startSeconds: Double
    var seconds: Double
    var sampleRate: Double
    var peak: Double
    /// Audio the bounded capture buffer could not keep. Reported, never hidden.
    var droppedSeconds: Double
}

/// One bounded chunk of the mixed timeline, sized for the shared engine.
struct MeetingSegment: Codable, Equatable, Sendable {
    var index: Int
    var file: String
    var startSeconds: Double
    var seconds: Double
    var bytes: Int
    /// Filled once this chunk is recognised. A retry resumes at the first nil.
    var text: String?
}

enum MeetingState: String, Codable, Sendable {
    /// Capture is in progress, or the app stopped before it could finish.
    case recording
    /// Originals are complete; segments are not planned yet.
    case stopped
    /// Segments exist; some may already carry text.
    case segmented
    /// Every segment has text; the transcript is not in history yet.
    case recognized
    /// The transcript is in history under this same identifier.
    case committed
}

struct MeetingManifest: Codable, Equatable, Sendable {
    static let currentFormat = 2
    // Ordinary recordings retain format 1. Only a finalized live transcript needs format 2.
    var formatVersion = 1
    /// Also the saved transcript's identifier, so a retry can never duplicate it.
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var purpose: String
    var appName: String?
    var appBundleID: String?
    var includesMicrophone: Bool
    var includesRemote: Bool
    var state: MeetingState
    var seconds: Double
    var tracks: [MeetingTrack] = []
    var segments: [MeetingSegment] = []
    /// Plain sentences about missing, quiet or interrupted audio.
    var gaps: [String] = []
    var failure: String?
    var liveText: String? = nil

    var orderedSegments: [MeetingSegment] { segments.sorted { $0.index < $1.index } }
    var recognizedText: String {
        if let liveText { return liveText }
        return orderedSegments.compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    var isFullyRecognized: Bool {
        guard hasValidTimeline else { return false }
        if liveText != nil { return formatVersion == 2 }
        return hasCompleteSegmentPlan && segments.allSatisfy { $0.text != nil }
    }
    var timelineSeconds: Double { tracks.map { $0.startSeconds + $0.seconds }.max() ?? 0 }
    /// A declared duration cannot hide a missing tail or a plan truncated at the cap.
    var hasValidTimeline: Bool {
        !tracks.isEmpty && timelineSeconds.isFinite && timelineSeconds > 0
            && timelineSeconds <= MeetingSegmentPlan.maximumMeetingSeconds
            && abs(seconds - timelineSeconds) < 0.001
    }
    var hasCompleteSegmentPlan: Bool {
        guard hasValidTimeline else { return false }
        let expected = MeetingSegmentPlan.plan(totalSeconds: timelineSeconds)
        guard !expected.isEmpty, expected.count == segments.count else { return false }
        return zip(orderedSegments, expected).allSatisfy { segment, window in
            segment.index == window.index && abs(segment.startSeconds - window.start) < 0.001
                && abs(segment.seconds - window.seconds) < 0.001
        }
    }
    /// Anything that still holds audio the person has not received text for. A recording that
    /// was recognised to the end without a word is finished, not unfinished: retrying it only
    /// repeats the empty result and, by rewriting it, hid older recordings behind it.
    var needsRecovery: Bool {
        state != .committed && !isSettledWithoutSpeech
            && (state == .recording || seconds > 0 || !tracks.isEmpty || !segments.isEmpty)
    }
    /// Recognised to the end with no words, or too short to hold any. Its audio stays on this
    /// Mac until the person shows or removes it; nothing offers to retry it.
    var isSettledWithoutSpeech: Bool {
        guard recognizedText.isEmpty, hasValidTimeline else { return false }
        // No recognition was possible. Keep the ordinary stopped shape readable
        // by older binaries, while this reader avoids offering pointless retry.
        if [.stopped, .recognized].contains(state), timelineSeconds < MeetingSegmentPlan.minimumSegmentSeconds,
           segments.isEmpty { return true }
        return state == .recognized && isFullyRecognized
    }
}

/// Sizes for the shared recognition engine. A meeting is chunked so no request
/// approaches the 30-minute or 64 MB limits the ordinary Dictate path enforces.
enum MeetingSegmentPlan {
    static let sampleRate = 16_000.0
    static let bytesPerSecond = 32_000
    static let maximumSegmentSeconds = 600.0
    static let maximumSegmentBytes = 64 * 1024 * 1024
    static let maximumMeetingSeconds = 7_200.0
    static let minimumSegmentSeconds = 0.5

    struct Window: Equatable {
        var index: Int
        var start: Double
        var seconds: Double
        var bytes: Int { Int((seconds * Double(bytesPerSecond)).rounded()) }
    }

    /// The longest chunk that satisfies both the duration and the byte bound.
    static var segmentSeconds: Double {
        min(maximumSegmentSeconds, Double(maximumSegmentBytes) / Double(bytesPerSecond))
    }

    static func plan(totalSeconds: Double) -> [Window] {
        guard totalSeconds.isFinite, totalSeconds >= minimumSegmentSeconds else { return [] }
        let total = min(totalSeconds, maximumMeetingSeconds)
        let chunk = segmentSeconds
        var windows: [Window] = []
        var start = 0.0
        while start < total {
            let seconds = min(chunk, total - start)
            // Borrow from the previous window so even a short tail stays
            // transcribable without exceeding the ten-minute request bound.
            if seconds < minimumSegmentSeconds, var last = windows.popLast() {
                let borrowed = minimumSegmentSeconds - seconds
                last.seconds -= borrowed
                windows.append(last)
                windows.append(Window(index: windows.count, start: start - borrowed,
                                      seconds: minimumSegmentSeconds))
            } else {
                windows.append(Window(index: windows.count, start: start, seconds: seconds))
            }
            start += chunk
        }
        return windows
    }

    static func filename(index: Int) -> String {
        MeetingStore.segmentsDirectory + "/" + String(format: "segment-%04d.wav", index)
    }
}

/// Space checks are deliberately blunt: they refuse to start a long recording on
/// a nearly full disk and stop safely rather than corrupt an original track.
enum MeetingDiskBudget {
    static let requiredStartBytes: Int64 = 512 * 1024 * 1024
    static let stopFloorBytes: Int64 = 192 * 1024 * 1024
    /// The bounded live buffer each track keeps before it reports dropped audio.
    static let captureBufferSeconds = 8.0

    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacityForImportantUsage { return capacity }
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
        return free.int64Value
    }

    static func checkStartSpace(at url: URL) throws {
        guard let available = availableBytes(at: url) else { return }
        guard available >= requiredStartBytes else {
            throw MeetingError.message("There is not enough free disk space to record a meeting safely. Free about 500 MB and try again.")
        }
    }
}

/// One app-managed Meetings root. Each session owns a UUID directory holding a
/// versioned manifest, its original tracks and its bounded segments. Nothing
/// here deletes a session. Confirmed transcript removal uses
/// MeetingTranscriptRemoval to coordinate its recording with saved history.
enum MeetingStore {
    static let manifestName = "meeting.json"
    static let tracksDirectory = "tracks"
    static let segmentsDirectory = "segments"
    static let maximumManifestBytes = 4 * 1024 * 1024

    static func sessionURL(root: URL, id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    static func create(root: URL, manifest: MeetingManifest) throws -> URL {
        try createPrivateDirectory(root)
        let session = sessionURL(root: root, id: manifest.id)
        guard !FileManager.default.fileExists(atPath: session.path) else {
            throw MeetingError.message("A meeting folder with this identifier already exists. It was left unchanged.")
        }
        try createPrivateDirectory(session)
        try createPrivateDirectory(session.appendingPathComponent(tracksDirectory, isDirectory: true))
        try createPrivateDirectory(session.appendingPathComponent(segmentsDirectory, isDirectory: true))
        try save(manifest, at: session)
        return session
    }

    static func load(from session: URL) throws -> MeetingManifest {
        try loadCheckpoint(from: session).manifest
    }

    static func loadCheckpoint(from session: URL) throws -> (manifest: MeetingManifest, bytes: Data) {
        let url = try safeURL(session: session, relative: manifestName)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= maximumManifestBytes else {
            throw MeetingError.message("The meeting record could not be read safely. Its folder was left unchanged.")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        guard data.count <= maximumManifestBytes else { throw MeetingError.message("The meeting record grew while being read. Its folder was left unchanged.") }
        let manifest: MeetingManifest
        do { manifest = try decoder.decode(MeetingManifest.self, from: data) }
        catch {
            throw MeetingError.message("The meeting record could not be read. Its folder and audio were left unchanged. \(error.localizedDescription)")
        }
        // A newer Workbench may have written this. Read nothing else from it.
        guard (1...MeetingManifest.currentFormat).contains(manifest.formatVersion) else {
            throw MeetingError.futureFormat(manifest.formatVersion)
        }
        guard manifest.id.uuidString == session.lastPathComponent else {
            throw MeetingError.message("The meeting record does not match its folder. It was left unchanged.")
        }
        try validate(manifest, at: session)
        return (manifest, data)
    }

    /// A staged sibling plus one atomic rename: a failed write leaves the
    /// previous durable record intact rather than a truncated one.
    static func save(_ manifest: MeetingManifest, at session: URL, replacing previous: MeetingManifest? = nil) throws {
        try validate(manifest, at: session)
        guard (1...MeetingManifest.currentFormat).contains(manifest.formatVersion) else {
            throw MeetingError.futureFormat(manifest.formatVersion)
        }
        let url = try safeURL(session: session, relative: manifestName)
        if FileManager.default.fileExists(atPath: url.path) {
            guard let previous, try Data(contentsOf: url) == encoded(previous) else {
                throw MeetingError.message("The meeting record changed outside this operation. It was left unchanged; retry after checking its folder.")
            }
        } else if previous != nil {
            throw MeetingError.message("The meeting record was moved or removed. Its audio was left unchanged.")
        }
        let data = try encoded(manifest)
        if let previous, previous.formatVersion == 1, manifest.formatVersion == 2 {
            let backup = try safeURL(session: session, relative: "meeting-v1.json")
            let original = try encoded(previous)
            if FileManager.default.fileExists(atPath: backup.path) {
                guard try Data(contentsOf: backup) == original else {
                    throw MeetingError.message("The previous-format meeting backup changed. Original audio was kept.")
                }
            } else { try writePrivate(original, to: backup) }
        }
        try writePrivate(data, to: url)
    }

    private static func encoded(_ value: MeetingManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard data.count <= maximumManifestBytes else {
            throw MeetingError.message("The meeting record grew beyond its safe size and was not written.")
        }
        return data
    }

    private static func validate(_ manifest: MeetingManifest, at session: URL) throws {
        guard manifest.liveText == nil || manifest.formatVersion == 2 else {
            throw MeetingError.message("A live meeting transcript requires its matching record format.")
        }
        guard manifest.id.uuidString == session.lastPathComponent,
              ["meeting", "call"].contains(manifest.purpose),
              manifest.seconds.isFinite, manifest.seconds >= 0,
              manifest.seconds <= MeetingSegmentPlan.maximumMeetingSeconds + 60,
              manifest.tracks.count <= 2, manifest.segments.count <= 13 else {
            throw MeetingError.message("The meeting record has an out-of-range duration and was not written.")
        }
        var sources = Set<MeetingTrackSource>()
        for track in manifest.tracks {
            guard sources.insert(track.source).inserted,
                  track.file == "\(tracksDirectory)/\(track.source.rawValue).caf",
                  track.startSeconds.isFinite, track.startSeconds >= 0,
                  track.seconds.isFinite, track.seconds >= 0,
                  track.startSeconds + track.seconds <= MeetingSegmentPlan.maximumMeetingSeconds + 60,
                  track.sampleRate.isFinite, (8_000...192_000).contains(track.sampleRate),
                  track.peak.isFinite, track.peak >= -1, track.peak <= 1,
                  track.droppedSeconds.isFinite, track.droppedSeconds >= 0 else {
                throw MeetingError.message("The meeting record links an unexpected track and was not written.")
            }
            _ = try safeURL(session: session, relative: track.file)
        }
        var indexes = Set<Int>()
        for segment in manifest.segments {
            guard indexes.insert(segment.index).inserted, segment.index >= 0,
                  segment.file == MeetingSegmentPlan.filename(index: segment.index),
                  segment.startSeconds.isFinite, segment.startSeconds >= 0,
                  segment.seconds.isFinite, segment.seconds >= MeetingSegmentPlan.minimumSegmentSeconds,
                  segment.seconds <= MeetingSegmentPlan.maximumSegmentSeconds,
                  segment.startSeconds + segment.seconds <= MeetingSegmentPlan.maximumMeetingSeconds,
                  segment.bytes > 0, segment.bytes <= MeetingSegmentPlan.maximumSegmentBytes else {
                throw MeetingError.message("The meeting record links an unexpected segment and was not written.")
            }
            _ = try safeURL(session: session, relative: segment.file)
        }
        var end = 0.0
        for (index, segment) in manifest.orderedSegments.enumerated() {
            guard segment.index == index, abs(segment.startSeconds - end) < 0.001 else {
                throw MeetingError.message("The meeting segments have an invalid order. The record was left unchanged.")
            }
            end = segment.startSeconds + segment.seconds
        }
        // Keep historical records readable. Complete timeline admission is stricter
        // and is checked before processing/committing or settling empty recovery.
        let hasTextShape = manifest.liveText != nil || (!manifest.segments.isEmpty && manifest.segments.allSatisfy { $0.text != nil })
        let tooShort = manifest.hasValidTimeline && manifest.timelineSeconds < MeetingSegmentPlan.minimumSegmentSeconds && manifest.segments.isEmpty
        if [.recognized, .committed].contains(manifest.state), !hasTextShape && !tooShort {
            throw MeetingError.message("The meeting record is missing recognised segments. It was left unchanged.")
        }
    }

    /// Relative paths only, no traversal, and no symbolic link on any component.
    static func safeURL(session: URL, relative: String) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw MeetingError.unsafePath
        }
        try rejectSymbolicLinks(in: session)
        var candidate = session
        for component in components {
            candidate.appendPathComponent(String(component))
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw MeetingError.unsafePath
            }
        }
        guard candidate.path.hasPrefix(session.path + "/") else { throw MeetingError.unsafePath }
        return candidate
    }

    /// Session directories only, newest first. Anything that is not a UUID
    /// directory is ignored and left in place.
    static func sessions(in root: URL) -> [URL] {
        guard (try? rejectSymbolicLinks(in: root)) != nil,
              let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        let sessions = entries.filter { url in
            guard UUID(uuidString: url.lastPathComponent) != nil else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
        return sessions.sorted { left, right in
            let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l > r
        }
    }

    static func createPrivateDirectory(_ url: URL) throws {
        try rejectSymbolicLinks(in: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw MeetingError.unsafePath }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func rejectSymbolicLinks(in url: URL) throws {
        guard url.isFileURL, !url.pathComponents.contains("..") else { throw MeetingError.unsafePath }
        var part = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            part.appendPathComponent(component)
            if (try? part.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw MeetingError.unsafePath
            }
        }
    }

    /// Stage with private permissions before replacement, then synchronise and
    /// atomically rename. A chmod or staging failure never replaces old bytes.
    static func writePrivate(_ data: Data, to url: URL) throws {
        try rejectSymbolicLinks(in: url)
        try AtomicPrivateFile.write(data, to: url)
    }
}

/// A person-readable summary of what a finished session actually contains. It
/// never implies both sides were captured when one of them is missing or silent.
enum MeetingSummary {
    static let quietPeak = 0.01

    /// A refused System Audio Recording tap records exact silence, so an app track that stayed quiet
    /// names that possibility beside where the switch is, in the words Home's Permissions row uses
    /// (MacPermission.callAudio.settingsPath); a broken tap is silent too, so it is a possibility,
    /// never a claim.
    static func gaps(for manifest: MeetingManifest, settings: String = MacPermission.callAudio.settingsPath) -> [String] {
        var notes: [String] = []
        let remote = manifest.tracks.first { $0.source == .remote }
        let local = manifest.tracks.first { $0.source == .local }
        if manifest.includesRemote {
            let name = manifest.appName ?? "the selected app"
            if remote == nil || remote?.seconds ?? 0 <= 0 {
                notes.append("No audio was received from \(name). Other people may be missing from the transcript.")
            } else if let peak = remote?.peak, peak >= 0, peak <= quietPeak {
                notes.append("No sound arrived from \(name). If the others were audible, Workbench may not have been allowed to record system audio (\(settings)).")
            }
        }
        if manifest.includesMicrophone {
            if local == nil || local?.seconds ?? 0 <= 0 {
                notes.append("No microphone audio was recorded. Your voice may be missing from the transcript.")
            } else if let peak = local?.peak, peak >= 0, peak <= quietPeak {
                notes.append("Your microphone stayed quiet for the whole recording.")
            }
        }
        for track in manifest.tracks where track.droppedSeconds > 0.05 {
            let side = track.source == .remote ? (manifest.appName ?? "the app") : "your microphone"
            notes.append(String(format: "About %.1f seconds from %@ could not be written and are missing.", track.droppedSeconds, side))
        }
        return notes
    }

    /// History keeps at most 32 notes of 500 characters, but a long call can pause or reconnect
    /// hundreds of times, and every retry rebuilt the same refused list. The manifest keeps every
    /// gap; History gets one line per source with the count and total length, and drops the
    /// person's own Stop & keep note, which is a choice rather than a limitation.
    static func historyNotes(_ notes: [String], appName: String?) -> [String] {
        var lines: [String] = [], gapLines = Set<String>()
        var gaps: [MeetingTrackSource: (count: Int, seconds: Double, line: Int)] = [:]
        for note in notes {
            if let gap = MeetingGapNote.parse(note) {
                guard gapLines.insert(note).inserted else { continue }
                if let total = gaps[gap.source] { gaps[gap.source] = (total.count + 1, total.seconds + gap.seconds, total.line) }
                else { gaps[gap.source] = (1, gap.seconds, lines.count); lines.append("") }
            } else if note != MeetingModel.keptForLater {
                lines.append(note)
            }
        }
        for (source, total) in gaps {
            let name = source == .local ? "Your microphone" : appName.flatMap { $0.isEmpty ? nil : $0 } ?? "The app"
            let length = MeetingGapNote.length(total.seconds)
            lines[total.line] = total.count == 1
                ? "\(name) had one gap (a pause or reconnection) of \(length); the recording keeps it as silence."
                : "\(name) had \(total.count) gaps (pauses or reconnections), \(length) in all; the recording keeps them as silence."
        }
        var kept: [String] = [], seen = Set<String>()
        for line in lines {
            let plain = String(String.UnicodeScalarView(line.unicodeScalars.map {
                CharacterSet.controlCharacters.contains($0) ? " " : $0
            })).trimmingCharacters(in: .whitespaces)
            let note = plain.count > 500 ? plain.prefix(499).trimmingCharacters(in: .whitespaces) + "…" : plain
            guard !note.isEmpty, seen.insert(note).inserted else { continue }
            kept.append(note)
        }
        // The fold replaces middle notes: the processor appends limitations of the saved result
        // (such as missing originals) last, and those must survive the cap.
        guard kept.count > 32, let last = kept.last else { return kept }
        return Array(kept.prefix(30)) + ["\(kept.count - 31) more notes about this recording were left out here.", last]
    }
}

/// The manifest's sentence for one gap in a source's saved audio, and its reverse, so History
/// can summarise gaps without guessing at their wording. Earlier builds wrote the same form.
enum MeetingGapNote {
    private static let ending = "s; the saved timeline includes silence."

    static func line(source: MeetingTrackSource, reason: String, start: Double, seconds: Double) -> String {
        "\(source.rawValue): \(reason) Gap at \(String(format: "%.2f", start))s for \(String(format: "%.2f", seconds))" + ending
    }

    static func parse(_ line: String) -> (source: MeetingTrackSource, seconds: Double)? {
        guard line.hasSuffix(ending), let colon = line.firstIndex(of: ":"),
              let source = MeetingTrackSource(rawValue: String(line[..<colon])),
              let marker = line.range(of: " Gap at ", options: .backwards), marker.lowerBound > colon else { return nil }
        let timing = line[marker.upperBound..<line.index(line.endIndex, offsetBy: -ending.count)].components(separatedBy: "s for ")
        guard timing.count == 2, let start = Double(timing[0]), let seconds = Double(timing[1]),
              start.isFinite, seconds.isFinite, seconds >= 0 else { return nil }
        return (source, seconds)
    }

    static func length(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole < 1 { return "under a second" }
        if whole < 60 { return "\(whole) s" }
        return whole % 60 == 0 ? "\(whole / 60) min" : "\(whole / 60) min \(whole % 60) s"
    }
}
