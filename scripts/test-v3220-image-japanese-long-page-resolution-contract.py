#!/usr/bin/env python3
"""Contract for preserving tall-page resolution before Koharu-style OCR slicing."""

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


class JapaneseLongPageResolutionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_tall_pages_keep_width_before_detector_slicing(self) -> None:
        image = braced_body(self.vision, "private static func makeOCRImage(")
        helper = braced_body(
            self.vision,
            "private static func longPageThumbnailMaxPixelSize(",
        )
        for marker in [
            "let thumbnailMaxPixelSize = longPageThumbnailMaxPixelSize(for: source)",
            "kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize",
        ]:
            self.assertIn(marker, image)
        for marker in [
            "CGImageSourceCopyPropertiesAtIndex(source, 0, nil)",
            "kCGImagePropertyPixelWidth",
            "kCGImagePropertyPixelHeight",
            "let aspectRatio = displayHeight / max(displayWidth, 1)",
            "guard aspectRatio > 3.5 else { return fallback }",
            "let maximumWidth = 1_800.0",
            "let maximumPixels = 16_000_000.0",
            "let widthScale = min(1, maximumWidth / displayWidth)",
            "let pixelScale = min(1, sqrt(maximumPixels / (displayWidth * displayHeight)))",
        ]:
            self.assertIn(marker, helper)
        self.assertNotIn(
            "kCGImageSourceThumbnailMaxPixelSize: 1_800",
            image,
        )

    def test_detector_text_region_is_not_bisected_by_vision_supplement(self) -> None:
        manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        crop = braced_body(
            self.vision,
            "private static func japaneseMangaOCRCropRect(",
        )
        self.assertIn("japaneseMangaOCRCropRect(\n                    region,", manga)
        self.assertIn(
            "_ region: JapanesePixelFirstRegion",
            self.vision,
        )
        for marker in [
            "let rect = region.rect",
            "guard case .vision = region.detector else",
            "return expanded",
            "for neighbor in regions where neighbor.rect != rect",
        ]:
            self.assertIn(marker, crop)

    def test_runtime_rejects_known_low_resolution_manga_ocr_errors(self) -> None:
        for marker in [
            'for rejected in ["撮乳", "城乳", "授乳", "技拶"]',
            'sum("爆乳" in value for value in vertical_texts) < 4',
            'sum("挨拶" in value for value in vertical_texts) < 4',
            '"image=1136x6400"',
            '"お願いします前は" in text',
        ]:
            self.assertIn(marker, self.runtime)

    def test_scope_keeps_model_and_fallback_boundaries(self) -> None:
        for source in [self.vision, self.manga]:
            for forbidden in [
                "TranslationSessionStore",
                "MangaOverlayProbeService",
                "groundTruth",
                "test/koharu_artifacts",
                "metrics/version_history.csv",
                "output/",
            ]:
                self.assertNotIn(forbidden, source)

    def test_version_and_ci_route_follow_v3219(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        previous = "python3 -B scripts/test-v3219-image-japanese-detector-boundary-contract.py"
        current = "python3 -B scripts/test-v3220-image-japanese-long-page-resolution-contract.py"
        runtime = "bash scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertLess(self.workflow.index(current), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3220-image-japanese-long-page-resolution-contract.py'",
            self.workflow,
        )
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 220) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.219;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
