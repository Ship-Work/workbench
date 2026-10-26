import AppKit
import SwiftUI

struct ShortcutKeycap: View {
    @ObservedObject var model: AppModel
    var id: UInt32
    var title: String
    var body: some View {
        Button { model.onEditShortcut?(id) } label: {
            HStack(spacing: 7) {
                Text(model.preferences.shortcut(id).label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Image(systemName: "pencil").font(.system(size: 10))
            }.padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(.primary)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(model.phase != .idle)
            .accessibilityLabel("Edit \(title.lowercased()) shortcut")
            .help("Opens Settings › Keyboard with this shortcut selected")
    }
}

struct ShortcutControl: View {
    @ObservedObject var model: AppModel
    var id: UInt32
    var title: String
    /// A settings row that already names the shortcut shows only its keys.
    var showsTitle = true
    var shortcut: VoiceShortcut { model.preferences.shortcut(id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if showsTitle { Text(title); Spacer() }
                ShortcutKeycap(model: model, id: id, title: title)
                if !showsTitle { Spacer() }
            }
            if let failure = model.shortcutFailures[id] { WorkbenchNote(failure, font: .caption) }
        }
    }
}

/// A row in a settings sheet: its name in one fixed column, its control and note beside it, so
/// every option on the sheet starts at the same edge.
struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) { content() }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Dictate's other options: the shortcut that starts it and how that shortcut records.
struct VoiceOptions: View {
    @ObservedObject var model: AppModel
    var showShortcut = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showShortcut {
                SettingsRow("Shortcut") { ShortcutControl(model: model, id: 1, title: "Dictation", showsTitle: false) }
            }
            SettingsRow("Activation") {
                Picker("Activation", selection: $model.preferences.capture) {
                    ForEach(CaptureMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize()
                // The same words the one-time hold lesson uses, with the shortcut as it is saved (#134 T5).
                // With the shortcut off, or held by another app, there is no key to teach; the keycap above sets one (#15).
                Text(VoiceOptions.activationHint(model.preferences.dictationShortcut, failure: model.shortcutFailures[1], capture: model.preferences.capture))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.disabled(model.phase != .idle)
    }
    nonisolated static func activationHint(_ shortcut: VoiceShortcut, failure: String?, capture: CaptureMode) -> String {
        guard shortcut.enabled else { return "Applies to the Voice to Text shortcut, which is off. Click the shortcut above to set one." }
        guard failure == nil else { return "Applies to the Voice to Text shortcut, which isn’t available. Click the shortcut above to choose another." }
        return capture == .hold ? HoldLesson.title(shortcut: shortcut.label) + " " + HoldLesson.body
            : "Press \(shortcut.label) to start dictating, and again to finish."
    }
}

/// Where Dictate's words go and how they are tidied (#134). A copy for ⌘V is a finished result
/// (#165), so the caption says what happens today: until Accessibility is approved, Paste
/// automatically copies, and Set up automatic paste… sits beside it as an option, never a step
/// to wait on. Each text style shows its description and one example checked against the real
/// cleanup.
struct DictateTaskOptions: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsRow("Delivery") {
                HStack(spacing: 10) {
                    Picker("Delivery", selection: $model.preferences.delivery) {
                        ForEach(DeliveryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                    if model.preferences.delivery == .paste {
                        // Secondary buttons on the sheet sit at the trailing edge, as Models and Your dictionary do.
                        Spacer()
                        if model.accessibilityGranted {
                            Label("Ready", systemImage: "checkmark.circle").foregroundStyle(Workbench.accent).font(.caption)
                        } else {
                            // The choice is kept for a later approval; copying works now.
                            Button("Set up automatic paste…") { model.requestAccessibility() }
                        }
                    }
                }
                Text(deliveryCaption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsRow("Text style") {
                Picker("Text style", selection: $model.preferences.cleanup) {
                    ForEach(CleanupStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize()
                Text(model.preferences.cleanup.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(model.preferences.cleanup.exampleText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.disabled(model.phase != .idle)
    }
    private var deliveryCaption: String {
        switch model.preferences.delivery {
        case .clipboard: return "Your words are copied. Paste with ⌘V."
        case .paste where model.accessibilityGranted: return "Your words go back into the text field you started in."
        case .paste: return "Until Accessibility is allowed, your words are copied and you paste with ⌘V. " + MacAccount.automaticPasteApproval
        }
    }
}
