import Foundation

enum TranscriptHandoffError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

/// Bounds for one explicitly selected handoff. They exist so a malformed skill,
/// an enormous session or a runaway selection fails before anything is published.
enum TranscriptHandoffLimits {
    static let maxTranscripts = 200
    static let maxTranscriptCharacters = 2_000_000
    static let maxSkillFiles = 200
    static let maxSkillFileBytes = 16_000_000
    static let maxEvidenceFiles = 2_000
    static let maxEvidenceFileBytes = 512_000_000
    static let maxEvidenceBytes = 2_000_000_000
}

/// One selectable skill for a transcript handoff. Workbench's own skills and
/// installed pack skills are both skill files; a host supplies `load`, so this
/// view layer never learns about pack distribution.
struct TranscriptHandoffSkill: Identifiable {
    let id: String
    let title: String
    let detail: String
    let load: () throws -> ReadbackSkillPackSnapshot
    /// Reply-only skills return their document as the answer, so they can run
    /// as a connected task. Other skills may create files and use the manual
    /// handoff instead. Declared in the skill file; see `SkillMetadata`.
    var repliesInline = false
    /// What the task field suggests for this skill until the person edits it.
    var defaultTask: String? = nil

    init(id: String, title: String, detail: String, load: @escaping () throws -> ReadbackSkillPackSnapshot,
         repliesInline: Bool = false, defaultTask: String? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.load = load
        self.repliesInline = repliesInline; self.defaultTask = defaultTask
    }

    /// A resolved skill file, behaving as its own metadata declares.
    init(_ snapshot: ReadbackSkillPackSnapshot, id: String? = nil, title: String, detail: String) {
        let metadata = SkillMetadata(snapshot: snapshot)
        self.init(id: id ?? snapshot.reference.id, title: title, detail: detail, load: { snapshot },
                  repliesInline: metadata.repliesInline, defaultTask: metadata.suggestedTask)
    }

    /// The skills every handoff offers before any installed pack skills, from
    /// the pack bundled with Workbench.
    static var builtIns: [TranscriptHandoffSkill] { (try? WorkbenchSkillPack.loaded.get()) ?? [] }

    /// The general follow-up skill, also used for details and Snap reviews. A
    /// damaged installation reports the problem when the skill is used.
    static var followUp: TranscriptHandoffSkill {
        let reference = TranscriptHandoffSkills.followUpReference
        return builtIns.first { $0.id == reference.id } ?? TranscriptHandoffSkill(id: reference.id, title: reference.name,
            detail: "Reinstall Workbench to restore its built-in skills.",
            load: { _ = try WorkbenchSkillPack.loaded.get(); throw TranscriptHandoffError.message("Workbench's follow-up skill is missing. Reinstall Workbench.") })
    }

    /// Wrap an already-resolved snapshot, for example one an installed
    /// `ReadbackSkillPackStore` produced for the host.
    static func installed(_ snapshot: ReadbackSkillPackSnapshot, detail: String) -> TranscriptHandoffSkill {
        TranscriptHandoffSkill(snapshot, id: snapshot.reference.id + "@" + snapshot.reference.version,
                               title: snapshot.reference.name, detail: detail)
    }
}

enum TranscriptHandoffSkills {
    static let followUpReference = ReadbackSkillPackReference(id: "workbench-follow-up", version: "1.0.0", name: "Prepare follow-up")

    static func followUpSnapshot() throws -> ReadbackSkillPackSnapshot { try TranscriptHandoffSkill.followUp.load() }

    /// A built-in skill's SKILL.md text, by id.
    static func builtInText(_ id: String) throws -> String {
        guard let skill = TranscriptHandoffSkill.builtIns.first(where: { $0.id == id }),
              let data = try skill.load().files[TranscriptHandoffStore.skillEntryPoint] else {
            throw TranscriptHandoffError.message("Workbench has no built-in skill \(id).")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Structural validation for any skill used as a handoff entry point. Bundled
/// deck packs additionally keep their exact-payload check.
enum TranscriptHandoffSkillCheck {
    static let bundledDeckIdentifiers = [ReadbackSkillPackReference.neutral.id, ReadbackSkillPackReference.serviceNow.id]
    static let reservedPaths = ["handoff.json", "readme.md", "skill-pack.json", "session.json"]

    static func validate(_ snapshot: ReadbackSkillPackSnapshot) throws {
        try snapshot.validate()
        let reference = snapshot.reference
        guard reference.id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", options: .regularExpression) != nil,
              reference.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              !reference.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscriptHandoffError.message("The chosen skill has no usable id, version and name. No handoff folder was created.")
        }
        guard let entry = snapshot.files[TranscriptHandoffStore.skillEntryPoint], !entry.isEmpty,
              String(data: entry, encoding: .utf8) != nil else {
            throw TranscriptHandoffError.message("The chosen skill has no readable \(TranscriptHandoffStore.skillEntryPoint) entry point. No handoff folder was created.")
        }
        guard (1...TranscriptHandoffLimits.maxSkillFiles).contains(snapshot.files.count) else {
            throw TranscriptHandoffError.message("The chosen skill has an unsupported number of files. No handoff folder was created.")
        }
        for path in snapshot.files.keys.sorted() {
            guard isSafeRelativePath(path) else {
                throw TranscriptHandoffError.message("The chosen skill contains an unsafe file path (\(path)). No handoff folder was created.")
            }
            guard !reservedPaths.contains(path.lowercased()), !path.lowercased().hasPrefix("inputs/"), !path.lowercased().hasPrefix("outputs/") else {
                throw TranscriptHandoffError.message("The chosen skill cannot supply \(path); that name belongs to the handoff folder. No handoff folder was created.")
            }
            let data = snapshot.files[path]!
            guard !data.isEmpty, data.count <= TranscriptHandoffLimits.maxSkillFileBytes else {
                throw TranscriptHandoffError.message("The chosen skill file \(path) is empty or too large. No handoff folder was created.")
            }
        }
        // A bundled deck pack must still be its exact complete payload.

    }

    /// A portable relative path: no absolute root, traversal, empty or hidden
    /// component, and no Windows-style separator smuggled into one component.
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), path.count <= 512 else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 16 else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
                && !component.hasPrefix(".") && !component.contains("\\") && !component.contains(":")
                && component.count <= 96
        }
    }
}

