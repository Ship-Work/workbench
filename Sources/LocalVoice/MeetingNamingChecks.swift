import Foundation

/// Synthetic checks for meeting names: the details they are saved in, how History, Home, Review
/// and Copy show them, the route through Apple's model with a stand-in for the model, and the
/// queue that names meetings one at a time. Every store lives in a temporary folder; the real
/// model, saved History and the clipboard are never used.
enum MeetingNamingChecks {
    @MainActor
    static func run() async throws -> [String] {
        var passed = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw VoiceError.message("MEETING_NAMING_CHECK_FAILED: \(name)") }
            passed += 1
        }
        let utcZone = TimeZone(identifier: "UTC")!
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Workbench-meeting-names-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: root) }

        // Saved details: an earlier build's record still reads, and the new fields survive a relaunch.
        let older = try JSONDecoder().decode(TranscriptMetadata.self, from: Data(#"{"purpose":"meeting","person":"Sam","captureNotes":["A note"]}"#.utf8))
        try check(older.title.isEmpty && older.app.isEmpty && older.summary == nil && older.person == "Sam" && older.captureNotes == ["A note"],
                  "details saved before names read with no name, app or summary")
        let damaged = try JSONDecoder().decode(TranscriptMetadata.self, from: Data(#"{"purpose":"call","app":"FaceTime","summary":{"title":3}}"#.utf8))
        try check(damaged.purpose == .call && damaged.app == "FaceTime" && damaged.summary == nil,
                  "a summary this build cannot read is dropped without losing the other details")
        let summary = TranscriptSummary(title: "Harbour release and Northwind export", about: "The team agreed to ship on the 29th with a timeout fix.",
                                        points: ["Marcus adds the reconciliation job by Thursday.", "Jordan runs the Northwind export on Wednesday."], words: 927)
        var meetingDetails = TranscriptMetadata(purpose: .meeting)
        meetingDetails.app = "Zoom"; meetingDetails.summary = summary
        let library = WorkbenchHistoryModel(directory: root.appendingPathComponent("LocalVoice"))
        let meeting = Transcript(date: Date(timeIntervalSince1970: 1_761_100_000), text: "You: Okay, I think everyone's here.\n\nOthers: Yeah.", seconds: 2_520)
        let dictation = Transcript(date: Date(timeIntervalSince1970: 1_761_100_600), text: "Ask Matt why sign-in fails on staging", seconds: 3)
        let call = Transcript(date: Date(timeIntervalSince1970: 1_761_000_000), text: "You: Hi Mum.", seconds: 300)
        library.setMetadata(meetingDetails, for: meeting.id)
        var callDetails = TranscriptMetadata(purpose: .call); callDetails.app = "FaceTime"
        library.setMetadata(callDetails, for: call.id)
        let reloaded = WorkbenchHistoryModel(directory: root.appendingPathComponent("LocalVoice"))
        try check(reloaded.metadata(for: meeting.id) == meetingDetails && reloaded.metadata(for: call.id).app == "FaceTime",
                  "a meeting's app and summary survive a relaunch")
        var tooLong = meetingDetails; tooLong.summary?.points = Array(repeating: "A point", count: 6)
        try check((try? tooLong.validated()) == nil, "a summary carries at most five points")
        var lineBreak = meetingDetails; lineBreak.title = "Two\nlines"
        try check((try? lineBreak.validated()) == nil, "a name is one line")

        // The name a capture is shown by.
        try check(meetingDetails.heading == "Harbour release and Northwind export", "a described meeting is shown by the name written on this Mac")
        var renamed = meetingDetails; renamed.title = "Harbour go/no-go"
        try check(renamed.heading == "Harbour go/no-go", "the person's own name wins over the written one")
        var unnamed = TranscriptMetadata(purpose: .meeting); unnamed.app = "Zoom"; unnamed.person = "Sam"
        try check(unnamed.heading == "Zoom meeting · Sam", "a meeting not yet described is named by its app and any names given")
        try check(TranscriptMetadata(purpose: .call).heading == "Call", "a call with no app or names reads as a call")
        try check(TranscriptMetadata().heading.isEmpty && TranscriptMetadata(purpose: .note).heading.isEmpty,
                  "a dictation nobody named has no heading and is shown by its words")
        var namedPrompt = TranscriptMetadata(); namedPrompt.title = "Release notes draft"
        try check(namedPrompt.heading == "Release notes draft", "a dictation the person named is shown by that name")

        // Search finds a meeting by its name, what it was about, its points and its app.
        let all = [dictation, meeting, call]
        for (query, expected) in [("northwind", [meeting.id]), ("reconciliation thursday", [meeting.id]), ("zoom", [meeting.id]),
                                  ("facetime", [call.id]), ("harbour export", [meeting.id])] {
            try check(library.matching(all, query: query).map(\.id) == expected, "search for \(query) finds the meeting by its details")
        }

        // History's Meetings filter shows meetings and calls only, with the same search.
        let merged = HistoryList.merged(transcripts: all, snaps: [], results: [])
        let meetingsShown = HistoryList.shown(merged, filter: .meetings, query: "", matchTranscripts: { library.matching($0, query: $1) },
            matchSnap: { _, _ in true }, resultText: { _ in "" }, isMeeting: { library.metadata(for: $0.id).isConversation })
        try check(meetingsShown.map(\.id) == [.transcript(meeting.id), .transcript(call.id)], "Meetings lists meetings and calls, newest first, and no dictation")
        let searched = HistoryList.shown(merged, filter: .meetings, query: "facetime", matchTranscripts: { library.matching($0, query: $1) },
            matchSnap: { _, _ in true }, resultText: { _ in "" }, isMeeting: { library.metadata(for: $0.id).isConversation })
        try check(searched.map(\.id) == [.transcript(call.id)], "Meetings keeps History's search")
        let transcriptsShown = HistoryList.shown(merged, filter: .transcripts, query: "", matchTranscripts: { library.matching($0, query: $1) },
            matchSnap: { _, _ in true }, resultText: { _ in "" }, isMeeting: { library.metadata(for: $0.id).isConversation })
        try check(transcriptsShown.count == 3, "Transcripts still lists every transcript")
        try check(HistoryFilter.allCases.map(\.title) == ["All", "Meetings", "Transcripts", "Snaps", "Results", "Archived"], "History's filters in order")

        // History reads by day: a heading before the first entry of each day, newest first.
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = utcZone
        let now = Date(timeIntervalSince1970: 1_761_163_200) // Wed 22 Oct 2025, 20:00 UTC
        let days = [0.0, -0.5, -1, -3, -40].map { Transcript(date: now.addingTimeInterval($0 * 86_400), text: "Words", seconds: 1) }
        let headings = HistoryDay.starts(HistoryList.merged(transcripts: days, snaps: [], results: []), now: now, calendar: gregorian)
        try check(headings.count == 4 && headings[.transcript(days[0].id)] == "Today" && headings[.transcript(days[1].id)] == nil
                  && headings[.transcript(days[2].id)] == "Yesterday" && headings[.transcript(days[4].id)] != nil,
                  "History heads each day once: Today, Yesterday, a weekday, then a date (\(headings.values.sorted()))")

        // Copy: a meeting starts with its name and when, where and how long; a dictation is its words.
        let utc = utcZone, locale = Locale(identifier: "en_AU")
        let copied = MeetingTranscriptCopy.text(meeting, metadata: meetingDetails, locale: locale, timeZone: utc)
        let stamp = meeting.date.formatted({ var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale); style.timeZone = utc; return style }())
        try check(copied == "Harbour release and Northwind export\nZoom · \(stamp) · 42 min\n\n" + meeting.text,
                  "a copied meeting leads with its name, app, time and length (copied: \(copied.prefix(120)))")
        try check(MeetingTranscriptCopy.text(call, metadata: callDetails, locale: locale, timeZone: utc).hasPrefix("FaceTime call\n"),
                  "a copied meeting not yet described leads with its app, not the app twice")
        try check(MeetingTranscriptCopy.text(dictation, metadata: TranscriptMetadata()) == dictation.text, "a copied dictation is exactly its words")
        let facts = TranscriptFacts.line(meeting, metadata: meetingDetails, words: 6)
        try check(facts.hasSuffix(" · Zoom · 42 min · 6 words"), "History's facts line names the app and length (\(facts))")
        try check(!TranscriptFacts.line(call, metadata: callDetails, words: 3).contains("FaceTime"), "the facts line leaves the app to an unnamed call's heading")
        let home = HomeMeetings.newest(all) { library.metadata(for: $0) }
        try check(home.first?.heading == "Harbour release and Northwind export" && home.first?.excerpt == summary.about,
                  "Home's newest meeting shows its name and what it was about")
        try check(home.last?.heading == "FaceTime call" && home.last?.excerpt == call.text, "Home's undescribed call shows its app and first words")

        // Cleaning what the model wrote.
        try check(MeetingNaming.title("\"Harbour Release and Northwind Escalation.\"") == "Harbour Release and Northwind Escalation", "quotes and a full stop leave a name")
        for generic in ["Meeting", "Weekly Meeting", "Meeting Summary", "Call", "Notes from the call", "Transcript review", "Hi"] {
            try check(MeetingNaming.title(generic) == nil, "\(generic) says nothing about the meeting")
        }
        try check(MeetingNaming.about("This is a summary of the meeting. The team agreed to ship. Marcus fixes the timeout. QA tests Friday.")
                  == "The team agreed to ship. Marcus fixes the timeout.", "what it was about keeps two sentences without boilerplate")
        try check(MeetingNaming.points(["- One", "One", "Two", "", "Three", "Four", "Five", "Six"]) == ["One", "Two", "Three", "Four", "Five"],
                  "points are trimmed, unique and at most five")
        try check(MeetingNaming.subjectsTitle(["Harbour release", "Hiring", "Northwind export", "Hiring", "Meeting"]) == "Hiring, Harbour release and Northwind export",
                  "a long meeting's fallback name lists its most named subjects")
        try check(MeetingNaming.subjectsTitle(["Meeting", "Discussion"]) == nil, "subjects that say nothing make no name")
        try check(MeetingNaming.spread([["A1", "A2", "A3"], ["B1"], ["C1", "C2"]]) == ["A1", "A2", "B1", "C1", "C2"],
                  "a long meeting's points cover every part before any part's third, in order")
        try check(MeetingNaming.spread((0..<10).map { ["P\($0)a", "P\($0)b"] }) == ["P0a", "P2a", "P4a", "P6a", "P8a"],
                  "from more than five parts, points are spread evenly across the meeting")

        // Reading in parts: every word kept, in order, cut between turns.
        let turn = { (i: Int) in (i % 2 == 0 ? "You: " : "Others: ") + String(repeating: "word\(i) ", count: 150).trimmingCharacters(in: .whitespaces) + "." }
        let long = (0..<20).map(turn).joined(separator: "\n\n")
        let parts = MeetingNaming.parts(long, words: 1_000)
        try check(parts.count == 4 && parts.allSatisfy { TextRules.wordCount($0) <= 1_000 }, "a 3,000-word meeting reads in four parts of at most 1,000 words")
        try check(parts.joined(separator: "\n\n") == long, "parts keep every word in order")
        let monologue = "You: " + (0..<300).map { "Sentence number \($0) is here." }.joined(separator: " ")
        let monologueParts = MeetingNaming.parts(monologue, words: 500)
        try check(monologueParts.count >= 3 && monologueParts.allSatisfy { TextRules.wordCount($0) <= 500 }, "a long turn is cut at sentence ends")
        try check(TextRules.wordCount(monologueParts.joined(separator: " ")) == TextRules.wordCount(monologue), "a long turn's parts keep every word")
        let manyNotes = (0..<30).map { MeetingNaming.PartNotes(subjects: ["Subject \($0)"], points: [String(repeating: "point ", count: 40)]) }
        try check(TextRules.wordCount(MeetingNaming.combined(manyNotes)) <= MeetingNaming.notesWords + 30 * 2,
                  "a two-hour meeting's notes stay inside the model's window")
        try check(MeetingNaming.combined(manyNotes).contains("Subject 29"), "every part's subjects reach the name, even when points are left out")

        // The route through the model, with a stand-in.
        let recorder = Requests()
        let wholeAnswer = #"{"title":"Harbour Release","about":"The team agreed to ship.","points":["Marcus fixes the timeout."]}"#
        let short = "You: " + String(repeating: "hello ", count: 20)
        guard case .described(let tooShort) = await MeetingNaming.describe(short, respond: { _, _ in wholeAnswer }) else {
            throw VoiceError.message("MEETING_NAMING_CHECK_FAILED: a short transcript ends described")
        }
        try check(tooShort.isEmpty && tooShort.words == 21, "a transcript too short to describe is kept as described, with nothing to show")
        let fifteen = (0..<6).map(turn).joined(separator: "\n\n")
        guard case .described(let whole) = await MeetingNaming.describe(fifteen, respond: { request, text in
            await recorder.add(request); return wholeAnswer
        }) else { throw VoiceError.message("MEETING_NAMING_CHECK_FAILED: a short meeting is described") }
        try check(whole.title == "Harbour Release" && whole.about == "The team agreed to ship." && whole.points == ["Marcus fixes the timeout."]
                  && whole.words == TextRules.wordCount(fifteen) && whole.source == MeetingNaming.source, "a meeting under 1,700 words is read whole")
        let shortRequests = await recorder.take()
        try check(shortRequests == [.meeting(fromNotes: false)], "a short meeting is one request")
        let partAnswer = #"{"subjects":["Harbour release"],"points":["Ship on the 29th."]}"#
        guard case .described(let parted) = await MeetingNaming.describe(long, respond: { request, _ in
            await recorder.add(request)
            if case .part = request { return partAnswer }
            return #"{"title":"Weekly Meeting","about":"The team agreed to ship on the 29th.","points":[]}"#
        }) else { throw VoiceError.message("MEETING_NAMING_CHECK_FAILED: a long meeting is described") }
        let longRequests = await recorder.take()
        try check(longRequests == [.part(index: 0, of: 4), .part(index: 1, of: 4), .part(index: 2, of: 4), .part(index: 3, of: 4), .meeting(fromNotes: true)],
                  "a long meeting is read in parts, then named from their notes")
        try check(parted.title == "Harbour release" && parted.about == "The team agreed to ship on the 29th." && parted.points == ["Ship on the 29th."],
                  "a generic name for a long meeting falls back to the subjects its parts named, and its points come from the parts")
        guard case .described(let unreadable) = await MeetingNaming.describe(fifteen, respond: { _, _ in "not json" }) else {
            throw VoiceError.message("MEETING_NAMING_CHECK_FAILED: an unreadable answer still ends")
        }
        try check(unreadable.isEmpty, "answers that can't be read leave the meeting described with nothing to show")
        let failed = await MeetingNaming.describe(fifteen, respond: { _, _ in throw URLError(.timedOut) })
        try check(failed == .later, "a model that fails or times out leaves the meeting for later")

        // The queue: idle until the app activates it, newest first, and never writing over changed words.
        var store: [UUID: (text: String, metadata: TranscriptMetadata)] = [:]
        let first = UUID(), second = UUID(), prompt = UUID()
        store[first] = ("You: first meeting words.", TranscriptMetadata(purpose: .meeting))
        store[second] = ("You: second meeting words.", TranscriptMetadata(purpose: .call))
        store[prompt] = ("A dictation", TranscriptMetadata())
        var described: [String] = []
        let namer = MeetingNamer()
        namer.read = { store[$0] }
        namer.write = { id, summary in store[id]?.metadata.summary = summary }
        namer.describe = { text in
            described.append(text)
            return .described(TranscriptSummary(title: "Named " + text.prefix(12), about: "About it.", words: TextRules.wordCount(text)))
        }
        namer.retryDelay = .milliseconds(10)
        namer.enqueue([first])
        try await settle(namer)
        try check(described.isEmpty && store[first]?.metadata.summary == nil, "nothing is read before the app activates naming")
        namer.activate()
        namer.enqueue([second, prompt], first: true)
        try await settle(namer)
        try check(described == ["You: second meeting words.", "You: first meeting words."], "the newest meeting is named first; dictations are never read")
        try check(store[first]?.metadata.summary?.title == "Named You: first m" && store[second]?.metadata.summary != nil, "each meeting gets its summary")
        try check(!MeetingNamer.needsSummary(store[first]!.metadata, words: TextRules.wordCount(store[first]!.text)), "a described meeting is not read again")
        try check(MeetingNamer.needsSummary(store[first]!.metadata, words: 99), "a meeting whose words changed is read again")

        let changing = UUID()
        store[changing] = ("You: words before.", TranscriptMetadata(purpose: .meeting))
        namer.describe = { text in store[changing]?.text = "You: words after the edit."; return .described(TranscriptSummary(title: "Old", about: "", words: 3)) }
        namer.enqueue([changing]); try await settle(namer)
        try check(store[changing]?.metadata.summary == nil, "a summary of words that changed while being read is not saved")

        var unavailableCalls = 0
        let a = UUID(), b = UUID()
        store[a] = ("You: a.", TranscriptMetadata(purpose: .meeting)); store[b] = ("You: b.", TranscriptMetadata(purpose: .meeting))
        namer.describe = { _ in unavailableCalls += 1; return .unavailable }
        namer.enqueue([a, b]); try await settle(namer)
        try check(unavailableCalls == 1, "without Apple Intelligence the queue stops after one try")

        var laterCalls = 0
        namer.describe = { _ in laterCalls += 1; return .later }
        namer.enqueue([a]); try await settle(namer)
        try check(laterCalls == MeetingNamer.maximumTries && store[a]?.metadata.summary == nil, "a busy model is tried three times, then left for the next launch")

        var enabled = false
        namer.isEnabled = { enabled }
        namer.describe = { _ in .described(TranscriptSummary(title: "On", about: "", words: 2)) }
        namer.enqueue([b]); try await settle(namer)
        try check(store[b]?.metadata.summary == nil, "with the switch off, nothing is read")
        enabled = true
        namer.enqueue([b]); try await settle(namer)
        try check(store[b]?.metadata.summary?.title == "On", "switched on again, waiting meetings are named")

        // Earlier recordings tell their app.
        // Meeting folders refuse a path through a symbolic link, as /var's is; /private/tmp is real.
        let meetingsRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("Workbench-meeting-names-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: meetingsRoot) }
        let recorded = UUID()
        _ = try MeetingStore.create(root: meetingsRoot, manifest: MeetingManifest(id: recorded, createdAt: Date(), updatedAt: Date(), purpose: "meeting",
            appName: "Microsoft Teams", appBundleID: "com.microsoft.teams2", includesMicrophone: true, includesRemote: true, state: .stopped, seconds: 60))
        _ = try MeetingStore.create(root: meetingsRoot, manifest: MeetingManifest(id: UUID(), createdAt: Date(), updatedAt: Date(), purpose: "meeting",
            appName: nil, appBundleID: nil, includesMicrophone: true, includesRemote: false, state: .stopped, seconds: 60))
        try check(MeetingNaming.appNames(in: meetingsRoot) == [recorded: "Microsoft Teams"], "a saved recording's app is read from its manifest")

        return ["MEETING_NAMING_CHECKS_OK: \(passed) checks"]
    }

    /// Lets the queue's worker run to the end of what it was given.
    @MainActor
    private static func settle(_ namer: MeetingNamer) async throws {
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(5))
            if namer.working == nil, !namer.isBusy { return }
        }
        throw VoiceError.message("MEETING_NAMING_CHECK_FAILED: the naming queue did not settle")
    }

    private actor Requests {
        var seen: [MeetingNaming.Request] = []
        func add(_ request: MeetingNaming.Request) { seen.append(request) }
        func take() -> [MeetingNaming.Request] { defer { seen = [] }; return seen }
    }
}

/// Names synthetic transcripts with Apple's own model through the app's route, for a person to
/// read: what each meeting is called, what it was about and how long it took on this Mac.
enum MeetingNamingModelCheck {
    static func run(files: [URL]) async throws -> String {
        guard MeetingNaming.isAvailable else { return "MEETING_NAMES_MODEL_UNAVAILABLE: Apple Intelligence is off or not available on this Mac." }
        var lines: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let start = Date()
            let outcome = await MeetingNaming.describe(text)
            let seconds = Date().timeIntervalSince(start)
            lines.append(String(format: "%@ · %d words · %.1f s", file.lastPathComponent, TextRules.wordCount(text), seconds))
            switch outcome {
            case .described(let summary):
                lines.append("  Name: " + summary.title)
                lines.append("  About: " + summary.about)
                lines += summary.points.map { "  • " + $0 }
            case .unavailable: lines.append("  unavailable")
            case .later: lines.append("  later (busy, refused or timed out)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
