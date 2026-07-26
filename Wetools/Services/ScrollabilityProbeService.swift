import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class ScrollabilityProbeService {
    struct Result {
        let analysis: ScrollProbeAnalysis
        let accessibilityRole: String
        let accessibilityHit: Bool
        let staticGridBlocks: [Int]
        let captureScrollSign: Int
        let columnSplit: ColumnSplitDetection?
    }

    private let screenshotService: ScreenCaptureScreenshotService
    private let config: ScrollingCaptureConfig

    init(screenshotService: ScreenCaptureScreenshotService, config: ScrollingCaptureConfig = .default) {
        self.screenshotService = screenshotService
        self.config = config
    }

    func probe(screen: NSScreen, rect: NSRect) async throws -> Result {
        let quartzRect = quartzRect(fromAppKit: rect)
        let quartzPoint = CGPoint(x: quartzRect.midX, y: quartzRect.midY)
        let enhancedAXEnabled = enableEnhancedAccessibility(at: quartzPoint)
        if enhancedAXEnabled {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        let accessibility = accessibilityAssessment(rect: quartzRect)
        let probePoint = preferredScrollingPoint(in: quartzRect) ?? quartzPoint

        let beforeImage = try await screenshotService.captureArea(on: screen, rect: rect)
        guard let before = cgImage(from: beforeImage) else {
            throw ScrollabilityProbeError.imageConversionFailed
        }
        let scrollAmount = config.probeScrollAmount(pixelHeight: before.height)

        let first = try await testScroll(
            deltaY: -scrollAmount,
            before: before,
            screen: screen,
            rect: rect,
            point: probePoint
        )
        var selected = first.analysis
        var selectedAfter = first.after
        var captureScrollSign = -1
        if first.analysis.verdict(config: config) == .notScrollable {
            let reverse = try await testScroll(
                deltaY: scrollAmount,
                before: before,
                screen: screen,
                rect: rect,
                point: probePoint
            )
            if reverse.analysis.verdict(config: config) != .notScrollable {
                selected = reverse.analysis
                selectedAfter = reverse.after
                captureScrollSign = 1
            }
        }

        let textureVerdict = selected.verdict(config: config)
        let supported = textureVerdict != .notScrollable
        let reason: ScrollDetectionReason?
        switch textureVerdict {
        case .scrollable: reason = nil
        case .fixedElements: reason = .fixedElements
        case .lowTexture: reason = .lowTexture
        case .notScrollable: reason = .notScrollable
        }
        let analysis = ScrollDetectionResult(
            identicalHash: selected.changedValidBlockCount == 0,
            bestDeltaY: 0,
            bestScore: selected.changedValidRatio,
            zeroOffsetScore: 0,
            verdict: supported ? .supported : .unsupported,
            reason: reason,
            points: []
        )
        let columnSplit = ColumnSplitDetector.detect(before: before, after: selectedAfter, config: config)
        if let layout = columnSplit?.layout {
            print("[ColumnSplitDetector] type=\(layout.type.rawValue) x*=\(layout.scrollingMinX)..<\(layout.scrollingMaxX) sourceWidth=\(layout.sourceWidth)")
        } else {
            print("[ColumnSplitDetector] no valid edge split detected")
        }
        return Result(
            analysis: analysis,
            accessibilityRole: accessibility.role,
            accessibilityHit: accessibility.hit,
            staticGridBlocks: selected.blocks.enumerated().compactMap {
                $0.element.isValid && !$0.element.isChanged ? $0.offset : nil
            },
            captureScrollSign: captureScrollSign,
            columnSplit: columnSplit
        )
    }

    private func testScroll(
        deltaY: Int,
        before: CGImage,
        screen: NSScreen,
        rect: NSRect,
        point: CGPoint
    ) async throws -> (analysis: TextureWeightedAnalysis, after: CGImage) {
        let restorationAnchor = accessibilityScrollPosition(at: point)
        postScroll(deltaY: deltaY, at: point, units: .pixel)
        let after = try await captureSettledFrame(screen: screen, rect: rect, initial: before)
        guard let analysis = TextureWeightedGridAnalyzer.analyze(before: before, after: after, config: config) else {
            throw ScrollabilityProbeError.imageConversionFailed
        }
        let movementMAE = ImageDifferenceAnalyzer.meanAbsoluteError(before, after) ?? .greatestFiniteMagnitude
        if restorationAnchor != nil || movementMAE >= config.probeStableFrameMAEThreshold {
            await restoreScroll(
                originalDeltaY: deltaY,
                before: before,
                latest: after,
                screen: screen,
                rect: rect,
                point: point,
                anchor: restorationAnchor
            )
        }
        return (analysis, after)
    }

    private func captureSettledFrame(screen: NSScreen, rect: NSRect, initial: CGImage) async throws -> CGImage {
        let attempts = max(2, Int(config.probeSettleTimeoutNanoseconds / config.probeSettleIntervalNanoseconds))
        var previous = initial
        var stablePairs = 0
        for _ in 0..<attempts {
            try await Task.sleep(nanoseconds: config.probeSettleIntervalNanoseconds)
            let image = try await screenshotService.captureArea(on: screen, rect: rect)
            guard let current = cgImage(from: image) else { throw ScrollabilityProbeError.imageConversionFailed }
            let mae = ImageDifferenceAnalyzer.meanAbsoluteError(previous, current) ?? .greatestFiniteMagnitude
            stablePairs = mae < config.probeStableFrameMAEThreshold ? stablePairs + 1 : 0
            previous = current
            if stablePairs >= 2 { break }
        }
        return previous
    }

    private func restoreScroll(
        originalDeltaY: Int,
        before: CGImage,
        latest: CGImage,
        screen: NSScreen,
        rect: NSRect,
        point: CGPoint,
        anchor: AccessibilityScrollPosition?
    ) async {
        let restoredWithAccessibility: Bool
        if let anchor {
            restoredWithAccessibility = AXUIElementSetAttributeValue(
                anchor.scrollBar,
                kAXValueAttribute as CFString,
                anchor.value
            ) == .success
        } else {
            restoredWithAccessibility = false
        }
        if !restoredWithAccessibility {
            postScroll(deltaY: -originalDeltaY, at: point, units: .pixel)
        }
        guard var restored = try? await captureSettledFrame(screen: screen, rect: rect, initial: latest) else { return }
        var bestMAE = ImageDifferenceAnalyzer.meanAbsoluteError(before, restored) ?? .greatestFiniteMagnitude
        guard bestMAE >= config.probeRestoredFrameMAEThreshold else { return }

        for _ in 0..<4 where bestMAE >= config.probeRestoredFrameMAEThreshold {
            guard let match = ScrollStitchMatcher.bestMatch(previous: before, current: restored) else { break }
            let measuredDisplacement = max(4, min(abs(originalDeltaY), before.height - match.overlap))
            let correction = match.direction == .down ? measuredDisplacement : -measuredDisplacement
            postScroll(deltaY: correction, at: point, units: .pixel)
            guard let candidate = try? await captureSettledFrame(screen: screen, rect: rect, initial: restored) else { break }
            let candidateMAE = ImageDifferenceAnalyzer.meanAbsoluteError(before, candidate) ?? .greatestFiniteMagnitude
            if candidateMAE <= bestMAE {
                restored = candidate
                bestMAE = candidateMAE
            } else {
                postScroll(deltaY: -correction, at: point, units: .pixel)
                break
            }
        }
    }

    private func accessibilityScrollPosition(at point: CGPoint) -> AccessibilityScrollPosition? {
        guard let area = scrollArea(at: point),
              let scrollBar = verticalScrollBar(near: area.element) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(scrollBar, kAXValueAttribute as CFString, &value) == .success,
              let value else { return nil }
        return AccessibilityScrollPosition(scrollBar: scrollBar, value: value)
    }

    private func verticalScrollBar(near element: AXUIElement) -> AXUIElement? {
        var candidate = element
        for _ in 0..<8 {
            var scrollBarValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(candidate, kAXVerticalScrollBarAttribute as CFString, &scrollBarValue) == .success,
               let scrollBarValue,
               CFGetTypeID(scrollBarValue) == AXUIElementGetTypeID() {
                return unsafeBitCast(scrollBarValue, to: AXUIElement.self)
            }
            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(candidate, kAXChildrenAttribute as CFString, &childrenValue) == .success,
               let children = childrenValue as? [AXUIElement],
               let scrollBar = children.first(where: { child in
                   var roleValue: CFTypeRef?
                   return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success &&
                       (roleValue as? String) == "AXScrollBar" && verticalOrientation(of: child)
               }) {
                return scrollBar
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            candidate = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        return nil
    }

    private func postScroll(deltaY: Int, at point: CGPoint, units: CGScrollEventUnit) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: units,
                wheelCount: 1,
                wheel1: Int32(deltaY),
                wheel2: 0,
                wheel3: 0
              ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func quartzRect(fromAppKit rect: NSRect) -> CGRect {
        let desktopFrame = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
        return CGRect(x: rect.minX, y: desktopFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    private func accessibilityAssessment(rect: CGRect) -> AccessibilityAssessment {
        let inset = min(3, min(rect.width, rect.height) / 4)
        let points = [
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.minX + inset, y: rect.minY + inset),
            CGPoint(x: rect.maxX - inset, y: rect.minY + inset),
            CGPoint(x: rect.minX + inset, y: rect.maxY - inset),
            CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        ]
        let hits = points.map(scrollArea(at:))
        let found = hits.compactMap { $0 }
        guard !found.isEmpty else { return AccessibilityAssessment(role: "unknown", hit: false) }
        guard found.count == points.count, let first = found.first else {
            return AccessibilityAssessment(role: found.first?.role ?? "unknown", hit: false)
        }
        let sameElement = found.dropFirst().allSatisfy { CFEqual(first.element, $0.element) }
        let containsSelection = first.frame?.insetBy(dx: -1, dy: -1).contains(rect) == true
        return AccessibilityAssessment(
            role: first.role,
            hit: sameElement && containsSelection
        )
    }

    private func preferredScrollingPoint(in rect: CGRect) -> CGPoint? {
        let candidates = [
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.minX + rect.width * 0.75, y: rect.midY),
            CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY)
        ]
        for point in candidates {
            guard let frame = scrollArea(at: point)?.frame else { continue }
            let intersection = frame.intersection(rect)
            guard !intersection.isNull, intersection.width > 1, intersection.height > 1 else { continue }
            return CGPoint(x: intersection.midX, y: intersection.midY)
        }
        return nil
    }

    private func enableEnhancedAccessibility(at point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var candidate: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &candidate) == .success,
              let candidate else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(candidate, &pid) == .success, pid > 0 else { return false }
        let application = AXUIElementCreateApplication(pid)
        return AXUIElementSetAttributeValue(
            application,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        ) == .success
    }

    private func scrollArea(at point: CGPoint) -> ScrollAreaHit? {
        let system = AXUIElementCreateSystemWide()
        var candidate: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &candidate) == .success,
              var element = candidate else {
            return nil
        }

        var closestRole = "unknown"
        for _ in 0..<12 {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                closestRole = role
                if isAcceptedScrollableRole(role, element: element) {
                    return ScrollAreaHit(element: element, role: role, frame: accessibilityFrame(of: element))
                }
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            element = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        _ = closestRole
        return nil
    }

    private func isAcceptedScrollableRole(_ role: String, element: AXUIElement) -> Bool {
        if role == kAXScrollAreaRole as String || role == "AXWebArea" || role == "AXList" ||
            role == "AXTable" || role == "AXOutline" {
            return true
        }
        guard role == "AXGroup" else { return false }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return false }
        return children.contains { child in
            var childRoleValue: CFTypeRef?
            return AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRoleValue) == .success &&
                (childRoleValue as? String) == "AXScrollBar" && verticalOrientation(of: child)
        }
    }

    private func verticalOrientation(of element: AXUIElement) -> Bool {
        var orientationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXOrientationAttribute as CFString, &orientationValue) == .success,
              let orientation = orientationValue as? String else { return true }
        return orientation == kAXVerticalOrientationValue as String
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}

