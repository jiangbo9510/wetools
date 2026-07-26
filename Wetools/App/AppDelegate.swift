import AppKit
import Carbon
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = JSONFileStore<AppSettings.Snapshot>(fileName: "settings.json")
    private lazy var settings = AppSettings(store: settingsStore)
    private lazy var localization = LocalizationManager(initialLanguage: settings.appLanguage)
    private lazy var providerStore = LLMProviderStore()
    private lazy var clipboardManager = ClipboardManager(settings: settings)
    private lazy var screenshotManager = ScreenshotManager(settings: settings, localization: localization, providerStore: providerStore)
    private let permissionManager = PermissionManager()
    private lazy var hotKeyManager = HotKeyManager(settings: settings)

    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private var clipboardHistoryWindowController: NSWindowController?
    private weak var clipboardPasteTargetApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestNotificationAuthorization()
        configureMenuBar()
        configureHotKeys()
        clipboardManager.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
        clipboardManager.stopMonitoring()
    }

    private func configureMenuBar() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "Wetools")
        item.button?.imagePosition = .imageLeading
        item.button?.title = "Wetools"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: localization.string("action.screenshotTool"), action: #selector(openScreenshotTool), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: localization.string("action.clipboardHistory"), action: #selector(triggerClipboardHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: localization.string("settings.title"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: localization.string("app.quit"), action: #selector(quit), keyEquivalent: "q"))

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func configureHotKeys() {
        hotKeyManager.onScreenshot = { [weak self] in self?.triggerScreenshot() }
        hotKeyManager.onClipboardHistory = { [weak self] in self?.triggerClipboardHistory() }
        hotKeyManager.registerAll()

        settings.onChange = { [weak self] in
            guard let self else { return }
            localization.language = settings.appLanguage
            configureMenuBar()
            settingsWindowController?.window?.title = localization.string("settings.title")
            hotKeyManager.registerAll()
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(
                settings: settings,
                permissionManager: permissionManager,
                localization: localization
            )
            let hostingController = NSHostingController(rootView: view)
            let window = EscapeClosingWindow(contentViewController: hostingController)
            window.title = localization.string("settings.title")
            window.setContentSize(NSSize(width: 620, height: 560))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    @objc private func triggerScreenshot() {
        NSLog("Screenshot hot key triggered")
        screenshotManager.startCaptureTool()
    }

    @objc private func openScreenshotTool() {
        screenshotManager.startCaptureTool()
    }

    @objc private func triggerClipboardHistory() {
        showClipboardHistory()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func showClipboardHistory() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        if frontmostApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            clipboardPasteTargetApp = frontmostApp
        }

        if clipboardHistoryWindowController == nil {
            let panel = ClipboardHistoryPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = localization.string("clipboard.history")
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            clipboardHistoryWindowController = NSWindowController(window: panel)
        }

        if let window = clipboardHistoryWindowController?.window {
            window.contentView = NSHostingView(rootView: ClipboardHistoryPanelView(
                clipboardManager: clipboardManager,
                settings: settings,
                localization: localization,
                onClose: { [weak window] in
                    window?.orderOut(nil)
                },
                pasteTargetApplication: { [weak self] in
                    self?.clipboardPasteTargetApp
                },
                onSettings: { [weak self, weak window] in
                    window?.orderOut(nil)
                    self?.openSettings()
                }
            ))
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: mouse.x - window.frame.width / 2, y: mouse.y - window.frame.height + 24))
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}

private final class EscapeClosingWindow: NSWindow {
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installEscapeMonitors()
    }

    override func close() {
        removeEscapeMonitors()
        super.close()
    }

    private func installEscapeMonitors() {
        guard localEscapeMonitor == nil, globalEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            self?.close()
            return nil
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return }
            DispatchQueue.main.async {
                self?.close()
            }
        }
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }
}

private final class ClipboardHistoryPanel: NSPanel {
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installEscapeMonitors()
    }

    override func orderOut(_ sender: Any?) {
        removeEscapeMonitors()
        super.orderOut(sender)
    }

    override func close() {
        removeEscapeMonitors()
        super.close()
    }

    private func installEscapeMonitors() {
        guard localEscapeMonitor == nil, globalEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            self?.orderOut(nil)
            return nil
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return }
            DispatchQueue.main.async {
                self?.orderOut(nil)
            }
        }
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }
}
