#!/usr/bin/env python3
"""Contract for bounded opposite-orientation Japanese crop rereads."""

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


class JapaneseCropOrientationFallbackContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.block_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.line_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.pass_helper = braced_body(
            self.vision,
            "private static func recognizeJapaneseCropPass(",
        )
        self.fallback = braced_body(
            self.vision,
            "private static func needsJapaneseOrientationFallback(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_block_crop_retries_only_weak_results_with_a_small_budget(self) -> None:
        for marker in [
            "var orientationFallbacksRemaining = 8",
            "needsJapaneseOrientationFallback(meaningfulPrimary)",
            "orientationFallbacksRemaining -= 1",
            "oppositeJapaneseOrientation(angle)",
            "minimumTextHeight: 0.004",
        ]:
            self.assertIn(marker, self.block_crops)

    def test_line_crop_reuses_the_same_fallback_boundary(self) -> None:
        for marker in [
            "var orientationFallbacksRemaining = 12",
            "recognizeJapaneseCropPass(",
            "needsJapaneseOrientationFallback(primary)",
            "minimumTextHeight: 0.002",
        ]:
            self.assertIn(marker, self.line_crops)
        self.assertTrue(
            "cropScale: cropScale" in self.line_crops
            or "cropScale: preparedCrop.scale" in self.line_crops
        )

    def test_primary_and_opposite_pass_share_mapping_and_postprocess(self) -> None:
        for marker in [
            "rotatedImage(crop, angle: angle)",
            "postProcessJapaneseText: true",
            "mapRotatedCropObservation(",
            "cropScale: cropScale",
        ]:
            self.assertIn(marker, self.pass_helper)
        self.assertIn("angle == 270 ? 90 : 270", self.vision)

    def test_fallback_gate_requires_weak_orientation_evidence(self) -> None:
        for marker in [
            "best.confidence < 0.48",
            "japaneseScriptDensity(in: best.text) < 0.5",
            "textLength <= 1",
        ]:
            self.assertIn(marker, self.fallback)

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

    def test_version_and_ci_route_follow_v3168(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 169) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.168;", self.project)
        old = "python3 -B scripts/test-v3168-image-japanese-ocr-postprocess-contract.py"
        new = "python3 -B scripts/test-v3169-image-japanese-crop-orientation-fallback-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