private struct ScrollAreaHit {
    let element: AXUIElement
    let role: String
    let frame: CGRect?
}

private struct AccessibilityAssessment {
    let role: String
    let hit: Bool
}

private struct AccessibilityScrollPosition {
    let scrollBar: AXUIElement
    let value: CFTypeRef
}

private enum ScrollabilityProbeError: LocalizedError {
    case imageConversionFailed

    var errorDescription: String? {
        "Unable to convert captured frames for scrollability analysis."
    }
}

@MainActor
struct ScrollDriverCaptureFailure: Error {
    let code: ScrollingCaptureFailureCode
    let frames: [CGImage]
    let estimatedDisplacements: [Int]
}

@MainActor
final class ScrollDriver {
    enum Progress {
        case captured(
            frame: CGImage,
            measuredDisplacements: [Int],
            scrollSign: Int,
            shouldWarnSlowDown: Bool
        )
    }

    struct Result {
        let frames: [CGImage]
        let measuredDisplacements: [Int]
        let scrollSign: Int
    }

    private let screenshotService: ScreenCaptureScreenshotService
    private let config: ScrollingCaptureConfig
    private var stopRequested = false
    private var scrollMonitor: Any?
    private var hasPendingScroll = false
    private var pendingScrollMagnitude: CGFloat = 0
    private var lastScrollEventAt = Date.distantPast

