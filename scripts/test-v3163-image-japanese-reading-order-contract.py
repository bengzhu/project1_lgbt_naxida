#!/usr/bin/env python3
"""Contract for Koharu-style recursive reading order in Japanese vertical OCR."""

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


class JapaneseReadingOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.vertical = braced_body(self.layout, "private static func orderedVerticalBands(")
        self.recursive = braced_body(self.layout, "private static func recursiveMangaReadingOrder(")
        self.cut = braced_body(self.layout, "private static func bestMangaReadingCut(")
        self.gap = braced_body(self.layout, "private static func largestMangaGap(")

    def test_vertical_path_uses_koharu_recursive_xy_cut(self) -> None:
        for marker in [
            "recursiveMangaReadingOrder(",
            "median(observations.map(\\.rect.width))",
            "median(observations.map(\\.rect.height))",
            "minimumGapX = max(medianWidth * 0.15, 0.01)",
            "minimumGapY = max(medianHeight * 0.10, 0.008)",
        ]:
            self.assertIn(marker, self.vertical)
        for marker in [
            "bestMangaReadingCut(",
            "case .x:",
            "first = observations.filter { $0.rect.midX >= cut.coordinate }",
            "first = observations.filter { $0.rect.midY <= cut.coordinate }",
            "return recursiveMangaReadingOrder(",
        ]:
            self.assertIn(marker, self.recursive)

    def test_cut_selection_and_fallback_preserve_manga_direction(self) -> None:
        for marker in [
            "largestMangaGap(xIntervals, minimum: minimumGapX)",
            "largestMangaGap(yIntervals, minimum: minimumGapY)",
            "widthY > max(0.01, widthX * 0.4)",
            "MangaReadingCut(axis: .y",
            "MangaReadingCut(axis: .x",
        ]:
            self.assertIn(marker, self.cut)
        for marker in [
            "currentMaxEnd",
            "gap >= minimum",
            "largest.map",
        ]:
            self.assertIn(marker, self.gap)
        # Later iterations use Koharu's row-bucket fallback when recursive
        # partitioning cannot produce a valid cut.
        self.assertIn("fallbackMangaObservationReadingOrder(", self.recursive)
        self.assertIn("minimumGapY: minimumGapY", self.recursive)

    def test_layout_scope_stays_vertical_and_does_not_touch_translation(self) -> None:
        self.assertIn(
            "orderedVerticalBands(resolved.filter { $0.direction == .vertical })",
            self.layout,
        )
        for forbidden in [
            "VisionOCRService",
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
        ]:
            self.assertNotIn(forbidden, self.layout)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3162(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 163) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.162;", self.project)
        old = "python3 -B scripts/test-v3162-image-japanese-line-perspective-ocr-contract.py"
        new = "python3 -B scripts/test-v3163-image-japanese-reading-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
