import Foundation

/// Timed synthetic samples and an injected recognizer. No device, provider or model access.
enum LiveVoiceChecks {
    static func run() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/Workbench-LiveVoiceChecks-\(UUID().uuidString)")
        try MeetingStore.createPrivateDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func expect(_ value: Bool, _ label: String) throws {
            guard value else { throw VoiceError.message("Live voice check failed: \(label)") }
            count += 1
        }
        func samples(_ words: Range<Int>) -> [Float] {
            words.flatMap { [Float](repeating: Float($0) / 100, count: 16_000) }
        }
        let decoder = FixtureDecoder()
        let journal = root.appendingPathComponent("checkpoint.json")
        let id = UUID()
        let service = LiveVoiceService(id: id,
            sources: [.init(source: .microphone, name: "Fixture mic"), .init(source: .app, name: "Fixture call")],
            journal: journal, recognize: { try await decoder.recognize($0) }, update: { _ in })
        service.input.append(.init(source: .microphone, samples: samples(1..<14), sampleRate: 16_000, start: 0))
        service.input.append(.init(source: .app, samples: samples(20..<23), sampleRate: 16_000, start: 1))
        // Pause/device loss keeps the actual gap; it must not move the later words to 13 s.
        service.input.append(.init(source: .microphone, samples: samples(14..<16), sampleRate: 16_000, start: 30))
        let final = await service.finish()
        try expect(final.complete, "both source runs finish")
        let mic = final.orderedSegments.filter { $0.source == .microphone }.map(\.text).joined(separator: " ")
        try expect(mic == (1..<16).map { "word\($0)" }.joined(separator: " "), "overlap neither repeats nor loses words")
        try expect(final.orderedSegments.filter { $0.source == .app }.map(\.text).joined(separator: " ") == "word20 word21 word22", "simultaneous sources retain separate words")
        try expect(final.orderedSegments.first(where: { $0.text == "word14" })?.start == 30 && final.completedThrough["microphone"] == 32, "route gap preserves absolute time")
        try expect(final.segments.allSatisfy(\.isFinal), "journal contains no provisional words")
        try expect(try LiveVoiceJournal.load(from: journal, sessionID: id) == final, "confirmed words survive a fresh read")
        let maximumConcurrency = await decoder.maximumConcurrency
        try expect(maximumConcurrency == 1, "one inference at a time across sources")
        do { _ = try LiveVoiceJournal.load(from: journal, sessionID: UUID()); throw CheckFailure() }
        catch is CheckFailure { throw VoiceError.message("Live voice check failed: stale identity accepted") }
        catch { count += 1 }

