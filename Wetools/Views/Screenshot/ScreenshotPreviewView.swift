import AppKit
import Carbon
import CoreImage
import SwiftUI
import Vision

struct ScreenshotPreviewView: View {
    @Environment(\.displayScale) private var displayScale

    let image: NSImage
    let screenImage: NSImage?
    @ObservedObject var settings: AppSettings
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var providerStore: LLMProviderStore
    let sourceRect: NSRect?
    let sourceScreenFrame: NSRect?
    let previewScreenFrame: NSRect?
    let allowsZoom: Bool
    let toolbarPlacement: ScreenshotToolbarPlacement
    let onEditingStarted: () -> Void

    @State private var selectedTool: ScreenshotEditTool?
    @State private var annotations: [ScreenshotAnnotation] = []
    @State private var draftAnnotation: ScreenshotAnnotation?
    @State private var drawingPoints: [CGPoint] = []
    @State private var selectedColor: Color = .red
    @State private var selectedLineWidth: AnnotationLineWidth = .medium
    @State private var errorMessage: String?
    @State private var isRecognizing = false
    @State private var watermarkText = "Wetools"
    @State private var watermarkOpacity = 0.35
    @State private var isWatermarkEditorPresented = false
    @State private var draftWatermarkText = "Wetools"
    @State private var draftWatermarkOpacity = 0.35
    @State private var watermarkPanel: WatermarkEditorPanel?
    @State private var selectedAnnotationID: UUID?
    @State private var activeAnnotationEdit: AnnotationEditState?
    @State private var hoveredToolNameKey: String?
    @State private var undoStack: [[ScreenshotAnnotation]] = []
    @State private var activeTextEdit: ActiveTextEdit?
    @State private var textFontSize: Double = 24
    @State private var hasStartedEditing = false
    @State private var displayRect: CGRect?
    @State private var dragStartDisplayRect: CGRect?
    @State private var ocrWindow: OCRTextWindow?
    @State private var selectedTranslationTarget: ScreenshotTranslationTarget?
    @State private var isTranslationTargetPickerPresented = false
    @State private var suppressTextCreationOnGestureEnd = false
    @State private var toolbarPosition: CGPoint?
    @State private var toolbarDragStartPosition: CGPoint?
    @State private var isMovingSelection = false
    @State private var zoomScale: CGFloat = 1
    @FocusState private var isTextEditorFocused: Bool

    private let ocrManager = OCRManager()

