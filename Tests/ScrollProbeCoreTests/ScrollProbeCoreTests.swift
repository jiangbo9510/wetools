import CoreGraphics
import ImageIO
import XCTest
@testable import ScrollProbeCore

final class ScrollProbeCoreTests: XCTestCase {
    func testReplayLatestCapturedFailureDiagnostics() throws {
        let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        let latest: URL
        if let replayPath = ProcessInfo.processInfo.environment["WETOOLS_REPLAY_DIR"] {
            latest = URL(fileURLWithPath: replayPath, isDirectory: true)
        } else {
            let directories = try FileManager.default.contentsOfDirectory(
                at: temporaryRoot,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.lastPathComponent.hasPrefix("WetoolsScrollingCapture-") }
            guard let discovered = directories.max(by: {
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }) else {
                throw XCTSkip("No real scrolling-capture diagnostics are available in /tmp.")
            }
            latest = discovered
        }
        let frameURLs = try FileManager.default.contentsOfDirectory(
            at: latest,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("frame_") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let frames = try frameURLs.map { url -> CGImage in
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        let log = try String(contentsOf: latest.appendingPathComponent("registration.log"))
        let estimates = log.split(separator: "\n").compactMap { line -> Int? in
            guard let range = line.range(of: "dy=") else { return nil }
            return Int(line[range.upperBound...])
        }
        let report = try XCTUnwrap(ScrollingFrameDiagnostics.analyze(
            frames: frames,
            estimatedDisplacements: estimates
        ))
        print("REPLAY_DIR=\(latest.path)")
        print("FRAME=\(report.frameWidth)x\(report.frameHeight) CONFIG=\(report.activeConfig)")
        for pair in report.pairs {
            print(
                "PAIR \(pair.pairIndex) dy=\(pair.displacementY.map(String.init) ?? "nil")"
                    + " overlap=\(pair.overlapRatio.map { String(format: "%.4f", $0) } ?? "nil")"
                    + " diff=\(pair.difference.map { String(format: "%.4f", $0) } ?? "nil")"
                    + " peak=\(pair.peakRatio.map { String(format: "%.4f", $0) } ?? "nil")"
                    + " estimate=\(pair.estimatedDisplacement.map(String.init) ?? "nil")"
            )
        }
        print(
            "COL_DIFF min=\(report.columnDifferenceMinimum) median=\(report.columnDifferenceMedian)"
                + " max=\(report.columnDifferenceMaximum) threshold=\(report.columnDifferenceThreshold)"
                + " staticRatio=\(report.staticColumnRatio)"
        )
        print("LAYOUT=\(String(describing: report.layout)) error=\(String(describing: report.layoutError))")
        XCTAssertGreaterThanOrEqual(frames.count, 3)
        let result = try ImageStitcher().stitch(
            frames: frames,
            injectedDisplacements: estimates,
            backingScaleFactor: 2
        )
        XCTAssertGreaterThan(result.image.height, frames[0].height)
        XCTAssertEqual(result.registrations.count, frames.count - 1)
        if let layout = report.layout {
            let autocorrelationPeak = RepeatedContentSelfCheck.maximumCorrelation(
                image: result.image,
                expectedDisplacements: result.registrations.map(\.displacementY),
                columnRanges: [
                    0..<layout.scrollingMinX,
                    layout.scrollingMaxX..<layout.sourceWidth
                ].filter { !$0.isEmpty }
            )
            print("STATIC_AUTOCORRELATION_PEAK=\(autocorrelationPeak)")
        }
    }

    func testFidelityStitchKeepsFixedColumnOnceAndPreservesScrollingRows() throws {
        let fixed = try makeImage(seed: 211, width: 80, height: 300)
        let scrollingSource = try makeImage(seed: 212, width: 220, height: 700)
        let offsets = [0, 180, 360]
        let frames = try offsets.map {
            try frameWithFixedLeftColumn(fixed: fixed, scrollingSource: scrollingSource, offset: $0, height: 300)
        }
        var config = ScrollingCaptureConfig.default
        config.cropScrollbar = false
        config.peakRatioThreshold = 1.05
        config.registrationPeakRatioThreshold = 1.05
        config.registrationMAEThreshold = 1
        let result = try ImageStitcher(config: config).stitch(
            frames: frames,
            injectedDisplacements: [180, 180],
            backingScaleFactor: 1
        )

        XCTAssertEqual(result.image.width, 300)
        XCTAssertEqual(result.image.height, 660)
        let scrollingOutput = try XCTUnwrap(result.image.cropping(to: CGRect(x: 80, y: 0, width: 220, height: 660)))
        let expectedScrolling = try XCTUnwrap(scrollingSource.cropping(to: CGRect(x: 0, y: 0, width: 220, height: 660)))
        XCTAssertEqual(Data(try rgbaBytes(scrollingOutput)), Data(try rgbaBytes(expectedScrolling)))
        let fixedTop = try XCTUnwrap(result.image.cropping(to: CGRect(x: 0, y: 0, width: 80, height: 300)))
        XCTAssertEqual(Data(try rgbaBytes(fixedTop)), Data(try rgbaBytes(fixed)))
    }

    func testFixedSidebarAndHeaderRenderOnceWhileScrollingBodyMatchesGroundTruth() throws {
        let fixed = try makeImage(seed: 220, width: 80, height: 300)
        let scrollingSource = try makeImage(seed: 221, width: 220, height: 760)
        let header = try makeImage(seed: 222, width: 300, height: 36)
        let offsets = [0, 180, 360]
        let frames = try offsets.map { offset in
            let frame = try frameWithFixedLeftColumn(
                fixed: fixed,
                scrollingSource: scrollingSource,
                offset: offset,
                height: 300
            )
            return try imageWithFixedHeader(frame: frame, header: header)
        }
        var config = ScrollingCaptureConfig.default
        config.registrationPeakRatioThreshold = 1.05
        config.registrationMAEThreshold = 1
        let result = try ImageStitcher(config: config).stitch(
            frames: frames,
            injectedDisplacements: [180, 180],
            backingScaleFactor: 1
        )

        let outputHeader = try XCTUnwrap(result.image.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: 300,
            height: 36
        )))
        XCTAssertEqual(Data(try rgbaBytes(outputHeader)), Data(try rgbaBytes(header)))
        let outputBody = try XCTUnwrap(result.image.cropping(to: CGRect(
            x: 80,
            y: 36,
            width: 220,
            height: 624
        )))
        let expectedBody = try XCTUnwrap(scrollingSource.cropping(to: CGRect(
            x: 0,
            y: 36,
            width: 220,
            height: 624
        )))
        XCTAssertEqual(Data(try rgbaBytes(outputBody)), Data(try rgbaBytes(expectedBody)))
    }

