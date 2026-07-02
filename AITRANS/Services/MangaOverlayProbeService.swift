import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Vision

enum MangaOverlayProbeServiceError: LocalizedError {
    case imageDecodeFailed
    case imageRenderFailed
    case pngEncodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "无法解码 test/1.png。"
        case .imageRenderFailed:
            "无法创建漫画探针输出画布。"
        case .pngEncodeFailed:
            "无法编码漫画探针 PNG 输出。"
        }
    }
}

struct MangaOverlayOCRBlock: Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var confidence: Float?
    var boundingBox: CGRect
    var rotationAngle: Int
    var bubbleID: Int?
    var bubbleAssignmentMethod: String
    var bubbleBoundingBox: CGRect?
    var source: String
    var crossBubbleMergeRejected: Bool
    var sliceIndex: Int?
    var sliceOverlapDeduped: Bool
}

struct MangaOverlayProbeCropping: Equatable, Sendable {
    var topRatio: CGFloat
    var bottomRatio: CGFloat
    var sideInsetRatio: CGFloat

    static let defaultValue = MangaOverlayProbeCropping(
        topRatio: 0.235,
        bottomRatio: 0.14,
        sideInsetRatio: 0
    )
}

private struct MangaOverlayOCRCandidate: Equatable, Sendable {
    var text: String
    var confidence: Float?
    var boundingBox: CGRect
    var rotationAngle: Int
    var bubbleID: Int?
    var bubbleAssignmentMethod: String
    var bubbleBoundingBox: CGRect?
    var source: String
    var sliceIndex: Int?
    var sliceOverlapDeduped: Bool
}

private struct MangaOverlayOCRCluster {
    var candidates: [MangaOverlayOCRCandidate]

    var boundingBox: CGRect {
        candidates.map(\.boundingBox).reduce(.null) { partial, rect in
            partial.union(rect)
        }
    }

    var bubbleID: Int? {
        candidates.first?.bubbleID
    }

    var bubbleAssignmentMethod: String {
        let methods = candidates.map(\.bubbleAssignmentMethod)
        if methods.contains("unassigned") {
            return "unassigned"
        }
        if methods.contains("overlapArea") {
            return "overlapArea"
        }
        return methods.first ?? "unknown"
    }

    var bubbleBoundingBox: CGRect? {
        candidates.first?.bubbleBoundingBox
    }

    var sliceIndex: Int? {
        let indexes = Set(candidates.compactMap(\.sliceIndex))
        return indexes.count == 1 ? indexes.first : nil
    }

    var sliceOverlapDeduped: Bool {
        candidates.contains { $0.sliceOverlapDeduped }
    }
}

private struct MangaOverlayBubbleCandidate: Equatable, Sendable {
    var index: Int
    var boundingBox: CGRect
    var source: String
    var area: CGFloat
    var confidence: Float
}

private struct MangaOverlayGlyphMaskPlan: Equatable, Sendable {
    var maskRect: CGRect
    var dilatedPixelOffsets: Set<Int>
    var pixelCount: Int
    var fillRects: [[Double]]
    var backgroundColor: [Double]?
    var backgroundStdDev: Double?
    var backgroundFillApplied: Bool
}

private struct MangaOverlayBubbleMaskRuntime: Equatable, Sendable {
    var width: Int
    var height: Int
    var ids: [Int]
    var safeRectsByBubbleID: [Int: CGRect]

    func dominantID(in rect: CGRect) -> (id: Int?, ratio: Double, counts: [String: Int]) {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return (nil, 0, [:]) }

        var counts: [Int: Int] = [:]
        var total = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let value = ids[y * width + x]
                guard value > 0 else { continue }
                counts[value - 1, default: 0] += 1
                total += 1
            }
        }
        let keyed = Dictionary(uniqueKeysWithValues: counts.map { (String($0.key), $0.value) })
        guard total > 0, let dominant = counts.max(by: { $0.value < $1.value }) else {
            return (nil, 0, keyed)
        }
        return (dominant.key, Double(dominant.value) / Double(total), keyed)
    }

    func coverageRatio(of rect: CGRect, bubbleID: Int?) -> Double {
        guard let bubbleID else { return 0 }
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }

        var covered = 0
        var total = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                total += 1
                if ids[y * width + x] == bubbleID + 1 {
                    covered += 1
                }
            }
        }
        return Double(covered) / Double(max(total, 1))
    }
}

struct MangaOverlayProbeBubble: Equatable, Codable, Sendable {
    var id: Int
    var bbox: [Double]
    var source: String
    var area: Double
    var confidence: Float
}

struct MangaOverlayTextRegion: Equatable, Codable, Sendable {
    var bbox: [Double]
    var bubbleID: Int?
    var source: String
    var confidence: Float?
    var assignmentMethod: String

    enum CodingKeys: String, CodingKey {
        case bbox
        case bubbleID
        case source
        case confidence
        case assignmentMethod
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bbox, forKey: .bbox)
        try container.encode(bubbleID, forKey: .bubbleID)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(assignmentMethod, forKey: .assignmentMethod)
    }
}

struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {
    var bubbles: [MangaOverlayProbeBubble]
    var textRegions: [MangaOverlayTextRegion]
    var bubbleAudits: [MangaOverlayBubbleSplitAudit]
    var assignedTextRegionCount: Int
    var unassignedTextRegionCount: Int
    var crossBubbleMergeRejectedCount: Int
    var notes: [String]
}

struct MangaOverlayBubbleSplitAudit: Equatable, Codable, Sendable {
    var bubbleID: Int
    var bbox: [Double]
    var source: String
    var area: Double
    var confidence: Double?
    var textRegionCount: Int
    var fusedBlockIndexes: [Int]
    var selectedBlockCount: Int
    var maxBlockOverlapRatio: Double
    var duplicateTextPairCount: Int
    var oversizedBubbleRisk: Bool
    var bubbleSplitCandidate: Bool
    var notes: [String]
}

struct MangaOverlaySliceOCRSlice: Equatable, Codable, Sendable {
    var index: Int
    var bbox: [Double]
    var overlapRatio: Double
    var rawObservationCount: Int
}

struct MangaOverlaySliceOCRCandidateSummary: Equatable, Codable, Sendable {
    var text: String
    var bbox: [Double]
    var sliceIndex: Int?
    var dedupedFromSliceIndexes: [Int]
    var bubbleID: Int?
    var source: String
    var sliceOverlapDeduped: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case bbox
        case sliceIndex
        case dedupedFromSliceIndexes
        case bubbleID
        case source
        case sliceOverlapDeduped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(bbox, forKey: .bbox)
        try container.encode(sliceIndex, forKey: .sliceIndex)
        try container.encode(dedupedFromSliceIndexes, forKey: .dedupedFromSliceIndexes)
        try container.encode(bubbleID, forKey: .bubbleID)
        try container.encode(source, forKey: .source)
        try container.encode(sliceOverlapDeduped, forKey: .sliceOverlapDeduped)
    }
}

struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {
    var enabled: Bool
    var reason: String
    var sourceImage: String
    var imageWidth: Int
    var imageHeight: Int
    var aspectRatio: Double
    var thresholdAspectRatio: Double
    var overlapRatio: Double
    var slices: [MangaOverlaySliceOCRSlice]
    var rawCandidateCount: Int
    var finalCandidateCount: Int
    var dedupedCandidateCount: Int
    var duplicateGroupCount: Int
    var residualOverlapDuplicateCount: Int
    var candidates: [MangaOverlaySliceOCRCandidateSummary]
    var notes: [String]
}

struct MangaOverlayPreprocessedOCRResult: Equatable, Sendable {
    var selectedText: String?
    var adaptiveText: String?
    var fixedText: String?
    var cropPaddingX: Double
    var cropPaddingY: Double
    var cropClampedByBubble: Bool
    var cropCandidatePreservesRawWords: Bool
    var cropFallbackTriggered: Bool
    var cropFallbackReason: String?
    var cropStrategyUsed: String
}

struct MangaOverlayTextRegionCropResult: Equatable, Sendable {
    var text: String?
    var regionBBox: [Double]
    var cropBBox: [Double]
    var clampSource: String
    var cropBBoxBeforeAssignmentCorrection: [Double]?
    var cropBBoxAfterAssignmentCorrection: [Double]?
    var cropBBoxBeforeSubRegionClamp: [Double]
    var cropBBoxAfterSubRegionClamp: [Double]
    var cropClampedByBubble: Bool
    var paddingX: Double
    var paddingY: Double
    var orientationHint: String
}

struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {
    var triggered: Bool
    var blockIndex: Int?
    var rawText: String
    var tightCropText: String?
    var fallbackText: String?
    var tightCropPreservesRawWords: Bool
    var fallbackPreservesRawWords: Bool
    var reason: String
}

private struct MangaOverlayRenderTextPlan: Equatable, Sendable {
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var lines: [String]
    var initialOverflow: Bool
    var minFontSizeReached: Bool
    var textTruncated: Bool
    var nonTransparentBounds: CGRect?
    var resolved: Bool
}

struct MangaOverlayProbeService: Sendable {
    private static let ocrScale: CGFloat = 2
    private static let sliceAspectRatioThreshold: CGFloat = 2.85
    private static let sliceOverlapRatio: CGFloat = 0.2
    private static let targetSliceAspectRatio: CGFloat = 2.05
    private static let minimumOverlayFontSize: CGFloat = 8

    func recognizeTextBlocks(
        in imageData: Data,
        cropping: MangaOverlayProbeCropping = .defaultValue,
        customWords: [String] = []
    ) async throws -> (
        image: CGImage,
        blocks: [MangaOverlayOCRBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        sliceOCR: MangaOverlaySliceOCRDiagnostics
    ) {
        try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let contentRect = Self.contentCropRect(for: image, cropping: cropping)
            let bubbles = try Self.detectBubbleCandidates(in: image, cropping: cropping, customWords: customWords)
            let sliceResult = try Self.recognizeRawCandidates(
                in: image,
                contentRect: contentRect,
                customWords: customWords,
                sourceImage: "test/1.png"
            )
            let rawCandidates = sliceResult.candidates
            let candidates = rawCandidates.map { Self.assignBubble(to: $0, bubbles: bubbles) }
            let mergeResult = Self.mergeCandidatesIntoBlocks(
                candidates,
                imageSize: CGSize(width: image.width, height: image.height)
            )
            let geometry = Self.bubbleGeometryDiagnostics(
                bubbles: bubbles,
                candidates: candidates,
                blocks: mergeResult.blocks,
                crossBubbleMergeRejectedCount: mergeResult.crossBubbleMergeRejectedCount
            )
            let sliceOCR = Self.sliceDiagnostics(
                from: sliceResult,
                assignedCandidates: candidates,
                sourceImage: "test/1.png",
                image: image
            )
            return (image, mergeResult.blocks, geometry, sliceOCR)
        }.value
    }

