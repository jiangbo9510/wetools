import AppKit
import ApplicationServices
import AVKit
import Carbon
import SwiftUI

@MainActor
final class ScreenshotManager {
    private let settings: AppSettings
    private let localization: LocalizationManager
    private let providerStore: LLMProviderStore
    private let screenshotService = ScreenCaptureScreenshotService()
    private lazy var scrollDriver = ScrollDriver(screenshotService: screenshotService)
    private let imageStitcher = ImageStitcher()
    private lazy var screenRecordingManager = ScreenRecordingManager(settings: settings)
    private let scrollingSession = ScrollingCaptureSession()

    private var actionPanel: NSPanel?
    private var selectionWindow: ScreenshotSelectionWindow?
    private var adjustmentWindow: ScreenshotAdjustmentWindow?
    private var scrollingPanel: NSPanel?
    private var captureOverlayWindow: ScreenshotCaptureOverlayWindow?
    private var scrollingTask: Task<Void, Never>?
    private var scrollingPreviewTask: Task<Void, Never>?
    private var isFinishingScrollingCapture = false
    private var scrollingFrames: [CGImage] = []
    private var scrollingInjectedDisplacements: [Int] = []
    private var scrollingStitchResult: ImageStitchResult?
    private var scrollingCaptureSign = 0
    private var recordingPanel: NSPanel?
    private var recordingCountdownWindow: NSPanel?
    private var recordingTimerWindow: NSPanel?
    private var recordingProcessingWindow: NSPanel?
    private var recordingStartTask: Task<Void, Never>?
    private var recordingFinishTask: Task<Void, Never>?
    private var recordingPreviewWindowController: NSWindowController?
    private var previewWindowController: NSWindowController?
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?
    private var retiredWindows: [NSWindow] = []

    init(settings: AppSettings, localization: LocalizationManager, providerStore: LLMProviderStore) {
        self.settings = settings
        self.localization = localization
        self.providerStore = providerStore
    }

