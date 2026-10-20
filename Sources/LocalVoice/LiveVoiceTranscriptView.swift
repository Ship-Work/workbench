import AppKit
import SwiftUI

/// Presentation reads capture and recognition separately. A quiet source is not
/// a finished call, and a delayed recognizer is not a stopped microphone.
extension LiveVoiceSnapshot {
    var recordingTitle: String {
        switch phase {
        case .idle: return "Ready to record"
        case .preparing: return "Starting recording"
        case .listening: return "Recording"
        case .paused: return "Paused"
        case .reconnecting: return "Reconnecting audio"
        case .finishing: return "Finishing transcript"
        case .completed: return "Transcript saved"
        case .recoverableFailure: return "Recording kept"
        }
    }

    var transcriptStatus: String {
        // Catching up is a real backlog, now. An incomplete pass still shows its words; the saved
        // transcript comes from the original audio, and the line says so rather than catching up forever (#280).
        if liveStopped && isActive { return "Live words stopped · the saved transcript will come from the original audio" }
        if recognitionDelayed {
            return liveIncomplete ? "Words are catching up · the saved transcript will come from the original audio"
                                  : "Words are catching up · audio is still being kept"
        }
        if liveIncomplete && phase == .listening { return "Live words continue · the saved transcript will come from the original audio" }
        if let message, !message.isEmpty { return message }
        switch phase {
        case .preparing: return "Preparing live words…"
        case .paused: return "Resume to continue the same recording."
        case .reconnecting: return "Keeping this session open while audio reconnects."
        case .finishing: return "Saving your words and original recording…"
        case .completed: return "Saved in History with the original recording."
        case .recoverableFailure: return "Original audio is available for recovery."
        default: return hasProvisionalText ? "The latest words may settle as you speak." : "Words appear here as you speak."
        }
    }
}

struct LiveVoiceSourcesView: View {
    let sources: [LiveVoiceSourceStatus]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { rows }
                VStack(alignment: .leading, spacing: 8) { rows }
            }
            // A source's explanation is on the page under its line, not only in its tooltip (Fit rule 2).
            ForEach(sources.filter { $0.message?.isEmpty == false }, id: \.source) { source in
                Text(source.message ?? "").font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice.source-note." + source.source.rawValue)
            }
        }
    }
    private var rows: some View {
        ForEach(sources, id: \.source) { source in
            Label {
                Text(source.name + " · " + status(source.health))
                    .font(.caption).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: source.source == .microphone ? "mic" : "speaker.wave.2")
                    .foregroundStyle(source.health == .unavailable ? Workbench.attention : Workbench.accent)
            }.help(source.message ?? source.name).accessibilityElement(children: .combine)
        }
    }
    private func status(_ health: LiveVoiceSourceStatus.Health) -> String {
        switch health {
        case .waiting: return "Waiting for audio"
        case .receiving: return "Receiving audio"
        case .quiet: return "Quiet"
        case .paused: return "Paused"
        case .reconnecting: return "Reconnecting"
        case .unavailable: return "Unavailable"
        }
    }
}

