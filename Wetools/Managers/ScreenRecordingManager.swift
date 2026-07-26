import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

@MainActor
final class ScreenRecordingManager: NSObject, ObservableObject {
    struct RecordingResult: Equatable {
        var url: URL
        var duration: TimeInterval
    }

    enum RecordingState: Equatable {
        case idle
        case preparing
        case recording(startedAt: Date)
        case finished(RecordingResult)
        case failed(String)
    }

    @Published private(set) var state: RecordingState = .idle
    @Published var includeMicrophone: Bool {
        didSet { settings.recordingMicrophone = includeMicrophone }
    }
    @Published private(set) var isPaused = false

    private let settings: AppSettings
    private var stream: Any?
    private var output: ScreenRecordingStreamOutput?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var microphoneSession: AVCaptureSession?
    private var microphoneOutput: MicrophoneRecordingOutput?
    private var microphoneWriter: AVAssetWriter?
    private var microphoneInput: AVAssetWriterInput?
    private var microphoneURL: URL?
    private var microphoneFirstSampleTime: CMTime?
    private var outputURL: URL?
    private var firstSampleTime: CMTime?
    private var lastVideoSampleTime: CMTime?
    private var hasCapturedVideoFrame = false
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0

    init(settings: AppSettings) {
        self.settings = settings
        includeMicrophone = settings.recordingMicrophone
        super.init()
    }

    func start(screen: NSScreen, rect: CGRect) async throws {
        guard #available(macOS 13.0, *) else { throw ScreenRecordingError.unsupportedOS }
        guard case .idle = state else { return }
        state = .preparing

        guard let displayID = screen.recordingDisplayID else { throw ScreenRecordingError.displayNotFound }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            NSLog(
                "Screen recording could not load shareable content. preflight=%@ error=%@",
                CGPreflightScreenCaptureAccess() ? "true" : "false",
                error.localizedDescription
            )
            if !CGPreflightScreenCaptureAccess() {
                throw ScreenRecordingError.screenRecordingPermissionRequired
            }
            throw error
        }
        NSLog(
            "Screen recording access confirmed by ScreenCaptureKit. preflight=%@ displays=%d",
            CGPreflightScreenCaptureAccess() ? "true" : "false",
            content.displays.count
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ScreenRecordingError.displayNotFound }

        let captureRect = rect.intersection(screen.frame)
        guard captureRect.width > 0, captureRect.height > 0 else { throw ScreenRecordingError.emptyCaptureRect }

        let scale = screen.backingScaleFactor
        let pixelSize = CGSize(
            width: Self.evenPixelLength(captureRect.width * scale),
            height: Self.evenPixelLength(captureRect.height * scale)
        )
        let url = try makeOutputURL()
        outputURL = url
        try prepareVideoWriter(url: url, pixelSize: pixelSize)
        if includeMicrophone {
            try await ensureMicrophoneAccess()
            try prepareMicrophoneCapture()
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: captureRect.minX - screen.frame.minX,
            y: screen.frame.maxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.excludesCurrentProcessAudio = true

        let streamOutput = ScreenRecordingStreamOutput { [weak self] sampleBuffer, type in
            Task { @MainActor in
                self?.handle(sampleBuffer: sampleBuffer, type: type)
            }
        }
        let captureStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try captureStream.addStreamOutput(streamOutput, type: SCStreamOutputType.screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))

        output = streamOutput
        stream = captureStream
        outputURL = url
        firstSampleTime = nil
        lastVideoSampleTime = nil
        hasCapturedVideoFrame = false
        startedAt = Date()
        pausedAt = nil
        accumulatedPausedDuration = 0
        isPaused = false