    func showActionPanel() {
        closeActionPanel()
        installEscapeMonitors()

        let view = ScreenshotActionPanelView(
            localization: localization,
            onScreenshot: { [weak self] in
                self?.closeActionPanel()
                self?.startAreaCapture()
            },
            onFullScreen: { [weak self] in
                self?.closeActionPanel()
                self?.captureFullScreen()
            },
            onScrollingScreenshot: { [weak self] in
                self?.closeActionPanel()
                self?.startScrollingCaptureSelection()
            },
            onRecording: { [weak self] in
                self?.closeActionPanel()
                self?.startRecordingSelection()
            },
            onOCR: { [weak self] in
                self?.closeActionPanel()
                self?.startAreaCapture()
            },
            onCancel: { [weak self] in
                self?.closeActionPanel()
            }
        )

        let panel = ScreenshotFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
            styleMask: [.hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(NSSize(width: max(300, fittingSize.width), height: max(56, fittingSize.height)))

        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - 90))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        actionPanel = panel
    }

    func startCaptureTool() {
        guard requestScreenCapturePermissionIfNeeded() else { return }
        installEscapeMonitors()
        guard let screen = NSScreen.main else { return }
        let window = ScreenshotSelectionWindow(screen: screen, localization: localization, showsModeSelector: true) { [weak self] mode, screen, rect in
            self?.finishSelectionWindow()
            guard let self, let screen, let rect else { return }
            switch mode {
            case .screenshot:
                self.captureArea(on: screen, rect: rect)
            case .scrolling:
                self.showScrollingPanel(screen: screen, rect: rect)
            case .recording:
                self.showRecordingPanel(screen: screen, rect: rect)
            }
        }
        showSelectionWindow(window)
    }

    func startAreaCapture() {
        guard requestScreenCapturePermissionIfNeeded() else { return }
        installEscapeMonitors()
        guard let screen = NSScreen.main else { return }
        let window = ScreenshotSelectionWindow(screen: screen, localization: localization) { [weak self] _, screen, rect in
            self?.finishSelectionWindow()
            guard let screen, let rect else { return }
            self?.captureArea(on: screen, rect: rect)
        }
        showSelectionWindow(window)
    }

    func captureFullScreen() {
        guard requestScreenCapturePermissionIfNeeded() else { return }
        guard let screen = NSScreen.main else {
            showCaptureError(ScreenCaptureScreenshotError.displayNotFound)
            return
        }

        Task { @MainActor in
            do {
                let image = try await screenshotService.captureFullScreen(on: screen)
                openPreview(image: image, sourceRect: screen.frame)
            } catch {
                showCaptureError(error)
            }
        }
    }

    private func startScrollingCaptureSelection() {
        guard requestScreenCapturePermissionIfNeeded() else { return }
        installEscapeMonitors()
        guard let screen = NSScreen.main else { return }
        let window = ScreenshotSelectionWindow(screen: screen, localization: localization, initialMode: .scrolling) { [weak self] _, screen, rect in
            self?.finishSelectionWindow()
            guard let self, let screen, let rect else { return }
            self.showScrollingPanel(screen: screen, rect: rect)
        }
        showSelectionWindow(window)
    }

    private func startRecordingSelection() {
        guard requestScreenCapturePermissionIfNeeded() else { return }
        installEscapeMonitors()
        guard let screen = NSScreen.main else { return }
        let window = ScreenshotSelectionWindow(screen: screen, localization: localization, initialMode: .recording) { [weak self] _, screen, rect in
            self?.finishSelectionWindow()
            guard let self, let screen, let rect else { return }
            self.showRecordingPanel(screen: screen, rect: rect)
        }
        showSelectionWindow(window)
    }

    private func showRecordingPanel(screen: NSScreen, rect: NSRect) {
        closeRecordingPanel()
        installEscapeMonitors()
        screenRecordingManager.reset()
        showCaptureOverlay(screen: screen, rect: rect)

        let view = ScreenRecordingControlView(
            manager: screenRecordingManager,
            localization: localization,
            onStart: { [weak self] in
                guard let self else { return }
                self.recordingStartTask?.cancel()
                self.recordingStartTask = Task { @MainActor in
                    defer { self.recordingStartTask = nil }
                    do {
                        try Task.checkCancellation()
                        self.closeRecordingOptionsPanelOnly()
                        try await self.showRecordingCountdown(screen: screen, rect: rect)
                        try Task.checkCancellation()
                        try await self.screenRecordingManager.start(screen: screen, rect: rect)
                        try Task.checkCancellation()
                        self.showRecordingTimer(screen: screen, rect: rect)
                    } catch is CancellationError {
                        await self.screenRecordingManager.cancel()
                        self.closeRecordingTimer()
                    } catch {
                        self.showCaptureError(error)
                        self.screenRecordingManager.reset()
                        self.closeRecordingTimer()
                    }
                }
            },
            onCancel: { [weak self] in
                self?.recordingStartTask?.cancel()
                self?.recordingStartTask = nil
                Task { @MainActor [weak self] in
                    await self?.screenRecordingManager.cancel()
                }
                self?.closeRecordingTimer()
                self?.closeRecordingPanel()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let panelSize = NSSize(
            width: min(max(200, fittingSize.width), screen.visibleFrame.width - 24),
            height: min(max(56, fittingSize.height), screen.visibleFrame.height - 24)
        )
        let availableFrame = screen.visibleFrame
        let panelOrigin = NSPoint(
            x: min(max(rect.midX - panelSize.width / 2, availableFrame.minX + 12), availableFrame.maxX - panelSize.width - 12),
            y: min(max(rect.midY - panelSize.height / 2, availableFrame.minY + 12), availableFrame.maxY - panelSize.height - 12)
        )

        let panel = ScreenshotFloatingPanel(
            contentRect: NSRect(origin: panelOrigin, size: panelSize),
            styleMask: [.hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.makeKeyAndOrderFront(nil)
        recordingPanel = panel
    }

    private func showSelectionWindow(_ window: ScreenshotSelectionWindow) {
        selectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func showRecordingCountdown(screen: NSScreen, rect: NSRect) async throws {
        for value in [3, 2, 1] {
            closeRecordingCountdown()
            let panel = ScreenshotFloatingPanel(
                contentRect: NSRect(x: rect.midX - 48, y: rect.midY - 48, width: 96, height: 96),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.contentView = NSHostingView(rootView: RecordingCountdownView(value: value))
            panel.orderFrontRegardless()
            recordingCountdownWindow = panel
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        closeRecordingCountdown()
    }

    private func showRecordingTimer(screen: NSScreen, rect: NSRect) {
        closeRecordingTimer()
        let panelSize = NSSize(width: 212, height: 42)
        let availableFrame = screen.visibleFrame
        let origin = recordingTimerOrigin(panelSize: panelSize, recordingRect: rect, availableFrame: availableFrame)
        let panel = ScreenshotFloatingPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: RecordingTimerView(
            manager: screenRecordingManager,
            localization: localization,
            onTogglePause: { [weak self] in
                self?.screenRecordingManager.togglePause()
            },
            onStop: { [weak self] in
                self?.finishRecording()
            }
        ))
        panel.orderFrontRegardless()
        recordingTimerWindow = panel
    }

    private func finishRecording() {
        closeRecordingTimer()
        closeCaptureOverlay()
        showRecordingProcessing()
        recordingFinishTask?.cancel()
        recordingFinishTask = Task { @MainActor in
            defer { recordingFinishTask = nil }
            do {
                let result = try await screenRecordingManager.stop()
                try Task.checkCancellation()
                closeRecordingProcessing()
                closeRecordingPanel()
                openRecordingPreview(result)
            } catch is CancellationError {
                closeRecordingProcessing()
                await screenRecordingManager.cancel()
                closeRecordingPanel()
            } catch {
                closeRecordingProcessing()
                screenRecordingManager.reset()
                closeRecordingPanel()
                uninstallEscapeMonitors()
                showCaptureError(error)
            }
        }
    }

    private func showRecordingProcessing() {
        closeRecordingProcessing()
        let panel = ScreenshotFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 72),
            styleMask: [.hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(localization.string("recording.generatingPreview"))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8)))
        panel.center()
        panel.orderFrontRegardless()
        recordingProcessingWindow = panel
    }

    private func closeRecordingProcessing() {
        guard let window = recordingProcessingWindow else { return }
        recordingProcessingWindow = nil
        retireWindow(window)
    }

    private func recordingTimerOrigin(panelSize: NSSize, recordingRect rect: NSRect, availableFrame: NSRect) -> NSPoint {
        let gap: CGFloat = 10
        let margin: CGFloat = 12
        let candidates = [
            NSPoint(x: rect.maxX - panelSize.width, y: rect.maxY + gap),
            NSPoint(x: rect.maxX - panelSize.width, y: rect.minY - panelSize.height - gap),
            NSPoint(x: rect.maxX + gap, y: rect.maxY - panelSize.height),
            NSPoint(x: rect.minX - panelSize.width - gap, y: rect.maxY - panelSize.height)
        ]

        for candidate in candidates {
            let candidateRect = NSRect(origin: candidate, size: panelSize)
            if availableFrame.contains(candidateRect), candidateRect.intersection(rect).isEmpty {
                return candidate
            }
        }

        return NSPoint(
            x: min(max(availableFrame.maxX - panelSize.width - margin, availableFrame.minX + margin), availableFrame.maxX - panelSize.width - margin),
            y: min(max(availableFrame.maxY - panelSize.height - margin, availableFrame.minY + margin), availableFrame.maxY - panelSize.height - margin)
        )
    }

    private func closeRecordingOptionsPanelOnly() {
        closePanelLater(&recordingPanel)
    }

    private func closeRecordingCountdown() {
        guard let window = recordingCountdownWindow else { return }
        recordingCountdownWindow = nil
        retireWindow(window)
    }

    private func closeRecordingTimer() {
        guard let window = recordingTimerWindow else { return }
        recordingTimerWindow = nil
        retireWindow(window)
    }

    private func showScrollingPanel(screen: NSScreen, rect: NSRect) {
        closeScrollingPanel()
        scrollingSession.reset()
        showCaptureOverlay(screen: screen, rect: rect)

        let view = ScrollingScreenshotControlView(
            localization: localization,
            session: scrollingSession,
            onStart: { [weak self] in
                self?.startScrollingCapture(screen: screen, rect: rect)
            },
            onConfirm: { [weak self] in
                self?.finishScrollingCapture(screen: screen, rect: rect, action: .confirm)
            },
            onDownload: { [weak self] in
                self?.finishScrollingCapture(screen: screen, rect: rect, action: .download)
            },
            onEdit: { [weak self] in
                self?.finishScrollingCapture(screen: screen, rect: rect, action: .edit)
            },
            onCancel: { [weak self] in
                self?.cancelScrollingCapture()
            }
        )

        let panelSize = NSSize(width: 430, height: 500)
        let panelOrigin = scrollingPanelOrigin(panelSize: panelSize, selectionRect: rect, availableFrame: screen.visibleFrame)
        let panel = ScreenshotFloatingPanel(
            contentRect: NSRect(origin: panelOrigin, size: panelSize),
            styleMask: [.hudWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        scrollingPanel = panel
    }

    private func startScrollingCapture(screen: NSScreen, rect: NSRect) {
        scrollingTask?.cancel()
        scrollingPreviewTask?.cancel()
        scrollingPreviewTask = nil
        scrollDriver.stop()
        scrollingFrames.removeAll()
        scrollingInjectedDisplacements.removeAll()
        scrollingStitchResult = nil
        scrollingCaptureSign = 0
        isFinishingScrollingCapture = false

        scrollingSession.hasStarted = true
        scrollingSession.isRunning = true
        scrollingSession.isCompleted = false
        scrollingSession.isFailed = false
        scrollingSession.errorMessage = nil
        scrollingTask = Task { @MainActor in
            do {
                let captureResult = try await scrollDriver.capture(screen: screen, rect: rect) { [weak self] progress in
                    self?.handleScrollingProgress(progress, screen: screen)
                }
                try Task.checkCancellation()
                if captureResult.scrollSign != 0 {
                    scrollingCaptureSign = captureResult.scrollSign
                }
                scrollingFrames = orderedScrollingFrames(captureResult.frames)
                scrollingInjectedDisplacements = orderedScrollingDisplacements(captureResult.measuredDisplacements)
                scrollingSession.isRunning = false
                try await updateScrollingPreview(screen: screen, marksCompleted: true)
            } catch is CancellationError {
                scrollingSession.isRunning = false
            } catch let captureFailure as ScrollDriverCaptureFailure {
                scrollingFrames = orderedScrollingFrames(captureFailure.frames)
                scrollingInjectedDisplacements = orderedScrollingDisplacements(
                    captureFailure.estimatedDisplacements
                )
                handleScrollingFailure(captureFailure.code, screen: screen, rect: rect)
            } catch let failure as ScrollingCaptureFailureCode {
                handleScrollingFailure(failure, screen: screen, rect: rect)
            } catch {
                scrollingSession.isRunning = false
                scrollingSession.errorMessage = error.localizedDescription
                showCaptureError(error)
            }
        }
    }

    private func handleScrollingProgress(_ progress: ScrollDriver.Progress, screen: NSScreen) {
        switch progress {
        case .captured(let frame, let measuredDisplacements, let scrollSign, let shouldWarnSlowDown):
            if scrollSign != 0 {
                scrollingCaptureSign = scrollSign
                scrollingSession.scrollSign = scrollSign
            }
            if scrollingCaptureSign < 0 {
                scrollingFrames.append(frame)
            } else {
                scrollingFrames.insert(frame, at: 0)
            }
            scrollingInjectedDisplacements = orderedScrollingDisplacements(measuredDisplacements)
            scrollingSession.frameCount = scrollingFrames.count
            scrollingSession.isInterrupted = false
            scrollingSession.shouldWarnSlowDown = shouldWarnSlowDown
            scrollingSession.errorMessage = shouldWarnSlowDown
                ? localization.string("screenshot.scrollingSlowWarning")
                : nil
            if scrollingFrames.count < 3 {
                scrollingSession.previewImage = scrollingImage(from: frame, scale: screen.backingScaleFactor)
            } else {
                scheduleScrollingPreviewUpdate(screen: screen)
            }
        }
    }

    private func scheduleScrollingPreviewUpdate(screen: NSScreen) {
        guard scrollingPreviewTask == nil else { return }
        let frames = scrollingFrames
        let displacements = scrollingInjectedDisplacements
        let scale = screen.backingScaleFactor
        let stitcher = imageStitcher
        scrollingPreviewTask = Task { @MainActor [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try stitcher.stitch(
                        frames: frames,
                        injectedDisplacements: displacements,
                        backingScaleFactor: scale
                    )
                }.value
                try Task.checkCancellation()
                guard let self else { return }
                self.scrollingPreviewTask = nil
                if self.scrollingFrames.count == frames.count {
                    self.applyScrollingStitchResult(result, scale: scale)
                } else {
                    self.scheduleScrollingPreviewUpdate(screen: screen)
                }
            } catch is CancellationError {
                self?.scrollingPreviewTask = nil
                return
            } catch {
                self?.scrollingPreviewTask = nil
                if let failure = error as? ScrollingCaptureFailureCode {
                    self?.scrollingSession.errorMessage = self?.scrollingFailureMessage(failure)
                }
            }
        }
    }

    private func updateScrollingPreview(screen: NSScreen, marksCompleted: Bool) async throws {
        scrollingPreviewTask?.cancel()
        guard scrollingFrames.count >= 3 else {
            scrollingSession.isCompleted = false
            scrollingSession.errorMessage = localization.string("screenshot.scrollingNoMovement")
            return
        }
        let frames = scrollingFrames
        let displacements = scrollingInjectedDisplacements
        let scale = screen.backingScaleFactor
        let stitcher = imageStitcher
        let result = try await Task.detached(priority: .userInitiated) {
            try stitcher.stitch(
                frames: frames,
                injectedDisplacements: displacements,
                backingScaleFactor: scale
            )
        }.value
        applyScrollingStitchResult(result, scale: scale)
        scrollingSession.isCompleted = marksCompleted
    }

    private func applyScrollingStitchResult(_ result: ImageStitchResult, scale: CGFloat) {
        scrollingStitchResult = result
        scrollingSession.previewImage = scrollingImage(from: result.image, scale: scale)
        scrollingSession.frameCount = scrollingFrames.count
        scrollingSession.errorMessage = nil
        scrollingSession.isInterrupted = false
        for registration in result.registrations {
            let confidence = String(format: "%.3f", registration.confidence)
            print("[ScrollingScreenshot] pair=\(registration.pairIndex) dy=\(registration.displacementY) confidence=\(confidence) fallback=\(registration.usedFallback)")
        }
    }

    private func handleScrollingFailure(
        _ failure: ScrollingCaptureFailureCode,
        screen: NSScreen,
        rect: NSRect
    ) {
        writeScrollingFailureDebug(failure)
        scrollDriver.stop()
        scrollingPreviewTask?.cancel()
        scrollingPreviewTask = nil
        scrollingFrames.removeAll()
        scrollingInjectedDisplacements.removeAll()
        scrollingStitchResult = nil
        scrollingSession.isRunning = false
        scrollingSession.isCompleted = false
        scrollingSession.isFailed = true
        scrollingSession.shouldWarnSlowDown = false
        scrollingSession.previewImage = nil
        scrollingSession.frameCount = 0
        scrollingSession.errorMessage = scrollingFailureMessage(failure)
        isFinishingScrollingCapture = false
        NSSound.beep()

        let alert = NSAlert()
        alert.messageText = localization.string("screenshot.scrollingFailedTitle")
        alert.informativeText = scrollingFailureMessage(failure)
        alert.addButton(withTitle: localization.string("screenshot.retry"))
        alert.addButton(withTitle: localization.string("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            showScrollingPanel(screen: screen, rect: rect)
        }
    }

    private func writeScrollingFailureDebug(_ failure: ScrollingCaptureFailureCode) {
        guard !scrollingFrames.isEmpty else { return }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WetoolsScrollingCapture-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (index, frame) in scrollingFrames.enumerated() {
                let representation = NSBitmapImageRep(cgImage: frame)
                guard let data = representation.representation(
                    using: .png,
                    properties: [.compressionFactor: 1]
                ) else { continue }
                try data.write(
                    to: directory.appendingPathComponent(String(format: "frame_%03d.png", index)),
                    options: .atomic
                )
            }
            let displacementLog = scrollingInjectedDisplacements.enumerated()
                .map { "pair=\($0.offset) dy=\($0.element)" }
                .joined(separator: "\n")
            let diagnosticText: String
            if let report = ScrollingFrameDiagnostics.analyze(
                frames: scrollingFrames,
                estimatedDisplacements: scrollingInjectedDisplacements
            ) {
                let pairLines = report.pairs.map { pair in
                    "pair=\(pair.pairIndex) measuredDy=\(pair.displacementY.map(String.init) ?? "nil") "
                        + "overlap=\(pair.overlapRatio.map { String(format: "%.4f", $0) } ?? "nil") "
                        + "difference=\(pair.difference.map { String(format: "%.4f", $0) } ?? "nil") "
                        + "peakRatio=\(pair.peakRatio.map { String(format: "%.4f", $0) } ?? "nil") "
                        + "estimate=\(pair.estimatedDisplacement.map(String.init) ?? "nil")"
                }.joined(separator: "\n")
                diagnosticText = """
                thresholds=\(report.activeConfig)
                colDiffMin=\(report.columnDifferenceMinimum)
                colDiffMedian=\(report.columnDifferenceMedian)
                colDiffMax=\(report.columnDifferenceMaximum)
                colDiffThreshold=\(report.columnDifferenceThreshold)
                staticColumnRatio=\(report.staticColumnRatio)
                layout=\(String(describing: report.layout))
                layoutError=\(String(describing: report.layoutError))
                \(pairLines)
                """
            } else {
                diagnosticText = "diagnostic=unavailable"
            }
            try """
            failure=\(failure.rawValue)
            frames=\(scrollingFrames.count)
            \(displacementLog)
            \(diagnosticText)
            """
            .write(
                to: directory.appendingPathComponent("registration.log"),
                atomically: true,
                encoding: .utf8
            )
            print("[ScrollingScreenshot] capture debug: \(directory.path)")
        } catch {
            print("[ScrollingScreenshot] unable to write capture debug: \(error.localizedDescription)")
        }
    }

    private func scrollingFailureMessage(_ failure: ScrollingCaptureFailureCode) -> String {
        switch failure {
        case .scrollTooFast:
            return localization.string("screenshot.scrollingTooFastFailed")
        case .directionReversed:
            return localization.string("screenshot.scrollingDirectionChanged")
        case .registrationFailed:
            return localization.string("screenshot.scrollingRegistrationFailed")
        case .layoutAmbiguous:
            return localization.string("screenshot.scrollingLayoutAmbiguous")
        case .internalStitchError:
            return localization.string("screenshot.scrollingInternalStitchError")
        }
    }

    private func scrollingImage(from image: CGImage, scale: CGFloat) -> NSImage {
        let safeScale = max(1, scale)
        return NSImage(
            cgImage: image,
            size: NSSize(width: CGFloat(image.width) / safeScale, height: CGFloat(image.height) / safeScale)
        )
    }

    private func orderedScrollingFrames(_ frames: [CGImage]) -> [CGImage] {
        scrollingCaptureSign <= 0 ? frames : Array(frames.reversed())
    }

    private func orderedScrollingDisplacements(_ displacements: [Int]) -> [Int] {
        scrollingCaptureSign <= 0 ? displacements : Array(displacements.reversed())
    }

    private func finishScrollingCapture(screen: NSScreen, rect: NSRect, action: ScrollingCompletionAction) {
        guard !isFinishingScrollingCapture else { return }
        guard !scrollingFrames.isEmpty else { return }
        isFinishingScrollingCapture = true
        scrollingSession.isRunning = false
        scrollDriver.stop()
        scrollingTask?.cancel()
        scrollingTask = nil
        scrollingPreviewTask?.cancel()
        scrollingPreviewTask = nil

        Task { @MainActor in
            do {
                if scrollingStitchResult == nil {
                    try await updateScrollingPreview(screen: screen, marksCompleted: true)
                }
            } catch {
                isFinishingScrollingCapture = false
                if let failure = error as? ScrollingCaptureFailureCode {
                    handleScrollingFailure(failure, screen: screen, rect: rect)
                } else {
                    showCaptureError(error)
                }
                return
            }
            guard scrollingStitchResult != nil, let image = scrollingSession.previewImage else {
                isFinishingScrollingCapture = false
                showUnsupportedNotice(messageKey: "screenshot.scrollingNoMovement")
                return
            }
            switch action {
            case .confirm:
                copyToPasteboard(image)
            case .download:
                saveScrollingImage(image)
            case .edit:
                openPreview(image: image, previewScreen: screen, usesFullScreenCanvas: true, allowsZoom: true)
            }
            scrollingFrames.removeAll()
            scrollingInjectedDisplacements.removeAll()
            scrollingStitchResult = nil
            isFinishingScrollingCapture = false
            closeScrollingPanel()
        }
    }

    private func cancelScrollingCapture() {
        scrollDriver.stop()
        scrollingTask?.cancel()
        scrollingTask = nil
        scrollingPreviewTask?.cancel()
        scrollingPreviewTask = nil
        isFinishingScrollingCapture = false
        scrollingFrames.removeAll()
        scrollingInjectedDisplacements.removeAll()
        scrollingStitchResult = nil
        scrollingCaptureSign = 0
        scrollingSession.reset()
        closeScrollingPanel()
    }

    private func saveScrollingImage(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = localization.string("screenshot.defaultFileName")
        guard panel.runModal() == .OK, let url = panel.url,
              let cgImage = image.cgImageForStitching else { return }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = image.size
        guard let data = representation.representation(using: .png, properties: [.compressionFactor: 1]) else { return }
        do {
            try data.write(to: url, options: Data.WritingOptions.atomic)
        } catch {
            showCaptureError(error)
        }
    }

    private func scrollingPanelOrigin(panelSize: NSSize, selectionRect rect: NSRect, availableFrame: NSRect) -> NSPoint {
        let gap: CGFloat = 10
        let candidates = [
            NSPoint(x: rect.maxX + gap, y: rect.maxY - panelSize.height),
            NSPoint(x: rect.minX - panelSize.width - gap, y: rect.maxY - panelSize.height),
            NSPoint(x: rect.maxX - panelSize.width, y: rect.minY - panelSize.height - gap),
            NSPoint(x: rect.maxX - panelSize.width, y: rect.maxY + gap)
        ]
        for candidate in candidates {
            let candidateRect = NSRect(origin: candidate, size: panelSize)
            if availableFrame.contains(candidateRect), candidateRect.intersection(rect).isEmpty {
                return candidate
            }
        }
        return NSPoint(
            x: max(availableFrame.minX + 8, availableFrame.maxX - panelSize.width - 8),
            y: max(availableFrame.minY + 8, availableFrame.maxY - panelSize.height - 8)
        )
    }

    private func captureArea(on screen: NSScreen, rect: NSRect) {
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                let screenImage = try await screenshotService.captureFullScreen(on: screen)
                let image = try await screenshotService.captureArea(on: screen, rect: rect)
                let cornerRadius = selectedWindowCornerRadius(for: rect, on: screen)
                let previewImage = cornerRadius > 0 ? image.withRoundedCorners(radius: cornerRadius) : image
                openPreview(image: previewImage, screenImage: screenImage, sourceRect: rect)
            } catch {
                showCaptureError(error)
            }
        }
    }

    private func openPreview(
        image: NSImage,
        screenImage: NSImage? = nil,
        sourceRect: NSRect? = nil,
        previewScreen: NSScreen? = nil,
        usesFullScreenCanvas: Bool = false,
        allowsZoom: Bool = false
    ) {
        weak var previewWindow: NSWindow?
        let view = ScreenshotPreviewView(
            image: image,
            screenImage: screenImage,
            settings: settings,
            localization: localization,
            providerStore: providerStore,
            sourceRect: sourceRect,
            sourceScreenFrame: sourceRect.flatMap { screen(containing: $0)?.frame },
            previewScreenFrame: usesFullScreenCanvas ? (previewScreen ?? NSScreen.main)?.frame : nil,
            allowsZoom: allowsZoom,
            toolbarPlacement: toolbarPlacement(for: sourceRect, in: sourceRect.flatMap { screen(containing: $0) }),
            onEditingStarted: {
                previewWindow?.isMovableByWindowBackground = false
            }
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        let window = ScreenshotPreviewWindow(contentViewController: hostingController)
        previewWindow = window
        window.title = localization.string("screenshot.preview")
        window.styleMask = [.borderless, .resizable]
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        positionPreviewWindow(window, image: image, sourceRect: sourceRect, previewScreen: previewScreen, usesFullScreenCanvas: usesFullScreenCanvas)
        let controller = NSWindowController(window: window)
        previewWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private func openRecordingPreview(_ result: ScreenRecordingManager.RecordingResult) {
        recordingPreviewWindowController?.close()
        let view = RecordingPreviewView(
            result: result,
            localization: localization,
            prepareOutput: { [weak self] in
                guard let self else { throw ScreenRecordingError.writerFailed }
                return try await self.screenRecordingManager.preparedOutputURL(for: result)
            },
            onCopy: { [weak self] url in
                guard let self else { return }
                try self.screenRecordingManager.copyRecordingToPasteboard(url)
            }
        )
        let controller = NSHostingController(rootView: view)
        let window = ScreenshotPreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localization.string("recording.preview")
        window.contentViewController = controller
        window.center()
        let windowController = NSWindowController(window: window)
        recordingPreviewWindowController = windowController
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
    }

    private func positionPreviewWindow(
        _ window: NSWindow,
        image: NSImage,
        sourceRect: NSRect?,
        previewScreen: NSScreen? = nil,
        usesFullScreenCanvas: Bool = false
    ) {
        let previewScreen = previewScreen ?? sourceRect.flatMap { screen(containing: $0) } ?? NSScreen.main
        let visibleFrame = previewScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        if usesFullScreenCanvas, let previewScreen {
            window.setContentSize(previewScreen.frame.size)
            window.minSize = NSSize(width: 320, height: 240)
            window.setFrame(previewScreen.frame, display: true)
            return
        }

        if sourceRect != nil, let previewScreen {
            window.setContentSize(previewScreen.frame.size)
            window.minSize = NSSize(width: 320, height: 240)
            window.setFrame(previewScreen.frame, display: true)
            return
        }

        let toolbarReserve: CGFloat = sourceRect == nil ? 124 : 0
        let availableImageSize = NSSize(
            width: max(160, visibleFrame.width - 80),
            height: max(120, visibleFrame.height - 80 - toolbarReserve)
        )
        let preferredImageSize = sourceRect?.size ?? image.size
        let imageScale = min(
            1,
            availableImageSize.width / max(preferredImageSize.width, 1),
            availableImageSize.height / max(preferredImageSize.height, 1)
        )
        let displayImageSize = NSSize(
            width: max(1, preferredImageSize.width * imageScale),
            height: max(1, preferredImageSize.height * imageScale)
        )
        let contentSize = sourceRect == nil
            ? NSSize(width: max(displayImageSize.width, min(700, availableImageSize.width)), height: displayImageSize.height + toolbarReserve)
            : displayImageSize
        window.setContentSize(contentSize)
        window.minSize = NSSize(width: min(160, contentSize.width), height: min(120, contentSize.height))

        var frame = window.frame
        if let sourceRect {
            frame.origin = NSPoint(
                x: sourceRect.minX,
                y: sourceRect.maxY - displayImageSize.height
            )
        } else {
            frame.origin = NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            )
        }
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + 20), visibleFrame.maxX - frame.width - 20)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + 20), visibleFrame.maxY - frame.height - 20)
        window.setFrame(frame, display: true)
    }

    private func toolbarPlacement(for sourceRect: NSRect?, in screen: NSScreen?) -> ScreenshotToolbarPlacement {
        guard let sourceRect, let screen else { return .bottomTrailing }
        if sourceRect.size.equalTo(screen.frame.size) { return .bottomTrailing }
        let horizontal: ScreenshotToolbarPlacement.Horizontal = sourceRect.midX < screen.frame.midX ? .leading : .trailing
        let vertical: ScreenshotToolbarPlacement.Vertical = sourceRect.midY < screen.frame.midY ? .bottom : .top
        return ScreenshotToolbarPlacement(horizontal: horizontal, vertical: vertical)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }

    private func selectedWindowCornerRadius(for rect: NSRect, on screen: NSScreen) -> CGFloat {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let allScreensFrame = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }

        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? pid_t) != currentPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width > 24,
                  height > 24 else {
                continue
            }

            let windowRect = NSRect(
                x: x,
                y: allScreensFrame.maxY - y - height,
                width: width,
                height: height
            ).intersection(screen.frame)

            if windowRect.isClose(to: rect, tolerance: 3) {
                return 12
            }
        }

        return 0
    }

    private func closeActionPanel() {
        closePanelLater(&actionPanel)
        uninstallEscapeMonitorsIfIdle()
    }

    private func closeScrollingPanel() {
        closePanelLater(&scrollingPanel)
        closeCaptureOverlay()
        uninstallEscapeMonitorsIfIdle()
    }

    private func closeRecordingPanel() {
        closePanelLater(&recordingPanel)
        closeRecordingCountdown()
        closeRecordingTimer()
        closeRecordingProcessing()
        closeCaptureOverlay()
        uninstallEscapeMonitorsIfIdle()
    }

    private func closeAdjustmentWindowLater() {
        guard let windowToClose = adjustmentWindow else { return }
        adjustmentWindow = nil
        retireWindow(windowToClose)
        uninstallEscapeMonitorsIfIdle()
    }

    private func showCaptureOverlay(screen: NSScreen, rect: NSRect) {
        closeCaptureOverlay()
        let overlay = ScreenshotCaptureOverlayWindow(screen: screen, globalSelectionRect: rect)
        captureOverlayWindow = overlay
        overlay.orderFrontRegardless()
    }

    private func closeCaptureOverlay() {
        guard let overlay = captureOverlayWindow else { return }
        captureOverlayWindow = nil
        retireWindow(overlay)
    }

    private func cancelAllInteractiveCapture() {
        recordingStartTask?.cancel()
        recordingStartTask = nil
        recordingFinishTask?.cancel()
        recordingFinishTask = nil
        closeActionPanel()
        closeSelectionWindowLater()
        closeAdjustmentWindowLater()
        closeCaptureOverlay()
        closeRecordingCountdown()
        closeRecordingTimer()
        closeRecordingProcessing()
        cancelScrollingCapture()
        Task { @MainActor [screenRecordingManager] in
            await screenRecordingManager.cancel()
        }
        closeRecordingPanel()
        recordingPreviewWindowController?.close()
        recordingPreviewWindowController = nil
        uninstallEscapeMonitors()
    }

    private func closePanelLater(_ panel: inout NSPanel?) {
        guard let panelToClose = panel else { return }
        panel = nil
        retireWindow(panelToClose)
    }

    private func closeSelectionWindowLater() {
        guard let windowToClose = selectionWindow else { return }
        selectionWindow = nil
        retireWindow(windowToClose)
    }

    private func finishSelectionWindow() {
        guard let windowToClose = selectionWindow else {
            uninstallEscapeMonitorsIfIdle()
            return
        }
        selectionWindow = nil
        retireWindow(windowToClose)
        uninstallEscapeMonitorsIfIdle()
    }

    private func retireWindow(_ window: NSWindow) {
        window.orderOut(nil)
        retiredWindows.append(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, window] in
            window.close()
            self?.retiredWindows.removeAll { $0 === window }
        }
    }

    private func installEscapeMonitors() {
        guard escapeLocalMonitor == nil, escapeGlobalMonitor == nil else { return }
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            DispatchQueue.main.async {
                self?.cancelAllInteractiveCapture()
            }
            return nil
        }
        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return }
            Task { @MainActor in
                self?.cancelAllInteractiveCapture()
            }
        }
    }

    private func uninstallEscapeMonitorsIfIdle() {
        guard actionPanel == nil, selectionWindow == nil, adjustmentWindow == nil, scrollingPanel == nil, recordingPanel == nil else { return }
        uninstallEscapeMonitors()
    }

    private func uninstallEscapeMonitors() {
        if let escapeLocalMonitor {
            NSEvent.removeMonitor(escapeLocalMonitor)
            self.escapeLocalMonitor = nil
        }
        if let escapeGlobalMonitor {
            NSEvent.removeMonitor(escapeGlobalMonitor)
            self.escapeGlobalMonitor = nil
        }
    }

    private func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func showUnsupportedNotice(messageKey: String) {
        let alert = NSAlert()
        alert.messageText = localization.string("app.name")
        alert.informativeText = localization.string(messageKey)
        alert.addButton(withTitle: localization.string("common.ok"))
        alert.runModal()
    }

    private func requestScreenCapturePermissionIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)
        if CGRequestScreenCaptureAccess() {
            return true
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = localization.string("screenshot.captureFailed")
        if let screenshotError = error as? ScreenCaptureScreenshotError,
           case .unsupportedOS = screenshotError {
            alert.informativeText = localization.string("screenshot.requiresMacOS14")
        } else if let recordingError = error as? ScreenRecordingError,
                  recordingError.requiresScreenRecordingPermissionNotice {
            alert.informativeText = localization.string("recording.permissionRequired")
        } else if let recordingError = error as? ScreenRecordingError,
                  case .noFramesCaptured = recordingError {
            alert.informativeText = localization.string("recording.noFramesCaptured")
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: localization.string("common.ok"))
        alert.runModal()
    }
}