    init(screenshotService: ScreenCaptureScreenshotService, config: ScrollingCaptureConfig = .default) {
        self.screenshotService = screenshotService
        self.config = config
    }

    func stop() {
        stopRequested = true
    }

    func capture(
        screen: NSScreen,
        rect: NSRect,
        progress: @escaping @MainActor (Progress) -> Void
    ) async throws -> Result {
        stopRequested = false
        hasPendingScroll = false
        pendingScrollMagnitude = 0
        lastScrollEventAt = .distantPast
        installScrollMonitor(selectionRect: rect)
        defer { removeScrollMonitor() }

        var frames: [CGImage] = []
        var measuredDisplacements: [Int] = []
        var detectedScrollSign = 0
        var stationaryPairs = 0
        var reversalTracker = DirectionReversalTracker()
        print("[ScrollingScreenshot] \(config.activeThresholdDescription)")
        let first = try await captureImage(screen: screen, rect: rect)
        frames.append(first)
        progress(.captured(
            frame: first,
            measuredDisplacements: measuredDisplacements,
            scrollSign: detectedScrollSign,
            shouldWarnSlowDown: false
        ))

        while frames.count < config.maximumFrames, !stopRequested, !Task.isCancelled {
            guard hasPendingScroll else {
                try await Task.sleep(nanoseconds: config.manualScrollPollNanoseconds)
                continue
            }
            let debounceSeconds = Double(config.manualScrollDebounceNanoseconds) / 1_000_000_000
            guard Date().timeIntervalSince(lastScrollEventAt) >= debounceSeconds else {
                try await Task.sleep(nanoseconds: config.manualScrollPollNanoseconds)
                continue
            }
            hasPendingScroll = false
            let estimatedDisplacement = Int(
                max(0, pendingScrollMagnitude * max(1, screen.backingScaleFactor)).rounded()
            )
            pendingScrollMagnitude = 0
            let candidate = try await waitForStableFrame(screen: screen, rect: rect)
            guard let previous = frames.last else { break }
            let difference = frameMAE(previous, candidate)
            if difference < config.identicalMAEThreshold {
                stationaryPairs += 1
                if stationaryPairs >= config.stationaryPairLimit { break }
                continue
            }

            let lockedDirection: ScrollStitchDirection? = switch detectedScrollSign {
            case ..<0: .down
            case 1...: .up
            default: nil
            }
            let registration: RealtimeScrollRegistration
            do {
                registration = try RealtimeScrollRegistrationValidator.validate(
                    previous: previous,
                    current: candidate,
                    estimatedDisplacement: estimatedDisplacement > 0 ? estimatedDisplacement : nil,
                    previousDisplacement: measuredDisplacements.last,
                    requiredDirection: lockedDirection,
                    isManualScrolling: true,
                    config: config
                )
                reversalTracker.recordForward()
            } catch ScrollingCaptureFailureCode.directionReversed {
                if reversalTracker.recordReverse(config: config) {
                    throw ScrollDriverCaptureFailure(
                        code: .directionReversed,
                        frames: frames + [candidate],
                        estimatedDisplacements: measuredDisplacements + [estimatedDisplacement]
                    )
                }
                print(
                    "[ScrollingScreenshot] discarded one reverse frame; "
                        + "\(config.effectiveDirectionReversalPairLimit) consecutive pairs fail"
                )
                continue
            } catch let failure as ScrollingCaptureFailureCode {
                throw ScrollDriverCaptureFailure(
                    code: failure,
                    frames: frames + [candidate],
                    estimatedDisplacements: measuredDisplacements + [estimatedDisplacement]
                )
            }
            if registration.displacementY < config.stationaryDisplacementPixels {
                stationaryPairs += 1
                if stationaryPairs >= config.stationaryPairLimit { break }
                continue
            }
            stationaryPairs = 0
            let candidateSign = registration.direction == .down ? -1 : 1
            detectedScrollSign = candidateSign
            frames.append(candidate)
            measuredDisplacements.append(registration.displacementY)
            progress(.captured(
                frame: candidate,
                measuredDisplacements: measuredDisplacements,
                scrollSign: detectedScrollSign,
                shouldWarnSlowDown: registration.shouldWarnSlowDown
            ))
        }

        return Result(
            frames: frames,
            measuredDisplacements: measuredDisplacements,
            scrollSign: detectedScrollSign
        )
    }

