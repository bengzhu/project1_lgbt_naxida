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
enum MangaOCRQuadBBoxFallbackRuntimeHarness {
    static func main() async throws {
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HarnessError.imageDecodeFailed
        }
        let detectorRegions = try await ComicTextBubbleDetectorService.shared.detectTextRegions(
            in: image
        )
        guard let detectorRegion = detectorRegions.max(by: {
            $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height
        }) else {
            throw HarnessError.detectorReturnedNoText
        }
        let composite = try makeComposite(with: image)
        let detectorCrop = mappedDetectorCrop(
            detectorRegion.rect,
            sourceImage: image,
            compositeImage: composite
        )
        let blankRect = ImageOCRLayoutRect(
            x: 0.08,
            y: 0.18,
            width: 0.34,
            height: 0.64
        )
        let detectorQuad = ImageOCRLayoutQuad(points: [
            ImageOCRLayoutPoint(x: detectorCrop.x, y: detectorCrop.y),
            ImageOCRLayoutPoint(x: detectorCrop.maxX, y: detectorCrop.y),
            ImageOCRLayoutPoint(x: detectorCrop.maxX, y: detectorCrop.maxY),
            ImageOCRLayoutPoint(x: detectorCrop.x, y: detectorCrop.maxY),
        ])

        let blankResults = try await MangaOCRService.shared.recognize(
            image: composite,
            requests: [
                MangaOCRRequest(textRect: blankRect, cropRect: blankRect),
            ]
        )
        let fallbackResults = try await MangaOCRService.shared.recognize(
            image: composite,
            requests: [
                MangaOCRRequest(
                    textRect: detectorCrop,
                    cropRect: blankRect,
                    cropQuad: detectorQuad,
                    cropQuadIsVertical: false
                ),
            ]
        )
        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        print("batchInference=\(batchInference)")
        print("detectorRegions=\(detectorRegions.count)")
        print("blankResults=\(blankResults.count)")
        for result in blankResults {
            print("blankConfidence=\(result.confidence)")
            print("blankText=\(result.text)")
        }
        print("fallbackResults=\(fallbackResults.count)")
        for result in fallbackResults {
            print("fallbackConfidence=\(result.confidence)")
            print("fallbackText=\(result.text)")
        }
    }

    private static func makeComposite(with image: CGImage) throws -> CGImage {
        let width = image.width * 2
        guard let context = CGContext(
            data: nil,
            width: width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw HarnessError.imageRenderFailed
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: image.height))
        context.draw(
            image,
            in: CGRect(
                x: image.width,
                y: 0,
                width: image.width,
                height: image.height
            )
        )
        guard let composite = context.makeImage() else {
            throw HarnessError.imageRenderFailed
        }
        return composite
    }

    private static func mappedDetectorCrop(
        _ rect: ImageOCRLayoutRect,
        sourceImage: CGImage,
        compositeImage: CGImage
    ) -> ImageOCRLayoutRect {
        let sourceWidth = Double(sourceImage.width)
        let sourceHeight = Double(sourceImage.height)
        let fontPixels = max(
            min(rect.width * sourceWidth, rect.height * sourceHeight),
            1
        )
        let basePadding = max(fontPixels * 0.08, 2)
        let horizontalPadding = max(fontPixels * 0.18, basePadding) / sourceWidth
        let verticalPadding = max(fontPixels * 0.12, basePadding) / sourceHeight
        let expanded = ImageOCRLayoutRect(
            x: rect.x - horizontalPadding,
            y: rect.y - verticalPadding,
            width: rect.width + horizontalPadding * 2,
            height: rect.height + verticalPadding * 2
        ).normalizedToUnit() ?? rect
        let widthScale = sourceWidth / Double(compositeImage.width)
        return ImageOCRLayoutRect(
            x: 0.5 + expanded.x * widthScale,
            y: expanded.y,
            width: expanded.width * widthScale,
            height: expanded.height
        )
    }
}

private enum HarnessError: Error {
    case imageDecodeFailed
    case imageRenderFailed
    case detectorReturnedNoText
}
