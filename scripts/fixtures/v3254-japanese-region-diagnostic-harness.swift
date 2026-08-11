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

private struct DiagnosticRecognition {
    let text: String
    let confidence: Float

    var japaneseDensity: Double {
        guard !text.isEmpty else { return 0 }
        let japanese = text.unicodeScalars.reduce(into: 0) { count, scalar in
            switch scalar.value {
            case 0x3041...0x3096, 0x30A1...0x30FA, 0x30FD...0x30FF,
                 0x3400...0x4DBF, 0x4E00...0x9FFF:
                count += 1
            default:
                break
            }
        }
        let scalarCount = text.unicodeScalars.count
        return scalarCount == 0 ? 0 : Double(japanese) / Double(scalarCount)
    }
}

private enum DiagnosticOrientation: String {
    case natural
    case rotate90
    case rotate270
}

@main
enum JapaneseRegionDiagnosticHarness {
    static func main() async throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(
                domain: "JapaneseRegionDiagnosticHarness",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "image path is required"]
            )
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(
                domain: "JapaneseRegionDiagnosticHarness",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "image decode failed"]
            )
        }

        let detectorRegions = try await ComicTextBubbleDetectorService.shared
            .detectTextRegions(in: image)
        let boundedRegions = Array(detectorRegions.prefix(12))
        let pixelRegions = VisionOCRService.diagnosticJapanesePixelFirstRegions(in: image)
        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        print("batchInference=\(batchInference)")
        print("detectorRegions=\(detectorRegions.count)")
        print("diagnosticRegions=\(boundedRegions.count)")
        print("pixelFirstRegions=\(pixelRegions.count)")
        for (index, region) in pixelRegions.enumerated() {
            print(
                "pixelRegion=\(index) x=\(format(region.rect.x)) y=\(format(region.rect.y)) "
                    + "w=\(format(region.rect.width)) h=\(format(region.rect.height)) "
                    + "rotation=\(region.detectorRotation) chars=\(region.characterCount) "
                    + "compact=\(region.isCompactCandidate)"
            )
        }
        if let tallImage = makeTallImage(image, copies: 4) {
            let longPixelRegions = VisionOCRService
                .diagnosticJapanesePixelFirstRegions(in: tallImage)
            let compactLongRegions = longPixelRegions.filter(\.isCompactCandidate)
            print("longPixelFirstRegions=\(longPixelRegions.count)")
            print("longCompactPixelRegions=\(compactLongRegions.count)")
            for (index, region) in compactLongRegions.enumerated() {
                print(
                    "longCompact=\(index) x=\(format(region.rect.x)) "
                        + "y=\(format(region.rect.y)) w=\(format(region.rect.width)) "
                        + "h=\(format(region.rect.height)) rotation=\(region.detectorRotation) "
                        + "chars=\(region.characterCount)"
                )
            }
            for (index, read) in VisionOCRService
                .diagnosticJapaneseCompactCropReads(in: tallImage)
                .enumerated() {
                print(
                    "longCompactRead=\(index) x=\(format(read.rect.x)) "
                        + "y=\(format(read.rect.y)) angle=\(read.angle) "
                    + "text=\(escaped(read.text)) confidence=\(format(read.confidence))"
                )
            }
            let longData = try encodePNG(tallImage)
            let longBlocks = try await VisionOCRService().recognizeTextBlocks(
                in: longData,
                sourceLanguage: .japanese
            )
            print("longBlocks=\(longBlocks.count)")
            for (index, block) in longBlocks.sorted(by: blockOrder).enumerated() {
                print(
                    "longBlock=\(index) x=\(format(block.boundingBox.x)) "
                        + "y=\(format(block.boundingBox.y)) "
                        + "w=\(format(block.boundingBox.width)) "
                        + "h=\(format(block.boundingBox.height)) "
                        + "direction=\(block.sourceDirection.rawValue) "
                        + "text=\(escaped(block.original))"
                )
            }
        }
        for (index, region) in boundedRegions.enumerated() {
            let rect = region.rect
            let pixelWidth = Double(image.width) * rect.width
            let pixelHeight = Double(image.height) * rect.height
            let rotates270 = pixelHeight > pixelWidth * 1.75
            print(
                "region=\(index) x=\(format(rect.x)) y=\(format(rect.y)) "
                    + "w=\(format(rect.width)) h=\(format(rect.height)) "
                    + "detectorConfidence=\(format(region.confidence)) "
                    + "rotate270Applied=\(rotates270)"
            )

            for orientation in [
                DiagnosticOrientation.natural,
                DiagnosticOrientation.rotate90,
                DiagnosticOrientation.rotate270
            ] {
                let recognition = try await recognize(
                    image: image,
                    rect: rect,
                    orientation: orientation
                )
                let result = recognition ?? DiagnosticRecognition(text: "", confidence: 0)
                print(
                    "region=\(index) \(orientation.rawValue)Text=\(escaped(result.text)) "
                        + "\(orientation.rawValue)Confidence=\(format(result.confidence)) "
                        + "\(orientation.rawValue)JapaneseDensity=\(format(result.japaneseDensity))"
                )
            }
        }
    }

    private static func recognize(
        image: CGImage,
        rect: ImageOCRLayoutRect,
        orientation: DiagnosticOrientation
    ) async throws -> DiagnosticRecognition? {
        switch orientation {
        case .natural:
            let request = MangaOCRRequest(
                textRect: rect,
                cropRect: rect,
                cropOrientation: .natural
            )
            return try await MangaOCRService.shared
                .recognize(image: image, requests: [request])
                .first
                .map { DiagnosticRecognition(text: $0.text, confidence: $0.confidence) }
        case .rotate270:
            let request = MangaOCRRequest(
                textRect: rect,
                cropRect: rect,
                cropOrientation: .koharuVertical270
            )
            return try await MangaOCRService.shared
                .recognize(image: image, requests: [request])
                .first
                .map { DiagnosticRecognition(text: $0.text, confidence: $0.confidence) }
        case .rotate90:
            guard let crop = cropImage(image, normalizedRect: rect),
                  let rotated = rotateImage90(crop) else {
                return nil
            }
            let unit = ImageOCRLayoutRect(x: 0, y: 0, width: 1, height: 1)
            let request = MangaOCRRequest(
                textRect: unit,
                cropRect: unit,
                cropOrientation: .natural
            )
            return try await MangaOCRService.shared
                .recognize(image: rotated, requests: [request])
                .first
                .map { DiagnosticRecognition(text: $0.text, confidence: $0.confidence) }
        }
    }

    private static func cropImage(
        _ image: CGImage,
        normalizedRect: ImageOCRLayoutRect
    ) -> CGImage? {
        guard let rect = normalizedRect.normalizedToUnit() else { return nil }
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        let pixels = CGRect(
            x: rect.x * bounds.width,
            y: rect.y * bounds.height,
            width: rect.width * bounds.width,
            height: rect.height * bounds.height
        )
        .integral
        .intersection(bounds)
        guard pixels.width >= 2, pixels.height >= 2 else { return nil }
        return image.cropping(to: pixels)
    }

    private static func rotateImage90(_ image: CGImage) -> CGImage? {
        let outputWidth = image.height
        let outputHeight = image.width
        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.translateBy(x: CGFloat(outputWidth), y: 0)
        context.rotate(by: .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }

    private static func makeTallImage(_ image: CGImage, copies: Int) -> CGImage? {
        guard copies > 0,
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height * copies,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .none
        for copy in 0..<copies {
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
        return context.makeImage()
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw NSError(
                domain: "JapaneseRegionDiagnosticHarness",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "image encoder unavailable"]
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(
                domain: "JapaneseRegionDiagnosticHarness",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "image encoding failed"]
            )
        }
        return encoded as Data
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

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func format<T: BinaryFloatingPoint>(_ value: T) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
    }
}
