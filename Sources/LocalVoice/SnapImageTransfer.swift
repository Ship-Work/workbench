import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A drag owns its full-resolution PNG, never a mutable store or editor. Finder
/// receives a named file promise; image-aware apps can read PNG bytes directly.
final class SnapImageTransfer: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let png: Data
    let filename: String
    private static let writes: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Workbench.SnapImageTransfer"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(png: Data, title: String) {
        self.png = png
        filename = Self.filename(title)
        super.init()
        fileType = UTType.png.identifier
        delegate = self
    }

    static func filename(_ title: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        var name = title.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if name.lowercased().hasSuffix(".png") { name.removeLast(4) }
        // Leave room for Finder's collision suffix and filesystem byte limits.
        while name.utf8.count > 180 { name.removeLast() }
        if name.isEmpty { name = "Snap" }
        return name + ".png"
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.png]
    }
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .png ? png : super.pasteboardPropertyList(forType: type)
    }
    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .png ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { filename }
    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { Self.writes }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            // Never replace an existing receiver file, even if its app supplied a conflicting URL.
            try png.write(to: url, options: .withoutOverwriting)
            completionHandler(nil)
        } catch { completionHandler(error) }
    }
}

/// Transparent pointer surface over a normal SwiftUI button. A click keeps the
/// button's action; a deliberate drag exports. Keyboard and VoiceOver stay with
/// the original button, so there is no second focus stop.
struct SnapImageDragSurface: NSViewRepresentable {
    let transfer: () throws -> SnapImageTransfer
    let click: () -> Void
    let failure: (Error) -> Void

    func makeNSView(context: Context) -> SnapImageDragView {
        let view = SnapImageDragView()
        view.setAccessibilityElement(false)
        updateNSView(view, context: context)
        return view
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SnapImageDragView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
    func updateNSView(_ view: SnapImageDragView, context: Context) {
        view.isEnabled = context.environment.isEnabled
        view.transfer = transfer; view.click = click; view.failure = failure
    }
}

/// Also used directly as the read-only workspace image. Editing the canvas
/// remains mark manipulation; its Copy image button supplies the drag surface.
final class SnapImageDragView: NSImageView, NSDraggingSource {
    var transfer: (() throws -> SnapImageTransfer)?
    var click: (() -> Void)?
    var failure: ((Error) -> Void)?
    private var mouseStart: NSPoint?
    private var activeTransfer: SnapImageTransfer?

    override func mouseDown(with event: NSEvent) { mouseStart = isEnabled ? event.locationInWindow : nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4,
              let transfer else { return }
        mouseStart = nil
        do {
            let snapshot = try transfer()
            guard let preview = NSImage(data: snapshot.png) else { throw SnapError.message("This image could not be dragged. Its original is unchanged.") }
            activeTransfer = snapshot
            let item = NSDraggingItem(pasteboardWriter: snapshot)
            let factor = min(1, 220 / max(preview.size.width, preview.size.height))
            let size = NSSize(width: preview.size.width * factor, height: preview.size.height * factor)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), contents: preview)
            beginDraggingSession(with: [item], event: event, source: self)
        } catch { failure?(error) }
    }
    override func mouseUp(with event: NSEvent) {
        let wasClick = mouseStart != nil
        mouseStart = nil
        if wasClick, bounds.contains(convert(event.locationInWindow, from: nil)) { click?() }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        activeTransfer = nil; mouseStart = nil
    }
}
