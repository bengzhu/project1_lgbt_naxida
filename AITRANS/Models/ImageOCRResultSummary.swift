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

    init(
        blocks: [ImageTranslationBlock],
        lowConfidenceThreshold: Float = Self.lowConfidenceThreshold
    ) {
        let threshold = min(max(Double(lowConfidenceThreshold), 0), 1)
        let confidences = blocks.map { min(max(Double($0.confidence), 0), 1) }

        totalBlockCount = blocks.count
        translatedBlockCount = blocks.count(where: { !$0.translation.isEmpty })
        averageConfidence = confidences.isEmpty
            ? nil
            : confidences.reduce(0, +) / Double(confidences.count)
        lowConfidenceBlockCount = confidences.count(where: { $0 < threshold })
        horizontalBlockCount = blocks.count(where: { $0.sourceDirection == .horizontal })
        verticalBlockCount = blocks.count(where: { $0.sourceDirection == .vertical })
        unknownDirectionBlockCount = blocks.count(where: {
            $0.sourceDirection == nil || $0.sourceDirection == .unknown
        })
    }
}
