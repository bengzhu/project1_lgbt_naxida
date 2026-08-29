#!/usr/bin/env python3
"""Static contract for v3.336 risk-first bounded Japanese vertical crops."""

from pathlib import Path
import math
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


def valid_confidence(value: float) -> float | None:
    return value if math.isfinite(value) and 0.0 <= value <= 1.0 else None


def at_risk(
    confidence: float,
    text: str,
    direction_confidence: float,
    direction: str = "vertical",
) -> bool:
    cleaned = text.strip()
    japanese = sum(
        any(
            lower <= ord(character) <= upper
            for lower, upper in (
                (0x3041, 0x3096),
                (0x30A1, 0x30FA),
                (0x3400, 0x4DBF),
                (0x4E00, 0x9FFF),
                (0xF900, 0xFAFF),
                (0xFF66, 0xFF9D),
            )
        )
        for character in cleaned
    )
    script_density = japanese / len(cleaned) if cleaned else 0.0
    letters = sum(
        any(
            lower <= ord(character) <= upper
            for lower, upper in (
                (0x3041, 0x3096),
                (0x30A1, 0x30FA),
                (0x3400, 0x4DBF),
                (0x4E00, 0x9FFF),
                (0xF900, 0xFAFF),
                (0xFF66, 0xFF9D),
            )
        )
        for character in cleaned
    )
    direction_is_weak = (
        direction != "vertical"
        or not math.isfinite(direction_confidence)
        or direction_confidence < 0.45
    )
    return (
        valid_confidence(confidence) is None
        or confidence < 0.60
        or not cleaned
        or script_density < 0.5
        or direction_is_weak
        or letters <= 2
    )


class JapaneseVerticalCropRiskPriorityContractTests(unittest.TestCase):
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
        cls.crop_stage = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )

    def test_risk_blocks_occupy_prefix_before_strong_blocks(self) -> None:
        blocks = [
            (0, 0.96, "今度こそ", 0.95),
            (1, 0.31, "ニコ", 0.35),
            (2, 0.88, "持ち帰る", 0.92),
            (3, 0.57, "やがって", 0.70),
        ]
        ordered = sorted(
            blocks,
            key=lambda block: (
                not at_risk(block[1], block[2], block[3]),
                valid_confidence(block[1])
                if valid_confidence(block[1]) is not None
                else float("-inf"),
            ),
        )
        self.assertEqual([block[0] for block in ordered[:2]], [1, 3])
        self.assertTrue(at_risk(0.31, "ニコ", 0.35))
        self.assertFalse(at_risk(0.96, "今度こそ", 0.95))

    def test_crop_sort_uses_risk_class_then_finite_weak_first_key(self) -> None:
        for marker in (
            "let lhsAtRisk = isJapaneseVerticalBlockAtRisk(lhs)",
            "let rhsAtRisk = isJapaneseVerticalBlockAtRisk(rhs)",
            "return lhsAtRisk && !rhsAtRisk",
            "let lhsConfidence = validOCRConfidence(lhs.confidence) ?? -.infinity",
            "let rhsConfidence = validOCRConfidence(rhs.confidence) ?? -.infinity",
            "return lhsConfidence < rhsConfidence",
            "lhs.directionConfidence.isFinite",
            "return lhsDirectionConfidence < rhsDirectionConfidence",
        ):
            self.assertIn(marker, self.crop_stage)

    def test_risk_gate_reuses_weak_text_and_direction_signals(self) -> None:
        risk_gate = function_body(
            self.vision,
            "private static func isJapaneseVerticalBlockAtRisk(\n",
        )
        for marker in (
            "postProcessJapaneseOCRText(block.text)",
            "validOCRConfidence(block.confidence) == nil",
            "block.confidence < 0.60",
            "text.isEmpty",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) < 0.5",
            "japaneseScriptDensity(in: text) < 0.5",
            "!block.directionConfidence.isFinite",
            "block.directionConfidence < 0.45",
            "letters <= 2",
        ):
            self.assertIn(marker, risk_gate)

    def test_request_cap_and_owner_assignment_are_unchanged(self) -> None:
        for marker in (
            ".prefix(16)",
            ".enumerated()",
            "owned.verticalTextRegionOwner = index",
            "let verticalBlockArray = Array(verticalBlocks)",
            "annotateJapaneseVerticalTextRegionOwners(",
            "var orientationFallbacksRemaining = 8",
        ):
            self.assertIn(marker, self.crop_stage)

    def test_line_first_and_reconnaissance_paths_remain_before_block_crops(self) -> None:
        for marker in (
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            "Self.recognizeJapanesePixelFirstVerticalCrops(",
            "Self.recognizeJapaneseVerticalTileFallback(",
            "for block in verticalBlocks",
            "koharuVerticalBlockCropRect(",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertLess(
            self.crop_stage.index("recognizeJapaneseVerticalLineCrops("),
            self.crop_stage.index("for block in verticalBlocks"),
        )

    def test_fallback_owner_coverage_and_orientation_budget_remain_bounded(self) -> None:
        for marker in (
            "hasCompleteJapaneseLineCoverage(",
            "blockFallbackCanReplacePartialLines(",
            "allowsBlockCropResults: true",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "verticalTextRegionOwner: block.verticalTextRegionOwner",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertEqual(self.crop_stage.count("orientationFallbacksRemaining -= 1"), 1)

    def test_downstream_translation_and_research_boundaries_are_unchanged(self) -> None:
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.vision, self.crop_stage):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("test/koharu_artifacts", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.342", "3.342"],
        )
        combined = self.workflow + self.flow + self.route + self.test_log + self.update_log
        for marker in (
            "scripts/test-v3336-japanese-vertical-crop-risk-priority-contract.py",
            "v3.342",
            "japanese-benchmark-v3.342-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3336-japanese-vertical-crop-risk-priority-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
