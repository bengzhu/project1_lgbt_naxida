#!/usr/bin/env python3
"""Contract for the bounded Japanese vertical-orientation OCR path."""

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


class JapaneseOrientationOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(
            self.vision,
            "func recognizeTextBlocks(in imageData: Data, sourceLanguage: SupportedLanguage)",
        )

    def test_japanese_uses_a_bounded_koharu_style_orientation_pass(self) -> None:
        for marker in [
            "if sourceLanguage == .japanese",
            "Self.rotatedImage(ocrImage, angle: 90)",
            '["ja-JP", "ja", "en-US", "en"]',
            "minimumTextHeight: 0.006",
            "automaticallyDetectsLanguage: false",
            "rotationApplied: 90",
        ]:
            self.assertIn(marker, self.recognize)

    def test_rotated_boxes_are_mapped_back_and_fused_before_layout(self) -> None:
        for marker in [
            "Self.mapRotatedObservation(",
            "mapPointToOriginal",
            "originalSize.width - point.y",
            "deduplicateObservations(observations)",
            "ImageOCRLayoutEngine.layout(",
        ]:
            self.assertIn(marker, self.vision)
        self.assertLess(
            self.vision.index("deduplicateObservations(observations)"),
            self.vision.index("ImageOCRLayoutEngine.layout("),
        )

    def test_existing_direction_layout_and_normal_path_remain(self) -> None:
        for marker in [
            "recognitionLevel = .accurate",
            "usesLanguageCorrection = true",
            "minimumTextHeight: 0.012",
            "sourceLanguage == .japanese || sourceLanguage == .simplifiedChinese",
            "verticalRatio >= 1.6",
            "orderedVerticalBands",
        ]:
            self.assertIn(marker, self.vision if "Ratio" not in marker and "Bands" not in marker else self.layout)

    def test_orientation_path_is_bounded_and_does_not_read_koharu_artifacts(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
        ]:
            self.assertNotIn(forbidden, self.vision)
        self.assertIn("private static func rotatedImage", self.vision)
        self.assertIn("case 90:", self.vision)

    def test_migration_stays_aligned_with_koharu_crop_then_ocr_boundary(self) -> None:
        self.assertIn("Koharu keeps detection/layout separate from recognition", self.vision)
        self.assertIn("existing layout engine restore manga right-to-left vertical order", self.vision)

    def test_japanese_reference_fixture_is_present(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        payload = fixture.read_bytes()
        self.assertGreater(len(payload), 100_000)
        self.assertTrue(payload.startswith(b"\xff\xd8"))

    def test_version_and_ci_route_follow_v3155(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 156) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.155;", self.project)
        old = "python3 -B scripts/test-v3155-image-empty-result-retry-action-contract.py"
        new = "python3 -B scripts/test-v3156-image-japanese-orientation-ocr-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("15[6]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
