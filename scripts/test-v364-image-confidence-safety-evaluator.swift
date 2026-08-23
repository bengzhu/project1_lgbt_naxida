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

private func block(_ confidence: Float) -> ImageTranslationBlock {
    ImageTranslationBlock(
        translation: "",
        confidence: confidence,
        sourceDirection: .horizontal,
        sourceDirectionOverride: nil
    )
}

private func testInvalidConfidenceFallsBackToReviewableZero() {
    let summary = ImageOCRResultSummary(blocks: [
        block(.nan),
        block(.infinity),
        block(-.infinity),
        block(-0.2),
        block(1.4)
    ])

    require(summary.averageConfidence?.isFinite == true, "average confidence must remain finite")
    require(summary.averageConfidence == 0, "invalid confidence must normalize to zero")
    require(summary.lowConfidenceBlockCount == 5, "invalid confidence must remain reviewable")
    require(ImageOCRResultSummary.normalizedConfidence(.nan) == 0, "NaN must normalize to zero")
    require(ImageOCRResultSummary.normalizedConfidence(.infinity) == 0, "infinity must normalize to zero")
    require(ImageOCRResultSummary.normalizedConfidence(-0.2) == 0, "negative confidence must normalize to zero")
    require(ImageOCRResultSummary.normalizedConfidence(1.4) == 0, "oversized confidence must normalize to zero")
}

@main
private struct ImageConfidenceSafetyEvaluator {
    static func main() {
        testInvalidConfidenceFallsBackToReviewableZero()
        print("v3.64 image confidence safety evaluator passed")
    }
}
