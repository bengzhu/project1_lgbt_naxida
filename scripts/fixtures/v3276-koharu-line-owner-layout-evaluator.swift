import Foundation

private func rect(_ y: Double) -> ImageOCRLayoutRect {
    ImageOCRLayoutRect(x: 0.72, y: y, width: 0.08, height: 0.06)
}

private func observation(
    _ text: String,
    y: Double,
    owner: Int?
) -> ImageOCRLayoutObservation {
    ImageOCRLayoutObservation(
        text: text,
        confidence: 0.9,
        rect: rect(y),
        sourceDirectionHint: .vertical,
        verticalTextRegionOwner: owner
    )
}

private func layout(
    _ firstOwner: Int?,
    _ secondOwner: Int?
) -> [ImageOCRLayoutBlock] {
    ImageOCRLayoutEngine.layout(
        [
            observation("上", y: 0.10, owner: firstOwner),
            observation("下", y: 0.18, owner: secondOwner),
        ],
        allowsVerticalText: true,
        prefersMangaReadingOrder: true
    )
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
private enum KoharuLineOwnerLayoutEvaluator {
    static func main() {
        let distinctOwners = layout(1, 2)
        require(distinctOwners.count == 2, "distinct known owners merged")
        require(
            Set(distinctOwners.compactMap(\.verticalTextRegionOwner)) == [1, 2],
            "distinct owner identity was not retained"
        )

        let sameOwner = layout(7, 7)
        require(sameOwner.count == 1, "same owner did not cluster")
        require(sameOwner[0].text == "上下", "same-owner reading order changed")
        require(sameOwner[0].verticalTextRegionOwner == 7, "same owner was lost")

        let ownerless = layout(nil, nil)
        require(ownerless.count == 1, "ownerless compatibility changed")
        require(ownerless[0].text == "上下", "ownerless reading order changed")
        require(ownerless[0].verticalTextRegionOwner == nil, "ownerless block gained owner")

        let mixed = layout(nil, 9)
        require(mixed.count == 1, "ownerless-known compatibility changed")
        require(mixed[0].text == "上下", "mixed reading order changed")
        require(mixed[0].verticalTextRegionOwner == nil, "mixed block exposed owner")

        print("v3.276 Koharu line owner layout evaluator passed")
    }
}
