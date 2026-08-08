#!/usr/bin/env python3
"""Contract for Koharu-style line-region envelopes around Japanese block crops."""

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


class JapaneseKoharuBlockLineEnvelopeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.block_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.envelope = braced_body(
            self.vision,
            "private static func koharuVerticalBlockCropRect(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_block_crop_consumes_related_line_regions_without_shrinking_block(self) -> None:
        self.assertIn("koharuVerticalBlockCropRect(", self.block_crops)
        self.assertNotIn(
            "normalizedRect: expandedVerticalCropRect(block.rect, imageSize: imageSize)",
            self.block_crops,
        )
        for marker in [
            "overlapRatio(observation.rect, block.rect) >= 0.25",
            ".compactMap(\\.lineRegionRect)",
            ".compactMap { $0.normalizedToUnit() }",
            "lineRegions.reduce(block.rect)",
            "partial.union(region)",
        ]:
            self.assertIn(marker, self.envelope)

    def test_missing_or_invalid_line_geometry_falls_back_to_existing_crop(self) -> None:
        for marker in [
            "guard !lineRegions.isEmpty else",
            "return expandedVerticalCropRect(block.rect, imageSize: imageSize)",
            "return expandedVerticalCropRect(envelope, imageSize: imageSize)",
        ]:
            self.assertIn(marker, self.envelope)
        self.assertIn("imageSize: imageSize", self.block_crops)

    def test_scope_remains_ordinary_japanese_block_crop_only(self) -> None:
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

    def test_version_and_ci_route_follow_v3198(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 199) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.198;", self.project)
        old = "python3 -B scripts/test-v3198-image-japanese-koharu-vertical-line-orientation-contract.py"
        new = "python3 -B scripts/test-v3199-image-japanese-koharu-block-line-envelope-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
