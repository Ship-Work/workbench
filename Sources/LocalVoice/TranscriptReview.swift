import AppKit
import Combine
import SwiftUI

/// One read-only visit to an exact saved transcript. It is page-owned, so a
/// History row leaving the lazy list cannot dismiss it or select another item.
/// No draft, selection, recording or persistent store belongs to this value.
struct TranscriptReview: Identifiable {
    let transcript: Transcript
    var version: TranscriptExportVersion = .cleaned
    var id: UUID { transcript.id }

    static func find(_ id: UUID, in history: [Transcript]) -> Self? {
        history.first { $0.id == id }.map { Self(transcript: $0) }
    }

    var text: String { TranscriptExport.text(for: transcript, version: version) }
}

/// Feedback belongs to this review visit. Success is brief; a failed copy or
/// export remains here until another explicit attempt succeeds or review ends.
/// Copy build details, Copy permission details and Home's Copy transcript
/// confirm through the same owner.
@MainActor
final class TranscriptReviewFeedback: ObservableObject {
    @Published private(set) var confirmation: LocalConfirmation<String>?
    @Published private(set) var problem: String?
    private let clock: MonotonicClock
    private let announce: @MainActor (String) -> Void
    private let expiry: NoticeExpiry

    init(clock: @escaping MonotonicClock = Monotonic.now, announce: @escaping @MainActor (String) -> Void = { FeedbackAnnouncement.post($0) }) {
        self.clock = clock; self.announce = announce
        expiry = NoticeExpiry(clock: clock)
    }

    func finish(_ success: String?, problem: String? = nil) {
        expiry.cancel()
        self.problem = problem
        guard let success else { confirmation = nil; return }
        let confirmation = LocalConfirmation(success, at: clock())
        self.confirmation = confirmation
        expiry.schedule(confirmation.lifetime) { [weak self] event in self?.expire(event) }
        // The label goes after four seconds; VoiceOver still hears what happened.
        announce(success)
    }

    /// Ends the confirmation only if it is still this one and it is due.
    func expire(_ event: UUID) {
        guard let confirmation, confirmation.lifetime.event == event else { return }
        if confirmation.lifetime.isDue(at: clock()) { self.confirmation = nil }
        else { expiry.schedule(confirmation.lifetime) { [weak self] event in self?.expire(event) } }
    }
}

struct TranscriptReviewView: View {
    @Environment(\.pageSectionFrames) private var sectionFrames
    @ObservedObject var model: AppModel
    let review: TranscriptReview
    let done: () -> Void
    @State private var version: TranscriptExportVersion
    @State private var recording: Transcript?
    @StateObject private var feedback = TranscriptReviewFeedback()

    init(model: AppModel, review: TranscriptReview, done: @escaping () -> Void) {
        self.model = model; self.review = review; self.done = done
        _version = State(initialValue: review.version)
    }

