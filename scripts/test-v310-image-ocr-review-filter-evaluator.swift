import Foundation

enum ImageTextDirection {
    case horizontal
    case vertical
    case unknown
}

struct ImageTranslationBlock {
    var token: Int
    var translation: String
    var confidence: Float
    var sourceDirection: ImageTextDirection?
}

private func block(
    _ token: Int,
    confidence: Float,
    direction: ImageTextDirection?,
    translation: String = "translated"
) -> ImageTranslationBlock {
    ImageTranslationBlock(
        token: token,
        translation: translation,
        confidence: confidence,
        sourceDirection: direction
    )
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testReviewUnionAndStableOrder() {
    let blocks = [
        block(1, confidence: 0.49, direction: .horizontal),
        block(2, confidence: 0.91, direction: .unknown),
        block(3, confidence: 0.20, direction: nil),
        block(4, confidence: 0.50, direction: .horizontal),
        block(5, confidence: 0.92, direction: .vertical)
    ]
    let summary = ImageOCRResultSummary(blocks: blocks)
    let reviewBlocks = ImageOCRReviewFilter.needsReview.blocks(from: blocks)

    require(summary.lowConfidenceBlockCount == 2, "strict threshold must exclude exactly 50 percent")
    require(summary.unknownDirectionBlockCount == 2, "nil and unknown directions must be counted")
    require(summary.reviewRequiredBlockCount == 3, "overlapping risks must count once")
    require(reviewBlocks.map(\.token) == [1, 2, 3], "review filtering must preserve source order")
    require(ImageOCRReviewFilter.all.blocks(from: blocks).map(\.token) == [1, 2, 3, 4, 5], "all must not filter")
}

private func testClampedThresholdAndConfidence() {
    let horizontal = block(1, confidence: 0.99, direction: .horizontal)
    let overRange = block(2, confidence: 1.5, direction: .horizontal)
    let unknown = block(3, confidence: 1.0, direction: nil)

    require(
        !ImageOCRResultSummary.hasLowConfidence(horizontal, lowConfidenceThreshold: -1),
        "negative threshold must clamp to zero"
    )
    require(
        ImageOCRResultSummary.hasLowConfidence(horizontal, lowConfidenceThreshold: 2),
        "threshold above one must clamp to one"
    )
    require(
        !ImageOCRResultSummary.hasLowConfidence(overRange, lowConfidenceThreshold: 2),
        "confidence above one must clamp to one"
    )
    require(ImageOCRResultSummary.hasUnknownDirection(unknown), "nil direction must require review")
}

@main
private struct ImageOCRReviewFilterEvaluator {
    static func main() {
        testReviewUnionAndStableOrder()
        testClampedThresholdAndConfidence()
        print("v3.1 image OCR review filter evaluator passed")
    }
}
