#!/usr/bin/env python3
"""Contract for Koharu's row-bucketed no-cut Japanese observation order."""

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


class JapaneseObservationRowFallbackContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.recursive = braced_body(
            self.layout,
            "private static func recursiveMangaReadingOrder(",
        )
        self.fallback = braced_body(
            self.layout,
            "private static func fallbackMangaObservationReadingOrder(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_no_cut_observation_fallback_is_row_bucketed_and_rtl(self) -> None:
        for marker in [
            "fallbackMangaObservationReadingOrder(",
            "minimumGapY: minimumGapY",
        ]:
            self.assertIn(marker, self.recursive)
        for marker in [
            "let rowHeight = max(minimumGapY * 4, 0.01)",
            "let lhsRow = floor(lhs.rect.y / rowHeight)",
            "let rhsRow = floor(rhs.rect.y / rowHeight)",
            "if lhsRow != rhsRow { return lhsRow < rhsRow }",
            "lhs.rect.midX > rhs.rect.midX",
            "lhs.rect.y < rhs.rect.y",
            "lhs.rect.width < rhs.rect.width",
            "lhs.rect.height < rhs.rect.height",
            "lhs.text < rhs.text",
            "let lhsConfidence = confidenceOrderingKey(lhs.observation.confidence)",
            "let rhsConfidence = confidenceOrderingKey(rhs.observation.confidence)",
            "return lhsConfidence > rhsConfidence",
        ]:
            self.assertIn(marker, self.fallback)

    def test_failed_partition_uses_same_safe_fallback(self) -> None:
        self.assertEqual(
            self.recursive.count("fallbackMangaObservationReadingOrder("),
            2,
        )
        self.assertNotIn("stableKey($0, -$0.rect.midX, $0.rect.y)", self.recursive)

    def test_mixed_block_fallback_and_non_manga_scope_remain(self) -> None:
        self.assertIn("fallbackMangaBlockReadingOrder", self.layout)
        for forbidden in [
            "VisionOCRService",
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.layout)

    def test_version_and_ci_route_follow_v3205(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 206) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.205;", self.project)
        old = "python3 -B scripts/test-v3205-image-japanese-koharu-line-coverage-fallback-contract.py"
        new = "python3 -B scripts/test-v3206-image-japanese-koharu-observation-row-fallback-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("scripts/test-v3206-image-japanese-koharu-observation-row-fallback-contract.py", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
