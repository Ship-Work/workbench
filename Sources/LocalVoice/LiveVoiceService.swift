import Foundation
import FluidAudio

struct LiveVoiceWord: Sendable {
    var text: String
    var start: Double
    var end: Double
}

struct LiveVoiceAudio: Sendable {
    var source: LiveVoiceSource
    var samples: [Float]
    var sampleRate: Double
    var start: Double
}

/// A bounded mailbox, rather than one Task per audio callback. Overflow invalidates live
/// completion, never the independently saved original audio or the committed words.
final class LiveVoiceInput: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [LiveVoiceAudio] = []
    private var frames = 0
    private var closed = false
    private var problem: String?
    private let maximumFrames: Int
    init(maximumFrames: Int = 12_000_000) { self.maximumFrames = maximumFrames }

    func append(_ audio: LiveVoiceAudio) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, problem == nil, !audio.samples.isEmpty else { return }
        guard audio.sampleRate.isFinite, (8_000...192_000).contains(audio.sampleRate),
              audio.start.isFinite, audio.start >= 0,
              audio.samples.allSatisfy(\.isFinite), frames + audio.samples.count <= maximumFrames else {
            problem = "Live text fell behind. The original recording is still being saved for transcription."
            pending.removeAll(); frames = 0; return
        }
        pending.append(audio); frames += audio.samples.count
    }
    func close() { lock.lock(); closed = true; lock.unlock() }
    func drain() -> (audio: [LiveVoiceAudio], closed: Bool, problem: String?) {
        lock.lock(); defer { lock.unlock() }
        let result = (pending, closed, problem)
        pending.removeAll(keepingCapacity: true); frames = 0
        return result
    }
}

/// Live words are confirmed a phrase at a time. Each reading covers one source from the last cut
/// to the newest audio, and a cut goes where that source is quiet, never through a word, so every
/// confirmed word comes from a single reading that had the audio on both sides of it. No boundary
/// has to be matched against the next reading, which is what used to leave a long meeting's live
/// pass incomplete and send the whole recording back through recognition at Stop. Quiet is judged
/// from the audio, as the saved-audio path judges it (MeetingConversation), because the model
/// stretches a word's timing over the silence after it. A word belongs to the phrase it starts in.
/// A phrase that reaches the model's 15 s window without a pause is cut at its quietest moment.
struct LiveVoiceWindow {
    /// Where phrases are cut. The meeting benchmark (docs/research) measured these values.
    struct Phrasing: Equatable {
        /// New audio between two readings of the open phrase: how often live words move.
        var previewSeconds = 2.0
        /// Quiet after the last word this long ends the phrase. The cut stays `settleSeconds` clear
        /// of the reading's end, where a word only starting may not be heard yet.
        var pauseSeconds = 1.2
        /// From this length the phrase is cut at its latest pause.
        var phraseSeconds = 10.0
        /// The longest phrase: one reading of it, read again with EmptyReading's silence, fits the
        /// model's 15 s window.
        var longestSeconds = 14.5
        /// Quiet this long between words is a pause.
        var gapSeconds = 0.3
        /// Audio this close to the end of a reading can still change; no cut goes there.
        var settleSeconds = 1.0
        /// A quiet reading with no words this long is passed over, up to the middle of its quiet.
        var silenceSeconds = 4.0
        /// A first word this long after the sound starts suggests the reading missed earlier words.
        var missedStartSeconds = 1.0
        /// Quiet kept before the first sound after the cut. Parakeet misses whole readings far more
        /// often after a long silence: one stretch of a synthetic meeting read with 3 s of silence first
        /// came back empty at 8 of 11 lengths, and at 0 of 11 starting 0.3 s or 1 s before the speech.
        /// A second keeps a soft first word that reads as quiet, and measured as well as 0.3 s.
        var leadingQuietSeconds = 1.0
    }
    /// Loudness frames and the adaptive floor speech must rise above, as MeetingConversation's.
    static let frameSeconds = 0.03, speechAboveFloor: Float = 12, quietestSpeech: Float = -50
    var source: LiveVoiceSource
    var start: Double
    var rate: Double
    var samples: [Float] = []
    /// The last cut: words before it are confirmed.
    var committed = 0
    /// How far the last reading reached.
    var previewed = 0
    var segmentID = UUID()
    var phrasing = Phrasing()
    /// Cuts made at the longest phrase with no pause in it, where a word on the edge can be split.
    private(set) var narrowCuts = 0
    private let frame: Int
    /// Loudness of each whole frame from `samples[0]`, and whether it is quiet.
    private var levels: [Float] = [], quiet: [Bool] = []
    private var floor: Float = -60
    /// The cut the last reading chose, applied by `accept`, with the last word it confirms.
    private var pending: (at: Double, narrow: Bool, next: UUID, last: LiveVoiceWord?)?
    /// The last confirmed word, so a word heard on both sides of a cut is kept once.
    private var lastConfirmed: LiveVoiceWord?
    init(source: LiveVoiceSource, start: Double, rate: Double, samples: [Float] = []) {
        self.source = source; self.start = start; self.rate = rate; confirmedThrough = start
        frame = max(1, Int((rate * Self.frameSeconds).rounded()))
        self.samples = samples
        measure()
    }
    var end: Double { start + Double(samples.count) / rate }
    var uncommittedSeconds: Double { Double(samples.count - committed) / rate }
    /// Audio no reading has reached yet: more than a few seconds means recognition is behind.
    var unreadSeconds: Double { Double(samples.count - previewed) / rate }
    /// Where this source's confirmed words end: the last cut.
    private(set) var confirmedThrough: Double

