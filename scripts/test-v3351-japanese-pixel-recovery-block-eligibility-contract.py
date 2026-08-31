#!/usr/bin/env python3
"""Static and pure-policy contract for v3.351 pixel recovery block eligibility."""

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
class LayoutBlock:
    direction: str
    direction_confidence: float
    text: str
    confidence: float
    japanese_letter: bool
    japanese_density: float
    script_density: float
    rect: tuple[float, float, float, float]


def reliable_vertical_block(block: LayoutBlock) -> bool:
    """Model the block-coverage gate shared by tile and pixel recovery."""
    return (
        block.direction == "vertical"
        and math.isfinite(block.direction_confidence)
        and 0.0 <= block.direction_confidence <= 1.0
        and block.direction_confidence >= 0.45
        and bool(block.text.strip())
        and math.isfinite(block.confidence)
        and 0.0 <= block.confidence <= 1.0
        and block.confidence >= 0.48
        and block.japanese_letter
        and block.japanese_density >= 0.5
        and block.script_density >= 0.5
    )


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


def pixel_detector_region_is_covered(
    block: tuple[float, float, float, float],
    candidate: tuple[float, float, float, float],
) -> bool:
    bx, by, bw, bh = block
    cx, cy, cw, ch = candidate
    horizontal_intersection = max(
        0.0, min(bx + bw, cx + cw) - max(bx, cx)
    )
    horizontal_coverage = horizontal_intersection / max(min(bw, cw), 0.001)
    vertical_intersection = max(
        0.0, min(by + bh, cy + ch) - max(by, cy)
    )
    vertical_coverage = vertical_intersection / max(ch, 0.001)
    return horizontal_coverage >= 0.45 and vertical_coverage >= 0.60


def pixel_candidate_is_covered(
    candidate: tuple[float, float, float, float],
    blocks: list[LayoutBlock],
) -> bool:
    return any(
        reliable_vertical_block(block)
        and pixel_detector_region_is_covered(block.rect, candidate)
        for block in blocks
    )


