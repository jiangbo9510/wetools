import CoreGraphics
import CryptoKit
import Foundation

public struct ScrollCorrelationPoint: Sendable {
    public let deltaY: Int
    public let score: Double

    public init(deltaY: Int, score: Double) {
        self.deltaY = deltaY
        self.score = score
    }
}

public enum ScrollProbeVerdict: String, Sendable {
    case supported = "SUPPORTED"
    case unsupported = "UNSUPPORTED"
}

public enum ScrollDetectionReason: String, Sendable {
    case notScrollable = "not scrollable"
    case mixedContent = "mixed content"
    case dynamicContent = "dynamic content"
    case fixedElements = "fixed elements"
    case lowTexture = "low texture"
}

public enum ScrollDetectionMessages {
    public static let mixedContentLocalizationKey = "screenshot.scrollingMixedContent"
    public static let mixedContent = "该区域包含固定不动的内容（如侧边栏/工具条），请重新框选纯滚动内容区域"
}

public struct ScrollDetectionConfiguration: Sendable {
    public let verticalStripeCount: Int
    public let stripeSampleColumnCount: Int
    public let staticStripeCoverageThreshold: Double
    public let staticHashDifferenceThreshold: Double
    public let maximumOffsetRatio: Double
    public let offsetStepRatio: Double
    public let similarityThreshold: Double
    public let minimumSimilarityGain: Double
    public let scrollAmountRatio: Double

    public static let `default` = ScrollDetectionConfiguration()

    public init(
        verticalStripeCount: Int = 4,
        stripeSampleColumnCount: Int = 8,
        staticStripeCoverageThreshold: Double = 0.70,
        staticHashDifferenceThreshold: Double = 0.005,
        maximumOffsetRatio: Double = 0.30,
        offsetStepRatio: Double = 0.01,
        similarityThreshold: Double = 0.86,
        minimumSimilarityGain: Double = 0.018,
        scrollAmountRatio: Double = 0.05
    ) {
        self.verticalStripeCount = max(1, verticalStripeCount)
        self.stripeSampleColumnCount = max(1, stripeSampleColumnCount)
        self.staticStripeCoverageThreshold = min(1, max(0, staticStripeCoverageThreshold))
        self.staticHashDifferenceThreshold = max(0, staticHashDifferenceThreshold)
        self.maximumOffsetRatio = maximumOffsetRatio
        self.offsetStepRatio = offsetStepRatio
        self.similarityThreshold = similarityThreshold
        self.minimumSimilarityGain = minimumSimilarityGain
        self.scrollAmountRatio = scrollAmountRatio
    }
}

public enum ScrollingCaptureStrictness: String, Sendable {
    case strict
    case balanced
}

public struct ScrollingCaptureConfig: Sendable {
    public var strictness: ScrollingCaptureStrictness = .balanced
    public var gridDimension = 4
    public var gridMAEThreshold = 2.0
    public var probeGridDimension = 8
    public var probeCompactGridDimension = 4
    public var probeMinimumBlockSidePixels = 24
    public var probeTextureVarianceThreshold = 4.0
    public var probeChangedMAEThreshold = 1.5
    public var probeSupportedChangedRatio = 0.60
    public var probeReverseTestChangedRatio = 0.10
    public var probeMinimumScrollPixels = 24
    public var probeMaximumScrollPixels = 64
    public var probeScrollHeightRatio = 0.06
    public var probeStableFrameMAEThreshold = 0.5
    public var probeRestoredFrameMAEThreshold = 1.0
    public var columnSplitSmoothingWidth = 5
    public var columnSplitDifferenceThreshold = 1.5
    public var columnSplitMinimumFixedRatio = 0.08
    public var columnSplitMaximumFixedRatio = 0.60
    public var columnSplitMinimumScrollingRatio = 0.40
    public var columnSplitBoundaryInsetPixels = 2
    public var probeSettleIntervalNanoseconds: UInt64 = 60_000_000
    public var probeSettleTimeoutNanoseconds: UInt64 = 800_000_000
    public var manualScrollDebounceNanoseconds: UInt64 = 220_000_000
    public var manualScrollPollNanoseconds: UInt64 = 50_000_000
    public var manualMinimumOverlapRatio = 0.20
    public var overlapWarningRatio = 0.35
    public var registrationPeakRatioThreshold = 1.15
    public var strictRegistrationPeakRatioThreshold = 1.30
    public var registrationEstimateTolerancePixels = 16
    public var strictRegistrationEstimateTolerancePixels = 12
    public var registrationContinuityTolerancePixels = 8
    public var directionReversalMinimumPixels = 40
    public var strictDirectionReversalMinimumPixels = 10
    public var directionReversalFrameRatio = 0.05
    public var directionReversalPairLimit = 2
    public var strictDirectionReversalPairLimit = 1
    public var stationaryDisplacementPixels = 3
    public var stationaryPairLimit = 2
    public var layoutAdaptiveDifferenceFloor = 1.0
    public var layoutAdaptivePeakRatio = 0.08
    public var layoutNoiseGapPixels = 4
    public var layoutMinimumFixedPixels = 3
    public var layoutAmbiguousInteriorMinimumPixels = 40
    public var layoutAmbiguousInteriorMinimumRatio = 0.05
    public var layoutMaximumFixedRowRatio = 0.35
    public var layoutMinimumFixedColumnRatio = 0.05
    public var strictLayoutMinimumFixedColumnRatio = 0.08
    public var layoutMaximumFixedColumnRatio = 0.70
    public var strictLayoutMaximumFixedColumnRatio = 0.60
    public var layoutMinimumScrollingColumnRatio = 0.40
    public var layoutTextureVarianceThreshold = 4.0
    public var repeatedContentCorrelationThreshold = 0.90
    public var repeatedContentMinimumColumnWidth = 40
    public var repeatedContentLagTolerancePixels = 5
    public var strictRepeatedContentLagTolerancePixels = 3
    public var automaticMaximumScrollRatio = 0.60
    public var scrollStepRatio = 0.60
    public var settleInitialNanoseconds: UInt64 = 280_000_000
    public var settleCheckNanoseconds: UInt64 = 90_000_000
    public var settledMAEThreshold = 0.8
    public var identicalMAEThreshold = 0.5
    public var identicalFrameLimit = 2
    public var maximumFrames = 60
    public var mouseInterferenceDistance: CGFloat = 48
    public var scrollbarWidthPoints: CGFloat = 16
    public var cropScrollbar = true
    public var minimumDisplacementRatio = 0.01
    public var strictMinimumDisplacementRatio = 0.20
    public var maximumDisplacementRatio = 0.90
    public var coarseDownsample = 2
    public var refinementRadius = 8
    public var registrationMAEThreshold = 20.0
    public var peakRatioThreshold = 1.3
    public var fixedRowMAEThreshold = 0.8
    public var debugSeams = false

    public static let `default` = ScrollingCaptureConfig()

    public init() {}

    public var effectiveRegistrationPeakRatioThreshold: Double {
        strictness == .strict ? strictRegistrationPeakRatioThreshold : registrationPeakRatioThreshold
    }

    public var effectiveMinimumDisplacementRatio: Double {
        strictness == .strict ? strictMinimumDisplacementRatio : minimumDisplacementRatio
    }

    public var effectiveRegistrationEstimateTolerancePixels: Int {
        strictness == .strict
            ? strictRegistrationEstimateTolerancePixels
            : registrationEstimateTolerancePixels
    }

    public var effectiveDirectionReversalPairLimit: Int {
        strictness == .strict ? strictDirectionReversalPairLimit : directionReversalPairLimit
    }

    public var effectiveLayoutMinimumFixedColumnRatio: Double {
        strictness == .strict
            ? strictLayoutMinimumFixedColumnRatio
            : layoutMinimumFixedColumnRatio
    }

    public var effectiveLayoutMaximumFixedColumnRatio: Double {
        strictness == .strict
            ? strictLayoutMaximumFixedColumnRatio
            : layoutMaximumFixedColumnRatio
    }

    public var effectiveRepeatedContentLagTolerancePixels: Int {
        strictness == .strict
            ? strictRepeatedContentLagTolerancePixels
            : repeatedContentLagTolerancePixels
    }

    public var effectiveAutomaticScrollRatio: Double {
        min(automaticMaximumScrollRatio, scrollStepRatio)
    }

    public func directionReversalTolerance(frameHeight: Int) -> Int {
        if strictness == .strict { return strictDirectionReversalMinimumPixels }
        return max(
            directionReversalMinimumPixels,
            Int((Double(frameHeight) * directionReversalFrameRatio).rounded(.up))
        )
    }

    public func ambiguousInteriorMinimumLength(axisLength: Int, strictMinimum: Int) -> Int {
        guard strictness == .balanced else { return strictMinimum }
        return max(
            layoutAmbiguousInteriorMinimumPixels,
            Int((Double(axisLength) * layoutAmbiguousInteriorMinimumRatio).rounded(.up))
        )
    }

    public var activeThresholdDescription: String {
        "strictness=\(strictness.rawValue) overlap>=\(manualMinimumOverlapRatio) "
            + "displacement>=\(effectiveMinimumDisplacementRatio) "
            + "peak>=\(effectiveRegistrationPeakRatioThreshold) "
            + "estimate<=\(effectiveRegistrationEstimateTolerancePixels)px "
            + "continuity<=\(registrationContinuityTolerancePixels)px "
            + "reversePairs=\(effectiveDirectionReversalPairLimit) "
            + "fixedColumns=\(effectiveLayoutMinimumFixedColumnRatio)...\(effectiveLayoutMaximumFixedColumnRatio)"
    }

    public func probeScrollAmount(pixelHeight: Int) -> Int {
        min(
            max(probeMinimumScrollPixels, probeMaximumScrollPixels),
            max(probeMinimumScrollPixels, Int((Double(max(1, pixelHeight)) * probeScrollHeightRatio).rounded()))
        )
    }
}

