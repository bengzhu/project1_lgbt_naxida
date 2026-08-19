import Foundation

@main
struct V3290ImageTranslationRenderSafetyEvaluator {
    static func main() {
        let clearBlock = ImageTranslationBlock(
            original: "日本語",
            translation: "中文",
            confidence: 0.9,
            boundingBox: NormalizedImageRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)
        )
        let clearReport = ImageTranslationRenderSafety.analyze(
            blocks: [clearBlock],
            overlayMode: .replace
        )
        precondition(clearReport.verdict == .clear)
        precondition(clearReport.reportOnly)
        precondition(!clearReport.groundTruthUsedForDecision)
        precondition(!clearReport.changesOCR)
        precondition(!clearReport.changesTranslation)
        precondition(!clearReport.changesOverlayRendering)

        let invalidBlock = ImageTranslationBlock(
            original: "坏框",
            confidence: 0.2,
            boundingBox: NormalizedImageRect(x: 0.2, y: 0.2, width: -0.1, height: 0.1)
        )
        let invalidReport = ImageTranslationRenderSafety.analyze(
            blocks: [invalidBlock],
            overlayMode: .replace
        )
        precondition(invalidReport.issues.contains { $0.code == .invalidGeometry })

        let edgeBlock = ImageTranslationBlock(
            original: "边界文字",
            confidence: 0.4,
            boundingBox: NormalizedImageRect(x: 0, y: 0.2, width: 0.95, height: 0.1)
        )
        let edgeReport = ImageTranslationRenderSafety.analyze(
            blocks: [edgeBlock],
            overlayMode: .adjacent
        )
        precondition(edgeReport.issues.contains { $0.code == .adjacentOverlayClipped })

        let firstBlock = ImageTranslationBlock(
            original: "第一块",
            confidence: 0.7,
            boundingBox: NormalizedImageRect(x: 0.2, y: 0.2, width: 0.1, height: 0.1)
        )
        let secondBlock = ImageTranslationBlock(
            original: "第二块",
            confidence: 0.7,
            boundingBox: NormalizedImageRect(x: 0.4, y: 0.2, width: 0.1, height: 0.1)
        )
        let collisionReport = ImageTranslationRenderSafety.analyze(
            blocks: [firstBlock, secondBlock],
            overlayMode: .adjacent
        )
        precondition(
            collisionReport.issues.contains {
                $0.code == .adjacentOverlayCollidesWithOtherBlock
            }
        )

        print("renderSafetyEvaluator=passed cases=4 groundTruthUsedForDecision=false")
    }
}
