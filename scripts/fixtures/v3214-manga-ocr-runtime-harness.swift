import Foundation

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
    var directionConfidence: Double
    var directionReason: String
}

@main
enum MangaOCRRuntimeHarness {
    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let blocks = try await VisionOCRService().recognizeTextBlocks(
            in: data,
            sourceLanguage: .japanese
        )
        print("blocks=\(blocks.count)")
        for block in blocks {
            print("\(block.sourceDirection.rawValue)\t\(block.original)")
        }
    }
}