    private var item: Transcript { review.transcript }
    private var text: String { TranscriptExport.text(for: item, version: version) }
    private var recordingAvailable: Bool {
        let purpose = model.historyLibrary.metadata(for: item.id).purpose
        return purpose == .meeting || purpose == .call || model.meetings.hasRecording(for: item.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transcript").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
            HStack {
                Text(HistoryDate.text(item.date))
                Text(model.historyLibrary.metadata(for: item.id).purpose.title)
                Spacer()
                Text("\(TextRules.wordCount(text)) words").monospacedDigit()
            }.font(.subheadline).foregroundStyle(.secondary)
            Picker("Wording", selection: $version) {
                Text("Current text").tag(TranscriptExportVersion.cleaned)
                Text("Original wording").tag(TranscriptExportVersion.original)
            }.pickerStyle(.segmented).accessibilityLabel("Transcript wording")
            VStack(alignment: .leading, spacing: 0) {
                // Capture notes are short, so they stay in view above the words that scroll.
                let notes = model.historyLibrary.metadata(for: item.id).captureNotes
                if !notes.isEmpty {
                    WorkbenchNote(notes.joined(separator: "\n")).frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top], Workbench.tilePadding)
                }
                TranscriptDocumentText(text: text)
            }.background(Workbench.surface, in: RoundedRectangle(cornerRadius: Workbench.tileRadius))
                // The hairline Dictate's transcript has, so the text box reads as one on macOS 26.
                .overlay(RoundedRectangle(cornerRadius: Workbench.tileRadius).strokeBorder(Workbench.border))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sectionFrames?("history.transcript-review.text", $0) }
                .accessibilityIdentifier("history.transcript-review.text")
            HStack(spacing: 12) {
                // The current-wording copy owner also retains its exact failure
                // recovery. Original wording can be selected or exported without
                // pretending that recovery points at those different words.
                Button("Copy current text") {
                    model.copyCapture(item)
                    if model.status == TextDelivery.copiedMessage { feedback.finish("Copied current text") }
                    else { feedback.finish(nil, problem: model.status) }
                }.disabled(item.text.isEmpty)
                Button(version == .original ? "Export original…" : "Export current text…") {
                    if let saved = model.exportCapture(item, version: version) {
                        if saved { feedback.finish("Saved") }
                        else { feedback.finish(nil, problem: model.attention?.message ?? "The transcript could not be saved.") }
                    }
                }
                Spacer()
                if recordingAvailable {
                    Button("Review recording") { recording = item }
                }
            }.controlSize(.regular)
            if let problem = feedback.problem {
                ScrollView {
                    WorkbenchNote(problem).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 60)
            } else {
                ConfirmationLabel(text: feedback.confirmation?.kind, reserving: ["Copied current text", "Saved"])
            }
        }.padding(Workbench.pagePadding)
            // A sheet the person can make bigger for a long meeting. macOS opens a sheet at its
            // minimum, so the minimum is the size it has always opened at.
            .frame(minWidth: 640, idealWidth: 640, maxWidth: 1000, minHeight: 560, idealHeight: 560, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sectionFrames?("history.transcript-review", $0) }
            .accessibilityIdentifier("history.transcript-review")
            .onExitCommand(perform: done)
            // Escape is Done even when no control has keyboard focus; the visible Done is Return.
            .background { Button("Done", action: done).keyboardShortcut(.cancelAction).hidden() }
            .sheet(item: $recording) { item in
                MeetingRecordingReviewView(meetings: model.meetings, playback: model.meetings.recordingPlayback,
                                           transcript: item) { recording = nil }
            }
    }
}

/// The saved words as native, read-only text. SwiftUI's Text lays out every line of
/// a long meeting before the sheet appears, and again on each wording switch; a text
/// view lays out only what is in view, so a two-hour meeting opens as fast as a note.
private struct TranscriptDocumentText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let view = TranscriptDocumentTextView(usingTextLayoutManager: false)
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: Workbench.tilePadding, height: Workbench.tilePadding)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.layoutManager?.allowsNonContiguousLayout = true
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.setAccessibilityLabel("Transcript")
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        // A wording switch reads from the start, as a fresh review does.
        view.textStorage?.setAttributedString(Self.document(text))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.scroll(.zero)
    }

    private static func document(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
        return NSAttributedString(string: text, attributes: [.font: NSFont.preferredFont(forTextStyle: .body),
                                                             .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }
}

private final class TranscriptDocumentTextView: NSTextView {
    /// A reading measure: long lines are hard to follow, so the words stop near 600 points
    /// with a little air between lines, however wide the sheet grows.
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        let width = max(0, min(size.width - 2 * textContainerInset.width, 600))
        if let container = textContainer, container.size.width != width {
            container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
    }

    /// Read-only words have no use for Return, so it stays the review's Done while the
    /// text has focus instead of a beep. Escape already reaches Done through the responder chain.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty,
           event.keyCode == 36 || event.keyCode == 76, window?.performKeyEquivalent(with: event) == true { return }
        super.keyDown(with: event)
    }
}
