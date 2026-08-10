import Foundation

enum ImageTextDirection {
    case horizontal
    case vertical
    case unknown
}

struct ImageTranslationBlock {
    var translation: String
    var confidence: Float
    var sourceDirection: ImageTextDirection?
    var sourceDirectionOverride: ImageTextDirection?

    var effectiveSourceDirection: ImageTextDirection? {
        switch sourceDirectionOverride {
        case .horizontal, .vertical: sourceDirectionOverride
        case .unknown, .none: sourceDirection
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func block(
    confidence: Float,
    translation: String = "",
    direction: ImageTextDirection? = nil
) -> ImageTranslationBlock {
    ImageTranslationBlock(
        translation: translation,
        confidence: confidence,
        sourceDirection: direction,
        sourceDirectionOverride: nil
    )
}

private func testEmptySummary() {
    let summary = ImageOCRResultSummary(blocks: [])
    require(summary.totalBlockCount == 0, "empty input must have no blocks")
    require(summary.averageConfidence == nil, "empty input must not invent confidence")
    require(summary.lowConfidenceBlockCount == 0, "empty input must not report low confidence")
}

private func testConfidenceAndTranslationSummary() {
    let summary = ImageOCRResultSummary(blocks: [
        block(confidence: -0.2, translation: "translated", direction: .horizontal),
        block(confidence: 0.5, direction: .vertical),
        block(confidence: 1.4, translation: "translated", direction: .unknown),
        block(confidence: 0.25)
    ])

    require(summary.totalBlockCount == 4, "all blocks must be counted")
    require(summary.translatedBlockCount == 2, "only non-empty translations count")
    require(summary.averageConfidence == 0.4375, "confidence must be clamped before averaging")
    require(summary.lowConfidenceBlockCount == 2, "threshold is strict and excludes exactly 50 percent")
}

private func testDirectionPartition() {
    let summary = ImageOCRResultSummary(blocks: [
        block(confidence: 0.9, direction: .horizontal),
        block(confidence: 0.9, direction: .vertical),
        block(confidence: 0.9, direction: .unknown),
        block(confidence: 0.9)
    ])

    require(summary.horizontalBlockCount == 1, "horizontal evidence must remain distinct")
    require(summary.verticalBlockCount == 1, "vertical evidence must remain distinct")
    require(summary.unknownDirectionBlockCount == 2, "nil and unknown directions share fallback accounting")
}

@main
private struct ImageOCRRerunEvaluator {
    static func main() {
        testEmptySummary()
        testConfidenceAndTranslationSummary()
        testDirectionPartition()
        print("v3.0 image OCR rerun evaluator passed")
    }
}
