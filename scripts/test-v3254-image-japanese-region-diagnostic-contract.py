#!/usr/bin/env python3
"""Contract for the bounded, read-only Japanese region orientation diagnostic."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class JapaneseRegionDiagnosticContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = read(
            "scripts/fixtures/v3254-japanese-region-diagnostic-harness.swift"
        )
        self.runtime = read(
            "scripts/test-v3254-image-japanese-region-diagnostic-runtime.sh"
        )
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")

    def test_matrix_covers_detector_geometry_and_three_orientations(self) -> None:
        for marker in [
            "detectTextRegions(in: image)",
            "detectorRegions=",
            "diagnosticRegions=",
            "diagnosticJapanesePixelFirstRegions(in: image)",
            "diagnosticJapaneseCompactCropReads(in: tallImage)",
            "longPixelFirstRegions=",
            "longCompactPixelRegions=",
            "longBlocks=",
            "detectorConfidence=",
            "rotate270Applied=",
            "DiagnosticOrientation.natural",
            "DiagnosticOrientation.rotate90",
            "DiagnosticOrientation.rotate270",
            "\\(orientation.rawValue)JapaneseDensity",
        ]:
            self.assertIn(marker, self.harness)

    def test_compact_gate_is_bounded_and_can_compete_with_a_weak_owner(self) -> None:
        for marker in [
            "isJapanesePixelFirstCompactCandidate",
            "(2...4).contains(characterCount)",
            "rect.width <= 0.08",
            "rect.height <= 0.08",
            "if unique.count == 128",
            "let reservedCompact = Array(compactCandidates.prefix(4))",
            "let remaining = max(0, 12 - reservedCompact.count)",
            "isWeakCompactJapaneseOwner",
            "observation.confidence < 0.80",
            "isCompactJapaneseRecovery",
            "promoteCompactJapaneseHorizontalObservations",
            "isUsableCompactJapaneseRecovery",
            "isBetterCompactJapaneseRecovery",
        ]:
            self.assertIn(marker, self.vision)

    def test_diagnostic_uses_existing_bounded_services_without_changing_request_budget(self) -> None:
        self.assertIn("MangaOCRService.shared", self.harness)
        self.assertIn("Array(detectorRegions.prefix(12))", self.harness)
        self.assertIn("MangaOCRRequest(", self.harness)
        self.assertIn("VisionOCRService.diagnosticJapanesePixelFirstRegions", self.harness)
        self.assertIn("VisionOCRService().recognizeTextBlocks", self.harness)
        self.assertIn("recognizeJapaneseMangaOCR(", self.vision)
        self.assertIn("Array(regions.prefix(12))", self.vision)
        self.assertIn("let requestsPerSlice = 12", self.vision)
        self.assertIn("let maximumRequests = 48", self.vision)
        self.assertIn("private static func cropImages(", self.manga)

    def test_layout_keeps_compact_recovery_as_a_separate_block(self) -> None:
        layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.assertIn(
            "guard !(line.preservesDetectorTextRegionBoundary\n            && cluster.containsPreservedDetectorTextRegionBoundary)",
            layout,
        )

    def test_runtime_oracle_is_sample_specific_and_not_a_general_ocr_claim(self) -> None:
        self.assertIn("test/jap.jpg", self.runtime)
        self.assertIn("expected five or six detector regions", self.runtime)
        self.assertIn("compactOwnerObserved", self.runtime)
        self.assertIn("production Vision fusion still owns the final", self.runtime)
        self.assertIn("expected twenty bounded long-page blocks", self.runtime)
        self.assertIn("expected four bounded compact vertical blocks", self.runtime)
        self.assertIn("compactTextSummary=host-variant", self.runtime)
        self.assertIn("940873", self.runtime)
        self.assertIn("text=．．．では最後", self.runtime)
        self.assertNotIn("runImageTranslationPipeline", self.runtime)

    def test_ci_and_version_are_advanced(self) -> None:
        previous = (
            "python3 -B scripts/test-v3255-image-japanese-manga-ocr-batch-eos-alignment-contract.py"
        )
        current = (
            "python3 -B scripts/test-v3256-image-review-direction-filter-focus-contract.py"
        )
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "bash scripts/test-v3254-image-japanese-region-diagnostic-runtime.sh",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.332", "3.332"])
        self.assertNotIn("MARKETING_VERSION = 3.255;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
