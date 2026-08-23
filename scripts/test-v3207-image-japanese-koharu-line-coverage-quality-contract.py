#!/usr/bin/env python3
"""Contract for quality-aware Japanese line coverage before block fallback is skipped."""

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


class JapaneseKoharuLineCoverageQualityContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.coverage = braced_body(
            self.vision,
            "private static func hasCompleteJapaneseLineCoverage(",
        )
        self.quality = braced_body(
            self.vision,
            "private static func isReliableJapaneseLineCoverageResult(",
        )
        self.matches = braced_body(
            self.vision,
            "private static func japaneseLineCoverageMatches(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_quality_gate_runs_before_a_line_can_skip_block_crop(self) -> None:
        self.assertIn(
            "isReliableJapaneseLineCoverageResult($0, candidate: candidate)",
            self.coverage,
        )
        self.assertIn(
            "&& japaneseLineCoverageMatches($0, candidate: candidate)",
            self.coverage,
        )
        self.assertLess(
            self.coverage.index("isReliableJapaneseLineCoverageResult($0, candidate: candidate)"),
            self.coverage.index("japaneseLineCoverageMatches($0, candidate: candidate)"),
        )
        self.assertIn("guard !hasLineOCRResult else { continue }", self.crops)

    def test_quality_gate_requires_confidence_and_japanese_script_evidence(self) -> None:
        for marker in [
            "validOCRConfidence(result.confidence) != nil",
            "result.confidence >= 0.48",
            "japaneseScriptDensity(in: text) >= 0.5",
            "let candidateLength = candidate.text.unicodeScalars.count",
            "let resultLength = text.unicodeScalars.count",
            "return candidateLength < 2 || resultLength >= 2",
        ]:
            self.assertIn(marker, self.quality)

    def test_geometry_and_distinct_source_line_matching_still_apply(self) -> None:
        for marker in [
            "observation.observationRole == .verticalLine",
            "let lineRegion = observation.lineRegionRect?.normalizedToUnit()",
            "availableLineResults.remove(at: resultIndex)",
            "lineResult.lineRegionRect?.normalizedToUnit()",
            "candidate.lineRegionRect ?? candidate.rect",
            "overlap >= 0.72",
            "resultArea <= candidateArea * 1.75",
        ]:
            self.assertIn(marker, self.coverage + self.matches)
        self.assertIn("for candidate in sourceLineCandidates", self.coverage)

    def test_scope_stays_ordinary_japanese_ocr_without_model_or_probe_access(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
            "VNCoreMLModel",
            "MLModel",
            "loadModel(",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3206(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 207) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.206;", self.project)
        previous = "python3 -B scripts/test-v3206-image-japanese-koharu-observation-row-fallback-contract.py"
        current = "python3 -B scripts/test-v3207-image-japanese-koharu-line-coverage-quality-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3207-image-japanese-koharu-line-coverage-quality-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
