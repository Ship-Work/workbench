import SwiftUI

enum CaptureHistoryAccessibility {
    static func context(for capture: Transcript, history: [Transcript] = [], locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let timestamp = formatter.string(from: capture.date)
        let collisions = history.filter { formatter.string(from: $0.date) == timestamp }
        let suffix = collisions.count > 1 && collisions.contains(where: { $0.id == capture.id })
            ? ", capture \(collisions.firstIndex(where: { $0.id == capture.id })! + 1) of \(collisions.count)" : ""
        return "captured \(timestamp)\(suffix)"
    }
    static func label(_ action: String, context: String) -> String { "\(action), \(context)" }
}

struct TranscriptRemoval {
    let transcript: Transcript
    let includesRecording: Bool
}

/// A transcript list's page-level sheets: read-only transcript review, the details
/// editor and the removal confirmation that names a saved recording. They sit
/// on the page, not the row, so a row leaving a lazy list cannot close them.
struct TranscriptHistoryDialogs: ViewModifier {
    @ObservedObject var model: AppModel
    @Binding var review: TranscriptReview?
    @Binding var details: Transcript?
    @Binding var removal: TranscriptRemoval?
    @Binding var recording: Transcript?
    private var removalIncludesRecording: Bool { removal?.includesRecording == true }

    func body(content: Content) -> some View {
        content
            .sheet(item: $review) { item in
                TranscriptReviewView(model: model, review: item) { review = nil }
            }
            .sheet(item: $recording) { item in
                MeetingRecordingReviewView(meetings: model.meetings, playback: model.meetings.recordingPlayback,
                                           transcript: item) { recording = nil }
            }
            .sheet(item: $details) { item in
                TranscriptMetadataEditor(transcript: item, library: model.historyLibrary, suggest: { model.onSuggestTranscriptDetails?(item.id) })
            }
            .confirmationDialog(removalIncludesRecording ? "Remove this transcript and its recording?" : "Remove this saved transcript?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                Button(removalIncludesRecording ? "Remove transcript and recording" : "Remove transcript", role: .destructive) {
                    if let removal { model.removeTranscript(removal.transcript, includingRecording: removal.includesRecording) }
                    removal = nil
                }
                Button("Cancel", role: .cancel) { removal = nil }
            } message: {
                Text(removalIncludesRecording
                     ? "Permanently removes this saved transcript and its recording from this Mac. Saved selections will show it as missing. Existing handoff snapshots and exported copies are kept."
                     : "Saved selections will show this item as missing. Existing handoff snapshots are kept.")
            }
    }
}

/// One saved transcript as History lists it, with the actions it has always
/// had. Its sheets belong to the page (see `TranscriptHistoryDialogs`), so the
/// row only names which transcript they show.
struct TranscriptHistoryRow: View {
    @ObservedObject var model: AppModel
    /// Observed here, so a row's checkbox follows the shared selection.
    @ObservedObject var library: WorkbenchHistoryModel
    let item: Transcript
    /// The captures to tell identical times apart among. Passing only those in
    /// the same second keeps a long history from being scanned for every row.
    var history: [Transcript]
    @Binding var review: TranscriptReview?
    @Binding var details: Transcript?
    @Binding var removal: TranscriptRemoval?
    @Binding var recording: Transcript?
    /// Copy and the context menu's Copy, which History confirms; the confirmation and any
    /// problem show here only while they belong to this transcript.
    let copy: () -> Void
    var copyConfirmation: String?
    var copyProblem: String?
    /// A meeting or call's own follow-up door, the one Meetings and Home have.
    var prepareFollowUp: ((UUID) -> Void)? = nil
    /// A door asked History to show this transcript (#134): its heading line is then a focus stop
    /// that takes keyboard and VoiceOver focus, as a revealed task's heading does. Focus is not
    /// selection; the checkbox and the shared selection are untouched.
    var shown = false
    var focus: FocusState<UUID?>.Binding
    var voiceOverFocus: AccessibilityFocusState<UUID?>.Binding

