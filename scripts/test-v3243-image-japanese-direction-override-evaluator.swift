import Foundation

// TranscriptModels contains service-owned diagnostic payloads. Keep this
// model-only evaluator independent from Vision/Core ML services.
struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func makeBlock(
    direction: ImageTextDirection?,
    override: ImageTextDirection? = nil
) -> ImageTranslationBlock {
    ImageTranslationBlock(
        original: "縦書き",
        translation: "竖排",
        confidence: 0.9,
        boundingBox: NormalizedImageRect(x: 0.1, y: 0.1, width: 0.2, height: 0.5),
        sourceDirection: direction,
        sourceDirectionOverride: override
    )
}

private func testEffectiveDirectionPreservesProvenance() {
    let automatic = makeBlock(direction: .unknown)
    require(automatic.sourceDirection == .unknown, "automatic mode must preserve OCR provenance")
    require(automatic.effectiveSourceDirection == .unknown, "automatic mode must use the OCR direction")
    require(!automatic.prefersVerticalWriting, "unknown OCR direction must remain horizontal")

    let vertical = makeBlock(direction: .unknown, override: .vertical)
    require(vertical.sourceDirection == .unknown, "manual override must not rewrite OCR provenance")
    require(vertical.effectiveSourceDirection == .vertical, "vertical override must become effective")
    require(vertical.prefersVerticalWriting, "CJK vertical override must enable vertical writing")

    let horizontal = makeBlock(direction: .vertical, override: .horizontal)
    require(horizontal.effectiveSourceDirection == .horizontal, "horizontal override must win over OCR")
    require(!horizontal.prefersVerticalWriting, "horizontal override must disable vertical writing")
}

private func testSummaryAndFilterConsumeEffectiveDirection() {
    let blocks = [
        makeBlock(direction: .unknown, override: .vertical),
        makeBlock(direction: .vertical, override: .horizontal),
        makeBlock(direction: nil),
    ]
    let summary = ImageOCRResultSummary(blocks: blocks)
    require(summary.verticalBlockCount == 1, "summary must count effective vertical overrides")
    require(summary.horizontalBlockCount == 1, "summary must count effective horizontal overrides")
    require(summary.unknownDirectionBlockCount == 1, "summary must retain unresolved automatic direction")
    require(ImageOCRReviewFilter.vertical.blocks(from: blocks).count == 1, "vertical filter must use effective direction")
    require(ImageOCRReviewFilter.unknownDirection.blocks(from: blocks).count == 1, "unknown filter must use effective direction")
}

@main
private struct JapaneseDirectionOverrideEvaluator {
    static func main() {
        testEffectiveDirectionPreservesProvenance()
        testSummaryAndFilterConsumeEffectiveDirection()
        print("v3.243 Japanese direction override evaluator passed")
    }
}
