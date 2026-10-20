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

    /// Store word timing, project it into readable turns. The microphone's copy of the other side
    /// is dropped word by word (SpeakerEcho.echoed); each source's remaining words become
    /// utterances cut as the saved-audio path cuts a track, and utterances take their turns in
    /// start order: a source's consecutive utterances stay one turn until the other source speaks
    /// or it pauses for `pauseSeconds`. Overlapping speakers alternate by utterance, never word by
    /// word, and different sources remain present when they overlap with their own words or
    /// independently say the same words.
    static func group(_ words: [LiveVoiceSegment]) -> [LiveVoiceSegment] {
        let spoken = words.filter { !$0.text.isEmpty }.sorted { $0.start < $1.start }
        let app = spoken.filter { $0.source == .app }, microphone = spoken.filter { $0.source == .microphone }
        let theirs = utterances(app)
        let mine = utterances(zip(microphone, SpeakerEcho.echoed(microphone, of: app)).compactMap { $1 ? nil : $0 }, around: theirs)
        var turns: [LiveVoiceSegment] = []
        for utterance in (mine + theirs).sorted(by: { ($0.start, $0.source.rawValue) < ($1.start, $1.source.rawValue) }) {
            if let last = turns.last, last.source == utterance.source, last.isFinal == utterance.isFinal,
               utterance.start - last.end < pauseSeconds {
                turns[turns.count - 1].text += " " + utterance.text
                turns[turns.count - 1].end = max(last.end, utterance.end)
            } else { turns.append(utterance) }
        }
        return turns
    }

    /// One source's words, in start order, as utterances cut where the saved-audio path cuts a
    /// track (a short pause or the longest clip) and where confirmed words meet provisional ones.
    /// Your words are also cut where they move into or out of one of the other side's utterances
    /// (`around`, in time order), by which one they fall in, so they take their places around
    /// theirs even across a short pause of theirs.
    private static func utterances(_ words: [LiveVoiceSegment], around speech: [LiveVoiceSegment] = []) -> [LiveVoiceSegment] {
        var result: [LiveVoiceSegment] = [], within: [Int?] = [], next = 0
        for word in words {
            let at = (word.start + word.end) / 2
            while next < speech.count, speech[next].end < at { next += 1 }
            let inside = next < speech.count && speech[next].start <= at ? next : nil
            if let last = result.last, last.isFinal == word.isFinal, within[within.count - 1] == inside,
               word.start - last.end < SpeakerEcho.pauseSeconds, word.end - last.start <= SpeakerEcho.longestSeconds {
                result[result.count - 1].text += " " + word.text
                result[result.count - 1].end = max(last.end, word.end)
            } else { result.append(word); within.append(inside) }
        }
        return result
    }
}

/// On laptop speakers the microphone also hears the other side (#377). Live words carry their
/// times and are judged word by word (`echoed`); saved-audio utterances have none and are
/// judged whole (`isEcho`, for MeetingConversation).
enum SpeakerEcho {
    /// The saved-audio path cuts each track into utterances at this much silence and at this
    /// length (MeetingConversation), and live words are cut the same way, so both order turns alike.
    static let pauseSeconds = 0.6
    static let longestSeconds = 25.0
    /// How far the microphone's lane can sit from the app's for one word heard on both: the
    /// speaker and room add a moment, Bluetooth or AirPlay output much more, and the two lanes
    /// count time from their own first sample with no drift correction (MeetingAudio).
    static let lagRange = -1.0...2.5
    /// Where two recognisers place the same word: within a frame or so of each other.
    static let timingSlack = 0.1
    /// The lag is estimated for each 10 s of microphone words from the minute around them, so a
    /// slow drift between the two clocks is followed.
    static let lagBlockSeconds = 10.0, lagWindowSeconds = 60.0
    /// Fewer words than this agreeing on one lag in that minute is no echo: nothing is dropped.
    static let minimumLagMatches = 4