    private func waitForStableFrame(screen: NSScreen, rect: NSRect) async throws -> CGImage {
        var previous = try await captureImage(screen: screen, rect: rect)
        for _ in 0..<6 {
            try await Task.sleep(nanoseconds: config.settleCheckNanoseconds)
            let current = try await captureImage(screen: screen, rect: rect)
            if frameMAE(previous, current) < config.settledMAEThreshold {
                return current
            }
            previous = current
        }
        return previous
    }

    private func captureImage(screen: NSScreen, rect: NSRect) async throws -> CGImage {
        let image = try await screenshotService.captureArea(on: screen, rect: rect)
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw ScrollabilityProbeError.imageConversionFailed
        }
        return cgImage
    }

    private func frameMAE(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        guard let analysis = GridChangeAnalyzer.analyze(
            before: lhs,
            after: rhs,
            dimension: config.gridDimension,
            threshold: .greatestFiniteMagnitude
        ) else { return .greatestFiniteMagnitude }
        return analysis.blockMAE.reduce(0, +) / Double(max(1, analysis.blockMAE.count))
    }

    private func installScrollMonitor(selectionRect: NSRect) {
        removeScrollMonitor()
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in
                guard let self,
                      selectionRect.contains(NSEvent.mouseLocation),
                      abs(event.scrollingDeltaY) > 0 else { return }
                self.hasPendingScroll = true
                self.pendingScrollMagnitude += abs(event.scrollingDeltaY)
                self.lastScrollEventAt = Date()
            }
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}
