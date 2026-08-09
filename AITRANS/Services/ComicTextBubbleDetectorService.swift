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

        return Self.mergeTextRegions(detections).map {
            ComicTextDetectorRegion(rect: $0.rect, confidence: $0.confidence)
        }
        .sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }
            return $0.rect.x > $1.rect.x
        }
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
                remaining.remove(at: index)
            }
            merged.append(candidate)
        }
        return merged
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