public struct GridChangeAnalysis: Sendable {
    public let changedBlockCount: Int
    public let totalBlockCount: Int
    public let blockMAE: [Double]

    public var changedRatio: Double {
        Double(changedBlockCount) / Double(max(1, totalBlockCount))
    }
}

public enum GridChangeAnalyzer {
    public static func analyze(
        before: CGImage,
        after: CGImage,
        dimension: Int,
        threshold: Double
    ) -> GridChangeAnalysis? {
        let width = min(before.width, after.width)
        let height = min(before.height, after.height)
        let dimension = max(1, dimension)
        guard let lhs = StitchPixelBuffer(image: before),
              let rhs = StitchPixelBuffer(image: after),
              width >= dimension,
              height >= dimension else { return nil }
        var scores: [Double] = []
        for row in 0..<dimension {
            let minY = height * row / dimension
            let maxY = height * (row + 1) / dimension
            for column in 0..<dimension {
                let minX = width * column / dimension
                let maxX = width * (column + 1) / dimension
                let xStep = max(1, (maxX - minX) / 48)
                let yStep = max(1, (maxY - minY) / 48)
                var total = 0.0
                var count = 0
                for y in stride(from: minY, to: maxY, by: yStep) {
                    for x in stride(from: minX, to: maxX, by: xStep) {
                        total += abs(Double(lhs.luminance(x: x, y: y)) - Double(rhs.luminance(x: x, y: y)))
                        count += 1
                    }
                }
                scores.append(count == 0 ? 0 : total / Double(count))
            }
        }
        return GridChangeAnalysis(
            changedBlockCount: scores.filter { $0 > threshold }.count,
            totalBlockCount: scores.count,
            blockMAE: scores
        )
    }
}

public struct TextureWeightedBlock: Sendable {
    public let row: Int
    public let column: Int
    public let minX: Int
    public let minY: Int
    public let width: Int
    public let height: Int
    public let textureVariance: Double
    public let mae: Double
    public let isValid: Bool
    public let isChanged: Bool
}

public enum TextureWeightedVerdict: Sendable {
    case scrollable
    case fixedElements
    case notScrollable
    case lowTexture
}

public struct TextureWeightedAnalysis: Sendable {
    public let dimension: Int
    public let blocks: [TextureWeightedBlock]

    public var validBlockCount: Int { blocks.filter(\.isValid).count }
    public var changedValidBlockCount: Int { blocks.filter { $0.isValid && $0.isChanged }.count }
    public var changedValidRatio: Double {
        guard validBlockCount > 0 else { return 0 }
        return Double(changedValidBlockCount) / Double(validBlockCount)
    }

    public func verdict(config: ScrollingCaptureConfig = .default) -> TextureWeightedVerdict {
        guard validBlockCount > 0 else { return .lowTexture }
        if changedValidRatio >= config.probeSupportedChangedRatio { return .scrollable }
        if changedValidRatio >= config.probeReverseTestChangedRatio { return .fixedElements }
        return .notScrollable
    }
}

public enum TextureWeightedGridAnalyzer {
    public static func analyze(
        before: CGImage,
        after: CGImage,
        config: ScrollingCaptureConfig = .default
    ) -> TextureWeightedAnalysis? {
        let width = min(before.width, after.width)
        let height = min(before.height, after.height)
        let fullDimension = max(1, config.probeGridDimension)
        let compactDimension = max(1, config.probeCompactGridDimension)
        let fullBlockSide = min(width / fullDimension, height / fullDimension)
        let dimension = fullBlockSide < config.probeMinimumBlockSidePixels ? compactDimension : fullDimension
        guard width >= dimension, height >= dimension,
              let lhs = StitchPixelBuffer(image: before),
              let rhs = StitchPixelBuffer(image: after) else { return nil }

        var blocks: [TextureWeightedBlock] = []
        blocks.reserveCapacity(dimension * dimension)
        for row in 0..<dimension {
            let minY = height * row / dimension
            let maxY = height * (row + 1) / dimension
            for column in 0..<dimension {
                let minX = width * column / dimension
                let maxX = width * (column + 1) / dimension
                let xStep = max(1, (maxX - minX) / 32)
                let yStep = max(1, (maxY - minY) / 32)
                var lhsSum = 0.0
                var lhsSquareSum = 0.0
                var rhsSum = 0.0
                var rhsSquareSum = 0.0
                var absoluteDifference = 0.0
                var count = 0
                for y in stride(from: minY, to: maxY, by: yStep) {
                    for x in stride(from: minX, to: maxX, by: xStep) {
                        let left = Double(lhs.luminance(x: x, y: y))
                        let right = Double(rhs.luminance(x: x, y: y))
                        lhsSum += left
                        lhsSquareSum += left * left
                        rhsSum += right
                        rhsSquareSum += right * right
                        absoluteDifference += abs(left - right)
                        count += 1
                    }
                }
                let divisor = Double(max(1, count))
                let lhsMean = lhsSum / divisor
                let rhsMean = rhsSum / divisor
                let lhsVariance = max(0, lhsSquareSum / divisor - lhsMean * lhsMean)
                let rhsVariance = max(0, rhsSquareSum / divisor - rhsMean * rhsMean)
                let textureVariance = max(lhsVariance, rhsVariance)
                let mae = absoluteDifference / divisor
                let isValid = textureVariance >= config.probeTextureVarianceThreshold
                blocks.append(TextureWeightedBlock(
                    row: row,
                    column: column,
                    minX: minX,
                    minY: minY,
                    width: maxX - minX,
                    height: maxY - minY,
                    textureVariance: textureVariance,
                    mae: mae,
                    isValid: isValid,
                    isChanged: isValid && mae > config.probeChangedMAEThreshold
                ))
            }
        }
        return TextureWeightedAnalysis(dimension: dimension, blocks: blocks)
    }
}

public enum ImageDifferenceAnalyzer {
    public static func meanAbsoluteError(_ before: CGImage, _ after: CGImage) -> Double? {
        let width = min(before.width, after.width)
        let height = min(before.height, after.height)
        guard width > 0, height > 0,
              let lhs = StitchPixelBuffer(image: before),
              let rhs = StitchPixelBuffer(image: after) else { return nil }
        let xStep = max(1, width / 256)
        let yStep = max(1, height / 256)
        var total = 0.0
        var count = 0
        for y in stride(from: 0, to: height, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                total += abs(Double(lhs.luminance(x: x, y: y)) - Double(rhs.luminance(x: x, y: y)))
                count += 1
            }
        }
        return count == 0 ? nil : total / Double(count)
    }
}

public enum ColumnSplitLayoutType: String, Sendable {
    case fixedLeft = "fixed-left"
    case fixedRight = "fixed-right"
    case fixedBoth = "fixed-both"
}

public struct ColumnSplitLayout: Sendable, Equatable {
    public let sourceWidth: Int
    public let scrollingMinX: Int
    public let scrollingMaxX: Int
    public let type: ColumnSplitLayoutType

    public var scrollingWidth: Int { scrollingMaxX - scrollingMinX }
    public var leftFixedWidth: Int { scrollingMinX }
    public var rightFixedWidth: Int { sourceWidth - scrollingMaxX }
    public var scrollingMidX: Int { scrollingMinX + scrollingWidth / 2 }
}

public struct ColumnSplitDetection: Sendable {
    public let layout: ColumnSplitLayout
    public let rawColumnDifferences: [Double]
    public let smoothedColumnDifferences: [Double]
}

public struct ColumnDifferenceProfile: Sendable {
    public let raw: [Double]
    public let smoothed: [Double]
}

public enum ColumnSplitDetector {
    public static func detect(
        before: CGImage,
        after: CGImage,
        config: ScrollingCaptureConfig = .default
    ) -> ColumnSplitDetection? {
        let width = min(before.width, after.width)
        guard let profile = differenceProfile(before: before, after: after, config: config) else { return nil }
        let raw = profile.raw
        let smoothed = profile.smoothed
        let scrolling = smoothed.map { $0 > config.columnSplitDifferenceThreshold }
        let leftStaticWidth = scrolling.prefix(while: { !$0 }).count
        let rightStaticWidth = scrolling.reversed().prefix(while: { !$0 }).count
        guard leftStaticWidth + rightStaticWidth < width else { return nil }

        let minimumFixedWidth = Int(ceil(Double(width) * config.columnSplitMinimumFixedRatio))
        let maximumFixedWidth = Int(floor(Double(width) * config.columnSplitMaximumFixedRatio))
        let leftQualifies = leftStaticWidth >= minimumFixedWidth && leftStaticWidth <= maximumFixedWidth
        let rightQualifies = rightStaticWidth >= minimumFixedWidth && rightStaticWidth <= maximumFixedWidth
        guard leftQualifies || rightQualifies else { return nil }
        if leftStaticWidth > 0 && !leftQualifies { return nil }
        if rightStaticWidth > 0 && !rightQualifies { return nil }

        let movingStart = leftQualifies ? leftStaticWidth : 0
        let movingEnd = rightQualifies ? width - rightStaticWidth : width
        guard movingEnd > movingStart,
              scrolling[movingStart..<movingEnd].allSatisfy({ $0 }),
              Double(movingEnd - movingStart) / Double(width) >= config.columnSplitMinimumScrollingRatio else {
            return nil
        }

        let inset = max(0, config.columnSplitBoundaryInsetPixels)
        let scrollingMinX = leftQualifies ? max(0, movingStart - inset) : 0
        let scrollingMaxX = rightQualifies ? min(width, movingEnd + inset) : width
        let type: ColumnSplitLayoutType = leftQualifies && rightQualifies
            ? .fixedBoth
            : (leftQualifies ? .fixedLeft : .fixedRight)
        return ColumnSplitDetection(
            layout: ColumnSplitLayout(
                sourceWidth: width,
                scrollingMinX: scrollingMinX,
                scrollingMaxX: scrollingMaxX,
                type: type
            ),
            rawColumnDifferences: raw,
            smoothedColumnDifferences: smoothed
        )
    }

