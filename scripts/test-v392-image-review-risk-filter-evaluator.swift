import Foundation

enum ImageTextDirection {
    case horizontal
    case vertical
    case unknown
}

struct ImageTranslationBlock {
    var confidence: Float
    var sourceDirection: ImageTextDirection?
    var translation: String
}

private func block(_ confidence: Float, _ direction: ImageTextDirection?) -> ImageTranslationBlock {
    ImageTranslationBlock(confidence: confidence, sourceDirection: direction, translation: "translated")
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testRiskFiltersPreserveSourceOrderAndOverlap() {
    let blocks = [
        block(0.49, .horizontal),
        block(0.91, .unknown),
        block(0.20, nil),
        block(0.80, .vertical),
        block(0.50, .horizontal)
    ]

    require(
        ImageOCRReviewFilter.all.blocks(from: blocks).map(\.confidence) == [0.49, 0.91, 0.20, 0.80, 0.50],
        "all filter must preserve every block and source order"
    )
    require(
        ImageOCRReviewFilter.lowConfidence.blocks(from: blocks).map(\.confidence) == [0.49, 0.20],
        "low-confidence filter must use the product threshold"
    )
    require(
        ImageOCRReviewFilter.unknownDirection.blocks(from: blocks).map(\.confidence) == [0.91, 0.20],
        "unknown-direction filter must include nil and unknown direction"
    )
    require(
        ImageOCRReviewFilter.needsReview.blocks(from: blocks).map(\.confidence) == [0.49, 0.91, 0.20],
        "needs-review filter must remain the union of both risks"
    )
}

private func testThresholdBoundaryRemainsStrict() {
    let boundary = block(0.50, .horizontal)
    require(
        ImageOCRReviewFilter.lowConfidence.blocks(from: [boundary]).isEmpty,
        "exactly 50 percent must not be classified as low confidence"
    )
}

@main
private struct ImageReviewRiskFilterEvaluator {
    static func main() {
        testRiskFiltersPreserveSourceOrderAndOverlap()
        testThresholdBoundaryRemainsStrict()
        print("v3.92 image review risk filter evaluator passed")
    }
}
