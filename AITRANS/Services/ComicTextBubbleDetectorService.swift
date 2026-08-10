import CoreGraphics
import CoreML
import CoreVideo
import Foundation

struct ComicTextDetectorRegion: Equatable, Sendable {
    var rect: ImageOCRLayoutRect
    var confidence: Float
}

enum ComicTextBubbleDetectorServiceError: LocalizedError {
    case modelResourceMissing(String)
    case modelOutputMissing(String)
    case imageRenderFailed

    var errorDescription: String? {
        switch self {
        case let .modelResourceMissing(name):
            "缺少漫画文字检测模型资源：\(name)"
        case let .modelOutputMissing(name):
            "漫画文字检测模型输出无效：\(name)"
        case .imageRenderFailed:
            "无法准备漫画文字检测图片"
        }
    }
}

actor ComicTextBubbleDetectorService {
    static let shared = ComicTextBubbleDetectorService()

    private var runtime: ComicTextBubbleDetectorRuntime?

    static func inferenceWindowCount(for image: CGImage) -> Int {
        ComicTextBubbleDetectorRuntime.inferenceWindowCount(
            imageWidth: image.width,
            imageHeight: image.height
        )
    }

    func detectTextRegions(in image: CGImage) throws -> [ComicTextDetectorRegion] {
        try Task.checkCancellation()
        let regions = try loadedRuntime().detectTextRegions(in: image)
        try Task.checkCancellation()
        return regions
    }

    private func loadedRuntime() throws -> ComicTextBubbleDetectorRuntime {
        if let runtime {
            return runtime
        }
        let loaded = try ComicTextBubbleDetectorRuntime(bundle: .main)
        runtime = loaded
        return loaded
    }
}

private struct ComicTextBubbleDetectorRuntime {
    private static let imageSize = 640
    private static let queryCount = 300
    private static let labelCount = 3
    private static let confidenceThreshold: Float = 0.30
    private static let textLabelIDs = Set([1, 2])
    private static let sliceAspectRatioThreshold = 3.5
    private static let sliceTargetAspectRatio = 3.0
    private static let sliceOverlapRatio = 0.20
    private static let minimumLastSliceRatio = 0.70

    private let model: MLModel