    public static func differenceProfile(
        before: CGImage,
        after: CGImage,
        config: ScrollingCaptureConfig = .default
    ) -> ColumnDifferenceProfile? {
        let width = min(before.width, after.width)
        let height = min(before.height, after.height)
        guard width >= 16, height > 0,
              let lhs = StitchPixelBuffer(image: before),
              let rhs = StitchPixelBuffer(image: after) else { return nil }
        let yStep = max(1, height / 1_024)
        let raw = (0..<width).map { x -> Double in
            var total = 0.0
            var count = 0
            for y in stride(from: 0, to: height, by: yStep) {
                total += abs(Double(lhs.luminance(x: x, y: y)) - Double(rhs.luminance(x: x, y: y)))
                count += 1
            }
            return count == 0 ? 0 : total / Double(count)
        }
        let smoothingWidth = max(1, config.columnSplitSmoothingWidth | 1)
        let radius = smoothingWidth / 2
        let smoothed = raw.indices.map { x -> Double in
            let lower = max(0, x - radius)
            let upper = min(width - 1, x + radius)
            return raw[lower...upper].reduce(0, +) / Double(upper - lower + 1)
        }
        return ColumnDifferenceProfile(raw: raw, smoothed: smoothed)
    }
}

public struct ScrollDetectionResult: Sendable {
    public let identicalHash: Bool
    public let bestDeltaY: Int
    public let bestScore: Double
    public let zeroOffsetScore: Double
    public let verdict: ScrollProbeVerdict
    public let reason: ScrollDetectionReason?
    public let points: [ScrollCorrelationPoint]

    public var isSupported: Bool { verdict == .supported }

    public init(
        identicalHash: Bool,
        bestDeltaY: Int,
        bestScore: Double,
        zeroOffsetScore: Double,
        verdict: ScrollProbeVerdict,
        reason: ScrollDetectionReason?,
        points: [ScrollCorrelationPoint]
    ) {
        self.identicalHash = identicalHash
        self.bestDeltaY = bestDeltaY
        self.bestScore = bestScore
        self.zeroOffsetScore = zeroOffsetScore
        self.verdict = verdict
        self.reason = reason
        self.points = points
    }
}

public typealias ScrollProbeAnalysis = ScrollDetectionResult

public struct DefaultScrollDetectionEngine: Sendable {
    public let configuration: ScrollDetectionConfiguration

    public init(configuration: ScrollDetectionConfiguration = .default) {
        self.configuration = configuration
    }

    public func detect(before: CGImage, after: CGImage) -> ScrollDetectionResult {
        let width = min(before.width, after.width)
        let height = min(before.height, after.height)
        guard width >= 32, height >= 32,
              let lhs = PixelBuffer(image: before, width: width, height: height),
              let rhs = PixelBuffer(image: after, width: width, height: height),
              let texture = TextureWeightedGridAnalyzer.analyze(before: before, after: after) else {
            return ScrollDetectionResult(
                identicalHash: false,
                bestDeltaY: 0,
                bestScore: 0,
                zeroOffsetScore: 0,
                verdict: .unsupported,
                reason: .dynamicContent,
                points: []
            )
        }

        let identicalHash = lhs.digest == rhs.digest

        let maxDelta = max(1, Int(Double(height) * configuration.maximumOffsetRatio))
        let reportStep = max(1, Int(Double(height) * configuration.offsetStepRatio))
        var offsets = Array(stride(from: 0, through: maxDelta, by: reportStep))
        if offsets.last != maxDelta { offsets.append(maxDelta) }

        let points = offsets.map { delta in
            ScrollCorrelationPoint(
                deltaY: delta,
                score: ScrollProbeAnalyzer.similarity(before: lhs, after: rhs, deltaY: delta)
            )
        }
        let zeroScore = points.first?.score ?? 0
        let best = points.max { lhs, rhs in lhs.score < rhs.score } ?? ScrollCorrelationPoint(deltaY: 0, score: 0)
        let textureVerdict = texture.verdict()
        let supported = textureVerdict != .notScrollable
        let reason: ScrollDetectionReason?
        switch textureVerdict {
        case .scrollable: reason = nil
        case .fixedElements: reason = .fixedElements
        case .lowTexture: reason = .lowTexture
        case .notScrollable: reason = .notScrollable
        }

        return ScrollDetectionResult(
            identicalHash: identicalHash,
            bestDeltaY: best.deltaY,
            bestScore: best.score,
            zeroOffsetScore: zeroScore,
            verdict: supported ? .supported : .unsupported,
            reason: reason,
            points: points
        )
    }

    private func unsupportedResult(
        identicalHash: Bool,
        reason: ScrollDetectionReason
    ) -> ScrollDetectionResult {
        ScrollDetectionResult(
            identicalHash: identicalHash,
            bestDeltaY: 0,
            bestScore: identicalHash ? 1 : 0,
            zeroOffsetScore: identicalHash ? 1 : 0,
            verdict: .unsupported,
            reason: reason,
            points: []
        )
    }
}

public enum ScrollProbeAnalyzer {
    public static func analyze(before: CGImage, after: CGImage) -> ScrollProbeAnalysis {
        DefaultScrollDetectionEngine().detect(before: before, after: after)
    }

    public static func csv(for analysis: ScrollProbeAnalysis) -> String {
        let rows = analysis.points.map { "\($0.deltaY),\(String(format: "%.6f", $0.score))" }
        return (["delta_y_px,similarity_score"] + rows).joined(separator: "\n") + "\n"
    }

    fileprivate static func similarity(before: PixelBuffer, after: PixelBuffer, deltaY: Int) -> Double {
        max(
            directionalSimilarity(before: before, after: after, deltaY: deltaY, beforeStartsLower: true),
            directionalSimilarity(before: before, after: after, deltaY: deltaY, beforeStartsLower: false)
        )
    }

    private static func directionalSimilarity(
        before: PixelBuffer,
        after: PixelBuffer,
        deltaY: Int,
        beforeStartsLower: Bool
    ) -> Double {
        let overlapHeight = before.height - deltaY
        guard overlapHeight > 16 else { return 0 }

        // Correlation runs only after all stripes are known to be changing, so the
        // whole selection can be sampled while still ignoring outer window edges.
        let minX = max(0, before.width / 12)
        let maxX = min(before.width, before.width - before.width / 12)
        let xStep = max(1, (maxX - minX) / 180)
        let yStep = max(1, overlapHeight / 160)
        var absoluteDifference = 0.0
        var sampleCount = 0

        var y = 0
        while y < overlapHeight {
            var x = minX
            while x < maxX {
                let beforeY = beforeStartsLower ? y + deltaY : y
                let afterY = beforeStartsLower ? y : y + deltaY
                let lhs = before.luminance(x: x, y: beforeY)
                let rhs = after.luminance(x: x, y: afterY)
                absoluteDifference += abs(Double(lhs) - Double(rhs))
                sampleCount += 1
                x += xStep
            }
            y += yStep
        }

        guard sampleCount > 0 else { return 0 }
        return max(0, 1 - absoluteDifference / (Double(sampleCount) * 255))
    }
}

public enum ScrollStitchDirection: Sendable {
    case up
    case down
}

public struct ScrollStitchMatch: Sendable {
    public let direction: ScrollStitchDirection
    public let overlap: Int
    public let difference: Double
    public let peakRatio: Double
}

public enum ScrollingCaptureFailureCode: String, Error, Sendable, Equatable {
    case scrollTooFast = "SCROLL_TOO_FAST"
    case directionReversed = "DIRECTION_REVERSED"
    case registrationFailed = "REGISTRATION_FAILED"
    case layoutAmbiguous = "LAYOUT_AMBIGUOUS"
    case internalStitchError = "INTERNAL_STITCH_ERROR"
}

public struct DirectionReversalTracker: Sendable {
    private var consecutiveCount = 0

    public init() {}

    public mutating func recordReverse(config: ScrollingCaptureConfig) -> Bool {
        consecutiveCount += 1
        return consecutiveCount >= config.effectiveDirectionReversalPairLimit
    }

    public mutating func recordForward() {
        consecutiveCount = 0
    }
}

public struct FixedRegionLayout: Sendable, Equatable {
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let topFixedHeight: Int
    public let bottomFixedHeight: Int
    public let scrollingMinX: Int
    public let scrollingMaxX: Int

    public var bodyMinY: Int { topFixedHeight }
    public var bodyMaxY: Int { sourceHeight - bottomFixedHeight }
    public var bodyHeight: Int { bodyMaxY - bodyMinY }
    public var scrollingWidth: Int { scrollingMaxX - scrollingMinX }
    public var leftFixedWidth: Int { scrollingMinX }
    public var rightFixedWidth: Int { sourceWidth - scrollingMaxX }
    public var hasFixedRows: Bool { topFixedHeight > 0 || bottomFixedHeight > 0 }
    public var hasFixedColumns: Bool { leftFixedWidth > 0 || rightFixedWidth > 0 }
}

public enum ScrollStitchMatcher {
    public static func overlapDifference(
        previous: CGImage,
        current: CGImage,
        overlap: Int,
        comparisonRange: Range<Int>? = nil
    ) -> Double {
        guard let previousBuffer = StitchPixelBuffer(image: previous),
              let currentBuffer = StitchPixelBuffer(image: current) else { return .greatestFiniteMagnitude }
        return stripeDifference(
            previous: previousBuffer,
            current: currentBuffer,
            overlap: overlap,
            comparisonRange: comparisonRange
        )
    }

    public static func bestMatch(
        previous: CGImage,
        current: CGImage,
        requiredDirection: ScrollStitchDirection? = nil,
        comparisonRange: Range<Int>? = nil
    ) -> ScrollStitchMatch? {
        guard previous.width == current.width, previous.height == current.height else { return nil }

        func candidate(_ direction: ScrollStitchDirection) -> ScrollStitchMatch? {
            let first = direction == .down ? previous : current
            let second = direction == .down ? current : previous
            guard let result = bestOverlap(previous: first, current: second, comparisonRange: comparisonRange) else { return nil }
            return ScrollStitchMatch(
                direction: direction,
                overlap: result.overlap,
                difference: result.difference,
                peakRatio: result.peakRatio
            )
        }

        if let requiredDirection {
            return candidate(requiredDirection)
        }
        return [candidate(.down), candidate(.up)]
            .compactMap { $0 }
            .min { $0.difference < $1.difference }
    }

