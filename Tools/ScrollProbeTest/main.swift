import AppKit
import ApplicationServices
import ArgumentParser
import CoreImage
import CoreGraphics
import CoreMedia
import Darwin
import Foundation
import ScreenCaptureKit
import ScrollProbeCore

@main
struct ScrollProbeTest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ScrollProbeTest",
        abstract: "Independently verifies whether a macOS screen region supports scrolling screenshots."
    )

    @Option(help: "Selection top-left x coordinate in screen points.")
    var x: Int

    @Option(help: "Selection top-left y coordinate in screen points.")
    var y: Int

    @Option(help: "Selection width in screen points.")
    var width: Int

    @Option(help: "Selection height in screen points.")
    var height: Int

    @Option(help: "Directory used for captured frames and correlation data.")
    var output: String = "./debug_output"

    @Flag(help: "Run probes continuously and create test_NNN subdirectories.")
    var loop = false

    @Flag(help: "Save a texture/MAE block visualization to /tmp.")
    var debugDetect = false

    mutating func run() async throws {
        setbuf(stdout, nil)
        guard width > 0, height > 0 else {
            throw ValidationError("--width and --height must be positive integers")
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ProbeError.screenCapturePermissionDenied
        }

        var testIndex = 1
        repeat {
            let baseURL = URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let directory = loop
                ? baseURL.appendingPathComponent(String(format: "test_%03d", testIndex), isDirectory: true)
                : baseURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await runSingleProbe(outputDirectory: directory)
            testIndex += 1
        } while loop
    }

    private func runSingleProbe(outputDirectory: URL) async throws {
        print("请在 3 秒内将鼠标移动到目标区域并确保该区域为前台窗口")
        for value in stride(from: 3, through: 1, by: -1) {
            print("\(value)...")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let rect = CGRect(x: x, y: y, width: width, height: height)
        let capture = try await RegionCapture(rect: rect)
        if enableEnhancedAccessibility(at: CGPoint(x: rect.midX, y: rect.midY)) {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        let before = try await capture.image()
        let beforeURL = outputDirectory.appendingPathComponent("frame_0_before.png")
        try writePNG(before, to: beforeURL)

        let config = ScrollingCaptureConfig.default
        let requestedScroll = config.probeScrollAmount(pixelHeight: before.height)
        let probePoint = CGPoint(x: rect.midX, y: rect.midY)
        let restorationAnchor = accessibilityScrollPosition(at: probePoint)
        postScroll(deltaY: -requestedScroll, at: probePoint)
        var after = try await captureSettledFrame(capture: capture, initial: before, config: config)
        guard var textureAnalysis = TextureWeightedGridAnalyzer.analyze(before: before, after: after, config: config) else {
            throw ProbeError.imageAnalysisFailed
        }
        if restorationAnchor != nil ||
            (ImageDifferenceAnalyzer.meanAbsoluteError(before, after) ?? .greatestFiniteMagnitude) >= config.probeStableFrameMAEThreshold {
            try await restoreScroll(
                originalDeltaY: -requestedScroll,
                before: before,
                latest: after,
                capture: capture,
                point: probePoint,
                anchor: restorationAnchor,
                config: config
            )
        }

        var captureDirection = "down"
        if textureAnalysis.verdict(config: config) == .notScrollable {
            let reverseAnchor = accessibilityScrollPosition(at: probePoint)
            postScroll(deltaY: requestedScroll, at: probePoint)
            let reverseAfter = try await captureSettledFrame(capture: capture, initial: before, config: config)
            guard let reverseAnalysis = TextureWeightedGridAnalyzer.analyze(before: before, after: reverseAfter, config: config) else {
                throw ProbeError.imageAnalysisFailed
            }
            if reverseAnalysis.verdict(config: config) != .notScrollable {
                after = reverseAfter
                textureAnalysis = reverseAnalysis
                captureDirection = "up"
            }
            if reverseAnchor != nil ||
                (ImageDifferenceAnalyzer.meanAbsoluteError(before, reverseAfter) ?? .greatestFiniteMagnitude) >= config.probeStableFrameMAEThreshold {
                try await restoreScroll(
                    originalDeltaY: requestedScroll,
                    before: before,
                    latest: reverseAfter,
                    capture: capture,
                    point: probePoint,
                    anchor: reverseAnchor,
                    config: config
                )
            }
        }

        let afterURL = outputDirectory.appendingPathComponent("frame_1_after.png")
        try writePNG(after, to: afterURL)
        let csvURL = outputDirectory.appendingPathComponent("texture_blocks.csv")
        try textureCSV(textureAnalysis).write(to: csvURL, atomically: true, encoding: .utf8)
        let columnProfile = ColumnSplitDetector.differenceProfile(before: before, after: after, config: config)
        let columnSplit = ColumnSplitDetector.detect(before: before, after: after, config: config)
        let columnCSVURL = outputDirectory.appendingPathComponent("column_diff.csv")
        if let columnProfile {
            try columnDifferenceCSV(columnProfile).write(to: columnCSVURL, atomically: true, encoding: .utf8)
        }
        var debugURL: URL?
        if debugDetect {
            let name = "scroll-detect-\(Int(Date().timeIntervalSince1970 * 1_000)).png"
            let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
            try writeDiagnosticImage(
                before: before,
                after: after,
                analysis: textureAnalysis,
                columnProfile: columnProfile,
                columnLayout: columnSplit?.layout,
                threshold: config.columnSplitDifferenceThreshold,
                to: url
            )
            debugURL = url
        }
        let accessibility = accessibilitySignal(at: CGPoint(x: rect.midX, y: rect.midY))
        let verdict = textureAnalysis.verdict(config: config)
        let supported = verdict != .notScrollable
        let resultDescription = supported ? "SUPPORTED (可长截图)" : "UNSUPPORTED (不可长截图)"

        print("""

        === 探测结果报告 ===
        目标区域: (\(x), \(y), \(width)x\(height))
        F0截图: \(beforeURL.path)
        F1截图: \(afterURL.path)
        有效纹理块: \(textureAnalysis.validBlockCount)/\(textureAnalysis.blocks.count)
        变化有效块: \(textureAnalysis.changedValidBlockCount)
        变化有效块占比: \(String(format: "%.4f", textureAnalysis.changedValidRatio))
        判定结果: \(resultDescription)
        判定原因: \(String(describing: verdict))
        初始有效滚动方向: \(captureDirection)
        辅助信号(Accessibility): role=\(accessibility.role), 命中=\(accessibility.hit)
        块级诊断数据已保存至: \(csvURL.path)
        列差异曲线已保存至: \(columnCSVURL.path)
        列切分布局: \(columnSplit?.layout.type.rawValue ?? "none") x*=\(columnSplit.map { "\($0.layout.scrollingMinX)..<\($0.layout.scrollingMaxX)" } ?? "none")
        Debug诊断图: \(debugURL?.path ?? "未启用（使用 --debug-detect 开启）")
        ====================
        """)
    }
}

private struct RegionCapture {
    let display: SCDisplay
    let configuration: SCStreamConfiguration
    let filter: SCContentFilter

    init(rect: CGRect) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.intersects(rect) }) ?? content.displays.first else {
            throw ProbeError.displayNotFound
        }
        let localRect = CGRect(
            x: rect.minX - display.frame.minX,
            y: rect.minY - display.frame.minY,
            width: rect.width,
            height: rect.height
        ).intersection(CGRect(origin: .zero, size: display.frame.size))
        guard localRect.width > 0, localRect.height > 0 else { throw ProbeError.emptyRegion }

        let scale = max(1, CGFloat(CGDisplayPixelsWide(display.displayID)) / max(1, display.frame.width))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = Int(localRect.width * scale)
        configuration.height = Int(localRect.height * scale)
        configuration.scalesToFit = false
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
        }
        configuration.showsCursor = false

        self.display = display
        self.configuration = configuration
        self.filter = SCContentFilter(display: display, excludingWindows: [])
    }

    func image() async throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        return try await ProbeSingleFrameCapture.capture(filter: filter, configuration: configuration)
    }
}