    /// Which microphone words echo the app's (#377). Live words carry their times, so the echo is
    /// found word by word: the lag between the lanes is the one most same-word pairs agree on in
    /// the minute around a word (within `lagRange`, at least `minimumLagMatches` of them), and a
    /// microphone word is an echo when the app said the same word at that lag, give or take
    /// `timingSlack`, each app word accounting for one microphone word at most. A word inside
    /// your own speech that matches by chance, with no echo word beside it, stays yours; a word
    /// or two the microphone heard differently between echo words, spelled like the app's words
    /// left there, goes with the echo. When unsure the words stay: a leaked echo is better than
    /// a lost word. Both lists in start order; the result is in the microphone's order.
    static func echoed(_ mine: [LiveVoiceSegment], of theirs: [LiveVoiceSegment]) -> [Bool] {
        let said = mine.map { normal($0.text) }, spoken = theirs.map { normal($0.text) }
        // Every pairing of a microphone word with the same app word at a lag an echo could have.
        var pairs: [(word: Int, app: Int, lag: Double)] = [], low = 0
        for (index, word) in mine.enumerated() where !said[index].isEmpty {
            while low < theirs.count, theirs[low].start < word.start - lagRange.upperBound { low += 1 }
            var app = low
            while app < theirs.count, theirs[app].start <= word.start - lagRange.lowerBound {
                if spoken[app] == said[index] { pairs.append((index, app, word.start - theirs[app].start)) }
                app += 1
            }
        }
        let lags = estimatedLags(mine, pairs)
        var used = [Bool](repeating: false, count: theirs.count), match = [Int?](repeating: nil, count: mine.count)
        var first = 0
        while first < pairs.count {
            var last = first
            while last < pairs.count, pairs[last].word == pairs[first].word { last += 1 }
            if let lag = lags[pairs[first].word], let best = pairs[first..<last]
                .filter({ !used[$0.app] && abs($0.lag - lag) <= timingSlack + 1e-9 })
                .min(by: { abs($0.lag - lag) < abs($1.lag - lag) }) {
                used[best.app] = true; match[best.word] = best.app
            }
            first = last
        }
        func close(_ earlier: Int, _ later: Int) -> Bool { mine[later].start - mine[earlier].end < pauseSeconds }
        // A run of one or two unmatched words between echo words, where the one to three app words
        // between those two are unmatched and spelled alike ("Lego" for "legal", "Mon day" for
        // "Monday"), even across a pause of theirs.
        var misheard = [Bool](repeating: false, count: mine.count), index = 0
        while index < mine.count {
            guard match[index] == nil else { index += 1; continue }
            var end = index
            while end < mine.count, match[end] == nil { end += 1 }
            if end - index <= 2, index > 0, end < mine.count, let left = match[index - 1], let right = match[end],
               right - left >= 2, right - left <= 4,
               (left + 1..<right).allSatisfy({ !used[$0] }),
               resembles((index..<end).map { said[$0] }.joined(), (left + 1..<right).map { spoken[$0] }.joined()) {
                for word in index..<end { misheard[word] = true }
            }
            index = end
        }
        // A match inside your own speech, your words close on both sides and neither of them echo, is
        // a coincidence; one at the edge of your words (a reply just before their pause) is their echo.
        let echo = mine.indices.map { match[$0] != nil || misheard[$0] }
        return mine.indices.map { index in
            guard match[index] != nil else { return misheard[index] }
            let beside = [index - 1, index + 1].filter { $0 >= 0 && $0 < mine.count && close(min($0, index), max($0, index)) }
            return beside.count < 2 || beside.contains { echo[$0] }
        }
    }

