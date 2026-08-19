import CoreGraphics
import Foundation
import ImageIO

enum SupportedLanguage: Equatable, Sendable {
    case japanese
    case simplifiedChinese

    var visionRecognitionLanguageIdentifiers: [String] {
        switch self {
        case .japanese:
            ["ja-JP", "ja", "en-US", "en"]
        case .simplifiedChinese:
            ["zh-Hans", "zh-CN", "en-US", "en"]
        }
    }
}

struct NormalizedImageRect: Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ImageTextDirection: String, Sendable {
    case horizontal
    case vertical
    case unknown
}

struct ImageTranslationBlock: Sendable {
    var original: String
    var confidence: Float
    var boundingBox: NormalizedImageRect
    var sourceDirection: ImageTextDirection
    var sourceDirectionOverride: ImageTextDirection? = nil
    var directionConfidence: Double
    var directionReason: String
    var ocrProvenance: ImageOCRBlockProvenance? = nil

    var effectiveSourceDirection: ImageTextDirection {
        sourceDirectionOverride ?? sourceDirection
    }
}

@main
enum MangaOCRBBoxPrimaryRuntimeHarness {
    static func main() async throws {
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HarnessError.imageDecodeFailed
        }
        let detectorRegions = try await ComicTextBubbleDetectorService.shared.detectTextRegions(
            in: image
        )
        let strong = detectorRegions.filter { $0.confidence >= 0.80 }
        guard let target = strong.min(by: { $0.rect.x < $1.rect.x }),
              let distractor = strong
                .filter({ $0.rect.x > 0.70 && $0.rect.y < 0.40 })
                .min(by: { $0.rect.y < $1.rect.y }) else {
            throw HarnessError.detectorRegionsMissing
        }

        let targetCrop = expandedDetectorCrop(target.rect, image: image)
        let distractorCrop = expandedDetectorCrop(distractor.rect, image: image)
        let distractorQuad = quad(for: distractorCrop)
        let targetResults = try await MangaOCRService.shared.recognize(
            image: image,
            requests: [MangaOCRRequest(textRect: target.rect, cropRect: targetCrop)]
        )
        let distractorResults = try await MangaOCRService.shared.recognize(
            image: image,
            requests: [MangaOCRRequest(textRect: distractor.rect, cropRect: distractorCrop)]
        )
        let adversarialResults = try await MangaOCRService.shared.recognize(
            image: image,
            requests: [
                MangaOCRRequest(
                    textRect: target.rect,
                    cropRect: targetCrop,
                    cropQuad: distractorQuad
                ),
            ]
        )
        guard let targetResult = targetResults.first,
              let distractorResult = distractorResults.first,
              let adversarialResult = adversarialResults.first else {
            throw HarnessError.recognitionMissing
        }

        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        print("batchInference=\(batchInference)")
        print("detectorRegions=\(detectorRegions.count)")
        print("targetConfidence=\(targetResult.confidence)")
        print("targetText=\(targetResult.text)")
        print("distractorConfidence=\(distractorResult.confidence)")
        print("distractorText=\(distractorResult.text)")
        print("adversarialConfidence=\(adversarialResult.confidence)")
        print("adversarialText=\(adversarialResult.text)")
    }

    private static func expandedDetectorCrop(
        _ rect: ImageOCRLayoutRect,
        image: CGImage
    ) -> ImageOCRLayoutRect {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        let fontPixels = max(
            min(rect.width * imageWidth, rect.height * imageHeight),
            1
        )
        let basePadding = max(fontPixels * 0.08, 2)
        let horizontalPadding = max(fontPixels * 0.18, basePadding) / imageWidth
        let verticalPadding = max(fontPixels * 0.12, basePadding) / imageHeight
        return ImageOCRLayoutRect(
            x: rect.x - horizontalPadding,
            y: rect.y - verticalPadding,
            width: rect.width + horizontalPadding * 2,
            height: rect.height + verticalPadding * 2
        ).normalizedToUnit() ?? rect
    }

    private static func quad(for rect: ImageOCRLayoutRect) -> ImageOCRLayoutQuad {
        ImageOCRLayoutQuad(points: [
            ImageOCRLayoutPoint(x: rect.x, y: rect.y),
            ImageOCRLayoutPoint(x: rect.maxX, y: rect.y),
            ImageOCRLayoutPoint(x: rect.maxX, y: rect.maxY),
            ImageOCRLayoutPoint(x: rect.x, y: rect.maxY),
        ])
    }
}

private enum HarnessError: Error {
    case imageDecodeFailed
    case detectorRegionsMissing
    case recognitionMissing
}
