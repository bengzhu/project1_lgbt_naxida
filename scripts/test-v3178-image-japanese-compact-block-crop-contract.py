#!/usr/bin/env python3
"""Contract for routing compact Japanese vertical blocks through block crops."""

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


class JapaneseCompactBlockCropContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.koharu_manga_ocr = read(
            "reference/koharu-main/koharu-app/src/pipeline/engines/manga_ocr.rs"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_compact_reason_reaches_bounded_block_crop_gate(self) -> None:
        for marker in [
            "let isStandardVerticalCandidate = aspectRatio >= 1.45",
            "block.rect.height >= 0.04",
            "let hasCompactDirectionReason = block.directionReason",
            "cjkCompactColumnTextRun",
            "let isCompactVerticalCandidate = hasCompactDirectionReason",
            "aspectRatio >= 1.20",
            "block.rect.height >= 0.022",
            "return block.direction == .vertical",
            ".prefix(16)",
        ]:
            self.assertIn(marker, self.crops)
        standard = self.crops.index("isStandardVerticalCandidate")
        compact = self.crops.index("isCompactVerticalCandidate")
        final_gate = self.crops.index("return block.direction == .vertical")
        self.assertLess(standard, final_gate)
        self.assertLess(compact, final_gate)

    def test_koharu_block_crop_boundary_is_explicit(self) -> None:
        self.assertIn("crop_text_block_bbox", self.koharu_manga_ocr)
        self.assertIn("texts.iter()", self.koharu_manga_ocr)
        self.assertIn("prefersMangaReadingOrder: true", self.crops)
        self.assertIn("expandedVerticalCropRect(block.rect", self.crops)
        self.assertIn("prepareJapaneseCropForVision", self.crops)

    def test_existing_tall_gate_and_scope_remain_safe(self) -> None:
        for marker in [
            "let isStandardVerticalCandidate = aspectRatio >= 1.45",
            "&& block.rect.height >= 0.04",
            "let isCompactVerticalCandidate = hasCompactDirectionReason",
            "&& aspectRatio >= 1.20",
            "&& block.rect.height >= 0.022",
        ]:
            self.assertIn(marker, self.crops)
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

    def test_version_and_ci_route_follow_v3177(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 178) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.177;", self.project)
        old = "python3 -B scripts/test-v3177-image-japanese-compact-vertical-direction-contract.py"
        new = "python3 -B scripts/test-v3178-image-japanese-compact-block-crop-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
