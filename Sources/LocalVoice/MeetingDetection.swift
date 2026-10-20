import AppKit
import CoreAudio
import Darwin
import Foundation

/// What the detector is allowed to see: a process identifier, a bundle
/// identifier, whether that process is running audio input or output and, for a
/// shared helper, which app macOS holds responsible for it. No samples, window
/// titles, page contents or browser automation are involved.
struct MeetingProcessSnapshot: Equatable {
    var pid: Int32
    var bundleID: String
    var isRunningInput: Bool
    var isRunningOutput: Bool
    var name: String? = nil
    /// AppKit metadata only; no windows or their contents are inspected.
    var isUserFacingApp: Bool = true
    /// The app a shared helper such as WebKit's media process plays sound for, read only for the
    /// helpers a catalogue app can host (MeetingResponsibleApp); nil for every other process.
    var responsibleBundleID: String? = nil

    var knownApp: MeetingKnownApp? { MeetingAppCatalogue.known(bundleID, responsibleBundleID: responsibleBundleID) }
    /// The source this process is listed, offered and captured under.
    var owner: String { MeetingAppCatalogue.owner(bundleID, responsibleBundleID: responsibleBundleID) }
}

/// The app macOS holds responsible for a process: the app a WebKit helper works for, as macOS
/// attributes the helper's microphone use to that app. macOS offers this only as a libSystem
/// function without a public header, so it is looked up by name. When it is missing, a helper
/// belongs to no app: Safari is then not offered from WebKit audio and the shared WebKit service
/// stays a manual choice, as before (#377).
enum MeetingResponsibleApp {
    private typealias Lookup = @convention(c) (pid_t) -> pid_t
    private static let lookup: Lookup? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Lookup.self) }

    static func bundleID(for pid: pid_t) -> String? {
        guard let lookup else { return nil }
        let responsible = lookup(pid)
        guard responsible > 0, responsible != pid else { return nil }
        return NSRunningApplication(processIdentifier: responsible)?.bundleIdentifier
    }
}

/// Capture's view of the same ownership, from Core Audio's process objects (MeetingProcessTap,
/// MeetingSystemCapture.currentApp), so a recording taps exactly what the picker listed.
extension MeetingCoreAudio {
    static func owner(of object: AudioObjectID) -> String? {
        guard let bundle = bundleID(of: object) else { return nil }
        return MeetingAppCatalogue.owner(bundle, responsibleBundleID: responsibleBundleID(of: object, bundle: bundle))
    }

    static func isTapped(_ object: AudioObjectID, for appBundleID: String) -> Bool {
        guard let bundle = bundleID(of: object) else { return false }
        return MeetingAppCatalogue.taps(bundle, responsibleBundleID: responsibleBundleID(of: object, bundle: bundle), for: appBundleID)
    }

    private static func responsibleBundleID(of object: AudioObjectID, bundle: String) -> String? {
        guard MeetingAppCatalogue.isHostedHelper(bundle), let pid = processID(of: object) else { return nil }
        return MeetingResponsibleApp.bundleID(for: pid)
    }
}

protocol MeetingProcessSource: AnyObject {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func snapshot() throws -> [MeetingProcessSnapshot]
    /// Only the processes detection can act on: catalogue apps and the calling
    /// service. Polls read this; the picker reads the whole snapshot.
    func detectionSnapshot() throws -> [MeetingProcessSnapshot]
}

extension MeetingProcessSource {
    func detectionSnapshot() throws -> [MeetingProcessSnapshot] {
        try snapshot().filter { MeetingDetector.considers($0.bundleID) }
    }
}

/// The real source. Every value comes from CoreAudio process metadata, which
/// macOS exposes from 14.2. Older systems report honestly that this is
/// unavailable instead of guessing from running applications.
final class MeetingSystemProcessSource: MeetingProcessSource {
    var isAvailable: Bool { MeetingCoreAudio.isProcessMetadataAvailable }
    var unavailableReason: String { MeetingCoreAudio.unavailableReason }

    func snapshot() throws -> [MeetingProcessSnapshot] { try snapshot(including: { _ in true }) }

    func detectionSnapshot() throws -> [MeetingProcessSnapshot] { try snapshot(including: MeetingDetector.considers) }

