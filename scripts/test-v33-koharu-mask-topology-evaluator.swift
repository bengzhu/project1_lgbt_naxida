import Foundation

@main
private enum V33KoharuMaskTopologyEvaluatorContract {
    static func main() throws {
        try testCompleteTopologyAndStableOrdering()
        try testCrossBubbleAndOrphanBlocking()
        try testDuplicateAndOverlappingAssignmentBlocking()
        try testEmptyGlyphBlocking()
        try testEmptyAssignedTextBoxBlocking()
        try testMaskShapeRejection()
        print("v3.3 Koharu mask topology evaluator contract passed")
    }

    private static func testCompleteTopologyAndStableOrdering() throws {
        let segment = mask(
            width: 6,
            rows: [
                [1, 1, 0, 0, 1, 1],
                [1, 1, 0, 0, 1, 1],
                [0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 0]
            ]
        )
        let bubbles = bubbleMask()
        let assignments = [
            assignment(block: 20, textBox: "box-b", x: 4, y: 0, width: 2, height: 2, bubble: 9),
            assignment(block: 10, textBox: "box-a", x: 0, y: 0, width: 2, height: 2, bubble: 7)
        ]
        let forward = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: segment,
            bubbleMask: bubbles,
            assignments: assignments
        )
        let reversed = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: segment,
            bubbleMask: bubbles,
            assignments: Array(assignments.reversed())
        )

        require(forward == reversed, "topology output must not depend on assignment input order")
        require(forward.passed, "complete one-to-one topology must pass")
        require(forward.blockers.isEmpty, "complete topology must have no blockers")
        require(forward.totalGlyphPixelCount == 8, "all glyph pixels must be counted")
        require(forward.insideAssignedBoxGlyphPixelCount == 8, "all glyph pixels must be inside assigned boxes")
        require(forward.expectedBubbleGlyphPixelCount == 8, "all glyph pixels must use their expected bubble")
        require(forward.foreignBubbleGlyphPixelCount == 0, "complete topology must have no foreign bubble pixels")
        require(forward.orphanGlyphPixelCount == 0, "complete topology must have no orphan pixels")
        require(forward.partitionConserved && forward.partitionPixelCount == 8, "global partition must conserve pixels")
        require(forward.assignmentLedgers.map(\.blockIndex) == [10, 20], "assignment ledgers must use stable block order")
        require(forward.assignmentLedgers.allSatisfy(\.partitionConserved), "assignment partitions must conserve pixels")
        require(forward.componentLedgers.map(\.componentIndex) == [0, 1], "components must use stable row-major indexes")
        require(forward.componentLedgers.map(\.bbox) == [
            KoharuMaskPixelRect(x: 0, y: 0, width: 2, height: 2),
            KoharuMaskPixelRect(x: 4, y: 0, width: 2, height: 2)
        ], "component bboxes must be exact")
    }

    private static func testCrossBubbleAndOrphanBlocking() throws {
        let segment = mask(
            width: 6,
            rows: [
                [0, 0, 0, 0, 0, 0],
                [0, 1, 1, 1, 1, 0],
                [0, 0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0, 1]
            ]
        )
        let result = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: segment,
            bubbleMask: bubbleMask(),
            assignments: [assignment(block: 10, textBox: "box-a", x: 1, y: 1, width: 4, height: 1, bubble: 7)]
        )

        require(!result.passed, "cross-bubble and orphan glyphs must block")
        require(result.totalGlyphPixelCount == 5, "all risky glyph pixels must be counted")
        require(result.insideAssignedBoxGlyphPixelCount == 4, "assigned union count must exclude orphan glyphs")
        require(result.expectedBubbleGlyphPixelCount == 2, "expected bubble partition must be exact")
        require(result.foreignBubbleGlyphPixelCount == 1, "foreign bubble partition must be exact")
        require(result.noBubbleGlyphPixelCount == 1, "no-bubble partition must be exact")
        require(result.orphanGlyphPixelCount == 1, "orphan partition must be exact")
        require(result.partitionPixelCount == 5 && result.partitionConserved, "risk partitions must still conserve pixels")
        require(result.crossBubbleComponentIndexes == [0], "cross-bubble component ledger must be stable")
        require(result.orphanComponentIndexes == [1], "orphan component ledger must be stable")
        require(result.blockers == [
            .glyphOutsideAssignedTextBox,
            .glyphOutsideBubble,
            .crossBubble
        ], "topology blockers must use stable severity order")
        require(result.componentLedgers[0].bubbleLabels == [0, 7, 9], "component bubble labels must be sorted")
        require(result.componentLedgers[0].crossesBubble, "foreign bubble contact must mark component crossing")
        require(result.componentLedgers[1].hasOrphanGlyph, "unassigned component must be marked orphan")
    }

    private static func testDuplicateAndOverlappingAssignmentBlocking() throws {
        let segment = mask(width: 2, rows: [[1, 1]])
        let bubbles = mask(width: 2, rows: [[7, 7]])
        let assignments = [
            assignment(block: 1, textBox: "box-1", x: 0, y: 0, width: 2, height: 1, bubble: 7),
            assignment(block: 1, textBox: "box-2", x: 0, y: 0, width: 2, height: 1, bubble: 7),
            assignment(block: 2, textBox: "box-1", x: 0, y: 0, width: 2, height: 1, bubble: 7)
        ]
        let forward = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: segment,
            bubbleMask: bubbles,
            assignments: assignments
        )
        let replay = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: segment,
            bubbleMask: bubbles,
            assignments: [assignments[2], assignments[0], assignments[1]]
        )

        require(forward == replay, "duplicate topology ledger must be input-order independent")
        require(forward.duplicateBlockIndexes == [1], "duplicate block assignments must be explicit")
        require(forward.duplicateTextBoxIDs == ["box-1"], "duplicate TextBox assignments must be explicit")
        require(forward.multiplyAssignedGlyphPixelCount == 2, "overlapping claim pixels must be counted once globally")
        require(forward.partitionConserved, "duplicate claims must not break the global owner partition")
        require(forward.blockers == [.duplicateAssignment, .overlappingAssignments], "duplicate blockers must be stable")
    }

    private static func testEmptyGlyphBlocking() throws {
        let empty = mask(width: 2, rows: [[0, 0], [0, 0]])
        let bubbles = mask(width: 2, rows: [[7, 7], [7, 7]])
        let result = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: empty,
            bubbleMask: bubbles,
            assignments: [assignment(block: 1, textBox: "box", x: 0, y: 0, width: 2, height: 2, bubble: 7)]
        )
        require(result.totalGlyphPixelCount == 0, "empty mask must report zero glyphs")
        require(result.partitionConserved, "zero-sized glyph partition must conserve")
        require(result.componentLedgers.isEmpty, "empty glyph mask must have no components")
        require(result.blockers == [.emptyGlyphMask], "empty glyph mask must remain blocked")
    }

    private static func testMaskShapeRejection() throws {
        let valid = mask(width: 2, rows: [[0, 0]])
        expect(.topologyMaskDimensionMismatch) {
            try KoharuMaskPayloadEvaluator.evaluateTopology(
                segmentMask: valid,
                bubbleMask: mask(width: 1, rows: [[0]]),
                assignments: []
            )
        }
        expect(.invalidDecodedMask) {
            try KoharuMaskPayloadEvaluator.evaluateTopology(
                segmentMask: KoharuDecodedMask(width: 2, height: 2, pixels: [1]),
                bubbleMask: KoharuDecodedMask(width: 2, height: 2, pixels: [0, 0, 0, 0]),
                assignments: []
            )
        }
    }

    private static func testEmptyAssignedTextBoxBlocking() throws {
        let segment = mask(width: 4, rows: [[1, 0, 0, 0]])
        let bubbles = mask(width: 4, rows: [[7, 7, 9, 9]])
        let result = try KoharuMaskPayloadEvaluator.evaluateTopology(
            segmentMask: segment,
            bubbleMask: bubbles,
            assignments: [
                assignment(block: 1, textBox: "box-with-glyph", x: 0, y: 0, width: 2, height: 1, bubble: 7),
                assignment(block: 2, textBox: "box-without-glyph", x: 2, y: 0, width: 2, height: 1, bubble: 9)
            ]
        )
        require(result.totalGlyphPixelCount == 1, "fixture must retain one global glyph")
        require(result.assignmentLedgers.map(\.glyphPixelCount) == [1, 0], "empty assignment must remain explicit")
        require(result.blockers == [.emptyAssignedTextBox], "one empty assigned TextBox must block topology")
    }

    private static func bubbleMask() -> KoharuDecodedMask {
        mask(
            width: 6,
            rows: Array(repeating: [7, 7, 7, 0, 9, 9], count: 4)
        )
    }

    private static func assignment(
        block: Int,
        textBox: String,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        bubble: Int
    ) -> KoharuMaskTopologyAssignment {
        KoharuMaskTopologyAssignment(
            blockIndex: block,
            textBoxID: textBox,
            rect: KoharuMaskPixelRect(x: x, y: y, width: width, height: height),
            expectedBubbleLabel: bubble
        )
    }

    private static func mask(width: Int, rows: [[Int]]) -> KoharuDecodedMask {
        require(rows.allSatisfy { $0.count == width }, "fixture rows must match width")
        return KoharuDecodedMask(width: width, height: rows.count, pixels: rows.flatMap { $0 })
    }

    private static func expect<T>(_ expected: KoharuMaskPayloadError, operation: () throws -> T) {
        do {
            _ = try operation()
            fatalError("expected \(expected)")
        } catch let error as KoharuMaskPayloadError {
            require(error == expected, "expected \(expected), got \(error)")
        } catch {
            fatalError("unexpected error: \(error)")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
