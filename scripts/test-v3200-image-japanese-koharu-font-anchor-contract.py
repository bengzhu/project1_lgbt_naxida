#!/usr/bin/env python3
"""Contract for preserving Koharu's block font-size anchor after line union."""

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


class JapaneseKoharuFontAnchorContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.blocks = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.envelope = braced_body(
            self.vision,
            "private static func koharuVerticalBlockCropRect(",
        )
        self.helper = braced_body(
            self.vision,
            "private static func expandedKoharuVerticalBlockEnvelopeCropRect(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_union_keeps_original_block_as_font_anchor(self) -> None:
        self.assertIn(
            "expandedKoharuVerticalBlockEnvelopeCropRect(",
            self.envelope,
        )
        self.assertIn("fontSizeReference: block.rect", self.envelope)
        self.assertIn("fontSizeReference: ImageOCRLayoutRect", self.vision)
        for marker in [
            "koharuVerticalCropPadding(",
            "fontSizeReference,",
            "envelope.x - padding.horizontal",
            "envelope.y - padding.vertical",
            ".normalizedToUnit() ?? envelope",
        ]:
            self.assertIn(marker, self.helper)
        self.assertNotIn("koharuVerticalCropPadding(\n            envelope", self.helper)

    def test_existing_geometry_union_and_safe_fallback_remain(self) -> None:
        for marker in [
            "lineRegions.reduce(block.rect)",
            "partial.union(region)",
            "guard !lineRegions.isEmpty else",
            "return expandedVerticalCropRect(block.rect, imageSize: imageSize)",
            "return expandedVerticalCropRect(envelope, imageSize: imageSize)",
        ]:
            self.assertIn(marker, self.envelope + self.helper)

    def test_scope_stays_ordinary_japanese_block_crop_only(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "TranslationSessionStore",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3199(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 200) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.199;", self.project)
        old = "python3 -B scripts/test-v3199-image-japanese-koharu-block-line-envelope-contract.py"
        new = "python3 -B scripts/test-v3200-image-japanese-koharu-font-anchor-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
