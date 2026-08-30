#!/usr/bin/env python3
"""Static and pure-policy contract for v3.352 direction-confidence risk domain."""

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


def direction_is_weak(direction: str, confidence: float | None) -> bool:
    normalized = valid_direction_confidence(confidence)
    return direction != "vertical" or normalized is None or normalized < 0.45


class JapaneseDirectionConfidenceRiskDomainContractTests(unittest.TestCase):
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
        cls.helper = function_body(
            cls.vision,
            "private static func validJapaneseDirectionConfidence(\n",
        )
        cls.weak_recovery = function_body(
            cls.vision,
            "private static func needsJapaneseWeakBlockRecovery(\n",
        )
        cls.risk_gate = function_body(
            cls.vision,
            "private static func isJapaneseVerticalBlockAtRisk(\n",
        )
        cls.crop_stage = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )

    def test_direction_domain_is_finite_and_closed(self) -> None:
        for value in (None, math.nan, math.inf, -math.inf, -0.01, 1.01):
            self.assertIsNone(valid_direction_confidence(value))
        for value in (0.0, 0.45, 1.0):
            self.assertEqual(valid_direction_confidence(value), value)

    def test_invalid_direction_scores_are_weak_for_vertical_recovery(self) -> None:
        self.assertTrue(direction_is_weak("vertical", None))
        self.assertTrue(direction_is_weak("vertical", math.nan))
        self.assertTrue(direction_is_weak("vertical", -0.1))
        self.assertTrue(direction_is_weak("vertical", 1.1))
        self.assertTrue(direction_is_weak("vertical", 0.44))
        self.assertFalse(direction_is_weak("vertical", 0.45))
        self.assertFalse(direction_is_weak("vertical", 0.92))

    def test_shared_helper_rejects_nonfinite_and_out_of_range_values(self) -> None:
        for marker in (
            "confidence.isFinite",
            "(0...1).contains(confidence)",
            "return nil",
            "return confidence",
        ):
            self.assertIn(marker, self.helper)

    def test_weak_block_recovery_uses_the_closed_direction_domain(self) -> None:
        for marker in (
            "let directionConfidence = block.directionConfidence",
            "validJapaneseDirectionConfidence(directionConfidence) == nil",
            "(directionConfidence ?? 0) < 0.45",
        ):
            self.assertIn(marker, self.weak_recovery)
        self.assertNotIn("(block.directionConfidence ?? 1) < 0.45", self.weak_recovery)

    def test_vertical_crop_risk_gate_uses_the_same_domain(self) -> None:
        for marker in (
            "validJapaneseDirectionConfidence(block.directionConfidence) == nil",
            "block.directionConfidence < 0.45",
            "validOCRConfidence(block.confidence) == nil",
            "block.confidence < 0.60",
            "text.isEmpty",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) < 0.5",
            "japaneseScriptDensity(in: text) < 0.5",
            "letters <= 2",
        ):
            self.assertIn(marker, self.risk_gate)
        self.assertNotIn("!block.directionConfidence.isFinite", self.risk_gate)

    def test_crop_sort_uses_domain_checked_direction_tie_break(self) -> None:
        for marker in (
            "validJapaneseDirectionConfidence(\n                lhs.directionConfidence\n            ) ?? -.infinity",
            "validJapaneseDirectionConfidence(\n                rhs.directionConfidence\n            ) ?? -.infinity",
            "return lhsDirectionConfidence < rhsDirectionConfidence",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertNotIn("lhs.directionConfidence.isFinite", self.crop_stage)
        self.assertNotIn("rhs.directionConfidence.isFinite", self.crop_stage)

    def test_existing_vertical_crop_budget_and_ordering_boundaries_remain(self) -> None:
        for marker in (
            "let lhsAtRisk = isJapaneseVerticalBlockAtRisk(lhs)",
            "let rhsAtRisk = isJapaneseVerticalBlockAtRisk(rhs)",
            "return lhsAtRisk && !rhsAtRisk",
            "let verticalBlocks = Self.boundedJapaneseVerticalCropBlocks(",
            "limit: 16",
            ".prefix(16)",
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            "Self.recognizeJapanesePixelFirstVerticalCrops(",
            "Self.recognizeJapaneseVerticalTileFallback(",
            "var orientationFallbacksRemaining = 8",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertEqual(self.crop_stage.count("orientationFallbacksRemaining -= 1"), 1)

    def test_recovery_remains_bounded_and_failure_cancel_safe(self) -> None:
        for marker in (
            "Self.boundedJapaneseWeakBlockRecoveryCandidates(",
            "Self.maximumJapaneseWeakBlockRecoveryRequests",
            "Task.checkCancellation()",
            "Self.recognizeTextBlockDetached(",
            "catch is CancellationError",
            "throw CancellationError()",
            "catch {",
            "continue",
        ):
            self.assertIn(marker, self.vision)

    def test_no_translation_persistence_or_optional_research_boundary_changes(self) -> None:
        for source in (self.helper, self.weak_recovery, self.risk_gate, self.crop_stage):
            self.assertNotIn("translate(", source)
            self.assertNotIn("persist(", source)
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("test/koharu_artifacts", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.362", "3.362"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3352-japanese-direction-confidence-risk-domain-contract.py",
            "v3.352",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, Path(__file__).read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
