#!/usr/bin/env python3
"""Contract for robust Manga OCR column ownership and partial-column recovery."""

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


class JapaneseMangaColumnOwnershipContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        self.robust = braced_body(
            self.vision,
            "private static func japanesePixelDetectorRobustColumnEnvelope(",
        )
        self.align = braced_body(
            self.vision,
            "private static func alignPartialJapaneseMangaOCRColumns(",
        )
        self.crop = braced_body(
            self.vision,
            "private static func japaneseMangaOCRCropRect(",
        )
        self.runtime = read(
            "scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_model_regions_are_aligned_before_request_crops(self) -> None:
        self.assertIn("alignPartialJapaneseMangaOCRColumns(", self.manga)
        self.assertIn("detectJapanesePixelFirstVerticalRegions(", self.manga)
        self.assertLess(
            self.manga.index("alignPartialJapaneseMangaOCRColumns("),
            self.manga.index("let requests ="),
        )
        for marker in [
            "japaneseMangaOCRCropRect(",
            "among: cropRegions",
            "textRect: region.rect",
            "regions.prefix(12)",
        ]:
            self.assertIn(marker, self.manga)

    def test_outlier_character_boxes_use_a_robust_column_core(self) -> None:
        for marker in [
            "characterRects.count >= 3",
            "maximumWidth * 0.35",
            "maximumHeight * 0.35",
            "median(glyphRects.map(\\.midX))",
            "median(glyphRects.map(\\.width))",
            "medianWidth >= broadEnvelope.width * 0.35",
            "medianWidth <= broadEnvelope.width * 0.82",
            "y: broadEnvelope.y",
            "height: broadEnvelope.height",
        ]:
            self.assertIn(marker, self.robust)
        envelope = braced_body(
            self.vision,
            "private static func japanesePixelDetectorCharacterEnvelope(",
        )
        self.assertIn("?? broadEnvelope", envelope)
        self.assertIn("return fallback", envelope)

    def test_partial_column_alignment_is_adjacent_and_bounded(self) -> None:
        for marker in [
            "candidate.characterCount >= 2",
            "candidate.characterCount <= 4",
            "neighbor.characterCount > candidate.characterCount",
            "centerDistance >= minimumSeparation",
            "centerDistance <= maximumSeparation",
            "topGap >= 0.012",
            "topGap <= min(candidate.rect.height * 0.65, 0.06)",
            "neighbor.rect.height >= candidate.rect.height * 0.75",
            "verticalOverlap >= 0.60",
            "height: candidate.rect.maxY - neighbor.rect.y",
        ]:
            self.assertIn(marker, self.align)
        self.assertNotIn("groundTruth", self.align)
        self.assertNotIn("expectedText", self.align)

    def test_padding_stops_at_neighbor_bisectors_without_cutting_core(self) -> None:
        self.assertTrue(
            "expandedVerticalLineCropRect(rect, imageSize: imageSize)" in self.crop
            or (
                "expandedVerticalLineCropRect(" in self.crop
                and "region.cropRectHint ?? rect" in self.crop
            )
        )
        for marker in [
            "verticalOverlap >= 0.50",
            "centerDistance >= min(rect.width, neighbor.rect.width) * 0.55",
            "centerDistance <= max(rect.width, neighbor.rect.width) * 2.25",
            "let boundary = (rect.midX + neighbor.rect.midX) / 2",
            "left = max(left, min(boundary, rect.x))",
            "right = min(right, max(boundary, rect.maxX))",
            "y: expanded.y",
            "height: expanded.height",
        ]:
            self.assertIn(marker, self.crop)

    def test_real_runtime_gates_fixed_cross_column_and_truncation_errors(self) -> None:
        for expected in [
            "今度こそ",
            "この爆乳を",
            "そのせいで",
            "つまんねー女に",
            "お願いします",
        ]:
            self.assertIn(expected, self.runtime)
        for rejected in [
            '"今度こそこの暴れ"',
            '"そのせいでつまりまーズ"',
            '"うまんねー女に"',
            '"vertical\\tいします"',
        ]:
            self.assertIn(rejected, self.runtime)
        self.assertTrue(
            "int(match.group(1)) != 12" in self.runtime
            or "int(match.group(1)) != 5" in self.runtime
        )

    def test_version_and_ci_route_follow_v3214(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 215) for version in versions)
        )
        previous = (
            "python3 -B "
            "scripts/test-v3214-image-japanese-bundled-manga-ocr-contract.py"
        )
        current = (
            "python3 -B "
            "scripts/test-v3215-image-japanese-manga-column-ownership-contract.py"
        )
        runtime = "bash scripts/test-v3214-image-japanese-manga-ocr-runtime.sh"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertLess(self.workflow.index(current), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx "
            "'scripts/test-v3215-image-japanese-manga-column-ownership-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