    var body: some View {
        ZStack(alignment: toolbarPlacement.alignment) {
            editorCanvas

            if shouldShowToolbar, let toolbarRect {
                toolBar
                    .simultaneousGesture(toolbarDragGesture())
                    .frame(width: toolbarRect.width, height: toolbarRect.height, alignment: .topLeading)
                    .position(x: toolbarRect.midX, y: toolbarRect.midY)
            } else if shouldShowToolbar {
                toolBar
                    .simultaneousGesture(toolbarDragGesture())
                    .frame(width: currentToolbarSize.width, height: currentToolbarSize.height, alignment: .topLeading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

        }
        .frame(minWidth: 160, minHeight: 120)
        .background(Color.clear)
        .onAppear {
            let initialDisplayRect = sourceCanvasRect(in: canvasSizeForLayout ?? image.size)
            displayRect = initialDisplayRect
            if toolbarPosition == nil, let initialDisplayRect, let rect = defaultToolbarRect(for: initialDisplayRect) {
                toolbarPosition = CGPoint(x: rect.midX, y: rect.midY)
            }
        }
        .overlayPreferenceValue(ToolbarTooltipAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let hoveredToolNameKey, let anchor = anchors[hoveredToolNameKey] {
                    let rect = proxy[anchor]
                    let title = localization.string(hoveredToolNameKey)
                    let tooltipWidth = min(
                        max(52, (title as NSString).size(withAttributes: [
                            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
                        ]).width + 20),
                        max(52, proxy.size.width - 16)
                    )
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
                        .shadow(radius: 8, y: 3)
                        .fixedSize(horizontal: true, vertical: true)
                        .position(
                            x: min(
                                max(rect.midX, tooltipWidth / 2 + 8),
                                proxy.size.width - tooltipWidth / 2 - 8
                            ),
                            y: max(18, rect.minY - 44)
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(
            ScreenshotPreviewKeyboardView(
                onEscape: { NSApp.keyWindow?.close() },
                onUndo: undo,
                onDelete: deleteSelectedAnnotation
            )
            .frame(width: 0, height: 0)
        )
    }

    private var editorCanvas: some View {
        GeometryReader { geometry in
            if allowsZoom {
                let baseRect = fittedImageRect(in: geometry.size)
                let zoomedSize = CGSize(width: baseRect.width * zoomScale, height: baseRect.height * zoomScale)
                let scrollCanvasSize = CGSize(
                    width: max(geometry.size.width, zoomedSize.width),
                    height: max(geometry.size.height, zoomedSize.height)
                )
                let zoomedRect = CGRect(
                    x: (scrollCanvasSize.width - zoomedSize.width) / 2,
                    y: (scrollCanvasSize.height - zoomedSize.height) / 2,
                    width: zoomedSize.width,
                    height: zoomedSize.height
                )

                ScrollView([.horizontal, .vertical]) {
                    canvasLayers(canvasSize: scrollCanvasSize, imageRect: zoomedRect)
                        .frame(width: scrollCanvasSize.width, height: scrollCanvasSize.height)
                }
                .scrollIndicators(.visible)
            } else {
                canvasLayers(canvasSize: geometry.size, imageRect: currentImageRect(in: geometry.size))
            }
        }
    }

    private func canvasLayers(canvasSize: CGSize, imageRect: CGRect) -> some View {
        ZStack {
            if let screenImage, sourceScreenFrame != nil {
                Image(nsImage: screenImage)
                    .resizable()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .position(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    .allowsHitTesting(false)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
            }

            dimmedBackground(imageRect: imageRect, canvasSize: canvasSize)

            ScreenshotAnnotationOverlay(
                annotations: visibleAnnotations,
                selectedID: selectedAnnotationID,
                canvasRect: imageRect
            )

            if let selectedTool {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if activeTextEdit != nil {
                            suppressTextCreationOnGestureEnd = true
                            commitActiveTextEdit()
                        }
                    }
                    .gesture(drawGesture(for: selectedTool, in: imageRect))
            }

            if selectedTool == nil, !hasStartedEditing {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .gesture(moveSelectionGesture(in: canvasSize))
            }

            if let activeTextEdit, let rect = activeTextEdit.annotation.rect(in: imageRect) {
                activeTextEditor(rect: rect, in: imageRect)
            }

            Rectangle()
                .strokeBorder(
                    Color(nsColor: .systemBlue),
                    lineWidth: 1 / max(1, displayScale)
                )
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
                .allowsHitTesting(false)
        }
    }

    private var toolBar: some View {
        VStack(alignment: toolbarPlacement.horizontal == .leading ? .leading : .trailing, spacing: 8) {
            HStack(spacing: 6) {
                toolbarDragHandle
                    .frame(width: 22, height: 30)

                if allowsZoom {
                    zoomControls
                    Divider().frame(height: 28)
                }

                toolButton(.rectangle, "rectangle")
                toolButton(.ellipse, "circle")
                toolButton(.line, "line.diagonal")
                toolButton(.arrow, "arrow.up.right")
                toolButton(.freehand, "scribble")
                toolButton(.text, "textformat")

                Divider().frame(height: 28)

                toolButton(.mosaic, "checkerboard.rectangle")
                highlightToolButton()

                Button {
                    beginWatermarkEditing()
                } label: {
                    Image(systemName: "text.badge.plus")
                        .frame(width: 30, height: 30)
                }
                .help(localization.string("screenshot.watermark"))
                .toolbarTooltip("screenshot.watermark", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

                Button {
                    pinScreenshot()
                } label: {
                    Image(systemName: "pin")
                        .frame(width: 30, height: 30)
                }
                .help(localization.string("screenshot.pin"))
                .toolbarTooltip("screenshot.pin", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

            Button {
                runOCR()
            } label: {
                Image(systemName: "text.viewfinder")
                    .frame(width: 30, height: 30)
                }
                .disabled(isRecognizing)
                .help(localization.string("screenshot.extractText"))
                .toolbarTooltip("screenshot.extractText", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

            HStack(spacing: 1) {
                Button {
                    translateImageText()
                } label: {
                    Image(systemName: "translate")
                        .frame(width: 30, height: 30)
                }

                Button {
                    isTranslationTargetPickerPresented.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 13, height: 22)
                }
                .popover(isPresented: $isTranslationTargetPickerPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ScreenshotTranslationTarget.allCases) { target in
                            Button {
                                selectedTranslationTarget = target
                                isTranslationTargetPickerPresented = false
                            } label: {
                                HStack {
                                    Text(target.displayName)
                                    Spacer(minLength: 18)
                                    if (selectedTranslationTarget ?? ScreenshotTranslationTarget.defaultTarget(for: localization.language)) == target {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .frame(minWidth: 126, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(8)
                    .background(.regularMaterial)
                }
            }
            .disabled(isRecognizing)
            .help(localization.string("screenshot.translateText"))
            .toolbarTooltip("screenshot.translateText", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

            Button {
                detectQRCode()
            } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .frame(width: 30, height: 30)
                }
                .help(localization.string("screenshot.detectQRCode"))
                .toolbarTooltip("screenshot.detectQRCode", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

                if isRecognizing {
                    ProgressView()
                        .controlSize(.small)
                }

                Divider().frame(height: 28)

                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 30, height: 30)
                }
                .disabled(undoStack.isEmpty)
                .help(localization.string("screenshot.undo"))
                .toolbarTooltip("screenshot.undo", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

                Button {
                    saveImage()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .frame(width: 30, height: 30)
                }
                .help(localization.string("screenshot.saveImage"))
                .toolbarTooltip("screenshot.saveImage", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

                Button {
                    NSApp.keyWindow?.close()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                }
                .help(localization.string("common.cancel"))
                .toolbarTooltip("common.cancel", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)

                Button {
                    copyImageAndClose()
                } label: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .frame(width: 30, height: 30)
                }
                .help(localization.string("screenshot.finishToClipboard"))
                .toolbarTooltip("screenshot.finishToClipboard", hoveredToolNameKey: $hoveredToolNameKey, localization: localization)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 16, weight: .medium))
            .controlSize(.large)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(width: currentToolbarSize.width)
            .contentShape(Rectangle())
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            Group {
                if let selectedTool, selectedTool.usesStrokeStyle {
                    strokeOptionsBar
                } else if selectedTool == .text {
                    textOptionsBar
                }
            }
        }
        .frame(width: currentToolbarSize.width, height: currentToolbarSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hoveredToolNameKey)
    }

    private var toolbarDragHandle: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(4), spacing: 3), count: 2), spacing: 3) {
            ForEach(0..<6, id: \.self) { _ in
                Circle()
                    .fill(Color.secondary.opacity(0.75))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 14, height: 22)
        .contentShape(Rectangle())
        .help(localization.string("screenshot.preview"))
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                zoomScale = max(0.25, zoomScale - 0.25)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 28)
            }
            .disabled(zoomScale <= 0.25)
            .help(localization.string("screenshot.zoomOut"))

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 42)

            Button {
                zoomScale = min(3, zoomScale + 0.25)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 28)
            }
            .disabled(zoomScale >= 3)
            .help(localization.string("screenshot.zoomIn"))
        }
    }

    private var strokeOptionsBar: some View {
        HStack(spacing: 10) {
            ForEach(AnnotationLineWidth.allCases) { width in
                Button {
                    selectedLineWidth = width
                } label: {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: width.dotDiameter, height: width.dotDiameter)
                        .frame(width: 24, height: 24)
                        .background(selectedLineWidth == width ? Color.accentColor.opacity(0.22) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 22)

            ForEach(AnnotationColorSwatch.swatches) { swatch in
                Button {
                    selectedColor = swatch.color
                } label: {
                    colorSwatchView(swatch.color)
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var textOptionsBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $textFontSize) {
                ForEach(Self.standardTextFontSizes, id: \.self) { size in
                    Text("\(Int(size))").tag(size)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 76)

            ForEach(AnnotationColorSwatch.swatches) { swatch in
                Button {
                    selectedColor = swatch.color
                } label: {
                    colorSwatchView(swatch.color)
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private static let standardTextFontSizes: [Double] = [12, 16, 24, 32, 48, 72, 96]

    private var currentToolbarSize: CGSize {
        toolbarSize(for: displayRect)
    }

    private func toolbarSize(for rect: CGRect?) -> CGSize {
        let availableWidth = max(240, canvasSizeForLayout?.width ?? 720)
        let hasSecondaryOptions = selectedTool?.usesStrokeStyle == true || selectedTool == .text
        return CGSize(width: min(availableWidth, 700), height: hasSecondaryOptions ? 112 : 62)
    }

    private var shouldShowToolbar: Bool {
        !isMovingSelection
    }

    private var toolbarRect: CGRect? {
        let canvasSize = canvasSizeForLayout ?? NSApp.keyWindow?.contentView?.bounds.size
        guard let canvasSize else { return nil }
        let size = currentToolbarSize
        let position: CGPoint
        if let toolbarPosition {
            position = toolbarPosition
        } else if let displayRect, let defaultRect = defaultToolbarRect(for: displayRect) {
            position = CGPoint(x: defaultRect.midX, y: defaultRect.midY)
        } else {
            return nil
        }
        let rect = CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2, width: size.width, height: size.height)
        return clampToolbar(rect, in: CGRect(origin: .zero, size: canvasSize).insetBy(dx: 0, dy: 8))
    }

    private func defaultToolbarRect(for displayRect: CGRect) -> CGRect? {
        let canvasSize = canvasSizeForLayout ?? NSApp.keyWindow?.contentView?.bounds.size
        guard let canvasSize else { return nil }
        let size = toolbarSize(for: displayRect)
        let margin: CGFloat = 8
        let spacing: CGFloat = 1
        let tooltipClearance: CGFloat = 58
        let originX: CGFloat
        if isFullScreenSelection(displayRect, canvasSize: canvasSize) {
            originX = displayRect.maxX - size.width
        } else {
            switch toolbarPlacement.horizontal {
            case .leading:
                originX = displayRect.minX
            case .trailing:
                originX = displayRect.maxX - size.width
            }
        }
        let topY = displayRect.minY - spacing - size.height / 2
        let bottomY = displayRect.maxY + spacing + size.height / 2
        let topFits = topY - size.height / 2 >= margin + tooltipClearance
        let bottomFits = bottomY + size.height / 2 <= canvasSize.height - margin
        let preferredY: CGFloat = {
            if isFullScreenSelection(displayRect, canvasSize: canvasSize) {
                return canvasSize.height - margin - size.height / 2
            }
            if sourceRect != nil {
                if topFits { return topY }
                if bottomFits { return bottomY }
            }
            if displayRect.height <= 220, topFits {
                return topY
            }
            switch toolbarPlacement.vertical {
            case .top:
                if topFits { return topY }
                if bottomFits { return bottomY }
            case .bottom:
                if bottomFits { return bottomY }
                if topFits { return topY }
            }
            let insideBottom = min(
                displayRect.maxY - margin - size.height / 2,
                canvasSize.height - margin - size.height / 2
            )
            return max(margin + size.height / 2, insideBottom)
        }()
        let clampedOriginX = min(max(originX, 0), canvasSize.width - size.width)
        let centerX = clampedOriginX + size.width / 2
        let centerY = min(max(preferredY, margin + size.height / 2), canvasSize.height - margin - size.height / 2)
        return CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height)
    }

    private func clampToolbar(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width)),
            y: min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height)),
            width: rect.width,
            height: rect.height
        )
    }

    private func isFullScreenSelection(_ rect: CGRect, canvasSize: CGSize) -> Bool {
        abs(rect.minX) <= 2 &&
            abs(rect.minY) <= 2 &&
            abs(rect.width - canvasSize.width) <= 2 &&
            abs(rect.height - canvasSize.height) <= 2
    }

    private func toolbarDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let canvasSize = canvasSizeForLayout ?? NSApp.keyWindow?.contentView?.bounds.size
                guard let canvasSize else { return }
                if toolbarDragStartPosition == nil {
                    toolbarDragStartPosition = toolbarPosition ?? toolbarRect.map { CGPoint(x: $0.midX, y: $0.midY) }
                }
                guard let toolbarDragStartPosition else { return }
                let proposed = CGPoint(
                    x: toolbarDragStartPosition.x + value.translation.width,
                    y: toolbarDragStartPosition.y + value.translation.height
                )
                let size = currentToolbarSize
                let rect = CGRect(x: proposed.x - size.width / 2, y: proposed.y - size.height / 2, width: size.width, height: size.height)
                let clamped = clampToolbar(rect, in: CGRect(origin: .zero, size: canvasSize).insetBy(dx: 0, dy: 8))
                toolbarPosition = CGPoint(x: clamped.midX, y: clamped.midY)
            }
            .onEnded { _ in
                toolbarDragStartPosition = nil
            }
    }

