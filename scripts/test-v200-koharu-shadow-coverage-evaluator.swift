import Foundation

// TranscriptModels references these service-owned diagnostics. The contract target
// does not compile the UIKit/Vision probe service, so lightweight stubs close the
// model graph without changing the App target.
struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}

@main
private enum V200KoharuShadowCoverageContract {
    static func main() throws {
        try testStableMaximumMatching()
        testCoverageVerdicts()
        try testLegacyReportDecoding()
        print("v2.0 Swift shadow coverage contract passed")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }

    private static func testStableMaximumMatching() throws {
        let augmented = MangaOverlayStableOneToOneTextBoxMatcher.assignments(
            preferencesByBlockIndex: [
                0: ["box-x", "box-y"],
                1: ["box-x"]
            ]
        )
        require(augmented == [0: "box-y", 1: "box-x"], "augmenting path must preserve maximum cardinality")
        require(Set(augmented.values).count == augmented.count, "TextBox assignments must be one-to-one")

        let contended = MangaOverlayStableOneToOneTextBoxMatcher.assignments(
            preferencesByBlockIndex: [
                1: ["box-x"],
                0: ["box-x"]
            ]
        )
        require(contended == [0: "box-x"], "lower block index must win deterministic single-edge contention")

        let replayed = MangaOverlayStableOneToOneTextBoxMatcher.assignments(
            preferencesByBlockIndex: [
                1: ["box-x"],
                0: ["box-x", "box-y"]
            ]
        )
        require(replayed == augmented, "matching must be stable across dictionary insertion order")
    }

    private static func testCoverageVerdicts() {
        let complete = evaluate(
            matched: [0, 1],
            succeeded: [0, 1],
            failed: [],
            skipped: [],
            textBoxIDs: ["box-a", "box-b"]
        )
        require(complete.coverageVerdict == "complete", "all-block success must be complete")
        require(complete.outcomePartitionValid, "complete result must have a valid partition")
        require(complete.successfulCoverageRatio == 1, "complete result must have full successful coverage")

        let partial = evaluate(
            matched: [0, 1],
            succeeded: [0],
            failed: [1],
            skipped: [],
            textBoxIDs: ["box-a", "box-b"]
        )
        require(partial.coverageVerdict == "partial", "local success must not close global coverage")
        require(partial.successfulCoverageRatio == 0.5, "partial success ratio must use all evaluated blocks")
        require(partial.matchedOCRSuccessRatio == 0.5, "matched OCR success ratio must use matched blocks")

        let noSuccess = evaluate(
            matched: [0],
            succeeded: [],
            failed: [0],
            skipped: [1],
            textBoxIDs: ["box-a"]
        )
        require(noSuccess.coverageVerdict == "noSuccessfulCoverage", "zero-success coverage must stay blocked")

        let duplicate = evaluate(
            matched: [0, 1],
            succeeded: [0, 1],
            failed: [],
            skipped: [],
            textBoxIDs: ["box-a", "box-a"]
        )
        require(duplicate.coverageVerdict == "inconsistentAssignmentLedger", "duplicate TextBox IDs must invalidate coverage")
        require(duplicate.duplicateAssignedTextBoxIDs == ["box-a"], "duplicate TextBox ID ledger must be deterministic")

        let invalidPartition = evaluate(
            matched: [0, 1],
            succeeded: [0],
            failed: [0],
            skipped: [1],
            textBoxIDs: ["box-a", "box-b"]
        )
        require(invalidPartition.coverageVerdict == "inconsistentAssignmentLedger", "overlapping outcomes must invalidate coverage")
        require(!invalidPartition.outcomePartitionValid, "overlapping outcomes must fail partition validation")
    }

    private static func evaluate(
        matched: [Int],
        succeeded: [Int],
        failed: [Int],
        skipped: [Int],
        textBoxIDs: [String]
    ) -> MangaOverlayExternalTextBoxCoverageEvaluation {
        MangaOverlayExternalTextBoxCoverageEvaluator.evaluate(
            evaluatedBlockIndexes: [0, 1],
            matchedBlockIndexes: matched,
            succeededBlockIndexes: succeeded,
            failedBlockIndexes: failed,
            skippedBlockIndexes: skipped,
            matchedTextBoxIDs: textBoxIDs
        )
    }

    private static func testLegacyReportDecoding() throws {
        let legacyJSON = #"""
        {
          "enabled": true,
          "executed": false,
          "gateVerdict": "manifestMissing",
          "activeArtifactsDirectory": false,
          "contractExampleOnly": false,
          "externalTextBoxesShadowOCRAllowed": false,
          "shadowOnly": true,
          "groundTruthNotUsed": true,
          "doesNotChangeFinalTextUsedForTranslation": true,
          "doesNotChangeMainOverlay": true,
          "candidateCount": 0,
          "ocrExecutedCount": 0,
          "ocrSucceededCount": 0,
          "betterThanControlCount": 0,
          "promotedExternalShadowBlocks": [],
          "wouldPromoteByExistingGateBlocks": [],
          "skippedBlocks": [0, 1],
          "sourceDirectionBreakdown": {},
          "orientationCategoryBreakdown": {},
          "linePolygonCandidateBlocks": [],
          "rotationCandidateBlocks": [],
          "verticalCandidateBlocks": [],
          "orientationShadowPathNeededBlocks": [],
          "orientationShadowPathExecutedBlocks": [],
          "orientationShadowPathPartialBlocks": [],
          "orientationShadowPathNotExecutedBlocks": [],
          "orientationUnsupportedBlocks": [],
          "orientationUnsupportedReasonBreakdown": {},
          "orientationReadinessVerdict": "blockedByReadinessGate",
          "blockSummaries": [],
          "candidates": [],
          "notes": []
        }
        """#
        let report = try JSONDecoder().decode(
            MangaOverlayExternalTextBoxShadowOCRReport.self,
            from: Data(legacyJSON.utf8)
        )
        require(report.evaluatedBlockCount == nil, "legacy reports must decode without v2.0 evaluated count")
        require(report.coverageVerdict == nil, "legacy reports must decode without v2.0 coverage verdict")
        require(report.duplicateAssignmentLedgers == nil, "legacy reports must decode without v2.0 contention ledger")
    }
}