    /// The bundle identifier is read first, so a process left out costs one
    /// property read: no PID, activity or AppKit lookup.
    private func snapshot(including: (String) -> Bool) throws -> [MeetingProcessSnapshot] {
        guard isAvailable else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        var result: [MeetingProcessSnapshot] = []
        for object in try MeetingCoreAudio.processObjectsChecked() {
            guard let bundleID = MeetingCoreAudio.bundleID(of: object),
                  !MeetingAppCatalogue.isExcluded(bundleID), including(bundleID),
                  let pid = MeetingCoreAudio.processID(of: object), pid != own else { continue }
            let application = NSRunningApplication(processIdentifier: pid)
            result.append(MeetingProcessSnapshot(pid: Int32(pid), bundleID: bundleID,
                                                 isRunningInput: try MeetingCoreAudio.activity(object, input: true),
                                                 isRunningOutput: try MeetingCoreAudio.activity(object, input: false),
                                                 name: application?.localizedName,
                                                 isUserFacingApp: application?.bundleURL?.pathExtension.lowercased() == "app"
                                                    && application?.activationPolicy != .prohibited,
                                                 responsibleBundleID: MeetingAppCatalogue.isHostedHelper(bundleID)
                                                    ? MeetingResponsibleApp.bundleID(for: pid) : nil))
        }
        return result
    }
}

/// Default-off metadata detection. It can only ever say that a call *may* be
/// running, because nothing it reads proves one. It never starts a recording,
/// and while it is switched off it does not read anything at all.
final class MeetingDetector {
    struct Options {
        /// Consecutive observations before an app is offered. One launch, or a
        /// single momentary input check, is never enough.
        var confirmations = 3
        var dismissCooldown: TimeInterval = 20 * 60
        var snoozeDuration: TimeInterval = 2 * 60 * 60
    }

    let source: MeetingProcessSource
    let options: Options
    /// Apps the detector stops offering for this run. In memory only;
    /// nothing persists them.
    var disabledBundleIDs: Set<String> = []
    var snoozedUntil: Date?
    /// Detection stays off until the person turns it on. Turning it off also forgets Snooze and
    /// every Not now, so turning it on again offers afresh; before, a snooze outlived the switch
    /// and kept every offer away with nothing on screen (#377).
    var isEnabled = false {
        didSet { if !isEnabled { forgetObservations(); snoozedUntil = nil; cooldowns.removeAll() } }
    }
    /// Suppresses offers while a recording or transcription is already running.
    var isSuppressed = false { didSet { if isSuppressed { forgetObservations() } } }
    private(set) var lastError: String?

    private var streaks: [String: Int] = [:]
    private var cooldowns: [String: Date] = [:]
    /// The process identifier each source was first listed with, by its owner bundle. A source
    /// keeps it while any of its audio processes is listed, so Meetings, which holds the chosen
    /// source by this number, never reads a running app as gone when a helper restarts or the
    /// main process joins or leaves Core Audio's list (#377). A read that lists the source no
    /// more forgets it.
    private var representatives: [String: Int32] = [:]

    init(source: MeetingProcessSource, options: Options = Options()) {
        self.source = source
        self.options = options
    }

    var isAvailable: Bool { source.isAvailable }
    var unavailableReason: String { source.unavailableReason }

    /// The picker list: audio apps Workbench recognises that exist right now.
    /// This is an explicit person-facing action, not detection.
    func availableApps() -> [MeetingAudioApp] {
        (try? enumerateApps().get()) ?? []
    }

    func enumerateApps() -> Result<[MeetingAudioApp], MeetingProblem> {
        guard source.isAvailable else { return .failure(.appAudioUnavailable(source.unavailableReason)) }
        do {
            let processes = try source.snapshot()
            lastError = nil
            return .success(availableApps(in: processes, covering: { _ in true }))
        } catch {
            let message = "Audio sources could not be checked. The previous selection was kept. " + error.localizedDescription
            lastError = message
            return .failure(.sourceProbe(message))
        }
    }