    private func colorSwatchView(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: color == .white ? 1 : 0))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: selectedColor == color ? 2 : 0).padding(-3))
            .frame(width: 18, height: 18)
            .frame(width: 24, height: 24)
    }

    private var visibleAnnotations: [ScreenshotAnnotation] {
        annotations + draftAnnotation.map { [$0] }.orEmpty + draftWatermarkAnnotation.map { [$0] }.orEmpty
    }

    private var renderAnnotations: [ScreenshotAnnotation] {
        annotations + draftWatermarkAnnotation.map { [$0] }.orEmpty
    }

    private var draftWatermarkAnnotation: ScreenshotAnnotation? {
        guard isWatermarkEditorPresented else { return nil }
        let text = draftWatermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return ScreenshotAnnotation(
            kind: .watermark,
            points: [CGPoint(x: 0.5, y: 0.5)],
            color: CodableColor(
                red: selectedColor.codableColor.red,
                green: selectedColor.codableColor.green,
                blue: selectedColor.codableColor.blue,
                alpha: draftWatermarkOpacity
            ),
            lineWidth: 1,
            text: text
        )
    }

    private func toolButton(_ tool: ScreenshotEditTool, _ systemImage: String) -> some View {
        Button {
            commitActiveTextEdit()
            selectedTool = tool
        } label: {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .help(localization.string(tool.localizationKey))
        .toolbarTooltip(tool.localizationKey, hoveredToolNameKey: $hoveredToolNameKey, localization: localization)
    }

    private func highlightToolButton() -> some View {
        Button {
            commitActiveTextEdit()
            selectedTool = .highlight
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.primary, lineWidth: 1.4)
                    .frame(width: 18, height: 14)
                Circle()
                    .stroke(Color.primary, lineWidth: 1.2)
                    .frame(width: 10, height: 10)
                Path { path in
                    path.move(to: CGPoint(x: 7, y: 12))
                    path.addLine(to: CGPoint(x: 10, y: 7))
                    path.addLine(to: CGPoint(x: 13, y: 12))
                }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                .frame(width: 20, height: 18)
            }
            .frame(width: 30, height: 30)
            .background(selectedTool == .highlight ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .help(localization.string(ScreenshotEditTool.highlight.localizationKey))
        .toolbarTooltip(ScreenshotEditTool.highlight.localizationKey, hoveredToolNameKey: $hoveredToolNameKey, localization: localization)
    }

    private func drawGesture(for selectedTool: ScreenshotEditTool, in canvasRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: selectedTool == .text || selectedTool == .tag ? 0 : 2)
            .onChanged { value in
                guard canvasRect.contains(value.location) else { return }

                if activeTextEdit != nil {
                    suppressTextCreationOnGestureEnd = true
                    commitActiveTextEdit()
                    return
                }

                if let activeAnnotationEdit {
                    updateAnnotation(activeAnnotationEdit, with: value.translation, in: canvasRect)
                    return
                }

                if let hit = hitAnnotation(at: value.startLocation, in: canvasRect) {
                    selectedAnnotationID = hit.annotation.id
                    if activeAnnotationEdit == nil {
                        pushUndoState()
                    }
                    activeAnnotationEdit = AnnotationEditState(
                        id: hit.annotation.id,
                        originalPoints: hit.annotation.points,
                        mode: hit.mode
                    )
                    return
                }

                selectedAnnotationID = nil
                let point = normalizedPoint(value.location, in: canvasRect)
                switch selectedTool {
                case .freehand:
                    drawingPoints.append(point)
                    draftAnnotation = ScreenshotAnnotation(
                        kind: .freehand,
                        points: drawingPoints,
                        color: selectedColor.codableColor,
                        lineWidth: selectedLineWidth.value
                    )
                case .text, .tag:
                    let start = normalizedPoint(value.startLocation, in: canvasRect)
                    draftAnnotation = ScreenshotAnnotation(
                        kind: selectedTool.annotationKind,
                        points: [start, point],
                        color: selectedColor.codableColor,
                        lineWidth: selectedTool == .text ? textFontSize / 5 : selectedLineWidth.value,
                        text: ""
                    )
                default:
                    let start = normalizedPoint(value.startLocation, in: canvasRect)
                    draftAnnotation = ScreenshotAnnotation(
                        kind: selectedTool.annotationKind,
                        points: [start, point],
                        color: selectedColor.codableColor,
                        lineWidth: selectedLineWidth.value
                    )
                }
            }
            .onEnded { value in
                defer {
                    draftAnnotation = nil
                    drawingPoints = []
                    activeAnnotationEdit = nil
                }

                if activeAnnotationEdit != nil { return }

                let location = value.location
                if selectedTool == .text {
                    if suppressTextCreationOnGestureEnd {
                        suppressTextCreationOnGestureEnd = false
                        return
                    }
                    guard canvasRect.contains(location) else { return }
                    let start = normalizedPoint(value.startLocation, in: canvasRect)
                    let endPoint = defaultTextEndPoint(from: value.startLocation, to: location, in: canvasRect)
                    let end = normalizedPoint(endPoint, in: canvasRect)
                    let annotation = ScreenshotAnnotation(
                        kind: .text,
                        points: [start, end],
                        color: selectedColor.codableColor,
                        lineWidth: textFontSize / 5,
                        text: ""
                    )
                    activeTextEdit = ActiveTextEdit(annotation: annotation, text: "")
                    DispatchQueue.main.async {
                        isTextEditorFocused = true
                    }
                    return
                }

                if selectedTool == .tag {
                    guard canvasRect.contains(location) else { return }
                    addTextAnnotation(at: normalizedPoint(location, in: canvasRect), isTag: selectedTool == .tag)
                    return
                }

                guard let draftAnnotation else { return }
                markEditingStarted()
                pushUndoState()
                annotations.append(draftAnnotation)
                selectedAnnotationID = draftAnnotation.id
            }
    }

    private func activeTextEditor(rect: CGRect, in canvasRect: CGRect) -> some View {
        let editorRect = activeTextEditorRect(baseRect: rect, in: canvasRect)
        return TextEditor(text: Binding(
            get: { activeTextEdit?.text ?? "" },
            set: { newValue in
                activeTextEdit?.text = newValue
                updateActiveTextRect(for: newValue, baseRect: rect, in: canvasRect)
            }
        ))
        .font(.system(size: textFontSize, weight: .semibold))
        .foregroundStyle(selectedColor)
        .scrollContentBackground(.hidden)
        .background(Color.white.opacity(0.08))
        .focused($isTextEditorFocused)
        .frame(width: editorRect.width, height: editorRect.height)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(selectedColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .position(x: editorRect.midX, y: editorRect.midY)
        .clipped()
        .onChange(of: textFontSize) { value in
            activeTextEdit?.annotation.lineWidth = value / 5
            updateActiveTextRect(for: activeTextEdit?.text ?? "", baseRect: rect, in: canvasRect)
        }
        .onChange(of: selectedColor) { value in
            activeTextEdit?.annotation.color = value.codableColor
        }
    }

    private func defaultTextEndPoint(from start: CGPoint, to end: CGPoint, in canvasRect: CGRect) -> CGPoint {
        if abs(start.x - end.x) > 4 || abs(start.y - end.y) > 4 {
            return end
        }
        return CGPoint(
            x: min(start.x + 180, canvasRect.maxX),
            y: min(start.y + max(44, textFontSize + 22), canvasRect.maxY)
        )
    }

    private func activeTextEditorRect(baseRect: CGRect, in canvasRect: CGRect) -> CGRect {
        let text = activeTextEdit?.text ?? ""
        let preferred = preferredTextEditorSize(text: text, minimum: baseRect.size)
        let width = min(preferred.width, max(40, canvasRect.maxX - baseRect.minX))
        let height = min(preferred.height, max(32, canvasRect.maxY - baseRect.minY))
        return CGRect(x: baseRect.minX, y: baseRect.minY, width: width, height: height)
    }

    private func preferredTextEditorSize(text: String, minimum: CGSize) -> CGSize {
        let lines = text.components(separatedBy: .newlines)
        let longestLine = lines.map(\.count).max() ?? 0
        let width = max(100, minimum.width, CGFloat(longestLine) * textFontSize * 0.62 + 28)
        let height = max(44, minimum.height, CGFloat(max(lines.count, 1)) * (textFontSize + 8) + 20)
        return CGSize(width: width, height: height)
    }

    private func updateActiveTextRect(for text: String, baseRect: CGRect, in canvasRect: CGRect) {
        guard var edit = activeTextEdit, edit.annotation.points.count >= 2 else { return }
        let editorRect = activeTextEditorRect(baseRect: baseRect, in: canvasRect)
        edit.annotation.points[1] = normalizedPoint(CGPoint(x: editorRect.maxX, y: editorRect.maxY), in: canvasRect)
        activeTextEdit = edit
    }

    private func commitActiveTextEdit() {
        guard var edit = activeTextEdit else { return }
        let text = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTextEdit = nil
        isTextEditorFocused = false
        guard !text.isEmpty else { return }
        edit.annotation.text = text
        edit.annotation.color = selectedColor.codableColor
        edit.annotation.lineWidth = textFontSize / 5
        markEditingStarted()
        pushUndoState()
        annotations.append(edit.annotation)
        selectedAnnotationID = edit.annotation.id
    }

    private func markEditingStarted() {
        guard !hasStartedEditing else { return }
        hasStartedEditing = true
        onEditingStarted()
    }

    private func hitAnnotation(at location: CGPoint, in canvasRect: CGRect) -> AnnotationHit? {
        for annotation in annotations.reversed() {
            if annotation.resizeHandle(in: canvasRect).contains(location) {
                return AnnotationHit(annotation: annotation, mode: .resize)
            }
            if annotation.contains(location, in: canvasRect) {
                return AnnotationHit(annotation: annotation, mode: .move)
            }
        }
        return nil
    }

    private func updateAnnotation(_ edit: AnnotationEditState, with translation: CGSize, in canvasRect: CGRect) {
        guard let index = annotations.firstIndex(where: { $0.id == edit.id }) else { return }
        let dx = translation.width / canvasRect.width
        let dy = translation.height / canvasRect.height
        switch edit.mode {
        case .move:
            annotations[index].points = edit.originalPoints.map { point in
                CGPoint(x: min(max(point.x + dx, 0), 1), y: min(max(point.y + dy, 0), 1))
            }
        case .resize:
            guard !edit.originalPoints.isEmpty else { return }
            if annotations[index].points.count >= 2 {
                var points = edit.originalPoints
                points[1] = CGPoint(x: min(max(points[1].x + dx, 0), 1), y: min(max(points[1].y + dy, 0), 1))
                annotations[index].points = points
            } else if let first = edit.originalPoints.first {
                annotations[index].lineWidth = max(1, annotations[index].lineWidth + Double((translation.width + translation.height) / 24))
                annotations[index].points = [first]
            }
        }
    }

    private func editSelectedAnnotation() {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else { return }
        switch annotations[index].kind {
        case .text, .tag, .watermark:
            let alert = NSAlert()
            alert.messageText = localization.string("common.edit")
            alert.addButton(withTitle: localization.string("common.ok"))
            alert.addButton(withTitle: localization.string("common.cancel"))
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
            field.stringValue = annotations[index].text ?? ""
            alert.accessoryView = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            pushUndoState()
            annotations[index].text = field.stringValue
        default:
            pushUndoState()
            annotations[index].color = selectedColor.codableColor
            annotations[index].lineWidth = selectedLineWidth.value
        }
    }

    private func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        pushUndoState()
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    private func addTextAnnotation(at point: CGPoint, isTag: Bool) {
        let alert = NSAlert()
        alert.messageText = localization.string(isTag ? "screenshot.tagText" : "screenshot.text")
        alert.addButton(withTitle: localization.string("common.ok"))
        alert.addButton(withTitle: localization.string("common.cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        field.placeholderString = localization.string(isTag ? "screenshot.tagText" : "screenshot.text")
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        markEditingStarted()
        pushUndoState()
        annotations.append(ScreenshotAnnotation(
            kind: isTag ? .tag : .text,
            points: [point],
            color: selectedColor.codableColor,
            lineWidth: selectedLineWidth.value,
            text: text
        ))
    }

    private func beginWatermarkEditing() {
        draftWatermarkText = watermarkText
        draftWatermarkOpacity = watermarkOpacity
        isWatermarkEditorPresented = true
        showWatermarkPanel()
    }

    private func commitWatermark() {
        guard let watermark = draftWatermarkAnnotation else { return }
        markEditingStarted()
        pushUndoState()
        watermarkText = watermark.text ?? watermarkText
        watermarkOpacity = watermark.color.alpha
        annotations.append(watermark)
        isWatermarkEditorPresented = false
        watermarkPanel?.close()
        watermarkPanel = nil
    }

    private func cancelWatermarkEditing() {
        isWatermarkEditorPresented = false
        watermarkPanel?.close()
        watermarkPanel = nil
    }

    private func showWatermarkPanel() {
        if let watermarkPanel {
            watermarkPanel.orderFrontRegardless()
            return
        }

        let panel = WatermarkEditorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 178),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = localization.string("screenshot.watermark")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.onClose = {
            isWatermarkEditorPresented = false
            watermarkPanel = nil
        }
        panel.contentView = NSHostingView(rootView: WatermarkEditorPanelView(
            localization: localization,
            text: $draftWatermarkText,
            opacity: $draftWatermarkOpacity,
            onCommit: commitWatermark,
            onCancel: cancelWatermarkEditing
        ))

        if let parentFrame = NSApp.keyWindow?.frame {
            panel.setFrameOrigin(NSPoint(x: parentFrame.midX - 220, y: parentFrame.midY - 89))
        } else {
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: mouse.x - 220, y: mouse.y - 89))
        }

        watermarkPanel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
        selectedAnnotationID = nil
        draftAnnotation = nil
        drawingPoints = []
        activeAnnotationEdit = nil
        isWatermarkEditorPresented = false
        watermarkPanel?.close()
        watermarkPanel = nil
    }

    private func copyImageAndClose() {
        commitActiveTextEdit()
        let output = renderedImage()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([output])
        NSApp.keyWindow?.close()
    }

    private func saveImage() {
        commitActiveTextEdit()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = localization.string("screenshot.defaultFileName")

        guard panel.runModal() == .OK, let url = panel.url,
              let data = renderedImage().pngData else { return }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pinScreenshot() {
        let output = renderedImage()
        let editorWindow = NSApp.keyWindow
        var pinnedWindow: PinnedScreenshotWindow!
        let pinnedSize = output.size
        let pinnedOrigin: NSPoint
        if let editorFrame = editorWindow?.frame {
            pinnedOrigin = NSPoint(x: editorFrame.minX, y: editorFrame.maxY - pinnedSize.height)
        } else {
            pinnedOrigin = NSEvent.mouseLocation
        }
        let hostingView = NSHostingView(rootView: PinnedScreenshotView(image: output) {
            pinnedWindow.close()
        }.frame(width: pinnedSize.width, height: pinnedSize.height))
        hostingView.frame = NSRect(origin: .zero, size: pinnedSize)
        pinnedWindow = PinnedScreenshotWindow(
            contentRect: NSRect(origin: pinnedOrigin, size: pinnedSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        pinnedWindow.contentView = hostingView
        pinnedWindow.setContentSize(pinnedSize)
        pinnedWindow.minSize = pinnedSize
        pinnedWindow.isFloatingPanel = true
        pinnedWindow.level = .floating
        pinnedWindow.backgroundColor = .clear
        pinnedWindow.isOpaque = false
        pinnedWindow.isMovableByWindowBackground = true
        pinnedWindow.hasShadow = true
        pinnedWindow.title = localization.string("screenshot.pin")
        pinnedWindow.orderFrontRegardless()
        editorWindow?.close()
    }

    private func runOCR() {
        isRecognizing = true
        errorMessage = nil

        Task {
            do {
                let result = try await ocrManager.recognizeText(
                    image: renderedImage(),
                    languages: settings.ocrLanguagePreference.recognitionLanguages
                )
                await MainActor.run {
                    showOCRWindow(text: result.fullText)
                    isRecognizing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRecognizing = false
                }
            }
        }
    }

    private func showOCRWindow(text: String) {
        ocrWindow?.close()
        let window = OCRTextWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.onClose = { ocrWindow = nil }
        window.contentView = NSHostingView(rootView: OCRTextFloatingView(
            localization: localization,
            initialText: text,
            onClose: { window.close() }
        ))

        if let frame = NSApp.keyWindow?.frame {
            window.setFrameOrigin(NSPoint(x: frame.minX, y: frame.maxY - 300))
        } else {
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: mouse.x - 210, y: mouse.y - 150))
        }
        ocrWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func translateImageText() {
        isRecognizing = true
        errorMessage = nil
        let target = selectedTranslationTarget ?? ScreenshotTranslationTarget.defaultTarget(for: localization.language)

        Task {
            do {
                let result = try await ocrManager.recognizeText(
                    image: renderedImage(),
                    languages: settings.ocrLanguagePreference.recognitionLanguages
                )
                let response = try await ScreenshotTextTranslationService.translate(
                    result.fullText,
                    target: target
                )
                await MainActor.run {
                    showOCRWindow(text: response)
                    isRecognizing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRecognizing = false
                }
            }
        }
    }

    private func detectQRCode() {
        guard let cgImage = renderedImage().cgImage else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let values = (request.results ?? []).compactMap(\.payloadStringValue)
            if !values.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(values.joined(separator: "\n"), forType: .string)
            }
            let alert = NSAlert()
            alert.messageText = localization.string("screenshot.detectQRCode")
            alert.informativeText = values.isEmpty ? localization.string("screenshot.noQRCode") : localization.string("screenshot.qrCopied")
            alert.addButton(withTitle: localization.string("common.ok"))
            alert.runModal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renderedImage() -> NSImage {
        ScreenshotRenderer.render(base: currentBaseImage(), annotations: renderAnnotations)
    }

    private func currentBaseImage() -> NSImage {
        guard let screenImage, sourceScreenFrame != nil, let displayRect else { return image }
        return screenImage.croppedFromTopLeftRect(displayRect) ?? image
    }

    private func currentImageRect(in size: CGSize) -> CGRect {
        if let displayRect {
            return displayRect
        }
        return fittedImageRect(in: size)
    }

    private var canvasSizeForLayout: CGSize? {
        sourceScreenFrame?.size ?? previewScreenFrame?.size
    }

    @ViewBuilder
    private func dimmedBackground(imageRect: CGRect, canvasSize: CGSize) -> some View {
        if imageRect.width < canvasSize.width || imageRect.height < canvasSize.height {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addRect(imageRect)
            }
            .fill(Color.black.opacity(0.25), style: FillStyle(eoFill: true))
        } else {
            Color.clear
        }
    }

    private func sourceCanvasRect(in size: CGSize) -> CGRect? {
        guard let sourceRect, let sourceScreenFrame else { return nil }
        return CGRect(
            x: sourceRect.minX - sourceScreenFrame.minX,
            y: sourceScreenFrame.maxY - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        )
        .intersection(CGRect(origin: .zero, size: size))
    }

    private func fittedImageRect(in size: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let toolbarReserve: CGFloat = sourceRect == nil ? currentToolbarSize.height + 12 : 0
        let availableHeight = max(1, size.height - toolbarReserve)
        let scale = min(size.width / image.size.width, availableHeight / image.size.height)
        let fittedSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (availableHeight - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func moveSelectionGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let displayRect else { return }
                if dragStartDisplayRect == nil {
                    dragStartDisplayRect = displayRect
                }
                isMovingSelection = true
                guard let dragStartDisplayRect else { return }
                let moved = CGRect(
                    x: dragStartDisplayRect.minX + value.translation.width,
                    y: dragStartDisplayRect.minY + value.translation.height,
                    width: dragStartDisplayRect.width,
                    height: dragStartDisplayRect.height
                )
                self.displayRect = clamp(moved, in: CGRect(origin: .zero, size: canvasSize))
            }
            .onEnded { _ in
                if let dragStartDisplayRect, let displayRect {
                    let distance = hypot(displayRect.minX - dragStartDisplayRect.minX, displayRect.minY - dragStartDisplayRect.minY)
                    if distance < 2 {
                        if toolbarPosition == nil, let rect = defaultToolbarRect(for: displayRect) {
                            toolbarPosition = CGPoint(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                dragStartDisplayRect = nil
                isMovingSelection = false
            }
    }

    private func clamp(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let maxX = max(bounds.minX, bounds.maxX - rect.width)
        let maxY = max(bounds.minY, bounds.maxY - rect.height)
        return CGRect(
            x: min(max(rect.minX, bounds.minX), maxX),
            y: min(max(rect.minY, bounds.minY), maxY),
            width: min(rect.width, bounds.width),
            height: min(rect.height, bounds.height)
        )
    }

    private func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - rect.minX) / rect.width, 0), 1),
            y: min(max((point.y - rect.minY) / rect.height, 0), 1)
        )
    }

    private func pushUndoState() {
        undoStack.append(annotations)
        if undoStack.count > 80 {
            undoStack.removeFirst(undoStack.count - 80)
        }
    }
}

