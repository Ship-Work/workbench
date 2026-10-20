import AVFoundation
import Foundation

/// The detection and admission defects of #377, each held where it was wrong. Synthetic process
/// metadata and a synthetic capture only: nothing here reads a real process, asks a permission,
/// opens a tap or microphone, or plays a sound.
@MainActor
enum MeetingDetectionChecks {
    static func run(root: URL) async throws -> Int {
        var checks = 0
        func expect(_ value: Bool, _ label: String) throws {
            guard value else { throw MeetingError.message("Meeting detection check failed: \(label)") }
            checks += 1
        }
        try safariChecks(expect: expect)
        try callServiceChecks(expect: expect)
        try await snoozeChecks(root: root, expect: expect)
        try await representativeChecks(root: root, expect: expect)
        return checks
    }

    /// Safari plays page and call audio in WebKit's media process, which every WebKit app has
    /// its own copy of. Only the copy macOS holds Safari responsible for is Safari's.
    private static func safariChecks(expect: (Bool, String) throws -> Void) throws {
        let gpu = "com.apple.WebKit.GPU", safari = "com.apple.Safari"
        try expect(MeetingAppCatalogue.known(gpu, responsibleBundleID: safari)?.bundleID == safari
                   && MeetingAppCatalogue.known(gpu, responsibleBundleID: "com.apple.mail") == nil
                   && MeetingAppCatalogue.known(gpu, responsibleBundleID: nil) == nil && MeetingAppCatalogue.known(gpu) == nil,
                   "a WebKit media process is Safari's only when macOS holds Safari responsible for it")
        try expect(MeetingAppCatalogue.known("com.apple.WebKit.Networking", responsibleBundleID: safari) == nil
                   && MeetingAppCatalogue.known(gpu, responsibleBundleID: "com.google.Chrome") == nil,
                   "only the helpers Safari lists can be attributed, and only to Safari")
        try expect(MeetingDetector.considers(gpu) && MeetingAppCatalogue.isHostedHelper(gpu) && !MeetingAppCatalogue.isHostedHelper("com.google.Chrome"),
                   "a detection read keeps WebKit's media processes so Safari's can be found")
        try expect(MeetingAppCatalogue.taps(gpu, responsibleBundleID: safari, for: safari)
                   && !MeetingAppCatalogue.taps(gpu, responsibleBundleID: "com.apple.mail", for: safari)
                   && MeetingAppCatalogue.taps(gpu, responsibleBundleID: "com.apple.mail", for: gpu)
                   && !MeetingAppCatalogue.taps(gpu, responsibleBundleID: safari, for: gpu),
                   "recording Safari taps its own WebKit audio; the shared WebKit source keeps every other app's and no longer Safari's")

        let source = Fixture()
        let detector = MeetingDetector(source: source)
        detector.isEnabled = true
        source.values = [
            .init(pid: 700, bundleID: safari, isRunningInput: false, isRunningOutput: false),
            .init(pid: 701, bundleID: gpu, isRunningInput: true, isRunningOutput: true, isUserFacingApp: false, responsibleBundleID: safari),
            .init(pid: 702, bundleID: gpu, isRunningInput: true, isRunningOutput: true, isUserFacingApp: false, responsibleBundleID: "com.apple.mail"),
            .init(pid: 703, bundleID: gpu, isRunningInput: false, isRunningOutput: true, isUserFacingApp: false)
        ]
        let choices = detector.availableApps()
        try expect(choices.filter { $0.bundleID == safari }.map(\.id) == [700] && choices.filter { $0.bundleID == gpu }.map(\.id) == [702]
                   && choices.first { $0.bundleID == gpu }?.name == "WebKit audio service (shared)",
                   "the picker lists Safari once, by its main process, and every other app's WebKit audio as the shared service")
        _ = detector.evaluate(); _ = detector.evaluate()
        let offer = detector.evaluate()
        try expect(offer?.id == 700 && offer?.bundleID == safari && offer.map(MeetingDetector.offerTitle) == "Possible call in Safari",
                   "a call in Safari, whose microphone runs in its WebKit media process, is offered as Safari (#377)")
        let call = MeetingAudioApp(id: 700, name: "Safari", bundleID: safari)
        try expect(detector.activity(for: call) == .active, "Safari's activity counts its WebKit media process")
        source.values[1].isRunningInput = false; source.values[1].isRunningOutput = false
        detector.forgetObservations()
        for _ in 0..<4 { _ = detector.evaluate() }
        try expect(detector.evaluate() == nil && detector.activity(for: call) == .inactive,
                   "another app's two-way WebKit audio is never offered or counted as Safari")
        source.values.removeAll { $0.pid == 701 || $0.pid == 702 }
        source.values[1].isRunningInput = true
        for _ in 0..<4 { _ = detector.evaluate() }
        try expect(detector.evaluate() == nil, "an unattributed WebKit service stays a manual choice even with two-way audio")

        let helperOnly = MeetingDetector(source: source)
        helperOnly.isEnabled = true
        source.values = [.init(pid: 711, bundleID: gpu, isRunningInput: true, isRunningOutput: true, isUserFacingApp: false, responsibleBundleID: safari)]
        _ = helperOnly.evaluate(); _ = helperOnly.evaluate()
        try expect(helperOnly.evaluate()?.id == 711 && helperOnly.availableApps().map(\.bundleID) == [safari],
                   "Safari without a main process in Core Audio's list is offered and listed by its WebKit media process")
        source.values[0].responsibleBundleID = nil
        helperOnly.forgetObservations()
        for _ in 0..<4 { _ = helperOnly.evaluate() }
        try expect(helperOnly.evaluate() == nil && helperOnly.availableApps().map(\.bundleID) == [gpu],
                   "without attribution the same process is the shared WebKit service and nothing is offered as Safari")
    }

