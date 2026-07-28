import Foundation

enum ImageOCRReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case needsReview = "待复查"

    var id: String { rawValue }

    func blocks(from blocks: [ImageTranslationBlock]) -> [ImageTranslationBlock] {
        switch self {
        case .all:
            blocks
        case .needsReview:
            blocks.filter { ImageOCRResultSummary.requiresReview($0) }
        }
    }
}
