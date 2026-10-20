import Foundation

/// Shared presentation contract for Meetings and Dictate. Capture owns these
/// facts; a view never infers recording health from recognizer progress.
enum LiveVoicePhase: String, Codable, Sendable {
    case idle, preparing, listening, paused, reconnecting, finishing, completed, recoverableFailure
}

enum LiveVoiceSource: String, Codable, CaseIterable, Sendable {
    case microphone, app
    var label: String { self == .microphone ? "You" : "Others" }
}

struct LiveVoiceSourceStatus: Equatable, Sendable {
    enum Health: String, Sendable { case waiting, receiving, quiet, paused, reconnecting, unavailable }
    var source: LiveVoiceSource
    var name: String
    var health: Health = .waiting
    var level: Double = 0
    var message: String?
}

struct LiveVoiceSegment: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var source: LiveVoiceSource
    var start: Double
    var end: Double
    var text: String
    var isFinal: Bool
}

struct LiveVoiceSnapshot: Equatable, Sendable {
    var sessionID: UUID?
    var phase: LiveVoicePhase = .idle
    var elapsed: Double = 0
    var sources: [LiveVoiceSourceStatus] = []
    var segments: [LiveVoiceSegment] = []
    var recognitionDelayed = false
    /// The live pass has missed or doubled words at a boundary or a backlog (#280): live words
    /// continue, and the saved transcript comes from the original audio at finish.
    var liveIncomplete = false
    /// The live pass stopped for good (a recogniser error, invalid timing, mailbox overflow or a
    /// journal write failure): no more live words; the saved transcript comes from the original audio.
    var liveStopped = false
    var message: String?

    var text: String { segments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ") }
    var hasProvisionalText: Bool { segments.contains { !$0.isFinal && !$0.text.isEmpty } }
    var isActive: Bool { [.preparing, .listening, .paused, .reconnecting, .finishing].contains(phase) }
}

/// A checkpoint records confirmed words, never a provisional UI hypothesis.
/// It lives beside owned audio and is not another History store.
struct LiveVoiceCheckpoint: Codable, Equatable, Sendable {
    var formatVersion = 1
    var sessionID: UUID
    var segments: [LiveVoiceSegment] = []
    var completedThrough: [String: Double] = [:]
    var complete = false
    var notes: [String] = []

    /// The saved original wording: the conversation's words without labels, a turn at a time.
    /// Two speakers are never zipped together word by word (#377), and a handoff that carries
    /// the conversation adds nothing from it (HandoffJobStore.originalAddsWording).
    var text: String { turns.map(\.text).joined(separator: " ") }
    var orderedSegments: [LiveVoiceSegment] {
        segments.sorted { ($0.start, $0.source.rawValue) < ($1.start, $1.source.rawValue) }
    }
    /// The turns a live meeting saves, without the microphone's copy of the other side (#377).
    var turns: [LiveVoiceSegment] { LiveVoiceTurns.group(segments) }
    var conversation: String {
        turns.map { "\($0.source.label): \($0.text)" }.joined(separator: "\n\n")
    }
}

enum LiveVoiceTurns {
    /// A pause this long starts a new paragraph for the same speaker (#377). People pause for a
    /// second or more inside one turn, so 0.8 s split a continuous speaker at almost every
    /// sentence. Two seconds is twice the silence a conversation usually leaves unremarked, and
    /// the saved-audio path already joins a speaker's utterances across shorter gaps
    /// (MeetingConversation.conversation), so a meeting reads the same whichever path saved it.
    /// A real turn change splits at once: the other source's words come between.
    static let pauseSeconds = 2.0

    /// Store word timing, project it into readable turns. Each source's words become utterances
    /// cut as the saved-audio path cuts a track, the microphone's copy of the other side is
    /// dropped (SpeakerEcho), and utterances take their turns in start order: a source's
    /// consecutive utterances stay one turn until the other source speaks or it pauses for
    /// `pauseSeconds`. Overlapping speakers alternate by utterance, never word by word, and
    /// different sources remain present when they overlap with their own words or
    /// independently say the same words.
    static func group(_ words: [LiveVoiceSegment]) -> [LiveVoiceSegment] {
        let spoken = words.filter { !$0.text.isEmpty }
        let theirs = utterances(spoken.filter { $0.source == .app })
        let mine = utterances(spoken.filter { $0.source == .microphone }, during: theirs)
        let echoes = SpeakerEcho.echoes(mine.map(SpeakerEcho.Utterance.init(_:)), of: theirs.map(SpeakerEcho.Utterance.init(_:)))
        let kept = zip(mine, echoes).compactMap { $1 ? nil : $0 } + theirs
        var turns: [LiveVoiceSegment] = []
        for utterance in kept.sorted(by: { ($0.start, $0.source.rawValue) < ($1.start, $1.source.rawValue) }) {
            if let last = turns.last, last.source == utterance.source, last.isFinal == utterance.isFinal,
               utterance.start - last.end < pauseSeconds {
                turns[turns.count - 1].text += " " + utterance.text
                turns[turns.count - 1].end = max(last.end, utterance.end)
            } else { turns.append(utterance) }
        }
        return turns
    }

