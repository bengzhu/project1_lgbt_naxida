#!/usr/bin/env python3
"""Static and pure-policy contract for v3.354 direction-owner domain."""

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


def valid_direction_confidence(value: float | None) -> float | None:
    if value is None or not math.isfinite(value) or not 0.0 <= value <= 1.0:
        return None
    return value


def direction_owner_is_eligible(
    direction: str, confidence: float | None, japanese_quality: bool = True
) -> bool:
    normalized = valid_direction_confidence(confidence)
    return (
        direction == "vertical"
        and normalized is not None
        and normalized >= 0.25
        and japanese_quality
    )


@dataclass(frozen=True)
class OwnerCandidate:
    direction: str
    direction_confidence: float | None
    japanese_quality: bool = True


class JapaneseDirectionOwnerDomainContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
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
        cls.crop_stage = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        cls.risk_gate = function_body(
            cls.vision,
            "private static func isJapaneseVerticalBlockAtRisk(\n",
        )
        cls.owner_matches = function_body(
            cls.vision,
            "private static func verticalTextRegionMatchIndices(\n",
        )
        cls.geometry_only = function_body(
            cls.vision,
            "private static func japaneseGeometryOnlyVerticalLineCandidates(\n",
        )

    def test_direction_domain_is_finite_and_closed(self) -> None:
        for value in (None, math.nan, math.inf, -math.inf, -0.01, 1.01):
            self.assertIsNone(valid_direction_confidence(value))
        for value in (0.0, 0.25, 0.45, 1.0):
            self.assertEqual(valid_direction_confidence(value), value)

    def test_owner_gate_rejects_invalid_direction_scores(self) -> None:
        invalid = [
            OwnerCandidate("vertical", None),
            OwnerCandidate("vertical", math.nan),
            OwnerCandidate("vertical", math.inf),
            OwnerCandidate("vertical", -math.inf),
            OwnerCandidate("vertical", -0.01),
            OwnerCandidate("vertical", 1.01),
            OwnerCandidate("vertical", 0.24),
            OwnerCandidate("horizontal", 0.90),
        ]
        self.assertTrue(
            all(
                not direction_owner_is_eligible(
                    item.direction,
                    item.direction_confidence,
                    item.japanese_quality,
                )
                for item in invalid
            )
        )

    def test_owner_gate_keeps_the_existing_threshold_and_quality_boundary(self) -> None:
        self.assertTrue(direction_owner_is_eligible("vertical", 0.25))
        self.assertTrue(direction_owner_is_eligible("vertical", 0.84))
        self.assertFalse(direction_owner_is_eligible("vertical", 0.84, False))

    def test_crop_candidate_gate_uses_the_closed_domain(self) -> None:
        for marker in (
            "let isKoharuDetectorVerticalCandidate = aspectRatio >= 1.15",
            "validJapaneseDirectionConfidence(\n                    block.directionConfidence",
            ").map { $0 >= 0.25 } ?? false",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertNotIn("block.directionConfidence >= 0.25", self.crop_stage)

    def test_line_owner_matching_uses_a_validated_local_score(self) -> None:
        for marker in (
            "let directionConfidence = validJapaneseDirectionConfidence(\n                      block.directionConfidence",
            "directionConfidence >= 0.25",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(block.text) >= 0.5",
            "japaneseScriptDensity(in: block.text) >= 0.5",
        ):
            self.assertIn(marker, self.owner_matches)
        self.assertNotIn("block.directionConfidence >= 0.25", self.owner_matches)

    def test_geometry_only_owner_matching_uses_the_same_domain(self) -> None:
        for marker in (
            "let directionConfidence = validJapaneseDirectionConfidence(\n                          block.directionConfidence",
            "directionConfidence >= 0.25",
            "japanesePixelDetectorRegionIsCovered(",
            "guard matchingBlocks.count == 1",
        ):
            self.assertIn(marker, self.geometry_only)
        self.assertNotIn("block.directionConfidence >= 0.25", self.geometry_only)

    def test_invalid_owner_scores_do_not_become_cross_block_bridges(self) -> None:
        valid = OwnerCandidate("vertical", 0.80)
        invalid = OwnerCandidate("vertical", math.inf)
        self.assertTrue(
            direction_owner_is_eligible(
                valid.direction, valid.direction_confidence
            )
        )
        self.assertFalse(
            direction_owner_is_eligible(
                invalid.direction, invalid.direction_confidence
            )
        )

    def test_existing_recovery_domain_and_budgets_remain_unchanged(self) -> None:
        for marker in (
            "validJapaneseDirectionConfidence(block.directionConfidence) == nil",
            "block.directionConfidence < 0.45",
        ):
            self.assertIn(marker, self.risk_gate)
        for marker in (
            "let verticalBlocks = Self.boundedJapaneseVerticalCropBlocks(",
            "limit: 16",
            ".prefix(16)",
            "var orientationFallbacksRemaining = 8",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "Self.recognizeJapaneseVerticalLineCrops(",
            "Self.recognizeJapanesePixelFirstVerticalCrops(",
            "Self.recognizeJapaneseVerticalTileFallback(",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertEqual(self.crop_stage.count("orientationFallbacksRemaining -= 1"), 1)

    def test_ownerless_compatibility_and_downstream_boundaries_remain(self) -> None:
        compatibility = function_body(
            self.vision,
            "private static func japaneseObservation(\n",
        )
        self.assertIn("guard let observationOwner", compatibility)
        self.assertIn("let blockOwner", compatibility)
        self.assertIn("return true", compatibility)
        for source in (self.crop_stage, self.owner_matches, self.geometry_only):
            for forbidden in (
                "translate(",
                "persist(",
                "groundTruth",
                "KOHARU_DATA_ROOT",
                "test/koharu_artifacts",
            ):
                self.assertNotIn(forbidden, source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.361", "3.361"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3353-japanese-vertical-crop-risk-balance-contract.py",
            "scripts/test-v3354-japanese-direction-owner-domain-contract.py",
            "v3.354",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        contract = Path(__file__).read_text(encoding="utf-8")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
