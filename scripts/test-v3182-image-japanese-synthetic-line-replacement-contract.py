#!/usr/bin/env python3
"""Contract for replacing covered axis bboxes with Japanese synthetic line regions."""

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


class JapaneseSyntheticLineReplacementContractTests(unittest.TestCase):
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
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_synthesized_regions_replace_only_covered_axis_candidates(self) -> None:
        for marker in [
            "let synthesizedCandidates = synthesizeJapaneseVerticalLineCandidates(",
            "let axisSeeds = synthesizedCandidates + uniqueCandidates.filter { candidate in",
            "!synthesizedCandidates.contains(where:",
            "isSameJapaneseLineRegion(candidate, as: $0)",
            "deduplicateJapaneseObservations(axisSeeds)",
            ".prefix(24)",
        ]:
            self.assertIn(marker, self.lines)
        self.assertLess(
            self.lines.index("let synthesizedCandidates = synthesizeJapaneseVerticalLineCandidates("),
            self.lines.index("let axisSeeds = synthesizedCandidates + uniqueCandidates.filter { candidate in"),
        )

    def test_perspective_quads_and_quality_fallback_remain_available(self) -> None:
        for marker in [
            "let perspectiveCandidates = Array(uniqueCandidates.prefix(24))",
            "recognizeJapanesePerspectiveLineCrop(",
            "consumedPixels: &perspectiveWarpPixels",
            "orientationFallbacksRemaining",
            "recognizeJapaneseCropPass(",
        ]:
            self.assertIn(marker, self.lines)
        # The replacement is axis-only; original observations still seed the
        # perspective path above the synthetic candidate construction.
        self.assertLess(
            self.lines.index("let perspectiveCandidates = Array(uniqueCandidates.prefix(24))"),
            self.lines.index("let synthesizedCandidates = synthesizeJapaneseVerticalLineCandidates("),
        )

    def test_synthesis_gate_stays_bounded_and_japanese(self) -> None:
        for marker in [
            "overlapRatio(observation.rect, block.rect) >= 0.25",
            "isJapaneseVerticalFragment(observation)",
            "fragments.count >= 2",
            "columnTolerance",
            "maximumGap",
            "zip(ordered, ordered.dropFirst())",
            "aspectRatio >= 1.25",
        ]:
            self.assertIn(marker, self.synthesis)
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3181(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 182) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.181;", self.project)
        old = "python3 -B scripts/test-v3181-image-japanese-line-path-dedupe-contract.py"
        new = "python3 -B scripts/test-v3182-image-japanese-synthetic-line-replacement-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
