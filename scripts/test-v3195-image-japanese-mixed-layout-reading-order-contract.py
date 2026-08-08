#!/usr/bin/env python3
"""Contract for Koharu-style mixed Japanese layout reading order."""

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


class JapaneseMixedLayoutReadingOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.merge = braced_body(
            self.layout,
            "private static func mergeReadingOrder(",
        )
        self.recursive = braced_body(
            self.layout,
            "private static func recursiveMangaBlockReadingOrder(",
        )
        self.fallback = braced_body(
            self.layout,
            "private static func fallbackMangaBlockReadingOrder(",
        )

    def test_japanese_layout_sorts_mixed_clusters_as_one_collection(self) -> None:
        for marker in [
            "prefersRightToLeft: prefersMangaReadingOrder",
            "guard prefersRightToLeft else",
            "let combined = horizontal + vertical",
            "recursiveMangaBlockReadingOrder(",
            "bestMangaBlockReadingCut(",
        ]:
            self.assertIn(marker, self.layout)
        self.assertIn("interleaveReadingOrder(horizontal: horizontal, vertical: vertical)", self.merge)

    def test_recursive_block_cut_keeps_koharu_x_and_y_partitions(self) -> None:
        for marker in [
            "case .x:",
            "first = blocks.filter { $0.rect.midX >= cut.coordinate }",
            "second = blocks.filter { $0.rect.midX < cut.coordinate }",
            "case .y:",
            "first = blocks.filter { $0.rect.midY <= cut.coordinate }",
            "second = blocks.filter { $0.rect.midY > cut.coordinate }",
            "return recursiveMangaBlockReadingOrder(",
        ]:
            self.assertIn(marker, self.recursive)

    def test_no_cut_fallback_is_row_bucketed_and_rtl(self) -> None:
        for marker in [
            "let rowHeight = max(minimumGapY * 4, 0.01)",
            "let lhsRow = floor(lhs.rect.y / rowHeight)",
            "let rhsRow = floor(rhs.rect.y / rowHeight)",
            "if lhsRow != rhsRow { return lhsRow < rhsRow }",
            "lhs.rect.midX > rhs.rect.midX",
            "previous global x-first",
        ]:
            self.assertIn(marker, self.fallback)

    def test_non_manga_path_keeps_legacy_interleave_and_scope(self) -> None:
        self.assertIn(
            "return interleaveReadingOrder(horizontal: horizontal, vertical: vertical)",
            self.merge,
        )
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
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3194(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 195) for version in versions))
        old = "python3 -B scripts/test-v3194-image-japanese-tight-region-iou-dedupe-contract.py"
        new = "python3 -B scripts/test-v3195-image-japanese-mixed-layout-reading-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
