import AppKit
import SwiftUI

/// Passive access to old recordings. Never scans processes, captures, transcribes or writes.
struct LegacyMeetingArchive {
    let directory: URL
    init(directory: URL = Workbench.supportDirectory(component: "Meetings")) { self.directory = directory }
    private var pendingDirectory: URL { directory.appendingPathComponent(".transcript-removals", isDirectory: true) }
    /// Older removal attempts could stage originals before saving History. Show both copies
    /// if interrupted recovery left a collision; never reconcile, move or delete them here.
    func recordings(for id: UUID) -> [URL] {
        [directory, pendingDirectory].map { $0.appendingPathComponent(id.uuidString, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    func hasRecording(for id: UUID) -> Bool { !recordings(for: id).isEmpty }
    var savedRecordingURLs: [URL] {
        [directory, pendingDirectory].flatMap { parent in
            ((try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? [])
                .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        }
    }
    var hasSavedRecordings: Bool { !savedRecordingURLs.isEmpty }
    func reveal(_ id: UUID? = nil) {
        let urls = id.map(recordings(for:)) ?? savedRecordingURLs
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [directory] : urls)
    }
    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ethdawg.meetings") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ethdawg.meetings") != nil }
}

struct LegacyMeetingRecoveryView: View {
    let archive: LegacyMeetingArchive
    var transcript: Transcript? = nil
    var done: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your saved recordings").font(.headline)
            Text("Meetings is now a separate app. Your existing transcripts remain in History and the original recordings stay on this Mac. In Meetings, choose Import from Workbench to copy them without moving or deleting the originals.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if LegacyMeetingArchive.isInstalled { Button("Open Meetings", action: LegacyMeetingArchive.openApp) }
                Button("Show saved recordings") { archive.reveal(transcript?.id) }
                if let done { Spacer(); Button("Done", action: done).keyboardShortcut(.defaultAction) }
            }
        }.padding(20).frame(maxWidth: 540, alignment: .leading)
    }
}
