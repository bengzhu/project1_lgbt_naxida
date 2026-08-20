import CoreGraphics
import Foundation
import ImageIO

enum SupportedLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case englishUS = "英语(美国)"
    case simplifiedChinese = "简体中文"
    case japanese = "日语"
    case french = "法语"
    case german = "德语"

    var id: String { rawValue }

    var visionRecognitionLanguageIdentifiers: [String] {
        switch self {
        case .englishUS:
            ["en-US", "en"]
        case .japanese:
            ["ja-JP", "ja", "en-US", "en"]
        case .simplifiedChinese:
            ["zh-Hans", "zh-CN", "en-US", "en"]
        case .french:
            ["fr-FR", "fr", "en-US", "en"]
        case .german:
            ["de-DE", "de", "en-US", "en"]
        }
    }
}

struct NormalizedImageRect: Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    func normalizedToUnit() -> Self? {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        let right = x + width
        let bottom = y + height
        guard right.isFinite, bottom.isFinite else { return nil }
        let left = min(max(x, 0), 1)
        let clippedRight = min(max(right, 0), 1)
        let top = min(max(y, 0), 1)
        let clippedBottom = min(max(bottom, 0), 1)
        guard clippedRight > left, clippedBottom > top else { return nil }
        return Self(
            x: left,
            y: top,
            width: clippedRight - left,
            height: clippedBottom - top
        )
    }
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
    var textKind: TranslationTextKind? = nil
    var ocrProvenance: ImageOCRBlockProvenance? = nil

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
        emit("directText=\(direct?.text ?? "<missing>")")
        emit("directConfidence=\(direct?.confidence ?? -.infinity)")

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
        var horizontalBlock = block
        horizontalBlock.sourceDirectionOverride = .horizontal
        guard horizontalBlock.effectiveSourceDirection == .horizontal,
              let horizontalRecognized = try await VisionOCRService().recognizeTextBlock(
                  in: data,
                  sourceLanguage: .japanese,
                  block: horizontalBlock
              ) else {
            throw HarnessError.horizontalRecognitionMissing
        }

        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        emit("batchInference=\(batchInference)")
        emit("detectorRegions=\(detectorRegions.count)")
        emit("effectiveDirection=\(block.effectiveSourceDirection.rawValue)")
        emit("text=\(recognized.original)")
        emit("confidence=\(recognized.confidence)")
        emit("horizontalDirection=\(horizontalBlock.effectiveSourceDirection.rawValue)")
        emit("horizontalText=\(horizontalRecognized.original)")
        emit("horizontalConfidence=\(horizontalRecognized.confidence)")
    }

    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
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
    case horizontalRecognitionMissing
}
