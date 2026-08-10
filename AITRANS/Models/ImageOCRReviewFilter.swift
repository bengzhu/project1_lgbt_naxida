import Foundation

enum ImageOCRReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case needsReview = "待复查"
    case lowConfidence = "低置信"
    case unknownDirection = "方向待定"
    case vertical = "竖排"

    var id: String { rawValue }

    func blocks(from blocks: [ImageTranslationBlock]) -> [ImageTranslationBlock] {
        switch self {
        case .all:
            blocks
        case .needsReview:
            blocks.filter { ImageOCRResultSummary.requiresReview($0) }
        case .lowConfidence:
            blocks.filter { ImageOCRResultSummary.hasLowConfidence($0) }
        case .unknownDirection:
            blocks.filter { ImageOCRResultSummary.hasUnknownDirection($0) }
        case .vertical:
            blocks.filter { $0.sourceDirection == .vertical }
        }
    }
}
