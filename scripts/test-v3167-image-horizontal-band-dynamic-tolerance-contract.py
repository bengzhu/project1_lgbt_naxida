#!/usr/bin/env python3
"""Contract for scale-aware horizontal OCR row grouping."""

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


class HorizontalBandDynamicToleranceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.horizontal = braced_body(
            self.layout,
            "private static func orderedHorizontalBands(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_row_tolerance_uses_current_box_height_with_bounds(self) -> None:
        for marker in [
            "let rowTolerance = min(",
            "max(median(observations.map(\\.rect.height)) * 0.55, 0.012)",
            "0.04",
            "observation.rect.y - anchor <= rowTolerance",
        ]:
            self.assertIn(marker, self.horizontal)
        self.assertNotIn("observation.rect.y - anchor <= 0.02", self.horizontal)

    def test_rtl_and_ltr_axis_order_remains_explicit(self) -> None:
        self.assertIn("prefersRightToLeft: Bool", self.layout)
        self.assertIn("prefersRightToLeft ? -$0.rect.x : $0.rect.x", self.horizontal)
        self.assertIn("prefersRightToLeft ? -$1.rect.x : $1.rect.x", self.horizontal)
        self.assertIn("anchor", self.horizontal)

    def test_scope_stays_layout_only(self) -> None:
        for forbidden in [
            "VisionOCRService",
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.layout)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3166(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 167) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.166;", self.project)
        old = "python3 -B scripts/test-v3166-image-japanese-punctuation-column-contract.py"
        new = "python3 -B scripts/test-v3167-image-horizontal-band-dynamic-tolerance-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