    private static func bestOverlap(
        previous: CGImage,
        current: CGImage,
        comparisonRange: Range<Int>?
    ) -> (overlap: Int, difference: Double, peakRatio: Double)? {
        let maxOverlap = min(previous.height, current.height) * 98 / 100
        let minOverlap = min(max(40, min(previous.height, current.height) / 12), maxOverlap)
        guard maxOverlap > minOverlap else { return nil }
        guard let previousBuffer = StitchPixelBuffer(image: previous),
              let currentBuffer = StitchPixelBuffer(image: current) else { return nil }

        var bestOverlap = minOverlap
        var bestDifference = Double.greatestFiniteMagnitude
        let step = 1
        for overlap in stride(from: minOverlap, through: maxOverlap, by: step) {
            let difference = stripeDifference(previous: previousBuffer, current: currentBuffer, overlap: overlap, comparisonRange: comparisonRange)
            if difference < bestDifference {
                bestOverlap = overlap
                bestDifference = difference
            }
        }

        for overlap in max(minOverlap, bestOverlap - step)...min(maxOverlap, bestOverlap + step) {
            let difference = stripeDifference(previous: previousBuffer, current: currentBuffer, overlap: overlap, comparisonRange: comparisonRange)
            if difference < bestDifference {
                bestOverlap = overlap
                bestDifference = difference
            }
        }
        var secondDifference = Double.greatestFiniteMagnitude
        for overlap in stride(from: minOverlap, through: maxOverlap, by: step)
        where abs(overlap - bestOverlap) > 2 {
            secondDifference = min(
                secondDifference,
                stripeDifference(
                    previous: previousBuffer,
                    current: currentBuffer,
                    overlap: overlap,
                    comparisonRange: comparisonRange
                )
            )
        }
        let peakRatio = secondDifference / max(bestDifference, 0.000_001)
        return bestDifference < 20 ? (bestOverlap, bestDifference, peakRatio) : nil
    }

    private static func stripeDifference(
        previous: StitchPixelBuffer,
        current: StitchPixelBuffer,
        overlap: Int,
        comparisonRange: Range<Int>?
    ) -> Double {
        let width = min(previous.width, current.width)
        let lowerBound = min(width, max(0, comparisonRange?.lowerBound ?? 0))
        let upperBound = min(width, max(lowerBound, comparisonRange?.upperBound ?? width))
        let insetX = max(0, (upperBound - lowerBound) / 8)
        let minX = lowerBound + insetX
        let maxX = upperBound - insetX
        let xStep = max(1, (maxX - minX) / 48)
        let yStep = max(1, overlap / 18)
        var total = 0.0
        var count = 0

        var y = 0
        while y < overlap {
            let previousY = previous.height - overlap + y
            var x = minX
            while x < maxX {
                total += abs(Double(previous.luminance(x: x, y: previousY)) - Double(current.luminance(x: x, y: y)))
                count += 1
                x += xStep
            }
            y += yStep
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }
}

public enum ManualScrollFrameValidator {
    public static func match(
        previous: CGImage,
        current: CGImage,
        requiredDirection: ScrollStitchDirection? = nil,
        config: ScrollingCaptureConfig = .default
    ) -> ScrollStitchMatch? {
        var comparisonRange: Range<Int>?
        if let layout = ColumnSplitDetector.detect(before: previous, after: current, config: config)?.layout {
            let edgeInset = max(0, config.columnSplitBoundaryInsetPixels * 2)
            let matchingMinX = layout.scrollingMinX + (layout.leftFixedWidth > 0 ? edgeInset : 0)
            let matchingMaxX = layout.scrollingMaxX - (layout.rightFixedWidth > 0 ? edgeInset : 0)
            if matchingMaxX > matchingMinX { comparisonRange = matchingMinX..<matchingMaxX }
        }
        guard let match = ScrollStitchMatcher.bestMatch(
            previous: previous,
            current: current,
            requiredDirection: requiredDirection,
            comparisonRange: comparisonRange
        ) else { return nil }
        let frameHeight = min(previous.height, current.height)
        let minimumOverlap = Int((Double(frameHeight) * config.manualMinimumOverlapRatio).rounded(.up))
        return match.overlap >= minimumOverlap ? match : nil
    }
}

public struct RealtimeScrollRegistration: Sendable {
    public let direction: ScrollStitchDirection
    public let displacementY: Int
    public let overlap: Int
    public let overlapRatio: Double
    public let peakRatio: Double
    public let usedEstimatedDisplacement: Bool
    public let shouldWarnSlowDown: Bool
}

public struct ScrollingPairDiagnostic: Sendable {
    public let pairIndex: Int
    public let direction: ScrollStitchDirection?
    public let displacementY: Int?
    public let overlapRatio: Double?
    public let difference: Double?
    public let peakRatio: Double?
    public let estimatedDisplacement: Int?
}

public struct ScrollingSequenceDiagnostic: Sendable {
    public let frameWidth: Int
    public let frameHeight: Int
    public let pairs: [ScrollingPairDiagnostic]
    public let layout: FixedRegionLayout?
    public let layoutError: ScrollingCaptureFailureCode?
    public let columnDifferenceMinimum: Double
    public let columnDifferenceMedian: Double
    public let columnDifferenceMaximum: Double
    public let columnDifferenceThreshold: Double
    public let staticColumnRatio: Double
    public let activeConfig: String
}

public enum ScrollingFrameDiagnostics {
    public static func analyze(
        frames: [CGImage],
        estimatedDisplacements: [Int] = [],
        config: ScrollingCaptureConfig = .default
    ) -> ScrollingSequenceDiagnostic? {
        guard let first = frames.first,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            return nil
        }
        let pairs = zip(frames, frames.dropFirst()).enumerated().map { index, images in
            let match = ScrollStitchMatcher.bestMatch(previous: images.0, current: images.1)
            return ScrollingPairDiagnostic(
                pairIndex: index,
                direction: match?.direction,
                displacementY: match.map { first.height - $0.overlap },
                overlapRatio: match.map { Double($0.overlap) / Double(first.height) },
                difference: match?.difference,
                peakRatio: match?.peakRatio,
                estimatedDisplacement: index < estimatedDisplacements.count
                    ? estimatedDisplacements[index]
                    : nil
            )
        }

        let buffers = frames.compactMap(StitchPixelBuffer.init(image:))
        let columnProfile: [Double]
        if buffers.count == frames.count, buffers.count > 1 {
            columnProfile = (0..<first.width).map { x in
                let values = zip(buffers, buffers.dropFirst()).map { lhs, rhs in
                    var total = 0.0
                    let step = max(1, first.height / 512)
                    var count = 0
                    for y in stride(from: 0, to: first.height, by: step) {
                        total += abs(
                            Double(lhs.luminance(x: x, y: y))
                                - Double(rhs.luminance(x: x, y: y))
                        )
                        count += 1
                    }
                    return total / Double(max(1, count))
                }.sorted()
                return values[values.count / 2]
            }
        } else {
            columnProfile = []
        }
        let sortedColumns = columnProfile.sorted()
        let peak = sortedColumns.isEmpty
            ? 0
            : sortedColumns[Int(Double(sortedColumns.count - 1) * 0.90)]
        let staticThreshold = max(
            config.layoutAdaptiveDifferenceFloor,
            peak * config.layoutAdaptivePeakRatio
        )
        let staticRatio = columnProfile.isEmpty
            ? 0
            : Double(columnProfile.filter { $0 <= staticThreshold }.count) / Double(columnProfile.count)

        let layout: FixedRegionLayout?
        let layoutError: ScrollingCaptureFailureCode?
        do {
            layout = try FidelityLayoutDetector.detect(frames: frames, config: config)
            layoutError = nil
        } catch let failure as ScrollingCaptureFailureCode {
            layout = nil
            layoutError = failure
        } catch {
            layout = nil
            layoutError = .layoutAmbiguous
        }
        return ScrollingSequenceDiagnostic(
            frameWidth: first.width,
            frameHeight: first.height,
            pairs: pairs,
            layout: layout,
            layoutError: layoutError,
            columnDifferenceMinimum: sortedColumns.first ?? 0,
            columnDifferenceMedian: sortedColumns.isEmpty ? 0 : sortedColumns[sortedColumns.count / 2],
            columnDifferenceMaximum: sortedColumns.last ?? 0,
            columnDifferenceThreshold: staticThreshold,
            staticColumnRatio: staticRatio,
            activeConfig: config.activeThresholdDescription
        )
    }
}