class JapanesePixelRecoveryBlockEligibilityContractTests(unittest.TestCase):
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
        cls.tile = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalTileFallback(\n",
        )

    def test_reliable_block_still_suppresses_duplicate_pixel_geometry(self) -> None:
        block = LayoutBlock(
            "vertical",
            0.84,
            "今度こそ",
            0.82,
            True,
            0.90,
            0.90,
            (0.40, 0.20, 0.08, 0.42),
        )
        candidate = (0.39, 0.18, 0.10, 0.48)
        self.assertTrue(reliable_vertical_block(block))
        self.assertTrue(pixel_candidate_is_covered(candidate, [block]))

    def test_weak_block_leaves_pixel_first_geometry_eligible(self) -> None:
        weak = LayoutBlock(
            "vertical",
            0.84,
            "今度こそ",
            0.31,
            True,
            0.90,
            0.90,
            (0.40, 0.20, 0.08, 0.42),
        )
        candidate = (0.39, 0.18, 0.10, 0.48)
        self.assertFalse(reliable_vertical_block(weak))
        self.assertFalse(pixel_candidate_is_covered(candidate, [weak]))

    def test_all_block_quality_failures_fail_closed(self) -> None:
        rect = (0.40, 0.20, 0.08, 0.42)
        failures = [
            LayoutBlock("horizontal", 0.90, "今度こそ", 0.90, True, 0.9, 0.9, rect),
            LayoutBlock("vertical", 0.31, "今度こそ", 0.90, True, 0.9, 0.9, rect),
            LayoutBlock("vertical", math.nan, "今度こそ", 0.90, True, 0.9, 0.9, rect),
            LayoutBlock("vertical", 1.01, "今度こそ", 0.90, True, 0.9, 0.9, rect),
            LayoutBlock("vertical", 0.90, "", 0.90, True, 0.9, 0.9, rect),
            LayoutBlock("vertical", 0.90, "noise", 0.90, False, 0.9, 0.9, rect),
            LayoutBlock("vertical", 0.90, "かな", 0.90, True, 0.49, 0.9, rect),
            LayoutBlock("vertical", 0.90, "かな", 0.90, True, 0.9, 0.49, rect),
            LayoutBlock("vertical", 0.90, "今度こそ", math.inf, True, 0.9, 0.9, rect),
            LayoutBlock("vertical", 0.90, "今度こそ", 0.479, True, 0.9, 0.9, rect),
        ]
        self.assertTrue(all(not reliable_vertical_block(block) for block in failures))

    def test_block_gate_precedes_pixel_geometry_coverage(self) -> None:
        gate = self.detector.index(
            "let reliableVerticalBlocks = verticalBlocks.filter"
        )
        coverage = self.detector.index(
            "let overlapsLayoutBlock = reliableVerticalBlocks.contains",
            gate,
        )
        self.assertLess(gate, coverage)
        for marker in (
            "let text = postProcessJapaneseOCRText(block.text)",
            "block.direction == .vertical",
            "block.directionConfidence.isFinite",
            "(0...1).contains(block.directionConfidence)",
            "block.directionConfidence >= 0.45",
            "!text.isEmpty",
            "validOCRConfidence(block.confidence) != nil",
            "block.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
            "japanesePixelDetectorRegionIsCovered(",
            "!overlapsLayoutBlock",
        ):
            self.assertIn(marker, self.detector)
        self.assertNotIn(
            "let overlapsLayoutBlock = verticalBlocks.contains",
            self.detector,
        )

    def test_existing_observation_gate_remains_independent(self) -> None:
        for marker in (
            "let existingVerticalRegions = observations.compactMap",
            "observation.sourceDirectionHint == .vertical",
            "observation.observationRole == .verticalLine",
            "isWeakCompactJapaneseOwner(observation)",
            "validOCRConfidence(observation.confidence) != nil",
            "observation.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
            "!existingVerticalRegions.contains(where:",
        ):
            self.assertIn(marker, self.detector)

    def test_line_frontier_and_tile_gate_are_not_replaced(self) -> None:
        for marker in (
            "let reliableLineRegions = lineObservations.compactMap",
            "japaneseLinePathRegion(observation)",
            "!reliableLineRegions.contains(where:",
        ):
            self.assertIn(marker, self.detector)
        for marker in (
            "let reliableVerticalBlocks = verticalBlocks.filter",
            "block.directionConfidence >= 0.45",
            "verticalTileIsCovered($0.rect, by: tileRect)",
        ):
            self.assertIn(marker, self.tile)

    def test_pixel_first_budget_and_crop_order_remain_bounded(self) -> None:
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
        ):
            self.assertIn(marker, self.detector + self.pixel)
        self.assertEqual(self.pixel.count("orientationFallbacksRemaining -= 1"), 1)

    def test_vertical_pipeline_order_and_recovery_frontier_remain(self) -> None:
        for marker in (
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            "Self.recognizeJapanesePixelFirstVerticalCrops(",
            "Self.recognizeJapaneseVerticalTileFallback(",
            "let recoveryFrontierObservations = lineRefined + pixelFirstRefined",
            "lineObservations: recoveryFrontierObservations",
            "for block in verticalBlocks",
        ):
            self.assertIn(marker, self.crops)
        self.assertLess(
            self.crops.index("Self.recognizeJapanesePixelFirstVerticalCrops("),
            self.crops.index("Self.recognizeJapaneseVerticalTileFallback("),
        )

    def test_no_translation_persistence_or_optional_research_in_detector_gate(self) -> None:
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.detector, self.pixel, self.crops, self.tile):
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
            ["3.378", "3.378"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3351-japanese-pixel-recovery-block-eligibility-contract.py",
            "v3.351",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, read(
                "scripts/test-v3351-japanese-pixel-recovery-block-eligibility-contract.py"
            ))


if __name__ == "__main__":
    unittest.main(verbosity=2)
