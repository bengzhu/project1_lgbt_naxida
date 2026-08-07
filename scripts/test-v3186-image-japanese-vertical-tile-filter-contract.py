#!/usr/bin/env python3
"""Contract for filtering horizontal noise from Japanese vertical tile rereads."""

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


class JapaneseVerticalTileFilterContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.filter = braced_body(
            self.vision,
            "private static func filterJapaneseVerticalTileObservations(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_filter_is_applied_before_tile_fallback_decision(self) -> None:
        self.assertIn("let verticalPrimary = filterJapaneseVerticalTileObservations(primary)", self.tiles)
        self.assertIn("needsJapaneseOrientationFallback(verticalPrimary)", self.tiles)
        self.assertLess(
            self.tiles.index("filterJapaneseVerticalTileObservations(primary)"),
            self.tiles.index("needsJapaneseOrientationFallback(verticalPrimary)"),
        )
        self.assertIn(
            "filterJapaneseVerticalTileObservations(opposite)",
            self.tiles,
        )

    def test_filter_keeps_japanese_vertical_geometry_only(self) -> None:
        for marker in [
            "let region = observation.lineRegionRect ?? observation.rect",
            "let ratio = region.height / max(region.width, 0.001)",
            "let scriptDensity = japaneseScriptDensity(in: observation.text)",
            "guard scriptDensity >= 0.5 else { return false }",
            "let isTallColumn = region.height >= 0.022 && ratio >= 1.18",
            "let isCompactFragment = region.height >= 0.018",
            "&& ratio >= 0.90",
            "observation.text.unicodeScalars.count <= 2",
        ]:
            self.assertIn(marker, self.filter)

    def test_tile_budget_and_shared_mapping_are_unchanged(self) -> None:
        for marker in [
            "let maximumTiles = 6",
            "let overlapPixels = max(Int((Double(tileWidth) * 0.18).rounded()), 1)",
            "verticalTileIsCovered($0.rect, by: tileRect)",
            "prepareJapaneseCropForVision(crop.image)",
            "angle: 90",
            "angle: 270",
            "minimumTextHeight: 0.003",
            "cropScale: preparedCrop.scale",
            "var orientationFallbacksRemaining = 4",
            "return deduplicateJapaneseObservations(refined)",
        ]:
            self.assertIn(marker, self.tiles)

    def test_model_and_artifact_boundaries_remain_closed(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3185(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 186) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.185;", self.project)
        old = "python3 -B scripts/test-v3185-image-japanese-vertical-tile-fallback-contract.py"
        new = "python3 -B scripts/test-v3186-image-japanese-vertical-tile-filter-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