public enum RealtimeScrollRegistrationValidator {
    public static func validate(
        previous: CGImage,
        current: CGImage,
        estimatedDisplacement: Int?,
        previousDisplacement: Int? = nil,
        requiredDirection: ScrollStitchDirection?,
        isManualScrolling: Bool = true,
        config: ScrollingCaptureConfig = .default
    ) throws -> RealtimeScrollRegistration {
        let frameHeight = min(previous.height, current.height)
        guard frameHeight > 0 else { throw ScrollingCaptureFailureCode.registrationFailed }
        if isManualScrolling,
           let estimatedDisplacement,
           Double(frameHeight - abs(estimatedDisplacement)) / Double(frameHeight)
            < config.manualMinimumOverlapRatio {
            throw ScrollingCaptureFailureCode.scrollTooFast
        }

        var matchingConfig = config
        matchingConfig.manualMinimumOverlapRatio = 0.02
        let unrestricted = ManualScrollFrameValidator.match(
            previous: previous,
            current: current,
            requiredDirection: requiredDirection,
            config: matchingConfig
        )
        guard let match = unrestricted else {
            if let requiredDirection,
               let reverseMatch = ManualScrollFrameValidator.match(
                   previous: previous,
                   current: current,
                   requiredDirection: requiredDirection == .down ? .up : .down,
                   config: matchingConfig
               ) {
                let reverseDisplacement = frameHeight - reverseMatch.overlap
                if reverseDisplacement > config.directionReversalTolerance(frameHeight: frameHeight) {
                    throw ScrollingCaptureFailureCode.directionReversed
                }
                return RealtimeScrollRegistration(
                    direction: requiredDirection,
                    displacementY: 0,
                    overlap: frameHeight,
                    overlapRatio: 1,
                    peakRatio: reverseMatch.peakRatio,
                    usedEstimatedDisplacement: false,
                    shouldWarnSlowDown: false
                )
            }
            throw ScrollingCaptureFailureCode.registrationFailed
        }

        let measuredDisplacement = frameHeight - match.overlap
        let overlapRatio = Double(match.overlap) / Double(frameHeight)
        guard !isManualScrolling || overlapRatio >= config.manualMinimumOverlapRatio else {
            throw ScrollingCaptureFailureCode.scrollTooFast
        }

        let estimate = estimatedDisplacement.map { min(frameHeight - 1, max(0, abs($0))) }
        let estimateDeviation = estimate.map { abs($0 - measuredDisplacement) } ?? .max
        let continuityDeviation = previousDisplacement.map {
            abs($0 - measuredDisplacement)
        } ?? .max
        let lowConfidence = match.peakRatio < config.effectiveRegistrationPeakRatioThreshold
        let accepted = !lowConfidence
            || estimateDeviation <= config.effectiveRegistrationEstimateTolerancePixels
            || continuityDeviation <= config.registrationContinuityTolerancePixels
        if !accepted {
            throw ScrollingCaptureFailureCode.registrationFailed
        }
        let displacement = lowConfidence
                && estimateDeviation <= config.effectiveRegistrationEstimateTolerancePixels
            ? (estimate ?? measuredDisplacement)
            : measuredDisplacement
        let finalOverlap = frameHeight - displacement
        guard !isManualScrolling
                || Double(finalOverlap) / Double(frameHeight) >= config.manualMinimumOverlapRatio else {
            throw ScrollingCaptureFailureCode.scrollTooFast
        }

        return RealtimeScrollRegistration(
            direction: match.direction,
            displacementY: displacement,
            overlap: finalOverlap,
            overlapRatio: Double(finalOverlap) / Double(frameHeight),
            peakRatio: match.peakRatio,
            usedEstimatedDisplacement: lowConfidence,
            shouldWarnSlowDown: Double(finalOverlap) / Double(frameHeight) < config.overlapWarningRatio
        )
    }
}

public struct ImageStitchRegistration: Sendable {
    public let pairIndex: Int
    public let displacementY: Int
    public let overlap: Int
    public let seamRowInNextFrame: Int
    public let confidence: Double
    public let usedFallback: Bool
}

public struct ImageStitchResult: @unchecked Sendable {
    public let image: CGImage
    public let registrations: [ImageStitchRegistration]
    public let stickyHeaderHeight: Int
    public let croppedScrollbarWidth: Int
}

public enum FidelityLayoutDetector {
    public static func detect(
        frames: [CGImage],
        config: ScrollingCaptureConfig = .default
    ) throws -> FixedRegionLayout {
        guard frames.count >= 3,
              let first = frames.first,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw ScrollingCaptureFailureCode.layoutAmbiguous
        }
        let buffers = try frames.map { image -> StitchPixelBuffer in
            guard let buffer = StitchPixelBuffer(image: image) else {
                throw ScrollingCaptureFailureCode.layoutAmbiguous
            }
            return buffer
        }

        let rowProfile = medianDifferenceProfile(
            buffers: buffers,
            axisLength: first.height
        ) { lhs, rhs, row in
            meanDifference(lhs, rhs, xRange: 0..<first.width, yRange: row..<(row + 1))
        }
        let rowThreshold = adaptiveThreshold(profile: rowProfile, config: config)
        let rowStatic = closeSmallGaps(
            rowProfile.map { $0 <= rowThreshold },
            maximumGap: config.layoutNoiseGapPixels
        )
        let top = rowStatic.prefix(while: { $0 }).count
        let bottom = rowStatic.reversed().prefix(while: { $0 }).count
        guard top + bottom < first.height else {
            throw ScrollingCaptureFailureCode.layoutAmbiguous
        }
        try validateFixedEdges(
            staticMask: rowStatic,
            leading: top,
            trailing: bottom,
            maximumFixed: Int(Double(first.height) * config.layoutMaximumFixedRowRatio),
            axis: "row",
            textureAt: { rowTexture(buffer: buffers[0], row: $0) },
            config: config
        )

        let bodyMinY = top
        let bodyMaxY = first.height - bottom
        guard bodyMaxY - bodyMinY >= config.layoutMinimumFixedPixels else {
            throw ScrollingCaptureFailureCode.layoutAmbiguous
        }
        let columnProfile = medianDifferenceProfile(
            buffers: buffers,
            axisLength: first.width
        ) { lhs, rhs, column in
            meanDifference(lhs, rhs, xRange: column..<(column + 1), yRange: bodyMinY..<bodyMaxY)
        }
        let columnThreshold = adaptiveThreshold(profile: columnProfile, config: config)
        let columnStatic = closeSmallGaps(
            columnProfile.map { $0 <= columnThreshold },
            maximumGap: config.layoutNoiseGapPixels
        )
        let left = columnStatic.prefix(while: { $0 }).count
        let right = columnStatic.reversed().prefix(while: { $0 }).count
        guard left + right < first.width else {
            throw ScrollingCaptureFailureCode.layoutAmbiguous
        }
        let minimumColumn = Int(ceil(
            Double(first.width) * config.effectiveLayoutMinimumFixedColumnRatio
        ))
        let maximumColumn = Int(floor(
            Double(first.width) * config.effectiveLayoutMaximumFixedColumnRatio
        ))
        try validateFixedEdges(
            staticMask: columnStatic,
            leading: left,
            trailing: right,
            minimumFixed: minimumColumn,
            maximumFixed: maximumColumn,
            axis: "column",
            textureAt: { columnTexture(buffer: buffers[0], column: $0, yRange: bodyMinY..<bodyMaxY) },
            config: config
        )

        let scrollingMinX = left >= minimumColumn ? left : 0
        let scrollingMaxX = right >= minimumColumn ? first.width - right : first.width
        guard scrollingMaxX > scrollingMinX,
              Double(scrollingMaxX - scrollingMinX) / Double(first.width) >= config.layoutMinimumScrollingColumnRatio else {
            throw ScrollingCaptureFailureCode.layoutAmbiguous
        }
        return FixedRegionLayout(
            sourceWidth: first.width,
            sourceHeight: first.height,
            topFixedHeight: top >= config.layoutMinimumFixedPixels ? top : 0,
            bottomFixedHeight: bottom >= config.layoutMinimumFixedPixels ? bottom : 0,
            scrollingMinX: scrollingMinX,
            scrollingMaxX: scrollingMaxX
        )
    }

    private static func medianDifferenceProfile(
        buffers: [StitchPixelBuffer],
        axisLength: Int,
        difference: (StitchPixelBuffer, StitchPixelBuffer, Int) -> Double
    ) -> [Double] {
        (0..<axisLength).map { index in
            median(zip(buffers, buffers.dropFirst()).map { difference($0.0, $0.1, index) })
        }
    }

    private static func adaptiveThreshold(
        profile: [Double],
        config: ScrollingCaptureConfig
    ) -> Double {
        let sorted = profile.sorted()
        let peakIndex = min(max(0, sorted.count - 1), Int(Double(max(0, sorted.count - 1)) * 0.90))
        let scrollingPeak = sorted.isEmpty ? 0 : sorted[peakIndex]
        return max(config.layoutAdaptiveDifferenceFloor, scrollingPeak * config.layoutAdaptivePeakRatio)
    }

    private static func closeSmallGaps(_ mask: [Bool], maximumGap: Int) -> [Bool] {
        guard maximumGap > 0, mask.count > 2 else { return mask }
        var result = mask
        var index = 0
        while index < mask.count {
            guard !mask[index] else {
                index += 1
                continue
            }
            let start = index
            while index < mask.count, !mask[index] { index += 1 }
            if start > 0, index < mask.count, index - start <= maximumGap {
                for gapIndex in start..<index { result[gapIndex] = true }
            }
        }
        return result
    }

    private static func validateFixedEdges(
        staticMask: [Bool],
        leading: Int,
        trailing: Int,
        minimumFixed: Int = 3,
        maximumFixed: Int,
        axis: String,
        textureAt: (Int) -> Double,
        config: ScrollingCaptureConfig
    ) throws {
        let edgeRanges = [
            0..<leading,
            (staticMask.count - trailing)..<staticMask.count
        ]
        for range in edgeRanges where !range.isEmpty {
            let width = range.count
            let textured = range.contains { textureAt($0) >= config.layoutTextureVarianceThreshold }
            if textured && (width < minimumFixed || width > maximumFixed) {
                print(
                    "[FidelityLayoutDetector] ambiguous \(axis) edge width=\(width), "
                        + "allowed=\(minimumFixed)...\(maximumFixed)"
                )
                throw ScrollingCaptureFailureCode.layoutAmbiguous
            }
        }
        let interiorStart = leading
        let interiorEnd = staticMask.count - trailing
        guard interiorEnd > interiorStart else { return }
        let ambiguousMinimum = config.ambiguousInteriorMinimumLength(
            axisLength: staticMask.count,
            strictMinimum: minimumFixed
        )
        var runStart: Int?
        for index in interiorStart...interiorEnd {
            let isStatic = index < interiorEnd && staticMask[index]
            if isStatic, runStart == nil {
                runStart = index
            } else if !isStatic, let start = runStart {
                if index - start >= ambiguousMinimum,
                   (start..<index).contains(where: { textureAt($0) >= config.layoutTextureVarianceThreshold }) {
                    print(
                        "[FidelityLayoutDetector] ambiguous internal \(axis) static range="
                            + "\(start)..<\(index)"
                    )
                    throw ScrollingCaptureFailureCode.layoutAmbiguous
                }
                runStart = nil
            }
        }
    }

    private static func meanDifference(
        _ lhs: StitchPixelBuffer,
        _ rhs: StitchPixelBuffer,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Double {
        let xStep = max(1, xRange.count / 256)
        let yStep = max(1, yRange.count / 256)
        var total = 0.0
        var count = 0
        for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: yStep) {
            for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: xStep) {
                total += abs(Double(lhs.luminance(x: x, y: y)) - Double(rhs.luminance(x: x, y: y)))
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    private static func rowTexture(buffer: StitchPixelBuffer, row: Int) -> Double {
        variance((0..<buffer.width).map { Double(buffer.luminance(x: $0, y: row)) })
    }

    private static func columnTexture(
        buffer: StitchPixelBuffer,
        column: Int,
        yRange: Range<Int>
    ) -> Double {
        variance(yRange.map { Double(buffer.luminance(x: column, y: $0)) })
    }

    private static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

public enum ImageStitcherError: LocalizedError {
    case insufficientFrames
    case inconsistentFrameSizes
    case imageConversionFailed
    case canvasCreationFailed

    public var errorDescription: String? {
        switch self {
        case .insufficientFrames: return "At least two frames are required for a scrolling screenshot."
        case .inconsistentFrameSizes: return "Scrolling screenshot frames must have identical dimensions."
        case .imageConversionFailed: return "Unable to read scrolling screenshot pixels."
        case .canvasCreationFailed: return "Unable to create the long screenshot canvas."
        }
    }
}

public enum ScrollingLivePreviewComposer {
    public static func append(
        base: CGImage,
        frame: CGImage,
        displacement: Int,
        direction: ScrollStitchDirection
    ) -> CGImage? {
        let width = min(base.width, frame.width)
        let addedHeight = min(max(1, displacement), frame.height)
        let frameCropY = direction == .down ? frame.height - addedHeight : 0
        guard let strip = frame.cropping(to: CGRect(x: 0, y: frameCropY, width: width, height: addedHeight)),
              let context = CGContext(
                data: nil,
                width: width,
                height: base.height + addedHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        if direction == .down {
            context.draw(base, in: CGRect(x: 0, y: addedHeight, width: width, height: base.height))
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: addedHeight))
        } else {
            context.draw(strip, in: CGRect(x: 0, y: base.height, width: width, height: addedHeight))
            context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: base.height))
        }
        return context.makeImage()
    }
}

