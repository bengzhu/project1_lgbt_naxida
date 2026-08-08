#!/usr/bin/env python3
"""Contract for bounded localized Japanese vertical reconnaissance windows."""

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


class JapaneseLocalizedTileWindowContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_full_height_strips_are_split_into_overlapping_local_windows(self) -> None:
        self.assertRegex(self.tiles, r"let maximumWindows = (12|18)")
        self.assertTrue(
            "japaneseVerticalSliceWindows(" in self.tiles
            or "Int((Double(imageHeight) * 0.58).rounded())" in self.tiles
        )
        self.assertTrue(
            "let verticalWindows =" in self.tiles
            or "var verticalStarts: [Int] = []" in self.tiles
        )

    def test_every_crop_uses_local_y_geometry_and_a_hard_total_budget(self) -> None:
        for marker in [
            "guard processedWindowCount < maximumWindows else { break }",
            "height: Double(pixelHeight) / Double(imageHeight)",
            "processedWindowCount += 1",
        ]:
            self.assertIn(marker, self.tiles)
        self.assertTrue(
            "for window in verticalWindows" in self.tiles
            or "for verticalStart in verticalStarts" in self.tiles
        )
        self.assertTrue(
            "y: Double(window.start) / Double(imageHeight)" in self.tiles
            or "y: Double(verticalStart) / Double(imageHeight)" in self.tiles
        )
        self.assertTrue(
            "let pixelHeight = window.height" in self.tiles
            or "let pixelHeight = min(windowHeight, imageHeight - verticalStart)" in self.tiles
        )
        self.assertLess(
            self.tiles.index("processedWindowCount += 1"),
            self.tiles.index("let preparedCrop = prepareJapaneseCropForVision(crop.image)"),
        )

    def test_existing_filter_mapping_and_orientation_budget_remain_in_force(self) -> None:
        for marker in [
            "verticalTileIsCovered($0.rect, by: tileRect)",
            "let preparedCrop = prepareJapaneseCropForVision(crop.image)",
            "let verticalPrimary = filterJapaneseVerticalTileObservations(primary)",
            "var orientationFallbacksRemaining = 4",
            "angle: 90",
            "angle: 270",
            "cropScale: preparedCrop.scale",
            "return deduplicateJapaneseObservations(refined)",
        ]:
            self.assertIn(marker, self.tiles)

    def test_migration_stays_on_the_japanese_vision_fallback_boundary(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3189(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 190) for version in versions)
        )
        old = "python3 -B scripts/test-v3189-image-japanese-single-glyph-direction-hint-contract.py"
        new = "python3 -B scripts/test-v3190-image-japanese-localized-tile-window-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