    func testRepeatedContentSelfCheckRejectsPeriodicTiling() throws {
        let tile = try makeImage(seed: 223, width: 80, height: 100)
        let tileBytes = try rgbaBytes(tile)
        let image = try image(
            bytes: tileBytes + tileBytes + tileBytes + tileBytes,
            width: 80,
            height: 400
        )

        XCTAssertThrowsError(try RepeatedContentSelfCheck.validate(
            image: image,
            expectedDisplacements: [100, 100],
            fixedColumnRanges: [0..<80]
        )) {
            XCTAssertEqual($0 as? ScrollingCaptureFailureCode, .internalStitchError)
        }
    }

    func testBalancedDirectionReversalRequiresTwoConsecutivePairs() {
        var tracker = DirectionReversalTracker()
        let config = ScrollingCaptureConfig.default

        XCTAssertFalse(tracker.recordReverse(config: config))
        XCTAssertTrue(tracker.recordReverse(config: config))
        tracker.recordForward()
        XCTAssertFalse(tracker.recordReverse(config: config))
    }

    func testStrictDirectionReversalFailsOnFirstPair() {
        var tracker = DirectionReversalTracker()
        var config = ScrollingCaptureConfig.default
        config.strictness = .strict

        XCTAssertTrue(tracker.recordReverse(config: config))
    }

    func testRealtimeRegistrationFailsFastWhenOverlapIsInsufficient() throws {
        let before = try makeImage(seed: 213, width: 240, height: 400)
        let after = try makeImage(seed: 214, width: 240, height: 400)

        XCTAssertThrowsError(try RealtimeScrollRegistrationValidator.validate(
            previous: before,
            current: after,
            estimatedDisplacement: 330,
            requiredDirection: nil
        )) {
            XCTAssertEqual($0 as? ScrollingCaptureFailureCode, .scrollTooFast)
        }
    }