        // Live words are confirmed a phrase at a time, cut where the source is quiet. Fixture words
        // are a second each; `dip` puts a short quiet between them, as speech has.
        func quiet(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * 16_000)) }
        func speech(_ words: Range<Int>, dip: Double) -> [Float] {
            words.flatMap { [Float](repeating: Float($0) / 100, count: 16_000) + [Float](repeating: 0.002, count: Int(dip * 16_000)) }
        }
        /// Reads a window the way the service does until nothing is left; returns the confirmed words.
        func drive(_ window: inout LiveVoiceWindow, _ decoder: FixtureDecoder, finishing: Bool) async throws -> [LiveVoiceSegment] {
            var confirmed: [LiveVoiceSegment] = []
            while let request = window.request(finishing: finishing) {
                let segments = try window.segments(words: try await decoder.recognize(request.audio), request: request)
                if window.accept(request) { confirmed += segments.filter(\.isFinal) } else if !finishing { break }
            }
            return confirmed
        }
        var window = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: samples(1..<4))
        let preview = window.request(finishing: false)!
        let provisional = try window.segments(words: await decoder.recognize(preview.audio), request: preview)
        try expect(!window.accept(preview) && provisional.allSatisfy { !$0.isFinal } && provisional.map(\.text).joined(separator: " ") == "word1 word2 word3",
                   "words show while their phrase is still open")
        _ = window.append(.init(source: .microphone, samples: quiet(2), sampleRate: 16_000, start: 3))
        let ended = window.request(finishing: false)!
        let stable = try window.segments(words: await decoder.recognize(ended.audio), request: ended)
        try expect(window.accept(ended) && stable.allSatisfy(\.isFinal) && stable.map(\.id) == provisional.map(\.id)
                   && abs(window.confirmedThrough - 4) < 0.05, "a pause ends the phrase in its middle, and its words keep their identity")

        // Parakeet can hear nothing in a reading over clear speech (EmptyReading): sound with no
        // words is never passed over as silence, and the next reading confirms the words.
        let deaf = FixtureDecoder(script: [[]])
        var missed = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: samples(1..<6) + quiet(1))
        let unheard = missed.request(finishing: false)!
        let none = try missed.segments(words: await deaf.recognize(unheard.audio), request: unheard)
        _ = missed.append(.init(source: .microphone, samples: quiet(4), sampleRate: 16_000, start: 6))
        try expect(none.isEmpty && !missed.accept(unheard), "a reading that hears nothing over speech confirms and cuts nothing")
        let missedWords = try await drive(&missed, deaf, finishing: false)
        try expect(missedWords.map(\.text) == (1..<6).map { "word\($0)" }, "the next reading confirms what the empty one missed")
        // A first word long after the sound starts means the reading missed the phrase's start.
        let late = FixtureDecoder(script: [[.init(text: "word3", start: 2, end: 3), .init(text: "word4", start: 3, end: 4)]])
        var lateStart = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: samples(1..<5) + quiet(2))
        let partial = lateStart.request(finishing: false)!
        _ = try lateStart.segments(words: await late.recognize(partial.audio), request: partial)
        try expect(!lateStart.accept(partial), "a reading whose first word comes 2 s after the sound confirms nothing")
        _ = lateStart.append(.init(source: .microphone, samples: quiet(2), sampleRate: 16_000, start: 6))
        let recovered = try await drive(&lateStart, late, finishing: false)
        try expect(recovered.map(\.text) == (1..<5).map { "word\($0)" }, "a later reading confirms the phrase from its first word")

        // Twenty seconds without a pause is cut in a gap between words in the window's second
        // half; every word is confirmed exactly once on either side.
        var continuous = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: speech(1..<21, dip: 0.06))
        var unbroken = try await drive(&continuous, FixtureDecoder(), finishing: false)
        unbroken += try await drive(&continuous, FixtureDecoder(), finishing: true)
        try expect(unbroken.map(\.text) == (1..<21).map { "word\($0)" } && continuous.narrowCuts >= 1,
                   "a phrase with no pause is cut between words and confirms each word once")
        // Silence alone is passed over without confirming anything.
        var silence = LiveVoiceWindow(source: .app, start: 10, rate: 16_000, samples: quiet(6))
        let hush = silence.request(finishing: false)!
        let nothing = try silence.segments(words: await decoder.recognize(hush.audio), request: hush)
        try expect(nothing.isEmpty && silence.accept(hush) && silence.confirmedThrough == 13 && silence.uncommittedSeconds == 3,
                   "six quiet seconds are passed over in the middle of their quiet")
        // A short gap in the source is silence in the original track, so it is silence here too and
        // the pass ends exactly where the track does (MeetingRecovery.complete).
        var gapped = LiveVoiceWindow(source: .app, start: 0, rate: 16_000, samples: samples(1..<3))
        _ = gapped.append(.init(source: .app, samples: samples(3..<4), sampleRate: 16_000, start: 2.05))
        let gappedWords = try await drive(&gapped, FixtureDecoder(), finishing: true)
        try expect(gapped.confirmedThrough == 3.05 && gappedWords.map(\.text) == ["word1", "word2", "word3"] && gappedWords.last?.start == 2.05,
                   "a 50 ms gap is kept as silence, so later words keep their times and the pass ends with the track")
        // The last reading confirms every word, even one the model timed in the padding after a short reply.
        var reply = LiveVoiceWindow(source: .microphone, start: 7, rate: 16_000, samples: [Float](repeating: 0.1, count: 1_600))
        let padded = try await drive(&reply, FixtureDecoder(script: [[.init(text: "Yes", start: 0.12, end: 0.2)]]), finishing: true)
        try expect(padded.map(\.text) == ["Yes"] && reply.confirmedThrough == 7.1, "a word timed past a short final reading is still confirmed")
        // A cut in a word's soft start hears it again at the very start of the next reading: kept
        // once. The same word said again later, inside the first one's stretched timing, stays.
        let repeats = FixtureDecoder(script: [[.init(text: "no", start: 0.5, end: 3.6)],
                                              [.init(text: "No", start: 0, end: 0.3), .init(text: "no", start: 0.5, end: 0.8)]])
        var repeated = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: samples(1..<3) + quiet(2))
        var spoken = try await drive(&repeated, repeats, finishing: false)
        _ = repeated.append(.init(source: .microphone, samples: samples(5..<7), sampleRate: 16_000, start: 4))
        spoken += try await drive(&repeated, repeats, finishing: true)
        try expect(spoken.map { "\($0.text)@\($0.start)" } == ["no@0.5", "no@3.5"],
                   "a word heard again at a reading's start is kept once, and the same word said again later stays")
        // A reading that probably missed words: none over sound, or a first word long after it starts.
        let afterQuiet = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: quiet(2) + samples(1..<3))
        let whole = afterQuiet.request(finishing: true)!
        let silentWindow = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: quiet(3))
        try expect(abs(whole.audioStart - 1) < 0.05 && afterQuiet.doubts([], whole) && !silentWindow.doubts([], silentWindow.request(finishing: true)!)
                   && !afterQuiet.doubts([.init(text: "word1", start: 1.1, end: 1.9)], whole)
                   && afterQuiet.doubts([.init(text: "word2", start: 2.5, end: 2.9)], whole),
                   "a reading starts a second before the sound, and one that hears nothing over sound or starts 1.5 s late is doubted")
        // In a noisy room speech can read as quiet; the cut that ends a phrase stays a second clear of
        // the reading's end, where a word the reading cut short may not have been heard.
        var soft = LiveVoiceWindow(source: .microphone, start: 0, rate: 16_000, samples: samples(1..<3) + [Float](repeating: 0.001, count: 24_000))
        let softRead = soft.request(finishing: false)!
        _ = try soft.segments(words: await decoder.recognize(softRead.audio), request: softRead)
        try expect(soft.accept(softRead) && soft.confirmedThrough <= 2.5 + 0.001, "a phrase's ending cut is at least a second before the reading's end")
        try expect(EmptyReading.retry(samples(1..<3))?.count == 32_000 + EmptyReading.paddingSamples && EmptyReading.retry(quiet(2)) == nil
                   && EmptyReading.retry(samples(1..<16)) == nil, "an empty reading is read again only over sound and within one window")
        let replies = LiveVoiceCheckpoint(sessionID: UUID(), segments: [
            .init(source: .microphone, start: 1, end: 1.2, text: "Yes", isFinal: true),
            .init(source: .app, start: 6, end: 6.2, text: "Yes", isFinal: true),
            .init(source: .microphone, start: 7, end: 7.2, text: "Certainly", isFinal: true)])
        try expect(replies.conversation == "You: Yes\n\nOthers: Yes\n\nYou: Certainly", "separate identical replies survive in their actual turn order")

        // Words `step` apart, each a quarter of a second long, from `start`.
        func said(_ source: LiveVoiceSource, _ text: String, at start: Double, step: Double = 0.3) -> [LiveVoiceSegment] {
            text.split(separator: " ").enumerated().map { offset, word in
                LiveVoiceSegment(source: source, start: start + Double(offset) * step, end: start + Double(offset) * step + 0.25,
                                 text: String(word), isFinal: true)
            }
        }
        // The app's words as the microphone hears them, `lag` later.
        func echo(of words: [LiveVoiceSegment], lag: (Double) -> Double) -> [LiveVoiceSegment] {
            words.map { LiveVoiceSegment(source: .microphone, start: $0.start + lag($0.start), end: $0.end + lag($0.start), text: $0.text, isFinal: true) }
        }
        // A speaker who pauses to think stays one turn (#377); a long pause still starts a new one.
        let thinking = LiveVoiceCheckpoint(sessionID: UUID(), segments: said(.microphone, "First the budget", at: 0)
            + said(.microphone, "then the slides", at: 2.05) + said(.microphone, "And a new point", at: 5.5))
        try expect(thinking.conversation == "You: First the budget then the slides\n\nYou: And a new point",
                   "a 1.2 s pause keeps one turn and a 2.6 s pause starts the next")
        // Two people talking at once alternate by utterance in the saved words, never word by word (#377).
        let overlap = LiveVoiceCheckpoint(sessionID: UUID(), segments: said(.app, "Thanks so much everyone", at: 4)
            + said(.microphone, "No problem", at: 4.35))
        try expect(overlap.text == "Thanks so much everyone No problem" && overlap.conversation == "Others: Thanks so much everyone\n\nYou: No problem",
                   "overlapping speakers keep their own words together in the original wording and the conversation")
        // On laptop speakers a reply right as the other side finishes is yours however quickly it comes
        // (#377): its first word is never taken for the end of their echo.
        let question = said(.app, "can you send it by Friday", at: 0), echoedQuestion = said(.microphone, "can you send it by Friday", at: 0.05)
        let quick = [("Yes", 0.0), ("Yes", 0.05), ("No not this week", 0.1), ("No", 0.15)].filter { reply, gap in
            LiveVoiceCheckpoint(sessionID: UUID(), segments: question + echoedQuestion + said(.microphone, reply, at: 1.75 + gap)).conversation
                != "Others: can you send it by Friday\n\nYou: \(reply)"
        }
        try expect(quick.isEmpty, "a reply 0 to 0.15 s after the other side finishes is kept whole and their echo is not (lost: \(quick))")
        // With headphones nothing is an echo: a word of theirs you say a moment later is yours (#377).
        let okay = LiveVoiceCheckpoint(sessionID: UUID(), segments: said(.app, "so I think okay we should move the launch to Friday and tell the whole team today", at: 0)
            + said(.microphone, "okay", at: 2.4))
        let friday = LiveVoiceCheckpoint(sessionID: UUID(), segments: said(.app, "which day works for you Friday or Monday either is fine for me", at: 0)
            + said(.microphone, "Friday", at: 3.0))
        try expect(okay.conversation.hasSuffix("\n\nYou: okay") && friday.conversation.hasSuffix("\n\nYou: Friday"),
                   "an \"okay\" 1.5 s after theirs and a \"Friday\" answering \"Friday or Monday\" are kept")
        // The echo of two phrases with a short pause between them is dropped however the microphone's
        // recogniser times the pause (#377).
        var leaked: [String] = []
        for pause in [0.65, 0.8] {
            for jitter in [0.0, 0.08, 0.16, 0.4] {
                let first = said(.app, "the budget goes to finance on Friday", at: 0), next = first.last!.end + pause
                var echo = said(.microphone, "the budget goes to finance on Friday", at: 0.05)
                echo[echo.count - 1].end += jitter
                let call = LiveVoiceCheckpoint(sessionID: UUID(), segments: first + said(.app, "and the slides go to Sam next week", at: next)
                    + echo + said(.microphone, "and the slides go to Sam next week", at: next + 0.05))
                if call.conversation != "Others: the budget goes to finance on Friday and the slides go to Sam next week" { leaked.append("\(pause) s/\(jitter) s") }
            }
        }
        try expect(leaked.isEmpty, "an echo across a 0.65 or 0.8 s pause of theirs is dropped at any microphone timing (leaked at \(leaked))")
        // Your words in the middle of their sentence, with its echo right around them, are yours (#377).
        let sentence = "we will send the contract to legal on Monday and then the signed copy goes to finance by the end of the month"
        var interrupted = said(.microphone, sentence, at: 0.05)
        for (offset, word) in "wait which legal team do you mean".split(separator: " ").enumerated() { interrupted[8 + offset].text = String(word) }
        let interjection = LiveVoiceCheckpoint(sessionID: UUID(), segments: said(.app, sentence, at: 0) + interrupted)
        try expect(interjection.conversation == "Others: \(sentence)\n\nYou: wait which legal team do you mean",
                   "an interjection inside the echo of their sentence is kept, and the echo around it is not")
        // The lanes can sit further apart than a speaker's delay (#377): a USB microphone's clock, a
        // Bluetooth or AirPlay output, or where each lane's first sample fell. The lag comes from the
        // words themselves, so the echo goes at -0.15, +0.5 and +1.0 s, and while the lag drifts from
        // 0 to 0.3 s over four minutes.
        let budget = said(.app, "the budget goes to finance on Friday", at: 0)
        let slides = said(.app, "and the slides go to Sam next week", at: budget.last!.end + 0.8)
        let shifted = [-0.15, 0.5, 1.0].filter { shift in
            LiveVoiceCheckpoint(sessionID: UUID(), segments: budget + slides + echo(of: budget + slides) { _ in shift }).conversation
                != "Others: the budget goes to finance on Friday and the slides go to Sam next week"
        }
        try expect(shifted.isEmpty, "an echo whose lane sits -0.15, +0.5 or +1.0 s from the call's is dropped (leaked at \(shifted))")
        let lines = ["the budget goes to finance on Friday afternoon", "Sam will review the numbers before the launch",
                     "we can move the venue deposit to next week", "please send the signed contract back to legal"]
        let fourMinutes = (0..<24).flatMap { said(.app, lines[$0 % lines.count], at: Double($0) * 10) }
        let drifting = LiveVoiceCheckpoint(sessionID: UUID(), segments: fourMinutes + echo(of: fourMinutes) { 0.3 * $0 / 240 })
        try expect(drifting.turns.count == 24 && !drifting.turns.contains { $0.source == .microphone },
                   "an echo whose lag drifts from 0 to 0.3 s over four minutes is dropped throughout")
        // With headphones there is no echo. Two people talking over each other share common words that
        // line up by chance; every one of yours is kept. Two review fixtures, 24 alignments each: none of
        // the 1,776 words is dropped (with three agreeing words as the minimum, 6 were).
        func talkedOver(_ theirs: String, _ mine: String) -> Int {
            stride(from: 0.0, to: 1.2, by: 0.05).reduce(0) { lost, offset in
                let words = said(.microphone, mine, at: offset, step: 0.33)
                let kept = LiveVoiceCheckpoint(sessionID: UUID(), segments: said(.app, theirs, at: 0) + words).turns
                    .filter { $0.source == .microphone }.map { $0.text.split(separator: " ").count }.reduce(0, +)
                return lost + words.count - kept
            }
        }
        let crossTalkLost = talkedOver("I spoke to the vendor this morning and they think the parts will arrive late next week so we may need to push the install back a few days and let the client know before Friday if that is okay with you",
                                       "that works for me but I want to check with the client first because they already booked the room for the install and moving it might cost us a fee so let me call them after this")
            + talkedOver("I think the plan is to move the launch to the end of the month and then we can tell the team about it and the date and the budget for the event so that is the plan for now and I think that is fine",
                         "but the team said that the date is fixed and the budget is the same so I do not think we can move it to the end of the month and I think we should keep it")
        try expect(crossTalkLost == 0, "with headphones, talking over each other keeps every one of your words (\(crossTalkLost) of 1,776 dropped)")
        // A word the microphone's recogniser heard differently inside the echo goes with it, so their turn
        // is not split ("Lego" for "legal"; "Mon day" for "Monday", just before a pause of theirs). A
        // word of your own there is kept.
        let contract = said(.app, "we will send the contract to legal on Monday", at: 0)
        let copy = said(.app, "and then the signed copy goes to finance", at: contract.last!.end + 0.7)
        func heard(_ change: (inout [LiveVoiceSegment]) -> Void) -> String {
            var words = echo(of: contract + copy) { _ in 0.05 }
            change(&words)
            return LiveVoiceCheckpoint(sessionID: UUID(), segments: contract + copy + words).conversation
        }
        let both = "Others: we will send the contract to legal on Monday and then the signed copy goes to finance"
        let lego = heard { $0[6].text = "Lego" }
        let monDay = heard { words in
            words[8].text = "Mon"; words[8].end = words[8].start + 0.12
            words.append(LiveVoiceSegment(source: .microphone, start: words[8].start + 0.14, end: words[8].start + 0.25, text: "day", isFinal: true))
        }
        try expect(lego == both && monDay == both, "a misheard word inside the echo does not split their turn (\(lego == both ? monDay : lego))")
        try expect(heard { $0[6].text = "wait" } == "Others: we will send the contract to legal on Monday\n\nYou: wait\n\nOthers: and then the signed copy goes to finance",
                   "a word of your own inside the echo is kept")
        // A short reply said over a short word of theirs is not taken for a mishearing of it (#377 review):
        // "OK" over "on", "They" over "the", "No" over "to".
        let shortReplies = ["OK": 7, "They": 3, "No": 5].map { word, index in (word, heard { $0[index].text = word }) }
        try expect(shortReplies.allSatisfy { word, conversation in
            conversation == "Others: we will send the contract to legal on Monday\n\nYou: \(word)\n\nOthers: and then the signed copy goes to finance" },
                   "a short reply of your own over a short word of theirs is kept, and their echo around it dropped (\(shortReplies.filter { $0.1 != "Others: we will send the contract to legal on Monday\n\nYou: \($0.0)\n\nOthers: and then the signed copy goes to finance" }.map { $0.1 }))")

        // On laptop speakers the microphone hears the call (#377): through the real service, its copy
        // of the other side is neither shown nor saved as You, and what you said yourself is.
        let echoDecoder = FixtureDecoder(), shown = SnapshotLog()
        let speakers = LiveVoiceService(id: UUID(),
            sources: [.init(source: .microphone, name: "Fixture mic"), .init(source: .app, name: "Fixture call")],
            journal: nil, recognize: { try await echoDecoder.recognize($0) }, update: { shown.append($0) })
        // Five words, enough to agree on the lanes' lag (SpeakerEcho.minimumLagMatches).
        speakers.input.append(.init(source: .app, samples: samples(20..<25), sampleRate: 16_000, start: 1))
        speakers.input.append(.init(source: .microphone, samples: samples(20..<25), sampleRate: 16_000, start: 1))
        speakers.input.append(.init(source: .microphone, samples: samples(30..<32), sampleRate: 16_000, start: 8))
        let heardCall = await speakers.finish()
        try expect(heardCall.complete && heardCall.conversation == "Others: word20 word21 word22 word23 word24\n\nYou: word30 word31"
                   && heardCall.text == "word20 word21 word22 word23 word24 word30 word31",
                   "the microphone's copy of the call is not saved as You, and your own words are")
        try expect(shown.all.last?.segments.map { "\($0.source.label): \($0.text)" } == ["Others: word20 word21 word22 word23 word24", "You: word30 word31"],
                   "the live transcript shows the call once and your own words as You")

        // Live words reach the main thread when something shown changes, not on every pass of a 10 Hz
        // loop (#377). 2.5 s of continuous audio in 50 ms packets publishes a handful of times, the
        // first words among them, and the final state still arrives.
        let pacedDecoder = FixtureDecoder(), paced = SnapshotLog()
        let streaming = LiveVoiceService(id: UUID(), sources: [.init(source: .microphone, name: "Fixture")], journal: nil,
            recognize: { try await pacedDecoder.recognize($0) }, update: { paced.append($0) })
        let stream = samples(1..<4), streamStarted = Date()
        for packet in 0..<50 {
            streaming.input.append(.init(source: .microphone, samples: Array(stream[packet * 800..<(packet + 1) * 800]),
                                         sampleRate: 16_000, start: Double(packet) * 0.05))
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let whileStreaming = paced.all
        // A busy CI runner stretches the 2.5 s, and the meter and clock may publish once a second of
        // it; one publish per 100 ms pass would be ten a second.
        let streamingSeconds = Date().timeIntervalSince(streamStarted)
        let streamed = await streaming.finish()
        try expect(whileStreaming.count <= Int(streamingSeconds.rounded(.up)) + 8 && whileStreaming.contains { !$0.text.isEmpty },
                   "2.5 s of streamed audio publishes \(whileStreaming.count) snapshots, words among them, not one per 100 ms pass")
        try expect(paced.all.last?.phase == .completed && paced.all.last?.text == streamed.text && streamed.text.hasPrefix("word1 word2"),
                   "the final state is published with every word")

        let failingDecoder = FixtureDecoder(failOn: 2)
        let lastFailedSnapshot = SnapshotBox()
        let failed = LiveVoiceService(id: UUID(), sources: [.init(source: .microphone, name: "Fixture")], journal: nil,
            recognize: { try await failingDecoder.recognize($0) }, update: { lastFailedSnapshot.set($0) })
        failed.input.append(.init(source: .microphone, samples: samples(1..<9) + quiet(1) + samples(9..<19), sampleRate: 16_000, start: 0))
        let failedPass = await failed.finish()
        try expect(!failedPass.complete && !failedPass.notes.isEmpty && (8...9).contains(failedPass.completedThrough["microphone"] ?? -1),
                   "failed second window cannot silently finalize partial text")
        var stoppedWhileListening = lastFailedSnapshot.current
        stoppedWhileListening.phase = .listening
        try expect(lastFailedSnapshot.current.liveStopped && !lastFailedSnapshot.current.recognitionDelayed
                   && stoppedWhileListening.transcriptStatus.hasPrefix("Live words stopped"),
                   "a dead live loop says it stopped rather than catching up")
        try expect(failedPass.text == (1..<9).map { "word\($0)" }.joined(separator: " "), "failure retains confirmed earlier words")

        let shortDecoder = FixtureDecoder()
        let short = LiveVoiceService(id: UUID(), sources: [.init(source: .microphone, name: "Fixture")], journal: nil,
            recognize: { audio in
                await shortDecoder.recordLength(audio.count)
                return [.init(text: "Yes", start: 0, end: 0.1)]
            }, update: { _ in })
        short.input.append(.init(source: .microphone, samples: [Float](repeating: 0.1, count: 1_600), sampleRate: 16_000, start: 4))
        let tiny = await short.finish()
        try expect(tiny.complete && tiny.text == "Yes" && tiny.completedThrough["microphone"] == 4.1, "very short final reply survives")
        let length = await shortDecoder.lastLength
        try expect(length == 4_800, "short tail is padded only for the recognizer")

        let mailbox = LiveVoiceInput(maximumFrames: 10)
        mailbox.append(.init(source: .microphone, samples: [Float](repeating: 0.1, count: 11), sampleRate: 16_000, start: 0))
        let overflow = mailbox.drain()
        try expect(overflow.audio.isEmpty && overflow.problem != nil, "bounded input explicitly reports loss instead of pretending silence")
        let empty = LiveVoiceService(id: UUID(), sources: [.init(source: .app, name: "Fixture")], journal: nil,
            recognize: { _ in throw CheckFailure() }, update: { _ in })
        try expect(!(await empty.finish()).complete, "missing source cannot become a complete transcript")
        let heldDecoder = FixtureDecoder(suspendFirst: true)
        let cancelled = LiveVoiceService(id: UUID(), sources: [.init(source: .microphone, name: "Fixture")], journal: nil,
            recognize: { try await heldDecoder.recognize($0) }, update: { _ in })
        cancelled.input.append(.init(source: .microphone, samples: samples(1..<19), sampleRate: 16_000, start: 0))
        for _ in 0..<1_000 {
            if await heldDecoder.isWaiting { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try expect(await heldDecoder.isWaiting, "cancellation fixture reaches inference")
        cancelled.requestCancel()
        await heldDecoder.resume()
        let cancelledResult = await cancelled.finish()
        let cancelledCalls = await heldDecoder.calls
        try expect(!cancelledResult.complete && cancelledCalls == 1 && cancelledResult.segments.isEmpty,
                   "Cancel waits for the running model request but never starts a queued window")

        // A decoder that falls more than 60 s behind loses the backlog, not the meeting (#280): the
        // newest audio is still recognised, the pass is incomplete, one note.
        let slowDecoder = FixtureDecoder(suspendFirst: true)
        let behind = LiveVoiceService(id: UUID(), sources: [.init(source: .microphone, name: "Fixture")], journal: nil,
            recognize: { try await slowDecoder.recognize($0) }, update: { _ in })
        behind.input.append(.init(source: .microphone, samples: samples(1..<4), sampleRate: 16_000, start: 0))
        for _ in 0..<1_000 {
            if await slowDecoder.isWaiting { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try expect(await slowDecoder.isWaiting, "backlog fixture reaches inference")
        behind.input.append(.init(source: .microphone, samples: samples(4..<74), sampleRate: 16_000, start: 3))
        behind.input.append(.init(source: .microphone, samples: samples(74..<79), sampleRate: 16_000, start: 73))
        await slowDecoder.resume()
        let caughtUp = await behind.finish()
        try expect(caughtUp.text == (74..<79).map { "word\($0)" }.joined(separator: " ") && caughtUp.completedThrough["microphone"] == 78,
                   "live words skip a backlog past 60 s and continue with the newest audio")
        try expect(!caughtUp.complete && caughtUp.notes.count == 1 && caughtUp.notes[0].contains("fell behind"),
                   "a dropped backlog marks the pass incomplete with one note; the original audio gives the saved words")
        print("Live voice checks passed (\(count)): overlap, source separation, gaps, progressive text, journal recovery, short replies, bounded input, failure, phrases cut in quiet, readings that hear nothing over speech, live words that outlast a backlog, turns across a pause, overlapping speakers, the microphone's copy of the call, and publishing on change. No devices or models were used.")
    }

    private struct CheckFailure: Error {}
    private final class SnapshotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = LiveVoiceSnapshot()
        var current: LiveVoiceSnapshot { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ snapshot: LiveVoiceSnapshot) { lock.lock(); value = snapshot; lock.unlock() }
    }
    /// Every snapshot a service published, in order.
    private final class SnapshotLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [LiveVoiceSnapshot] = []
        var all: [LiveVoiceSnapshot] { lock.lock(); defer { lock.unlock() }; return values }
        func append(_ snapshot: LiveVoiceSnapshot) { lock.lock(); values.append(snapshot); lock.unlock() }
    }
    private actor FixtureDecoder {
        var calls = 0
        var active = 0
        var maximumConcurrency = 0
        var lastLength = 0
        let failOn: Int?
        let suspendFirst: Bool
        /// Words for the first calls, relative to each request's audio; later calls read the fixture audio.
        let script: [[LiveVoiceWord]]
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }
        init(failOn: Int? = nil, suspendFirst: Bool = false, script: [[LiveVoiceWord]] = []) {
            self.failOn = failOn; self.suspendFirst = suspendFirst; self.script = script
        }
        func resume() { continuation?.resume(); continuation = nil }
        func recordLength(_ length: Int) { lastLength = length }
        func recognize(_ samples: [Float]) async throws -> [LiveVoiceWord] {
            calls += 1; active += 1; maximumConcurrency = max(maximumConcurrency, active)
            defer { active -= 1 }
            if calls == failOn { throw CheckFailure() }
            if suspendFirst && calls == 1 { await withCheckedContinuation { continuation = $0 } }
            await Task.yield()
            if calls <= script.count { return script[calls - 1] }
            var words: [LiveVoiceWord] = []
            var start = 0
            while start < samples.count {
                let word = Int((samples[start] * 100).rounded())
                var end = start + 1
                while end < samples.count && Int((samples[end] * 100).rounded()) == word { end += 1 }
                if word > 0 { words.append(.init(text: "word\(word)", start: Double(start) / 16_000, end: Double(end) / 16_000)) }
                start = end
            }
            return words
        }
    }
}
