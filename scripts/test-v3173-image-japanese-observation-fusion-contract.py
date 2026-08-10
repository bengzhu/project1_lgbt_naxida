#!/usr/bin/env python3
"""Contract for language-aware Japanese OCR observation fusion."""

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


class JapaneseObservationFusionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.recognize = braced_body(
            self.vision,
            "func recognizeTextBlocks(in imageData: Data, sourceLanguage: SupportedLanguage)",
        )
        self.dedupe = braced_body(
            self.vision,
            "private static func deduplicateObservations(",
        )
        self.score = braced_body(
            self.vision,
            "private static func observationScore(",
        )
        self.evidence = braced_body(
            self.vision,
            "private static func japaneseObservationEvidence(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_japanese_path_uses_a_scoped_fusion_helper(self) -> None:
        for marker in [
            "let finalObservations = sourceLanguage == .japanese",
            "Self.deduplicateObservations(observations)",
            "private static func deduplicateJapaneseObservations(",
            "deduplicateObservations(observations, prefersJapanese: true)",
        ]:
            self.assertIn(
                marker,
                self.vision
                if marker.startswith("private") or marker.startswith("deduplicate")
                else self.recognize,
            )
        self.assertTrue(
            "Self.deduplicateJapaneseObservations(observations)" in self.recognize
            or "Self.deduplicateJapaneseObservations(\n" in self.recognize
        )

    def test_japanese_scoring_is_bounded_and_keeps_normal_score(self) -> None:
        for marker in [
            "prefersJapanese: Bool = false",
            "let baseScore =",
            "guard prefersJapanese else { return baseScore }",
            "return baseScore + japaneseObservationEvidence(in: observation.text)",
            "japaneseScriptDensity(in: text)",
            "japanesePunctuationDensity(in: text)",
            "min(\n            scriptDensity * 0.9 + punctuationDensity * 0.2,\n            1.1\n        )",
            "return -0.65",
        ]:
            self.assertIn(marker, self.score + self.evidence + self.vision)

    def test_vertical_candidate_selection_uses_japanese_preference(self) -> None:
        for marker in [
            "deduplicateJapaneseObservations(observations)",
            "isBetterJapaneseObservation($0, $1)",
            "max(by: { isBetterJapaneseObservation($0, $1) })",
        ]:
            self.assertIn(marker, self.vision)
        self.assertTrue(
            "deduplicateJapaneseObservations(uniqueCandidates + synthesizedCandidates)" in self.vision
            or "deduplicateJapaneseObservations(axisSeeds)" in self.vision
        )

    def test_non_japanese_layout_keeps_original_dedupe_path(self) -> None:
        self.assertIn(
            ": Self.deduplicateObservations(observations)",
            self.recognize,
        )
        self.assertIn("private static func isBetterObservation(", self.vision)
        self.assertIn("private static func japanesePunctuationDensity(", self.vision)

    def test_scope_stays_out_of_probe_store_and_active_artifacts(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_and_ci_route_follow_v3172(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 173) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.172;", self.project)
        old = "python3 -B scripts/test-v3172-image-japanese-vertical-fragment-line-contract.py"
        new = "python3 -B scripts/test-v3173-image-japanese-observation-fusion-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
