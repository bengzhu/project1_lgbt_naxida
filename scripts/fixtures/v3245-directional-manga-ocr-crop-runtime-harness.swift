import CoreGraphics
import Foundation
import ImageIO

enum SupportedLanguage: Equatable {
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

struct NormalizedImageRect {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ImageTextDirection: String {
    case horizontal
    case vertical
    case unknown
}

struct ImageTranslationBlock {
    var original: String
    var confidence: Float
    var boundingBox: NormalizedImageRect
    var sourceDirection: ImageTextDirection
    var sourceDirectionOverride: ImageTextDirection? = nil
    var directionConfidence: Double
    var directionReason: String

    var effectiveSourceDirection: ImageTextDirection {
        sourceDirectionOverride ?? sourceDirection
    }
}

@main
enum DirectionalMangaOCRCropRuntimeHarness {
    static func main() async throws {
        let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: imageURL)
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HarnessError.imageDecodeFailed
        }

        let detectorRegions = try await ComicTextBubbleDetectorService.shared
            .detectTextRegions(in: image)
        let strong = detectorRegions.filter { $0.confidence >= 0.80 }
        guard let target = strong.min(by: { $0.rect.x < $1.rect.x }) else {
            throw HarnessError.detectorRegionsMissing
        }
        let directCrop = expandedDetectorCrop(target.rect, image: image)
        let direct = try await MangaOCRService.shared.recognize(
            image: image,
            requests: [
                MangaOCRRequest(
                    textRect: target.rect,
                    cropRect: directCrop,
                    cropOrientation: .koharuVertical270
                ),
            ]
        ).first
        print("directText=\(direct?.text ?? "<missing>")")
        print("directConfidence=\(direct?.confidence ?? -.infinity)")

        let block = ImageTranslationBlock(
            original: "",
            confidence: 0,
            boundingBox: NormalizedImageRect(
                x: target.rect.x,
                y: target.rect.y,
                width: target.rect.width,
                height: target.rect.height
            ),
            sourceDirection: .unknown,
            sourceDirectionOverride: .vertical,
            directionConfidence: 1,
            directionReason: "runtime override"
        )
        guard block.effectiveSourceDirection == .vertical,
              let recognized = try await VisionOCRService().recognizeTextBlock(
                  in: data,
                  sourceLanguage: .japanese,
                  block: block
              ) else {
            throw HarnessError.recognitionMissing
        }

        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        print("batchInference=\(batchInference)")
        print("detectorRegions=\(detectorRegions.count)")
        print("effectiveDirection=\(block.effectiveSourceDirection.rawValue)")
        print("text=\(recognized.original)")
        print("confidence=\(recognized.confidence)")
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
}

private enum HarnessError: Error {
    case imageDecodeFailed
    case detectorRegionsMissing
    case recognitionMissing
}
