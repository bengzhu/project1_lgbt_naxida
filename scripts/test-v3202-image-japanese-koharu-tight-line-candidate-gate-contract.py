#!/usr/bin/env python3
"""Contract for using Koharu-tight line geometry in Japanese line candidate gating."""

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


class JapaneseKoharuTightLineCandidateGateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.line_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.candidate_gate = braced_body(
            self.vision,
            "private static func isVerticalLineCandidate(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_line_gate_prefers_tight_region_but_keeps_layout_overlap_box(self) -> None:
        self.assertIn(
            "let lineRegion = observation.lineRegionRect ?? observation.rect",
            self.line_crops,
        )
        self.assertIn("overlapRatio(observation.rect, block.rect) >= 0.25", self.line_crops)
        self.assertIn("isVerticalLineCandidate(lineRegion)", self.line_crops)
        self.assertNotIn("isVerticalLineCandidate(observation.rect)", self.line_crops)

    def test_gate_keeps_bounded_koharu_vertical_geometry(self) -> None:
        self.assertIn("rect.height / max(rect.width, 0.001) >= 1.25", self.candidate_gate)
        self.assertIn("rect.height >= 0.018", self.candidate_gate)
        self.assertNotIn("lineRegionRect", self.candidate_gate)

    def test_scope_stays_ordinary_japanese_line_reread(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3201(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 202) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.201;", self.project)
        old = "python3 -B scripts/test-v3201-image-japanese-koharu-line-orientation-provenance-contract.py"
        new = "python3 -B scripts/test-v3202-image-japanese-koharu-tight-line-candidate-gate-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