public struct ImageStitcher: Sendable {
    public let config: ScrollingCaptureConfig

    public init(config: ScrollingCaptureConfig = .default) {
        self.config = config
    }

    public func stitch(
        frames: [CGImage],
        injectedDisplacements: [Int] = [],
        backingScaleFactor: CGFloat = 2
    ) throws -> ImageStitchResult {
        guard frames.count >= 3 else { throw ImageStitcherError.insufficientFrames }
        guard let first = frames.first else { throw ImageStitcherError.insufficientFrames }
        guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw ImageStitcherError.inconsistentFrameSizes
        }
        let layout = try FidelityLayoutDetector.detect(frames: frames, config: config)
        let cropRect = CGRect(
            x: layout.scrollingMinX,
            y: layout.bodyMinY,
            width: layout.scrollingWidth,
            height: layout.bodyHeight
        )
        let scrollingFrames = frames.compactMap { $0.cropping(to: cropRect) }
        guard scrollingFrames.count == frames.count else {
            throw ImageStitcherError.imageConversionFailed
        }
        let buffers = try scrollingFrames.map { image -> StitchPixelBuffer in
            guard let buffer = StitchPixelBuffer(image: image) else { throw ImageStitcherError.imageConversionFailed }
            return buffer
        }

        let comparisonWidth = layout.scrollingWidth
        var registrations: [ImageStitchRegistration] = []

        for pairIndex in 0..<(buffers.count - 1) {
            let estimate = pairIndex < injectedDisplacements.count
                ? injectedDisplacements[pairIndex]
                : nil
            registrations.append(try register(
                previous: buffers[pairIndex],
                next: buffers[pairIndex + 1],
                pairIndex: pairIndex,
                comparisonWidth: comparisonWidth,
                estimatedDisplacement: estimate,
                previousDisplacement: registrations.last?.displacementY
            ))
        }

        var offsets = [0]
        for registration in registrations {
            offsets.append(offsets.last! + registration.displacementY)
        }
        let seams = registrations.enumerated().map { index, registration in
            offsets[index + 1] + registration.seamRowInNextFrame
        }

        var segments: [CGImage] = []
        for index in scrollingFrames.indices {
            let startGlobal = index == 0 ? 0 : seams[index - 1]
            let endGlobal = index == scrollingFrames.count - 1
                ? offsets[index] + layout.bodyHeight
                : seams[index]
            let localStart = max(0, startGlobal - offsets[index])
            let localEnd = min(layout.bodyHeight, endGlobal - offsets[index])
            guard localEnd > localStart,
                  let segment = scrollingFrames[index].cropping(to: CGRect(
                    x: 0,
                    y: localStart,
                    width: comparisonWidth,
                    height: localEnd - localStart
                  )) else { continue }
            segments.append(segment)
        }

        let outputHeight = segments.reduce(0) { $0 + $1.height }
        guard outputHeight > 0,
              let context = CGContext(
                data: nil,
                width: comparisonWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw ImageStitcherError.canvasCreationFailed }

