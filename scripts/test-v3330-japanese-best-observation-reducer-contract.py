#!/usr/bin/env python3
"""Static and pure-policy contract for v3.330 Japanese best reduction."""

from dataclasses import dataclass
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function signature: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function body: {signature}")


@dataclass(frozen=True)
class Observation:
    text: str
    confidence: float
    score: float
    rotation: int
    role: str
    letter_density: float = 1.0
    script_density: float = 1.0


def is_better_japanese(lhs: Observation, rhs: Observation) -> bool:
    if lhs.score != rhs.score:
        return lhs.score > rhs.score
    return lhs.text < rhs.text


def swift_max_by_better(observations: list[Observation]) -> Observation | None:
    """Emulate Sequence.max(by:) with the incorrect descending predicate."""
    if not observations:
        return None
    result = observations[0]
    for candidate in observations[1:]:
        if is_better_japanese(result, candidate):
            result = candidate
    return result


def best_japanese_observation(
    observations: list[Observation],
) -> Observation | None:
    if not observations:
        return None
    best = observations[0]
    for candidate in observations[1:]:
        if is_better_japanese(candidate, best):
            best = candidate
    return best


def needs_orientation_fallback(observations: list[Observation]) -> bool:
    best = best_japanese_observation(observations)
    if best is None:
        return True
    return (
        best.confidence < 0.48
        or best.letter_density < 0.5
        or best.script_density < 0.5
        or len(best.text) <= 1
    )


class JapaneseBestObservationReducerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.flow = read("md/flow/flow.md") + read("md/flow/flowchart.md")
        cls.route = read(
            "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
        )
        cls.test_log = read("md/test/test.md")
        cls.update_log = read("update_log.md")
        cls.japanese_reducer = function_body(
            cls.vision,
            "private static func bestJapaneseObservation(\n",
        )
        cls.reducer = function_body(
            cls.vision,
            "private static func bestObservation(\n",
        )
        cls.orientation = function_body(
            cls.vision,
            "private static func needsJapaneseOrientationFallback(\n",
        )
        cls.synthesis = function_body(
            cls.vision,
            "private static func synthesizeJapaneseVerticalLineCandidates(\n",
        )

    def test_descending_comparator_in_swift_max_selects_the_weakest_item(self) -> None:
        strong = Observation("今度こそ", 0.91, 15.0, 270, "verticalLine")
        weak = Observation("日", 0.41, 8.0, 90, "page")
        self.assertEqual(swift_max_by_better([strong, weak]), weak)
        self.assertEqual(best_japanese_observation([strong, weak]), strong)

    def test_explicit_reducer_selects_the_best_in_any_input_order(self) -> None:
        observations = [
            Observation("弱", 0.48, 8.0, 90, "page"),
            Observation("今度こそ", 0.92, 15.0, 270, "verticalLine"),
            Observation("中程度", 0.70, 11.0, 90, "page"),
        ]
        expected = observations[1]
        self.assertEqual(best_japanese_observation(observations), expected)
        self.assertEqual(best_japanese_observation(list(reversed(observations))), expected)

    def test_strong_read_prevents_spurious_opposite_orientation_request(self) -> None:
        strong = Observation("今度こそ", 0.92, 15.0, 270, "verticalLine")
        weak = Observation("日", 0.41, 8.0, 90, "page")
        self.assertFalse(needs_orientation_fallback([strong, weak]))
        self.assertTrue(needs_orientation_fallback([weak]))
        self.assertTrue(needs_orientation_fallback([]))

    def test_synthesized_metadata_comes_from_the_strongest_fragment(self) -> None:
        strong = Observation("今", 0.92, 15.0, 270, "verticalLine")
        weak = Observation("度", 0.49, 8.0, 90, "page")
        best = best_japanese_observation([strong, weak])
        self.assertIsNotNone(best)
        self.assertEqual((best.rotation, best.role), (270, "verticalLine"))
        self.assertEqual("".join(item.text for item in [strong, weak]), "今度")
        self.assertAlmostEqual(
            sum(item.confidence for item in [strong, weak]) / 2,
            0.705,
        )

    def test_product_and_diagnostic_call_sites_use_the_shared_best_reducer(self) -> None:
        self.assertIn("bestJapaneseObservation(\n                    in: ordered.map(\\.observation)", self.synthesis)
        self.assertIn("bestJapaneseObservation(in: observations)", self.orientation)
        self.assertIn("bestJapaneseObservation(in: observations)", self.vision[:1_0000])
        self.assertIn(
            "Self.bestObservation(\n            in: eligibleObservations,\n            prefersJapanese: japanese",
            self.vision,
        )
        self.assertNotIn(
            ".max(by: { isBetterJapaneseObservation($0, $1) })",
            self.vision,
        )
        self.assertNotIn("eligibleObservations.max", self.vision)

    def test_reducer_uses_candidate_first_descending_comparison(self) -> None:
        for marker in (
            "guard var best = observations.first else { return nil }",
            "for candidate in observations.dropFirst()",
            "isBetterObservation(\n                candidate,\n                best,",
            "prefersJapanese: prefersJapanese",
            "best = candidate",
        ):
            self.assertIn(marker, self.reducer)
        self.assertNotIn("max(by:", self.reducer)
        self.assertIn(
            "bestObservation(in: observations, prefersJapanese: true)",
            self.japanese_reducer,
        )

    def test_orientation_quality_thresholds_and_budgets_are_unchanged(self) -> None:
        for marker in (
            "best.confidence < 0.48",
            "japaneseLetterDensity(best.text) < 0.5",
            "japaneseScriptDensity(in: best.text) < 0.5",
            "textLength <= 1",
        ):
            self.assertIn(marker, self.orientation)
        for marker in (
            "var orientationFallbacksRemaining = 12",
            "var orientationFallbacksRemaining = 8",
            "var orientationFallbacksRemaining = 4",
        ):
            self.assertIn(marker, self.vision)

    def test_fragment_text_confidence_owner_and_geometry_stay_fixed(self) -> None:
        for marker in (
            "text: ordered.map { $0.observation.text }.joined()",
            "confidence: confidence",
            "verticalTextRegionOwner: owner",
            "lineRegionRect: rect",
            "sourceDirectionHint: .vertical",
        ):
            self.assertIn(marker, self.synthesis)

    def test_fusion_translation_cancel_and_persistence_boundaries_stay_fixed(self) -> None:
        self.assertIn("return deduplicateJapaneseObservations(synthesized)", self.synthesis)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("translateJapaneseImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        self.assertIn("CancellationError", self.store)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.342", "3.342"],
        )
        combined = self.workflow + self.flow + self.route + self.test_log + self.update_log
        for marker in (
            "scripts/test-v3330-japanese-best-observation-reducer-contract.py",
            "v3.330",
            "japanese-benchmark-v3.330-",
        ):
            self.assertIn(marker, combined)


if __name__ == "__main__":
    unittest.main()
