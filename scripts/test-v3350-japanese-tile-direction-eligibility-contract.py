#!/usr/bin/env python3
"""Static and pure-policy contract for v3.351 tile direction eligibility."""

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
class TileBlock:
    direction: str
    direction_confidence: float
    text: str
    confidence: float
    japanese_letter: bool
    japanese_density: float
    script_density: float
    rect: tuple[float, float, float, float]


@dataclass(frozen=True)
class LineObservation:
    role: str
    text: str
    confidence: float
    vertical: bool
    rect: tuple[float, float, float, float]


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


def vertical_tile_is_covered(
    block: tuple[float, float, float, float],
    tile: tuple[float, float, float, float],
) -> bool:
    bx, by, bw, bh = block
    tx, ty, tw, th = tile
    horizontal_intersection = max(
        0.0, min(bx + bw, tx + tw) - max(bx, tx)
    )
    horizontal_coverage = horizontal_intersection / max(min(bw, tw), 0.001)
    vertical_intersection = max(
        0.0, min(by + bh, ty + th) - max(by, ty)
    )
    vertical_coverage = vertical_intersection / max(th, 0.001)
    return horizontal_coverage >= 0.45 and vertical_coverage >= 0.30


def eligible_tile_blocks(blocks: list[TileBlock]) -> list[TileBlock]:
    """Model v3.351's fail-closed direction and OCR coverage gate."""
    return [
        block
        for block in blocks
        if (
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
    ]


def eligible_line_observations(
    observations: list[LineObservation],
) -> list[LineObservation]:
    return [
        observation
        for observation in observations
        if (
            observation.role == "verticalLine"
            and bool(observation.text.strip())
            and math.isfinite(observation.confidence)
            and 0.0 <= observation.confidence <= 1.0
            and observation.confidence >= 0.48
            and observation.vertical
        )
    ]


def uncovered_tiles(
    tiles: list[tuple[float, float, float, float]],
    blocks: list[TileBlock],
    lines: list[LineObservation],
) -> list[tuple[float, float, float, float]]:
    reliable_blocks = eligible_tile_blocks(blocks)
    reliable_lines = eligible_line_observations(lines)
    return [
        tile
        for tile in tiles
        if not any(
            vertical_tile_is_covered(block.rect, tile)
            for block in reliable_blocks
        )
        and not any(
            overlap_ratio(observation.rect, tile) >= 0.60
            for observation in reliable_lines
        )
    ]


class JapaneseTileDirectionEligibilityContractTests(unittest.TestCase):
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
        cls.tile = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        cls.risk = function_body(
            cls.vision,
            "private static func isJapaneseVerticalBlockAtRisk(",
        )
        cls.detector = function_body(
            cls.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(",
        )
        cls.crops = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        cls.frontier = function_body(
            cls.vision,
            "private static func japaneseLinePathRegion(",
        )

    def test_direction_quality_gate_precedes_tile_coverage(self) -> None:
        quality = self.tile.index(
            "let reliableVerticalBlocks = verticalBlocks.filter"
        )
        coverage = self.tile.index(
            "!reliableVerticalBlocks.contains(where:", quality
        )
        self.assertLess(quality, coverage)
        for marker in (
            "block.direction == .vertical",
            "block.directionConfidence.isFinite",
            "(0...1).contains(block.directionConfidence)",
            "block.directionConfidence >= 0.45",
            "let text = postProcessJapaneseOCRText(block.text)",
            "!text.isEmpty",
            "validOCRConfidence(block.confidence) != nil",
            "block.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "JapaneseOCRTextNormalizer.japaneseLetterDensity(text) >= 0.5",
            "japaneseScriptDensity(in: text) >= 0.5",
            "verticalTileIsCovered($0.rect, by: tileRect)",
        ):
            self.assertIn(marker, self.tile)

    def test_confident_vertical_block_suppresses_duplicate_tile(self) -> None:
        block = TileBlock(
            "vertical",
            0.84,
            "今度こそ",
            0.82,
            True,
            0.90,
            0.90,
            (0.74, 0.20, 0.08, 0.42),
        )
        tile = (0.70, 0.10, 0.22, 0.62)
        self.assertEqual(uncovered_tiles([tile], [block], []), [])

    def test_directionally_weak_vertical_block_leaves_tile_eligible(self) -> None:
        weak = TileBlock(
            "vertical",
            0.31,
            "今度こそ",
            0.82,
            True,
            0.90,
            0.90,
            (0.74, 0.20, 0.08, 0.42),
        )
        tile = (0.70, 0.10, 0.22, 0.62)
        self.assertEqual(uncovered_tiles([tile], [weak], []), [tile])

    def test_direction_confidence_domain_and_threshold_are_exact(self) -> None:
        rect = (0.74, 0.20, 0.08, 0.42)

        def block(direction_confidence: float) -> TileBlock:
            return TileBlock(
                "vertical",
                direction_confidence,
                "今度こそ",
                0.82,
                True,
                0.90,
                0.90,
                rect,
            )

        for confidence in (
            math.nan,
            math.inf,
            -math.inf,
            -0.01,
            0.449,
            1.01,
        ):
            self.assertEqual(eligible_tile_blocks([block(confidence)]), [])
        self.assertEqual(len(eligible_tile_blocks([block(0.45)])), 1)

    def test_existing_ocr_quality_gate_remains_required(self) -> None:
        rect = (0.74, 0.20, 0.08, 0.42)

        def block(confidence: float) -> TileBlock:
            return TileBlock(
                "vertical",
                0.84,
                "今度こそ",
                confidence,
                True,
                0.90,
                0.90,
                rect,
            )

        for confidence in (math.nan, math.inf, -math.inf, -0.01, 1.01, 0.479):
            self.assertEqual(eligible_tile_blocks([block(confidence)]), [])
        self.assertEqual(len(eligible_tile_blocks([block(0.48)])), 1)

    def test_empty_non_japanese_density_and_direction_fail_closed(self) -> None:
        rect = (0.74, 0.20, 0.08, 0.42)
        blocks = [
            TileBlock("vertical", 0.84, "", 0.90, True, 0.90, 0.90, rect),
            TileBlock("vertical", 0.84, "noise", 0.90, False, 0.90, 0.90, rect),
            TileBlock("vertical", 0.84, "かな", 0.90, True, 0.49, 0.90, rect),
            TileBlock("vertical", 0.84, "かな", 0.90, True, 0.90, 0.49, rect),
            TileBlock("horizontal", 0.84, "かな", 0.90, True, 0.90, 0.90, rect),
        ]
        self.assertEqual(eligible_tile_blocks(blocks), [])

    def test_risk_classifier_uses_the_same_direction_boundary(self) -> None:
        for marker in (
            "validJapaneseDirectionConfidence(block.directionConfidence) == nil",
            "block.directionConfidence < 0.45",
        ):
            self.assertIn(marker, self.risk)

    def test_line_frontier_remains_a_separate_coverage_gate(self) -> None:
        line = LineObservation(
            "verticalLine", "持ち帰る！", 0.91, True, (0.74, 0.20, 0.08, 0.42)
        )
        tile = (0.70, 0.10, 0.22, 0.62)
        self.assertEqual(uncovered_tiles([tile], [], [line]), [])
        weak_line = LineObservation(
            "verticalLine", "弱", 0.20, True, line.rect
        )
        self.assertEqual(uncovered_tiles([tile], [], [weak_line]), [tile])
        for marker in (
            "let reliableLineRegions = lineObservations.compactMap",
            "japaneseLinePathRegion(observation)",
            "overlapRatio($0, tileRect) >= 0.60",
        ):
            self.assertIn(marker, self.tile)
        for marker in (
            "observationRole == .verticalLine",
            "validOCRConfidence(observation.confidence) != nil",
            "observation.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "japaneseScriptDensity(in: text) >= 0.5",
            "isVerticalLineCandidate(region)",
        ):
            self.assertIn(marker, self.frontier)

    def test_tile_budget_and_crop_order_remain_bounded(self) -> None:
        for marker in (
            "let maximumTiles = 6",
            "let maximumWindows = 18",
            "guard processedWindowCount < maximumWindows else { return }",
            "processedWindowCount += 1",
            "for window in verticalWindows",
            "for start in mangaOrderedStarts",
            "return deduplicateJapaneseObservations(refined)",
        ):
            self.assertIn(marker, self.tile)
        self.assertEqual(self.tile.count("processedWindowCount += 1"), 1)

    def test_pixel_first_and_block_paths_keep_distinct_boundaries(self) -> None:
        self.assertIn("!overlapsLayoutBlock", self.detector)
        self.assertIn("!existingVerticalRegions.contains(where:", self.detector)
        self.assertIn(
            "let recoveryFrontierObservations = lineRefined + pixelFirstRefined",
            self.crops,
        )
        self.assertIn("lineObservations: recoveryFrontierObservations", self.crops)
        self.assertIn("!reliableVerticalBlocks.contains(where:", self.tile)

    def test_direction_gate_does_not_change_tile_crop_or_orientation_paths(self) -> None:
        for marker in (
            "japaneseVerticalSliceWindows(",
            "prepareJapaneseCropForVision(crop.image)",
            "recognizeJapaneseCropPass(",
            "angle: 90",
            "var orientationFallbacksRemaining = 4",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "angle: 270",
            "filterJapaneseVerticalTileObservations(primary)",
        ):
            self.assertIn(marker, self.tile)

    def test_translation_persistence_and_optional_research_stay_outside_gate(self) -> None:
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.tile, self.detector, self.crops):
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
            ["3.380", "3.380"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3350-japanese-tile-direction-eligibility-contract.py",
            "v3.351",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3350-japanese-tile-direction-eligibility-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