    /// During an explicitly started recording, monitor only its chosen app's
    /// audio-use metadata: what its recording taps, including the service that
    /// plays its calls. This is independent of proactive Start offers.
    func activity(for app: MeetingAudioApp) -> MeetingAutoFinish.Activity {
        guard source.isAvailable, Self.finishesAutomatically(app) else { return .unknown }
        do {
            let processes = try source.detectionSnapshot().filter {
                MeetingAppCatalogue.taps($0.bundleID, responsibleBundleID: $0.responsibleBundleID, for: app.bundleID)
            }
            return processes.contains { $0.isRunningInput || $0.isRunningOutput } ? .active : .inactive
        } catch { return .unknown }
    }

    /// Finish when call audio ends reads activity only for catalogue apps and the calling
    /// service; every other source, like the microphone alone, finishes when the person says.
    static func finishesAutomatically(_ app: MeetingAudioApp?) -> Bool {
        guard let app else { return false }
        return MeetingAppCatalogue.known(app.bundleID) != nil || isCallService(app)
    }

    /// Recording options' caption for Finish when call audio ends. It said only microphone-only
    /// recordings finish manually, while any app the catalogue does not know never finishes by
    /// itself either (#377); finishesAutomatically is the rule it describes.
    static let automaticFinishCaption = "After a supported call app, or a call on this Mac, stops using audio, a short countdown lets you keep recording. Silence, Pause and reconnecting audio never finish a session. Microphone-only recordings and other apps or services finish manually."

    /// One choice per source. `covers` names the sources this read could have seen, so a
    /// detection read, which leaves out every other process, forgets only its own.
    private func availableApps(in processes: [MeetingProcessSnapshot], covering covers: (String) -> Bool) -> [MeetingAudioApp] {
        var seen = Set<String>()
        var apps: [MeetingAudioApp] = []
        // A selected app's tap already includes its recognised helper processes.
        // Show one choice for that same scope, preferring its stable main process.
        let ordered = processes.sorted { left, right in
            if left.isUserFacingApp != right.isUserFacingApp { return left.isUserFacingApp }
            let leftMain = left.knownApp?.bundleID.caseInsensitiveCompare(left.bundleID) == .orderedSame
            let rightMain = right.knownApp?.bundleID.caseInsensitiveCompare(right.bundleID) == .orderedSame
            if leftMain != rightMain { return leftMain }
            return left.pid < right.pid
        }
        // Numbers a source was listed with stay that source's while it is listed. A new source
        // whose process reuses one is listed by the negated number, which no process holds, so
        // a chosen source is never silently replaced by another app; capture finds either by bundle.
        var taken = Set(representatives.values)
        for process in ordered {
            let known = process.knownApp
            let serviceName = MeetingAppCatalogue.manualServiceNames[process.bundleID]
            let bundleID = process.owner
            guard process.pid != ProcessInfo.processInfo.processIdentifier,
                  !MeetingAppCatalogue.isExcluded(process.bundleID),
                  process.isUserFacingApp || known != nil || serviceName != nil,
                  seen.insert(bundleID).inserted else { continue }
            var id = process.pid
            if let kept = representatives[bundleID] { id = kept }
            else {
                while taken.contains(id) { id = id > 0 ? -id : id &- 1 }
                taken.insert(id)
            }
            apps.append(MeetingAudioApp(id: id, name: known?.name ?? serviceName ?? process.name ?? process.bundleID,
                                        bundleID: bundleID))
        }
        for bundleID in Array(representatives.keys) where covers(bundleID) && !seen.contains(bundleID) {
            representatives[bundleID] = nil
        }
        for app in apps { representatives[app.bundleID] = app.id }
        return apps.sorted { left, right in
            let leftKind = MeetingAppCatalogue.known(left.bundleID)?.kind ?? .browser
            let rightKind = MeetingAppCatalogue.known(right.bundleID)?.kind ?? .browser
            if leftKind != rightKind { return leftKind == .communication }
            if left.name != right.name { return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending }
            return left.id < right.id
        }
    }

