import Foundation

@main
struct KoharuMaskPayloadEvaluatorContract {
    static func main() throws {
        let bubble = try KoharuMaskPayloadEvaluator.evaluateBubble(
            width: 4,
            height: 3,
            encoding: "rowMajorRLE",
            runs: [[0, 5], [7, 2], [0, 2], [7, 2], [0, 1]],
            instances: [KoharuBubbleMaskInstanceSummary(
                id: "bubble-7",
                bbox: [1, 1, 2, 2],
                pixelCount: 4,
                maskValue: 7
            )],
            maxPixelCount: 12
        )
        guard case let .validated(validBubble) = bubble else { preconditionFailure("v2 bubble payload was not evaluated") }
        let bubbleStats = validBubble.mask.statistics(in: KoharuMaskPixelRect(x: 0, y: 1, width: 3, height: 2))
        precondition(bubbleStats.sampledPixelCount == 6)
        precondition(bubbleStats.majorityNonzeroLabel == 7)
        precondition(bubbleStats.majorityNonzeroPixelCount == 4)
        precondition(abs(bubbleStats.nonzeroCoverageRatio - (4.0 / 6.0)) < 0.000_001)
        precondition(validBubble.mask.containmentRatio(of: 7, in: KoharuMaskPixelRect(x: 1, y: 1, width: 1, height: 2)) == 0.5)
        let overflowClampedStats = validBubble.mask.statistics(
            in: KoharuMaskPixelRect(x: 1, y: 1, width: Int.max, height: Int.max)
        )
        precondition(overflowClampedStats.sampledPixelCount == 6)
        precondition(validBubble.mask.statistics(
            in: KoharuMaskPixelRect(x: Int.max, y: Int.max, width: Int.max, height: Int.max)
        ).sampledPixelCount == 0)

        let segment = try KoharuMaskPayloadEvaluator.evaluateSegment(
            width: 4,
            height: 3,
            encoding: "rowMajorRLE",
            runs: [[0, 5], [1, 2], [0, 4], [1, 1]],
            glyphPixelCount: 3,
            connectedComponentCount: 2,
            maxPixelCount: 12
        )
        guard case let .validated(validSegment) = segment else { preconditionFailure("v2 segment payload was not evaluated") }
        precondition(validSegment.glyphPixelCount == 3)
        precondition(validSegment.connectedComponentCount == 2)

        let summaryBubble = try KoharuMaskPayloadEvaluator.evaluateBubble(
            width: nil,
            height: nil,
            encoding: nil,
            runs: nil,
            instances: [],
            maxPixelCount: 12
        )
        precondition(summaryBubble == .summaryOnly)
        let summarySegment = try KoharuMaskPayloadEvaluator.evaluateSegment(
            width: 4,
            height: 3,
            encoding: nil,
            runs: nil,
            glyphPixelCount: 3,
            connectedComponentCount: 2,
            maxPixelCount: 12
        )
        precondition(summarySegment == .summaryOnly)

        expect(.decodedLengthMismatch(expected: 4, actual: 3)) {
            try KoharuMaskPayloadEvaluator.decode(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[0, 3]],
                allowedLabels: [0], maxPixelCount: 4
            )
        }
        expect(.decodedLengthExceeded(index: 0)) {
            try KoharuMaskPayloadEvaluator.decode(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[0, 5]],
                allowedLabels: [0], maxPixelCount: 4
            )
        }
        expect(.invalidLabel(index: 0, label: 2)) {
            try KoharuMaskPayloadEvaluator.decode(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[2, 4]],
                allowedLabels: [0, 1], maxPixelCount: 4
            )
        }
        expect(.invalidRunLength(index: 0)) {
            try KoharuMaskPayloadEvaluator.decode(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[0, 0]],
                allowedLabels: [0], maxPixelCount: 4
            )
        }
        expect(.dimensionOverflow) {
            try KoharuMaskPayloadEvaluator.decode(
                width: Int.max, height: 2, encoding: "rowMajorRLE", runs: [],
                allowedLabels: [0], maxPixelCount: Int.max
            )
        }
        expect(.pixelLimitExceeded(expected: 6, limit: 5)) {
            try KoharuMaskPayloadEvaluator.decode(
                width: 3, height: 2, encoding: "rowMajorRLE", runs: [[0, 6]],
                allowedLabels: [0], maxPixelCount: 5
            )
        }
        expect(.duplicateBubbleMaskValue(7)) {
            try KoharuMaskPayloadEvaluator.evaluateBubble(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[7, 4]],
                instances: [
                    KoharuBubbleMaskInstanceSummary(id: "a", bbox: [0, 0, 2, 2], pixelCount: 4, maskValue: 7),
                    KoharuBubbleMaskInstanceSummary(id: "b", bbox: [0, 0, 2, 2], pixelCount: 4, maskValue: 7)
                ],
                maxPixelCount: 4
            )
        }
        expect(.bubblePixelCountMismatch(id: "a", expected: 3, actual: 4)) {
            try KoharuMaskPayloadEvaluator.evaluateBubble(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[7, 4]],
                instances: [KoharuBubbleMaskInstanceSummary(id: "a", bbox: [0, 0, 2, 2], pixelCount: 3, maskValue: 7)],
                maxPixelCount: 4
            )
        }
        expect(.bubbleBoundingBoxMismatch(id: "a", expected: [0, 0, 1, 2], actual: [0, 0, 2, 2])) {
            try KoharuMaskPayloadEvaluator.evaluateBubble(
                width: 2, height: 2, encoding: "rowMajorRLE", runs: [[7, 4]],
                instances: [KoharuBubbleMaskInstanceSummary(id: "a", bbox: [0, 0, 1, 2], pixelCount: 4, maskValue: 7)],
                maxPixelCount: 4
            )
        }
        expect(.segmentComponentCountMismatch(expected: 1, actual: 2)) {
            try KoharuMaskPayloadEvaluator.evaluateSegment(
                width: 3, height: 2, encoding: "rowMajorRLE", runs: [[1, 1], [0, 4], [1, 1]],
                glyphPixelCount: 2, connectedComponentCount: 1, maxPixelCount: 6
            )
        }
        print("Koharu mask payload evaluator contract passed")
    }

    private static func expect<T>(_ expected: KoharuMaskPayloadError, operation: () throws -> T) {
        do {
            _ = try operation()
            preconditionFailure("expected \(expected)")
        } catch let error as KoharuMaskPayloadError {
            precondition(error == expected, "expected \(expected), got \(error)")
        } catch {
            preconditionFailure("unexpected error: \(error)")
        }
    }
}
