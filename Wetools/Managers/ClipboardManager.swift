import AppKit
import ApplicationServices
import Carbon
import CryptoKit
import Foundation

@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let settings: AppSettings
    private let store = JSONFileStore<ClipboardHistorySnapshot>(fileName: "clipboard-history.json")
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(settings: AppSettings) {
        self.settings = settings
        items = store.load()?.items ?? []
    }

    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.pollPasteboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func delete(_ item: ClipboardItem) {
        if let imagePath = item.imagePath {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        for item in items {
            if let imagePath = item.imagePath {
                try? FileManager.default.removeItem(atPath: imagePath)
            }
        }
        items.removeAll()
        persist()
    }

    func writeToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            guard let imagePath = item.imagePath,
                  let image = NSImage(contentsOfFile: imagePath) else { return }
            pasteboard.writeObjects([image])
        case .file:
            guard let filePath = item.filePath else { return }
            pasteboard.writeObjects([URL(fileURLWithPath: filePath) as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
    }

    func paste(_ item: ClipboardItem, autoPaste: Bool) {
        paste(item, autoPaste: autoPaste, targetApplication: nil)
    }

    func paste(_ item: ClipboardItem, autoPaste: Bool, targetApplication: NSRunningApplication?) {
        writeToPasteboard(item)
        promoteToMostRecent(item)
        guard autoPaste else { return }
        guard ensureAccessibilityPermissionForAutoPaste() else { return }

        if let targetApplication {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.simulateCommandV(targetApplication: targetApplication)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.simulateCommandV()
            }
        }
    }

    private func ensureAccessibilityPermissionForAutoPaste() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        NSLog("Accessibility permission is required to paste clipboard history into the previous app.")
        return false
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let fileURL = readFileURL(from: pasteboard) {
            addFile(fileURL)
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            addText(text)
            return
        }

        if let image = readImage(from: pasteboard) {
            addImage(image)
        }
    }

    private func addText(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let hash = sha256(Data(normalized.utf8))
        guard items.first?.contentHash != hash else { return }

        items.removeAll { $0.contentHash == hash }
        items.insert(ClipboardItem(
            id: UUID(),
            kind: .text,
            preview: normalized.previewText,
            text: text,
            imagePath: nil,
            filePath: nil,
            fileType: nil,
            contentHash: hash,
            createdAt: Date()
        ), at: 0)
        trimIfNeeded()
        persist()
    }

    private func addImage(_ image: NSImage) {
        guard let data = image.pngData else { return }
        let hash = sha256(data)
        guard items.first?.contentHash != hash else { return }

        items.removeAll { $0.contentHash == hash }

        do {
            let imageURL = try imageDirectory().appendingPathComponent("\(hash).png")
            try data.write(to: imageURL, options: [.atomic])
            items.insert(ClipboardItem(
                id: UUID(),
                kind: .image,
                preview: "Image",
                text: nil,
                imagePath: imageURL.path,
                filePath: nil,
                fileType: nil,
                contentHash: hash,
                createdAt: Date()
            ), at: 0)
            trimIfNeeded()
            persist()
        } catch {
            NSLog("Failed to store clipboard image: \(error.localizedDescription)")
        }
    }


    private func addFile(_ url: URL) {
        let path = url.path
        guard !path.isEmpty else { return }
        let hash = sha256(Data(path.utf8))
        guard items.first?.contentHash != hash else { return }

        items.removeAll { $0.contentHash == hash }
        items.insert(ClipboardItem(
            id: UUID(),
            kind: .file,
            preview: url.lastPathComponent,
            text: nil,
            imagePath: nil,
            filePath: path,
            fileType: url.pathExtension.lowercased(),
            contentHash: hash,
            createdAt: Date()
        ), at: 0)
        trimIfNeeded()
        persist()
    }

    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil),
           let image = objects.first as? NSImage {
            return image
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }


    private func readFileURL(from pasteboard: NSPasteboard) -> URL? {
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil),
           let url = objects.compactMap({ $0 as? URL }).first,
           url.isFileURL {
            return url
        }

        if let string = pasteboard.string(forType: .fileURL),
           let url = URL(string: string),
           url.isFileURL {
            return url
        }

        return nil
    }

    private func trimIfNeeded() {
        let maxItems = max(1, settings.maxClipboardHistory)
        guard items.count > maxItems else { return }
        let removed = items.suffix(from: maxItems)
        for item in removed {
            if let imagePath = item.imagePath {
                try? FileManager.default.removeItem(atPath: imagePath)
            }
        }
        items = Array(items.prefix(maxItems))
    }

    private func promoteToMostRecent(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var promotedItem = items.remove(at: index)
        promotedItem.createdAt = Date()
        items.insert(promotedItem, at: 0)
        persist()
    }

    private func persist() {
        store.save(ClipboardHistorySnapshot(items: items))
    }

    private func imageDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("Wetools", isDirectory: true).appendingPathComponent("ClipboardImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func simulateCommandV(targetApplication: NSRunningApplication? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        if let processIdentifier = targetApplication?.processIdentifier {
            keyDown?.postToPid(processIdentifier)
            keyUp?.postToPid(processIdentifier)
        } else {
            keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
            keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
}

private extension String {
    var previewText: String {
        let compact = replacingOccurrences(of: "\n", with: " ")
        if compact.count <= 80 { return compact }
        return String(compact.prefix(80)) + "..."
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