/// One selectable transcript surface in Meetings and Dictate. Native text keeps
/// selection and reading position while hypotheses change, including mouse-wheel
/// scrolling; new words never drag a reader away from earlier turns.
struct LiveVoiceTranscriptView: View {
    let snapshot: LiveVoiceSnapshot
    var conversation = false
    var completedText: String? = nil
    @State private var atLatest = true
    @State private var latestRequest = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snapshot.phase == .completed ? "Transcript" : "Live transcript").font(Workbench.sectionTitle)
                Spacer()
                if !atLatest {
                    Button("Latest words") { latestRequest += 1 }.controlSize(.small)
                }
            }
            if snapshot.segments.isEmpty && (completedText ?? "").isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(snapshot.phase == .paused ? "Your transcript will continue here." : "Listening for your words…")
                        .font(.body).foregroundStyle(.secondary)
                    Text(snapshot.transcriptStatus).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: LiveTranscriptText.minimumHeight, alignment: .topLeading).padding(.top, 8)
            } else {
                LiveTranscriptText(segments: snapshot.segments, conversation: conversation,
                                   completedText: completedText, latestRequest: latestRequest,
                                   atLatest: $atLatest)
                    .id(snapshot.sessionID)
                    .accessibilityIdentifier("voice.live-transcript")
                // A saved transcript's page already says so in its status title.
                if snapshot.phase != .completed {
                    Text(snapshot.transcriptStatus).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct LiveTranscriptText: NSViewRepresentable {
    /// Short transcripts take only their own height; long ones scroll inside, keeping the
    /// newest words in view without pushing the page's controls away.
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 360
    var segments: [LiveVoiceSegment]
    var conversation: Bool
    var completedText: String?
    var latestRequest: Int
    @Binding var atLatest: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let text = NSTextView(frame: .zero)
        text.isEditable = false; text.isSelectable = true; text.isRichText = true
        text.drawsBackground = false; text.textContainerInset = NSSize(width: 0, height: 4)
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("Transcript")
        scroll.documentView = text
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak scroll, weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                guard let scroll, let coordinator else { return }
                coordinator.reportLatest?(Self.isAtLatest(scroll))
            }
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        context.coordinator.reportLatest = { value in
            DispatchQueue.main.async { if atLatest != value { atLatest = value } }
        }
        let follow = storage.length == 0 || Self.isAtLatest(scroll)
        let selected = text.selectedRange(), position = scroll.contentView.bounds.origin
        if context.coordinator.show(segments: segments, conversation: conversation, completedText: completedText, in: storage) {
            let length = storage.length
            text.setSelectedRange(NSRange(location: min(selected.location, length),
                                          length: min(selected.length, max(0, length - selected.location))))
            text.layoutManager?.ensureLayout(for: text.textContainer!)
            if follow && selected.length == 0 { text.scrollToEndOfDocument(nil) }
            else { scroll.contentView.scroll(to: position); scroll.reflectScrolledClipView(scroll.contentView) }
        }
        if context.coordinator.latestRequest != latestRequest {
            context.coordinator.latestRequest = latestRequest
            text.setSelectedRange(NSRange(location: storage.length, length: 0))
            text.scrollToEndOfDocument(nil)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        return CGSize(width: width, height: Self.fittedHeight(segments: segments, conversation: conversation,
                                                              completedText: completedText, width: width))
    }
    /// The page relayouts every second for its clock, so measuring a two-hour meeting whole
    /// stalled the app. A prefix is never taller than the whole text, so measuring stops once
    /// one reaches the clamp; a short transcript is still measured whole, exactly as before.
    static func fittedHeight(segments: [LiveVoiceSegment], conversation: Bool, completedText: String?, width: CGFloat) -> CGFloat {
        var limit = 16
        while true {
            let prefix = attributedText(segments: segments, conversation: conversation, completedText: completedText, limit: limit)
            let used = ceil(prefix.text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8
            if prefix.whole || used >= maximumHeight { return min(maximumHeight, max(minimumHeight, used)) }
            limit *= 2
        }
    }
    private static func isAtLatest(_ scroll: NSScrollView) -> Bool {
        guard let document = scroll.documentView else { return true }
        return document.bounds.height - scroll.contentView.bounds.maxY < 30
    }
    /// The first `limit` turns, or about `limit` turns' worth of a saved transcript, and whether that was all of it.
    fileprivate static func attributedText(segments: [LiveVoiceSegment], conversation: Bool, completedText: String?,
                                           limit: Int) -> (text: NSAttributedString, whole: Bool) {
        let style = TurnStyle()
        if let completedText {
            let prefix = completedText.prefix(limit > Int.max / 200 ? Int.max : limit * 200)
            return (NSAttributedString(string: String(prefix), attributes: style.body), prefix.endIndex == completedText.endIndex)
        }
        let result = NSMutableAttributedString()
        for index in segments.indices.prefix(limit) { append(index, of: segments, conversation: conversation, style: style, to: result) }
        return (result, limit >= segments.count)
    }

    fileprivate struct TurnStyle {
        let body: [NSAttributedString.Key: Any]
        let label: [NSAttributedString.Key: Any]
        init() {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 12
            // Dictate's editor reads at the title 3 size (15 pt standard); both grow with larger text.
            body = [.font: NSFont.preferredFont(forTextStyle: .title3), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            label = [.font: NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium),
                     .foregroundColor: NSColor.secondaryLabelColor]
        }
    }

    /// The words a speaker has not yet confirmed carry on their confirmed turn (#377): the same
    /// paragraph, quieter, rather than a second speaker line at every commit while they talk.
    static func continues(_ turn: LiveVoiceSegment, with next: LiveVoiceSegment) -> Bool {
        turn.source == next.source && turn.isFinal && !next.isFinal && next.start - turn.end < LiveVoiceTurns.pauseSeconds
    }

    /// One turn after its separator from the turn before; in a conversation, under its speaker line.
    fileprivate static func append(_ index: Int, of segments: [LiveVoiceSegment], conversation: Bool,
                                   style: TurnStyle, to result: NSMutableAttributedString) {
        let segment = segments[index]
        let paragraph = conversation && !(index > 0 && continues(segments[index - 1], with: segment))
        if index > 0 { result.append(NSAttributedString(string: paragraph ? "\n\n" : " ", attributes: style.body)) }
        if paragraph {
            let minutes = max(0, Int(segment.start)) / 60, seconds = max(0, Int(segment.start)) % 60
            result.append(NSAttributedString(string: "\(segment.source.label)  ·  \(minutes):\(String(format: "%02d", seconds))\n",
                                             attributes: style.label))
        }
        var body = style.body
        if !segment.isFinal { body[.foregroundColor] = NSColor.secondaryLabelColor }
        result.append(NSAttributedString(string: segment.text, attributes: body))
    }

    final class Coordinator {
        var latestRequest = 0
        var reportLatest: ((Bool) -> Void)?
        var observation: NSObjectProtocol?
        /// The turns the text holds and where each one ends, so an update rewrites only from the
        /// first turn that changed (#377). Live words change at the end several times a second;
        /// rebuilding and comparing a two-hour transcript for each change held the main thread.
        private var shown: [LiveVoiceSegment] = []
        private var ends: [Int] = []
        private var shownConversation = false
        private var shownCompleted: String?
        deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }

        /// Brings the text to these turns, or to the saved transcript; false when it already shows them.
        func show(segments: [LiveVoiceSegment], conversation: Bool, completedText: String?, in storage: NSTextStorage) -> Bool {
            if let completedText {
                guard completedText != shownCompleted else { return false }
                storage.setAttributedString(LiveTranscriptText.attributedText(segments: [], conversation: conversation,
                                                                              completedText: completedText, limit: .max).text)
                shown = []; ends = []; shownCompleted = completedText
                return true
            }
            var first = 0
            if shownCompleted == nil, shownConversation == conversation, ends.count == shown.count, (ends.last ?? 0) == storage.length {
                let common = min(shown.count, segments.count)
                while first < common, shown[first] == segments[first] { first += 1 }
                if first == shown.count, first == segments.count { return false }
            }
            // A turn's separator depends on the turn before it, which is unchanged here.
            let keep = first == 0 ? 0 : ends[first - 1], style = TurnStyle()
            let changed = NSMutableAttributedString()
            var next = Array(ends.prefix(first))
            for index in first..<segments.count {
                LiveTranscriptText.append(index, of: segments, conversation: conversation, style: style, to: changed)
                next.append(keep + changed.length)
            }
            storage.replaceCharacters(in: NSRange(location: keep, length: storage.length - keep), with: changed)
            shown = segments; ends = next; shownConversation = conversation; shownCompleted = nil
            return true
        }
    }
}
