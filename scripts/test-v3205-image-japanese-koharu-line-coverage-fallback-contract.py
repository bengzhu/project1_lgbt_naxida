#!/usr/bin/env python3
"""Contract for complete Japanese line coverage before skipping block OCR."""

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


class JapaneseKoharuLineCoverageContractTests(unittest.TestCase):
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
        self.sources = braced_body(
            self.vision,
            "private static func japaneseLineCoverageSourceCandidates(",
        )
        self.matches = braced_body(
            self.vision,
            "private static func japaneseLineCoverageMatches(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_helper_is_used_for_block_fallback_decision(self) -> None:
        self.assertIn(
            "let hasLineOCRResult = lineRefined.contains",
            self.crops,
        )
        self.assertIn(
            "let hasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage(",
            self.crops,
        )
        self.assertIn("sourceObservations: safeObservations", self.crops)
        self.assertIn("lineRefined: lineRefined", self.crops)
        self.assertIn("guard !hasLineOCRResult else { continue }", self.crops)
        self.assertLess(
            self.crops.index("let hasCompleteLineCoverage = Self.hasCompleteJapaneseLineCoverage("),
            self.crops.index("guard !hasLineOCRResult else { continue }"),
        )

    def test_source_candidates_are_enumerated_with_tight_ownership(self) -> None:
        for marker in [
            "sourceObservations.filter",
            "let lineRegion = observation.lineRegionRect ?? observation.rect",
            "overlapRatio(observation.rect, block.rect) >= 0.25",
            "japaneseLineRegionOverlapsBlock(observation, block: block)",
            "isVerticalLineCandidate(lineRegion)",
            "isDuplicateObservation(candidate, of: $0, prefersJapanese: true)",
        ]:
            self.assertIn(marker, self.sources)
        self.assertIn("guard !sourceLineCandidates.isEmpty else", self.coverage)

    def test_partial_coverage_keeps_block_fallback(self) -> None:
        for marker in [
            "guard availableLineResults.count >= sourceLineCandidates.count else",
            "guard let resultIndex = availableLineResults.firstIndex(where:",
            "japaneseLineCoverageMatches($0, candidate: candidate)",
            "else {\n                return false\n            }",
            "availableLineResults.remove(at: resultIndex)",
            "return true",
        ]:
            self.assertIn(marker, self.coverage)
        self.assertIn("guard !hasLineOCRResult else { continue }", self.crops)

    def test_complete_coverage_can_skip_only_after_distinct_vertical_results(self) -> None:
        for marker in [
            "observation.observationRole == .verticalLine",
            "let lineRegion = observation.lineRegionRect?.normalizedToUnit()",
            "observation.text.trimmingCharacters(in: .whitespacesAndNewlines)",
            "lineResult.lineRegionRect?.normalizedToUnit()",
            "candidate.lineRegionRect ?? candidate.rect",
            "overlap >= 0.72",
            "resultArea <= candidateArea * 1.75",
        ]:
            self.assertIn(marker, self.coverage + self.matches)
        self.assertIn("return true", self.coverage)

    def test_synthesized_or_noise_result_cannot_cover_multiple_lines(self) -> None:
        self.assertIn("for candidate in sourceLineCandidates", self.coverage)
        self.assertIn("availableLineResults.remove(at: resultIndex)", self.coverage)
        self.assertIn("resultArea <= candidateArea * 1.75", self.matches)
        self.assertIn("guard !sourceLineCandidates.isEmpty else", self.coverage)

    def test_scope_fixture_and_no_model_boundary(self) -> None:
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

    def test_version_and_ci_route_follow_v3204(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 205) for version in versions)
        )
        self.assertIn("MARKETING_VERSION = 3.205;", self.project)
        previous = "python3 -B scripts/test-v3204-image-japanese-koharu-line-first-ocr-contract.py"
        current = "python3 -B scripts/test-v3205-image-japanese-koharu-line-coverage-fallback-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3205-image-japanese-koharu-line-coverage-fallback-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
