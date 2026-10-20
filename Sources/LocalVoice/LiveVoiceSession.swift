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

    var text: String { orderedSegments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ") }
    var orderedSegments: [LiveVoiceSegment] {
        segments.sorted { ($0.start, $0.source.rawValue) < ($1.start, $1.source.rawValue) }
    }
    var conversation: String {
        LiveVoiceTurns.group(orderedSegments).map { "\($0.source.label): \($0.text)" }.joined(separator: "\n\n")
    }
}

enum LiveVoiceTurns {
    /// Store word timing, project adjacent same-source words into readable turns. Different
    /// sources remain present even when they overlap or independently say the same words.
    static func group(_ words: [LiveVoiceSegment]) -> [LiveVoiceSegment] {
        var turns: [LiveVoiceSegment] = []
        for word in words.sorted(by: { ($0.start, $0.source.rawValue) < ($1.start, $1.source.rawValue) }) where !word.text.isEmpty {
            if let last = turns.last, last.source == word.source, last.isFinal == word.isFinal, word.start - last.end <= 0.8 {
                turns[turns.count - 1].text += " " + word.text
                turns[turns.count - 1].end = max(last.end, word.end)
            } else { turns.append(word) }
        }
        return turns
    }
}

/// On laptop speakers the microphone also hears the other side (#377). The saved-audio
/// conversation's rule (MeetingConversation), kept beside the live words so they can share it:
/// a microphone utterance is an echo when it mostly overlaps an app utterance in time and
/// repeats its words.
enum SpeakerEcho {
    /// The saved-audio path cuts each track into utterances at this much silence and at this
    /// length (MeetingConversation).
    static let pauseSeconds = 0.6
    static let longestSeconds = 25.0

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
