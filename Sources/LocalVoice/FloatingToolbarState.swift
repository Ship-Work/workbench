import AppKit
import StageKit
import ToolbarCore

extension FloatingControlAnchor {
    var toolbarAnchor: ToolbarAnchor {
        switch self {
        case .topLeft: return .topLeft
        case .top: return .top
        case .topRight: return .topRight
        case .left: return .left
        case .right: return .right
        case .bottomLeft: return .bottomLeft
        case .bottom: return .bottom
        case .bottomRight: return .bottomRight
        }
    }
}

/// Each item retains its action for the duration of native menu tracking.
final class ToolbarMenuAction: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, checked: Bool = false, enabled: Bool = true, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self; state = checked ? .on : .off; isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { run() }
}