    /// FaceTime and Phone calls play in the Mac calling service, which their own processes never hold.
    private static func callServiceChecks(expect: (Bool, String) throws -> Void) throws {
        let service = "com.apple.avconferenced"
        for app in ["com.apple.FaceTime", "com.apple.mobilephone"] {
            try expect(MeetingAppCatalogue.taps(service, responsibleBundleID: nil, for: app) && MeetingAppCatalogue.taps(app, responsibleBundleID: nil, for: app),
                       "recording \(app) taps its own processes and the calling service, where its call plays (#377)")
        }
        try expect(!MeetingAppCatalogue.taps(service, responsibleBundleID: nil, for: "us.zoom.xos")
                   && !MeetingAppCatalogue.taps("com.apple.TelephonyUtilities", responsibleBundleID: nil, for: "com.apple.FaceTime")
                   && MeetingAppCatalogue.known(service) == nil,
                   "no other app taps the calling service, the telephony service stays out, and the calling service is never merged into an app")
        let source = Fixture()
        let detector = MeetingDetector(source: source)
        detector.isEnabled = true
        source.values = [.init(pid: 720, bundleID: "com.apple.FaceTime", isRunningInput: false, isRunningOutput: false),
                         .init(pid: 721, bundleID: service, isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        let faceTime = MeetingAudioApp(id: 720, name: "FaceTime", bundleID: "com.apple.FaceTime")
        try expect(detector.activity(for: faceTime) == .active,
                   "a FaceTime recording sees its call's audio in the calling service, so its guarded finish can see the call end")
        try expect(Set(detector.availableApps().map(\.id)) == [720, 721], "FaceTime and the calling service stay two choices")
        _ = detector.evaluate(); _ = detector.evaluate()
        let offer = detector.evaluate()
        try expect(offer?.id == 721 && offer.map(MeetingDetector.offerTitle) == "Possible call on this Mac",
                   "the calling service's audio is offered as a call on this Mac, never as FaceTime")
        source.values[1].isRunningInput = false; source.values[1].isRunningOutput = false
        try expect(detector.activity(for: faceTime) == .inactive, "the call service going quiet reads as FaceTime's call ending")
    }

    /// Snooze hid offers with nothing on screen, and outlived turning detection off and on.
    private static func snoozeChecks(root: URL, expect: (Bool, String) throws -> Void) async throws {
        let source = Fixture()
        let detector = MeetingDetector(source: source)
        let now = Date(timeIntervalSince1970: 1_000_000)
        detector.isEnabled = true
        detector.snooze(now: now)
        let until = now.addingTimeInterval(2 * 60 * 60)
        try expect(detector.snoozeLine(now: now.addingTimeInterval(60)) == "Call offers are snoozed until \(until.formatted(date: .omitted, time: .shortened)).",
                   "the Meetings page can say offers are snoozed and when that ends (#377)")
        try expect(detector.snoozeLine(now: until) == nil, "the line goes when the snooze ends")
        source.values = [.init(pid: 730, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true)]
        _ = detector.evaluate(now: until); _ = detector.evaluate(now: until)
        try expect(detector.evaluate(now: until)?.id == 730 && detector.snoozedUntil == nil, "an ended snooze is cleared, not kept")
        detector.snooze(now: now)
        detector.isEnabled = false
        try expect(detector.snoozeLine(now: now) == nil && detector.snoozedUntil == nil, "turning detection off clears the snooze and its line")

        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-MeetingSnooze-" + UUID().uuidString).path
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = MeetingModel(directory: root.appendingPathComponent("snooze"), defaults: defaults, processSource: source,
                                 transcribe: { _ in "unused" }, microphonePermission: { true }, captureFactory: { Capture() })
        model.detectionEnabled = true
        for _ in 0..<3 { model.refreshDetection() }
        try expect(model.offer?.id == 730, "a sustained call is offered")
        model.snoozeOffers()
        for _ in 0..<4 { model.refreshDetection() }
        try expect(model.offer == nil, "Snooze holds offers")
        model.detectionEnabled = false; model.detectionEnabled = true
        for _ in 0..<3 { model.refreshDetection() }
        try expect(model.offer?.id == 730, "turning detection off and on clears a snooze, so the call is offered again (#377)")
        model.dismissOffer()
        for _ in 0..<4 { model.refreshDetection() }
        try expect(model.offer == nil, "Not now holds this app's offers")
        model.detectionEnabled = false; model.detectionEnabled = true
        for _ in 0..<3 { model.refreshDetection() }
        try expect(model.offer?.id == 730, "turning detection off and on also clears Not now")
        model.detectionEnabled = false
        await model.prepareForShutdown()
    }

    /// The chosen app is held by one process number; a running app read as no longer available
    /// when that process changed, though capture already follows the app by bundle.
    private static func representativeChecks(root: URL, expect: (Bool, String) throws -> Void) async throws {
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-MeetingRepresentative-" + UUID().uuidString).path
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = Fixture(), capture = Capture()
        let model = MeetingModel(directory: root.appendingPathComponent("representative"), defaults: defaults, processSource: source,
                                 transcribe: { _ in "unused" }, microphonePermission: { true }, captureFactory: { capture })
        let chrome = "com.google.Chrome"
        source.values = [.init(pid: 741, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        model.refreshApps(); model.selectAudioSource(741)
        try expect(model.admission.canStart, "Chrome is chosen by its audio helper")
        source.values.append(.init(pid: 740, bundleID: chrome, isRunningInput: false, isRunningOutput: false))
        model.refreshApps()
        try expect(model.admission.canStart && model.apps.filter { $0.bundleID == chrome }.map(\.id) == [741],
                   "Chrome's main process joining Core Audio's list keeps the chosen source (#377)")
        source.values = [.init(pid: 740, bundleID: chrome, isRunningInput: false, isRunningOutput: false),
                         .init(pid: 742, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        model.refreshApps()
        try expect(model.admission.canStart && model.admission.captureProblem == nil && model.apps.filter { $0.bundleID == chrome }.map(\.id) == [741],
                   "Chrome's audio helper restarting keeps the chosen source rather than reading as no longer available (#377)")
        model.useAppAudioOnly()
        await model.start()
        try expect(capture.started?.id == 741 && capture.started?.bundleID == chrome && model.problem == .unknown(Capture.refusal),
                   "Start passes the chosen app to capture, which finds its current processes by bundle")
        source.values.append(.init(pid: 741, bundleID: "example.player", isRunningInput: false, isRunningOutput: true, name: "Example Player"))
        model.refreshApps()
        try expect(model.apps.first { $0.bundleID == chrome }?.id == 741 && model.apps.first { $0.bundleID == "example.player" }?.id == -741
                   && Set(model.apps.map(\.id)).count == model.apps.count && model.admission.canStart,
                   "another app whose process reuses the chosen number is listed apart, so the choice never silently becomes that app")
        source.values = []
        model.refreshApps()
        try expect(model.admission.captureProblem == .sourceDisappeared, "an app that quit still reads as no longer available")
        source.values = [.init(pid: 750, bundleID: chrome, isRunningInput: false, isRunningOutput: false)]
        model.refreshApps()
        try expect(model.apps.first { $0.bundleID == chrome }?.id == 750, "a relaunched app is listed by its new process")
        source.failure = true; model.refreshApps(); source.failure = false
        source.values = [.init(pid: 751, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        model.refreshApps()
        try expect(model.apps.first { $0.bundleID == chrome }?.id == 750, "a failed read forgets nothing it could not see")
        await model.prepareForShutdown()
    }

    private final class Fixture: MeetingProcessSource {
        var isAvailable = true
        var unavailableReason = "Synthetic unavailable metadata"
        var values: [MeetingProcessSnapshot] = []
        var failure = false
        func snapshot() throws -> [MeetingProcessSnapshot] {
            if failure { throw MeetingError.message("Synthetic metadata failure") }
            return values
        }
    }

    /// Records the app Start passed and refuses, so the model's own start path runs to capture.
    private final class Capture: MeetingCapture {
        static let refusal = "Synthetic capture refusal"
        var started: MeetingAudioApp?
        func start(_ request: MeetingCaptureRequest) async throws {
            started = request.app
            throw MeetingError.message(Self.refusal)
        }
        func finish() async -> MeetingCaptureReport { MeetingCaptureReport() }
        func requestStop() {}
        var elapsedSeconds: Double { 0 }
        var stopReason: String? { nil }
    }
}
