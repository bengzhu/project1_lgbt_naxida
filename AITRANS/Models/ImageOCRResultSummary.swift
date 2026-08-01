import Foundation

struct ImageOCRResultSummary: Equatable, Sendable {
    static let lowConfidenceThreshold: Float = 0.5

    var totalBlockCount: Int
    var translatedBlockCount: Int
    var averageConfidence: Double?
    var lowConfidenceBlockCount: Int
    var horizontalBlockCount: Int
    var verticalBlockCount: Int
    var unknownDirectionBlockCount: Int
    var reviewRequiredBlockCount: Int

    init(
        blocks: [ImageTranslationBlock],
        lowConfidenceThreshold: Float = Self.lowConfidenceThreshold
    ) {
        let confidences = blocks.map { Double(Self.normalizedConfidence($0.confidence)) }

        totalBlockCount = blocks.count
        translatedBlockCount = blocks.count(where: { !$0.translation.isEmpty })
        averageConfidence = confidences.isEmpty
            ? nil
            : confidences.reduce(0, +) / Double(confidences.count)
        lowConfidenceBlockCount = blocks.count(where: {
            Self.hasLowConfidence($0, lowConfidenceThreshold: lowConfidenceThreshold)
        })
        horizontalBlockCount = blocks.count(where: { $0.sourceDirection == .horizontal })
        verticalBlockCount = blocks.count(where: { $0.sourceDirection == .vertical })
        unknownDirectionBlockCount = blocks.count(where: {
            $0.sourceDirection == nil || $0.sourceDirection == .unknown
        })
        reviewRequiredBlockCount = blocks.count(where: {
            Self.requiresReview($0, lowConfidenceThreshold: lowConfidenceThreshold)
        })
    }

    static func requiresReview(
        _ block: ImageTranslationBlock,
        lowConfidenceThreshold: Float = Self.lowConfidenceThreshold
    ) -> Bool {
        hasLowConfidence(block, lowConfidenceThreshold: lowConfidenceThreshold) || hasUnknownDirection(block)
    }

    static func hasLowConfidence(
        _ block: ImageTranslationBlock,
        lowConfidenceThreshold: Float = Self.lowConfidenceThreshold
    ) -> Bool {
        let threshold = normalizedConfidence(lowConfidenceThreshold)
        let confidence = normalizedConfidence(block.confidence)
        return confidence < threshold
    }

    static func normalizedConfidence(_ rawConfidence: Float) -> Float {
        guard rawConfidence.isFinite else { return 0 }
        return min(max(rawConfidence, 0), 1)
    }

    static func hasUnknownDirection(_ block: ImageTranslationBlock) -> Bool {
        block.sourceDirection == nil || block.sourceDirection == .unknown
    }

}
