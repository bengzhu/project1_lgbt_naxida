#!/usr/bin/env python3
"""Contract for manga right-to-left scheduling of bounded OCR windows."""

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


class JapaneseMangaWindowOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_budget_is_scheduled_by_height_band_right_to_left_before_ocr(self) -> None:
        for marker in [
            "let verticalWindows = japaneseVerticalSliceWindows(",
            "let mangaOrderedStarts = starts.sorted { $0 > $1 }",
            "for window in verticalWindows",
            "for start in mangaOrderedStarts",
            "guard processedWindowCount < maximumWindows else { return }",
        ]:
            self.assertIn(marker, self.tiles)
        self.assertLess(
            self.tiles.index("for window in verticalWindows"),
            self.tiles.index("for start in mangaOrderedStarts"),
        )

    def test_each_column_keeps_top_to_bottom_slice_order(self) -> None:
        self.assertIn("for window in verticalWindows", self.tiles)
        self.assertIn("for start in mangaOrderedStarts", self.tiles)
        self.assertLess(
            self.tiles.index("for window in verticalWindows"),
            self.tiles.index("for start in mangaOrderedStarts"),
        )
        self.assertIn("y: Double(window.start) / Double(imageHeight)", self.tiles)

    def test_japanese_fallback_boundaries_remain_intact(self) -> None:
        for marker in [
            "verticalTileIsCovered($0.rect, by: tileRect)",
            "let verticalPrimary = filterJapaneseVerticalTileObservations(primary)",
            "var orientationFallbacksRemaining = 4",
            "return deduplicateJapaneseObservations(refined)",
        ]:
            self.assertIn(marker, self.tiles)
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3191(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 192) for version in versions)
        )
        old = "python3 -B scripts/test-v3191-image-japanese-koharu-slicer-contract.py"
        new = "python3 -B scripts/test-v3192-image-japanese-manga-window-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