private final class ProbeSingleFrameCapture: NSObject, SCStreamOutput {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var continuation: CheckedContinuation<CGImage, Error>?

    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let receiver = ProbeSingleFrameCapture()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "ScrollProbe.SingleFrame"))
        return try await withCheckedThrowingContinuation { continuation in
            receiver.continuation = continuation
            Task {
                do { try await stream.startCapture() }
                catch { receiver.finish(.failure(error), stream: stream) }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        finish(.success(cgImage), stream: stream)
    }

    private func finish(_ result: Result<CGImage, Error>, stream: SCStream) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        Task { try? await stream.stopCapture() }
    }
}

private enum ProbeError: LocalizedError {
    case screenCapturePermissionDenied
    case displayNotFound
    case emptyRegion
    case pngEncodingFailed
    case imageAnalysisFailed

    var errorDescription: String? {
        switch self {
        case .screenCapturePermissionDenied: "没有屏幕录制权限。请在系统设置 > 隐私与安全性 > 屏幕录制中允许当前终端或 Codex，然后重新运行。"
        case .displayNotFound: "没有找到包含选区的显示器。"
        case .emptyRegion: "选区不在任何显示器范围内。"
        case .pngEncodingFailed: "无法将截图编码为 PNG。"
        case .imageAnalysisFailed: "无法分析截图像素。"
        }
    }
}