    mutating func append(_ audio: LiveVoiceAudio) -> Bool {
        guard rate == audio.sampleRate, abs(end - audio.start) < 0.1 else { return false }
        // The original track fills a short gap in its source with silence (MeetingAudio); so does
        // this window, or its end would fall short of the track's and the pass could not complete.
        let gap = Int(((audio.start - end) * rate).rounded())
        if gap > 0 { samples += [Float](repeating: 0, count: gap) }
        samples += audio.samples
        measure()
        return true
    }
    private mutating func measure() {
        while (levels.count + 1) * frame <= samples.count {
            var sum: Float = 0
            for index in (levels.count * frame)..<((levels.count + 1) * frame) { sum += samples[index] * samples[index] }
            let level = 20 * log10(max((sum / Float(frame)).squareRoot(), 1e-9))
            floor = level < floor ? level : floor + (level - floor) * 0.001
            levels.append(level); quiet.append(level <= max(floor + Self.speechAboveFloor, Self.quietestSpeech))
        }
    }

    struct Request {
        var audio: [Float]
        var audioStart: Double
        /// The last cut; this reading confirms words that start from here.
        var from: Double
        var through: Double
        /// Finishing: every word in this reading is confirmed, even one timed in its padding.
        var final: Bool
        var endFrame: Int
    }
    func request(finishing: Bool) -> Request? {
        guard samples.count > committed else { return nil }
        let longest = Int(phrasing.longestSeconds * rate), open = samples.count - committed
        let final = finishing && open <= longest
        guard final || open >= longest || Double(samples.count - previewed) / rate >= phrasing.previewSeconds else { return nil }
        let through = min(samples.count, committed + longest)
        // The reading starts a moment before the first sound after the cut, not at a long silence.
        let sound = (committed / frame..<min(quiet.count, through / frame)).first { !quiet[$0] }
        let from = max(committed, (sound ?? 0) * frame - Int(phrasing.leadingQuietSeconds * rate))
        return Request(audio: Array(samples[from..<through]), audioStart: start + Double(from) / rate,
                       from: start + Double(committed) / rate, through: start + Double(through) / rate,
                       final: final, endFrame: through)
    }
    mutating func segments(words: [LiveVoiceWord], request: Request) throws -> [LiveVoiceSegment] {
        // Padding and EmptyReading's silence can run past the audio, never by a second.
        let bound = request.through - request.audioStart + 1
        guard words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= bound }) else {
            throw VoiceError.message("The speech model returned invalid word timing. Original audio is kept.")
        }
        var heard = words.map { LiveVoiceWord(text: $0.text, start: request.audioStart + $0.start, end: request.audioStart + $0.end) }
            .filter { $0.start >= request.from }.sorted { $0.start < $1.start }
        // A cut that fell in a word's soft start hears it again at the very start of the next
        // reading, overlapping the last confirmed word: kept once. A repeat said later stays.
        if let previous = lastConfirmed, let first = heard.first, first.start < previous.end, first.start < request.audioStart + 0.1,
           Self.plain(first.text) == Self.plain(previous.text) { heard.removeFirst() }
        let cut = request.final ? (at: request.through, narrow: false) : self.cut(heard, request)
        let next = UUID()
        pending = cut.map { cut in (cut.at, cut.narrow, next, request.final ? heard.last : heard.last { $0.start < cut.at }) }
        var confirmed = 0, open = 0
        return heard.map { word in
            let final = request.final || (cut.map { word.start < $0.at } ?? false)
            defer { if final { confirmed += 1 } else { open += 1 } }
            // A word keeps its identity from provisional to confirmed, so the page never redraws it.
            return LiveVoiceSegment(id: Self.identity(final || cut == nil ? segmentID : next, final ? confirmed : open),
                                    source: source, start: word.start, end: word.end, text: word.text, isFinal: final)
        }
    }
    /// Nil keeps the phrase open for the next reading.
    private func cut(_ heard: [LiveVoiceWord], _ request: Request) -> (at: Double, narrow: Bool)? {
        let first = committed / frame + (committed % frame == 0 ? 0 : 1)
        let last = min(levels.count, request.endFrame / frame)
        guard last > first else { return nil }
        func time(_ frame: Int) -> Double { start + Double(frame * self.frame) / rate }
        // Quiet runs in this reading, in frames. A word the model heard is sound around its start
        // however soft it was: a quiet-sounding first or last word is never cut through.
        var still = quiet
        for word in heard {
            let from = max(0, Int((word.start - 0.1 - start) * rate) / frame), to = min(still.count, Int((word.start + 0.2 - start) * rate) / frame + 1)
            if from < to { for index in from..<to { still[index] = false } }
        }
        var runs: [Range<Int>] = [], index = first
        while index < last {
            guard still[index] else { index += 1; continue }
            var end = index + 1
            while end < last, still[end] { end += 1 }
            runs.append(index..<end); index = end
        }
        let span = request.through - request.from
        let longest = request.endFrame - committed >= Int(phrasing.longestSeconds * rate)
        let settled = request.through - phrasing.settleSeconds
        func seconds(_ run: Range<Int>) -> Double { Double(run.count * frame) / rate }
        func middle(_ run: Range<Int>) -> Double { (time(run.lowerBound) + time(run.upperBound)) / 2 }
        // Where sound starts after the cut: speech, or a noise the model may hear as nothing.
        let sounding = (first..<last).first { !quiet[$0] }.map(time)
        if heard.isEmpty {
            // A reading can miss speech outright (EmptyReading), so sound with no words waits for
            // the next reading; only a whole window of it is passed over.
            guard sounding == nil ? span >= phrasing.silenceSeconds : longest else { return nil }
            // Nothing said: pass over it, cutting in its latest quiet before the last second.
            let early = runs.filter { middle($0) <= request.through - 1 }
            return (early.last.map(middle) ?? request.through - 1, false)
        }
        // The model hears a word a moment after it starts. Far later than that, the reading
        // probably missed the phrase's first words; the next reading gets another chance.
        if let sounding, heard[0].start - sounding > phrasing.missedStartSeconds, !longest { return nil }
        // The speaker has stopped: quiet from the last sound to the end of the reading. In a noisy
        // room speech can read as quiet, so the cut stays clear of the end, where a word the
        // reading cut short may not have been heard.
        if let tail = runs.last, tail.upperBound == last, seconds(tail) >= phrasing.pauseSeconds,
           heard.contains(where: { $0.start < time(tail.lowerBound) }) {
            return (min(middle(tail), settled), false)
        }
        guard longest || span >= phrasing.phraseSeconds else { return nil }
        let settledRuns = runs.filter { middle($0) <= settled && middle($0) > heard[0].start }
        if let pause = settledRuns.last(where: { seconds($0) >= phrasing.gapSeconds }) { return (middle(pause), false) }
        guard longest else { return nil }
        // No pause in a whole window: in its second half, the widest quiet, else the quietest frame.
        let half = request.from + phrasing.longestSeconds / 2
        if let widest = settledRuns.filter({ middle($0) >= half }).max(by: { $0.count < $1.count }) { return (middle(widest), true) }
        let lower = max(first, Int((half - start) * rate) / frame), upper = min(last, Int((settled - start) * rate) / frame)
        let quietest = lower < upper ? (lower..<upper).min { levels[$0] < levels[$1] }! : last - 1
        return (time(quietest) + Self.frameSeconds / 2, true)
    }
    /// A reading that probably missed words: none over sound, or its first word long after the
    /// sound starts. The service reads a phrase's last reading again a moment later in when so.
    func doubts(_ words: [LiveVoiceWord], _ request: Request) -> Bool {
        let first = committed / frame, last = min(quiet.count, request.endFrame / frame)
        guard first < last, let sound = (first..<last).first(where: { !quiet[$0] }) else { return false }
        let sounding = start + Double(sound * frame) / rate
        guard let earliest = words.map(\.start).min() else { return true }
        return request.audioStart + earliest - sounding > phrasing.missedStartSeconds
    }
    @discardableResult mutating func accept(_ request: Request) -> Bool {
        previewed = max(previewed, request.endFrame)
        guard let cut = pending else { return false }
        pending = nil
        committed = min(request.endFrame, max(committed + 1, Int(((cut.at - start) * rate).rounded())))
        confirmedThrough = start + Double(committed) / rate
        if let last = cut.last { lastConfirmed = last }
        if cut.narrow { narrowCuts += 1 }
        segmentID = cut.next
        // Confirmed audio is no longer needed; whole frames go so loudness stays aligned.
        let discard = committed / frame * frame
        samples.removeFirst(discard); start += Double(discard) / rate
        levels.removeFirst(discard / frame); quiet.removeFirst(discard / frame)
        committed -= discard; previewed = max(0, previewed - discard)
        return true
    }
    private static func plain(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
    private static func identity(_ base: UUID, _ index: Int) -> UUID {
        var identity = base.uuid
        withUnsafeMutableBytes(of: &identity) { bytes in
            let suffix = UInt32(index)
            for offset in 0..<4 { bytes[12 + offset] ^= UInt8(truncatingIfNeeded: suffix >> (offset * 8)) }
        }
        return UUID(uuid: identity)
    }
    /// Audio a source's queue holds, in seconds.
    static func queuedSeconds(_ queue: [LiveVoiceWindow]) -> Double {
        queue.reduce(0) { $0 + Double($1.samples.count) / $1.rate }
    }
    /// A backlog past the limit drops the oldest whole window(s) until the rest fits (#280), so live
    /// words skip ahead instead of stopping. Returns the uncommitted start of the first dropped window,
    /// where live words go missing, or nil when nothing was dropped.
    static func trimBacklog(_ queue: inout [LiveVoiceWindow], limit: Double = 60) -> Double? {
        guard queuedSeconds(queue) > limit, let first = queue.first else { return nil }
        let from = first.start + Double(first.committed) / first.rate
        while !queue.isEmpty, queuedSeconds(queue) > limit { queue.removeFirst() }
        return from
    }
}

