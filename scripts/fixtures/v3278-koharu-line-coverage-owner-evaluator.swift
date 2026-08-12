import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
private enum KoharuLineCoverageOwnerEvaluator {
    static func main() {
        require(
            ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                lineResultOwner: 7,
                candidateOwner: 7,
                blockOwner: 7
            ),
            "exact known owner did not prove coverage"
        )
        require(
            !ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                lineResultOwner: nil,
                candidateOwner: 7,
                blockOwner: 7
            ),
            "ownerless result proved a known block"
        )
        require(
            !ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                lineResultOwner: 7,
                candidateOwner: nil,
                blockOwner: 7
            ),
            "ownerless candidate proved a known block"
        )
        require(
            !ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                lineResultOwner: 8,
                candidateOwner: 7,
                blockOwner: 7
            ),
            "foreign result owner proved a known block"
        )
        require(
            ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                lineResultOwner: nil,
                candidateOwner: 9,
                blockOwner: nil
            ),
            "ownerless block lost historical mixed compatibility"
        )
        require(
            !ImageOCRLayoutEngine.lineCoverageOwnersProveBlock(
                lineResultOwner: 8,
                candidateOwner: 9,
                blockOwner: nil
            ),
            "ownerless block accepted two distinct known owners"
        )

        print("v3.278 Koharu line coverage owner evaluator passed")
    }
}
