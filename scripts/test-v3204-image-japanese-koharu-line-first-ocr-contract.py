#!/usr/bin/env python3
"""Contract for Koharu line-first OCR with block fallback for Japanese crops."""

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


class JapaneseKoharuLineFirstOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.line = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_line_regions_run_before_block_crop(self) -> None:
        line_call = self.crops.index(
            "let lineRefined = Self.recognizeJapaneseVerticalLineCrops("
        )
        block_crop_call = self.crops.index(
            "let primary = recognizeJapaneseCropPass("
        )
        self.assertLess(line_call, block_crop_call)
        self.assertIn("refined.append(contentsOf: lineRefined)", self.crops)

    def test_block_crop_is_only_fallback_when_line_reread_has_no_result(self) -> None:
        guard_marker = "let hasLineOCRResult = lineRefined.contains"
        guard_start = self.crops.index(guard_marker)
        guard_end = self.crops.index("let angle =", guard_start)
        guard_region = self.crops[guard_start:guard_end]
        self.assertIn("overlapRatio(observation.rect, block.rect) >= 0.25", guard_region)
        self.assertIn(
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            guard_region,
        )
        self.assertIn("guard !hasLineOCRResult else { continue }", guard_region)
        self.assertIn("refined.append(contentsOf: primary)", self.crops)

    def test_line_path_keeps_its_own_bounded_fallbacks(self) -> None:
        self.assertIn("orientationFallbacksRemaining = 12", self.line)
        self.assertIn("perspectiveWarpPixels", self.line)
        self.assertIn("prefix(24)", self.line)
        self.assertIn("japaneseLineRegionOverlapsBlock", self.line)

    def test_scope_stays_ordinary_japanese_ocr_only(self) -> None:
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

    def test_version_and_ci_route_follow_v3203(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 204) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.203;", self.project)
        old = "python3 -B scripts/test-v3203-image-japanese-koharu-line-block-ownership-contract.py"
        new = "python3 -B scripts/test-v3204-image-japanese-koharu-line-first-ocr-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
