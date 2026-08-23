import CoreGraphics
import CoreML
import CoreVideo
import Foundation

struct ComicTextDetectorRegion: Equatable, Sendable {
    var rect: ImageOCRLayoutRect
    var confidence: Float
    /// Assigned only after detector merge and deterministic sort. This is a
    /// session-local TextRegion identity, not a product-visible block ID.
    var regionID: ImageOCRRegionID? = nil
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

    static func diagnosticKoharuTriangleRGB(_ image: CGImage) throws -> [UInt8] {
        try ComicTextBubbleDetectorRuntime.diagnosticKoharuTriangleRGB(image)
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

        let merged = Self.mergeTextRegions(Self.mergeSliceRegions(detections))
            .compactMap {
                guard let confidence = Self.validDetectorConfidence($0.confidence) else {
                    return nil
                }
                return ComicTextDetectorRegion(rect: $0.rect, confidence: confidence)
            }
        let sorted = merged.sorted {
            let lhsConfidence = Self.detectorConfidenceRank($0.confidence)
            let rhsConfidence = Self.detectorConfidenceRank($1.confidence)
            if lhsConfidence != rhsConfidence { return lhsConfidence > rhsConfidence }
            if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }
            if $0.rect.x != $1.rect.x { return $0.rect.x > $1.rect.x }
            if $0.rect.width != $1.rect.width { return $0.rect.width < $1.rect.width }
            return $0.rect.height < $1.rect.height
        }
        return sorted.enumerated().map { index, region in
            var identified = region
            identified.regionID = ImageOCRRegionID("detector-region-\(index)")
            return identified
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
                let logit = logitValues[index]
                guard logit.isFinite else { continue }
                guard let score = Self.validDetectorConfidence(
                    Self.sigmoid(logit)
                ) else {
                    continue
                }
                scored.append(
                    ScoredPrediction(
                        score: score,
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
        let resizedRGB = try makeKoharuTriangleRGB(image)
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

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw ComicTextBubbleDetectorServiceError.imageRenderFailed
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for row in 0..<imageSize {
            let sourceRow = row * imageSize * 3
            let targetRow = baseAddress.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for column in 0..<imageSize {
                let sourceOffset = sourceRow + column * 3
                let targetOffset = column * 4
                // CVPixelBuffer's 32BGRA layout is B, G, R, A. The RGB
                // plane above is kept in Koharu's channel order until this
                // final copy so the resampler never depends on Core Graphics
                // interpolation, alpha, or color-profile behavior.
                targetRow[targetOffset] = resizedRGB[sourceOffset + 2]
                targetRow[targetOffset + 1] = resizedRGB[sourceOffset + 1]
                targetRow[targetOffset + 2] = resizedRGB[sourceOffset]
                targetRow[targetOffset + 3] = 255
            }
        }
        return pixelBuffer
    }

    /// Convert a CGImage to canonical DeviceRGB bytes and apply the same
    /// separable triangle filter used by Koharu's image-rs
    /// `resize_exact(..., FilterType::Triangle)`. Core Graphics' `.high`
    /// interpolation is not equivalent: image-rs uses a pixel-centred
    /// triangle kernel, enlarges the support when downsampling, normalizes
    /// edge weights, and rounds only after the horizontal pass.
    private static func makeKoharuTriangleRGB(_ image: CGImage) throws -> [UInt8] {
        guard image.width > 0,
              image.height > 0,
              image.width <= Int.max / max(image.height, 1),
              image.width * image.height <= 64_000_000 else {
            throw ComicTextBubbleDetectorServiceError.imageRenderFailed
        }
        let sourceBytesPerRow = image.width * 4
        var source = [UInt8](repeating: 0, count: sourceBytesPerRow * image.height)
        let rendered = source.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: sourceBytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        guard rendered else {
            throw ComicTextBubbleDetectorServiceError.imageRenderFailed
        }

        var rgb = [UInt8](repeating: 0, count: image.width * image.height * 3)
        for index in 0..<(image.width * image.height) {
            let sourceOffset = index * 4
            let targetOffset = index * 3
            // DeviceRGB + byteOrder32Little stores B, G, R in the first
            // three bytes. Keep the public diagnostic plane in R, G, B order.
            rgb[targetOffset] = source[sourceOffset + 2]
            rgb[targetOffset + 1] = source[sourceOffset + 1]
            rgb[targetOffset + 2] = source[sourceOffset]
        }
        return triangleResize(
            rgb,
            sourceWidth: image.width,
            sourceHeight: image.height,
            targetWidth: imageSize,
            targetHeight: imageSize
        )
    }

    /// Read-only runtime oracle used by the deterministic preprocessing
    /// harness. Production inference uses the same helper through
    /// `makePixelBuffer(from:)`.
    static func diagnosticKoharuTriangleRGB(_ image: CGImage) throws -> [UInt8] {
        try makeKoharuTriangleRGB(image)
    }

    private static func triangleResize(
        _ source: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> [UInt8] {
        let sourcePixelCount = sourceWidth * sourceHeight
        guard sourceWidth > 0,
              sourceHeight > 0,
              targetWidth > 0,
              targetHeight > 0,
              source.count == sourcePixelCount * 3 else {
            return []
        }

        // image-rs vertical_sample keeps the first pass as f32 RGBA. We only
        // need RGB here, but retaining Float until the final horizontal pass
        // is important: rounding after the vertical pass changes detector
        // pixels and is not Koharu-compatible.
        let verticalCount = sourceWidth * targetHeight * 3
        var vertical = [Float](repeating: 0, count: verticalCount)
        let verticalRatio = Float(sourceHeight) / Float(targetHeight)
        let verticalScale = max(verticalRatio, 1)
        let verticalSupport = verticalScale
        for outputY in 0..<targetHeight {
            let inputY = (Float(outputY) + 0.5) * verticalRatio
            let left = max(
                0,
                min(
                    sourceHeight - 1,
                    Int(floor(inputY - verticalSupport))
                )
            )
            let right = max(
                left + 1,
                min(
                    sourceHeight,
                    Int(ceil(inputY + verticalSupport))
                )
            )
            let kernelOrigin = inputY - 0.5
            var weights: [(index: Int, value: Float)] = []
            var weightSum: Float = 0
            for sourceY in left..<right {
                let distance = (Float(sourceY) - kernelOrigin) / verticalScale
                let value = abs(distance) < 1 ? 1 - abs(distance) : 0
                weights.append((sourceY, value))
                weightSum += value
            }
            guard weightSum > 0, weightSum.isFinite else { continue }
            for outputX in 0..<sourceWidth {
                for channel in 0..<3 {
                    var sum: Float = 0
                    for weight in weights {
                        let sourceOffset = (weight.index * sourceWidth + outputX) * 3 + channel
                        sum += Float(source[sourceOffset]) * weight.value / weightSum
                    }
                    let targetOffset = (outputY * sourceWidth + outputX) * 3 + channel
                    vertical[targetOffset] = sum
                }
            }
        }

        let targetPixelCount = targetWidth * targetHeight
        var output = [UInt8](repeating: 0, count: targetPixelCount * 3)
        let horizontalRatio = Float(sourceWidth) / Float(targetWidth)
        let horizontalScale = max(horizontalRatio, 1)
        let horizontalSupport = horizontalScale
        for outputY in 0..<targetHeight {
            for outputX in 0..<targetWidth {
                let inputX = (Float(outputX) + 0.5) * horizontalRatio
                let left = max(
                    0,
                    min(
                        sourceWidth - 1,
                        Int(floor(inputX - horizontalSupport))
                    )
                )
                let right = max(
                    left + 1,
                    min(
                        sourceWidth,
                        Int(ceil(inputX + horizontalSupport))
                    )
                )
                let kernelOrigin = inputX - 0.5
                var weights: [(index: Int, value: Float)] = []
                var weightSum: Float = 0
                for sourceX in left..<right {
                    let distance = (Float(sourceX) - kernelOrigin) / horizontalScale
                    let value = abs(distance) < 1 ? 1 - abs(distance) : 0
                    weights.append((sourceX, value))
                    weightSum += value
                }
                guard weightSum > 0, weightSum.isFinite else { continue }
                for channel in 0..<3 {
                    var sum: Float = 0
                    for weight in weights {
                        let sourceOffset = (outputY * sourceWidth + weight.index) * 3 + channel
                        sum += vertical[sourceOffset] * weight.value / weightSum
                    }
                    let rounded = sum.rounded()
                    let targetOffset = (outputY * targetWidth + outputX) * 3 + channel
                    output[targetOffset] = UInt8(
                        min(max(rounded, 0), 255)
                    )
                }
            }
        }
        return output
    }

    private static func sigmoid(_ value: Float) -> Float {
        1 / (1 + exp(-value))
    }

    /// Detector confidence is a probability only when it is finite and within
    /// the closed unit interval. Reject invalid model output before it can own
    /// a top-query slot or cross the detector/TextRegion boundary.
    private static func validDetectorConfidence(_ confidence: Float) -> Float? {
        guard confidence.isFinite, (0...1).contains(confidence) else {
            return nil
        }
        return confidence
    }

    /// Keep sorting total and deterministic even if a future merge/input path
    /// bypasses the normal detector-score validation boundary.
    private static func detectorConfidenceRank(_ confidence: Float) -> Float {
        validDetectorConfidence(confidence) ?? -.infinity
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