private func captureSettledFrame(
    capture: RegionCapture,
    initial: CGImage,
    config: ScrollingCaptureConfig
) async throws -> CGImage {
    let attempts = max(2, Int(config.probeSettleTimeoutNanoseconds / config.probeSettleIntervalNanoseconds))
    var previous = initial
    var stablePairs = 0
    for _ in 0..<attempts {
        try await Task.sleep(nanoseconds: config.probeSettleIntervalNanoseconds)
        let current = try await capture.image()
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
    capture: RegionCapture,
    point: CGPoint,
    anchor: ProbeAccessibilityScrollPosition?,
    config: ScrollingCaptureConfig
) async throws {
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
        postScroll(deltaY: -originalDeltaY, at: point)
    }
    var restored = try await captureSettledFrame(capture: capture, initial: latest, config: config)
    var bestMAE = ImageDifferenceAnalyzer.meanAbsoluteError(before, restored) ?? .greatestFiniteMagnitude
    for _ in 0..<4 where bestMAE >= config.probeRestoredFrameMAEThreshold {
        guard let match = ScrollStitchMatcher.bestMatch(previous: before, current: restored) else { break }
        let measuredDisplacement = max(4, min(abs(originalDeltaY), before.height - match.overlap))
        let correction = match.direction == .down ? measuredDisplacement : -measuredDisplacement
        postScroll(deltaY: correction, at: point)
        let candidate = try await captureSettledFrame(capture: capture, initial: restored, config: config)
        let candidateMAE = ImageDifferenceAnalyzer.meanAbsoluteError(before, candidate) ?? .greatestFiniteMagnitude
        if candidateMAE <= bestMAE {
            restored = candidate
            bestMAE = candidateMAE
        } else {
            postScroll(deltaY: -correction, at: point)
            break
        }
    }
}

private func textureCSV(_ analysis: TextureWeightedAnalysis) -> String {
    let rows = analysis.blocks.map {
        "\($0.row),\($0.column),\(String(format: "%.4f", $0.textureVariance)),\(String(format: "%.4f", $0.mae)),\($0.isValid),\($0.isChanged)"
    }
    return (["row,column,texture_variance,mae,is_valid,is_changed"] + rows).joined(separator: "\n") + "\n"
}

