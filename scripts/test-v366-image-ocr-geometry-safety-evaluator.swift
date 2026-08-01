import Foundation

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> ImageOCRLayoutRect {
    ImageOCRLayoutRect(x: x, y: y, width: width, height: height)
}

private func observation(_ text: String, _ rect: ImageOCRLayoutRect) -> ImageOCRLayoutObservation {
    ImageOCRLayoutObservation(text: text, confidence: 0.9, rect: rect)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func requireRect(_ actual: ImageOCRLayoutRect?, _ expected: ImageOCRLayoutRect, _ message: String) {
    guard let actual else { preconditionFailure(message) }
    let values = [actual.x, actual.y, actual.width, actual.height]
    let expectedValues = [expected.x, expected.y, expected.width, expected.height]
    precondition(
        zip(values, expectedValues).allSatisfy { abs($0 - $1) < 0.000_001 },
        message
    )
}

@main
private enum ImageOCRGeometrySafetyEvaluator {
    static func main() {
        let inBounds = rect(0.2, 0.3, 0.25, 0.12)
        requireRect(inBounds.normalizedToUnit(), inBounds, "in-bounds rectangles must remain unchanged")

        let clipped = rect(0.9, 0.8, 0.5, 0.5).normalizedToUnit()
        requireRect(clipped, rect(0.9, 0.8, 0.1, 0.2), "oversized rectangles must clip as a whole")

        let partiallyVisible = rect(-0.2, -0.1, 0.3, 0.4).normalizedToUnit()
        requireRect(partiallyVisible, rect(0, 0, 0.1, 0.3), "partially visible rectangles must keep visible geometry")

        require(rect(0, 0, 0, 0).normalizedToUnit() == nil, "zero-area rectangles must be rejected")
        require(rect(.nan, 0.1, 0.2, 0.2).normalizedToUnit() == nil, "NaN rectangles must be rejected")
        require(rect(0.1, 0.1, .infinity, 0.2).normalizedToUnit() == nil, "infinite rectangles must be rejected")

        let observations = [
            observation("valid", inBounds),
            observation("zero", rect(0.4, 0.4, 0, 0.1)),
            observation("nan", rect(.nan, 0.1, 0.2, 0.2)),
            observation("clipped", rect(0.9, 0.8, 0.5, 0.5))
        ]
        let blocks = ImageOCRLayoutEngine.layout(observations, allowsVerticalText: false)
        require(blocks.map(\.text) == ["valid", "clipped"], "layout must discard invalid geometry and retain clipped text")
        requireRect(blocks.last?.rect, rect(0.9, 0.8, 0.1, 0.2), "layout must expose clipped geometry")
        require(blocks.allSatisfy { $0.rect.x >= 0 && $0.rect.y >= 0 && $0.rect.maxX <= 1 && $0.rect.maxY <= 1 }, "layout output must stay in unit space")

        print("v3.66 image OCR geometry safety evaluator passed")
    }
}
