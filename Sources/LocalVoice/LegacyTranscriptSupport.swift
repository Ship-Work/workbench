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

/// The saved note for a recording that Workbench finished rather than the person (#377): that it
/// did, then why, so the transcript read later in History says why its words end there.
enum MeetingSelfFinish {
    /// How every such note begins, so Home can rank it after a note about what the recording lost.
    static let prefix = "Workbench finished this recording itself."
    static let callAudioEnded = "The call app stopped using audio."
    static func note(_ why: String) -> String { prefix + " " + why }
}
enum MeetingFollowUp {
    /// The bundled Meeting notes and follow-up skill: what changed, decisions, actions with an owner and a
    /// date only when the speakers gave them, open questions and a follow-up message. Its own suggested
    /// task applies; a keyword guess never becomes a claimed decision.
    static let skillID = "workbench-meeting-follow-up"

    /// The review's skills for a door. A meeting's own Prepare follow-up… offers every transcript skill
    /// with the meeting skill preferred, so the person can still choose Coach or the general follow-up.
    /// The other single-transcript door, Suggest details, keeps the general skill alone, as before.
    /// A History selection keeps the pack's remembered choice.
    static func reviewSkills(meetingDoor: Bool, singleTranscript: Bool, builtIns: [TranscriptHandoffSkill],
                             packSkills: [TranscriptHandoffSkill], packPreferred: String?)
        -> (skills: [TranscriptHandoffSkill], preferred: String?) {
        if meetingDoor {
            let skills = builtIns + packSkills
            return (skills, skills.contains { $0.id == skillID } ? skillID : nil)
        }
        if singleTranscript { return ([.followUp], nil) }
        return (builtIns + packSkills, packPreferred)
    }
}