        microphoneSession?.startRunning()
        try await captureStream.startCapture()
        NSLog("Screen recording stream started for %.0fx%.0f pixels.", pixelSize.width, pixelSize.height)
        try await waitForFirstFrameIfNeeded(captureStream)
        state = .recording(startedAt: startedAt ?? Date())
    }

    func stop() async throws -> RecordingResult {
        guard #available(macOS 13.0, *) else { throw ScreenRecordingError.unsupportedOS }
        guard let captureStream = stream as? SCStream, let url = outputURL else { throw ScreenRecordingError.noActiveRecording }
        finishActivePauseIfNeeded()

        try await withTimeout(seconds: 10) {
            try await captureStream.stopCapture()
        }
        microphoneSession?.stopRunning()
        let duration = max(
            0.1,
            Date().timeIntervalSince(startedAt ?? Date()) - accumulatedPausedDuration
        )

        try await withTimeout(seconds: 15) {
            try await self.finishVideoWriter()
        }
        if includeMicrophone {
            try await withTimeout(seconds: 15) {
                try await self.finishMicrophoneWriter()
            }
            if let microphoneURL {
                try await mergeMicrophoneAudio(from: microphoneURL, into: url)
            }
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            throw ScreenRecordingError.writerFailed
        }

        cleanup(keepState: true)
        let result = RecordingResult(url: url, duration: duration)
        state = .finished(result)
        return result
    }

    func preparedOutputURL(for result: RecordingResult) async throws -> URL {
        result.url
    }

    func cancel() async {
        if #available(macOS 13.0, *), let captureStream = stream as? SCStream {
            try? await captureStream.stopCapture()
        }
        microphoneSession?.stopRunning()
        writer?.cancelWriting()
        microphoneWriter?.cancelWriting()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        if let microphoneURL {
            try? FileManager.default.removeItem(at: microphoneURL)
        }
        isPaused = false
        cleanup(keepState: false)
    }

    func reset() {
        writer?.cancelWriting()
        microphoneWriter?.cancelWriting()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        isPaused = false
        cleanup(keepState: false)
        state = .idle
    }

    func togglePause() {
        guard case .recording = state else { return }
        if isPaused {
            finishActivePauseIfNeeded()
            isPaused = false
        } else {
            pausedAt = Date()
            isPaused = true
        }
    }

    func elapsedRecordingDuration(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let activePauseDuration = pausedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(
            0,
            date.timeIntervalSince(startedAt) - accumulatedPausedDuration - activePauseDuration
        )
    }

    private func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw ScreenRecordingError.stopTimedOut
            }
            guard let result = try await group.next() else {
                throw ScreenRecordingError.stopTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    private func waitForFirstFrameIfNeeded(_ captureStream: SCStream) async throws {
        for _ in 0..<20 {
            if hasCapturedVideoFrame { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        try? await captureStream.stopCapture()
        NSLog(
            "Screen recording received no writable screen frame. writerStatus=%d writerError=%@",
            writer?.status.rawValue ?? -1,
            writer?.error?.localizedDescription ?? "none"
        )
        writer?.cancelWriting()
        cleanup(keepState: false)
        throw ScreenRecordingError.noFramesCaptured
    }

    func copyRecordingToPasteboard(_ url: URL) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.writeObjects([url as NSURL])
        guard didWrite else {
            throw ScreenRecordingError.pasteboardWriteFailed
        }
    }

    func trimRecording(_ result: RecordingResult, start: TimeInterval, end: TimeInterval) async throws -> RecordingResult {
        let clampedStart = max(0, min(start, result.duration))
        let clampedEnd = max(clampedStart + 0.1, min(end, result.duration))
        let output = result.url.deletingLastPathComponent().appendingPathComponent("\(result.url.deletingPathExtension().lastPathComponent) Trimmed.mp4")
        try? FileManager.default.removeItem(at: output)

        let asset = AVURLAsset(url: result.url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ScreenRecordingError.writerSetupFailed
        }
        export.outputURL = output
        export.outputFileType = .mp4
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: clampedStart, preferredTimescale: 600),
            duration: CMTime(seconds: clampedEnd - clampedStart, preferredTimescale: 600)
        )

        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }

        guard export.status == .completed else { throw export.error ?? ScreenRecordingError.writerFailed }
        let trimmed = RecordingResult(url: output, duration: clampedEnd - clampedStart)
        state = .finished(trimmed)
        return trimmed
    }

    private func prepareVideoWriter(url: URL, pixelSize: CGSize) throws {
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, Int(pixelSize.width * pixelSize.height * 2))
            ]
        ])
        input.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(input) else { throw ScreenRecordingError.writerSetupFailed }
        assetWriter.add(input)
        writer = assetWriter
        videoInput = input
    }

    private func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            guard granted else { throw ScreenRecordingError.microphonePermissionRequired }
        case .denied, .restricted:
            throw ScreenRecordingError.microphonePermissionRequired
        @unknown default:
            throw ScreenRecordingError.microphonePermissionRequired
        }
    }

    private func prepareMicrophoneCapture() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw ScreenRecordingError.microphoneUnavailable
        }

        let microphoneURL = outputURLForMicrophone()
        try? FileManager.default.removeItem(at: microphoneURL)
        let microphoneWriter = try AVAssetWriter(outputURL: microphoneURL, fileType: .m4a)
        let microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000
        ])
        microphoneInput.expectsMediaDataInRealTime = true
        guard microphoneWriter.canAdd(microphoneInput) else {
            throw ScreenRecordingError.writerSetupFailed
        }
        microphoneWriter.add(microphoneInput)

        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(deviceInput) else {
            throw ScreenRecordingError.microphoneUnavailable
        }
        captureSession.addInput(deviceInput)

        let streamOutput = MicrophoneRecordingOutput { [weak self] sampleBuffer in
            Task { @MainActor in
                self?.handleMicrophone(sampleBuffer)
            }
        }
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(
            streamOutput,
            queue: DispatchQueue(label: "com.wetools.microphone-recording", qos: .userInitiated)
        )
        guard captureSession.canAddOutput(audioOutput) else {
            throw ScreenRecordingError.microphoneUnavailable
        }
        captureSession.addOutput(audioOutput)

        self.microphoneURL = microphoneURL
        self.microphoneWriter = microphoneWriter
        self.microphoneInput = microphoneInput
        microphoneSession = captureSession
        microphoneOutput = streamOutput
        microphoneFirstSampleTime = nil
    }

    private func finishVideoWriter() async throws {
        guard let assetWriter = writer else { throw ScreenRecordingError.noActiveRecording }
        guard firstSampleTime != nil else {
            assetWriter.cancelWriting()
            throw ScreenRecordingError.noFramesCaptured
        }
        if let lastVideoSampleTime {
            assetWriter.endSession(atSourceTime: lastVideoSampleTime)
        }
        videoInput?.markAsFinished()
        await withCheckedContinuation { continuation in
            assetWriter.finishWriting { continuation.resume() }
        }
        if assetWriter.status == .failed {
            let message = assetWriter.error?.localizedDescription ?? ScreenRecordingError.writerFailed.localizedDescription
            state = .failed(message)
            throw ScreenRecordingError.writerFailed
        }
    }

    private func finishMicrophoneWriter() async throws {
        guard let microphoneWriter, let microphoneInput else {
            throw ScreenRecordingError.microphoneUnavailable
        }
        guard microphoneFirstSampleTime != nil else {
            microphoneWriter.cancelWriting()
            throw ScreenRecordingError.microphoneNoSamples
        }
        microphoneInput.markAsFinished()
        await withCheckedContinuation { continuation in
            microphoneWriter.finishWriting { continuation.resume() }
        }
        guard microphoneWriter.status == .completed else {
            throw microphoneWriter.error ?? ScreenRecordingError.writerFailed
        }
    }

    private func handle(sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        if type == .screen, !Self.isCompleteScreenFrame(sampleBuffer) { return }
        if isPaused { return }
        guard let adjustedSampleBuffer = sampleBuffer.removingTimeOffset(accumulatedPausedDuration) else { return }
        switch type {
        case .screen:
            appendVideo(adjustedSampleBuffer)
        case .audio:
            break
        @unknown default:
            break
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, let videoInput else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard startWriterIfNeeded(writer, at: time),
              videoInput.isReadyForMoreMediaData else { return }
        if videoInput.append(sampleBuffer) {
            lastVideoSampleTime = time
            hasCapturedVideoFrame = true
        }
    }

    private func handleMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, !isPaused,
              let adjustedSampleBuffer = sampleBuffer.removingTimeOffset(accumulatedPausedDuration),
              let microphoneWriter,
              let microphoneInput else {
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(adjustedSampleBuffer)
        if microphoneFirstSampleTime == nil {
            guard microphoneWriter.startWriting() else { return }
            microphoneWriter.startSession(atSourceTime: time)
            microphoneFirstSampleTime = time
        }
        guard microphoneWriter.status == .writing,
              microphoneInput.isReadyForMoreMediaData else {
            return
        }
        microphoneInput.append(adjustedSampleBuffer)
    }

    private func startWriterIfNeeded(_ writer: AVAssetWriter, at time: CMTime) -> Bool {
        guard firstSampleTime == nil else { return writer.status == .writing }
        guard writer.startWriting() else {
            state = .failed(writer.error?.localizedDescription ?? ScreenRecordingError.writerSetupFailed.localizedDescription)
            return false
        }
        writer.startSession(atSourceTime: time)
        firstSampleTime = time
        return true
    }

    private func cleanup(keepState: Bool) {
        microphoneSession?.stopRunning()
        stream = nil
        output = nil
        writer = nil
        videoInput = nil
        microphoneSession = nil
        microphoneOutput = nil
        microphoneWriter = nil
        microphoneInput = nil
        if let microphoneURL {
            try? FileManager.default.removeItem(at: microphoneURL)
        }
        microphoneURL = nil
        microphoneFirstSampleTime = nil
        outputURL = nil
        firstSampleTime = nil
        lastVideoSampleTime = nil
        hasCapturedVideoFrame = false
        startedAt = nil
        pausedAt = nil
        accumulatedPausedDuration = 0
        if !keepState {
            state = .idle
        }
    }

    private func makeOutputURL() throws -> URL {
        let directory: URL
        if !settings.defaultSaveDirectory.isEmpty {
            directory = URL(fileURLWithPath: settings.defaultSaveDirectory, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Wetools Recording \(Self.timestamp()).mp4")
    }

    private func outputURLForMicrophone() -> URL {
        let baseURL = outputURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Wetools Recording \(Self.timestamp()).mp4")
        return baseURL
            .deletingPathExtension()
            .appendingPathExtension("microphone.m4a")
    }

    private func mergeMicrophoneAudio(from microphoneURL: URL, into videoURL: URL) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let microphoneAsset = AVURLAsset(url: microphoneURL)
        guard let sourceVideoTrack = videoAsset.tracks(withMediaType: .video).first,
              let sourceMicrophoneTrack = microphoneAsset.tracks(withMediaType: .audio).first else {
            throw ScreenRecordingError.microphoneNoSamples
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenRecordingError.writerSetupFailed
        }
        let videoDuration = videoAsset.duration
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        videoTrack.preferredTransform = sourceVideoTrack.preferredTransform

        var mixedAudioTracks: [AVMutableCompositionTrack] = []
        for sourceAudioTrack in videoAsset.tracks(withMediaType: .audio) {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: min(videoDuration, sourceAudioTrack.timeRange.duration)),
                of: sourceAudioTrack,
                at: .zero
            )
            mixedAudioTracks.append(track)
        }

        guard let microphoneTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenRecordingError.writerSetupFailed
        }
        let microphoneDuration = min(videoDuration, sourceMicrophoneTrack.timeRange.duration)
        try microphoneTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: microphoneDuration),
            of: sourceMicrophoneTrack,
            at: .zero
        )
        mixedAudioTracks.append(microphoneTrack)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixedAudioTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(1, at: .zero)
            return parameters
        }

        let mergedURL = videoURL
            .deletingPathExtension()
            .appendingPathExtension("merged.mp4")
        try? FileManager.default.removeItem(at: mergedURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ScreenRecordingError.writerSetupFailed
        }
        exporter.outputURL = mergedURL
        exporter.outputFileType = .mp4
        exporter.audioMix = audioMix
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            throw exporter.error ?? ScreenRecordingError.writerFailed
        }

        try FileManager.default.removeItem(at: videoURL)
        try FileManager.default.moveItem(at: mergedURL, to: videoURL)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func evenPixelLength(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }

    private static func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue) else {
            return true
        }
        return status == .complete
    }

    private func finishActivePauseIfNeeded() {
        guard let pausedAt else { return }
        accumulatedPausedDuration += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }
}

