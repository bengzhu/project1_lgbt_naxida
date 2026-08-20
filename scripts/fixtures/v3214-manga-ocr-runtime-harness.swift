import Foundation

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
enum MangaOCRRuntimeHarness {
    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let blocks = try await VisionOCRService().recognizeTextBlocks(
            in: data,
            sourceLanguage: .japanese
        )
        let batchInference = try await MangaOCRService.shared.batchInferenceEnabled()
        print("batchInference=\(batchInference)")
        print("blocks=\(blocks.count)")
        for block in blocks {
            print("\(block.sourceDirection.rawValue)\t\(block.original)")
        }
    }
}
