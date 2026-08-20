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
enum LongPageMangaOCRRuntimeHarness {
    private static let sourceCopies = 4

    static func main() async throws {
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HarnessError.imageDecodeFailed
        }
        let tallHeight = image.height * sourceCopies
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: tallHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw HarnessError.imageRenderFailed
        }
        context.interpolationQuality = .none
        for copy in 0..<sourceCopies {
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: copy * image.height,
                    width: image.width,
                    height: image.height
                )
            )
        }
        guard let tallImage = context.makeImage() else {
            throw HarnessError.imageRenderFailed
        }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw HarnessError.imageEncodeFailed
        }
        CGImageDestinationAddImage(destination, tallImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageEncodeFailed
        }

        let blocks = try await VisionOCRService().recognizeTextBlocks(
            in: encoded as Data,
            sourceLanguage: .japanese
        )
        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        print("batchInference=\(batchInference)")
        print("copies=\(sourceCopies)")
        print("image=\(tallImage.width)x\(tallImage.height)")
        print("blocks=\(blocks.count)")
        for block in blocks.sorted(by: blockOrder) {
            print(
                String(
                    format: "block=%.6f,%.6f,%.6f,%.6f direction=%@ text=%@",
                    block.boundingBox.x,
                    block.boundingBox.y,
                    block.boundingBox.width,
                    block.boundingBox.height,
                    block.sourceDirection.rawValue,
                    block.original
                )
            )
        }
    }

    private static func blockOrder(
        _ left: ImageTranslationBlock,
        _ right: ImageTranslationBlock
    ) -> Bool {
        if left.boundingBox.y != right.boundingBox.y {
            return left.boundingBox.y < right.boundingBox.y
        }
        return left.boundingBox.x > right.boundingBox.x
    }
}

private enum HarnessError: Error {
    case imageDecodeFailed
    case imageRenderFailed
    case imageEncodeFailed
}