private final class ScreenshotFloatingPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct RecordingCountdownView: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.78))
            Text("\(value)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 96, height: 96)
    }
}

private struct RecordingTimerView: View {
    @ObservedObject var manager: ScreenRecordingManager
    @ObservedObject var localization: LocalizationManager
    let onTogglePause: () -> Void
    let onStop: () -> Void
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(manager.isPaused ? .orange : .red)
                .frame(width: 8, height: 8)
            Text(timeText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 52, alignment: .leading)

            Button(action: onTogglePause) {
                Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(localization.string(manager.isPaused ? "recording.resume" : "recording.pause"))

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(localization.string("recording.stop"))

            toolbarDragDots
                .background(RecordingPanelDragView())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: Capsule())
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    private var timeText: String {
        guard case .recording = manager.state else { return "00:00" }
        let seconds = max(0, Int(manager.elapsedRecordingDuration(at: now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var toolbarDragDots: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(4), spacing: 3), count: 2), spacing: 3) {
            ForEach(0..<6, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 14, height: 22)
        .contentShape(Rectangle())
    }
}

private struct RecordingPanelDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> RecordingPanelDragNSView {
        RecordingPanelDragNSView()
    }

    func updateNSView(_ nsView: RecordingPanelDragNSView, context: Context) {}
}

