import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderView: View {
    let title: String
    @Binding var hotKey: HotKey
    @ObservedObject var localization: LocalizationManager

    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(minWidth: 128, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            Button(buttonTitle) {
                isRecording = true
            }
            .keyboardShortcut(.cancelAction)

            Text(hotKey.displayText)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isRecording ? .accentColor : .secondary)
                .frame(width: 120, alignment: .leading)

            Text(isRecording ? localization.string("settings.hotkey.recordingHint") : localization.string("settings.hotkey.clickToRecordHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HotKeyCaptureRepresentable(isRecording: $isRecording) { event in
                guard let recordedHotKey = HotKey(event: event) else { return }
                hotKey = recordedHotKey
                isRecording = false
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var buttonTitle: String {
        isRecording ? localization.string("settings.hotkey.recording") : localization.string("settings.hotkey.record")
    }
}

private struct HotKeyCaptureRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (NSEvent) -> Void

    func makeNSView(context: Context) -> HotKeyCaptureView {
        let view = HotKeyCaptureView()
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.isRecording = isRecording

        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class HotKeyCaptureView: NSView {
    var isRecording = false
    var onRecord: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        onRecord?(event)
    }
}

private extension HotKey {
    init?(event: NSEvent) {
        let modifiers = HotKeyModifiers(eventModifierFlags: event.modifierFlags)
        guard !modifiers.isEmpty else { return nil }

        self.init(
            key: HotKeyKey(keyCode: UInt32(event.keyCode), displayText: event.hotKeyDisplayText),
            modifiers: modifiers
        )
    }
}

private extension HotKeyModifiers {
    init(eventModifierFlags flags: NSEvent.ModifierFlags) {
        var modifiers: HotKeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}

private extension NSEvent {
    var hotKeyDisplayText: String {
        if let specialKey = specialKeyDisplayText {
            return specialKey
        }

        if let charactersIgnoringModifiers, !charactersIgnoringModifiers.isEmpty {
            return charactersIgnoringModifiers.uppercased()
        }

        return "Key \(keyCode)"
    }

    var specialKeyDisplayText: String? {
        switch Int(keyCode) {
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_Command: return "Command"
        case kVK_Shift: return "Shift"
        case kVK_CapsLock: return "Caps Lock"
        case kVK_Option: return "Option"
        case kVK_Control: return "Control"
        case kVK_RightCommand: return "Right Command"
        case kVK_RightShift: return "Right Shift"
        case kVK_RightOption: return "Right Option"
        case kVK_RightControl: return "Right Control"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: return nil
        }
    }
}
