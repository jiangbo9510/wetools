import SwiftUI

struct ScreenshotActionPanelView: View {
    @ObservedObject var localization: LocalizationManager
    @State private var hoveredTitleKey: String?

    let onScreenshot: () -> Void
    let onFullScreen: () -> Void
    let onScrollingScreenshot: () -> Void
    let onRecording: () -> Void
    let onOCR: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.grid.3x3")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            optionButton("screenshot.area", systemImage: "selection.pin.in.out", action: onScreenshot)
            optionButton("screenshot.fullScreen", systemImage: "macwindow", action: onFullScreen)
            optionButton("action.recording", systemImage: "record.circle", action: onRecording)
            optionButton("screenshot.extractText", systemImage: "text.viewfinder", action: onOCR)

            Divider()
                .frame(height: 28)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(localization.string("common.cancel"))
            .onHover { hovering in
                hoveredTitleKey = hovering ? "common.cancel" : nil
            }
            .overlay(alignment: .top) {
                tooltip(for: "common.cancel")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
        .buttonStyle(.bordered)
        .animation(.easeOut(duration: 0.12), value: hoveredTitleKey)
    }

    private func optionButton(_ titleKey: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 20)
        }
            .help(localization.string(titleKey))
            .onHover { hovering in
                hoveredTitleKey = hovering ? titleKey : nil
            }
            .overlay(alignment: .top) {
                tooltip(for: titleKey)
            }
            .zIndex(hoveredTitleKey == titleKey ? 1 : 0)
    }

    private func tooltip(for titleKey: String) -> some View {
        Group {
            if hoveredTitleKey == titleKey {
                Text(localization.string(titleKey))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 8, y: 3)
                    .fixedSize(horizontal: true, vertical: true)
                    .offset(y: -38)
                    .transition(.opacity)
            }
        }
    }
}