        var cursorY = outputHeight
        for (index, segment) in segments.enumerated() {
            cursorY -= segment.height
            context.draw(segment, in: CGRect(x: 0, y: cursorY, width: segment.width, height: segment.height))
            if config.debugSeams, index < segments.count - 1 {
                context.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.setLineWidth(1)
                context.move(to: CGPoint(x: 0, y: cursorY))
                context.addLine(to: CGPoint(x: comparisonWidth, y: cursorY))
                context.strokePath()
            }
        }
        guard let scrollingImage = context.makeImage(),
              let image = FidelityFrameComposer.compose(
                  firstFrame: first,
                  scrollingImage: scrollingImage,
                  layout: layout
              ) else {
            throw ImageStitcherError.canvasCreationFailed
        }
        try RepeatedContentSelfCheck.validate(
            image: image,
            expectedDisplacements: registrations.map(\.displacementY),
            fixedColumnRanges: [
                0..<layout.scrollingMinX,
                layout.scrollingMaxX..<layout.sourceWidth
            ].filter { !$0.isEmpty },
            config: config
        )
        return ImageStitchResult(
            image: image,
            registrations: registrations,
            stickyHeaderHeight: layout.topFixedHeight,
            croppedScrollbarWidth: 0
        )
    }

    private func register(
        previous: StitchPixelBuffer,
        next: StitchPixelBuffer,
        pairIndex: Int,
        comparisonWidth: Int,
        estimatedDisplacement: Int?,
        previousDisplacement: Int?
    ) throws -> ImageStitchRegistration {
        let minDY = max(1, Int(Double(previous.height) * config.effectiveMinimumDisplacementRatio))
        let maxDY = min(previous.height - 2, Int(Double(previous.height) * config.maximumDisplacementRatio))
        guard maxDY >= minDY else { throw ScrollingCaptureFailureCode.registrationFailed }
        let coarseStep = max(1, (maxDY - minDY) / 100)
        let previousFeatures = rowFeatures(buffer: previous, width: comparisonWidth)
        let nextFeatures = rowFeatures(buffer: next, width: comparisonWidth)
        var candidates: [(dy: Int, score: Double)] = []

        if maxDY >= minDY {
            for dy in stride(from: minDY, through: maxDY, by: coarseStep) {
                candidates.append((dy, featureDistance(
                    previous: previousFeatures,
                    next: nextFeatures,
                    displacement: dy,
                    stickyHeader: 0
                )))
            }
        }
        let coarseCenters = candidates.sorted { $0.score < $1.score }.prefix(4).map(\.dy)
        let estimateCenter = estimatedDisplacement.map { min(max($0, minDY), maxDY) }
        var refinementOffsets = Set<Int>()
        for center in coarseCenters + (estimateCenter.map { [$0] } ?? []) {
            let refineStart = max(minDY, center - config.refinementRadius)
            let refineEnd = min(maxDY, center + config.refinementRadius)
            if refineEnd >= refineStart {
                refinementOffsets.formUnion(refineStart...refineEnd)
            }
        }
        var refined: [(dy: Int, score: Double)] = []
        for dy in refinementOffsets.sorted() {
            refined.append((dy, pixelMAE(
                previous: previous,
                next: next,
                displacement: dy,
                stickyHeader: 0,
                width: comparisonWidth
            )))
        }
        refined.sort { $0.score < $1.score }
        let best = refined.first
        let second = refined.first { candidate in
            guard let best else { return true }
            return abs(candidate.dy - best.dy) > 2
        }
        let peakRatio = (second?.score ?? .greatestFiniteMagnitude) / max(best?.score ?? 1, 0.000_001)
        let estimateDeviation = estimateCenter.flatMap { estimate in
            best.map { abs($0.dy - estimate) }
        } ?? .max
        let continuityDeviation = previousDisplacement.flatMap { previousDisplacement in
            best.map { abs($0.dy - previousDisplacement) }
        } ?? .max
        let reliable = best != nil
            && best!.score <= config.registrationMAEThreshold
            && (
                peakRatio >= config.effectiveRegistrationPeakRatioThreshold
                    || estimateDeviation <= config.effectiveRegistrationEstimateTolerancePixels
                    || continuityDeviation <= config.registrationContinuityTolerancePixels
            )
        let displacement: Int
        let usedEstimate: Bool
        if reliable, let best {
            displacement = best.dy
            usedEstimate = false
        } else if let estimateCenter,
                  estimateDeviation <= config.effectiveRegistrationEstimateTolerancePixels {
            displacement = estimateCenter
            usedEstimate = true
        } else {
            throw ScrollingCaptureFailureCode.registrationFailed
        }
        let overlap = previous.height - displacement
        guard Double(overlap) / Double(previous.height) >= config.manualMinimumOverlapRatio else {
            throw ScrollingCaptureFailureCode.scrollTooFast
        }
        let seam = bestSeamRow(
            previous: previous,
            next: next,
            displacement: displacement,
            stickyHeader: 0,
            width: comparisonWidth
        )
        return ImageStitchRegistration(
            pairIndex: pairIndex,
            displacementY: displacement,
            overlap: overlap,
            seamRowInNextFrame: seam,
            confidence: peakRatio,
            usedFallback: usedEstimate
        )
    }

    private func detectStickyHeader(buffers: [StitchPixelBuffer], comparisonWidth: Int) -> Int {
        guard buffers.count > 1 else { return 0 }
        let limit = buffers[0].height / 3
        var height = 0
        for y in 0..<limit {
            let maximumDifference = zip(buffers, buffers.dropFirst()).map {
                rowMAE($0.0, $0.1, firstY: y, secondY: y, width: comparisonWidth)
            }.max() ?? .greatestFiniteMagnitude
            if maximumDifference <= config.fixedRowMAEThreshold {
                height = y + 1
            } else if y > height + 3 {
                break
            }
        }
        return height >= 3 ? height : 0
    }

    private func rowFeatures(buffer: StitchPixelBuffer, width: Int) -> [StitchRowFeature] {
        (0..<buffer.height).map { y in
            let step = max(1, width / 64)
            var values: [Double] = []
            var hash: UInt64 = 0
            var previous = Int(buffer.luminance(x: 0, y: y))
            var x = 0
            var bit = 0
            while x < width {
                let value = Int(buffer.luminance(x: x, y: y))
                values.append(Double(value))
                if bit < 64, value >= previous { hash |= UInt64(1) << UInt64(bit) }
                previous = value
                bit += 1
                x += step
            }
            let mean = values.reduce(0, +) / Double(max(1, values.count))
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, values.count))
            return StitchRowFeature(mean: mean, variance: variance.squareRoot(), hash: hash)
        }
    }

    private func featureDistance(
        previous: [StitchRowFeature],
        next: [StitchRowFeature],
        displacement: Int,
        stickyHeader: Int
    ) -> Double {
        let overlap = previous.count - displacement
        guard overlap > stickyHeader + 2 else { return .greatestFiniteMagnitude }
        let step = max(1, (overlap - stickyHeader) / 160)
        var total = 0.0
        var count = 0
        for nextY in stride(from: stickyHeader, to: overlap, by: step) {
            let lhs = previous[nextY + displacement]
            let rhs = next[nextY]
            total += abs(lhs.mean - rhs.mean) / 255
            total += abs(lhs.variance - rhs.variance) / 128
            total += Double((lhs.hash ^ rhs.hash).nonzeroBitCount) / 64
            count += 1
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    private func pixelMAE(
        previous: StitchPixelBuffer,
        next: StitchPixelBuffer,
        displacement: Int,
        stickyHeader: Int,
        width: Int
    ) -> Double {
        let overlap = previous.height - displacement
        guard overlap > stickyHeader else { return .greatestFiniteMagnitude }
        let xStep = max(1, config.coarseDownsample)
        let yStep = max(1, config.coarseDownsample)
        var total = 0.0
        var count = 0
        for y in stride(from: stickyHeader, to: overlap, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                total += abs(Double(previous.luminance(x: x, y: y + displacement)) - Double(next.luminance(x: x, y: y)))
                count += 1
            }
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }

    private func bestSeamRow(
        previous: StitchPixelBuffer,
        next: StitchPixelBuffer,
        displacement: Int,
        stickyHeader: Int,
        width: Int
    ) -> Int {
        let overlap = previous.height - displacement
        guard overlap > stickyHeader else { return max(0, overlap) }
        var bestRow = overlap
        var bestScore = Double.greatestFiniteMagnitude
        for y in stickyHeader..<overlap {
            let score = rowMAE(previous, next, firstY: y + displacement, secondY: y, width: width)
            if score < bestScore {
                bestScore = score
                bestRow = y
            }
        }
        return bestRow
    }

    private func rowMAE(
        _ first: StitchPixelBuffer,
        _ second: StitchPixelBuffer,
        firstY: Int,
        secondY: Int,
        width: Int
    ) -> Double {
        let step = max(1, width / 256)
        var total = 0.0
        var count = 0
        for x in stride(from: 0, to: width, by: step) {
            total += abs(Double(first.luminance(x: x, y: firstY)) - Double(second.luminance(x: x, y: secondY)))
            count += 1
        }
        return count == 0 ? .greatestFiniteMagnitude : total / Double(count)
    }
}

public enum FidelityFrameComposer {
    public static func compose(
        firstFrame: CGImage,
        scrollingImage: CGImage,
        layout: FixedRegionLayout
    ) -> CGImage? {
        guard layout.sourceWidth == firstFrame.width,
              layout.sourceHeight == firstFrame.height,
              layout.bodyHeight > 0,
              layout.scrollingWidth == scrollingImage.width else { return nil }
        guard let source = RGBAStitchBuffer(image: firstFrame),
              let scrolling = RGBAStitchBuffer(image: scrollingImage) else { return nil }

        let outputHeight = layout.topFixedHeight + scrolling.height + layout.bottomFixedHeight
        var output = [UInt8](repeating: 0, count: source.width * outputHeight * 4)

        copyRectangle(
            from: source,
            sourceX: 0,
            sourceY: 0,
            width: source.width,
            height: layout.topFixedHeight,
            to: &output,
            outputWidth: source.width,
            destinationX: 0,
            destinationY: 0
        )
        copyRectangle(
            from: scrolling,
            sourceX: 0,
            sourceY: 0,
            width: scrolling.width,
            height: scrolling.height,
            to: &output,
            outputWidth: source.width,
            destinationX: layout.scrollingMinX,
            destinationY: layout.topFixedHeight
        )
        copyRectangle(
            from: source,
            sourceX: 0,
            sourceY: layout.bodyMaxY,
            width: source.width,
            height: layout.bottomFixedHeight,
            to: &output,
            outputWidth: source.width,
            destinationX: 0,
            destinationY: layout.topFixedHeight + scrolling.height
        )

        let fixedRanges = [
            0..<layout.scrollingMinX,
            layout.scrollingMaxX..<source.width
        ].filter { !$0.isEmpty }
        for range in fixedRanges {
            renderFixedColumn(
                source: source,
                sourceRange: range,
                layout: layout,
                scrollingHeight: scrolling.height,
                output: &output
            )
        }
        return makeRGBAImage(bytes: output, width: source.width, height: outputHeight)
    }

    private static func renderFixedColumn(
        source: RGBAStitchBuffer,
        sourceRange: Range<Int>,
        layout: FixedRegionLayout,
        scrollingHeight: Int,
        output: inout [UInt8]
    ) {
        let retainedHeight = min(layout.bodyHeight, scrollingHeight)
        copyRectangle(
            from: source,
            sourceX: sourceRange.lowerBound,
            sourceY: layout.bodyMinY,
            width: sourceRange.count,
            height: retainedHeight,
            to: &output,
            outputWidth: source.width,
            destinationX: sourceRange.lowerBound,
            destinationY: layout.topFixedHeight
        )
        let extensionHeight = scrollingHeight - retainedHeight
        guard extensionHeight > 0 else { return }

        let sampleEnd = layout.bodyMinY + retainedHeight
        let sampleStart = max(layout.bodyMinY, sampleEnd - 10)
        let transitionHeight = min(8, extensionHeight)
        for x in sourceRange {
            var median = [UInt8](repeating: 0, count: 4)
            for channel in 0..<3 {
                let values = (sampleStart..<sampleEnd)
                    .map { source.component(x: x, y: $0, channel: channel) }
                    .sorted()
                median[channel] = values[values.count / 2]
            }
            median[3] = 255
            for extensionY in 0..<extensionHeight {
                let destinationY = layout.topFixedHeight + retainedHeight + extensionY
                let outputIndex = (destinationY * source.width + x) * 4
                let transition = extensionY < transitionHeight
                    ? Double(extensionY + 1) / Double(transitionHeight + 1)
                    : 1
                for channel in 0..<3 {
                    let edge = Double(source.component(x: x, y: sampleEnd - 1, channel: channel))
                    output[outputIndex + channel] = UInt8(
                        (edge * (1 - transition) + Double(median[channel]) * transition).rounded()
                    )
                }
                output[outputIndex + 3] = 255
            }
        }
    }

    private static func copyRectangle(
        from source: RGBAStitchBuffer,
        sourceX: Int,
        sourceY: Int,
        width: Int,
        height: Int,
        to output: inout [UInt8],
        outputWidth: Int,
        destinationX: Int,
        destinationY: Int
    ) {
        guard width > 0, height > 0 else { return }
        for row in 0..<height {
            let sourceStart = ((sourceY + row) * source.width + sourceX) * 4
            let destinationStart = ((destinationY + row) * outputWidth + destinationX) * 4
            output[destinationStart..<(destinationStart + width * 4)] =
                source.bytes[sourceStart..<(sourceStart + width * 4)]
        }
    }

    fileprivate static func makeRGBAImage(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
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
        )
    }
}

