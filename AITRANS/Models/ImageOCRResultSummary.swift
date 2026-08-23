import Foundation

struct ImageOCRResultSummary: Equatable, Sendable {
    // Keep the review surface aligned with the bundled Manga OCR quality gate.
    // A result below 0.55 is not reliable enough to silently leave out of review.
    static let lowConfidenceThreshold: Float = 0.55

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
        horizontalBlockCount = blocks.count(where: { $0.effectiveSourceDirection == .horizontal })
        verticalBlockCount = blocks.count(where: { $0.effectiveSourceDirection == .vertical })
        unknownDirectionBlockCount = blocks.count(where: {
            $0.effectiveSourceDirection == nil || $0.effectiveSourceDirection == .unknown
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
        guard rawConfidence.isFinite,
              (0...1).contains(rawConfidence) else {
            return 0
        }
        return rawConfidence
    }

    static func hasUnknownDirection(_ block: ImageTranslationBlock) -> Bool {
        block.effectiveSourceDirection == nil || block.effectiveSourceDirection == .unknown
    }

}