private final class RecordingPanelDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct RecordingPreviewView: View {
    let result: ScreenRecordingManager.RecordingResult
    @ObservedObject var localization: LocalizationManager
    let prepareOutput: () async throws -> URL
    let onCopy: (URL) throws -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPreparingOutput = false
    @State private var successMessageKey: String?

    var body: some View {
        VStack(spacing: 0) {
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            VStack(spacing: 8) {
                Slider(value: Binding(
                    get: { currentTime },
                    set: { seek(to: $0) }
                ), in: 0...max(duration, 0.1))

                HStack(spacing: 14) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)

                    Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(localization.string("common.download")) {
                        Task { await downloadRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPreparingOutput)

                    Button(localization.string("recording.copyToClipboard")) {
                        Task { await copyRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPreparingOutput)

                    if isPreparingOutput {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 480)
        .overlay(alignment: .bottom) {
            if let successMessageKey {
                Label(localization.string(successMessageKey), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.bottom, 76)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: setupPlayer)
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            if let player {
                currentTime = player.currentTime().seconds.finiteOrZero
                duration = player.currentItem?.duration.seconds.finiteOrZero ?? result.duration
                isPlaying = player.rate != 0
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let player {
            RecordingPlayerView(player: player)
        } else {
            ProgressView()
        }
    }

    private func setupPlayer() {
        duration = result.duration
        let player = AVPlayer(url: result.url)
        self.player = player
        duration = player.currentItem?.asset.duration.seconds.finiteOrZero ?? result.duration
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.rate == 0 {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    private func seek(to seconds: Double) {
        currentTime = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func downloadRecording() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = desiredOutputFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isPreparingOutput = true
        let preparedURL: URL
        do {
            preparedURL = try await prepareOutput()
        } catch {
            isPreparingOutput = false
            NSAlert(error: error).runModal()
            return
        }
        do {
            if preparedURL.standardizedFileURL != url.standardizedFileURL {
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.copyItem(at: preparedURL, to: url)
            }
            isPreparingOutput = false
            await showSuccess("recording.downloadSucceeded")
        } catch {
            isPreparingOutput = false
            NSAlert(error: error).runModal()
        }
    }

    private func copyRecording() async {
        isPreparingOutput = true
        do {
            let preparedURL = try await prepareOutput()
            try onCopy(preparedURL)
            isPreparingOutput = false
            await showSuccess("recording.copySucceeded")
        } catch {
            isPreparingOutput = false
            NSAlert(error: error).runModal()
        }
    }

    private func showSuccess(_ key: String) async {
        withAnimation(.easeOut(duration: 0.15)) {
            successMessageKey = key
        }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        guard successMessageKey == key else { return }
        withAnimation(.easeIn(duration: 0.15)) {
            successMessageKey = nil
        }
    }

    private var desiredOutputFileName: String {
        let baseName = result.url.deletingPathExtension().lastPathComponent
        return "\(baseName).mp4"
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}

private struct RecordingPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private struct ScreenRecordingControlView: View {
    @ObservedObject var manager: ScreenRecordingManager
    @ObservedObject var localization: LocalizationManager
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            recordingToggle(
                localization.string("recording.microphone"),
                systemImage: "mic",
                isOn: Binding(
                    get: { manager.includeMicrophone },
                    set: { manager.includeMicrophone = $0 }
                ),
                isDisabled: false
            )

            Button(localization.string("recording.start"), action: onStart)
                .keyboardShortcut(.defaultAction)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
        }
        .controlSize(.large)
        .font(.system(size: 16))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.white)
        .buttonStyle(.bordered)
    }

    private func recordingToggle(_ title: String, systemImage: String, isOn: Binding<Bool>, isDisabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .help(title)
        }
        .toggleStyle(.checkbox)
        .disabled(isDisabled)
    }
}

private enum ScrollingCompletionAction {
    case confirm
    case download
    case edit
}

@MainActor
private final class ScrollingCaptureSession: ObservableObject {
    @Published var hasStarted = false
    @Published var isRunning = false
    @Published var isCompleted = false
    @Published var isFailed = false
    @Published var previewImage: NSImage?
    @Published var frameCount = 0
    @Published var errorMessage: String?
    @Published var isInterrupted = false
    @Published var scrollSign = 0
    @Published var shouldWarnSlowDown = false

    func reset() {
        hasStarted = false
        isRunning = false
        isCompleted = false
        isFailed = false
        previewImage = nil
        frameCount = 0
        errorMessage = nil
        isInterrupted = false
        scrollSign = 0
        shouldWarnSlowDown = false
    }
}

private struct ScrollingScreenshotControlView: View {
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var session: ScrollingCaptureSession
    let onStart: () -> Void
    let onConfirm: () -> Void
    let onDownload: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if session.hasStarted {
                activePreview
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 28))
                    Text(localization.string("screenshot.scrollingReadyHint"))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            controls
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var activePreview: some View {
        VStack(spacing: 8) {
            Group {
                if let image = session.previewImage {
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: 1).id("scroll-preview-top")
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: max(1, geometry.size.width - 8))
                                    Color.clear.frame(height: 1).id("scroll-preview-bottom")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .onChange(of: session.frameCount) { _ in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    proxy.scrollTo(
                                        session.scrollSign > 0 ? "scroll-preview-top" : "scroll-preview-bottom",
                                        anchor: session.scrollSign > 0 ? .top : .bottom
                                    )
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(session.shouldWarnSlowDown || session.isInterrupted ? .orange : .red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if session.isRunning {
                Text("✓ " + localization.string("screenshot.scrollingFrameCount", session.frameCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                onStart()
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 28, height: 28)
            }
            .disabled(session.isRunning || session.isCompleted)
            .help(localization.string("screenshot.scrollingStart"))

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
            }
            .help(localization.string("common.cancel"))

            Button {
                onConfirm()
            } label: {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
            }
            .disabled(session.previewImage == nil || session.frameCount < 3)
            .help(localization.string("screenshot.finishToClipboard"))

            Button(action: onDownload) {
                Image(systemName: "arrow.down.to.line")
                    .frame(width: 28, height: 28)
            }
            .disabled(session.previewImage == nil || session.frameCount < 3)
            .help(localization.string("screenshot.saveImage"))

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: 28, height: 28)
            }
            .disabled(session.previewImage == nil || session.frameCount < 3)
            .help(localization.string("screenshot.edit"))
        }
        .buttonStyle(.borderless)
        .font(.system(size: 16, weight: .semibold))
    }
}

private final class ScreenshotPreviewWindow: NSWindow {
    private var localEscapeMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        installEscapeMonitors()
    }

    override func close() {
        removeEscapeMonitors()
        super.close()
    }

    private func installEscapeMonitors() {
        guard localEscapeMonitor == nil else { return }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, Int(event.keyCode) == kVK_Escape else { return event }
            self.close()
            return nil
        }
    }

    private func removeEscapeMonitors() {
        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
    }
}

private enum ScreenshotCaptureMode: CaseIterable {
    case screenshot
    case scrolling
    case recording

