#!/usr/bin/env python3
"""Contract for separating detector ownership from Japanese vertical direction."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseDetectorDirectionProvenanceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        self.suppression = braced_body(
            self.vision,
            "private static func suppressJapaneseDetectorOwnedPageSupplements(",
        )
        self.horizontal_merge = braced_body(
            self.layout,
            "private static func shouldMergeHorizontally(",
        )
        self.vertical_merge = braced_body(
            self.layout,
            "private static func shouldMergeVertically(",
        )

    def test_detector_node_keeps_ownership_and_explicit_vertical_provenance(self) -> None:
        for marker in [
            "sourceDirectionHint: .vertical",
            "sourceDirectionHint: .vertical",
            "observationRole: .detectorTextRegion",
            "preservesDetectorTextRegionBoundary:",
            "Self.isReliableJapaneseMangaOCRResult(result)",
        ]:
            self.assertIn(marker, self.manga)
        self.assertIn("case detectorTextRegion", self.vision)

    def test_detector_supplement_filter_is_direction_agnostic_and_failure_safe(self) -> None:
        self.assertIn("observation.preservesDetectorTextRegionBoundary", self.suppression)
        self.assertNotIn("observation.observationRole == .verticalLine", self.suppression)
        self.assertIn("guard !detectorOwners.isEmpty else { return observations }", self.suppression)

    def test_each_detector_node_stays_separate_for_both_layout_directions(self) -> None:
        for body in [self.horizontal_merge, self.vertical_merge]:
            self.assertIn("line.preservesDetectorTextRegionBoundary", body)
            self.assertIn("cluster.containsPreservedDetectorTextRegionBoundary", body)
            self.assertIn("return false", body)

    def test_scope_is_japanese_ocr_and_historical_fallbacks_remain(self) -> None:
        self.assertIn("sourceLanguage == .japanese", self.vision)
        self.assertIn("Self.deduplicateObservations(observations)", self.vision)
        self.assertIn("guard !detectorOwners.isEmpty else { return observations }", self.suppression)
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3222(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 223) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.222;", self.project)
        previous = "python3 -B scripts/test-v3222-image-translation-block-retry-focus-contract.py"
        current = "python3 -B scripts/test-v3223-image-japanese-detector-direction-provenance-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3223-image-japanese-detector-direction-provenance-contract.py'",
            self.workflow,
        )

    def test_reference_fixture_is_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
