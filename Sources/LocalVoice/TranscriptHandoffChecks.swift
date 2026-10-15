import Foundation

/// Synthetic checks for what a handoff takes from History: selected transcripts
/// as records, a skill's structure and one Snap & Talk session as evidence.
/// Like the other scripted checks they build their own folders under the
/// temporary directory: no microphone, screen recording, saved history,
/// preferences or network is touched, and nothing is copied to the clipboard
/// or handed to another app.
enum TranscriptHandoffChecks {
    private static let deletedMarker = "RECENTLY-DELETED-SECTION-MARKER"
    private static let unreferencedMarker = "UNREFERENCED-LEFTOVER-MARKER"

    /// The Snap & Talk deck prompt exactly as it shipped, so making the handoff
    /// prompt skill-driven cannot quietly change the existing behaviour.
    private static func expectedDeckPrompt(_ url: URL) -> String {
        """
        Use the `SKILL.md` in this Workbench Snap & Talk session folder as the task instructions.

        Session folder: \(url.standardizedFileURL.path)

        Read `session.json`, use only files inside the session folder, and build the requested slide deck. Keep the original session and any `template.pptx` unchanged. Keep the work local unless I explicitly authorize an external upload or service.
        """
    }

    @MainActor
    static func runAll() throws {
        var passed = 0
        // A plain Bool, so a check can compare values read from the file system.
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw TranscriptHandoffError.message("TRANSCRIPT_HANDOFF_CHECK_FAILED: \(message)") }
            passed += 1
        }
        func rejects(_ message: String, _ work: () throws -> Void) throws {
            do { try work() }
            catch { passed += 1; return }
            throw TranscriptHandoffError.message("TRANSCRIPT_HANDOFF_CHECK_FAILED: \(message)")
        }

        let fm = FileManager.default
        let fixture = fm.temporaryDirectory.appendingPathComponent("Workbench-transcript-handoff-\(UUID().uuidString)", isDirectory: true)
        try ReadbackStore.createPrivateDirectory(fixture)
        defer { try? fm.removeItem(at: fixture) }

        func write(_ root: URL, _ relative: String, _ text: String) throws {
            try ReadbackStore.writePrivate(Data(text.utf8), to: root.appendingPathComponent(relative))
        }
        func files(in root: URL) throws -> [String: Data] {
            var found: [String: Data] = [:]
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
                throw TranscriptHandoffError.message("TRANSCRIPT_HANDOFF_CHECK_FAILED: unable to enumerate \(root.lastPathComponent)")
            }
            for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                found[String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))] = try Data(contentsOf: url)
            }
            return found
        }

        /// A synthetic Snap & Talk session: live screenshot/narration pairs, an
        /// optional Recently Deleted section and an unreferenced leftover file.
        func makeSession(_ name: String, live: Int = 2, trashed: Bool = true) throws -> (URL, ReadbackManifest) {
            let root = fixture.appendingPathComponent(name, isDirectory: true)
            try ReadbackStore.createPrivateDirectory(root)
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent("items"))
            try ReadbackStore.createPrivateDirectory(root.appendingPathComponent("trash"))
            var sections: [ReadbackSection] = []
            for index in stride(from: 1, through: live, by: 1) {
                let id = UUID(), directory = "items/\(id.uuidString.lowercased())"
                try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory))
                try write(root, directory + "/screen.png", "screenshot \(index)")
                try write(root, directory + "/narration.wav", "audio \(index)")
                try write(root, directory + "/narration-original.txt", "original narration \(index)")
                try write(root, directory + "/narration.txt", "edited narration \(index)")
                sections.append(ReadbackSection(id: id, capturedAt: Date(timeIntervalSince1970: Double(index) * 100),
                    displayName: "Display \(index)", directory: directory, screenshot: directory + "/screen.png",
                    audio: directory + "/narration.wav", originalTranscript: directory + "/narration-original.txt",
                    transcript: directory + "/narration.txt", status: .ready, failure: nil, deletedAt: nil))
            }
            if trashed {
                let id = UUID(), directory = "trash/\(id.uuidString.lowercased())"
                try ReadbackStore.createPrivateDirectory(root.appendingPathComponent(directory))
                try write(root, directory + "/screen.png", deletedMarker)
                sections.append(ReadbackSection(id: id, capturedAt: Date(timeIntervalSince1970: 900), displayName: "Deleted display",
                    directory: directory, screenshot: directory + "/screen.png", audio: nil, originalTranscript: nil,
                    transcript: nil, status: .ready, failure: nil, deletedAt: Date(timeIntervalSince1970: 950)))
            }
            // A leftover the session no longer links: recovery files never travel.
            try write(root, "items/leftover-recovered.txt", unreferencedMarker)
            let manifest = ReadbackManifest(id: UUID(), title: name, createdAt: Date(timeIntervalSince1970: 10),
                                            updatedAt: Date(timeIntervalSince1970: 20), sections: sections)
            try ReadbackStore.save(manifest, at: root)
            try ReadbackStore.writePrivate(try JSONEncoder().encode(ReadbackSkillPackProvenance(pack: .neutral)),
                                           to: root.appendingPathComponent(ReadbackStore.skillPackReceiptName))
            return (root, manifest)
        }

        // The transcripts the person selected.
        let firstSelected = Transcript(date: Date(timeIntervalSince1970: 1_700_000_100), text: "We agreed to run the pilot next month.",
                                       seconds: 12.5, rawText: "um we agreed to run the pilot next month", cleanupMethod: "Light")
        let secondSelected = Transcript(date: Date(timeIntervalSince1970: 1_700_000_200), text: "The second selected capture has no separate original.", seconds: 4)

        // 1. The built-in neutral skill is a complete, structurally valid entry point.
        let builtIn = try TranscriptHandoffSkills.followUpSnapshot()
        try TranscriptHandoffSkillCheck.validate(builtIn)
        passed += 1
        guard let entry = builtIn.files[TranscriptHandoffStore.skillEntryPoint],
              let skillText = String(data: entry, encoding: .utf8) else {
            throw TranscriptHandoffError.message("TRANSCRIPT_HANDOFF_CHECK_FAILED: the built-in skill has no readable SKILL.md")
        }
        try check(builtIn.files.count == 1 && builtIn.reference.id == "workbench-follow-up", "the built-in follow-up skill is one self-contained entry point")
        try check(skillText.contains("handoff.json") && skillText.contains("original") && skillText.contains("cleaned"),
                  "the skill reads the manifest and distinguishes original from cleaned wording")
        try check(skillText.contains("transcriptRole") && skillText.contains("adopted") && skillText.contains("reference"),
                  "the skill respects the person's chosen dictation role")
        try check(skillText.contains("Do not invent") && skillText.contains("commitments"), "the skill forbids invented commitments")
        try check(skillText.contains("outputs/") && skillText.contains("unchanged"), "the skill preserves originals")
        try check(skillText.contains("direct authorization"), "the skill does not authorize external delivery")

        // 2. Only the chosen captures become records, with both wordings kept apart.
        let records = try TranscriptHandoffStore.records(for: [firstSelected, secondSelected])
        try check(records.map(\.id) == [firstSelected.id, secondSelected.id] && records.map(\.index) == [1, 2],
                  "records keep the selected transcripts in the order they were chosen")
        try check(records[0].hasSeparateOriginal && records[0].cleanedText == firstSelected.text && records[0].originalText == firstSelected.rawText,
                  "a cleaned capture keeps its original recognised wording separately")
        try check(!records[1].hasSeparateOriginal && records[1].originalText == secondSelected.text,
                  "a capture without a separate original repeats its wording instead of losing it")
        try check(records[0].capturedAt == firstSelected.date && records[0].cleanup == "Light", "records carry the original capture time and cleanup method")
        let textFiles = records.flatMap { [$0.cleanedFile, $0.originalFile] }
        try check(Set(textFiles).count == 4 && textFiles.allSatisfy { $0.hasPrefix(TranscriptHandoffStore.transcriptsDirectory + "/") },
                  "each selected transcript names its own cleaned and original text files under inputs/")
        try rejects("an empty selection is refused") { _ = try TranscriptHandoffStore.records(for: []) }
        try rejects("the same transcript cannot be selected twice") { _ = try TranscriptHandoffStore.records(for: [firstSelected, firstSelected]) }

        // 3. One session as evidence: only its live, referenced files travel.
        let (session, sessionManifest) = try makeSession("Snap and Talk session")
        let sourceBefore = try files(in: session)
        let source = try TranscriptHandoffStore.evidence(at: session)
        let evidence = source.record
        func travelling(_ relative: String?) -> String? {
            guard let relative, let file = source.files.first(where: { $0.relative == relative }) else { return nil }
            return (try? Data(contentsOf: file.source)).flatMap { String(data: $0, encoding: .utf8) }
        }
        try check(evidence.sections.count == 2 && evidence.sessionID == sessionManifest.id && evidence.sessionSkill == .neutral,
                  "the whole live session travels with its own skill provenance and no deleted sections")
        try check(source.files.count == 8 && Set(source.files.map(\.relative)).count == 8,
                  "each live section brings exactly its screenshot, audio and two narration files")
        let allText = source.files.compactMap { try? Data(contentsOf: $0.source) }.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
        try check(!allText.contains(deletedMarker), "a Recently Deleted section is never copied as evidence")
        try check(!allText.contains(unreferencedMarker), "an unreferenced leftover file in the session is never copied")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let recorded = String(decoding: try encoder.encode(evidence), as: UTF8.self)
        try check(evidence.sourceFolderName == session.lastPathComponent && !recorded.contains(session.path) && !recorded.contains(fixture.path),
                  "only the session's folder name is recorded, never where it lives")
        for (offset, section) in evidence.sections.enumerated() {
            let index = offset + 1
            try check(travelling(section.screenshot) == "screenshot \(index)" && travelling(section.audio) == "audio \(index)",
                      "section \(index) keeps its screenshot beside its own narration audio")
            try check(travelling(section.originalTranscript) == "original narration \(index)" && travelling(section.editedTranscript) == "edited narration \(index)",
                      "section \(index) keeps both narration versions of the same screenshot")
            try check(section.screenshot.hasPrefix(TranscriptHandoffStore.evidenceDirectory + "/") && section.index == index,
                      "section \(index) is stored under inputs/ with a stable order")
        }
        try check(files(in: session) == sourceBefore, "reading evidence never modifies or moves the source session")

        // 3a. The manifest History's Hand off writes round-trips its records and evidence.
        let manifest = TranscriptHandoffManifest(id: UUID(), title: "Synthetic follow-up", createdAt: Date(timeIntervalSince1970: 1_700_000_500),
                                                 skill: builtIn.reference, skillFiles: builtIn.files.keys.sorted(),
                                                 transcripts: records, evidence: evidence)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TranscriptHandoffManifest.self, from: try encoder.encode(manifest))
        try check(decoded == manifest && decoded.formatVersion == TranscriptHandoffManifest.currentFormat
                    && decoded.skillEntryPoint == TranscriptHandoffStore.skillEntryPoint,
                  "handoff.json round-trips the selected transcripts, evidence, skill and identity")

        // 3b. The Hand off review turns the session into one reference item per live screenshot.
        let items = try HandoffSessionEvidence.snapshots(at: session)
        try check(items.count == 2 && items.allSatisfy { $0.role == .reference }
                    && items.map(\.images) == [[Data("screenshot 1".utf8)], [Data("screenshot 2".utf8)]]
                    && items.map(\.text) == ["edited narration 1", "edited narration 2"]
                    && items.map(\.originalText) == ["original narration 1", "original narration 2"],
                  "each live screenshot reaches the review with its own saved words")

        // 4. Snap & Talk keeps its deck prompt for every assistant.
        for target in ReadbackHandoffTarget.allCases {
            try check(target.prompt(for: session) == expectedDeckPrompt(session), "\(target.title) Snap & Talk handoff still points at session.json and the deck skill")
        }

        // 5. A skill that cannot be a handoff's entry point is refused.
        let synthetic = ReadbackSkillPackReference(id: "synthetic-skill", version: "1.0.0", name: "Synthetic skill")
        let entryData = Data("---\nname: synthetic\n---\n\n# Synthetic\n".utf8)
        func rejectsSkill(_ message: String, _ reference: ReadbackSkillPackReference, _ payload: [String: Data]) throws {
            try rejects(message) { try TranscriptHandoffSkillCheck.validate(ReadbackSkillPackSnapshot(reference: reference, files: payload)) }
        }
        try TranscriptHandoffSkillCheck.validate(ReadbackSkillPackSnapshot(reference: synthetic,
            files: [TranscriptHandoffStore.skillEntryPoint: entryData, "notes/extra.md": entryData]))
        passed += 1
        try rejectsSkill("a skill without a SKILL.md entry point", synthetic, ["notes.md": entryData])
        try rejectsSkill("a skill with an empty entry point", synthetic, [TranscriptHandoffStore.skillEntryPoint: Data()])
        try rejectsSkill("a skill with an unusable version", ReadbackSkillPackReference(id: "synthetic-skill", version: "1.0", name: "Synthetic skill"),
                         [TranscriptHandoffStore.skillEntryPoint: entryData])
        for unsafe in ["../escape.md", "/absolute.md", "nested/../escape.md", ".hidden/asset.md", "inputs/transcripts/fake.txt",
                       TranscriptHandoffStore.manifestName, "README.md", "outputs/result.md"] {
            try rejectsSkill("a skill supplying \(unsafe)", synthetic, [TranscriptHandoffStore.skillEntryPoint: entryData, unsafe: entryData])
        }
        try rejectsSkill("an incomplete bundled deck pack", .serviceNow, [TranscriptHandoffStore.skillEntryPoint: entryData])

        // 6. Malformed, aliased and incomplete evidence is refused.
        func rejectsEvidence(_ message: String, _ url: URL) throws {
            try rejects(message) { _ = try TranscriptHandoffStore.evidence(at: url) }
        }
        let notASession = fixture.appendingPathComponent("Not a session", isDirectory: true)
        try ReadbackStore.createPrivateDirectory(notASession)
        try write(notASession, "notes.txt", "Just a folder")
        try rejectsEvidence("a folder that is not a Snap & Talk session", notASession)
        try rejectsEvidence("a session folder that does not exist", fixture.appendingPathComponent("Absent session", isDirectory: true))
        let aliasedSession = fixture.appendingPathComponent("Aliased session")
        try fm.createSymbolicLink(at: aliasedSession, withDestinationURL: session)
        try rejectsEvidence("a session folder that is a symbolic link", aliasedSession)
        try fm.removeItem(at: aliasedSession)

        let (aliasedMedia, aliasedManifest) = try makeSession("Session with an aliased screenshot")
        let aliasedScreenshot = aliasedMedia.appendingPathComponent(aliasedManifest.sections[0].screenshot)
        try fm.removeItem(at: aliasedScreenshot)
        try fm.createSymbolicLink(at: aliasedScreenshot, withDestinationURL: aliasedMedia.appendingPathComponent(aliasedManifest.sections[1].screenshot))
        try rejectsEvidence("a section screenshot that aliases another section", aliasedMedia)

        let (incomplete, incompleteManifest) = try makeSession("Session missing a screenshot")
        try fm.removeItem(at: incomplete.appendingPathComponent(incompleteManifest.sections[0].screenshot))
        try rejectsEvidence("a session whose screenshot file is missing", incomplete)

        let (emptied, _) = try makeSession("Session with only deleted sections", live: 0, trashed: true)
        do {
            _ = try TranscriptHandoffStore.evidence(at: emptied)
            throw TranscriptHandoffError.message("TRANSCRIPT_HANDOFF_CHECK_FAILED: deleted-only sessions must be refused")
        } catch {
            try check(error.localizedDescription.contains("Recently Deleted"), "the deleted-only refusal explains that deleted items are never copied")
        }

        // 6a. Choose a session… hands the folder straight to the review, so a
        // folder that is not a session has to explain itself there.
        do {
            _ = try HandoffSessionEvidence.snapshots(at: notASession)
            throw TranscriptHandoffError.message("TRANSCRIPT_HANDOFF_CHECK_FAILED: a folder that is not a session must be refused")
        } catch {
            try check(error.localizedDescription.contains("not a readable Snap & Talk session"),
                      "the review can say why a chosen folder is not a session")
        }
        try check(files(in: session) == sourceBefore, "every refused handoff leaves the chosen session untouched")
        try check(files(in: notASession) == ["notes.txt": Data("Just a folder".utf8)], "a refused folder is left as it was")
        print("TRANSCRIPT_HANDOFF_CHECKS_OK: \(passed) checks")
    }
}
