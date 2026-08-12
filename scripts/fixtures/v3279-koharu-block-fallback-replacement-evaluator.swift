import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
private enum KoharuBlockFallbackReplacementEvaluator {
    static func main() {
        require(
            ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: [4, 4],
                blockOwner: 4,
                hasCompleteLineCoverage: true
            ),
            "complete exact-owner fallback did not replace partial lines"
        )
        require(
            !ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: [4, 5],
                blockOwner: 4,
                hasCompleteLineCoverage: true
            ),
            "foreign-owner fallback replaced partial lines"
        )
        require(
            !ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: [4, nil],
                blockOwner: 4,
                hasCompleteLineCoverage: true
            ),
            "ownerless fallback replaced known-owner partial lines"
        )
        require(
            !ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: [4],
                blockOwner: nil,
                hasCompleteLineCoverage: true
            ),
            "fallback replaced partial lines for an ownerless block"
        )
        require(
            !ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: [4],
                blockOwner: 4,
                hasCompleteLineCoverage: false
            ),
            "incomplete exact-owner fallback replaced partial lines"
        )
        require(
            !ImageOCRLayoutEngine.blockFallbackCanReplacePartialLines(
                fallbackOwners: [],
                blockOwner: 4,
                hasCompleteLineCoverage: true
            ),
            "empty fallback replaced partial lines"
        )

        print("v3.279 Koharu block fallback replacement evaluator passed")
    }
}
