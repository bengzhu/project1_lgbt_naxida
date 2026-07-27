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

private func permutations<T>(_ values: [T]) -> [[T]] {
    guard let first = values.first else { return [[]] }
    return permutations(Array(values.dropFirst())).flatMap { remainder in
        (0...remainder.count).map { index in
            var result = remainder
            result.insert(first, at: index)
            return result
        }
    }
}

private func signature(_ blocks: [ImageOCRLayoutBlock]) -> [String] {
    blocks.map { "\($0.direction.rawValue):\($0.text):\($0.rect.x):\($0.rect.y)" }
}

@main
private enum ImageOCRDirectionEvaluator {
static func main() {
let horizontalFixture = [
    observation("world", rect(0.28, 0.10, 0.18, 0.04)),
    observation("next", rect(0.10, 0.30, 0.20, 0.04)),
    observation("hello", rect(0.10, 0.10, 0.16, 0.04))
]
let horizontal = ImageOCRLayoutEngine.layout(horizontalFixture, allowsVerticalText: false)
require(horizontal.map(\.text) == ["hello world", "next"], "horizontal reading order must be stable")

let verticalFixture = [
    observation("下", rect(0.78, 0.16, 0.025, 0.06)),
    observation("左", rect(0.62, 0.08, 0.025, 0.06)),
    observation("上", rect(0.78, 0.08, 0.025, 0.06)),
    observation("列", rect(0.62, 0.16, 0.025, 0.06))
]
let vertical = ImageOCRLayoutEngine.layout(verticalFixture, allowsVerticalText: true)
require(vertical.map(\.text) == ["上下", "左列"], "vertical columns must read right-to-left and top-to-bottom")
require(vertical.allSatisfy { $0.direction == .vertical }, "column evidence must retain vertical direction")

let mixedFixture = verticalFixture + [observation("TITLE", rect(0.08, 0.02, 0.30, 0.04))]
let mixedExpected = signature(ImageOCRLayoutEngine.layout(mixedFixture, allowsVerticalText: true))
for permutation in permutations(mixedFixture) {
    require(
        signature(ImageOCRLayoutEngine.layout(permutation, allowsVerticalText: true)) == mixedExpected,
        "mixed layout must be identical for every input permutation"
    )
}
require(mixedExpected.first?.contains("TITLE") == true, "horizontal title above vertical content must remain first")

let comparatorChain = [
    observation("A", rect(0.30, 0.00, 0.15, 0.04)),
    observation("B", rect(0.20, 0.015, 0.15, 0.04)),
    observation("C", rect(0.10, 0.030, 0.15, 0.04))
]
let chainExpected = signature(ImageOCRLayoutEngine.layout(comparatorChain, allowsVerticalText: false))
for permutation in permutations(comparatorChain) {
    require(
        signature(ImageOCRLayoutEngine.layout(permutation, allowsVerticalText: false)) == chainExpected,
        "row-band chain must not create comparator cycles"
    )
}

let horizontalColumns = [
    observation("L1", rect(0.10, 0.10, 0.18, 0.04)),
    observation("R1", rect(0.62, 0.10, 0.18, 0.04)),
    observation("L2", rect(0.10, 0.16, 0.18, 0.04)),
    observation("R2", rect(0.62, 0.16, 0.18, 0.04))
]
let horizontalColumnsExpected = ["L1\nL2", "R1\nR2"]
for permutation in permutations(horizontalColumns) {
    require(
        ImageOCRLayoutEngine.layout(permutation, allowsVerticalText: false).map(\.text)
            == horizontalColumnsExpected,
        "interleaved horizontal columns must merge into their closest compatible clusters"
    )
}

let horizontalCJKFragments = [
    observation("你", rect(0.20, 0.20, 0.025, 0.06)),
    observation("好", rect(0.25, 0.20, 0.025, 0.06))
]
let fragments = ImageOCRLayoutEngine.layout(horizontalCJKFragments, allowsVerticalText: true)
require(fragments.count == 1, "nearby horizontal CJK fragments must not split into vertical blocks")
require(fragments.first?.direction != .vertical, "horizontal CJK fragments must not be promoted to vertical")
require(fragments.first?.text == "你 好", "horizontal CJK fragments must preserve left-to-right text")

let tallRun = ImageOCRLayoutEngine.layout(
    [observation("漫画", rect(0.70, 0.10, 0.04, 0.18))],
    allowsVerticalText: true
)
require(tallRun.first?.direction == .vertical, "multi-character tall CJK text may establish vertical evidence")
let isolated = ImageOCRLayoutEngine.layout(
    [observation("口", rect(0.40, 0.40, 0.025, 0.06))],
    allowsVerticalText: true
)
require(isolated.first?.direction == .unknown, "isolated single-character tall CJK must remain unknown")
let nonCJK = ImageOCRLayoutEngine.layout(
    [observation("I", rect(0.40, 0.40, 0.02, 0.10))],
    allowsVerticalText: false
)
require(nonCJK.first?.direction == .unknown, "non-CJK tall boxes must not become vertical")

print("v2.7 image OCR direction evaluator passed")
}
}
