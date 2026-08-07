#!/usr/bin/env python3
"""Contract for the bounded Koharu-style Japanese crop preprocessor."""

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


class JapaneseCropPreprocessContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.blocks = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.prepare = braced_body(
            self.vision,
            "private static func prepareJapaneseCropForVision(",
        )
        self.grayscale = braced_body(
            self.vision,
            "private static func grayscaleJapaneseCrop(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_vertical_block_crops_use_the_preprocessor_and_preserve_scale(self) -> None:
        for marker in [
            "let preparedCrop = prepareJapaneseCropForVision(crop.image)",
            "crop: preparedCrop.image",
            "cropScale: preparedCrop.scale",
            "minimumTextHeight: 0.004",
            "needsJapaneseOrientationFallback(primary)",
        ]:
            self.assertIn(marker, self.blocks)

    def test_preprocessor_is_bounded_and_falls_back_safely(self) -> None:
        for marker in [
            "sqrt(maximumPixels / pixels)",
            "boundedScale > 1.01",
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

    def test_grayscale_boundary_matches_koharu_crop_preprocess(self) -> None:
        for marker in [
            'CIFilter(name: "CIColorControls")',
            "kCIInputSaturationKey",
            "CIContext(options: [.cacheIntermediates: false])",
            "context.createCGImage(output, from: extent)",
        ]:
            self.assertIn(marker, self.grayscale)
        self.assertIn("grayscaleJapaneseCrop(image) ?? image", self.prepare)

    def test_normal_language_full_page_path_is_not_replaced(self) -> None:
        japanese = braced_body(self.vision, "if sourceLanguage == .japanese {")
        self.assertNotIn("prepareJapaneseCropForVision(ocrImage)", japanese)
        self.assertIn("postProcessJapaneseText: sourceLanguage == .japanese", self.vision)

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

    def test_version_and_ci_route_follow_v3169(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 170) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.169;", self.project)
        old = "python3 -B scripts/test-v3169-image-japanese-crop-orientation-fallback-contract.py"
        new = "python3 -B scripts/test-v3170-image-japanese-crop-preprocess-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