private extension CMSampleBuffer {
    func removingTimeOffset(_ seconds: TimeInterval) -> CMSampleBuffer? {
        guard seconds > 0 else { return self }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            self,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        ) == noErr, count > 0 else {
            return self
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: count
        )
        guard CMSampleBufferGetSampleTimingInfoArray(
            self,
            entryCount: count,
            arrayToFill: &timing,
            entriesNeededOut: &count
        ) == noErr else {
            return nil
        }

        let offset = CMTime(seconds: seconds, preferredTimescale: 600)
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - offset
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - offset
            }
        }

        var adjusted: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: self,
            sampleTimingEntryCount: timing.count,
            sampleTimingArray: &timing,
            sampleBufferOut: &adjusted
        ) == noErr else {
            return nil
        }
        return adjusted
    }
}

private final class ScreenRecordingStreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer, SCStreamOutputType) -> Void

    init(handler: @escaping (CMSampleBuffer, SCStreamOutputType) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        handler(sampleBuffer, outputType)
    }
}

private final class MicrophoneRecordingOutput: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }
}

enum ScreenRecordingError: LocalizedError {
    case unsupportedOS
    case screenRecordingPermissionRequired
    case displayNotFound
    case emptyCaptureRect
    case writerSetupFailed
    case writerFailed
    case noActiveRecording
    case noFramesCaptured
    case microphonePermissionRequired
    case microphoneUnavailable
    case microphoneNoSamples
    case stopTimedOut
    case pasteboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Screen recording requires macOS 13.0 or later."
        case .screenRecordingPermissionRequired:
            return "Screen recording permission is required."
        case .displayNotFound:
            return "Unable to find the display to record."
        case .emptyCaptureRect:
            return "The selected recording area is empty."
        case .writerSetupFailed:
            return "Unable to prepare the recording writer."
        case .writerFailed:
            return "The recording could not be finalized."
        case .noActiveRecording:
            return "There is no active recording to stop."
        case .noFramesCaptured:
            return "The screen capture stream started, but no video frames could be written."
        case .microphonePermissionRequired:
            return "Microphone permission is required when microphone recording is enabled."
        case .microphoneUnavailable:
            return "The selected microphone is unavailable."
        case .microphoneNoSamples:
            return "No microphone audio was captured."
        case .stopTimedOut:
            return "Stopping the recording timed out."
        case .pasteboardWriteFailed:
            return "Unable to copy the recording to the clipboard."
        }
    }

    var requiresScreenRecordingPermissionNotice: Bool {
        switch self {
        case .screenRecordingPermissionRequired:
            return true
        default:
            return false
        }
    }
}

private extension NSScreen {
    var recordingDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
