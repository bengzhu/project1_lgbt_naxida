#!/usr/bin/env python3
"""Contract for preferring successful Japanese line polygons over duplicate bbox rereads."""

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


class JapaneseLinePathDedupeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.same_region = braced_body(
            self.vision,
            "private static func isSameJapaneseLineRegion(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_strong_perspective_results_cover_matching_axis_candidates(self) -> None:
        for marker in [
            "var perspectiveCoveredCandidates: [VisionOCRObservation] = []",
            "needsJapaneseOrientationFallback(meaningfulPerspective)",
            "perspectiveCoveredCandidates.append(candidate)",
            "guard !perspectiveCoveredCandidates.contains(where:",
            "isSameJapaneseLineRegion(candidate, as: $0)",
            "continue",
        ]:
            self.assertIn(marker, self.lines)
        self.assertLess(
            self.lines.index("perspectiveCoveredCandidates.append(candidate)"),
            self.lines.index("guard !perspectiveCoveredCandidates.contains(where:"),
        )

    def test_coverage_is_geometry_scoped_and_keeps_quality_fallback(self) -> None:
        for marker in [
            "let candidateRegion = candidate.lineRegionRect ?? candidate.rect",
            "let coveredRegion = covered.lineRegionRect ?? covered.rect",
            "overlapRatio(candidateRegion, coveredRegion) >= 0.72",
        ]:
            self.assertIn(marker, self.same_region)
        self.assertIn(
            "if !needsJapaneseOrientationFallback(meaningfulPerspective)",
            self.lines,
        )
        self.assertIn("orientationFallbacksRemaining", self.lines)
        self.assertIn("recognizeJapaneseCropPass(", self.lines)

    def test_scope_and_existing_line_budget_remain_safe(self) -> None:
        for marker in [
            "let perspectiveCandidates = Array(uniqueCandidates.prefix(24))",
            "let axisCandidates = Array(",
            ".prefix(24)",
            "consumedPixels: &perspectiveWarpPixels",
        ]:
            self.assertIn(marker, self.lines)
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

    def test_version_and_ci_route_follow_v3180(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 181) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.180;", self.project)
        old = "python3 -B scripts/test-v3180-image-japanese-line-warp-bbox-contract.py"
        new = "python3 -B scripts/test-v3181-image-japanese-line-path-dedupe-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
