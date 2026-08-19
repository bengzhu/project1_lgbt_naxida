#!/usr/bin/env python3
"""Contract for bounded Japanese vertical tile reconnaissance before crop OCR."""

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


class JapaneseVerticalTileFallbackContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.recognize = braced_body(
            self.vision,
            "func recognizeTextBlocksWithShadowLedger(",
        )
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.coverage = braced_body(
            self.vision,
            "private static func verticalTileIsCovered(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_tile_fallback_is_reached_from_japanese_crop_boundary(self) -> None:
        self.assertIn("if sourceLanguage == .japanese", self.recognize)
        self.assertIn(
            "Self.recognizeJapaneseVerticalTileFallback(",
            self.crops,
        )
        self.assertLess(
            self.crops.index("Self.recognizeJapaneseVerticalTileFallback("),
            self.crops.index("let imageSize = CGSize("),
        )

    def test_tiles_are_overlapped_and_hard_bounded(self) -> None:
        for marker in [
            "let maximumTiles = 6",
            "starts.count < maximumTiles",
            "let tileWidth = max(Int((Double(imageWidth) / 4).rounded()), 2)",
            "let overlapPixels = max(Int((Double(tileWidth) * 0.18).rounded()), 1)",
            "let step = max(tileWidth - overlapPixels, 1)",
            "let lastStart = max(imageWidth - tileWidth, 0)",
            "starts[starts.count - 1] = lastStart",
        ]:
            self.assertIn(marker, self.tiles)

    def test_covered_tiles_are_skipped_and_crops_use_shared_mapping(self) -> None:
        self.assertIn("verticalTileIsCovered($0.rect, by: tileRect)", self.tiles)
        self.assertIn("let preparedCrop = prepareJapaneseCropForVision(crop.image)", self.tiles)
        for marker in [
            "angle: 90",
            "angle: 270",
            "minimumTextHeight: 0.003",
            "cropScale: preparedCrop.scale",
            "var orientationFallbacksRemaining = 4",
            "return deduplicateJapaneseObservations(refined)",
        ]:
            self.assertIn(marker, self.tiles)
        self.assertTrue(
            "needsJapaneseOrientationFallback(primary)" in self.tiles
            or "needsJapaneseOrientationFallback(verticalPrimary)" in self.tiles
        )

    def test_coverage_gate_is_directional_and_bounded(self) -> None:
        for marker in [
            "horizontalIntersection",
            "horizontalCoverage",
            "verticalIntersection",
            "verticalCoverage",
            "horizontalCoverage >= 0.45",
            "verticalCoverage >= 0.30",
        ]:
            self.assertIn(marker, self.coverage)

    def test_migration_stays_model_and_probe_independent(self) -> None:
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

    def test_version_and_ci_route_follow_v3184(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 185) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.184;", self.project)
        old = "python3 -B scripts/test-v3184-image-japanese-line-geometry-dedupe-contract.py"
        new = "python3 -B scripts/test-v3185-image-japanese-vertical-tile-fallback-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
