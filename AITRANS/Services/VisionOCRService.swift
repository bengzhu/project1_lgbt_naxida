import Foundation
import ImageIO
import Vision

enum VisionOCRServiceError: LocalizedError {
    case imageDecodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "无法解码图片，请选择 PNG、JPEG 或系统支持的图片格式"
        }
    }
}

struct VisionOCRService: Sendable {
    func recognizeTextBlocks(in imageData: Data, sourceLanguage: SupportedLanguage) async throws -> [ImageTranslationBlock] {
        let task = Task.detached(priority: .userInitiated) {
            let ocrImage = try Self.makeOCRImage(from: imageData)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.012

            let supportedLanguages = (try? request.supportedRecognitionLanguages()) ?? []
            let preferredLanguages = sourceLanguage.visionRecognitionLanguageIdentifiers.filter { supportedLanguages.contains($0) }
            if !preferredLanguages.isEmpty {
                request.recognitionLanguages = preferredLanguages
            }

            let handler = VNImageRequestHandler(cgImage: ocrImage, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = observations.compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }

                let rawBox = observation.boundingBox
                return OCRLine(
                    text: text,
                    confidence: candidate.confidence,
                    rect: NormalizedImageRect(
                        x: Self.clampNormalized(Double(rawBox.origin.x)),
                        y: Self.clampNormalized(Double(1 - rawBox.origin.y - rawBox.height)),
                        width: Self.clampNormalized(Double(rawBox.width)),
                        height: Self.clampNormalized(Double(rawBox.height))
                    )
                )
            }
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.rect.y - rhs.rect.y)
                if yDelta > 0.02 {
                    return lhs.rect.y < rhs.rect.y
                }
                return lhs.rect.x < rhs.rect.x
            }

            return Self.clusterLinesIntoBlocks(lines)
        }

        return try await task.value
    }

    private static func makeOCRImage(from imageData: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw VisionOCRServiceError.imageDecodeFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_800
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VisionOCRServiceError.imageDecodeFailed
        }

        return image
    }

    private static func clampNormalized(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func clusterLinesIntoBlocks(_ lines: [OCRLine]) -> [ImageTranslationBlock] {
        var clusters: [OCRCluster] = []

        for line in lines {
            if let lastIndex = clusters.indices.last, shouldMerge(line, into: clusters[lastIndex]) {
                clusters[lastIndex].append(line)
            } else {
                clusters.append(OCRCluster(line: line))
            }
        }

        return clusters.map { cluster in
            ImageTranslationBlock(
                original: cluster.mergedText,
                confidence: cluster.averageConfidence,
                boundingBox: cluster.rect
            )
        }
    }

    private static func shouldMerge(_ line: OCRLine, into cluster: OCRCluster) -> Bool {
        let rect = cluster.rect
        let lineBottom = line.rect.y + line.rect.height
        let clusterBottom = rect.y + rect.height
        let verticalGap = line.rect.y - clusterBottom
        let averageHeight = max((line.rect.height + rect.height) / 2, 0.012)
        let sameBand = abs(line.rect.y - rect.y) <= averageHeight * 0.55
        let closeVertically = verticalGap <= max(0.018, averageHeight * 0.90)

        guard sameBand || closeVertically else {
            return false
        }

        let overlap = horizontalOverlap(line.rect, rect)
        let narrowerWidth = max(min(line.rect.width, rect.width), 0.001)
        let overlapRatio = overlap / narrowerWidth
        let centerDistance = abs(line.rect.midX - rect.midX)
        let lineTouchesClusterVertically = lineBottom >= rect.y - 0.01 && line.rect.y <= clusterBottom + 0.035

        return lineTouchesClusterVertically && (overlapRatio > 0.18 || centerDistance < 0.26)
    }

    private static func horizontalOverlap(_ lhs: NormalizedImageRect, _ rhs: NormalizedImageRect) -> Double {
        max(0, min(lhs.maxX, rhs.maxX) - max(lhs.x, rhs.x))
    }
}

private struct OCRLine: Sendable {
    var text: String
    var confidence: Float
    var rect: NormalizedImageRect
}

private struct OCRCluster: Sendable {
    private(set) var lines: [OCRLine]
    private(set) var rect: NormalizedImageRect

    init(line: OCRLine) {
        self.lines = [line]
        self.rect = line.rect
    }

    mutating func append(_ line: OCRLine) {
        lines.append(line)
        rect = rect.union(line.rect)
    }

    var mergedText: String {
        var output = ""
        var previous: OCRLine?

        for line in lines {
            if let previous {
                let sameLine = abs(previous.rect.y - line.rect.y) <= max(previous.rect.height, line.rect.height) * 0.50
                output += sameLine ? " " : "\n"
            }
            output += line.text
            previous = line
        }

        return output
    }

    var averageConfidence: Float {
        guard !lines.isEmpty else { return 0 }
        let total = lines.reduce(Float(0)) { $0 + $1.confidence }
        return total / Float(lines.count)
    }
}

private extension NormalizedImageRect {
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }

    func union(_ other: NormalizedImageRect) -> NormalizedImageRect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(self.maxX, other.maxX)
        let maxY = max(self.maxY, other.maxY)
        return NormalizedImageRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}