struct TranscriptHandoffTranscript: Codable, Equatable {
    /// The saved Workbench transcript identifier, so a draft can be traced back.
    var id: UUID
    var index: Int
    var capturedAt: Date
    var seconds: Double
    var words: Int
    var cleanup: String?
    var hasSeparateOriginal: Bool
    var cleanedFile: String
    var originalFile: String
    var cleanedText: String
    var originalText: String
}

struct TranscriptHandoffEvidenceSection: Codable, Equatable {
    var id: UUID
    var index: Int
    var capturedAt: Date
    var displayName: String
    var status: String
    var screenshot: String
    var audio: String?
    var originalTranscript: String?
    var editedTranscript: String?
}

/// One explicitly selected Snap & Talk session, copied as evidence. Only the
/// live referenced files travel: Recently Deleted sections, replaced-file
/// archives and unreferenced files in the source folder stay behind.
struct TranscriptHandoffEvidence: Codable, Equatable {
    var kind = "snap-and-talk-session"
    var sessionID: UUID
    var sessionTitle: String
    /// Folder name only. A handoff never records where the source lives.
    var sourceFolderName: String
    var createdAt: Date
    var updatedAt: Date
    /// The session's own recorded skill, kept as provenance. Its skill files are
    /// not copied, so this handoff keeps one SKILL.md entry point.
    var sessionSkill: ReadbackSkillPackReference?
    var directory: String
    var sections: [TranscriptHandoffEvidenceSection]
}

enum TranscriptHandoffRole: String, Codable, CaseIterable {
    case instructions, reference
    var title: String { self == .instructions ? "My instructions" : "Reference material" }
}

struct TranscriptHandoffManifest: Codable, Equatable {
    static let currentFormat = 1
    var formatVersion = currentFormat
    var transcriptRole: TranscriptHandoffRole = .instructions
    var id: UUID
    var title: String
    var createdAt: Date
    var source = "Workbench Recent transcriptions"
    var skill: ReadbackSkillPackReference
    var skillEntryPoint = TranscriptHandoffStore.skillEntryPoint
    var skillFiles: [String]
    var outputs = TranscriptHandoffStore.outputsDirectory
    var transcripts: [TranscriptHandoffTranscript]
    var evidence: TranscriptHandoffEvidence?
}

/// The portable handoff.json layout and the transcript records that History's
/// Hand off (`HandoffJobStore`) writes into its task folder, and the reader for
/// one chosen Snap & Talk session that the review turns into evidence items.
enum TranscriptHandoffStore {
    static let manifestName = "handoff.json"
    static let skillEntryPoint = "SKILL.md"
    static let transcriptsDirectory = "inputs/transcripts"
    static let evidenceDirectory = "inputs/evidence"
    static let outputsDirectory = "outputs"

    static func records(for transcripts: [Transcript]) throws -> [TranscriptHandoffTranscript] {
        guard !transcripts.isEmpty else {
            throw TranscriptHandoffError.message("Select at least one transcript before handing off. Nothing was created.")
        }
        guard transcripts.count <= TranscriptHandoffLimits.maxTranscripts else {
            throw TranscriptHandoffError.message("Select at most \(TranscriptHandoffLimits.maxTranscripts) transcripts for one handoff. Nothing was created.")
        }
        var seen = Set<UUID>()
        return try transcripts.enumerated().map { offset, item in
            guard seen.insert(item.id).inserted else {
                throw TranscriptHandoffError.message("The same transcript was selected twice. Nothing was created.")
            }
            let cleaned = item.text
            let original = item.rawText ?? item.text
            guard cleaned.count <= TranscriptHandoffLimits.maxTranscriptCharacters,
                  original.count <= TranscriptHandoffLimits.maxTranscriptCharacters else {
                throw TranscriptHandoffError.message("One selected transcript is too large to copy into a handoff folder. Nothing was created.")
            }
            let index = offset + 1
            let stem = String(format: "%03d", index) + "-" + item.id.uuidString.lowercased()
            return TranscriptHandoffTranscript(
                id: item.id, index: index, capturedAt: item.date, seconds: item.seconds,
                words: TextRules.wordCount(cleaned), cleanup: item.cleanupMethod,
                hasSeparateOriginal: original != cleaned,
                cleanedFile: transcriptsDirectory + "/" + stem + "-cleaned.txt",
                originalFile: transcriptsDirectory + "/" + stem + "-original.txt",
                cleanedText: cleaned, originalText: original)
        }
    }

