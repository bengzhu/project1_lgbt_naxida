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
        let result = try await recognizeExternalTextBoxCrop(
            in: image,
            textBoxBBox: textBoxBBox,
            options: options,
            rotationAngle: 0
        )
        return (result.text, result.cropBBox, result.paddingX, result.paddingY)
    }

    func recognizeExternalTextBoxCrop(
        in image: CGImage,
        textBoxBBox: [Double],
        options: MangaOverlayPreprocessingOptions = .defaultValue,
        rotationAngle: Int,
        recognitionLanguages: [String]? = nil
    ) async throws -> (text: String?, cropBBox: [Double], paddingX: Double, paddingY: Double, rotationApplied: Double) {
        try await Task.detached(priority: .userInitiated) {
            let bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let seedRect = Self.clamp(Self.rect(from: textBoxBBox), to: bounds).integral
            let normalizedRotation = [0, 90, 180, 270].contains(rotationAngle) ? rotationAngle : 0
            guard seedRect.width >= 2, seedRect.height >= 2 else {
                return (nil, Self.bboxArray(from: seedRect), 0, 0, Double(normalizedRotation))
            }
            let padding = Self.adaptiveCropPadding(for: seedRect)
            let cropRect = Self.clamp(
                seedRect.insetBy(dx: -padding.x, dy: -padding.y),
                to: bounds
            ).integral
            let text = try Self.recognizePreprocessedText(
                in: image,
                cropRect: cropRect,
                options: options,
                rotationAngle: normalizedRotation,
                recognitionLanguages: recognitionLanguages
            )
            return (text, Self.bboxArray(from: cropRect), Double(padding.x), Double(padding.y), Double(normalizedRotation))
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
        options: MangaOverlayPreprocessingOptions,
        rotationAngle: Int = 0,
        recognitionLanguages: [String]? = nil
    ) throws -> String? {
        guard cropRect.width >= 2, cropRect.height >= 2 else { return nil }
        let cropped = try croppedImage(image, rect: cropRect)
        let prepared = try preprocessedImage(cropped, options: options)
        let normalizedRotation = [0, 90, 180, 270].contains(rotationAngle) ? rotationAngle : 0
        let rotated = try rotatedImage(prepared, angle: normalizedRotation)
        let candidates = try recognizeTextCandidates(
            in: rotated,
            angle: 0,
            scaledContentSize: CGSize(width: CGFloat(rotated.width), height: CGFloat(rotated.height)),
            contentOrigin: .zero,
            scale: 1,
            customWords: [],
            recognitionLanguages: recognitionLanguages
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
        koharuDistanceFieldSafeAreaReport: MangaKoharuDistanceFieldSafeAreaReport? = nil,
        koharuBubbleAdjacencySeamReport: MangaKoharuBubbleAdjacencySeamReport? = nil,
        koharuRenderSpriteFitPlannerReport: MangaKoharuRenderSpriteFitPlannerReport? = nil,
        koharuNativeTextBoxDetectorLiteReport: MangaKoharuNativeTextBoxDetectorLiteReport? = nil,
        koharuNativeTextBoxDetectorLiteShadowOCRReport: MangaKoharuNativeTextBoxDetectorLiteShadowOCRReport? = nil,
        koharuNativeTextBoxDetectorLiteRefinementReport: MangaKoharuNativeTextBoxDetectorLiteRefinementReport? = nil,
        koharuNativeTextBoxDetectorLiteClosedLoopReport: MangaKoharuNativeTextBoxDetectorLiteClosedLoopReport? = nil,
        koharuNativeBubbleMaskInstanceLiteReport: MangaKoharuNativeBubbleMaskInstanceLiteReport? = nil,
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
            let imageBitmap = Self.makeRGBA8Bitmap(from: image)
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
                    bitmap: imageBitmap,
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

    func makeKoharuNativeBubbleMaskInstanceLiteReport(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?,
        bubbleAssignmentCorrectionReport: MangaOverlayBubbleAssignmentCorrectionReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        koharuDistanceFieldSafeAreaReport: MangaKoharuDistanceFieldSafeAreaReport?,
        koharuBubbleAdjacencySeamReport: MangaKoharuBubbleAdjacencySeamReport?,
        koharuRenderSpriteFitPlannerReport: MangaKoharuRenderSpriteFitPlannerReport?,
        koharuNativeTextBoxDetectorLiteClosedLoopReport: MangaKoharuNativeTextBoxDetectorLiteClosedLoopReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?
    ) async -> MangaKoharuNativeBubbleMaskInstanceLiteReport {
        await Task.detached(priority: .userInitiated) {
            func uniqueSorted(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }
            func countBy(_ values: [String]) -> [String: Int] {
                values.reduce(into: [:]) { partial, value in partial[value, default: 0] += 1 }
            }
            func formatted(_ value: Double?) -> String {
                value?.formatted(.number.precision(.fractionLength(4))) ?? "nil"
            }
            func area(_ rect: CGRect) -> Double {
                Double(max(0, rect.width) * max(0, rect.height))
            }
            func iou(_ lhs: CGRect, _ rhs: CGRect) -> Double {
                let intersection = lhs.intersection(rhs)
                guard !intersection.isNull else { return 0 }
                return area(intersection) / max(1, area(lhs) + area(rhs) - area(intersection))
            }
            func gap(_ lhs: CGRect, _ rhs: CGRect) -> Double {
                if lhs.intersects(rhs) { return 0 }
                let dx = max(max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX), 0)
                let dy = max(max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY), 0)
                return Double(sqrt(dx * dx + dy * dy))
            }
            func signal(
                _ name: String,
                _ value: String,
                source: String,
                decision: Bool = true,
                evaluation: Bool = false
            ) -> MangaKoharuNativeBubbleMaskInstanceLiteSignal {
                MangaKoharuNativeBubbleMaskInstanceLiteSignal(
                    name: name,
                    value: value,
                    sourceReport: source,
                    groundTruthFreeDecisionSignal: decision,
                    groundTruthUsedForEvaluationOnly: evaluation
                )
            }
            func gate(
                _ id: String,
                _ name: String,
                _ scope: String,
                _ status: String,
                _ threshold: String,
                _ affected: [Int],
                _ failure: String,
                _ action: String,
                _ signals: [MangaKoharuNativeBubbleMaskInstanceLiteSignal]
            ) -> MangaKoharuNativeBubbleMaskInstanceLiteGate {
                MangaKoharuNativeBubbleMaskInstanceLiteGate(
                    gateID: id,
                    gateName: name,
                    scope: scope,
                    status: status,
                    threshold: threshold,
                    affectedBlocks: uniqueSorted(affected),
                    decisionSignals: signals,
                    failureMeans: failure,
                    recommendedAction: action,
                    groundTruthUsedForDecision: false
                )
            }
            func makeEmptyBlockLedger(
                for block: MangaOverlayProbeBlock,
                reason: String,
                nextAction: String
            ) -> MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger {
                MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger(
                    blockIndex: block.index,
                    currentBubbleID: block.bubbleID,
                    instanceLiteMajorityID: nil,
                    instanceLiteMajorityPixelCount: 0,
                    instanceLiteMajorityCoverage: 0,
                    instanceLiteSecondaryIDs: [:],
                    assignmentAgreement: "outsideAcceptedInstances",
                    assignmentConflictReason: reason,
                    bbox: block.bbox,
                    seedRect: block.bbox,
                    currentSafeLayoutRect: block.safeLayoutRect,
                    instanceLiteSafeRect: nil,
                    instanceLiteBlockScopedSafeRect: nil,
                    instanceLiteSafeRectPolicy: "missingInstanceLiteSafeRect",
                    distanceFieldSafeRectFromInstanceLite: nil,
                    distanceFieldSafeRectSource: "nativeBubbleMaskInstanceLite",
                    currentRenderNonTransparentBounds: block.renderNonTransparentBounds,
                    spriteContainedByInstanceLiteMask: false,
                    spriteBlockScopedSafeRectContainmentRatio: 0,
                    spriteContainedByBlockScopedSafeRect: false,
                    spriteContainmentPolicy: "missingBlockScopedSafeRect",
                    sameInstanceRenderSpriteOverlapCount: 0,
                    spriteSiblingCollisionPolicy: "missingInstanceLiteSiblings",
                    siblingPartitionStatus: "manualReviewOnly",
                    splitRisk: "manualReviewOnly",
                    adjacencyRisk: "manualReviewOnly",
                    segmentGlyphEvidenceStatus: "unknown",
                    translationFailureCategory: block.failureCategory,
                    translationFailureRoute: block.blockPassed ? "translationPassed" : block.failureCategory,
                    detectorLiteClosedLoopRoute: nil,
                    renderLockStatus: block.renderCollisionResolved ? "renderCollisionResolved" : "renderLockOpen",
                    primaryBottleneck: "bubbleMaskInstanceMissing",
                    nextAction: nextAction,
                    decisionSignals: [
                        signal("instanceLiteMajorityID", "nil", source: "koharuNativeBubbleMaskInstanceLiteReport"),
                        signal("blockedReason", reason, source: "koharuNativeBubbleMaskInstanceLiteReport")
                    ],
                    evaluationSignals: [
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks", decision: false, evaluation: true),
                        signal("ocrGroundTruthSimilarity", formatted(block.ocrGroundTruthSimilarity), source: "blocks", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }

            let allBlockIndexes = blocks.map(\.index)
            let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let contentCrop = Self.contentCropRect(for: image, cropping: .defaultValue).integral
            let contentBBox = Self.bboxArray(from: Self.clamp(contentCrop, to: imageBounds))
            guard let bitmap = Self.makeRGBA8Bitmap(from: image) else {
                let ledgers = blocks.map {
                    makeEmptyBlockLedger(for: $0, reason: "sourceImageBytesUnavailable", nextAction: "restoreProbeImageByteAccess")
                }
                let gates = [
                    gate("G-native-bubblemask-instance-lite-image-bytes", "Image bytes available", "SourceImage", "blocked", "32-bit CGImage provider bytes readable", allBlockIndexes, "instance-lite mask cannot inspect source pixels", "restoreProbeImageByteAccess", [signal("imageBytesAvailable", "false", source: "SourceImage")]),
                    gate("G-native-bubblemask-instance-lite-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "instance-lite mask mutates OCR, translation, safeLayoutRect, renderer, blockPassed, or currentBlockSource", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuNativeBubbleMaskInstanceLiteReport")])
                ]
                return MangaKoharuNativeBubbleMaskInstanceLiteReport(
                    enabled: true,
                    source: "AITRANSProbe",
                    referencePipeline: "Koharu",
                    referenceConcept: "BubbleMask.NativeInstanceLite.PixelIDMask",
                    referenceWorkItemID: "WI-koharu-native-bubblemask-instance-lite",
                    evaluatedBlockCount: blocks.count,
                    sourceImageWidth: image.width,
                    sourceImageHeight: image.height,
                    contentCropBBox: contentBBox,
                    instanceCount: 0,
                    blockLedgerCount: ledgers.count,
                    siblingLedgerCount: 0,
                    adjacencyLedgerCount: 0,
                    gateCount: gates.count,
                    groundTruthUsedForDecision: false,
                    groundTruthUsedForEvaluationOnly: true,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true,
                    nativeInstanceLite: true,
                    proxyNotRealKoharuBubbleMask: true,
                    usesSourceImagePixels: true,
                    externalArtifactsRequiredForThisReport: false,
                    instanceLiteVerdict: "blockedByInsufficientPixelEvidence",
                    instanceQualityBreakdown: [:],
                    assignmentAgreementBreakdown: countBy(ledgers.map(\.assignmentAgreement)),
                    splitRiskBreakdown: countBy(ledgers.map(\.splitRisk)),
                    siblingPartitionBreakdown: countBy(ledgers.map(\.siblingPartitionStatus)),
                    safeRectComparisonBreakdown: [:],
                    safeRectPolicyBreakdown: countBy(ledgers.map(\.instanceLiteSafeRectPolicy)),
                    spriteContainmentBreakdown: countBy(ledgers.map { $0.spriteContainedByInstanceLiteMask ? "contained" : "notContained" }),
                    spriteBlockScopedContainmentBreakdown: countBy(ledgers.map(\.spriteContainmentPolicy)),
                    spriteSiblingCollisionBreakdown: countBy(ledgers.map(\.spriteSiblingCollisionPolicy)),
                    adjacencyRiskBreakdown: countBy(ledgers.map(\.adjacencyRisk)),
                    primaryBottleneckBreakdown: countBy(ledgers.map(\.primaryBottleneck)),
                    nextActionBreakdown: countBy(ledgers.map(\.nextAction)),
                    needsRealBubbleMaskBlocks: allBlockIndexes,
                    needsRealSegmentMaskBlocks: [],
                    needsRealTextBoxesBlocks: [],
                    manualReviewBlocks: allBlockIndexes,
                    renderLockedBlocks: blocks.filter(\.renderCollisionResolved).map(\.index),
                    instances: [],
                    blockLedgers: ledgers,
                    siblingLedgers: [],
                    adjacencyLedgers: [],
                    gateLedger: gates,
                    notes: ["Source image pixels were unavailable; native BubbleMask instance-lite emitted blocked ledger only."]
                )
            }

            let bytes = bitmap.pixels
            let bytesPerRow = bitmap.bytesPerRow
            let cropRect = Self.clamp(contentCrop, to: imageBounds)
            let minX = max(0, Int(cropRect.minX.rounded(.down)))
            let maxX = min(image.width, Int(cropRect.maxX.rounded(.up)))
            let minY = max(0, Int(cropRect.minY.rounded(.down)))
            let maxY = min(image.height, Int(cropRect.maxY.rounded(.up)))
            let cropWidth = max(0, maxX - minX)
            let cropHeight = max(0, maxY - minY)
            var candidatePixels = [Bool](repeating: false, count: cropWidth * cropHeight)
            if cropWidth > 0, cropHeight > 0 {
                for localY in 0..<cropHeight {
                    let y = minY + localY
                    for localX in 0..<cropWidth {
                        let x = minX + localX
                        let offset = y * bytesPerRow + x * 4
                        guard offset + 2 < bytes.count else { continue }
                        let r = Int(bytes[offset])
                        let g = Int(bytes[offset + 1])
                        let b = Int(bytes[offset + 2])
                        let maxChannel = max(r, g, b)
                        let minChannel = min(r, g, b)
                        let luminance = (r * 299 + g * 587 + b * 114) / 1000
                        candidatePixels[localY * cropWidth + localX] = luminance >= 222 && (maxChannel - minChannel) <= 42
                    }
                }
            }

            let bubbleRects = bubbleGeometry.bubbles.map { bubble in
                (bubble: bubble, rect: Self.clamp(Self.rect(from: bubble.bbox), to: imageBounds))
            }
            let segmentByBlock = Dictionary(
                uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
            )
            let maskByBlock = Dictionary(
                uniqueKeysWithValues: (bubbleMaskReport?.blockDiagnostics ?? []).map { ($0.blockIndex, $0) }
            )
            var splitByBlock: [Int: [Int]] = [:]
            for diagnostic in bubbleSplitCandidateReport?.diagnostics ?? [] {
                for blockIndex in diagnostic.seedBlockIndexes {
                    splitByBlock[blockIndex, default: []].append(diagnostic.id)
                }
            }
            let seamByBlock = Dictionary(
                uniqueKeysWithValues: (koharuBubbleAdjacencySeamReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
            )
            let renderFitByBlock = Dictionary(
                uniqueKeysWithValues: (koharuRenderSpriteFitPlannerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
            )
            let closedLoopByBlock = Dictionary(
                uniqueKeysWithValues: (koharuNativeTextBoxDetectorLiteClosedLoopReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
            )
            let renderLockByBlock = Dictionary(
                uniqueKeysWithValues: (koharuRenderRegressionLockReport?.blockLocks ?? []).map { ($0.blockIndex, $0) }
            )

            var visited = [Bool](repeating: false, count: candidatePixels.count)
            struct PixelComponent {
                var bbox: CGRect
                var pixelOffsets: Set<Int>
                var pixelCount: Int
                var rejectionReasons: [String]
                var matchedBubbleID: Int?
                var matchedIoU: Double?
            }
            var components: [PixelComponent] = []
            let minArea = 180
            let maxArea = max(1_000, Int(Double(cropWidth * cropHeight) * 0.22))
            for startY in 0..<cropHeight {
                for startX in 0..<cropWidth {
                    let start = startY * cropWidth + startX
                    guard candidatePixels.indices.contains(start), candidatePixels[start], !visited[start] else { continue }
                    var queue = [start]
                    var cursor = 0
                    visited[start] = true
                    var offsets = Set<Int>()
                    var localMinX = startX
                    var localMaxX = startX
                    var localMinY = startY
                    var localMaxY = startY
                    while cursor < queue.count {
                        let current = queue[cursor]
                        cursor += 1
                        let cy = current / cropWidth
                        let cx = current % cropWidth
                        let globalX = minX + cx
                        let globalY = minY + cy
                        offsets.insert(globalY * image.width + globalX)
                        localMinX = min(localMinX, cx)
                        localMaxX = max(localMaxX, cx)
                        localMinY = min(localMinY, cy)
                        localMaxY = max(localMaxY, cy)
                        let neighbors = [
                            (cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)
                        ]
                        for (nx, ny) in neighbors where nx >= 0 && ny >= 0 && nx < cropWidth && ny < cropHeight {
                            let next = ny * cropWidth + nx
                            if candidatePixels[next], !visited[next] {
                                visited[next] = true
                                queue.append(next)
                            }
                        }
                    }
                    let rect = CGRect(
                        x: minX + localMinX,
                        y: minY + localMinY,
                        width: localMaxX - localMinX + 1,
                        height: localMaxY - localMinY + 1
                    ).integral
                    let pixelCount = offsets.count
                    var rejectionReasons: [String] = []
                    if pixelCount < minArea { rejectionReasons.append("tooSmall") }
                    if pixelCount > maxArea { rejectionReasons.append("tooLargeOrPanelBackground") }
                    if rect.width < 10 || rect.height < 10 { rejectionReasons.append("bboxTooSmall") }
                    let bboxArea = max(1, Int((rect.width * rect.height).rounded()))
                    let fillRatio = Double(pixelCount) / Double(bboxArea)
                    if fillRatio < 0.18 { rejectionReasons.append("lowFillRatio") }
                    let bestBubble = bubbleRects.max { lhs, rhs in
                        iou(rect, lhs.rect) < iou(rect, rhs.rect)
                    }
                    let bestIoU = bestBubble.map { iou(rect, $0.rect) } ?? 0
                    let containsBlock = blocks.contains { block in
                        rect.intersects(Self.rect(from: block.bbox))
                    }
                    if bestIoU < 0.03 && !containsBlock {
                        rejectionReasons.append("notNearTextOrBubbleGeometry")
                    }
                    if !rejectionReasons.contains("tooSmall") {
                        components.append(
                            PixelComponent(
                                bbox: rect,
                                pixelOffsets: offsets,
                                pixelCount: pixelCount,
                                rejectionReasons: rejectionReasons,
                                matchedBubbleID: bestBubble?.bubble.id,
                                matchedIoU: bestIoU
                            )
                        )
                    }
                }
            }

            let acceptedComponents = components
                .filter { component in
                    !component.rejectionReasons.contains("tooLargeOrPanelBackground")
                        && !component.rejectionReasons.contains("notNearTextOrBubbleGeometry")
                        && !component.rejectionReasons.contains("bboxTooSmall")
                }
                .sorted { lhs, rhs in
                    if abs(lhs.bbox.minY - rhs.bbox.minY) > 4 { return lhs.bbox.minY < rhs.bbox.minY }
                    return lhs.bbox.minX < rhs.bbox.minX
                }

            var pixelOffsetsByInstanceID: [Int: Set<Int>] = [:]
            var instanceRectsByID: [Int: CGRect] = [:]
            var sourceBubbleByInstanceID: [Int: Int?] = [:]
            for (offset, component) in acceptedComponents.enumerated() {
                let id = offset + 1
                pixelOffsetsByInstanceID[id] = component.pixelOffsets
                instanceRectsByID[id] = component.bbox
                sourceBubbleByInstanceID[id] = component.matchedBubbleID
            }

            func majority(in rect: CGRect) -> (id: Int?, count: Int, coverage: Double, secondary: [String: Int]) {
                let clamped = Self.clamp(rect.integral, to: imageBounds)
                let x0 = max(0, Int(clamped.minX.rounded(.down)))
                let x1 = min(image.width, Int(clamped.maxX.rounded(.up)))
                let y0 = max(0, Int(clamped.minY.rounded(.down)))
                let y1 = min(image.height, Int(clamped.maxY.rounded(.up)))
                guard x0 < x1, y0 < y1 else { return (nil, 0, 0, [:]) }
                var counts: [Int: Int] = [:]
                var total = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        total += 1
                        let key = y * image.width + x
                        for (id, offsets) in pixelOffsetsByInstanceID where offsets.contains(key) {
                            counts[id, default: 0] += 1
                            break
                        }
                    }
                }
                let secondary = Dictionary(uniqueKeysWithValues: counts.map { (String($0.key), $0.value) })
                guard let winner = counts.max(by: { $0.value < $1.value }) else {
                    return (nil, 0, 0, secondary)
                }
                return (winner.key, winner.value, Double(winner.value) / Double(max(1, total)), secondary)
            }

            func pixelCoverage(of rect: CGRect, instanceID: Int?) -> Double {
                guard let instanceID, let offsets = pixelOffsetsByInstanceID[instanceID] else { return 0 }
                let clamped = Self.clamp(rect.integral, to: imageBounds)
                let x0 = max(0, Int(clamped.minX.rounded(.down)))
                let x1 = min(image.width, Int(clamped.maxX.rounded(.up)))
                let y0 = max(0, Int(clamped.minY.rounded(.down)))
                let y1 = min(image.height, Int(clamped.maxY.rounded(.up)))
                guard x0 < x1, y0 < y1 else { return 0 }
                var covered = 0
                var total = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        total += 1
                        if offsets.contains(y * image.width + x) { covered += 1 }
                    }
                }
                return Double(covered) / Double(max(1, total))
            }

            func maskDerivedSafeRect(for instanceID: Int?) -> CGRect? {
                guard let instanceID,
                      let offsets = pixelOffsetsByInstanceID[instanceID],
                      let instanceRect = instanceRectsByID[instanceID],
                      !offsets.isEmpty else { return nil }
                let clamped = Self.clamp(instanceRect.integral, to: imageBounds)
                let x0 = max(0, Int(clamped.minX.rounded(.down)))
                let x1 = min(image.width, Int(clamped.maxX.rounded(.up)))
                let y0 = max(0, Int(clamped.minY.rounded(.down)))
                let y1 = min(image.height, Int(clamped.maxY.rounded(.up)))
                guard x0 < x1, y0 < y1 else { return nil }

                var rowRuns: [Int: (minX: Int, maxX: Int, count: Int)] = [:]
                var columnRuns: [Int: (minY: Int, maxY: Int, count: Int)] = [:]
                for offset in offsets {
                    let y = offset / image.width
                    let x = offset % image.width
                    guard x >= x0, x < x1, y >= y0, y < y1 else { continue }
                    if var row = rowRuns[y] {
                        row.minX = min(row.minX, x)
                        row.maxX = max(row.maxX, x)
                        row.count += 1
                        rowRuns[y] = row
                    } else {
                        rowRuns[y] = (x, x, 1)
                    }
                    if var column = columnRuns[x] {
                        column.minY = min(column.minY, y)
                        column.maxY = max(column.maxY, y)
                        column.count += 1
                        columnRuns[x] = column
                    } else {
                        columnRuns[x] = (y, y, 1)
                    }
                }
                guard !rowRuns.isEmpty, !columnRuns.isEmpty else { return nil }

                let maskInset = max(2, min(12, Int((min(clamped.width, clamped.height) * 0.08).rounded(.down))))
                var safeMinX = Int.max
                var safeMaxX = Int.min
                var safeMinY = Int.max
                var safeMaxY = Int.min
                for offset in offsets {
                    let y = offset / image.width
                    let x = offset % image.width
                    guard let row = rowRuns[y], let column = columnRuns[x] else { continue }
                    let distanceToMaskEdge = min(x - row.minX, row.maxX - x, y - column.minY, column.maxY - y)
                    guard distanceToMaskEdge >= maskInset else { continue }
                    safeMinX = min(safeMinX, x)
                    safeMaxX = max(safeMaxX, x)
                    safeMinY = min(safeMinY, y)
                    safeMaxY = max(safeMaxY, y)
                }

                if safeMinX <= safeMaxX, safeMinY <= safeMaxY {
                    return Self.clamp(
                        CGRect(x: safeMinX, y: safeMinY, width: safeMaxX - safeMinX + 1, height: safeMaxY - safeMinY + 1).integral,
                        to: imageBounds
                    )
                }

                let rowCoverageThreshold = max(3, Int((clamped.width * 0.35).rounded(.down)))
                let columnCoverageThreshold = max(3, Int((clamped.height * 0.35).rounded(.down)))
                let denseRows = rowRuns.filter { $0.value.count >= rowCoverageThreshold }.map(\.key)
                let denseColumns = columnRuns.filter { $0.value.count >= columnCoverageThreshold }.map(\.key)
                guard let denseMinX = denseColumns.min(),
                      let denseMaxX = denseColumns.max(),
                      let denseMinY = denseRows.min(),
                      let denseMaxY = denseRows.max(),
                      denseMinX <= denseMaxX,
                      denseMinY <= denseMaxY else { return nil }
                return Self.clamp(
                    CGRect(x: denseMinX, y: denseMinY, width: denseMaxX - denseMinX + 1, height: denseMaxY - denseMinY + 1).integral,
                    to: imageBounds
                )
            }

            var instanceSafeRectsByID: [Int: CGRect] = [:]
            for instanceID in pixelOffsetsByInstanceID.keys {
                if let safeRect = maskDerivedSafeRect(for: instanceID) {
                    instanceSafeRectsByID[instanceID] = safeRect
                }
            }

            let blockMajorities = Dictionary(uniqueKeysWithValues: blocks.map { block in
                (block.index, majority(in: Self.rect(from: block.bbox)))
            })
            var blocksByInstance: [Int: [MangaOverlayProbeBlock]] = [:]
            for block in blocks {
                if let id = blockMajorities[block.index]?.id {
                    blocksByInstance[id, default: []].append(block)
                }
            }

            var instances: [MangaKoharuNativeBubbleMaskInstanceLiteInstanceLedger] = []
            for (offset, component) in acceptedComponents.enumerated() {
                let id = offset + 1
                let relatedBlocks = blocks.filter { block in
                    component.bbox.intersects(Self.rect(from: block.bbox))
                }.map(\.index)
                let siblingBlocks = blocksByInstance[id]?.map(\.index) ?? []
                let bboxArea = max(1, Int((component.bbox.width * component.bbox.height).rounded()))
                let fillRatio = Double(component.pixelCount) / Double(bboxArea)
                let edgeClosure = min(1, max(0, fillRatio * 1.35))
                let interiorConfidence = min(1, max(0, fillRatio * 0.75 + Double(relatedBlocks.count) * 0.08 + (component.matchedIoU ?? 0) * 0.4))
                var rejectionReasons = component.rejectionReasons
                if siblingBlocks.count > 1 { rejectionReasons.append("sameInstanceMultipleBlocks") }
                if (component.matchedIoU ?? 0) < 0.08 { rejectionReasons.append("weakExistingBubbleAssociation") }
                let quality: String
                if rejectionReasons.contains("weakExistingBubbleAssociation") {
                    quality = "needsRealBubbleMaskArtifact"
                } else if interiorConfidence >= 0.62, component.pixelCount >= minArea {
                    quality = "nativeBubbleMaskInstanceLiteReportOnly"
                } else {
                    quality = "manualReviewOnly"
                }
                let needReason = quality == "needsRealBubbleMaskArtifact" || siblingBlocks.count > 1
                    ? "instance-lite cannot prove true Koharu BubbleMask boundary for this bubble"
                    : nil
                instances.append(
                    MangaKoharuNativeBubbleMaskInstanceLiteInstanceLedger(
                        instanceID: id,
                        maskValue: id,
                        bbox: Self.bboxArray(from: component.bbox),
                        pixelCount: component.pixelCount,
                        bboxArea: bboxArea,
                        fillRatio: fillRatio,
                        interiorConfidence: interiorConfidence,
                        edgeClosureScore: edgeClosure,
                        sourceBubbleID: component.matchedBubbleID,
                        matchedExistingBubbleID: component.matchedBubbleID,
                        matchedBubbleIoU: component.matchedIoU,
                        relatedBlockIndexes: uniqueSorted(relatedBlocks),
                        sameBubbleSiblingBlockIndexes: uniqueSorted(siblingBlocks),
                        adjacentInstanceIDs: [],
                        pixelMaskSource: "sourceImageThresholdConnectedComponent",
                        generationSignals: [
                            signal("pixelCount", String(component.pixelCount), source: "SourceImage"),
                            signal("fillRatio", formatted(fillRatio), source: "SourceImage"),
                            signal("matchedBubbleIoU", formatted(component.matchedIoU), source: "bubbleGeometry")
                        ],
                        rejectionReasons: Array(Set(rejectionReasons)).sorted(),
                        instanceQualityVerdict: quality,
                        needsRealBubbleMaskReason: needReason,
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                )
            }

            var adjacencyLedgers: [MangaKoharuNativeBubbleMaskInstanceLiteAdjacencyLedger] = []
            for lhs in instances {
                for rhs in instances where lhs.instanceID < rhs.instanceID {
                    guard let lhsRect = instanceRectsByID[lhs.instanceID],
                          let rhsRect = instanceRectsByID[rhs.instanceID] else { continue }
                    let bboxGap = gap(lhsRect, rhsRect)
                    guard bboxGap <= 18 || lhsRect.insetBy(dx: -8, dy: -8).intersects(rhsRect) else { continue }
                    let affected = uniqueSorted(lhs.relatedBlockIndexes + rhs.relatedBlockIndexes)
                    let seamRisk = bboxGap <= 3 ? "touchingOrOverlappingInstances" : "nearbySeparatedInstances"
                    adjacencyLedgers.append(
                        MangaKoharuNativeBubbleMaskInstanceLiteAdjacencyLedger(
                            instanceAID: lhs.instanceID,
                            instanceBID: rhs.instanceID,
                            bboxGap: bboxGap,
                            maskGap: bboxGap,
                            adjacencyStatus: bboxGap <= 3 ? "touchingOrOverlapping" : "nearbySeparated",
                            seamRisk: seamRisk,
                            relatedSplitCandidateIDs: uniqueSorted(affected.flatMap { splitByBlock[$0] ?? [] }),
                            affectedBlocks: affected,
                            nextAction: "keepInstanceLiteReportOnlyAndCollectRealBubbleMask",
                            decisionSignals: [
                                signal("bboxGap", formatted(bboxGap), source: "koharuNativeBubbleMaskInstanceLiteReport"),
                                signal("seamRisk", seamRisk, source: "koharuNativeBubbleMaskInstanceLiteReport")
                            ],
                            groundTruthUsedForDecision: false,
                            wouldChangeMainFlow: false,
                            diagnosticOnly: true
                        )
                    )
                }
            }
            let adjacentByID = adjacencyLedgers.reduce(into: [Int: [Int]]()) { partial, ledger in
                partial[ledger.instanceAID, default: []].append(ledger.instanceBID)
                partial[ledger.instanceBID, default: []].append(ledger.instanceAID)
            }
            for index in instances.indices {
                instances[index].adjacentInstanceIDs = uniqueSorted(adjacentByID[instances[index].instanceID] ?? [])
            }

            func rectOverlapCount(_ rects: [CGRect]) -> Int {
                var count = 0
                for i in rects.indices {
                    for j in rects.indices where j > i {
                        if rects[i].intersects(rects[j]) { count += 1 }
                    }
                }
                return count
            }

            var siblingLedgers: [MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger] = []
            for (instanceID, siblingBlocks) in blocksByInstance.sorted(by: { $0.key < $1.key }) {
                guard siblingBlocks.count > 1 else { continue }
                let currentRects = siblingBlocks.compactMap { block in block.safeLayoutRect.map(Self.rect(from:)) }
                let instanceSafeRects = siblingBlocks.compactMap { _ in instanceSafeRectsByID[instanceID] }
                let blockScopedSafeRects = siblingBlocks.map { block in
                    Self.clamp(Self.rect(from: block.bbox), to: imageBounds)
                }
                let renderSpriteRects = siblingBlocks.compactMap { block in
                    block.renderNonTransparentBounds.map(Self.rect(from:))
                }
                let renderSpriteOverlapCount = rectOverlapCount(renderSpriteRects)
                let seamRelated = adjacencyLedgers.contains { ledger in
                    ledger.affectedBlocks.contains { blockIndex in siblingBlocks.map(\.index).contains(blockIndex) }
                }
                let status = seamRelated || siblingBlocks.count > 1 ? "needsSiblingPartition" : "singleBlockStable"
                let safeRectPolicy = "sameInstanceSiblingKeepSeedRect"
                let spriteCollisionPolicy: String
                if renderSpriteRects.count < siblingBlocks.count {
                    spriteCollisionPolicy = "missingRenderSpriteBounds"
                } else if renderSpriteOverlapCount > 0 {
                    spriteCollisionPolicy = "sameInstanceSpriteOverlapManualReview"
                } else {
                    spriteCollisionPolicy = "sameInstanceSpritesSeparated"
                }
                siblingLedgers.append(
                    MangaKoharuNativeBubbleMaskInstanceLiteSiblingLedger(
                        instanceID: instanceID,
                        blockIndexes: uniqueSorted(siblingBlocks.map(\.index)),
                        currentBubbleID: sourceBubbleByInstanceID[instanceID] ?? nil,
                        currentSafeRectOverlapCount: rectOverlapCount(currentRects),
                        instanceLiteSafeRectOverlapCount: rectOverlapCount(instanceSafeRects),
                        blockScopedSafeRectOverlapCount: rectOverlapCount(blockScopedSafeRects),
                        renderSpriteOverlapCount: renderSpriteOverlapCount,
                        sameBubbleSafeRectPolicy: safeRectPolicy,
                        sameBubbleSpriteCollisionPolicy: spriteCollisionPolicy,
                        seamCandidateRelated: seamRelated,
                        siblingPartitionStatus: status,
                        needsRealBubbleMask: true,
                        nextAction: "collectRealBubbleMaskForSiblingPartition",
                        decisionSignals: [
                            signal("blockCount", String(siblingBlocks.count), source: "blocks"),
                            signal("sameBubbleSafeRectPolicy", safeRectPolicy, source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("blockScopedSafeRectOverlapCount", String(rectOverlapCount(blockScopedSafeRects)), source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("renderSpriteOverlapCount", String(renderSpriteOverlapCount), source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("sameBubbleSpriteCollisionPolicy", spriteCollisionPolicy, source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("seamCandidateRelated", String(seamRelated), source: "koharuBubbleAdjacencySeamReport")
                        ],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                )
            }

            let siblingStatusByInstance = Dictionary(uniqueKeysWithValues: siblingLedgers.map { ($0.instanceID ?? -1, $0.siblingPartitionStatus) })
            let siblingSpriteOverlapByInstance = Dictionary(uniqueKeysWithValues: siblingLedgers.map { ($0.instanceID ?? -1, $0.renderSpriteOverlapCount) })
            let siblingSpritePolicyByInstance = Dictionary(uniqueKeysWithValues: siblingLedgers.map { ($0.instanceID ?? -1, $0.sameBubbleSpriteCollisionPolicy) })
            let adjacencyRiskByInstance = adjacencyLedgers.reduce(into: [Int: String]()) { partial, ledger in
                partial[ledger.instanceAID] = ledger.seamRisk
                partial[ledger.instanceBID] = ledger.seamRisk
            }

            var blockLedgers: [MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger] = []
            for block in blocks.sorted(by: { $0.index < $1.index }) {
                let seedRect = Self.clamp(Self.rect(from: block.bbox), to: imageBounds)
                let maj = blockMajorities[block.index] ?? (id: nil, count: 0, coverage: 0, secondary: [:])
                let matchedBubble = maj.id.flatMap { sourceBubbleByInstanceID[$0] ?? nil }
                let assignment: String
                let conflict: String?
                if maj.id == nil {
                    assignment = "noMajorityMaskPixels"
                    conflict = "seed bbox contains no accepted instance-lite mask pixels"
                } else if block.bubbleID == nil {
                    assignment = "missingCurrentBubbleID"
                    conflict = "current block has no bubbleID to compare"
                } else if matchedBubble == block.bubbleID {
                    assignment = "agreesWithCurrentBubbleID"
                    conflict = nil
                } else if maj.secondary.count > 1 {
                    assignment = "multipleInstanceOverlap"
                    conflict = "seed bbox overlaps multiple instance-lite masks"
                } else {
                    assignment = "majorityMaskDiffersFromCurrentBubbleID"
                    conflict = "instance-lite majority maps to \(matchedBubble.map(String.init) ?? "nil") while current bubbleID is \(block.bubbleID.map(String.init) ?? "nil")"
                }
                let safeRect = maj.id.flatMap { instanceSafeRectsByID[$0] }
                let sameInstanceSiblingCount = maj.id.flatMap { blocksByInstance[$0]?.count } ?? 0
                let hasSameInstanceSiblings = sameInstanceSiblingCount > 1
                let blockScopedSafeRect = safeRect.map { hasSameInstanceSiblings ? seedRect : $0 }
                let safeRectPolicy: String
                if safeRect == nil {
                    safeRectPolicy = "missingInstanceLiteSafeRect"
                } else if hasSameInstanceSiblings {
                    safeRectPolicy = "sameInstanceSiblingKeepSeedRect"
                } else {
                    safeRectPolicy = "singleBlockUseMaskDerivedSafeRect"
                }
                let currentSafe = block.safeLayoutRect.map(Self.rect(from:))
                let safeRectComparison: String
                if blockScopedSafeRect == nil {
                    safeRectComparison = "missingInstanceLiteSafeRect"
                } else if let currentSafe, let blockScopedSafeRect, area(currentSafe.intersection(blockScopedSafeRect)) / max(1, min(area(currentSafe), area(blockScopedSafeRect))) >= 0.55 {
                    safeRectComparison = "similarToCurrentSafeRect"
                } else {
                    safeRectComparison = "differsFromCurrentSafeRect"
                }
                let renderRect = block.renderNonTransparentBounds.map(Self.rect(from:))
                let renderCoverage = renderRect.map { pixelCoverage(of: $0, instanceID: maj.id) } ?? 0
                let spriteContained = renderCoverage >= 0.72
                let spriteBlockScopedContainment = {
                    guard let renderRect, let blockScopedSafeRect else { return 0.0 }
                    return Self.rectContainmentRatio(inner: renderRect, outer: blockScopedSafeRect)
                }()
                let spriteContainedByScopedSafeRect = renderRect != nil
                    && blockScopedSafeRect != nil
                    && spriteBlockScopedContainment >= 0.995
                let spriteContainmentPolicy: String
                if renderRect == nil {
                    spriteContainmentPolicy = "missingRenderSpriteBounds"
                } else if blockScopedSafeRect == nil {
                    spriteContainmentPolicy = "missingBlockScopedSafeRect"
                } else if spriteContainedByScopedSafeRect {
                    spriteContainmentPolicy = "spriteWithinBlockScopedSafeRect"
                } else {
                    spriteContainmentPolicy = "spriteEscapesBlockScopedSafeRect"
                }
                let sameInstanceSpriteOverlapCount = maj.id.flatMap { siblingSpriteOverlapByInstance[$0] } ?? 0
                let spriteSiblingCollisionPolicy = maj.id.flatMap { siblingSpritePolicyByInstance[$0] } ?? "singleBlockOrNoInstance"
                let segmentStatus: String
                if let segment = segmentByBlock[block.index] {
                    if segment.usableForCropEvidence { segmentStatus = "segmentGlyphEvidenceUsable" }
                    else if !segment.rejectionReasons.isEmpty { segmentStatus = "segmentGlyphEvidenceWeak" }
                    else { segmentStatus = "segmentGlyphEvidenceUnknown" }
                } else {
                    segmentStatus = "segmentGlyphEvidenceMissing"
                }
                let splitRisk = splitByBlock[block.index]?.isEmpty == false
                    ? "bubbleSplitRisk"
                    : (maskByBlock[block.index]?.bubbleIDConsistent == false ? "assignmentConflictSplitRisk" : "noSplitRiskDetected")
                let siblingStatus = maj.id.flatMap { siblingStatusByInstance[$0] } ?? "singleBlockOrNoInstance"
                let adjacencyRisk = maj.id.flatMap { adjacencyRiskByInstance[$0] } ?? (seamByBlock[block.index]?.blockSeamRisk ?? "noAdjacencyRiskDetected")
                let translationRoute = block.blockPassed ? "translationPassed" : block.failureCategory
                let detectorRoute = closedLoopByBlock[block.index]?.closedLoopRoute
                let renderStatus: String
                if renderLockByBlock[block.index]?.renderCollisionResolved == false || !block.renderCollisionResolved {
                    renderStatus = "renderLockOpen"
                } else if renderFitByBlock[block.index]?.fitVerdict == "renderLockedNoPromotion" {
                    renderStatus = "renderLockedNoPromotion"
                } else {
                    renderStatus = "renderStable"
                }
                let primary: String
                if renderStatus != "renderStable" {
                    primary = "renderLocked"
                } else if block.failureCategory == "modelOutputFailure" || block.failureCategory == "translationLanguageQualityFailure" {
                    primary = "translationModelFloor"
                } else if segmentStatus == "segmentGlyphEvidenceWeak" || segmentStatus == "segmentGlyphEvidenceMissing" {
                    primary = "segmentGlyphEvidenceWeak"
                } else if splitRisk != "noSplitRiskDetected" {
                    primary = "bubbleSplitRisk"
                } else if siblingStatus == "needsSiblingPartition" {
                    primary = "sameBubbleSiblingPartitionRisk"
                } else if assignment != "agreesWithCurrentBubbleID" {
                    primary = assignment == "noMajorityMaskPixels" ? "bubbleMaskInstanceMissing" : "bubbleMaskAssignmentConflict"
                } else if detectorRoute == "needsRealKoharuTextBoxes" || detectorRoute == "waitForRealTextBoxes" {
                    primary = "detectorLiteClosedLoopNeedsTextBoxes"
                } else if block.failureCategory == "ocrInputSuspect" {
                    primary = "currentFusedOCRStable"
                } else {
                    primary = "manualReviewOnly"
                }
                let nextAction: String
                switch primary {
                case "renderLocked": nextAction = "keepRenderLockReportOnly"
                case "translationModelFloor": nextAction = "keepModelFloorSeparate"
                case "segmentGlyphEvidenceWeak": nextAction = "collectRealSegmentMask"
                case "bubbleSplitRisk", "sameBubbleSiblingPartitionRisk", "bubbleMaskAssignmentConflict", "bubbleMaskInstanceMissing":
                    nextAction = "collectRealBubbleMaskOrReviewInstanceLiteFullProbe"
                case "detectorLiteClosedLoopNeedsTextBoxes": nextAction = "collectRealTextBoxes"
                case "currentFusedOCRStable": nextAction = "keepCurrentFusedOCR"
                default: nextAction = "manualReviewOnly"
                }
                blockLedgers.append(
                    MangaKoharuNativeBubbleMaskInstanceLiteBlockLedger(
                        blockIndex: block.index,
                        currentBubbleID: block.bubbleID,
                        instanceLiteMajorityID: maj.id,
                        instanceLiteMajorityPixelCount: maj.count,
                        instanceLiteMajorityCoverage: maj.coverage,
                        instanceLiteSecondaryIDs: maj.secondary,
                        assignmentAgreement: assignment,
                        assignmentConflictReason: conflict,
                        bbox: block.bbox,
                        seedRect: Self.bboxArray(from: seedRect),
                        currentSafeLayoutRect: block.safeLayoutRect,
                        instanceLiteSafeRect: safeRect.map(Self.bboxArray(from:)),
                        instanceLiteBlockScopedSafeRect: blockScopedSafeRect.map(Self.bboxArray(from:)),
                        instanceLiteSafeRectPolicy: safeRectPolicy,
                        distanceFieldSafeRectFromInstanceLite: blockScopedSafeRect.map(Self.bboxArray(from:)),
                        distanceFieldSafeRectSource: hasSameInstanceSiblings ? "nativeBubbleMaskInstanceLiteBlockScopedSeedRect" : "nativeBubbleMaskInstanceLite",
                        currentRenderNonTransparentBounds: block.renderNonTransparentBounds,
                        spriteContainedByInstanceLiteMask: spriteContained,
                        spriteBlockScopedSafeRectContainmentRatio: spriteBlockScopedContainment,
                        spriteContainedByBlockScopedSafeRect: spriteContainedByScopedSafeRect,
                        spriteContainmentPolicy: spriteContainmentPolicy,
                        sameInstanceRenderSpriteOverlapCount: sameInstanceSpriteOverlapCount,
                        spriteSiblingCollisionPolicy: spriteSiblingCollisionPolicy,
                        siblingPartitionStatus: siblingStatus,
                        splitRisk: splitRisk,
                        adjacencyRisk: adjacencyRisk,
                        segmentGlyphEvidenceStatus: segmentStatus,
                        translationFailureCategory: block.failureCategory,
                        translationFailureRoute: translationRoute,
                        detectorLiteClosedLoopRoute: detectorRoute,
                        renderLockStatus: renderStatus,
                        primaryBottleneck: primary,
                        nextAction: nextAction,
                        decisionSignals: [
                            signal("currentBubbleID", block.bubbleID.map(String.init) ?? "nil", source: "blocks"),
                            signal("instanceLiteMajorityID", maj.id.map(String.init) ?? "nil", source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("assignmentAgreement", assignment, source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("safeRectComparison", safeRectComparison, source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("safeRectSource", safeRect == nil ? "nil" : "maskDerivedInstanceLitePixels", source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("safeRectPolicy", safeRectPolicy, source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("sameInstanceSiblingCount", String(sameInstanceSiblingCount), source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("spriteBlockScopedSafeRectContainmentRatio", formatted(spriteBlockScopedContainment), source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("spriteContainmentPolicy", spriteContainmentPolicy, source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("sameInstanceRenderSpriteOverlapCount", String(sameInstanceSpriteOverlapCount), source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("spriteSiblingCollisionPolicy", spriteSiblingCollisionPolicy, source: "koharuNativeBubbleMaskInstanceLiteReport")
                        ],
                        evaluationSignals: [
                            signal("groundTruthMatch", block.groundTruthMatch, source: "blocks", decision: false, evaluation: true),
                            signal("ocrGroundTruthSimilarity", formatted(block.ocrGroundTruthSimilarity), source: "blocks", decision: false, evaluation: true),
                            signal("bestGroundTruthType", block.bestGroundTruthType ?? "nil", source: "blocks", decision: false, evaluation: true)
                        ],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                )
            }

            let needsRealBubbleMaskBlocks = uniqueSorted(blockLedgers.filter {
                ["bubbleMaskInstanceMissing", "bubbleMaskAssignmentConflict", "bubbleSplitRisk", "sameBubbleSiblingPartitionRisk"].contains($0.primaryBottleneck)
            }.map(\.blockIndex))
            let needsRealSegmentMaskBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "segmentGlyphEvidenceWeak" }.map(\.blockIndex))
            let needsRealTextBoxesBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "detectorLiteClosedLoopNeedsTextBoxes" }.map(\.blockIndex))
            let manualReviewBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "manualReviewOnly" }.map(\.blockIndex))
            let renderLockedBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "renderLocked" }.map(\.blockIndex))
            let instanceVerdict: String
            if instances.isEmpty {
                instanceVerdict = "blockedByInsufficientPixelEvidence"
            } else if !needsRealBubbleMaskBlocks.isEmpty {
                instanceVerdict = "needsRealBubbleMaskArtifact"
            } else if !renderLockedBlocks.isEmpty {
                instanceVerdict = "renderLockedNoPromotion"
            } else {
                instanceVerdict = "nativeBubbleMaskInstanceLiteReportOnly"
            }
            let gates = [
                gate("G-native-bubblemask-instance-lite-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "instance-lite mask mutates OCR, translation, safeLayoutRect, renderer, blockPassed, failureCategory, candidate selection, active artifacts, or currentBlockSource", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-no-ground-truth-decision", "No ground truth decision", "report", "passed", "groundTruthUsedForDecision=false", allBlockIndexes, "ground truth influences mask generation, majority assignment, route, nextAction, verdict, or gate", "moveGroundTruthToEvaluationSignalsOnly", [signal("groundTruthUsedForDecision", "false", source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-source-pixels", "Source pixels", "SourceImage", instances.isEmpty ? "warning" : "passed", "usesSourceImagePixels=true and pixelMaskSource=sourceImageThresholdConnectedComponent", allBlockIndexes, "report copies rounded-rect proxy instead of using source image pixels", "restorePixelConnectedComponentMask", [signal("usesSourceImagePixels", "true", source: "koharuNativeBubbleMaskInstanceLiteReport"), signal("instanceCount", String(instances.count), source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-proxy-boundary", "Proxy boundary", "BubbleMask", "passed", "proxyNotRealKoharuBubbleMask=true", allBlockIndexes, "instance-lite mask is promoted as real Koharu BubbleMask", "keepProxyBoundaryOrCollectRealArtifact", [signal("proxyNotRealKoharuBubbleMask", "true", source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-block-ledger-count", "Block ledger count", "blocks", blockLedgers.count == blocks.count ? "passed" : "warning", "blockLedgerCount==totalBlocksDetected", allBlockIndexes, "some final blocks lack majority assignment ledger rows", "restoreBlockLedgerCoverage", [signal("blockLedgerCount", String(blockLedgers.count), source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-instance-ledger-visible", "Instance ledger visible", "BubbleMask", instances.isEmpty ? "warning" : "passed", "instanceCount>=1 or blockedByInsufficientPixelEvidence", allBlockIndexes, "instance-lite silently emits empty report without blocked verdict", "writeBlockedPixelEvidenceGate", [signal("instanceLiteVerdict", instanceVerdict, source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-safe-rect-report-only", "Safe rect report-only", "RenderedSprites", "passed", "distanceFieldSafeRectSource=nativeBubbleMaskInstanceLite and not written back", allBlockIndexes, "instance-lite safe rect mutates block.safeLayoutRect or distanceField report", "keepSafeRectComparisonReportOnly", [signal("safeRectWriteBack", "false", source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-sibling-safe-rect-policy", "Sibling safe rect policy", "BubbleMask", "passed", "same-instance sibling blocks keep block-scoped seed rects report-only", siblingLedgers.flatMap(\.blockIndexes), "same-instance sibling blocks are expanded into one shared instance safe rect", "keepSiblingSafeRectPolicyReportOnly", [signal("sameInstanceSiblingLedgerCount", String(siblingLedgers.count), source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-sibling-sprite-collision", "Sibling sprite collision preview", "RenderedSprites", "passed", "same-instance render sprite overlap is audited report-only", siblingLedgers.flatMap(\.blockIndexes), "same-instance rendered sprites collide without a visible sibling collision ledger", "keepSiblingSpriteCollisionReportOnly", [signal("sameInstanceSiblingLedgerCount", String(siblingLedgers.count), source: "koharuNativeBubbleMaskInstanceLiteReport"), signal("spriteSiblingCollisionPolicies", countBy(siblingLedgers.map(\.sameBubbleSpriteCollisionPolicy)).map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","), source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-no-ocr-llm-png", "No OCR LLM PNG", "budget", "passed", "no OCR/LLM calls and no PNG output", [], "instance-lite adds OCR, LLM, or new PNG output", "removeHeavyWorkFromInstanceLite", [signal("ocrCalls", "0", source: "koharuNativeBubbleMaskInstanceLiteReport"), signal("llmCalls", "0", source: "koharuNativeBubbleMaskInstanceLiteReport"), signal("pngOutputs", "0", source: "koharuNativeBubbleMaskInstanceLiteReport")]),
                gate("G-native-bubblemask-instance-lite-real-artifact-boundary", "External artifact boundary", "ExternalArtifacts", "passed", "externalArtifactsRequiredForThisReport=false and active artifacts unchanged", [], "instance-lite creates, copies, or modifies active Koharu artifacts", "doNotCreateActiveArtifacts", [signal("externalArtifactsRequiredForThisReport", "false", source: "koharuNativeBubbleMaskInstanceLiteReport")])
            ]

            return MangaKoharuNativeBubbleMaskInstanceLiteReport(
                enabled: true,
                source: "AITRANSProbe",
                referencePipeline: "Koharu",
                referenceConcept: "BubbleMask.NativeInstanceLite.PixelIDMask",
                referenceWorkItemID: "WI-koharu-native-bubblemask-instance-lite",
                evaluatedBlockCount: blocks.count,
                sourceImageWidth: image.width,
                sourceImageHeight: image.height,
                contentCropBBox: contentBBox,
                instanceCount: instances.count,
                blockLedgerCount: blockLedgers.count,
                siblingLedgerCount: siblingLedgers.count,
                adjacencyLedgerCount: adjacencyLedgers.count,
                gateCount: gates.count,
                groundTruthUsedForDecision: false,
                groundTruthUsedForEvaluationOnly: true,
                wouldChangeMainFlow: false,
                diagnosticOnly: true,
                nativeInstanceLite: true,
                proxyNotRealKoharuBubbleMask: true,
                usesSourceImagePixels: true,
                externalArtifactsRequiredForThisReport: false,
                instanceLiteVerdict: instanceVerdict,
                instanceQualityBreakdown: countBy(instances.map(\.instanceQualityVerdict)),
                assignmentAgreementBreakdown: countBy(blockLedgers.map(\.assignmentAgreement)),
                splitRiskBreakdown: countBy(blockLedgers.map(\.splitRisk)),
                siblingPartitionBreakdown: countBy(blockLedgers.map(\.siblingPartitionStatus)),
                safeRectComparisonBreakdown: countBy(blockLedgers.map {
                    if $0.instanceLiteBlockScopedSafeRect == nil { return "missingInstanceLiteSafeRect" }
                    if $0.currentSafeLayoutRect == $0.instanceLiteBlockScopedSafeRect { return "sameAsCurrentSafeRect" }
                    return "comparedReportOnly"
                }),
                safeRectPolicyBreakdown: countBy(blockLedgers.map(\.instanceLiteSafeRectPolicy)),
                spriteContainmentBreakdown: countBy(blockLedgers.map { $0.spriteContainedByInstanceLiteMask ? "contained" : "notContainedOrUnproven" }),
                spriteBlockScopedContainmentBreakdown: countBy(blockLedgers.map(\.spriteContainmentPolicy)),
                spriteSiblingCollisionBreakdown: countBy(blockLedgers.map(\.spriteSiblingCollisionPolicy)),
                adjacencyRiskBreakdown: countBy(blockLedgers.map(\.adjacencyRisk)),
                primaryBottleneckBreakdown: countBy(blockLedgers.map(\.primaryBottleneck)),
                nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                needsRealBubbleMaskBlocks: needsRealBubbleMaskBlocks,
                needsRealSegmentMaskBlocks: needsRealSegmentMaskBlocks,
                needsRealTextBoxesBlocks: needsRealTextBoxesBlocks,
                manualReviewBlocks: manualReviewBlocks,
                renderLockedBlocks: renderLockedBlocks,
                instances: instances.sorted { $0.instanceID < $1.instanceID },
                blockLedgers: blockLedgers,
                siblingLedgers: siblingLedgers.sorted { ($0.instanceID ?? -1) < ($1.instanceID ?? -1) },
                adjacencyLedgers: adjacencyLedgers.sorted {
                    if $0.instanceAID == $1.instanceAID { return $0.instanceBID < $1.instanceBID }
                    return $0.instanceAID < $1.instanceAID
                },
                gateLedger: gates,
                notes: [
                    "koharuNativeBubbleMaskInstanceLiteReport builds a shadow-only BubbleMask instance-lite ledger from source image near-white connected components inside the existing content crop.",
                    "Existing bubble geometry is used only for association, validation, and routing; this report is not a real Koharu BubbleMask and does not create active external artifacts.",
                    "Ground truth appears only in evaluationSignals and never drives mask generation, majority assignment, route, nextAction, verdict, or gates.",
                    "Instance-lite safe rect and sprite containment are report-only comparisons and are not written to safeLayoutRect, DistanceField reports, renderer state, overlay PNGs, OCR input, translation input, or crop adoption."
                ]
            )
        }.value
    }

    func makeKoharuNativeSegmentMaskRefinementLiteReport(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        detectorLiteReport: MangaKoharuNativeTextBoxDetectorLiteReport?,
        koharuNativeBubbleMaskInstanceLiteReport: MangaKoharuNativeBubbleMaskInstanceLiteReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?
    ) async -> MangaKoharuNativeSegmentMaskRefinementLiteReport {
        await Task.detached(priority: .userInitiated) {
            func uniqueSorted(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }
            func countBy(_ values: [String]) -> [String: Int] {
                values.reduce(into: [:]) { partial, value in partial[value, default: 0] += 1 }
            }
            func area(_ rect: CGRect) -> Double {
                Double(max(0, rect.width) * max(0, rect.height))
            }
            func formatted(_ value: Double?) -> String {
                value?.formatted(.number.precision(.fractionLength(4))) ?? "nil"
            }
            func signal(
                _ name: String,
                _ value: String,
                source: String,
                decision: Bool = true,
                evaluation: Bool = false
            ) -> MangaKoharuNativeSegmentMaskRefinementLiteSignal {
                MangaKoharuNativeSegmentMaskRefinementLiteSignal(
                    name: name,
                    value: value,
                    sourceReport: source,
                    groundTruthFreeDecisionSignal: decision,
                    groundTruthUsedForEvaluationOnly: evaluation
                )
            }
            func gate(
                _ id: String,
                _ name: String,
                _ scope: String,
                _ status: String,
                _ threshold: String,
                _ affected: [Int],
                _ failure: String,
                _ action: String,
                _ signals: [MangaKoharuNativeSegmentMaskRefinementLiteSignal]
            ) -> MangaKoharuNativeSegmentMaskRefinementLiteGate {
                MangaKoharuNativeSegmentMaskRefinementLiteGate(
                    gateID: id,
                    gateName: name,
                    scope: scope,
                    status: status,
                    threshold: threshold,
                    affectedBlocks: uniqueSorted(affected),
                    decisionSignals: signals,
                    failureMeans: failure,
                    recommendedAction: action,
                    groundTruthUsedForDecision: false
                )
            }
            func expandedTextBoxRect(_ rect: CGRect, direction: String, bounds: CGRect) -> (rect: CGRect, paddingX: Double, paddingY: Double) {
                let shortSide = max(1, min(rect.width, rect.height))
                let longSide = max(rect.width, rect.height)
                let vertical = direction.lowercased().contains("vertical")
                let paddingX = vertical ? max(3, shortSide * 0.18) : max(2, longSide * 0.06)
                let paddingY = vertical ? max(2, longSide * 0.06) : max(3, shortSide * 0.22)
                return (Self.clamp(rect.insetBy(dx: -paddingX, dy: -paddingY).integral, to: bounds), Double(paddingX), Double(paddingY))
            }

            let allBlockIndexes = blocks.map(\.index)
            let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let contentCrop = Self.clamp(Self.contentCropRect(for: image, cropping: .defaultValue).integral, to: imageBounds)
            let contentBBox = Self.bboxArray(from: contentCrop)
            let segmentByBlock = Dictionary(
                uniqueKeysWithValues: (segmentMaskReport?.diagnostics ?? []).map { ($0.blockIndex, $0) }
            )
            let renderLockByBlock = Dictionary(
                uniqueKeysWithValues: (koharuRenderRegressionLockReport?.blockLocks ?? []).map { ($0.blockIndex, $0) }
            )
            let instanceLiteByBlock = Dictionary(
                uniqueKeysWithValues: (koharuNativeBubbleMaskInstanceLiteReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
            )
            let instanceRectByID = Dictionary(
                uniqueKeysWithValues: (koharuNativeBubbleMaskInstanceLiteReport?.instances ?? []).map { ($0.instanceID, Self.rect(from: $0.bbox)) }
            )
            let instanceBubbleByID = Dictionary(
                uniqueKeysWithValues: (koharuNativeBubbleMaskInstanceLiteReport?.instances ?? []).map {
                    ($0.instanceID, $0.matchedExistingBubbleID ?? $0.sourceBubbleID)
                }
            )
            let bubbleRectByID = Dictionary(
                uniqueKeysWithValues: bubbleGeometry.bubbles.map { ($0.id, Self.rect(from: $0.bbox)) }
            )
            var detectorCandidatesByBlock: [Int: [MangaKoharuNativeTextBoxDetectorLiteCandidate]] = [:]
            for candidate in detectorLiteReport?.candidates ?? [] {
                for blockIndex in candidate.relatedCurrentBlockIndexes {
                    detectorCandidatesByBlock[blockIndex, default: []].append(candidate)
                }
            }
            let detectorCandidateByID = Dictionary(
                uniqueKeysWithValues: (detectorLiteReport?.candidates ?? []).map { ($0.candidateID, $0) }
            )
            for blockIndex in detectorCandidatesByBlock.keys {
                detectorCandidatesByBlock[blockIndex]?.sort {
                    if $0.score == $1.score { return $0.candidateID < $1.candidateID }
                    return $0.score > $1.score
                }
            }

            func textBoxSegmentLink(
                block: MangaOverlayProbeBlock,
                sourceTextBoxCandidateID: String?,
                sourceTextBoxCandidate: MangaKoharuNativeTextBoxDetectorLiteCandidate?
            ) -> (
                verdict: String,
                candidateVerdict: String?,
                shadowOCREligible: Bool?,
                overlapRatio: Double,
                sameBubble: Bool,
                accepted: Bool
            ) {
                guard let sourceTextBoxCandidateID, let candidate = sourceTextBoxCandidate else {
                    return ("fallbackFinalBlockBBox", nil, nil, 0, false, false)
                }
                let relation = candidate.relatedBlockRelations.first { $0.blockIndex == block.index }
                let overlap = relation?.overlapRatio ?? 0
                let sameBubble = relation?.sameBubble ?? (candidate.sourceBubbleID == block.bubbleID)
                if !sameBubble {
                    return ("sourceTextBoxBubbleMismatch", candidate.candidateVerdict, candidate.shadowOCREligible, overlap, false, false)
                }
                if candidate.candidateVerdict == "acceptedShadowOnly" {
                    let accepted = overlap >= 0.08 || relation?.centerContained == true
                    return (accepted ? "acceptedTextBoxCandidate" : "weakAcceptedTextBoxRelation", candidate.candidateVerdict, candidate.shadowOCREligible, overlap, sameBubble, accepted)
                }
                if candidate.candidateVerdict == "manualReviewOnly" || candidate.candidateVerdict == "manualReviewUnionFallback" {
                    return ("manualReviewTextBoxCandidate", candidate.candidateVerdict, candidate.shadowOCREligible, overlap, sameBubble, false)
                }
                return ("rejectedTextBoxCandidate", candidate.candidateVerdict, candidate.shadowOCREligible, overlap, sameBubble, false)
            }

            func emptyCandidate(
                block: MangaOverlayProbeBlock,
                reason: String,
                source: String = "currentFinalBlockBBoxFallback"
            ) -> MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger {
                let rect = Self.clamp(Self.rect(from: block.bbox), to: imageBounds)
                return MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger(
                    candidateID: "segmentMaskRefinementLite.block\(block.index).fallback",
                    blockIndex: block.index,
                    source: source,
                    sourceTextBoxCandidateID: nil,
                    sourceBubbleID: block.bubbleID,
                    sourceInstanceLiteID: instanceLiteByBlock[block.index]?.instanceLiteMajorityID,
                    bbox: Self.bboxArray(from: rect),
                    expandedTextBoxRect: Self.bboxArray(from: rect),
                    directionHint: "unknown",
                    paddingX: 0,
                    paddingY: 0,
                    rawPixelCount: 0,
                    afterTextBoxClampPixelCount: 0,
                    afterBubbleClampPixelCount: 0,
                    connectedComponentCount: 0,
                    largestComponentArea: 0,
                    maskBBox: nil,
                    maskFillRatio: 0,
                    textboxCoverage: 0,
                    bubbleCoverage: 0,
                    maskContainedByTextBoxRatio: 0,
                    maskContainedByBubbleRatio: 0,
                    maskMajorityInstanceLiteID: nil,
                    maskMajorityBubbleID: nil,
                    maskMajorityCoverage: 0,
                    maskMajorityAgreement: "maskMissing",
                    sourceTextBoxCandidateVerdict: nil,
                    sourceTextBoxShadowOCREligible: nil,
                    sourceTextBoxBlockOverlapRatio: 0,
                    sourceTextBoxSameBubble: false,
                    sourceTextBoxAcceptedForSegmentMask: false,
                    sourceTextBoxLinkVerdict: "fallbackFinalBlockBBox",
                    existingGlyphOverlap: 0,
                    segmentProxyAgreement: 0,
                    candidateVerdict: reason,
                    rejectionReasons: [reason],
                    decisionSignals: [signal("blockedReason", reason, source: "koharuNativeSegmentMaskRefinementLiteReport")],
                    evaluationSignals: [
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks", decision: false, evaluation: true),
                        signal("ocrGroundTruthSimilarity", formatted(block.ocrGroundTruthSimilarity), source: "blocks", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }

            guard let bitmap = Self.makeRGBA8Bitmap(from: image) else {
                let candidates = blocks.map { emptyCandidate(block: $0, reason: "blockedByMissingSourcePixels") }
                let blockLedgers = blocks.map { block in
                    MangaKoharuNativeSegmentMaskRefinementLiteBlockLedger(
                        blockIndex: block.index,
                        bubbleID: block.bubbleID,
                        instanceLiteMajorityID: instanceLiteByBlock[block.index]?.instanceLiteMajorityID,
                        bbox: block.bbox,
                        finalTextUsedForTranslation: block.finalTextUsedForTranslation,
                        failureCategory: block.failureCategory,
                        blockPassed: block.blockPassed,
                        selectedCandidateID: nil,
                        selectedSourceTextBoxCandidateID: nil,
                        selectedSourceTextBoxLinkVerdict: "fallbackFinalBlockBBox",
                        candidateCount: 1,
                        maskBBox: nil,
                        rawPixelCount: 0,
                        afterTextBoxClampPixelCount: 0,
                        afterBubbleClampPixelCount: 0,
                        componentCount: 0,
                        textboxCoverage: 0,
                        bubbleCoverage: 0,
                        maskContainedByTextBoxRatio: 0,
                        maskContainedByBubbleRatio: 0,
                        maskMajorityInstanceLiteID: nil,
                        maskMajorityBubbleID: nil,
                        maskMajorityCoverage: 0,
                        maskMajorityAgreement: "maskMissing",
                        existingGlyphOverlap: 0,
                        segmentProxyAgreement: 0,
                        maskContainedByTextBox: false,
                        maskContainedByBubble: false,
                        wouldBeUsableForClearTextMask: false,
                        wouldBeUsableForOCRCropConstraint: false,
                        wouldBeUsableForRenderContainment: false,
                        primaryBottleneck: "segmentMaskPixelEvidenceWeak",
                        nextAction: "manualReviewOnly",
                        decisionSignals: [signal("sourcePixelsAvailable", "false", source: "SourceImage")],
                        evaluationSignals: [signal("groundTruthMatch", block.groundTruthMatch, source: "blocks", decision: false, evaluation: true)],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                }
                let gates = [
                    gate("G-native-segmentmask-refinement-lite-source-pixels", "Source pixels", "SourceImage", "blocked", "source image pixels readable", allBlockIndexes, "SegmentMask refinement-lite cannot inspect source pixels", "restoreProbeImageByteAccess", [signal("sourcePixelsAvailable", "false", source: "SourceImage")]),
                    gate("G-native-segmentmask-refinement-lite-no-main-flow-writeback", "No main flow writeback", "report", "passed", "wouldChangeMainFlow=false", [], "refinement-lite mutates OCR, translation, rendering, glyph fill, safeLayoutRect, or currentBlockSource", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuNativeSegmentMaskRefinementLiteReport")])
                ]
                return MangaKoharuNativeSegmentMaskRefinementLiteReport(
                    enabled: true,
                    source: "AITRANSProbe",
                    referencePipeline: "Koharu",
                    referenceConcept: "SegmentMask.NativeRefinementLite.TextBoxConstrainedGlyphMask",
                    referenceWorkItemID: "WI-koharu-native-segmentmask-refinement-lite",
                    evaluatedBlockCount: blocks.count,
                    sourceImageWidth: image.width,
                    sourceImageHeight: image.height,
                    contentCropBBox: contentBBox,
                    candidateLedgerCount: candidates.count,
                    blockLedgerCount: blockLedgers.count,
                    siblingLedgerCount: 0,
                    gateCount: gates.count,
                    groundTruthUsedForDecision: false,
                    groundTruthUsedForEvaluationOnly: true,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true,
                    nativeRefinementLite: true,
                    proxyNotRealKoharuSegmentMask: true,
                    usesSourceImagePixels: true,
                    usesTextBoxConstraints: true,
                    usesBubbleMaskConstraints: true,
                    externalArtifactsRequiredForThisReport: false,
                    refinementLiteVerdict: "blockedByMissingSourcePixels",
                    candidateSourceBreakdown: countBy(candidates.map(\.source)),
                    candidateVerdictBreakdown: countBy(candidates.map(\.candidateVerdict)),
                    pixelEvidenceBreakdown: ["missingSourcePixels": candidates.count],
                    textboxClampBreakdown: [:],
                    bubbleClampBreakdown: [:],
                    componentFilteringBreakdown: [:],
                    maskContainmentBreakdown: [:],
                    maskMajorityAgreementBreakdown: [:],
                    textBoxSegmentLinkBreakdown: countBy(candidates.map(\.sourceTextBoxLinkVerdict)),
                    segmentFromAcceptedTextBoxCount: candidates.filter(\.sourceTextBoxAcceptedForSegmentMask).count,
                    segmentFromRejectedTextBoxCount: candidates.filter { $0.sourceTextBoxLinkVerdict == "rejectedTextBoxCandidate" }.count,
                    segmentFromFallbackBBoxCount: candidates.filter { $0.sourceTextBoxLinkVerdict == "fallbackFinalBlockBBox" }.count,
                    siblingMaskOverlapBreakdown: [:],
                    primaryBottleneckBreakdown: countBy(blockLedgers.map(\.primaryBottleneck)),
                    nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                    needsRealSegmentMaskBlocks: allBlockIndexes,
                    needsRealTextBoxesBlocks: [],
                    needsRealBubbleMaskBlocks: [],
                    manualReviewBlocks: allBlockIndexes,
                    renderLockedBlocks: [],
                    candidateLedgers: candidates,
                    blockLedgers: blockLedgers,
                    siblingLedgers: [],
                    gateLedger: gates,
                    notes: ["Source image pixels were unavailable; SegmentMask refinement-lite emitted blocked report-only ledgers."]
                )
            }

            func analyzeCandidate(
                block: MangaOverlayProbeBlock,
                candidateID: String,
                source: String,
                sourceTextBoxCandidateID: String?,
                sourceTextBoxCandidate: MangaKoharuNativeTextBoxDetectorLiteCandidate?,
                sourceRect: CGRect,
                directionHint: String,
                sourceBubbleID: Int?
            ) -> MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger {
                let link = textBoxSegmentLink(
                    block: block,
                    sourceTextBoxCandidateID: sourceTextBoxCandidateID,
                    sourceTextBoxCandidate: sourceTextBoxCandidate
                )
                let (expandedRect, paddingX, paddingY) = expandedTextBoxRect(sourceRect, direction: directionHint, bounds: contentCrop)
                let instanceID = instanceLiteByBlock[block.index]?.instanceLiteMajorityID
                let instanceRect = instanceID.flatMap { instanceRectByID[$0] }
                let bubbleRect = block.bubbleID.flatMap { bubbleRectByID[$0] }
                let bubbleConstraint = instanceRect ?? bubbleRect
                let glyphRect = (segmentByBlock[block.index]?.glyphMaskRect ?? block.glyphMaskRect).map(Self.rect(from:))
                let x0 = max(0, Int(expandedRect.minX.rounded(.down)))
                let x1 = min(image.width, Int(expandedRect.maxX.rounded(.up)))
                let y0 = max(0, Int(expandedRect.minY.rounded(.down)))
                let y1 = min(image.height, Int(expandedRect.maxY.rounded(.up)))
                var foreground = [Bool](repeating: false, count: max(0, x1 - x0) * max(0, y1 - y0))
                var bubbleForeground = [Bool](repeating: false, count: foreground.count)
                var rawPixelCount = 0
                var bubblePixelCount = 0
                var minMaskX = Int.max
                var minMaskY = Int.max
                var maxMaskX = Int.min
                var maxMaskY = Int.min
                let scanWidth = max(0, x1 - x0)
                let scanHeight = max(0, y1 - y0)
                if scanWidth > 0, scanHeight > 0 {
                    for localY in 0..<scanHeight {
                        let y = y0 + localY
                        for localX in 0..<scanWidth {
                            let x = x0 + localX
                            let offset = y * bitmap.bytesPerRow + x * 4
                            guard offset + 2 < bitmap.pixels.count else { continue }
                            let r = Int(bitmap.pixels[offset])
                            let g = Int(bitmap.pixels[offset + 1])
                            let b = Int(bitmap.pixels[offset + 2])
                            let luminance = (r * 299 + g * 587 + b * 114) / 1000
                            let contrast = max(r, g, b) - min(r, g, b)
                            let isTextPixel = luminance <= 150 || (luminance <= 190 && contrast >= 36)
                            guard isTextPixel else { continue }
                            let idx = localY * scanWidth + localX
                            foreground[idx] = true
                            rawPixelCount += 1
                            let pointRect = CGRect(x: x, y: y, width: 1, height: 1)
                            let insideBubble = bubbleConstraint.map { $0.intersects(pointRect) } ?? false
                            if insideBubble || bubbleConstraint == nil {
                                bubbleForeground[idx] = true
                                bubblePixelCount += 1
                                minMaskX = min(minMaskX, x)
                                minMaskY = min(minMaskY, y)
                                maxMaskX = max(maxMaskX, x)
                                maxMaskY = max(maxMaskY, y)
                            }
                        }
                    }
                }
                var visited = [Bool](repeating: false, count: bubbleForeground.count)
                var componentCount = 0
                var largestComponentArea = 0
                if scanWidth > 0, scanHeight > 0 {
                    for startY in 0..<scanHeight {
                        for startX in 0..<scanWidth {
                            let start = startY * scanWidth + startX
                            guard bubbleForeground[start], !visited[start] else { continue }
                            componentCount += 1
                            var queue = [start]
                            var cursor = 0
                            var componentArea = 0
                            visited[start] = true
                            while cursor < queue.count {
                                let current = queue[cursor]
                                cursor += 1
                                componentArea += 1
                                let cy = current / scanWidth
                                let cx = current % scanWidth
                                for ny in max(0, cy - 1)...min(scanHeight - 1, cy + 1) {
                                    for nx in max(0, cx - 1)...min(scanWidth - 1, cx + 1) {
                                        let next = ny * scanWidth + nx
                                        if bubbleForeground[next], !visited[next] {
                                            visited[next] = true
                                            queue.append(next)
                                        }
                                    }
                                }
                            }
                            largestComponentArea = max(largestComponentArea, componentArea)
                        }
                    }
                }
                let maskRect: CGRect? = maxMaskX >= minMaskX && maxMaskY >= minMaskY
                    ? CGRect(x: minMaskX, y: minMaskY, width: maxMaskX - minMaskX + 1, height: maxMaskY - minMaskY + 1).integral
                    : nil
                let maskArea = maskRect.map(area) ?? 0
                let textBoxArea = max(1, area(expandedRect))
                let bubbleArea = max(1, area(bubbleConstraint ?? expandedRect))
                let textBoxContainment = maskRect.map {
                    Self.rectContainmentRatio(inner: $0, outer: expandedRect)
                } ?? 0
                let bubbleContainment = maskRect.map { mask in
                    bubbleConstraint.map { Self.rectContainmentRatio(inner: mask, outer: $0) } ?? 0
                } ?? 0
                let instanceContainment = maskRect.map { mask in
                    instanceRect.map { Self.rectContainmentRatio(inner: mask, outer: $0) } ?? 0
                } ?? 0
                let maskMajorityInstanceID = instanceContainment >= 0.90 ? instanceID : nil
                let maskMajorityBubbleID = maskMajorityInstanceID.flatMap { instanceBubbleByID[$0] ?? nil }
                let expectedBubbleID = sourceBubbleID ?? block.bubbleID
                let instanceAssignmentAgreement = instanceLiteByBlock[block.index]?.assignmentAgreement
                let maskMajorityCoverage = max(instanceContainment, bubbleContainment)
                let maskMajorityAgreement: String
                if maskRect == nil {
                    maskMajorityAgreement = "maskMissing"
                } else if let instanceID, maskMajorityInstanceID == instanceID, instanceContainment >= 0.90 {
                    maskMajorityAgreement = "agreesWithBlockInstanceLiteMajority"
                } else if let expectedBubbleID,
                          let maskMajorityBubbleID,
                          maskMajorityBubbleID == expectedBubbleID,
                          bubbleContainment >= 0.90,
                          instanceAssignmentAgreement == "agreesWithCurrentBubbleID" {
                    maskMajorityAgreement = "agreesWithSourceBubble"
                } else if instanceID == nil {
                    maskMajorityAgreement = "noInstanceMajority"
                } else if maskMajorityCoverage < 0.50 {
                    maskMajorityAgreement = "weakMaskMajority"
                } else {
                    maskMajorityAgreement = "differsFromBlockInstanceLiteMajority"
                }
                let glyphOverlap: Double
                if let maskRect, let glyphRect {
                    let intersection = maskRect.intersection(glyphRect)
                    glyphOverlap = intersection.isNull ? 0 : area(intersection) / max(1, min(area(maskRect), area(glyphRect)))
                } else {
                    glyphOverlap = 0
                }
                let textCoverage = maskArea / textBoxArea
                let bubbleCoverage = Double(bubblePixelCount) / max(1, Double(rawPixelCount))
                let segmentAgreement = glyphOverlap > 0 ? glyphOverlap : min(1, Double(block.glyphMaskPixelCount) / max(1, Double(rawPixelCount)))
                var rejectionReasons: [String] = []
                if sourceTextBoxCandidateID == nil && source == "currentFinalBlockBBoxFallback" {
                    rejectionReasons.append("textBoxConstraintMissing")
                }
                if link.verdict == "sourceTextBoxBubbleMismatch" {
                    rejectionReasons.append("sourceTextBoxBubbleMismatch")
                }
                if bubbleConstraint == nil {
                    rejectionReasons.append("bubbleConstraintMissing")
                }
                if rawPixelCount < 12 {
                    rejectionReasons.append("maskTooSparse")
                }
                if textCoverage > 0.55 {
                    rejectionReasons.append("maskTooLargeLikelyBackground")
                }
                if componentCount == 0 {
                    rejectionReasons.append("componentFilteringRejected")
                }
                if maskRect != nil, textBoxContainment < 0.92 {
                    rejectionReasons.append("maskEscapesTextBox")
                }
                if maskRect != nil, bubbleContainment < 0.90 {
                    rejectionReasons.append("maskEscapesBubble")
                }
                if maskMajorityAgreement == "differsFromBlockInstanceLiteMajority" {
                    rejectionReasons.append("maskMajorityDisagreesWithBubble")
                }
                let verdict: String
                if rejectionReasons.contains("textBoxConstraintMissing") {
                    verdict = "textBoxConstraintMissing"
                } else if rejectionReasons.contains("sourceTextBoxBubbleMismatch") {
                    verdict = "sourceTextBoxBubbleMismatch"
                } else if rejectionReasons.contains("bubbleConstraintMissing") {
                    verdict = "bubbleConstraintMissing"
                } else if rejectionReasons.contains("maskTooSparse") {
                    verdict = "maskTooSparse"
                } else if rejectionReasons.contains("maskTooLargeLikelyBackground") {
                    verdict = "maskTooLargeLikelyBackground"
                } else if rejectionReasons.contains("componentFilteringRejected") {
                    verdict = "componentFilteringRejected"
                } else if rejectionReasons.contains("maskEscapesTextBox") {
                    verdict = "maskEscapesTextBox"
                } else if rejectionReasons.contains("maskEscapesBubble") {
                    verdict = "maskEscapesBubble"
                } else if rejectionReasons.contains("maskMajorityDisagreesWithBubble") {
                    verdict = "maskMajorityDisagreesWithBubble"
                } else if segmentAgreement < 0.15 {
                    verdict = "weakPixelEvidence"
                } else {
                    verdict = "refinementLiteUsableForReport"
                }
                return MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger(
                    candidateID: candidateID,
                    blockIndex: block.index,
                    source: source,
                    sourceTextBoxCandidateID: sourceTextBoxCandidateID,
                    sourceBubbleID: sourceBubbleID,
                    sourceInstanceLiteID: instanceID,
                    bbox: Self.bboxArray(from: sourceRect),
                    expandedTextBoxRect: Self.bboxArray(from: expandedRect),
                    directionHint: directionHint,
                    paddingX: paddingX,
                    paddingY: paddingY,
                    rawPixelCount: rawPixelCount,
                    afterTextBoxClampPixelCount: rawPixelCount,
                    afterBubbleClampPixelCount: bubblePixelCount,
                    connectedComponentCount: componentCount,
                    largestComponentArea: largestComponentArea,
                    maskBBox: maskRect.map(Self.bboxArray(from:)),
                    maskFillRatio: maskArea > 0 ? Double(bubblePixelCount) / max(1, maskArea) : 0,
                    textboxCoverage: textCoverage,
                    bubbleCoverage: bubbleCoverage,
                    maskContainedByTextBoxRatio: textBoxContainment,
                    maskContainedByBubbleRatio: bubbleContainment,
                    maskMajorityInstanceLiteID: maskMajorityInstanceID,
                    maskMajorityBubbleID: maskMajorityBubbleID,
                    maskMajorityCoverage: maskMajorityCoverage,
                    maskMajorityAgreement: maskMajorityAgreement,
                    sourceTextBoxCandidateVerdict: link.candidateVerdict,
                    sourceTextBoxShadowOCREligible: link.shadowOCREligible,
                    sourceTextBoxBlockOverlapRatio: link.overlapRatio,
                    sourceTextBoxSameBubble: link.sameBubble,
                    sourceTextBoxAcceptedForSegmentMask: link.accepted,
                    sourceTextBoxLinkVerdict: link.verdict,
                    existingGlyphOverlap: glyphOverlap,
                    segmentProxyAgreement: segmentAgreement,
                    candidateVerdict: verdict,
                    rejectionReasons: rejectionReasons,
                    decisionSignals: [
                        signal("source", source, source: "koharuNativeSegmentMaskRefinementLiteReport"),
                        signal("sourceTextBoxCandidateID", sourceTextBoxCandidateID ?? "nil", source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("sourceTextBoxLinkVerdict", link.verdict, source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("sourceTextBoxCandidateVerdict", link.candidateVerdict ?? "nil", source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("sourceTextBoxBlockOverlapRatio", formatted(link.overlapRatio), source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("sourceTextBoxSameBubble", String(link.sameBubble), source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("sourceInstanceLiteID", instanceID.map(String.init) ?? "nil", source: "koharuNativeBubbleMaskInstanceLiteReport"),
                        signal("rawPixelCount", String(rawPixelCount), source: "SourceImage"),
                        signal("afterBubbleClampPixelCount", String(bubblePixelCount), source: "koharuNativeSegmentMaskRefinementLiteReport"),
                        signal("maskContainedByTextBoxRatio", formatted(textBoxContainment), source: "koharuNativeSegmentMaskRefinementLiteReport"),
                        signal("maskContainedByBubbleRatio", formatted(bubbleContainment), source: "koharuNativeSegmentMaskRefinementLiteReport"),
                        signal("maskMajorityAgreement", maskMajorityAgreement, source: "koharuNativeSegmentMaskRefinementLiteReport")
                    ],
                    evaluationSignals: [
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks", decision: false, evaluation: true),
                        signal("ocrGroundTruthSimilarity", formatted(block.ocrGroundTruthSimilarity), source: "blocks", decision: false, evaluation: true),
                        signal("bestGroundTruthType", block.bestGroundTruthType ?? "nil", source: "blocks", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }

            var candidateLedgers: [MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger] = []
            var blockLedgers: [MangaKoharuNativeSegmentMaskRefinementLiteBlockLedger] = []
            for block in blocks.sorted(by: { $0.index < $1.index }) {
                var perBlockCandidates: [MangaKoharuNativeSegmentMaskRefinementLiteCandidateLedger] = []
                let detectorCandidates = Array((detectorCandidatesByBlock[block.index] ?? []).prefix(2))
                for (offset, detectorCandidate) in detectorCandidates.enumerated() {
                    let source = detectorCandidate.candidateID.contains("refinement") ? "nativeDetectorLiteRefinedTextBox" : "nativeDetectorLiteTextBox"
                    perBlockCandidates.append(
                        analyzeCandidate(
                            block: block,
                            candidateID: "segmentMaskRefinementLite.block\(block.index).detector\(offset)",
                            source: source,
                            sourceTextBoxCandidateID: detectorCandidate.candidateID,
                            sourceTextBoxCandidate: detectorCandidateByID[detectorCandidate.candidateID],
                            sourceRect: Self.rect(from: detectorCandidate.bbox),
                            directionHint: detectorCandidate.directionHint,
                            sourceBubbleID: detectorCandidate.sourceBubbleID
                        )
                    )
                }
                if perBlockCandidates.isEmpty {
                    perBlockCandidates.append(
                        analyzeCandidate(
                            block: block,
                            candidateID: "segmentMaskRefinementLite.block\(block.index).fallback",
                            source: "currentFinalBlockBBoxFallback",
                            sourceTextBoxCandidateID: nil,
                            sourceTextBoxCandidate: nil,
                            sourceRect: Self.rect(from: block.bbox),
                            directionHint: "unknown",
                            sourceBubbleID: block.bubbleID
                        )
                    )
                }
                candidateLedgers.append(contentsOf: perBlockCandidates)
                let selected = perBlockCandidates.first { $0.candidateVerdict == "refinementLiteUsableForReport" } ?? perBlockCandidates.first
                let renderLocked = renderLockByBlock[block.index]?.renderCollisionResolved == false || !block.renderCollisionResolved
                let instanceID = instanceLiteByBlock[block.index]?.instanceLiteMajorityID
                let segment = segmentByBlock[block.index]
                let containedByTextBox = (selected?.maskContainedByTextBoxRatio ?? 0) >= 0.92
                    && !(selected?.rejectionReasons.contains("textBoxConstraintMissing") ?? true)
                let containedByBubble = (selected?.maskContainedByBubbleRatio ?? 0) >= 0.90
                    && !(selected?.rejectionReasons.contains("bubbleConstraintMissing") ?? true)
                let usableClear = selected?.candidateVerdict == "refinementLiteUsableForReport" && (selected?.afterBubbleClampPixelCount ?? 0) >= 24
                let usableOCRCrop = usableClear && (selected?.textboxCoverage ?? 0) < 0.45
                let usableRender = usableClear && containedByBubble && !renderLocked
                let primary: String
                if renderLocked {
                    primary = "renderLocked"
                } else if block.failureCategory == "modelOutputFailure" || block.failureCategory == "translationLanguageQualityFailure" {
                    primary = "translationModelFloor"
                } else if selected?.rejectionReasons.contains("textBoxConstraintMissing") == true {
                    primary = "textBoxConstraintMissing"
                } else if selected?.sourceTextBoxLinkVerdict == "rejectedTextBoxCandidate"
                    || selected?.sourceTextBoxLinkVerdict == "sourceTextBoxBubbleMismatch"
                    || selected?.sourceTextBoxLinkVerdict == "weakAcceptedTextBoxRelation" {
                    primary = "textBoxSegmentLinkWeak"
                } else if selected?.rejectionReasons.contains("bubbleConstraintMissing") == true {
                    primary = "bubbleMaskConstraintMissing"
                } else if selected?.candidateVerdict != "refinementLiteUsableForReport" {
                    primary = "segmentMaskPixelEvidenceWeak"
                } else if segment?.usableForCropEvidence == true {
                    primary = "segmentMaskProxyStableReportOnly"
                } else if block.failureCategory == "ocrInputSuspect" {
                    primary = "ocrInputStillDominant"
                } else {
                    primary = "manualReviewOnly"
                }
                let nextAction: String
                switch primary {
                case "renderLocked": nextAction = "keepRenderLockReportOnly"
                case "translationModelFloor": nextAction = "keepModelFloorSeparate"
                case "textBoxConstraintMissing": nextAction = "collectRealTextBoxes"
                case "textBoxSegmentLinkWeak": nextAction = "auditTextBoxSegmentLinkage"
                case "bubbleMaskConstraintMissing": nextAction = "collectRealBubbleMask"
                case "segmentMaskPixelEvidenceWeak": nextAction = "collectRealSegmentMask"
                case "ocrInputStillDominant": nextAction = "keepSegmentMaskRefinementLiteReportOnly"
                case "segmentMaskProxyStableReportOnly": nextAction = "keepSegmentMaskRefinementLiteReportOnly"
                default: nextAction = "manualReviewOnly"
                }
                blockLedgers.append(
                    MangaKoharuNativeSegmentMaskRefinementLiteBlockLedger(
                        blockIndex: block.index,
                        bubbleID: block.bubbleID,
                        instanceLiteMajorityID: instanceID,
                        bbox: block.bbox,
                        finalTextUsedForTranslation: block.finalTextUsedForTranslation,
                        failureCategory: block.failureCategory,
                        blockPassed: block.blockPassed,
                        selectedCandidateID: selected?.candidateID,
                        selectedSourceTextBoxCandidateID: selected?.sourceTextBoxCandidateID,
                        selectedSourceTextBoxLinkVerdict: selected?.sourceTextBoxLinkVerdict ?? "fallbackFinalBlockBBox",
                        candidateCount: perBlockCandidates.count,
                        maskBBox: selected?.maskBBox,
                        rawPixelCount: selected?.rawPixelCount ?? 0,
                        afterTextBoxClampPixelCount: selected?.afterTextBoxClampPixelCount ?? 0,
                        afterBubbleClampPixelCount: selected?.afterBubbleClampPixelCount ?? 0,
                        componentCount: selected?.connectedComponentCount ?? 0,
                        textboxCoverage: selected?.textboxCoverage ?? 0,
                        bubbleCoverage: selected?.bubbleCoverage ?? 0,
                        maskContainedByTextBoxRatio: selected?.maskContainedByTextBoxRatio ?? 0,
                        maskContainedByBubbleRatio: selected?.maskContainedByBubbleRatio ?? 0,
                        maskMajorityInstanceLiteID: selected?.maskMajorityInstanceLiteID,
                        maskMajorityBubbleID: selected?.maskMajorityBubbleID,
                        maskMajorityCoverage: selected?.maskMajorityCoverage ?? 0,
                        maskMajorityAgreement: selected?.maskMajorityAgreement ?? "maskMissing",
                        existingGlyphOverlap: selected?.existingGlyphOverlap ?? 0,
                        segmentProxyAgreement: selected?.segmentProxyAgreement ?? 0,
                        maskContainedByTextBox: containedByTextBox,
                        maskContainedByBubble: containedByBubble,
                        wouldBeUsableForClearTextMask: usableClear,
                        wouldBeUsableForOCRCropConstraint: usableOCRCrop,
                        wouldBeUsableForRenderContainment: usableRender,
                        primaryBottleneck: primary,
                        nextAction: nextAction,
                        decisionSignals: [
                            signal("selectedCandidateID", selected?.candidateID ?? "nil", source: "koharuNativeSegmentMaskRefinementLiteReport"),
                            signal("candidateVerdict", selected?.candidateVerdict ?? "nil", source: "koharuNativeSegmentMaskRefinementLiteReport"),
                            signal("selectedSourceTextBoxCandidateID", selected?.sourceTextBoxCandidateID ?? "nil", source: "koharuNativeTextBoxDetectorLiteReport"),
                            signal("selectedSourceTextBoxLinkVerdict", selected?.sourceTextBoxLinkVerdict ?? "nil", source: "koharuNativeTextBoxDetectorLiteReport"),
                            signal("instanceLiteMajorityID", instanceID.map(String.init) ?? "nil", source: "koharuNativeBubbleMaskInstanceLiteReport"),
                            signal("maskContainedByTextBoxRatio", formatted(selected?.maskContainedByTextBoxRatio), source: "koharuNativeSegmentMaskRefinementLiteReport"),
                            signal("maskContainedByBubbleRatio", formatted(selected?.maskContainedByBubbleRatio), source: "koharuNativeSegmentMaskRefinementLiteReport"),
                            signal("maskMajorityAgreement", selected?.maskMajorityAgreement ?? "nil", source: "koharuNativeSegmentMaskRefinementLiteReport"),
                            signal("renderLocked", String(renderLocked), source: "koharuRenderRegressionLockReport,blocks")
                        ],
                        evaluationSignals: [
                            signal("groundTruthMatch", block.groundTruthMatch, source: "blocks", decision: false, evaluation: true),
                            signal("ocrGroundTruthSimilarity", formatted(block.ocrGroundTruthSimilarity), source: "blocks", decision: false, evaluation: true),
                            signal("bestGroundTruthType", block.bestGroundTruthType ?? "nil", source: "blocks", decision: false, evaluation: true)
                        ],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                )
            }

            var siblingLedgers: [MangaKoharuNativeSegmentMaskRefinementLiteSiblingLedger] = []
            let grouped = Dictionary(grouping: blockLedgers) { ledger in
                "\(ledger.bubbleID.map(String.init) ?? "nil"):\(ledger.instanceLiteMajorityID.map(String.init) ?? "nil")"
            }
            for group in grouped.values where group.count > 1 {
                var overlapCount = 0
                var pixelOverlapEstimate = 0
                let sorted = group.sorted { $0.blockIndex < $1.blockIndex }
                for i in sorted.indices {
                    for j in sorted.indices where j > i {
                        guard let a = sorted[i].maskBBox.map(Self.rect(from:)),
                              let b = sorted[j].maskBBox.map(Self.rect(from:)) else { continue }
                        let intersection = a.intersection(b)
                        if !intersection.isNull, area(intersection) > 0 {
                            overlapCount += 1
                            pixelOverlapEstimate += Int(area(intersection).rounded())
                        }
                    }
                }
                let needsSegment = overlapCount > 0 || sorted.contains { !$0.wouldBeUsableForClearTextMask }
                let needsBubble = sorted.contains { $0.instanceLiteMajorityID == nil }
                let siblingRisk = overlapCount > 0 ? "maskOverlapRisk" : "sameBubbleSiblingReportOnly"
                siblingLedgers.append(
                    MangaKoharuNativeSegmentMaskRefinementLiteSiblingLedger(
                        bubbleID: sorted.first?.bubbleID,
                        instanceLiteID: sorted.first?.instanceLiteMajorityID,
                        blockIndexes: sorted.map(\.blockIndex),
                        maskBBoxOverlapCount: overlapCount,
                        pixelOverlapEstimate: pixelOverlapEstimate,
                        sameBubbleSiblingRisk: siblingRisk,
                        seamRisk: overlapCount > 0 ? "needsSeamPartitionEvidence" : "noSeamRiskDetected",
                        needsRealSegmentMask: needsSegment,
                        needsRealBubbleMask: needsBubble,
                        nextAction: needsSegment ? "collectRealSegmentMask" : (needsBubble ? "collectRealBubbleMask" : "keepSegmentMaskRefinementLiteReportOnly"),
                        decisionSignals: [
                            signal("maskBBoxOverlapCount", String(overlapCount), source: "koharuNativeSegmentMaskRefinementLiteReport"),
                            signal("pixelOverlapEstimate", String(pixelOverlapEstimate), source: "koharuNativeSegmentMaskRefinementLiteReport")
                        ],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                )
            }

            let needsRealSegmentMaskBlocks = uniqueSorted(blockLedgers.filter {
                $0.primaryBottleneck == "segmentMaskPixelEvidenceWeak" || !$0.wouldBeUsableForClearTextMask
            }.map(\.blockIndex))
            let needsRealTextBoxesBlocks = uniqueSorted(blockLedgers.filter {
                $0.primaryBottleneck == "textBoxConstraintMissing" || $0.primaryBottleneck == "textBoxSegmentLinkWeak"
            }.map(\.blockIndex))
            let needsRealBubbleMaskBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "bubbleMaskConstraintMissing" }.map(\.blockIndex))
            let manualReviewBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "manualReviewOnly" }.map(\.blockIndex))
            let renderLockedBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "renderLocked" }.map(\.blockIndex))
            let verdict: String
            if candidateLedgers.isEmpty {
                verdict = "blockedByMissingTextBoxCandidates"
            } else if candidateLedgers.allSatisfy({ $0.rawPixelCount == 0 }) {
                verdict = "blockedByInsufficientPixelEvidence"
            } else if !needsRealTextBoxesBlocks.isEmpty {
                verdict = "needsRealTextBoxesArtifact"
            } else if !needsRealBubbleMaskBlocks.isEmpty {
                verdict = "needsRealBubbleMaskArtifact"
            } else if !needsRealSegmentMaskBlocks.isEmpty {
                verdict = "needsRealSegmentMaskArtifact"
            } else if !renderLockedBlocks.isEmpty {
                verdict = "renderLockedNoPromotion"
            } else {
                verdict = "nativeSegmentMaskRefinementLiteReportOnly"
            }
            let gates = [
                gate("G-native-segmentmask-refinement-lite-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "SegmentMask refinement-lite mutates OCR, translation, renderer, cleanup, glyphMaskFillRects, safeLayoutRect, blockPassed, or currentBlockSource", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-no-ground-truth-decision", "No ground truth decision", "report", "passed", "groundTruthUsedForDecision=false", allBlockIndexes, "ground truth drives threshold, TextBox choice, mask, route, nextAction, verdict, or gate", "moveGroundTruthToEvaluationSignalsOnly", [signal("groundTruthUsedForDecision", "false", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-source-pixels", "Source pixels", "SourceImage", "passed", "usesSourceImagePixels=true", allBlockIndexes, "report is pure bbox copy without source pixel evidence", "restorePixelScan", [signal("usesSourceImagePixels", "true", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-textbox-constrained", "TextBox constrained", "TextBoxes", needsRealTextBoxesBlocks.isEmpty ? "passed" : "warning", "usesTextBoxConstraints=true and fallback is explicit", needsRealTextBoxesBlocks, "TextBox constraints are missing or fake-promoted as real Koharu TextBoxes", "collectRealTextBoxes", [signal("usesTextBoxConstraints", "true", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-textbox-linkage-audited", "TextBox SegmentMask linkage audited", "TextBoxes->SegmentMask", "passed", "source TextBox candidate verdict, block overlap, same-bubble relation, and fallback status are recorded", allBlockIndexes, "SegmentMask refinement silently consumes weak or wrong-bubble TextBox candidates", "recordTextBoxSegmentLinkage", [signal("textBoxSegmentLinkBreakdown", countBy(candidateLedgers.map(\.sourceTextBoxLinkVerdict)).map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","), source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-no-rejected-textbox-silent-selection", "No rejected TextBox silent selection", "TextBoxes->SegmentMask", candidateLedgers.contains { $0.sourceTextBoxLinkVerdict == "rejectedTextBoxCandidate" || $0.sourceTextBoxLinkVerdict == "sourceTextBoxBubbleMismatch" } ? "warning" : "passed", "rejected or wrong-bubble TextBox source must be visible in linkage ledger", blockLedgers.filter { $0.selectedSourceTextBoxLinkVerdict == "rejectedTextBoxCandidate" || $0.selectedSourceTextBoxLinkVerdict == "sourceTextBoxBubbleMismatch" }.map(\.blockIndex), "rejected TextBox candidates are treated as clean SegmentMask constraints", "collectRealTextBoxesOrKeepFallbackExplicit", [signal("selectedTextBoxSegmentLinkBreakdown", countBy(blockLedgers.map(\.selectedSourceTextBoxLinkVerdict)).map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","), source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-bubble-constrained", "Bubble constrained", "BubbleMask", needsRealBubbleMaskBlocks.isEmpty ? "passed" : "warning", "usesBubbleMaskConstraints=true with instance-lite or bubble geometry fallback", needsRealBubbleMaskBlocks, "glyph mask can leak across bubbles without explicit blocker", "collectRealBubbleMask", [signal("usesBubbleMaskConstraints", "true", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-proxy-boundary", "Proxy boundary", "SegmentMask", "passed", "proxyNotRealKoharuSegmentMask=true", allBlockIndexes, "refinement-lite mask is promoted as real Koharu SegmentMask", "keepProxyBoundaryOrCollectRealArtifact", [signal("proxyNotRealKoharuSegmentMask", "true", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-block-ledger-count", "Block ledger count", "blocks", blockLedgers.count == blocks.count ? "passed" : "warning", "blockLedgerCount==totalBlocksDetected", allBlockIndexes, "some final blocks lack SegmentMask refinement ledger rows", "restoreBlockLedgerCoverage", [signal("blockLedgerCount", String(blockLedgers.count), source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-no-ocr-llm-png", "No OCR LLM PNG", "budget", "passed", "no OCR/LLM calls and no PNG output", [], "refinement-lite adds OCR, LLM, or new PNG outputs", "removeHeavyWorkFromSegmentMaskRefinement", [signal("ocrCalls", "0", source: "koharuNativeSegmentMaskRefinementLiteReport"), signal("llmCalls", "0", source: "koharuNativeSegmentMaskRefinementLiteReport"), signal("pngOutputs", "0", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-no-main-flow-writeback", "No main flow writeback", "report", "passed", "diagnosticOnly=true", [], "refinement-lite writes into TextRegion crop, overlay renderer, glyph fill, blockPassed, failureCategory, or currentBlockSource", "keepReportOnly", [signal("diagnosticOnly", "true", source: "koharuNativeSegmentMaskRefinementLiteReport")]),
                gate("G-native-segmentmask-refinement-lite-real-artifact-boundary", "Real artifact boundary", "ExternalArtifacts", "passed", "externalArtifactsRequiredForThisReport=false and active artifacts unchanged", [], "refinement-lite creates or edits active test/koharu_artifacts", "doNotCreateActiveArtifacts", [signal("externalArtifactsRequiredForThisReport", "false", source: "koharuNativeSegmentMaskRefinementLiteReport")])
            ]

            return MangaKoharuNativeSegmentMaskRefinementLiteReport(
                enabled: true,
                source: "AITRANSProbe",
                referencePipeline: "Koharu",
                referenceConcept: "SegmentMask.NativeRefinementLite.TextBoxConstrainedGlyphMask",
                referenceWorkItemID: "WI-koharu-native-segmentmask-refinement-lite",
                evaluatedBlockCount: blocks.count,
                sourceImageWidth: image.width,
                sourceImageHeight: image.height,
                contentCropBBox: contentBBox,
                candidateLedgerCount: candidateLedgers.count,
                blockLedgerCount: blockLedgers.count,
                siblingLedgerCount: siblingLedgers.count,
                gateCount: gates.count,
                groundTruthUsedForDecision: false,
                groundTruthUsedForEvaluationOnly: true,
                wouldChangeMainFlow: false,
                diagnosticOnly: true,
                nativeRefinementLite: true,
                proxyNotRealKoharuSegmentMask: true,
                usesSourceImagePixels: true,
                usesTextBoxConstraints: true,
                usesBubbleMaskConstraints: true,
                externalArtifactsRequiredForThisReport: false,
                refinementLiteVerdict: verdict,
                candidateSourceBreakdown: countBy(candidateLedgers.map(\.source)),
                candidateVerdictBreakdown: countBy(candidateLedgers.map(\.candidateVerdict)),
                pixelEvidenceBreakdown: countBy(candidateLedgers.map { $0.rawPixelCount >= 24 ? "pixelEvidencePresent" : "pixelEvidenceWeak" }),
                textboxClampBreakdown: countBy(candidateLedgers.map { $0.sourceTextBoxCandidateID == nil ? "fallbackFinalBlockBBoxConstraint" : "nativeDetectorLiteConstraint" }),
                bubbleClampBreakdown: countBy(candidateLedgers.map { $0.sourceInstanceLiteID == nil ? "bubbleGeometryFallback" : "instanceLiteConstraint" }),
                componentFilteringBreakdown: countBy(candidateLedgers.map { $0.connectedComponentCount > 0 ? "componentsPresent" : "componentFilteringRejected" }),
                maskContainmentBreakdown: countBy(blockLedgers.map {
                    if $0.maskBBox == nil { return "maskMissing" }
                    if !$0.maskContainedByTextBox { return "maskEscapesTextBox" }
                    if !$0.maskContainedByBubble { return "maskEscapesBubble" }
                    return "containedByTextBoxAndBubble"
                }),
                maskMajorityAgreementBreakdown: countBy(blockLedgers.map(\.maskMajorityAgreement)),
                textBoxSegmentLinkBreakdown: countBy(candidateLedgers.map(\.sourceTextBoxLinkVerdict)),
                segmentFromAcceptedTextBoxCount: candidateLedgers.filter(\.sourceTextBoxAcceptedForSegmentMask).count,
                segmentFromRejectedTextBoxCount: candidateLedgers.filter { $0.sourceTextBoxLinkVerdict == "rejectedTextBoxCandidate" || $0.sourceTextBoxLinkVerdict == "sourceTextBoxBubbleMismatch" }.count,
                segmentFromFallbackBBoxCount: candidateLedgers.filter { $0.sourceTextBoxLinkVerdict == "fallbackFinalBlockBBox" }.count,
                siblingMaskOverlapBreakdown: countBy(siblingLedgers.map(\.sameBubbleSiblingRisk)),
                primaryBottleneckBreakdown: countBy(blockLedgers.map(\.primaryBottleneck)),
                nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                needsRealSegmentMaskBlocks: needsRealSegmentMaskBlocks,
                needsRealTextBoxesBlocks: needsRealTextBoxesBlocks,
                needsRealBubbleMaskBlocks: needsRealBubbleMaskBlocks,
                manualReviewBlocks: manualReviewBlocks,
                renderLockedBlocks: renderLockedBlocks,
                candidateLedgers: candidateLedgers.sorted { $0.candidateID < $1.candidateID },
                blockLedgers: blockLedgers.sorted { $0.blockIndex < $1.blockIndex },
                siblingLedgers: siblingLedgers.sorted { lhs, rhs in
                    if lhs.bubbleID == rhs.bubbleID { return (lhs.instanceLiteID ?? -1) < (rhs.instanceLiteID ?? -1) }
                    return (lhs.bubbleID ?? -1) < (rhs.bubbleID ?? -1)
                },
                gateLedger: gates,
                notes: [
                    "koharuNativeSegmentMaskRefinementLiteReport builds a TextBox-constrained glyph pixel mask ledger from source image pixels inside the existing content crop.",
                    "Detector-lite TextBoxes are preferred; final block bbox fallback is explicit and never promoted as real Koharu TextBoxes.",
                    "Instance-lite BubbleMask or current bubble geometry constrains glyph pixels report-only; no crop, OCR, renderer, clear-text, glyph fill, safeLayoutRect, or overlay state is changed.",
                    "Ground truth appears only in evaluationSignals and never drives thresholds, candidate choice, mask generation, route, nextAction, verdict, or gates."
                ]
            )
        }.value
    }

    func makeKoharuDistanceFieldSafeAreaReport(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        koharuBubbleIndexShadowLedgerReport: MangaKoharuBubbleIndexShadowLedgerReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?
    ) async -> MangaKoharuDistanceFieldSafeAreaReport {
        await Task.detached(priority: .userInitiated) {
            struct DistanceSummary {
                var bubbleID: Int
                var bbox: [Double]
                var maskPixelCount: Int
                var edgePixelCount: Int
                var safeThresholdPx: Double
                var maxDistancePx: Double
                var maxDistancePoint: [Double]?
                var centroidPoint: [Double]?
                var centroidDistancePx: Double?
                var safePixelCount: Int
                var safePixelBBox: [Double]?
                var maximumSafeRect: [Double]?
                var maximumSafeRectArea: Double
                var fallbackReason: String?
            }

            func uniqueSorted(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }
            func joined(_ values: [Int]) -> String { uniqueSorted(values).map(String.init).joined(separator: ",") }
            func countBy(_ values: [String]) -> [String: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
            func area(_ rect: CGRect?) -> Double {
                guard let rect, !rect.isNull, rect.width > 0, rect.height > 0 else { return 0 }
                return Double(rect.width * rect.height)
            }
            func rectIoU(_ lhs: [Double]?, _ rhs: [Double]?) -> Double? {
                guard let lhs, let rhs else { return nil }
                let lhsRect = Self.rect(from: lhs)
                let rhsRect = Self.rect(from: rhs)
                guard area(lhsRect) > 0, area(rhsRect) > 0 else { return nil }
                let intersection = lhsRect.intersection(rhsRect)
                let intersectionArea = area(intersection)
                let unionArea = area(lhsRect) + area(rhsRect) - intersectionArea
                guard unionArea > 0 else { return nil }
                return intersectionArea / unionArea
            }
            func containment(_ inner: [Double]?, in outer: [Double]?) -> Bool? {
                guard let inner, let outer else { return nil }
                return Self.rectContainmentRatio(inner: Self.rect(from: inner), outer: Self.rect(from: outer)) >= 0.995
            }
            func overlapRatio(_ lhs: [Double], _ rhs: [Double]) -> Double {
                let lhsRect = Self.rect(from: lhs)
                let rhsRect = Self.rect(from: rhs)
                guard area(lhsRect) > 0, area(rhsRect) > 0 else { return 0 }
                return area(lhsRect.intersection(rhsRect)) / max(min(area(lhsRect), area(rhsRect)), 1)
            }
            func maxOverlap(_ rects: [[Double]]) -> Double {
                guard rects.count > 1 else { return 0 }
                var result = 0.0
                for lhs in 0..<rects.count {
                    for rhs in (lhs + 1)..<rects.count {
                        result = max(result, overlapRatio(rects[lhs], rects[rhs]))
                    }
                }
                return result
            }
            func signal(
                _ name: String,
                _ value: String,
                source: String,
                decision: Bool = true,
                evaluation: Bool = false
            ) -> MangaKoharuDistanceFieldSignal {
                MangaKoharuDistanceFieldSignal(
                    name: name,
                    value: value,
                    sourceReport: source,
                    groundTruthFreeDecisionSignal: decision,
                    groundTruthUsedForEvaluationOnly: evaluation
                )
            }

            func maximumSafeRect(in safe: [Bool], width: Int, height: Int, originX: Int, originY: Int) -> CGRect? {
                guard width > 0, height > 0 else { return nil }
                var heights = [Int](repeating: 0, count: width)
                var best = CGRect.zero
                var bestArea = 0
                for y in 0..<height {
                    for x in 0..<width {
                        heights[x] = safe[y * width + x] ? heights[x] + 1 : 0
                    }
                    var stack: [Int] = []
                    for x in 0...width {
                        let current = x == width ? 0 : heights[x]
                        while let last = stack.last, heights[last] > current {
                            _ = stack.removeLast()
                            let h = heights[last]
                            let start = (stack.last ?? -1) + 1
                            let rectWidth = x - start
                            let rectArea = h * rectWidth
                            if rectArea > bestArea {
                                bestArea = rectArea
                                best = CGRect(x: originX + start, y: originY + y - h + 1, width: rectWidth, height: h)
                            }
                        }
                        stack.append(x)
                    }
                }
                return bestArea > 0 ? best.integral : nil
            }

            func distanceSummary(for bubble: MangaOverlayProbeBubble, runtime: MangaOverlayBubbleMaskRuntime) -> DistanceSummary {
                let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
                let bubbleRect = Self.clamp(Self.rect(from: bubble.bbox).integral, to: imageBounds)
                let minX = max(0, Int(bubbleRect.minX))
                let maxX = min(runtime.width, Int(bubbleRect.maxX))
                let minY = max(0, Int(bubbleRect.minY))
                let maxY = min(runtime.height, Int(bubbleRect.maxY))
                let localWidth = max(0, maxX - minX)
                let localHeight = max(0, maxY - minY)
                guard localWidth > 0, localHeight > 0 else {
                    return DistanceSummary(bubbleID: bubble.id, bbox: bubble.bbox, maskPixelCount: 0, edgePixelCount: 0, safeThresholdPx: 0, maxDistancePx: 0, maxDistancePoint: nil, centroidPoint: nil, centroidDistancePx: nil, safePixelCount: 0, safePixelBBox: nil, maximumSafeRect: nil, maximumSafeRectArea: 0, fallbackReason: "emptyBubbleBBox")
                }

                let targetID = bubble.id + 1
                var mask = [Bool](repeating: false, count: localWidth * localHeight)
                var maskPixels: [(x: Int, y: Int)] = []
                maskPixels.reserveCapacity(localWidth * localHeight / 2)
                for y in 0..<localHeight {
                    for x in 0..<localWidth where runtime.ids[(minY + y) * runtime.width + (minX + x)] == targetID {
                        mask[y * localWidth + x] = true
                        maskPixels.append((x, y))
                    }
                }
                guard !maskPixels.isEmpty else {
                    return DistanceSummary(bubbleID: bubble.id, bbox: bubble.bbox, maskPixelCount: 0, edgePixelCount: 0, safeThresholdPx: 0, maxDistancePx: 0, maxDistancePoint: nil, centroidPoint: nil, centroidDistancePx: nil, safePixelCount: 0, safePixelBBox: nil, maximumSafeRect: nil, maximumSafeRectArea: 0, fallbackReason: "emptyProxyMask")
                }

                let large = 1_000_000
                var distances = [Int](repeating: large, count: localWidth * localHeight)
                var edgeCount = 0
                for pixel in maskPixels {
                    let x = pixel.x
                    let y = pixel.y
                    let index = y * localWidth + x
                    var edge = false
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx
                            let ny = y + dy
                            if nx < 0 || ny < 0 || nx >= localWidth || ny >= localHeight || !mask[ny * localWidth + nx] {
                                edge = true
                            }
                        }
                    }
                    if edge {
                        edgeCount += 1
                        distances[index] = 0
                    }
                }

                if edgeCount == 0 {
                    for pixel in maskPixels {
                        distances[pixel.y * localWidth + pixel.x] = 0
                    }
                } else {
                    for y in 0..<localHeight {
                        for x in 0..<localWidth where mask[y * localWidth + x] {
                            let index = y * localWidth + x
                            if x > 0 { distances[index] = min(distances[index], distances[index - 1] + 10) }
                            if y > 0 { distances[index] = min(distances[index], distances[index - localWidth] + 10) }
                            if x > 0 && y > 0 { distances[index] = min(distances[index], distances[index - localWidth - 1] + 14) }
                            if x + 1 < localWidth && y > 0 { distances[index] = min(distances[index], distances[index - localWidth + 1] + 14) }
                        }
                    }
                    if localHeight > 0 {
                        for y in stride(from: localHeight - 1, through: 0, by: -1) {
                            for x in stride(from: localWidth - 1, through: 0, by: -1) where mask[y * localWidth + x] {
                                let index = y * localWidth + x
                                if x + 1 < localWidth { distances[index] = min(distances[index], distances[index + 1] + 10) }
                                if y + 1 < localHeight { distances[index] = min(distances[index], distances[index + localWidth] + 10) }
                                if x + 1 < localWidth && y + 1 < localHeight { distances[index] = min(distances[index], distances[index + localWidth + 1] + 14) }
                                if x > 0 && y + 1 < localHeight { distances[index] = min(distances[index], distances[index + localWidth - 1] + 14) }
                            }
                        }
                    }
                }

                var maxDistance = 0
                var maxPoint: (x: Int, y: Int)?
                var sumX = 0
                var sumY = 0
                let threshold = max(3.0, Double(min(localWidth, localHeight)) * 0.12)
                var safe = [Bool](repeating: false, count: localWidth * localHeight)
                var safeCount = 0
                var safeMinX = localWidth
                var safeMinY = localHeight
                var safeMaxX = -1
                var safeMaxY = -1
                for pixel in maskPixels {
                    let index = pixel.y * localWidth + pixel.x
                    let distance = distances[index]
                    sumX += pixel.x
                    sumY += pixel.y
                    if distance > maxDistance {
                        maxDistance = distance
                        maxPoint = pixel
                    }
                    if Double(distance) / 10.0 >= threshold {
                        safe[index] = true
                        safeCount += 1
                        safeMinX = min(safeMinX, pixel.x)
                        safeMinY = min(safeMinY, pixel.y)
                        safeMaxX = max(safeMaxX, pixel.x)
                        safeMaxY = max(safeMaxY, pixel.y)
                    }
                }

                let centroidX = Int((Double(sumX) / Double(maskPixels.count)).rounded())
                let centroidY = Int((Double(sumY) / Double(maskPixels.count)).rounded())
                let centroidIndex = centroidY >= 0 && centroidY < localHeight && centroidX >= 0 && centroidX < localWidth
                    ? centroidY * localWidth + centroidX
                    : nil
                let centroidDistance = centroidIndex.flatMap { mask[$0] ? Double(distances[$0]) / 10.0 : nil }
                let safeBBox: CGRect? = safeCount > 0
                    ? CGRect(x: minX + safeMinX, y: minY + safeMinY, width: safeMaxX - safeMinX + 1, height: safeMaxY - safeMinY + 1)
                    : nil
                let maxRect = maximumSafeRect(in: safe, width: localWidth, height: localHeight, originX: minX, originY: minY)
                let fallbackReason = safeCount == 0 ? "safePixelThresholdTooHighForProxyMask" : (maxRect == nil ? "maximumSafeRectUnavailable" : nil)
                return DistanceSummary(
                    bubbleID: bubble.id,
                    bbox: bubble.bbox,
                    maskPixelCount: maskPixels.count,
                    edgePixelCount: edgeCount,
                    safeThresholdPx: threshold,
                    maxDistancePx: Double(maxDistance) / 10.0,
                    maxDistancePoint: maxPoint.map { [Double(minX + $0.x), Double(minY + $0.y)] },
                    centroidPoint: [Double(minX + centroidX), Double(minY + centroidY)],
                    centroidDistancePx: centroidDistance,
                    safePixelCount: safeCount,
                    safePixelBBox: safeBBox.map(Self.bboxArray(from:)),
                    maximumSafeRect: maxRect.map(Self.bboxArray(from:)),
                    maximumSafeRectArea: area(maxRect),
                    fallbackReason: fallbackReason
                )
            }

            let runtime = Self.makeApproximateBubbleMaskRuntime(image: image, bubbleGeometry: bubbleGeometry)
            let summaries = Dictionary(uniqueKeysWithValues: bubbleGeometry.bubbles.map { bubble in
                (bubble.id, distanceSummary(for: bubble, runtime: runtime))
            })
            let maskInstancesByBubble = Dictionary(uniqueKeysWithValues: (bubbleMaskReport?.instances ?? []).map { ($0.bubbleID, $0) })
            let bubbleIndexByBlock = Dictionary(uniqueKeysWithValues: (koharuBubbleIndexShadowLedgerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) })
            let renderByBlock = Dictionary(uniqueKeysWithValues: (koharuRenderRegressionLockReport?.blockLocks ?? []).map { ($0.blockIndex, $0) })
            let splitCandidates = bubbleSplitCandidateReport?.diagnostics ?? []
            let splitCandidatesByBlock = Dictionary(grouping: splitCandidates.flatMap { candidate in
                candidate.seedBlockIndexes.map { (blockIndex: $0, candidate: candidate) }
            }) { $0.blockIndex }
            let blocksByBubble = Dictionary(grouping: blocks.compactMap { block -> (Int, MangaOverlayProbeBlock)? in
                guard let bubbleID = block.bubbleID else { return nil }
                return (bubbleID, block)
            }) { $0.0 }.mapValues { $0.map(\.1).sorted { $0.index < $1.index } }

            let siblingGroups = blocksByBubble
                .filter { $0.value.count > 1 }
                .map { (bubbleID: $0.key, blocks: $0.value) }
                .sorted { $0.bubbleID < $1.bubbleID }
            let siblingGroupIDsByBubble = Dictionary(uniqueKeysWithValues: siblingGroups.map { ($0.bubbleID, ["DF-\($0.bubbleID)"]) })

            let bubbleLedgers: [MangaKoharuDistanceFieldBubbleLedger] = bubbleGeometry.bubbles.map { bubble in
                let summary = summaries[bubble.id]
                let currentMaskSafeRect = maskInstancesByBubble[bubble.id]?.safeRect ?? runtime.safeRectsByBubbleID[bubble.id].map(Self.bboxArray(from:))
                let distanceRect = summary?.maximumSafeRect ?? currentMaskSafeRect
                let iou = rectIoU(currentMaskSafeRect, distanceRect)
                let maskPixels = max(summary?.maskPixelCount ?? 0, 1)
                let safeCount = summary?.safePixelCount ?? 0
                let verdict: String
                if bubbleMaskReport == nil {
                    verdict = "needsRealBubbleMask"
                } else if safeCount == 0 {
                    verdict = "fallbackToCurrentMaskSafeRect"
                } else if (summary?.maximumSafeRect) != nil {
                    verdict = "maximumSafeRectAvailable"
                } else if (summary?.safePixelBBox) != nil {
                    verdict = "safePixelBBoxFallback"
                } else {
                    verdict = "safeAreaTooSmall"
                }
                let action: String
                if verdict == "needsRealBubbleMask" {
                    action = "collectRealBubbleMaskArtifact"
                } else if verdict == "fallbackToCurrentMaskSafeRect" || verdict == "safeAreaTooSmall" {
                    action = "keepCurrentSafeLayoutReportOnly"
                } else {
                    action = "keepDistanceFieldSafeAreaReportOnly"
                }
                let blockIndexes = blocksByBubble[bubble.id]?.map(\.index) ?? []
                return MangaKoharuDistanceFieldBubbleLedger(
                    bubbleID: bubble.id,
                    bbox: bubble.bbox,
                    maskPixelCount: summary?.maskPixelCount ?? 0,
                    edgePixelCount: summary?.edgePixelCount ?? 0,
                    distanceMetric: "twoPassChamfer8Neighbor",
                    safeThresholdPx: summary?.safeThresholdPx ?? 0,
                    maxDistancePx: summary?.maxDistancePx ?? 0,
                    maxDistancePoint: summary?.maxDistancePoint,
                    centroidPoint: summary?.centroidPoint,
                    centroidDistancePx: summary?.centroidDistancePx,
                    safePixelCount: safeCount,
                    safePixelCoverageRatio: Double(safeCount) / Double(maskPixels),
                    safePixelBBox: summary?.safePixelBBox,
                    maximumSafeRect: distanceRect,
                    maximumSafeRectAlgorithm: summary?.maximumSafeRect == nil ? "safePixelBBoxOrCurrentMaskSafeRectFallback" : "histogramMaxRectangleOnSafePixels",
                    maximumSafeRectArea: summary?.maximumSafeRectArea ?? area(currentMaskSafeRect.map(Self.rect(from:))),
                    safeRectCoverageRatio: area(distanceRect.map(Self.rect(from:))) / Double(maskPixels),
                    currentMaskSafeRect: currentMaskSafeRect,
                    currentVsDistanceSafeRectIoU: iou,
                    blockIndexes: blockIndexes,
                    siblingGroupIDs: siblingGroupIDsByBubble[bubble.id] ?? [],
                    safePixelVerdict: verdict,
                    fallbackReason: summary?.fallbackReason,
                    nextAction: action,
                    decisionSignals: [
                        signal("distanceMetric", "twoPassChamfer8Neighbor", source: "koharuDistanceFieldSafeAreaReport"),
                        signal("safePixelCount", String(safeCount), source: "koharuDistanceFieldSafeAreaReport"),
                        signal("currentVsDistanceSafeRectIoU", iou?.formatted(.number.precision(.fractionLength(4))) ?? "nil", source: "koharuDistanceFieldSafeAreaReport")
                    ],
                    evaluationSignals: [
                        signal("dialogueBlockCount", String(blocks.filter { blockIndexes.contains($0.index) && $0.bestGroundTruthType == "dialogue" }.count), source: "blocks.bestGroundTruthType", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }.sorted { $0.bubbleID < $1.bubbleID }
            let bubbleLedgerByID = Dictionary(uniqueKeysWithValues: bubbleLedgers.map { ($0.bubbleID, $0) })

            let blockLedgers: [MangaKoharuDistanceFieldBlockLedger] = blocks.map { block in
                let bubbleLedger = block.bubbleID.flatMap { bubbleLedgerByID[$0] }
                let distanceRect = bubbleLedger?.maximumSafeRect ?? block.safeLayoutRect
                let currentRect = block.safeLayoutRect
                let currentArea = area(currentRect.map(Self.rect(from:)))
                let distanceArea = area(distanceRect.map(Self.rect(from:)))
                let areaDelta = currentArea > 0 ? (distanceArea - currentArea) / currentArea : nil
                let iou = rectIoU(currentRect, distanceRect)
                let spriteBounds = renderByBlock[block.index]?.renderNonTransparentBounds ?? block.renderNonTransparentBounds
                let spriteCurrent = containment(spriteBounds, in: currentRect)
                let spriteDistance = containment(spriteBounds, in: distanceRect)
                let render = renderByBlock[block.index]
                let renderVerdict = render?.renderStatus == "textTruncated" || render?.renderStatus == "maskOverflowUnresolved" || render?.renderStatus == "renderCollisionUnresolved" ? "renderIssueOpen" : "renderLocked"
                let comparison: String
                if renderVerdict == "renderIssueOpen" {
                    comparison = "currentRectAlreadyRenderLocked"
                } else if bubbleMaskReport == nil || block.bubbleID == nil {
                    comparison = "needsRealBubbleMask"
                } else if distanceRect == nil {
                    comparison = "missingDistanceRect"
                } else if spriteDistance == false {
                    comparison = "distanceRectWouldRiskSprite"
                } else if let iou, iou >= 0.86 {
                    comparison = "distanceRectMatchesCurrent"
                } else if let areaDelta, areaDelta > 0.12 {
                    comparison = "distanceRectLargerReportOnly"
                } else if let areaDelta, areaDelta < -0.12 {
                    comparison = "distanceRectSmallerReportOnly"
                } else {
                    comparison = "manualReviewOnly"
                }
                let action: String
                if comparison == "needsRealBubbleMask" {
                    action = "collectRealBubbleMaskArtifact"
                } else if comparison == "currentRectAlreadyRenderLocked" {
                    action = "inspectRenderLockGateLedger"
                } else if comparison == "distanceRectWouldRiskSprite" {
                    action = "keepCurrentSafeLayoutReportOnly"
                } else if comparison == "manualReviewOnly" {
                    action = "manualReviewOnly"
                } else {
                    action = "keepDistanceFieldSafeAreaReportOnly"
                }
                let spriteContainmentValue: String
                if spriteCurrent == true && spriteDistance == true {
                    spriteContainmentValue = "containedByBoth"
                } else if spriteCurrent == true && spriteDistance == false {
                    spriteContainmentValue = "distanceRectRisk"
                } else if spriteCurrent == false && spriteDistance == true {
                    spriteContainmentValue = "distanceRectImprovesContainment"
                } else {
                    spriteContainmentValue = "spriteBoundsUnavailableOrUncontained"
                }
                return MangaKoharuDistanceFieldBlockLedger(
                    blockIndex: block.index,
                    bubbleID: block.bubbleID,
                    bbox: block.bbox,
                    blockPassed: block.blockPassed,
                    failureCategory: block.failureCategory,
                    groundTruthMatch: block.groundTruthMatch,
                    bestGroundTruthType: block.bestGroundTruthType,
                    ocrSimilarityForEvaluation: block.ocrGroundTruthSimilarity,
                    currentSafeLayoutRect: currentRect,
                    currentSafeLayoutSource: block.safeLayoutSource,
                    bubbleIndexShadowSafeRect: bubbleIndexByBlock[block.index]?.shadowSafeLayoutRect,
                    distanceFieldSafeRect: distanceRect,
                    distanceFieldSafeRectSource: bubbleLedger?.maximumSafeRect == nil ? "fallbackCurrentSafeLayoutRect" : "koharuDistanceFieldSafeAreaReport.maximumSafeRect",
                    currentVsDistanceSafeRectIoU: iou,
                    currentVsDistanceAreaDeltaRatio: areaDelta,
                    spriteBounds: spriteBounds,
                    spriteContainedByCurrentSafeRect: spriteCurrent,
                    spriteContainedByDistanceSafeRect: spriteDistance,
                    renderLockVerdict: renderVerdict,
                    safeRectComparisonVerdict: comparison,
                    safeRectComparisonSignals: [
                        signal("currentVsDistanceSafeRectIoU", iou?.formatted(.number.precision(.fractionLength(4))) ?? "nil", source: "koharuDistanceFieldSafeAreaReport"),
                        signal("areaDeltaRatio", areaDelta?.formatted(.number.precision(.fractionLength(4))) ?? "nil", source: "koharuDistanceFieldSafeAreaReport"),
                        signal("spriteContainment", spriteContainmentValue, source: "koharuDistanceFieldSafeAreaReport")
                    ],
                    primaryBottleneck: bubbleIndexByBlock[block.index]?.primaryBottleneck ?? block.failureCategory,
                    nextAction: action,
                    decisionSignals: [
                        signal("safeRectComparisonVerdict", comparison, source: "koharuDistanceFieldSafeAreaReport"),
                        signal("renderLockVerdict", renderVerdict, source: "koharuRenderRegressionLockReport"),
                        signal("nextAction", action, source: "koharuDistanceFieldSafeAreaReport")
                    ],
                    evaluationSignals: [
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks.groundTruthMatch", decision: false, evaluation: true),
                        signal("bestGroundTruthType", block.bestGroundTruthType ?? "nil", source: "blocks.bestGroundTruthType", decision: false, evaluation: true),
                        signal("ocrSimilarityForEvaluation", block.ocrGroundTruthSimilarity?.formatted(.number.precision(.fractionLength(4))) ?? "nil", source: "blocks.ocrGroundTruthSimilarity", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }.sorted { $0.blockIndex < $1.blockIndex }

            let siblingLedgers: [MangaKoharuDistanceFieldSiblingLedger] = siblingGroups.map { group in
                let blockIndexes = group.blocks.map(\.index)
                let currentRects = group.blocks.compactMap(\.safeLayoutRect)
                let distanceRect = bubbleLedgerByID[group.bubbleID]?.maximumSafeRect
                let currentOverlap = maxOverlap(currentRects)
                let distanceArea = area(distanceRect.map(Self.rect(from:)))
                let currentTotalArea = currentRects.reduce(0.0) { $0 + area(Self.rect(from: $1)) }
                let sharedRatio = currentTotalArea > 0 ? distanceArea / currentTotalArea : 0
                let minPerBlockRatio = group.blocks.reduce(1.0) { partial, block in
                    let blockArea = area(block.safeLayoutRect.map(Self.rect(from:)))
                    let ratio = blockArea > 0 ? distanceArea / (blockArea * Double(group.blocks.count)) : 0
                    return min(partial, ratio)
                }
                let splitIDs = uniqueSorted(blockIndexes.flatMap { blockIndex in
                    (splitCandidatesByBlock[blockIndex] ?? []).map { $0.candidate.id }
                })
                let verdict: String
                if bubbleMaskReport == nil {
                    verdict = "needsRealBubbleMask"
                } else if !splitIDs.isEmpty {
                    verdict = "splitCandidatePresent"
                } else if currentOverlap >= 0.18 {
                    verdict = "partitionOverlapRisk"
                } else if distanceRect == nil || minPerBlockRatio < 0.55 {
                    verdict = "distanceSafeAreaTooSmallForSiblings"
                } else {
                    verdict = "distanceSafeAreaSupportsCurrentPartitions"
                }
                let action = verdict == "distanceSafeAreaSupportsCurrentPartitions"
                    ? "keepSiblingDistanceLedgerReportOnly"
                    : (verdict == "needsRealBubbleMask" ? "collectRealBubbleMaskArtifact" : "reviewDistanceFieldSiblingPartition")
                return MangaKoharuDistanceFieldSiblingLedger(
                    siblingGroupID: "DF-\(group.bubbleID)",
                    bubbleID: group.bubbleID,
                    blockIndexes: blockIndexes,
                    currentSafeLayoutRects: currentRects,
                    distanceFieldSafeRect: distanceRect,
                    currentMaxOverlapRatio: currentOverlap,
                    distanceRectSharedAreaRatio: sharedRatio,
                    minimumPerBlockAreaRatio: minPerBlockRatio,
                    splitCandidateIDs: splitIDs,
                    siblingDistanceVerdict: verdict,
                    nextAction: action,
                    decisionSignals: [
                        signal("currentMaxOverlapRatio", currentOverlap.formatted(.number.precision(.fractionLength(4))), source: "blocks.safeLayoutRect"),
                        signal("distanceRectSharedAreaRatio", sharedRatio.formatted(.number.precision(.fractionLength(4))), source: "koharuDistanceFieldSafeAreaReport"),
                        signal("splitCandidateIDs", splitIDs.map(String.init).joined(separator: ","), source: "bubbleSplitCandidateReport")
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }

            let safeRectDiffBlocks = uniqueSorted(blockLedgers.filter {
                guard let iou = $0.currentVsDistanceSafeRectIoU else { return false }
                return iou < 0.86
            }.map(\.blockIndex))
            let spriteRiskBlocks = uniqueSorted(blockLedgers.filter { $0.safeRectComparisonVerdict == "distanceRectWouldRiskSprite" }.map(\.blockIndex))
            let siblingRiskBlocks = uniqueSorted(siblingLedgers.filter { $0.siblingDistanceVerdict != "distanceSafeAreaSupportsCurrentPartitions" }.flatMap(\.blockIndexes))
            let needsRealBubbleMaskBlocks = uniqueSorted(blockLedgers.filter { $0.safeRectComparisonVerdict == "needsRealBubbleMask" }.map(\.blockIndex))
            let renderLockedBlocks = uniqueSorted(blockLedgers.filter { $0.renderLockVerdict == "renderLocked" }.map(\.blockIndex))
            let manualReviewBlocks = uniqueSorted(blockLedgers.filter { $0.nextAction == "manualReviewOnly" }.map(\.blockIndex))

            func gate(
                _ id: String,
                _ name: String,
                _ scope: String,
                _ status: String,
                _ threshold: String,
                _ affected: [Int],
                _ failure: String,
                _ action: String,
                _ signals: [MangaKoharuDistanceFieldSignal]
            ) -> MangaKoharuDistanceFieldGate {
                MangaKoharuDistanceFieldGate(
                    gateID: id,
                    gateName: name,
                    scope: scope,
                    status: status,
                    threshold: threshold,
                    affectedBlocks: uniqueSorted(affected),
                    decisionSignals: signals,
                    failureMeans: failure,
                    recommendedAction: action,
                    groundTruthUsedForDecision: false
                )
            }

            let allBlocks = blocks.map(\.index)
            let gateLedger = [
                gate("G-distance-field-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "DistanceField safe area mutates OCR, translation, safeLayoutRect, renderer, or block pass state", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-no-ground-truth-decision", "No ground truth decision", "report", "passed", "groundTruthUsedForDecision=false", allBlocks, "ground truth influences safe pixels, maximum rect, sibling verdict, gate, or next action", "moveGroundTruthToEvaluationSignalsOnly", [signal("groundTruthUsedForDecision", "false", source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-rounded-proxy-boundary", "Rounded proxy boundary", "BubbleMask", "passed", "proxyNotRealBubbleMask=true and usesRoundedRectProxyMask=true", allBlocks, "rounded-rect proxy is promoted as real Koharu BubbleMask", "keepProxyBoundaryOrCollectRealArtifact", [signal("usesRoundedRectProxyMask", "true", source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-bubble-ledger-count", "Bubble ledger count", "BubbleIndex", bubbleLedgers.count == (bubbleMaskReport?.instanceCount ?? bubbleGeometry.bubbles.count) ? "passed" : "warning", "bubbleLedgerCount==bubbleMaskReport.instanceCount", allBlocks, "distance field bubble ledger count does not match proxy bubble instances", "inspectBubbleMaskRuntime", [signal("bubbleLedgerCount", String(bubbleLedgers.count), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-block-ledger-count", "Block ledger count", "blocks", blockLedgers.count == blocks.count ? "passed" : "warning", "blockLedgerCount==totalBlocksDetected", allBlocks, "some final blocks lack distance-field safe area comparison", "restoreDistanceFieldBlockLedger", [signal("blockLedgerCount", String(blockLedgers.count), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-safe-pixels-computed", "Safe pixels computed", "BubbleIndex", bubbleLedgers.contains { $0.safePixelCount > 0 } ? "passed" : "warning", "at least one proxy bubble has safe pixels", allBlocks, "distance field never finds safe pixels and only falls back", "inspectSafeThreshold", [signal("safePixelBubbleCount", String(bubbleLedgers.filter { $0.safePixelCount > 0 }.count), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-maximum-safe-rect", "Maximum safe rect", "BubbleIndex", bubbleLedgers.contains { $0.maximumSafeRect != nil } ? "passed" : "warning", "maximumSafeRect available or fallback reason explicit", allBlocks, "safe pixels exist but no safe rect or fallback reason is recorded", "inspectMaximumSafeRectAlgorithm", [signal("maximumSafeRectCount", String(bubbleLedgers.filter { $0.maximumSafeRect != nil }.count), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-sprite-containment", "Sprite containment", "RenderedSprites", spriteRiskBlocks.isEmpty ? "passed" : "warning", "distance rect must not be promoted when sprite containment regresses", spriteRiskBlocks, "distance-field safe rect would clip existing rendered sprite", "keepCurrentSafeLayoutReportOnly", [signal("spriteRiskBlocks", joined(spriteRiskBlocks), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-sibling-audited", "Sibling audited", "BubbleIndex", siblingLedgers.isEmpty || siblingRiskBlocks.isEmpty ? "passed" : "warning", "same-bubble sibling groups have report-only distance safe-area comparison", siblingRiskBlocks, "sibling distance safe area conflicts are hidden or applied to renderer", "reviewDistanceFieldSiblingPartition", [signal("siblingLedgerCount", String(siblingLedgers.count), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-distance-field-render-lock-respected", "Render lock respected", "FinalRender", koharuRenderRegressionLockReport == nil ? "warning" : "passed", "render lock remains upstream evidence only", koharuRenderRegressionLockReport?.renderIssueBlocks ?? [], "DistanceField report ignores render lock or changes overlay output", "inspectRenderLockGateLedger", [signal("renderLockVerdict", koharuRenderRegressionLockReport?.renderLockVerdict ?? "nil", source: "koharuRenderRegressionLockReport")]),
                gate("G-distance-field-bubble-index-linked", "BubbleIndex linked", "BubbleIndex", koharuBubbleIndexShadowLedgerReport == nil ? "warning" : "passed", "v1.35 BubbleIndex shadow ledger is available as comparison input", allBlocks, "distance-field report cannot compare against BubbleIndex shadow ledger", "restoreKoharuBubbleIndexShadowLedgerReport", [signal("bubbleIndexReportAvailable", String(koharuBubbleIndexShadowLedgerReport != nil), source: "koharuBubbleIndexShadowLedgerReport")]),
                gate("G-distance-field-ci-fast-ready", "CI fast ready", "ci-fast", "passed", "uses existing proxy mask and reports only", allBlocks, "DistanceField report adds OCR/LLM/full-only dependency", "keepCIFastReportOnly", [signal("inputReports", "bubbleGeometry,bubbleMaskReport,koharuBubbleIndexShadowLedgerReport,koharuRenderRegressionLockReport", source: "koharuDistanceFieldSafeAreaReport")])
            ]

            let distanceFieldVerdict: String
            if bubbleMaskReport == nil {
                distanceFieldVerdict = "blockedByMissingBubbleMaskProxy"
            } else if koharuBubbleIndexShadowLedgerReport == nil {
                distanceFieldVerdict = "blockedByMissingBubbleIndexLedger"
            } else if !needsRealBubbleMaskBlocks.isEmpty {
                distanceFieldVerdict = "needsRealBubbleMaskArtifact"
            } else if !spriteRiskBlocks.isEmpty {
                distanceFieldVerdict = "renderLockedNoPromotion"
            } else if !manualReviewBlocks.isEmpty || !siblingRiskBlocks.isEmpty {
                distanceFieldVerdict = "manualReviewOnly"
            } else if safeRectDiffBlocks.isEmpty {
                distanceFieldVerdict = "distanceFieldShadowReady"
            } else {
                distanceFieldVerdict = "reportOnlySafeAreaCandidateReady"
            }

            return MangaKoharuDistanceFieldSafeAreaReport(
                enabled: true,
                source: "AITRANSProbe",
                referencePipeline: "Koharu",
                referenceConcept: "BubbleIndex.DistanceFieldSafePixels.MaximumSafeRect",
                evaluatedBlockCount: blocks.count,
                evaluatedBubbleCount: bubbleMaskReport?.instanceCount ?? bubbleGeometry.bubbles.count,
                bubbleLedgerCount: bubbleLedgers.count,
                blockLedgerCount: blockLedgers.count,
                siblingLedgerCount: siblingLedgers.count,
                gateCount: gateLedger.count,
                groundTruthUsedForDecision: false,
                groundTruthUsedForEvaluationOnly: true,
                wouldChangeMainFlow: false,
                diagnosticOnly: true,
                proxyNotRealBubbleMask: true,
                usesRoundedRectProxyMask: true,
                externalArtifactsRequiredForThisReport: false,
                distanceFieldVerdict: distanceFieldVerdict,
                safePixelVerdictBreakdown: countBy(bubbleLedgers.map(\.safePixelVerdict)),
                safeRectComparisonBreakdown: countBy(blockLedgers.map(\.safeRectComparisonVerdict)),
                spriteContainmentBreakdown: countBy(blockLedgers.map { ledger in
                    if ledger.spriteContainedByCurrentSafeRect == true && ledger.spriteContainedByDistanceSafeRect == true { return "containedByBoth" }
                    if ledger.spriteContainedByCurrentSafeRect == true && ledger.spriteContainedByDistanceSafeRect == false { return "distanceRectRisk" }
                    if ledger.spriteContainedByCurrentSafeRect == false && ledger.spriteContainedByDistanceSafeRect == true { return "distanceRectImprovesContainment" }
                    return "spriteBoundsUnavailableOrUncontained"
                }),
                siblingDistanceVerdictBreakdown: countBy(siblingLedgers.map(\.siblingDistanceVerdict)),
                nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                safeRectDiffBlocks: safeRectDiffBlocks,
                spriteRiskBlocks: spriteRiskBlocks,
                siblingRiskBlocks: siblingRiskBlocks,
                needsRealBubbleMaskBlocks: needsRealBubbleMaskBlocks,
                renderLockedBlocks: renderLockedBlocks,
                manualReviewBlocks: manualReviewBlocks,
                bubbleLedgers: bubbleLedgers,
                blockLedgers: blockLedgers,
                siblingLedgers: siblingLedgers,
                gateLedger: gateLedger,
                notes: [
                    "koharuDistanceFieldSafeAreaReport is a report-only Koharu BubbleIndex distance-field safe area shadow report.",
                    "It computes safe pixels and maximum safe rectangles from AITRANS rounded-rect BubbleMask proxy IDs inside each bubble bbox; it does not use real Koharu BubbleMask artifacts.",
                    "Ground truth appears only in evaluationSignals; safe pixel verdicts, safe rect comparison, sibling verdicts, gates, and nextAction use ground-truth-free geometry/render signals.",
                    "The report does not add OCR or LLM calls and does not change OCR, translation input, safeLayoutRect, glyphMaskFillRects, background fill, overlay rendering, blockPassed, failureCategory, active artifacts, currentBlockSource, or PNG output behavior."
                ]
            )
        }.value
    }

    func makeKoharuBubbleAdjacencySeamReport(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        bubbleSplitCandidateReport: MangaOverlayBubbleSplitCandidateReport?,
        koharuBubbleIndexShadowLedgerReport: MangaKoharuBubbleIndexShadowLedgerReport?,
        koharuDistanceFieldSafeAreaReport: MangaKoharuDistanceFieldSafeAreaReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?
    ) async -> MangaKoharuBubbleAdjacencySeamReport {
        do {
            func uniqueSorted(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }
            func uniqueSortedStrings(_ values: [String]) -> [String] { Array(Set(values)).sorted() }
            func countBy(_ values: [String]) -> [String: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
            func joined(_ values: [Int]) -> String { uniqueSorted(values).map(String.init).joined(separator: ",") }
            func area(_ rect: CGRect?) -> Double {
                guard let rect, !rect.isNull, rect.width > 0, rect.height > 0 else { return 0 }
                return Double(rect.width * rect.height)
            }
            func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
            func rectGap(_ lhs: CGRect, _ rhs: CGRect) -> Double {
                let dx = max(0, max(lhs.minX - rhs.maxX, rhs.minX - lhs.maxX))
                let dy = max(0, max(lhs.minY - rhs.maxY, rhs.minY - lhs.maxY))
                return hypot(Double(dx), Double(dy))
            }
            func rectOverlapArea(_ lhs: CGRect, _ rhs: CGRect) -> Double {
                area(lhs.intersection(rhs))
            }
            func signal(
                _ name: String,
                _ value: String,
                source: String,
                decision: Bool = true,
                evaluation: Bool = false
            ) -> MangaKoharuBubbleAdjacencySeamSignal {
                MangaKoharuBubbleAdjacencySeamSignal(
                    name: name,
                    value: value,
                    sourceReport: source,
                    groundTruthFreeDecisionSignal: decision,
                    groundTruthUsedForEvaluationOnly: evaluation
                )
            }
            func formatted(_ value: Double?) -> String {
                value?.formatted(.number.precision(.fractionLength(4))) ?? "nil"
            }

            let allBlocks = blocks.map(\.index)
            let runtime = Self.makeApproximateBubbleMaskRuntime(image: image, bubbleGeometry: bubbleGeometry)
            let splitCandidates = bubbleSplitCandidateReport?.diagnostics ?? []
            let splitCandidatesByParent = Dictionary(grouping: splitCandidates, by: \.parentBubbleID)
            let splitCandidatesByBlock = Dictionary(grouping: splitCandidates.flatMap { candidate in
                candidate.seedBlockIndexes.map { (blockIndex: $0, candidate: candidate) }
            }) { $0.blockIndex }
            let bubbleIndexByBlock = Dictionary(uniqueKeysWithValues: (koharuBubbleIndexShadowLedgerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) })
            let distanceFieldByBlock = Dictionary(uniqueKeysWithValues: (koharuDistanceFieldSafeAreaReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) })
            let blocksByBubble = Dictionary(grouping: blocks.compactMap { block -> (Int, MangaOverlayProbeBlock)? in
                guard let bubbleID = block.bubbleID else { return nil }
                return (bubbleID, block)
            }) { $0.0 }.mapValues { $0.map(\.1).sorted { $0.index < $1.index } }
            let siblingGroups = blocksByBubble
                .filter { $0.value.count > 1 }
                .map { (bubbleID: $0.key, groupID: "SEAM-\($0.key)", blocks: $0.value) }
                .sorted { $0.bubbleID < $1.bubbleID }
            let siblingGroupIDsByBubble = Dictionary(uniqueKeysWithValues: siblingGroups.map { ($0.bubbleID, [$0.groupID]) })
            let siblingBlocksByBlock = Dictionary(uniqueKeysWithValues: blocks.map { block in
                let siblings = block.bubbleID.flatMap { blocksByBubble[$0] }?.map(\.index).filter { $0 != block.index } ?? []
                return (block.index, siblings)
            })
            let assignmentConflictBlocks = uniqueSorted(
                (bubbleMaskReport?.inconsistentBubbleAssignmentBlocks ?? [])
                + (koharuBubbleIndexShadowLedgerReport?.conflictBlocks ?? [])
            )
            let renderLockedBlocks = uniqueSorted(
                (koharuRenderRegressionLockReport?.blockLocks.filter { $0.renderStatus == "renderLocked" }.map(\.blockIndex) ?? [])
                + (koharuRenderRegressionLockReport?.renderIssueBlocks ?? [])
                + blocks.filter { $0.renderCollisionChecked && $0.renderCollisionResolved }.map(\.index)
            )
            let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(runtime.width), height: CGFloat(runtime.height))
            let bubbleRectsByID = Dictionary(
                uniqueKeysWithValues: bubbleGeometry.bubbles.map { bubble in
                    (bubble.id, Self.rect(from: bubble.bbox).intersection(imageBounds).integral)
                }
            )

            func proxyBoundarySamples(for bubbleID: Int, maxSamples: Int = 384) -> [(Int, Int)] {
                guard let rect = bubbleRectsByID[bubbleID],
                      !rect.isNull,
                      rect.width >= 1,
                      rect.height >= 1 else {
                    return []
                }
                let targetID = bubbleID + 1
                let minX = max(0, Int(rect.minX))
                let maxX = min(runtime.width, Int(rect.maxX))
                let minY = max(0, Int(rect.minY))
                let maxY = min(runtime.height, Int(rect.maxY))
                guard minX < maxX, minY < maxY else { return [] }
                let areaPixels = max(1, (maxX - minX) * (maxY - minY))
                let sampleStride = max(1, Int(ceil(sqrt(Double(areaPixels) / Double(maxSamples)))))
                func maskID(at x: Int, _ y: Int) -> Int {
                    guard x >= 0, x < runtime.width, y >= 0, y < runtime.height else { return 0 }
                    return runtime.ids[y * runtime.width + x]
                }
                func isBoundary(_ x: Int, _ y: Int) -> Bool {
                    maskID(at: x - 1, y) != targetID
                    || maskID(at: x + 1, y) != targetID
                    || maskID(at: x, y - 1) != targetID
                    || maskID(at: x, y + 1) != targetID
                }

                var samples: [(Int, Int)] = []
                var y = minY
                while y < maxY {
                    var x = minX
                    while x < maxX {
                        if maskID(at: x, y) == targetID, isBoundary(x, y) {
                            samples.append((x, y))
                        }
                        x += sampleStride
                    }
                    y += sampleStride
                }
                if samples.isEmpty {
                    y = minY
                    while y < maxY {
                        var x = minX
                        while x < maxX {
                            if maskID(at: x, y) == targetID {
                                samples.append((x, y))
                            }
                            x += sampleStride
                        }
                        y += sampleStride
                    }
                }
                guard samples.count > maxSamples else { return samples }
                let pickStride = max(1, Int(ceil(Double(samples.count) / Double(maxSamples))))
                return stride(from: 0, to: samples.count, by: pickStride).prefix(maxSamples).map { samples[$0] }
            }

            func proxyMaskGapBetweenBubbleIDs(_ lhs: Int, _ rhs: Int, bboxGap: Double, threshold: Double) -> Double {
                if bboxGap > max(32.0, threshold * 3.0) {
                    return bboxGap
                }
                let lhsSamples = proxyBoundarySamples(for: lhs)
                let rhsSamples = proxyBoundarySamples(for: rhs)
                guard !lhsSamples.isEmpty, !rhsSamples.isEmpty else { return .infinity }
                var bestSquared = Double.infinity
                let earlyExitSquared = max(1.0, min(2.0, max(1.0, threshold * 0.25)))
                for a in lhsSamples {
                    for b in rhsSamples {
                        let dx = Double(a.0 - b.0)
                        let dy = Double(a.1 - b.1)
                        let squared = dx * dx + dy * dy
                        if squared < bestSquared {
                            bestSquared = squared
                        }
                        if bestSquared <= earlyExitSquared {
                            return sqrt(bestSquared)
                        }
                    }
                }
                return sqrt(bestSquared)
            }

            func seamGeometry(for seedBlocks: [MangaOverlayProbeBlock], parentRect: CGRect?) -> (String, [Double]?, [Double]?, [Int], [Int], Double) {
                guard seedBlocks.count > 1 else {
                    let rect = parentRect ?? seedBlocks.first.map { Self.rect(from: $0.bbox) } ?? .zero
                    let line = rect.isNull ? nil : [Double(rect.midX), Double(rect.minY), Double(rect.midX), Double(rect.maxY)]
                    return ("unknown", line, rect.isNull ? nil : Self.bboxArray(from: rect), seedBlocks.map(\.index), [], 0)
                }
                let sortedX = seedBlocks.sorted { center(Self.rect(from: $0.bbox)).x < center(Self.rect(from: $1.bbox)).x }
                let sortedY = seedBlocks.sorted { center(Self.rect(from: $0.bbox)).y < center(Self.rect(from: $1.bbox)).y }
                func largestGap(_ sorted: [MangaOverlayProbeBlock], axis: String) -> (Int, Double, CGFloat) {
                    var bestIndex = 1
                    var bestGap = -Double.infinity
                    var bestValue = CGFloat.zero
                    for index in 1..<sorted.count {
                        let lhs = Self.rect(from: sorted[index - 1].bbox)
                        let rhs = Self.rect(from: sorted[index].bbox)
                        let gap: Double
                        let value: CGFloat
                        if axis == "x" {
                            gap = Double(rhs.minX - lhs.maxX)
                            value = (lhs.maxX + rhs.minX) / 2
                        } else {
                            gap = Double(rhs.minY - lhs.maxY)
                            value = (lhs.maxY + rhs.minY) / 2
                        }
                        if gap > bestGap {
                            bestGap = gap
                            bestIndex = index
                            bestValue = value
                        }
                    }
                    return (bestIndex, max(0, bestGap), bestValue)
                }
                let xGap = largestGap(sortedX, axis: "x")
                let yGap = largestGap(sortedY, axis: "y")
                let rect = parentRect ?? seedBlocks.map { Self.rect(from: $0.bbox) }.reduce(CGRect.null) { $0.union($1) }
                if xGap.1 >= yGap.1 {
                    let left = sortedX.prefix(xGap.0).map(\.index)
                    let right = sortedX.suffix(sortedX.count - xGap.0).map(\.index)
                    let corridor = CGRect(x: xGap.2 - 2, y: rect.minY, width: 4, height: rect.height)
                    return ("vertical", [Double(xGap.2), Double(rect.minY), Double(xGap.2), Double(rect.maxY)], Self.bboxArray(from: corridor), Array(left), Array(right), xGap.1)
                } else {
                    let top = sortedY.prefix(yGap.0).map(\.index)
                    let bottom = sortedY.suffix(sortedY.count - yGap.0).map(\.index)
                    let corridor = CGRect(x: rect.minX, y: yGap.2 - 2, width: rect.width, height: 4)
                    return ("horizontal", [Double(rect.minX), Double(yGap.2), Double(rect.maxX), Double(yGap.2)], Self.bboxArray(from: corridor), Array(top), Array(bottom), yGap.1)
                }
            }

            let sortedBubbles = bubbleGeometry.bubbles.sorted { $0.id < $1.id }
            var pairLedgers: [MangaKoharuBubbleAdjacencyPairLedger] = []
            for lhsIndex in sortedBubbles.indices {
                for rhsIndex in sortedBubbles.indices where rhsIndex > lhsIndex {
                    let lhs = sortedBubbles[lhsIndex]
                    let rhs = sortedBubbles[rhsIndex]
                    let lhsRect = Self.rect(from: lhs.bbox)
                    let rhsRect = Self.rect(from: rhs.bbox)
                    let gap = rectGap(lhsRect, rhsRect)
                    let threshold = max(8.0, Double(min(min(lhsRect.width, lhsRect.height), min(rhsRect.width, rhsRect.height))) * 0.04)
                    let overlap = rectOverlapArea(lhsRect, rhsRect)
                    let expanded = lhsRect.insetBy(dx: CGFloat(-threshold), dy: CGFloat(-threshold)).intersects(rhsRect)
                    let pairSplitCandidates = (splitCandidatesByParent[lhs.id] ?? []) + (splitCandidatesByParent[rhs.id] ?? [])
                    let sharedSplitIDs = uniqueSorted(pairSplitCandidates.map(\.id))
                    let sharedSiblingIDs = uniqueSortedStrings((siblingGroupIDsByBubble[lhs.id] ?? []) + (siblingGroupIDsByBubble[rhs.id] ?? []))
                    let lhsBlocks = Set(blocksByBubble[lhs.id]?.map(\.index) ?? [])
                    let rhsBlocks = Set(blocksByBubble[rhs.id]?.map(\.index) ?? [])
                    let conflictShared = assignmentConflictBlocks.filter { lhsBlocks.contains($0) || rhsBlocks.contains($0) }
                    let relatedByStructure = !sharedSplitIDs.isEmpty || !sharedSiblingIDs.isEmpty || !conflictShared.isEmpty
                    guard overlap > 0 || expanded || gap <= threshold || relatedByStructure else { continue }
                    let maskGap = proxyMaskGapBetweenBubbleIDs(lhs.id, rhs.id, bboxGap: gap, threshold: threshold)
                    let proxyTouching = maskGap.isFinite && maskGap <= max(2.0, threshold * 0.5)
                    let relatedBlocks = uniqueSorted(Array(lhsBlocks.union(rhsBlocks)).filter { assignmentConflictBlocks.contains($0) || renderLockedBlocks.contains($0) || !(splitCandidatesByBlock[$0] ?? []).isEmpty })
                    let distanceConflict = relatedBlocks.contains { distanceFieldByBlock[$0]?.safeRectComparisonVerdict != "distanceRectMatchesCurrentLayout" && distanceFieldByBlock[$0] != nil }
                    let renderInvolved = relatedBlocks.contains { renderLockedBlocks.contains($0) }
                    let verdict: String
                    if overlap > 0 {
                        verdict = "overlappingProxyBBoxes"
                    } else if proxyTouching {
                        verdict = "touchingProxyMasks"
                    } else if !sharedSplitIDs.isEmpty {
                        verdict = "sameParentSplitCandidate"
                    } else if !sharedSiblingIDs.isEmpty {
                        verdict = "siblingLayoutOnly"
                    } else if distanceConflict || !conflictShared.isEmpty {
                        verdict = "needsRealBubbleMask"
                    } else {
                        verdict = "adjacentButSeparated"
                    }
                    let action: String
                    if verdict == "needsRealBubbleMask" || verdict == "touchingProxyMasks" || verdict == "overlappingProxyBBoxes" {
                        action = "collectRealBubbleMaskArtifact"
                    } else if verdict == "sameParentSplitCandidate" {
                        action = "reviewSeamCandidateReportOnly"
                    } else {
                        action = "keepAdjacencyLedgerReportOnly"
                    }
                    let pairID = "P-\(lhs.id)-\(rhs.id)"
                    pairLedgers.append(MangaKoharuBubbleAdjacencyPairLedger(
                        pairID: pairID,
                        bubbleAID: lhs.id,
                        bubbleBID: rhs.id,
                        bubbleABBox: lhs.bbox,
                        bubbleBBBox: rhs.bbox,
                        bboxOverlapArea: overlap,
                        bboxGapPx: gap,
                        expandedBBoxIntersects: expanded,
                        proxyMaskTouching: proxyTouching,
                        proxyMaskMinimumGapPx: maskGap.isFinite ? maskGap : gap,
                        maskGapAlgorithm: "roundedRectProxyMaskSampled",
                        sharedBlockIndexes: relatedBlocks,
                        sameBubbleSiblingGroupIDs: sharedSiblingIDs,
                        splitCandidateIDs: sharedSplitIDs,
                        distanceFieldSafeRectConflict: distanceConflict,
                        renderLockInvolved: renderInvolved,
                        pairVerdict: verdict,
                        nextAction: action,
                        decisionSignals: [
                            signal("bboxGapPx", formatted(gap), source: "bubbleGeometry"),
                            signal("bboxOverlapArea", formatted(overlap), source: "bubbleGeometry"),
                            signal("proxyMaskMinimumGapPx", formatted(maskGap.isFinite ? maskGap : nil), source: "koharuBubbleAdjacencySeamReport")
                        ],
                        evaluationSignals: [
                            signal("relatedDialogueBlocks", String(blocks.filter { relatedBlocks.contains($0.index) && $0.bestGroundTruthType == "dialogue" }.count), source: "blocks.bestGroundTruthType", decision: false, evaluation: true)
                        ],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    ))
                }
            }

            var seamCandidates: [MangaKoharuBubbleSeamCandidateLedger] = []
            for candidate in splitCandidates.sorted(by: { $0.id < $1.id }) {
                let seedBlocks = candidate.seedBlockIndexes.compactMap { blockIndex in blocks.first { $0.index == blockIndex } }
                let parentRect = bubbleGeometry.bubbles.first { $0.id == candidate.parentBubbleID }.map { Self.rect(from: $0.bbox) }
                let geometry = seamGeometry(for: seedBlocks, parentRect: parentRect)
                let blockIndexes = uniqueSorted(candidate.seedBlockIndexes)
                let ocrDamage = blockIndexes.filter { blockIndex in
                    let block = blocks.first { $0.index == blockIndex }
                    return block?.failureCategory == "ocrInputSuspect" || (block?.ocrGroundTruthSimilarity ?? 1) < 0.65
                }
                let safeRisk = blockIndexes.filter { distanceFieldByBlock[$0]?.safeRectComparisonVerdict != "distanceRectMatchesCurrentLayout" && distanceFieldByBlock[$0] != nil }
                let renderRisk = blockIndexes.filter { renderLockedBlocks.contains($0) }
                let conflict = blockIndexes.filter { assignmentConflictBlocks.contains($0) }
                let score = min(1.0, (geometry.5 / max(1.0, Double(max(parentRect?.width ?? 0, parentRect?.height ?? 0)))) + (conflict.isEmpty ? 0 : 0.25) + (safeRisk.isEmpty ? 0 : 0.15))
                let verdict: String
                if !renderRisk.isEmpty {
                    verdict = "renderLockedNoSplit"
                } else if !conflict.isEmpty {
                    verdict = "assignmentConflictNeedsReview"
                } else if !safeRisk.isEmpty {
                    verdict = "splitCandidateNeedsRealBubbleMask"
                } else {
                    verdict = "reportOnlySeamCandidate"
                }
                let action = verdict == "reportOnlySeamCandidate" ? "keepSeamCandidateReportOnly" : (verdict == "renderLockedNoSplit" ? "inspectRenderLockGateLedger" : "collectRealBubbleMaskArtifact")
                seamCandidates.append(MangaKoharuBubbleSeamCandidateLedger(
                    seamCandidateID: "SC-split-\(candidate.id)",
                    source: "bubbleSplitCandidateReport",
                    parentBubbleID: candidate.parentBubbleID,
                    relatedBubbleIDs: [candidate.parentBubbleID],
                    blockIndexes: blockIndexes,
                    splitCandidateIDs: [candidate.id],
                    siblingGroupID: nil,
                    seamOrientation: geometry.0,
                    seamLine: geometry.1,
                    seamCorridorRect: geometry.2,
                    leftOrTopBlockIndexes: geometry.3,
                    rightOrBottomBlockIndexes: geometry.4,
                    protectedBlockIndexes: blockIndexes,
                    wouldIsolateBlocks: uniqueSorted(geometry.3 + geometry.4),
                    ocrDamageBlocks: ocrDamage,
                    assignmentConflictBlocks: conflict,
                    safeAreaRiskBlocks: safeRisk,
                    renderLockedBlocks: renderRisk,
                    seamScore: score,
                    seamCandidateVerdict: verdict,
                    promotionBlockedReasons: ["reportOnly", "proxyNotRealBubbleMask"] + (renderRisk.isEmpty ? [] : ["renderLockInvolved"]),
                    nextAction: action,
                    decisionSignals: [
                        signal("sourceCandidateID", String(candidate.id), source: "bubbleSplitCandidateReport"),
                        signal("seamGapPx", formatted(geometry.5), source: "blocks.bbox"),
                        signal("assignmentConflictBlocks", joined(conflict), source: "bubbleMaskReport")
                    ],
                    evaluationSignals: [
                        signal("ocrDamageBlocks", joined(ocrDamage), source: "blocks.ocrGroundTruthSimilarity", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                ))
            }
            for group in siblingGroups {
                let parentRect = bubbleGeometry.bubbles.first { $0.id == group.bubbleID }.map { Self.rect(from: $0.bbox) }
                let geometry = seamGeometry(for: group.blocks, parentRect: parentRect)
                let blockIndexes = group.blocks.map(\.index)
                let splitIDs = uniqueSorted(blockIndexes.flatMap { (splitCandidatesByBlock[$0] ?? []).map { $0.candidate.id } })
                let safeRisk = blockIndexes.filter { distanceFieldByBlock[$0]?.safeRectComparisonVerdict == "distanceRectWouldRiskSprite" }
                let verdict = splitIDs.isEmpty && safeRisk.isEmpty ? "siblingLayoutNoSplit" : "distanceFieldTooSmallForSplit"
                let action = verdict == "siblingLayoutNoSplit" ? "keepSiblingLayoutReportOnly" : "reviewSeamCandidateReportOnly"
                seamCandidates.append(MangaKoharuBubbleSeamCandidateLedger(
                    seamCandidateID: "SC-sibling-\(group.bubbleID)",
                    source: "sameBubbleSiblingGroup",
                    parentBubbleID: group.bubbleID,
                    relatedBubbleIDs: [group.bubbleID],
                    blockIndexes: blockIndexes,
                    splitCandidateIDs: splitIDs,
                    siblingGroupID: group.groupID,
                    seamOrientation: geometry.0,
                    seamLine: geometry.1,
                    seamCorridorRect: geometry.2,
                    leftOrTopBlockIndexes: geometry.3,
                    rightOrBottomBlockIndexes: geometry.4,
                    protectedBlockIndexes: blockIndexes,
                    wouldIsolateBlocks: [],
                    ocrDamageBlocks: blockIndexes.filter { blockIndex in
                        blocks.first { $0.index == blockIndex }?.failureCategory == "ocrInputSuspect"
                    },
                    assignmentConflictBlocks: blockIndexes.filter { assignmentConflictBlocks.contains($0) },
                    safeAreaRiskBlocks: safeRisk,
                    renderLockedBlocks: blockIndexes.filter { renderLockedBlocks.contains($0) },
                    seamScore: min(1.0, geometry.5 / max(1.0, Double(max(parentRect?.width ?? 0, parentRect?.height ?? 0)))),
                    seamCandidateVerdict: verdict,
                    promotionBlockedReasons: ["siblingLayoutReportOnly", "wouldChangeMainFlow=false"],
                    nextAction: action,
                    decisionSignals: [
                        signal("siblingGroupID", group.groupID, source: "koharuBubbleAdjacencySeamReport"),
                        signal("seamGapPx", formatted(geometry.5), source: "blocks.bbox")
                    ],
                    evaluationSignals: [
                        signal("groundTruthTypes", uniqueSortedStrings(group.blocks.compactMap(\.bestGroundTruthType)).joined(separator: ","), source: "blocks.bestGroundTruthType", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                ))
            }

            let pairIDsByBlock = Dictionary(grouping: pairLedgers.flatMap { pair in
                pair.sharedBlockIndexes.map { (blockIndex: $0, pairID: pair.pairID) }
            }) { $0.blockIndex }.mapValues { uniqueSortedStrings($0.map(\.pairID)) }
            let seamIDsByBlock = Dictionary(grouping: seamCandidates.flatMap { seam in
                seam.blockIndexes.map { (blockIndex: $0, seamID: seam.seamCandidateID) }
            }) { $0.blockIndex }.mapValues { uniqueSortedStrings($0.map(\.seamID)) }

            let blockLedgers: [MangaKoharuBubbleSeamBlockLedger] = blocks.map { block in
                let splitIDs = uniqueSorted((splitCandidatesByBlock[block.index] ?? []).map { $0.candidate.id })
                let siblings = siblingBlocksByBlock[block.index] ?? []
                let conflict = assignmentConflictBlocks.contains(block.index)
                let renderVerdict = renderLockedBlocks.contains(block.index) ? "renderLocked" : "renderStableOrNotInvolved"
                let ocrRisk: String
                if block.failureCategory == "ocrInputSuspect" || (block.ocrGroundTruthSimilarity ?? 1) < 0.65 {
                    ocrRisk = "ocrDamageRisk"
                } else if block.groundTruthMatch == "unmatched" {
                    ocrRisk = "unmatchedEvaluationOnly"
                } else {
                    ocrRisk = "noOcrDamageSignal"
                }
                let seamRisk: String
                if conflict {
                    seamRisk = "assignmentConflict"
                } else if !splitIDs.isEmpty {
                    seamRisk = "splitCandidate"
                } else if !siblings.isEmpty {
                    seamRisk = "sameBubbleSibling"
                } else if !(pairIDsByBlock[block.index] ?? []).isEmpty {
                    seamRisk = "adjacentBubbleContext"
                } else {
                    seamRisk = "noSeamRisk"
                }
                let verdict: String
                if renderVerdict == "renderLocked" {
                    verdict = "renderLockedNoSeamAction"
                } else if conflict {
                    verdict = "assignmentConflictReportOnly"
                } else if !splitIDs.isEmpty {
                    verdict = "splitCandidateReportOnly"
                } else if !siblings.isEmpty {
                    verdict = "sameBubbleSiblingLayoutOnly"
                } else if seamRisk == "adjacentBubbleContext" {
                    verdict = "needsRealBubbleMask"
                } else {
                    verdict = "noSeamRisk"
                }
                let action: String
                if verdict == "needsRealBubbleMask" || verdict == "assignmentConflictReportOnly" {
                    action = "collectRealBubbleMaskArtifact"
                } else if verdict == "renderLockedNoSeamAction" {
                    action = "inspectRenderLockGateLedger"
                } else if verdict == "splitCandidateReportOnly" {
                    action = "reviewSeamCandidateReportOnly"
                } else {
                    action = "keepBubbleAdjacencySeamReportOnly"
                }
                return MangaKoharuBubbleSeamBlockLedger(
                    blockIndex: block.index,
                    bubbleID: block.bubbleID,
                    bbox: block.bbox,
                    blockPassed: block.blockPassed,
                    failureCategory: block.failureCategory,
                    groundTruthMatch: block.groundTruthMatch,
                    bestGroundTruthType: block.bestGroundTruthType,
                    ocrSimilarityForEvaluation: block.ocrGroundTruthSimilarity,
                    currentSafeLayoutRect: block.safeLayoutRect,
                    bubbleIndexShadowBubbleID: bubbleIndexByBlock[block.index]?.shadowBubbleID,
                    distanceFieldSafeRect: distanceFieldByBlock[block.index]?.distanceFieldSafeRect,
                    relatedPairIDs: pairIDsByBlock[block.index] ?? [],
                    relatedSeamCandidateIDs: seamIDsByBlock[block.index] ?? [],
                    splitCandidateIDs: splitIDs,
                    sameBubbleSiblingBlockIndexes: siblings,
                    assignmentConflict: conflict,
                    ocrDamageRisk: ocrRisk,
                    renderLockVerdict: renderVerdict,
                    blockSeamRisk: seamRisk,
                    blockSeamVerdict: verdict,
                    primaryBottleneck: bubbleIndexByBlock[block.index]?.primaryBottleneck ?? block.failureCategory,
                    nextAction: action,
                    decisionSignals: [
                        signal("blockSeamRisk", seamRisk, source: "koharuBubbleAdjacencySeamReport"),
                        signal("assignmentConflict", String(conflict), source: "bubbleMaskReport"),
                        signal("splitCandidateIDs", joined(splitIDs), source: "bubbleSplitCandidateReport")
                    ],
                    evaluationSignals: [
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks.groundTruthMatch", decision: false, evaluation: true),
                        signal("ocrSimilarityForEvaluation", formatted(block.ocrGroundTruthSimilarity), source: "blocks.ocrGroundTruthSimilarity", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }.sorted { $0.blockIndex < $1.blockIndex }

            let seamRiskBlocks = uniqueSorted(blockLedgers.filter { $0.blockSeamRisk != "noSeamRisk" }.map(\.blockIndex))
            let splitReviewBlocks = uniqueSorted(blockLedgers.filter { !$0.splitCandidateIDs.isEmpty }.map(\.blockIndex))
            let sameBubbleSiblingBlocks = uniqueSorted(blockLedgers.filter { !$0.sameBubbleSiblingBlockIndexes.isEmpty }.map(\.blockIndex))
            let needsRealBubbleMaskBlocks = uniqueSorted(blockLedgers.filter { $0.nextAction == "collectRealBubbleMaskArtifact" }.map(\.blockIndex))
            let manualReviewBlocks = uniqueSorted(blockLedgers.filter { $0.blockSeamVerdict == "manualReviewOnly" || $0.nextAction == "manualReviewOnly" }.map(\.blockIndex))

            func gate(
                _ id: String,
                _ name: String,
                _ scope: String,
                _ status: String,
                _ threshold: String,
                _ affected: [Int],
                _ failure: String,
                _ action: String,
                _ signals: [MangaKoharuBubbleAdjacencySeamSignal]
            ) -> MangaKoharuBubbleAdjacencySeamGate {
                MangaKoharuBubbleAdjacencySeamGate(
                    gateID: id,
                    gateName: name,
                    scope: scope,
                    status: status,
                    threshold: threshold,
                    affectedBlocks: uniqueSorted(affected),
                    decisionSignals: signals,
                    failureMeans: failure,
                    recommendedAction: action,
                    groundTruthUsedForDecision: false
                )
            }

            let gateLedger = [
                gate("G-bubble-adjacency-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "adjacency seam report mutates OCR, translation, layout, renderer, blockPassed, or candidate selection", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-bubble-adjacency-no-ground-truth-decision", "No ground truth decision", "report", "passed", "groundTruthUsedForDecision=false", allBlocks, "ground truth influences adjacency, seam, assignment, split, gate, or nextAction", "moveGroundTruthToEvaluationSignalsOnly", [signal("groundTruthUsedForDecision", "false", source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-bubble-adjacency-proxy-boundary", "Proxy boundary", "BubbleMask", "passed", "proxyNotRealBubbleMask=true and usesRoundedRectProxyMask=true", allBlocks, "rounded-rect proxy is promoted as real Koharu BubbleMask instance ID", "collectRealBubbleMaskArtifact", [signal("proxyNotRealBubbleMask", "true", source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-bubble-adjacency-pair-ledger", "Pair ledger count", "BubbleMask", pairLedgers.isEmpty ? "warning" : "passed", "pairLedgerCount>=1 for current manga page", allBlocks, "adjacent or conflicting bubbles are hidden", "restoreBubblePairLedger", [signal("pairLedgerCount", String(pairLedgers.count), source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-bubble-adjacency-seam-candidates", "Seam candidates", "BubbleMask", seamCandidates.count >= (bubbleSplitCandidateReport?.candidateCount ?? 0) ? "passed" : "warning", "seamCandidateCount>=bubbleSplitCandidateReport.candidateCount", splitReviewBlocks, "split candidates lack seam ledger rows", "restoreSeamCandidateLedger", [signal("seamCandidateCount", String(seamCandidates.count), source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-bubble-adjacency-block-ledger", "Block ledger count", "blocks", blockLedgers.count == blocks.count ? "passed" : "warning", "blockLedgerCount==totalBlocksDetected", allBlocks, "some final blocks lack seam ledger rows", "restoreBlockSeamLedger", [signal("blockLedgerCount", String(blockLedgers.count), source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-bubble-adjacency-assignment-conflicts", "Assignment conflicts surfaced", "BubbleIndex", assignmentConflictBlocks.isEmpty ? "passed" : "warning", "assignment conflicts explicitly listed", assignmentConflictBlocks, "assignment conflict blocks are silently hidden or corrected", "reviewRealBubbleMaskNeed", [signal("assignmentConflictBlocks", joined(assignmentConflictBlocks), source: "bubbleMaskReport,koharuBubbleIndexShadowLedgerReport")]),
                gate("G-bubble-adjacency-sibling-layout", "Sibling layout audited", "BubbleIndex", siblingGroups.isEmpty || !sameBubbleSiblingBlocks.isEmpty ? "passed" : "warning", "same-bubble sibling groups produce seam ledger rows", sameBubbleSiblingBlocks, "sibling layout is mistaken for applied split", "keepSiblingLayoutReportOnly", [signal("siblingGroupCount", String(siblingGroups.count), source: "blocks.bubbleID")]),
                gate("G-bubble-adjacency-render-lock-respected", "Render lock respected", "FinalRender", koharuRenderRegressionLockReport == nil ? "warning" : "passed", "render lock remains evidence only", renderLockedBlocks, "seam report changes overlay or safeLayoutRect despite render lock", "inspectRenderLockGateLedger", [signal("renderLockedBlocks", joined(renderLockedBlocks), source: "koharuRenderRegressionLockReport,blocks.renderDiagnostics")]),
                gate("G-bubble-adjacency-distance-field-linked", "DistanceField linked", "BubbleIndex", koharuDistanceFieldSafeAreaReport == nil ? "warning" : "passed", "v1.36 DistanceField report is available as seam evidence", allBlocks, "seam report cannot explain safe-area conflict evidence", "restoreKoharuDistanceFieldSafeAreaReport", [signal("distanceFieldReportAvailable", String(koharuDistanceFieldSafeAreaReport != nil), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-bubble-adjacency-ci-fast-ready", "CI fast ready", "ci-fast", "passed", "uses existing reports only", allBlocks, "seam report adds OCR/LLM/full-only dependency", "keepCIFastReportOnly", [signal("inputReports", "bubbleGeometry,bubbleMaskReport,bubbleSplitCandidateReport,koharuBubbleIndexShadowLedgerReport,koharuDistanceFieldSafeAreaReport,koharuRenderRegressionLockReport", source: "koharuBubbleAdjacencySeamReport")])
            ]

            let adjacencyVerdict: String
            if bubbleMaskReport == nil {
                adjacencyVerdict = "blockedByMissingBubbleMaskProxy"
            } else if !needsRealBubbleMaskBlocks.isEmpty {
                adjacencyVerdict = "needsRealBubbleMaskArtifact"
            } else if !manualReviewBlocks.isEmpty {
                adjacencyVerdict = "manualReviewOnly"
            } else if seamCandidates.isEmpty {
                adjacencyVerdict = "adjacencySeamLedgerReady"
            } else {
                adjacencyVerdict = "reportOnlySeamCandidatesReady"
            }

            return MangaKoharuBubbleAdjacencySeamReport(
                enabled: true,
                source: "AITRANSProbe",
                referencePipeline: "Koharu",
                referenceConcept: "BubbleMask.InstanceAdjacency.SeamPartition",
                evaluatedBlockCount: blocks.count,
                evaluatedBubbleCount: bubbleMaskReport?.instanceCount ?? bubbleGeometry.bubbles.count,
                pairLedgerCount: pairLedgers.count,
                seamCandidateCount: seamCandidates.count,
                blockLedgerCount: blockLedgers.count,
                gateCount: gateLedger.count,
                groundTruthUsedForDecision: false,
                groundTruthUsedForEvaluationOnly: true,
                wouldChangeMainFlow: false,
                diagnosticOnly: true,
                proxyNotRealBubbleMask: true,
                usesRoundedRectProxyMask: true,
                externalArtifactsRequiredForThisReport: false,
                adjacencyVerdict: adjacencyVerdict,
                pairVerdictBreakdown: countBy(pairLedgers.map(\.pairVerdict)),
                seamCandidateVerdictBreakdown: countBy(seamCandidates.map(\.seamCandidateVerdict)),
                blockSeamRiskBreakdown: countBy(blockLedgers.map(\.blockSeamRisk)),
                assignmentRiskBreakdown: countBy(blockLedgers.map { $0.assignmentConflict ? "assignmentConflict" : "assignmentStableOrUnrelated" }),
                nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                adjacentBubblePairs: pairLedgers.map(\.pairID).sorted(),
                seamCandidateIDs: seamCandidates.map(\.seamCandidateID).sorted(),
                seamRiskBlocks: seamRiskBlocks,
                assignmentConflictBlocks: assignmentConflictBlocks,
                splitReviewBlocks: splitReviewBlocks,
                sameBubbleSiblingBlocks: sameBubbleSiblingBlocks,
                needsRealBubbleMaskBlocks: needsRealBubbleMaskBlocks,
                manualReviewBlocks: manualReviewBlocks,
                pairLedgers: pairLedgers.sorted { $0.pairID < $1.pairID },
                seamCandidateLedgers: seamCandidates.sorted { $0.seamCandidateID < $1.seamCandidateID },
                blockLedgers: blockLedgers,
                gateLedger: gateLedger,
                notes: [
                    "koharuBubbleAdjacencySeamReport is a report-only Koharu BubbleMask instance adjacency and seam shadow ledger.",
                    "It uses AITRANS rounded-rect BubbleMask proxy, BubbleIndex, DistanceField, split candidate, sibling, OCR damage, and render lock evidence; it does not use real Koharu BubbleMask artifacts.",
                    "Ground truth appears only in evaluationSignals; adjacency, seam, split, assignment, gate, and nextAction decisions use ground-truth-free geometry/render signals.",
                    "The report does not add OCR or LLM calls and does not change OCR, translation input, safeLayoutRect, DistanceField safe rect, glyphMaskFillRects, background fill, overlay rendering, blockPassed, failureCategory, active artifacts, currentBlockSource, or PNG output behavior."
                ]
            )
        }
    }

    func makeKoharuRenderSpriteFitPlannerReport(
        blocks: [MangaOverlayProbeBlock],
        koharuBubbleIndexShadowLedgerReport: MangaKoharuBubbleIndexShadowLedgerReport?,
        koharuDistanceFieldSafeAreaReport: MangaKoharuDistanceFieldSafeAreaReport?,
        koharuBubbleAdjacencySeamReport: MangaKoharuBubbleAdjacencySeamReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?
    ) async -> MangaKoharuRenderSpriteFitPlannerReport {
        await Task.detached(priority: .userInitiated) {
            func uniqueSorted(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }
            func uniqueSortedStrings(_ values: [String]) -> [String] { Array(Set(values)).sorted() }
            func countBy(_ values: [String]) -> [String: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
            func joined(_ values: [Int]) -> String { uniqueSorted(values).map(String.init).joined(separator: ",") }
            func area(_ rect: CGRect?) -> Double {
                guard let rect, !rect.isNull, rect.width > 0, rect.height > 0 else { return 0 }
                return Double(rect.width * rect.height)
            }
            func areaDelta(candidate: [Double]?, current: [Double]?) -> Double? {
                let currentArea = area(current.map(Self.rect(from:)))
                guard currentArea > 0 else { return nil }
                return (area(candidate.map(Self.rect(from:))) - currentArea) / currentArea
            }
            func containment(_ inner: [Double]?, in outer: [Double]?) -> Bool? {
                guard let inner, let outer else { return nil }
                return Self.rectContainmentRatio(inner: Self.rect(from: inner), outer: Self.rect(from: outer)) >= 0.995
            }
            func overlapRatio(_ lhs: [Double]?, _ rhs: [Double]?) -> Double {
                guard let lhs, let rhs else { return 0 }
                let lhsRect = Self.rect(from: lhs)
                let rhsRect = Self.rect(from: rhs)
                let base = max(min(area(lhsRect), area(rhsRect)), 1)
                return area(lhsRect.intersection(rhsRect)) / base
            }
            func maxOverlap(_ rects: [[Double]]) -> Double {
                guard rects.count > 1 else { return 0 }
                var result = 0.0
                for lhs in 0..<rects.count {
                    for rhs in (lhs + 1)..<rects.count {
                        result = max(result, overlapRatio(rects[lhs], rects[rhs]))
                    }
                }
                return result
            }
            func signal(
                _ name: String,
                _ value: String,
                source: String,
                decision: Bool = true,
                evaluation: Bool = false
            ) -> MangaKoharuRenderSpriteFitSignal {
                MangaKoharuRenderSpriteFitSignal(
                    name: name,
                    value: value,
                    sourceReport: source,
                    groundTruthFreeDecisionSignal: decision,
                    groundTruthUsedForEvaluationOnly: evaluation
                )
            }
            func formatted(_ value: Double?) -> String {
                value?.formatted(.number.precision(.fractionLength(4))) ?? "nil"
            }
            func cjkCount(_ text: String) -> Int {
                text.unicodeScalars.filter { scalar in
                    (0x4E00...0x9FFF).contains(Int(scalar.value))
                    || (0x3400...0x4DBF).contains(Int(scalar.value))
                    || (0x3040...0x30FF).contains(Int(scalar.value))
                }.count
            }
            func latinCount(_ text: String) -> Int {
                text.unicodeScalars.filter { scalar in
                    (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
                }.count
            }
            func renderText(for block: MangaOverlayProbeBlock, lock: MangaKoharuRenderBlockLock?) -> (source: String, text: String) {
                if block.blockPassed, !block.translationCandidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ("translationCandidate", block.translationCandidate)
                }
                if let fallback = lock?.fallbackTextForRender, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ("failureFallback", fallback)
                }
                if !block.finalTextUsedForTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ("failureFallback", "翻译失败\n\(block.finalTextUsedForTranslation)")
                }
                return ("emptyCandidateFallback", "翻译失败")
            }
            func estimateTextBudget(text: String, fontSize: Double?, rect: [Double]?) -> (lineCount: Int, charsPerLine: Int, verdict: String) {
                guard let rect else {
                    return (max(1, text.count), 1, "renderDiagnosticsMissing")
                }
                let width = max(1, Self.rect(from: rect).width)
                let height = max(1, Self.rect(from: rect).height)
                let font = max(8, fontSize ?? min(18, Double(height) * 0.35))
                let charsPerLine = max(1, Int((Double(width) / (font * 0.62)).rounded(.down)))
                let lineCount = max(1, Int(ceil(Double(max(text.count, 1)) / Double(charsPerLine))))
                let maxLines = max(1, Int((Double(height) / (font * 1.18)).rounded(.down)))
                let verdict: String
                if lineCount > maxLines + 1 {
                    verdict = "fontBudgetOverflowRisk"
                } else if lineCount >= maxLines {
                    verdict = "fontBudgetTight"
                } else {
                    verdict = "fontBudgetComfortable"
                }
                return (lineCount, charsPerLine, verdict)
            }

            let allBlocks = blocks.map(\.index)
            let bubbleIndexByBlock = Dictionary(uniqueKeysWithValues: (koharuBubbleIndexShadowLedgerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) })
            let distanceFieldByBlock = Dictionary(uniqueKeysWithValues: (koharuDistanceFieldSafeAreaReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) })
            let seamByBlock = Dictionary(uniqueKeysWithValues: (koharuBubbleAdjacencySeamReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) })
            let renderByBlock = Dictionary(uniqueKeysWithValues: (koharuRenderRegressionLockReport?.blockLocks ?? []).map { ($0.blockIndex, $0) })
            let blocksByBubble = Dictionary(grouping: blocks.compactMap { block -> (Int, MangaOverlayProbeBlock)? in
                guard let bubbleID = block.bubbleID else { return nil }
                return (bubbleID, block)
            }) { $0.0 }.mapValues { $0.map(\.1).sorted { $0.index < $1.index } }
            let siblingIndexesByBlock = Dictionary(uniqueKeysWithValues: blocks.map { block in
                let siblings = block.bubbleID.flatMap { blocksByBubble[$0] }?.map(\.index).filter { $0 != block.index } ?? []
                return (block.index, siblings)
            })

            let blockLedgers: [MangaKoharuRenderSpriteFitBlockLedger] = blocks.map { block in
                let renderLock = renderByBlock[block.index]
                let textInfo = renderText(for: block, lock: renderLock)
                let currentRect = block.safeLayoutRect ?? renderLock?.safeLayoutRect
                let bubbleIndexRect = bubbleIndexByBlock[block.index]?.shadowSafeLayoutRect
                let distanceRect = distanceFieldByBlock[block.index]?.distanceFieldSafeRect
                let spriteBounds = renderLock?.renderNonTransparentBounds ?? block.renderNonTransparentBounds
                let selectedSource: String
                let selectedRect: [Double]?
                if containment(spriteBounds, in: currentRect) == true {
                    selectedSource = "currentSafeLayoutRect"
                    selectedRect = currentRect
                } else if containment(spriteBounds, in: distanceRect) == true {
                    selectedSource = "distanceFieldSafeRect"
                    selectedRect = distanceRect
                } else if bubbleIndexRect != nil {
                    selectedSource = "bubbleIndexShadowSafeRect"
                    selectedRect = bubbleIndexRect
                } else {
                    selectedSource = "currentSafeLayoutRect"
                    selectedRect = currentRect
                }
                let budget = estimateTextBudget(text: textInfo.text, fontSize: block.renderFontSize ?? renderLock?.renderFontSize, rect: selectedRect)
                let spriteCurrent = containment(spriteBounds, in: currentRect)
                let spriteDistance = containment(spriteBounds, in: distanceRect)
                let siblings = siblingIndexesByBlock[block.index] ?? []
                let siblingOverlap = siblings.contains { siblingIndex in
                    guard let sibling = blocks.first(where: { $0.index == siblingIndex }) else { return false }
                    return overlapRatio(currentRect, sibling.safeLayoutRect) >= 0.08
                }
                let relatedSeams = seamByBlock[block.index]?.relatedSeamCandidateIDs ?? []
                let renderVerdict = renderLock?.renderStatus ?? (block.renderCollisionChecked ? "renderDiagnosticsAvailable" : "renderDiagnosticsMissing")
                let failureRequired = renderLock?.failureOverlayRequired ?? !block.blockPassed
                let failureFit: String
                if !failureRequired {
                    failureFit = "notRequired"
                } else if budget.verdict == "fontBudgetOverflowRisk" {
                    failureFit = "failureFallbackLongTextRisk"
                } else if spriteCurrent == false {
                    failureFit = "failureFallbackSpriteContainmentRisk"
                } else {
                    failureFit = "failureFallbackAccounted"
                }
                let fitVerdict: String
                if block.safeLayoutRect == nil || spriteBounds == nil {
                    fitVerdict = "renderDiagnosticsMissing"
                } else if !relatedSeams.isEmpty && (seamByBlock[block.index]?.blockSeamVerdict == "needsRealBubbleMask") {
                    fitVerdict = "seamConstrainedNeedsRealBubbleMask"
                } else if siblingOverlap {
                    fitVerdict = "siblingOverlapRisk"
                } else if failureFit == "failureFallbackLongTextRisk" {
                    fitVerdict = "failureFallbackLongTextRisk"
                } else if budget.verdict == "fontBudgetTight" || budget.verdict == "fontBudgetOverflowRisk" {
                    fitVerdict = "fontBudgetTight"
                } else if spriteDistance == true && spriteCurrent != true {
                    fitVerdict = "distanceFieldCandidateFitsReportOnly"
                } else if spriteCurrent == true {
                    fitVerdict = "currentSpriteFits"
                } else {
                    fitVerdict = "manualReviewOnly"
                }
                let action: String
                if fitVerdict == "seamConstrainedNeedsRealBubbleMask" {
                    action = "collectRealBubbleMaskArtifact"
                } else if fitVerdict == "renderDiagnosticsMissing" {
                    action = "restoreRenderDiagnostics"
                } else if fitVerdict == "manualReviewOnly" || fitVerdict == "siblingOverlapRisk" || fitVerdict == "fontBudgetTight" {
                    action = "manualReviewOnly"
                } else {
                    action = "keepRenderSpriteFitPlannerReportOnly"
                }
                let bottleneck: String
                if fitVerdict == "currentSpriteFits" {
                    bottleneck = "noneRenderLocked"
                } else if failureFit.hasPrefix("failureFallback") && failureFit != "failureFallbackAccounted" {
                    bottleneck = "failureFallbackFit"
                } else if siblingOverlap {
                    bottleneck = "sameBubbleSiblingFit"
                } else if !relatedSeams.isEmpty {
                    bottleneck = "seamConstrainedSafeArea"
                } else {
                    bottleneck = budget.verdict
                }
                return MangaKoharuRenderSpriteFitBlockLedger(
                    blockIndex: block.index,
                    bubbleID: block.bubbleID,
                    bbox: block.bbox,
                    blockPassed: block.blockPassed,
                    failureCategory: block.failureCategory,
                    textSourceForRender: textInfo.source,
                    renderTextCharacterCount: textInfo.text.count,
                    renderTextCJKCount: cjkCount(textInfo.text),
                    renderTextLatinCount: latinCount(textInfo.text),
                    currentSafeLayoutRect: currentRect,
                    bubbleIndexShadowSafeRect: bubbleIndexRect,
                    distanceFieldSafeRect: distanceRect,
                    selectedReportOnlyFitRectSource: selectedSource,
                    selectedReportOnlyFitRect: selectedRect,
                    currentRenderFontSize: block.renderFontSize ?? renderLock?.renderFontSize,
                    renderNonTransparentBounds: spriteBounds,
                    renderCollisionChecked: block.renderCollisionChecked || (renderLock?.renderCollisionChecked ?? false),
                    renderCollisionResolved: block.renderCollisionResolved || (renderLock?.renderCollisionResolved ?? false),
                    renderTextTruncated: block.renderTextTruncated || (renderLock?.renderTextTruncated ?? false),
                    spriteContainedByCurrentSafeRect: spriteCurrent,
                    spriteContainedByDistanceFieldSafeRect: spriteDistance,
                    estimatedLineCount: budget.lineCount,
                    estimatedCharsPerLine: budget.charsPerLine,
                    fontBudgetVerdict: budget.verdict,
                    fitVerdict: fitVerdict,
                    failureOverlayRequired: failureRequired,
                    failureOverlayFitVerdict: failureFit,
                    relatedSeamCandidateIDs: relatedSeams,
                    sameBubbleSiblingBlockIndexes: siblings,
                    siblingOverlapRisk: siblingOverlap,
                    renderLockVerdict: renderVerdict,
                    primaryRenderBottleneck: bottleneck,
                    nextAction: action,
                    decisionSignals: [
                        signal("selectedReportOnlyFitRectSource", selectedSource, source: "koharuRenderSpriteFitPlannerReport"),
                        signal("fontBudgetVerdict", budget.verdict, source: "blocks.renderFontSize,safeLayoutRect"),
                        signal("fitVerdict", fitVerdict, source: "koharuRenderSpriteFitPlannerReport")
                    ],
                    evaluationSignals: [
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks.groundTruthMatch", decision: false, evaluation: true),
                        signal("ocrSimilarityForEvaluation", formatted(block.ocrGroundTruthSimilarity), source: "blocks.ocrGroundTruthSimilarity", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }.sorted { $0.blockIndex < $1.blockIndex }

            let blockLedgerByIndex = Dictionary(uniqueKeysWithValues: blockLedgers.map { ($0.blockIndex, $0) })
            func makeLayoutCandidateLedger(
                block: MangaOverlayProbeBlock,
                ledger: MangaKoharuRenderSpriteFitBlockLedger?,
                candidateSource: String,
                candidateRect: [Double]?,
                siblingCurrentRects: [[Double]],
                siblingDistanceRects: [[Double]],
                currentArea: Double
            ) -> MangaKoharuRenderSpriteLayoutCandidateLedger {
                let contained: Bool? = containment(ledger?.renderNonTransparentBounds, in: candidateRect)
                let currentOverlap: Bool = siblingCurrentRects.contains { siblingRect in
                    overlapRatio(candidateRect, siblingRect) >= 0.08
                }
                let distanceOverlap: Bool = siblingDistanceRects.contains { siblingRect in
                    overlapRatio(candidateRect, siblingRect) >= 0.08
                }
                let relatedSeams: [String] = ledger?.relatedSeamCandidateIDs ?? []
                let verdict: String
                if candidateRect == nil {
                    verdict = "missingCandidateRect"
                } else if currentOverlap || distanceOverlap {
                    verdict = "siblingOverlapRisk"
                } else if !relatedSeams.isEmpty && candidateSource != "currentSafeLayoutRect" {
                    verdict = "seamConstrainedNeedsRealBubbleMask"
                } else if contained == true && candidateSource == "currentSafeLayoutRect" {
                    verdict = "currentRendererBaseline"
                } else if contained == true {
                    verdict = "containedButRequiresRendererTask"
                } else {
                    verdict = "reportOnlyCandidateNoPromotion"
                }
                let action: String = verdict == "seamConstrainedNeedsRealBubbleMask"
                    ? "collectRealBubbleMaskArtifact"
                    : "keepLayoutCandidateReportOnly"
                var blockers: [String] = ["reportOnly", "wouldChangeMainFlow=false"]
                if candidateSource != "currentSafeLayoutRect" {
                    blockers.append("notPromotedToRenderer")
                }
                if verdict == "missingCandidateRect" {
                    blockers.append("missingCandidateRect")
                }
                let candidateID = "RSF-\(block.index)-\(candidateSource)"
                let candidateArea = area(candidateRect.map(Self.rect(from:)))
                let areaDeltaValue: Double? = currentArea > 0
                    ? areaDelta(candidate: candidateRect, current: ledger?.currentSafeLayoutRect)
                    : nil
                let decisionSignals: [MangaKoharuRenderSpriteFitSignal] = [
                    signal("candidateSource", candidateSource, source: "koharuRenderSpriteFitPlannerReport"),
                    signal("spriteContained", contained.map(String.init) ?? "nil", source: "blocks.renderNonTransparentBounds"),
                    signal("candidateVerdict", verdict, source: "koharuRenderSpriteFitPlannerReport")
                ]
                let evaluationSignals: [MangaKoharuRenderSpriteFitSignal] = [
                    signal("blockPassed", String(block.blockPassed), source: "blocks.blockPassed", decision: false, evaluation: true)
                ]
                return MangaKoharuRenderSpriteLayoutCandidateLedger(
                    candidateID: candidateID,
                    blockIndex: block.index,
                    candidateSource: candidateSource,
                    candidateRect: candidateRect,
                    candidateArea: candidateArea,
                    currentSpriteBounds: ledger?.renderNonTransparentBounds,
                    spriteContained: contained,
                    areaDeltaVsCurrent: areaDeltaValue,
                    overlapsSiblingCurrentSafeRect: currentOverlap,
                    overlapsSiblingDistanceFieldRect: distanceOverlap,
                    relatedSeamCandidateIDs: relatedSeams,
                    candidateVerdict: verdict,
                    promotionBlockedReasons: blockers,
                    nextAction: action,
                    decisionSignals: decisionSignals,
                    evaluationSignals: evaluationSignals,
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }

            var layoutCandidateLedgers: [MangaKoharuRenderSpriteLayoutCandidateLedger] = []
            for block in blocks {
                let ledger = blockLedgerByIndex[block.index]
                let siblings = siblingIndexesByBlock[block.index] ?? []
                let siblingCurrentRects = siblings.compactMap { blockLedgerByIndex[$0]?.currentSafeLayoutRect }
                let siblingDistanceRects = siblings.compactMap { blockLedgerByIndex[$0]?.distanceFieldSafeRect }
                let currentArea = area(ledger?.currentSafeLayoutRect.map(Self.rect(from:)))
                let candidates: [(String, [Double]?)] = [
                    ("currentSafeLayoutRect", ledger?.currentSafeLayoutRect),
                    ("distanceFieldSafeRect", ledger?.distanceFieldSafeRect),
                    ("bubbleIndexShadowSafeRect", ledger?.bubbleIndexShadowSafeRect)
                ]
                for (source, rect) in candidates {
                    let candidateLedger = makeLayoutCandidateLedger(
                        block: block,
                        ledger: ledger,
                        candidateSource: source,
                        candidateRect: rect,
                        siblingCurrentRects: siblingCurrentRects,
                        siblingDistanceRects: siblingDistanceRects,
                        currentArea: currentArea
                    )
                    layoutCandidateLedgers.append(candidateLedger)
                }
            }
            layoutCandidateLedgers.sort { lhs, rhs in
                lhs.blockIndex == rhs.blockIndex ? lhs.candidateID < rhs.candidateID : lhs.blockIndex < rhs.blockIndex
            }

            let siblingLedgers: [MangaKoharuRenderSpriteSiblingFitLedger] = blocksByBubble
                .filter { $0.value.count > 1 }
                .map { bubbleID, groupBlocks in
                    let indexes = groupBlocks.map(\.index)
                    let ledgers = indexes.compactMap { blockLedgerByIndex[$0] }
                    let currentOverlap = maxOverlap(ledgers.compactMap(\.currentSafeLayoutRect))
                    let distanceOverlap = maxOverlap(ledgers.compactMap(\.distanceFieldSafeRect))
                    let spriteOverlap = maxOverlap(ledgers.compactMap(\.renderNonTransparentBounds))
                    let seamIDs = uniqueSortedStrings(ledgers.flatMap(\.relatedSeamCandidateIDs))
                    let verdict: String
                    if !seamIDs.isEmpty {
                        verdict = "seamConstrainedSiblingGroup"
                    } else if currentOverlap >= 0.08 {
                        verdict = "currentSafeRectOverlapRisk"
                    } else if distanceOverlap >= 0.08 {
                        verdict = "distanceFieldSiblingOverlapRisk"
                    } else if koharuBubbleIndexShadowLedgerReport == nil {
                        verdict = "needsRealBubbleMaskArtifact"
                    } else {
                        verdict = "siblingPartitionStable"
                    }
                    let fitVerdict = (verdict == "siblingPartitionStable") ? "currentSiblingFitStable" : "siblingOverlapRisk"
                    let action = verdict == "needsRealBubbleMaskArtifact" || verdict == "seamConstrainedSiblingGroup"
                        ? "collectRealBubbleMaskArtifact"
                        : (verdict == "siblingPartitionStable" ? "keepSiblingFitReportOnly" : "manualReviewOnly")
                    return MangaKoharuRenderSpriteSiblingFitLedger(
                        siblingGroupID: "RSF-\(bubbleID)",
                        bubbleID: bubbleID,
                        blockIndexes: indexes,
                        currentSafeRectMaxOverlapRatio: currentOverlap,
                        distanceFieldSafeRectMaxOverlapRatio: distanceOverlap,
                        currentSpriteBoundsOverlapRatio: spriteOverlap,
                        relatedSeamCandidateIDs: seamIDs,
                        sameBubbleSiblingPartitionVerdict: verdict,
                        fitVerdict: fitVerdict,
                        affectedBlocks: verdict == "siblingPartitionStable" ? [] : indexes,
                        nextAction: action,
                        decisionSignals: [
                            signal("currentSafeRectMaxOverlapRatio", formatted(currentOverlap), source: "blocks.safeLayoutRect"),
                            signal("distanceFieldSafeRectMaxOverlapRatio", formatted(distanceOverlap), source: "koharuDistanceFieldSafeAreaReport"),
                            signal("sameBubbleSiblingPartitionVerdict", verdict, source: "koharuRenderSpriteFitPlannerReport")
                        ],
                        evaluationSignals: [
                            signal("blockCount", String(indexes.count), source: "blocks.bubbleID", decision: false, evaluation: true)
                        ],
                        groundTruthUsedForDecision: false,
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true
                    )
                }
                .sorted { $0.bubbleID < $1.bubbleID }

            let fontRiskBlocks = uniqueSorted(blockLedgers.filter {
                $0.fontBudgetVerdict == "fontBudgetTight" || $0.fontBudgetVerdict == "fontBudgetOverflowRisk"
            }.map(\.blockIndex))
            let spriteRiskBlocks = uniqueSorted(blockLedgers.filter {
                $0.spriteContainedByCurrentSafeRect == false || $0.spriteContainedByDistanceFieldSafeRect == false
            }.map(\.blockIndex))
            let siblingRiskBlocks = uniqueSorted(blockLedgers.filter(\.siblingOverlapRisk).map(\.blockIndex) + siblingLedgers.flatMap(\.affectedBlocks))
            let failureRiskBlocks = uniqueSorted(blockLedgers.filter {
                $0.failureOverlayFitVerdict == "failureFallbackLongTextRisk" || $0.failureOverlayFitVerdict == "failureFallbackSpriteContainmentRisk"
            }.map(\.blockIndex))
            let seamBlocks = uniqueSorted(blockLedgers.filter { !$0.relatedSeamCandidateIDs.isEmpty }.map(\.blockIndex))
            let needsRealBubbleMaskBlocks = uniqueSorted(blockLedgers.filter { $0.nextAction == "collectRealBubbleMaskArtifact" }.map(\.blockIndex) + siblingLedgers.filter { $0.nextAction == "collectRealBubbleMaskArtifact" }.flatMap(\.blockIndexes))
            let renderLockedBlocks = uniqueSorted(blockLedgers.filter { $0.renderLockVerdict == "renderLocked" || $0.fitVerdict == "currentSpriteFits" }.map(\.blockIndex))
            let manualReviewBlocks = uniqueSorted(blockLedgers.filter { $0.nextAction == "manualReviewOnly" }.map(\.blockIndex) + siblingLedgers.filter { $0.nextAction == "manualReviewOnly" }.flatMap(\.blockIndexes))

            func gate(
                _ id: String,
                _ name: String,
                _ scope: String,
                _ status: String,
                _ threshold: String,
                _ affected: [Int],
                _ failure: String,
                _ action: String,
                _ signals: [MangaKoharuRenderSpriteFitSignal]
            ) -> MangaKoharuRenderSpriteFitGate {
                MangaKoharuRenderSpriteFitGate(
                    gateID: id,
                    gateName: name,
                    scope: scope,
                    status: status,
                    threshold: threshold,
                    affectedBlocks: uniqueSorted(affected),
                    decisionSignals: signals,
                    failureMeans: failure,
                    recommendedAction: action,
                    groundTruthUsedForDecision: false
                )
            }

            let gateLedger = [
                gate("G-render-sprite-fit-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "fit planner mutates renderer, safeLayoutRect, OCR, translation, or block pass state", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuRenderSpriteFitPlannerReport")]),
                gate("G-render-sprite-fit-no-ground-truth-decision", "No ground truth decision", "report", "passed", "groundTruthUsedForDecision=false", allBlocks, "ground truth influences fit verdict, candidate choice, sibling risk, gate, or next action", "moveGroundTruthToEvaluationSignalsOnly", [signal("groundTruthUsedForDecision", "false", source: "koharuRenderSpriteFitPlannerReport")]),
                gate("G-render-sprite-fit-block-ledger-count", "Block ledger count", "blocks", blockLedgers.count == blocks.count ? "passed" : "warning", "blockLedgerCount==totalBlocksDetected", allBlocks, "some final blocks lack render sprite fit ledger rows", "restoreRenderSpriteFitBlockLedger", [signal("blockLedgerCount", String(blockLedgers.count), source: "koharuRenderSpriteFitPlannerReport")]),
                gate("G-render-sprite-fit-layout-candidates", "Layout candidates", "RenderedSprites", layoutCandidateLedgers.count >= blocks.count ? "passed" : "warning", "layoutCandidateCount>=totalBlocksDetected", allBlocks, "layout candidate ledger is missing current/distance/bubble-index candidates", "restoreLayoutCandidateLedger", [signal("layoutCandidateCount", String(layoutCandidateLedgers.count), source: "koharuRenderSpriteFitPlannerReport")]),
                gate("G-render-sprite-fit-current-render-lock-linked", "Render lock linked", "FinalRender", koharuRenderRegressionLockReport == nil ? "warning" : "passed", "koharuRenderRegressionLockReport available as upstream evidence", allBlocks, "fit planner ignores render regression lock or changes overlay renderer", "inspectRenderLockGateLedger", [signal("renderLockAvailable", String(koharuRenderRegressionLockReport != nil), source: "koharuRenderRegressionLockReport")]),
                gate("G-render-sprite-fit-distance-field-linked", "DistanceField linked", "BubbleIndex", koharuDistanceFieldSafeAreaReport == nil ? "warning" : "passed", "koharuDistanceFieldSafeAreaReport available", allBlocks, "fit planner cannot compare distance-field candidate rects", "restoreDistanceFieldSafeAreaReport", [signal("distanceFieldAvailable", String(koharuDistanceFieldSafeAreaReport != nil), source: "koharuDistanceFieldSafeAreaReport")]),
                gate("G-render-sprite-fit-bubble-index-linked", "BubbleIndex linked", "BubbleIndex", koharuBubbleIndexShadowLedgerReport == nil ? "warning" : "passed", "koharuBubbleIndexShadowLedgerReport available", allBlocks, "fit planner cannot compare BubbleIndex shadow safe rects", "restoreBubbleIndexShadowLedgerReport", [signal("bubbleIndexAvailable", String(koharuBubbleIndexShadowLedgerReport != nil), source: "koharuBubbleIndexShadowLedgerReport")]),
                gate("G-render-sprite-fit-seam-linked", "Seam linked", "BubbleMask", koharuBubbleAdjacencySeamReport == nil ? "warning" : "passed", "koharuBubbleAdjacencySeamReport available", seamBlocks, "fit planner hides seam-constrained layout risk", "restoreBubbleAdjacencySeamReport", [signal("seamReportAvailable", String(koharuBubbleAdjacencySeamReport != nil), source: "koharuBubbleAdjacencySeamReport")]),
                gate("G-render-sprite-fit-failure-overlay-accounted", "Failure overlay accounted", "RenderedSprites", failureRiskBlocks.isEmpty ? "passed" : "warning", "failure fallback text fit risk is explicit", failureRiskBlocks, "failed blocks are silently skipped or their fallback text budget is hidden", "reviewFailureFallbackFit", [signal("failureOverlayRiskBlocks", joined(failureRiskBlocks), source: "koharuRenderSpriteFitPlannerReport")]),
                gate("G-render-sprite-fit-no-renderer-mutation", "No renderer mutation", "FinalRender", "passed", "overlay renderer and PNG behavior unchanged", [], "fit planner writes back safeLayoutRect, glyph mask, background fill, or overlay PNG", "revertRendererMutation", [signal("proxyNotRealKoharuRenderer", "true", source: "koharuRenderSpriteFitPlannerReport")]),
                gate("G-render-sprite-fit-ci-fast-ready", "CI fast ready", "ci-fast", "passed", "uses existing reports only", allBlocks, "fit planner adds OCR/LLM/full-only dependency", "keepCIFastReportOnly", [signal("inputReports", "blocks,koharuRenderRegressionLockReport,koharuBubbleIndexShadowLedgerReport,koharuDistanceFieldSafeAreaReport,koharuBubbleAdjacencySeamReport", source: "koharuRenderSpriteFitPlannerReport")])
            ]

            let plannerVerdict: String
            if koharuRenderRegressionLockReport == nil {
                plannerVerdict = "blockedByMissingRenderDiagnostics"
            } else if !needsRealBubbleMaskBlocks.isEmpty {
                plannerVerdict = "needsRealBubbleMaskArtifact"
            } else if !manualReviewBlocks.isEmpty || !fontRiskBlocks.isEmpty || !siblingRiskBlocks.isEmpty || !failureRiskBlocks.isEmpty {
                plannerVerdict = "manualReviewOnly"
            } else if renderLockedBlocks.count == blocks.count {
                plannerVerdict = "renderLockedNoPromotion"
            } else if layoutCandidateLedgers.contains(where: { $0.candidateSource != "currentSafeLayoutRect" && $0.candidateVerdict == "containedButRequiresRendererTask" }) {
                plannerVerdict = "reportOnlyLayoutCandidatesReady"
            } else {
                plannerVerdict = "renderSpriteFitLedgerReady"
            }

            return MangaKoharuRenderSpriteFitPlannerReport(
                enabled: true,
                source: "AITRANSProbe",
                referencePipeline: "Koharu",
                referenceConcept: "RenderedSprites.FontSizeSearch.SpriteFitBudget",
                referenceWorkItemID: "WI-koharu-render-sprite-fit-planner",
                evaluatedBlockCount: blocks.count,
                layoutCandidateCount: layoutCandidateLedgers.count,
                blockLedgerCount: blockLedgers.count,
                siblingLedgerCount: siblingLedgers.count,
                gateCount: gateLedger.count,
                groundTruthUsedForDecision: false,
                groundTruthUsedForEvaluationOnly: true,
                wouldChangeMainFlow: false,
                diagnosticOnly: true,
                proxyNotRealKoharuRenderer: true,
                proxyNotRealBubbleMask: true,
                externalArtifactsRequiredForThisReport: false,
                fitPlannerVerdict: plannerVerdict,
                textSourceBreakdown: countBy(blockLedgers.map(\.textSourceForRender)),
                layoutRectSourceBreakdown: countBy(blockLedgers.map(\.selectedReportOnlyFitRectSource)),
                fitVerdictBreakdown: countBy(blockLedgers.map(\.fitVerdict)),
                fontBudgetBreakdown: countBy(blockLedgers.map(\.fontBudgetVerdict)),
                spriteContainmentBreakdown: countBy(blockLedgers.map { ledger in
                    if ledger.spriteContainedByCurrentSafeRect == true && ledger.spriteContainedByDistanceFieldSafeRect == true { return "containedByBoth" }
                    if ledger.spriteContainedByCurrentSafeRect == true { return "containedByCurrentOnly" }
                    if ledger.spriteContainedByDistanceFieldSafeRect == true { return "containedByDistanceOnly" }
                    return "uncontainedOrMissingSpriteBounds"
                }),
                siblingFitVerdictBreakdown: countBy(siblingLedgers.map(\.sameBubbleSiblingPartitionVerdict)),
                failureOverlayFitBreakdown: countBy(blockLedgers.map(\.failureOverlayFitVerdict)),
                nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                fontBudgetRiskBlocks: fontRiskBlocks,
                spriteContainmentRiskBlocks: spriteRiskBlocks,
                siblingOverlapRiskBlocks: siblingRiskBlocks,
                failureOverlayRiskBlocks: failureRiskBlocks,
                seamConstrainedBlocks: seamBlocks,
                needsRealBubbleMaskBlocks: needsRealBubbleMaskBlocks,
                renderLockedBlocks: renderLockedBlocks,
                manualReviewBlocks: manualReviewBlocks,
                layoutCandidateLedgers: layoutCandidateLedgers,
                blockLedgers: blockLedgers,
                siblingLedgers: siblingLedgers,
                gateLedger: gateLedger,
                notes: [
                    "koharuRenderSpriteFitPlannerReport is a report-only Koharu RenderedSprites fit planner ledger.",
                    "It estimates font budget, line pressure, layout candidates, sibling overlap, seam constraints, sprite containment, and failure fallback fit from existing render diagnostics and Koharu shadow reports only.",
                    "Ground truth appears only in evaluationSignals; fit verdicts, layout candidate status, sibling fit, gates, and nextAction use ground-truth-free render and geometry signals.",
                    "The report does not add OCR or LLM calls and does not change OCR, translation input, safeLayoutRect, DistanceField safe rect, glyphMaskFillRects, background fill, overlay rendering, blockPassed, failureCategory, active artifacts, currentBlockSource, or PNG output behavior."
                ]
            )
        }.value
    }

    func makeKoharuNativeTextBoxDetectorLiteReport(
        image: CGImage,
        blocks: [MangaOverlayProbeBlock],
        bubbleGeometry: MangaOverlayBubbleGeometryDiagnostics,
        bubbleMaskReport: MangaOverlayBubbleMaskReport?,
        segmentMaskReport: MangaOverlaySegmentMaskReport?,
        translationModelFloorComparisonReport: MangaTranslationModelFloorComparisonReport?,
        koharuRenderRegressionLockReport: MangaKoharuRenderRegressionLockReport?
    ) async -> MangaKoharuNativeTextBoxDetectorLiteReport {
        await Task.detached(priority: .userInitiated) {
            func uniqueSorted(_ values: [Int]) -> [Int] { Array(Set(values)).sorted() }
            func countBy(_ values: [String]) -> [String: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
            func formatted(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(4))) }
            func area(_ rect: CGRect) -> Double { Double(max(0, rect.width) * max(0, rect.height)) }
            func signal(
                _ name: String,
                _ value: String,
                source: String,
                decision: Bool = true,
                evaluation: Bool = false
            ) -> MangaKoharuNativeTextBoxDetectorLiteSignal {
                MangaKoharuNativeTextBoxDetectorLiteSignal(
                    name: name,
                    value: value,
                    sourceReport: source,
                    groundTruthFreeDecisionSignal: decision,
                    groundTruthUsedForEvaluationOnly: evaluation
                )
            }
            func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> Double {
                let intersection = lhs.intersection(rhs)
                guard !intersection.isNull else { return 0 }
                return area(intersection) / max(1, min(area(lhs), area(rhs)))
            }
            func projectionPeakCount(_ values: [Int], threshold: Int) -> Int {
                guard !values.isEmpty else { return 0 }
                var peaks = 0
                var inPeak = false
                for value in values {
                    if value >= threshold {
                        if !inPeak { peaks += 1 }
                        inPeak = true
                    } else {
                        inPeak = false
                    }
                }
                return peaks
            }
            func directionHint(width: CGFloat, height: CGFloat, horizontalPeaks: Int, verticalPeaks: Int) -> String {
                if height > width * 1.15 || verticalPeaks > horizontalPeaks + 1 { return "verticalCandidate" }
                if width > height * 1.10 || horizontalPeaks >= verticalPeaks { return "horizontal" }
                return "unknown"
            }
            func candidateVerdict(
                rect: CGRect,
                bubbleRect: CGRect,
                darkDensity: Double,
                componentCount: Int,
                bubbleCoverage: Double,
                segmentOverlap: Double,
                score: Double
            ) -> (String, Bool, [String]) {
                var reasons: [String] = []
                let bubbleArea = max(1, area(bubbleRect))
                let rectArea = area(rect)
                if bubbleCoverage < 0.72 { reasons.append("outsideBubble") }
                if darkDensity < 0.012 { reasons.append("lowDensity") }
                if rectArea / bubbleArea > 0.78 { reasons.append("tooLarge") }
                if componentCount < 2 { reasons.append("tooFewComponents") }
                if segmentOverlap < 0.05 { reasons.append("weakSegmentEvidence") }
                if reasons.contains("outsideBubble") { return ("rejectedOutsideBubble", false, reasons) }
                if reasons.contains("tooLarge") { return ("rejectedTooLarge", false, reasons) }
                if reasons.contains("lowDensity") { return ("rejectedLowDensity", false, reasons) }
                if reasons.contains("weakSegmentEvidence") && score < 0.58 { return ("rejectedWeakSegmentEvidence", false, reasons) }
                if score >= 0.52 { return ("acceptedShadowOnly", true, reasons) }
                return ("manualReviewOnly", false, reasons)
            }

            guard let bitmap = Self.makeRGBA8Bitmap(from: image) else {
                let gate = MangaKoharuNativeTextBoxDetectorLiteGate(
                    gateID: "G-native-textbox-detector-lite-image-bytes",
                    gateName: "Image bytes available",
                    scope: "SourceImage",
                    status: "blocked",
                    threshold: "32-bit CGImage provider bytes readable",
                    affectedBlocks: blocks.map(\.index),
                    decisionSignals: [signal("imageBytesAvailable", "false", source: "SourceImage")],
                    failureMeans: "native detector-lite cannot inspect pixels",
                    recommendedAction: "restoreProbeImageByteAccess",
                    groundTruthUsedForDecision: false
                )
                return MangaKoharuNativeTextBoxDetectorLiteReport(
                    enabled: true,
                    source: "AITRANSProbe",
                    referencePipeline: "Koharu",
                    referenceConcept: "TextBoxes.NativeDetectorLite.PreOCRArtifact",
                    referenceWorkItemID: "WI-koharu-native-textbox-detector-lite",
                    evaluatedBlockCount: blocks.count,
                    evaluatedBubbleCount: bubbleGeometry.bubbles.count,
                    candidateCount: 0,
                    acceptedCandidateCount: 0,
                    rejectedCandidateCount: 0,
                    shadowOCREligibleCandidateCount: 0,
                    blockLedgerCount: 0,
                    bubbleLedgerCount: 0,
                    gateCount: 1,
                    groundTruthUsedForDecision: false,
                    groundTruthUsedForEvaluationOnly: true,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true,
                    proxyNotRealKoharuTextBoxes: true,
                    externalArtifactsRequiredForThisReport: false,
                    detectorLiteVerdict: "insufficientPixelEvidence",
                    candidateSourceBreakdown: [:],
                    directionHintBreakdown: [:],
                    candidateVerdictBreakdown: [:],
                    blockRelationBreakdown: [:],
                    rejectionReasonBreakdown: ["imageBytesUnavailable": 1],
                    primaryBottleneckBreakdown: [:],
                    nextActionBreakdown: [:],
                    ocrInputSuspectBlocks: [],
                    bubbleAssignmentRiskBlocks: [],
                    segmentEvidenceWeakBlocks: [],
                    modelFloorLimitedBlocks: [],
                    renderLockedBlocks: [],
                    needsRealTextBoxesBlocks: blocks.map(\.index),
                    manualReviewBlocks: blocks.map(\.index),
                    candidates: [],
                    blockLedgers: [],
                    bubbleLedgers: [],
                    gateLedger: [gate],
                    notes: ["Pixel bytes unavailable; detector-lite report emitted blocked gate only."]
                )
            }

            let bytes = bitmap.pixels
            let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            let bytesPerRow = bitmap.bytesPerRow
            let maskRuntime = Self.makeApproximateBubbleMaskRuntime(image: image, bubbleGeometry: bubbleGeometry)
            let segmentRects = (segmentMaskReport?.diagnostics ?? []).compactMap { diagnostic -> CGRect? in
                guard let rect = diagnostic.glyphMaskRect else { return nil }
                return Self.rect(from: rect)
            }

            func segmentOverlap(for rect: CGRect) -> Double {
                guard !segmentRects.isEmpty else { return 0 }
                var intersectionArea = 0.0
                for segmentRect in segmentRects {
                    let intersection = rect.intersection(segmentRect)
                    if !intersection.isNull {
                        intersectionArea += area(intersection)
                    }
                }
                return min(1, intersectionArea / max(1, area(rect)))
            }

            func makeCandidates(for bubble: MangaOverlayProbeBubble) -> [MangaKoharuNativeTextBoxDetectorLiteCandidate] {
                typealias Component = (rect: CGRect, pixelCount: Int)
                let bubbleRect = Self.clamp(Self.rect(from: bubble.bbox).integral, to: imageBounds)
                guard bubbleRect.width >= 8, bubbleRect.height >= 8 else { return [] }
                let width = Int(bubbleRect.width)
                let height = Int(bubbleRect.height)
                guard width > 0, height > 0 else { return [] }

                var gray = [UInt8](repeating: 255, count: width * height)
                var sum = 0
                for localY in 0..<height {
                    let y = Int(bubbleRect.minY) + localY
                    for localX in 0..<width {
                        let x = Int(bubbleRect.minX) + localX
                        guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
                        let offset = y * bytesPerRow + x * 4
                        guard offset + 2 < bytes.count else { continue }
                        let luminance = (Int(bytes[offset]) * 299 + Int(bytes[offset + 1]) * 587 + Int(bytes[offset + 2]) * 114) / 1000
                        gray[localY * width + localX] = UInt8(max(0, min(255, luminance)))
                        sum += luminance
                    }
                }
                let mean = Double(sum) / Double(max(1, width * height))
                let threshold = max(30, min(205, Int(mean - 24)))
                var foreground = [Bool](repeating: false, count: width * height)
                for y in 0..<height {
                    for x in 0..<width {
                        let index = y * width + x
                        foreground[index] = Int(gray[index]) <= threshold
                    }
                }

                var visited = [Bool](repeating: false, count: width * height)
                var components: [Component] = []
                let minArea = max(2, Int(min(bubbleRect.width, bubbleRect.height) * 0.025))
                let maxArea = max(minArea + 1, Int(area(bubbleRect) * 0.16))
                for startY in 0..<height {
                    for startX in 0..<width {
                        let startOffset = startY * width + startX
                        guard foreground[startOffset], !visited[startOffset] else { continue }
                        var queue = [startOffset]
                        var cursor = 0
                        visited[startOffset] = true
                        var pixelCount = 0
                        var minX = startX
                        var maxX = startX
                        var minY = startY
                        var maxY = startY
                        while cursor < queue.count {
                            let offset = queue[cursor]
                            cursor += 1
                            pixelCount += 1
                            let y = offset / width
                            let x = offset % width
                            minX = min(minX, x)
                            maxX = max(maxX, x)
                            minY = min(minY, y)
                            maxY = max(maxY, y)
                            for neighbor in Self.glyphNeighborOffsets(x: x, y: y, width: width, height: height) {
                                if foreground[neighbor], !visited[neighbor] {
                                    visited[neighbor] = true
                                    queue.append(neighbor)
                                }
                            }
                        }
                        guard pixelCount >= minArea, pixelCount <= maxArea else { continue }
                        let rect = CGRect(
                            x: CGFloat(minX) + bubbleRect.minX,
                            y: CGFloat(minY) + bubbleRect.minY,
                            width: CGFloat(maxX - minX + 1),
                            height: CGFloat(maxY - minY + 1)
                        )
                        let longSide = max(rect.width, rect.height)
                        let shortSide = max(1, min(rect.width, rect.height))
                        guard longSide / shortSide <= 18 else { continue }
                        components.append((rect: rect, pixelCount: pixelCount))
                    }
                }
                guard !components.isEmpty else { return [] }

                func unionRect(for cluster: [Component]) -> CGRect {
                    var union = cluster[0].rect
                    for component in cluster.dropFirst() {
                        union = union.union(component.rect)
                    }
                    return Self.clamp(union.insetBy(dx: -3, dy: -3).integral, to: bubbleRect)
                }

                func projectionClusters(axis: String) -> (clusters: [[Component]], score: Double) {
                    let sorted: [Component]
                    let axisLength: CGFloat
                    if axis == "x" {
                        sorted = components.sorted { $0.rect.midX < $1.rect.midX }
                        axisLength = max(1, bubbleRect.width)
                    } else {
                        sorted = components.sorted { $0.rect.midY < $1.rect.midY }
                        axisLength = max(1, bubbleRect.height)
                    }
                    guard let first = sorted.first else { return ([], 0) }
                    let splitGap = max(12, min(bubbleRect.width, bubbleRect.height) * 0.11)
                    var clusters: [[Component]] = [[first]]
                    var currentMax = axis == "x" ? first.rect.maxX : first.rect.maxY
                    var bestGap: CGFloat = 0
                    for component in sorted.dropFirst() {
                        let nextMin = axis == "x" ? component.rect.minX : component.rect.minY
                        let nextMax = axis == "x" ? component.rect.maxX : component.rect.maxY
                        let gap = nextMin - currentMax
                        if gap >= splitGap {
                            clusters.append([component])
                            bestGap = max(bestGap, gap)
                            currentMax = nextMax
                        } else {
                            clusters[clusters.count - 1].append(component)
                            currentMax = max(currentMax, nextMax)
                        }
                    }
                    let validClusters = clusters.filter { cluster in
                        let rect = unionRect(for: cluster)
                        return cluster.count >= 2
                            && rect.width >= 4
                            && rect.height >= 4
                            && area(rect) / max(1, area(bubbleRect)) <= 0.72
                    }
                    guard validClusters.count >= 2 else { return ([], 0) }
                    return (Array(validClusters.prefix(4)), Double(bestGap / axisLength))
                }

                let xClusters = projectionClusters(axis: "x")
                let yClusters = projectionClusters(axis: "y")
                let selectedClusters: [[Component]]
                if xClusters.clusters.count >= 2 || yClusters.clusters.count >= 2 {
                    selectedClusters = xClusters.score >= yClusters.score ? xClusters.clusters : yClusters.clusters
                } else {
                    selectedClusters = []
                }

                let candidateInputs: [([Component], String)]
                if selectedClusters.count >= 2 {
                    candidateInputs = selectedClusters.map { ($0, "componentCluster") } + [(components, "unionFallback")]
                } else {
                    candidateInputs = [(components, "singleUnion")]
                }

                func buildCandidate(from cluster: [Component], clusterIndex: Int, clusterKind: String) -> MangaKoharuNativeTextBoxDetectorLiteCandidate {
                    let unionRect = unionRect(for: cluster)
                    let localUnion = unionRect.offsetBy(dx: -bubbleRect.minX, dy: -bubbleRect.minY)
                    var horizontalProjection = [Int](repeating: 0, count: height)
                    var verticalProjection = [Int](repeating: 0, count: width)
                    let minY = max(0, Int(localUnion.minY))
                    let maxY = min(height, Int(localUnion.maxY))
                    let minX = max(0, Int(localUnion.minX))
                    let maxX = min(width, Int(localUnion.maxX))
                    for y in minY..<maxY {
                        for x in minX..<maxX where foreground[y * width + x] {
                            horizontalProjection[y] += 1
                            verticalProjection[x] += 1
                        }
                    }
                    let hThreshold = max(1, Int(Double(maxX - minX) * 0.08))
                    let vThreshold = max(1, Int(Double(maxY - minY) * 0.08))
                    let hPeaks = projectionPeakCount(horizontalProjection, threshold: hThreshold)
                    let vPeaks = projectionPeakCount(verticalProjection, threshold: vThreshold)
                    let hint = directionHint(width: unionRect.width, height: unionRect.height, horizontalPeaks: hPeaks, verticalPeaks: vPeaks)
                    let acceptedPixelCount = cluster.reduce(0) { $0 + $1.pixelCount }
                    let darkDensity = Double(acceptedPixelCount) / max(1, area(unionRect))
                    let bubbleCoverage = maskRuntime.coverageRatio(of: unionRect, bubbleID: bubble.id)
                    let glyphOverlap = segmentOverlap(for: unionRect)
                    let aspect = Double(unionRect.width / max(1, unionRect.height))
                    let coverageScore = min(1, bubbleCoverage)
                    let densityScore = min(1, darkDensity / 0.16)
                    let componentScore = min(1, Double(cluster.count) / 10.0)
                    let segmentScore = min(1, glyphOverlap * 1.35)
                    let score = (coverageScore * 0.32) + (densityScore * 0.26) + (componentScore * 0.18) + (segmentScore * 0.14) + (min(1, Double(max(hPeaks, vPeaks)) / 6.0) * 0.10)
                    var verdict = candidateVerdict(
                        rect: unionRect,
                        bubbleRect: bubbleRect,
                        darkDensity: darkDensity,
                        componentCount: cluster.count,
                        bubbleCoverage: bubbleCoverage,
                        segmentOverlap: glyphOverlap,
                        score: score
                    )
                    if clusterKind == "unionFallback" {
                        verdict.0 = "manualReviewUnionFallback"
                        verdict.1 = false
                        verdict.2.append("multiCandidateUnionFallbackNotShadowOCREligible")
                    }
                    var blockRelations = blocks.compactMap { block -> MangaKoharuNativeTextBoxDetectorLiteBlockRelation? in
                        let blockRect = Self.rect(from: block.bbox)
                        let center = CGPoint(x: blockRect.midX, y: blockRect.midY)
                        let overlap = overlapRatio(blockRect, unionRect)
                        let centerContained = unionRect.contains(center)
                        let sameBubble = block.bubbleID == bubble.id
                        if clusterKind == "componentCluster" {
                            guard sameBubble && (overlap >= 0.08 || centerContained) else { return nil }
                        } else {
                            guard sameBubble || overlap >= 0.20 || centerContained else { return nil }
                        }
                        let reason: String
                        if sameBubble && centerContained {
                            reason = "sameBubbleCenterContained"
                        } else if sameBubble && overlap >= 0.08 {
                            reason = "sameBubbleOverlap"
                        } else if centerContained {
                            reason = "centerContained"
                        } else {
                            reason = "overlapFallback"
                        }
                        return MangaKoharuNativeTextBoxDetectorLiteBlockRelation(
                            blockIndex: block.index,
                            overlapRatio: overlap,
                            centerContained: centerContained,
                            sameBubble: sameBubble,
                            relationReason: reason
                        )
                    }
                    var relatedBlocks = blockRelations.map(\.blockIndex)
                    if relatedBlocks.isEmpty, clusterKind == "componentCluster" {
                        let fallbackRelations = blocks
                            .filter { $0.bubbleID == bubble.id }
                            .map { block in
                                (index: block.index, overlap: overlapRatio(Self.rect(from: block.bbox), unionRect))
                            }
                            .sorted { lhs, rhs in
                                if lhs.overlap == rhs.overlap { return lhs.index < rhs.index }
                                return lhs.overlap > rhs.overlap
                            }
                            .prefix(1)
                        relatedBlocks = fallbackRelations.map(\.index)
                        blockRelations.append(contentsOf: fallbackRelations.map {
                            MangaKoharuNativeTextBoxDetectorLiteBlockRelation(
                                blockIndex: $0.index,
                                overlapRatio: $0.overlap,
                                centerContained: false,
                                sameBubble: true,
                                relationReason: "nearestSameBubbleFallback"
                            )
                        })
                    }
                    let matchedBlocks = blocks.filter { block in
                        overlapRatio(Self.rect(from: block.bbox), unionRect) >= 0.35
                    }.map(\.index)
                    let candidateID = "NTBDL-\(bubble.id)-\(String(format: "%02d", clusterIndex))"
                    let splitSignal = selectedClusters.count >= 2 ? "multiCandidateBubble" : "singleCandidateBubble"
                    return MangaKoharuNativeTextBoxDetectorLiteCandidate(
                        candidateID: candidateID,
                        source: "nativeDetectorLite",
                        sourceBubbleID: bubble.id,
                        bbox: Self.bboxArray(from: unionRect),
                        candidateArea: area(unionRect),
                        directionHint: hint,
                        generationSignals: ["connectedComponentGroup", "strokeDensityBand", "projectionBand", "bubbleInteriorDarkPixels", "glyphProxyOverlap", clusterKind, splitSignal],
                        bubbleCoverageRatio: bubbleCoverage,
                        segmentGlyphOverlapRatio: glyphOverlap,
                        darkPixelDensity: darkDensity,
                        componentCount: cluster.count,
                        projectionPeakCount: max(hPeaks, vPeaks),
                        aspectRatio: aspect,
                        score: score,
                        candidateVerdict: verdict.0,
                        shadowOCREligible: verdict.1,
                        matchedBlockIndexes: uniqueSorted(matchedBlocks),
                        relatedCurrentBlockIndexes: uniqueSorted(relatedBlocks),
                        relatedBlockRelations: blockRelations.sorted { lhs, rhs in
                            if lhs.blockIndex == rhs.blockIndex { return lhs.overlapRatio > rhs.overlapRatio }
                            return lhs.blockIndex < rhs.blockIndex
                        },
                        wouldChangeMainFlow: false,
                        diagnosticOnly: true,
                        groundTruthUsedForDecision: false,
                        decisionSignals: [
                            signal("source", "nativeDetectorLite", source: "SourceImagePixels"),
                            signal("clusterKind", clusterKind, source: "SourceImagePixels"),
                            signal("candidatePoolCap", "4 component clusters plus 1 union fallback per bubble", source: "koharuNativeTextBoxDetectorLiteReport"),
                            signal("darkPixelDensity", formatted(darkDensity), source: "SourceImagePixels"),
                            signal("bubbleCoverageRatio", formatted(bubbleCoverage), source: "BubbleMaskProxy"),
                            signal("score", formatted(score), source: "koharuNativeTextBoxDetectorLiteReport")
                        ],
                        evaluationSignals: [
                            signal("matchedBlockIndexes", uniqueSorted(matchedBlocks).map(String.init).joined(separator: ","), source: "blocks.bbox", decision: false, evaluation: true)
                        ],
                        rejectionReasons: verdict.2,
                        notes: [
                            "candidate bbox is generated from pixel dark component clusters and projection valleys inside bubble bbox before any Vision OCR text is read",
                            "Vision OCR text, pre-crop plan, line plan, TextRegion crop output, and ground truth are not used to generate or rank this candidate"
                        ]
                    )
                }

                return candidateInputs.enumerated().map { index, input in
                    buildCandidate(from: input.0, clusterIndex: index, clusterKind: input.1)
                }
            }

            var candidates: [MangaKoharuNativeTextBoxDetectorLiteCandidate] = []
            for bubble in bubbleGeometry.bubbles.sorted(by: { $0.id < $1.id }) {
                candidates.append(contentsOf: makeCandidates(for: bubble))
            }
            func detectorCandidateSort(_ lhs: MangaKoharuNativeTextBoxDetectorLiteCandidate, _ rhs: MangaKoharuNativeTextBoxDetectorLiteCandidate) -> Bool {
                if lhs.sourceBubbleID != rhs.sourceBubbleID {
                    return (lhs.sourceBubbleID ?? -1) < (rhs.sourceBubbleID ?? -1)
                }
                if lhs.shadowOCREligible != rhs.shadowOCREligible {
                    return lhs.shadowOCREligible && !rhs.shadowOCREligible
                }
                if abs(lhs.score - rhs.score) > 0.0001 {
                    return lhs.score > rhs.score
                }
                return lhs.candidateID < rhs.candidateID
            }
            candidates.sort { lhs, rhs in
                detectorCandidateSort(lhs, rhs)
            }

            let candidatesByBubble = Dictionary(grouping: candidates) { $0.sourceBubbleID ?? -1 }
            let candidatesByBlock = Dictionary(grouping: candidates.flatMap { candidate in
                candidate.relatedCurrentBlockIndexes.map { (blockIndex: $0, candidate: candidate) }
            }) { $0.blockIndex }.mapValues { $0.map(\.candidate).sorted(by: detectorCandidateSort) }
            let modelFloorBlocks = Set(translationModelFloorComparisonReport?.noisyModelFloorBlocks ?? [])
            let renderLockedSet = Set((koharuRenderRegressionLockReport?.blockLocks ?? []).filter { $0.renderStatus == "renderLocked" }.map(\.blockIndex))
            let segmentWeakSet = Set(segmentMaskReport?.weakSegmentBlocks ?? [])
            let bubbleRiskSet = Set(bubbleMaskReport?.inconsistentBubbleAssignmentBlocks ?? [])

            let blockLedgers: [MangaKoharuNativeTextBoxDetectorLiteBlockLedger] = blocks.map { block in
                let blockCandidates = candidatesByBlock[block.index] ?? []
                let best = blockCandidates.first
                let bestRect = best.map { Self.rect(from: $0.bbox) }
                let blockRect = Self.rect(from: block.bbox)
                let coverage = bestRect.map { overlapRatio(blockRect, $0) } ?? 0
                let bestRelation = best?.relatedBlockRelations.first { $0.blockIndex == block.index }
                let coverageVerdict: String
                if best == nil {
                    coverageVerdict = "noNativeCandidate"
                } else if coverage >= 0.70 {
                    coverageVerdict = "candidateCoversCurrentBlock"
                } else if coverage >= 0.35 {
                    coverageVerdict = "candidatePartiallyCoversCurrentBlock"
                } else {
                    coverageVerdict = "candidateWeakCoverage"
                }
                let bubbleRisk = bubbleRiskSet.contains(block.index) ? "assignmentRisk" : "assignmentStable"
                let segmentVerdict = segmentWeakSet.contains(block.index) ? "segmentEvidenceWeak" : "segmentEvidenceAvailable"
                let ocrRisk = block.failureCategory == "ocrInputSuspect" ? "ocrInputSuspect" : "notPrimaryOCRRisk"
                let modelLimited = modelFloorBlocks.contains(block.index)
                let renderLocked = renderLockedSet.contains(block.index) || block.renderCollisionResolved
                let primary: String
                if best == nil || coverage < 0.35 {
                    primary = "needsNativeTextBoxArtifact"
                } else if bubbleRisk == "assignmentRisk" {
                    primary = "bubbleMaskProxyBoundary"
                } else if segmentVerdict == "segmentEvidenceWeak" {
                    primary = "segmentMaskProxyWeak"
                } else if ocrRisk == "ocrInputSuspect" {
                    primary = "ocrInputDamage"
                } else if modelLimited {
                    primary = "modelTranslationFloor"
                } else if renderLocked {
                    primary = "renderLocked"
                } else {
                    primary = "manualReviewOnly"
                }
                let nextAction: String
                switch primary {
                case "needsNativeTextBoxArtifact":
                    nextAction = "reviewDetectorLiteCandidateAndCollectRealTextBoxes"
                case "bubbleMaskProxyBoundary":
                    nextAction = "collectRealBubbleMaskArtifact"
                case "segmentMaskProxyWeak":
                    nextAction = "collectRealSegmentMaskArtifact"
                case "modelTranslationFloor":
                    nextAction = "keepModelFloorSeparate"
                case "renderLocked":
                    nextAction = "keepRenderLockReportOnly"
                default:
                    nextAction = "manualReviewOnly"
                }
                return MangaKoharuNativeTextBoxDetectorLiteBlockLedger(
                    blockIndex: block.index,
                    bbox: block.bbox,
                    bubbleID: block.bubbleID,
                    blockPassed: block.blockPassed,
                    failureCategory: block.failureCategory,
                    finalTextUsedForTranslation: block.finalTextUsedForTranslation,
                    ocrGroundTruthSimilarity: block.ocrGroundTruthSimilarity,
                    currentTextBoxSource: "VisionOCRFusedBlock",
                    candidateIDs: blockCandidates.map(\.candidateID),
                    bestCandidateID: best?.candidateID,
                    bestCandidateBBox: best?.bbox,
                    bestCandidateScore: best?.score,
                    bestCandidateCoverageRatio: bestRelation?.overlapRatio ?? coverage,
                    bestCandidateCenterContained: bestRelation?.centerContained ?? false,
                    bestCandidateSameBubble: bestRelation?.sameBubble ?? false,
                    bestCandidateVerdict: best?.candidateVerdict,
                    bestCandidateShadowOCREligible: best?.shadowOCREligible ?? false,
                    candidateCoverageVerdict: coverageVerdict,
                    directionHint: best?.directionHint ?? "unknown",
                    bubbleAssignmentRisk: bubbleRisk,
                    segmentEvidenceVerdict: segmentVerdict,
                    ocrInputRisk: ocrRisk,
                    modelFloorLimited: modelLimited,
                    renderLocked: renderLocked,
                    primaryBottleneck: primary,
                    nextAction: nextAction,
                    decisionSignals: [
                        signal("candidateCoverageVerdict", coverageVerdict, source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("bestCandidateVerdict", best?.candidateVerdict ?? "nil", source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("bestCandidateRelationReason", bestRelation?.relationReason ?? "nil", source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("bubbleAssignmentRisk", bubbleRisk, source: "bubbleMaskReport"),
                        signal("segmentEvidenceVerdict", segmentVerdict, source: "segmentMaskReport")
                    ],
                    evaluationSignals: [
                        signal("ocrGroundTruthSimilarity", block.ocrGroundTruthSimilarity.map(formatted) ?? "nil", source: "blocks.ocrGroundTruthSimilarity", decision: false, evaluation: true),
                        signal("groundTruthMatch", block.groundTruthMatch, source: "blocks.groundTruthMatch", decision: false, evaluation: true)
                    ],
                    groundTruthUsedForDecision: false,
                    wouldChangeMainFlow: false,
                    diagnosticOnly: true
                )
            }.sorted { $0.blockIndex < $1.blockIndex }

            let blocksByBubble = Dictionary(grouping: blocks.compactMap { block -> (Int, MangaOverlayProbeBlock)? in
                guard let bubbleID = block.bubbleID else { return nil }
                return (bubbleID, block)
            }) { $0.0 }.mapValues { $0.map(\.1).sorted { $0.index < $1.index } }

            let bubbleLedgers: [MangaKoharuNativeTextBoxDetectorLiteBubbleLedger] = bubbleGeometry.bubbles.sorted { $0.id < $1.id }.map { bubble in
                let bubbleCandidates = candidatesByBubble[bubble.id] ?? []
                let blockIndexes = blocksByBubble[bubble.id]?.map(\.index) ?? []
                let accepted = bubbleCandidates.filter { $0.candidateVerdict == "acceptedShadowOnly" }
                let directionBreakdown = countBy(bubbleCandidates.map(\.directionHint))
                let splitRisk = blockIndexes.count > 1 ? "sameBubbleMultiBlockSplitRisk" : "singleBlockOrNoBlock"
                let siblingRisk = blockIndexes.count > 1 ? "sameBubbleSiblingRisk" : "none"
                let needsRealBubbleMask = bubbleRiskSet.contains { blockIndexes.contains($0) } || blockIndexes.count > 1
                let coverageVerdict: String
                if accepted.isEmpty {
                    coverageVerdict = "noAcceptedNativeTextBox"
                } else if accepted.count >= max(1, blockIndexes.count) {
                    coverageVerdict = "nativeCandidateCoverageAvailable"
                } else {
                    coverageVerdict = "nativeCandidateCoveragePartial"
                }
                let action = needsRealBubbleMask ? "collectRealBubbleMaskArtifact" : "keepNativeDetectorLiteReportOnly"
                return MangaKoharuNativeTextBoxDetectorLiteBubbleLedger(
                    bubbleID: bubble.id,
                    bubbleBBox: bubble.bbox,
                    currentBlockIndexes: blockIndexes,
                    candidateIDs: bubbleCandidates.map(\.candidateID),
                    candidateCount: bubbleCandidates.count,
                    acceptedCandidateCount: accepted.count,
                    directionHintBreakdown: directionBreakdown,
                    splitRisk: splitRisk,
                    sameBubbleSiblingRisk: siblingRisk,
                    needsRealBubbleMask: needsRealBubbleMask,
                    nativeTextBoxCoverageVerdict: coverageVerdict,
                    nextAction: action,
                    decisionSignals: [
                        signal("candidateCount", String(bubbleCandidates.count), source: "koharuNativeTextBoxDetectorLiteReport"),
                        signal("currentBlockCount", String(blockIndexes.count), source: "blocks.bubbleID")
                    ],
                    evaluationSignals: [
                        signal("bubbleSource", bubble.source, source: "bubbleGeometry", decision: false, evaluation: true)
                    ]
                )
            }

            let acceptedCandidates = candidates.filter { $0.candidateVerdict == "acceptedShadowOnly" }
            let rejectedCandidates = candidates.filter { $0.candidateVerdict.hasPrefix("rejected") }
            let ocrBlocks = uniqueSorted(blockLedgers.filter { $0.ocrInputRisk == "ocrInputSuspect" }.map(\.blockIndex))
            let bubbleBlocks = uniqueSorted(blockLedgers.filter { $0.bubbleAssignmentRisk == "assignmentRisk" }.map(\.blockIndex))
            let segmentBlocks = uniqueSorted(blockLedgers.filter { $0.segmentEvidenceVerdict == "segmentEvidenceWeak" }.map(\.blockIndex))
            let modelBlocks = uniqueSorted(blockLedgers.filter(\.modelFloorLimited).map(\.blockIndex))
            let renderBlocks = uniqueSorted(blockLedgers.filter(\.renderLocked).map(\.blockIndex))
            let needsTextBoxBlocks = uniqueSorted(blockLedgers.filter { $0.primaryBottleneck == "needsNativeTextBoxArtifact" }.map(\.blockIndex))
            let manualBlocks = uniqueSorted(blockLedgers.filter { $0.nextAction == "manualReviewOnly" }.map(\.blockIndex))
            let allBlocks = blocks.map(\.index)

            func gate(
                _ id: String,
                _ name: String,
                _ scope: String,
                _ status: String,
                _ threshold: String,
                _ affected: [Int],
                _ failure: String,
                _ action: String,
                _ signals: [MangaKoharuNativeTextBoxDetectorLiteSignal]
            ) -> MangaKoharuNativeTextBoxDetectorLiteGate {
                MangaKoharuNativeTextBoxDetectorLiteGate(
                    gateID: id,
                    gateName: name,
                    scope: scope,
                    status: status,
                    threshold: threshold,
                    affectedBlocks: uniqueSorted(affected),
                    decisionSignals: signals,
                    failureMeans: failure,
                    recommendedAction: action,
                    groundTruthUsedForDecision: false
                )
            }

            let gateLedger = [
                gate("G-native-textbox-detector-lite-report-only", "Report only", "report", "passed", "wouldChangeMainFlow=false", [], "detector-lite mutates OCR, translation, renderer, blockPassed, currentBlockSource, or crop adoption", "revertBehavioralChange", [signal("wouldChangeMainFlow", "false", source: "koharuNativeTextBoxDetectorLiteReport")]),
                gate("G-native-textbox-detector-lite-no-ground-truth-decision", "No ground truth decision", "report", "passed", "groundTruthUsedForDecision=false", allBlocks, "ground truth influences candidate bbox, ranking, eligibility, gate, or next action", "moveGroundTruthToEvaluationSignalsOnly", [signal("groundTruthUsedForDecision", "false", source: "koharuNativeTextBoxDetectorLiteReport")]),
	                gate("G-native-textbox-detector-lite-pre-ocr-source", "Pre OCR source", "TextBoxes", "passed", "candidate source is SourceImage pixels plus geometry", allBlocks, "Vision OCR text, pre-crop plan, line plan, crop output, or ground truth is used as detector output", "keepCandidateGenerationPixelFirst", [signal("candidateSource", "SourceImagePixels+BubbleGeometry", source: "koharuNativeTextBoxDetectorLiteReport")]),
	                gate("G-native-textbox-detector-lite-candidate-pool-cap", "Candidate pool cap", "TextBoxes", "passed", "per bubble <=4 component clusters + 1 diagnostic union fallback", allBlocks, "detector-lite candidate pool grows without a fixed ci-fast budget cap", "keepPerBubbleCandidatePoolBounded", [signal("candidatePoolCap", "5", source: "koharuNativeTextBoxDetectorLiteReport")]),
	                gate("G-native-textbox-detector-lite-candidate-count", "Candidate count", "TextBoxes", candidates.isEmpty ? "warning" : "passed", "candidateCount>=1", allBlocks, "detector-lite produced no candidates", "inspectPixelThresholds", [signal("candidateCount", String(candidates.count), source: "koharuNativeTextBoxDetectorLiteReport")]),
                gate("G-native-textbox-detector-lite-block-ledger-count", "Block ledger count", "blocks", blockLedgers.count == blocks.count ? "passed" : "warning", "blockLedgerCount==totalBlocksDetected", allBlocks, "some final blocks lack detector-lite ledger rows", "restoreBlockLedgerCoverage", [signal("blockLedgerCount", String(blockLedgers.count), source: "koharuNativeTextBoxDetectorLiteReport")]),
                gate("G-native-textbox-detector-lite-bubble-ledger-count", "Bubble ledger count", "BubbleMask", bubbleLedgers.count == bubbleGeometry.bubbles.count ? "passed" : "warning", "bubbleLedgerCount==bubbleGeometry.bubbles.count", allBlocks, "some bubbles lack detector-lite ledger rows", "restoreBubbleLedgerCoverage", [signal("bubbleLedgerCount", String(bubbleLedgers.count), source: "koharuNativeTextBoxDetectorLiteReport")]),
                gate("G-native-textbox-detector-lite-proxy-boundary", "Proxy boundary", "TextBoxes", "passed", "proxyNotRealKoharuTextBoxes=true", allBlocks, "detector-lite is promoted as real Koharu TextBoxes", "keepProxyBoundaryOrCollectRealArtifact", [signal("proxyNotRealKoharuTextBoxes", "true", source: "koharuNativeTextBoxDetectorLiteReport")]),
                gate("G-native-textbox-detector-lite-ci-fast-ready", "CI fast ready", "ci-fast", "passed", "no OCR or LLM added", allBlocks, "detector-lite adds full-only or expensive OCR/LLM dependency to ci-fast", "keepCIFastReportOnly", [signal("shadowOCRExecuted", "false", source: "koharuNativeTextBoxDetectorLiteReport")])
            ]

            let detectorVerdict: String
            if candidates.isEmpty {
                detectorVerdict = "insufficientPixelEvidence"
            } else if acceptedCandidates.isEmpty {
                detectorVerdict = "shadowOnlyCandidatesReady"
            } else if !needsTextBoxBlocks.isEmpty {
                detectorVerdict = "nativeTextBoxCandidatesReady"
            } else if !bubbleBlocks.isEmpty {
                detectorVerdict = "blockedByProxyOnlyBubbleMask"
            } else if modelBlocks.count >= max(1, blocks.count / 2) {
                detectorVerdict = "modelFloorDominates"
            } else {
                detectorVerdict = "manualReviewOnly"
            }

            return MangaKoharuNativeTextBoxDetectorLiteReport(
                enabled: true,
                source: "AITRANSProbe",
                referencePipeline: "Koharu",
                referenceConcept: "TextBoxes.NativeDetectorLite.PreOCRArtifact",
                referenceWorkItemID: "WI-koharu-native-textbox-detector-lite",
                evaluatedBlockCount: blocks.count,
                evaluatedBubbleCount: bubbleGeometry.bubbles.count,
                candidateCount: candidates.count,
                acceptedCandidateCount: acceptedCandidates.count,
                rejectedCandidateCount: rejectedCandidates.count,
                shadowOCREligibleCandidateCount: candidates.filter(\.shadowOCREligible).count,
                blockLedgerCount: blockLedgers.count,
                bubbleLedgerCount: bubbleLedgers.count,
                gateCount: gateLedger.count,
                groundTruthUsedForDecision: false,
                groundTruthUsedForEvaluationOnly: true,
                wouldChangeMainFlow: false,
                diagnosticOnly: true,
                proxyNotRealKoharuTextBoxes: true,
                externalArtifactsRequiredForThisReport: false,
                detectorLiteVerdict: detectorVerdict,
                candidateSourceBreakdown: countBy(candidates.map(\.source)),
                directionHintBreakdown: countBy(candidates.map(\.directionHint)),
                candidateVerdictBreakdown: countBy(candidates.map(\.candidateVerdict)),
                blockRelationBreakdown: countBy(candidates.flatMap { $0.relatedBlockRelations.map(\.relationReason) }),
                rejectionReasonBreakdown: countBy(candidates.flatMap(\.rejectionReasons)),
                primaryBottleneckBreakdown: countBy(blockLedgers.map(\.primaryBottleneck)),
                nextActionBreakdown: countBy(blockLedgers.map(\.nextAction)),
                ocrInputSuspectBlocks: ocrBlocks,
                bubbleAssignmentRiskBlocks: bubbleBlocks,
                segmentEvidenceWeakBlocks: segmentBlocks,
                modelFloorLimitedBlocks: modelBlocks,
                renderLockedBlocks: renderBlocks,
                needsRealTextBoxesBlocks: needsTextBoxBlocks,
                manualReviewBlocks: manualBlocks,
                candidates: candidates,
                blockLedgers: blockLedgers,
                bubbleLedgers: bubbleLedgers,
                gateLedger: gateLedger,
                notes: [
	                    "koharuNativeTextBoxDetectorLiteReport is a shadow-only pre-OCR TextBoxes candidate layer.",
	                    "Each bubble may emit a bounded pre-OCR candidate pool: up to 4 component-cluster TextBoxes plus 1 diagnostic union fallback that is not shadow-OCR eligible.",
	                    "Candidate bboxes are generated from source image dark components, projection bands, density, bubble coverage, and glyph proxy overlap; Vision OCR text, ground truth, pre-crop plans, line plans, and crop OCR output are not used to generate or rank candidates.",
                    "The report does not execute OCR by default, does not add LLM calls, and does not change finalTextUsedForTranslation, blockPassed, failureCategory, overlay rendering, textRegionCropReport.adoptedCount, active artifacts, or configuration.currentBlockSource.",
                    "proxyNotRealKoharuTextBoxes=true: detector-lite candidates are not real Koharu TextBoxes and remain report-only until a separate promotion gate exists."
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
        koharuDistanceFieldSafeAreaReport: MangaKoharuDistanceFieldSafeAreaReport? = nil,
        koharuBubbleAdjacencySeamReport: MangaKoharuBubbleAdjacencySeamReport? = nil,
        koharuRenderSpriteFitPlannerReport: MangaKoharuRenderSpriteFitPlannerReport? = nil,
        koharuNativeTextBoxDetectorLiteReport: MangaKoharuNativeTextBoxDetectorLiteReport? = nil,
        koharuNativeTextBoxDetectorLiteShadowOCRReport: MangaKoharuNativeTextBoxDetectorLiteShadowOCRReport? = nil,
        koharuNativeTextBoxDetectorLiteRefinementReport: MangaKoharuNativeTextBoxDetectorLiteRefinementReport? = nil,
        koharuNativeTextBoxDetectorLiteClosedLoopReport: MangaKoharuNativeTextBoxDetectorLiteClosedLoopReport? = nil,
        koharuNativeBubbleMaskInstanceLiteReport: MangaKoharuNativeBubbleMaskInstanceLiteReport? = nil,
        koharuNativeSegmentMaskRefinementLiteReport: MangaKoharuNativeSegmentMaskRefinementLiteReport? = nil,
        koharuNativeArtifactBundleLiteReport: MangaKoharuNativeArtifactBundleLiteReport? = nil,
        koharuNativePromotionGateLiteReport: MangaKoharuNativePromotionGateLiteReport? = nil,
        koharuNativeArtifactContractDryRunReport: MangaKoharuNativeArtifactContractDryRunReport? = nil,
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
        let koharuDistanceFieldBlockLedgerByBlock = Dictionary(
            uniqueKeysWithValues: (koharuDistanceFieldSafeAreaReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let koharuBubbleSeamBlockLedgerByBlock = Dictionary(
            uniqueKeysWithValues: (koharuBubbleAdjacencySeamReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let renderSpriteFitByBlock = Dictionary(
            uniqueKeysWithValues: (koharuRenderSpriteFitPlannerReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeTextBoxDetectorLiteByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeTextBoxDetectorLiteReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeTextBoxDetectorLiteShadowOCRByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeTextBoxDetectorLiteShadowOCRReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeTextBoxDetectorLiteRefinementByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeTextBoxDetectorLiteRefinementReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeTextBoxDetectorLiteClosedLoopByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeTextBoxDetectorLiteClosedLoopReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeBubbleMaskInstanceLiteByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeBubbleMaskInstanceLiteReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
        )
        let nativeSegmentMaskRefinementLiteByBlock = Dictionary(
            uniqueKeysWithValues: (koharuNativeSegmentMaskRefinementLiteReport?.blockLedgers ?? []).map { ($0.blockIndex, $0) }
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
            let externalShadowDirection = externalShadowSummary?.selectedSourceDirection ?? "nil"
            let externalShadowOrientation = externalShadowSummary?.selectedOrientationCategory ?? "nil"
            let externalShadowLinePolygons = externalShadowSummary.map { String($0.selectedLinePolygonsPresent) } ?? "false"
            let externalShadowRotation = externalShadowSummary?.selectedRotationDegrees?.formatted(.number.precision(.fractionLength(2))) ?? "nil"
            let externalShadowOrientationNeeded = externalShadowSummary.map { String($0.orientationShadowPathNeeded) } ?? "false"
            let externalShadowOrientationExecuted = externalShadowSummary.map { String($0.orientationShadowPathExecuted) } ?? "false"
            let externalShadowOrientationVerdict = externalShadowSummary?.orientationReadinessVerdict ?? "nil"
            let externalShadowAttemptedRotations = externalShadowSummary?.orientationAttemptedRotations
                .map { $0.formatted(.number.precision(.fractionLength(1))) }
                .joined(separator: ",") ?? "nil"
            let externalShadowSelectedRotation = externalShadowSummary?.orientationSelectedRotation?.formatted(.number.precision(.fractionLength(1))) ?? "nil"
            let externalShadowLanguages = externalShadowSummary?.orientationRecognitionLanguages.joined(separator: ",") ?? "default"
            let externalShadowUnsupported = externalShadowSummary?.orientationUnsupportedReason ?? "none"
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
            let koharuDistanceFieldBlockLedger = koharuDistanceFieldBlockLedgerByBlock[block.index]
            let koharuBubbleSeamBlockLedger = koharuBubbleSeamBlockLedgerByBlock[block.index]
            let renderSpriteFit = renderSpriteFitByBlock[block.index]
            let nativeTextBoxDetectorLite = nativeTextBoxDetectorLiteByBlock[block.index]
            let nativeTextBoxDetectorLiteShadowOCR = nativeTextBoxDetectorLiteShadowOCRByBlock[block.index]
            let nativeTextBoxDetectorLiteRefinement = nativeTextBoxDetectorLiteRefinementByBlock[block.index]
            let nativeTextBoxDetectorLiteClosedLoop = nativeTextBoxDetectorLiteClosedLoopByBlock[block.index]
            let nativeBubbleMaskInstanceLite = nativeBubbleMaskInstanceLiteByBlock[block.index]
            let nativeSegmentMaskRefinementLite = nativeSegmentMaskRefinementLiteByBlock[block.index]
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
            externalTextBoxShadowOCR: executed=\(externalShadowSummary.map { String($0.ocrExecuted) } ?? "false") selectedTextBoxID=\(externalShadowSummary?.selectedTextBoxID ?? "none") candidateBBox=[\(externalShadowBBox)] ocrSucceeded=\(externalShadowSummary.map { String($0.ocrSucceeded) } ?? "false") ocrText=\(externalShadowText) qualityDelta=\(externalShadowDelta) wordPreservation=\(externalShadowPreservation) promotionVerdict=\(externalShadowSummary?.promotionVerdict ?? "skipped") blockers=\(externalShadowBlockers) sourceDirection=\(externalShadowDirection) orientation=\(externalShadowOrientation) linePolygonsPresent=\(externalShadowLinePolygons) rotationDegrees=\(externalShadowRotation) orientationShadowNeeded=\(externalShadowOrientationNeeded) orientationShadowExecuted=\(externalShadowOrientationExecuted) orientationAttemptedRotations=\(externalShadowAttemptedRotations) orientationSelectedRotation=\(externalShadowSelectedRotation) orientationLanguages=\(externalShadowLanguages) orientationUnsupported=\(externalShadowUnsupported) orientationVerdict=\(externalShadowOrientationVerdict)
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
            distanceFieldBlockLedger: block=\(koharuDistanceFieldBlockLedger.map { String($0.blockIndex) } ?? "nil") bubbleID=\(koharuDistanceFieldBlockLedger?.bubbleID.map(String.init) ?? "nil") currentIoU=\(koharuDistanceFieldBlockLedger?.currentVsDistanceSafeRectIoU?.formatted(.number.precision(.fractionLength(3))) ?? "nil") spriteCurrent=\(koharuDistanceFieldBlockLedger?.spriteContainedByCurrentSafeRect.map(String.init) ?? "nil") spriteDistance=\(koharuDistanceFieldBlockLedger?.spriteContainedByDistanceSafeRect.map(String.init) ?? "nil") verdict=\(koharuDistanceFieldBlockLedger?.safeRectComparisonVerdict ?? "nil") next=\(koharuDistanceFieldBlockLedger?.nextAction ?? "nil")
            bubbleSeamBlockLedger: block=\(koharuBubbleSeamBlockLedger.map { String($0.blockIndex) } ?? "nil") bubbleID=\(koharuBubbleSeamBlockLedger?.bubbleID.map(String.init) ?? "nil") pairs=[\(koharuBubbleSeamBlockLedger?.relatedPairIDs.joined(separator: ",") ?? "nil")] seams=[\(koharuBubbleSeamBlockLedger?.relatedSeamCandidateIDs.joined(separator: ",") ?? "nil")] risk=\(koharuBubbleSeamBlockLedger?.blockSeamRisk ?? "nil") verdict=\(koharuBubbleSeamBlockLedger?.blockSeamVerdict ?? "nil") next=\(koharuBubbleSeamBlockLedger?.nextAction ?? "nil")
            renderSpriteFit: block=\(renderSpriteFit.map { String($0.blockIndex) } ?? "nil") source=\(renderSpriteFit?.textSourceForRender ?? "nil") chars=\(renderSpriteFit.map { String($0.renderTextCharacterCount) } ?? "nil") cjk=\(renderSpriteFit.map { String($0.renderTextCJKCount) } ?? "nil") latin=\(renderSpriteFit.map { String($0.renderTextLatinCount) } ?? "nil") rectSource=\(renderSpriteFit?.selectedReportOnlyFitRectSource ?? "nil") fontBudget=\(renderSpriteFit?.fontBudgetVerdict ?? "nil") fit=\(renderSpriteFit?.fitVerdict ?? "nil") failureOverlayFit=\(renderSpriteFit?.failureOverlayFitVerdict ?? "nil") seams=[\(renderSpriteFit?.relatedSeamCandidateIDs.joined(separator: ",") ?? "nil")] siblings=[\(renderSpriteFit?.sameBubbleSiblingBlockIndexes.map(String.init).joined(separator: ",") ?? "nil")] next=\(renderSpriteFit?.nextAction ?? "nil")
            nativeTextBoxDetectorLiteBlockLedger: block=\(nativeTextBoxDetectorLite.map { String($0.blockIndex) } ?? "nil") bubbleID=\(nativeTextBoxDetectorLite?.bubbleID.map(String.init) ?? "nil") candidates=[\(nativeTextBoxDetectorLite?.candidateIDs.joined(separator: ",") ?? "nil")] best=\(nativeTextBoxDetectorLite?.bestCandidateID ?? "nil") score=\(nativeTextBoxDetectorLite?.bestCandidateScore?.formatted(.number.precision(.fractionLength(3))) ?? "nil") relationOverlap=\(nativeTextBoxDetectorLite?.bestCandidateCoverageRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil") relationCenter=\(nativeTextBoxDetectorLite.map { String($0.bestCandidateCenterContained) } ?? "nil") relationSameBubble=\(nativeTextBoxDetectorLite.map { String($0.bestCandidateSameBubble) } ?? "nil") bestVerdict=\(nativeTextBoxDetectorLite?.bestCandidateVerdict ?? "nil") bestShadow=\(nativeTextBoxDetectorLite.map { String($0.bestCandidateShadowOCREligible) } ?? "nil") coverage=\(nativeTextBoxDetectorLite?.candidateCoverageVerdict ?? "nil") direction=\(nativeTextBoxDetectorLite?.directionHint ?? "nil") bottleneck=\(nativeTextBoxDetectorLite?.primaryBottleneck ?? "nil") next=\(nativeTextBoxDetectorLite?.nextAction ?? "nil")
            nativeTextBoxDetectorLiteShadowOCRBlockLedger: block=\(nativeTextBoxDetectorLiteShadowOCR.map { String($0.blockIndex) } ?? "nil") bubbleID=\(nativeTextBoxDetectorLiteShadowOCR?.bubbleID.map(String.init) ?? "nil") selected=\(nativeTextBoxDetectorLiteShadowOCR?.selectedCandidateID ?? "nil") outcome=\(nativeTextBoxDetectorLiteShadowOCR?.shadowOutcome ?? "nil") shadowText=\(nativeTextBoxDetectorLiteShadowOCR?.shadowOCRNormalizedText?.replacing("\n", with: " / ") ?? "nil") qualityDelta=\(nativeTextBoxDetectorLiteShadowOCR?.qualityDeltaVsCurrent?.formatted(.number.precision(.fractionLength(3))) ?? "nil") similarityDelta=\(nativeTextBoxDetectorLiteShadowOCR?.ocrSimilarityDeltaForEvaluation?.formatted(.number.precision(.fractionLength(3))) ?? "nil") bottleneck=\(nativeTextBoxDetectorLiteShadowOCR?.primaryBottleneck ?? "nil") next=\(nativeTextBoxDetectorLiteShadowOCR?.nextAction ?? "nil")
            nativeTextBoxDetectorLiteRefinementBlockLedger: block=\(nativeTextBoxDetectorLiteRefinement.map { String($0.blockIndex) } ?? "nil") bubbleID=\(nativeTextBoxDetectorLiteRefinement?.bubbleID.map(String.init) ?? "nil") target=\(nativeTextBoxDetectorLiteRefinement?.targetReason ?? "nil") base=\(nativeTextBoxDetectorLiteRefinement?.baseCandidateID ?? "nil") refined=[\(nativeTextBoxDetectorLiteRefinement?.refinedBBox?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil")] strategy=\(nativeTextBoxDetectorLiteRefinement?.refinementStrategy ?? "nil") outcome=\(nativeTextBoxDetectorLiteRefinement?.refinementOutcome ?? "nil") refinedText=\(nativeTextBoxDetectorLiteRefinement?.refinedOCRNormalizedText?.replacing("\n", with: " / ") ?? "nil") qualityDeltaCurrent=\(nativeTextBoxDetectorLiteRefinement?.qualityDeltaVsCurrent?.formatted(.number.precision(.fractionLength(3))) ?? "nil") qualityDeltaDetector=\(nativeTextBoxDetectorLiteRefinement?.qualityDeltaVsDetectorLiteShadow?.formatted(.number.precision(.fractionLength(3))) ?? "nil") similarityDelta=\(nativeTextBoxDetectorLiteRefinement?.ocrSimilarityDeltaForEvaluation?.formatted(.number.precision(.fractionLength(3))) ?? "nil") bottleneck=\(nativeTextBoxDetectorLiteRefinement?.primaryBottleneck ?? "nil") next=\(nativeTextBoxDetectorLiteRefinement?.nextAction ?? "nil")
            nativeTextBoxDetectorLiteClosedLoopBlockLedger: block=\(nativeTextBoxDetectorLiteClosedLoop.map { String($0.blockIndex) } ?? "nil") bubbleID=\(nativeTextBoxDetectorLiteClosedLoop?.bubbleID.map(String.init) ?? "nil") failure=\(nativeTextBoxDetectorLiteClosedLoop?.failureCategory ?? "nil") shadow=\(nativeTextBoxDetectorLiteClosedLoop?.detectorLiteShadowOutcome ?? "nil") refinement=\(nativeTextBoxDetectorLiteClosedLoop?.refinementOutcome ?? "nil") best=\(nativeTextBoxDetectorLiteClosedLoop?.bestReportOnlyCandidateID ?? "nil") delta=\(nativeTextBoxDetectorLiteClosedLoop?.qualityDeltaVsCurrent?.formatted(.number.precision(.fractionLength(3))) ?? "nil") bubble=\(nativeTextBoxDetectorLiteClosedLoop?.bubbleAssignmentStatus ?? "nil") segment=\(nativeTextBoxDetectorLiteClosedLoop?.segmentGlyphEvidenceStatus ?? "nil") translationRoute=\(nativeTextBoxDetectorLiteClosedLoop?.translationFailureRoute ?? "nil") render=\(nativeTextBoxDetectorLiteClosedLoop?.renderLockStatus ?? "nil") bottleneck=\(nativeTextBoxDetectorLiteClosedLoop?.primaryBottleneck ?? "nil") route=\(nativeTextBoxDetectorLiteClosedLoop?.closedLoopRoute ?? "nil") next=\(nativeTextBoxDetectorLiteClosedLoop?.nextAction ?? "nil")
            nativeBubbleMaskInstanceLiteBlockLedger: block=\(nativeBubbleMaskInstanceLite.map { String($0.blockIndex) } ?? "nil") currentBubbleID=\(nativeBubbleMaskInstanceLite?.currentBubbleID.map(String.init) ?? "nil") majorityID=\(nativeBubbleMaskInstanceLite?.instanceLiteMajorityID.map(String.init) ?? "nil") majorityCoverage=\(nativeBubbleMaskInstanceLite?.instanceLiteMajorityCoverage.formatted(.number.precision(.fractionLength(3))) ?? "nil") agreement=\(nativeBubbleMaskInstanceLite?.assignmentAgreement ?? "nil") conflict=\(nativeBubbleMaskInstanceLite?.assignmentConflictReason ?? "nil") safeRect=[\(nativeBubbleMaskInstanceLite?.instanceLiteSafeRect?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil")] scopedSafeRect=[\(nativeBubbleMaskInstanceLite?.instanceLiteBlockScopedSafeRect?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil")] safeRectPolicy=\(nativeBubbleMaskInstanceLite?.instanceLiteSafeRectPolicy ?? "nil") distanceFieldSource=\(nativeBubbleMaskInstanceLite?.distanceFieldSafeRectSource ?? "nil") spriteContained=\(nativeBubbleMaskInstanceLite.map { String($0.spriteContainedByInstanceLiteMask) } ?? "nil") spriteScopedContainmentRatio=\(nativeBubbleMaskInstanceLite?.spriteBlockScopedSafeRectContainmentRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil") spriteContainedByScopedSafeRect=\(nativeBubbleMaskInstanceLite.map { String($0.spriteContainedByBlockScopedSafeRect) } ?? "nil") spriteContainmentPolicy=\(nativeBubbleMaskInstanceLite?.spriteContainmentPolicy ?? "nil") siblingSpriteOverlap=\(nativeBubbleMaskInstanceLite.map { String($0.sameInstanceRenderSpriteOverlapCount) } ?? "nil") siblingSpritePolicy=\(nativeBubbleMaskInstanceLite?.spriteSiblingCollisionPolicy ?? "nil") sibling=\(nativeBubbleMaskInstanceLite?.siblingPartitionStatus ?? "nil") split=\(nativeBubbleMaskInstanceLite?.splitRisk ?? "nil") adjacency=\(nativeBubbleMaskInstanceLite?.adjacencyRisk ?? "nil") segment=\(nativeBubbleMaskInstanceLite?.segmentGlyphEvidenceStatus ?? "nil") translationRoute=\(nativeBubbleMaskInstanceLite?.translationFailureRoute ?? "nil") detectorRoute=\(nativeBubbleMaskInstanceLite?.detectorLiteClosedLoopRoute ?? "nil") render=\(nativeBubbleMaskInstanceLite?.renderLockStatus ?? "nil") bottleneck=\(nativeBubbleMaskInstanceLite?.primaryBottleneck ?? "nil") next=\(nativeBubbleMaskInstanceLite?.nextAction ?? "nil")
            nativeSegmentMaskRefinementLiteBlockLedger: block=\(nativeSegmentMaskRefinementLite.map { String($0.blockIndex) } ?? "nil") selected=\(nativeSegmentMaskRefinementLite?.selectedCandidateID ?? "nil") pixels=\(nativeSegmentMaskRefinementLite.map { String($0.afterBubbleClampPixelCount) } ?? "nil") textBoxCoverage=\(nativeSegmentMaskRefinementLite?.textboxCoverage.formatted(.number.precision(.fractionLength(3))) ?? "nil") bubbleCoverage=\(nativeSegmentMaskRefinementLite?.bubbleCoverage.formatted(.number.precision(.fractionLength(3))) ?? "nil") textBoxContainment=\(nativeSegmentMaskRefinementLite?.maskContainedByTextBoxRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil") bubbleContainment=\(nativeSegmentMaskRefinementLite?.maskContainedByBubbleRatio.formatted(.number.precision(.fractionLength(3))) ?? "nil") majorityAgreement=\(nativeSegmentMaskRefinementLite?.maskMajorityAgreement ?? "nil") glyphOverlap=\(nativeSegmentMaskRefinementLite?.existingGlyphOverlap.formatted(.number.precision(.fractionLength(3))) ?? "nil") segmentAgreement=\(nativeSegmentMaskRefinementLite?.segmentProxyAgreement.formatted(.number.precision(.fractionLength(3))) ?? "nil") containedTextBox=\(nativeSegmentMaskRefinementLite.map { String($0.maskContainedByTextBox) } ?? "nil") containedBubble=\(nativeSegmentMaskRefinementLite.map { String($0.maskContainedByBubble) } ?? "nil") clearText=\(nativeSegmentMaskRefinementLite.map { String($0.wouldBeUsableForClearTextMask) } ?? "nil") ocrCrop=\(nativeSegmentMaskRefinementLite.map { String($0.wouldBeUsableForOCRCropConstraint) } ?? "nil") render=\(nativeSegmentMaskRefinementLite.map { String($0.wouldBeUsableForRenderContainment) } ?? "nil") bottleneck=\(nativeSegmentMaskRefinementLite?.primaryBottleneck ?? "nil") next=\(nativeSegmentMaskRefinementLite?.nextAction ?? "nil")
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
        let convergenceBundleLinkageWorkItem = koharuArtifactConvergenceReport?.workItemLedger.first {
            $0.workItemID == "WI-koharu-native-artifact-bundle-lite-textbox-segment-linkage"
        }
        let convergencePromotionLinkageWorkItem = koharuArtifactConvergenceReport?.workItemLedger.first {
            $0.workItemID == "WI-koharu-native-promotion-gate-lite-textbox-segment-linkage"
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
        let distanceFieldBubbleLedgerSummary = (koharuDistanceFieldSafeAreaReport?.bubbleLedgers ?? [])
            .map { "distanceFieldBubbleLedger: bubbleID=\($0.bubbleID) maxDistance=\($0.maxDistancePx.formatted(.number.precision(.fractionLength(2)))) safePixels=\($0.safePixelCount) maxRect=[\($0.maximumSafeRect?.map { String(Int($0.rounded())) }.joined(separator: ",") ?? "nil")] verdict=\($0.safePixelVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let distanceFieldSiblingLedgerSummary = (koharuDistanceFieldSafeAreaReport?.siblingLedgers ?? [])
            .map { "distanceFieldSiblingLedger: group=\($0.siblingGroupID) bubbleID=\($0.bubbleID) blocks=[\($0.blockIndexes.map(String.init).joined(separator: ","))] verdict=\($0.siblingDistanceVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let bubbleAdjacencyPairSummary = (koharuBubbleAdjacencySeamReport?.pairLedgers ?? [])
            .map { "bubbleAdjacencyPair: pair=\($0.pairID) bubbles=\($0.bubbleAID)-\($0.bubbleBID) gap=\($0.bboxGapPx.formatted(.number.precision(.fractionLength(2)))) overlap=\($0.bboxOverlapArea.formatted(.number.precision(.fractionLength(2)))) verdict=\($0.pairVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let bubbleSeamCandidateSummary = (koharuBubbleAdjacencySeamReport?.seamCandidateLedgers ?? [])
            .map { "bubbleSeamCandidate: id=\($0.seamCandidateID) parent=\($0.parentBubbleID.map(String.init) ?? "nil") orientation=\($0.seamOrientation) blocks=[\($0.blockIndexes.map(String.init).joined(separator: ","))] score=\($0.seamScore.formatted(.number.precision(.fractionLength(3)))) verdict=\($0.seamCandidateVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let renderSpriteLayoutCandidateSummary = (koharuRenderSpriteFitPlannerReport?.layoutCandidateLedgers ?? [])
            .prefix(40)
            .map { "renderSpriteLayoutCandidate: id=\($0.candidateID) block=\($0.blockIndex) source=\($0.candidateSource) area=\($0.candidateArea.formatted(.number.precision(.fractionLength(1)))) contained=\($0.spriteContained.map(String.init) ?? "nil") verdict=\($0.candidateVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let renderSpriteSiblingFitSummary = (koharuRenderSpriteFitPlannerReport?.siblingLedgers ?? [])
            .map { "renderSpriteSiblingFit: group=\($0.siblingGroupID) bubbleID=\($0.bubbleID) blocks=[\($0.blockIndexes.map(String.init).joined(separator: ","))] currentOverlap=\($0.currentSafeRectMaxOverlapRatio.formatted(.number.precision(.fractionLength(3)))) distanceOverlap=\($0.distanceFieldSafeRectMaxOverlapRatio.formatted(.number.precision(.fractionLength(3)))) verdict=\($0.sameBubbleSiblingPartitionVerdict) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativeTextBoxDetectorLiteShadowOCRCandidateSummary = (koharuNativeTextBoxDetectorLiteShadowOCRReport?.candidates ?? [])
            .prefix(32)
            .map { "nativeTextBoxDetectorLiteShadowOCRCandidate: id=\($0.candidateID) source=\($0.sourceCandidateID) block=\($0.relatedBlockIndex) bubble=\($0.sourceBubbleID.map(String.init) ?? "nil") bbox=[\($0.bbox.map { String(Int($0.rounded())) }.joined(separator: ","))] dir=\($0.directionHint) rotation=\($0.rotationApplied.formatted(.number.precision(.fractionLength(0)))) succeeded=\($0.ocrSucceeded) outcome=\($0.outcome) qualityDelta=\($0.qualityDeltaVsCurrent.formatted(.number.precision(.fractionLength(3)))) wordPreservation=\($0.wordPreservationVsCurrent.formatted(.number.precision(.fractionLength(3)))) text=\($0.ocrNormalizedText.replacing("\n", with: " / "))" }
            .joined(separator: "\n")
        let nativeTextBoxDetectorLiteShadowOCRRotationSummary = Dictionary(
            grouping: koharuNativeTextBoxDetectorLiteShadowOCRReport?.candidates ?? [],
            by: { $0.rotationApplied.formatted(.number.precision(.fractionLength(0))) }
        )
            .mapValues(\.count)
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
        let nativeTextBoxDetectorLiteRefinementCandidateSummary = (koharuNativeTextBoxDetectorLiteRefinementReport?.candidates ?? [])
            .prefix(24)
            .map { "nativeTextBoxDetectorLiteRefinementCandidate: id=\($0.candidateID) source=\($0.source) block=\($0.blockIndex) bubble=\($0.sourceBubbleID.map(String.init) ?? "nil") base=[\($0.baseBBox.map { String(Int($0.rounded())) }.joined(separator: ","))] refined=[\($0.refinedBBox.map { String(Int($0.rounded())) }.joined(separator: ","))] strategy=\($0.refinementStrategy) target=\($0.targetReason) succeeded=\($0.ocrSucceeded) outcome=\($0.outcome) qualityDeltaCurrent=\($0.qualityDeltaVsCurrent.formatted(.number.precision(.fractionLength(3)))) qualityDeltaDetector=\($0.qualityDeltaVsDetectorLiteShadow?.formatted(.number.precision(.fractionLength(3))) ?? "nil") text=\($0.ocrNormalizedText.replacing("\n", with: " / "))" }
            .joined(separator: "\n")
        let nativeTextBoxDetectorLiteClosedLoopFamilySummary = (koharuNativeTextBoxDetectorLiteClosedLoopReport?.candidateFamilyLedgers ?? [])
            .prefix(24)
            .map { "nativeTextBoxDetectorLiteCandidateFamily: family=\($0.familyID) block=\($0.blockIndex) bubble=\($0.bubbleID.map(String.init) ?? "nil") best=\($0.bestReportOnlyCandidateID ?? "nil") source=\($0.bestReportOnlyCandidateSource ?? "nil") delta=\($0.qualityDeltaVsCurrent?.formatted(.number.precision(.fractionLength(3))) ?? "nil") evalSimilarityDelta=\($0.groundTruthSimilarityDeltaForEvaluation?.formatted(.number.precision(.fractionLength(3))) ?? "nil") verdict=\($0.candidateFamilyVerdict) whyNotPromoted=\($0.whyNotPromoted.joined(separator: " | "))" }
            .joined(separator: "\n")
        let nativeBubbleMaskInstanceSummary = (koharuNativeBubbleMaskInstanceLiteReport?.instances ?? [])
            .prefix(24)
            .map { "nativeBubbleMaskInstanceLiteInstance: id=\($0.instanceID) mask=\($0.maskValue) bubble=\($0.matchedExistingBubbleID.map(String.init) ?? "nil") bbox=[\($0.bbox.map { String(Int($0.rounded())) }.joined(separator: ","))] pixels=\($0.pixelCount) fill=\($0.fillRatio.formatted(.number.precision(.fractionLength(3)))) confidence=\($0.interiorConfidence.formatted(.number.precision(.fractionLength(3)))) source=\($0.pixelMaskSource) verdict=\($0.instanceQualityVerdict) related=\($0.relatedBlockIndexes.map(String.init).joined(separator: ",")) siblings=\($0.sameBubbleSiblingBlockIndexes.map(String.init).joined(separator: ",")) adjacent=\($0.adjacentInstanceIDs.map(String.init).joined(separator: ",")) rejections=\($0.rejectionReasons.joined(separator: " | "))" }
            .joined(separator: "\n")
        let nativeBubbleMaskSiblingSummary = (koharuNativeBubbleMaskInstanceLiteReport?.siblingLedgers ?? [])
            .prefix(24)
            .map { "nativeBubbleMaskInstanceLiteSiblingLedger: instance=\($0.instanceID.map(String.init) ?? "nil") blocks=\($0.blockIndexes.map(String.init).joined(separator: ",")) currentOverlap=\($0.currentSafeRectOverlapCount) instanceOverlap=\($0.instanceLiteSafeRectOverlapCount) blockScopedOverlap=\($0.blockScopedSafeRectOverlapCount) renderSpriteOverlap=\($0.renderSpriteOverlapCount) policy=\($0.sameBubbleSafeRectPolicy) spritePolicy=\($0.sameBubbleSpriteCollisionPolicy) seam=\($0.seamCandidateRelated) status=\($0.siblingPartitionStatus) needsRealBubbleMask=\($0.needsRealBubbleMask) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativeBubbleMaskAdjacencySummary = (koharuNativeBubbleMaskInstanceLiteReport?.adjacencyLedgers ?? [])
            .prefix(24)
            .map { "nativeBubbleMaskInstanceLiteAdjacencyLedger: pair=\($0.instanceAID)-\($0.instanceBID) bboxGap=\($0.bboxGap.formatted(.number.precision(.fractionLength(2)))) maskGap=\($0.maskGap.formatted(.number.precision(.fractionLength(2)))) status=\($0.adjacencyStatus) seamRisk=\($0.seamRisk) blocks=\($0.affectedBlocks.map(String.init).joined(separator: ",")) splitCandidates=\($0.relatedSplitCandidateIDs.map(String.init).joined(separator: ",")) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativeSegmentMaskRefinementCandidateSummary = (koharuNativeSegmentMaskRefinementLiteReport?.candidateLedgers ?? [])
            .prefix(24)
            .map { "nativeSegmentMaskRefinementLiteCandidate: id=\($0.candidateID) block=\($0.blockIndex) source=\($0.source) textBox=\($0.sourceTextBoxCandidateID ?? "nil") textBoxVerdict=\($0.sourceTextBoxCandidateVerdict ?? "nil") textBoxLink=\($0.sourceTextBoxLinkVerdict) textBoxOverlap=\($0.sourceTextBoxBlockOverlapRatio.formatted(.number.precision(.fractionLength(3)))) textBoxSameBubble=\($0.sourceTextBoxSameBubble) textBoxAccepted=\($0.sourceTextBoxAcceptedForSegmentMask) bubble=\($0.sourceBubbleID.map(String.init) ?? "nil") instance=\($0.sourceInstanceLiteID.map(String.init) ?? "nil") bbox=[\($0.bbox.map { String(Int($0.rounded())) }.joined(separator: ","))] expanded=[\($0.expandedTextBoxRect.map { String(Int($0.rounded())) }.joined(separator: ","))] pixels=\($0.afterBubbleClampPixelCount) components=\($0.connectedComponentCount) textBoxCoverage=\($0.textboxCoverage.formatted(.number.precision(.fractionLength(3)))) bubbleCoverage=\($0.bubbleCoverage.formatted(.number.precision(.fractionLength(3)))) textBoxContainment=\($0.maskContainedByTextBoxRatio.formatted(.number.precision(.fractionLength(3)))) bubbleContainment=\($0.maskContainedByBubbleRatio.formatted(.number.precision(.fractionLength(3)))) majorityAgreement=\($0.maskMajorityAgreement) majorityCoverage=\($0.maskMajorityCoverage.formatted(.number.precision(.fractionLength(3)))) glyphOverlap=\($0.existingGlyphOverlap.formatted(.number.precision(.fractionLength(3)))) segmentAgreement=\($0.segmentProxyAgreement.formatted(.number.precision(.fractionLength(3)))) verdict=\($0.candidateVerdict) rejections=\($0.rejectionReasons.joined(separator: " | "))" }
            .joined(separator: "\n")
        let nativeSegmentMaskRefinementSiblingSummary = (koharuNativeSegmentMaskRefinementLiteReport?.siblingLedgers ?? [])
            .prefix(24)
            .map { "nativeSegmentMaskRefinementLiteSiblingLedger: bubble=\($0.bubbleID.map(String.init) ?? "nil") instance=\($0.instanceLiteID.map(String.init) ?? "nil") blocks=[\($0.blockIndexes.map(String.init).joined(separator: ","))] overlaps=\($0.maskBBoxOverlapCount) pixels=\($0.pixelOverlapEstimate) risk=\($0.sameBubbleSiblingRisk) seam=\($0.seamRisk) needsRealSegmentMask=\($0.needsRealSegmentMask) needsRealBubbleMask=\($0.needsRealBubbleMask) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativeArtifactBundleLiteBlockSummary = (koharuNativeArtifactBundleLiteReport?.blockLedgers ?? [])
            .prefix(32)
            .map { ledger in
                "nativeArtifactBundleLiteBlockLedger: block=\(ledger.blockIndex) bubble=\(ledger.bubbleID.map(String.init) ?? "nil") textBox=\(ledger.selectedTextBoxLite.componentID):\(ledger.selectedTextBoxLite.componentSource):\(ledger.selectedTextBoxLite.readinessStatus) bubbleComponent=\(ledger.selectedBubbleInstanceLite.componentID):\(ledger.selectedBubbleInstanceLite.componentSource):\(ledger.selectedBubbleInstanceLite.readinessStatus) segment=\(ledger.selectedSegmentMaskLite.componentID):\(ledger.selectedSegmentMaskLite.componentSource):\(ledger.selectedSegmentMaskLite.readinessStatus) textBoxSegmentLink=\(ledger.selectedTextBoxSegmentLinkVerdict):\(ledger.textBoxSegmentLinkageStatus):risk=\(ledger.textBoxSegmentLinkageRisk) consistency=\(ledger.artifactConsistencyVerdict) primary=\(ledger.primaryBlockingArtifact) next=\(ledger.nextAction)"
            }
            .joined(separator: "\n")
        let nativeArtifactBundleLiteEdgeSummary = (koharuNativeArtifactBundleLiteReport?.consistencyEdges ?? [])
            .prefix(48)
            .map { "nativeArtifactBundleLiteConsistencyEdge: id=\($0.edgeID) type=\($0.edgeType) status=\($0.status) severity=\($0.severity) blocks=[\($0.affectedBlocks.map(String.init).joined(separator: ","))] evidence=\($0.evidence.joined(separator: " | "))" }
            .joined(separator: "\n")
        let nativeArtifactBundleLiteWorkItemSummary = (koharuNativeArtifactBundleLiteReport?.workItems ?? [])
            .map { "nativeArtifactBundleLiteWorkItem: id=\($0.workItemID) target=\($0.targetArtifact) status=\($0.status) priority=\($0.priority) blocks=[\($0.affectedBlocks.map(String.init).joined(separator: ","))] next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativePromotionBlockSummary = (koharuNativePromotionGateLiteReport?.blockLedgers ?? [])
            .prefix(32)
            .map {
                "nativePromotionBlockLedger: block=\($0.blockIndex) bubble=\($0.bubbleID.map(String.init) ?? "nil") eligibility=\($0.promotionEligibility) textBoxes=\($0.textBoxesPromotionStatus) bubbleMask=\($0.bubbleMaskPromotionStatus) segmentMask=\($0.segmentMaskPromotionStatus) textBoxSegmentLink=\($0.textBoxSegmentLinkVerdict):\($0.textBoxSegmentLinkagePromotionStatus) ocr=\($0.ocrTextPromotionStatus) translation=\($0.translationPromotionStatus) render=\($0.renderPromotionStatus) primary=\($0.primaryBlockingArtifact) bottleneck=\($0.probeBottleneckCategory) next=\($0.nextAction) mustNotPromote=\($0.mustNotPromoteReasons.joined(separator: " | "))"
            }
            .joined(separator: "\n")
        let nativePromotionStageGateSummary = (koharuNativePromotionGateLiteReport?.stageGates ?? [])
            .map { "nativePromotionStageGate: stage=\($0.stageName) artifact=\($0.referenceKoharuArtifact) readiness=\($0.stageReadiness) eligible=[\($0.eligibleBlocks.map(String.init).joined(separator: ","))] blocked=[\($0.blockedBlocks.map(String.init).joined(separator: ","))] stop=[\($0.stopBlocks.map(String.init).joined(separator: ","))] missing=\($0.missingEvidence.joined(separator: " | "))" }
            .joined(separator: "\n")
        let nativePromotionPreviewSummary = (koharuNativePromotionGateLiteReport?.candidateExportPreviews ?? [])
            .prefix(32)
            .map { "nativeCandidateExportPreview: id=\($0.previewID) block=\($0.blockIndex) stage=\($0.targetArtifactStage) source=\($0.candidateSource) sourceReport=\($0.sourceReport) canExport=\($0.canBeExportedNow) wouldCreateActiveArtifact=\($0.wouldCreateActiveArtifact) reason=\($0.reasonNotExported)" }
            .joined(separator: "\n")
        let nativePromotionWorkItemSummary = (koharuNativePromotionGateLiteReport?.workItems ?? [])
            .map { "nativePromotionWorkItem: id=\($0.workItemID) target=\($0.targetArtifact) status=\($0.status) priority=\($0.priority) blocks=[\($0.affectedBlocks.map(String.init).joined(separator: ","))] next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativeArtifactContractDryRunFileSummary = (koharuNativeArtifactContractDryRunReport?.requiredFiles ?? [])
            .map { "nativeArtifactContractDryRunRequiredFile: path=\($0.path) kind=\($0.artifactKind) activeFileFound=\($0.activeFileFound) dryRunPreviews=\($0.dryRunPreviewCount) status=\($0.status) missingFields=\($0.missingRequiredFields.joined(separator: " | ")) forbiddenSourceCount=\($0.forbiddenSourceCount) next=\($0.nextAction)" }
            .joined(separator: "\n")
        let nativeArtifactContractDryRunPreviewSummary = (koharuNativeArtifactContractDryRunReport?.previews ?? [])
            .prefix(32)
            .map { "nativeArtifactContractDryRunPreview: id=\($0.previewID) block=\($0.blockIndex) stage=\($0.targetArtifactStage) source=\($0.candidateSource) destination=\($0.destinationPath) contractReady=\($0.canSatisfyContractDryRun) activeExportAllowed=\($0.activeExportAllowed) missing=\($0.missingRequiredFields.joined(separator: " | ")) forbidden=\($0.forbiddenSourceReasons.joined(separator: " | "))" }
            .joined(separator: "\n")
        let nativeArtifactContractDryRunGateSummary = (koharuNativeArtifactContractDryRunReport?.gateLedger ?? [])
            .map { "nativeArtifactContractDryRunGate: id=\($0.gateID) status=\($0.status) scope=\($0.scope) affected=[\($0.affectedBlocks.map(String.init).joined(separator: ","))] action=\($0.recommendedAction)" }
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
        koharuDistanceFieldSafeAreaReport: enabled=\(koharuDistanceFieldSafeAreaReport.map { String($0.enabled) } ?? "nil") bubbles=\(koharuDistanceFieldSafeAreaReport.map { String($0.bubbleLedgerCount) } ?? "nil") blocks=\(koharuDistanceFieldSafeAreaReport.map { String($0.blockLedgerCount) } ?? "nil") siblings=\(koharuDistanceFieldSafeAreaReport.map { String($0.siblingLedgerCount) } ?? "nil") gates=\(koharuDistanceFieldSafeAreaReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuDistanceFieldSafeAreaReport?.distanceFieldVerdict ?? "nil")
        distanceFieldSafePixel=\(koharuDistanceFieldSafeAreaReport?.safePixelVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        distanceFieldSafeRectComparison=\(koharuDistanceFieldSafeAreaReport?.safeRectComparisonBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        distanceFieldSpriteContainment=\(koharuDistanceFieldSafeAreaReport?.spriteContainmentBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        distanceFieldNextAction=\(koharuDistanceFieldSafeAreaReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(distanceFieldBubbleLedgerSummary.isEmpty ? "distanceFieldBubbleLedger: nil" : distanceFieldBubbleLedgerSummary)
        \(distanceFieldSiblingLedgerSummary.isEmpty ? "distanceFieldSiblingLedger: nil" : distanceFieldSiblingLedgerSummary)
        koharuBubbleAdjacencySeamReport: enabled=\(koharuBubbleAdjacencySeamReport.map { String($0.enabled) } ?? "nil") bubbles=\(koharuBubbleAdjacencySeamReport.map { String($0.evaluatedBubbleCount) } ?? "nil") pairs=\(koharuBubbleAdjacencySeamReport.map { String($0.pairLedgerCount) } ?? "nil") seams=\(koharuBubbleAdjacencySeamReport.map { String($0.seamCandidateCount) } ?? "nil") blocks=\(koharuBubbleAdjacencySeamReport.map { String($0.blockLedgerCount) } ?? "nil") gates=\(koharuBubbleAdjacencySeamReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuBubbleAdjacencySeamReport?.adjacencyVerdict ?? "nil")
        bubbleAdjacencyPairVerdict=\(koharuBubbleAdjacencySeamReport?.pairVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        bubbleSeamCandidateVerdict=\(koharuBubbleAdjacencySeamReport?.seamCandidateVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        bubbleSeamRisk=\(koharuBubbleAdjacencySeamReport?.blockSeamRiskBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        bubbleSeamNextAction=\(koharuBubbleAdjacencySeamReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(bubbleAdjacencyPairSummary.isEmpty ? "bubbleAdjacencyPair: nil" : bubbleAdjacencyPairSummary)
        \(bubbleSeamCandidateSummary.isEmpty ? "bubbleSeamCandidate: nil" : bubbleSeamCandidateSummary)
        koharuRenderSpriteFitPlannerReport: enabled=\(koharuRenderSpriteFitPlannerReport.map { String($0.enabled) } ?? "nil") blocks=\(koharuRenderSpriteFitPlannerReport.map { String($0.blockLedgerCount) } ?? "nil") layoutCandidates=\(koharuRenderSpriteFitPlannerReport.map { String($0.layoutCandidateCount) } ?? "nil") siblings=\(koharuRenderSpriteFitPlannerReport.map { String($0.siblingLedgerCount) } ?? "nil") gates=\(koharuRenderSpriteFitPlannerReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuRenderSpriteFitPlannerReport?.fitPlannerVerdict ?? "nil")
        renderSpriteTextSource=\(koharuRenderSpriteFitPlannerReport?.textSourceBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        renderSpriteFitVerdict=\(koharuRenderSpriteFitPlannerReport?.fitVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        renderSpriteFontBudget=\(koharuRenderSpriteFitPlannerReport?.fontBudgetBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        renderSpriteFailureOverlayFit=\(koharuRenderSpriteFitPlannerReport?.failureOverlayFitBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        renderSpriteNextAction=\(koharuRenderSpriteFitPlannerReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(renderSpriteLayoutCandidateSummary.isEmpty ? "renderSpriteLayoutCandidate: nil" : renderSpriteLayoutCandidateSummary)
        \(renderSpriteSiblingFitSummary.isEmpty ? "renderSpriteSiblingFit: nil" : renderSpriteSiblingFitSummary)
        koharuNativeTextBoxDetectorLiteReport: enabled=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.enabled) } ?? "nil") blocks=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.blockLedgerCount) } ?? "nil") bubbles=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.bubbleLedgerCount) } ?? "nil") candidates=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.candidateCount) } ?? "nil") accepted=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.acceptedCandidateCount) } ?? "nil") shadowEligible=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.shadowOCREligibleCandidateCount) } ?? "nil") gates=\(koharuNativeTextBoxDetectorLiteReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuNativeTextBoxDetectorLiteReport?.detectorLiteVerdict ?? "nil")
        nativeTextBoxDetectorLiteCandidateVerdict=\(koharuNativeTextBoxDetectorLiteReport?.candidateVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteDirection=\(koharuNativeTextBoxDetectorLiteReport?.directionHintBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteBottleneck=\(koharuNativeTextBoxDetectorLiteReport?.primaryBottleneckBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteNextAction=\(koharuNativeTextBoxDetectorLiteReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteCandidateLedger: \((koharuNativeTextBoxDetectorLiteReport?.candidates.prefix(24).map { "\($0.candidateID):bubble=\($0.sourceBubbleID.map(String.init) ?? "nil"):bbox=[\($0.bbox.map { String(Int($0.rounded())) }.joined(separator: ","))]:dir=\($0.directionHint):score=\($0.score.formatted(.number.precision(.fractionLength(3)))):verdict=\($0.candidateVerdict):shadow=\($0.shadowOCREligible):relations=\($0.relatedBlockRelations.map { "#\($0.blockIndex)/\($0.relationReason)/ov=\($0.overlapRatio.formatted(.number.precision(.fractionLength(2))))/same=\($0.sameBubble)" }.joined(separator: ";"))" }.joined(separator: " | ")) ?? "nil")
        nativeTextBoxDetectorLiteBubbleLedger: \((koharuNativeTextBoxDetectorLiteReport?.bubbleLedgers.map { "bubble=\($0.bubbleID):candidates=\($0.candidateCount):accepted=\($0.acceptedCandidateCount):coverage=\($0.nativeTextBoxCoverageVerdict):split=\($0.splitRisk):sibling=\($0.sameBubbleSiblingRisk):next=\($0.nextAction)" }.joined(separator: " | ")) ?? "nil")
        koharuNativeTextBoxDetectorLiteShadowOCRReport: enabled=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.enabled) } ?? "nil") inputCandidates=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.inputCandidateCount) } ?? "nil") selected=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.selectedCandidateCount) } ?? "nil") ocrExecuted=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.ocrExecutedCount) } ?? "nil") succeeded=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.ocrSucceededCount) } ?? "nil") empty=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.emptyOCRCount) } ?? "nil") better=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.betterThanCurrentCount) } ?? "nil") worse=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.worseThanCurrentCount) } ?? "nil") same=\(koharuNativeTextBoxDetectorLiteShadowOCRReport.map { String($0.sameAsCurrentCount) } ?? "nil") verdict=\(koharuNativeTextBoxDetectorLiteShadowOCRReport?.shadowOCRVerdict ?? "nil")
        nativeTextBoxDetectorLiteShadowOCROutcome=\(koharuNativeTextBoxDetectorLiteShadowOCRReport?.ocrOutcomeBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteShadowOCRQualityDelta=\(koharuNativeTextBoxDetectorLiteShadowOCRReport?.qualityDeltaBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteShadowOCRRotation=\(nativeTextBoxDetectorLiteShadowOCRRotationSummary.isEmpty ? "nil" : nativeTextBoxDetectorLiteShadowOCRRotationSummary)
        nativeTextBoxDetectorLiteShadowOCRNextAction=\(koharuNativeTextBoxDetectorLiteShadowOCRReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(nativeTextBoxDetectorLiteShadowOCRCandidateSummary.isEmpty ? "nativeTextBoxDetectorLiteShadowOCRCandidate: nil" : nativeTextBoxDetectorLiteShadowOCRCandidateSummary)
        koharuNativeTextBoxDetectorLiteRefinementReport: enabled=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.enabled) } ?? "nil") targets=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.targetBlockCount) } ?? "nil") candidates=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.refinedCandidateCount) } ?? "nil") ocrExecuted=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.ocrExecutedCount) } ?? "nil") succeeded=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.ocrSucceededCount) } ?? "nil") empty=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.emptyOCRCount) } ?? "nil") betterCurrent=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.refinedBetterThanCurrentCount) } ?? "nil") betterDetectorLite=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.refinedBetterThanDetectorLiteCount) } ?? "nil") worse=\(koharuNativeTextBoxDetectorLiteRefinementReport.map { String($0.refinedWorseThanDetectorLiteCount) } ?? "nil") verdict=\(koharuNativeTextBoxDetectorLiteRefinementReport?.refinementVerdict ?? "nil")
        nativeTextBoxDetectorLiteRefinementOutcome=\(koharuNativeTextBoxDetectorLiteRefinementReport?.ocrOutcomeBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteRefinementStrategy=\(koharuNativeTextBoxDetectorLiteRefinementReport?.refinementStrategyBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeTextBoxDetectorLiteRefinementNextAction=\(koharuNativeTextBoxDetectorLiteRefinementReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(nativeTextBoxDetectorLiteRefinementCandidateSummary.isEmpty ? "nativeTextBoxDetectorLiteRefinementCandidate: nil" : nativeTextBoxDetectorLiteRefinementCandidateSummary)
        koharuNativeTextBoxDetectorLiteClosedLoopReport: enabled=\(koharuNativeTextBoxDetectorLiteClosedLoopReport.map { String($0.enabled) } ?? "nil") families=\(koharuNativeTextBoxDetectorLiteClosedLoopReport.map { String($0.candidateFamilyCount) } ?? "nil") blocks=\(koharuNativeTextBoxDetectorLiteClosedLoopReport.map { String($0.blockLedgerCount) } ?? "nil") stop=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.stopBlockIndexes.map(String.init).joined(separator: ",") ?? "nil") fullReview=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.fullProbeReviewBlockIndexes.map(String.init).joined(separator: ",") ?? "nil") realTextBoxes=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.realTextBoxesNeededBlocks.map(String.init).joined(separator: ",") ?? "nil") realBubbleMask=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.realBubbleMaskNeededBlocks.map(String.init).joined(separator: ",") ?? "nil") realSegmentMask=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.realSegmentMaskNeededBlocks.map(String.init).joined(separator: ",") ?? "nil") modelFloor=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.modelFloorRoutedBlocks.map(String.init).joined(separator: ",") ?? "nil") renderLock=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.renderLockRoutedBlocks.map(String.init).joined(separator: ",") ?? "nil") verdict=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.closedLoopVerdict ?? "nil")
        detectorLiteClosedLoopRoute=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.routeBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        detectorLiteClosedLoopBottleneck=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.primaryBottleneckBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        detectorLiteClosedLoopNextAction=\(koharuNativeTextBoxDetectorLiteClosedLoopReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        \(nativeTextBoxDetectorLiteClosedLoopFamilySummary.isEmpty ? "nativeTextBoxDetectorLiteCandidateFamily: nil" : nativeTextBoxDetectorLiteClosedLoopFamilySummary)
        koharuNativeBubbleMaskInstanceLiteReport: enabled=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.enabled) } ?? "nil") instances=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.instanceCount) } ?? "nil") blocks=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.blockLedgerCount) } ?? "nil") siblings=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.siblingLedgerCount) } ?? "nil") adjacency=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.adjacencyLedgerCount) } ?? "nil") gates=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuNativeBubbleMaskInstanceLiteReport?.instanceLiteVerdict ?? "nil") proxyNotRealKoharuBubbleMask=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.proxyNotRealKoharuBubbleMask) } ?? "nil") nativeInstanceLite=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.nativeInstanceLite) } ?? "nil") groundTruthUsedForDecision=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.groundTruthUsedForDecision) } ?? "nil") wouldChangeMainFlow=\(koharuNativeBubbleMaskInstanceLiteReport.map { String($0.wouldChangeMainFlow) } ?? "nil")
        nativeBubbleMaskInstanceLiteQuality=\(koharuNativeBubbleMaskInstanceLiteReport?.instanceQualityBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteAssignment=\(koharuNativeBubbleMaskInstanceLiteReport?.assignmentAgreementBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteSplit=\(koharuNativeBubbleMaskInstanceLiteReport?.splitRiskBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteSibling=\(koharuNativeBubbleMaskInstanceLiteReport?.siblingPartitionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteSafeRect=\(koharuNativeBubbleMaskInstanceLiteReport?.safeRectComparisonBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteSafeRectPolicy=\(koharuNativeBubbleMaskInstanceLiteReport?.safeRectPolicyBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteBlockScopedSpriteContainment=\(koharuNativeBubbleMaskInstanceLiteReport?.spriteBlockScopedContainmentBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteSiblingSpriteCollision=\(koharuNativeBubbleMaskInstanceLiteReport?.spriteSiblingCollisionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteBottleneck=\(koharuNativeBubbleMaskInstanceLiteReport?.primaryBottleneckBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeBubbleMaskInstanceLiteNextAction=\(koharuNativeBubbleMaskInstanceLiteReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        needsRealBubbleMaskBlocks=\(koharuNativeBubbleMaskInstanceLiteReport?.needsRealBubbleMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealSegmentMaskBlocks=\(koharuNativeBubbleMaskInstanceLiteReport?.needsRealSegmentMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealTextBoxesBlocks=\(koharuNativeBubbleMaskInstanceLiteReport?.needsRealTextBoxesBlocks.map(String.init).joined(separator: ",") ?? "nil")
        \(nativeBubbleMaskInstanceSummary.isEmpty ? "nativeBubbleMaskInstanceLiteInstance: nil" : nativeBubbleMaskInstanceSummary)
        \(nativeBubbleMaskSiblingSummary.isEmpty ? "nativeBubbleMaskInstanceLiteSiblingLedger: nil" : nativeBubbleMaskSiblingSummary)
        \(nativeBubbleMaskAdjacencySummary.isEmpty ? "nativeBubbleMaskInstanceLiteAdjacencyLedger: nil" : nativeBubbleMaskAdjacencySummary)
        koharuNativeSegmentMaskRefinementLiteReport: enabled=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.enabled) } ?? "nil") candidates=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.candidateLedgerCount) } ?? "nil") blocks=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.blockLedgerCount) } ?? "nil") siblings=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.siblingLedgerCount) } ?? "nil") gates=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuNativeSegmentMaskRefinementLiteReport?.refinementLiteVerdict ?? "nil") proxyNotRealKoharuSegmentMask=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.proxyNotRealKoharuSegmentMask) } ?? "nil") nativeRefinementLite=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.nativeRefinementLite) } ?? "nil") groundTruthUsedForDecision=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.groundTruthUsedForDecision) } ?? "nil") wouldChangeMainFlow=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.wouldChangeMainFlow) } ?? "nil")
        nativeSegmentMaskRefinementLiteSource=\(koharuNativeSegmentMaskRefinementLiteReport?.candidateSourceBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteVerdict=\(koharuNativeSegmentMaskRefinementLiteReport?.candidateVerdictBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLitePixels=\(koharuNativeSegmentMaskRefinementLiteReport?.pixelEvidenceBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteTextBoxClamp=\(koharuNativeSegmentMaskRefinementLiteReport?.textboxClampBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteTextBoxLink=\(koharuNativeSegmentMaskRefinementLiteReport?.textBoxSegmentLinkBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") acceptedTextBox=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.segmentFromAcceptedTextBoxCount) } ?? "nil") rejectedTextBox=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.segmentFromRejectedTextBoxCount) } ?? "nil") fallbackBBox=\(koharuNativeSegmentMaskRefinementLiteReport.map { String($0.segmentFromFallbackBBoxCount) } ?? "nil")
        nativeSegmentMaskRefinementLiteBubbleClamp=\(koharuNativeSegmentMaskRefinementLiteReport?.bubbleClampBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteContainment=\(koharuNativeSegmentMaskRefinementLiteReport?.maskContainmentBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteMajorityAgreement=\(koharuNativeSegmentMaskRefinementLiteReport?.maskMajorityAgreementBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteBottleneck=\(koharuNativeSegmentMaskRefinementLiteReport?.primaryBottleneckBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeSegmentMaskRefinementLiteNextAction=\(koharuNativeSegmentMaskRefinementLiteReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        needsRealSegmentMaskBlocks=\(koharuNativeSegmentMaskRefinementLiteReport?.needsRealSegmentMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealTextBoxesBlocks=\(koharuNativeSegmentMaskRefinementLiteReport?.needsRealTextBoxesBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealBubbleMaskBlocks=\(koharuNativeSegmentMaskRefinementLiteReport?.needsRealBubbleMaskBlocks.map(String.init).joined(separator: ",") ?? "nil")
        \(nativeSegmentMaskRefinementCandidateSummary.isEmpty ? "nativeSegmentMaskRefinementLiteCandidate: nil" : nativeSegmentMaskRefinementCandidateSummary)
        \(nativeSegmentMaskRefinementSiblingSummary.isEmpty ? "nativeSegmentMaskRefinementLiteSiblingLedger: nil" : nativeSegmentMaskRefinementSiblingSummary)
        koharuNativeArtifactBundleLiteReport: enabled=\(koharuNativeArtifactBundleLiteReport.map { String($0.enabled) } ?? "nil") bundles=\(koharuNativeArtifactBundleLiteReport.map { String($0.bundleLedgerCount) } ?? "nil") edges=\(koharuNativeArtifactBundleLiteReport.map { String($0.consistencyEdgeCount) } ?? "nil") workItems=\(koharuNativeArtifactBundleLiteReport.map { String($0.workItemCount) } ?? "nil") gates=\(koharuNativeArtifactBundleLiteReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuNativeArtifactBundleLiteReport?.bundleLiteVerdict ?? "nil") nativeBundleLite=\(koharuNativeArtifactBundleLiteReport.map { String($0.nativeBundleLite) } ?? "nil") proxyTextBoxes=\(koharuNativeArtifactBundleLiteReport.map { String($0.proxyNotRealKoharuTextBoxes) } ?? "nil") proxyBubbleMask=\(koharuNativeArtifactBundleLiteReport.map { String($0.proxyNotRealKoharuBubbleMask) } ?? "nil") proxySegmentMask=\(koharuNativeArtifactBundleLiteReport.map { String($0.proxyNotRealKoharuSegmentMask) } ?? "nil") groundTruthUsedForDecision=\(koharuNativeArtifactBundleLiteReport.map { String($0.groundTruthUsedForDecision) } ?? "nil") wouldChangeMainFlow=\(koharuNativeArtifactBundleLiteReport.map { String($0.wouldChangeMainFlow) } ?? "nil")
        nativeArtifactBundleLiteComponentReadiness=\(koharuNativeArtifactBundleLiteReport?.componentReadinessBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeArtifactBundleLiteConsistency=\(koharuNativeArtifactBundleLiteReport?.artifactConsistencyBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeArtifactBundleLiteTextBoxSegmentLink=\(koharuNativeArtifactBundleLiteReport?.textBoxSegmentLinkBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") reviewBlocks=\(koharuNativeArtifactBundleLiteReport?.textBoxSegmentLinkageReviewBlocks.map(String.init).joined(separator: ",") ?? "nil")
        nativeArtifactBundleLiteBlockingArtifact=\(koharuNativeArtifactBundleLiteReport?.primaryBlockingArtifactBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeArtifactBundleLiteNextAction=\(koharuNativeArtifactBundleLiteReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativeArtifactBundleLiteReadyForFullProbe=\(koharuNativeArtifactBundleLiteReport?.readyForFullProbeReviewBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealTextBoxes=\(koharuNativeArtifactBundleLiteReport?.needsRealTextBoxesBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealBubbleMask=\(koharuNativeArtifactBundleLiteReport?.needsRealBubbleMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealSegmentMask=\(koharuNativeArtifactBundleLiteReport?.needsRealSegmentMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") modelFloor=\(koharuNativeArtifactBundleLiteReport?.modelFloorBlockedBlocks.map(String.init).joined(separator: ",") ?? "nil") renderLocked=\(koharuNativeArtifactBundleLiteReport?.renderLockedBlocks.map(String.init).joined(separator: ",") ?? "nil")
        \(nativeArtifactBundleLiteBlockSummary.isEmpty ? "nativeArtifactBundleLiteBlockLedger: nil" : nativeArtifactBundleLiteBlockSummary)
        \(nativeArtifactBundleLiteEdgeSummary.isEmpty ? "nativeArtifactBundleLiteConsistencyEdge: nil" : nativeArtifactBundleLiteEdgeSummary)
        \(nativeArtifactBundleLiteWorkItemSummary.isEmpty ? "nativeArtifactBundleLiteWorkItem: nil" : nativeArtifactBundleLiteWorkItemSummary)
        koharuNativePromotionGateLiteReport: enabled=\(koharuNativePromotionGateLiteReport.map { String($0.enabled) } ?? "nil") blocks=\(koharuNativePromotionGateLiteReport.map { String($0.blockLedgerCount) } ?? "nil") stageGates=\(koharuNativePromotionGateLiteReport.map { String($0.stageGateCount) } ?? "nil") previews=\(koharuNativePromotionGateLiteReport.map { String($0.candidateExportPreviewCount) } ?? "nil") workItems=\(koharuNativePromotionGateLiteReport.map { String($0.workItemCount) } ?? "nil") gates=\(koharuNativePromotionGateLiteReport.map { String($0.gateCount) } ?? "nil") verdict=\(koharuNativePromotionGateLiteReport?.promotionVerdict ?? "nil") promotionGateLite=\(koharuNativePromotionGateLiteReport.map { String($0.promotionGateLite) } ?? "nil") previewOnly=\(koharuNativePromotionGateLiteReport.map { String($0.nativePromotionPreviewOnly) } ?? "nil") groundTruthUsedForDecision=\(koharuNativePromotionGateLiteReport.map { String($0.groundTruthUsedForDecision) } ?? "nil") wouldChangeMainFlow=\(koharuNativePromotionGateLiteReport.map { String($0.wouldChangeMainFlow) } ?? "nil")
        nativePromotionStageReadiness=\(koharuNativePromotionGateLiteReport?.stageReadinessBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativePromotionEligibility=\(koharuNativePromotionGateLiteReport?.promotionEligibilityBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativePromotionBlockingArtifact=\(koharuNativePromotionGateLiteReport?.primaryBlockingArtifactBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativePromotionBottleneck=\(koharuNativePromotionGateLiteReport?.probeBottleneckBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativePromotionTextBoxSegmentLink=\(koharuNativePromotionGateLiteReport?.textBoxSegmentLinkBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") blocked=\(koharuNativePromotionGateLiteReport?.textBoxSegmentLinkageBlockedBlocks.map(String.init).joined(separator: ",") ?? "nil")
        nativePromotionNextAction=\(koharuNativePromotionGateLiteReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        nativePromotionShadowReviewEligible=\(koharuNativePromotionGateLiteReport?.shadowReviewEligibleBlocks.map(String.init).joined(separator: ",") ?? "nil") stopLocalTuning=\(koharuNativePromotionGateLiteReport?.stopLocalTuningBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealTextBoxes=\(koharuNativePromotionGateLiteReport?.needsRealTextBoxesBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealBubbleMask=\(koharuNativePromotionGateLiteReport?.needsRealBubbleMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") needsRealSegmentMask=\(koharuNativePromotionGateLiteReport?.needsRealSegmentMaskBlocks.map(String.init).joined(separator: ",") ?? "nil") modelFloor=\(koharuNativePromotionGateLiteReport?.modelFloorBlockedBlocks.map(String.init).joined(separator: ",") ?? "nil") renderLocked=\(koharuNativePromotionGateLiteReport?.renderLockedBlocks.map(String.init).joined(separator: ",") ?? "nil")
        \(nativePromotionStageGateSummary.isEmpty ? "nativePromotionStageGate: nil" : nativePromotionStageGateSummary)
        \(nativePromotionBlockSummary.isEmpty ? "nativePromotionBlockLedger: nil" : nativePromotionBlockSummary)
        \(nativePromotionPreviewSummary.isEmpty ? "nativeCandidateExportPreview: nil" : nativePromotionPreviewSummary)
        \(nativePromotionWorkItemSummary.isEmpty ? "nativePromotionWorkItem: nil" : nativePromotionWorkItemSummary)
        koharuNativeArtifactContractDryRunReport: enabled=\(koharuNativeArtifactContractDryRunReport.map { String($0.enabled) } ?? "nil") requiredFiles=\(koharuNativeArtifactContractDryRunReport.map { String($0.requiredFileCount) } ?? "nil") previews=\(koharuNativeArtifactContractDryRunReport.map { String($0.dryRunPreviewCount) } ?? "nil") gates=\(koharuNativeArtifactContractDryRunReport.map { String($0.contractGateCount) } ?? "nil") verdict=\(koharuNativeArtifactContractDryRunReport?.contractDryRunVerdict ?? "nil") dryRunOnly=\(koharuNativeArtifactContractDryRunReport.map { String($0.dryRunOnly) } ?? "nil") activeExportAllowed=\(koharuNativeArtifactContractDryRunReport.map { String($0.activeExportAllowed) } ?? "nil") groundTruthUsedForDecision=\(koharuNativeArtifactContractDryRunReport.map { String($0.groundTruthUsedForDecision) } ?? "nil") wouldChangeMainFlow=\(koharuNativeArtifactContractDryRunReport.map { String($0.wouldChangeMainFlow) } ?? "nil")
        artifactContractDryRunReadiness=\(koharuNativeArtifactContractDryRunReport?.readinessVerdict ?? "nil") activeDirectory=\(koharuNativeArtifactContractDryRunReport.map { String($0.activeArtifactsDirectory) } ?? "nil") shadowOCRAllowed=\(koharuNativeArtifactContractDryRunReport.map { String($0.externalTextBoxesShadowOCRAllowed) } ?? "nil") sourceImage=\(koharuNativeArtifactContractDryRunReport?.sourceImage ?? "nil") coordinateSpace=\(koharuNativeArtifactContractDryRunReport?.coordinateSpace ?? "nil")
        artifactContractDryRunRequiredFileStatus=\(koharuNativeArtifactContractDryRunReport?.requiredFileStatusBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        artifactContractDryRunTargetArtifacts=\(koharuNativeArtifactContractDryRunReport?.targetArtifactBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        artifactContractDryRunMissingFields=\(koharuNativeArtifactContractDryRunReport?.missingRequiredFieldBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        artifactContractDryRunForbiddenSources=\(koharuNativeArtifactContractDryRunReport?.forbiddenSourceBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        artifactContractDryRunNextAction=\(koharuNativeArtifactContractDryRunReport?.nextActionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil")
        artifactContractDryRunValidatorCommands=\(koharuNativeArtifactContractDryRunReport?.validatorCommands.joined(separator: " | ") ?? "nil")
        artifactContractDryRunForbiddenActiveSources=\(koharuNativeArtifactContractDryRunReport?.forbiddenActiveSources.joined(separator: ",") ?? "nil")
        \(nativeArtifactContractDryRunFileSummary.isEmpty ? "nativeArtifactContractDryRunRequiredFile: nil" : nativeArtifactContractDryRunFileSummary)
        \(nativeArtifactContractDryRunPreviewSummary.isEmpty ? "nativeArtifactContractDryRunPreview: nil" : nativeArtifactContractDryRunPreviewSummary)
        \(nativeArtifactContractDryRunGateSummary.isEmpty ? "nativeArtifactContractDryRunGate: nil" : nativeArtifactContractDryRunGateSummary)
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
        externalTextBoxShadowOCR: enabled=\(externalTextBoxShadowOCRReport.map { String($0.enabled) } ?? "nil") executed=\(externalTextBoxShadowOCRReport.map { String($0.executed) } ?? "nil") gateVerdict=\(externalTextBoxShadowOCRReport?.gateVerdict ?? "nil") candidates=\(externalTextBoxShadowOCRReport.map { String($0.candidateCount) } ?? "nil") ocrExecuted=\(externalTextBoxShadowOCRReport.map { String($0.ocrExecutedCount) } ?? "nil") betterThanControl=\(externalTextBoxShadowOCRReport.map { String($0.betterThanControlCount) } ?? "nil") skipped=\(externalTextBoxShadowOCRReport?.skippedBlocks.map(String.init).joined(separator: ",") ?? "nil") orientationVerdict=\(externalTextBoxShadowOCRReport?.orientationReadinessVerdict ?? "nil") orientation=\(externalTextBoxShadowOCRReport?.orientationCategoryBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") sourceDirection=\(externalTextBoxShadowOCRReport?.sourceDirectionBreakdown.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",") ?? "nil") linePolygonBlocks=\(externalTextBoxShadowOCRReport?.linePolygonCandidateBlocks.map(String.init).joined(separator: ",") ?? "nil") rotationBlocks=\(externalTextBoxShadowOCRReport?.rotationCandidateBlocks.map(String.init).joined(separator: ",") ?? "nil") verticalBlocks=\(externalTextBoxShadowOCRReport?.verticalCandidateBlocks.map(String.init).joined(separator: ",") ?? "nil") orientationNeeded=\(externalTextBoxShadowOCRReport?.orientationShadowPathNeededBlocks.map(String.init).joined(separator: ",") ?? "nil") orientationExecuted=\(externalTextBoxShadowOCRReport?.orientationShadowPathExecutedBlocks.map(String.init).joined(separator: ",") ?? "nil") orientationNotExecuted=\(externalTextBoxShadowOCRReport?.orientationShadowPathNotExecutedBlocks.map(String.init).joined(separator: ",") ?? "nil")
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
        convergenceBundleTextBoxSegmentLinkage=status:\(convergenceBundleLinkageWorkItem?.status ?? "nil"):blocks=\(convergenceBundleLinkageWorkItem?.targetBlocks.map(String.init).joined(separator: ",") ?? "nil"):next=\(convergenceBundleLinkageWorkItem?.nextAction ?? "nil")
        convergencePromotionTextBoxSegmentLinkage=status:\(convergencePromotionLinkageWorkItem?.status ?? "nil"):blocks=\(convergencePromotionLinkageWorkItem?.targetBlocks.map(String.init).joined(separator: ",") ?? "nil"):next=\(convergencePromotionLinkageWorkItem?.nextAction ?? "nil")

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
        sliceIndex: Int? = nil,
        recognitionLanguages: [String]? = nil
    ) throws -> [MangaOverlayOCRCandidate] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        if !customWords.isEmpty {
            request.customWords = customWords
        }
        let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
        let requestedLanguages = recognitionLanguages ?? ["en-US", "en"]
        let availableRequestedLanguages = requestedLanguages.filter { supportedLanguages.contains($0) }
        if !availableRequestedLanguages.isEmpty {
            request.recognitionLanguages = availableRequestedLanguages
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

    private struct RGBA8Bitmap {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var pixels: [UInt8]
    }

    private static func makeRGBA8Bitmap(from image: CGImage) -> RGBA8Bitmap? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            context.flush()
            return true
        }
        guard rendered else { return nil }
        return RGBA8Bitmap(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
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
        let backgroundBitmap = makeRGBA8Bitmap(from: image)
        return try draw(on: image) { context, _ in
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
                    let background = sampleBackgroundColor(bitmap: backgroundBitmap, near: expanded)
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

    private static func sampleBackgroundColor(bitmap: RGBA8Bitmap?, near rect: CGRect) -> CGColor {
        guard let bitmap else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 0.94)
        }

        let bytes = bitmap.pixels
        let bytesPerRow = bitmap.bytesPerRow
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(bitmap.width), height: CGFloat(bitmap.height))
        let ring = expand(rect, by: 0.24, bounds: bounds)
        var samples: [(Int, Int, Int)] = []
        let step = max(1, Int(min(ring.width, ring.height) / 12))
        for y in stride(from: Int(ring.minY), through: Int(ring.maxY), by: step) {
            for x in stride(from: Int(ring.minX), through: Int(ring.maxX), by: step) {
                guard !rect.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))), x >= 0, y >= 0, x < bitmap.width, y < bitmap.height else { continue }
                let offset = y * bytesPerRow + x * 4
                guard offset + 2 < bytes.count else { continue }
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
        bitmap: RGBA8Bitmap?,
        blockRect: CGRect,
        bubbleRect: CGRect?
    ) -> MangaOverlayGlyphMaskPlan? {
        guard let bubbleRect else { return nil }
        guard let bitmap,
              bitmap.width == image.width,
              bitmap.height == image.height else {
            return nil
        }

        let bytes = bitmap.pixels
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let bubbleBounds = clamp(bubbleRect.integral, to: imageBounds)
        let ocrBounds = clamp(expand(blockRect, by: 0.08, bounds: imageBounds).integral, to: bubbleBounds)
        guard bubbleBounds.width >= 4, bubbleBounds.height >= 4, ocrBounds.width >= 2, ocrBounds.height >= 2 else {
            return nil
        }

        let width = Int(bubbleBounds.width)
        let height = Int(bubbleBounds.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = bitmap.bytesPerRow
        var gray = [UInt8](repeating: 255, count: width * height)
        for localY in 0..<height {
            let y = Int(bubbleBounds.minY) + localY
            for localX in 0..<width {
                let x = Int(bubbleBounds.minX) + localX
                guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
                let offset = y * bytesPerRow + x * 4
                guard offset + 2 < bytes.count else { continue }
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
            bitmap: bitmap,
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
        bitmap: RGBA8Bitmap,
        bubbleBounds: CGRect,
        excludedOffsets: Set<Int>
    ) -> (color: [Double], stdDev: Double)? {
        let width = Int(bubbleBounds.width)
        let height = Int(bubbleBounds.height)
        guard width > 0, height > 0 else { return nil }

        let bytes = bitmap.pixels
        let bytesPerRow = bitmap.bytesPerRow
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
            guard x >= 0, y >= 0, x < bitmap.width, y < bitmap.height else { continue }
            let offset = y * bytesPerRow + x * 4
            guard offset + 2 < bytes.count else { continue }
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
