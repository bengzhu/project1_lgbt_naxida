#!/usr/bin/env python3
"""Contract for bounded height-aware Japanese vertical block clustering."""

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


class JapaneseVerticalClusterGapContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.merge = braced_body(
            self.engine,
            "private static func shouldMergeVertically(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_vertical_merge_keeps_same_column_guards_and_adds_height_signal(self) -> None:
        for marker in [
            "let sameColumn =",
            "let gap = line.rect.y - rect.maxY",
            "let widthLimit = max(line.rect.width, rect.width) * 1.2",
            "let heightLimit = max((line.rect.height + rect.height) / 2, 0.012) * 0.35",
            "let verticalGapLimit = min(max(0.025, max(widthLimit, heightLimit)), 0.08)",
            "return sameColumn && gap >= -0.015 && gap <= verticalGapLimit",
        ]:
            self.assertIn(marker, self.merge)

    def test_koharu_block_then_crop_scope_remains_explicit(self) -> None:
        for marker in [
            "Koharu forms a text block before handing its crop to Manga OCR",
            "static func layout(",
        ]:
            self.assertIn(marker, self.engine)
        for marker in [
            "ImageOCRLayoutEngine.layout(",
            "recognizeJapaneseVerticalCrops(",
            "recognizeJapaneseVerticalLineCrops(",
        ]:
            self.assertIn(marker, self.vision)
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.engine)
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3173(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 174) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.173;", self.project)
        old = "python3 -B scripts/test-v3173-image-japanese-observation-fusion-contract.py"
        new = "python3 -B scripts/test-v3174-image-japanese-vertical-cluster-gap-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