    func testAutomaticRegistrationDoesNotUseManualScrollTooFastGate() throws {
        let before = try makeImage(seed: 224, width: 240, height: 400)
        let after = try shiftedImage(before, deltaY: 330, fillSeed: 225)

        XCTAssertNoThrow(try RealtimeScrollRegistrationValidator.validate(
            previous: before,
            current: after,
            estimatedDisplacement: 330,
            requiredDirection: nil,
            isManualScrolling: false
        ))
    }

    func testBalancedAndStrictThresholdProfilesRemainDistinct() {
        let balanced = ScrollingCaptureConfig.default
        var strict = ScrollingCaptureConfig.default
        strict.strictness = .strict

        XCTAssertEqual(balanced.effectiveRegistrationPeakRatioThreshold, 1.15)
        XCTAssertEqual(strict.effectiveRegistrationPeakRatioThreshold, 1.30)
        XCTAssertEqual(balanced.effectiveRegistrationEstimateTolerancePixels, 16)
        XCTAssertEqual(strict.effectiveRegistrationEstimateTolerancePixels, 12)
        XCTAssertEqual(balanced.effectiveDirectionReversalPairLimit, 2)
        XCTAssertEqual(strict.effectiveDirectionReversalPairLimit, 1)
        XCTAssertEqual(balanced.effectiveLayoutMinimumFixedColumnRatio, 0.05)
        XCTAssertEqual(strict.effectiveLayoutMinimumFixedColumnRatio, 0.08)
        XCTAssertLessThanOrEqual(balanced.effectiveAutomaticScrollRatio, 0.60)
    }

    func testPeriodicScrollingContentIsNotRejectedWithoutStaticColumns() throws {
        let tile = try makeImage(seed: 226, width: 80, height: 100)
        let tileBytes = try rgbaBytes(tile)
        let image = try image(
            bytes: tileBytes + tileBytes + tileBytes + tileBytes,
            width: 80,
            height: 400
        )

        XCTAssertNoThrow(try RepeatedContentSelfCheck.validate(
            image: image,
            expectedDisplacements: [100, 100],
            fixedColumnRanges: []
        ))
    }

    func testRealtimeRegistrationRejectsDirectionReversal() throws {
        let upper = try makeImage(seed: 215, width: 240, height: 400)
        let lower = try shiftedImage(upper, deltaY: 90, fillSeed: 216)

        XCTAssertThrowsError(try RealtimeScrollRegistrationValidator.validate(
            previous: lower,
            current: upper,
            estimatedDisplacement: 90,
            requiredDirection: .down
        )) {
            XCTAssertEqual($0 as? ScrollingCaptureFailureCode, .directionReversed)
        }
    }

