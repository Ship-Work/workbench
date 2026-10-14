import AppIntents
import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A recording someone chose, from Import audio or a shortcut. A file macOS can't open says so with
/// the next step, never Core Audio's error number, which has no words of its own (#337).
enum ImportedAudio {
    static let unreadable = "Workbench can’t read this file as audio. It may be incomplete or in a format macOS can’t open, such as WMA. Try an M4A, MP3 or WAV recording."
    static func open(_ url: URL) throws -> AVAudioFile {
        do { return try AVAudioFile(forReading: url) }
        catch { throw VoiceError.message(unreadable) }
    }
}

/// IntentFile may supply only Data. Give that private copy its actual audio extension;
/// providers and decoders must never receive the old generic `input.audio` name.
enum ShortcutAudioFile {
    static let maximumBytes = 64 * 1024 * 1024
    private static let extensions: [String: String] = [
        "wav": "wav", "wave": "wav", "m4a": "m4a", "mp3": "mp3", "flac": "flac",
        "aif": "aiff", "aiff": "aiff", "aifc": "aifc", "caf": "caf", "aac": "aac"
    ]

    static func fileExtension(filename: String, type: UTType?) throws -> String {
        // Prefer the declared audio type. A generic public.audio/data type has no
        // useful extension, so fall back to a known extension on the supplied name.
        // macOS can report "mp4" as public.mpeg-4-audio's preferred extension.
        // Our recording/server contract uses its audio-specific M4A spelling.
        if let type, type.conforms(to: .mpeg4Audio) { return "m4a" }
        if let type, type.conforms(to: .audio), let ext = type.preferredFilenameExtension?.lowercased(),
           let canonical = extensions[ext] { return canonical }
        if let type, type != .data, type != .item, !type.conforms(to: .audio) {
            throw VoiceError.message("Shortcuts did not identify this input as audio. Pass a recording or an audio file to Workbench.")
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let canonical = extensions[ext] else {
            throw VoiceError.message("Shortcuts did not identify the audio format. Pass a named WAV, M4A, MP3 or FLAC file, or preserve the recording’s audio type.")
        }
        return canonical
    }

    static func stage(_ audio: IntentFile, in directory: URL) throws -> URL {
        let data = audio.data
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw VoiceError.message("Choose a non-empty audio file up to 64 MB.")
        }
        let ext = try fileExtension(filename: audio.filename, type: audio.type)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Only a fixed stem and allowlisted extension enter this path. Never append
        // the incoming filename, even if it contains path traversal or control text.
        let source = directory.appendingPathComponent("input." + ext)
        try data.write(to: source, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        return source
    }

    static func validateSize(_ source: URL) throws {
        guard source.isFileURL else { throw VoiceError.message("Pass an audio file to Workbench, not a remote URL.") }
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size <= maximumBytes else {
            throw VoiceError.message("Choose a non-empty audio file up to 64 MB.")
        }
    }
}

/// One continuation per invocation: an action can never observe a previous draft.
@MainActor
final class DictationRequest {
    private(set) var id: UUID?
    private var completion: ((Result<String, Error>) -> Void)?
    func begin(id: UUID, completion: @escaping (Result<String, Error>) -> Void) throws {
        guard self.id == nil else { throw VoiceError.message("A Workbench Shortcuts transcription is already running. Finish or cancel it first.") }
        self.id = id; self.completion = completion
    }
    func finish(id: UUID, result: Result<String, Error>) {
        guard self.id == id else { return }
        let callback = completion; self.id = nil; completion = nil
        callback?(result)
    }
    func cancel() {
        if let id { finish(id: id, result: .failure(CancellationError())) }
    }
}

/// Shortcuts owns Record Audio and its Stop button. This action never opens a microphone.
struct TranscribeWithWorkbench: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Transcribe with Workbench"
    static var description = IntentDescription("Turn Record Audio or an audio file into text with the speech model selected in Workbench. Connect the result to Create Note, Copy to Clipboard, or any text action. Configure the model in Workbench Settings first. A local server controls whether it forwards audio elsewhere.")
    static var openAppWhenRun = false
    @Parameter(title: "Audio", supportedTypeIdentifiers: ["public.audio"], inputConnectionBehavior: .connectToPreviousIntentResult)
    var audio: IntentFile
    static var parameterSummary: some ParameterSummary { Summary("Transcribe \(\.$audio)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let model = AppModel.intentModel else { throw VoiceError.message("Open Workbench and configure a speech model in Settings, then run the shortcut again.") }
        let id = UUID()
        let captureProgress = progress
        captureProgress.totalUnitCount = 1; captureProgress.isCancellable = true
        let configuration = await model.engine.configuration()
        captureProgress.localizedDescription = configuration.provider == .parakeet
            ? "Workbench · transcribing with Parakeet on this Mac"
            : "Workbench · transcribing with \(configuration.model) through your local server"
        captureProgress.cancellationHandler = { Task { @MainActor in model.cancelShortcut(id) } }
        defer { captureProgress.cancellationHandler = nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Workbench-shortcut-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source: URL
        if let url = audio.fileURL { source = url }
        else { source = try ShortcutAudioFile.stage(audio, in: temporary) }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        try ShortcutAudioFile.validateSize(source)
        let text = try await model.transcribeForShortcut(source, id: id)
        captureProgress.completedUnitCount = 1
        return .result(value: text)
    }
}

struct VoiceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TranscribeWithWorkbench(), phrases: ["Transcribe audio with \(.applicationName)"],
                    shortTitle: "Transcribe with Workbench", systemImageName: "waveform")
    }
}