private enum ScreenshotEditTool: CaseIterable {
    case rectangle
    case ellipse
    case line
    case arrow
    case freehand
    case text
    case tag
    case mosaic
    case highlight

    var annotationKind: ScreenshotAnnotation.Kind {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .arrow: .arrow
        case .freehand: .freehand
        case .text: .text
        case .tag: .tag
        case .mosaic: .mosaic
        case .highlight: .highlight
        }
    }

    var localizationKey: String {
        switch self {
        case .rectangle: "screenshot.tool.rectangle"
        case .ellipse: "screenshot.tool.ellipse"
        case .line: "screenshot.tool.line"
        case .arrow: "screenshot.tool.arrow"
        case .freehand: "screenshot.tool.freehand"
        case .text: "screenshot.tool.text"
        case .tag: "screenshot.tool.tag"
        case .mosaic: "screenshot.tool.mosaic"
        case .highlight: "screenshot.tool.highlight"
        }
    }

    var usesStrokeStyle: Bool {
        switch self {
        case .rectangle, .ellipse, .line, .arrow, .freehand:
            return true
        case .text, .tag, .mosaic, .highlight:
            return false
        }
    }
}

private enum ScreenshotTranslationTarget: String, CaseIterable, Identifiable {
    case english
    case simplifiedChinese
    case traditionalChinese
    case french
    case spanish
    case russian
    case arabic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .french:
            return "Français"
        case .spanish:
            return "Español"
        case .russian:
            return "Русский"
        case .arabic:
            return "العربية"
        }
    }

    var prompt: String {
        "Translate the following OCR text into \(promptLanguageName). Return only the translated text."
    }

    var languageCode: String {
        switch self {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-CN"
        case .traditionalChinese:
            return "zh-TW"
        case .french:
            return "fr"
        case .spanish:
            return "es"
        case .russian:
            return "ru"
        case .arabic:
            return "ar"
        }
    }

    private var promptLanguageName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .traditionalChinese:
            return "Traditional Chinese"
        case .french:
            return "French"
        case .spanish:
            return "Spanish"
        case .russian:
            return "Russian"
        case .arabic:
            return "Arabic"
        }
    }

    static func defaultTarget(for appLanguage: AppLanguage) -> ScreenshotTranslationTarget {
        switch appLanguage {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
        }
    }
}

