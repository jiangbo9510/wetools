import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

enum ScreenCaptureScreenshotError: LocalizedError {
    case unsupportedOS
    case displayNotFound
    case emptyCaptureRect

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "ScreenCaptureKit screenshots require macOS 14.0 or later."
        case .displayNotFound:
            return "Unable to find the display to capture."
        case .emptyCaptureRect:
            return "The selected screenshot area is empty."
        }
    }
}

@MainActor
final class ScreenCaptureScreenshotService {
    func captureFullScreen(on screen: NSScreen) async throws -> NSImage {
        return try await captureUsingScreenCaptureKit(screen: screen, rect: screen.frame)
    }

    func captureArea(on screen: NSScreen, rect: NSRect) async throws -> NSImage {
        guard rect.width > 0, rect.height > 0 else {
            throw ScreenCaptureScreenshotError.emptyCaptureRect
        }

        return try await captureUsingScreenCaptureKit(screen: screen, rect: rect)
    }

    private func captureUsingScreenCaptureKit(screen: NSScreen, rect: NSRect) async throws -> NSImage {
        guard let displayID = screen.displayID else {
            throw ScreenCaptureScreenshotError.displayNotFound
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureScreenshotError.displayNotFound
        }

        let scale = screen.backingScaleFactor
        let captureRect = rect.intersection(screen.frame)
        guard captureRect.width > 0, captureRect.height > 0 else {
            throw ScreenCaptureScreenshotError.emptyCaptureRect
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentApplication = content.applications.first { $0.processID == currentPID }
        let filter: SCContentFilter
        if let currentApplication {
            filter = SCContentFilter(display: display, excludingApplications: [currentApplication], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = NSRect(
            x: captureRect.minX - screen.frame.minX,
            y: screen.frame.maxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )
        configuration.width = Int(captureRect.width * scale)
        configuration.height = Int(captureRect.height * scale)
        configuration.showsCursor = false
        configuration.queueDepth = 1
        configuration.scalesToFit = false

        let cgImage: CGImage
        if #available(macOS 14.0, *) {
            configuration.captureResolution = .best
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } else {
            cgImage = try await SCStreamSingleFrameCapture.capture(filter: filter, configuration: configuration)
        }
        return NSImage(cgImage: cgImage, size: captureRect.size)
    }
}

private final class SCStreamSingleFrameCapture: NSObject, SCStreamOutput {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var stream: SCStream?

    static func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let receiver = SCStreamSingleFrameCapture()
        return try await receiver.capture(filter: filter, configuration: configuration)
    }

    private func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "Wetools.SingleFrameCapture"))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                Task {
                    do {
                        try await stream.startCapture()
                    } catch {
                        self.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            Task { try? await stream.stopCapture() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            finish(.failure(ScreenCaptureScreenshotError.emptyCaptureRect))
            return
        }
        finish(.success(cgImage))
    }

    private func finish(_ result: Result<CGImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        self.stream = nil
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