    init(bundle: Bundle) throws {
        let configuration = MLModelConfiguration()
        // This converted RT-DETR graph aborts inside MPSGraph on some macOS/iOS
        // runtimes when GPU compilation is enabled. CPU-only inference is slower
        // but deterministic and, unlike an Objective-C assertion, remains inside
        // the service's recoverable error boundary.
        configuration.computeUnits = .cpuOnly
        guard let modelURL = bundle.url(
            forResource: "ComicTextBubbleDetectorINT8",
            withExtension: "mlmodelc"
        ) else {
            throw ComicTextBubbleDetectorServiceError.modelResourceMissing(
                "ComicTextBubbleDetectorINT8.mlmodelc"
            )
        }
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    func detectTextRegions(in image: CGImage) throws -> [ComicTextDetectorRegion] {
        let slices = Self.detectorSlices(
            imageWidth: image.width,
            imageHeight: image.height
        )
        var detections: [DetectorPrediction] = []
        for slice in slices {
            try Task.checkCancellation()
            let sliceImage: CGImage
            if slice.startY == 0, slice.height == image.height {
                sliceImage = image
            } else {
                let cropRect = CGRect(
                    x: 0,
                    y: slice.startY,
                    width: image.width,
                    height: slice.height
                )
                guard let cropped = image.cropping(to: cropRect) else {
                    throw ComicTextBubbleDetectorServiceError.imageRenderFailed
                }
                sliceImage = cropped
            }
            detections.append(contentsOf: try detectPredictions(in: sliceImage).compactMap {
                Self.mapPredictionToFullImage(
                    $0,
                    slice: slice,
                    imageHeight: image.height
                )
            })
        }

        return Self.mergeTextRegions(Self.mergeSliceRegions(detections)).map {
            ComicTextDetectorRegion(rect: $0.rect, confidence: $0.confidence)
        }
        .sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }
            return $0.rect.x > $1.rect.x
        }
    }

    fileprivate static func inferenceWindowCount(
        imageWidth: Int,
        imageHeight: Int
    ) -> Int {
        detectorSlices(imageWidth: imageWidth, imageHeight: imageHeight).count
    }

    private func detectPredictions(in image: CGImage) throws -> [DetectorPrediction] {
        let pixelBuffer = try Self.makePixelBuffer(from: image)
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try model.prediction(from: input)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
              logits.dataType == .float32,
              logits.count == Self.queryCount * Self.labelCount else {
            throw ComicTextBubbleDetectorServiceError.modelOutputMissing("logits")
        }
        guard let boxes = output.featureValue(for: "pred_boxes")?.multiArrayValue,
              boxes.dataType == .float32,
              boxes.count == Self.queryCount * 4 else {
            throw ComicTextBubbleDetectorServiceError.modelOutputMissing("pred_boxes")
        }

        let logitValues = logits.dataPointer.bindMemory(
            to: Float.self,
            capacity: logits.count
        )
        let boxValues = boxes.dataPointer.bindMemory(
            to: Float.self,
            capacity: boxes.count
        )
        var scored: [ScoredPrediction] = []
        scored.reserveCapacity(Self.queryCount * Self.labelCount)
        for queryIndex in 0..<Self.queryCount {
            for labelID in 0..<Self.labelCount {
                let index = queryIndex * Self.labelCount + labelID
                scored.append(
                    ScoredPrediction(
                        score: Self.sigmoid(logitValues[index]),
                        queryIndex: queryIndex,
                        labelID: labelID
                    )
                )
            }
        }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.queryIndex != $1.queryIndex { return $0.queryIndex < $1.queryIndex }
            return $0.labelID < $1.labelID
        }

        let minimumWidth = 5 / Double(max(image.width, 1))
        let minimumHeight = 5 / Double(max(image.height, 1))
        var detections: [DetectorPrediction] = []
        for prediction in scored.prefix(Self.queryCount) {
            guard prediction.score >= Self.confidenceThreshold,
                  Self.textLabelIDs.contains(prediction.labelID) else {
                continue
            }
            let offset = prediction.queryIndex * 4
            guard let rect = Self.normalizedRect(
                centerX: boxValues[offset],
                centerY: boxValues[offset + 1],
                width: boxValues[offset + 2],
                height: boxValues[offset + 3]
            ),
            rect.width > minimumWidth,
            rect.height > minimumHeight else {
                continue
            }
            detections.append(
                DetectorPrediction(
                    labelID: prediction.labelID,
                    confidence: prediction.score,
                    rect: rect
                )
            )
        }
        return detections
    }

    /// Exact normalized-coordinate port of Koharu's ImageSlicer defaults.
    /// The last slice always reaches the page bottom; a short tail is folded
    /// into that slice instead of paying for a mostly empty extra inference.
    private static func detectorSlices(
        imageWidth: Int,
        imageHeight: Int
    ) -> [DetectorSlice] {
        guard imageWidth >= 1, imageHeight >= 1 else { return [] }
        let pageAspectRatio = Double(imageHeight) / Double(max(imageWidth, 1))
        guard pageAspectRatio > sliceAspectRatioThreshold else {
            return [DetectorSlice(startY: 0, height: imageHeight)]
        }

        let targetHeight = max(
            Int((Double(imageWidth) * sliceTargetAspectRatio).rounded()),
            1
        )
        let effectiveHeight = max(
            Int((Double(targetHeight) * (1 - sliceOverlapRatio)).rounded()),
            1
        )
        var sliceCount = max(
            Int(ceil(Double(imageHeight) / Double(effectiveHeight))),
            1
        )
        if sliceCount > 1 {
            let lastStart = (sliceCount - 1) * effectiveHeight
            let lastHeight = max(imageHeight - lastStart, 0)
            if Double(lastHeight) / Double(targetHeight) <= minimumLastSliceRatio {
                sliceCount -= 1
            }
        }

        return (0..<sliceCount).compactMap { index in
            let startY = index * effectiveHeight
            guard startY < imageHeight else { return nil }
            let height = index + 1 == sliceCount
                ? imageHeight - startY
                : min(targetHeight, imageHeight - startY)
            guard height >= 1 else { return nil }
            return DetectorSlice(startY: startY, height: height)
        }
    }

    private static func mapPredictionToFullImage(
        _ prediction: DetectorPrediction,
        slice: DetectorSlice,
        imageHeight: Int
    ) -> DetectorPrediction? {
        let fullHeight = Double(max(imageHeight, 1))
        guard let rect = ImageOCRLayoutRect(
            x: prediction.rect.x,
            y: (Double(slice.startY) + prediction.rect.y * Double(slice.height)) / fullHeight,
            width: prediction.rect.width,
            height: prediction.rect.height * Double(slice.height) / fullHeight
        ).normalizedToUnit() else {
            return nil
        }
        return DetectorPrediction(
            labelID: prediction.labelID,
            confidence: prediction.confidence,
            rect: rect
        )
    }

    private static func makePixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            imageSize,
            imageSize,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
            throw ComicTextBubbleDetectorServiceError.imageRenderFailed
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            throw ComicTextBubbleDetectorServiceError.imageRenderFailed
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: imageSize,
            height: imageSize,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw ComicTextBubbleDetectorServiceError.imageRenderFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: imageSize, height: imageSize))
        return pixelBuffer
    }

    private static func sigmoid(_ value: Float) -> Float {
        1 / (1 + exp(-value))
    }

    private static func normalizedRect(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float
    ) -> ImageOCRLayoutRect? {
        let rect = ImageOCRLayoutRect(
            x: Double(centerX - width / 2),
            y: Double(centerY - height / 2),
            width: Double(width),
            height: Double(height)
        )
        return rect.normalizedToUnit()
    }

    /// Koharu merges overlapping text_bubble/text_free detections into one
    /// TextRegion before recognition, while retaining the strongest confidence.
    private static func mergeTextRegions(
        _ detections: [DetectorPrediction]
    ) -> [DetectorPrediction] {
        var remaining = detections
        var merged: [DetectorPrediction] = []
        while var candidate = remaining.popLast() {
            var index = 0
            while index < remaining.count {
                let other = remaining[index]
                let overlaps = intersectionOverUnion(candidate.rect, other.rect) >= 0.50
                    || isMostlyContained(outer: candidate.rect, inner: other.rect, threshold: 0.30)
                    || isMostlyContained(outer: other.rect, inner: candidate.rect, threshold: 0.30)
                guard overlaps else {
                    index += 1
                    continue
                }
                candidate.rect = candidate.rect.union(other.rect)
                candidate.confidence = max(candidate.confidence, other.confidence)
                swapRemove(at: index, from: &remaining)
            }
            merged.append(candidate)
        }
        return merged
    }

    /// Koharu first reconciles same-label regions emitted by overlapping image
    /// slices. Coordinates are normalized here, so the reference implementation's
    /// `image_height * 0.1` bound is exactly `0.1` in this coordinate space.
    private static func mergeSliceRegions(
        _ detections: [DetectorPrediction]
    ) -> [DetectorPrediction] {
        var regions = detections
        let yDistanceThreshold = 0.1
        var index = 0
        while index < regions.count {
            var compare = index + 1
            while compare < regions.count {
                guard regions[index].labelID == regions[compare].labelID else {
                    compare += 1
                    continue
                }

                let first = regions[index].rect
                let second = regions[compare].rect
                let firstArea = area(first)
                let secondArea = area(second)
                let regionIoU = intersectionOverUnion(first, second)
                let containment = containmentRelation(first, second, threshold: 0.85)

                if containment.contained {
                    if !containment.firstContainsSecond {
                        regions[index].rect = second
                    }
                    regions[index].confidence = max(
                        regions[index].confidence,
                        regions[compare].confidence
                    )
                    swapRemove(at: compare, from: &regions)
                    continue
                }

                if regionIoU >= 0.50 {
                    if secondArea > firstArea {
                        regions[index].rect = second
                    }
                    regions[index].confidence = max(
                        regions[index].confidence,
                        regions[compare].confidence
                    )
                    swapRemove(at: compare, from: &regions)
                    continue
                }

                let firstWidth = max(first.width, 0.000_001)
                let firstHeight = max(first.height, 0.000_001)
                let secondWidth = max(second.width, 0.000_001)
                let secondHeight = max(second.height, 0.000_001)
                let yDistance = min(
                    abs(first.y - second.maxY),
                    abs(first.maxY - second.y)
                )
                let localYThreshold = min(
                    yDistanceThreshold,
                    max(firstHeight, secondHeight) * 0.1
                )
                let xOverlap = max(
                    min(first.maxX, second.maxX) - max(first.x, second.x),
                    0
                )
                let xOverlapRatio = xOverlap / min(firstWidth, secondWidth)
                let largestArea = max(firstArea, secondArea)
                let sizeRatio = largestArea > 0
                    ? min(firstArea, secondArea) / largestArea
                    : 0

                if yDistance < localYThreshold,
                   xOverlapRatio > 0.2,
                   sizeRatio > 0.3,
                   abs(first.x - second.x) < 0.5 * max(firstWidth, secondWidth),
                   abs(first.maxX - second.maxX) < 0.5 * max(firstWidth, secondWidth) {
                    let mergedRect = first.union(second)
                    if area(mergedRect) <= 3.0 * largestArea {
                        regions[index].rect = mergedRect
                        regions[index].confidence = max(
                            regions[index].confidence,
                            regions[compare].confidence
                        )
                        swapRemove(at: compare, from: &regions)
                        continue
                    }
                }
                compare += 1
            }
            index += 1
        }
        return regions
    }

    private static func swapRemove(
        at index: Int,
        from regions: inout [DetectorPrediction]
    ) {
        let lastIndex = regions.index(before: regions.endIndex)
        if index != lastIndex {
            regions.swapAt(index, lastIndex)
        }
        regions.removeLast()
    }

    private static func intersectionOverUnion(
        _ lhs: ImageOCRLayoutRect,
        _ rhs: ImageOCRLayoutRect
    ) -> Double {
        let intersection = intersectionArea(lhs, rhs)
        let union = area(lhs) + area(rhs) - intersection
        return union > 0 ? intersection / union : 0
    }

    private static func isMostlyContained(
        outer: ImageOCRLayoutRect,
        inner: ImageOCRLayoutRect,
        threshold: Double
    ) -> Bool {
        let innerArea = area(inner)
        guard innerArea > 0, area(outer) >= innerArea else { return false }
        return intersectionArea(outer, inner) / innerArea >= threshold
    }

    private static func containmentRelation(
        _ first: ImageOCRLayoutRect,
        _ second: ImageOCRLayoutRect,
        threshold: Double
    ) -> (contained: Bool, firstContainsSecond: Bool) {
        let firstArea = area(first)
        let secondArea = area(second)
        guard firstArea > 0, secondArea > 0 else { return (false, false) }
        let containmentRatio = intersectionArea(first, second) / min(firstArea, secondArea)
        guard containmentRatio >= threshold else { return (false, false) }
        return (true, firstArea >= secondArea)
    }

    private static func intersectionArea(
        _ lhs: ImageOCRLayoutRect,
        _ rhs: ImageOCRLayoutRect
    ) -> Double {
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.x, rhs.x))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.y, rhs.y))
        return width * height
    }

    private static func area(_ rect: ImageOCRLayoutRect) -> Double {
        max(rect.width, 0) * max(rect.height, 0)
    }
}

private struct ScoredPrediction {
    var score: Float
    var queryIndex: Int
    var labelID: Int
}

private struct DetectorPrediction {
    var labelID: Int
    var confidence: Float
    var rect: ImageOCRLayoutRect
}

private struct DetectorSlice {
    var startY: Int
    var height: Int
}