private enum ScreenshotTextTranslationError: LocalizedError {
    case emptyText
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "No text was recognized for translation."
        case .invalidResponse:
            return "The translation service returned an unexpected response."
        }
    }
}

private enum ScreenshotTextTranslationService {
    static func translate(_ text: String, target: ScreenshotTranslationTarget) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScreenshotTextTranslationError.emptyText }

        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target.languageCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components?.url else { throw ScreenshotTextTranslationError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw ScreenshotTextTranslationError.invalidResponse
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [Any] else {
            throw ScreenshotTextTranslationError.invalidResponse
        }

        let translated = sentences.compactMap { item -> String? in
            guard let parts = item as? [Any] else { return nil }
            return parts.first as? String
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translated.isEmpty else { throw ScreenshotTextTranslationError.invalidResponse }
        return translated
    }
}

struct ScreenshotToolbarPlacement {
    enum Horizontal {
        case leading
        case trailing
    }

    enum Vertical {
        case top
        case bottom
    }

    var horizontal: Horizontal
    var vertical: Vertical

    static let bottomTrailing = ScreenshotToolbarPlacement(horizontal: .trailing, vertical: .bottom)

    var alignment: Alignment {
        switch (horizontal, vertical) {
        case (.leading, .top): return .topLeading
        case (.trailing, .top): return .topTrailing
        case (.leading, .bottom): return .bottomLeading
        case (.trailing, .bottom): return .bottomTrailing
        }
    }
}