    func testAmbiguousInternalFixedBandFailsWithoutProducingOutput() throws {
        let source = try makeImage(seed: 217, width: 300, height: 900)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 300, height: 300)))
        let offsets = [0, 150, 300]
        let frames = try offsets.map { offset -> CGImage in
            let shifted = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: offset, width: 300, height: 300)))
            return try imageWithFixedBand(before: first, shifted: shifted, minX: 120, maxX: 180)
        }
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        XCTAssertThrowsError(try ImageStitcher().stitch(
            frames: frames,
            injectedDisplacements: [150, 150],
            backingScaleFactor: 1
        )) {
            XCTAssertEqual($0 as? ScrollingCaptureFailureCode, .layoutAmbiguous)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path), [])
    }

    func testColumnSplitDetectsFixedLeftSidebar() throws {
        let before = try makeImage(seed: 201, width: 400, height: 500)
        let shifted = try shiftedImage(before, deltaY: 48, fillSeed: 202)
        let after = try imageWithFixedColumns(before: before, shifted: shifted, leftWidth: 120, rightWidth: 0)
        let detection = try XCTUnwrap(ColumnSplitDetector.detect(before: before, after: after))

        XCTAssertEqual(detection.layout.type, .fixedLeft)
        XCTAssertEqual(detection.layout.scrollingMinX, 118, accuracy: 3)
        XCTAssertEqual(detection.layout.scrollingMaxX, 400)
    }

    func testColumnSplitDetectsFixedColumnsOnBothSides() throws {
        let before = try makeImage(seed: 203, width: 500, height: 500)
        let shifted = try shiftedImage(before, deltaY: 52, fillSeed: 204)
        let after = try imageWithFixedColumns(before: before, shifted: shifted, leftWidth: 90, rightWidth: 110)
        let detection = try XCTUnwrap(ColumnSplitDetector.detect(before: before, after: after))

        XCTAssertEqual(detection.layout.type, .fixedBoth)
        XCTAssertEqual(detection.layout.scrollingMinX, 88, accuracy: 3)
        XCTAssertEqual(detection.layout.scrollingMaxX, 392, accuracy: 3)
    }

    func testColumnSplitReturnsNilForFullyScrollingSelection() throws {
        let before = try makeImage(seed: 205, width: 400, height: 500)
        let after = try shiftedImage(before, deltaY: 45, fillSeed: 206)

        XCTAssertNil(ColumnSplitDetector.detect(before: before, after: after))
    }

    func testColumnSplitReturnsNilForFloatingStaticBand() throws {
        let before = try makeImage(seed: 207, width: 400, height: 500)
        let shifted = try shiftedImage(before, deltaY: 45, fillSeed: 208)
        let after = try imageWithFixedBand(before: before, shifted: shifted, minX: 150, maxX: 230)

        XCTAssertNil(ColumnSplitDetector.detect(before: before, after: after))
    }

    func testProbeScrollAmountStaysSmallAndBounded() {
        let config = ScrollingCaptureConfig.default

        XCTAssertEqual(config.probeScrollAmount(pixelHeight: 100), 24)
        XCTAssertEqual(config.probeScrollAmount(pixelHeight: 1_000), 60)
        XCTAssertEqual(config.probeScrollAmount(pixelHeight: 2_000), 64)
    }

    func testLivePreviewGrowsDownwardWithoutDuplicateRows() throws {
        let source = try makeImage(seed: 101, width: 180, height: 600)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 300)))
        let second = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 200, width: 180, height: 300)))
        let preview = try XCTUnwrap(ScrollingLivePreviewComposer.append(
            base: first,
            frame: second,
            displacement: 200,
            direction: .down
        ))
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 500)))

        XCTAssertEqual(Data(try rgbaBytes(preview)), Data(try rgbaBytes(expected)))
    }

    func testLivePreviewGrowsUpwardWithoutDuplicateRows() throws {
        let source = try makeImage(seed: 102, width: 180, height: 600)
        let lower = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 200, width: 180, height: 300)))
        let upper = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 300)))
        let preview = try XCTUnwrap(ScrollingLivePreviewComposer.append(
            base: lower,
            frame: upper,
            displacement: 200,
            direction: .up
        ))
        let expected = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 180, height: 500)))

        XCTAssertEqual(Data(try rgbaBytes(preview)), Data(try rgbaBytes(expected)))
    }

    func testTextureVotingAllowsLowTextureSelectionWithWarning() throws {
        let before = try solidImage(value: 245, width: 320, height: 320)
        let after = try solidImage(value: 245, width: 320, height: 320)
        let analysis = try XCTUnwrap(TextureWeightedGridAnalyzer.analyze(before: before, after: after))

        XCTAssertEqual(analysis.validBlockCount, 0)
        XCTAssertEqual(analysis.verdict(), .lowTexture)
    }

    func testTextureVotingAllowsFixedElementsWithWarning() throws {
        let before = try makeImage(seed: 1, width: 320, height: 320)
        let after = try imageChangingBlocks(source: before, dimension: 8, changedBlockCount: 20)
        let analysis = try XCTUnwrap(TextureWeightedGridAnalyzer.analyze(before: before, after: after))

        XCTAssertEqual(analysis.dimension, 8)
        XCTAssertEqual(analysis.changedValidBlockCount, 20)
        XCTAssertEqual(analysis.verdict(), .fixedElements)
    }

    func testTextureVotingSupportsWhenSixtyPercentOfValidBlocksChange() throws {
        let before = try makeImage(seed: 2, width: 320, height: 320)
        let after = try imageChangingBlocks(source: before, dimension: 8, changedBlockCount: 40)
        let analysis = try XCTUnwrap(TextureWeightedGridAnalyzer.analyze(before: before, after: after))

        XCTAssertGreaterThanOrEqual(analysis.changedValidRatio, 0.60)
        XCTAssertEqual(analysis.verdict(), .scrollable)
    }

    func testTextureVotingUsesFourByFourGridForSmallSelection() throws {
        let before = try makeImage(seed: 3, width: 160, height: 160)
        let after = try imageChangingBlocks(source: before, dimension: 4, changedBlockCount: 8)
        let analysis = try XCTUnwrap(TextureWeightedGridAnalyzer.analyze(before: before, after: after))

        XCTAssertEqual(analysis.dimension, 4)
    }

    func testKnownVerticalTranslationIsSupported() throws {
        let before = try makeImage(seed: 7, width: 320, height: 420)
        let after = try shiftedImage(before, deltaY: 40, fillSeed: 99)
        let beforeData = [UInt8](before.dataProvider!.data! as Data)
        let afterData = [UInt8](after.dataProvider!.data! as Data)
        let rowBytes = before.bytesPerRow
        XCTAssertEqual(
            Array(beforeData[(40 * rowBytes)..<(41 * rowBytes)]),
            Array(afterData[0..<rowBytes])
        )

        let result = ScrollProbeAnalyzer.analyze(before: before, after: after)
        XCTAssertTrue(result.isSupported)
        XCTAssertNil(result.reason)
        XCTAssertEqual(result.bestDeltaY, 40, accuracy: 5)
        XCTAssertGreaterThan(result.bestScore, 0.98)
    }

    func testIdenticalFramesAreUnsupported() throws {
        let image = try makeImage(seed: 11, width: 320, height: 420)
        let result = ScrollProbeAnalyzer.analyze(before: image, after: image)

        XCTAssertFalse(result.isSupported)
        XCTAssertTrue(result.identicalHash)
        XCTAssertEqual(result.reason, .notScrollable)
    }

    func testUnrelatedDynamicFramesPassTextureVotingForStitchingFallback() throws {
        let before = try makeImage(seed: 21, width: 320, height: 420)
        let after = try makeImage(seed: 22, width: 320, height: 420)
        let result = ScrollProbeAnalyzer.analyze(before: before, after: after)

        XCTAssertTrue(result.isSupported)
        XCTAssertNil(result.reason)
        XCTAssertLessThan(result.bestScore, 0.86)
    }

    func testFixedLeftHalfAndScrollingRightHalfContinuesWithWarning() throws {
        let before = try makeImage(seed: 31, width: 400, height: 500)
        let shifted = try shiftedImage(before, deltaY: 50, fillSeed: 32)
        let after = try imageWithFixedLeftSidebar(before: before, shifted: shifted, sidebarWidth: 200)

        let result = ScrollProbeAnalyzer.analyze(before: before, after: after)

        XCTAssertTrue(result.isSupported)
        XCTAssertEqual(result.reason, .fixedElements)
    }

    func testNarrowFixedSidebarStillPassesTextureVote() throws {
        let before = try makeImage(seed: 41, width: 400, height: 500)
        let shifted = try shiftedImage(before, deltaY: 50, fillSeed: 42)
        let after = try imageWithFixedLeftSidebar(before: before, shifted: shifted, sidebarWidth: 75)

        let result = ScrollProbeAnalyzer.analyze(before: before, after: after)

        XCTAssertTrue(result.isSupported)
        XCTAssertNil(result.reason)
    }

    func testStitchMatcherDetectsDownwardScroll() throws {
        let before = try makeImage(seed: 51, width: 320, height: 420)
        let after = try shiftedImage(before, deltaY: 60, fillSeed: 52)

        let match = try XCTUnwrap(ScrollStitchMatcher.bestMatch(previous: before, current: after))

        XCTAssertEqual(match.direction, .down)
        XCTAssertEqual(match.overlap, 360, accuracy: 3)
        XCTAssertLessThan(match.difference, 1)
    }

    func testStitchMatcherDetectsUpwardScroll() throws {
        let later = try makeImage(seed: 61, width: 320, height: 420)
        let earlier = try shiftedImage(later, deltaY: 60, fillSeed: 62)

        let match = try XCTUnwrap(ScrollStitchMatcher.bestMatch(previous: earlier, current: later))

        XCTAssertEqual(match.direction, .up)
        XCTAssertEqual(match.overlap, 360, accuracy: 3)
    }

    func testStitchMatcherRejectsFramesWithoutOverlap() throws {
        let before = try makeImage(seed: 71, width: 320, height: 420)
        let after = try makeImage(seed: 72, width: 320, height: 420)

        XCTAssertNil(ScrollStitchMatcher.bestMatch(previous: before, current: after))
    }

    func testManualScrollValidatorSupportsUpAndDownButKeepsOneDirection() throws {
        let upper = try makeImage(seed: 75, width: 320, height: 420)
        let lower = try shiftedImage(upper, deltaY: 60, fillSeed: 76)

        let downward = ManualScrollFrameValidator.match(previous: upper, current: lower)
        XCTAssertEqual(downward?.direction, .down)
        XCTAssertNotNil(ManualScrollFrameValidator.match(
            previous: lower,
            current: upper,
            requiredDirection: .up
        ))
        XCTAssertNil(ManualScrollFrameValidator.match(
            previous: lower,
            current: upper,
            requiredDirection: .down
        ))
    }

    func testManualScrollValidatorIgnoresDetectedFixedSidebar() throws {
        let before = try makeImage(seed: 217, width: 400, height: 500)
        let shifted = try shiftedImage(before, deltaY: 60, fillSeed: 218)
        let after = try imageWithFixedColumns(before: before, shifted: shifted, leftWidth: 180, rightWidth: 0)
        let layout = try XCTUnwrap(ColumnSplitDetector.detect(before: before, after: after)?.layout)
        let matchingMinX = layout.scrollingMinX + 4
        let croppedBefore = try XCTUnwrap(before.cropping(to: CGRect(
            x: matchingMinX,
            y: 0,
            width: layout.scrollingMaxX - matchingMinX,
            height: before.height
        )))
        let croppedAfter = try XCTUnwrap(after.cropping(to: CGRect(
            x: matchingMinX,
            y: 0,
            width: layout.scrollingMaxX - matchingMinX,
            height: after.height
        )))
        let expectedOverlap = try XCTUnwrap(croppedBefore.cropping(to: CGRect(
            x: 0,
            y: 60,
            width: croppedBefore.width,
            height: 440
        )))
        let actualOverlap = try XCTUnwrap(croppedAfter.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: croppedAfter.width,
            height: 440
        )))
        XCTAssertEqual(Data(try rgbaBytes(expectedOverlap)), Data(try rgbaBytes(actualOverlap)))
        XCTAssertLessThan(ScrollStitchMatcher.overlapDifference(
            previous: before,
            current: after,
            overlap: 440,
            comparisonRange: matchingMinX..<layout.scrollingMaxX
        ), 1)
        XCTAssertNotNil(ScrollStitchMatcher.bestMatch(
            previous: before,
            current: after,
            comparisonRange: matchingMinX..<layout.scrollingMaxX
        ))
        let match = try XCTUnwrap(ManualScrollFrameValidator.match(previous: before, current: after))

        XCTAssertEqual(match.direction, .down)
        XCTAssertEqual(match.overlap, 440, accuracy: 3)
    }

    func testManualScrollValidatorRejectsTooLittleOverlap() throws {
        let before = try makeImage(seed: 77, width: 320, height: 420)
        let after = try shiftedImage(before, deltaY: 350, fillSeed: 78)

        XCTAssertNil(ManualScrollFrameValidator.match(previous: before, current: after))
    }

    func testImageStitcherReconstructsContinuousSourceWithoutDuplicateOrMissingRows() throws {
        let source = try makeImage(seed: 81, width: 240, height: 1_200)
        let frameHeight = 420
        let offsets = [0, 237, 503]
        let frames = try offsets.map { offset -> CGImage in
            guard let frame = source.cropping(to: CGRect(x: 0, y: offset, width: source.width, height: frameHeight)) else {
                throw TestError.imageCreation
            }
            return frame
        }
        var config = ScrollingCaptureConfig.default
        config.cropScrollbar = false
        config.peakRatioThreshold = 1.05
        config.registrationMAEThreshold = 1
        let result = try ImageStitcher(config: config).stitch(
            frames: frames,
            injectedDisplacements: [240, 260],
            backingScaleFactor: 1
        )
        XCTAssertEqual(result.registrations.count, 2)
        XCTAssertEqual(result.registrations[0].displacementY, offsets[1] - offsets[0], accuracy: 1)
        XCTAssertEqual(result.registrations[1].displacementY, offsets[2] - offsets[1], accuracy: 1)
        XCTAssertFalse(result.registrations[0].usedFallback)
        XCTAssertFalse(result.registrations[1].usedFallback)

        let expectedHeight = offsets.last! + frameHeight
        XCTAssertEqual(result.image.width, source.width)
        XCTAssertEqual(result.image.height, expectedHeight)
        guard let expected = source.cropping(to: CGRect(x: 0, y: 0, width: source.width, height: expectedHeight)) else {
            throw TestError.imageCreation
        }
        XCTAssertEqual(Data(try rgbaBytes(result.image)), Data(try rgbaBytes(expected)))
    }

    func testImageStitcherKeepsStickyHeaderOnceAndPreservesBodyRows() throws {
        let source = try makeImage(seed: 91, width: 220, height: 1_000)
        let header = try makeImage(seed: 92, width: 220, height: 36)
        let frameHeight = 360
        let offsets = [0, 211, 455]
        let frames = try offsets.map { offset in
            try frameWithFixedHeader(source: source, header: header, offset: offset, height: frameHeight)
        }
        var config = ScrollingCaptureConfig.default
        config.cropScrollbar = false
        config.peakRatioThreshold = 1.05
        config.registrationMAEThreshold = 1
        let result = try ImageStitcher(config: config).stitch(
            frames: frames,
            injectedDisplacements: [210, 245],
            backingScaleFactor: 1
        )

        XCTAssertEqual(result.stickyHeaderHeight, header.height)
        XCTAssertEqual(result.registrations[0].displacementY, 211, accuracy: 1)
        XCTAssertEqual(result.registrations[1].displacementY, 244, accuracy: 1)
        let expected = try frameWithFixedHeader(
            source: source,
            header: header,
            offset: 0,
            height: offsets.last! + frameHeight
        )
        XCTAssertEqual(result.image.height, expected.height)
        XCTAssertEqual(Data(try rgbaBytes(result.image)), Data(try rgbaBytes(expected)))
    }

    private func makeImage(seed: UInt64, width: Int, height: Int) throws -> CGImage {
        var generator = SeededGenerator(seed: seed)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = UInt8(truncatingIfNeeded: generator.next() >> 32)
            bytes[index + 1] = UInt8(truncatingIfNeeded: generator.next() >> 32)
            bytes[index + 2] = UInt8(truncatingIfNeeded: generator.next() >> 32)
            bytes[index + 3] = 255
        }
        return try image(bytes: bytes, width: width, height: height)
    }

    private func solidImage(value: UInt8, width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: value, count: width * height * 4)
        for index in stride(from: 3, to: bytes.count, by: 4) { bytes[index] = 255 }
        return try image(bytes: bytes, width: width, height: height)
    }

    private func imageChangingBlocks(source: CGImage, dimension: Int, changedBlockCount: Int) throws -> CGImage {
        guard let data = source.dataProvider?.data as Data? else { throw TestError.imageCreation }
        var output = [UInt8](data)
        let bytesPerPixel = source.bitsPerPixel / 8
        for block in 0..<min(changedBlockCount, dimension * dimension) {
            let row = block / dimension
            let column = block % dimension
            let minX = source.width * column / dimension
            let maxX = source.width * (column + 1) / dimension
            let minY = source.height * row / dimension
            let maxY = source.height * (row + 1) / dimension
            for y in minY..<maxY {
                for x in minX..<maxX {
                    let index = y * source.bytesPerRow + x * bytesPerPixel
                    output[index] = output[index] &+ 32
                    output[index + 1] = output[index + 1] &+ 32
                    output[index + 2] = output[index + 2] &+ 32
                }
            }
        }
        return try image(bytes: output, width: source.width, height: source.height)
    }

    private func shiftedImage(_ source: CGImage, deltaY: Int, fillSeed: UInt64) throws -> CGImage {
        guard let data = source.dataProvider?.data as Data? else { throw TestError.imageCreation }
        let width = source.width
        let height = source.height
        let bytesPerRow = source.bytesPerRow
        var output = [UInt8](repeating: 0, count: bytesPerRow * height)
        let sourceBytes = [UInt8](data)
        let copiedRows = height - deltaY
        for y in 0..<copiedRows {
            let sourceStart = (y + deltaY) * bytesPerRow
            let targetStart = y * bytesPerRow
            output.replaceSubrange(targetStart..<(targetStart + bytesPerRow), with: sourceBytes[sourceStart..<(sourceStart + bytesPerRow)])
        }
        var generator = SeededGenerator(seed: fillSeed)
        for index in (copiedRows * bytesPerRow)..<output.count {
            output[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: generator.next() >> 32)
        }
        return try image(bytes: output, width: width, height: height)
    }

    private func imageWithFixedLeftSidebar(before: CGImage, shifted: CGImage, sidebarWidth: Int) throws -> CGImage {
        guard let beforeData = before.dataProvider?.data as Data?,
              let shiftedData = shifted.dataProvider?.data as Data? else { throw TestError.imageCreation }
        let bytesPerPixel = before.bitsPerPixel / 8
        let bytesPerRow = before.bytesPerRow
        var output = [UInt8](shiftedData)
        let original = [UInt8](beforeData)
        let fixedBytes = sidebarWidth * bytesPerPixel
        for y in 0..<before.height {
            let rowStart = y * bytesPerRow
            output.replaceSubrange(
                rowStart..<(rowStart + fixedBytes),
                with: original[rowStart..<(rowStart + fixedBytes)]
            )
        }
        return try image(bytes: output, width: before.width, height: before.height)
    }

    private func imageWithFixedColumns(
        before: CGImage,
        shifted: CGImage,
        leftWidth: Int,
        rightWidth: Int
    ) throws -> CGImage {
        var output = try imageWithFixedBand(before: before, shifted: shifted, minX: 0, maxX: leftWidth)
        if rightWidth > 0 {
            output = try imageWithFixedBand(
                before: before,
                shifted: output,
                minX: before.width - rightWidth,
                maxX: before.width
            )
        }
        return output
    }

    private func imageWithFixedBand(before: CGImage, shifted: CGImage, minX: Int, maxX: Int) throws -> CGImage {
        guard let beforeData = before.dataProvider?.data as Data?,
              let shiftedData = shifted.dataProvider?.data as Data? else { throw TestError.imageCreation }
        let bytesPerPixel = before.bitsPerPixel / 8
        let bytesPerRow = before.bytesPerRow
        var output = [UInt8](shiftedData)
        let original = [UInt8](beforeData)
        for y in 0..<before.height {
            let rowStart = y * bytesPerRow
            let start = rowStart + minX * bytesPerPixel
            let end = rowStart + maxX * bytesPerPixel
            output.replaceSubrange(start..<end, with: original[start..<end])
        }
        return try image(bytes: output, width: before.width, height: before.height)
    }

    private func frameWithFixedHeader(source: CGImage, header: CGImage, offset: Int, height: Int) throws -> CGImage {
        guard let sourceFrame = source.cropping(to: CGRect(x: 0, y: offset, width: source.width, height: height)),
              let sourceData = sourceFrame.dataProvider?.data as Data?,
              let headerData = header.dataProvider?.data as Data? else { throw TestError.imageCreation }
        var output = [UInt8](sourceData)
        let headerBytes = [UInt8](headerData)
        for y in 0..<header.height {
            let outputStart = y * sourceFrame.bytesPerRow
            let headerStart = y * header.bytesPerRow
            output.replaceSubrange(
                outputStart..<(outputStart + sourceFrame.bytesPerRow),
                with: headerBytes[headerStart..<(headerStart + header.bytesPerRow)]
            )
        }
        return try image(bytes: output, width: source.width, height: height)
    }

    private func imageWithFixedHeader(frame: CGImage, header: CGImage) throws -> CGImage {
        guard frame.width == header.width else { throw TestError.imageCreation }
        var output = try rgbaBytes(frame)
        let headerBytes = try rgbaBytes(header)
        let bytesPerRow = frame.width * 4
        for y in 0..<header.height {
            let outputStart = y * bytesPerRow
            let headerStart = y * bytesPerRow
            output.replaceSubrange(
                outputStart..<(outputStart + bytesPerRow),
                with: headerBytes[headerStart..<(headerStart + bytesPerRow)]
            )
        }
        return try image(bytes: output, width: frame.width, height: frame.height)
    }

    private func frameWithFixedLeftColumn(
        fixed: CGImage,
        scrollingSource: CGImage,
        offset: Int,
        height: Int
    ) throws -> CGImage {
        guard fixed.height == height,
              let scrolling = scrollingSource.cropping(to: CGRect(
                x: 0,
                y: offset,
                width: scrollingSource.width,
                height: height
              )),
              let context = CGContext(
                data: nil,
                width: fixed.width + scrolling.width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw TestError.imageCreation }
        context.draw(fixed, in: CGRect(x: 0, y: 0, width: fixed.width, height: height))
        context.draw(scrolling, in: CGRect(x: fixed.width, y: 0, width: scrolling.width, height: height))
        guard let image = context.makeImage() else { throw TestError.imageCreation }
        return image
    }

    private func image(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw TestError.imageCreation }
        return image
    }

    private func rgbaBytes(_ image: CGImage) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw TestError.imageCreation }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

private enum TestError: Error {
    case imageCreation
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}
