import AppKit
import Foundation

enum HandoffJobsChecks {
    /// One small, explicitly requested provider acceptance test. Every record
    /// and preference is isolated; no existing transcript or metadata is read.
    @MainActor static func runMetadataFixture(output: URL) async throws {
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw VoiceError.message("Choose a new verification output directory; existing evidence was kept.")
        }
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench.synthetic.metadata." + UUID().uuidString).path
        guard let defaults = UserDefaults(suiteName: suite) else { throw VoiceError.message("Could not create isolated test preferences.") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "handoff.cli.codex")
        let transcript = Transcript(text: "Meeting notes: I met Avery Example from Example Company to discuss a pilot and agree the next meeting.",
            seconds: 12, rawText: "Um, meeting notes: I met Avery Example from Example Company to discuss a pilot and agree the next meeting.")
        let libraryURL = output.appendingPathComponent("library")
        let library = WorkbenchHistoryModel(directory: libraryURL)
        let original = TranscriptMetadata(purpose: .note, person: "", company: "", tags: ["review-pending"],
            captureNotes: ["Synthetic recording limitation for preservation."])
        library.setMetadata(original, for: transcript.id)
        guard library.error == nil else { throw VoiceError.message(library.error!) }
        let model = HandoffJobsModel(directory: output.appendingPathComponent("handoffs"), defaults: defaults)
        await model.refresh()
        guard model.connections[.codex]?.ready == true else {
            throw VoiceError.message(model.connections[.codex]?.detail ?? "Codex connection was unavailable.")
        }
        let source = HandoffSourceSnapshot(reference: .init(kind: .transcript, id: transcript.id), title: "Synthetic meeting",
            capturedAt: transcript.date, text: transcript.text, originalText: transcript.rawText!, role: .reference,
            captureNotes: original.captureNotes, seconds: transcript.seconds)
        let job = try model.prepare(sources: [source], task: MetadataSuggestionReview.task, skill: try TranscriptHandoffSkills.followUpSnapshot())
        model.start(job, provider: .codex)
        while model.isBusy { try await Task.sleep(nanoseconds: 200_000_000) }
        guard let complete = model.jobs.first(where: { $0.id == job.id }), complete.status == .completed,
              complete.providerSessionID != nil, let result = model.result(complete) else {
            throw VoiceError.message(model.error ?? model.jobs.first?.detail ?? "Details suggestion did not complete.")
        }
        let review = try MetadataSuggestionReview(job: complete, result: result, jobs: model, transcripts: [transcript])
        guard review.metadata.purpose == .meeting, review.metadata.person == "Avery Example",
              review.metadata.company == "Example Company", library.metadata(for: transcript.id) == original else {
            throw VoiceError.message("The suggestion was not grounded in the synthetic names, or changed metadata before review.")
        }
        library.setMetadata(TranscriptMetadata(purpose: review.metadata.purpose, person: review.metadata.person,
            company: review.metadata.company, tags: review.metadata.tags, reviewedSuggestion: review.receipt,
            captureNotes: original.captureNotes), for: transcript.id)
        let reopened = WorkbenchHistoryModel(directory: libraryURL)
        let applied = reopened.metadata(for: transcript.id)
        guard library.error == nil, reopened.error == nil, applied.reviewedSuggestion == review.receipt,
              applied.captureNotes == original.captureNotes, applied.person == "Avery Example",
              review.transcript.text == transcript.text, review.transcript.rawText == transcript.rawText else {
            throw VoiceError.message("Reviewed metadata did not persist with provenance and unchanged original wording.")
        }
        try HandoffJobStore.verify(complete, root: model.folder(complete))
        let receipt: [String: Any] = ["synthetic": true, "status": "passed", "jobID": complete.id.uuidString,
            "providerSessionID": complete.providerSessionID!, "metadataUntouchedUntilReview": true,
            "originalWordingPreserved": true, "recordingLimitationsPreserved": true,
            "reviewedMetadataSurvivedReopen": true, "resultFolder": model.folder(complete).path]
        try HandoffJobStore.write(JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]),
            to: output.appendingPathComponent("verification.json"))
        print("HANDOFF_METADATA_FIXTURE_OK: final response parsed, original details stayed unchanged until review, and reviewed details reopened with provenance. Folder: " + output.path)
    }

    /// Explicit developer acceptance command. Reads exactly the 45 supplied
    /// synthetic PNGs; a ground-truth file or generator is never sent.
    @MainActor static func runVisualFixture(images directory: URL, output: URL) async throws {
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw VoiceError.message("Choose a new verification output directory; existing evidence was kept.")
        }
        var sources: [HandoffSourceSnapshot] = []
        for index in 1...45 {
            let name = String(format: "source-%02d", index)
            let url = directory.appendingPathComponent(name + ".png")
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? Int.max) <= 10 * 1024 * 1024 else {
                throw VoiceError.message("A synthetic image is unavailable or exceeds the connected limit.")
            }
            let bytes = try Data(contentsOf: url)
            _ = try SnapRendering.image(bytes)
            sources.append(HandoffSourceSnapshot(reference: .init(kind: .snap, id: UUID()), title: name,
                capturedAt: Date(timeIntervalSince1970: 100 + Double(index)), text: "Synthetic visual acceptance source " + name,
                originalText: "Synthetic visual acceptance source " + name, role: .reference, images: [bytes]))
        }
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench.synthetic.visual." + UUID().uuidString).path
        guard let defaults = UserDefaults(suiteName: suite) else { throw VoiceError.message("Could not create isolated test preferences.") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "handoff.cli.codex")
        let model = HandoffJobsModel(directory: output, defaults: defaults)
        await model.refresh()
        guard model.connections[.codex]?.ready == true else {
            throw VoiceError.message(model.connections[.codex]?.detail ?? "Codex connection was unavailable.")
        }
        let request = """
        Analyze all 45 selected synthetic screenshots as one body of evidence. Group their concrete statements into themes and write a useful synthesis.
        Then include a complete coverage table with exactly one row per source-01 through source-45: source name, a link to its supplied image, visible theme, concrete statement, and the exact unique visual marker printed inside that image.
        Read each image. Mark anything unreadable explicitly; do not invent markers or omit sources. The supplied text contains no marker values. Return Markdown only.
        """
        let job = try model.prepare(sources: sources, task: request, skill: try TranscriptHandoffSkills.followUpSnapshot())
        model.start(job, provider: .codex)
        while model.isBusy { try await Task.sleep(nanoseconds: 200_000_000) }
        guard let complete = model.jobs.first(where: { $0.id == job.id }), complete.status == .completed,
              complete.providerSessionID != nil, let result = model.result(complete), !result.isEmpty else {
            throw VoiceError.message(model.error ?? model.jobs.first?.detail ?? "Visual task did not complete.")
        }
        try HandoffJobStore.verify(complete, root: model.folder(complete))
        let record = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: model.folder(complete).appendingPathComponent("selection.json"))
        guard record.items.count == 45, record.items.flatMap(\.images).count == 45 else {
            throw VoiceError.message("Visual verification did not preserve all 45 selected sources.")
        }
        print("HANDOFF_VISUAL_FIXTURE_RETURNED: 45 sources preserved; compare result to ground truth outside the provider job. Folder: " + model.folder(complete).path)
    }

    @MainActor static func run() async throws -> [String] {
        var passed = try await HandoffManualChecks.run()
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw VoiceError.message("HANDOFF_JOBS_CHECK_FAILED: " + message) }
            passed += 1
        }
        func rejects(_ label: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { passed += 1; return }
            throw VoiceError.message("HANDOFF_JOBS_CHECK_FAILED: " + label)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-job-check-" + UUID().uuidString)
        try HandoffJobStore.privateDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let followUpText = try TranscriptHandoffSkills.builtInText(TranscriptHandoffSkills.followUpReference.id)
        let id = UUID(), snapID = UUID()
        let phrase = "Synthetic meeting: Alex Example proposed a pilot."
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
        let sources = [
            HandoffSourceSnapshot(reference: WorkbenchItemReference(kind: .transcript, id: id), title: "Synthetic meeting",
                capturedAt: Date(timeIntervalSince1970: 100), text: phrase, originalText: "um " + phrase, role: .reference,
                captureNotes: ["The selected app stopped producing audio."], seconds: 53.86666666666667),
            HandoffSourceSnapshot(reference: WorkbenchItemReference(kind: .snap, id: snapID), title: "Synthetic Snap",
                capturedAt: Date(timeIntervalSince1970: 101), text: "One selected screenshot", originalText: "One selected screenshot",
                role: .reference, images: [image])
        ]
        let skill = try TranscriptHandoffSkills.followUpSnapshot()
        let meetingTask = TranscriptHandoffSkill.builtIns.first { $0.id == MeetingFollowUp.skillID }?.defaultTask ?? "Prepare notes and a follow-up message from this conversation."
        let store = HandoffJobsModel(directory: root)
        let first = try store.prepare(sources: sources, task: "Summarize the decision.", skill: skill)
        let again = try store.prepare(sources: sources, task: "Summarize the decision.", skill: skill)
        try check(first.id == again.id && store.jobs.count == 1, "repeated prepare reuses immutable selected snapshot")
        let folder = store.folder(first)
        try HandoffJobStore.verify(first, root: folder); passed += 1
        let snapshot = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: folder.appendingPathComponent("selection.json"))
        try check(snapshot.items.map(\.reference) == sources.map(\.reference), "only selected stable identities enter job")
        try check(snapshot.items[0].role == .reference && snapshot.items[0].originalText == "um " + phrase, "original wording and reference role survive")
        try check(snapshot.items[1].images.count == 1, "selected image stays paired with its own text")
        let legacy = try HandoffJobStore.read(TranscriptHandoffManifest.self, at: folder.appendingPathComponent("handoff.json"))
        try check(legacy.transcripts.count == 1 && legacy.transcriptRole == .reference, "portable transcript skill manifest remains readable")
        try check(snapshot.items[0].seconds == 53.86666666666667 && legacy.transcripts[0].seconds == 53.86666666666667,
                  "the recorded duration survives the frozen selection and portable transcript export")
        var oldInput = try JSONSerialization.jsonObject(with: HandoffJobStore.encode(snapshot.items[0])) as! [String: Any]
        oldInput.removeValue(forKey: "seconds")
        let oldRecord = try JSONDecoder().decode(HandoffInputRecord.self, from: JSONSerialization.data(withJSONObject: oldInput))
        try check(oldRecord.seconds == nil && oldRecord.reference == snapshot.items[0].reference,
                  "an older frozen input still decodes with unknown duration and its original identity")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent(legacy.transcripts[0].originalFile).path), "portable original file is present")
        try check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("outputs").path), "portable output directory is present")
        let manual = HandoffJobStore.prompt(snapshot: snapshot, skill: followUpText, folder: folder, manual: true)
        try check(manual.contains(phrase) && manual.contains("Original wording:") && manual.contains("Attach these selected image"), "manual fallback includes selected words and exact attachment step")
        let connected = HandoffJobStore.prompt(snapshot: snapshot, skill: followUpText, folder: folder, manual: false)
        try check(connected.contains("format requested by the task") && connected.contains("REFERENCE"), "connected task output and source roles explicit")
        // A two-sided meeting saves its labelled conversation as the text and the same words
        // unlabelled as the original (MeetingRecovery.commitCheckpoint). Built by the real
        // producer, with same-side pauses so labels repeat, an hour-long call is sent once.
        let marker = "Unique marker: the cobalt orchard plan stays."
        let call = LiveVoiceCheckpoint(sessionID: UUID(), segments: (0..<620).map { (index: Int) -> LiveVoiceSegment in
            let words = "Point \(index + 1). Maya will review the proposal on Thursday and Sam will confirm the room."
            let source: LiveVoiceSource = index / 2 % 2 == 0 ? .microphone : .app
            return LiveVoiceSegment(source: source, start: Double(index) * 6, end: Double(index) * 6 + 5,
                                    text: index == 310 ? words + " " + marker : words, isFinal: true)
        })
        try check(call.conversation.count > 55_000 && call.conversation.contains("You: Point 2.") && call.conversation.contains("\n\nOthers: Point 4."),
                  "the synthetic call is an hour-long labelled conversation whose labels repeat")
        let calls = HandoffJobsModel(directory: root.appendingPathComponent("call"))
        let callJob = try calls.prepare(sources: [HandoffSourceSnapshot(reference: WorkbenchItemReference(kind: .transcript, id: UUID()),
            title: "Synthetic call", capturedAt: Date(timeIntervalSince1970: 200), text: call.conversation, originalText: call.text,
            role: .reference, seconds: 3_720)], task: meetingTask, skill: skill)
        let callFolder = calls.folder(callJob)
        let callSnapshot = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: callFolder.appendingPathComponent("selection.json"))
        let callPrompts = [true, false].map { HandoffJobStore.prompt(snapshot: callSnapshot, skill: followUpText, folder: callFolder, manual: $0) }
        try check(callPrompts.allSatisfy { !$0.contains("Original wording:") && $0.components(separatedBy: marker).count == 2 },
                  "a two-sided meeting's unlabelled original is not sent a second time")
        let callProblem = HandoffRunReadiness.inputProblem(provider: .codex, prompt: callPrompts[1], imageBytes: [], items: 1)
        let readyRunner = SubscriptionConnection(provider: .codex, executable: URL(fileURLWithPath: "/usr/bin/false"), version: "synthetic",
                                                 ready: true, detail: "Synthetic fixture; no process or network.")
        try check(callPrompts[1].count < SubscriptionCLILimits.maximumPromptCharacters && callProblem == nil
                  && HandoffRunReadiness.evaluate(provider: .codex, enabled: true, checking: false, connection: readyRunner, busy: false,
                                                  compatible: true, inputProblem: callProblem).state == .ready,
                  "an hour-long two-sided meeting stays within the connected limit, so Start task is offered")
        // A two-hour call by the same producer is one transcript past the connected limit (#377).
        // Choosing fewer items cannot help one item, so its reason names the step that works:
        // Copy instructions, whose copy carries the whole call. Several items keep both steps.
        let long = LiveVoiceCheckpoint(sessionID: UUID(), segments: (0..<1_240).map { (index: Int) -> LiveVoiceSegment in
            let words = "Point \(index + 1). Maya will review the proposal on Thursday and Sam will confirm the room."
            return LiveVoiceSegment(source: index / 2 % 2 == 0 ? .microphone : .app, start: Double(index) * 6, end: Double(index) * 6 + 5,
                                    text: index == 1_239 ? words + " " + marker : words, isFinal: true)
        })
        let longJob = try calls.prepare(sources: [HandoffSourceSnapshot(reference: WorkbenchItemReference(kind: .transcript, id: UUID()),
            title: "Synthetic two-hour call", capturedAt: Date(timeIntervalSince1970: 300), text: long.conversation, originalText: long.text,
            role: .reference, seconds: 7_200)], task: meetingTask, skill: skill)
        let longFolder = calls.folder(longJob)
        let longSnapshot = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: longFolder.appendingPathComponent("selection.json"))
        let longPrompts = [true, false].map { HandoffJobStore.prompt(snapshot: longSnapshot, skill: followUpText, folder: longFolder, manual: $0) }
        let longProblem = HandoffRunReadiness.inputProblem(provider: .codex, prompt: longPrompts[1], imageBytes: [], items: longSnapshot.items.count)
        let longReadiness = HandoffRunReadiness.evaluate(provider: .codex, enabled: true, checking: false, connection: readyRunner, busy: false,
                                                         compatible: true, inputProblem: longProblem)
        try check(longPrompts[1].count > SubscriptionCLILimits.maximumPromptCharacters && longReadiness.state == .inputLimit && !longReadiness.canStart
                  && longProblem?.contains("Use Copy instructions") == true && longProblem?.contains("fewer items") == false
                  && longPrompts[0].components(separatedBy: marker).count == 2,
                  "a two-hour meeting past the connected limit names Copy instructions, which carries its last words, never Choose fewer items")
        try check(HandoffRunReadiness.inputProblem(provider: .codex, prompt: longPrompts[1], imageBytes: [], items: 2)?.contains("Choose fewer items") == true,
                  "a selection of several items past the limit can still be made smaller")
        let callPortable = try HandoffJobStore.read(TranscriptHandoffManifest.self, at: callFolder.appendingPathComponent("handoff.json"))
        try check(callSnapshot.items[0].originalText == call.text
                  && (try Data(contentsOf: callFolder.appendingPathComponent(callPortable.transcripts[0].originalFile))) == Data(call.text.utf8),
                  "the frozen selection and portable original keep the unlabelled words byte for byte")
        var editedCall = callSnapshot
        editedCall.items[0].text = call.conversation.replacingOccurrences(of: "Point 7. Maya", with: "Point 7. Avery")
        try check(HandoffJobStore.prompt(snapshot: editedCall, skill: followUpText, folder: callFolder, manual: false).contains("Original wording:"),
                  "a meeting edited after it was saved keeps its original wording beside the text")
        // Only a label opening the text or a paragraph is a label; any other difference keeps the original.
        let shapes: [(text: String, original: String, adds: Bool)] = [
            ("You: Ready.\n\nOthers:  Agreed,\nthanks.", "Ready. Agreed, thanks.", false),
            ("You: Ready.\n\nOthers: You: Agreed.", "Ready. Agreed.", true),
            ("You: Ready. Others: Agreed.", "Ready. Agreed.", true),
            ("You: Ready.\n\n\nOthers: Agreed.", "Ready. Agreed.", true),
            ("You: Ready.\n\nOthers: Agreed.", "Ready. Agreed. More.", true),
            ("You: Ready.\n\nOthers: Agreed. More.", "Ready. Agreed.", true),
        ]
        try check(shapes.allSatisfy { HandoffJobStore.originalAddsWording(text: $0.text, original: $0.original) == $0.adds },
                  "an original that differs from the conversation only by its opening labels and spacing is the only one left out")
        // Resolve the actual links supplied to an assistant from the documents
        // each route asks it to produce, rather than checking a path fragment.
        func imageLinks(in prompt: String) throws -> [String] {
            let expression = try NSRegularExpression(pattern: #"\]\(([^)]+)\)"#)
            let text = prompt as NSString
            return expression.matches(in: prompt, range: NSRange(location: 0, length: text.length))
                .map { text.substring(with: $0.range(at: 1)) }
                .filter { $0.contains("inputs/") }
        }
        func linkedImage(_ link: String, from document: String) throws -> Data {
            let directory = folder.appendingPathComponent(document).deletingLastPathComponent()
            return try Data(contentsOf: directory.appendingPathComponent(link).standardizedFileURL)
        }
        let manualLinks = try imageLinks(in: manual)
        let directLinks = manualLinks.filter { $0.hasPrefix("../inputs/") }
        let nestedLinks = manualLinks.filter { $0.hasPrefix("../../inputs/") }
        try check(directLinks.count == 1 && nestedLinks.count == 1, "manual prompt supplies links for direct and nested output documents")
        try check(try linkedImage(directLinks[0], from: "outputs/follow-up.md") == image,
                  "manual source link resolves to the exact frozen image from outputs")
        try check(try linkedImage(nestedLinks[0], from: "outputs/review/follow-up.md") == image,
                  "nested manual source-link example resolves to the exact frozen image")
        let connectedLinks = try imageLinks(in: connected)
        try check(connectedLinks.count == 1 && connectedLinks[0] == snapshot.items[1].images[0],
                  "connected source links retain the root-relative inventory path")
        try check(try linkedImage(connectedLinks[0], from: "result.md") == image,
                  "connected result source link resolves to the exact frozen image")
        try HandoffJobStore.verify(first, root: folder); passed += 1
        try check(snapshot.items[0].captureNotes == sources[0].captureNotes && connected.contains("The selected app stopped producing audio."),
                  "recording gaps survive frozen inputs and provider prompt without modifying source words")

        var edited = sources
        edited[0].text = "Changed words."
        try check(edited != sources, "same IDs with changed words require a refreshed review")
        edited = sources; edited[1].images = [Data("different".utf8)]
        try check(edited != sources, "same IDs with changed image bytes require a refreshed review")
        let imagePath = folder.appendingPathComponent(snapshot.items[1].images[0])
        try HandoffJobStore.write(Data("tampered".utf8), to: imagePath)
        try rejects("image mutation rejected before dispatch") { try HandoffJobStore.verify(first, root: folder) }
        let repaired = try store.prepare(sources: sources, task: "Summarize the decision.", skill: skill)
        try check(repaired.id != first.id, "explicit fresh review preserves damaged snapshot and creates new immutable input")
        try HandoffJobStore.verify(repaired, root: store.folder(repaired)); passed += 1
        let third = try store.prepare(sources: sources, task: "Prepare another draft.", skill: skill)
        try HandoffJobStore.write(Data("{broken".utf8), to: folder.appendingPathComponent("receipt.json"))
        let recovered = HandoffJobsModel(directory: root)
        try check(Set(recovered.jobs.map(\.id)) == Set([repaired.id, third.id]), "one damaged receipt cannot hide other jobs")
        try check(recovered.error != nil, "damaged receipt remains visible as a recovery problem")
        var pending = third
        pending.status = .running
        try HandoffJobStore.write(HandoffJobStore.encode(pending), to: store.folder(third).appendingPathComponent("receipt.json"))
        let relaunched = HandoffJobsModel(directory: root)
        try check(relaunched.jobs.first(where: { $0.id == third.id })?.status == .interrupted, "uncertain run becomes interrupted after restart")
        try check(!relaunched.isBusy, "restart never automatically launches a task")
        try rejects("too many images refused without changing jobs") {
            var tooMany = sources
            tooMany[1].images = Array(repeating: image, count: HandoffJobStore.maximumImages + 1)
            _ = try store.prepare(sources: tooMany, task: "Summarize", skill: skill)
        }
        let before = try Data(contentsOf: store.folder(repaired).appendingPathComponent("selection.json"))
        try rejects("duplicate reference refused") { _ = try store.prepare(sources: [sources[0], sources[0]], task: "Summarize", skill: skill) }
        try check(Data(contentsOf: store.folder(repaired).appendingPathComponent("selection.json")) == before, "invalid work leaves prior snapshot exact")
        for reserved in ["selection.json", "Receipt.JSON", "result.md"] {
            var files = skill.files
            files[reserved] = Data("skill content".utf8)
            try rejects("owned handoff names cannot be replaced by a skill") {
                _ = try store.prepare(sources: sources, task: "Summarize", skill: .init(reference: skill.reference, files: files))
            }
        }
        let batch = (1...45).map { index in
            HandoffSourceSnapshot(reference: .init(kind: .snap, id: UUID()), title: "Source \(index)", capturedAt: Date(),
                text: "", originalText: "", role: .reference, images: [image])
        }
        let batchJob = try store.prepare(sources: batch, task: "Synthesize every selected image.", skill: skill)
        let batchRecord = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: store.folder(batchJob).appendingPathComponent("selection.json"))
        try check(batchRecord.items.count == 45 && batchRecord.items.flatMap(\.images).count == 45,
                  "representative 45-image batch preserves every selected source")
        try HandoffJobStore.verify(batchJob, root: store.folder(batchJob)); passed += 1

        // A coloured private marker outside a deliberate crop must not reach
        // either the connected or manual job, while the local original remains.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<40 { for x in 0..<100 {
            let offset = y * bitmap.bytesPerRow + x * 4
            bitmap.bitmapData![offset] = x < 50 ? 0 : 255
            bitmap.bitmapData![offset + 1] = x < 50 ? 255 : 0
            bitmap.bitmapData![offset + 2] = 0
            bitmap.bitmapData![offset + 3] = 255
        } }
        let uncropped = bitmap.representation(using: .png, properties: [:])!
        let cropped = try SnapRendering.render(uncropped, edit: SnapEdit(crop: SnapCrop(x: 0, y: 0, width: 0.5, height: 1)))
        let privateSnap = SnapHandoffSnapshot(id: UUID(), title: "Cropped", createdAt: Date(), originalPNG: uncropped,
            renderedPNG: cropped, note: "", tags: [])
        let reviewed = privateSnap.reviewedHandoffSource
        try check(reviewed.images == [cropped] && privateSnap.originalPNG == uncropped, "crop is sole dispatch image; original stays local")
        let croppedBitmap = NSBitmapImageRep(data: reviewed.images[0])!
        let pixel = croppedBitmap.colorAt(x: 49, y: 20)!.usingColorSpace(.deviceRGB)!
        try check(croppedBitmap.pixelsWide == 50 && pixel.redComponent < 0.1 && pixel.greenComponent > 0.9,
                  "outside-crop red marker is absent from reviewed pixels")
        let cropJob = try store.prepare(sources: [reviewed], task: "Describe this image", skill: skill)
        let cropRecord = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: store.folder(cropJob).appendingPathComponent("selection.json"))
        try check(Data(contentsOf: store.folder(cropJob).appendingPathComponent(cropRecord.items[0].images[0])) == cropped,
                  "immutable job contains visible crop, never original pixels")
        try rejects("empty provider metadata is not a valid migration-default suggestion") { _ = try MetadataSuggestionReview.parse("{}") }
        try rejects("provider errors cannot clear metadata") { _ = try MetadataSuggestionReview.parse("{\"error\":\"Unable to read\"}") }
        let proposal = try MetadataSuggestionReview.parse("{\"purpose\":\"meeting\",\"person\":\"Alex Example\",\"company\":\"\",\"tags\":[\"pilot\"]}")
        try check(proposal.purpose == .meeting && proposal.person == "Alex Example", "complete typed suggestion remains reviewable")
        let detailsJob = try store.prepare(sources: [sources[0]], task: MetadataSuggestionReview.task, skill: skill)
        let detailsRecord = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: store.folder(detailsJob).appendingPathComponent("selection.json"))
        let detailsPrompt = HandoffJobStore.prompt(snapshot: detailsRecord, skill: followUpText,
            folder: store.folder(detailsJob), manual: false)
        try check(detailsPrompt.contains("Recording limitations are preserved separately")
            && !detailsPrompt.contains("preserve these qualifications in your result"),
            "details task retains recording limitations without forcing them into the JSON proposal")
        // Home's recap: a details suggestion made after the follow-up, from the same meeting, is
        // not shown as the follow-up; with only the suggestion, Prepare follow-up… stays.
        let recaps = HandoffJobsModel(directory: root.appendingPathComponent("home-recap"), switches: ({ _ in false }, { _, _ in }))
        var recapClock = Date(timeIntervalSince1970: 1_000)
        recaps.clock = { recapClock.addTimeInterval(1); return recapClock }
        let meetingFollowUp = try recaps.prepare(sources: [sources[0]], task: meetingTask, skill: skill)
        let laterDetails = try recaps.prepare(sources: [sources[0]], task: MetadataSuggestionReview.task, skill: skill)
        await recaps.loadTaskFiles(recaps.jobs)
        let recapInputs = { (job: HandoffJob) in recaps.files(job)?.inputs.items.map(\.reference) ?? [] }
        try check(laterDetails.createdAt > meetingFollowUp.createdAt && recaps.isMetadataSuggestion(laterDetails)
                  && HomeMeetings.followUp(for: id, in: recaps.visibleJobs, inputs: recapInputs, excluding: { recaps.isMetadataSuggestion($0) })?.id == meetingFollowUp.id,
                  "Home's recap names the meeting's follow-up, not a newer details suggestion")
        try check(HomeMeetings.followUp(for: id, in: recaps.visibleJobs.filter { $0.id == laterDetails.id }, inputs: recapInputs,
                                        excluding: { recaps.isMetadataSuggestion($0) }) == nil,
                  "a meeting with only a details suggestion still offers Prepare follow-up…")
        // A details suggestion is named as the door that asked for it. A follow-up, or a details
        // task the person edited, keeps the skill's name, and the name leaves the fingerprint alone.
        let editedDetails = try recaps.prepare(sources: [sources[0]], task: MetadataSuggestionReview.task + " Also list action items.", skill: skill)
        await recaps.loadTaskFiles(recaps.jobs)
        try check(detailsJob.title == "Suggest details" && laterDetails.title == "Suggest details" && recaps.title(laterDetails) == "Suggest details",
                  "an assistant's details suggestion is titled Suggest details")
        try check(meetingFollowUp.title == "Prepare follow-up" && recaps.title(meetingFollowUp) == "Prepare follow-up" && first.title == "Prepare follow-up",
                  "a meeting follow-up and a general task keep the skill's name")
        try check(editedDetails.title == "Prepare follow-up" && !recaps.isMetadataSuggestion(editedDetails) && recaps.title(editedDetails) == "Prepare follow-up",
                  "a details task the person edited is not a details suggestion and keeps the skill's name")
        try check(try recaps.prepare(sources: [sources[0]], task: MetadataSuggestionReview.task, skill: skill).id == laterDetails.id,
                  "preparing the same details task again reuses it; the title is not part of the fingerprint")
        // A details suggestion saved under the skill's name, before it had its own, reads as one.
        var savedEarlier = laterDetails
        savedEarlier.title = "Prepare follow-up"
        try HandoffJobStore.write(HandoffJobStore.encode(savedEarlier), to: recaps.folder(laterDetails).appendingPathComponent("receipt.json"))
        let restarted = HandoffJobsModel(directory: root.appendingPathComponent("home-recap"), switches: ({ _ in false }, { _, _ in }))
        await restarted.loadTaskFiles(restarted.jobs)
        let earlierDetails = restarted.jobs.first { $0.id == laterDetails.id }, earlierFollowUp = restarted.jobs.first { $0.id == meetingFollowUp.id }
        try check(earlierDetails?.title == "Prepare follow-up" && earlierDetails.map(restarted.title) == "Suggest details"
                  && earlierFollowUp.map(restarted.title) == "Prepare follow-up",
                  "a details suggestion saved as Prepare follow-up shows as Suggest details; a real follow-up keeps its name")

        let snaps = SnapStore(root: root.appendingPathComponent("review-snaps"))
        let snap = try snaps.insert(originalPNG: image, width: 1, height: 1, title: "User-reviewed name", source: .screen)
        let namedID = UUID()
        let context = try SnapOrganization.context(store: snaps, ids: [snap.id], selectionID: namedID, title: "Customer research")
        let namedSource = HandoffSourceSnapshot(reference: .init(kind: .snap, id: snap.id), title: snap.title,
            capturedAt: snap.createdAt, text: "User note", originalText: "User note", role: .reference, images: [image])
        var namedJob = try store.prepare(sources: [namedSource], task: SnapOrganization.assistantInstruction, skill: skill, review: context)
        let namedRoot = store.folder(namedJob)
        let namedRecord = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: namedRoot.appendingPathComponent("selection.json"))
        try check(namedRecord.review?.selectionID == namedID && namedJob.reviewKey == context.key,
                  "logical named review survives the immutable task boundary")
        let link = namedRecord.items[0].images[0]
        let reply = """
        ```markdown
        # Proposed synthesis
        [Plain](\(link))
        [Angle](<\(link)>)
        [Title](\(link) "Capture")
        [Angle title](<\(link)> "Capture")
        [Dot](./\(link) 'Capture')
        [Reference][one] and [Reference with title][two].

        [one]: \(link)
        [two]: <\(link)> "Source image"
        [three]:
          ./\(link) 'Source image'
        Suggested rename and exclusion remain proposals.
        ```
        """
        try HandoffJobStore.write(Data(reply.utf8), to: namedRoot.appendingPathComponent("result.md"))
        let published = try HandoffReviewPublication.publish(job: namedJob, snapshot: namedRecord, result: reply,
            store: snaps, root: namedRoot, replacingChanges: false)
        let current = try snaps.readOrganization(key: context.key)!
        try check(current.digest == published && Data(contentsOf: namedRoot.appendingPathComponent("result.md")) == Data(reply.utf8),
                  "current review publishes without changing the immutable provider reply")
        try check(current.text.hasPrefix("# Proposed synthesis\n") && !current.text.contains("```"),
                  "whole-document Markdown wrapper is removed only from the published review")
        func publishedText(_ value: String) -> String {
            SnapOrganization.rebasedResult(value, inputs: [], jobRoot: namedRoot, destination: current.url)
        }
        let innerCode = "# Review\n\n```swift\nlet answer = 42\n```\n"
        try check(publishedText("````markdown\n" + innerCode + "````\n") == innerCode,
                  "long outer Markdown fence preserves internal code byte-for-byte")
        try check(publishedText("\r\n  ~~~MD\r\n# Review 🌿\r\n  ~~~~\r\n") == "# Review 🌿\r\n",
                  "Markdown-labelled tilde wrapper supports CRLF, Unicode and longer closing fences")
        for unchanged in ["# Plain review\n", "```swift\nlet answer = 42\n```", "```\n# Code example\n```",
                          "Intro\n```markdown\n# Example\n```", "```md\n# Example\n```\nAfterword",
                          "```md\n# One\n```\n```md\n# Two\n```", "```markdown\n# Unclosed",
                          "```markdown\n" + innerCode + "```", "```markdown\n\n```"] {
            try check(publishedText(unchanged) == unchanged,
                      "plain, non-Markdown, partial and ambiguous fenced replies retain their exact text")
        }
        let expression = try NSRegularExpression(pattern: #"\]\(<?([^> )]+)"#)
        let links = expression.matches(in: current.text, range: NSRange(current.text.startIndex..., in: current.text))
        try check(links.count == 5, "all supported Markdown link forms remain present")
        for match in links {
            let destination = (current.text as NSString).substring(with: match.range(at: 1))
            guard let url = URL(string: destination, relativeTo: current.url)?.absoluteURL else { throw VoiceError.message("A published link is invalid.") }
            try check(try Data(contentsOf: url) == image, "published source link opens the exact frozen image")
        }
        let definitions = try NSRegularExpression(pattern: #"(?m)^\[[^\]]+\]:\s*<?([^> \r\n]+)"#)
        let references = definitions.matches(in: current.text, range: NSRange(current.text.startIndex..., in: current.text))
        try check(references.count == 3, "reference-style source definitions retain their labels and titles")
        for match in references {
            let destination = (current.text as NSString).substring(with: match.range(at: 1))
            guard let url = URL(string: destination, relativeTo: current.url)?.absoluteURL else { throw VoiceError.message("A published reference is invalid.") }
            try check(try Data(contentsOf: url) == image, "published reference-style link opens the exact frozen image")
        }
        namedJob.status = .completed; namedJob.publishedReviewDigest = published; namedJob.reviewPublishedAt = Date()
        try HandoffJobStore.write(HandoffJobStore.encode(namedJob), to: namedRoot.appendingPathComponent("receipt.json"))
        var changedSource = namedSource; changedSource.text = "Additional user note"
        let nextContext = try SnapOrganization.context(store: snaps, ids: [snap.id], selectionID: namedID, title: "Customer research")
        let nextJob = try store.prepare(sources: [changedSource], task: SnapOrganization.assistantInstruction, skill: skill, review: nextContext)
        let nextRecord = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: store.folder(nextJob).appendingPathComponent("selection.json"))
        try check(nextJob.id != namedJob.id && nextJob.reviewKey == namedJob.reviewKey && nextRecord.review?.previousDocument == current.text,
                  "changed named evidence makes a new immutable task with the same current review and prior reference")
        let reopenedJobs = HandoffJobsModel(directory: root)
        reopenedJobs.currentReviewDigest = { key in (try? snaps.readOrganization(key: key))?.digest }
        try check(reopenedJobs.visibleJobs.filter { $0.reviewKey == context.key }.count == 1
            && reopenedJobs.currentPublishedJob(key: context.key)?.id == namedJob.id,
            "newer ready task does not hide the last published result and named history groups once")
        // History asks for the current review's digest on every redraw (#150): the store answers
        // from the file's stamp and reads the document again only when the file changes.
        let reviewBefore = try snaps.readOrganization(key: context.key)!
        try check(snaps.organizationDigest(key: context.key) == reviewBefore.digest, "the kept digest is the document's digest")
        // Permissions are not part of the stamp, so an unreadable file with the same date and size must be answered from the kept digest.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: reviewBefore.url.path)
        try check(snaps.organizationDigest(key: context.key) == reviewBefore.digest, "an unchanged stamp is answered without reading the file")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reviewBefore.url.path)
        let sameLength = Data(String(repeating: "x", count: reviewBefore.text.utf8.count).utf8)
        try sameLength.write(to: reviewBefore.url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: reviewBefore.url.path)
        try check(snaps.organizationDigest(key: context.key) == SnapStore.digest(sameLength), "a changed stamp reads the document again")
        _ = try snaps.writeOrganization(reviewBefore.text, key: context.key)
        try check(snaps.organizationDigest(key: context.key) == reviewBefore.digest, "a saved review is digested afresh")
        try check(snaps.organizationDigest(key: String(repeating: "0", count: 64)) == nil, "a review that does not exist answers nil")
        let manualReview = "A newer human-edited review. Keep this."
        _ = try snaps.writeOrganization(manualReview, key: context.key)
        try rejects("late completion cannot overwrite a changed review") {
            _ = try HandoffReviewPublication.publish(job: nextJob, snapshot: nextRecord, result: reply,
                store: snaps, root: store.folder(nextJob), replacingChanges: false)
        }
        try check(try snaps.readOrganization(key: context.key)?.text == manualReview, "conflicted publication preserves the newer human document")
        _ = try HandoffReviewPublication.publish(job: nextJob, snapshot: nextRecord, result: reply,
            store: snaps, root: store.folder(nextJob), replacingChanges: true)
        let backups = try FileManager.default.contentsOfDirectory(at: store.folder(nextJob).appendingPathComponent("outputs"), includingPropertiesForKeys: nil)
        try check(backups.count == 1 && String(contentsOf: backups[0], encoding: .utf8) == manualReview,
                  "deliberate replacement preserves the intervening human document")
        let unchangedSnap = try snaps.read(snap.id)
        try check(unchangedSnap.title == "User-reviewed name" && unchangedSnap.archivedAt == nil,
                  "publishing assistant prose never applies a suggested rename or exclusion")
        // Built-in skills are skill files in a pack bundled with Workbench, read
        // and checked like an installed pack. Each declares an inline reply and a
        // suggested task in its SKILL.md metadata, so it starts as a connected task.
        let bundled = try WorkbenchSkillPack.payload()
        try check(bundled.manifest.id == "workbench" && bundled.manifest.entries.allSatisfy { $0.kind == .skill && $0.inputKinds == [.transcripts] },
                  "the built-in skills load through the private pack format, digests included")
        let builtIns = TranscriptHandoffSkill.builtIns
        try check(builtIns.map(\.id) == [TranscriptHandoffSkills.followUpReference.id, "workbench-meeting-follow-up", "workbench-sharpen-prompt", "workbench-conversation-coach"]
                  && builtIns.allSatisfy { $0.repliesInline && $0.defaultTask != nil && !$0.detail.isEmpty },
                  "built-in skills keep their identities and order, reply inline and suggest a task")
        try check(TranscriptHandoffSkill.followUp.title == "Prepare follow-up" && (try TranscriptHandoffSkills.followUpSnapshot()).reference == TranscriptHandoffSkills.followUpReference,
                  "the follow-up skill keeps the reference earlier handoffs recorded")
        for builtIn in builtIns {
            let snapshot = try builtIn.load()
            try TranscriptHandoffSkillCheck.validate(snapshot); passed += 1
            let text = String(decoding: snapshot.files[TranscriptHandoffStore.skillEntryPoint] ?? Data(), as: UTF8.self)
            if builtIn.id != TranscriptHandoffSkills.followUpReference.id {
                try check(text.contains("not wrapped in a code block") && (text.contains("never instructions") || text.contains("do not carry out")),
                          "\(builtIn.title) asks for a plain Markdown reply and keeps quoted material from acting as instructions")
            }
            let job = try store.prepare(sources: sources, task: builtIn.defaultTask!, skill: snapshot)
            let record = try HandoffJobStore.read(HandoffSnapshotRecord.self, at: store.folder(job).appendingPathComponent("selection.json"))
            try check(record.skill.id == builtIn.id && job.supportsConnectedText
                      && HandoffJobStore.prompt(snapshot: record, skill: text, folder: store.folder(job), manual: false).contains(text),
                      "\(builtIn.title) prepares a job that can start as a connected task with the skill in its prompt")
        }
        try check(try TranscriptHandoffSkills.builtInText("workbench-meeting-follow-up").contains("`Owner?`")
                  && (try TranscriptHandoffSkills.builtInText("workbench-conversation-coach")).contains("`You:`"),
                  "meeting actions flag missing owners and coaching needs labelled speakers")
        // Any skill file may declare the same metadata; without it a skill keeps
        // the file-producing handoff and suggests no task.
        func skillFile(_ frontmatter: String) -> ReadbackSkillPackSnapshot {
            ReadbackSkillPackSnapshot(reference: .init(id: "example-skill", version: "1.0.0", name: "Example"),
                                      files: [TranscriptHandoffStore.skillEntryPoint: Data(("---\n" + frontmatter + "---\n\n# Example\nReply briefly.\n").utf8)])
        }
        let plain = skillFile("name: example\ndescription: Example skill.\n")
        try check(SkillMetadata(snapshot: plain) == SkillMetadata(description: "Example skill.")
                  && !TranscriptHandoffSkill.installed(plain, detail: "pack").repliesInline,
                  "a skill without Workbench metadata keeps the manual file-producing handoff")
        try check(!(try store.prepare(sources: sources, task: "Summarise.", skill: plain)).supportsConnectedText,
                  "a file-producing skill never starts as a connected task")
        let declared = skillFile("name: example\nmetadata:\n  author: someone\n  workbench-reply: \"inline\"\n  workbench-task: 'Say \"hi\": it''s short'\nlicense: MIT\n")
        let pack = TranscriptHandoffSkill.installed(declared, detail: "pack")
        try check(pack.repliesInline && pack.defaultTask == "Say \"hi\": it's short",
                  "a pack skill's metadata makes it reply inline with its task; quotes and unknown keys are handled")
        try check(SkillMetadata(skill: "# No frontmatter\nworkbench-reply: inline\n") == SkillMetadata()
                  && SkillMetadata(skill: "---\nworkbench-reply: inline\n---\n") == SkillMetadata(),
                  "Workbench keys count only inside the frontmatter's metadata map")

        // History: Hand off names the task it actually used, and each task lists
        // what it was made from, read off the main thread from its own folder.
        // Its own switches and pasteboard keep the person's preferences and
        // clipboard out of it.
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let doors = HandoffJobsModel(directory: root.appendingPathComponent("history-door"),
                                     switches: ({ _ in false }, { _, _ in }), pasteboard: pasteboard)
        let madeFrom = try doors.prepare(sources: sources, task: "Summarize the decision.", skill: skill)
        let newer = try doors.prepare(sources: sources, task: "A newer, different request.", skill: skill)
        try check(doors.jobs.first?.id == newer.id && newer.id != madeFrom.id, "a different request is a newer task at the top")
        var reported: [UUID] = []
        try doors.handOff(sources: sources, task: "Summarize the decision.", skill: skill, provider: nil) { reported.append($0) }
        try check(reported == [madeFrom.id] && doors.jobs.count == 2,
                  "Hand off with identical inputs reports the earlier task it reused, not the newest one")
        try check(pasteboard.string(forType: .string)?.contains("Task: Summarize the decision.") == true && doors.error == nil,
                  "Copy instructions copies that task's instructions to the pasteboard it was given")
        try doors.handOff(sources: sources, task: "A third request.", skill: skill, provider: nil) { reported.append($0) }
        try check(reported.count == 2 && reported[1] == doors.jobs.first?.id && !Set([madeFrom.id, newer.id]).contains(reported[1]),
                  "a changed request reports the new task it prepared")
        try doors.handOff(sources: sources, task: "Summarize the decision.", skill: skill, provider: .codex) { reported.append($0) }
        try check(reported.count == 2 && doors.error != nil, "a task that could not start reports nothing to reveal")
        doors.error = nil

        // Connected tasks, through a scripted runner so no provider process ever
        // starts, as the surface gallery already does: the connection switch, a
        // run that completes, one that fails and is retried, an empty reply, a
        // run stopped by the person and by quitting, and the receipts each leaves.
        final class Switches { var on: Set<SubscriptionProvider> = [] }
        final class Script { var runs = 0; var prompts: [String] = []; var images: [[URL]] = []; var folders: [URL] = [] }
        let switches = Switches(), script = Script()
        let live = HandoffJobsModel(directory: root.appendingPathComponent("live"),
                                         switches: ({ switches.on.contains($0) }, { if $1 { _ = switches.on.insert($0) } else { _ = switches.on.remove($0) } }),
                                         pasteboard: pasteboard)
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var stateChanges = 0
        live.clock = { now }
        live.onStateChange = { stateChanges += 1 }
        func scripted(_ reply: @escaping @Sendable () async throws -> SubscriptionCLIResult) -> HandoffRunner {
            HandoffRunner(discover: { provider in
                SubscriptionConnection(provider: provider, executable: URL(fileURLWithPath: "/usr/bin/false"), version: "scripted",
                                       ready: provider == .claude, detail: provider == .claude ? "Scripted connection; nothing is sent." : "Not installed.")
            }, run: { _, prompt, images, folder, onSession in
                script.runs += 1; script.prompts.append(prompt); script.images.append(images); script.folders.append(folder)
                onSession("scripted-session-\(script.runs)")
                // A real provider announces its session well before it finishes; give the receipt that order.
                try await Task.sleep(nanoseconds: 50_000_000)
                return try await reply()
            })
        }
        func settle(_ what: String, until done: () -> Bool) async throws {
            for _ in 0..<500 where !done() { try await Task.sleep(nanoseconds: 20_000_000) }
            guard done() else { throw VoiceError.message("HANDOFF_JOBS_CHECK_FAILED: did not settle: " + what) }
        }
        func job(_ id: UUID) throws -> HandoffJob {
            try live.jobs.first(where: { $0.id == id }) ?? { throw VoiceError.message("HANDOFF_JOBS_CHECK_FAILED: task \(id) is missing") }()
        }
        live.runner = scripted { SubscriptionCLIResult(providerSessionID: "scripted-final", text: "# Decision\n\nA scripted result.") }
        try check(live.connections.isEmpty, "nothing is discovered before a provider is switched on")
        live.setEnabled(.claude, true)
        try await settle("the scripted connection") { live.connections[.claude]?.ready == true }
        try check(live.enabled(.claude) && live.connections[.codex] == nil, "switching a provider on discovers that provider only")
        let completes = try live.prepare(sources: sources, task: "Summarize the decision.", skill: skill)
        try check(!live.canRun(completes, with: .claude), "a task cannot run before its folder has been read")
        await live.loadTaskFiles([completes])
        try check(live.canRun(completes, with: .claude) && !live.canRun(completes, with: .codex),
                  "a read task fits the live provider, and only a live one")
        live.start(completes, provider: .claude)
        let started = try job(completes.id)
        try check(live.isBusy && live.activeID == completes.id && stateChanges == 1
                  && started.status == .running && started.attempts == 1 && started.provider == .claude && started.attemptStartedAt == now
                  && started.detail.hasPrefix("Starting " + SubscriptionProvider.claude.title),
                  "starting marks the task running with its provider and clock, and tells the host once")
        try await settle("the scripted run") { !live.isBusy }
        let completed = try job(completes.id)
        try check(completed.status == .completed && completed.providerSessionID == "scripted-final" && stateChanges == 2
                  && completed.detail == "Result saved. Review it before using or sending it.",
                  "a completed run saves the provider's final session on the receipt and tells the host again")
        try check(script.runs == 1 && script.folders == [live.folder(completes)] && script.images[0].count == 1
                  && script.images[0][0].path.hasPrefix(live.folder(completes).path)
                  && script.prompts[0].contains("Task: Summarize the decision.") && script.prompts[0].contains("REFERENCE"),
                  "the runner receives the task folder, the frozen image inside it and the live prompt")
        try check(live.result(completed) == "# Decision\n\nA scripted result."
                  && (try HandoffJobStore.read(HandoffJob.self, at: live.folder(completes).appendingPathComponent("receipt.json"))).status == .completed,
                  "the result and the receipt are on disk")
        live.start(completed, provider: .claude)
        try check(!live.isBusy && script.runs == 1 && live.notice == "This selection already has a result, shown in History.",
                  "a completed task does not run again")
        live.notice = nil

        live.runner = scripted { throw SubscriptionCLIError.failed("The scripted provider stopped before it finished.") }
        let fails = try live.prepare(sources: sources, task: "Draft the booking note.", skill: skill)
        now = now.addingTimeInterval(60)
        live.start(fails, provider: .claude)
        try await settle("the scripted failure") { !live.isBusy }
        let failed = try job(fails.id)
        try check(failed.status == .failed && failed.attempts == 1 && failed.providerSessionID == "scripted-session-2"
                  && failed.detail == "The scripted provider stopped before it finished." && failed.updatedAt == now
                  && !FileManager.default.fileExists(atPath: live.folder(fails).appendingPathComponent("result.md").path),
                  "a failed run keeps the session the provider announced, says why, and writes no result")
        live.start(failed, provider: .claude)
        try check(!live.isBusy && live.error?.contains("before choosing Retry") == true, "a failed task needs an explicit retry")
        live.notice = nil
        live.runner = scripted { SubscriptionCLIResult(providerSessionID: nil, text: "Second attempt.") }
        now = now.addingTimeInterval(60)
        live.start(failed, provider: .claude, retry: true)
        try await settle("the retry") { !live.isBusy }
        let retried = try job(fails.id)
        try check(retried.status == .completed && retried.attempts == 2 && retried.previousAttempts.count == 1
                  && retried.previousAttempts[0].number == 1 && retried.previousAttempts[0].status == .failed
                  && retried.previousAttempts[0].providerSessionID == "scripted-session-2" && retried.providerSessionID == "scripted-session-3"
                  && live.result(retried) == "Second attempt.",
                  "a retry keeps the failed attempt in the receipt and the announced session when the reply names none")

        live.runner = scripted { SubscriptionCLIResult(providerSessionID: nil, text: " \n") }
        let empty = try live.prepare(sources: sources, task: "Prepare another draft.", skill: skill)
        live.start(empty, provider: .claude)
        try await settle("the empty reply") { !live.isBusy }
        try check(try job(empty.id).status == .failed && (try job(empty.id)).detail == "The provider returned no usable result.",
                  "an empty reply is a failure, not a result")

        live.runner = scripted { try await Task.sleep(nanoseconds: 3_600 * 1_000_000_000); return SubscriptionCLIResult(providerSessionID: nil, text: "Never.") }
        let stopped = try live.prepare(sources: sources, task: "Plan the walkthrough.", skill: skill)
        live.start(stopped, provider: .claude)
        try await settle("the long run's session") { (try? job(stopped.id))?.providerSessionID != nil }
        let waiting = try live.prepare(sources: sources, task: "A request made while one runs.", skill: skill)
        live.start(waiting, provider: .claude)
        try check(live.error?.hasPrefix("A handoff is already running.") == true && live.activeID == stopped.id, "one live task runs at a time")
        live.notice = nil
        live.cancel()
        try await settle("the stopped run") { !live.isBusy }
        try check(try job(stopped.id).status == .cancelled && (try job(stopped.id)).detail.hasPrefix("Stopped locally.")
                  && (try job(waiting.id)).status == .ready,
                  "stopping a run marks it cancelled and leaves the waiting task ready")
        live.start(waiting, provider: .claude)
        try await settle("the quitting run's session") { (try? job(waiting.id))?.providerSessionID != nil }
        await live.prepareForShutdown()
        try check(!live.isBusy && (try job(waiting.id)).status == .cancelled, "quitting waits for the running task to stop and records that")
        live.setEnabled(.claude, false)
        try check(live.connections[.claude] == nil && !live.enabled(.claude), "switching a provider off forgets its connection")
        let unconnected = try live.prepare(sources: sources, task: "A request with no connection.", skill: skill)
        live.start(unconnected, provider: .claude)
        try check(!live.isBusy && live.error?.hasPrefix(SubscriptionProvider.claude.title + " is off.") == true,
                  "a task cannot start without a connection")
        live.error = nil
        let reopenedConnected = HandoffJobsModel(directory: live.directory, switches: ({ _ in false }, { _, _ in }), pasteboard: pasteboard)
        let statuses = Dictionary(uniqueKeysWithValues: reopenedConnected.jobs.map { ($0.id, $0.status) })
        try check(reopenedConnected.error == nil && !reopenedConnected.isBusy
                  && statuses == [completes.id: .completed, fails.id: .completed, empty.id: .failed, stopped.id: .cancelled, waiting.id: .cancelled, unconnected.id: .ready],
                  "every receipt survives a relaunch with the status its run ended in")

        // A meeting's follow-up door end to end (#377), through the review's own owner with a
        // scripted runner and the door's own skill and request. Copy instructions leaves a follow-up
        // only prepared, whose Home door stays Prepare follow-up…; reopening it and choosing Start task
        // runs that same task and its result reaches the tile. A failed task runs again from a new
        // review. A stopped or interrupted one may have completed, so the review finds it before the
        // press, Start task sends nothing, and only History's Retry… sends it again.
        final class ReplyMode: @unchecked Sendable { var value = "result" }
        let mode = ReplyMode()
        let doorReply: @Sendable () async throws -> SubscriptionCLIResult = {
            switch mode.value {
            case "fail": throw SubscriptionCLIError.failed("The scripted provider stopped before it finished.")
            case "hold": try await Task.sleep(nanoseconds: 3_600 * 1_000_000_000); return SubscriptionCLIResult(providerSessionID: nil, text: "Never.")
            default: return SubscriptionCLIResult(providerSessionID: nil, text: "# Follow-up for Alex\n\nAlex Example sends the pilot plan on Friday.")
            }
        }
        let doorSwitches = ({ (provider: SubscriptionProvider) in switches.on.contains(provider) },
                            { (provider: SubscriptionProvider, on: Bool) in if on { _ = switches.on.insert(provider) } else { _ = switches.on.remove(provider) } })
        let door = HandoffJobsModel(directory: root.appendingPathComponent("meeting-door"), switches: doorSwitches, pasteboard: pasteboard)
        door.clock = { now }
        door.runner = scripted(doorReply)
        door.setEnabled(.claude, true)
        try await settle("the meeting door's connection") { door.connections[.claude]?.ready == true }
        let meetingSkill = try (TranscriptHandoffSkill.builtIns.first { $0.id == MeetingFollowUp.skillID }
            ?? { throw VoiceError.message("HANDOFF_JOBS_CHECK_FAILED: the meeting skill is missing") }()).load()
        let doorTask = HomeMeetings.doorTask ?? meetingTask
        var meeting = [sources[0]]; meeting[0].role = .reference
        func doorFollowUp() async -> (job: HandoffJob, inputs: HandoffJobInputs?)? {
            await door.loadTaskFiles(door.visibleJobs)
            return HomeMeetings.followUp(for: id, in: door.visibleJobs, inputs: { door.files($0)?.inputs.items.map(\.reference) ?? [] },
                                         excluding: { door.isMetadataSuggestion($0) }).map { ($0, door.files($0)?.inputs) }
        }
        var revealed: [UUID] = []
        try door.handOff(sources: meeting, task: doorTask, skill: meetingSkill, provider: nil) { revealed.append($0) }
        let copied = await doorFollowUp()
        try check(copied != nil && revealed == [copied!.job.id] && copied?.job.status == .ready && copied?.job.attempts == 0
                  && door.savedTask(sources: meeting, task: doorTask, skill: meetingSkill)?.id == copied?.job.id
                  && !HomeMeetings.opensFollowUp(copied?.job, inputs: copied?.inputs, meeting: id)
                  && HomeMeetings.followUpState(copied!.job.status) == "Follow-up prepared, no result yet",
                  "a follow-up copied from the meeting's door keeps Prepare follow-up… on Home, which the review finds before anything is prepared")
        try check(try HandoffJobStore.identity(sources: meeting, task: doorTask, skill: meetingSkill, review: nil).fingerprint == copied?.job.fingerprint,
                  "the review's lookup uses the same identity as the task it prepared")
        let runsBefore = script.runs
        try door.handOff(sources: meeting, task: doorTask, skill: meetingSkill, provider: .claude) { revealed.append($0) }
        try check(revealed == [copied!.job.id, copied!.job.id] && door.activeID == copied!.job.id && door.error == nil,
                  "reopening the meeting's review and choosing Start task runs the same prepared task")
        try await settle("the copied follow-up's run") { !door.isBusy }
        let returned = await doorFollowUp()
        try check(returned?.job.id == copied!.job.id && returned?.job.status == .completed && script.runs == runsBefore + 1
                  && HomeMeetings.opensFollowUp(returned?.job, inputs: returned?.inputs, meeting: id)
                  && returned.flatMap { door.files($0.job)?.resultText }.map { HomeMeetings.recap($0) } == "Follow-up for Alex · Alex Example sends the pilot plan on Friday.",
                  "its result returns to the tile as the recap, and the door becomes Open follow-up")

        // A failed task: the runner said it failed, so Start task in a new review runs it again.
        mode.value = "fail"
        var failedRun: [UUID] = []
        try door.handOff(sources: meeting, task: "Draft the thank-you note.", skill: meetingSkill, provider: .claude) { failedRun.append($0) }
        try await settle("the failed run") { !door.isBusy }
        mode.value = "result"
        var rerun: [UUID] = []
        try door.handOff(sources: meeting, task: "Draft the thank-you note.", skill: meetingSkill, provider: .claude) { rerun.append($0) }
        try check(failedRun.count == 1 && rerun == failedRun && door.activeID == failedRun[0] && door.error == nil
                  && door.notice == HandoffJobsModel.startedAgain && HandoffJobsModel.mayHaveCompleted(.failed) == nil,
                  "Start task in a new review of a failed selection runs its task again and says so")
        try await settle("the failed task's second attempt") { !door.isBusy }
        let second = door.jobs.first { $0.id == failedRun[0] }
        try check(second?.status == .completed && second?.attempts == 2 && second?.previousAttempts.map(\.status) == [.failed]
                  && second.flatMap { door.result($0) } == "# Follow-up for Alex\n\nAlex Example sends the pilot plan on Friday.",
                  "the failed attempt stays under Previous attempts beside the new result")

        // A stopped task may have been processed: the review says so before the press, and Start task sends nothing.
        mode.value = "hold"
        var stoppedRun: [UUID] = []
        try door.handOff(sources: meeting, task: "List the open questions.", skill: meetingSkill, provider: .claude) { stoppedRun.append($0) }
        try await settle("the held run's session") { door.jobs.first { stoppedRun.contains($0.id) }?.providerSessionID != nil }
        door.cancel()
        try await settle("the stopped run") { !door.isBusy }
        mode.value = "result"
        let stoppedTask = door.savedTask(sources: meeting, task: "List the open questions.", skill: meetingSkill)
        let stoppedReadiness = HandoffRunReadiness.evaluate(provider: .claude, enabled: true, checking: false, connection: door.connections[.claude],
            busy: false, compatible: true, inputProblem: nil, mayHaveCompleted: stoppedTask.flatMap { HandoffJobsModel.mayHaveCompleted($0.status) })
        try check(stoppedTask?.id == stoppedRun.first && stoppedTask?.status == .cancelled && !stoppedReadiness.canStart
                  && stoppedReadiness.detail.contains("may have been processed") && stoppedReadiness.detail.contains("History"),
                  "before the press, the review finds the stopped task and says beside Start task that it may have been processed")
        let runsAtStop = script.runs
        var resent: [UUID] = []
        try door.handOff(sources: meeting, task: "List the open questions.", skill: meetingSkill, provider: .claude) { resent.append($0) }
        try check(resent.isEmpty && script.runs == runsAtStop && !door.isBusy && door.error == HandoffJobsModel.mayHaveCompleted(.cancelled)
                  && door.jobs.first { $0.id == stoppedRun.first }?.status == .cancelled,
                  "Start task never sends a stopped task again; it names History, where Retry… is")
        // The same item with new content, as a Snap or transcript edited while the review is open, is
        // not the stopped task: the review's key changes with the replaced selection, the lookup finds
        // nothing, and Start task runs a fresh task (#377).
        var editedMeeting = meeting; editedMeeting[0].text += " A later edit."
        let keyBefore = HandoffReviewView.SavedTaskKey.make(task: "List the open questions.", skill: meetingSkill.reference.id, sources: meeting,
                                                         roles: [:], review: nil, previousReview: true, selection: 1, jobs: door.jobs)
        let replacedKey = HandoffReviewView.SavedTaskKey.make(task: "List the open questions.", skill: meetingSkill.reference.id, sources: editedMeeting,
                                                              roles: [:], review: nil, previousReview: true, selection: 2, jobs: door.jobs)
        let unchangedKey = HandoffReviewView.SavedTaskKey.make(task: "List the open questions.", skill: meetingSkill.reference.id, sources: meeting,
                                                               roles: [:], review: nil, previousReview: true, selection: 1, jobs: door.jobs)
        let editedTask = door.savedTask(sources: editedMeeting, task: "List the open questions.", skill: meetingSkill)
        var fresh: [UUID] = []
        try door.handOff(sources: editedMeeting, task: "List the open questions.", skill: meetingSkill, provider: .claude) { fresh.append($0) }
        try check(editedMeeting[0].reference == meeting[0].reference && keyBefore != replacedKey && keyBefore == unchangedKey && editedTask == nil
                  && fresh.count == 1 && fresh.first != stoppedRun.first && door.error == nil,
                  "the same item with new content is not the stopped task: the key changes, the lookup finds none and Start task runs a fresh task")
        try await settle("the edited selection's run") { !door.isBusy }
        // A stopped task whose folder no longer verifies would not be reused by Start task, so it no longer holds Start task.
        let stoppedFolder = door.directory.appendingPathComponent(stoppedRun[0].uuidString)
        try HandoffJobStore.write(Data("Changed outside Workbench.".utf8), to: stoppedFolder.appendingPathComponent("SKILL.md"))
        let damaged = door.savedTask(sources: meeting, task: "List the open questions.", skill: meetingSkill)
        var replacement: [UUID] = []
        try door.handOff(sources: meeting, task: "List the open questions.", skill: meetingSkill, provider: .claude) { replacement.append($0) }
        try check(damaged == nil && replacement.count == 1 && replacement.first != stoppedRun.first && door.error == nil,
                  "a stopped task whose saved folder fails verification no longer holds Start task; a fresh task runs instead")
        try await settle("the replacement run") { !door.isBusy }

        // An interrupted run, as a relaunch finds one: Workbench quit while it was running.
        var unsure = try door.prepare(sources: meeting, task: "Name the decisions.", skill: meetingSkill)
        unsure.status = .running; unsure.attempts = 1; unsure.provider = .claude; unsure.providerSessionID = "scripted-unsure"
        try HandoffJobStore.write(HandoffJobStore.encode(unsure), to: door.folder(unsure).appendingPathComponent("receipt.json"))
        let relaunchedDoor = HandoffJobsModel(directory: door.directory, switches: doorSwitches, pasteboard: pasteboard)
        relaunchedDoor.clock = { now }
        relaunchedDoor.runner = scripted(doorReply)
        await relaunchedDoor.refresh()
        let interrupted = relaunchedDoor.savedTask(sources: meeting, task: "Name the decisions.", skill: meetingSkill)
        let runsAtRelaunch = script.runs
        var resumed: [UUID] = []
        try relaunchedDoor.handOff(sources: meeting, task: "Name the decisions.", skill: meetingSkill, provider: .claude) { resumed.append($0) }
        try check(interrupted?.status == .interrupted && HandoffJobsModel.mayHaveCompleted(.interrupted)?.contains("may have completed") == true
                  && resumed.isEmpty && script.runs == runsAtRelaunch && !relaunchedDoor.isBusy
                  && relaunchedDoor.error == HandoffJobsModel.mayHaveCompleted(.interrupted),
                  "Start task never sends an interrupted task again; the review says it may have completed")
        try check(relaunchedDoor.start(interrupted!, provider: .claude, retry: true) && relaunchedDoor.activeID == unsure.id,
                  "History's explicit Retry… still runs the interrupted task")
        try await settle("the interrupted task's retry") { !relaunchedDoor.isBusy }
        let doorRetried = relaunchedDoor.jobs.first { $0.id == unsure.id }
        try check(doorRetried?.status == .completed && doorRetried?.previousAttempts.map(\.status) == [.interrupted]
                  && doorRetried?.previousAttempts.first?.providerSessionID == "scripted-unsure",
                  "the interrupted attempt keeps its provider receipt under Previous attempts")
        door.setEnabled(.claude, false)

        try check(doors.files(madeFrom) == nil, "nothing is read from a task folder on the main thread before it is asked for")
        await doors.loadTaskFiles(doors.jobs)
        let inputs = try doors.files(madeFrom).map(\.inputs) ?? { throw VoiceError.message("HANDOFF_JOBS_CHECK_FAILED: task files not loaded") }()
        try check(inputs.problem == nil && inputs.task == "Summarize the decision." && inputs.items.map(\.reference) == sources.map(\.reference)
                  && inputs.items.map(\.title) == ["Synthetic meeting", "Synthetic Snap"] && inputs.items[0].originalText == "um " + phrase,
                  "a task lists its frozen inputs and request from its own selection.json")
        try check(doors.files(madeFrom)?.imageBytes == [image.count] && doors.files(madeFrom)?.imageURLs.count == 1
                  && doors.files(madeFrom)?.resultReadable == false,
                  "a task's image sizes and missing result are known without reading them again")
        let loaded = doors.taskFiles
        await doors.loadTaskFiles(doors.jobs)
        try check(doors.taskFiles == loaded, "unchanged task folders are not read again")
        let frozenImage = inputs.items[1].images[0]
        try check(try doors.inputImageURL(madeFrom, path: frozenImage).map { try Data(contentsOf: $0) } == image,
                  "a frozen input image opens from the task's own folder")
        try check(doors.inputImageURL(madeFrom, path: "../" + frozenImage) == nil && doors.inputImageURL(madeFrom, path: "selection.json") == nil
                  && doors.inputImageURL(madeFrom, path: "inputs/not-recorded.png") == nil,
                  "only safe image paths the task recorded are opened")
        let selectionURL = doors.folder(madeFrom).appendingPathComponent("selection.json")
        let frozenSelection = try Data(contentsOf: selectionURL)
        func reloaded() async -> HandoffJobInputs? { await doors.loadTaskFiles([madeFrom]); return doors.files(madeFrom)?.inputs }
        try HandoffJobStore.write(Data("{broken".utf8), to: selectionURL)
        let damagedRecord = await reloaded()
        try check(damagedRecord == HandoffJobInputs(problem: HandoffJobInputs.damaged),
                  "a damaged selection.json is reported instead of guessed at, once it changes on disk")
        try check(try Data(contentsOf: selectionURL) == Data("{broken".utf8), "reading a damaged selection never rewrites it")
        try FileManager.default.removeItem(at: selectionURL)
        let missingRecord = await reloaded()
        try check(missingRecord == HandoffJobInputs(problem: HandoffJobInputs.missing), "a missing selection.json is reported as missing")
        try HandoffJobStore.write(try Data(contentsOf: doors.folder(newer).appendingPathComponent("selection.json")), to: selectionURL)
        let foreignRecord = await reloaded()
        try check(foreignRecord == HandoffJobInputs(problem: HandoffJobInputs.foreign), "another task's selection is not shown as this task's inputs")
        try HandoffJobStore.write(frozenSelection, to: selectionURL)
        let restoredRecord = await reloaded()
        try check(restoredRecord == inputs, "the restored selection lists the same inputs again")

        // A task folder, or the whole Handoffs folder, replaced by a symbolic
        // link to a copy elsewhere is not followed, even though the copy is valid.
        let fm = FileManager.default
        let newerFolder = doors.folder(newer), aside = root.appendingPathComponent("aside-" + newer.id.uuidString)
        try HandoffJobStore.write(Data("Result kept aside.".utf8), to: newerFolder.appendingPathComponent("result.md"))
        await doors.loadTaskFiles([newer])
        try check(doors.files(newer)?.resultReadable == true && doors.result(newer) == "Result kept aside.", "a saved result is offered")
        try fm.moveItem(at: newerFolder, to: aside)
        try fm.createSymbolicLink(at: newerFolder, withDestinationURL: aside)
        await doors.loadTaskFiles([newer])
        try check(doors.files(newer) == HandoffTaskFiles(inputs: .init(problem: HandoffJobInputs.replaced), imageBytes: nil, imageURLs: [:], resultReadable: false),
                  "a task folder replaced by a symbolic link is reported, and nothing in it is read")
        try check(doors.inputImageURL(newer, path: frozenImage) == nil && doors.result(newer) == nil,
                  "images and results are not read through a replaced task folder")
        try rejects("a replaced task folder fails verification before anything is sent") { try HandoffJobStore.verify(newer, root: newerFolder) }
        let clipboard = pasteboard.changeCount
        doors.copy(newer)
        try check(doors.error != nil && pasteboard.changeCount == clipboard, "Copy instructions refuses a replaced task folder and copies nothing")
        doors.showResult(newer)
        try check(doors.error?.hasPrefix("This task’s result can’t be opened") == true, "Open result says why it cannot open a replaced folder's result")
        doors.error = nil
        try fm.removeItem(at: newerFolder)
        try fm.moveItem(at: aside, to: newerFolder)
        let handoffs = doors.directory, handoffsAside = root.appendingPathComponent("history-door-aside")
        try fm.moveItem(at: handoffs, to: handoffsAside)
        try fm.createSymbolicLink(at: handoffs, withDestinationURL: handoffsAside)
        await doors.loadTaskFiles(doors.jobs)
        try check(doors.jobs.allSatisfy { doors.files($0)?.inputs.problem == HandoffJobInputs.replaced } && doors.inputImageURL(madeFrom, path: frozenImage) == nil,
                  "a Handoffs folder replaced by a symbolic link is not followed")
        try fm.removeItem(at: handoffs)
        try fm.moveItem(at: handoffsAside, to: handoffs)
        await doors.loadTaskFiles(doors.jobs)
        try check(doors.files(madeFrom)?.inputs == inputs, "the restored folders are read again")

        // A result that exists but cannot be read, or is not text, says so.
        let resultURL = doors.folder(madeFrom).appendingPathComponent("result.md")
        try HandoffJobStore.write(Data([0xFF, 0xFE, 0xFD]), to: resultURL)
        await doors.loadTaskFiles([madeFrom])
        try check(doors.files(madeFrom)?.resultReadable == false && doors.result(madeFrom) == nil, "a result that is not UTF-8 text is not shown as text")
        doors.showResult(madeFrom)
        try check(doors.error?.hasPrefix("This task’s result can’t be opened") == true, "Open result reports a result that is not text instead of doing nothing")
        doors.error = nil
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: resultURL.path)
        await doors.loadTaskFiles([madeFrom])
        try check(doors.files(madeFrom)?.resultReadable == false, "a result this Mac account cannot read is marked unreadable")
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: resultURL.path)
        try HandoffJobStore.write(Data("A synthetic result.".utf8), to: resultURL)
        let text = await doors.loadResult(madeFrom)
        try check(text == "A synthetic result.", "a saved result is read off the main thread")
        // Bring the stamp current first, so removing the image is the only change the next read sees (#150).
        await doors.loadTaskFiles([madeFrom])
        try check(doors.files(madeFrom)?.imageBytes != nil, "the frozen image is still counted before it is removed")
        try FileManager.default.removeItem(at: doors.folder(madeFrom).appendingPathComponent(frozenImage))
        await doors.loadTaskFiles([madeFrom])
        try check(doors.inputImageURL(madeFrom, path: frozenImage) == nil && doors.files(madeFrom)?.inputs.items[1].images == [frozenImage]
                  && doors.files(madeFrom)?.imageBytes == nil && doors.files(madeFrom)?.imageURLs.isEmpty == true,
                  "a missing frozen image is unavailable while its input stays listed")
        passed += try await HistoryResultReuseChecks.run(root: root.appendingPathComponent("Result reuse"))
        return ["HANDOFF_JOBS_CHECKS_OK: \(passed) checks"]
    }
}