    /// One source's words as utterances, cut where the saved-audio path cuts a track (a short
    /// pause or the longest clip) and where confirmed words meet provisional ones. Live words
    /// know their times, so the microphone's are also cut where the other side starts or stops
    /// speaking: a quick reply after the other side finishes is judged on its own words, not
    /// dropped with the echo before it. `during` is the other side's utterances in time order.
    private static func utterances(_ words: [LiveVoiceSegment], during speech: [LiveVoiceSegment] = []) -> [LiveVoiceSegment] {
        var result: [LiveVoiceSegment] = [], heard: [Bool] = [], next = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            let at = (word.start + word.end) / 2
            while next < speech.count, speech[next].end + SpeakerEcho.lagSeconds < at { next += 1 }
            let over = next < speech.count && speech[next].start - SpeakerEcho.lagSeconds <= at
            if let last = result.last, last.isFinal == word.isFinal, heard.last == over,
               word.start - last.end < SpeakerEcho.pauseSeconds, word.end - last.start <= SpeakerEcho.longestSeconds {
                result[result.count - 1].text += " " + word.text
                result[result.count - 1].end = max(last.end, word.end)
            } else { result.append(word); heard.append(over) }
        }
        return result
    }
}

/// On laptop speakers the microphone also hears the other side (#377). One rule for live words
/// (LiveVoiceTurns) and the saved-audio conversation (MeetingConversation): a microphone
/// utterance is an echo when it mostly overlaps an app utterance in time and repeats its words.
enum SpeakerEcho {
    /// The saved-audio path cuts each track into utterances at this much silence and at this
    /// length (MeetingConversation), and live words are cut the same way, so both judge the
    /// same shapes.
    static let pauseSeconds = 0.6
    static let longestSeconds = 25.0
    /// The microphone hears the app's sound a moment after it plays, and recognisers place word
    /// boundaries a little loosely; this much either side of the other side's speech is during it.
    static let lagSeconds = 0.3

    struct Utterance: Equatable, Sendable {
        var start: Double
        var end: Double
        var text: String
    }

    static func isEcho(_ mine: Utterance, of theirs: Utterance) -> Bool {
        let length = max(mine.end - mine.start, 0.001)
        guard min(mine.end, theirs.end) - max(mine.start, theirs.start) >= 0.5 * length else { return false }
        return similarity(mine.text, theirs.text) >= 0.5 || containment(mine, in: theirs) >= 0.75
    }

    /// Which microphone utterances echo an app utterance, in the microphone's order. Only app
    /// utterances that overlap in time are compared, so a long call costs little more than a short one.
    static func echoes(_ mine: [Utterance], of theirs: [Utterance]) -> [Bool] {
        let theirs = theirs.sorted { $0.start < $1.start }
        // The latest end among the first n app utterances: past it, nothing earlier can overlap.
        var reach: [Double] = []
        for utterance in theirs { reach.append(max(reach.last ?? -.infinity, utterance.end)) }
        return mine.map { heard in
            var low = 0, high = theirs.count
            while low < high {
                let middle = (low + high) / 2
                if theirs[middle].start < heard.end { low = middle + 1 } else { high = middle }
            }
            var index = low - 1
            while index >= 0, reach[index] > heard.start {
                if isEcho(heard, of: theirs[index]) { return true }
                index -= 1
            }
            return false
        }
    }

    /// Word overlap between two recognised texts, from 0 to 1.
    static func similarity(_ first: String, _ second: String) -> Double {
        let a = Set(words(first)), b = Set(words(second))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// For a microphone utterance no longer than the app's, the share of its words the app said
    /// in the same order around the same time (#377). Overlap measured both ways never drops a
    /// short fragment inside a long utterance; this does, and a reply such as "yes" is still
    /// kept unless the other side said it then. A saved clip has no word times, so the app's
    /// words are spread evenly over its utterance and only those within a few seconds count.
    static func containment(_ mine: Utterance, in theirs: Utterance) -> Double {
        let said = words(mine.text), heard = words(theirs.text)
        guard !said.isEmpty, said.count <= heard.count else { return 0 }
        let length = max(theirs.end - theirs.start, 0.001), slack = max(2, 0.2 * length)
        let near = heard.indices.filter { index in
            let at = theirs.start + (Double(index) + 0.5) / Double(heard.count) * length
            return at >= mine.start - slack && at <= mine.end + slack
        }.map { heard[$0] }
        // The most of the microphone's words the app said in the same order, one row at a time.
        var row = [Int](repeating: 0, count: near.count + 1)
        for word in said {
            var diagonal = 0
            for index in near.indices {
                let above = row[index + 1]
                row[index + 1] = word == near[index] ? diagonal + 1 : max(above, row[index])
                diagonal = above
            }
        }
        return Double(row[near.count]) / Double(said.count)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

extension SpeakerEcho.Utterance {
    init(_ segment: LiveVoiceSegment) { self.init(start: segment.start, end: segment.end, text: segment.text) }
}
