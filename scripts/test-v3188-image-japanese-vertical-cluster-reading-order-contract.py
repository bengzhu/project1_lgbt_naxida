#!/usr/bin/env python3
"""Contract for deterministic Koharu-style vertical cluster reading order."""

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


class JapaneseVerticalClusterReadingOrderContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.layout = read("AITRANS/Services/ImageOCRLayoutEngine.swift")
        self.cluster = braced_body(self.layout, "var block: ImageOCRLayoutBlock")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_vertical_text_is_sorted_top_to_bottom_before_joining(self) -> None:
        direction = self.cluster.index("if direction == .vertical")
        ordered = self.cluster.index("let orderedObservations = observations.sorted", direction)
        joined = self.cluster.index("orderedObservations.map(\\.text).joined()", ordered)
        self.assertLess(direction, ordered)
        self.assertLess(ordered, joined)
        for marker in [
            "stableKey($0, $0.rect.y, -$0.rect.midX)",
            "stableKey($1, $1.rect.y, -$1.rect.midX)",
        ]:
            self.assertIn(marker, self.cluster)

    def test_horizontal_text_keeps_existing_line_break_logic(self) -> None:
        vertical_end = self.cluster.index("} else {")
        horizontal = self.cluster[vertical_end:]
        self.assertIn("observations.enumerated().reduce(into: \"\")", horizontal)
        self.assertIn("let sameLine = abs(previous.rect.y - observation.rect.y)", horizontal)
        self.assertIn("output += sameLine ? \" \" : \"\\n\"", horizontal)
        self.assertEqual(self.cluster.count("orderedObservations.map(\\.text).joined()"), 1)

    def test_cluster_still_only_merges_same_vertical_column(self) -> None:
        merge = braced_body(self.layout, "private static func shouldMergeVertically(")
        for marker in [
            "let sameColumn = horizontalOverlap(line.rect, rect)",
            "let gap = line.rect.y - rect.maxY",
            "let verticalGapLimit = min(max(0.025, max(widthLimit, heightLimit)), 0.08)",
            "return sameColumn && gap >= -0.015 && gap <= verticalGapLimit",
        ]:
            self.assertIn(marker, merge)

    def test_model_and_artifact_boundaries_remain_closed(self) -> None:
        for source in [self.layout]:
            for forbidden in [
                "TranslationSessionStore",
                "MangaOverlayProbeService",
                "groundTruth",
                "test/koharu_artifacts",
                "metrics/version_history.csv",
                "output/",
            ]:
                self.assertNotIn(forbidden, source)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3187(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 188) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.187;", self.project)
        old = "python3 -B scripts/test-v3187-image-japanese-crop-direction-hint-contract.py"
        new = "python3 -B scripts/test-v3188-image-japanese-vertical-cluster-reading-order-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
