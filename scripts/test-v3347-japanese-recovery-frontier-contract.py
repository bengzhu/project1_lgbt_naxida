#!/usr/bin/env python3
"""Static and pure-policy contract for v3.347 Japanese recovery frontier."""

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
class Observation:
    role: str
    text: str
    confidence: float
    rect: tuple[float, float, float, float]
    vertical: bool


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


def reliable_line_frontier(observations: list[Observation]) -> list[Observation]:
    """Model japaneseLinePathRegion's fail-closed coverage gate."""
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
    frontier: list[Observation],
) -> list[tuple[float, float, float, float]]:
    reliable = reliable_line_frontier(frontier)
    return [
        tile
        for tile in tiles
        if not any(overlap_ratio(observation.rect, tile) >= 0.60 for observation in reliable)
    ]


class JapaneseRecoveryFrontierContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.crops = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        cls.pixel = function_body(
            cls.vision,
            "private static func recognizeJapanesePixelFirstVerticalCrops(\n",
        )
        cls.detector = function_body(
            cls.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(\n",
        )
        cls.tile = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalTileFallback(\n",
        )
        cls.frontier = function_body(
            cls.vision,
            "private static func japaneseLinePathRegion(\n",
        )
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )

    def test_reliable_pixel_first_output_reaches_tile_frontier(self) -> None:
        pixel_call = self.crops.index(
            "let pixelFirstRefined = Self.recognizeJapanesePixelFirstVerticalCrops("
        )
        append_pixel = self.crops.index(
            "refined.append(contentsOf: pixelFirstRefined)", pixel_call
        )
        frontier = self.crops.index(
            "let recoveryFrontierObservations = lineRefined + pixelFirstRefined",
            append_pixel,
        )
        tile_call = self.crops.index(
            "Self.recognizeJapaneseVerticalTileFallback(", frontier
        )
        tile_argument = self.crops.index(
            "lineObservations: recoveryFrontierObservations", tile_call
        )
        self.assertLess(pixel_call, append_pixel)
        self.assertLess(append_pixel, frontier)
        self.assertLess(frontier, tile_call)
        self.assertLess(tile_call, tile_argument)

    def test_only_meaningful_pixel_first_results_can_suppress_tiles(self) -> None:
        for marker in (
            "meaningfulJapaneseRecoveryObservations(",
            "observationRole: .verticalLine",
            "isCompactJapaneseRecovery: isCompactCandidate",
        ):
            self.assertIn(marker, self.pixel)
        for marker in (
            "observationRole == .verticalLine",
            "validOCRConfidence(observation.confidence) != nil",
            "observation.confidence >= 0.48",
            "JapaneseOCRTextNormalizer.containsJapaneseLetter(text)",
            "japaneseScriptDensity(in: text) >= 0.5",
            "isVerticalLineCandidate(region)",
        ):
            self.assertIn(marker, self.frontier)
        self.assertIn("japaneseLinePathRegion(observation)", self.tile)
        self.assertIn("overlapRatio($0, tileRect) >= 0.60", self.tile)

    def test_reliable_pixel_frontier_frees_later_tile_slot(self) -> None:
        pixel = Observation(
            "verticalLine", "今度こそ", 0.82, (0.74, 0.20, 0.08, 0.42), True
        )
        duplicate_tile = (0.70, 0.10, 0.22, 0.62)
        later_gap = (0.10, 0.10, 0.22, 0.62)
        self.assertEqual(
            uncovered_tiles([duplicate_tile, later_gap], [pixel]),
            [later_gap],
        )

    def test_weak_empty_or_wrong_role_pixel_output_does_not_suppress_tiles(self) -> None:
        tile = (0.70, 0.10, 0.22, 0.62)
        weak = Observation("verticalLine", "弱", 0.20, (0.74, 0.20, 0.08, 0.42), True)
        empty = Observation("verticalLine", "", 0.90, (0.74, 0.20, 0.08, 0.42), True)
        horizontal = Observation("crop", "横", 0.90, (0.74, 0.20, 0.08, 0.42), False)
        self.assertEqual(uncovered_tiles([tile], [weak, empty, horizontal]), [tile])

    def test_frontier_model_keeps_existing_line_results(self) -> None:
        line = Observation("verticalLine", "持ち帰る！", 0.91, (0.20, 0.10, 0.08, 0.42), True)
        pixel = Observation("verticalLine", "今度こそ", 0.82, (0.74, 0.20, 0.08, 0.42), True)
        self.assertEqual(
            reliable_line_frontier([line, pixel]),
            [line, pixel],
        )

    def test_tile_budget_and_ordering_remain_bounded(self) -> None:
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

    def test_pixel_budget_orientation_and_geometry_paths_remain(self) -> None:
        for marker in (
            "for candidate in candidates.prefix(12)",
            "var orientationFallbacksRemaining = 4",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "expandedVerticalLineCropRect(",
            "prepareJapaneseCropForVision(crop.image)",
            "VNDetectTextRectanglesRequest()",
            "japanesePixelDetectorCharacterQuad(",
        ):
            self.assertIn(marker, self.pixel + self.crops + self.detector)
        self.assertIn("let reliableLineRegions = lineObservations.compactMap", self.tile)

    def test_no_translation_persistence_or_optional_research_path_enters_recovery_frontier(
        self,
    ) -> None:
        for source in (self.crops, self.pixel, self.tile, self.frontier):
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
            ["3.383", "3.383"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3347-japanese-recovery-frontier-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3347-japanese-recovery-frontier-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
