#!/usr/bin/env python3
"""Contract for porting Koharu ImageSlicer geometry into Japanese OCR."""

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


class JapaneseKoharuSlicerContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.slicer = braced_body(
            self.vision,
            "private static func japaneseVerticalSliceWindows(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_slicer_constants_match_koharu_image_slicer(self) -> None:
        # The reference checkout is research material and is intentionally not
        # required to be present in CI. These values are the constants migrated
        # from Koharu's ImageSlicer::default into the product path below.
        for marker in [
            "let sliceTargetAspectRatio = 3.0",
            "let sliceOverlapRatio = 0.20",
            "let minimumLastSliceRatio = 0.70",
            "Double(stripWidth) * sliceTargetAspectRatio",
            "Double(targetHeight) * (1 - sliceOverlapRatio)",
        ]:
            self.assertIn(marker, self.slicer)

    def test_small_final_slice_is_folded_into_bottom_reaching_window(self) -> None:
        for marker in [
            "Int(ceil(Double(imageHeight) / Double(effectiveHeight)))",
            "let lastStart = (sliceCount - 1) * effectiveHeight",
            "let lastHeight = max(imageHeight - lastStart, 0)",
            "Double(lastHeight) / Double(targetHeight) <= minimumLastSliceRatio",
            "sliceCount -= 1",
            "index + 1 == sliceCount",
            "? imageHeight - start",
        ]:
            self.assertIn(marker, self.slicer)

    def test_tile_fallback_consumes_slices_with_a_bounded_page_budget(self) -> None:
        for marker in [
            "let maximumWindows = 18",
            "let verticalWindows = japaneseVerticalSliceWindows(",
            "imageHeight: imageHeight",
            "stripWidth: tileWidth",
            "for window in verticalWindows",
            "guard processedWindowCount < maximumWindows else { break }",
            "let pixelHeight = window.height",
            "y: Double(window.start) / Double(imageHeight)",
        ]:
            self.assertIn(marker, self.tiles)
        for marker in [
            "var orientationFallbacksRemaining = 4",
            "filterJapaneseVerticalTileObservations(primary)",
            "return deduplicateJapaneseObservations(refined)",
        ]:
            self.assertIn(marker, self.tiles)

    def test_scope_remains_japanese_vision_fallback_only(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        self.assertGreater((ROOT / "test/jap.jpg").stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3190(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.191", "3.191"])
        old = "python3 -B scripts/test-v3190-image-japanese-localized-tile-window-contract.py"
        new = "python3 -B scripts/test-v3191-image-japanese-koharu-slicer-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
