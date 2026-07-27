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
            let layoutObservations = observations.compactMap { observation -> ImageOCRLayoutObservation? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }

                let rawBox = observation.boundingBox
                let rect = ImageOCRLayoutRect(
                    x: Self.clampNormalized(Double(rawBox.origin.x)),
                    y: Self.clampNormalized(Double(1 - rawBox.origin.y - rawBox.height)),
                    width: Self.clampNormalized(Double(rawBox.width)),
                    height: Self.clampNormalized(Double(rawBox.height))
                )
                return ImageOCRLayoutObservation(
                    text: text,
                    confidence: candidate.confidence,
                    rect: rect
                )
            }
            let allowsVerticalText = sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese
            return ImageOCRLayoutEngine.layout(
                layoutObservations,
                allowsVerticalText: allowsVerticalText
            ).map { block in
                ImageTranslationBlock(
                    original: block.text,
                    confidence: block.confidence,
                    boundingBox: NormalizedImageRect(
                        x: block.rect.x,
                        y: block.rect.y,
                        width: block.rect.width,
                        height: block.rect.height
                    ),
                    sourceDirection: ImageTextDirection(rawValue: block.direction.rawValue) ?? .unknown,
                    directionConfidence: block.directionConfidence,
                    directionReason: block.directionReason
                )
            }
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
}
