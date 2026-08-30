#!/usr/bin/env python3
"""Static and pure-policy contract for v3.348 pixel recovery eligibility."""

from dataclasses import dataclass
import math
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
class ExistingRegion:
    role: str
    vertical_hint: bool
    text: str
    confidence: float
    japanese_letter: bool
    japanese_density: float
    script_density: float
    rect: tuple[float, float, float, float]
    weak_compact_owner: bool = False


def eligible_existing_vertical_regions(
    observations: list[ExistingRegion],
) -> list[ExistingRegion]:
    """Model the fail-closed geometry coverage policy in v3.348."""
    eligible: list[ExistingRegion] = []
    for observation in observations:
        if not (
            observation.vertical_hint
            or observation.role == "verticalLine"
        ):
            continue
        if observation.weak_compact_owner:
            continue
        if (
            not observation.text.strip()
            or not math.isfinite(observation.confidence)
            or not 0.0 <= observation.confidence <= 1.0
            or observation.confidence < 0.48
            or not observation.japanese_letter
            or observation.japanese_density < 0.5
            or observation.script_density < 0.5
        ):
            continue
        eligible.append(observation)
    return eligible


def overlap_ratio(
    lhs: tuple[float, float, float, float],
    rhs: tuple[float, float, float, float],
) -> float:
    lx, ly, lw, lh = lhs
    rx, ry, rw, rh = rhs
    intersection = max(0.0, min(lx + lw, rx + rw) - max(lx, rx)) * max(
        0.0, min(ly + lh, ry + rh) - max(ly, ry)
    )
    minimum_area = max(min(lw * lh, rw * rh), 0.0001)
    return intersection / minimum_area


def pixel_candidate_is_covered(
    candidate: tuple[float, float, float, float],
    observations: list[ExistingRegion],
) -> bool:
    return any(
        overlap_ratio(observation.rect, candidate) >= 0.60
        for observation in eligible_existing_vertical_regions(observations)
    )


class JapanesePixelRecoveryEligibilityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("README.md")
            + read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.detector = function_body(
            cls.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(\n",
        )
        cls.pixel = function_body(
            cls.vision,
            "private static func recognizeJapanesePixelFirstVerticalCrops(\n",
        )
        cls.crops = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        cls.frontier = function_body(
            cls.vision,
            "private static func japaneseLinePathRegion(\n",
        )

    def test_direction_and_compact_gates_precede_meaningful_coverage_gate(self) -> None:
        direction = self.detector.index(
            "guard observation.sourceDirectionHint == .vertical"
        )
        compact = self.detector.index(
            "if isWeakCompactJapaneseOwner(observation)", direction
        )
        text = self.detector.index(
            "let text = postProcessJapaneseOCRText(observation.text)", compact
        )
        returned = self.detector.index(
            "return observation.lineRegionRect ?? observation.rect", text
        )
        self.assertLess(direction, compact)
        self.assertLess(compact, text)
        self.assertLess(text, returned)
        for marker in (
            "observation.sourceDirectionHint == .vertical",
            "observation.observationRole == .verticalLine",
            "isWeakCompactJapaneseOwner(observation)",
            "postProcessJapaneseOCRText(observation.text)",
            "validOCRConfidence(observation.confidence) != nil",
            "observation.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
            "return observation.lineRegionRect ?? observation.rect",
        ):
            self.assertIn(marker, self.detector)

    def test_reliable_page_or_line_read_suppresses_duplicate_pixel_geometry(self) -> None:
        candidate = (0.40, 0.20, 0.08, 0.42)
        page = ExistingRegion(
            "page",
            True,
            "今度こそ",
            0.82,
            True,
            0.90,
            0.90,
            candidate,
        )
        line = ExistingRegion(
            "verticalLine",
            False,
            "持ち帰る！",
            0.91,
            True,
            0.90,
            0.90,
            (0.70, 0.20, 0.08, 0.42),
        )
        self.assertEqual(eligible_existing_vertical_regions([page]), [page])
        self.assertEqual(eligible_existing_vertical_regions([line]), [line])
        self.assertTrue(pixel_candidate_is_covered(candidate, [page]))

    def test_weak_page_read_leaves_pixel_first_candidate_eligible(self) -> None:
        candidate = (0.40, 0.20, 0.08, 0.42)
        weak = ExistingRegion(
            "page",
            True,
            "今度こそ",
            0.31,
            True,
            0.90,
            0.90,
            candidate,
        )
        self.assertEqual(eligible_existing_vertical_regions([weak]), [])
        self.assertFalse(pixel_candidate_is_covered(candidate, [weak]))

    def test_empty_non_japanese_low_density_and_wrong_role_fail_closed(self) -> None:
        rect = (0.40, 0.20, 0.08, 0.42)
        observations = [
            ExistingRegion("page", True, "", 0.90, True, 0.90, 0.90, rect),
            ExistingRegion("page", True, "noise", 0.90, False, 0.90, 0.90, rect),
            ExistingRegion("page", True, "かな", 0.90, True, 0.49, 0.90, rect),
            ExistingRegion("page", True, "かな", 0.90, True, 0.90, 0.49, rect),
            ExistingRegion("crop", False, "かな", 0.90, True, 0.90, 0.90, rect),
        ]
        self.assertEqual(eligible_existing_vertical_regions(observations), [])

    def test_weak_compact_owner_does_not_claim_coverage_even_with_good_text(self) -> None:
        compact = ExistingRegion(
            "detectorTextRegion",
            True,
            "ニコッ",
            0.79,
            True,
            0.90,
            0.90,
            (0.40, 0.20, 0.05, 0.05),
            weak_compact_owner=True,
        )
        self.assertEqual(eligible_existing_vertical_regions([compact]), [])

    def test_confidence_domain_and_threshold_are_exact(self) -> None:
        rect = (0.40, 0.20, 0.08, 0.42)

        def observation(confidence: float) -> ExistingRegion:
            return ExistingRegion(
                "page", True, "今度こそ", confidence, True, 0.90, 0.90, rect
            )

        for confidence in (math.nan, math.inf, -math.inf, -0.01, 1.01, 0.479):
            self.assertEqual(
                eligible_existing_vertical_regions([observation(confidence)]),
                [],
            )
        self.assertEqual(
            len(eligible_existing_vertical_regions([observation(0.48)])),
            1,
        )

    def test_pixel_first_budget_geometry_and_existing_fallbacks_remain_bounded(self) -> None:
        for marker in (
            "for candidate in candidates.prefix(12)",
            "var orientationFallbacksRemaining = 4",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "expandedVerticalLineCropRect(",
            "prepareJapaneseCropForVision(crop.image)",
            "VNDetectTextRectanglesRequest()",
            "japanesePixelDetectorCharacterEnvelope(",
            "japanesePixelDetectorCharacterQuad(",
            "!overlapsLayoutBlock",
            "!existingVerticalRegions.contains(where:",
            "!reliableLineRegions.contains(where:",
        ):
            self.assertIn(marker, self.detector + self.pixel)
        self.assertIn("meaningfulJapaneseRecoveryObservations(", self.pixel)
        self.assertIn("let reliableLineRegions = lineObservations.compactMap", self.detector)

    def test_strict_line_frontier_and_tile_fallback_remain_separate(self) -> None:
        for marker in (
            "observationRole == .verticalLine",
            "validOCRConfidence(observation.confidence) != nil",
            "observation.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "japaneseScriptDensity(in: text) >= 0.5",
            "isVerticalLineCandidate(region)",
        ):
            self.assertIn(marker, self.frontier)
        self.assertIn("Self.recognizeJapaneseVerticalTileFallback(", self.crops)
        self.assertIn("lineObservations: recoveryFrontierObservations", self.crops)

    def test_translation_persistence_and_optional_research_are_outside_this_gate(self) -> None:
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.detector, self.pixel, self.crops):
            for forbidden in (
                "TranslationSessionStore",
                "persist(",
                "groundTruth",
                "KOHARU_DATA_ROOT",
                "test/koharu_artifacts",
            ):
                self.assertNotIn(forbidden, source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.357", "3.357"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3348-japanese-pixel-recovery-eligibility-contract.py",
            "v3.348",
            "japanese-benchmark-v3.348-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3348-japanese-pixel-recovery-eligibility-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