    struct EvidenceFile {
        let relative: String
        let source: URL
    }

    struct EvidenceSource {
        let record: TranscriptHandoffEvidence
        let files: [EvidenceFile]
    }

    /// Read one explicitly selected Snap & Talk session and list exactly the
    /// live files that will travel. Nothing in the source is written or moved.
    static func evidence(at url: URL) throws -> EvidenceSource {
        let fm = FileManager.default
        let root = url.standardizedFileURL
        if (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw TranscriptHandoffError.message("The selected Snap & Talk folder is a symbolic link. Choose the real session folder; nothing was created.")
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TranscriptHandoffError.message("The selected Snap & Talk session folder is not available. Nothing was created.")
        }
        let session: ReadbackManifest
        do { session = try ReadbackStore.load(from: root) }
        catch {
            throw TranscriptHandoffError.message("That folder is not a readable Snap & Talk session. \(error.localizedDescription) Choose the session folder itself.")
        }
        let active = session.sections.filter { $0.deletedAt == nil }
        guard !active.isEmpty else {
            throw TranscriptHandoffError.message("That Snap & Talk session has no current sections to include. Items in Recently Deleted are never copied. Nothing was created.")
        }
        let directory = evidenceDirectory + "/session-" + session.id.uuidString.lowercased()
        var files: [EvidenceFile] = []
        var totalBytes = 0
        var sections: [TranscriptHandoffEvidenceSection] = []
        for (offset, section) in active.enumerated() {
            func include(_ relative: String?, label: String) throws -> String? {
                guard let relative else { return nil }
                // safeURL rejects traversal and any symbolic-link component.
                let source = try ReadbackStore.safeURL(root: root, relative: relative)
                guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true, let size = values.fileSize, size > 0,
                      size <= TranscriptHandoffLimits.maxEvidenceFileBytes else {
                    throw TranscriptHandoffError.message("Section \(offset + 1) of the selected session is missing or cannot read its \(label). Nothing was created, and the session was not changed.")
                }
                totalBytes += size
                let target = directory + "/" + relative
                guard TranscriptHandoffSkillCheck.isSafeRelativePath(target) else {
                    throw TranscriptHandoffError.message("Section \(offset + 1) of the selected session uses an unsupported file path. Nothing was created.")
                }
                files.append(EvidenceFile(relative: target, source: source))
                return target
            }
            guard let screenshot = try include(section.screenshot, label: "screenshot") else {
                throw TranscriptHandoffError.message("Section \(offset + 1) of the selected session has no screenshot. Nothing was created.")
            }
            sections.append(TranscriptHandoffEvidenceSection(
                id: section.id, index: offset + 1, capturedAt: section.capturedAt,
                displayName: section.displayName, status: section.status.rawValue, screenshot: screenshot,
                audio: try include(section.audio, label: "narration audio"),
                originalTranscript: try include(section.originalTranscript, label: "original narration"),
                editedTranscript: try include(section.transcript, label: "edited narration")))
        }
        guard files.count <= TranscriptHandoffLimits.maxEvidenceFiles, totalBytes <= TranscriptHandoffLimits.maxEvidenceBytes else {
            throw TranscriptHandoffError.message("The selected session is too large to copy into a handoff folder. Nothing was created.")
        }
        let record = TranscriptHandoffEvidence(
            sessionID: session.id, sessionTitle: session.title, sourceFolderName: root.lastPathComponent,
            createdAt: session.createdAt, updatedAt: session.updatedAt, sessionSkill: session.skillPack,
            directory: directory, sections: sections)
        return EvidenceSource(record: record, files: files)
    }

    /// Relative paths inside the handoff folder stay portable and real.
    static func safeURL(root: URL, relative: String) throws -> URL {
        guard TranscriptHandoffSkillCheck.isSafeRelativePath(relative) else {
            throw TranscriptHandoffError.message("The handoff folder cannot use the path \(relative). Nothing was created.")
        }
        // The folder itself is checked as well as each step below it: a folder
        // replaced by a symbolic link would otherwise lead every path elsewhere.
        guard HandoffJobStore.isRealFolder(root) else {
            throw TranscriptHandoffError.message("The handoff folder is missing or was replaced outside Workbench. Nothing was read or created.")
        }
        var candidate = root.standardizedFileURL
        for component in relative.split(separator: "/") {
            candidate.appendPathComponent(String(component))
            if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw TranscriptHandoffError.message("The handoff folder cannot follow a symbolic link. Nothing was created.")
            }
        }
        return candidate
    }
}