    static let visibleCases: [ScreenshotCaptureMode] = [.screenshot, .recording]

    var localizationKey: String {
        switch self {
        case .screenshot: return "screenshot.area"
        case .scrolling: return "screenshot.scrolling"
        case .recording: return "action.recording"
        }
    }
}

private final class ScreenshotSelectionWindow: NSWindow {
    init(
        screen: NSScreen,
        localization: LocalizationManager,
        initialMode: ScreenshotCaptureMode = .screenshot,
        showsModeSelector: Bool = false,
        completion: @escaping (ScreenshotCaptureMode, NSScreen?, NSRect?) -> Void
    ) {
        let view = ScreenshotSelectionView(
            frame: screen.frame,
            localization: localization,
            initialMode: initialMode,
            showsModeSelector: showsModeSelector,
            completion: completion
        )
        view.screenForCapture = screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false
        self.contentView = view
        self.backgroundColor = .clear
        self.isOpaque = false
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        makeKey()
        if let view = contentView {
            makeFirstResponder(view)
        }
    }
}

private final class ScreenshotCaptureOverlayWindow: NSWindow {
    init(screen: NSScreen, globalSelectionRect: NSRect) {
        let view = ScreenshotCaptureOverlayView(screen: screen, globalSelectionRect: globalSelectionRect)
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        contentView = view
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }
}

private final class ScreenshotCaptureOverlayView: NSView {
    private let selectionRect: NSRect