private func columnDifferenceCSV(_ profile: ColumnDifferenceProfile) -> String {
    let rows = zip(profile.raw.indices, zip(profile.raw, profile.smoothed)).map {
        "\($0.0),\(String(format: "%.6f", $0.1.0)),\(String(format: "%.6f", $0.1.1))"
    }
    return (["x,raw_col_diff,smoothed_col_diff"] + rows).joined(separator: "\n") + "\n"
}

private func writeDiagnosticImage(
    before: CGImage,
    after: CGImage,
    analysis: TextureWeightedAnalysis,
    columnProfile: ColumnDifferenceProfile?,
    columnLayout: ColumnSplitLayout?,
    threshold: Double,
    to url: URL
) throws {
    let graphHeight: CGFloat = 180
    let imageHeight = max(before.height, after.height)
    let beforeWidth = CGFloat(before.width)
    let afterWidth = CGFloat(after.width)
    let imageSize = NSSize(width: beforeWidth + afterWidth, height: CGFloat(imageHeight) + graphHeight)
    let output = NSImage(size: imageSize)
    output.lockFocus()
    NSImage(cgImage: before, size: NSSize(width: before.width, height: before.height)).draw(
        in: NSRect(x: 0, y: graphHeight, width: beforeWidth, height: CGFloat(before.height))
    )
    NSImage(cgImage: after, size: NSSize(width: after.width, height: after.height)).draw(
        in: NSRect(x: beforeWidth, y: graphHeight, width: afterWidth, height: CGFloat(after.height))
    )
    for block in analysis.blocks {
        let color: NSColor = !block.isValid ? .systemGray : (block.isChanged ? .systemGreen : .systemOrange)
        let rect = NSRect(
            x: beforeWidth + CGFloat(block.minX),
            y: graphHeight + CGFloat(after.height - block.minY - block.height),
            width: CGFloat(block.width),
            height: CGFloat(block.height)
        )
        color.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()
        let label = String(
            format: "T%.1f M%.1f %@/%@",
            block.textureVariance,
            block.mae,
            block.isValid ? "V" : "X",
            block.isChanged ? "C" : "S"
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(7, min(11, CGFloat(block.width) / 8)), weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72)
        ]
        (label as NSString).draw(at: NSPoint(x: rect.minX + 3, y: rect.maxY - 15), withAttributes: attributes)
    }
    if let columnLayout {
        NSColor.systemBlue.setStroke()
        for boundary in [columnLayout.scrollingMinX, columnLayout.scrollingMaxX] {
            let x = beforeWidth + CGFloat(boundary)
            let path = NSBezierPath()
            path.lineWidth = 3
            path.move(to: NSPoint(x: x, y: graphHeight))
            path.line(to: NSPoint(x: x, y: graphHeight + CGFloat(after.height)))
            path.stroke()
        }
    }
    if let columnProfile, !columnProfile.smoothed.isEmpty {
        NSColor.black.withAlphaComponent(0.86).setFill()
        NSBezierPath(rect: NSRect(x: beforeWidth, y: 0, width: afterWidth, height: graphHeight)).fill()
        let graphMax = max(threshold * 2, columnProfile.smoothed.max() ?? threshold)
        func graphY(_ value: Double) -> CGFloat {
            min(graphHeight - 8, max(8, CGFloat(value / graphMax) * (graphHeight - 16)))
        }
        NSColor.systemOrange.setStroke()
        let thresholdPath = NSBezierPath()
        thresholdPath.move(to: NSPoint(x: beforeWidth, y: graphY(threshold)))
        thresholdPath.line(to: NSPoint(x: beforeWidth + afterWidth, y: graphY(threshold)))
        thresholdPath.stroke()
        NSColor.systemCyan.setStroke()
        let curve = NSBezierPath()
        for (index, value) in columnProfile.smoothed.enumerated() {
            let point = NSPoint(x: beforeWidth + CGFloat(index), y: graphY(value))
            if index == 0 {
                curve.move(to: point)
            } else {
                curve.line(to: point)
            }
        }
        curve.lineWidth = 2
        curve.stroke()
    }
    output.unlockFocus()
    guard let tiff = output.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw ProbeError.pngEncodingFailed
    }
    try data.write(to: url, options: .atomic)
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw ProbeError.pngEncodingFailed
    }
    try data.write(to: url, options: .atomic)
}

