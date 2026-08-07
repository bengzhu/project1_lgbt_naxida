#!/usr/bin/env python3
"""Contract for Koharu font-size-derived Japanese vertical crop padding."""

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


class JapaneseFontSizePaddingContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.padding = braced_body(
            self.vision,
            "private static func koharuVerticalCropPadding(",
        )
        self.blocks = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )

    def test_padding_uses_koharu_font_size_in_pixel_space(self) -> None:
        for marker in [
            "let imageWidth = Double(imageSize.width)",
            "let imageHeight = Double(imageSize.height)",
            "let widthPixels = max(rect.width * imageWidth, 1)",
            "let heightPixels = max(rect.height * imageHeight, 1)",
            "let fontSizePixels = max(min(widthPixels, heightPixels), 1)",
            "let basePaddingPixels = max(fontSizePixels * 0.08, 2)",
            "let horizontalPaddingPixels = max(fontSizePixels * 0.18, basePaddingPixels)",
            "let verticalPaddingPixels = max(fontSizePixels * 0.12, basePaddingPixels)",
            "min(horizontalPaddingPixels / imageWidth, 0.08)",
            "min(verticalPaddingPixels / imageHeight, 0.08)",
        ]:
            self.assertIn(marker, self.padding)

    def test_block_and_line_paths_share_source_pixel_dimensions(self) -> None:
        image_size_marker = "let imageSize = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))"
        self.assertIn(image_size_marker, self.blocks)
        self.assertIn(image_size_marker, self.lines)
        self.assertIn(
            "expandedVerticalCropRect(block.rect, imageSize: imageSize)",
            self.blocks,
        )
        self.assertIn(
            "let cropRect = expandedVerticalLineCropRect(for: candidate, imageSize: imageSize)",
            self.lines,
        )
        self.assertIn("prepareJapaneseCropForVision(crop.image)", self.blocks + self.lines)

    def test_normalized_fallback_and_scope_remain_safe(self) -> None:
        for marker in [
            "imageSize: CGSize? = nil",
            "let padding = imageSize.flatMap { koharuVerticalCropPadding(rect, imageSize: $0) }",
            ".normalizedToUnit() ?? rect",
        ]:
            self.assertIn(marker, self.vision)
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3174(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 175) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.174;", self.project)
        old = "python3 -B scripts/test-v3174-image-japanese-vertical-cluster-gap-contract.py"
        new = "python3 -B scripts/test-v3175-image-japanese-font-size-padding-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
