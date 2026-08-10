import Foundation

// TranscriptModels references service-owned diagnostics. Keep this model-only
// evaluator independent from Vision/Core ML services with equivalent stubs.
struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func normalized(_ text: String) -> String {
    ImageTranslationVerticalTextLayout.normalizedCharacters(in: text).joined()
}

private func testKoharuEmphasisPairs() {
    let cases = [
        ("!!", "‼"),
        ("？？", "⁇"),
        ("!?", "⁉"),
        ("？！", "⁈"),
        ("!!?", "‼?"),
        ("?!!", "?‼"),
        ("!?!", "⁉!"),
        ("Hello!?!", "Hello⁉!"),
    ]

    for (input, expected) in cases {
        require(normalized(input) == expected, "vertical emphasis normalization mismatch for \(input)")
    }
}

private func testVerticalGlyphsAndPunctuationClassification() {
    require(
        ImageTranslationVerticalTextLayout.verticalGlyph(for: "、") == "︑",
        "ideographic comma must use its vertical presentation form"
    )
    require(
        ImageTranslationVerticalTextLayout.verticalGlyph(for: "「") == "﹁",
        "corner quote must use its vertical presentation form"
    )
    require(
        ImageTranslationVerticalTextLayout.verticalGlyph(for: "！") == "﹗",
        "fullwidth bang must use its vertical presentation form"
    )
    require(
        ImageTranslationVerticalTextLayout.isFullwidthPunctuation("。"),
        "ideographic full stop must be classified as fullwidth punctuation"
    )
    require(
        ImageTranslationVerticalTextLayout.isFullwidthPunctuation("！"),
        "fullwidth bang must be classified as fullwidth punctuation"
    )
    require(
        !ImageTranslationVerticalTextLayout.isFullwidthPunctuation("A"),
        "Latin letters must not be classified as fullwidth punctuation"
    )
}

private func testNewlinesAreNotVerticalCells() {
    require(
        normalized("甲\n乙") == "甲乙",
        "newlines must not consume bounded vertical cells"
    )
}

@main
private struct JapaneseVerticalPunctuationEvaluator {
    static func main() {
        testKoharuEmphasisPairs()
        testVerticalGlyphsAndPunctuationClassification()
        testNewlinesAreNotVerticalCells()
        print("v3.242 Japanese vertical punctuation evaluator passed")
    }
}
