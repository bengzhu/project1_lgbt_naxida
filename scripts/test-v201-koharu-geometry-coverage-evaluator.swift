import Foundation

struct MangaOverlayBubbleGeometryDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlaySliceOCRDiagnostics: Equatable, Codable, Sendable {}
struct MangaOverlayCropFallbackSelfTest: Equatable, Codable, Sendable {}

@main
private enum V201KoharuGeometryCoverageContract {
    static func main() throws {
        testAssignmentGeometry()
        testCoverageGeometryGate()
        try testLegacyReportDecoding()
        print("v2.1 Swift geometry coverage contract passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private static func geometry(
        iou: Double,
        centerContained: Bool = false,
        blockBubbleID: String? = "bubble-a",
        textBoxBubbleID: String? = "bubble-a"
    ) -> MangaOverlayExternalTextBoxGeometryEvaluation {
        MangaOverlayExternalTextBoxGeometryEvaluator.evaluate(
            iou: iou,
            centerContained: centerContained,
            blockBubbleID: blockBubbleID,
            textBoxBubbleID: textBoxBubbleID
        )
    }

    private static func testAssignmentGeometry() {
        require(geometry(iou: 0.009).spatialGeometryVerdict == "rejectedNoSpatialEvidence", "IoU below the weak edge threshold must be rejected")
        require(!geometry(iou: 0.011).assignmentGeometryTrusted, "weak overlap must remain shadow-only")
        require(geometry(iou: 0.10).assignmentGeometryTrusted, "trusted IoU boundary must pass")
        require(geometry(iou: 0.02, centerContained: true).assignmentGeometryTrusted, "center containment must provide trusted spatial evidence")

        let conflict = geometry(iou: 0.4, textBoxBubbleID: "bubble-b")
        require(conflict.bubbleAlignmentVerdict == "conflict", "different Bubble IDs must conflict")
        require(!conflict.assignmentGeometryTrusted, "Bubble conflict must block geometry trust")

        let unknown = geometry(iou: 0.4, textBoxBubbleID: nil)
        require(unknown.bubbleAlignmentVerdict == "unknown", "missing Bubble identity must be unknown")
        require(!unknown.assignmentGeometryTrusted, "unknown Bubble alignment must not be trusted")
    }

    private static func testCoverageGeometryGate() {
        let blocked = MangaOverlayExternalTextBoxCoverageEvaluator.evaluate(
            evaluatedBlockIndexes: [0, 1],
            matchedBlockIndexes: [0, 1],
            succeededBlockIndexes: [0, 1],
            failedBlockIndexes: [],
            skippedBlockIndexes: [],
            matchedTextBoxIDs: ["box-a", "box-b"],
            geometryTrustedBlockIndexes: [0],
            geometryUnknownBubbleBlockIndexes: [1]
        )
        require(blocked.coverageVerdict == "geometryBlocked", "full OCR success with weak geometry must stay blocked")
        require(blocked.geometryCoverageVerdict == "partial", "mixed geometry trust must be partial")
        require(blocked.geometryWeakBlockIndexes == [1], "weak geometry ledger must identify the affected block")
        require(blocked.geometryUnknownBubbleBlockIndexes == [1], "unknown Bubble ledger must be preserved")
        require(blocked.geometryCoverageRatio == 0.5, "geometry ratio must use all evaluated blocks")

        let complete = MangaOverlayExternalTextBoxCoverageEvaluator.evaluate(
            evaluatedBlockIndexes: [0, 1],
            matchedBlockIndexes: [0, 1],
            succeededBlockIndexes: [0, 1],
            failedBlockIndexes: [],
            skippedBlockIndexes: [],
            matchedTextBoxIDs: ["box-a", "box-b"],
            geometryTrustedBlockIndexes: [0, 1]
        )
        require(complete.coverageVerdict == "complete", "all strong successful assignments must complete coverage")
        require(complete.geometryCoverageVerdict == "complete", "all strong assignments must complete geometry coverage")
        require(complete.geometryCoverageRatio == 1, "complete geometry coverage ratio must be one")

        let strongButOCRFailed = MangaOverlayExternalTextBoxCoverageEvaluator.evaluate(
            evaluatedBlockIndexes: [0, 1],
            matchedBlockIndexes: [0, 1],
            succeededBlockIndexes: [0],
            failedBlockIndexes: [1],
            skippedBlockIndexes: [],
            matchedTextBoxIDs: ["box-a", "box-b"],
            geometryTrustedBlockIndexes: [0, 1]
        )
        require(strongButOCRFailed.geometryCoverageVerdict == "complete", "geometry coverage must remain independent of OCR outcome")
        require(strongButOCRFailed.geometryWeakBlockIndexes.isEmpty, "strong geometry must not be mislabeled weak when OCR fails")
        require(strongButOCRFailed.coverageVerdict == "partial", "OCR failure must still block overall coverage")
    }

    private static func testLegacyReportDecoding() throws {
        let json = #"""
        {
          "enabled": true, "executed": false, "gateVerdict": "manifestMissing",
          "activeArtifactsDirectory": false, "contractExampleOnly": false,
          "externalTextBoxesShadowOCRAllowed": false, "shadowOnly": true,
          "groundTruthNotUsed": true, "doesNotChangeFinalTextUsedForTranslation": true,
          "doesNotChangeMainOverlay": true, "candidateCount": 0, "ocrExecutedCount": 0,
          "ocrSucceededCount": 0, "betterThanControlCount": 0,
          "promotedExternalShadowBlocks": [], "wouldPromoteByExistingGateBlocks": [],
          "skippedBlocks": [], "sourceDirectionBreakdown": {}, "orientationCategoryBreakdown": {},
          "linePolygonCandidateBlocks": [], "rotationCandidateBlocks": [], "verticalCandidateBlocks": [],
          "orientationShadowPathNeededBlocks": [], "orientationShadowPathExecutedBlocks": [],
          "orientationShadowPathPartialBlocks": [], "orientationShadowPathNotExecutedBlocks": [],
          "orientationUnsupportedBlocks": [], "orientationUnsupportedReasonBreakdown": {},
          "orientationReadinessVerdict": "blockedByReadinessGate", "blockSummaries": [],
          "candidates": [], "notes": []
        }
        """#
        let report = try JSONDecoder().decode(MangaOverlayExternalTextBoxShadowOCRReport.self, from: Data(json.utf8))
        require(report.geometryCoverageVerdict == nil, "v2.0 reports must decode without geometry fields")
    }
}