    /// One detection step. Returns an app only when the same supported app has
    /// been running audio input for several consecutive steps.
    func evaluate(now: Date = Date()) -> MeetingAudioApp? {
        guard isEnabled, !isSuppressed, source.isAvailable else { return nil }
        if let until = snoozedUntil {
            if until > now { streaks.removeAll(); return nil }
            snoozedUntil = nil
        }
        var candidates: [String: MeetingAudioApp] = [:]
        // A failed read forgets the streaks but keeps the listed numbers: nothing was seen to go.
        guard let processes = read() else { return nil }
        let choices = Dictionary(uniqueKeysWithValues: availableApps(in: processes, covering: Self.considers).map { ($0.bundleID, $0) })
        for process in processes {
            guard process.pid != ProcessInfo.processInfo.processIdentifier,
                  !MeetingAppCatalogue.isExcluded(process.bundleID),
                  let known = process.knownApp,
                  !disabledBundleIDs.contains(known.bundleID),
                  // Playing sound alone is not a call. Something must be using
                  // the microphone through that app.
                  process.isRunningInput else { continue }
            candidates[known.bundleID] = choices[known.bundleID]
        }
        // Observed Mac call activity uses this service. Requiring both
        // directions avoids input-only checks and output-only sounds, but is
        // still only a possible-call signal. Other manual services stay manual.
        for process in processes where MeetingAppCatalogue.callServiceBundleIDs.contains(process.bundleID)
            && process.isRunningInput && process.isRunningOutput && !disabledBundleIDs.contains(process.bundleID) {
            candidates[process.bundleID] = choices[process.bundleID]
        }
        for bundleID in Array(streaks.keys) where candidates[bundleID] == nil { streaks[bundleID] = 0 }
        for bundleID in candidates.keys { streaks[bundleID, default: 0] += 1 }
        let ready = candidates.values.filter { app in
            guard streaks[app.bundleID, default: 0] >= options.confirmations else { return false }
            if let until = cooldowns[app.bundleID], until > now { return false }
            return true
        }
        // A known app is the more specific signal; the calling service is offered
        // only when no meeting app or browser qualifies.
        return ready.sorted { left, right in
            let leftRank = Self.offerRank(left.bundleID), rightRank = Self.offerRank(right.bundleID)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.bundleID < right.bundleID
        }.first
    }

    private func read() -> [MeetingProcessSnapshot]? {
        do { let value = try source.detectionSnapshot(); lastError = nil; return value }
        catch {
            lastError = "Audio activity could not be checked. \(error.localizedDescription)"
            forgetObservations()
            return nil
        }
    }

    /// "Not now" for this app: no further offer until the cooldown passes.
    func dismiss(_ app: MeetingAudioApp, now: Date = Date()) {
        cooldowns[app.bundleID] = now.addingTimeInterval(options.dismissCooldown)
        streaks[app.bundleID] = 0
    }

    func snooze(now: Date = Date()) {
        snoozedUntil = now.addingTimeInterval(options.snoozeDuration)
        streaks.removeAll()
    }

    /// The Meetings page's one line while Snooze holds every offer, with the time it ends (#377).
    /// Nil while detection is off and once the snooze is over.
    func snoozeLine(now: Date = Date()) -> String? {
        guard isEnabled, let until = snoozedUntil, until > now else { return nil }
        return Self.snoozeLine(until: until)
    }

    static func snoozeLine(until: Date) -> String {
        "Call offers are snoozed until \(until.formatted(date: .omitted, time: .shortened))."
    }

    func disable(_ app: MeetingAudioApp) {
        disabledBundleIDs.insert(app.bundleID)
        streaks[app.bundleID] = 0
        cooldowns[app.bundleID] = nil
    }

    /// Turning detection off forgets every observation immediately.
    func forgetObservations() {
        streaks.removeAll()
    }

    static func offerTitle(for app: MeetingAudioApp) -> String {
        isCallService(app) ? "Possible call on this Mac" : "Possible call in " + app.name
    }

    static func isCallService(_ app: MeetingAudioApp) -> Bool { MeetingAppCatalogue.callServiceBundleIDs.contains(app.bundleID) }

    /// Only a catalogue app, a helper one can host, or the calling service can become an offer
    /// or own a catalogue choice, so a poll needs no other process's metadata.
    static func considers(_ bundleID: String) -> Bool {
        MeetingAppCatalogue.known(bundleID) != nil || MeetingAppCatalogue.callServiceBundleIDs.contains(bundleID)
            || MeetingAppCatalogue.isHostedHelper(bundleID)
    }

    private static func offerRank(_ bundleID: String) -> Int {
        if MeetingAppCatalogue.callServiceBundleIDs.contains(bundleID) { return 2 }
        return MeetingAppCatalogue.known(bundleID)?.kind == .communication ? 0 : 1
    }
}
