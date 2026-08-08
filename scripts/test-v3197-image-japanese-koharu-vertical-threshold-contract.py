#!/usr/bin/env python3
"""Contract for Koharu's bounded vertical detector threshold in Japanese block crops."""

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


class JapaneseKoharuVerticalThresholdContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.pipeline = braced_body(self.vision, "func recognizeTextBlocks(")
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_koharu_detector_threshold_is_bounded_and_reaches_block_crop(self) -> None:
        for marker in [
            "let isKoharuDetectorVerticalCandidate = aspectRatio >= 1.15",
            "&& block.rect.height >= 0.035",
            "&& block.directionConfidence >= 0.25",
            "|| isKoharuDetectorVerticalCandidate",
            ".prefix(16)",
        ]:
            self.assertIn(marker, self.crops)
        self.assertLess(
            self.crops.index("let isKoharuDetectorVerticalCandidate"),
            self.crops.index(".prefix(16)"),
        )

    def test_existing_standard_and_compact_safety_gates_remain(self) -> None:
        for marker in [
            "let isStandardVerticalCandidate = aspectRatio >= 1.45",
            "let hasCompactDirectionReason = block.directionReason",
            "let isCompactVerticalCandidate = hasCompactDirectionReason",
            "aspectRatio >= 1.20",
            "block.rect.height >= 0.022",
            "return block.direction == .vertical",
        ]:
            self.assertIn(marker, self.crops)
        self.assertIn("ImageOCRLayoutEngine.layout(", self.crops)
        self.assertIn("prefersMangaReadingOrder: true", self.crops)

    def test_threshold_is_japanese_crop_only_and_does_not_load_models_or_probe_data(self) -> None:
        self.assertIn("if sourceLanguage == .japanese", self.pipeline)
        self.assertIn("Self.recognizeJapaneseVerticalCrops(", self.pipeline)
        self.assertNotIn("recognizeJapaneseVerticalCrops(", self.vision.split("if sourceLanguage == .japanese", 1)[0])
        for forbidden in [
            "MangaOCR",
            "PaddleOCR",
            "MangaOverlayProbeService",
            "TranslationSessionStore",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.crops)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3196(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 197) for version in versions)
        )
        old = "python3 -B scripts/test-v3196-image-japanese-koharu-batch-translation-contract.py"
        new = "python3 -B scripts/test-v3197-image-japanese-koharu-vertical-threshold-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