private struct ActiveTextEdit {
    var annotation: ScreenshotAnnotation
    var text: String
}

private enum AnnotationLineWidth: CaseIterable, Identifiable {
    case thin
    case medium
    case thick

    var id: Self { self }

    var value: Double {
        switch self {
        case .thin: return 2
        case .medium: return 5
        case .thick: return 9
        }
    }

    var dotDiameter: CGFloat {
        CGFloat(value)
    }
}

private struct AnnotationColorSwatch: Identifiable {
    var id: String { name }
    var name: String
    var color: Color

    static let swatches: [AnnotationColorSwatch] = [
        AnnotationColorSwatch(name: "red", color: .red),
        AnnotationColorSwatch(name: "white", color: .white),
        AnnotationColorSwatch(name: "blue", color: .blue),
        AnnotationColorSwatch(name: "green", color: .green),
        AnnotationColorSwatch(name: "yellow", color: .yellow),
        AnnotationColorSwatch(name: "black", color: .black),
        AnnotationColorSwatch(name: "gray", color: .gray)
    ]
}

private struct ScreenshotPreviewKeyboardView: NSViewRepresentable {
    let onEscape: () -> Void
    let onUndo: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> ScreenshotPreviewKeyboardNSView {
        let view = ScreenshotPreviewKeyboardNSView()
        view.onEscape = onEscape
        view.onUndo = onUndo
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: ScreenshotPreviewKeyboardNSView, context: Context) {
        nsView.onEscape = onEscape
        nsView.onUndo = onUndo
        nsView.onDelete = onDelete
    }
}

private final class ScreenshotPreviewKeyboardNSView: NSView {
    var onEscape: (() -> Void)?
    var onUndo: (() -> Void)?
    var onDelete: (() -> Void)?
    private var localMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func installMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.onEscape?()
                return nil
            }
            if Int(event.keyCode) == kVK_ANSI_Z, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                self.onUndo?()
                return nil
            }
            if Int(event.keyCode) == kVK_Delete || Int(event.keyCode) == kVK_ForwardDelete {
                self.onDelete?()
                return nil
            }
            return event
        }
    }
}

private struct ToolbarTooltipAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ToolbarTooltipModifier: ViewModifier {
    let titleKey: String
    @Binding var hoveredToolNameKey: String?
    @ObservedObject var localization: LocalizationManager

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoveredToolNameKey = hovering ? titleKey : nil
            }
            .anchorPreference(key: ToolbarTooltipAnchorKey.self, value: .bounds) { [titleKey: $0] }
            .zIndex(hoveredToolNameKey == titleKey ? 1 : 0)
    }
}

private extension NSImage {
    func croppedFromTopLeftRect(_ rect: CGRect) -> NSImage? {
        guard rect.width > 0, rect.height > 0, size.width > 0, size.height > 0 else { return nil }
        let sourceRect = NSRect(
            x: rect.minX,
            y: size.height - rect.maxY,
            width: min(rect.width, size.width - rect.minX),
            height: min(rect.height, size.height - (size.height - rect.maxY))
        ).intersection(NSRect(origin: .zero, size: size))
        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }

        let output = NSImage(size: sourceRect.size)
        output.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: sourceRect.size),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        return output
    }
}

private extension View {
    func toolbarTooltip(_ titleKey: String, hoveredToolNameKey: Binding<String?>, localization: LocalizationManager) -> some View {
        modifier(ToolbarTooltipModifier(titleKey: titleKey, hoveredToolNameKey: hoveredToolNameKey, localization: localization))
    }
}

private struct WatermarkEditorPanelView: View {
    @ObservedObject var localization: LocalizationManager
    @Binding var text: String
    @Binding var opacity: Double
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.string("screenshot.watermark"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
            }