    /// The lag at each microphone word, or nil where no lag has enough agreement. `pairs` are in
    /// the microphone's order.
    private static func estimatedLags(_ mine: [LiveVoiceSegment], _ pairs: [(word: Int, app: Int, lag: Double)]) -> [Double?] {
        var result = [Double?](repeating: nil, count: mine.count), index = 0, low = 0, high = 0
        while index < mine.count {
            let block = (mine[index].start / lagBlockSeconds).rounded(.down)
            var last = index
            while last < mine.count, (mine[last].start / lagBlockSeconds).rounded(.down) == block { last += 1 }
            let center = (block + 0.5) * lagBlockSeconds
            while low < pairs.count, mine[pairs[low].word].start < center - lagWindowSeconds / 2 { low += 1 }
            high = max(high, low)
            while high < pairs.count, mine[pairs[high].word].start <= center + lagWindowSeconds / 2 { high += 1 }
            // The busiest band of 2 × `timingSlack`, and its middle.
            let lags = pairs[low..<high].map(\.lag).sorted()
            var best: (count: Int, lag: Double)?, end = 0
            for start in lags.indices {
                end = max(end, start)
                while end < lags.count, lags[end] - lags[start] <= 2 * timingSlack + 1e-9 { end += 1 }
                if end - start >= minimumLagMatches, end - start > best?.count ?? 0 { best = (end - start, (lags[start] + lags[end - 1]) / 2) }
            }
            for word in index..<last { result[word] = best?.lag }
            index = last
        }
        return result
    }

    /// Two recognisers' spellings of the same speech: the same letters, one in three changed,
    /// added or dropped (contract, contracts), or a shared start of three letters, or one the
    /// start of the other (OK, okay). Words are compared joined, so "Mon day" is "Monday".
    /// Words people say on their own as a reply; one heard inside the echo is kept as theirs, never merged.
    static let replyWords: Set<String> = ["no", "yes", "ok", "okay", "oh", "what", "wait", "sorry", "sure", "yeah", "right", "so"]
    static func resembles(_ heard: String, _ said: String) -> Bool {
        let a = Array(heard), b = Array(said), shorter = min(a.count, b.count)
        // Short words resemble almost anything ("no"/"not", "ok"/"on", "they"/"the"), and a reply word
        // is far more often yours than a mishearing, so only longer words, never a reply, count as alike.
        guard a == b || (shorter >= 4 && !replyWords.contains(heard)) else { return false }
        let prefix = zip(a, b).prefix { $0 == $1 }.count
        if a == b || prefix >= 3 || (prefix >= 2 && prefix == shorter) { return true }
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var diagonal = row[0]; row[0] = i + 1
            for (j, y) in b.enumerated() {
                let above = row[j + 1]
                row[j + 1] = x == y ? diagonal : 1 + min(diagonal, above, row[j])
                diagonal = above
            }
        }
        return row[b.count] <= max(1, shorter / 3)
    }

    struct Utterance: Equatable, Sendable {
        var start: Double
        var end: Double
        var text: String
    }

    /// The saved-audio rule: a microphone utterance is an echo when it mostly overlaps an app
    /// utterance in time and repeats its words, measured both ways, or, at three words or more,
    /// when the app said three quarters of them in the same order close to the same time. A
    /// reply of one or two words is judged only the first way, so it is never dropped for a word
    /// the other side happened to say nearby.
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

    /// For a microphone utterance of three words or more and no longer than the app's, the share
    /// of its words the app said in the same order around the same time (#377). Overlap measured
    /// both ways never drops a short fragment inside a long utterance; this does. A saved clip has
    /// no word times, so the app's words are spread evenly over its utterance and only those
    /// within a second, or a tenth of the utterance if that is longer, count.
    static func containment(_ mine: Utterance, in theirs: Utterance) -> Double {
        let said = words(mine.text), heard = words(theirs.text)
        guard said.count >= 3, said.count <= heard.count else { return 0 }
        let length = max(theirs.end - theirs.start, 0.001), slack = max(1, 0.1 * length)
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
    /// A recognised word's letters and digits, as the live window compares words.
    private static func normal(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
}