private func postScroll(deltaY: Int, at point: CGPoint) {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
          ) else { return }
    event.location = point
    event.post(tap: .cghidEventTap)
}

private func accessibilitySignal(at point: CGPoint) -> (role: String, hit: Bool) {
    let system = AXUIElementCreateSystemWide()
    var candidate: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &candidate) == .success,
          var element = candidate else {
        return ("unknown", false)
    }

    var closestRole = "unknown"
    for _ in 0..<12 {
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String {
            closestRole = role
            if role == kAXScrollAreaRole as String || role == "AXList" || role == "AXTable" ||
                role == "AXOutline" || role == "AXWebArea" ||
                (role == "AXGroup" && hasVerticalScrollBar(element)) {
                return (role, true)
            }
        }

        var parentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
              let parentValue,
              CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
        element = unsafeBitCast(parentValue, to: AXUIElement.self)
    }
    return (closestRole, false)
}

private func hasVerticalScrollBar(_ element: AXUIElement) -> Bool {
    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement] else { return false }
    return children.contains { child in
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
              (roleValue as? String) == "AXScrollBar" else { return false }
        var orientationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXOrientationAttribute as CFString, &orientationValue) == .success,
              let orientation = orientationValue as? String else { return true }
        return orientation == kAXVerticalOrientationValue as String
    }
}

private struct ProbeAccessibilityScrollPosition {
    let scrollBar: AXUIElement
    let value: CFTypeRef
}

private func accessibilityScrollPosition(at point: CGPoint) -> ProbeAccessibilityScrollPosition? {
    let system = AXUIElementCreateSystemWide()
    var candidateValue: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &candidateValue) == .success,
          var candidate = candidateValue else { return nil }

    for _ in 0..<12 {
        if let scrollBar = verticalScrollBar(of: candidate) {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(scrollBar, kAXValueAttribute as CFString, &value) == .success,
               let value {
                return ProbeAccessibilityScrollPosition(scrollBar: scrollBar, value: value)
            }
        }
        var parentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
              let parentValue,
              CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
        candidate = unsafeBitCast(parentValue, to: AXUIElement.self)
    }
    return nil
}

private func verticalScrollBar(of element: AXUIElement) -> AXUIElement? {
    var scrollBarValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXVerticalScrollBarAttribute as CFString, &scrollBarValue) == .success,
       let scrollBarValue,
       CFGetTypeID(scrollBarValue) == AXUIElementGetTypeID() {
        return unsafeBitCast(scrollBarValue, to: AXUIElement.self)
    }
    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement] else { return nil }
    return children.first { child in
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
              (roleValue as? String) == "AXScrollBar" else { return false }
        var orientationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXOrientationAttribute as CFString, &orientationValue) == .success,
              let orientation = orientationValue as? String else { return true }
        return orientation == kAXVerticalOrientationValue as String
    }
}

private func enableEnhancedAccessibility(at point: CGPoint) -> Bool {
    let system = AXUIElementCreateSystemWide()
    var candidate: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &candidate) == .success,
          let candidate else { return false }
    var pid: pid_t = 0
    guard AXUIElementGetPid(candidate, &pid) == .success, pid > 0 else { return false }
    return AXUIElementSetAttributeValue(
        AXUIElementCreateApplication(pid),
        "AXEnhancedUserInterface" as CFString,
        kCFBooleanTrue
    ) == .success
}
