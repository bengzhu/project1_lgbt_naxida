#!/usr/bin/env python3
"""Contract for bounded synthetic line regions from fragmented Japanese glyphs."""

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


class JapaneseVerticalFragmentLineContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.synthesis = braced_body(
            self.vision,
            "private static func synthesizeJapaneseVerticalLineCandidates(",
        )
        self.fragment = braced_body(
            self.vision,
            "private static func isJapaneseVerticalFragment(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_fragmented_candidates_become_bounded_axis_line_crops(self) -> None:
        for marker in [
            "let perspectiveCandidates = Array(uniqueCandidates.prefix(24))",
            "synthesizeJapaneseVerticalLineCandidates(",
            "let axisCandidates = Array(",
            "deduplicateObservations(uniqueCandidates + synthesizedCandidates)",
            ".prefix(24)",
            "recognizeJapanesePerspectiveLineCrop(",
        ]:
            self.assertIn(marker, self.lines)

    def test_synthesis_requires_short_japanese_same_column_fragments(self) -> None:
        for marker in [
            "overlapRatio(observation.rect, block.rect) >= 0.25",
            "isJapaneseVerticalFragment(observation)",
            "fragments.count >= 2",
            "columnTolerance",
            "maximumGap",
            "zip(ordered, ordered.dropFirst())",
            "reduce(ordered[0].rect) { $0.union($1) }",
            "lineRegionQuad: nil",
        ]:
            self.assertIn(marker, self.synthesis)

    def test_fragment_gate_rejects_non_japanese_or_large_regions(self) -> None:
        for marker in [
            "scalarCount <= 2",
            "japaneseScriptDensity(in: observation.text) >= 0.5",
            "region.height >= 0.012",
            "ratio >= 0.75",
        ]:
            self.assertIn(marker, self.fragment)

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

    def test_version_and_ci_route_follow_v3171(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 172) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.171;", self.project)
        old = "python3 -B scripts/test-v3171-image-japanese-line-crop-preprocess-contract.py"
        new = "python3 -B scripts/test-v3172-image-japanese-vertical-fragment-line-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
