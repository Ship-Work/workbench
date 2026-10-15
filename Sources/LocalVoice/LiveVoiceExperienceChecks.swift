import AppKit
import SwiftUI

@MainActor enum LiveVoiceExperienceChecks {
    static func run() throws {
        var count = 0
        func expect(_ value: Bool, _ label: String) throws {
            guard value else { throw VoiceError.message("Live voice experience: " + label) }
            count += 1
        }
        var guardrail = MeetingAutoFinish()
        try expect(guardrail.observe(.inactive, now: 0, suspended: false) == nil
            && guardrail.observe(.inactive, now: 100, suspended: false) == nil, "a never-active source cannot finish a session")
        _ = guardrail.observe(.active, now: 100, suspended: false)
        try expect(guardrail.observe(.inactive, now: 101, suspended: false) == nil
            && guardrail.observe(.inactive, now: 120, suspended: false) == nil, "brief audio-use gaps do not show a countdown")
        try expect(guardrail.observe(.inactive, now: 121, suspended: false) == 10, "sustained inactivity starts a ten-second grace period")
        try expect(guardrail.observe(.active, now: 124, suspended: false) == nil, "renewed call audio cancels a pending finish")
        _ = guardrail.observe(.inactive, now: 125, suspended: false)
        try expect(guardrail.observe(.inactive, now: 154, suspended: false) == 1
            && guardrail.observe(.inactive, now: 155, suspended: false) == 0, "finish waits for the full fresh grace period")
        _ = guardrail.observe(.active, now: 160, suspended: false)
        _ = guardrail.observe(.inactive, now: 161, suspended: false)
        try expect(guardrail.observe(.unknown, now: 189, suspended: false) == nil
            && guardrail.observe(.inactive, now: 250, suspended: false) == nil, "metadata failure revokes finish until fresh active evidence")
        _ = guardrail.observe(.active, now: 251, suspended: false)
        _ = guardrail.observe(.inactive, now: 252, suspended: false)
        try expect(guardrail.observe(.inactive, now: 281, suspended: true) == nil
            && guardrail.observe(.inactive, now: 330, suspended: false) == nil, "pause and route reconnection cannot finish a call")
        _ = guardrail.observe(.active, now: 331, suspended: false)
        guardrail.keepRecording()
        try expect(guardrail.observe(.inactive, now: 400, suspended: false) == nil
            && guardrail.observe(.active, now: 401, suspended: false) == nil
            && guardrail.observe(.inactive, now: 500, suspended: false) == nil, "Keep recording disables automatic finish for this session")
        let source = ActivityFixture()
        let detector = MeetingDetector(source: source)
        let app = MeetingAudioApp(id: 42, name: "Chrome", bundleID: "com.google.Chrome")
        source.values = [.init(pid: 43, bundleID: "com.google.Chrome.helper.audio", isRunningInput: false, isRunningOutput: true)]
        try expect(detector.activity(for: app) == .active, "browser helper output keeps a muted call active")
        source.values[0].isRunningOutput = false
        try expect(detector.activity(for: app) == .inactive, "both input and output must stop")
        source.failure = true
        try expect(detector.activity(for: app) == .unknown, "metadata errors cannot masquerade as a call ending")
        source.failure = false
        let unknown = MeetingAudioApp(id: 44, name: "Other app", bundleID: "example.other")
        try expect(detector.activity(for: unknown) == .unknown, "unclassified sources keep manual Finish")
        let snapshot = LiveVoiceSnapshot(phase: .listening, recognitionDelayed: true)
        try expect(snapshot.recordingTitle == "Recording" && snapshot.transcriptStatus.contains("catching up"),
                   "delayed words do not claim capture stopped")
        // A meeting's own door prefers the bundled meeting skill and still offers the rest; the details
        // door keeps the general skill alone; a History selection keeps the pack's remembered choice.
        let builtIns = TranscriptHandoffSkill.builtIns
        let packSkill = TranscriptHandoffSkill(id: "pack.example", title: "Pack skill", detail: "Synthetic", load: { throw VoiceError.message("synthetic") })
        let meetingDoor = MeetingFollowUp.reviewSkills(meetingDoor: true, singleTranscript: true, builtIns: builtIns, packSkills: [packSkill], packPreferred: "pack.example")
        try expect(builtIns.contains { $0.id == MeetingFollowUp.skillID } && meetingDoor.preferred == MeetingFollowUp.skillID
            && meetingDoor.skills.map(\.id) == builtIns.map(\.id) + ["pack.example"], "a meeting's door offers every transcript skill with Meeting notes and follow-up preferred")
        let detailsDoor = MeetingFollowUp.reviewSkills(meetingDoor: false, singleTranscript: true, builtIns: builtIns, packSkills: [packSkill], packPreferred: "pack.example")
        try expect(detailsDoor.skills.map(\.id) == [TranscriptHandoffSkill.followUp.id] && detailsDoor.preferred == nil, "the details door keeps the general follow-up skill alone")
        let selectionDoor = MeetingFollowUp.reviewSkills(meetingDoor: false, singleTranscript: false, builtIns: builtIns, packSkills: [packSkill], packPreferred: "pack.example")
        try expect(selectionDoor.skills.count == builtIns.count + 1 && selectionDoor.preferred == "pack.example", "a History selection keeps the pack's remembered skill")
        let meetingSkill = try TranscriptHandoffSkills.builtInText(MeetingFollowUp.skillID)
        try expect(meetingSkill.contains("## Follow-up message") && meetingSkill.contains("Nothing is sent") && meetingSkill.contains("Owner?"),
                   "the meeting skill asks for a follow-up message, flags missing owners and sends nothing")
        try expect((builtIns.first { $0.id == MeetingFollowUp.skillID }?.defaultTask ?? "").contains("follow-up message"), "the meeting skill suggests its own task")
        // A call that fills the screen or sits on another Space still sees the offer, and a menu-bar
        // app's inactivity never hides it.
        let offerPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 145), styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: true)
        MeetingOfferPanelController.configure(offerPanel)
        try expect(offerPanel.collectionBehavior.contains(.canJoinAllSpaces) && offerPanel.collectionBehavior.contains(.fullScreenAuxiliary)
                   && !offerPanel.hidesOnDeactivate && offerPanel.level == .floating, "the offer panel joins every Space, full-screen calls included, and stays while Workbench is inactive")
        // A source's explanation is on the page under its line, not only in a tooltip.
        _ = NSApplication.shared
        let plain = [LiveVoiceSourceStatus(source: .app, name: "Zoom", health: .quiet)]
        var explained = plain
        explained[0].message = MeetingSilenceHint.message(appName: "Zoom", elapsed: 15, heard: false, activity: .active, permission: "Screen & System Audio Recording")
        let plainHeight = NSHostingView(rootView: LiveVoiceSourcesView(sources: plain).frame(width: 420)).fittingSize.height
        let explainedHeight = NSHostingView(rootView: LiveVoiceSourcesView(sources: explained).frame(width: 420)).fittingSize.height
        try expect(explainedHeight > plainHeight + 8, "a source's explanation takes its own line under the source (\(Int(plainHeight)) → \(Int(explainedHeight)) pt)")
        try checkLongTranscriptLayout(expect)
        print("Live voice experience: \(count) checks passed")
    }

    /// A two-hour call keeps the page responsive: the clock's once-a-second relayout must not
    /// measure every turn. Synthetic words only, hosted offscreen like the renders.
    private static func checkLongTranscriptLayout(_ expect: (Bool, String) throws -> Void) throws {
        _ = NSApplication.shared
        let words = Array(repeating: "word", count: 13).joined(separator: " ")
        let turns = (0..<1_200).map { index in
            LiveVoiceSegment(source: index.isMultiple(of: 2) ? .app : .microphone, start: Double(index * 6),
                             end: Double(index * 6 + 5), text: "Turn \(index) " + words, isFinal: true)
        }
        let snapshot = LiveVoiceSnapshot(sessionID: UUID(), phase: .listening, elapsed: 7_200, segments: turns)
        let saved = turns.map { "\($0.source.label): \($0.text)" }.joined(separator: "\n\n")
        for completedText in [nil, saved] {
            let view = NSHostingView(rootView: TranscriptLayoutProbe(caption: "0:00", snapshot: snapshot, completedText: completedText))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 948, height: 800),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view; window.isReleasedWhenClosed = false
            view.layoutSubtreeIfNeeded()
            var timings: [Double] = []
            for second in 1...3 {
                view.rootView = TranscriptLayoutProbe(caption: "0:0\(second)", snapshot: snapshot, completedText: completedText)
                let started = Date()
                view.layoutSubtreeIfNeeded()
                timings.append(Date().timeIntervalSince(started))
            }
            // Measuring every turn took about 20 s here; the clamp takes 0.1 to 0.25 s, the upper end on a
            // shared CI runner. A second keeps that twentyfold margin without failing on a slow machine.
            let median = timings.sorted()[1], kind = completedText == nil ? "live" : "saved"
            try expect(median < 1.0, "a 1,200-turn \(kind) transcript relayouts for the clock in under a second (median \(Int(median * 1000)) ms)")
            try expect(transcriptScroll(in: view)?.frame.height == LiveTranscriptText.maximumHeight,
                       "a 1,200-turn \(kind) transcript stays clamped at 360 pt")
            window.close()
        }
        let short = Array(turns.prefix(3))
        let view = NSHostingView(rootView: TranscriptLayoutProbe(caption: "0:25",
            snapshot: LiveVoiceSnapshot(sessionID: UUID(), phase: .listening, elapsed: 25, segments: short), completedText: nil))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 602, height: 470),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view; window.isReleasedWhenClosed = false
        view.layoutSubtreeIfNeeded()
        let hosted = transcriptScroll(in: view)
        let whole = (hosted?.documentView as? NSTextView)?.attributedString() ?? NSAttributedString()
        let measured = ceil(whole.boundingRect(with: NSSize(width: hosted?.frame.width ?? 0, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8
        try expect(whole.length > 0 && hosted?.frame.height == min(LiveTranscriptText.maximumHeight, max(LiveTranscriptText.minimumHeight, measured)),
                   "a three-turn transcript keeps the height of its whole text")
        window.close()
    }

    private static func transcriptScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.documentView is NSTextView { return scroll }
        for child in view.subviews { if let found = transcriptScroll(in: child) { return found } }
        return nil
    }

    private struct TranscriptLayoutProbe: View {
        let caption: String
        let snapshot: LiveVoiceSnapshot
        let completedText: String?
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(caption).font(.caption).monospacedDigit()
                LiveVoiceTranscriptView(snapshot: snapshot, conversation: true, completedText: completedText)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private final class ActivityFixture: MeetingProcessSource {
        var isAvailable = true
        var unavailableReason = "Synthetic fixture"
        var values: [MeetingProcessSnapshot] = []
        var failure = false
        func snapshot() throws -> [MeetingProcessSnapshot] {
            if failure { throw VoiceError.message("Synthetic metadata error") }
            return values
        }
    }

    /// Production transcript views, synthetic words only, no microphone or
    /// Accessibility inspection. Renders both appearances and recovery states.
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func state(_ phase: LiveVoicePhase, silentApp: Bool = false) -> LiveVoiceSnapshot {
            let words = [
                LiveVoiceSegment(source: .app, start: 12, end: 15, text: "Let's review the checklist before choosing a launch date.", isFinal: true),
                LiveVoiceSegment(source: .microphone, start: 16, end: 20, text: "I'll update it tomorrow and send it for review.", isFinal: true),
                LiveVoiceSegment(source: .app, start: 21, end: 25, text: "Great. We can decide on the date after that.", isFinal: phase == .completed)
            ]
            var app = LiveVoiceSourceStatus(source: .app, name: "Mac calling service", health: phase == .paused ? .paused : silentApp ? .quiet : .receiving)
            if silentApp { app.message = MeetingSilenceHint.message(appName: app.name, elapsed: 25, heard: false, activity: .active, permission: "Screen & System Audio Recording") }
            return LiveVoiceSnapshot(sessionID: UUID(), phase: phase, elapsed: 25,
                sources: [app, .init(source: .microphone, name: "Your microphone", health: phase == .reconnecting ? .reconnecting : .quiet)],
                segments: silentApp ? words.filter { $0.source == .microphone } : words)
        }
        // The five phases, plus a call whose app has stayed silent long enough to name the permission.
        let states = [LiveVoicePhase.listening, .paused, .reconnecting, .finishing, .completed].map { ($0.rawValue, state($0)) }
            + [("silent-app", state(.listening, silentApp: true))]
        for dark in [false, true] {
            for (name, snapshot) in states {
                let content = VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("Meetings").font(.title2.weight(.semibold)); Spacer(); Text("0:25").monospacedDigit() }
                    Text(snapshot.recordingTitle).font(.headline)
                    LiveVoiceSourcesView(sources: snapshot.sources)
                    Divider()
                    LiveVoiceTranscriptView(snapshot: snapshot, conversation: true)
                }.padding(24).frame(width: 650, height: 470).background(Workbench.background)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let view = NSHostingView(rootView: content)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 470),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = view; window.isReleasedWhenClosed = false
                view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                let image = try SurfaceGallery.snapshot(view)
                guard let data = image.representation(using: .png, properties: [:]) else { throw VoiceError.message("Could not render live transcript") }
                try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
                window.close()
            }
        }
    }
}