/// Live words degrade instead of dying (#280). Each kind is noted once per pass; the pass is then
/// incomplete and the saved transcript comes from the original audio at finish.
enum LiveVoiceDegradation: Hashable {
    case backlog
    func note(at seconds: Double) -> String {
        "Live text fell behind at \(Int(seconds.rounded())) s; the words from the original audio replace it at finish."
    }
}

enum LiveVoiceJournal {
    static func save(_ checkpoint: LiveVoiceCheckpoint, to url: URL) throws {
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func load(from url: URL, sessionID: UUID) throws -> LiveVoiceCheckpoint {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 16 * 1024 * 1024 else {
            throw VoiceError.message("The live transcript checkpoint could not be read safely.")
        }
        let checkpoint = try JSONDecoder().decode(LiveVoiceCheckpoint.self, from: Data(contentsOf: url))
        guard checkpoint.formatVersion == 1, checkpoint.sessionID == sessionID,
              checkpoint.segments.count <= 100_000, Set(checkpoint.segments.map(\.id)).count == checkpoint.segments.count,
              checkpoint.segments.allSatisfy({ $0.isFinal && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= 7_260 }),
              checkpoint.completedThrough.keys.allSatisfy({ LiveVoiceSource(rawValue: $0) != nil }),
              checkpoint.completedThrough.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 7_260 }) else {
            throw VoiceError.message("The live transcript checkpoint has invalid timing or identity.")
        }
        return checkpoint
    }
}

