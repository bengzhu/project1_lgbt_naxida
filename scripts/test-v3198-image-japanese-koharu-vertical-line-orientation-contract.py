#!/usr/bin/env python3
"""Contract for Koharu's preferred 270-degree Japanese vertical line reread."""

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


class JapaneseKoharuVerticalLineOrientationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.line_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.block_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.orientation = braced_body(
            self.vision,
            "private static func koharuPreferredJapaneseVerticalLineOrientation(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_vertical_line_path_prefers_koharu_rotate270(self) -> None:
        self.assertIn("rotate270", self.vision)
        self.assertIn("270", self.orientation)
        self.assertEqual(
            self.line_crops.count(
                "koharuPreferredJapaneseVerticalLineOrientation()"
            ),
            2,
        )
        for marker in [
            "let angle = koharuPreferredJapaneseVerticalLineOrientation()",
            "recognizeJapanesePerspectiveLineCrop(",
            "recognizeJapaneseCropPass(",
        ]:
            self.assertIn(marker, self.line_crops)

    def test_weak_line_results_still_use_bounded_opposite_fallback(self) -> None:
        for marker in [
            "var orientationFallbacksRemaining = 12",
            "needsJapaneseOrientationFallback(meaningfulPerspective)",
            "needsJapaneseOrientationFallback(meaningfulPrimary)",
            "orientationFallbacksRemaining -= 1",
            "oppositeJapaneseOrientation(angle)",
        ]:
            self.assertIn(marker, self.line_crops)
        self.assertIn("angle == 270 ? 90 : 270", self.vision)

    def test_scope_does_not_change_block_or_tile_orientation_boundaries(self) -> None:
        self.assertIn("$0.rotationApplied == 270 ? 270 : 90", self.block_crops)
        self.assertIn("angle: 90", self.tiles)
        self.assertIn("angle: 270", self.tiles)
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "TranslationSessionStore",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_existing_line_budgets_and_fixture_remain_present(self) -> None:
        for marker in [
            "let perspectiveCandidates = Array(",
            ".prefix(24)",
            "consumedPixels: &perspectiveWarpPixels",
            "preparedPixels <= 4_000_000",
            "consumedPixels + preparedPixels <= 16_000_000",
        ]:
            self.assertIn(marker, self.line_crops + self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3197(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 198) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.197;", self.project)
        old = "python3 -B scripts/test-v3197-image-japanese-koharu-vertical-threshold-contract.py"
        new = "python3 -B scripts/test-v3198-image-japanese-koharu-vertical-line-orientation-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
