#!/usr/bin/env python3
"""Static and validator contracts for v1.92 line polygon warp shadow OCR."""

from pathlib import Path
import importlib.util
import json
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuLinePolygonWarpContractTests(unittest.TestCase):
    def test_warp_is_bounded_and_uses_top_left_coordinate_conversion(self) -> None:
        service = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.assertIn("import CoreImage", service)
        self.assertIn('CIFilter(name: "CIPerspectiveCorrection")', service)
        self.assertIn("ciHeight - corners[0].y", service)
        self.assertIn("guard polygon.count == 4", service)
        self.assertIn("let maximumLineCount = 24", service)
        self.assertIn("let maximumTotalOutputPixels: CGFloat = 16_000_000", service)
        self.assertIn("linePolygonWarpRequiresFourPoints", service)
        self.assertIn("let centroid = CGPoint(", service)
        self.assertIn("let convex = crossProducts.allSatisfy", service)
        self.assertIn('ocrPath: "bboxFallbackAfterEmptyLinePolygonWarpOCR"', service)
        self.assertIn('bboxFallbackReason: "linePolygonWarpOCRReturnedEmpty"', service)
        self.assertIn("for (index, polygon) in linePolygons.enumerated()", service)
        self.assertIn("failureReasons.append(error.reason)", service)
        self.assertIn("linePolygonWarpLineExecutionFailed", service)
        self.assertIn("if warpedLineCount == 0, !failureReasons.isEmpty", service)
        self.assertIn("linePolygonWarpAllLinesFailed", service)
        self.assertIn('failureReasons.append("linePolygonWarpOCRReturnedEmpty:\\(index)")', service)
        self.assertIn("lineFailureReasons: failureReasons", service)
        self.assertIn("linePolygonWarpFailureReasons: warpFailureReasons", service)
        self.assertIn('"linePolygonPerspectiveWarpPartial"', service)

    def test_store_keeps_warp_shadow_only_and_blocks_failed_warp(self) -> None:
        store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.assertIn("linePolygons: selected.textBox.linePolygons", store)
        self.assertIn('orientationUnsupportedReasons.append("linePolygonWarpFailed")', store)
        self.assertIn("deskewExecuted: linePolygonWarpOutputSelected", store)
        self.assertIn('variantName: linePolygonWarpOutputSelected', store)
        self.assertIn(
            '["linePolygonPerspectiveWarp", "linePolygonPerspectiveWarpPartial"].contains(crop.ocrPath)',
            store,
        )
        self.assertIn('orientationUnsupportedReasons.append("linePolygonWarpOutputNotSelected")', store)
        self.assertIn('orientationUnsupportedReasons.append("linePolygonWarpPartialFailure")', store)
        self.assertIn('!blockers.contains("linePolygonWarpPartialFailure")', store)
        self.assertIn('crop.ocrPath == "linePolygonPerspectiveWarpPartial"', store)
        self.assertIn('"externalArtifact.linePolygonWarpPartial"', store)
        self.assertIn("warpError?.lineFailureReasons.isEmpty == false", store)
        self.assertIn(
            "let linePolygonWarpFailureReasons = Array(Set(crop.linePolygonWarpFailureReasons)).sorted()",
            store,
        )
        self.assertNotIn("Set(attempts.flatMap(\\.linePolygonWarpFailureReasons))", store)
        self.assertIn('!blockers.contains("linePolygonWarpOutputNotSelected")', store)
        self.assertIn("if lhsText.isEmpty != rhsText.isEmpty", store)
        self.assertIn("if lhs.linePolygonWarpExecuted != rhs.linePolygonWarpExecuted", store)
        self.assertLess(
            store.index("if lhsText.isEmpty != rhsText.isEmpty"),
            store.index("if lhs.linePolygonWarpExecuted != rhs.linePolygonWarpExecuted"),
        )
        self.assertIn('"wouldPromoteByExistingGateReportOnly"', store)
        self.assertNotIn('unsupportedReasons.append("linePolygonWarpUnsupported")', store)
        self.assertNotIn("line-polygon warp remain unsupported", store)

    def test_validator_reports_only_four_point_warp_as_supported(self) -> None:
        result = subprocess.run(
            [
                "python3",
                "-B",
                "scripts/validate-koharu-artifacts.py",
                "--root",
                "md/koharu研究/artifact_contract/examples/valid_orientation_partial_unsupported",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        data = json.loads(result.stdout)
        orientation = data["orientationMetadataSummary"]
        self.assertTrue(orientation["currentShadowOCRSupport"]["linePolygonWarp"])
        self.assertTrue(
            orientation["currentShadowOCRSupport"]["linePolygonWarpRequiresExactlyFourPoints"]
        )
        self.assertIn(
            "orientation-partial-vertical-linepolygon",
            orientation["orientationLinePolygonWarpSupportedTextBoxIDs"],
        )
        reasons = orientation["orientationUnsupportedReasonBreakdown"]
        self.assertNotIn("linePolygonWarpUnsupported", reasons)
        self.assertGreater(reasons.get("arbitraryRotationUnsupported", 0), 0)

    def test_validator_rejects_five_point_polygon_from_warp_support(self) -> None:
        validator_path = ROOT / "scripts/validate-koharu-artifacts.py"
        spec = importlib.util.spec_from_file_location("koharu_validator", validator_path)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        summary = module.summarize_orientation_metadata(
            [
                {
                    "id": "five-point",
                    "sourceDirection": "horizontal",
                    "linePolygons": [[[0, 0], [10, 0], [12, 5], [10, 10], [0, 10]]],
                }
            ]
        )
        self.assertNotIn(
            "five-point", summary["orientationLinePolygonWarpSupportedTextBoxIDs"]
        )
        self.assertIn("five-point", summary["orientationUnsupportedTextBoxIDs"])
        self.assertEqual(
            summary["orientationUnsupportedReasonBreakdown"][
                "linePolygonWarpRequiresFourPoints"
            ],
            1,
        )

        degenerate = module.summarize_orientation_metadata(
            [
                {
                    "id": "repeated-point",
                    "sourceDirection": "horizontal",
                    "linePolygons": [[[0, 0], [10, 0], [10, 0], [0, 10]]],
                }
            ]
        )
        self.assertNotIn(
            "repeated-point",
            degenerate["orientationLinePolygonWarpSupportedTextBoxIDs"],
        )
        self.assertEqual(
            degenerate["orientationUnsupportedReasonBreakdown"][
                "linePolygonWarpShapeUnsupported"
            ],
            1,
        )

    def test_cloud_static_checks_run_this_contract(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        self.assertIn("python3 -B scripts/test-v192-koharu-line-polygon-warp-contract.py", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