    init(screen: NSScreen, globalSelectionRect: NSRect) {
        selectionRect = NSRect(
            x: globalSelectionRect.minX - screen.frame.minX,
            y: globalSelectionRect.minY - screen.frame.minY,
            width: globalSelectionRect.width,
            height: globalSelectionRect.height
        ).intersection(NSRect(origin: .zero, size: screen.frame.size))
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        let dimPath = NSBezierPath(rect: bounds)
        dimPath.append(NSBezierPath(rect: selectionRect))
        dimPath.windingRule = .evenOdd
        dimPath.fill()

        CaptureSelectionBorder.draw(selectionRect, in: self)
    }
}

private final class ScreenshotAdjustmentWindow: NSWindow {
    init(
        screen: NSScreen,
        rect: NSRect,
        completion: @escaping (NSScreen?, NSRect?) -> Void
    ) {
        let view = ScreenshotAdjustmentView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            rect: rect,
            completion: completion
        )
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        contentView = view
        backgroundColor = .clear
        isOpaque = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        makeKey()
        if let view = contentView {
            makeFirstResponder(view)
        }
    }
}

private final class ScreenshotAdjustmentView: NSView {
    private let screen: NSScreen
    private let completion: (NSScreen?, NSRect?) -> Void
    private var selectionRect: NSRect
    private var dragStartPoint: NSPoint?
    private var dragStartRect: NSRect?
    private var didDrag = false

