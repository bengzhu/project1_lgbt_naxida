import Foundation

enum ImageTextDirection {
    case horizontal
    case vertical
    case unknown
}

struct ImageTranslationBlock {
    var token: Int
    var confidence: Float
    var sourceDirection: ImageTextDirection?
    var sourceDirectionOverride: ImageTextDirection?
    var translation: String

    var effectiveSourceDirection: ImageTextDirection? {
        switch sourceDirectionOverride {
        case .horizontal, .vertical: sourceDirectionOverride
        case .unknown, .none: sourceDirection
        }
    }
}

private func block(
    _ token: Int,
    confidence: Float,
    direction: ImageTextDirection?
) -> ImageTranslationBlock {
    ImageTranslationBlock(
        token: token,
        confidence: confidence,
        sourceDirection: direction,
        sourceDirectionOverride: nil,
        translation: "translated"
    )
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func testVerticalFilterPreservesOrderAndIncludesHighConfidenceBlocks() {
    let blocks = [
        block(1, confidence: 0.98, direction: .vertical),
        block(2, confidence: 0.22, direction: .vertical),
        block(3, confidence: 0.94, direction: .horizontal),
        block(4, confidence: 0.88, direction: .unknown),
        block(5, confidence: 0.91, direction: nil),
    ]

    require(
        ImageOCRReviewFilter.vertical.blocks(from: blocks).map(\.token) == [1, 2],
        "vertical filter must preserve source order and include high-confidence vertical blocks"
    )
    require(
        ImageOCRReviewFilter.vertical.blocks(from: blocks).allSatisfy {
            $0.effectiveSourceDirection == .vertical
        },
        "vertical filter must exclude horizontal and unknown direction blocks"
    )
    require(
        ImageOCRReviewFilter.all.blocks(from: blocks).map(\.token) == [1, 2, 3, 4, 5],
        "vertical presentation filter must not change the all result"
    )
}

private func testRiskFilterSemanticsRemainUnchanged() {
    let blocks = [
        block(1, confidence: 0.98, direction: .vertical),
        block(2, confidence: 0.22, direction: .vertical),
        block(3, confidence: 0.94, direction: .horizontal),
        block(4, confidence: 0.88, direction: .unknown),
        block(5, confidence: 0.91, direction: nil),
    ]

    require(
        ImageOCRReviewFilter.needsReview.blocks(from: blocks).map(\.token) == [2, 4, 5],
        "needs-review filter must remain the low-confidence/unknown-direction union"
    )
}

@main
private struct JapaneseVerticalReviewFilterEvaluator {
    static func main() {
        testVerticalFilterPreservesOrderAndIncludesHighConfidenceBlocks()
        testRiskFilterSemanticsRemainUnchanged()
        print("v3.234 Japanese vertical review filter evaluator passed")
    }
}
