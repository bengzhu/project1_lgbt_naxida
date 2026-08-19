#!/usr/bin/env python3
"""Contract for the bounded bidirectional Japanese orientation OCR pass."""

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


class JapaneseBidirectionalOrientationOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(
            self.vision,
            "func recognizeTextBlocksWithShadowLedger(",
        )

    def test_japanese_runs_only_the_two_bounded_rotated_directions(self) -> None:
        for marker in [
            "if sourceLanguage == .japanese",
            "for angle in [90, 270]",
            "Self.rotatedImage(ocrImage, angle: angle)",
            "rotationApplied: angle",
            "angle: angle",
            'let japaneseOrientationLanguages = ["ja-JP", "ja", "en-US", "en"]',
            "minimumTextHeight: 0.006",
            "automaticallyDetectsLanguage: false",
        ]:
            self.assertIn(marker, self.recognize)

    def test_both_direction_results_are_mapped_before_dedupe_and_layout(self) -> None:
        for marker in [
            "observations.append(contentsOf: rotatedObservations)",
            "Self.mapRotatedObservation(",
            "mapPointToOriginal",
            "case 270:",
            "CGPoint(x: point.y, y: originalSize.height - point.x)",
            "deduplicateObservations(observations)",
            "ImageOCRLayoutEngine.layout(",
        ]:
            self.assertIn(marker, self.vision)
        self.assertLess(
            self.vision.index("deduplicateObservations(observations)"),
            self.vision.index("ImageOCRLayoutEngine.layout("),
        )

    def test_existing_normal_and_vertical_layout_paths_remain(self) -> None:
        for marker in [
            "minimumTextHeight: 0.012",
            "sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese",
            "verticalRatio >= 1.6",
            "orderedVerticalBands",
        ]:
            self.assertIn(marker, self.vision if "Ratio" not in marker and "Bands" not in marker else read("AITRANS/Services/ImageOCRLayoutEngine.swift"))

    def test_orientation_path_does_not_cross_probe_or_active_artifact_boundaries(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_reference_fixture_is_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        payload = fixture.read_bytes()
        self.assertGreater(len(payload), 100_000)
        self.assertTrue(payload.startswith(b"\xff\xd8"))

    def test_version_and_ci_route_follow_v3156(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 157) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.156;", self.project)
        previous = "python3 -B scripts/test-v3156-image-japanese-orientation-ocr-contract.py"
        current = "python3 -B scripts/test-v3157-image-japanese-bidirectional-orientation-ocr-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn("15[7]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