public enum RepeatedContentSelfCheck {
    public static func maximumCorrelation(
        image: CGImage,
        expectedDisplacements: [Int],
        columnRanges: [Range<Int>],
        config: ScrollingCaptureConfig = .default
    ) -> Double {
        let positive = expectedDisplacements.filter { $0 > 0 }.sorted()
        guard let medianDisplacement = positive.isEmpty ? nil : positive[positive.count / 2],
              let buffer = RGBAStitchBuffer(image: image),
              buffer.height > medianDisplacement * 2 else { return 0 }
        let minimumLag = max(
            1,
            medianDisplacement - config.effectiveRepeatedContentLagTolerancePixels
        )
        let maximumLag = min(
            buffer.height / 2,
            medianDisplacement + config.effectiveRepeatedContentLagTolerancePixels
        )
        guard maximumLag >= minimumLag else { return 0 }
        let columns = Set(columnRanges.flatMap(Array.init))
        return columns.map { x in
            (minimumLag...maximumLag).map {
                verticalCorrelation(buffer: buffer, column: x, lag: $0)
            }.max() ?? 0
        }.max() ?? 0
    }

    public static func validate(
        image: CGImage,
        expectedDisplacements: [Int],
        fixedColumnRanges: [Range<Int>] = [],
        config: ScrollingCaptureConfig = .default
    ) throws {
        let positive = expectedDisplacements.filter { $0 > 0 }.sorted()
        guard let medianDisplacement = positive.isEmpty ? nil : positive[positive.count / 2],
              let buffer = RGBAStitchBuffer(image: image),
              buffer.height > medianDisplacement * 2 else { return }

        let minimumLag = max(
            1,
            medianDisplacement - config.effectiveRepeatedContentLagTolerancePixels
        )
        let maximumLag = min(
            buffer.height / 2,
            medianDisplacement + config.effectiveRepeatedContentLagTolerancePixels
        )
        guard maximumLag >= minimumLag else { return }

        let checkedColumns: Set<Int>
        if config.strictness == .strict {
            checkedColumns = Set(0..<buffer.width)
        } else {
            checkedColumns = Set(fixedColumnRanges.flatMap(Array.init))
            guard !checkedColumns.isEmpty else { return }
        }
        var suspiciousRun = 0
        var correlations: [Double] = []
        for x in 0..<buffer.width {
            guard checkedColumns.contains(x) else {
                correlations.append(0)
                suspiciousRun = 0
                continue
            }
            let correlation = (minimumLag...maximumLag).map {
                verticalCorrelation(buffer: buffer, column: x, lag: $0)
            }.max() ?? 0
            correlations.append(correlation)
            if correlation >= config.repeatedContentCorrelationThreshold {
                suspiciousRun += 1
                if suspiciousRun >= config.repeatedContentMinimumColumnWidth {
                    writeFailureHeatmap(
                        correlations: correlations
                            + [Double](repeating: 0, count: buffer.width - correlations.count),
                        expectedDisplacement: medianDisplacement
                    )
                    throw ScrollingCaptureFailureCode.internalStitchError
                }
            } else {
                suspiciousRun = 0
            }
        }
    }

    private static func writeFailureHeatmap(
        correlations: [Double],
        expectedDisplacement: Int
    ) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WetoolsScrollingSelfCheck-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let height = 64
            let pixels = correlations.flatMap { value in
                [UInt8](repeating: UInt8(min(255, max(0, value * 255))), count: height)
            }
            var imageData = Data("P5\n\(correlations.count) \(height)\n255\n".utf8)
            for y in 0..<height {
                for x in correlations.indices {
                    imageData.append(pixels[x * height + y])
                }
            }
            try imageData.write(to: directory.appendingPathComponent("autocorrelation_heatmap.pgm"))
            try "expected_displacement=\(expectedDisplacement)\nthreshold=0.9\n"
                .write(
                    to: directory.appendingPathComponent("self_check.log"),
                    atomically: true,
                    encoding: .utf8
                )
            print("[ScrollingScreenshot] self-check debug: \(directory.path)")
        } catch {
            print("[ScrollingScreenshot] unable to write self-check debug: \(error.localizedDescription)")
        }
    }

    private static func verticalCorrelation(
        buffer: RGBAStitchBuffer,
        column: Int,
        lag: Int
    ) -> Double {
        let count = buffer.height - lag
        guard count > 16 else { return 0 }
        let step = max(1, count / 512)
        var first: [Double] = []
        var second: [Double] = []
        for y in stride(from: 0, to: count, by: step) {
            first.append(luminance(buffer: buffer, x: column, y: y))
            second.append(luminance(buffer: buffer, x: column, y: y + lag))
        }
        guard first.count > 8 else { return 0 }
        let firstMean = first.reduce(0, +) / Double(first.count)
        let secondMean = second.reduce(0, +) / Double(second.count)
        var numerator = 0.0
        var firstEnergy = 0.0
        var secondEnergy = 0.0
        for index in first.indices {
            let lhs = first[index] - firstMean
            let rhs = second[index] - secondMean
            numerator += lhs * rhs
            firstEnergy += lhs * lhs
            secondEnergy += rhs * rhs
        }
        guard firstEnergy / Double(first.count) >= 4,
              secondEnergy / Double(second.count) >= 4 else { return 0 }
        return numerator / max(0.000_001, sqrt(firstEnergy * secondEnergy))
    }

    private static func luminance(buffer: RGBAStitchBuffer, x: Int, y: Int) -> Double {
        Double(buffer.component(x: x, y: y, channel: 0)) * 0.2126
            + Double(buffer.component(x: x, y: y, channel: 1)) * 0.7152
            + Double(buffer.component(x: x, y: y, channel: 2)) * 0.0722
    }
}

private struct StitchRowFeature {
    let mean: Double
    let variance: Double
    let hash: UInt64
}

private struct StitchPixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    let bytesPerRow: Int
    let bytesPerPixel: Int

    init?(image: CGImage) {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel >= 24,
              let data = image.dataProvider?.data as Data? else { return nil }
        width = image.width
        height = image.height
        bytes = [UInt8](data)
        bytesPerRow = image.bytesPerRow
        bytesPerPixel = image.bitsPerPixel / 8
    }

    func luminance(x: Int, y: Int) -> UInt8 {
        let index = y * bytesPerRow + x * bytesPerPixel
        let red = Double(bytes[index])
        let green = Double(bytes[index + 1])
        let blue = Double(bytes[index + 2])
        return UInt8(min(255, max(0, red * 0.2126 + green * 0.7152 + blue * 0.0722)))
    }
}

private struct RGBAStitchBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: CGImage) {
        let imageWidth = image.width
        let imageHeight = image.height
        var storage = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let created = storage.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: imageWidth,
                    height: imageHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: imageWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                        CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard created else { return nil }
        width = imageWidth
        height = imageHeight
        bytes = storage
    }

    func component(x: Int, y: Int, channel: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + channel]
    }

    func makeImage() -> CGImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

fileprivate struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    let bytesPerRow: Int
    let bytesPerPixel: Int
    let digest: SHA256.Digest

    init?(image: CGImage, width: Int, height: Int) {
        guard image.bitsPerComponent == 8,
              image.bitsPerPixel >= 24,
              let providerData = image.dataProvider?.data as Data? else { return nil }
        let bytes = [UInt8](providerData)
        self.width = width
        self.height = height
        self.bytes = bytes
        self.bytesPerRow = image.bytesPerRow
        self.bytesPerPixel = image.bitsPerPixel / 8
        self.digest = SHA256.hash(data: Data(bytes))
    }

    func luminance(x: Int, y: Int) -> UInt8 {
        let index = y * bytesPerRow + x * bytesPerPixel
        let red = Double(bytes[index])
        let green = Double(bytes[index + 1])
        let blue = Double(bytes[index + 2])
        return UInt8(min(255, max(0, red * 0.2126 + green * 0.7152 + blue * 0.0722)))
    }

    func stripeIsStatic(
        comparedWith other: PixelBuffer,
        minX: Int,
        maxX: Int,
        sampleColumnCount: Int,
        coverageThreshold: Double,
        differenceThreshold: Double
    ) -> Bool {
        let columnCount = min(sampleColumnCount, maxX - minX)
        guard columnCount > 0 else { return true }

        var staticColumnCount = 0
        for index in 0..<columnCount {
            let columnMinX = minX + (maxX - minX) * index / columnCount
            let columnMaxX = minX + (maxX - minX) * (index + 1) / columnCount
            if regionIsStatic(
                comparedWith: other,
                minX: columnMinX,
                maxX: columnMaxX,
                differenceThreshold: differenceThreshold
            ) {
                staticColumnCount += 1
            }
        }

        return Double(staticColumnCount) / Double(columnCount) >= coverageThreshold
    }

    private func regionIsStatic(
        comparedWith other: PixelBuffer,
        minX: Int,
        maxX: Int,
        differenceThreshold: Double
    ) -> Bool {
        let lhsHash = fastStripeHash(minX: minX, maxX: maxX)
        let rhsHash = other.fastStripeHash(minX: minX, maxX: maxX)
        if lhsHash == rhsHash { return true }
        guard differenceThreshold > 0 else { return false }
        return stripeDifferenceRatio(comparedWith: other, minX: minX, maxX: maxX) <= differenceThreshold
    }

    private func fastStripeHash(minX: Int, maxX: Int) -> UInt64 {
        let xStep = max(1, (maxX - minX) / 64)
        let yStep = max(1, height / 64)
        var hash: UInt64 = 14_695_981_039_346_656_037
        var y = 0
        while y < height {
            var x = minX
            while x < maxX {
                hash ^= UInt64(luminance(x: x, y: y) >> 2)
                hash &*= 1_099_511_628_211
                x += xStep
            }
            y += yStep
        }
        return hash
    }

    private func stripeDifferenceRatio(comparedWith other: PixelBuffer, minX: Int, maxX: Int) -> Double {
        let xStep = max(1, (maxX - minX) / 64)
        let yStep = max(1, height / 64)
        var changed = 0
        var total = 0
        var y = 0
        while y < height {
            var x = minX
            while x < maxX {
                if abs(Int(luminance(x: x, y: y)) - Int(other.luminance(x: x, y: y))) > 2 {
                    changed += 1
                }
                total += 1
                x += xStep
            }
            y += yStep
        }
        return total == 0 ? 1 : Double(changed) / Double(total)
    }
}
