import AppKit

/// Executes the production pointer handlers and AppKit coordinate conversion.
/// Only session creation is intercepted: this does not claim an OS/receiver drop.
@MainActor
enum SnapDragChecks {
    private final class Probe: SnapImageDragView {
        var initiatingEvent: NSEvent?
        var items: [NSDraggingItem] = []
        let session = NSDraggingSession()
        override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession {
            self.items = items; initiatingEvent = event
            return session
        }
    }

    static func run(png: Data) throws -> Int {
        var checks = 0
        func check(_ condition: Bool, _ text: String) throws {
            guard condition else { throw SnapError.message("SNAP_DRAG_CHECK_FAILED: " + text) }
            checks += 1
        }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: true)
        let view = Probe(frame: NSRect(x: 40, y: 30, width: 300, height: 150))
        window.contentView!.addSubview(view)
        func event(_ type: NSEvent.EventType, _ point: NSPoint, _ time: TimeInterval) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [.shift], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0.5)!
        }
        let start = NSPoint(x: 100, y: 70), moved = NSPoint(x: 220, y: 140)
        let down = event(.leftMouseDown, start, 1)
        var clicks = 0, failures = 0, snapshots = 0
        weak var frozen: SnapImageTransfer?
        view.click = { clicks += 1 }; view.failure = { _ in failures += 1 }
        view.transfer = {
            snapshots += 1
            let transfer = SnapImageTransfer(png: png, title: "Synthetic image")
            frozen = transfer
            return transfer
        }
        view.mouseDown(with: down)
        view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 102, y: 71), 2))
        try check(snapshots == 0 && view.initiatingEvent == nil, "sub-threshold motion does not prepare a drag")
        view.mouseUp(with: event(.leftMouseUp, start, 3))
        try check(clicks == 1, "sub-threshold motion remains an ordinary click")

        view.mouseDown(with: down)
        view.mouseDragged(with: event(.leftMouseDragged, moved, 4))
        try check(view.initiatingEvent === down, "AppKit receives the exact initiating mouse-down event after coalesced movement")
        let frame = view.items.first!.draggingFrame, origin = view.convert(start, from: nil)
        try check(abs(frame.midX - origin.x) < 0.01 && abs(frame.midY - origin.y) < 0.01, "the preview and initiating event share an origin, preventing a cursor-offset jump")
        try check(snapshots == 1 && frozen?.png == png, "the drag owns one unchanged image snapshot")
        view.mouseUp(with: event(.leftMouseUp, moved, 5))
        try check(clicks == 1, "ending a drag does not also invoke the click action")
        view.items.removeAll()
        view.draggingSession(view.session, endedAt: .zero, operation: [])
        try check(frozen == nil, "cancellation releases the source-owned snapshot")

        view.transfer = { throw SnapError.message("Synthetic unavailable image") }
        view.mouseDown(with: down); view.mouseDragged(with: event(.leftMouseDragged, moved, 6))
        view.mouseUp(with: event(.leftMouseUp, start, 7))
        try check(failures == 1 && clicks == 1, "unavailable image reports once without invoking a click")
        view.mouseDown(with: down); view.mouseUp(with: event(.leftMouseUp, start, 8))
        try check(clicks == 2, "a failed drag leaves the next click usable")
        view.isEnabled = false
        view.mouseDown(with: down); view.mouseDragged(with: event(.leftMouseDragged, moved, 9))
        view.mouseUp(with: event(.leftMouseUp, start, 10))
        try check(clicks == 2 && failures == 1, "a disabled image neither clicks nor prepares a drag")
        print("SNAP_DRAG_CHECKS_OK: \(checks) checks; native initiation boundary intercepted, no receiver acceptance")
        return checks
    }
}