    func runSyntheticLongImageSliceProbe(
        imageData: Data,
        cropping: MangaOverlayProbeCropping = .defaultValue,
        customWords: [String] = []
    ) async throws -> MangaOverlaySliceOCRDiagnostics {
        try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let contentRect = Self.contentCropRect(for: image, cropping: cropping)
            let contentImage = try Self.croppedImage(image, rect: contentRect)
            let syntheticImage = try Self.verticallyStackedImage(contentImage, copies: 3)
            let syntheticRect = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(syntheticImage.width),
                height: CGFloat(syntheticImage.height)
            )
            let raw = try Self.recognizeRawCandidates(
                in: syntheticImage,
                contentRect: syntheticRect,
                customWords: customWords,
                sourceImage: "synthetic:test/1.png-content-x3"
            )
            let candidates = raw.candidates.map { candidate in
                var updated = candidate
                updated.source = "syntheticSliceOCR"
                return updated
            }
            return Self.sliceDiagnostics(
                from: raw,
                assignedCandidates: candidates,
                sourceImage: "synthetic:test/1.png-content-x3",
                image: syntheticImage
            )
        }.value
    }

    func recognizePreprocessedText(
        in image: CGImage,
        block: MangaOverlayOCRBlock,
        options: MangaOverlayPreprocessingOptions = .defaultValue
    ) async throws -> MangaOverlayPreprocessedOCRResult {
        try await Task.detached(priority: .userInitiated) {
            guard options.enabled else {
                return MangaOverlayPreprocessedOCRResult(
                    selectedText: nil,
                    adaptiveText: nil,
                    fixedText: nil,
                    cropPaddingX: 0,
                    cropPaddingY: 0,
                    cropClampedByBubble: false,
                    cropCandidatePreservesRawWords: false,
                    cropFallbackTriggered: false,
                    cropFallbackReason: "preprocessing disabled",
                    cropStrategyUsed: "disabled"
                )
            }
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let cropBounds = block.bubbleBoundingBox.map { $0.intersection(bounds) } ?? bounds
            let adaptivePadding = Self.adaptiveCropPadding(for: block.boundingBox)
            let adaptiveExpanded: CGRect
            if let bubbleBounds = block.bubbleBoundingBox?.intersection(bounds),
               Self.shouldUseBubbleWideCrop(for: block.boundingBox, bubbleBounds: bubbleBounds) {
                adaptiveExpanded = bubbleBounds
            } else {
                adaptiveExpanded = block.boundingBox.insetBy(dx: -adaptivePadding.x, dy: -adaptivePadding.y)
            }
            let adaptiveCropRect = Self.clamp(adaptiveExpanded, to: cropBounds).integral
            let fixedExpanded = Self.expand(block.boundingBox, by: 0.18, bounds: bounds)
            let fixedCropRect = Self.clamp(fixedExpanded, to: cropBounds).integral

            let adaptiveText = try Self.recognizePreprocessedText(in: image, cropRect: adaptiveCropRect, options: options)
            let fixedText = try Self.recognizePreprocessedText(in: image, cropRect: fixedCropRect, options: options)
            let adaptivePreservesRawWords = Self.cropCandidatePreservesRawWords(
                rawText: block.text,
                candidateText: adaptiveText
            )
            let fixedPreservesRawWords = Self.cropCandidatePreservesRawWords(
                rawText: block.text,
                candidateText: fixedText
            )
            let fallbackTriggered = !adaptivePreservesRawWords && fixedPreservesRawWords
            let selectedText = fallbackTriggered ? fixedText : adaptiveText
            let fallbackReason = fallbackTriggered
                ? "adaptive crop lost raw OCR words; fell back to fixed 18% crop"
                : nil

            return MangaOverlayPreprocessedOCRResult(
                selectedText: selectedText,
                adaptiveText: adaptiveText,
                fixedText: fixedText,
                cropPaddingX: Double(adaptivePadding.x),
                cropPaddingY: Double(adaptivePadding.y),
                cropClampedByBubble: block.bubbleBoundingBox != nil && !adaptiveExpanded.integral.equalTo(adaptiveCropRect),
                cropCandidatePreservesRawWords: fallbackTriggered ? fixedPreservesRawWords : adaptivePreservesRawWords,
                cropFallbackTriggered: fallbackTriggered,
                cropFallbackReason: fallbackReason,
                cropStrategyUsed: fallbackTriggered ? "fixedFallback" : "adaptive"
            )
        }.value
    }

    func recognizeTextRegionCrop(
        in image: CGImage,
        seedBBox: [Double],
        bubbleBBox: [Double]?,
        correctedBubbleBBox: [Double]? = nil,
        splitCandidateBBox: [Double]? = nil,
        subRegionBBox: [Double]? = nil,
        options: MangaOverlayPreprocessingOptions = .defaultValue,
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> MangaOverlayTextRegionCropResult {
        try await Task.detached(priority: .userInitiated) {
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let contentBounds = Self.contentCropRect(for: image, cropping: cropping).intersection(bounds)
            let seedRect = Self.clamp(Self.rect(from: seedBBox), to: contentBounds).integral
            guard seedRect.width >= 2, seedRect.height >= 2 else {
                return MangaOverlayTextRegionCropResult(
                    text: nil,
                    regionBBox: seedBBox,
                    cropBBox: Self.bboxArray(from: seedRect),
                    clampSource: "contentRect",
                    cropBBoxBeforeAssignmentCorrection: nil,
                    cropBBoxAfterAssignmentCorrection: nil,
                    cropBBoxBeforeSubRegionClamp: Self.bboxArray(from: seedRect),
                    cropBBoxAfterSubRegionClamp: Self.bboxArray(from: seedRect),
                    cropClampedByBubble: false,
                    paddingX: 0,
                    paddingY: 0,
                    orientationHint: "invalid"
                )
            }

            let orientationHint = seedRect.height > seedRect.width * 1.35 ? "verticalCandidate" : "horizontal"
            let estimatedFontSize = max(6, min(seedRect.width, seedRect.height))
            let paddingX = orientationHint == "verticalCandidate"
                ? max(4, min(estimatedFontSize * 0.72, seedRect.width * 0.55))
                : max(5, min(estimatedFontSize * 0.38, seedRect.width * 0.38))
            let paddingY = orientationHint == "verticalCandidate"
                ? max(5, min(estimatedFontSize * 0.46, seedRect.height * 0.40))
                : max(7, min(estimatedFontSize * 0.88, seedRect.height * 0.72))
            let regionRect = seedRect.insetBy(dx: -paddingX, dy: -paddingY)

            let fallbackLimit: CGRect
            if let bubbleBBox {
                let bubbleRect = Self.rect(from: bubbleBBox).intersection(bounds)
                fallbackLimit = bubbleRect.isNull ? contentBounds : bubbleRect.intersection(contentBounds)
            } else {
                fallbackLimit = contentBounds
            }
            let fallbackCropRect = Self.clamp(regionRect, to: fallbackLimit).integral
            let subRegionLimit: CGRect?
            if let subRegionBBox {
                let rect = Self.rect(from: subRegionBBox).intersection(contentBounds)
                subRegionLimit = rect.isNull || rect.width < 2 || rect.height < 2 ? nil : rect
            } else {
                subRegionLimit = nil
            }
            let correctedLimit: CGRect?
            if let correctedBubbleBBox {
                let rect = Self.rect(from: correctedBubbleBBox).intersection(contentBounds)
                correctedLimit = rect.isNull || rect.width < 2 || rect.height < 2 ? nil : rect
            } else {
                correctedLimit = nil
            }
            let splitLimit: CGRect?
            if let splitCandidateBBox {
                let rect = Self.rect(from: splitCandidateBBox).intersection(contentBounds)
                splitLimit = rect.isNull || rect.width < 2 || rect.height < 2 ? nil : rect
            } else {
                splitLimit = nil
            }
            let cropLimit = splitLimit ?? correctedLimit ?? subRegionLimit ?? fallbackLimit
            let cropRect = Self.clamp(regionRect, to: cropLimit).integral
            let clampSource: String
            if splitLimit != nil {
                clampSource = "splitCandidate"
            } else if correctedLimit != nil {
                clampSource = "correctedBubbleMask"
            } else if subRegionLimit != nil {
                clampSource = "subRegion"
            } else if bubbleBBox != nil {
                clampSource = "bubbleBBox"
            } else {
                clampSource = "contentRect"
            }
            let clampedByBubble = clampSource != "contentRect" && !regionRect.integral.equalTo(cropRect)
            let text = try Self.recognizePreprocessedText(in: image, cropRect: cropRect, options: options)

            return MangaOverlayTextRegionCropResult(
                text: text,
                regionBBox: Self.bboxArray(from: Self.clamp(regionRect, to: contentBounds).integral),
                cropBBox: Self.bboxArray(from: cropRect),
                clampSource: clampSource,
                cropBBoxBeforeAssignmentCorrection: (splitLimit != nil || correctedLimit != nil) ? Self.bboxArray(from: fallbackCropRect) : nil,
                cropBBoxAfterAssignmentCorrection: (splitLimit != nil || correctedLimit != nil) ? Self.bboxArray(from: cropRect) : nil,
                cropBBoxBeforeSubRegionClamp: Self.bboxArray(from: fallbackCropRect),
                cropBBoxAfterSubRegionClamp: Self.bboxArray(from: cropRect),
                cropClampedByBubble: clampedByBubble,
                paddingX: Double(paddingX),
                paddingY: Double(paddingY),
                orientationHint: orientationHint
            )
        }.value
    }

    func recognizeExternalTextBoxCrop(
        in image: CGImage,
        textBoxBBox: [Double],
        options: MangaOverlayPreprocessingOptions = .defaultValue
    ) async throws -> (text: String?, cropBBox: [Double], paddingX: Double, paddingY: Double) {
        try await Task.detached(priority: .userInitiated) {
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let seedRect = Self.clamp(Self.rect(from: textBoxBBox), to: bounds).integral
            guard seedRect.width >= 2, seedRect.height >= 2 else {
                return (nil, Self.bboxArray(from: seedRect), 0, 0)
            }
            let padding = Self.adaptiveCropPadding(for: seedRect)
            let cropRect = Self.clamp(
                seedRect.insetBy(dx: -padding.x, dy: -padding.y),
                to: bounds
            ).integral
            let text = try Self.recognizePreprocessedText(in: image, cropRect: cropRect, options: options)
            return (text, Self.bboxArray(from: cropRect), Double(padding.x), Double(padding.y))
        }.value
    }

    func runCropFallbackSelfTest(
        in image: CGImage,
        block: MangaOverlayOCRBlock?,
        blockIndex: Int?,
        options: MangaOverlayPreprocessingOptions = .defaultValue
    ) async throws -> MangaOverlayCropFallbackSelfTest {
        try await Task.detached(priority: .userInitiated) {
            guard options.enabled, let block else {
                return MangaOverlayCropFallbackSelfTest(
                    triggered: false,
                    blockIndex: nil,
                    rawText: "",
                    tightCropText: nil,
                    fallbackText: nil,
                    tightCropPreservesRawWords: false,
                    fallbackPreservesRawWords: false,
                    reason: "preprocessing disabled or no block available"
                )
            }
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let cropBounds = block.bubbleBoundingBox.map { $0.intersection(bounds) } ?? bounds
            let tightRect = Self.clamp(
                block.boundingBox.insetBy(dx: block.boundingBox.width * 0.48, dy: block.boundingBox.height * 0.48),
                to: cropBounds
            ).integral
            let fallbackRect = Self.clamp(Self.expand(block.boundingBox, by: 0.18, bounds: bounds), to: cropBounds).integral
            let tightText = try Self.recognizePreprocessedText(in: image, cropRect: tightRect, options: options)
            let fallbackText = try Self.recognizePreprocessedText(in: image, cropRect: fallbackRect, options: options)
            let tightPreserves = Self.cropCandidatePreservesRawWords(rawText: block.text, candidateText: tightText)
            let fallbackPreserves = Self.cropCandidatePreservesRawWords(rawText: block.text, candidateText: fallbackText)
            let triggered = !tightPreserves && fallbackPreserves
            return MangaOverlayCropFallbackSelfTest(
                triggered: triggered,
                blockIndex: blockIndex,
                rawText: block.text,
                tightCropText: tightText,
                fallbackText: fallbackText,
                tightCropPreservesRawWords: tightPreserves,
                fallbackPreservesRawWords: fallbackPreserves,
                reason: triggered
                    ? "synthetic tight crop lost raw words and fixed crop preserved them"
                    : "synthetic tight crop did not prove fallback; inspect tight/fallback OCR text"
            )
        }.value
    }

    private static func recognizePreprocessedText(
        in image: CGImage,
        cropRect: CGRect,
        options: MangaOverlayPreprocessingOptions
    ) throws -> String? {
        guard cropRect.width >= 2, cropRect.height >= 2 else { return nil }
        let cropped = try croppedImage(image, rect: cropRect)
        let prepared = try preprocessedImage(cropped, options: options)
        let candidates = try recognizeTextCandidates(
            in: prepared,
            angle: 0,
            scaledContentSize: CGSize(width: CGFloat(prepared.width), height: CGFloat(prepared.height)),
            contentOrigin: .zero,
            scale: 1,
            customWords: []
        )
        let text = candidates
            .sorted {
                if abs($0.boundingBox.minY - $1.boundingBox.minY) > 8 {
                    return $0.boundingBox.minY < $1.boundingBox.minY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func adaptiveCropPadding(for rect: CGRect) -> CGPoint {
        let estimatedFontSize = max(6, min(rect.width, rect.height))
        let isVerticalText = rect.height > rect.width * 1.35
        let horizontalPadding = isVerticalText ? estimatedFontSize * 0.75 : estimatedFontSize * 0.45
        let verticalPadding = isVerticalText ? estimatedFontSize * 0.45 : estimatedFontSize * 0.75
        return CGPoint(
            x: max(4, min(horizontalPadding, rect.width * 0.45)),
            y: max(4, min(verticalPadding, rect.height * 0.55))
        )
    }

    private static func shouldUseBubbleWideCrop(for blockRect: CGRect, bubbleBounds: CGRect) -> Bool {
        guard bubbleBounds.width > 0, bubbleBounds.height > 0 else { return false }
        let widthCoverage = blockRect.width / bubbleBounds.width
        let heightCoverage = blockRect.height / bubbleBounds.height
        let blockArea = blockRect.width * blockRect.height
        let bubbleArea = bubbleBounds.width * bubbleBounds.height
        let blockLooksPartial = widthCoverage < 0.55 || heightCoverage < 0.52 || blockArea < bubbleArea * 0.36
        let bubbleIsReasonableOCRCrop = bubbleBounds.width <= blockRect.width * 3.2
            && bubbleBounds.height <= blockRect.height * 3.2
        return blockLooksPartial && bubbleIsReasonableOCRCrop
    }

    static func cropCandidatePreservesRawWords(rawText: String, candidateText: String?) -> Bool {
        let rawWords = ocrWords(rawText)
        guard !rawWords.isEmpty, let candidateText else { return false }
        let candidateWords = Set(ocrWords(candidateText))
        guard !candidateWords.isEmpty else { return false }
        let required = rawWords.count <= 2 ? rawWords.count : Int(ceil(Double(rawWords.count) * 0.7))
        let preservedCount = rawWords.filter { candidateWords.contains($0) }.count
        return preservedCount >= max(1, required)
    }

    private static func ocrWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    func renderOutputs(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        outputDirectory: URL,
        preprocessing: MangaOverlayPreprocessingOptions = .defaultValue,
        cropping: MangaOverlayProbeCropping = .defaultValue,
        textRegionCropReport: MangaOverlayTextRegionCropReport? = nil,
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport? = nil,
        segmentMaskReport: MangaOverlaySegmentMaskReport? = nil,
        preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport? = nil,
        cropExperimentReport: MangaOverlayCropExperimentReport? = nil,
        textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport? = nil,
        lineTextBoxPlanReport: MangaOverlayLineTextBoxPlanReport? = nil,
        lineCropExperimentReport: MangaOverlayLineCropExperimentReport? = nil,
        externalArtifactReadinessReport: MangaOverlayExternalArtifactReadinessReport? = nil,
        externalTextBoxShadowOCRReport: MangaOverlayExternalTextBoxShadowOCRReport? = nil,
        internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport? = nil,
        routingDrivenTranslationComparisonReport: MangaRoutingDrivenTranslationComparisonReport? = nil,
        ocrCharacterDamageAuditReport: MangaOCRCharacterDamageAuditReport? = nil,
        readingOrderStructureAuditReport: MangaReadingOrderStructureAuditReport? = nil,
        structureActionCandidateReport: MangaStructureActionCandidateReport? = nil,
        koharuArtifactDAGReport: MangaKoharuArtifactDAGReport? = nil,
        koharuStageGapReplicationReport: MangaKoharuStageGapReplicationReport? = nil,
        koharuNativeReplicationScoreboardReport: MangaKoharuNativeReplicationScoreboardReport? = nil,
        nativeTextBoxProxyLedgerReport: MangaNativeTextBoxProxyLedgerReport? = nil,
        bubbleMaskAssignmentSplitScoreboardReport: MangaBubbleMaskAssignmentSplitScoreboardReport? = nil,
        segmentMaskProxyCoverageScoreboardReport: MangaSegmentMaskProxyCoverageScoreboardReport? = nil,
        koharuArtifactConvergenceReport: MangaKoharuArtifactConvergenceReport? = nil,
        koharuPipelineResolverReport: MangaKoharuPipelineResolverReport? = nil,
        koharuWorkOrderRouterReport: MangaKoharuWorkOrderRouterReport? = nil,
        koharuExternalArtifactRequestPacketReport: MangaKoharuExternalArtifactRequestPacketReport? = nil,
        koharuNativeAlgorithmReplayMatrixReport: MangaKoharuNativeAlgorithmReplayMatrixReport? = nil,
        koharuBubbleIndexShadowLedgerReport: MangaKoharuBubbleIndexShadowLedgerReport? = nil,
        translationModelFloorComparisonReport: MangaTranslationModelFloorComparisonReport? = nil,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport? = nil,
        bubbleMaskReport: MangaOverlayBubbleMaskReport? = nil,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport? = nil,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport? = nil,
        bubbleDebugImagePath: String? = nil,
        bubbleCropsImagePath: String? = nil,
        bubbleTextOverlayImagePath: String? = nil,
        renderDiagnosticPNGs: Bool = true
    ) async throws -> MangaOverlayProbeOutputFiles {
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let debugURL = outputDirectory.appendingPathComponent("1_debug_boxes.png")
            let overlayURL = outputDirectory.appendingPathComponent("1_translated_overlay.png")
            let ocrTextURL = outputDirectory.appendingPathComponent("1_ocr_text_overlay.png")
            let deterministicCorrectionURL = outputDirectory.appendingPathComponent("1_deterministic_correction_overlay.png")
            let deterministicTranslationURL = outputDirectory.appendingPathComponent("1_deterministic_translation_overlay.png")
            let ocrProbeTextURL = outputDirectory.appendingPathComponent("1_ocr_probe_text.txt")
            let cropsURL = outputDirectory.appendingPathComponent("1_block_crops.png")
            let preprocessedURL = outputDirectory.appendingPathComponent("1_preprocessed_content.png")
            let debugImage = try Self.drawDebugBoxes(on: image, blocks: blocks)
            let overlayImage = try Self.drawTranslatedOverlay(on: image, blocks: blocks)
            try Self.writePNG(debugImage, to: debugURL)
            try Self.writePNG(overlayImage, to: overlayURL)
            var ocrTextPath: String?
            var deterministicCorrectionPath: String?
            var deterministicTranslationPath: String?
            var cropsPath: String?
            if renderDiagnosticPNGs {
                let ocrTextImage = try Self.drawOCRTextOverlay(on: image, blocks: blocks)
                let deterministicCorrectionImage = try Self.drawDeterministicCorrectionOverlay(on: image, blocks: blocks)
                let deterministicTranslationImage = try Self.drawDeterministicTranslationOverlay(on: image, blocks: blocks)
                let cropsImage = try Self.drawBlockCrops(from: image, blocks: blocks, preprocessing: preprocessing)
                try Self.writePNG(ocrTextImage, to: ocrTextURL)
                try Self.writePNG(deterministicCorrectionImage, to: deterministicCorrectionURL)
                try Self.writePNG(deterministicTranslationImage, to: deterministicTranslationURL)
                try Self.writePNG(cropsImage, to: cropsURL)
                ocrTextPath = ocrTextURL.path
                deterministicCorrectionPath = deterministicCorrectionURL.path
                deterministicTranslationPath = deterministicTranslationURL.path
                cropsPath = cropsURL.path
            }
            try Self.writeOCRProbeText(
                blocks: blocks,
                textRegionCropReport: textRegionCropReport,
                textBoxCandidateReport: textBoxCandidateReport,
                segmentMaskReport: segmentMaskReport,
                preCropTextBoxPlanReport: preCropTextBoxPlanReport,
                cropExperimentReport: cropExperimentReport,
                textBoxPlanFailureReport: textBoxPlanFailureReport,
                lineTextBoxPlanReport: lineTextBoxPlanReport,
                lineCropExperimentReport: lineCropExperimentReport,
                externalArtifactReadinessReport: externalArtifactReadinessReport,
                externalTextBoxShadowOCRReport: externalTextBoxShadowOCRReport,
                internalStructureBottleneckReport: internalStructureBottleneckReport,
                routingDrivenTranslationComparisonReport: routingDrivenTranslationComparisonReport,
                ocrCharacterDamageAuditReport: ocrCharacterDamageAuditReport,
                readingOrderStructureAuditReport: readingOrderStructureAuditReport,
                structureActionCandidateReport: structureActionCandidateReport,
                koharuArtifactDAGReport: koharuArtifactDAGReport,
                koharuStageGapReplicationReport: koharuStageGapReplicationReport,
                koharuNativeReplicationScoreboardReport: koharuNativeReplicationScoreboardReport,
                nativeTextBoxProxyLedgerReport: nativeTextBoxProxyLedgerReport,
                bubbleMaskAssignmentSplitScoreboardReport: bubbleMaskAssignmentSplitScoreboardReport,
                segmentMaskProxyCoverageScoreboardReport: segmentMaskProxyCoverageScoreboardReport,
                koharuArtifactConvergenceReport: koharuArtifactConvergenceReport,
                koharuPipelineResolverReport: koharuPipelineResolverReport,
                koharuWorkOrderRouterReport: koharuWorkOrderRouterReport,
                koharuExternalArtifactRequestPacketReport: koharuExternalArtifactRequestPacketReport,
                koharuNativeAlgorithmReplayMatrixReport: koharuNativeAlgorithmReplayMatrixReport,
                koharuBubbleIndexShadowLedgerReport: koharuBubbleIndexShadowLedgerReport,
                translationModelFloorComparisonReport: translationModelFloorComparisonReport,
                koharuRenderRegressionLockReport: koharuRenderRegressionLockReport,
                bubbleMaskReport: bubbleMaskReport,
                bubbleAssignmentCorrectionReport: bubbleAssignmentCorrectionReport,
                bubbleSplitCandidateReport: bubbleSplitCandidateReport,
                to: ocrProbeTextURL
            )

            var preprocessedPath: String?
            if preprocessing.enabled && renderDiagnosticPNGs {
                let contentRect = Self.contentCropRect(for: image, cropping: cropping)
                let cropped = try Self.croppedImage(image, rect: contentRect)
                let prepared = try Self.preprocessedImage(cropped, options: preprocessing)
                try Self.writePNG(prepared, to: preprocessedURL)
                preprocessedPath = preprocessedURL.path
            }
            return MangaOverlayProbeOutputFiles(
                debugBoxesImage: debugURL.path,
                overlayImage: overlayURL.path,
                ocrTextOverlayImage: ocrTextPath,
                deterministicCorrectionOverlayImage: deterministicCorrectionPath,
                deterministicTranslationOverlayImage: deterministicTranslationPath,
                ocrProbeTextFile: ocrProbeTextURL.path,
                blockCropsImage: cropsPath,
                preprocessedContentImage: preprocessedPath,
                bubbleDebugImage: bubbleDebugImagePath,
                bubbleCropsImage: bubbleCropsImagePath,
                bubbleTextOverlayImage: bubbleTextOverlayImagePath
            )
        }.value
    }

    func applySafeLayoutAndRenderingDiagnostics(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport? = nil
    ) async -> [MangaOverlayProbeBlock] {
        await Task.detached(priority: .userInitiated) {
            let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let bubbleRects = Dictionary(
                uniqueKeysWithValues: bubbleGeometry.bubbles.map { bubble in
                    (bubble.id, Self.clamp(Self.rect(from: bubble.bbox), to: imageBounds))
                }
            )
            let maskInstances = Dictionary(
                uniqueKeysWithValues: (bubbleMaskReport?.instances ?? []).map { ($0.bubbleID, $0) }
            )
            let maskDiagnostics = Dictionary(
                uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) }
            )
            let groupedByBubble = Dictionary(grouping: blocks) { block in
                block.bubbleID
            }
            var safeRectsByBlockID: [UUID: (rect: CGRect, source: String)] = [:]

            for (bubbleID, group) in groupedByBubble {
                guard let bubbleID, let bubbleRect = bubbleRects[bubbleID] else {
                    for block in group {
                        let blockRect = Self.rect(from: block.bbox)
                        let safeRect = Self.clamp(Self.expand(blockRect, by: 0.14, bounds: imageBounds), to: imageBounds)
                        safeRectsByBlockID[block.id] = (safeRect, "blockFallbackNoBubble")
                    }
                    continue
                }

                let insetBubble = Self.safeBubbleRect(for: bubbleRect, representativeBlocks: group)
                if group.count == 1 {
                    if let block = group.first {
                        safeRectsByBlockID[block.id] = (insetBubble, "bubbleInsetSingle")
                    }
                } else {
                    for block in group {
                        let partition = Self.partitionedSafeRect(
                            for: block,
                            in: group,
                            bubbleSafeRect: insetBubble
                        )
                        safeRectsByBlockID[block.id] = (partition, "bubbleInsetPartitioned")
                    }
                }
            }

            return blocks.map { block in
                var updated = block
                let blockRect = Self.rect(from: block.bbox)
                let fallbackRect = Self.clamp(Self.expand(blockRect, by: 0.14, bounds: imageBounds), to: imageBounds)
                let safeEntry = safeRectsByBlockID[block.id] ?? (fallbackRect, "blockFallbackNoSafeRect")
                let bboxSafeRect = Self.ensureMinimumRect(safeEntry.rect, fallback: fallbackRect, bounds: imageBounds)
                var safeRect = bboxSafeRect
                var safeSource = safeEntry.source
                let maskDiagnostic = maskDiagnostics[block.index]
                if let bubbleID = maskDiagnostic?.maskDominantBubbleID ?? block.bubbleID,
                   let instance = maskInstances[bubbleID],
                   let maskSafe = instance.safeRect.map(Self.rect(from:)),
                   instance.maskCoverageRatio >= 0.48,
                   (maskDiagnostic?.maskDominantCoverageRatio ?? 0) >= 0.34,
                   maskSafe.width >= 8,
                   maskSafe.height >= 8 {
                    let partitionedMaskRect: CGRect
                    if let group = groupedByBubble[block.bubbleID], group.count > 1 {
                        partitionedMaskRect = Self.partitionedSafeRect(
                            for: block,
                            in: group,
                            bubbleSafeRect: Self.clamp(maskSafe, to: imageBounds)
                        )
                    } else {
                        partitionedMaskRect = Self.clamp(maskSafe, to: imageBounds)
                    }
                    let minimumMaskRect = Self.ensureMinimumRect(partitionedMaskRect, fallback: bboxSafeRect, bounds: imageBounds)
                    if minimumMaskRect.width >= 8, minimumMaskRect.height >= 8 {
                        safeRect = minimumMaskRect
                        safeSource = (safeEntry.source == "blockFallbackNoBubble" || safeEntry.source == "blockFallbackNoSafeRect")
                            ? "maskSafeBlockFallback"
                            : "maskSafeRect"
                    }
                }
                let text = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.safeLayoutRect = Self.bboxArray(from: safeRect)
                updated.safeLayoutSourceBeforeMask = safeEntry.source
                updated.safeLayoutSource = safeSource
                updated.maskSafeRect = safeSource.hasPrefix("maskSafe") ? Self.bboxArray(from: safeRect) : nil
                let glyphPlan = Self.makeGlyphMaskPlan(
                    image: image,
                    blockRect: blockRect,
                    bubbleRect: block.bubbleID.flatMap { bubbleRects[$0] }
                )
                updated.glyphMaskPixelCount = glyphPlan?.pixelCount ?? 0
                updated.glyphMaskRect = glyphPlan.map { Self.bboxArray(from: $0.maskRect) }
                updated.glyphMaskFillRects = glyphPlan?.fillRects ?? []
                updated.backgroundFillApplied = glyphPlan?.backgroundFillApplied ?? false
                updated.backgroundColorStdDev = glyphPlan?.backgroundStdDev
                updated.backgroundFillColor = glyphPlan?.backgroundColor

                if text.isEmpty {
                    updated.renderCollisionChecked = false
                    return updated
                }

                let plan = Self.makeRenderTextPlan(
                    text,
                    in: safeRect,
                    minFontSize: Self.minimumOverlayFontSize
                )
                updated.renderCollisionChecked = true
                updated.renderCollisionInitialOverflow = plan.initialOverflow
                updated.renderCollisionResolved = plan.resolved
                updated.renderFontSize = Double(plan.fontSize)
                updated.renderMinFontSizeReached = plan.minFontSizeReached
                updated.renderTextTruncated = plan.textTruncated
                if let bounds = plan.nonTransparentBounds {
                    let globalBounds = bounds.offsetBy(dx: safeRect.minX, dy: safeRect.minY)
                    updated.renderNonTransparentBounds = Self.bboxArray(from: globalBounds)
                    let maskCoverage = globalBounds.isNull
                        ? 0
                        : Self.rectContainmentRatio(inner: globalBounds, outer: safeRect)
                    let estimatedPixels = max(0, Int((globalBounds.width * globalBounds.height).rounded()))
                    updated.renderMaskCollisionChecked = bubbleMaskReport != nil
                    updated.renderMaskOverflowPixelCount = maskCoverage >= 0.98 ? 0 : estimatedPixels
                    updated.renderMaskCollisionResolved = updated.renderMaskOverflowPixelCount == 0
                } else {
                    updated.renderNonTransparentBounds = nil
                    updated.renderMaskCollisionChecked = bubbleMaskReport != nil
                    updated.renderMaskCollisionResolved = bubbleMaskReport != nil
                    updated.renderMaskOverflowPixelCount = 0
                }
                return updated
            }
        }.value
    }

    func makeBubbleMaskReport(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        textRegionCropReport: MangaOverlayTextRegionCropReport?
    ) async -> MangaOverlayBubbleMaskReport {
        await Task.detached(priority: .userInitiated) {
            let runtime = Self.makeApproximateBubbleMaskRuntime(image: image, bubbleGeometry: bubbleGeometry)
            let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let splitCandidateIDs = Set(
                bubbleGeometry.bubbleAudits
                    .filter(\.bubbleSplitCandidate)
                    .map(\.bubbleID)
            )
            let cropDiagnostics = Dictionary(
                uniqueKeysWithValues: (textRegionCropReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
            )

            var blockDiagnostics: [MangaOverlayBubbleMaskBlockDiagnostic] = []
            for block in blocks {
                let seedRect = Self.clamp(Self.rect(from: block.bbox), to: imageBounds)
                let dominant = runtime.dominantID(in: seedRect)
                let dominantID = dominant.id
                let consistent = block.bubbleID == nil
                    ? dominantID == nil
                    : dominantID == block.bubbleID
                let crop = cropDiagnostics[block.index]
                let cropRect = crop.map { Self.clamp(Self.rect(from: $0.cropBBox), to: imageBounds) }
                let cropCoverage = cropRect.map { runtime.coverageRatio(of: $0, bubbleID: block.bubbleID ?? dominantID) }
                let cropRejectedReason = cropCoverage.flatMap { $0 < 0.55 ? "lowMaskCoverage" : nil }
                blockDiagnostics.append(
                    MangaOverlayBubbleMaskBlockDiagnostic(
                        blockIndex: block.index,
                        currentBubbleID: block.bubbleID,
                        maskDominantBubbleID: dominantID,
                        maskDominantCoverageRatio: dominant.ratio,
                        maskIDsUnderSeed: dominant.counts,
                        bubbleIDConsistent: consistent,
                        safeLayoutSourceBeforeMask: block.safeLayoutSourceBeforeMask ?? block.safeLayoutSource,
                        safeLayoutSourceAfterMask: block.safeLayoutSource,
                        maskSafeRect: dominantID.flatMap { runtime.safeRectsByBubbleID[$0].map(Self.bboxArray(from:)) },
                        renderMaskCollisionChecked: block.renderMaskCollisionChecked,
                        renderMaskCollisionResolved: block.renderMaskCollisionResolved,
                        renderMaskOverflowPixelCount: block.renderMaskOverflowPixelCount,
                        cropMaskCoverageRatio: cropCoverage,
                        cropMaskRejectedReason: cropRejectedReason
                    )
                )
            }

            let instances = bubbleGeometry.bubbles.map { bubble in
                let bubbleRect = Self.clamp(Self.rect(from: bubble.bbox), to: imageBounds)
                let bboxPixelCount = max(1, Int((bubbleRect.width * bubbleRect.height).rounded()))
                var maskPixelCount = 0
                for value in runtime.ids where value == bubble.id + 1 {
                    maskPixelCount += 1
                }
                let safeRect = runtime.safeRectsByBubbleID[bubble.id]
                let safePixelCount = safeRect.map { Int(($0.width * $0.height).rounded()) } ?? 0
                var riskFlags: [String] = []
                if splitCandidateIDs.contains(bubble.id) {
                    riskFlags.append("oversizedBubbleSplitCandidate")
                }
                if Double(maskPixelCount) / Double(bboxPixelCount) < 0.35 {
                    riskFlags.append("lowMaskCoverage")
                }
                if safePixelCount < 96 {
                    riskFlags.append("safeRectTooSmall")
                }
                return MangaOverlayBubbleMaskInstanceDiagnostic(
                    bubbleID: bubble.id,
                    bbox: bubble.bbox,
                    maskPixelCount: maskPixelCount,
                    bboxPixelCount: bboxPixelCount,
                    maskCoverageRatio: Double(maskPixelCount) / Double(bboxPixelCount),
                    source: "roundedRectApproximation",
                    confidence: Double(bubble.confidence),
                    safePixelCount: safePixelCount,
                    safeBBox: maskPixelCount > 0 ? bubble.bbox : nil,
                    safeRect: safeRect.map(Self.bboxArray(from:)),
                    safeRectCoverageRatio: Double(safePixelCount) / Double(bboxPixelCount),
                    riskFlags: riskFlags,
                    notes: [
                        "instance ID mask approximated from existing bubble bbox only",
                        "internal raster value is bubbleID + 1 so background can remain 0",
                        "overlap resolution is stable: smaller bbox area then higher confidence wins",
                        "ground truth is not used"
                    ]
                )
            }
            let inconsistent = blockDiagnostics
                .filter { !$0.bubbleIDConsistent }
                .map(\.blockIndex)
            let overflow = blockDiagnostics
                .filter { $0.renderMaskOverflowPixelCount > 0 }
                .map(\.blockIndex)
            let maskSafeBlocks = blockDiagnostics
                .filter { ($0.safeLayoutSourceAfterMask ?? "").hasPrefix("maskSafe") }
                .count
            return MangaOverlayBubbleMaskReport(
                enabled: true,
                imageWidth: image.width,
                imageHeight: image.height,
                instanceCount: instances.count,
                instances: instances,
                blockDiagnostics: blockDiagnostics,
                maskSafeLayoutBlocks: maskSafeBlocks,
                bboxFallbackBlocks: max(0, blocks.count - maskSafeBlocks),
                inconsistentBubbleAssignmentBlocks: inconsistent,
                renderMaskOverflowBlocks: overflow,
                notes: [
                    "lightweight BubbleMask instance-ID approximation, not a real segmentation model",
                    "mask is used for diagnostics and safe-layout preference only",
                    "TextRegion crop adoption guardrails are unchanged"
                ]
            )
        }.value
    }

    private static func makeApproximateBubbleMaskRuntime(
        image: CGImage,
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics
    ) -> MangaOverlayBubbleMaskRuntime {
        let width = image.width
        let height = image.height
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let sortedBubbles = bubbleGeometry.bubbles.sorted { lhs, rhs in
            let lhsRect = rect(from: lhs.bbox)
            let rhsRect = rect(from: rhs.bbox)
            let lhsArea = lhsRect.width * lhsRect.height
            let rhsArea = rhsRect.width * rhsRect.height
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence < rhs.confidence
            }
            return lhs.id > rhs.id
        }

        var ids = [Int](repeating: 0, count: width * height)
        for bubble in sortedBubbles {
            let rect = clamp(rect(from: bubble.bbox).integral, to: imageBounds)
            guard rect.width >= 2, rect.height >= 2 else { continue }
            let minX = max(0, Int(rect.minX))
            let maxX = min(width, Int(rect.maxX))
            let minY = max(0, Int(rect.minY))
            let maxY = min(height, Int(rect.maxY))
            let radius = max(3, min(rect.width, rect.height) * 0.18)
            for y in minY..<maxY {
                for x in minX..<maxX where roundedRectContains(
                    point: CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5),
                    rect: rect,
                    radius: radius
                ) {
                    ids[y * width + x] = bubble.id + 1
                }
            }
        }

        let safeRects = Dictionary(
            uniqueKeysWithValues: bubbleGeometry.bubbles.compactMap { bubble -> (Int, CGRect)? in
                let bubbleRect = clamp(rect(from: bubble.bbox), to: imageBounds)
                guard bubbleRect.width >= 10, bubbleRect.height >= 10 else { return nil }
                let inset = max(4, min(bubbleRect.width, bubbleRect.height) * 0.14)
                let safeRect = clamp(bubbleRect.insetBy(dx: inset, dy: inset), to: imageBounds).integral
                guard safeRect.width >= 8, safeRect.height >= 8 else { return nil }
                return (bubble.id, safeRect)
            }
        )

        return MangaOverlayBubbleMaskRuntime(
            width: width,
            height: height,
            ids: ids,
            safeRectsByBubbleID: safeRects
        )
    }

    private static func roundedRectContains(point: CGPoint, rect: CGRect, radius: CGFloat) -> Bool {
        guard rect.contains(point) else { return false }
        let clampedRadius = min(radius, min(rect.width, rect.height) / 2)
        let inner = rect.insetBy(dx: clampedRadius, dy: clampedRadius)
        if point.x >= inner.minX && point.x <= inner.maxX {
            return true
        }
        if point.y >= inner.minY && point.y <= inner.maxY {
            return true
        }

        let cornerX = point.x < inner.minX ? inner.minX : inner.maxX
        let cornerY = point.y < inner.minY ? inner.minY : inner.maxY
        let dx = point.x - cornerX
        let dy = point.y - cornerY
        return dx * dx + dy * dy <= clampedRadius * clampedRadius
    }

    @discardableResult
    static func recreateDirectory(_ url: URL) throws -> Int {
        let fileManager = FileManager.default
        var removedItemCount = 0
        if fileManager.fileExists(atPath: url.path) {
            removedItemCount = (try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return removedItemCount
    }

    static func writeReport(_ report: MangaOverlayProbeReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    static func renderContactSheet(outputFiles: MangaOverlayProbeOutputFiles, outputDirectory: URL) throws -> String? {
        let entries: [(String, String?)] = [
            ("whole-page OCR", outputFiles.ocrTextOverlayImage),
            ("bubble-first OCR", outputFiles.bubbleTextOverlayImage),
            ("bubble crops", outputFiles.bubbleCropsImage),
            ("translated overlay", outputFiles.overlayImage),
            ("deterministic OCR", outputFiles.deterministicCorrectionOverlayImage),
            ("deterministic translation", outputFiles.deterministicTranslationOverlayImage)
        ]
        let images = entries.compactMap { title, path -> (String, CGImage)? in
            guard let path,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = try? makeImage(from: data) else {
                return nil
            }
            return (title, image)
        }
        guard !images.isEmpty else { return nil }

        let columns = 2
        let tileWidth: CGFloat = 520
        let tileHeight: CGFloat = 680
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let canvasSize = CGSize(width: tileWidth * CGFloat(columns), height: tileHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))
            for (index, entry) in images.enumerated() {
                let column = index % columns
                let row = index / columns
                let tile = CGRect(
                    x: CGFloat(column) * tileWidth + 10,
                    y: CGFloat(row) * tileHeight + 10,
                    width: tileWidth - 20,
                    height: tileHeight - 20
                )
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(tile)
                drawText(
                    entry.0,
                    in: CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: 30),
                    fontSize: 17,
                    textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    backgroundColor: CGColor(red: 0.1, green: 0.16, blue: 0.24, alpha: 0.9),
                    context: context
                )
                let imageRect = aspectFitRect(
                    imageSize: CGSize(width: entry.1.width, height: entry.1.height),
                    bounds: CGRect(x: tile.minX + 6, y: tile.minY + 38, width: tile.width - 12, height: tile.height - 44)
                )
                UIImage(cgImage: entry.1).draw(in: imageRect)
            }
        }
        guard let image = rendered.cgImage else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        let url = outputDirectory.appendingPathComponent("1_probe_contact_sheet.png")
        try writePNG(image, to: url)
        return url.path
    }

    func compareCustomLexicon(
        in imageData: Data,
        customWords: [String],
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> MangaOverlayLexiconComparison {
        let withoutLexicon = try await recognizeTextBlocks(in: imageData, cropping: cropping, customWords: [])
        let withLexicon = try await recognizeTextBlocks(in: imageData, cropping: cropping, customWords: customWords)
        let pairedCount = min(withoutLexicon.blocks.count, withLexicon.blocks.count)
        var changedIndexes: [Int] = []
        for index in 0..<pairedCount where withoutLexicon.blocks[index].text != withLexicon.blocks[index].text {
            changedIndexes.append(index)
        }
        if withoutLexicon.blocks.count != withLexicon.blocks.count {
            changedIndexes.append(contentsOf: pairedCount..<max(withoutLexicon.blocks.count, withLexicon.blocks.count))
        }
        let notes: [String] = changedIndexes.isEmpty
            ? ["customWords did not change final merged block text in this run"]
            : ["customWords changed \(changedIndexes.count) merged block(s); effect is lexicon/language-correction hinting, not general OCR repair"]
        return MangaOverlayLexiconComparison(
            enabled: !customWords.isEmpty,
            customWords: customWords,
            withoutLexiconTotalBlocks: withoutLexicon.blocks.count,
            withLexiconTotalBlocks: withLexicon.blocks.count,
            changedBlockIndexes: changedIndexes,
            notes: notes
        )
    }

    func compareVisionAPIs(
        in imageData: Data,
        customWords: [String],
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> MangaOverlayVisionAPIComparison {
        try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let contentRect = Self.contentCropRect(for: image, cropping: cropping)
            let croppedImage = try Self.croppedImage(image, rect: contentRect)
            let scaledImage = try Self.scaledImage(croppedImage, scale: Self.ocrScale)
            let oldTexts = try Self.recognizeTextCandidates(
                in: scaledImage,
                angle: 0,
                scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                contentOrigin: contentRect.origin,
                scale: Self.ocrScale,
                customWords: customWords
            ).map(\.text)

            if #available(iOS 18.0, *) {
                do {
                    let newTexts = try await Self.recognizeTextWithSwiftAPI(in: scaledImage, customWords: customWords)
                    return MangaOverlayVisionAPIComparison(
                        oldAPITotalObservations: oldTexts.count,
                        newAPISupported: true,
                        newAPITotalObservations: newTexts.count,
                        changed: oldTexts != newTexts,
                        oldAPISample: Array(oldTexts.prefix(20)),
                        newAPISample: Array(newTexts.prefix(20)),
                        error: nil
                    )
                } catch {
                    return MangaOverlayVisionAPIComparison(
                        oldAPITotalObservations: oldTexts.count,
                        newAPISupported: true,
                        newAPITotalObservations: nil,
                        changed: nil,
                        oldAPISample: Array(oldTexts.prefix(20)),
                        newAPISample: [],
                        error: "\(type(of: error)): \(error.localizedDescription)"
                    )
                }
            } else {
                return MangaOverlayVisionAPIComparison(
                    oldAPITotalObservations: oldTexts.count,
                    newAPISupported: false,
                    newAPITotalObservations: nil,
                    changed: nil,
                    oldAPISample: Array(oldTexts.prefix(20)),
                    newAPISample: [],
                    error: "RecognizeTextRequest requires iOS 18+"
                )
            }
        }.value
    }

    func runBubbleFirstProbe(
        imageData: Data,
        groundTruth: [MangaGroundTruthEntry],
        preprocessing: MangaOverlayPreprocessingOptions,
        customWords: [String],
        outputDirectory: URL,
        cropping: MangaOverlayProbeCropping = .defaultValue
    ) async throws -> (comparison: MangaOverlayFrameworkComparison, debugPath: String, cropsPath: String, seedDebugPath: String, textOverlayPath: String) {
        let start = Date.now
        return try await Task.detached(priority: .userInitiated) {
            let image = try Self.makeImage(from: imageData)
            let bubbles = try Self.detectBubbleCandidates(in: image, cropping: cropping, customWords: customWords)
            let seedDebugCandidates = try Self.rawBubbleSeedCandidates(in: image, cropping: cropping, customWords: customWords)
            let results = try bubbles.flatMap { bubble in
                try Self.bubbleResults(
                    for: bubble,
                    image: image,
                    preprocessing: preprocessing,
                    customWords: customWords,
                    groundTruth: groundTruth
                )
            }
            .filter(Self.shouldKeepBubbleResult)
            .enumerated()
            .map { offset, result in
                MangaOverlayBubbleResult(
                    index: offset,
                    bbox: result.bbox,
                    bubbleID: result.bubbleID,
                    source: result.source,
                    text: result.text,
                    bestGroundTruthIndex: result.bestGroundTruthIndex,
                    bestGroundTruthType: result.bestGroundTruthType,
                    groundTruthMatch: result.groundTruthMatch,
                    bestSimilarity: result.bestSimilarity,
                    legacySimilarity: result.legacySimilarity,
                    wordOrderPreserved: result.wordOrderPreserved
                )
            }

            let bubbleMetrics = Self.frameworkMetrics(
                texts: results.map(\.text),
                groundTruth: groundTruth,
                processingTimeMs: Int(Date.now.timeIntervalSince(start) * 1000)
            )
            let debugURL = outputDirectory.appendingPathComponent("1_bubble_debug.png")
            let cropsURL = outputDirectory.appendingPathComponent("1_bubble_crops.png")
            let seedDebugURL = outputDirectory.appendingPathComponent("1_bubble_seed_debug.png")
            let textOverlayURL = outputDirectory.appendingPathComponent("1_bubble_text_overlay.png")
            let debugImage = try Self.drawBubbleDebug(on: image, bubbles: bubbles)
            let cropsImage = try Self.drawBubbleCrops(from: image, bubbles: bubbles, results: results, preprocessing: preprocessing)
            let seedDebugImage = try Self.drawBubbleDebug(on: image, bubbles: seedDebugCandidates)
            let textOverlayImage = try Self.drawBubbleTextOverlay(on: image, results: results)
            try Self.writePNG(debugImage, to: debugURL)
            try Self.writePNG(cropsImage, to: cropsURL)
            try Self.writePNG(seedDebugImage, to: seedDebugURL)
            try Self.writePNG(textOverlayImage, to: textOverlayURL)
            let comparison = MangaOverlayFrameworkComparison(
                groundTruth: groundTruth,
                comparisonUnit: "trustedGroundTruthMatches",
                wholePage: MangaOverlayFrameworkMetrics(
                    totalBlocksDetected: 0,
                    processingTimeMs: 0,
                    accuracyVsGroundTruth: 0,
                    matchedGroundTruthCount: 0,
                    unmatchedBlockCount: 0
                ),
                bubbleFirst: bubbleMetrics,
                blocksOnlyInWholePage: [],
                blocksOnlyInBubbleFirst: [],
                blocksFoundByBoth: 0,
                matchedGroundTruthUnionCount: 0,
                consistencyPassed: true,
                consistencyWarnings: [],
                bubbleResults: results,
                notes: [
                    "bubble-first is independent probe path; it does not replace whole-page OCR",
                    "bubble detection uses near-white connected components, so non-white narration/effect text can be missed"
                ]
            )
            return (comparison, debugURL.path, cropsURL.path, seedDebugURL.path, textOverlayURL.path)
        }.value
    }

    @available(iOS 18.0, *)
    private static func recognizeTextWithSwiftAPI(in image: CGImage, customWords: [String]) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        let englishLanguages = request.supportedRecognitionLanguages.filter { language in
            let identifier = language.minimalIdentifier
            return identifier == "en" || identifier == "en-US"
        }
        if !englishLanguages.isEmpty {
            request.recognitionLanguages = englishLanguages
        }
        if !customWords.isEmpty {
            request.customWords = customWords
        }
        request.minimumTextHeightFraction = 0.006
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty || Self.isNoise(text) ? nil : text
        }
    }

    static func writeOCRProbeText(
        blocks: [MangaOverlayProbeBlock],
        textRegionCropReport: MangaOverlayTextRegionCropReport?,
        textBoxCandidateReport: MangaOverlayTextBoxCandidateReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?,
        preCropTextBoxPlanReport: MangaOverlayPreCropTextBoxPlanReport?,
        cropExperimentReport: MangaOverlayCropExperimentReport?,
        textBoxPlanFailureReport: MangaOverlayTextBoxPlanFailureReport?,
        lineTextBoxPlanReport: MangaOverlayLineTextBoxPlanReport?,
        lineCropExperimentReport: MangaOverlayLineCropExperimentReport?,
        externalArtifactReadinessReport: MangaOverlayExternalArtifactReadinessReport?,
        externalTextBoxShadowOCRReport: MangaOverlayExternalTextBoxShadowOCRReport?,
        internalStructureBottleneckReport: MangaOverlayInternalStructureBottleneckReport?,
        routingDrivenTranslationComparisonReport: MangaRoutingDrivenTranslationComparisonReport?,
        ocrCharacterDamageAuditReport: MangaOCRCharacterDamageAuditReport?,
        readingOrderStructureAuditReport: MangaReadingOrderStructureAuditReport?,
        structureActionCandidateReport: MangaStructureActionCandidateReport?,
        koharuArtifactDAGReport: MangaKoharuArtifactDAGReport?,
        koharuStageGapReplicationReport: MangaKoharuStageGapReplicationReport?,
        koharuNativeReplicationScoreboardReport: MangaKoharuNativeReplicationScoreboardReport?,
        nativeTextBoxProxyLedgerReport: MangaNativeTextBoxProxyLedgerReport?,
        bubbleMaskAssignmentSplitScoreboardReport: MangaBubbleMaskAssignmentSplitScoreboardReport?,
        segmentMaskProxyCoverageScoreboardReport: MangaSegmentMaskProxyCoverageScoreboardReport?,
        koharuArtifactConvergenceReport: MangaKoharuArtifactConvergenceReport?,
        koharuPipelineResolverReport: MangaKoharuPipelineResolverReport?,
        koharuWorkOrderRouterReport: MangaKoharuWorkOrderRouterReport?,
        koharuExternalArtifactRequestPacketReport: MangaKoharuExternalArtifactRequestPacketReport?,
        koharuNativeAlgorithmReplayMatrixReport: MangaKoharuNativeAlgorithmReplayMatrixReport? = nil,
        koharuBubbleIndexShadowLedgerReport: MangaKoharuBubbleIndexShadowLedgerReport? = nil,
        translationModelFloorComparisonReport: MangaTranslationModelFloorComparisonReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        to url: URL
    ) throws {
        let textRegionByBlock = Dictionary(
            uniqueKeysWithValues: (textRegionCropReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let textBoxByBlock = Dictionary(
            uniqueKeysWithValues: (textBoxCandidateReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let segmentByBlock = Dictionary(
            uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let preCropPlanSummaryByBlock = Dictionary(
            uniqueKeysWithValues: (preCropTextBoxPlanReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let preCropPlanByID = Dictionary(
            uniqueKeysWithValues: (preCropTextBoxPlanReport?.plans ?? []).map { ($0.planID, $0) }
        )
        let experimentSummaryByBlock = Dictionary(
            uniqueKeysWithValues: (cropExperimentReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let experimentCandidateByID = Dictionary(
            uniqueKeysWithValues: (cropExperimentReport?.candidates ?? []).map { ($0.candidateID, $0) }
        )
        let failureSummaryByBlock = Dictionary(
            uniqueKeysWithValues: (textBoxPlanFailureReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let linePlanSummaryByBlock = Dictionary(
            uniqueKeysWithValues: (lineTextBoxPlanReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let linePlanByID = Dictionary(
            uniqueKeysWithValues: (lineTextBoxPlanReport?.plans ?? []).map { ($0.planID, $0) }
        )
        let lineExperimentSummaryByBlock = Dictionary(
            uniqueKeysWithValues: (lineCropExperimentReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let lineExperimentCandidateByID = Dictionary(
            uniqueKeysWithValues: (lineCropExperimentReport?.candidates ?? []).map { ($0.candidateID, $0) }
        )
        let externalArtifactAlignmentByBlock = Dictionary(
            uniqueKeysWithValues: (externalArtifactReadinessReport?.blockAlignment ?? []).map { ($0.blockIndex, $0) }
        )
        let externalShadowSummaryByBlock = Dictionary(
            uniqueKeysWithValues: (externalTextBoxShadowOCRReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let internalBottleneckByBlock = Dictionary(
            uniqueKeysWithValues: (internalStructureBottleneckReport?.blockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let routingComparisonByBlock = Dictionary(
            uniqueKeysWithValues: (routingDrivenTranslationComparisonReport?.cases ?? []).map { ($0.blockIndex, $0) }
        )
        let ocrDamageByBlock = Dictionary(
            uniqueKeysWithValues: (ocrCharacterDamageAuditReport?.cases ?? []).map { ($0.blockIndex, $0) }
        )
        let readingOrderByBlock = Dictionary(
            uniqueKeysWithValues: (readingOrderStructureAuditReport?.cases ?? []).map { ($0.blockIndex, $0) }
        )
        let structureActionByBlock = Dictionary(
            uniqueKeysWithValues: (structureActionCandidateReport?.cases ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuArtifactTraceByBlock = Dictionary(
            uniqueKeysWithValues: (koharuArtifactDAGReport?.blockTraces ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuStageGapPlanByBlock = Dictionary(
            uniqueKeysWithValues: (koharuStageGapReplicationReport?.blockPlans ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuNativeScorecardByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeReplicationScoreboardReport?.blockScorecards ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeTextBoxLedgerByBlock = Dictionary(
            uniqueKeysWithValues: (nativeTextBoxProxyLedgerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let bubbleMaskScoreboardByBlock = Dictionary(
            uniqueKeysWithValues: (bubbleMaskAssignmentSplitScoreboardReport?.blockScorecards ?? []).map { ($0.blockIndex, $0) }
        )
        let segmentMaskProxyScoreboardByBlock = Dictionary(
            uniqueKeysWithValues: (segmentMaskProxyCoverageScoreboardReport?.blockScorecards ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuConvergencePathByBlock = Dictionary(
            uniqueKeysWithValues: (koharuArtifactConvergenceReport?.blockPaths ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuResolverTraceByBlock = Dictionary(
            uniqueKeysWithValues: (koharuPipelineResolverReport?.blockTraces ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuWorkOrderRouteByBlock = Dictionary(
            uniqueKeysWithValues: (koharuWorkOrderRouterReport?.blockRoutes ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuExternalArtifactRequestByBlock = Dictionary(
            uniqueKeysWithValues: (koharuExternalArtifactRequestPacketReport?.blockRequests ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuNativeReplayRouteByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeAlgorithmReplayMatrixReport?.blockRoutes ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuBubbleIndexBlockLedgerByBlock = Dictionary(
            uniqueKeysWithValues: (koharuBubbleIndexShadowLedgerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let translationFloorNoisyByBlock = Dictionary(
            uniqueKeysWithValues: (translationModelFloorComparisonReport?.noisyBlockSummaries ?? []).map { ($0.blockIndex, $0) }
        )
        let renderLockByBlock = Dictionary(
            uniqueKeysWithValues: (koharuRenderRegressionLockReport?.blockLocks ?? []).map { ($0.blockIndex, $0) }
        )
        let maskByBlock = Dictionary(
            uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        let correctionByBlock = Dictionary(
            uniqueKeysWithValues: (bubbleAssignmentCorrectionReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
        )
        var splitByBlock: [Int: MangaOverlayBubbleSplitCandidateDiagnostic] = [:]
        for diagnostic in bubbleSplitCandidateReport?.diagnostics ?? [] {
            for index in diagnostic.seedBlockIndexes where splitByBlock[index] == nil {
                splitByBlock[index] = diagnostic
            }
        }
        let content = blocks.map { block in
            let bbox = block.bbox.map { String(Int($0.rounded())) }.joined(separator: ",")
            let raw = block.rawOcrText.replacing("\n", with: " / ")
            let preprocessed = block.afterPreprocessingOcrText?.replacing("\n", with: " / ") ?? "nil"
            let adaptivePreprocessed = block.adaptivePreprocessingOcrText?.replacing("\n", with: " / ") ?? "nil"
            let fixedPreprocessed = block.fixedPreprocessingOcrText?.replacing("\n", with: " / ") ?? "nil"
            let final = block.finalTextUsedForTranslation.replacing("\n", with: " / ")
            let deterministic = block.deterministicCorrectionText?.replacing("\n", with: " / ") ?? "nil"
            let truth = block.bestGroundTruthText ?? "nil"
            let bubbleID = block.bubbleID.map(String.init) ?? "nil"
            let similarity = block.ocrGroundTruthSimilarity.map {
                $0.formatted(.number.precision(.fractionLength(3)))
            } ?? "nil"
            let legacySimilarity = block.ocrLegacySimilarity.map {
                $0.formatted(.number.precision(.fractionLength(3)))
            } ?? "nil"
            let translation = block.translationCandidate.replacing("\n", with: " / ")
            let rawOutput = block.rawOutput.replacing("\n", with: " / ")
            let deterministicTranslation = block.deterministicCorrectionTranslationCandidate?.replacing("\n", with: " / ") ?? "nil"
            let deterministicTranslationRaw = block.deterministicCorrectionTranslationRawOutput?.replacing("\n", with: " / ") ?? "nil"
            let sliceIndex = block.sliceIndex.map(String.init) ?? "nil"
            let safeLayout = block.safeLayoutRect?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let renderBounds = block.renderNonTransparentBounds?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let glyphRect = block.glyphMaskRect?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let backgroundStdDev = block.backgroundColorStdDev?.formatted(.number.precision(.fractionLength(2))) ?? "nil"
            let textRegion = textRegionByBlock[block.index]
            let textRegionCrop = textRegion?.textRegionCropText?.replacing("\n", with: " / ") ?? "nil"
            let textRegionSelected = textRegion?.selectedText.replacing("\n", with: " / ") ?? "nil"
            let textRegionCropBBox = textRegion?.cropBBox.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textRegionClampSource = textRegion?.clampSource ?? "nil"
            let textRegionSubRegionID = textRegion?.subRegionID.map(String.init) ?? "nil"
            let textRegionSubRegionBBox = textRegion?.subRegionBBox?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textRegionSubRegionCoverage = textRegion?.subRegionCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textRegionSubRegionRejected = textRegion?.subRegionRejectedReason ?? "nil"
            let textRegionCropBeforeSubRegion = textRegion?.cropBBoxBeforeSubRegionClamp.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textRegionCropAfterSubRegion = textRegion?.cropBBoxAfterSubRegionClamp.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textRegionCropBeforeAssignment = textRegion?.cropBBoxBeforeAssignmentCorrection?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textRegionCropAfterAssignment = textRegion?.cropBBoxAfterAssignmentCorrection?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textRegionCropMaskCoverage = textRegion?.cropMaskCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textRegionCropMaskCoverageBefore = textRegion?.cropMaskCoverageBefore?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textRegionCropMaskCoverageAfter = textRegion?.cropMaskCoverageAfter?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textRegionCropMaskRejected = textRegion?.cropMaskRejectedReason ?? "nil"
            let textRegionCorrectedBubbleID = textRegion?.correctedBubbleID.map(String.init) ?? "nil"
            let textRegionSplitCandidateID = textRegion?.splitCandidateID.map(String.init) ?? "nil"
            let textRegionAssignmentRejected = textRegion?.assignmentCorrectionRejectedReason ?? "nil"
            let textRegionSplitRejected = textRegion?.splitCandidateRejectedReason ?? "nil"
            let textRegionReasons = textRegion?.rejectionReasons.joined(separator: " | ") ?? "nil"
            let textRegionPreservation = textRegion?.rawWordPreservationRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textRegionQuality = textRegion.map {
                "\($0.originalQualityScore.formatted(.number.precision(.fractionLength(3)))) -> \($0.candidateQualityScore.formatted(.number.precision(.fractionLength(3))))"
            } ?? "nil"
            let mask = maskByBlock[block.index]
            let maskDominantID = mask?.maskDominantBubbleID.map(String.init) ?? "nil"
            let maskDominantCoverage = mask?.maskDominantCoverageRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let maskSafeRect = mask?.maskSafeRect?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let correction = correctionByBlock[block.index]
            let correctionReasons = correction?.rejectionReasons.joined(separator: " | ") ?? "nil"
            let correctionRisks = correction?.riskFlags.joined(separator: " | ") ?? "nil"
            let split = splitByBlock[block.index]
            let splitReasons = split?.rejectionReasons.joined(separator: " | ") ?? "nil"
            let splitBBox = split?.bbox.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textBox = textBoxByBlock[block.index]
            let textBoxBBox = textBox?.bbox.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let textBoxRejections = textBox?.rejectionReasons.joined(separator: " | ") ?? "nil"
            let textBoxRisks = textBox?.riskFlags.joined(separator: " | ") ?? "nil"
            let textBoxScore = textBox?.evidenceScore.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textBoxGlyphOverlap = textBox?.glyphOverlapRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let textBoxBubbleCoverage = textBox?.bubbleMaskCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let segment = segmentByBlock[block.index]
            let segmentTextBoxCoverage = segment?.textBoxCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let segmentBubbleCoverage = segment?.bubbleMaskCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let segmentRejections = segment?.rejectionReasons.joined(separator: " | ") ?? "nil"
            let preCropSummary = preCropPlanSummaryByBlock[block.index]
            let preCropSelectedPlans = preCropSummary?.selectedPlanIDsForShadowOCR
                .compactMap { preCropPlanByID[$0] }
                .map { "\($0.planID):\($0.variantName):score=\($0.evidenceScore.formatted(.number.precision(.fractionLength(3)))) bbox=[\($0.bbox.map { String(Int($0.rounded())) }.joined(separator: ","))]" }
                .joined(separator: " | ") ?? "nil"
            let preCropRejectedPlans = preCropSummary?.rejectedPlanIDs.map(String.init).joined(separator: ",") ?? "nil"
            let preCropStopReasons = preCropSummary?.stopReasons.joined(separator: " | ") ?? "nil"
            let experimentSummary = experimentSummaryByBlock[block.index]
            let controlCandidate = experimentSummary?.controlCandidateID.flatMap { experimentCandidateByID[$0] }
            let bestShadowCandidate = experimentSummary?.bestShadowCandidateID.flatMap { experimentCandidateByID[$0] }
            let experimentControlText = controlCandidate?.ocrText?.replacing("\n", with: " / ") ?? "nil"
            let experimentShadowText = bestShadowCandidate?.ocrText?.replacing("\n", with: " / ") ?? "nil"
            let experimentControlQuality = controlCandidate?.qualityScoreAfter.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let experimentShadowQuality = bestShadowCandidate?.qualityScoreAfter.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let experimentShadowDelta = bestShadowCandidate?.qualityDelta.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let experimentStopReasons = experimentSummary?.stopReasons.joined(separator: " | ") ?? "nil"
            let failureSummary = failureSummaryByBlock[block.index]
            let failurePassedChecks = failureSummary?.passedPromotionChecks.joined(separator: " | ") ?? "nil"
            let failureFailedChecks = failureSummary?.failedPromotionChecks.joined(separator: " | ") ?? "nil"
            let failureBlockers = failureSummary?.promotionBlockers.joined(separator: " | ") ?? "nil"
            let linePlanSummary = linePlanSummaryByBlock[block.index]
            let lineSelectedPlans = linePlanSummary?.selectedPlanIDsForShadowOCR
                .compactMap { linePlanByID[$0] }
                .map {
                    "\($0.planID):\($0.variantName):parent=\($0.parentPlanID.map(String.init) ?? "nil"):angle=\($0.deskewAngleDegrees?.formatted(.number.precision(.fractionLength(1))) ?? "nil"):score=\($0.evidenceScore.formatted(.number.precision(.fractionLength(3)))) ocrExecuted=\($0.ocrExecuted) bbox=[\($0.bbox.map { String(Int($0.rounded())) }.joined(separator: ","))]"
                }
                .joined(separator: " | ") ?? "nil"
            let lineRejectedPlans = linePlanSummary?.rejectedPlanIDs.map(String.init).joined(separator: ",") ?? "nil"
            let linePlanStopReasons = linePlanSummary?.stopReasons.joined(separator: " | ") ?? "nil"
            let lineExperimentSummary = lineExperimentSummaryByBlock[block.index]
            let bestLineCandidate = lineExperimentSummary?.bestShadowCandidateID.flatMap { lineExperimentCandidateByID[$0] }
            let lineBestText = bestLineCandidate?.ocrText?.replacing("\n", with: " / ") ?? "nil"
            let lineBestDelta = bestLineCandidate?.qualityDelta.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let lineBestPreservation = bestLineCandidate?.wordPreservationRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let linePromotionChecks = bestLineCandidate.map { candidate -> (passed: String, failed: String) in
                var passed: [String] = []
                var failed: [String] = []
                candidate.ocrSucceeded ? passed.append("ocrSucceeded") : failed.append("emptyLocalOCR")
                candidate.wordPreservationRatio >= 0.80 ? passed.append("wordPreservationRatio>=0.80") : failed.append("wordPreservationRatioBelow0.80")
                candidate.qualityDelta > 0.08 ? passed.append("qualityDelta>0.08") : failed.append("qualityDeltaBelowOrEqual0.08")
                for blocker in candidate.rejectionReasons + candidate.riskFlags {
                    failed.append(blocker)
                }
                return (Array(Set(passed)).sorted().joined(separator: " | "), Array(Set(failed)).sorted().joined(separator: " | "))
            }
            let lineResearchDecision = lineExperimentSummary?.notes
                .filter { $0.hasPrefix("lineResearchDecision=") || $0.hasPrefix("reason=") }
                .joined(separator: " ") ?? "skipped"
            let lineStopReasons = lineExperimentSummary?.stopReasons.joined(separator: " | ") ?? "nil"
            let externalAlignment = externalArtifactAlignmentByBlock[block.index]
            let externalReadiness = externalArtifactReadinessReport?.readinessVerdict ?? "nil"
            let externalNextAction = externalArtifactReadinessReport?.nextAction ?? "nil"
            let externalShadowAllowed = externalArtifactReadinessReport.map { String($0.externalTextBoxesShadowOCRAllowed) } ?? "nil"
            let externalActiveDirectory = externalArtifactReadinessReport.map { String($0.activeArtifactsDirectory) } ?? "nil"
            let externalContractExampleOnly = externalArtifactReadinessReport.map { String($0.contractExampleOnly) } ?? "nil"
            let externalTextBoxMatch = externalAlignment?.bestTextBoxID ?? "none"
            let externalTextBoxIoU = externalAlignment?.bestTextBoxIoU?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let externalBubbleMatch = externalAlignment?.bestBubbleInstanceID ?? "none"
            let externalBubbleIoU = externalAlignment?.bestBubbleIoU?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let externalSegmentCoverage = externalAlignment?.segmentCoverageLevel ?? "missing"
            let externalAlignmentVerdict = externalAlignment?.alignmentVerdict ?? "notEvaluatedMissingArtifacts"
            let externalShadowSummary = externalShadowSummaryByBlock[block.index]
            let externalShadowBBox = externalShadowSummary?.candidateBBox?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil"
            let externalShadowText = externalShadowSummary?.ocrText?.replacing("\n", with: " / ") ?? "nil"
            let externalShadowDelta = externalShadowSummary?.qualityDelta?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let externalShadowPreservation = externalShadowSummary?.wordPreservationRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let externalShadowBlockers = externalShadowSummary?.blockers.joined(separator: " | ") ?? "nil"
            let bottleneck = internalBottleneckByBlock[block.index]
            let bottleneckSecondary = bottleneck?.secondaryBottlenecks.joined(separator: " | ") ?? "nil"
            let bottleneckEvidence = bottleneck?.evidence.joined(separator: " | ") ?? "nil"
            let bottleneckMustNotPromote = bottleneck?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let routingComparison = routingComparisonByBlock[block.index]
            let routingVariantFailureReasons = routingComparison?.variantFailureReasons.joined(separator: " | ") ?? "nil"
            let routingMustNotPromote = routingComparison?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let ocrDamage = ocrDamageByBlock[block.index]
            let damagedTokens = ocrDamage?.damagedTokens.joined(separator: ",") ?? "nil"
            let missingTokens = ocrDamage?.missingGroundTruthTokens.joined(separator: ",") ?? "nil"
            let extraTokens = ocrDamage?.extraOcrTokens.joined(separator: ",") ?? "nil"
            let substitutions = ocrDamage?.suspectedSubstitutions.joined(separator: ",") ?? "nil"
            let repeatedDamage = ocrDamage?.repeatedKeywordDamage.joined(separator: ",") ?? "nil"
            let ocrDamageCropBlockers = ocrDamage?.cropBlockers.joined(separator: " | ") ?? "nil"
            let ocrDamageMustNotPromote = ocrDamage?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let readingOrder = readingOrderByBlock[block.index]
            let readingOrderRisks = readingOrder?.orderRiskFlags.joined(separator: " | ") ?? "nil"
            let readingOrderSiblings = readingOrder?.sameBubbleSiblingBlockIndexes.map(String.init).joined(separator: ",") ?? "nil"
            let readingOrderMustNotPromote = readingOrder?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let structureAction = structureActionByBlock[block.index]
            let structureActionTypes = structureAction?.candidateTypes.joined(separator: ",") ?? "nil"
            let structureActionVerdicts = structureAction?.promotionVerdicts.joined(separator: ",") ?? "nil"
            let structureActionNextSteps = structureAction?.recommendedNextSteps.joined(separator: ",") ?? "nil"
            let structureActionSkipReasons = structureAction?.candidates
                .compactMap(\.executionSkippedReason)
                .joined(separator: " | ") ?? "nil"
            let structureActionDeltas = structureAction?.candidates
                .map { "\($0.candidateType):\($0.delta.summary.joined(separator: "+"))" }
                .joined(separator: " | ") ?? "nil"
            let koharuArtifactTrace = koharuArtifactTraceByBlock[block.index]
            let koharuStageStatus = koharuArtifactTrace?.stageTraces
                .filter { ["bubbleMask", "textBoxes", "segmentMask", "ocrText", "translation", "renderLayout"].contains($0.stageName) }
                .map { "\($0.stageName)=\($0.status)" }
                .joined(separator: " | ") ?? "nil"
            let koharuStageGapPlan = koharuStageGapPlanByBlock[block.index]
            let koharuStageGapEvidence = koharuStageGapPlan?.minimumEvidenceToCollect.joined(separator: " | ") ?? "nil"
            let koharuStageGapMustNotPromote = koharuStageGapPlan?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let koharuNativeScorecard = koharuNativeScorecardByBlock[block.index]
            let koharuNativeStopEvidence = koharuNativeScorecard?.stopEvidence.joined(separator: " | ") ?? "nil"
            let koharuNativePrioritySignals = koharuNativeScorecard?.prioritySignals.joined(separator: " | ") ?? "nil"
            let koharuNativeMustNotPromote = koharuNativeScorecard?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let nativeTextBoxLedger = nativeTextBoxLedgerByBlock[block.index]
            let nativeTextBoxSources = nativeTextBoxLedger?.candidateSources.joined(separator: ",") ?? "nil"
            let nativeTextBoxStopReasons = nativeTextBoxLedger?.stoplistReasons.joined(separator: " | ") ?? "nil"
            let nativeTextBoxGates = [
                "word=\(nativeTextBoxLedger?.rawWordPreservationStatus ?? "nil")",
                "protected=\(nativeTextBoxLedger?.protectedKeywordStatus ?? "nil")",
                "bubble=\(nativeTextBoxLedger?.bubbleConstraintStatus ?? "nil")",
                "segment=\(nativeTextBoxLedger?.segmentMaskConstraintStatus ?? "nil")",
                "damage=\(nativeTextBoxLedger?.ocrDamageStatus ?? "nil")",
                "model=\(nativeTextBoxLedger?.translationModelFloorStatus ?? "nil")",
                "render=\(nativeTextBoxLedger?.renderStatus ?? "nil")"
            ].joined(separator: ",")
            let bubbleMaskScoreboard = bubbleMaskScoreboardByBlock[block.index]
            let bubbleMaskScoreboardSiblings = bubbleMaskScoreboard?.siblingBlockIndexes.map(String.init).joined(separator: ",") ?? "nil"
            let bubbleMaskScoreboardSplitIDs = bubbleMaskScoreboard?.splitCandidateIDs.map(String.init).joined(separator: ",") ?? "nil"
            let bubbleMaskScoreboardMustNotPromote = bubbleMaskScoreboard?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let segmentMaskProxyScoreboard = segmentMaskProxyScoreboardByBlock[block.index]
            let segmentMaskProxyTextBoxCoverage = segmentMaskProxyScoreboard?.textBoxCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let segmentMaskProxyBubbleCoverage = segmentMaskProxyScoreboard?.bubbleMaskCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let segmentMaskProxySafeRectCoverage = segmentMaskProxyScoreboard?.safeRectCoverageRatio?.formatted(.number.precision(.fractionLength(3))) ?? "nil"
            let segmentMaskProxyMustNotPromote = segmentMaskProxyScoreboard?.mustNotPromoteReasons.joined(separator: " | ") ?? "nil"
            let koharuArtifactPath = koharuConvergencePathByBlock[block.index]
            let koharuResolverTrace = koharuResolverTraceByBlock[block.index]
            let koharuWorkOrderRoute = koharuWorkOrderRouteByBlock[block.index]
            let koharuExternalArtifactRequest = koharuExternalArtifactRequestByBlock[block.index]
            let koharuNativeReplayRoute = koharuNativeReplayRouteByBlock[block.index]
            let koharuBubbleIndexBlockLedger = koharuBubbleIndexBlockLedgerByBlock[block.index]
            let translationFloorNoisy = translationFloorNoisyByBlock[block.index]
            let renderLock = renderLockByBlock[block.index]
            let cropAttribution = textRegion?.failureAttribution.joined(separator: " | ") ?? "nil"
            return """
            #\(block.index) bbox=[\(bbox)] bubbleID=\(bubbleID) bubbleAssignmentMethod=\(block.bubbleAssignmentMethod) crossBubbleMergeRejected=\(block.crossBubbleMergeRejected) sliceIndex=\(sliceIndex) sliceOverlapDeduped=\(block.sliceOverlapDeduped) angle=\(block.rotationAngleUsed) groundTruthMatch=\(block.groundTruthMatch) ocrSimilarity=\(similarity) legacySimilarity=\(legacySimilarity) wordOrder=\(block.wordOrderPreserved.map(String.init) ?? "nil") blockPassed=\(block.blockPassed)
            rawOCR: \(raw)
            afterPreprocessing: \(preprocessed)
            adaptivePreprocessing: \(adaptivePreprocessed)
            fixedPreprocessing: \(fixedPreprocessed)
            cropPaddingX: \(block.cropPaddingX?.formatted(.number.precision(.fractionLength(1))) ?? "nil")
            cropPaddingY: \(block.cropPaddingY?.formatted(.number.precision(.fractionLength(1))) ?? "nil")
            cropClampedByBubble: \(block.cropClampedByBubble)
            cropCandidatePreservesRawWords: \(block.cropCandidatePreservesRawWords)
            cropFallbackTriggered: \(block.cropFallbackTriggered)
            cropFallbackReason: \(block.cropFallbackReason ?? "nil")
            cropStrategyUsed: \(block.cropStrategyUsed ?? "nil")
            textRegionCrop: \(textRegionCrop)
            textRegionSelected: \(textRegionSelected)
            textRegionAdopted: \(textRegion.map { String($0.adopted) } ?? "nil")
            textRegionSelectionReason: \(textRegion?.selectionReason ?? "nil")
            textRegionRejectionReasons: \(textRegionReasons)
            textRegionCropBBox: [\(textRegionCropBBox)]
            textRegionClampSource: \(textRegionClampSource)
            textRegionSubRegionID: \(textRegionSubRegionID)
            textRegionSubRegionBBox: [\(textRegionSubRegionBBox)]
            textRegionSubRegionCoverage: \(textRegionSubRegionCoverage)
            textRegionSubRegionRejectedReason: \(textRegionSubRegionRejected)
            textRegionCropBBoxBeforeSubRegionClamp: [\(textRegionCropBeforeSubRegion)]
            textRegionCropBBoxAfterSubRegionClamp: [\(textRegionCropAfterSubRegion)]
            textRegionCorrectedBubbleID: \(textRegionCorrectedBubbleID)
            textRegionSplitCandidateID: \(textRegionSplitCandidateID)
            textRegionCropBBoxBeforeAssignmentCorrection: [\(textRegionCropBeforeAssignment)]
            textRegionCropBBoxAfterAssignmentCorrection: [\(textRegionCropAfterAssignment)]
            textRegionCropMaskCoverage: \(textRegionCropMaskCoverage)
            textRegionCropMaskCoverageBefore: \(textRegionCropMaskCoverageBefore)
            textRegionCropMaskCoverageAfter: \(textRegionCropMaskCoverageAfter)
            textRegionCropMaskRejectedReason: \(textRegionCropMaskRejected)
            textRegionAssignmentCorrectionRejectedReason: \(textRegionAssignmentRejected)
            textRegionSplitCandidateRejectedReason: \(textRegionSplitRejected)
            textRegionWordPreservation: \(textRegionPreservation)
            textRegionQualityScore: \(textRegionQuality)
            textBoxCandidate: id=\(textBox.map { String($0.id) } ?? "nil") source=\(textBox?.source ?? "nil") bbox=[\(textBoxBBox)] evidenceScore=\(textBoxScore) eligibleForCrop=\(textBox.map { String($0.eligibleForCrop) } ?? "nil") derivedFromTextRegionCrop=\(textBox.map { String($0.derivedFromTextRegionCrop) } ?? "nil") usedForTextRegionCrop=\(textBox.map { String($0.usedForTextRegionCrop) } ?? "nil") glyphOverlap=\(textBoxGlyphOverlap) bubbleCoverage=\(textBoxBubbleCoverage) rejections=\(textBoxRejections) risks=\(textBoxRisks)
            segmentMask: pixels=\(segment.map { String($0.glyphMaskPixelCount) } ?? "nil") rect=[\(glyphRect)] fillRects=\(segment.map { String($0.glyphMaskFillRectCount) } ?? "nil") textBoxCoverage=\(segmentTextBoxCoverage) bubbleCoverage=\(segmentBubbleCoverage) usableForCropEvidence=\(segment.map { String($0.usableForCropEvidence) } ?? "nil") rejections=\(segmentRejections)
            preCropTextBoxPlans: shadowOnly=true groundTruthNotUsed=true notWrittenToFinalTextUsedForTranslation=true selected=[\(preCropSelectedPlans)] rejectedPlanIDs=[\(preCropRejectedPlans)] planningVerdict=\(preCropSummary?.planningVerdict ?? "nil") stopReasons=\(preCropStopReasons)
            cropExperiment: controlID=\(experimentSummary?.controlCandidateID.map(String.init) ?? "nil") controlVariant=\(controlCandidate?.variantName ?? "nil") controlText=\(experimentControlText) controlQuality=\(experimentControlQuality) bestShadowID=\(experimentSummary?.bestShadowCandidateID.map(String.init) ?? "nil") bestVariant=\(experimentSummary?.bestVariantName ?? "nil") bestText=\(experimentShadowText) bestQuality=\(experimentShadowQuality) qualityDelta=\(experimentShadowDelta) promotionVerdict=\(experimentSummary?.promotionVerdict ?? "nil") stopReasons=\(experimentStopReasons)
            textBoxPlanFailure: primary=\(failureSummary?.primaryFailureCategory ?? "nil") verdict=\(failureSummary?.verdict ?? "nil") action=\(failureSummary?.recommendedNextAction ?? "nil") bestShadowBetterThanControl=\(failureSummary.map { String($0.bestShadowBetterThanControl) } ?? "nil") blockers=\(failureBlockers)
            promotionChecks: passed=\(failurePassedChecks) failed=\(failureFailedChecks)
            lineTextBoxPlans: shadowOnly=true targetBy=v1.9ContinueGeometry selected=[\(lineSelectedPlans)] rejectedPlanIDs=[\(lineRejectedPlans)] planningVerdict=\(linePlanSummary?.planningVerdict ?? "skipped") stopReasons=\(linePlanStopReasons)
            lineCropExperiment: bestLineShadowID=\(lineExperimentSummary?.bestShadowCandidateID.map(String.init) ?? "nil") bestVariant=\(lineExperimentSummary?.bestVariantName ?? "nil") bestText=\(lineBestText) qualityDelta=\(lineBestDelta) wordPreservation=\(lineBestPreservation) promotionVerdict=\(lineExperimentSummary?.promotionVerdict ?? "nil") stopReasons=\(lineStopReasons)
            linePromotionChecks: passed=\(linePromotionChecks?.passed ?? "nil") failed=\(linePromotionChecks?.failed ?? "nil")
            lineResearchDecision: \(lineResearchDecision)
            externalArtifacts: readiness=\(externalReadiness) shadowOCRAllowed=\(externalShadowAllowed) activeDirectory=\(externalActiveDirectory) contractExampleOnly=\(externalContractExampleOnly) textBoxID=\(externalTextBoxMatch) textBoxIoU=\(externalTextBoxIoU) bubbleInstanceID=\(externalBubbleMatch) bubbleIoU=\(externalBubbleIoU) segmentMask=\(externalSegmentCoverage) alignment=\(externalAlignmentVerdict) nextAction=\(externalNextAction)
            externalTextBoxShadowOCR: executed=\(externalShadowSummary.map { String($0.ocrExecuted) } ?? "false") selectedTextBoxID=\(externalShadowSummary?.selectedTextBoxID ?? "none") candidateBBox=[\(externalShadowBBox)] ocrSucceeded=\(externalShadowSummary.map { String($0.ocrSucceeded) } ?? "false") ocrText=\(externalShadowText) qualityDelta=\(externalShadowDelta) wordPreservation=\(externalShadowPreservation) promotionVerdict=\(externalShadowSummary?.promotionVerdict ?? "skipped") blockers=\(externalShadowBlockers)
            internalStructureBottleneck: primary=\(bottleneck?.primaryBottleneck ?? "nil") secondary=\(bottleneckSecondary) recommended=\(bottleneck?.recommendedNextAction ?? "nil") evidence=\(bottleneckEvidence) mustNotPromote=\(bottleneckMustNotPromote)
            routingDrivenTranslationComparison: variantID=\(routingComparison?.variantID ?? "nil") improvement=\(routingComparison?.improvementCategory ?? "nil") controlPassed=\(routingComparison.map { String($0.controlPassed) } ?? "nil") variantPassed=\(routingComparison.map { String($0.variantPassed) } ?? "nil") variantCandidate=\(routingComparison?.variantCandidate.replacing("\n", with: " / ") ?? "nil") variantRawClass=\(routingComparison?.variantRawOutputClassification ?? "nil") variantCandidateClass=\(routingComparison?.variantCandidateClassification ?? "nil") latinLeakReduced=\(routingComparison.map { String($0.latinLeakReduced) } ?? "nil") failures=\(routingVariantFailureReasons) diagnosticOnly=\(routingComparison.map { String($0.diagnosticOnly) } ?? "nil") mustNotPromote=\(routingMustNotPromote)
            ocrCharacterDamageAudit: damaged=[\(damagedTokens)] missing=[\(missingTokens)] extra=[\(extraTokens)] substitutions=[\(substitutions)] repeatedKeywordDamage=[\(repeatedDamage)] lineBreakRisk=\(ocrDamage.map { String($0.lineBreakRisk) } ?? "nil") action=\(ocrDamage?.recommendedNextAction ?? "nil") cropBlockers=\(ocrDamageCropBlockers) textBoxEvidence=\(ocrDamage?.textBoxEvidenceSummary ?? "nil") segmentEvidence=\(ocrDamage?.segmentMaskEvidenceSummary ?? "nil") diagnosticOnly=\(ocrDamage.map { String($0.diagnosticOnly) } ?? "nil") mustNotPromote=\(ocrDamageMustNotPromote)
            readingOrderStructureAudit: currentOrderIndex=\(readingOrder.map { String($0.currentOrderIndex) } ?? "nil") proposedReadingOrderIndex=\(readingOrder.map { String($0.proposedReadingOrderIndex) } ?? "nil") orderChanged=\(readingOrder.map { String($0.orderChanged) } ?? "nil") orderConfidence=\(readingOrder?.orderConfidence.formatted(.number.precision(.fractionLength(3))) ?? "nil") bubbleGroupID=\(readingOrder?.bubbleGroupID ?? "nil") sameBubbleSiblingBlockIndexes=[\(readingOrderSiblings)] bubbleAssignmentRisk=\(readingOrder?.bubbleAssignmentRisk ?? "nil") splitOrMergeRisk=\(readingOrder?.splitOrMergeRisk ?? "nil") duplicateOrFragmentRisk=\(readingOrder?.duplicateOrFragmentRisk ?? "nil") recommendedStructureAction=\(readingOrder?.recommendedStructureAction ?? "nil") risks=\(readingOrderRisks) diagnosticOnly=\(readingOrder.map { String($0.diagnosticOnly) } ?? "nil") mustNotPromote=\(readingOrderMustNotPromote)
            structureActionCandidates: count=\(structureAction.map { String($0.candidateCount) } ?? "0") executed=\(structureAction.map { String($0.executedCandidateCount) } ?? "0") types=\(structureActionTypes) verdicts=\(structureActionVerdicts) nextSteps=\(structureActionNextSteps) skipped=\(structureActionSkipReasons) deltas=\(structureActionDeltas)
            koharuArtifactTrace: firstBlockingStage=\(koharuArtifactTrace?.firstBlockingStage ?? "nil") firstBlockingReason=\(koharuArtifactTrace?.firstBlockingReason ?? "nil") downstreamImpacts=\(koharuArtifactTrace?.downstreamImpacts.joined(separator: ",") ?? "nil") recommendedNextAction=\(koharuArtifactTrace?.recommendedNextAction ?? "nil") keyStages=\(koharuStageStatus)
            koharuStageGapPlan: firstBlocking=\(koharuStageGapPlan?.firstBlockingStageFromDAG ?? "nil") targetStage=\(koharuStageGapPlan?.targetCanonicalStage ?? "nil") gap=\(koharuStageGapPlan?.primaryGapCategory ?? "nil") workPackage=\(koharuStageGapPlan?.recommendedWorkPackageID ?? "nil") requiresRealArtifact=\(koharuStageGapPlan.map { String($0.requiresRealExternalArtifact) } ?? "nil") requiresFullProbe=\(koharuStageGapPlan.map { String($0.requiresFullProbe) } ?? "nil") canCIFast=\(koharuStageGapPlan.map { String($0.canBeEvaluatedInCIFast) } ?? "nil") nextAction=\(koharuStageGapPlan?.nextAction ?? "nil") evidence=\(koharuStageGapEvidence) mustNotPromote=\(koharuStageGapMustNotPromote)
            koharuNativeBlockScorecard: primaryStage=\(koharuNativeScorecard?.primaryNativeStage ?? "nil") bottleneck=\(koharuNativeScorecard?.primaryBottleneck ?? "nil") priority=\(koharuNativeScorecard?.recommendedPriority ?? "nil") ocrGate=\(koharuNativeScorecard?.ocrGateStatus ?? "nil") bubbleGate=\(koharuNativeScorecard?.bubbleGateStatus ?? "nil") segmentGate=\(koharuNativeScorecard?.segmentGateStatus ?? "nil") translationGate=\(koharuNativeScorecard?.translationGateStatus ?? "nil") renderGate=\(koharuNativeScorecard?.renderGateStatus ?? "nil") stopLocalCropOrLine=\(koharuNativeScorecard.map { String($0.stopLocalCropOrLineTuning) } ?? "nil") stopEvidence=\(koharuNativeStopEvidence) workItem=\(koharuNativeScorecard?.recommendedWorkItemID ?? "nil") nextAction=\(koharuNativeScorecard?.nextAction ?? "nil") prioritySignals=\(koharuNativePrioritySignals) mustNotPromote=\(koharuNativeMustNotPromote)
            nativeTextBoxProxyLedger: qualityStatus=\(nativeTextBoxLedger?.qualityStatus ?? "nil") sources=\(nativeTextBoxSources) stoplistHit=\(nativeTextBoxLedger.map { String($0.stoplistHit) } ?? "nil") primaryFreezeReason=\(nativeTextBoxLedger?.primaryFreezeReason ?? "nil") gates=\(nativeTextBoxGates) nextAction=\(nativeTextBoxLedger?.nextAction ?? "nil") stopReasons=\(nativeTextBoxStopReasons)
            bubbleMaskScoreboard: assignmentStatus=\(bubbleMaskScoreboard?.assignmentStatus ?? "nil") maskDominantBubbleID=\(bubbleMaskScoreboard?.maskDominantBubbleID.map(String.init) ?? "nil") splitRisk=\(bubbleMaskScoreboard?.splitRisk ?? "nil") splitCandidateIDs=[\(bubbleMaskScoreboardSplitIDs)] siblings=[\(bubbleMaskScoreboardSiblings)] siblingLayoutStatus=\(bubbleMaskScoreboard?.siblingLayoutStatus ?? "nil") renderMaskStatus=\(bubbleMaskScoreboard?.renderMaskStatus ?? "nil") nextAction=\(bubbleMaskScoreboard?.nextAction ?? "nil") mustNotPromote=\(bubbleMaskScoreboardMustNotPromote)
            segmentMaskProxyScoreboard: coverage=\(segmentMaskProxyScoreboard?.coverageStatus ?? "nil") cleanup=\(segmentMaskProxyScoreboard?.cleanupStatus ?? "nil") renderMask=\(segmentMaskProxyScoreboard?.renderMaskStatus ?? "nil") glyphPixels=\(segmentMaskProxyScoreboard.map { String($0.glyphMaskPixelCount) } ?? "nil") textBoxCoverage=\(segmentMaskProxyTextBoxCoverage) bubbleCoverage=\(segmentMaskProxyBubbleCoverage) safeRectCoverage=\(segmentMaskProxySafeRectCoverage) backgroundFill=\(segmentMaskProxyScoreboard.map { String($0.backgroundFillApplied) } ?? "nil") nextAction=\(segmentMaskProxyScoreboard?.nextAction ?? "nil") mustNotPromote=\(segmentMaskProxyMustNotPromote)
            koharuArtifactPath: firstBlockingArtifact=\(koharuArtifactPath?.firstBlockingArtifact ?? "nil") textBox=\(koharuArtifactPath?.textBoxStatus ?? "nil") bubble=\(koharuArtifactPath?.bubbleMaskStatus ?? "nil") segment=\(koharuArtifactPath?.segmentMaskStatus ?? "nil") translation=\(koharuArtifactPath?.translationStatus ?? "nil") render=\(koharuArtifactPath?.renderStatus ?? "nil") modelFloorLimited=\(koharuArtifactPath.map { String($0.modelFloorLimited) } ?? "nil") renderLocked=\(koharuArtifactPath.map { String($0.renderLocked) } ?? "nil") needsRealArtifact=\(koharuArtifactPath.map { String($0.needsRealArtifact) } ?? "nil") nextAction=\(koharuArtifactPath?.primaryNextAction ?? "nil")
            koharuPipelineResolverTrace: firstBlockedNodeID=\(koharuResolverTrace?.firstBlockedNodeID ?? "nil") primaryBottleneck=\(koharuResolverTrace?.primaryBottleneck ?? "nil") recommendedExecutionItemID=\(koharuResolverTrace?.recommendedExecutionItemID ?? "nil") recommendedNextAction=\(koharuResolverTrace?.recommendedNextAction ?? "nil") requiresExternalArtifact=\(koharuResolverTrace.map { String($0.requiresExternalArtifact) } ?? "nil") stoplistedLocalTuning=\(koharuResolverTrace.map { String($0.stoplistedLocalTuning) } ?? "nil")
            koharuWorkOrderRoute: primaryWorkOrder=\(koharuWorkOrderRoute?.primaryWorkOrderID ?? "nil") secondary=\(koharuWorkOrderRoute?.secondaryWorkOrderIDs.joined(separator: ",") ?? "nil") bottleneck=\(koharuWorkOrderRoute?.primaryBottleneck ?? "nil") budget=\(koharuWorkOrderRoute?.budgetClass ?? "nil") external=\(koharuWorkOrderRoute.map { String($0.requiresExternalArtifact) } ?? "nil") stoplisted=\(koharuWorkOrderRoute.map { String($0.stoplistedLocalTuning) } ?? "nil") modelFloor=\(koharuWorkOrderRoute.map { String($0.modelFloorLimited) } ?? "nil") renderLocked=\(koharuWorkOrderRoute.map { String($0.renderLocked) } ?? "nil") nextAction=\(koharuWorkOrderRoute?.recommendedNextAction ?? "nil")
            koharuExternalArtifactRequest: primary=\(koharuExternalArtifactRequest?.primaryWorkOrderID ?? "nil") needsTextBoxes=\(koharuExternalArtifactRequest.map { String($0.needsTextBoxes) } ?? "nil") needsBubbleMask=\(koharuExternalArtifactRequest.map { String($0.needsBubbleMask) } ?? "nil") needsSegmentMask=\(koharuExternalArtifactRequest.map { String($0.needsSegmentMask) } ?? "nil") nextAction=\(koharuExternalArtifactRequest?.nextAction ?? "nil") stoplistedLocalTuning=\(koharuExternalArtifactRequest.map { String($0.stoplistedLocalTuning) } ?? "nil") readiness=\(koharuExternalArtifactRequest?.externalArtifactReadinessVerdict ?? "nil") shadowOCR=\(koharuExternalArtifactRequest?.externalTextBoxShadowOCRStatus ?? "nil") missing=\(koharuExternalArtifactRequest?.missingRealArtifactReasons.joined(separator: " | ") ?? "nil")
            koharuNativeReplayRoute: primary=\(koharuNativeReplayRoute?.primaryReplayCandidateID ?? "nil") secondary=\(koharuNativeReplayRoute?.secondaryReplayCandidateIDs.joined(separator: ",") ?? "nil") stage=\(koharuNativeReplayRoute?.primaryKoharuStage ?? "nil") bottleneck=\(koharuNativeReplayRoute?.primaryBottleneck ?? "nil") nextAction=\(koharuNativeReplayRoute?.nextAction ?? "nil") requiresExternalArtifact=\(koharuNativeReplayRoute.map { String($0.requiresExternalArtifact) } ?? "nil") modelFloorLimited=\(koharuNativeReplayRoute.map { String($0.modelFloorLimited) } ?? "nil") renderLocked=\(koharuNativeReplayRoute.map { String($0.renderLocked) } ?? "nil") stoplistedLocalTuning=\(koharuNativeReplayRoute.map { String($0.stoplistedLocalTuning) } ?? "nil")
            koharuBubbleIndexBlockLedger: block=\(koharuBubbleIndexBlockLedger.map { String($0.blockIndex) } ?? "nil") bubbleID=\(koharuBubbleIndexBlockLedger?.bubbleID.map(String.init) ?? "nil") shadowBubbleID=\(koharuBubbleIndexBlockLedger?.shadowBubbleID.map(String.init) ?? "nil") assignment=\(koharuBubbleIndexBlockLedger?.assignmentVerdict ?? "nil") safeArea=\(koharuBubbleIndexBlockLedger?.safeAreaVerdict ?? "nil") sibling=\(koharuBubbleIndexBlockLedger?.siblingPartitionVerdict ?? "nil") render=\(koharuBubbleIndexBlockLedger?.renderLockVerdict ?? "nil") next=\(koharuBubbleIndexBlockLedger?.nextAction ?? "nil")
            translationFloorNoisyBlock: modelFloorLimited=\(translationFloorNoisy.map { String($0.modelFloorLimited) } ?? "nil") ocrInputSuspect=\(translationFloorNoisy.map { String($0.ocrInputSuspect) } ?? "nil") languageQualityFailure=\(translationFloorNoisy.map { String($0.translationLanguageQualityFailure) } ?? "nil") routingOutcome=\(translationFloorNoisy?.routingComparisonOutcome ?? "nil") nextAction=\(translationFloorNoisy?.recommendedNextAction ?? "nil")
            renderLock: status=\(renderLock?.renderStatus ?? "nil") failureOverlayRequired=\(renderLock.map { String($0.failureOverlayRequired) } ?? "nil") failureOverlayLocked=\(renderLock.map { String($0.failureOverlayLocked) } ?? "nil") safeLayoutSource=\(renderLock?.safeLayoutSource ?? "nil") maskOverflowPixels=\(renderLock.map { String($0.renderMaskOverflowPixelCount) } ?? "nil") truncated=\(renderLock.map { String($0.renderTextTruncated) } ?? "nil") nextAction=\(renderLock?.recommendedNextAction ?? "nil")
            cropFailureAttribution: \(cropAttribution)
            safeLayoutRect: [\(safeLayout)]
            safeLayoutSource: \(block.safeLayoutSource ?? "nil")
            maskDominantBubbleID: \(maskDominantID)
            maskDominantCoverage: \(maskDominantCoverage)
            maskSafeRect: [\(maskSafeRect)]
            maskBubbleIDConsistent: \(mask.map { String($0.bubbleIDConsistent) } ?? "nil")
            bubbleAssignmentCorrection: decision=\(correction?.decision ?? "nil") recommended=\(correction.map { String($0.correctionRecommended) } ?? "nil") correctedBubbleID=\(correction?.correctedBubbleID.map(String.init) ?? "nil") appliedToCropClamp=\(correction.map { String($0.correctionAppliedToCropClamp) } ?? "nil") rejections=\(correctionReasons) risks=\(correctionRisks)
            bubbleSplitCandidate: id=\(split.map { String($0.id) } ?? "nil") parentBubbleID=\(split.map { String($0.parentBubbleID) } ?? "nil") bbox=[\(splitBBox)] clampEligible=\(split.map { String($0.clampEligible) } ?? "nil") rejections=\(splitReasons)
            renderMaskCollision: checked=\(block.renderMaskCollisionChecked) resolved=\(block.renderMaskCollisionResolved) overflowPixels=\(block.renderMaskOverflowPixelCount)
            renderCollision: checked=\(block.renderCollisionChecked) initialOverflow=\(block.renderCollisionInitialOverflow) resolved=\(block.renderCollisionResolved) fontSize=\(block.renderFontSize?.formatted(.number.precision(.fractionLength(1))) ?? "nil") minFont=\(block.renderMinFontSizeReached) truncated=\(block.renderTextTruncated) nonTransparentBounds=[\(renderBounds)]
            glyphMask: pixels=\(block.glyphMaskPixelCount) rect=[\(glyphRect)] fillRects=\(block.glyphMaskFillRects.count)
            backgroundFill: applied=\(block.backgroundFillApplied) stdDev=\(backgroundStdDev)
            finalForTranslation: \(final)
            deterministicCorrection: \(deterministic)
            bestGroundTruth: \(truth)
            translationCandidate: \(translation)
            rawOutput: \(rawOutput)
            deterministicCorrectionTranslationPassed: \(block.deterministicCorrectionTranslationPassed.map(String.init) ?? "nil")
            deterministicCorrectionTranslationCandidate: \(deterministicTranslation)
            deterministicCorrectionTranslationRawOutput: \(deterministicTranslationRaw)
            deterministicCorrectionTranslationFailureDetail: \(block.deterministicCorrectionTranslationFailureDetail ?? "nil")
            failureCategory: \(block.failureCategory)
            failureReasons: \(block.failureReasons.joined(separator: " | "))
            translationFailureDetail: \(block.translationFailureDetail ?? "nil")
            qualityNotes: \(block.qualityNotes.joined(separator: " | "))
            decisionTrace: \(block.translationDecisionTrace.joined(separator: " | "))
            """
        }
        .joined(separator: "\n\n")
        let translationFloorCleanCaseSummary = (translationModelFloorComparisonReport?.cleanCases ?? [])
            .map { cleanCase in
                let baseline = cleanCase.baselineCandidate.replacing("\n", with: " / ")
                let variant = cleanCase.variantCandidate.replacing("\n", with: " / ")
                return "translationFloorCleanCase: gtIndex=\(cleanCase.groundTruthIndex) baselinePassed=\(cleanCase.baselinePassed) variantPassed=\(cleanCase.variantPassed) outcome=\(cleanCase.promptVariantOutcome) baselineCandidate=\(baseline) variantCandidate=\(variant)"
            }
            .joined(separator: "\n")
        let translationFloorPromptOutcomes = translationModelFloorComparisonReport?.promptVariantOutcomeBreakdown
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ",") ?? "nil"
        let renderOutputMissing = (koharuRenderRegressionLockReport?.outputFileChecks ?? [])
            .filter { $0.requiredInCIFast && !$0.nonEmpty }
            .map(\.fileName)
            .joined(separator: ",")
        let renderWorkItem = koharuArtifactConvergenceReport?.workItemLedger.first {
            $0.workItemID == "WI-render-regression-lock"
        }
        let resolverQueueSummary = (koharuPipelineResolverReport?.executionQueue ?? [])
            .map { "\($0.executionItemID):status=\($0.status):next=\($0.recommendedNextAction)" }
            .joined(separator: " | ")
        let workOrderQueueSummary = (koharuWorkOrderRouterReport?.workOrders ?? [])
            .map { "\($0.workOrderID):status=\($0.status):priority=\($0.priority):next=\($0.recommendedNextAction)" }
            .joined(separator: " | ")
        let requestRequiredFilesSummary = (koharuExternalArtifactRequestPacketReport?.requiredFiles ?? [])
            .map { "\($0.artifactKind):present=\($0.present):status=\($0.contractStatus):path=\($0.path)" }
            .joined(separator: " | ")
        let requestArtifactRequirementsSummary = (koharuExternalArtifactRequestPacketReport?.artifactRequirements ?? [])
            .map { "\($0.artifactKind):status=\($0.status):blocks=[\($0.targetBlocks.map(String.init).joined(separator: ","))]:next=\($0.nextAction)" }
            .joined(separator: " | ")
        let nativeReplayCandidateQueueSummary = (koharuNativeAlgorithmReplayMatrixReport?.candidates ?? [])
            .map { "\($0.candidateID):status=\($0.status):budget=\($0.budgetClass):next=\($0.nextAction)" }
            .joined(separator: " | ")
        let nativeReplayStageSummary = (koharuNativeAlgorithmReplayMatrixReport?.stages ?? [])
            .map { "\($0.stageName):status=\($0.status):metric=\($0.primaryMetric):next=\($0.nextAction)" }
            .joined(separator: " | ")
        let bubbleIndexBubbleLedgerSummary = (koharuBubbleIndexShadowLedgerReport?.bubbleLedgers ?? [])
            .map { "bubbleIndexBubbleLedger: bubbleID=\($0.bubbleID) blocks=[\($0.blockIndexes.map(String.init).joined(separator: ","))] verdict=\($0.layoutVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let bubbleIndexSiblingLedgerSummary = (koharuBubbleIndexShadowLedgerReport?.siblingLedgers ?? [])
            .map { "bubbleIndexSiblingLedger: group=\($0.siblingGroupID) bubbleID=\($0.bubbleID) blocks=[\($0.blockIndexes.map(String.init).joined(separator: ","))] verdict=\($0.partitionVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let externalSummary = """
        koharuNativeAlgorithmReplayMatrixReport: enabled=\(koharuNativeAlgorithmReplayMatrixReport.map { String($0.enabled) } ?? "nil") stages=\(koharuNativeAlgorithmReplayMatrixReport.map { String($0.stageCount) } ?? "nil") candidates=\(koharuNativeAlgorithmReplayMatrixReport.map { String($0.candidateCount) } ?? "nil") blockRoutes=\(koharuNativeAlgorithmReplayMatrixReport.map { String($0.blockRouteCount) } ?? "nil") gates=\(koharuNativeAlgorithmReplayMatrixReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuNativeAlgorithmReplayMatrixReport?.matrixVerdict ?? "nil")
        nativeReplayStageStatus=\(koharuNativeAlgorithmReplayMatrixReport?.stageStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeReplayCandidateStatus=\(koharuNativeAlgorithmReplayMatrixReport?.candidateStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeReplayBudget=\(koharuNativeAlgorithmReplayMatrixReport?.budgetClassBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        candidateQueue: \(nativeReplayCandidateQueueSummary.isEmpty ? "nil" : nativeReplayCandidateQueueSummary)
        stageMatrix: \(nativeReplayStageSummary.isEmpty ? "nil" : nativeReplayStageSummary)
        koharuBubbleIndexShadowLedgerReport: enabled=\(koharuBubbleIndexShadowLedgerReport.map { String($0.enabled) } ?? "nil") blocks=\(koharuBubbleIndexShadowLedgerReport.map { String($0.blockLedgerCount) } ?? "nil") bubbles=\(koharuBubbleIndexShadowLedgerReport.map { String($0.bubbleLedgerCount) } ?? "nil") siblings=\(koharuBubbleIndexShadowLedgerReport.map { String($0.siblingLedgerCount) } ?? "nil") gates=\(koharuBubbleIndexShadowLedgerReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuBubbleIndexShadowLedgerReport?.ledgerVerdict ?? "nil")
        bubbleIndexAssignment=\(koharuBubbleIndexShadowLedgerReport?.assignmentVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        bubbleIndexSafeArea=\(koharuBubbleIndexShadowLedgerReport?.safeAreaVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        bubbleIndexSiblingPartition=\(koharuBubbleIndexShadowLedgerReport?.siblingPartitionVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        bubbleIndexNextAction=\(koharuBubbleIndexShadowLedgerReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(bubbleIndexBubbleLedgerSummary.isEmpty ? "bubbleIndexBubbleLedger: nil" : bubbleIndexBubbleLedgerSummary)
        \(bubbleIndexSiblingLedgerSummary.isEmpty ? "bubbleIndexSiblingLedger: nil" : bubbleIndexSiblingLedgerSummary)
        koharuWorkOrderRouterReport: enabled=\(koharuWorkOrderRouterReport.map { String($0.enabled) } ?? "nil") workOrders=\(koharuWorkOrderRouterReport.map { String($0.workOrderCount) } ?? "nil") blockRoutes=\(koharuWorkOrderRouterReport.map { String($0.blockRouteCount) } ?? "nil") gates=\(koharuWorkOrderRouterReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuWorkOrderRouterReport?.routerVerdict ?? "nil")
        workOrderStatus=\(koharuWorkOrderRouterReport?.workOrderStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        workOrderPriority=\(koharuWorkOrderRouterReport?.workOrderPriorityBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        workOrderBudget=\(koharuWorkOrderRouterReport?.budgetClassBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        workOrderQueue: \(workOrderQueueSummary.isEmpty ? "nil" : workOrderQueueSummary)
        koharuExternalArtifactRequestPacketReport: enabled=\(koharuExternalArtifactRequestPacketReport.map { String($0.enabled) } ?? "nil") requiredFiles=\(koharuExternalArtifactRequestPacketReport.map { String($0.requiredFileCount) } ?? "nil") requirements=\(koharuExternalArtifactRequestPacketReport.map { String($0.artifactRequirementCount) } ?? "nil") blockRequests=\(koharuExternalArtifactRequestPacketReport.map { String($0.blockRequestCount) } ?? "nil") gates=\(koharuExternalArtifactRequestPacketReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuExternalArtifactRequestPacketReport?.requestPacketVerdict ?? "nil")
        requestPacketReadiness=\(koharuExternalArtifactRequestPacketReport?.readinessVerdict ?? "nil") activeDirectory=\(koharuExternalArtifactRequestPacketReport.map { String($0.activeArtifactsDirectory) } ?? "nil") contractExampleOnly=\(koharuExternalArtifactRequestPacketReport.map { String($0.contractExampleOnly) } ?? "nil") shadowOCRAllowed=\(koharuExternalArtifactRequestPacketReport.map { String($0.externalTextBoxesShadowOCRAllowed) } ?? "nil")
        requiredFiles: \(requestRequiredFilesSummary.isEmpty ? "nil" : requestRequiredFilesSummary)
        artifactRequirements: \(requestArtifactRequirementsSummary.isEmpty ? "nil" : requestArtifactRequirementsSummary)
        requestPacketBlockedByMissingRealArtifact=\(koharuExternalArtifactRequestPacketReport?.blockedByMissingRealArtifactBlocks.map(String.init).joined(separator: ",") ?? "nil") readyForExternalShadowOCR=\(koharuExternalArtifactRequestPacketReport?.readyForExternalShadowOCRBlocks.map(String.init).joined(separator: ",") ?? "nil") forbiddenActiveSources=\(koharuExternalArtifactRequestPacketReport?.forbiddenActiveSources.joined(separator: ",") ?? "nil")
        koharuPipelineResolverReport: enabled=\(koharuPipelineResolverReport.map { String($0.enabled) } ?? "nil") nodes=\(koharuPipelineResolverReport.map { String($0.nodeCount) } ?? "nil") edges=\(koharuPipelineResolverReport.map { String($0.edgeCount) } ?? "nil") blockTraces=\(koharuPipelineResolverReport.map { String($0.blockTraceCount) } ?? "nil") executionQueue=\(koharuPipelineResolverReport.map { String($0.executionQueueCount) } ?? "nil") opPreviews=\(koharuPipelineResolverReport.map { String($0.opPreviewCount) } ?? "nil") gates=\(koharuPipelineResolverReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuPipelineResolverReport?.resolverVerdict ?? "nil")
        resolverNodeStatus=\(koharuPipelineResolverReport?.nodeStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        resolverArtifactAvailability=\(koharuPipelineResolverReport?.artifactAvailabilityBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        resolverFirstBlockedNode=\(koharuPipelineResolverReport?.firstBlockedNodeBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        resolverExecutionQueue: \(resolverQueueSummary.isEmpty ? "nil" : resolverQueueSummary)
        resolverBlockedByMissingRealArtifact=\(koharuPipelineResolverReport?.blockedByMissingRealArtifactBlocks.map(String.init).joined(separator: ",") ?? "nil") stoplistedLocalTuning=\(koharuPipelineResolverReport?.stoplistedLocalTuningBlocks.map(String.init).joined(separator: ",") ?? "nil") modelFloorLimited=\(koharuPipelineResolverReport?.modelFloorLimitedBlocks.map(String.init).joined(separator: ",") ?? "nil") renderLocked=\(koharuPipelineResolverReport?.renderLockedBlocks.map(String.init).joined(separator: ",") ?? "nil")
        koharuRenderRegressionLockReport: enabled=\(koharuRenderRegressionLockReport.map { String($0.enabled) } ?? "nil") blocks=\(koharuRenderRegressionLockReport.map { String($0.evaluatedBlockCount) } ?? "nil") verdict=\(koharuRenderRegressionLockReport?.renderLockVerdict ?? "nil") renderedSpritesStage=\(koharuRenderRegressionLockReport?.renderedSpritesStageStatus ?? "nil") finalRenderStage=\(koharuRenderRegressionLockReport?.finalRenderStageStatus ?? "nil")
        renderIssues: overflow=\(koharuRenderRegressionLockReport?.renderCollisionUnresolvedBlocks.map(String.init).joined(separator: ",") ?? "nil") truncated=\(koharuRenderRegressionLockReport?.renderTextTruncatedBlocks.map(String.init).joined(separator: ",") ?? "nil") maskOverflow=\(koharuRenderRegressionLockReport?.renderMaskOverflowBlocks.map(String.init).joined(separator: ",") ?? "nil") missingSafeLayout=\(koharuRenderRegressionLockReport?.blockLocks.filter { $0.safeLayoutRect == nil }.map { String($0.blockIndex) }.joined(separator: ",") ?? "nil")
        outputFiles: corePresent=\(koharuRenderRegressionLockReport.map { String($0.coreOutputFilesPresent) } ?? "nil") coreNonEmpty=\(koharuRenderRegressionLockReport.map { String($0.coreOutputFilesNonEmpty) } ?? "nil") missing=\(renderOutputMissing.isEmpty ? "none" : renderOutputMissing)
        renderRegressionLockWorkItem: status=\(renderWorkItem?.status ?? "nil") closedByVersion=\(renderWorkItem?.closedByVersion ?? "nil") blockers=\(renderWorkItem?.remainingBlockers.joined(separator: ",") ?? "nil")
        translationModelFloorComparisonReport: enabled=\(translationModelFloorComparisonReport.map { String($0.enabled) } ?? "nil") cleanCases=\(translationModelFloorComparisonReport.map { String($0.evaluatedCleanCaseCount) } ?? "nil") noisyBlocks=\(translationModelFloorComparisonReport.map { String($0.evaluatedNoisyBlockCount) } ?? "nil") baselinePassRate=\(translationModelFloorComparisonReport.map { $0.baselinePassRate.formatted(.number.precision(.fractionLength(4))) } ?? "nil") variantPassRate=\(translationModelFloorComparisonReport.map { $0.variantPassRate.formatted(.number.precision(.fractionLength(4))) } ?? "nil") delta=\(translationModelFloorComparisonReport.map { $0.passRateDelta.formatted(.number.precision(.fractionLength(4))) } ?? "nil") floorVerdict=\(translationModelFloorComparisonReport?.floorVerdict ?? "nil")
        promptVariantOutcome=\(translationFloorPromptOutcomes)
        modelFloorBlocks=\(translationModelFloorComparisonReport?.noisyModelFloorBlocks.map(String.init).joined(separator: ",") ?? "nil") ocrSuspectBlocks=\(translationModelFloorComparisonReport?.noisyOCRSuspectBlocks.map(String.init).joined(separator: ",") ?? "nil") languageQualityBlocks=\(translationModelFloorComparisonReport?.noisyTranslationLanguageQualityBlocks.map(String.init).joined(separator: ",") ?? "nil")
        batchFormatFailure=\(translationModelFloorComparisonReport.map { String($0.batchFormatFailure) } ?? "nil")
        \(translationFloorCleanCaseSummary)
        externalArtifactReadiness: activeDirectory=\(externalArtifactReadinessReport.map { String($0.activeArtifactsDirectory) } ?? "nil") contractExampleOnly=\(externalArtifactReadinessReport.map { String($0.contractExampleOnly) } ?? "nil") shadowOCRAllowed=\(externalArtifactReadinessReport.map { String($0.externalTextBoxesShadowOCRAllowed) } ?? "nil") manifestFound=\(externalArtifactReadinessReport.map { String($0.manifestFound) } ?? "nil") textBoxesFound=\(externalArtifactReadinessReport.map { String($0.textBoxesFound) } ?? "nil") bubbleMaskFound=\(externalArtifactReadinessReport.map { String($0.bubbleMaskFound) } ?? "nil") segmentMaskFound=\(externalArtifactReadinessReport.map { String($0.segmentMaskFound) } ?? "nil") verdict=\(externalArtifactReadinessReport?.readinessVerdict ?? "nil") nextAction=\(externalArtifactReadinessReport?.nextAction ?? "nil") missing=\(externalArtifactReadinessReport?.missingArtifacts.joined(separator: ",") ?? "nil")
        externalTextBoxShadowOCR: enabled=\(externalTextBoxShadowOCRReport.map { String($0.enabled) } ?? "nil") executed=\(externalTextBoxShadowOCRReport.map { String($0.executed) } ?? "nil") gateVerdict=\(externalTextBoxShadowOCRReport?.gateVerdict ?? "nil") candidates=\(externalTextBoxShadowOCRReport.map { String($0.candidateCount) } ?? "nil") ocrExecuted=\(externalTextBoxShadowOCRReport.map { String($0.ocrExecutedCount) } ?? "nil") betterThanControl=\(externalTextBoxShadowOCRReport.map { String($0.betterThanControlCount) } ?? "nil") skipped=\(externalTextBoxShadowOCRReport?.skippedBlocks.map(String.init).joined(separator: ",") ?? "nil")
        internalStructureBottleneckReport: evaluated=\(internalStructureBottleneckReport.map { String($0.evaluatedBlockCount) } ?? "nil") primary=\(internalStructureBottleneckReport?.primaryBottleneckBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") recommended=\(internalStructureBottleneckReport?.recommendedActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") duplicateOrFragment=\(internalStructureBottleneckReport?.duplicateOrFragmentBlocks.map(String.init).joined(separator: ",") ?? "nil")
        routingDrivenTranslationComparisonReport: enabled=\(routingDrivenTranslationComparisonReport.map { String($0.enabled) } ?? "nil") evaluated=\(routingDrivenTranslationComparisonReport.map { String($0.evaluatedCaseCount) } ?? "nil") targets=\(routingDrivenTranslationComparisonReport?.targetBlockIndexes.map(String.init).joined(separator: ",") ?? "nil") controlPassed=\(routingDrivenTranslationComparisonReport.map { String($0.controlPassedCount) } ?? "nil") variantPassed=\(routingDrivenTranslationComparisonReport.map { String($0.variantPassedCount) } ?? "nil") improvements=\(routingDrivenTranslationComparisonReport?.improvementBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        ocrCharacterDamageAuditReport: enabled=\(ocrCharacterDamageAuditReport.map { String($0.enabled) } ?? "nil") evaluated=\(ocrCharacterDamageAuditReport.map { String($0.evaluatedBlockCount) } ?? "nil") targets=\(ocrCharacterDamageAuditReport?.targetBlockIndexes.map(String.init).joined(separator: ",") ?? "nil") lineBreakRisk=\(ocrCharacterDamageAuditReport?.lineBreakRiskBlocks.map(String.init).joined(separator: ",") ?? "nil") cropBlocked=\(ocrCharacterDamageAuditReport?.cropBlockedBlocks.map(String.init).joined(separator: ",") ?? "nil") actions=\(ocrCharacterDamageAuditReport?.recommendedActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        readingOrderStructureAuditReport: enabled=\(readingOrderStructureAuditReport.map { String($0.enabled) } ?? "nil") evaluated=\(readingOrderStructureAuditReport.map { String($0.evaluatedBlockCount) } ?? "nil") orderChanged=\(readingOrderStructureAuditReport?.orderChangedBlocks.map(String.init).joined(separator: ",") ?? "nil") lowConfidenceOrderBlocks=\(readingOrderStructureAuditReport?.lowConfidenceOrderBlocks.map(String.init).joined(separator: ",") ?? "nil") multiBlockBubbleGroups=\(readingOrderStructureAuditReport?.multiBlockBubbleGroups.map { "\($0.key):[\($0.value.map(String.init).joined(separator: ","))]" }.sorted().joined(separator: " | ") ?? "nil") maskConflictBlocks=\(readingOrderStructureAuditReport?.maskConflictBlocks.map(String.init).joined(separator: ",") ?? "nil") splitRiskBlocks=\(readingOrderStructureAuditReport?.splitRiskBlocks.map(String.init).joined(separator: ",") ?? "nil") duplicateOrFragmentRiskBlocks=\(readingOrderStructureAuditReport?.duplicateOrFragmentRiskBlocks.map(String.init).joined(separator: ",") ?? "nil") actions=\(readingOrderStructureAuditReport?.recommendedStructureActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        structureActionCandidateReport: enabled=\(structureActionCandidateReport.map { String($0.enabled) } ?? "nil") evaluated=\(structureActionCandidateReport.map { String($0.evaluatedBlockCount) } ?? "nil") candidates=\(structureActionCandidateReport.map { String($0.candidateCount) } ?? "nil") executed=\(structureActionCandidateReport.map { String($0.executedCandidateCount) } ?? "nil") skipped=\(structureActionCandidateReport.map { String($0.skippedCandidateCount) } ?? "nil") types=\(structureActionCandidateReport?.candidateTypeBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") verdicts=\(structureActionCandidateReport?.promotionVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") nextSteps=\(structureActionCandidateReport?.recommendedNextStepBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") wouldImprove=\(structureActionCandidateReport?.reportOnlyWouldImproveBlocks.map(String.init).joined(separator: ",") ?? "nil") blocked=\(structureActionCandidateReport?.blockedBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealArtifact=\(structureActionCandidateReport?.needsRealArtifactBlocks.map(String.init).joined(separator: ",") ?? "nil")
        koharuArtifactDAGReport: enabled=\(koharuArtifactDAGReport.map { String($0.enabled) } ?? "nil") evaluated=\(koharuArtifactDAGReport.map { String($0.evaluatedBlockCount) } ?? "nil") stages=\(koharuArtifactDAGReport.map { String($0.stageCount) } ?? "nil") edges=\(koharuArtifactDAGReport.map { String($0.edgeCount) } ?? "nil") stageStatus=\(koharuArtifactDAGReport?.stageStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") firstBlocking=\(koharuArtifactDAGReport?.firstBlockingStageBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") downstreamImpact=\(koharuArtifactDAGReport?.downstreamImpactBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") realArtifactGateVerdict=\(koharuArtifactDAGReport?.realArtifactGateVerdict ?? "nil") realArtifactGateNextAction=\(koharuArtifactDAGReport?.realArtifactGateNextAction ?? "nil") needsTextBoxes=\(koharuArtifactDAGReport?.blocksNeedingRealTextBoxes.map(String.init).joined(separator: ",") ?? "nil") needsBubbleMask=\(koharuArtifactDAGReport?.blocksNeedingRealBubbleMask.map(String.init).joined(separator: ",") ?? "nil") needsSegmentMask=\(koharuArtifactDAGReport?.blocksNeedingRealSegmentMask.map(String.init).joined(separator: ",") ?? "nil")
        koharuStageGapReplicationReport: enabled=\(koharuStageGapReplicationReport.map { String($0.enabled) } ?? "nil") stages=\(koharuStageGapReplicationReport.map { String($0.canonicalStageCount) } ?? "nil") gaps=\(koharuStageGapReplicationReport.map { String($0.gapCount) } ?? "nil") workPackages=\(koharuStageGapReplicationReport.map { String($0.workPackageCount) } ?? "nil") readiness=\(koharuStageGapReplicationReport?.replicationReadinessBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") blockedByRealArtifact=\(koharuStageGapReplicationReport?.blockedByRealArtifactStages.joined(separator: ",") ?? "nil") stopTuning=\(koharuStageGapReplicationReport?.stopTuningStages.joined(separator: ",") ?? "nil") mustWaitForExternalArtifact=\(koharuStageGapReplicationReport?.mustWaitForExternalArtifactStages.joined(separator: ",") ?? "nil")
        koharuNativeReplicationScoreboardReport: enabled=\(koharuNativeReplicationScoreboardReport.map { String($0.enabled) } ?? "nil") stages=\(koharuNativeReplicationScoreboardReport.map { String($0.stageScorecardCount) } ?? "nil") gates=\(koharuNativeReplicationScoreboardReport.map { String($0.gateCount) } ?? "nil") workItems=\(koharuNativeReplicationScoreboardReport.map { String($0.workItemCount) } ?? "nil") stageStatus=\(koharuNativeReplicationScoreboardReport?.stageStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") gateStatus=\(koharuNativeReplicationScoreboardReport?.gateStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") stopLocalTuningBlocks=\(koharuNativeReplicationScoreboardReport?.stopLocalTuningBlocks.map(String.init).joined(separator: ",") ?? "nil") externalRequired=\(koharuNativeReplicationScoreboardReport.map { String($0.externalArtifactsRequiredForThisReport) } ?? "nil")
        nativeTextBoxProxyLedgerReport: enabled=\(nativeTextBoxProxyLedgerReport.map { String($0.enabled) } ?? "nil") evaluated=\(nativeTextBoxProxyLedgerReport.map { String($0.evaluatedBlockCount) } ?? "nil") qualityStatus=\(nativeTextBoxProxyLedgerReport?.qualityStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") freezeReasons=\(nativeTextBoxProxyLedgerReport?.freezeReasonBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") stoplistBlocks=\(nativeTextBoxProxyLedgerReport?.stoplistBlocks.map(String.init).joined(separator: ",") ?? "nil") shadowOnlyEligibleBlocks=\(nativeTextBoxProxyLedgerReport?.shadowOnlyEligibleBlocks.map(String.init).joined(separator: ",") ?? "nil") gates=\(nativeTextBoxProxyLedgerReport.map { String($0.gateCount) } ?? "nil") candidates=\(nativeTextBoxProxyLedgerReport.map { String($0.candidateLedgerCount) } ?? "nil")
        bubbleMaskAssignmentSplitScoreboardReport: enabled=\(bubbleMaskAssignmentSplitScoreboardReport.map { String($0.enabled) } ?? "nil") evaluatedBlocks=\(bubbleMaskAssignmentSplitScoreboardReport.map { String($0.evaluatedBlockCount) } ?? "nil") evaluatedBubbles=\(bubbleMaskAssignmentSplitScoreboardReport.map { String($0.evaluatedBubbleCount) } ?? "nil") assignmentStatus=\(bubbleMaskAssignmentSplitScoreboardReport?.assignmentStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") splitRisk=\(bubbleMaskAssignmentSplitScoreboardReport?.splitRiskBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") siblingLayout=\(bubbleMaskAssignmentSplitScoreboardReport?.siblingLayoutStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") renderMask=\(bubbleMaskAssignmentSplitScoreboardReport?.renderMaskStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") conflictBlocks=\(bubbleMaskAssignmentSplitScoreboardReport?.conflictBlocks.map(String.init).joined(separator: ",") ?? "nil") splitRiskBlocks=\(bubbleMaskAssignmentSplitScoreboardReport?.splitRiskBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealBubbleMaskBlocks=\(bubbleMaskAssignmentSplitScoreboardReport?.needsRealBubbleMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") gates=\(bubbleMaskAssignmentSplitScoreboardReport.map { String($0.gateCount) } ?? "nil")
        segmentMaskProxyCoverageScoreboardReport: enabled=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.enabled) } ?? "nil") evaluated=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.evaluatedBlockCount) } ?? "nil") glyphMaskBlocks=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.glyphMaskBlockCount) } ?? "nil") usableCleanup=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.usableForCleanupBlockCount) } ?? "nil") usableCropEvidence=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.usableForCropEvidenceBlockCount) } ?? "nil") weak=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.weakSegmentBlockCount) } ?? "nil") coverageStatus=\(segmentMaskProxyCoverageScoreboardReport?.coverageStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") cleanupStatus=\(segmentMaskProxyCoverageScoreboardReport?.cleanupStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") renderMask=\(segmentMaskProxyCoverageScoreboardReport?.renderMaskStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") backgroundFill=\(segmentMaskProxyCoverageScoreboardReport?.backgroundFillStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") needsRealSegmentMask=\(segmentMaskProxyCoverageScoreboardReport?.needsRealSegmentMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") gates=\(segmentMaskProxyCoverageScoreboardReport.map { String($0.gateCount) } ?? "nil")
        koharuArtifactConvergenceReport: enabled=\(koharuArtifactConvergenceReport.map { String($0.enabled) } ?? "nil") stages=\(koharuArtifactConvergenceReport.map { String($0.stageCount) } ?? "nil") blockPaths=\(koharuArtifactConvergenceReport.map { String($0.blockPathCount) } ?? "nil") workItems=\(koharuArtifactConvergenceReport.map { String($0.workItemLedgerCount) } ?? "nil") gates=\(koharuArtifactConvergenceReport.map { String($0.gateCount) } ?? "nil")
        convergenceStatus=\(koharuArtifactConvergenceReport?.convergenceStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        firstBlockingArtifact=\(koharuArtifactConvergenceReport?.firstBlockingArtifactBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        primaryNextAction=\(koharuArtifactConvergenceReport?.primaryNextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        closedWorkItems=\(koharuArtifactConvergenceReport?.closedWorkItems.joined(separator: ",") ?? "nil") openWorkItems=\(koharuArtifactConvergenceReport?.openWorkItems.joined(separator: ",") ?? "nil")

        """
        let cleanContent = (externalSummary + content)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        try cleanContent.write(to: url, atomically: true, encoding: String.Encoding.utf8)
    }

    private static func bubbleResults(
        for bubble: MangaOverlayBubbleCandidate,
        image: CGImage,
        preprocessing: MangaOverlayPreprocessingOptions,
        customWords: [String],
        groundTruth: [MangaGroundTruthEntry]
    ) throws -> [MangaOverlayBubbleResult] {
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let cropRect = expand(bubble.boundingBox, by: 0.08, bounds: bounds).integral
        let cropped = try croppedImage(image, rect: cropRect)
        let processed: CGImage
        let scale: CGFloat
        if preprocessing.enabled, bubble.source == "whiteComponent" {
            processed = try preprocessedImage(cropped, options: preprocessing)
            scale = 1
        } else if bubble.source == "ocrSeed" {
            processed = try scaledImage(cropped, scale: ocrScale)
            scale = ocrScale
        } else {
            processed = cropped
            scale = 1
        }
        let candidates = try recognizeTextCandidates(
            in: processed,
            angle: 0,
            scaledContentSize: CGSize(width: CGFloat(processed.width), height: CGFloat(processed.height)),
            contentOrigin: .zero,
            scale: 1,
            customWords: customWords
        )

        let localBlocks: [MangaOverlayOCRBlock]
        if bubble.source == "ocrSeed" {
            localBlocks = mergeCandidatesIntoBlocks(
                candidates,
                imageSize: CGSize(width: CGFloat(processed.width), height: CGFloat(processed.height))
            ).blocks
        } else {
            let text = mergeText(from: orderedCandidates(candidates))
            let rect = candidates.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
            localBlocks = text.isEmpty ? [] : [
                MangaOverlayOCRBlock(
                    text: text,
                    confidence: nil,
                    boundingBox: rect.isNull ? CGRect(origin: .zero, size: CGSize(width: processed.width, height: processed.height)) : rect,
                    rotationAngle: 0,
                    bubbleID: bubble.index,
                    bubbleAssignmentMethod: "bubbleCrop",
                    bubbleBoundingBox: bubble.boundingBox,
                    source: "bubbleFirst",
                    crossBubbleMergeRejected: false,
                    sliceIndex: nil,
                    sliceOverlapDeduped: false
                )
            ]
        }

        return localBlocks.map { block in
            let globalRect = clamp(
                CGRect(
                    x: cropRect.minX + block.boundingBox.minX / scale,
                    y: cropRect.minY + block.boundingBox.minY / scale,
                    width: block.boundingBox.width / scale,
                    height: block.boundingBox.height / scale
                ).standardized,
                to: bounds
            )
            let match = bestGroundTruthMatch(text: block.text, groundTruth: groundTruth)
            return MangaOverlayBubbleResult(
                index: bubble.index,
                bbox: [globalRect.minX, globalRect.minY, globalRect.width, globalRect.height].map(Double.init),
                bubbleID: bubble.index,
                source: "\(bubble.source):split",
                text: block.text,
                bestGroundTruthIndex: match.index,
                bestGroundTruthType: match.entry?.type,
                groundTruthMatch: match.matchState,
                bestSimilarity: match.similarity,
                legacySimilarity: match.legacySimilarity,
                wordOrderPreserved: match.wordOrderPreserved
            )
        }
    }

    private static func shouldKeepBubbleResult(_ result: MangaOverlayBubbleResult) -> Bool {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let normalized = normalizedOCRText(text)
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let latinLetters = normalized.unicodeScalars.count { scalar in
            (0x41...0x5A).contains(Int(scalar.value)) || (0x61...0x7A).contains(Int(scalar.value))
        }
        guard normalized.count >= 8 || (normalized.count >= 5 && words.count >= 2) else { return false }
        let rect = CGRect(
            x: result.bbox.indices.contains(0) ? result.bbox[0] : 0,
            y: result.bbox.indices.contains(1) ? result.bbox[1] : 0,
            width: result.bbox.indices.contains(2) ? result.bbox[2] : 0,
            height: result.bbox.indices.contains(3) ? result.bbox[3] : 0
        )
        if latinLetters == 0 {
            return false
        }
        if words.count < 2, (normalized.count < 18 || rect.width * rect.height < 1500) {
            return false
        }
        return true
    }

    private static func recognizeTextCandidates(
        in image: CGImage,
        angle: Int,
        scaledContentSize: CGSize,
        contentOrigin: CGPoint,
        scale: CGFloat,
        customWords: [String],
        source: String = "wholePageOCR",
        sliceIndex: Int? = nil
    ) throws -> [MangaOverlayOCRCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        if !customWords.isEmpty {
            request.customWords = customWords
        }
        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let englishLanguages = ["en-US", "en"].filter { supportedLanguages.contains($0) }
        if !englishLanguages.isEmpty {
            request.recognitionLanguages = englishLanguages
        }
        request.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.isNoise(text) else { return nil }

            let pixelBox = Self.pixelRect(
                from: observation.boundingBox,
                imageSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            )
            let scaledContentBox = Self.mapRectToOriginal(
                pixelBox,
                angle: angle,
                rotatedSize: CGSize(width: CGFloat(image.width), height: CGFloat(image.height)),
                originalSize: scaledContentSize
            )
            let originalBox = CGRect(
                x: contentOrigin.x + scaledContentBox.minX / scale,
                y: contentOrigin.y + scaledContentBox.minY / scale,
                width: scaledContentBox.width / scale,
                height: scaledContentBox.height / scale
            ).standardized

            return MangaOverlayOCRCandidate(
                text: text,
                confidence: candidate.confidence,
                boundingBox: originalBox,
                rotationAngle: angle,
                bubbleID: nil,
                bubbleAssignmentMethod: "unassigned",
                bubbleBoundingBox: nil,
                source: source,
                sliceIndex: sliceIndex,
                sliceOverlapDeduped: false
            )
        }
    }

    private static func makeImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            throw MangaOverlayProbeServiceError.imageDecodeFailed
        }
        return image
    }

    private static func contentCropRect(for image: CGImage, cropping: MangaOverlayProbeCropping) -> CGRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let x = width * cropping.sideInsetRatio
        let y = height * cropping.topRatio
        let bottom = height * cropping.bottomRatio
        return CGRect(
            x: x,
            y: y,
            width: width - x * 2,
            height: max(1, height - y - bottom)
        ).integral
    }

    private static func croppedImage(_ image: CGImage, rect: CGRect) throws -> CGImage {
        guard let cropped = image.cropping(to: rect) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return cropped
    }

    private static func scaledImage(_ image: CGImage, scale: CGFloat) throws -> CGImage {
        guard scale != 1 else { return image }
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let scaled = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return scaled
    }

    private static func verticallyStackedImage(_ image: CGImage, copies: Int) throws -> CGImage {
        let copies = max(1, copies)
        let width = image.width
        let height = image.height * copies
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        for index in 0..<copies {
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: CGFloat(index * image.height),
                    width: CGFloat(width),
                    height: CGFloat(image.height)
                )
            )
        }
        guard let stacked = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return stacked
    }

    private static func formatRatio(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }

    private static func preprocessedImage(_ image: CGImage, options: MangaOverlayPreprocessingOptions) throws -> CGImage {
        var current = image
        if options.cropUpscaleEnabled, options.cropScale > 1 {
            current = try scaledImage(current, scale: CGFloat(options.cropScale))
        }
        if options.grayscaleEnabled || options.contrastBrightnessEnabled || options.adaptiveThresholdEnabled {
            current = try rasterProcessedImage(current, options: options)
        }
        if options.sharpenEnabled {
            current = try sharpenedImage(current)
        }
        return current
    }

    private static func rasterProcessedImage(_ image: CGImage, options: MangaOverlayPreprocessingOptions) throws -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var luminance = [UInt8](repeating: 0, count: width * height)
        var sum = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let gray = (red * 299 + green * 587 + blue * 114) / 1000
                luminance[y * width + x] = UInt8(max(0, min(255, gray)))
                sum += gray
            }
        }
        let mean = max(1, sum / max(1, width * height))

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                var gray = Int(luminance[index])
                if options.contrastBrightnessEnabled {
                    gray = max(0, min(255, Int((Double(gray - mean) * 1.35) + 188)))
                }
                if options.adaptiveThresholdEnabled {
                    let localMean = localAverage(luminance, x: x, y: y, width: width, height: height, radius: 8)
                    gray = gray < localMean - 10 ? 0 : 255
                }
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = UInt8(gray)
                pixels[offset + 1] = UInt8(gray)
                pixels[offset + 2] = UInt8(gray)
                pixels[offset + 3] = 255
            }
        }

        guard let output = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return output
    }

    private static func localAverage(_ luminance: [UInt8], x: Int, y: Int, width: Int, height: Int, radius: Int) -> Int {
        let minX = max(0, x - radius)
        let maxX = min(width - 1, x + radius)
        let minY = max(0, y - radius)
        let maxY = min(height - 1, y + radius)
        let step = max(1, radius / 4)
        var sum = 0
        var count = 0
        for sampleY in stride(from: minY, through: maxY, by: step) {
            for sampleX in stride(from: minX, through: maxX, by: step) {
                sum += Int(luminance[sampleY * width + sampleX])
                count += 1
            }
        }
        return count == 0 ? 255 : sum / count
    }

    private static func sharpenedImage(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var input = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let inputContext = CGContext(
            data: &input,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        inputContext.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var output = input
        guard width > 2, height > 2 else { return image }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                for channel in 0..<3 {
                    let center = Int(input[(y * bytesPerRow) + (x * bytesPerPixel) + channel]) * 5
                    let top = Int(input[((y - 1) * bytesPerRow) + (x * bytesPerPixel) + channel])
                    let bottom = Int(input[((y + 1) * bytesPerRow) + (x * bytesPerPixel) + channel])
                    let left = Int(input[(y * bytesPerRow) + ((x - 1) * bytesPerPixel) + channel])
                    let right = Int(input[(y * bytesPerRow) + ((x + 1) * bytesPerPixel) + channel])
                    output[(y * bytesPerRow) + (x * bytesPerPixel) + channel] = UInt8(max(0, min(255, center - top - bottom - left - right)))
                }
            }
        }

        guard let outputContext = CGContext(
            data: &output,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let rendered = outputContext.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return rendered
    }

    private static func rotatedImage(_ image: CGImage, angle: Int) throws -> CGImage {
        guard angle != 0 else { return image }

        let width = image.width
        let height = image.height
        let outputSize = angle == 180
            ? CGSize(width: CGFloat(width), height: CGFloat(height))
            : CGSize(width: CGFloat(height), height: CGFloat(width))

        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }

        switch angle {
        case 90:
            context.translateBy(x: outputSize.width, y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: outputSize.width, y: outputSize.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: outputSize.height)
            context.rotate(by: -.pi / 2)
        default:
            break
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let rotated = context.makeImage() else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return rotated
    }

    private static func pixelRect(from normalizedBox: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalizedBox.minX * imageSize.width,
            y: (1 - normalizedBox.maxY) * imageSize.height,
            width: normalizedBox.width * imageSize.width,
            height: normalizedBox.height * imageSize.height
        ).standardized
    }

    private static func mapRectToOriginal(
        _ rect: CGRect,
        angle: Int,
        rotatedSize: CGSize,
        originalSize: CGSize
    ) -> CGRect {
        let points = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ].map { point in
            mapPointToOriginal(point, angle: angle, rotatedSize: rotatedSize, originalSize: originalSize)
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return clamp(
            CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            to: CGRect(origin: .zero, size: originalSize)
        )
    }

    private static func mapPointToOriginal(
        _ point: CGPoint,
        angle: Int,
        rotatedSize: CGSize,
        originalSize: CGSize
    ) -> CGPoint {
        switch angle {
        case 90:
            CGPoint(x: originalSize.width - point.y, y: point.x)
        case 180:
            CGPoint(x: originalSize.width - point.x, y: originalSize.height - point.y)
        case 270:
            CGPoint(x: point.y, y: originalSize.height - point.x)
        default:
            point
        }
    }

    private struct MergeCandidatesResult {
        var blocks: [MangaOverlayOCRBlock]
        var crossBubbleMergeRejectedCount: Int
        var rejectedBubbleIDs: Set<Int>
        var rejectedUnassignedMerge: Bool
    }

    private struct BubbleAssignmentScore {
        var bubble: MangaOverlayBubbleCandidate
        var overlap: CGFloat
        var containsCenter: Bool
        var centerContainment: CGFloat
        var score: CGFloat
    }

    private struct SliceDefinition {
        var index: Int
        var rect: CGRect
        var overlapRatio: CGFloat
    }

    private struct SliceRawCandidateResult {
        var enabled: Bool
        var reason: String
        var contentRect: CGRect
        var thresholdAspectRatio: CGFloat
        var overlapRatio: CGFloat
        var slices: [SliceDefinition]
        var rawCandidates: [MangaOverlayOCRCandidate]
        var candidates: [MangaOverlayOCRCandidate]
        var duplicateGroups: [[MangaOverlayOCRCandidate]]
    }

    private static func recognizeRawCandidates(
        in image: CGImage,
        contentRect: CGRect,
        customWords: [String],
        sourceImage: String
    ) throws -> SliceRawCandidateResult {
        let aspectRatio = contentRect.height / max(1, contentRect.width)
        guard aspectRatio > sliceAspectRatioThreshold else {
            let croppedImage = try croppedImage(image, rect: contentRect)
            let scaledImage = try scaledImage(croppedImage, scale: ocrScale)
            let candidates = try [0, 90, 180, 270].flatMap { angle in
                let rotatedImage = try rotatedImage(scaledImage, angle: angle)
                return try recognizeTextCandidates(
                    in: rotatedImage,
                    angle: angle,
                    scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                    contentOrigin: contentRect.origin,
                    scale: ocrScale,
                    customWords: customWords,
                    source: "wholePageOCR",
                    sliceIndex: nil
                )
            }
            return SliceRawCandidateResult(
                enabled: false,
                reason: "\(sourceImage) aspectRatio \(formatRatio(aspectRatio)) <= threshold \(formatRatio(sliceAspectRatioThreshold)); using whole-page OCR",
                contentRect: contentRect,
                thresholdAspectRatio: sliceAspectRatioThreshold,
                overlapRatio: sliceOverlapRatio,
                slices: [],
                rawCandidates: candidates,
                candidates: candidates,
                duplicateGroups: []
            )
        }

        let slices = verticalSlices(for: contentRect)
        let rawCandidates = try slices.flatMap { slice in
            let croppedImage = try croppedImage(image, rect: slice.rect)
            let scaledImage = try scaledImage(croppedImage, scale: ocrScale)
            return try [0, 90, 180, 270].flatMap { angle in
                let rotatedImage = try rotatedImage(scaledImage, angle: angle)
                return try recognizeTextCandidates(
                    in: rotatedImage,
                    angle: angle,
                    scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                    contentOrigin: slice.rect.origin,
                    scale: ocrScale,
                    customWords: customWords,
                    source: "sliceOCR",
                    sliceIndex: slice.index
                )
            }
        }
        let deduped = deduplicateSliceCandidates(rawCandidates)
        return SliceRawCandidateResult(
            enabled: true,
            reason: "\(sourceImage) aspectRatio \(formatRatio(aspectRatio)) > threshold \(formatRatio(sliceAspectRatioThreshold)); using vertical slice OCR",
            contentRect: contentRect,
            thresholdAspectRatio: sliceAspectRatioThreshold,
            overlapRatio: sliceOverlapRatio,
            slices: slices,
            rawCandidates: rawCandidates,
            candidates: deduped.candidates,
            duplicateGroups: deduped.duplicateGroups
        )
    }

    private static func verticalSlices(for contentRect: CGRect) -> [SliceDefinition] {
        let targetHeight = max(contentRect.width * targetSliceAspectRatio, contentRect.height / 3)
        let sliceHeight = min(contentRect.height, max(contentRect.width * 1.25, targetHeight))
        let step = max(1, sliceHeight * (1 - sliceOverlapRatio))
        var slices: [SliceDefinition] = []
        var minY = contentRect.minY
        var index = 0
        while minY < contentRect.maxY {
            let adjustedY = minY
            let rect = CGRect(
                x: contentRect.minX,
                y: adjustedY,
                width: contentRect.width,
                height: min(sliceHeight, contentRect.maxY - adjustedY)
            ).integral
            slices.append(SliceDefinition(index: index, rect: rect, overlapRatio: sliceOverlapRatio))
            index += 1
            if rect.maxY >= contentRect.maxY { break }
            minY += step
        }
        return slices
    }

    private static func deduplicateSliceCandidates(
        _ candidates: [MangaOverlayOCRCandidate]
    ) -> (candidates: [MangaOverlayOCRCandidate], duplicateGroups: [[MangaOverlayOCRCandidate]]) {
        var survivors: [MangaOverlayOCRCandidate] = []
        var duplicateGroups: [[MangaOverlayOCRCandidate]] = []
        for candidate in candidates.sorted(by: isBetterCandidate) {
            guard let index = survivors.firstIndex(where: { isSliceDuplicate(candidate, of: $0) }) else {
                survivors.append(candidate)
                continue
            }
            let existing = survivors[index]
            let best = isBetterCandidate(candidate, existing) ? candidate : existing
            var marked = best
            marked.sliceOverlapDeduped = true
            survivors[index] = marked
            duplicateGroups.append([existing, candidate])
        }
        return (survivors, duplicateGroups)
    }

    private static func isSliceDuplicate(_ candidate: MangaOverlayOCRCandidate, of existing: MangaOverlayOCRCandidate) -> Bool {
        guard candidate.sliceIndex != existing.sliceIndex else { return false }
        let iou = intersectionOverUnion(candidate.boundingBox, existing.boundingBox)
        let containment = overlapRatio(candidate.boundingBox, existing.boundingBox)
        let textA = normalizedOCRText(candidate.text)
        let textB = normalizedOCRText(existing.text)
        let similarText = textA == textB
            || textA.contains(textB)
            || textB.contains(textA)
            || textSimilarity(textA, textB) >= 0.72
        guard similarText else { return false }
        return iou >= 0.38 || containment >= 0.72
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return intersectionArea / max(1, unionArea)
    }

    private static func sliceDiagnostics(
        from result: SliceRawCandidateResult,
        assignedCandidates: [MangaOverlayOCRCandidate],
        sourceImage: String,
        image: CGImage
    ) -> MangaOverlaySliceOCRDiagnostics {
        let dedupedSliceIDs = Set(result.duplicateGroups.flatMap { group in
            group.compactMap(\.sliceIndex)
        })
        let candidateSummaries = assignedCandidates.map { candidate in
            MangaOverlaySliceOCRCandidateSummary(
                text: candidate.text,
                bbox: rectArray(candidate.boundingBox),
                sliceIndex: candidate.sliceIndex,
                dedupedFromSliceIndexes: candidate.sliceOverlapDeduped ? Array(dedupedSliceIDs).sorted() : [],
                bubbleID: candidate.bubbleID,
                source: candidate.source,
                sliceOverlapDeduped: candidate.sliceOverlapDeduped
            )
        }
        return MangaOverlaySliceOCRDiagnostics(
            enabled: result.enabled,
            reason: result.reason,
            sourceImage: sourceImage,
            imageWidth: image.width,
            imageHeight: image.height,
            aspectRatio: Double(result.contentRect.height / max(1, result.contentRect.width)),
            thresholdAspectRatio: Double(result.thresholdAspectRatio),
            overlapRatio: Double(result.overlapRatio),
            slices: result.slices.map { slice in
                MangaOverlaySliceOCRSlice(
                    index: slice.index,
                    bbox: rectArray(slice.rect),
                    overlapRatio: Double(slice.overlapRatio),
                    rawObservationCount: result.rawCandidates.filter { $0.sliceIndex == slice.index }.count
                )
            },
            rawCandidateCount: result.rawCandidates.count,
            finalCandidateCount: assignedCandidates.count,
            dedupedCandidateCount: result.rawCandidates.count - assignedCandidates.count,
            duplicateGroupCount: result.duplicateGroups.count,
            residualOverlapDuplicateCount: residualSliceDuplicateCount(in: assignedCandidates),
            candidates: candidateSummaries,
            notes: [
                "slice OCR is enabled only when content aspect ratio exceeds threshold",
                "overlap dedupe uses bbox IoU/containment plus text similarity and never uses ground truth",
                "slice bbox y values are restored into the original image coordinate system before bubble assignment"
            ]
        )
    }

    private static func residualSliceDuplicateCount(in candidates: [MangaOverlayOCRCandidate]) -> Int {
        var count = 0
        for leftIndex in candidates.indices {
            for rightIndex in candidates.indices where rightIndex > leftIndex {
                if isSliceDuplicate(candidates[leftIndex], of: candidates[rightIndex]) {
                    count += 1
                }
            }
        }
        return count
    }

    private static func mergeCandidatesIntoBlocks(
        _ candidates: [MangaOverlayOCRCandidate],
        imageSize: CGSize
    ) -> MergeCandidatesResult {
        let cleanCandidates = deduplicateCandidates(candidates)
            .filter { $0.boundingBox.width >= 14 && $0.boundingBox.height >= 7 }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 18 {
                    return lhs.boundingBox.minY < rhs.boundingBox.minY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

        var clusters: [MangaOverlayOCRCluster] = []
        var crossBubbleMergeRejectedCount = 0
        var rejectedBubbleIDs = Set<Int>()
        var rejectedUnassignedMerge = false
        for candidate in cleanCandidates {
            let spatialMatches = clusters.indices.filter { shouldCluster(candidate, with: clusters[$0]) }
            if spatialMatches.contains(where: { !sameBubble(candidate, clusters[$0]) }) {
                crossBubbleMergeRejectedCount += 1
                recordRejectedBubbleID(candidate.bubbleID, rejectedBubbleIDs: &rejectedBubbleIDs, rejectedUnassignedMerge: &rejectedUnassignedMerge)
                for index in spatialMatches where !sameBubble(candidate, clusters[index]) {
                    recordRejectedBubbleID(clusters[index].bubbleID, rejectedBubbleIDs: &rejectedBubbleIDs, rejectedUnassignedMerge: &rejectedUnassignedMerge)
                }
            }
            if let index = spatialMatches.first(where: { sameBubble(candidate, clusters[$0]) }) {
                clusters[index].candidates.append(candidate)
            } else {
                clusters.append(MangaOverlayOCRCluster(candidates: [candidate]))
            }
        }

        let merged = mergeOverlappingClusters(
            clusters,
            rejectedCount: &crossBubbleMergeRejectedCount,
            rejectedBubbleIDs: &rejectedBubbleIDs,
            rejectedUnassignedMerge: &rejectedUnassignedMerge
        )
            .map { cluster in
                let ordered = orderedCandidates(cluster.candidates)
                let text = mergeText(from: ordered)
                let confidenceValues = ordered.compactMap(\.confidence)
                let confidence = confidenceValues.isEmpty
                    ? nil
                    : confidenceValues.reduce(0, +) / Float(confidenceValues.count)
                let angle = dominantAngle(in: ordered)
                return MangaOverlayOCRBlock(
                    text: text,
                    confidence: confidence,
                    boundingBox: clamp(cluster.boundingBox.insetBy(dx: -6, dy: -6), to: CGRect(origin: .zero, size: imageSize)),
                    rotationAngle: angle,
                    bubbleID: cluster.bubbleID,
                    bubbleAssignmentMethod: cluster.bubbleAssignmentMethod,
                    bubbleBoundingBox: cluster.bubbleBoundingBox,
                    source: "wholePageOCR",
                    crossBubbleMergeRejected: false,
                    sliceIndex: cluster.sliceIndex,
                    sliceOverlapDeduped: cluster.sliceOverlapDeduped
                )
            }
            .filter { !$0.text.isEmpty }
            .sorted {
                if abs($0.boundingBox.minY - $1.boundingBox.minY) > 20 {
                    return $0.boundingBox.minY < $1.boundingBox.minY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
        return MergeCandidatesResult(
            blocks: merged.map { block in
                var updated = block
                updated.crossBubbleMergeRejected = block.bubbleID.map { rejectedBubbleIDs.contains($0) } ?? rejectedUnassignedMerge
                return updated
            },
            crossBubbleMergeRejectedCount: crossBubbleMergeRejectedCount,
            rejectedBubbleIDs: rejectedBubbleIDs,
            rejectedUnassignedMerge: rejectedUnassignedMerge
        )
    }

    private static func sameBubble(_ candidate: MangaOverlayOCRCandidate, _ cluster: MangaOverlayOCRCluster) -> Bool {
        candidate.bubbleID == cluster.bubbleID
    }

    private static func recordRejectedBubbleID(
        _ bubbleID: Int?,
        rejectedBubbleIDs: inout Set<Int>,
        rejectedUnassignedMerge: inout Bool
    ) {
        if let bubbleID {
            rejectedBubbleIDs.insert(bubbleID)
        } else {
            rejectedUnassignedMerge = true
        }
    }

    private static func shouldCluster(_ candidate: MangaOverlayOCRCandidate, with cluster: MangaOverlayOCRCluster) -> Bool {
        let candidateBox = candidate.boundingBox
        let clusterBox = cluster.boundingBox
        if overlapRatio(candidateBox, clusterBox) > 0.18 {
            return true
        }

        let verticalGap = max(0, max(candidateBox.minY - clusterBox.maxY, clusterBox.minY - candidateBox.maxY))
        let horizontalIntersection = max(0, min(candidateBox.maxX, clusterBox.maxX) - max(candidateBox.minX, clusterBox.minX))
        let horizontalOverlap = horizontalIntersection / max(1, min(candidateBox.width, clusterBox.width))
        let centerDeltaX = abs(candidateBox.midX - clusterBox.midX)

        let sameColumn = horizontalOverlap > 0.18 || centerDeltaX < max(24, clusterBox.width * 0.28)
        let nearbyLine = verticalGap < max(18, min(candidateBox.height, clusterBox.height) * 1.4)
        return sameColumn && nearbyLine
    }

    private static func mergeOverlappingClusters(
        _ input: [MangaOverlayOCRCluster],
        rejectedCount: inout Int,
        rejectedBubbleIDs: inout Set<Int>,
        rejectedUnassignedMerge: inout Bool
    ) -> [MangaOverlayOCRCluster] {
        var clusters = input
        var didMerge = true

        while didMerge {
            didMerge = false
            outer: for leftIndex in clusters.indices {
                for rightIndex in clusters.indices where rightIndex > leftIndex {
                    guard shouldMergeClusters(clusters[leftIndex], clusters[rightIndex]) else { continue }
                    guard clusters[leftIndex].bubbleID == clusters[rightIndex].bubbleID else {
                        rejectedCount += 1
                        recordRejectedBubbleID(clusters[leftIndex].bubbleID, rejectedBubbleIDs: &rejectedBubbleIDs, rejectedUnassignedMerge: &rejectedUnassignedMerge)
                        recordRejectedBubbleID(clusters[rightIndex].bubbleID, rejectedBubbleIDs: &rejectedBubbleIDs, rejectedUnassignedMerge: &rejectedUnassignedMerge)
                        continue
                    }
                    clusters[leftIndex].candidates.append(contentsOf: clusters[rightIndex].candidates)
                    clusters.remove(at: rightIndex)
                    didMerge = true
                    break outer
                }
            }
        }

        return clusters
    }

    private static func shouldMergeClusters(_ lhs: MangaOverlayOCRCluster, _ rhs: MangaOverlayOCRCluster) -> Bool {
        let lhsBox = lhs.boundingBox
        let rhsBox = rhs.boundingBox
        if overlapRatio(lhsBox, rhsBox) > 0.12 {
            return true
        }

        let verticalGap = max(0, max(lhsBox.minY - rhsBox.maxY, rhsBox.minY - lhsBox.maxY))
        let horizontalIntersection = max(0, min(lhsBox.maxX, rhsBox.maxX) - max(lhsBox.minX, rhsBox.minX))
        let horizontalOverlap = horizontalIntersection / max(1, min(lhsBox.width, rhsBox.width))
        let centerDeltaX = abs(lhsBox.midX - rhsBox.midX)
        return verticalGap < 12
            && (horizontalOverlap > 0.45 || centerDeltaX < min(lhsBox.width, rhsBox.width) * 0.35)
    }

    private static func deduplicateCandidates(_ candidates: [MangaOverlayOCRCandidate]) -> [MangaOverlayOCRCandidate] {
        var result: [MangaOverlayOCRCandidate] = []
        for candidate in candidates.sorted(by: isBetterCandidate) {
            guard !result.contains(where: { isDuplicateCandidate(candidate, of: $0) }) else { continue }
            result.append(candidate)
        }
        return result
    }

    private static func isBetterCandidate(_ lhs: MangaOverlayOCRCandidate, _ rhs: MangaOverlayOCRCandidate) -> Bool {
        let lhsScore = Double(lhs.text.count) + Double(lhs.confidence ?? 0) * 8 - Double(lhs.rotationAngle == 0 ? 0 : 1)
        let rhsScore = Double(rhs.text.count) + Double(rhs.confidence ?? 0) * 8 - Double(rhs.rotationAngle == 0 ? 0 : 1)
        return lhsScore > rhsScore
    }

    private static func isDuplicateCandidate(_ candidate: MangaOverlayOCRCandidate, of existing: MangaOverlayOCRCandidate) -> Bool {
        guard overlapRatio(candidate.boundingBox, existing.boundingBox) > 0.48 else { return false }
        let lhs = normalizedOCRText(candidate.text)
        let rhs = normalizedOCRText(existing.text)
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs) || textSimilarity(lhs, rhs) > 0.76
    }

    private static func normalizedOCRText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let lhsBigrams = bigrams(lhs)
        let rhsBigrams = bigrams(rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return lhs == rhs ? 1 : 0
        }
        let commonCount = lhsBigrams.intersection(rhsBigrams).count
        return Double(commonCount * 2) / Double(lhsBigrams.count + rhsBigrams.count)
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count > 1 else { return Set(characters.map(String.init)) }
        return Set(characters.indices.dropLast().map { index in
            String(characters[index]) + String(characters[characters.index(after: index)])
        })
    }

    private static func orderedCandidates(_ candidates: [MangaOverlayOCRCandidate]) -> [MangaOverlayOCRCandidate] {
        candidates.sorted {
            if abs($0.boundingBox.minY - $1.boundingBox.minY) > max(8, min($0.boundingBox.height, $1.boundingBox.height) * 0.7) {
                return $0.boundingBox.minY < $1.boundingBox.minY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
    }

    private static func mergeText(from candidates: [MangaOverlayOCRCandidate]) -> String {
        var lines: [String] = []
        var currentLine: [MangaOverlayOCRCandidate] = []

        for candidate in deduplicateLineText(candidates) {
            if let last = currentLine.last,
               abs(candidate.boundingBox.midY - last.boundingBox.midY) > max(10, last.boundingBox.height * 0.75) {
                lines.append(currentLine.map(\.text).joined(separator: " "))
                currentLine = [candidate]
            } else {
                currentLine.append(candidate)
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine.map(\.text).joined(separator: " "))
        }

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func deduplicateLineText(_ candidates: [MangaOverlayOCRCandidate]) -> [MangaOverlayOCRCandidate] {
        var seen = Set<String>()
        var output: [MangaOverlayOCRCandidate] = []
        for candidate in candidates {
            let key = normalizedOCRText(candidate.text)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(candidate)
        }
        return output
    }

    private static func dominantAngle(in candidates: [MangaOverlayOCRCandidate]) -> Int {
        let grouped = Dictionary(grouping: candidates, by: \.rotationAngle)
        return grouped.max { lhs, rhs in
            let lhsScore = lhs.value.reduce(0) { $0 + $1.text.count }
            let rhsScore = rhs.value.reduce(0) { $0 + $1.text.count }
            return lhsScore < rhsScore
        }?.key ?? 0
    }

    private static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let minArea = max(1, min(lhs.width * lhs.height, rhs.width * rhs.height))
        return intersectionArea / minArea
    }

    private static func candidateOverlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        return intersectionArea / max(1, lhs.width * lhs.height)
    }

    private static func assignBubble(
        to candidate: MangaOverlayOCRCandidate,
        bubbles: [MangaOverlayBubbleCandidate]
    ) -> MangaOverlayOCRCandidate {
        guard !bubbles.isEmpty else {
            return MangaOverlayOCRCandidate(
                text: candidate.text,
                confidence: candidate.confidence,
                boundingBox: candidate.boundingBox,
                rotationAngle: candidate.rotationAngle,
                bubbleID: nil,
                bubbleAssignmentMethod: "unassigned",
                bubbleBoundingBox: nil,
                source: candidate.source,
                sliceIndex: candidate.sliceIndex,
                sliceOverlapDeduped: candidate.sliceOverlapDeduped
            )
        }

        let center = CGPoint(x: candidate.boundingBox.midX, y: candidate.boundingBox.midY)
        let ranked: [BubbleAssignmentScore] = bubbles.map { bubble in
            let overlap = candidateOverlapRatio(candidate.boundingBox, bubble.boundingBox)
            let centerContainment = centerContainmentScore(center, in: bubble.boundingBox)
            return BubbleAssignmentScore(
                bubble: bubble,
                overlap: overlap,
                containsCenter: bubble.boundingBox.contains(center),
                centerContainment: centerContainment,
                score: overlap * 0.45 + centerContainment * 0.55
            )
        }
        .sorted {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.bubble.area < $1.bubble.area
        }

        let centerMatches = ranked.filter { $0.containsCenter }
        if centerMatches.count > 1,
           let selected = selectedCenterMatch(centerMatches, center: center) {
            return MangaOverlayOCRCandidate(
                text: candidate.text,
                confidence: candidate.confidence,
                boundingBox: candidate.boundingBox,
                rotationAngle: candidate.rotationAngle,
                bubbleID: selected.bubble.index,
                bubbleAssignmentMethod: "centerPoint",
                bubbleBoundingBox: selected.bubble.boundingBox,
                source: candidate.source,
                sliceIndex: candidate.sliceIndex,
                sliceOverlapDeduped: candidate.sliceOverlapDeduped
            )
        } else if centerMatches.count > 1 {
            return unassignedBubbleCandidate(from: candidate)
        }

        if let best = ranked.first,
           best.overlap >= 0.18,
           best.centerContainment >= 0.18,
           (ranked.count < 2 || best.score - ranked[1].score >= 0.08) {
            return MangaOverlayOCRCandidate(
                text: candidate.text,
                confidence: candidate.confidence,
                boundingBox: candidate.boundingBox,
                rotationAngle: candidate.rotationAngle,
                bubbleID: best.bubble.index,
                bubbleAssignmentMethod: "overlapArea",
                bubbleBoundingBox: best.bubble.boundingBox,
                source: candidate.source,
                sliceIndex: candidate.sliceIndex,
                sliceOverlapDeduped: candidate.sliceOverlapDeduped
            )
        }

        if let best = centerMatches.first,
           best.overlap >= 0.04,
           best.centerContainment >= 0.32,
           (centerMatches.count < 2 || best.centerContainment - centerMatches[1].centerContainment >= 0.14) {
            return MangaOverlayOCRCandidate(
                text: candidate.text,
                confidence: candidate.confidence,
                boundingBox: candidate.boundingBox,
                rotationAngle: candidate.rotationAngle,
                bubbleID: best.bubble.index,
                bubbleAssignmentMethod: "centerPoint",
                bubbleBoundingBox: best.bubble.boundingBox,
                source: candidate.source,
                sliceIndex: candidate.sliceIndex,
                sliceOverlapDeduped: candidate.sliceOverlapDeduped
            )
        }

        return unassignedBubbleCandidate(from: candidate)
    }

    private static func unassignedBubbleCandidate(from candidate: MangaOverlayOCRCandidate) -> MangaOverlayOCRCandidate {
        MangaOverlayOCRCandidate(
            text: candidate.text,
            confidence: candidate.confidence,
            boundingBox: candidate.boundingBox,
            rotationAngle: candidate.rotationAngle,
            bubbleID: nil,
            bubbleAssignmentMethod: "unassigned",
            bubbleBoundingBox: nil,
            source: candidate.source,
            sliceIndex: candidate.sliceIndex,
            sliceOverlapDeduped: candidate.sliceOverlapDeduped
        )
    }

    private static func selectedCenterMatch(
        _ matches: [BubbleAssignmentScore],
        center: CGPoint
    ) -> BubbleAssignmentScore? {
        let verticallyRanked = matches.sorted { lhs, rhs in
            let lhsDistance = abs(center.y - lhs.bubble.boundingBox.midY)
            let rhsDistance = abs(center.y - rhs.bubble.boundingBox.midY)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.bubble.area < rhs.bubble.area
        }
        guard let best = verticallyRanked.first else { return nil }
        guard best.overlap >= 0.04, best.centerContainment >= 0.12 else { return nil }
        guard verticallyRanked.count > 1 else { return best }

        let bestDistance = abs(center.y - best.bubble.boundingBox.midY)
        let secondDistance = abs(center.y - verticallyRanked[1].bubble.boundingBox.midY)
        if secondDistance - bestDistance >= 12 {
            return best
        }
        if best.score - verticallyRanked[1].score >= 0.12 {
            return best
        }
        return nil
    }

    private static func centerContainmentScore(_ point: CGPoint, in rect: CGRect) -> CGFloat {
        guard rect.contains(point), rect.width > 0, rect.height > 0 else { return 0 }
        let horizontal = min(point.x - rect.minX, rect.maxX - point.x) / max(1, rect.width / 2)
        let vertical = min(point.y - rect.minY, rect.maxY - point.y) / max(1, rect.height / 2)
        return max(0, min(1, min(horizontal, vertical)))
    }

    private static func bubbleGeometryDiagnostics(
        bubbles: [MangaOverlayBubbleCandidate],
        candidates: [MangaOverlayOCRCandidate],
        blocks: [MangaOverlayOCRBlock],
        crossBubbleMergeRejectedCount: Int
    ) -> MangaOverlayBubbleGeometryDiagnostics {
        let probeBubbles = bubbles.map { bubble in
            MangaOverlayProbeBubble(
                id: bubble.index,
                bbox: rectArray(bubble.boundingBox),
                source: bubble.source,
                area: Double(bubble.area),
                confidence: bubble.confidence
            )
        }
        let regions = candidates.map { candidate in
            MangaOverlayTextRegion(
                bbox: rectArray(candidate.boundingBox),
                bubbleID: candidate.bubbleID,
                source: candidate.source,
                confidence: candidate.confidence,
                assignmentMethod: candidate.bubbleAssignmentMethod
            )
        }
        let indexedBlocks = Array(blocks.enumerated())
        let audits = bubbles.map { bubble in
            let bubbleRegions = candidates.filter { $0.bubbleID == bubble.index }
            let bubbleBlocks = indexedBlocks.filter { $0.element.bubbleID == bubble.index }
            let blockValues = bubbleBlocks.map(\.element)
            let maxOverlap = maxBlockOverlapRatio(blocks: blockValues)
            let duplicatePairs = duplicateTextPairCount(blocks: blockValues)
            let areaRatio = bubble.boundingBox.width * bubble.boundingBox.height
                / max(1, CGFloat(bubbles.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 1))
            let oversized = bubbleBlocks.count >= 2 && (areaRatio >= 0.55 || maxOverlap >= 0.45 || duplicatePairs > 0)
            var auditNotes: [String] = []
            if blockValues.count >= 2 {
                auditNotes.append("multipleFusedBlocksInBubble")
            }
            if maxOverlap >= 0.45 {
                auditNotes.append("highBlockOverlapWithinBubble")
            }
            if duplicatePairs > 0 {
                auditNotes.append("similarTextCandidatesWithinBubble")
            }
            if oversized {
                auditNotes.append("bubbleSplitCandidateDiagnosticOnly")
            }
            return MangaOverlayBubbleSplitAudit(
                bubbleID: bubble.index,
                bbox: rectArray(bubble.boundingBox),
                source: bubble.source,
                area: Double(bubble.area),
                confidence: Double(bubble.confidence),
                textRegionCount: bubbleRegions.count,
                fusedBlockIndexes: bubbleBlocks.map(\.offset).sorted(),
                selectedBlockCount: blockValues.count,
                maxBlockOverlapRatio: maxOverlap,
                duplicateTextPairCount: duplicatePairs,
                oversizedBubbleRisk: oversized,
                bubbleSplitCandidate: oversized,
                notes: auditNotes
            )
        }
        let assigned = regions.filter { $0.bubbleID != nil }.count
        let notes = [
            "bubble geometry is used as the primary merge boundary for whole-page OCR",
            "unassigned OCR observations are kept but only merge with other unassigned observations",
            "preprocessed OCR crops are clamped to the assigned bubble bbox when present",
            "bubbleAudits are diagnostic only and do not split or replace the main flow"
        ]
        return MangaOverlayBubbleGeometryDiagnostics(
            bubbles: probeBubbles,
            textRegions: regions,
            bubbleAudits: audits,
            assignedTextRegionCount: assigned,
            unassignedTextRegionCount: regions.count - assigned,
            crossBubbleMergeRejectedCount: crossBubbleMergeRejectedCount,
            notes: notes
        )
    }

    private static func rectArray(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map(Double.init)
    }

    private static func maxBlockOverlapRatio(blocks: [MangaOverlayOCRBlock]) -> Double {
        guard blocks.count > 1 else { return 0 }
        var maxOverlap = 0.0
        for leftIndex in blocks.indices {
            for rightIndex in blocks.indices where rightIndex > leftIndex {
                let left = blocks[leftIndex].boundingBox
                let right = blocks[rightIndex].boundingBox
                let intersection = left.intersection(right)
                guard !intersection.isNull else { continue }
                let smallerArea = min(left.width * left.height, right.width * right.height)
                guard smallerArea > 0 else { continue }
                maxOverlap = max(maxOverlap, Double((intersection.width * intersection.height) / smallerArea))
            }
        }
        return maxOverlap
    }

    private static func duplicateTextPairCount(blocks: [MangaOverlayOCRBlock]) -> Int {
        guard blocks.count > 1 else { return 0 }
        var count = 0
        for leftIndex in blocks.indices {
            for rightIndex in blocks.indices where rightIndex > leftIndex {
                let leftWords = bubbleAuditWords(blocks[leftIndex].text)
                let rightWords = bubbleAuditWords(blocks[rightIndex].text)
                guard !leftWords.isEmpty, !rightWords.isEmpty else { continue }
                let leftSet = Set(leftWords)
                let rightSet = Set(rightWords)
                let union = leftSet.union(rightSet).count
                let similarity = Double(leftSet.intersection(rightSet).count) / Double(max(union, 1))
                if similarity >= 0.45 {
                    count += 1
                }
            }
        }
        return count
    }

    private static func bubbleAuditWords(_ text: String) -> [String] {
        text
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    private static func detectBubbleCandidates(
        in image: CGImage,
        cropping: MangaOverlayProbeCropping,
        customWords: [String]
    ) throws -> [MangaOverlayBubbleCandidate] {
        let contentRect = contentCropRect(for: image, cropping: cropping)
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var mask = [Bool](repeating: false, count: width * height)
        let minX = max(0, Int(contentRect.minX))
        let maxX = min(width - 1, Int(contentRect.maxX))
        let minY = max(0, Int(contentRect.minY))
        let maxY = min(height - 1, Int(contentRect.maxY))
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let luminance = (red * 299 + green * 587 + blue * 114) / 1000
                mask[y * width + x] = luminance > 218 && (maxChannel - minChannel) < 34
            }
        }

        var visited = [Bool](repeating: false, count: width * height)
        var rects: [CGRect] = []
        let minArea = max(280, Int(CGFloat(width * height) * 0.00035))
        let maxArea = Int(CGFloat(width * height) * 0.055)
        let imageArea = CGFloat(width * height)
        for y in minY...maxY {
            for x in minX...maxX {
                let startIndex = y * width + x
                guard mask[startIndex], !visited[startIndex] else { continue }
                var queue = [(x, y)]
                visited[startIndex] = true
                var cursor = 0
                var componentMinX = x
                var componentMaxX = x
                var componentMinY = y
                var componentMaxY = y
                var area = 0
                while cursor < queue.count {
                    let (currentX, currentY) = queue[cursor]
                    cursor += 1
                    area += 1
                    componentMinX = min(componentMinX, currentX)
                    componentMaxX = max(componentMaxX, currentX)
                    componentMinY = min(componentMinY, currentY)
                    componentMaxY = max(componentMaxY, currentY)
                    for (nextX, nextY) in [(currentX + 1, currentY), (currentX - 1, currentY), (currentX, currentY + 1), (currentX, currentY - 1)] {
                        guard nextX >= minX, nextX <= maxX, nextY >= minY, nextY <= maxY else { continue }
                        let nextIndex = nextY * width + nextX
                        guard mask[nextIndex], !visited[nextIndex] else { continue }
                        visited[nextIndex] = true
                        queue.append((nextX, nextY))
                    }
                }

                let rect = CGRect(
                    x: componentMinX,
                    y: componentMinY,
                    width: max(1, componentMaxX - componentMinX + 1),
                    height: max(1, componentMaxY - componentMinY + 1)
                )
                let fillRatio = CGFloat(area) / max(1, rect.width * rect.height)
                let aspectRatio = rect.width / max(1, rect.height)
                let rectArea = rect.width * rect.height
                let isPageSized = rect.width > CGFloat(width) * 0.72
                    || rect.height > contentRect.height * 0.45
                    || rectArea > imageArea * 0.08
                guard area >= minArea,
                      area <= maxArea,
                      !isPageSized,
                      rect.width >= 24,
                      rect.height >= 18,
                      aspectRatio >= 0.22,
                      aspectRatio <= 6.2,
                      fillRatio >= 0.28 else { continue }
                rects.append(expand(rect, by: 0.1, bounds: CGRect(x: 0, y: 0, width: width, height: height)))
            }
        }

        let seedRects = try ocrSeedBubbleRects(
            in: image,
            contentRect: contentRect,
            customWords: customWords
        )
        let seedOnlyRects = deduplicateSeedBubbleRects(seedRects)
        let whiteOnlyRects = mergeBubbleRects(rects).filter { white in
            !seedOnlyRects.contains { seed in
                overlapRatio(seed, white) > 0.62
            }
        }
        let candidates = seedOnlyRects.map { rect in
            (rect: rect, source: "ocrSeed")
        } + whiteOnlyRects.map { rect in
            (rect: rect, source: "whiteComponent")
        }
        return candidates
            .filter { item in
                item.rect.width >= 34
                    && item.rect.height >= 28
                    && item.rect.width <= CGFloat(width) * 0.58
                    && item.rect.height <= contentRect.height * 0.4
            }
            .sorted {
                if abs($0.rect.minY - $1.rect.minY) > 20 {
                    return $0.rect.minY < $1.rect.minY
                }
                return $0.rect.minX < $1.rect.minX
            }
            .enumerated()
            .map { index, item in
                MangaOverlayBubbleCandidate(
                    index: index,
                    boundingBox: item.rect,
                    source: item.source,
                    area: item.rect.width * item.rect.height,
                    confidence: item.source == "ocrSeed" ? 0.82 : 0.68
                )
        }
    }

    private static func ocrSeedBubbleRects(
        in image: CGImage,
        contentRect: CGRect,
        customWords: [String]
    ) throws -> [CGRect] {
        let croppedImage = try croppedImage(image, rect: contentRect)
        let scaledImage = try scaledImage(croppedImage, scale: ocrScale)
        let candidates = try [0, 90, 180, 270].flatMap { angle in
            let rotatedImage = try rotatedImage(scaledImage, angle: angle)
            return try recognizeTextCandidates(
                in: rotatedImage,
                angle: angle,
                scaledContentSize: CGSize(width: CGFloat(scaledImage.width), height: CGFloat(scaledImage.height)),
                contentOrigin: contentRect.origin,
                scale: ocrScale,
                customWords: customWords
            )
        }
        let blocks = mergeCandidatesIntoBlocks(
            candidates,
            imageSize: CGSize(width: image.width, height: image.height)
        ).blocks
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return blocks
            .map { block -> CGRect in
                let rect = block.boundingBox
                let longText = block.text.count > 34
                let widthPad = max(18, rect.width * (longText ? 1.25 : 1.85))
                let heightPad = max(20, rect.height * 0.8)
                return clamp(rect.insetBy(dx: -widthPad, dy: -heightPad), to: bounds).integral
            }
            .filter { rect in
                rect.width >= 42
                    && rect.height >= 34
                    && rect.width <= CGFloat(image.width) * 0.62
                    && rect.height <= contentRect.height * 0.42
            }
    }

    private static func rawBubbleSeedCandidates(
        in image: CGImage,
        cropping: MangaOverlayProbeCropping,
        customWords: [String]
    ) throws -> [MangaOverlayBubbleCandidate] {
        let contentRect = contentCropRect(for: image, cropping: cropping)
        let seedRects = try ocrSeedBubbleRects(in: image, contentRect: contentRect, customWords: customWords)
        return seedRects.enumerated().map { index, rect in
            MangaOverlayBubbleCandidate(
                index: index,
                boundingBox: rect,
                source: "ocrSeedRaw",
                area: rect.width * rect.height,
                confidence: 0.72
            )
        }
    }

    private static func mergeBubbleRects(_ rects: [CGRect]) -> [CGRect] {
        var output: [CGRect] = []
        for rect in rects.sorted(by: { $0.minY == $1.minY ? $0.minX < $1.minX : $0.minY < $1.minY }) {
            if let index = output.firstIndex(where: { overlapRatio($0, rect) > 0.2 || $0.insetBy(dx: -8, dy: -8).intersects(rect) }) {
                output[index] = output[index].union(rect)
            } else {
                output.append(rect)
            }
        }
        return output.sorted {
            if abs($0.minY - $1.minY) > 20 {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    private static func deduplicateSeedBubbleRects(_ rects: [CGRect]) -> [CGRect] {
        var output: [CGRect] = []
        for rect in rects.sorted(by: { ($0.width * $0.height) > ($1.width * $1.height) }) {
            if let index = output.firstIndex(where: { overlapRatio($0, rect) > 0.78 }) {
                output[index] = output[index].union(rect)
            } else {
                output.append(rect)
            }
        }
        return output.sorted {
            if abs($0.minY - $1.minY) > 20 {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }
    }

    static let groundTruthMatchThreshold = 0.42

    struct GroundTruthMatch: Equatable, Sendable {
        var index: Int?
        var entry: MangaGroundTruthEntry?
        var similarity: Double
        var legacySimilarity: Double
        var wordOrderPreserved: Bool?
        var matchState: String
    }

    static func bestGroundTruthMatch(
        text: String,
        groundTruth: [MangaGroundTruthEntry],
        threshold: Double = groundTruthMatchThreshold
    ) -> GroundTruthMatch {
        let words = normalizedWords(text)
        guard !words.isEmpty else {
            return GroundTruthMatch(index: nil, entry: nil, similarity: 0, legacySimilarity: 0, wordOrderPreserved: nil, matchState: "unmatched")
        }
        var bestIndex: Int?
        var bestEntry: MangaGroundTruthEntry?
        var bestScore = 0.0
        var bestLegacyScore = 0.0
        var bestWordOrder: Bool?
        for (index, truth) in groundTruth.enumerated() {
            let score = wordLevelSimilarity(words, normalizedWords(truth.text))
            if score > bestScore {
                bestScore = score
                bestLegacyScore = textSimilarity(normalizedOCRText(text), normalizedOCRText(truth.text))
                bestWordOrder = wordOrderPreserved(ocrWords: words, truthWords: normalizedWords(truth.text))
                bestIndex = index
                bestEntry = truth
            }
        }
        if bestScore < threshold {
            return GroundTruthMatch(
                index: nil,
                entry: nil,
                similarity: bestScore,
                legacySimilarity: bestLegacyScore,
                wordOrderPreserved: bestWordOrder,
                matchState: "unmatched"
            )
        }
        return GroundTruthMatch(
            index: bestIndex,
            entry: bestEntry,
            similarity: bestScore,
            legacySimilarity: bestLegacyScore,
            wordOrderPreserved: bestWordOrder,
            matchState: "matched"
        )
    }

    static func frameworkMetrics(
        texts: [String],
        groundTruth: [MangaGroundTruthEntry],
        processingTimeMs: Int
    ) -> MangaOverlayFrameworkMetrics {
        let matches = texts.map { bestGroundTruthMatch(text: $0, groundTruth: groundTruth) }
        let matched = matches.filter { $0.index != nil }
        let dialogueScores = matched.filter { $0.entry?.type == MangaGroundTruthEntry.dialogueType }.map(\.similarity)
        let scores = dialogueScores.isEmpty ? matched.map(\.similarity) : dialogueScores
        let average = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        return MangaOverlayFrameworkMetrics(
            totalBlocksDetected: texts.count,
            processingTimeMs: processingTimeMs,
            accuracyVsGroundTruth: average,
            matchedGroundTruthCount: matched.count,
            unmatchedBlockCount: matches.count - matched.count
        )
    }

    static func matchedGroundTruthIndexes(
        texts: [String],
        groundTruth: [MangaGroundTruthEntry],
        types: Set<String> = [MangaGroundTruthEntry.dialogueType]
    ) -> Set<Int> {
        var matched = Set<Int>()
        for text in texts {
            let match = bestGroundTruthMatch(text: text, groundTruth: groundTruth)
            if let index = match.index,
               let type = match.entry?.type,
               types.contains(type) {
                matched.insert(index)
            }
        }
        return matched
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func wordLevelSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        let distance = levenshteinDistance(lhs, rhs)
        return max(0, 1 - Double(distance) / Double(max(lhs.count, rhs.count, 1)))
    }

    private static func wordOrderPreserved(ocrWords: [String], truthWords: [String]) -> Bool? {
        let matchedTruthIndexes = ocrWords.compactMap { ocrWord in
            truthWords.firstIndex { truthWord in
                truthWord == ocrWord || correctionWordSimilarity(ocrWord, truthWord) >= 0.74
            }
        }
        guard matchedTruthIndexes.count >= 3 else { return nil }
        return zip(matchedTruthIndexes, matchedTruthIndexes.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private static func correctionWordSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
        let distance = levenshteinDistance(Array(lhs), Array(rhs))
        return 1 - Double(distance) / Double(max(max(lhs.count, rhs.count), 1))
    }

    private static func levenshteinDistance<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for lhsIndex in 1...lhs.count {
            current[0] = lhsIndex
            for rhsIndex in 1...rhs.count {
                let cost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private static func drawBubbleDebug(on image: CGImage, bubbles: [MangaOverlayBubbleCandidate]) throws -> CGImage {
        try draw(on: image) { context, _ in
            context.setLineWidth(max(3, CGFloat(image.width) * 0.006))
            for bubble in bubbles {
                let isSeed = bubble.source.hasPrefix("ocrSeed")
                let strokeColor = isSeed
                    ? CGColor(red: 0.12, green: 0.45, blue: 1, alpha: 1)
                    : CGColor(red: 0.1, green: 0.72, blue: 0.25, alpha: 1)
                let labelColor = isSeed
                    ? CGColor(red: 0.1, green: 0.34, blue: 0.86, alpha: 0.9)
                    : CGColor(red: 0.1, green: 0.65, blue: 0.22, alpha: 0.9)
                context.setStrokeColor(strokeColor)
                context.stroke(bubble.boundingBox)
                drawText(
                    "B\(bubble.index) \(isSeed ? "seed" : "white")",
                    in: CGRect(x: bubble.boundingBox.minX, y: max(0, bubble.boundingBox.minY - 28), width: 128, height: 26),
                    fontSize: 18,
                    textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    backgroundColor: labelColor,
                    context: context
                )
            }
        }
    }

    private static func drawBubbleCrops(
        from image: CGImage,
        bubbles: [MangaOverlayBubbleCandidate],
        results: [MangaOverlayBubbleResult],
        preprocessing: MangaOverlayPreprocessingOptions
    ) throws -> CGImage {
        let tileWidth: CGFloat = 280
        let tileHeight: CGFloat = 210
        let columns = 2
        let rows = max(1, Int(ceil(Double(max(bubbles.count, 1)) / Double(columns))))
        let canvasSize = CGSize(width: tileWidth * CGFloat(columns), height: tileHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        var renderError: Error?
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.94, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))
            for bubble in bubbles {
                let column = bubble.index % columns
                let row = bubble.index / columns
                let tileRect = CGRect(x: CGFloat(column) * tileWidth + 8, y: CGFloat(row) * tileHeight + 8, width: tileWidth - 16, height: tileHeight - 16)
                do {
                    let cropRect = expand(bubble.boundingBox, by: 0.08, bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
                    let cropped = try croppedImage(image, rect: cropRect)
                    let processed = preprocessing.enabled ? try preprocessedImage(cropped, options: preprocessing) : cropped
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(tileRect)
                    let result = results.first(where: { $0.index == bubble.index })
                    let header = "B\(bubble.index) \(bubble.source) sim \(Int(((result?.bestSimilarity ?? 0) * 100).rounded()))%"
                    drawText(header, in: CGRect(x: tileRect.minX, y: tileRect.minY, width: tileRect.width, height: 23), fontSize: 13, textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), backgroundColor: CGColor(red: 0.1, green: 0.36, blue: 0.74, alpha: 0.9), context: context)
                    UIImage(cgImage: processed).draw(in: aspectFitRect(imageSize: CGSize(width: processed.width, height: processed.height), bounds: CGRect(x: tileRect.minX, y: tileRect.minY + 26, width: tileRect.width, height: tileRect.height - 76)))
                    let text = result?.text ?? ""
                    drawText(text.isEmpty ? "<no OCR>" : text, in: CGRect(x: tileRect.minX, y: tileRect.maxY - 48, width: tileRect.width, height: 46), fontSize: 10, textColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.84), context: context)
                } catch {
                    renderError = error
                }
            }
        }
        if let renderError {
            throw renderError
        }
        guard let output = rendered.cgImage else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return output
    }

    private static func drawBubbleTextOverlay(on image: CGImage, results: [MangaOverlayBubbleResult]) throws -> CGImage {
        try draw(on: image) { context, _ in
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            for result in results {
                let rect = rect(from: result.bbox)
                context.setStrokeColor(CGColor(red: 0.05, green: 0.38, blue: 0.95, alpha: 0.95))
                context.setLineWidth(2)
                context.stroke(rect)

                let similarity = result.bestSimilarity.formatted(.number.precision(.fractionLength(3)))
                let text = "#\(result.index) bubble-first\nsim=\(similarity)\n\(result.text)"
                let textRect = expand(rect, by: 0.22, bounds: bounds)
                context.setFillColor(CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 0.9))
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawDebugBoxes(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            context.setStrokeColor(CGColor(red: 1, green: 0.08, blue: 0.18, alpha: 1))
            context.setLineWidth(max(3, CGFloat(image.width) * 0.006))

            for block in blocks {
                let rect = rect(from: block.bbox)
                context.stroke(rect)
                drawText(
                    "#\(block.index) B\(block.bubbleID.map(String.init) ?? "-")",
                    in: CGRect(x: rect.minX, y: max(0, rect.minY - 30), width: 120, height: 28),
                    fontSize: 18,
                    textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                    backgroundColor: CGColor(red: 1, green: 0.08, blue: 0.18, alpha: 0.88),
                    context: context
                )
            }
        }
    }

    private static func drawTranslatedOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            for block in blocks where !block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
                let layoutRect = block.safeLayoutRect.map { rect(from: $0) }
                let expanded = clamp(layoutRect ?? expand(rect(from: block.bbox), by: 0.14, bounds: bounds), to: bounds)
                if block.backgroundFillApplied,
                   let colorComponents = block.backgroundFillColor,
                   colorComponents.count == 3,
                   !block.glyphMaskFillRects.isEmpty {
                    let background = CGColor(
                        red: colorComponents[0],
                        green: colorComponents[1],
                        blue: colorComponents[2],
                        alpha: 0.98
                    )
                    context.setFillColor(background)
                    for fillRect in block.glyphMaskFillRects {
                        context.fill(clamp(rect(from: fillRect), to: bounds))
                    }
                } else {
                    let background = sampleBackgroundColor(image: image, near: expanded)
                    context.setFillColor(background)
                    context.fill(expanded)
                }
                context.setStrokeColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 0.25))
                context.setLineWidth(1.5)
                context.stroke(expanded)

                drawCollisionCheckedText(
                    block.translatedText,
                    in: expanded,
                    context: context
                )
            }
        }
    }

    private static func drawOCRTextOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            for block in blocks {
                let rect = rect(from: block.bbox)
                context.setStrokeColor(CGColor(red: 0.05, green: 0.35, blue: 1, alpha: 0.9))
                context.setLineWidth(2)
                context.stroke(rect)

                let text = "#\(block.index) raw:\n\(block.rawOcrText)\npre:\n\(block.afterPreprocessingOcrText ?? "<off/no change>")"
                let textRect = expand(rect, by: 0.2, bounds: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.86))
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawDeterministicCorrectionOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            for block in blocks {
                let rect = rect(from: block.bbox)
                let changed = !block.deterministicCorrectionAppliedRules.isEmpty
                context.setStrokeColor(changed
                    ? CGColor(red: 0.58, green: 0.12, blue: 0.92, alpha: 0.95)
                    : CGColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 0.65)
                )
                context.setLineWidth(changed ? 2.5 : 1.5)
                context.stroke(rect)

                let originalSimilarity = block.ocrGroundTruthSimilarity.map {
                    $0.formatted(.number.precision(.fractionLength(3)))
                } ?? "n/a"
                let correctedSimilarity = block.deterministicCorrectionSimilarity.map {
                    $0.formatted(.number.precision(.fractionLength(3)))
                } ?? "n/a"
                let rules = block.deterministicCorrectionAppliedRules.isEmpty
                    ? "rules: <none>"
                    : "rules: \(block.deterministicCorrectionAppliedRules.joined(separator: ", "))"
                let correctedText = block.deterministicCorrectionText ?? block.finalTextUsedForTranslation
                let text = "#\(block.index) deterministic OCR\nsim: \(originalSimilarity) -> \(correctedSimilarity)\nraw:\n\(block.finalTextUsedForTranslation)\nfix:\n\(correctedText)\n\(rules)"
                let textRect = expand(rect, by: changed ? 0.32 : 0.22, bounds: bounds)
                context.setFillColor(changed
                    ? CGColor(red: 0.97, green: 0.92, blue: 1, alpha: 0.9)
                    : CGColor(red: 1, green: 1, blue: 1, alpha: 0.8)
                )
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawDeterministicTranslationOverlay(on image: CGImage, blocks: [MangaOverlayProbeBlock]) throws -> CGImage {
        try draw(on: image) { context, _ in
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            for block in blocks {
                guard block.deterministicCorrectionTranslationPassed != nil else { continue }
                let rect = rect(from: block.bbox)
                let passed = block.deterministicCorrectionTranslationPassed == true
                context.setStrokeColor(passed
                    ? CGColor(red: 0.05, green: 0.55, blue: 0.25, alpha: 0.95)
                    : CGColor(red: 0.85, green: 0.16, blue: 0.18, alpha: 0.95)
                )
                context.setLineWidth(2.5)
                context.stroke(rect)

                let correctedText = block.deterministicCorrectionText ?? ""
                let candidate = block.deterministicCorrectionTranslationCandidate ?? ""
                let failure = block.deterministicCorrectionTranslationFailureDetail ?? "passed"
                let text = "#\(block.index) deterministic translation\nfix:\n\(correctedText)\ntranslation:\n\(candidate)\n\(failure)"
                let textRect = expand(rect, by: 0.34, bounds: bounds)
                context.setFillColor(passed
                    ? CGColor(red: 0.9, green: 1, blue: 0.93, alpha: 0.9)
                    : CGColor(red: 1, green: 0.92, blue: 0.92, alpha: 0.9)
                )
                context.fill(textRect)
                drawFittingText(text, in: textRect.insetBy(dx: 4, dy: 4), context: context)
            }
        }
    }

    private static func drawBlockCrops(
        from image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        preprocessing: MangaOverlayPreprocessingOptions
    ) throws -> CGImage {
        let tileWidth: CGFloat = 260
        let tileHeight: CGFloat = 220
        let columns = 2
        let rows = max(1, Int(ceil(Double(blocks.count) / Double(columns))))
        let canvasSize = CGSize(width: tileWidth * CGFloat(columns), height: tileHeight * CGFloat(rows))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        var renderError: Error?
        let rendered = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setFillColor(CGColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))

            for (offset, block) in blocks.enumerated() {
                let column = offset % columns
                let row = offset / columns
                let origin = CGPoint(x: CGFloat(column) * tileWidth, y: CGFloat(row) * tileHeight)
                let tileRect = CGRect(x: origin.x + 8, y: origin.y + 8, width: tileWidth - 16, height: tileHeight - 16)
                do {
                    let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
                    let rect = rect(from: block.bbox)
                    let paddingX = CGFloat(block.cropPaddingX ?? max(5, rect.width * 0.18))
                    let paddingY = CGFloat(block.cropPaddingY ?? max(5, rect.height * 0.18))
                    let cropRect = clamp(rect.insetBy(dx: -paddingX, dy: -paddingY), to: bounds).integral
                    let cropped = try croppedImage(image, rect: cropRect)
                    let processed = preprocessing.enabled ? try preprocessedImage(cropped, options: preprocessing) : cropped
                    let cropImage = UIImage(cgImage: processed)
                    let imageRect = CGRect(x: tileRect.minX, y: tileRect.minY + 28, width: tileRect.width, height: tileRect.height - 62)
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(tileRect)
                    drawText("#\(block.index) \(block.cropStrategyUsed ?? "crop")", in: CGRect(x: tileRect.minX, y: tileRect.minY, width: 150, height: 24), fontSize: 14, textColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1), backgroundColor: CGColor(red: 1, green: 0.08, blue: 0.18, alpha: 0.88), context: context)
                    cropImage.draw(in: aspectFitRect(imageSize: CGSize(width: processed.width, height: processed.height), bounds: imageRect))
                    drawText(block.afterPreprocessingOcrText ?? block.rawOcrText, in: CGRect(x: tileRect.minX, y: tileRect.maxY - 32, width: tileRect.width, height: 30), fontSize: 11, textColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1), backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.82), context: context)
                } catch {
                    renderError = error
                }
            }
        }
        if let renderError {
            throw renderError
        }
        guard let output = rendered.cgImage else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return output
    }

    private static func aspectFitRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func safeBubbleRect(
        for bubbleRect: CGRect,
        representativeBlocks: [MangaOverlayProbeBlock]
    ) -> CGRect {
        let verticalCount = representativeBlocks.filter { block in
            let blockRect = Self.rect(from: block.bbox)
            return blockRect.height > blockRect.width * 1.18
        }.count
        let verticalDominant = verticalCount > representativeBlocks.count / 2
        let insetRatio: CGFloat = verticalDominant ? 0.20 : 0.12
        let shortSide = max(1, min(bubbleRect.width, bubbleRect.height))
        let inset = max(4, shortSide * insetRatio)
        let insetRect = bubbleRect.insetBy(dx: inset, dy: inset)
        guard insetRect.width >= 12, insetRect.height >= 12 else {
            return bubbleRect.insetBy(dx: min(4, bubbleRect.width * 0.08), dy: min(4, bubbleRect.height * 0.08))
        }
        return insetRect
    }

    private static func partitionedSafeRect(
        for block: MangaOverlayProbeBlock,
        in group: [MangaOverlayProbeBlock],
        bubbleSafeRect: CGRect
    ) -> CGRect {
        let blockRects = group.map { (id: $0.id, rect: Self.rect(from: $0.bbox)) }
        let verticalSpread = blockRects.map(\.1.midY).max().map { maxY in
            maxY - (blockRects.map(\.1.midY).min() ?? maxY)
        } ?? 0
        let horizontalSpread = blockRects.map(\.1.midX).max().map { maxX in
            maxX - (blockRects.map(\.1.midX).min() ?? maxX)
        } ?? 0
        let sortByY = verticalSpread >= horizontalSpread
        let sorted = blockRects.sorted { lhs, rhs in
            sortByY ? lhs.rect.midY < rhs.rect.midY : lhs.rect.midX < rhs.rect.midX
        }
        guard let position = sorted.firstIndex(where: { $0.id == block.id }) else {
            return bubbleSafeRect
        }

        let current = sorted[position].rect
        var partition = bubbleSafeRect
        if sortByY {
            let partitionMinY: CGFloat = position > 0 ? (sorted[position - 1].rect.midY + current.midY) / 2 : bubbleSafeRect.minY
            let partitionMaxY: CGFloat = position < sorted.count - 1 ? (current.midY + sorted[position + 1].rect.midY) / 2 : bubbleSafeRect.maxY
            partition = CGRect(x: bubbleSafeRect.minX, y: partitionMinY, width: bubbleSafeRect.width, height: partitionMaxY - partitionMinY)
        } else {
            let partitionMinX: CGFloat = position > 0 ? (sorted[position - 1].rect.midX + current.midX) / 2 : bubbleSafeRect.minX
            let partitionMaxX: CGFloat = position < sorted.count - 1 ? (current.midX + sorted[position + 1].rect.midX) / 2 : bubbleSafeRect.maxX
            partition = CGRect(x: partitionMinX, y: bubbleSafeRect.minY, width: partitionMaxX - partitionMinX, height: bubbleSafeRect.height)
        }

        let localInset = max(2, min(partition.width, partition.height) * 0.04)
        let candidate = partition.insetBy(dx: localInset, dy: localInset)
        return ensureMinimumRect(candidate, fallback: partition, bounds: bubbleSafeRect)
    }

    private static func ensureMinimumRect(_ rect: CGRect, fallback: CGRect, bounds: CGRect) -> CGRect {
        let candidate = rect.width >= 8 && rect.height >= 8 ? rect : fallback
        return clamp(candidate, to: bounds)
    }

    private static func draw(
        on image: CGImage,
        actions: (CGContext, CGSize) throws -> Void
    ) throws -> CGImage {
        let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        var renderError: Error?
        let rendered = renderer.image { rendererContext in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            do {
                try actions(rendererContext.cgContext, size)
            } catch {
                renderError = error
            }
        }
        if let renderError {
            throw renderError
        }
        guard let output = rendered.cgImage else {
            throw MangaOverlayProbeServiceError.imageRenderFailed
        }
        return output
    }

    private static func drawCollisionCheckedText(_ text: String, in rect: CGRect, context: CGContext) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        let plan = makeRenderTextPlan(cleanText, in: rect, minFontSize: minimumOverlayFontSize)
        drawLines(plan.lines, in: rect, fontSize: plan.fontSize, lineHeight: plan.lineHeight, context: context)
    }

    private static func drawFittingText(_ text: String, in rect: CGRect, context: CGContext) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        var fontSize = min(max(10, rect.height * 0.46), 32)
        while fontSize > 9 {
            let lines = wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)
            let lineHeight = fontSize * 1.18
            if CGFloat(lines.count) * lineHeight <= rect.height {
                drawLines(lines, in: rect, fontSize: fontSize, lineHeight: lineHeight, context: context)
                return
            }
            fontSize -= 1
        }

        let lines = wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)
        drawLines(Array(lines.prefix(max(1, Int(rect.height / (fontSize * 1.18))))), in: rect, fontSize: fontSize, lineHeight: fontSize * 1.18, context: context)
    }

    private static func makeRenderTextPlan(
        _ text: String,
        in rect: CGRect,
        minFontSize: CGFloat
    ) -> MangaOverlayRenderTextPlan {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxFontSize = min(max(10, rect.height * 0.38), 30)
        let initialLines = wrappedLines(cleanText, fontSize: maxFontSize, maxWidth: rect.width)
        let initialBounds = renderedTextBounds(
            lines: initialLines,
            fontSize: maxFontSize,
            lineHeight: maxFontSize * 1.18,
            rect: rect
        )
        let initialOverflow = initialBounds.map { !rect.insetBy(dx: -0.5, dy: -0.5).contains($0) } ?? false

        var fontSize = maxFontSize
        var selectedLines = initialLines
        var selectedBounds = initialBounds
        var minReached = false
        var truncated = false
        var resolved = !initialOverflow

        while fontSize >= minFontSize {
            let lines = wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)
            let lineHeight = fontSize * 1.18
            let bounds = renderedTextBounds(lines: lines, fontSize: fontSize, lineHeight: lineHeight, rect: rect)
            let fits = bounds.map { rect.insetBy(dx: -0.5, dy: -0.5).contains($0) } ?? true
            selectedLines = lines
            selectedBounds = bounds
            if fits {
                resolved = true
                break
            }
            fontSize -= 1
        }

        if fontSize < minFontSize {
            fontSize = minFontSize
            minReached = true
            let lineHeight = fontSize * 1.18
            let lines = wrappedLines(cleanText, fontSize: fontSize, maxWidth: rect.width)
            let maxLines = max(1, Int(floor(rect.height / lineHeight)))
            if lines.count > maxLines {
                selectedLines = Array(lines.prefix(maxLines))
                truncated = true
            } else {
                selectedLines = lines
            }
            selectedBounds = renderedTextBounds(lines: selectedLines, fontSize: fontSize, lineHeight: lineHeight, rect: rect)
            resolved = selectedBounds.map { rect.insetBy(dx: -0.5, dy: -0.5).contains($0) } ?? true
        }

        return MangaOverlayRenderTextPlan(
            fontSize: fontSize,
            lineHeight: fontSize * 1.18,
            lines: selectedLines,
            initialOverflow: initialOverflow,
            minFontSizeReached: minReached,
            textTruncated: truncated,
            nonTransparentBounds: selectedBounds?.offsetBy(dx: -rect.minX, dy: -rect.minY),
            resolved: resolved
        )
    }

    private static func renderedTextBounds(
        lines: [String],
        fontSize: CGFloat,
        lineHeight: CGFloat,
        rect: CGRect
    ) -> CGRect? {
        guard !lines.isEmpty else { return nil }
        let width = max(1, Int(ceil(rect.width)))
        let height = max(1, Int(ceil(max(rect.height, CGFloat(lines.count) * lineHeight))))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        UIGraphicsPushContext(context)
        drawLines(
            lines,
            in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
            fontSize: fontSize,
            lineHeight: lineHeight,
            context: context
        )
        UIGraphicsPopContext()

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                guard alpha > 0 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: rect.minX + CGFloat(minX),
            y: rect.minY + CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }

    private static func drawLines(
        _ lines: [String],
        in rect: CGRect,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        context: CGContext
    ) {
        let totalHeight = CGFloat(lines.count) * lineHeight
        var y = rect.minY + max(0, (rect.height - totalHeight) / 2)
        for line in lines {
            drawText(
                line,
                in: CGRect(x: rect.minX, y: y, width: rect.width, height: lineHeight),
                fontSize: fontSize,
                textColor: CGColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1),
                backgroundColor: nil,
                context: context
            )
            y += lineHeight
        }
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        textColor: CGColor,
        backgroundColor: CGColor?,
        context: CGContext
    ) {
        if let backgroundColor {
            context.setFillColor(backgroundColor)
            context.fill(rect)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor(cgColor: textColor)
        ]
        (text as NSString).draw(in: rect.insetBy(dx: 3, dy: 0), withAttributes: attributes)
    }

    private static func wrappedLines(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in text {
            let candidate = current.isEmpty ? String(character) : current + String(character)
            if estimatedTextWidth(candidate, fontSize: fontSize) <= maxWidth || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(character)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func estimatedTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        text.reduce(0) { width, character in
            let scalar = String(character).unicodeScalars.first?.value ?? 0
            let isASCII = scalar < 128
            return width + fontSize * (isASCII ? 0.58 : 1.02)
        }
    }

    private static func sampleBackgroundColor(image: CGImage, near rect: CGRect) -> CGColor {
        guard let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData),
              image.bitsPerPixel == 32 else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 0.94)
        }

        let bytesPerRow = image.bytesPerRow
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let ring = expand(rect, by: 0.24, bounds: bounds)
        var samples: [(Int, Int, Int)] = []
        let step = max(1, Int(min(ring.width, ring.height) / 12))
        for y in stride(from: Int(ring.minY), through: Int(ring.maxY), by: step) {
            for x in stride(from: Int(ring.minX), through: Int(ring.maxX), by: step) {
                guard !rect.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))), x >= 0, y >= 0, x < image.width, y < image.height else { continue }
                let offset = y * bytesPerRow + x * 4
                samples.append((Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])))
            }
        }

        guard !samples.isEmpty else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 0.94)
        }
        let sorted = samples.sorted { lhs, rhs in
            lhs.0 + lhs.1 + lhs.2 > rhs.0 + rhs.1 + rhs.2
        }
        let picked = sorted[min(sorted.count - 1, max(0, sorted.count / 6))]
        return CGColor(
            red: Double(picked.0) / 255,
            green: Double(picked.1) / 255,
            blue: Double(picked.2) / 255,
            alpha: 0.96
        )
    }

    private static func makeGlyphMaskPlan(
        image: CGImage,
        blockRect: CGRect,
        bubbleRect: CGRect?
    ) -> MangaOverlayGlyphMaskPlan? {
        guard let bubbleRect else { return nil }
        guard let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData),
              image.bitsPerPixel == 32 else {
            return nil
        }

        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let bubbleBounds = clamp(bubbleRect.integral, to: imageBounds)
        let ocrBounds = clamp(expand(blockRect, by: 0.08, bounds: imageBounds).integral, to: bubbleBounds)
        guard bubbleBounds.width >= 4, bubbleBounds.height >= 4, ocrBounds.width >= 2, ocrBounds.height >= 2 else {
            return nil
        }

        let width = Int(bubbleBounds.width)
        let height = Int(bubbleBounds.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = image.bytesPerRow
        var gray = [UInt8](repeating: 255, count: width * height)
        for localY in 0..<height {
            let y = Int(bubbleBounds.minY) + localY
            for localX in 0..<width {
                let x = Int(bubbleBounds.minX) + localX
                guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
                let offset = y * bytesPerRow + x * 4
                let red = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let blue = Double(bytes[offset + 2])
                gray[localY * width + localX] = UInt8(max(0, min(255, (0.299 * red + 0.587 * green + 0.114 * blue).rounded())))
            }
        }

        let integralWidth = width + 1
        var integral = [Int](repeating: 0, count: integralWidth * (height + 1))
        for y in 0..<height {
            var rowSum = 0
            for x in 0..<width {
                rowSum += Int(gray[y * width + x])
                integral[(y + 1) * integralWidth + x + 1] = integral[y * integralWidth + x + 1] + rowSum
            }
        }

        var foreground = [Bool](repeating: false, count: width * height)
        let radius = max(4, min(12, Int(min(bubbleBounds.width, bubbleBounds.height) / 6)))
        for y in 0..<height {
            for x in 0..<width {
                let minY = max(0, y - radius)
                let maxY = min(height - 1, y + radius)
                let minX = max(0, x - radius)
                let maxX = min(width - 1, x + radius)
                let sum = integral[(maxY + 1) * integralWidth + maxX + 1]
                    - integral[minY * integralWidth + maxX + 1]
                    - integral[(maxY + 1) * integralWidth + minX]
                    + integral[minY * integralWidth + minX]
                let count = (maxY - minY + 1) * (maxX - minX + 1)
                let localMean = count > 0 ? Double(sum) / Double(count) : 255
                let value = Double(gray[y * width + x])
                foreground[y * width + x] = value < localMean - 22 && value < 205
            }
        }

        let minComponentArea = max(3, Int(min(blockRect.width, blockRect.height) * 0.08))
        let maxComponentArea = max(minComponentArea + 1, Int(bubbleBounds.width * bubbleBounds.height * 0.18))
        let ocrLocalRect = ocrBounds.offsetBy(dx: -bubbleBounds.minX, dy: -bubbleBounds.minY)
        var visited = [Bool](repeating: false, count: width * height)
        var acceptedOffsets = Set<Int>()

        for startY in 0..<height {
            for startX in 0..<width {
                let startOffset = startY * width + startX
                guard foreground[startOffset], !visited[startOffset] else { continue }

                var queue = [startOffset]
                visited[startOffset] = true
                var cursor = 0
                var component: [Int] = []
                var minX = startX
                var maxX = startX
                var minY = startY
                var maxY = startY
                while cursor < queue.count {
                    let offset = queue[cursor]
                    cursor += 1
                    component.append(offset)
                    let y = offset / width
                    let x = offset % width
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    for neighbor in glyphNeighborOffsets(x: x, y: y, width: width, height: height) {
                        if foreground[neighbor], !visited[neighbor] {
                            visited[neighbor] = true
                            queue.append(neighbor)
                        }
                    }
                }

                let area = component.count
                guard area >= minComponentArea, area <= maxComponentArea else { continue }
                let componentRect = CGRect(
                    x: CGFloat(minX),
                    y: CGFloat(minY),
                    width: CGFloat(maxX - minX + 1),
                    height: CGFloat(maxY - minY + 1)
                )
                guard componentRect.intersects(ocrLocalRect) else { continue }

                let longSide = max(componentRect.width, componentRect.height)
                let shortSide = max(1, min(componentRect.width, componentRect.height))
                guard longSide / shortSide <= 16 else { continue }
                acceptedOffsets.formUnion(component)
            }
        }

        guard !acceptedOffsets.isEmpty else { return nil }
        let dilatedOffsets = dilateGlyphOffsets(
            acceptedOffsets,
            width: width,
            height: height,
            radius: 2
        )
        let fillRects = glyphFillRects(
            offsets: dilatedOffsets,
            width: width,
            origin: bubbleBounds.origin,
            maxRects: 5_000
        )
        let background = glyphBackgroundEstimate(
            image: image,
            bytes: bytes,
            bubbleBounds: bubbleBounds,
            excludedOffsets: dilatedOffsets
        )
        let stdDevThreshold = 45.0
        return MangaOverlayGlyphMaskPlan(
            maskRect: boundingRect(for: dilatedOffsets, width: width).offsetBy(dx: bubbleBounds.minX, dy: bubbleBounds.minY),
            dilatedPixelOffsets: dilatedOffsets,
            pixelCount: dilatedOffsets.count,
            fillRects: fillRects,
            backgroundColor: background?.color,
            backgroundStdDev: background?.stdDev,
            backgroundFillApplied: (background?.stdDev ?? .greatestFiniteMagnitude) <= stdDevThreshold
        )
    }

    private static func glyphNeighborOffsets(x: Int, y: Int, width: Int, height: Int) -> [Int] {
        var offsets: [Int] = []
        if x > 0 { offsets.append(y * width + x - 1) }
        if x + 1 < width { offsets.append(y * width + x + 1) }
        if y > 0 { offsets.append((y - 1) * width + x) }
        if y + 1 < height { offsets.append((y + 1) * width + x) }
        return offsets
    }

    private static func dilateGlyphOffsets(
        _ offsets: Set<Int>,
        width: Int,
        height: Int,
        radius: Int
    ) -> Set<Int> {
        var result = offsets
        for offset in offsets {
            let y = offset / width
            let x = offset % width
            for dy in -radius...radius {
                for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                    let nx = x + dx
                    let ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height {
                        result.insert(ny * width + nx)
                    }
                }
            }
        }
        return result
    }

    private static func boundingRect(for offsets: Set<Int>, width: Int) -> CGRect {
        guard let first = offsets.first else { return .zero }
        var minX = first % width
        var maxX = minX
        var minY = first / width
        var maxY = minY
        for offset in offsets {
            let y = offset / width
            let x = offset % width
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func glyphFillRects(
        offsets: Set<Int>,
        width: Int,
        origin: CGPoint,
        maxRects: Int
    ) -> [[Double]] {
        let groupedByY = Dictionary(grouping: offsets) { $0 / width }
        var rects: [[Double]] = []
        for y in groupedByY.keys.sorted() {
            let xs = groupedByY[y, default: []].map { $0 % width }.sorted()
            guard var runStart = xs.first else { continue }
            var previous = runStart
            for x in xs.dropFirst() {
                if x == previous + 1 {
                    previous = x
                    continue
                }
                rects.append([
                    Double(origin.x + CGFloat(runStart)),
                    Double(origin.y + CGFloat(y)),
                    Double(previous - runStart + 1),
                    1
                ])
                runStart = x
                previous = x
            }
            rects.append([
                Double(origin.x + CGFloat(runStart)),
                Double(origin.y + CGFloat(y)),
                Double(previous - runStart + 1),
                1
            ])
        }
        if rects.count <= maxRects {
            return rects
        }
        let bucket = Int(ceil(Double(rects.count) / Double(maxRects)))
        return stride(from: 0, to: rects.count, by: bucket).map { start in
            let slice = rects[start..<min(rects.count, start + bucket)]
            let minX = slice.map { $0[0] }.min() ?? 0
            let minY = slice.map { $0[1] }.min() ?? 0
            let maxX = slice.map { $0[0] + $0[2] }.max() ?? minX
            let maxY = slice.map { $0[1] + $0[3] }.max() ?? minY
            return [minX, minY, maxX - minX, maxY - minY]
        }
    }

    private static func glyphBackgroundEstimate(
        image: CGImage,
        bytes: UnsafePointer<UInt8>,
        bubbleBounds: CGRect,
        excludedOffsets: Set<Int>
    ) -> (color: [Double], stdDev: Double)? {
        let width = Int(bubbleBounds.width)
        let height = Int(bubbleBounds.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = image.bytesPerRow
        var redValues: [Int] = []
        var greenValues: [Int] = []
        var blueValues: [Int] = []
        var sampleOffsets = Set<Int>()
        for glyphOffset in excludedOffsets {
            let glyphY = glyphOffset / width
            let glyphX = glyphOffset % width
            for dy in -7...7 {
                for dx in -7...7 {
                    let distanceSquared = dx * dx + dy * dy
                    guard distanceSquared >= 16, distanceSquared <= 49 else { continue }
                    let nx = glyphX + dx
                    let ny = glyphY + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let offset = ny * width + nx
                    if !excludedOffsets.contains(offset) {
                        sampleOffsets.insert(offset)
                    }
                }
            }
        }

        let maxSamples = 1800
        let orderedOffsets: [Int]
        if sampleOffsets.count > maxSamples {
            let sorted = sampleOffsets.sorted()
            let strideSize = max(1, sorted.count / maxSamples)
            orderedOffsets = stride(from: 0, to: sorted.count, by: strideSize).map { sorted[$0] }
        } else {
            orderedOffsets = Array(sampleOffsets)
        }

        for localOffset in orderedOffsets {
            let localY = localOffset / width
            let localX = localOffset % width
            let y = Int(bubbleBounds.minY) + localY
            let x = Int(bubbleBounds.minX) + localX
            guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
            let offset = y * bytesPerRow + x * 4
            redValues.append(Int(bytes[offset]))
            greenValues.append(Int(bytes[offset + 1]))
            blueValues.append(Int(bytes[offset + 2]))
        }
        guard redValues.count >= 12 else { return nil }
        let medians = [
            median(redValues),
            median(greenValues),
            median(blueValues)
        ]
        var squaredError = 0.0
        let count = redValues.count
        for index in 0..<count {
            squaredError += pow(Double(redValues[index]) - medians[0], 2)
            squaredError += pow(Double(greenValues[index]) - medians[1], 2)
            squaredError += pow(Double(blueValues[index]) - medians[2], 2)
        }
        let stdDev = sqrt(squaredError / Double(count * 3))
        return (
            color: medians.map { max(0, min(1, $0 / 255)) },
            stdDev: stdDev
        )
    }

    private static func median(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[middle - 1] + sorted[middle]) / 2
        }
        return Double(sorted[middle])
    }

    private static func rect(from bbox: [Double]) -> CGRect {
        guard bbox.count == 4 else { return .zero }
        return CGRect(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3]).standardized
    }

    private static func bboxArray(from rect: CGRect) -> [Double] {
        [
            Double(rect.minX.rounded()),
            Double(rect.minY.rounded()),
            Double(rect.width.rounded()),
            Double(rect.height.rounded())
        ]
    }

    private static func rectContainmentRatio(inner: CGRect, outer: CGRect) -> Double {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull, inner.width > 0, inner.height > 0 else { return 0 }
        return Double((intersection.width * intersection.height) / max(1, inner.width * inner.height))
    }

    private static func expand(_ rect: CGRect, by fraction: Double, bounds: CGRect) -> CGRect {
        let dx = max(5, rect.width * fraction)
        let dy = max(5, rect.height * fraction)
        return clamp(rect.insetBy(dx: -dx, dy: -dy), to: bounds)
    }

    private static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let minX = max(bounds.minX, rect.minX)
        let minY = max(bounds.minY, rect.minY)
        let maxX = min(bounds.maxX, rect.maxX)
        let maxY = min(bounds.maxY, rect.maxY)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw MangaOverlayProbeServiceError.pngEncodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MangaOverlayProbeServiceError.pngEncodeFailed
        }
    }

    private static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lettersOrNumbers = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let letters = trimmed.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }
        return trimmed.count <= 1 && lettersOrNumbers.isEmpty
            || lettersOrNumbers.isEmpty
            || letters.count < 2
            || trimmed.localizedCaseInsensitiveContains("nhentai.net")
            || trimmed.localizedCaseInsensitiveContains("of 36")
            || trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
    }

    private static func isBrowserChrome(_ rect: CGRect, imageHeight: CGFloat) -> Bool {
        rect.minY < 160 || rect.maxY > imageHeight - 95
    }
}
