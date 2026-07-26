import AppKit
import Carbon
import SwiftUI

struct ClipboardHistoryPanelView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var localization: LocalizationManager

    var onClose: () -> Void
    var pasteTargetApplication: () -> NSRunningApplication?
    var onSettings: () -> Void

    @State private var query = ""
    @State private var selectedID: ClipboardItem.ID?
    @State private var page = 0
    @State private var localKeyMonitor: Any?

    private let pageSize = 20

    private var filteredItems: [ClipboardItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return clipboardManager.items
        }

        return clipboardManager.items.filter { item in
            item.preview.localizedCaseInsensitiveContains(query) ||
            (item.text?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var pagedItems: [ClipboardItem] {
        guard !filteredItems.isEmpty else { return [] }
        let start = min(page * pageSize, max(filteredItems.count - 1, 0))
        let end = min(start + pageSize, filteredItems.count)
        return Array(filteredItems[start..<end])
    }

    private var pageRangeText: String {
        guard !filteredItems.isEmpty else { return "0 - 0" }
        let start = page * pageSize + 1
        let end = min((page + 1) * pageSize, filteredItems.count)
        return "\(start) - \(end)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(localization.string("clipboard.history"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            TextField(localization.string("clipboard.search"), text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            if pagedItems.isEmpty {
                Spacer()
                Text(localization.string("clipboard.empty"))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(pagedItems, selection: $selectedID) { item in
                    ClipboardHistoryRow(item: item, localization: localization) {
                        clipboardManager.delete(item)
                        clampPage()
                    } onPaste: {
                        selectedID = item.id
                        paste(item)
                    }
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 18)
            }

            Divider()

            HStack {
                Button {
                    onSettings()
                } label: {
                    Label(localization.string("settings.title"), systemImage: "gearshape")
                }

                Button(localization.string("clipboard.clearAll")) {
                    clipboardManager.clear()
                    selectedID = nil
                    page = 0
                }
                .disabled(clipboardManager.items.isEmpty)

                Spacer()

                Text(pageRangeText)
                    .font(.system(size: 10, design: .monospaced))

                Button {
                    page = max(page - 1, 0)
                    selectedID = pagedItems.first?.id
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(page == 0)

                Button {
                    page = min(page + 1, maxPage)
                    selectedID = pagedItems.first?.id
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(page >= maxPage)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            KeyboardCaptureView(
                onUp: selectPrevious,
                onDown: selectNext,
                onReturn: pasteSelected,
                onEscape: onClose
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
        }
        .frame(width: 360, height: 320)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            selectedID = pagedItems.first?.id
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: query) { _ in
            page = 0
            selectedID = pagedItems.first?.id
        }
    }

    private func installKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == localization.string("clipboard.history") else {
                return event
            }

            switch Int(event.keyCode) {
            case kVK_UpArrow:
                selectPrevious()
                return nil
            case kVK_DownArrow:
                selectNext()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                pasteSelected()
                return nil
            case kVK_Escape:
                onClose()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func pasteSelected() {
        guard let item = selectedItem else { return }
        paste(item)
    }

    private func paste(_ item: ClipboardItem) {
        let targetApplication = pasteTargetApplication()
        onClose()
        DispatchQueue.main.async {
            clipboardManager.paste(item, autoPaste: true, targetApplication: targetApplication)
        }
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedID else { return pagedItems.first }
        return pagedItems.first { $0.id == selectedID }
    }

    private func selectPrevious() {
        moveSelection(delta: -1)
    }

    private func selectNext() {
        moveSelection(delta: 1)
    }

    private func moveSelection(delta: Int) {
        guard !pagedItems.isEmpty else { return }
        let currentIndex = selectedItem.flatMap { selected in
            pagedItems.firstIndex { $0.id == selected.id }
        } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), pagedItems.count - 1)
        selectedID = pagedItems[nextIndex].id
    }

    private var maxPage: Int {
        max((filteredItems.count - 1) / pageSize, 0)
    }

    private func clampPage() {
        page = min(page, maxPage)
        selectedID = pagedItems.first?.id
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    @ObservedObject var localization: LocalizationManager
    let onDelete: () -> Void
    let onPaste: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayPreview)
                    .font(.system(size: 10, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
            }
            .buttonStyle(.borderless)
            .help(localization.string("common.delete"))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPaste)
        .padding(.vertical, 1)
    }

    private var displayPreview: String {
        switch item.kind {
        case .text:
            return item.preview
        case .image:
            return localization.string("clipboard.image")
        case .file:
            return item.preview
        }
    }

    private var iconName: String {
        switch item.kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file:
            if ["mov", "mp4", "gif"].contains(item.fileType ?? "") { return "film" }
            return "doc"
        }
    }
}

private struct KeyboardCaptureView: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyboardCaptureNSView {
        let view = KeyboardCaptureNSView()
        view.onUp = onUp
        view.onDown = onDown
        view.onReturn = onReturn
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureNSView, context: Context) {
        nsView.onUp = onUp
        nsView.onDown = onDown
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyboardCaptureNSView: NSView {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            onUp?()
        case kVK_DownArrow:
            onDown?()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onReturn?()
        case kVK_Escape:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
