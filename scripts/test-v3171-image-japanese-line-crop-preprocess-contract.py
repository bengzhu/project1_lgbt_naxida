#!/usr/bin/env python3
"""Contract for the shared Koharu-style preprocessing of Japanese line crops."""

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


class JapaneseLineCropPreprocessContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.perspective = braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )
        self.prepare = braced_body(
            self.vision,
            "private static func prepareJapaneseCropForVision(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_axis_aligned_line_crops_share_the_bounded_preprocessor(self) -> None:
        for marker in [
            "let preparedCrop = prepareJapaneseCropForVision(crop.image)",
            "crop: preparedCrop.image",
            "cropScale: preparedCrop.scale",
            "minimumTextHeight: 0.002",
            "needsJapaneseOrientationFallback(meaningfulPrimary)",
        ]:
            self.assertIn(marker, self.lines)
        self.assertNotIn("resizedImage(crop.image, scale: 2)", self.lines)

    def test_perspective_line_crops_charge_prepared_pixels(self) -> None:
        for marker in [
            "let warpedPixels = CGFloat(warped.width) * CGFloat(warped.height)",
            "warpedPixels <= 4_000_000",
            "let preparedCrop = prepareJapaneseCropForVision(warped)",
            "let preparedPixels = CGFloat(preparedCrop.image.width) * CGFloat(preparedCrop.image.height)",
            "preparedPixels <= 4_000_000",
            "consumedPixels + preparedPixels <= 16_000_000",
            "consumedPixels += preparedPixels",
            "rotatedImage(preparedCrop.image, angle: angle)",
        ]:
            self.assertIn(marker, self.perspective)
        self.assertNotIn("resizedImage(warped, scale: 2)", self.perspective)

    def test_preprocessor_still_has_koharu_boundary_and_safe_limits(self) -> None:
        for marker in [
            "grayscaleJapaneseCrop(image) ?? image",
            "sqrt(maximumPixels / pixels)",
            "resizedImage(grayscale, scale: boundedScale)",
            "return (grayscale, 1)",
            "return (resized, boundedScale)",
        ]:
            self.assertIn(marker, self.prepare)
        for marker in [
            "maximumPixels: CGFloat = 4_000_000",
            "preferredScale: CGFloat = 2",
        ]:
            self.assertIn(marker, self.vision)

    def test_scope_stays_in_ordinary_japanese_ocr(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3170(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 171) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.170;", self.project)
        old = "python3 -B scripts/test-v3170-image-japanese-crop-preprocess-contract.py"
        new = "python3 -B scripts/test-v3171-image-japanese-line-crop-preprocess-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