/// One serial inference loop for both sources. Recognition never runs on an audio callback
/// or the main actor. A failed/overloaded live pass leaves batch recovery fully available.
final class LiveVoiceService: @unchecked Sendable {
    typealias Recognize = @Sendable ([Float]) async throws -> [LiveVoiceWord]
    let input = LiveVoiceInput()
    private let task: Task<LiveVoiceCheckpoint, Never>

    init(id: UUID, sources: [LiveVoiceSourceStatus], journal: URL?, recognize: @escaping Recognize,
         update: @escaping @Sendable (LiveVoiceSnapshot) -> Void) {
        let input = input
        task = Task.detached(priority: .utility) {
            defer { input.close() }
            var checkpoint = LiveVoiceCheckpoint(sessionID: id)
            var runs: [LiveVoiceSource: [LiveVoiceWindow]] = [:]
            var tails: [LiveVoiceSource: [LiveVoiceSegment]] = [:]
            var snapshot = LiveVoiceSnapshot(sessionID: id, phase: .listening, sources: sources)
            var stopped = false
            var reconciled = true
            var noted: Set<LiveVoiceDegradation> = []
            var published: LiveVoiceSnapshot?
            let clock = ContinuousClock()
            var publishedAt = clock.now, savedAt = clock.now
            func degrade(_ kind: LiveVoiceDegradation, at seconds: Double) {
                reconciled = false
                if noted.insert(kind).inserted { checkpoint.notes.append(kind.note(at: seconds)) }
            }
            do {
                while true {
                    try Task.checkCancellation()
                    let batch = input.drain()
                    if let problem = batch.problem { throw VoiceError.message(problem) }
                    stopped = batch.closed
                    var wordsChanged = false
                    for audio in batch.audio {
                        if let index = snapshot.sources.firstIndex(where: { $0.source == audio.source }) {
                            let peak = audio.samples.map { abs($0) }.max() ?? 0
                            snapshot.sources[index].health = peak > 0.001 ? .receiving : .quiet
                            snapshot.sources[index].level = min(1, Double(peak) * 4)
                        }
                        snapshot.elapsed = max(snapshot.elapsed, audio.start + Double(audio.samples.count) / audio.sampleRate)
                        var queue = runs[audio.source] ?? []
                        if queue.isEmpty || !queue[queue.count - 1].append(audio) {
                            queue.append(LiveVoiceWindow(source: audio.source, start: audio.start, rate: audio.sampleRate, samples: audio.samples))
                        }
                        // Bound both the mailbox and audio retained during inference. Past 60 s the
                        // oldest window(s) go and live words continue from the newest audio; the
                        // original audio gives the saved words (#280).
                        if let behindFrom = LiveVoiceWindow.trimBacklog(&queue) {
                            degrade(.backlog, at: behindFrom)
                            tails[audio.source] = []
                            wordsChanged = true
                        }
                        runs[audio.source] = queue
                    }
                    var worked = false
                    for source in LiveVoiceSource.allCases {
                        guard var queue = runs[source], !queue.isEmpty else { continue }
                        let finishing = stopped || queue.count > 1
                        if let request = queue[0].request(finishing: finishing) {
                            worked = true
                            var samples = try AudioConverter().resample(request.audio, from: queue[0].rate)
                            // FluidAudio needs 0.3 s. Keep short final replies by padding, not dropping.
                            if samples.count < 4_800 { samples += [Float](repeating: 0, count: 4_800 - samples.count) }
                            var words = samples.allSatisfy({ abs($0) < 0.000001 }) ? [] : try await recognize(samples)
                            try Task.checkCancellation()
                            // A phrase's last reading has no later one to correct it: one that probably
                            // missed words is read again 80 ms later in, and the fuller reading kept.
                            if request.final, samples.count >= 4_800 + 1_280, queue[0].doubts(words, request) {
                                let later = try await recognize(Array(samples.dropFirst(1_280)))
                                try Task.checkCancellation()
                                if later.count > words.count { words = later.map { LiveVoiceWord(text: $0.text, start: $0.start + 0.08, end: $0.end + 0.08) } }
                            }
                            let segments = try queue[0].segments(words: words, request: request)
                            tails[source] = segments.filter { !$0.isFinal }
                            wordsChanged = true
                            if queue[0].accept(request) {
                                let confirmed = segments.filter(\.isFinal)
                                checkpoint.segments += confirmed
                                checkpoint.completedThrough[source.rawValue] = queue[0].confirmedThrough
                                // Only a complete journal is ever read back (MeetingRecovery, Dictate), and each
                                // save rewrites every word so far, so a long meeting saves twice a minute, not per phrase.
                                if let journal, !confirmed.isEmpty, clock.now - savedAt >= .seconds(30) {
                                    try LiveVoiceJournal.save(checkpoint, to: journal); savedAt = clock.now
                                }
                            }
                        }
                        if finishing && queue[0].uncommittedSeconds == 0 { queue.removeFirst() }
                        runs[source] = queue
                    }
                    // Turns are rebuilt only when words changed, not on every pass of this loop (#377).
                    if wordsChanged { snapshot.segments = LiveVoiceTurns.group(checkpoint.segments + tails.values.flatMap { $0 }) }
                    snapshot.recognitionDelayed = runs.values.flatMap { $0 }.contains { $0.unreadSeconds > 6 }
                    snapshot.liveIncomplete = !reconciled
                    snapshot.phase = stopped ? .finishing : .listening
                    // The loop passes ten times a second and every publish reaches the main thread, so it
                    // publishes when something a page shows changes (words, phase, a source's health or
                    // note) and the meter and clock at most once a second (#377). New words and the
                    // final state are never held back.
                    if published.map({ !$0.showsSame(as: snapshot) }) ?? true || clock.now - publishedAt >= .seconds(1) {
                        update(snapshot)
                        published = snapshot; publishedAt = clock.now
                    }
                    if stopped && runs.values.allSatisfy(\.isEmpty) { break }
                    if !worked { try await Task.sleep(nanoseconds: 100_000_000) }
                }
                checkpoint.complete = reconciled && sources.allSatisfy { checkpoint.completedThrough[$0.source.rawValue] != nil }
                if let journal { try LiveVoiceJournal.save(checkpoint, to: journal) }
                snapshot.phase = checkpoint.complete ? .completed : .recoverableFailure
            } catch {
                checkpoint.complete = false
                checkpoint.notes.append(error is CancellationError ? "Live text was cancelled. Original audio is kept." : error.localizedDescription)
                if let journal { try? LiveVoiceJournal.save(checkpoint, to: journal) }
                snapshot.phase = .recoverableFailure
                // The loop is over: say so rather than catching up forever (#280).
                snapshot.recognitionDelayed = false
                snapshot.liveIncomplete = true
                snapshot.liveStopped = true
                snapshot.message = checkpoint.notes.last
            }
            update(snapshot)
            return checkpoint
        }
    }
    func finish() async -> LiveVoiceCheckpoint { input.close(); return await task.value }
    func requestCancel() { input.close(); task.cancel() }
    func cancel() async -> LiveVoiceCheckpoint { requestCancel(); return await task.value }
}

private extension LiveVoiceSnapshot {
    /// The same on any page: everything but the meter levels and elapsed time, which no page
    /// shows from here (each model keeps its own clock).
    func showsSame(as other: LiveVoiceSnapshot) -> Bool {
        var mine = self, theirs = other
        mine.elapsed = 0; theirs.elapsed = 0
        for index in mine.sources.indices { mine.sources[index].level = 0 }
        for index in theirs.sources.indices { theirs.sources[index].level = 0 }
        return mine == theirs
    }
}
