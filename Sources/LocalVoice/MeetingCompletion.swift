import Foundation

/// Resolve saved wording when Copy is pressed, rather than using the live
/// transcript view or the meeting's completion-time display snapshot.
enum MeetingTranscriptCopy {
    /// What Copy puts on the clipboard. A meeting or call starts with its name and when, where and
    /// how long, so meetings pasted together into an assistant stay apart; a dictation is its words.
    static func text(_ item: Transcript, metadata: TranscriptMetadata, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard metadata.isConversation else { return item.text }
        return heading(item, metadata: metadata, locale: locale, timeZone: timeZone) + "\n\n" + item.text
    }

    /// The heading Copy puts over a meeting or call's words; none for a dictation.
    static func copyHeading(_ item: Transcript, metadata: TranscriptMetadata) -> String? {
        metadata.isConversation ? heading(item, metadata: metadata) : nil
    }

    /// "Harbour release and Northwind export" over "Zoom · 21 Oct 2026 at 10:02 · 42 min".
    static func heading(_ item: Transcript, metadata: TranscriptMetadata, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale); style.timeZone = timeZone
        let named = !metadata.title.isEmpty || !(metadata.summary?.title ?? "").isEmpty
        let facts = (named && !metadata.app.isEmpty ? [metadata.app] : []) + [item.date.formatted(style), HomeMeetings.duration(item.seconds)]
        return metadata.heading + "\n" + facts.joined(separator: " · ")
    }

    static func copy(_ id: UUID, in history: [Transcript], write: (Transcript) -> String?) -> String? {
        guard let transcript = history.first(where: { $0.id == id }) else {
            return "This transcript is no longer in History. Nothing was copied."
        }
        guard !transcript.text.isEmpty else {
            return "This saved transcript has no text to copy. Review it in History."
        }
        return write(transcript)
    }
}

extension AppModel {
    /// What Copy puts over a saved transcript's words, from its details.
    func copyHeading(_ item: Transcript) -> String? {
        MeetingTranscriptCopy.copyHeading(item, metadata: historyLibrary.metadata(for: item.id))
    }

    /// Copy uses History's complete current record and its existing clipboard
    /// receipt/recovery owner. It does not require a ready model or assistant.
    func copyMeetingTranscript(_ id: UUID) -> String? {
        MeetingTranscriptCopy.copy(id, in: history) { item in
            copyCapture(item, heading: copyHeading(item))
            return status == TextDelivery.copiedMessage ? nil : status
        }
    }
}
