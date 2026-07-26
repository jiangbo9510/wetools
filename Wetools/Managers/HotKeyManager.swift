import Carbon
import AppKit
import Foundation

@MainActor
final class HotKeyManager {
    enum HotKeyAction: UInt32, CaseIterable {
        case screenshot = 1
        case clipboardHistory = 2
    }

    var onScreenshot: (() -> Void)?
    var onClipboardHistory: (() -> Void)?

    private weak var settings: AppSettings?
    private var registeredRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var fallbackGlobalMonitor: Any?
    private var fallbackLocalMonitor: Any?

    init(settings: AppSettings) {
        self.settings = settings
        installEventHandler()
    }

    deinit {
        for ref in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        MainActor.assumeIsolated {
            removeFallbackMonitors()
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func registerAll() {
        guard let settings else { return }
        unregisterAll()

        register(settings.screenshotHotKey, action: .screenshot)
        register(settings.clipboardHistoryHotKey, action: .clipboardHistory)
        installFallbackMonitors()
    }

    func unregisterAll() {
        for ref in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
        removeFallbackMonitors()
    }

    private func register(_ hotKey: HotKey, action: HotKeyAction) {
        var hotKeyRef: EventHotKeyRef?
        let signature = OSType(UInt32("WTLS".fourCharCode))
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(hotKey.key.keyCode, hotKey.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == noErr, let hotKeyRef {
            registeredRefs.append(hotKeyRef)
        } else {
            NSLog("Failed to register hot key \(hotKey.displayText), status: \(status)")
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }
                Task { @MainActor in
                    manager.handle(actionID: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func handle(actionID: UInt32) {
        guard let action = HotKeyAction(rawValue: actionID) else { return }

        switch action {
        case .screenshot:
            onScreenshot?()
        case .clipboardHistory:
            onClipboardHistory?()
        }
    }

    private func installFallbackMonitors() {
        removeFallbackMonitors()
        fallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleFallback(event: event)
            }
        }
        fallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleFallback(event: event) {
                return nil
            }
            return event
        }
    }

    private func removeFallbackMonitors() {
        if let fallbackGlobalMonitor {
            NSEvent.removeMonitor(fallbackGlobalMonitor)
            self.fallbackGlobalMonitor = nil
        }
        if let fallbackLocalMonitor {
            NSEvent.removeMonitor(fallbackLocalMonitor)
            self.fallbackLocalMonitor = nil
        }
    }

    @discardableResult
    private func handleFallback(event: NSEvent) -> Bool {
        guard let settings else { return false }
        if event.matches(settings.screenshotHotKey) {
            NSLog("Screenshot fallback hot key triggered")
            onScreenshot?()
            return true
        }
        if event.matches(settings.clipboardHistoryHotKey) {
            NSLog("Clipboard fallback hot key triggered")
            onClipboardHistory?()
            return true
        }
        return false
    }
}

private extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}

private extension NSEvent {
    func matches(_ hotKey: HotKey) -> Bool {
        guard UInt32(keyCode) == hotKey.key.keyCode else { return false }
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command) == hotKey.modifiers.contains(.command) &&
            flags.contains(.option) == hotKey.modifiers.contains(.option) &&
            flags.contains(.control) == hotKey.modifiers.contains(.control) &&
            flags.contains(.shift) == hotKey.modifiers.contains(.shift)
    }
}