    var body: some View {
        let context = CaptureHistoryAccessibility.context(for: item, history: history)
        let metadata = library.metadata(for: item.id)
        let ref = WorkbenchItemReference(kind: .transcript, id: item.id)
        let words = TextRules.wordCount(item.text)
        let hasRecording = metadata.isConversation || model.meetings.hasRecording(for: item.id)
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(get: { library.selected.contains(ref) }, set: { include in
                var refs = library.selected
                if include { refs.insert(ref) } else { refs.remove(ref) }
                library.setSelected(refs)
            })).toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel(CaptureHistoryAccessibility.label("Select transcript, " + (metadata.heading.isEmpty ? metadata.purpose.title : metadata.heading), context: context))
            VStack(alignment: .leading, spacing: 10) {
                let heading = metadata.heading
                if heading.isEmpty {
                    HStack {
                        Image(systemName: "mic").foregroundStyle(Workbench.accent).accessibilityHidden(true)
                        Text(HistoryDate.time(item.date))
                        Text(metadata.purpose.title).fontWeight(.medium)
                        Spacer(); Text(TextRules.wordCountLabel(words))
                    }.font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(CaptureHistoryAccessibility.label("Transcript, " + metadata.purpose.title, context: context) + ", " + TextRules.wordCountLabel(words))
                        .focusable(shown).focused(focus, equals: item.id)
                        .accessibilityFocused(voiceOverFocus, equals: item.id)
                } else {
                    // A meeting, a call or a named capture leads with its name, then when, where and how long:
                    // what you recognise it by, not its opening small talk.
                    let facts = TranscriptFacts.line(item, metadata: metadata, words: words, day: false)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: metadata.isConversation ? WorkbenchHome.symbol(of: "meeting") : "mic")
                                .foregroundStyle(Workbench.accent).accessibilityHidden(true)
                            Text(heading).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(facts).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel(CaptureHistoryAccessibility.label(heading + ", " + facts, context: context))
                        .focusable(shown).focused(focus, equals: item.id)
                        .accessibilityFocused(voiceOverFocus, equals: item.id)
                }
                let fields = [metadata.person, metadata.company] + metadata.tags.map { "#" + $0 }
                if fields.contains(where: { !$0.isEmpty }) { Text(fields.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                if let summary = metadata.summary, !summary.about.isEmpty {
                    // What it was about, then where the words came from: the transcript is one click away.
                    TranscriptAbout(summary: summary, lineLimit: 3)
                } else {
                    Text(item.text).font(Workbench.bodyText).lineLimit(metadata.isConversation ? 4 : 8)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(metadata.isConversation ? .secondary : .primary)
                }
                if !metadata.captureNotes.isEmpty {
                    WorkbenchNote(metadata.captureNotes.joined(separator: " "))
                }
                if hasRecording {
                    HStack {
                        Label("Original recording", systemImage: "waveform").foregroundStyle(.secondary)
                        Spacer()
                        Button("Review recording") { recording = item }
                            .accessibilityLabel(CaptureHistoryAccessibility.label("Review original recording", context: context))
                    }.font(.callout).buttonStyle(.borderless)
                }
                // One row font for links and the More menu, so a menu title cannot render larger
                // than the links beside it. Review transcript's Wording switch shows the original
                // words, so the row needs no separate Original link.
                HStack(spacing: 12) {
                    Button("Copy", action: copy).accessibilityLabel(CaptureHistoryAccessibility.label("Copy", context: context))
                    Button("Review transcript") { review = TranscriptReview(transcript: item) }
                        .accessibilityLabel(CaptureHistoryAccessibility.label("Review transcript", context: context))
                    if metadata.isConversation, let prepareFollowUp {
                        Button("Prepare follow-up…") { prepareFollowUp(item.id) }
                            .help("Start task runs it here and brings its result to History; Copy instructions copies it for your own assistant.")
                            .accessibilityLabel(CaptureHistoryAccessibility.label("Prepare follow-up", context: context))
                    }
                    Button("Details…") { details = item }.accessibilityLabel(CaptureHistoryAccessibility.label("Details", context: context))
                    Menu {
                        moreActions
                    } label: { Text("More").font(.callout) }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(CaptureHistoryAccessibility.label("More transcript actions", context: context))
                    // Kept after More, where the Spacer absorbs its width while nothing shows (Fit rule 7).
                    ConfirmationLabel(text: copyConfirmation, reserving: ["Copied"])
                    Spacer()
                    Button {
                        removal = TranscriptRemoval(transcript: item, includesRecording: model.meetings.hasRecording(for: item.id))
                    } label: { Image(systemName: "trash") }
                        .accessibilityLabel(CaptureHistoryAccessibility.label("Remove transcript", context: context))
                        .help("Remove transcript…")
                }.buttonStyle(.borderless).font(.callout)
                if let copyProblem { WorkbenchNote(copyProblem, font: .caption) }
            }
        }.workbenchCard(outlined: shown)
            // The row's whole action set, where a Mac person looks for it first.
            .contextMenu {
                Button("Copy", action: copy)
                Button("Review transcript") { review = TranscriptReview(transcript: item) }
                Button("Details…") { details = item }
                if hasRecording { Button("Review recording") { recording = item } }
                if metadata.isConversation, let prepareFollowUp { Button("Prepare follow-up…") { prepareFollowUp(item.id) } }
                Divider()
                moreActions
                Divider()
                Button("Remove transcript…", role: .destructive) {
                    removal = TranscriptRemoval(transcript: item, includesRecording: model.meetings.hasRecording(for: item.id))
                }
            }
    }

    @ViewBuilder private var moreActions: some View {
        Button("Open in Dictate") { model.openTranscript(item) }
        Button("Save prompt") { model.savePrompt(item.text) }
        Button("Export current text…") { model.exportCapture(item, version: .cleaned) }
        Button("Export original wording…") { model.exportCapture(item, version: .original) }
    }
}

/// A transcript's facts after its name: when, the app it recorded, how long and how many words.
enum TranscriptFacts {
    /// `day: false` under History's day headings, where a row says only its time.
    static func line(_ item: Transcript, metadata: TranscriptMetadata, words: Int, day: Bool = true) -> String {
        let named = !metadata.title.isEmpty || !(metadata.summary?.title ?? "").isEmpty
        var parts = [day ? HistoryDate.text(item.date) : HistoryDate.time(item.date)]
        // The fallback name already says the app ("Zoom meeting"); a real name leaves it to this line.
        if named, !metadata.app.isEmpty { parts.append(metadata.app) }
        if metadata.isConversation, item.seconds > 0 { parts.append(HomeMeetings.duration(item.seconds)) }
        parts.append(TextRules.wordCountLabel(words))
        return parts.joined(separator: " · ")
    }
}

/// What a meeting was about, as written on this Mac, marked so it never reads as the person's words.
struct TranscriptAbout: View {
    let summary: TranscriptSummary
    var lineLimit: Int? = nil
    var showsPoints = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.about).font(Workbench.bodyText).lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: lineLimit == nil)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if showsPoints, !summary.points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(point).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                }.font(Workbench.bodyText)
            }
            Label(lineLimit == nil ? TranscriptAbout.receipt : "Written on this Mac", systemImage: "sparkles")
                .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                .help(TranscriptAbout.receipt)
        }
    }

    static let receipt = "Written on this Mac by Apple Intelligence · your words are unchanged"
}
