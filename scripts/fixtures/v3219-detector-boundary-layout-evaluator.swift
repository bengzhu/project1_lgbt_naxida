import Foundation

private func rect(
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double
) -> ImageOCRLayoutRect {
    ImageOCRLayoutRect(x: x, y: y, width: width, height: height)
}

private func observation(
    _ text: String,
    _ rect: ImageOCRLayoutRect,
    preservesBoundary: Bool
) -> ImageOCRLayoutObservation {
    ImageOCRLayoutObservation(
        text: text,
        confidence: 0.9,
        rect: rect,
        sourceDirectionHint: .vertical,
        preservesDetectorTextRegionBoundary: preservesBoundary
    )
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
private enum DetectorBoundaryLayoutEvaluator {
    static func main() {
        let tail = rect(0.75, 0.19, 0.13, 0.04)
        let nextPageHead = rect(0.75, 0.268, 0.13, 0.046)

        let detectorBlocks = ImageOCRLayoutEngine.layout(
            [
                observation("お願いします", tail, preservesBoundary: true),
                observation("前は生意気に", nextPageHead, preservesBoundary: true),
            ],
            allowsVerticalText: true,
            prefersMangaReadingOrder: true
        )
        require(detectorBlocks.count == 2, "detector TextRegions must remain separate")
        require(
            detectorBlocks.map(\.text) == ["お願いします", "前は生意気に"],
            "detector TextRegion text order must remain intact"
        )

        let visionBlocks = ImageOCRLayoutEngine.layout(
            [
                observation("上", tail, preservesBoundary: false),
                observation("下", nextPageHead, preservesBoundary: false),
            ],
            allowsVerticalText: true,
            prefersMangaReadingOrder: true
        )
        require(visionBlocks.count == 1, "Vision fragments must keep bounded clustering")
        require(visionBlocks[0].text == "上下", "Vision fragment order must remain top-to-bottom")

        print("v3.219 detector TextRegion boundary evaluator passed")
    }
}
