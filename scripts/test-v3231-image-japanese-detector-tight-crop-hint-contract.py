#!/usr/bin/env python3
"""Contract for tight, crop-only geometry hints on detector-owned Japanese OCR."""

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


class JapaneseDetectorTightCropHintContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.single_runtime = read(
            "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        )
        self.long_runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.regions = braced_body(
            self.vision,
            "private static func japaneseMangaOCRRegions(",
        )
        self.hint = braced_body(
            self.vision,
            "private static func japaneseDetectorCropHint(",
        )
        self.crop = braced_body(
            self.vision,
            "private static func japaneseMangaOCRCropRect(",
        )

    def test_detector_geometry_remains_layout_owner(self) -> None:
        self.assertIn("rect: detectorRegion.rect", self.regions)
        self.assertIn("cropRectHint: japaneseDetectorCropHint(", self.regions)
        self.assertIn("textRect: region.rect", self.vision)
        self.assertIn("Optional tight character-envelope crop", self.vision)

    def test_hint_requires_full_vertical_character_support(self) -> None:
        for marker in [
            "case .vision = candidate.detector",
            "candidate.characterCount >= 2",
            "isJapanesePixelFirstVerticalCandidate(rect)",
            "overlap >= 0.80",
            "detectorCoverage >= 0.55",
            "candidateCoverage >= 0.80",
            "areaRatio >= 0.35",
            "areaRatio <= 1.05",
            "horizontalCoverage / max(detectorRect.width, 0.001) >= 0.45",
            "verticalCoverage / max(detectorRect.height, 0.001) >= 0.85",
            "rect.width < detectorRect.width * 0.90",
        ]:
            self.assertIn(marker, self.hint)

    def test_hint_changes_crop_only_and_detector_regions_keep_existing_padding(self) -> None:
        self.assertIn("region.cropRectHint ?? rect", self.crop)
        self.assertIn("guard case .vision = region.detector else {", self.crop)
        self.assertIn("return expanded", self.crop)
        self.assertNotIn("region.cropRectHint =", self.vision)

    def test_existing_runtime_and_failure_boundaries_remain(self) -> None:
        for source in (self.single_runtime, self.long_runtime):
            self.assertIn("batchInference=true", source)
            self.assertIn("MangaOCREncoderINT8", source)
        self.assertIn("catch is CancellationError", self.vision)
        self.assertIn("throw CancellationError()", self.vision)
        self.assertIn("sourceLanguage == .japanese", self.vision)

    def test_ci_route_and_version_follow_v3230(self) -> None:
        previous = "python3 -B scripts/test-v3230-image-japanese-batch-runtime-parser-contract.py"
        current = "python3 -B scripts/test-v3231-image-japanese-detector-tight-crop-hint-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3231-image-japanese-detector-tight-crop-hint-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 231) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.230;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
