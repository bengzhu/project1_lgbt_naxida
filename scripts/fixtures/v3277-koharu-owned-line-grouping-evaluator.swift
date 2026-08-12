import Foundation

private func observation(
    _ text: String,
    confidence: Float = 0.9,
    x: Double = 0.72,
    y: Double,
    width: Double = 0.06,
    height: Double = 0.08,
    owner: Int?,
    preservesBoundary: Bool = false
) -> ImageOCRLayoutObservation {
    ImageOCRLayoutObservation(
        text: text,
        confidence: confidence,
        rect: ImageOCRLayoutRect(x: x, y: y, width: width, height: height),
        sourceDirectionHint: .vertical,
        preservesDetectorTextRegionBoundary: preservesBoundary,
        verticalTextRegionOwner: owner
    )
}

private func layout(
    _ observations: [ImageOCRLayoutObservation],
    prefersMangaReadingOrder: Bool = true
) -> [ImageOCRLayoutBlock] {
    ImageOCRLayoutEngine.layout(
        observations,
        allowsVerticalText: true,
        prefersMangaReadingOrder: prefersMangaReadingOrder
    )
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
private enum KoharuOwnedLineGroupingEvaluator {
    static func main() {
        let distantSameOwner = layout([
            observation("下", confidence: 0.2, y: 0.76, owner: 7, preservesBoundary: true),
            observation("上", confidence: 0.8, y: 0.08, owner: 7, preservesBoundary: true),
        ])
        require(distantSameOwner.count == 1, "distant same-owner lines split")
        require(distantSameOwner[0].text == "上下", "same-owner line order changed")
        require(distantSameOwner[0].verticalTextRegionOwner == 7, "same owner was lost")
        require(
            abs(distantSameOwner[0].confidence - 0.5) < 0.0001,
            "same-owner confidence is not the line arithmetic mean"
        )

        let distantDistinctOwners = layout([
            observation("甲", y: 0.08, owner: 1),
            observation("乙", y: 0.76, owner: 2),
        ])
        require(distantDistinctOwners.count == 2, "distinct known owners merged")
        require(
            Set(distantDistinctOwners.compactMap(\.verticalTextRegionOwner)) == [1, 2],
            "distinct owner identity changed"
        )

        let distantOwnerless = layout([
            observation("前", y: 0.08, owner: nil),
            observation("後", y: 0.76, owner: nil),
        ])
        require(distantOwnerless.count == 2, "ownerless geometry fallback changed")

        let ambiguousOwnerless = layout([
            observation("右", x: 0.69, y: 0.08, owner: 10),
            observation("左", x: 0.75, y: 0.08, owner: 11),
            observation("中", x: 0.72, y: 0.155, owner: nil),
        ])
        require(ambiguousOwnerless.count == 3, "ambiguous ownerless line joined an owner")
        require(
            ambiguousOwnerless.count { $0.verticalTextRegionOwner == nil } == 1,
            "ambiguous ownerless line gained an owner"
        )

        let unambiguousOwnerless = layout([
            observation("上", y: 0.08, owner: 15),
            observation("下", y: 0.155, owner: nil),
        ])
        require(unambiguousOwnerless.count == 1, "unambiguous ownerless compatibility changed")
        require(unambiguousOwnerless[0].text == "上下", "unambiguous ownerless order changed")
        require(unambiguousOwnerless[0].verticalTextRegionOwner == nil, "mixed block exposed owner")

        let nonManga = layout(
            [
                observation("上段", y: 0.08, width: 0.04, height: 0.10, owner: 21),
                observation("下段", y: 0.76, width: 0.04, height: 0.10, owner: 21),
            ],
            prefersMangaReadingOrder: false
        )
        require(nonManga.count == 2, "owner-first grouping escaped manga layout")

        print("v3.277 Koharu owned line grouping evaluator passed")
    }
}