            TextField(localization.string("screenshot.watermarkText"), text: $text)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(localization.string("screenshot.watermarkOpacity"))
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(opacity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $opacity, in: 0.08...0.8)
                    .help(localization.string("screenshot.watermarkOpacityHelp"))
            }

            HStack {
                Text(localization.string("screenshot.watermarkOpacityHelp"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(localization.string("common.cancel"), action: onCancel)
                Button(localization.string("common.ok"), action: onCommit)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private final class WatermarkEditorPanel: NSPanel {
    var onClose: (() -> Void)?
    private var localEscapeMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installEscapeMonitor()
    }

    override func close() {
        removeEscapeMonitor()
        let callback = onClose
        onClose = nil
        super.close()
        callback?()
    }

    private func installEscapeMonitor() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, Int(event.keyCode) == kVK_Escape else { return event }
            self.close()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }
}

private struct OCRTextFloatingView: View {
    @ObservedObject var localization: LocalizationManager
    @State var text: String
    @State private var isEditable = false
    let onClose: () -> Void

    init(localization: LocalizationManager, initialText: String, onClose: @escaping () -> Void) {
        self.localization = localization
        self._text = State(initialValue: initialText)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Spacer()
                Button(localization.string("common.edit")) {
                    isEditable.toggle()
                }
                Button(localization.string("common.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .padding(12)
        }
        .frame(width: 420, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private final class OCRTextWindow: NSPanel {
    var onClose: (() -> Void)?
    private var localEscapeMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installEscapeMonitor()
    }

    override func close() {
        removeEscapeMonitor()
        let callback = onClose
        onClose = nil
        super.close()
        callback?()
    }

    private func installEscapeMonitor() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, Int(event.keyCode) == kVK_Escape else { return event }
            self.close()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }
}

private struct PinnedScreenshotView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: image.size.width, height: image.size.height)

            PinnedWindowDragView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .background(Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct PinnedWindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> PinnedWindowDragNSView {
        PinnedWindowDragNSView()
    }

    func updateNSView(_ nsView: PinnedWindowDragNSView, context: Context) {}
}

private final class PinnedWindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class PinnedScreenshotWindow: NSPanel {
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
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

private struct AnnotationHit {
    var annotation: ScreenshotAnnotation
    var mode: AnnotationEditMode
}

private struct AnnotationEditState {
    var id: UUID
    var originalPoints: [CGPoint]
    var mode: AnnotationEditMode
}

private enum AnnotationEditMode {
    case move
    case resize
}

private struct ScreenshotAnnotation: Identifiable {
    enum Kind {
        case rectangle
        case ellipse
        case line
        case arrow
        case freehand
        case text
        case tag
        case mosaic
        case highlight
        case watermark
    }

    var id = UUID()
    var kind: Kind
    var points: [CGPoint]
    var color: CodableColor
    var lineWidth: Double
    var text: String?
}

private struct CodableColor {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct ScreenshotAnnotationOverlay: View {
    let annotations: [ScreenshotAnnotation]
    let selectedID: UUID?
    let canvasRect: CGRect

    var body: some View {
        ZStack {
            ForEach(annotations) { annotation in
                annotationView(annotation)
                if annotation.id == selectedID, let rect = annotation.selectionRect(in: canvasRect) {
                    Rectangle()
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                        .position(x: rect.maxX, y: rect.maxY)
                }
            }
        }
    }

    @ViewBuilder
    private func annotationView(_ annotation: ScreenshotAnnotation) -> some View {
        switch annotation.kind {
        case .rectangle:
            if let rect = annotation.rect(in: canvasRect) {
                Rectangle()
                    .stroke(annotation.color.swiftUIColor, lineWidth: annotation.lineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        case .ellipse:
            if let rect = annotation.rect(in: canvasRect) {
                Ellipse()
                    .stroke(annotation.color.swiftUIColor, lineWidth: annotation.lineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        case .line, .arrow, .freehand:
            Path { path in
                let points = annotation.points.map { annotation.denormalize($0, in: canvasRect) }
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(annotation.color.swiftUIColor, style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round))
            if annotation.kind == .arrow, let end = annotation.points.last, let before = annotation.points.dropLast().last {
                ArrowHeadView(start: annotation.denormalize(before, in: canvasRect), end: annotation.denormalize(end, in: canvasRect), color: annotation.color.swiftUIColor)
            }
        case .text:
            if let text = annotation.text, let rect = annotation.rect(in: canvasRect) {
                Text(text)
                    .font(.system(size: max(14, annotation.lineWidth * 5), weight: .semibold))
                    .foregroundStyle(annotation.color.swiftUIColor)
                    .multilineTextAlignment(.leading)
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .position(x: rect.midX, y: rect.midY)
            } else if let point = annotation.points.first, let text = annotation.text {
                Text(text)
                    .font(.system(size: max(14, annotation.lineWidth * 5), weight: .semibold))
                    .foregroundStyle(annotation.color.swiftUIColor)
                    .position(annotation.denormalize(point, in: canvasRect))
            }
        case .tag:
            if let point = annotation.points.first, let text = annotation.text {
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(annotation.color.swiftUIColor, in: Capsule())
                    .position(annotation.denormalize(point, in: canvasRect))
            }
        case .mosaic:
            if let rect = annotation.rect(in: canvasRect) {
                MosaicView(color: annotation.color.swiftUIColor)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        case .highlight:
            if let rect = annotation.rect(in: canvasRect) {
                HighlightView(canvasRect: canvasRect, highlightRect: rect)
            }
        case .watermark:
            if let text = annotation.text {
                WatermarkPatternView(text: text, color: annotation.color.swiftUIColor)
                    .frame(width: canvasRect.width, height: canvasRect.height)
                    .position(x: canvasRect.midX, y: canvasRect.midY)
                    .mask(
                        Rectangle()
                            .frame(width: canvasRect.width, height: canvasRect.height)
                            .position(x: canvasRect.midX, y: canvasRect.midY)
                    )
            }
        }
    }
}

private struct WatermarkPatternView: View {
    let text: String
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let columns = stride(from: -geometry.size.width, through: geometry.size.width * 2, by: max(180, textWidth)).map { $0 }
            let rows = stride(from: -geometry.size.height, through: geometry.size.height * 2, by: 110).map { $0 }
            ZStack {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, y in
                    ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, x in
                        Text(text)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(color)
                            .rotationEffect(.degrees(-28))
                            .position(x: x + (rowIndex.isMultiple(of: 2) ? 0 : 90) + CGFloat(columnIndex % 2) * 10, y: y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var textWidth: CGFloat {
        CGFloat(max(text.count, 4)) * 24
    }
}

private struct ArrowHeadView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        Path { path in
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length: CGFloat = 16
            let left = CGPoint(x: end.x - cos(angle - .pi / 6) * length, y: end.y - sin(angle - .pi / 6) * length)
            let right = CGPoint(x: end.x - cos(angle + .pi / 6) * length, y: end.y - sin(angle + .pi / 6) * length)
            path.move(to: end)
            path.addLine(to: left)
            path.move(to: end)
            path.addLine(to: right)
        }
        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}

private struct MosaicView: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let block: CGFloat = 12
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let opacity = ((Int(x / block) + Int(y / block)).isMultiple(of: 2)) ? 0.55 : 0.32
                    context.fill(Path(CGRect(x: x, y: y, width: block, height: block)), with: .color(color.opacity(opacity)))
                    x += block
                }
                y += block
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(Rectangle())
    }
}

private struct HighlightView: View {
    let canvasRect: CGRect
    let highlightRect: CGRect

    var body: some View {
        Path { path in
            path.addRect(canvasRect)
            path.addRect(highlightRect)
        }
        .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
    }
}

private enum ScreenshotRenderer {
    static func render(base image: NSImage, annotations: [ScreenshotAnnotation]) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        for annotation in annotations {
            draw(annotation, imageSize: image.size)
        }
        output.unlockFocus()
        return output
    }

    private static func draw(_ annotation: ScreenshotAnnotation, imageSize: CGSize) {
        let color = annotation.color.nsColor
        color.setStroke()
        color.setFill()
        let lineWidth = CGFloat(annotation.lineWidth)

        switch annotation.kind {
        case .rectangle:
            guard let rect = annotation.rect(in: CGRect(origin: .zero, size: imageSize)).flipped(in: imageSize) else { return }
            let path = NSBezierPath(rect: rect)
            path.lineWidth = lineWidth
            path.stroke()
        case .ellipse:
            guard let rect = annotation.rect(in: CGRect(origin: .zero, size: imageSize)).flipped(in: imageSize) else { return }
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = lineWidth
            path.stroke()
        case .line, .arrow, .freehand:
            let points = annotation.points.map { annotation.denormalize($0, in: CGRect(origin: .zero, size: imageSize)).flipped(in: imageSize) }
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            if annotation.kind == .arrow, let end = points.last, let before = points.dropLast().last {
                drawArrowHead(from: before, to: end, color: color)
            }
        case .text:
            drawText(annotation.text, annotation: annotation, imageSize: imageSize, color: color, fontSize: max(16, lineWidth * 5))
        case .tag:
            drawTag(annotation.text, at: annotation.points.first, imageSize: imageSize, color: color)
        case .mosaic:
            guard let rect = annotation.rect(in: CGRect(origin: .zero, size: imageSize)).flipped(in: imageSize) else { return }
            drawMosaic(rect: rect, color: color)
        case .highlight:
            guard let rect = annotation.rect(in: CGRect(origin: .zero, size: imageSize)).flipped(in: imageSize) else { return }
            NSColor.black.withAlphaComponent(0.48).setFill()
            let outer = NSBezierPath(rect: NSRect(origin: .zero, size: imageSize))
            outer.append(NSBezierPath(rect: rect))
            outer.windingRule = .evenOdd
            outer.fill()
        case .watermark:
            drawWatermark(annotation.text, imageSize: imageSize, color: color)
        }
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, color: NSColor) {
        color.setStroke()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 18
        let left = CGPoint(x: end.x - cos(angle - .pi / 6) * length, y: end.y - sin(angle - .pi / 6) * length)
        let right = CGPoint(x: end.x - cos(angle + .pi / 6) * length, y: end.y - sin(angle + .pi / 6) * length)
        let path = NSBezierPath()
        path.move(to: end)
        path.line(to: left)
        path.move(to: end)
        path.line(to: right)
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func drawText(_ text: String?, annotation: ScreenshotAnnotation, imageSize: CGSize, color: NSColor, fontSize: CGFloat) {
        guard let text else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
        let string = NSString(string: text)
        let imageRect = CGRect(origin: .zero, size: imageSize)
        if let rect = annotation.rect(in: imageRect).flipped(in: imageSize) {
            string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        } else if let point = annotation.points.first {
            let destination = CGPoint(x: point.x * imageSize.width, y: (1 - point.y) * imageSize.height)
            let size = string.size(withAttributes: attributes)
            string.draw(at: CGPoint(x: destination.x - size.width / 2, y: destination.y - size.height / 2), withAttributes: attributes)
        }
    }

    private static func drawWatermark(_ text: String?, imageSize: CGSize, color: NSColor) {
        guard let text, !text.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let fontSize: CGFloat = 48
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color
        ]
        let string = NSString(string: text)
        let size = string.size(withAttributes: attributes)
        let columnStep = max(size.width + 110, 260)
        let rowStep: CGFloat = 150

        var row = 0
        var y = -imageSize.height
        while y <= imageSize.height * 2 {
            var x = -imageSize.width + (row.isMultiple(of: 2) ? 0 : columnStep / 2)
            while x <= imageSize.width * 2 {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: x, yBy: y)
                transform.rotate(byDegrees: -28)
                transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
                transform.concat()
                string.draw(at: .zero, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
                x += columnStep
            }
            row += 1
            y += rowStep
        }
    }

    private static func drawTag(_ text: String?, at point: CGPoint?, imageSize: CGSize, color: NSColor) {
        guard let text, let point else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let string = NSString(string: text)
        let textSize = string.size(withAttributes: attributes)
        let origin = CGPoint(
            x: point.x * imageSize.width - textSize.width / 2 - 10,
            y: (1 - point.y) * imageSize.height - textSize.height / 2 - 5
        )
        let rect = NSRect(x: origin.x, y: origin.y, width: textSize.width + 20, height: textSize.height + 10)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        string.draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 5), withAttributes: attributes)
    }

    private static func drawMosaic(rect: CGRect, color: NSColor) {
        let block: CGFloat = 14
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                color.withAlphaComponent(((Int(x / block) + Int(y / block)).isMultiple(of: 2)) ? 0.55 : 0.32).setFill()
                NSRect(x: x, y: y, width: block, height: block).fill()
                x += block
            }
            y += block
        }
    }
}

private extension ScreenshotAnnotation {
    func rect(in canvas: CGRect) -> CGRect? {
        guard points.count >= 2 else { return nil }
        let a = denormalize(points[0], in: canvas)
        let b = denormalize(points[1], in: canvas)
        return CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    func denormalize(_ point: CGPoint, in canvas: CGRect) -> CGPoint {
        CGPoint(x: canvas.minX + point.x * canvas.width, y: canvas.minY + point.y * canvas.height)
    }

    func selectionRect(in canvas: CGRect) -> CGRect? {
        switch kind {
        case .rectangle, .ellipse, .mosaic, .highlight, .line, .arrow:
            return rect(in: canvas)?.insetBy(dx: -6, dy: -6)
        case .freehand:
            let denormalized = points.map { denormalize($0, in: canvas) }
            guard let first = denormalized.first else { return nil }
            return denormalized.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }.insetBy(dx: -8, dy: -8)
        case .text, .tag, .watermark:
            if kind == .text, let rect = rect(in: canvas) {
                return rect.insetBy(dx: -6, dy: -6)
            }
            guard let point = points.first else { return nil }
            let center = denormalize(point, in: canvas)
            let textWidth = CGFloat(max(text?.count ?? 4, 4)) * 12
            return CGRect(x: center.x - textWidth / 2, y: center.y - 18, width: textWidth, height: 36).insetBy(dx: -6, dy: -6)
        }
    }

    func resizeHandle(in canvas: CGRect) -> CGRect {
        guard let rect = selectionRect(in: canvas) else { return .null }
        return CGRect(x: rect.maxX - 10, y: rect.maxY - 10, width: 20, height: 20)
    }

    func contains(_ point: CGPoint, in canvas: CGRect) -> Bool {
        let tolerance = max(CGFloat(lineWidth) / 2 + 5, 7)
        switch kind {
        case .rectangle, .mosaic, .highlight:
            guard let rect = rect(in: canvas) else { return false }
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && !inner.contains(point)
        case .ellipse:
            guard let rect = rect(in: canvas), rect.width > 0, rect.height > 0 else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let rx = rect.width / 2
            let ry = rect.height / 2
            let normalized = pow((point.x - center.x) / rx, 2) + pow((point.y - center.y) / ry, 2)
            let toleranceRatio = tolerance / max(min(rx, ry), 1)
            return abs(normalized - 1) <= toleranceRatio
        case .line, .arrow, .freehand:
            let denormalized = points.map { denormalize($0, in: canvas) }
            guard denormalized.count >= 2 else { return false }
            return zip(denormalized, denormalized.dropFirst()).contains { start, end in
                point.distanceToSegment(start: start, end: end) <= tolerance
            }
        case .text:
            guard let rect = rect(in: canvas) else { return false }
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .tag, .watermark:
            guard let rect = selectionRect(in: canvas) else { return false }
            return rect.contains(point)
        }
    }
}

private extension Optional where Wrapped == CGRect {
    func flipped(in size: CGSize) -> CGRect? {
        guard let self else { return nil }
        return CGRect(x: self.minX, y: size.height - self.maxY, width: self.width, height: self.height)
    }
}

private extension CGPoint {
    func flipped(in size: CGSize) -> CGPoint {
        CGPoint(x: x, y: size.height - y)
    }

    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else {
            return hypot(x - start.x, y - start.y)
        }
        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(x - projection.x, y - projection.y)
    }
}

private extension Color {
    var codableColor: CodableColor {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? .systemCyan
        return CodableColor(red: nsColor.redComponent, green: nsColor.greenComponent, blue: nsColor.blueComponent, alpha: nsColor.alphaComponent)
    }
}

private extension Optional where Wrapped == [ScreenshotAnnotation] {
    var orEmpty: [ScreenshotAnnotation] { self ?? [] }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    var cgImage: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
