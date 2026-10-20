import AVFoundation
import CoreAudio
import Foundation

/// The detection and admission defects of #377, each held where it was wrong. Synthetic process
/// metadata and a synthetic capture only: nothing here lists audio processes, asks a permission,
/// opens a tap or microphone, or plays a sound. One check resolves the responsible-app lookup
/// and asks it about launchd (docs/desktop.md, Decisions), and the disk check writes a few
/// seconds of synthetic PCM through the real track writer in a temporary folder.
@MainActor
enum MeetingDetectionChecks {
    static func run(root: URL) async throws -> Int {
        var checks = 0
        func expect(_ value: Bool, _ label: String) throws {
            guard value else { throw MeetingError.message("Meeting detection check failed: \(label)") }
            checks += 1
        }
        try safariChecks(expect: expect)
        try attributionChecks(expect: expect)
        try await unavailableAdmissionChecks(root: root, expect: expect)
        try tapScopeChecks(expect: expect)
        try callServiceChecks(expect: expect)
        try await snoozeChecks(root: root, expect: expect)
        try await representativeChecks(root: root, expect: expect)
        try finishCaptionChecks(expect: expect)
        try await diskBudgetChecks(root: root, expect: expect)
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

    /// The responsible-app lookup resolves here and fails closed; without it Safari is never
    /// offered and its picker entry says its calls are not supported, rather than recording silence.
    private static func attributionChecks(expect: (Bool, String) throws -> Void) throws {
        try expect(MeetingResponsibleApp.isAvailable, "the responsible-app lookup resolves from libSystem on this macOS (docs/desktop.md, Decisions)")
        try expect(MeetingResponsibleApp.bundleID(for: 1) == nil && MeetingResponsibleApp.bundleID(for: -5) == nil,
                   "launchd, responsible for itself, and a process that does not exist attribute to no app")
        let safari = "com.apple.Safari", gpu = "com.apple.WebKit.GPU"
        try expect(MeetingAppCatalogue.unavailableReason(safari, attributedHelper: true) == nil
                   && MeetingAppCatalogue.unavailableReason(safari, attributedHelper: false)?.hasPrefix("Workbench can't find Safari's call audio right now") == true
                   && MeetingAppCatalogue.unavailableReason("com.google.Chrome", attributedHelper: false) == nil,
                   "only an app whose calls play in shared helpers depends on attribution")
        // A missing lookup and a helper the lookup does not attribute (it answers -1 or itself)
        // both reach the snapshot as no responsible app; support is decided by each read.
        let source = Fixture()
        source.values = [.init(pid: 760, bundleID: safari, isRunningInput: true, isRunningOutput: true),
                         .init(pid: 761, bundleID: gpu, isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        let detector = MeetingDetector(source: source)
        detector.isEnabled = true
        for _ in 0..<4 { _ = detector.evaluate() }
        let unattributed = detector.availableApps().first { $0.bundleID == safari }
        try expect(detector.evaluate() == nil && unattributed?.name == "Safari (its call audio isn't available to Workbench right now)"
                   && unattributed?.unavailableReason != nil,
                   "a read that attributes no WebKit helper to Safari never offers it, and its entry says its call audio isn't available (#377)")
        source.values[1].responsibleBundleID = safari
        let attributed = detector.availableApps().first { $0.bundleID == safari }
        _ = detector.evaluate(); _ = detector.evaluate()
        try expect(attributed?.name == "Safari" && attributed?.unavailableReason == nil && detector.evaluate()?.bundleID == safari,
                   "the next read that attributes one of its helpers makes Safari a call source again")
        source.values[1].responsibleBundleID = "com.ethdawg.workbench.preview"
        try expect(detector.availableApps().first { $0.bundleID == safari }?.unavailableReason != nil
                   && !detector.availableApps().contains { $0.bundleID == gpu },
                   "Workbench's own WebKit helper is never Safari's and never the shared WebKit service")
    }

    /// Start used to run the microphone prompt, the speech check and a session before capture
    /// refused an unattributed Safari; admission now refuses with the reason first.
    private static func unavailableAdmissionChecks(root: URL, expect: (Bool, String) throws -> Void) async throws {
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-MeetingUnavailable-" + UUID().uuidString).path
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = Fixture(), store = root.appendingPathComponent("unavailable")
        var permissions = 0, captures = 0
        let model = MeetingModel(directory: store, defaults: defaults, processSource: source, transcribe: { _ in "unused" },
                                 microphonePermission: { permissions += 1; return true },
                                 captureFactory: { captures += 1; return Capture() }, microphoneStatus: { .notDetermined })
        source.values = [.init(pid: 765, bundleID: "com.apple.Safari", isRunningInput: false, isRunningOutput: true)]
        model.refreshApps(); model.selectAudioSource(765)
        let reason = model.apps.first?.unavailableReason
        try expect(reason != nil && model.admission.captureProblem == .appAudioUnavailable(reason!) && !model.admission.canStart,
                   "an unattributed Safari choice is refused by admission, with the reason, before Start (#377)")
        await model.start()
        try expect(model.problem == .appAudioUnavailable(reason!) && permissions == 0 && captures == 0 && MeetingStore.sessions(in: store).isEmpty,
                   "Start asks for no microphone, runs no capture and creates no session")
        source.values.append(.init(pid: 766, bundleID: "com.apple.WebKit.GPU", isRunningInput: true, isRunningOutput: true,
                                   isUserFacingApp: false, responsibleBundleID: "com.apple.Safari"))
        model.refreshApps()
        try expect(model.admission.captureProblem == nil && model.admission.canStart, "a read that attributes Safari's helper admits it")
        await model.prepareForShutdown()
    }

    /// Capture binds to and taps processes by the same ownership the picker lists, as a pure rule.
    private static func tapScopeChecks(expect: (Bool, String) throws -> Void) throws {
        let safari = "com.apple.Safari", gpu = "com.apple.WebKit.GPU"
        let processes: [MeetingTapScope.Process] = [
            .init(object: 11, pid: 770, bundleID: safari),
            .init(object: 12, pid: 771, bundleID: gpu, responsibleBundleID: safari),
            .init(object: 13, pid: 772, bundleID: gpu, responsibleBundleID: "com.apple.mail"),
            .init(object: 14, pid: 773, bundleID: gpu),
            .init(object: 15, pid: 774, bundleID: "com.apple.avconferenced"),
            .init(object: 16, pid: 775, bundleID: "com.apple.FaceTime"),
            .init(object: 17, pid: 776, bundleID: "com.google.Chrome.helper"),
            .init(object: 18, pid: 777, bundleID: "com.google.Chrome"),
            .init(object: 19, pid: 778, bundleID: "com.ethdawg.workbench.preview"),
            .init(object: 20, pid: 779, bundleID: gpu, responsibleBundleID: "com.ethdawg.workbench.preview")
        ]
        func tapped(_ bundle: String) -> [AudioObjectID] { MeetingTapScope.tapped(for: bundle, among: processes).map(\.object) }
        try expect(tapped(safari) == [11, 12] && tapped(gpu) == [13, 14] && tapped("com.apple.FaceTime") == [15, 16]
                   && tapped("com.apple.avconferenced") == [15] && tapped("com.google.Chrome") == [17, 18],
                   "Safari taps itself and its own WebKit helper, the shared WebKit source every other app's, FaceTime itself and the calling service")
        func bound(_ id: Int32, _ bundle: String, own: Int32 = 1) -> Int32? {
            MeetingTapScope.representative(of: MeetingAudioApp(id: id, name: "", bundleID: bundle), among: processes, own: own)?.pid
        }
        try expect(bound(771, safari) == 771 && bound(999, safari) == 770 && bound(741, "com.google.Chrome") == 776,
                   "a recording binds to its listed process while it is the app's, and otherwise finds the app's current process by bundle")
        try expect(bound(774, "com.apple.FaceTime") == 775 && bound(772, safari) == 770
                   && MeetingTapScope.representative(of: MeetingAudioApp(id: 775, name: "", bundleID: "com.apple.FaceTime"),
                                                     among: processes.filter { $0.pid != 775 }, own: 1) == nil,
                   "a call service or another app's helper is never an app's own process, so FaceTime without its process cannot bind")
        try expect(bound(778, "com.ethdawg.workbench.preview") == nil && bound(777, "com.google.Chrome", own: 777) == 776
                   && bound(779, gpu) == 772,
                   "Workbench, its own process and the WebKit helper behind its own web views never bind")
        try expect(MeetingTapScope.unavailableReason(for: safari, among: processes) == nil
                   && MeetingTapScope.unavailableReason(for: safari, among: processes.filter { $0.object != 12 }) != nil
                   && MeetingTapScope.unavailableReason(for: "com.google.Chrome", among: []) == nil,
                   "capture refuses Safari itself when the processes it reads attribute no helper to Safari")
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
        source.uptime += 10
        source.values = [.init(pid: 750, bundleID: chrome, isRunningInput: false, isRunningOutput: false)]
        model.refreshApps()
        try expect(model.apps.first { $0.bundleID == chrome }?.id == 741 && model.admission.canStart,
                   "the same app back within 30 seconds is the chosen source again")
        source.values = []
        model.refreshApps(); source.uptime += 31; model.refreshApps()
        source.values = [.init(pid: 752, bundleID: chrome, isRunningInput: false, isRunningOutput: false)]
        model.refreshApps()
        try expect(model.apps.first { $0.bundleID == chrome }?.id == 752 && model.admission.captureProblem == .sourceDisappeared,
                   "an app gone for over 30 seconds is listed afresh, and the old choice is not quietly revived")
        source.failure = true; source.uptime += 60; model.refreshApps(); source.failure = false
        source.values = [.init(pid: 753, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        model.refreshApps()
        try expect(model.apps.first { $0.bundleID == chrome }?.id == 752, "a failed read forgets nothing it could not see")
        await model.prepareForShutdown()

        // The review's case: a source listed only through a helper that is gone for more than one
        // three-second poll. Polls and the picker both read during the gap.
        let gap = Fixture()
        let polls = MeetingModel(directory: root.appendingPathComponent("helper-gap"), defaults: defaults, processSource: gap,
                                 transcribe: { _ in "unused" }, microphonePermission: { true }, captureFactory: { capture })
        polls.detectionEnabled = true
        gap.values = [.init(pid: 790, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        polls.refreshApps(); polls.selectAudioSource(790)
        gap.values = []
        for _ in 0..<3 { gap.uptime += 3; polls.refreshDetection(); polls.refreshApps() }
        try expect(polls.admission.captureProblem == .sourceDisappeared, "while no Chrome process is listed the choice says so")
        gap.values = [.init(pid: 791, bundleID: "com.google.Chrome.helper", isRunningInput: true, isRunningOutput: true, isUserFacingApp: false)]
        gap.uptime += 1; polls.refreshDetection(); polls.refreshApps()
        try expect(polls.admission.canStart && polls.apps.first { $0.bundleID == chrome }?.id == 790,
                   "a helper gone for ten seconds, across several polls, comes back as the chosen source (#377)")
        polls.detectionEnabled = false
        await polls.prepareForShutdown()
    }

    /// Finish when call audio ends reads activity only for catalogue apps and the calling service.
    private static func finishCaptionChecks(expect: (Bool, String) throws -> Void) throws {
        let automatic = MeetingAppCatalogue.supported.map { MeetingAudioApp(id: 1, name: $0.name, bundleID: $0.bundleID) }
            + [MeetingAudioApp(id: 2, name: "Mac calling service", bundleID: "com.apple.avconferenced")]
        let manual = [MeetingAudioApp(id: 3, name: "Example", bundleID: "example.player"),
                      MeetingAudioApp(id: 4, name: "Mac telephony service", bundleID: "com.apple.TelephonyUtilities"),
                      MeetingAudioApp(id: 5, name: "WebKit audio service (shared)", bundleID: "com.apple.WebKit.GPU")]
        try expect(automatic.allSatisfy(MeetingDetector.finishesAutomatically) && !manual.contains(where: MeetingDetector.finishesAutomatically)
                   && !MeetingDetector.finishesAutomatically(nil),
                   "only catalogue apps and calls on this Mac finish by themselves")
        let detector = MeetingDetector(source: Fixture())
        try expect(manual.allSatisfy { detector.activity(for: $0) == .unknown }, "every manual source's activity reads as unknown, which never finishes")
        let caption = MeetingDetector.automaticFinishCaption
        try expect(caption.contains("a supported call app, or a call on this Mac") && caption.contains("Microphone-only recordings and other apps or services finish manually"),
                   "the Finish when call audio ends caption names every source that finishes manually, not only the microphone (#377)")
    }

    /// The start check promised a safe meeting with room for two tracks for about half an hour.
    private static func diskBudgetChecks(root: URL, expect: (Bool, String) throws -> Void) async throws {
        func trackBytes(seconds: Int, rate: Double) async throws -> Int64 {
            let directory = root.appendingPathComponent("disk-\(seconds)-" + UUID().uuidString, isDirectory: true)
            try MeetingStore.createPrivateDirectory(directory)
            let writer = try MeetingTrackRecorder(source: .remote, directory: directory, sampleRate: rate, timeline: MeetingCaptureTimeline())
            try writer.open()
            let chunk = [Float](repeating: 0.25, count: Int(rate / 10)), host = MeetingClock.now()
            for index in 0..<(seconds * 10) {
                chunk.withUnsafeBufferPointer {
                    writer.append($0.baseAddress!, count: chunk.count, hostTime: host + AVAudioTime.hostTime(forSeconds: Double(index) / 10))
                }
                if index % 10 == 9 { try await Task.sleep(nanoseconds: 60_000_000) }
            }
            let track = await Task.detached { writer.close() }.value
            guard abs(track.seconds - Double(seconds)) < 0.001, writer.failure == nil else {
                throw MeetingError.message("The synthetic \(seconds)-second track did not write (\(writer.failure ?? "short")).")
            }
            let size = try FileManager.default.attributesOfItem(atPath: writer.url.path)[.size] as? NSNumber
            return size?.int64Value ?? 0
        }
        let perSecond = (try await trackBytes(seconds: 3, rate: 48_000) - trackBytes(seconds: 1, rate: 48_000)) / 2
        let fastPerSecond = (try await trackBytes(seconds: 3, rate: 96_000) - trackBytes(seconds: 1, rate: 96_000)) / 2
        try expect(perSecond == 96_000 && fastPerSecond == 192_000 && MeetingDiskBudget.trackBytesPerSecond(sampleRate: 48_000) == perSecond
                   && MeetingDiskBudget.trackBytesPerSecond(sampleRate: 96_000) == fastPerSecond,
                   "the budget uses the real track writer's format: 16-bit mono, 96,000 bytes a second at 48 kHz and 192,000 at 96 kHz")
        try expect(MeetingDiskBudget.trackBytesPerSecond(sampleRate: nil) == perSecond && MeetingDiskBudget.trackBytesPerSecond(sampleRate: 0) == perSecond,
                   "an unreadable device rate counts as 48 kHz")
        let seconds = Int64(MeetingSegmentPlan.maximumMeetingSeconds), segments = Int64(MeetingSegmentPlan.bytesPerSecond) * seconds
        let both = MeetingDiskBudget.tracks(app: true, microphone: true), at48: (MeetingTrackSource) -> Double? = { _ in 48_000 }
        try expect(both == [.remote, .local] && MeetingDiskBudget.tracks(app: false, microphone: true) == [.local],
                   "a meeting names one original per source")
        let twoTrack = MeetingDiskBudget.requiredStartBytes(meetingTracks: both, sampleRate: at48)
        try expect(twoTrack >= 2 * perSecond * seconds + segments + MeetingDiskBudget.stopFloorBytes,
                   "starting a meeting with both sources needs room for two tracks for two hours and their transcription segments above the stop floor (#377)")
        try expect(twoTrack - 2 * perSecond * seconds - segments == MeetingDiskBudget.stopFloorBytes
                   && MeetingDiskBudget.requiredStartBytes(meetingTracks: [.local], sampleRate: at48) - perSecond * seconds - segments == MeetingDiskBudget.stopFloorBytes,
                   "an admitted meeting reaches the low-disk stop only if something else fills the disk")
        let fastOutput: (MeetingTrackSource) -> Double? = { $0 == .remote ? 96_000 : 48_000 }
        let fast = MeetingDiskBudget.requiredStartBytes(meetingTracks: both, sampleRate: fastOutput)
        try expect(fast == (fastPerSecond + perSecond) * seconds + segments + MeetingDiskBudget.stopFloorBytes
                   && MeetingDiskBudget.startRefusal(available: fast - 1, meetingTracks: both, sampleRate: fastOutput)?.contains("about 2.6 GB") == true
                   && MeetingDiskBudget.startRefusal(available: twoTrack, meetingTracks: both, sampleRate: fastOutput) != nil,
                   "a 96 kHz output device sizes the app track at its own rate, so the 48 kHz figure is not enough")
        try expect(MeetingDiskBudget.requiredStartBytes(meetingTracks: nil) == 512 * 1024 * 1024
                   && MeetingDiskBudget.startRefusal(available: 0, meetingTracks: nil) == "There is not enough free disk space to record a meeting safely. Free about 500 MB and try again.",
                   "Dictate's live capture, which passes no meeting tracks, keeps the floor and wording it had")
        let refusal = MeetingDiskBudget.startRefusal(available: twoTrack - 1, meetingTracks: both, sampleRate: at48)
        try expect(refusal?.contains("Two hours with these sources needs about 1.9 GB free") == true && !(refusal ?? "").contains("500 MB")
                   && MeetingDiskBudget.startRefusal(available: twoTrack, meetingTracks: both, sampleRate: at48) == nil
                   && MeetingDiskBudget.startRefusal(available: twoTrack - 1, meetingTracks: [.remote], sampleRate: at48) == nil
                   && MeetingDiskBudget.startRefusal(available: 1, meetingTracks: [.remote], sampleRate: at48)?.contains("about 1.2 GB") == true,
                   "the refusal names what two hours of the meeting's sources need, and exactly that much space starts")
    }

    private final class Fixture: MeetingProcessSource {
        var isAvailable = true
        var unavailableReason = "Synthetic unavailable metadata"
        var values: [MeetingProcessSnapshot] = []
        var failure = false
        var uptime: TimeInterval = 1_000
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