    init(frame: NSRect, screen: NSScreen, rect: NSRect, completion: @escaping (NSScreen?, NSRect?) -> Void) {
        self.screen = screen
        self.completion = completion
        self.selectionRect = NSRect(
            x: rect.minX - screen.frame.minX,
            y: rect.minY - screen.frame.minY,
            width: rect.width,
            height: rect.height
        ).intersection(NSRect(origin: .zero, size: screen.frame.size))
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        let dimPath = NSBezierPath(rect: bounds)
        dimPath.append(NSBezierPath(rect: selectionRect))
        dimPath.windingRule = .evenOdd
        dimPath.fill()

        CaptureSelectionBorder.draw(selectionRect, in: self)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard selectionRect.contains(point) else { return }
        dragStartPoint = point
        dragStartRect = selectionRect
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint, let dragStartRect else { return }
        let point = convert(event.locationInWindow, from: nil)
        let translation = NSSize(width: point.x - dragStartPoint.x, height: point.y - dragStartPoint.y)
        if abs(translation.width) > 2 || abs(translation.height) > 2 {
            didDrag = true
        }
        selectionRect = clamped(
            NSRect(
                x: dragStartRect.minX + translation.width,
                y: dragStartRect.minY + translation.height,
                width: dragStartRect.width,
                height: dragStartRect.height
            )
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartPoint = nil
            dragStartRect = nil
        }
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard selectionRect.contains(point) else { return }
        completeAfterCurrentEvent(rect: globalSelectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            completeAfterCurrentEvent(rect: nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private var globalSelectionRect: NSRect {
        NSRect(
            x: screen.frame.minX + selectionRect.minX,
            y: screen.frame.minY + selectionRect.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }

    private func clamped(_ rect: NSRect) -> NSRect {
        let maxX = max(bounds.minX, bounds.maxX - rect.width)
        let maxY = max(bounds.minY, bounds.maxY - rect.height)
        return NSRect(
            x: min(max(rect.minX, bounds.minX), maxX),
            y: min(max(rect.minY, bounds.minY), maxY),
            width: min(rect.width, bounds.width),
            height: min(rect.height, bounds.height)
        )
    }

    private func completeAfterCurrentEvent(rect: NSRect?) {
        guard let window else {
            completion(rect == nil ? nil : screen, rect)
            return
        }

        window.orderOut(nil)
        DispatchQueue.main.async { [completion, screen] in
            completion(rect == nil ? nil : screen, rect)
        }
    }
}

private final class ScreenshotSelectionView: NSView {
    var screenForCapture: NSScreen?

    private let localization: LocalizationManager
    private let completion: (ScreenshotCaptureMode, NSScreen?, NSRect?) -> Void
    private let showsModeSelector: Bool
    private var selectedMode: ScreenshotCaptureMode
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var hoveredGlobalRect: NSRect?
    private var didChangeModeOnMouseDown = false
    private var modeButtonRects: [ScreenshotCaptureMode: NSRect] = [:]

    init(
        frame: NSRect,
        localization: LocalizationManager,
        initialMode: ScreenshotCaptureMode,
        showsModeSelector: Bool,
        completion: @escaping (ScreenshotCaptureMode, NSScreen?, NSRect?) -> Void
    ) {
        self.localization = localization
        self.completion = completion
        self.selectedMode = initialMode
        self.showsModeSelector = showsModeSelector
        super.init(frame: frame)
        wantsLayer = true
        updateHoveredRect(at: NSEvent.mouseLocation)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let selection = selectionRect ?? hoveredSelectionRect

        NSColor.black.withAlphaComponent(0.25).setFill()
        let dimPath = NSBezierPath(rect: bounds)
        if let selection {
            dimPath.append(NSBezierPath(rect: selection))
        }
        dimPath.windingRule = .evenOdd
        dimPath.fill()

        guard let selection else { return }
        CaptureSelectionBorder.draw(selection, in: self)

        drawModeSelectorIfNeeded()
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredRect(at: window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin ?? NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let mode = modeButtonRects.first(where: { $0.value.contains(point) })?.key {
            selectedMode = mode
            startPoint = nil
            currentPoint = nil
            didChangeModeOnMouseDown = true
            needsDisplay = true
            return
        }

        didChangeModeOnMouseDown = false
        startPoint = point
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if didChangeModeOnMouseDown {
            didChangeModeOnMouseDown = false
            return
        }
        currentPoint = convert(event.locationInWindow, from: nil)
        if let selection = selectionRect, selection.width > 8, selection.height > 8 {
            let screenRect = convert(selection, to: nil)
            let globalRect = window?.convertToScreen(screenRect) ?? screenRect
            completeAfterCurrentEvent(screen: screenForCapture, rect: globalRect)
            return
        }

        completeAfterCurrentEvent(screen: screenForCapture, rect: hoveredGlobalRect ?? screenForCapture?.frame)
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            completeAfterCurrentEvent(screen: nil, rect: nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private func completeAfterCurrentEvent(screen: NSScreen?, rect: NSRect?) {
        guard let window else {
            completion(selectedMode, screen, rect)
            return
        }

        window.orderOut(nil)
        DispatchQueue.main.async { [completion, selectedMode] in
            completion(selectedMode, screen, rect)
        }
    }

    private func drawModeSelectorIfNeeded() {
        guard showsModeSelector else { return }
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let modes = ScreenshotCaptureMode.visibleCases
        let buttonWidths = modes.map { mode in
            ceil(localization.string(mode.localizationKey).size(withAttributes: [.font: font]).width) + 28
        }
        let buttonHeight: CGFloat = 32
        let spacing: CGFloat = 6
        let totalWidth = buttonWidths.reduce(0, +) + CGFloat(modes.count - 1) * spacing
        let origin = NSPoint(x: bounds.midX - totalWidth / 2, y: bounds.maxY - 58)
        let containerRect = NSRect(
            x: origin.x - 8,
            y: origin.y - 8,
            width: totalWidth + 16,
            height: buttonHeight + 16
        )

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: containerRect, xRadius: 10, yRadius: 10).fill()

        modeButtonRects.removeAll()
        var buttonX = origin.x
        for (index, mode) in modes.enumerated() {
            let buttonWidth = buttonWidths[index]
            let rect = NSRect(
                x: buttonX,
                y: origin.y,
                width: buttonWidth,
                height: buttonHeight
            )
            buttonX += buttonWidth + spacing
            modeButtonRects[mode] = rect
            (mode == selectedMode ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.12)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
            let titleRect = rect.insetBy(dx: 4, dy: 8)
            localization.string(mode.localizationKey).draw(in: titleRect, withAttributes: attributes)
        }
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        guard abs(startPoint.x - currentPoint.x) > 2 || abs(startPoint.y - currentPoint.y) > 2 else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private var hoveredSelectionRect: NSRect? {
        guard let hoveredGlobalRect, let window else { return nil }
        return convert(window.convertFromScreen(hoveredGlobalRect), from: nil).intersection(bounds)
    }

    private func updateHoveredRect(at globalPoint: NSPoint) {
        guard startPoint == nil || selectionRect == nil else { return }
        hoveredGlobalRect = Self.windowRect(containing: globalPoint, on: screenForCapture) ?? screenForCapture?.frame
        needsDisplay = true
    }

    private static func windowRect(containing point: NSPoint, on screen: NSScreen?) -> NSRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let screenFrame = screen?.frame
        let allScreensFrame = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }

        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? pid_t) != currentPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width > 24,
                  height > 24 else {
                continue
            }

            let rect = NSRect(
                x: x,
                y: allScreensFrame.maxY - y - height,
                width: width,
                height: height
            )
            guard rect.contains(point) else { continue }
            if let screenFrame, rect.intersection(screenFrame).isEmpty { continue }
            return screenFrame.map { rect.intersection($0) } ?? rect
        }

        return nil
    }
}

private enum CaptureSelectionBorder {
    static func draw(_ rect: NSRect, in view: NSView) {
        let scale = max(1, view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        let lineWidth = 1 / scale
        let alignedRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard alignedRect.width > 0, alignedRect.height > 0 else { return }

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: alignedRect)
        path.lineWidth = lineWidth
        path.stroke()
    }
}


private extension NSImage {
    var contentDigest: String {
        guard let tiffRepresentation else { return UUID().uuidString }
        return String(tiffRepresentation.hashValue)
    }

    func withRoundedCorners(radius: CGFloat) -> NSImage {
        guard radius > 0, size.width > 0, size.height > 0 else { return self }
        let output = NSImage(size: size)
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        let rect = NSRect(origin: .zero, size: size)
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        output.unlockFocus()
        return output
    }
}

private extension NSRect {
    func isClose(to other: NSRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}


private extension NSImage {
    var cgImageForStitching: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

private extension Double {
    var finiteOrZero: Double {
        isFinite ? self : 0
    }
}
