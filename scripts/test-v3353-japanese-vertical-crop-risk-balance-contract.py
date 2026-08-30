#!/usr/bin/env python3
"""Static and pure-policy contract for v3.353 vertical crop risk balance."""

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
class Block:
    offset: int
    y: float
    at_risk: bool


def bounded_vertical_crop_blocks(
    blocks: list[Block], limit: int
) -> list[Block]:
    """Model the v3.353 risk-first, same-class spatial selector."""
    if limit <= 0 or len(blocks) <= limit:
        return blocks

    band_count = min(limit, len(blocks))
    bands: list[list[Block]] = [[] for _ in range(band_count)]
    for block in blocks:
        bounded_center_y = (
            min(max(block.y, 0.0), 1.0)
            if math.isfinite(block.y)
            else 0.0
        )
        band = min(int(bounded_center_y * band_count), band_count - 1)
        bands[band].append(block)

    populated = [index for index, band in enumerate(bands) if band]
    if len(populated) <= 1:
        return blocks[:limit]

    def round_robin(
        source: list[list[Block]], populated_bands: list[int], slots: int
    ) -> list[Block]:
        selected: list[Block] = []
        cursors = [0] * band_count
        while len(selected) < slots:
            added = False
            for band_index in populated_bands:
                if len(selected) >= slots or cursors[band_index] >= len(source[band_index]):
                    continue
                selected.append(source[band_index][cursors[band_index]])
                cursors[band_index] += 1
                added = True
            if not added:
                break
        return selected

    risk_bands = [
        [block for block in band if block.at_risk]
        for band in bands
    ]
    populated_risk = [index for index, band in enumerate(risk_bands) if band]
    if populated_risk:
        selected = round_robin(risk_bands, populated_risk, limit)
        if len(selected) < limit:
            non_risk_bands = [
                [block for block in band if not block.at_risk]
                for band in bands
            ]
            populated_non_risk = [
                index for index, band in enumerate(non_risk_bands) if band
            ]
            selected.extend(
                round_robin(non_risk_bands, populated_non_risk, limit - len(selected))
            )
    else:
        selected = round_robin(bands, populated, limit)

    selected_offsets = {block.offset for block in selected}
    return [block for block in blocks if block.offset in selected_offsets]


class JapaneseVerticalCropRiskBalanceContractTests(unittest.TestCase):
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
        cls.selector = function_body(
            cls.vision,
            "private static func boundedJapaneseVerticalCropBlocks(\n",
        )
        cls.crop_stage = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )

    def test_dense_weak_band_is_not_displaced_by_strong_other_bands(self) -> None:
        blocks = [
            *[Block(index, 0.02, True) for index in range(16)],
            *[Block(16 + index, 0.10 + index * 0.055, False) for index in range(16)],
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=16)
        self.assertEqual([block.offset for block in selected], list(range(16)))
        self.assertTrue(all(block.at_risk for block in selected))

    def test_risky_candidates_are_balanced_only_inside_the_risk_class(self) -> None:
        blocks = [
            Block(0, 0.08, True),
            Block(1, 0.12, True),
            Block(2, 0.88, True),
            Block(3, 0.92, True),
            Block(4, 0.48, False),
            Block(5, 0.52, False),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=2)
        self.assertEqual([block.offset for block in selected], [0, 2])

    def test_all_risky_candidates_precede_non_risky_fill(self) -> None:
        blocks = [
            Block(0, 0.04, True),
            Block(1, 0.46, False),
            Block(2, 0.94, True),
            Block(3, 0.74, False),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=3)
        self.assertEqual([block.offset for block in selected], [0, 1, 2])

    def test_no_risk_candidates_keep_existing_spatial_round_robin(self) -> None:
        blocks = [
            Block(0, 0.02, False),
            Block(1, 0.06, False),
            Block(2, 0.09, False),
            Block(3, 0.12, False),
            Block(4, 0.55, False),
            Block(5, 0.84, False),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=4)
        self.assertEqual([block.offset for block in selected], [0, 1, 4, 5])

    def test_under_budget_and_single_band_keep_historical_prefix(self) -> None:
        under_budget = [Block(index, 0.1, index % 2 == 0) for index in range(4)]
        self.assertEqual(bounded_vertical_crop_blocks(under_budget, 4), under_budget)

        single_band = [Block(index, 0.04 + index * 0.02, True) for index in range(6)]
        self.assertEqual(
            bounded_vertical_crop_blocks(single_band, 4),
            single_band[:4],
        )

    def test_selector_keeps_geometry_fail_closed_and_original_output_order(self) -> None:
        blocks = [
            Block(0, math.nan, True),
            Block(1, 0.04, False),
            Block(2, 0.58, False),
            Block(3, 0.86, False),
            Block(4, 0.90, False),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=4)
        self.assertEqual([block.offset for block in selected], [0, 1, 2, 3])

    def test_risk_aware_selector_is_called_after_existing_risk_sort(self) -> None:
        for marker in (
            "let prioritizedVerticalBlocks = ImageOCRLayoutEngine.layout(",
            ".sorted { lhs, rhs in",
            "let lhsAtRisk = isJapaneseVerticalBlockAtRisk(lhs)",
            "let rhsAtRisk = isJapaneseVerticalBlockAtRisk(rhs)",
            "return lhsAtRisk && !rhsAtRisk",
            "let verticalBlocks = Self.boundedJapaneseVerticalCropBlocks(",
            "prioritizedVerticalBlocks",
            "limit: 16",
        ):
            self.assertIn(marker, self.crop_stage)

    def test_selector_contains_risk_first_then_same_class_spatial_pass(self) -> None:
        for marker in (
            "guard limit > 0, blocks.count > limit else { return blocks }",
            "let bandCount = min(limit, blocks.count)",
            "let centerY = block.rect.y + block.rect.height / 2",
            "centerY.isFinite",
            "let populatedBands = bands.indices.filter { !bands[$0].isEmpty }",
            "populatedBands.count > 1",
            "let riskBands = bands.map { offsets in",
            "isJapaneseVerticalBlockAtRisk(blocks[$0])",
            "let populatedRiskBands = riskBands.indices.filter",
            "var riskCursors = Array(repeating: 0, count: bandCount)",
            "for bandIndex in populatedRiskBands",
            "let nonRiskBands = bands.map { offsets in",
            "!isJapaneseVerticalBlockAtRisk(blocks[$0])",
            "var nonRiskCursors = Array(repeating: 0, count: bandCount)",
            "let populatedNonRiskBands = nonRiskBands.indices.filter",
            "return blocks.enumerated()",
            ".filter { selectedOffsets.contains($0.offset) }",
            ".map(\\.element)",
        ):
            self.assertIn(marker, self.selector)
        self.assertNotIn("ImageOCRLayoutEngine.layout", self.selector)
        self.assertNotIn("Task", self.selector)

    def test_hard_cap_and_existing_recovery_paths_remain(self) -> None:
        for marker in (
            ".prefix(16)",
            ".enumerated()",
            "owned.verticalTextRegionOwner = index",
            "let verticalBlockArray = Array(verticalBlocks)",
            "annotateJapaneseVerticalTextRegionOwners(",
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops(",
            "Self.recognizeJapanesePixelFirstVerticalCrops(",
            "Self.recognizeJapaneseVerticalTileFallback(",
            "var orientationFallbacksRemaining = 8",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
        ):
            self.assertIn(marker, self.crop_stage)
        self.assertEqual(self.crop_stage.count("orientationFallbacksRemaining -= 1"), 1)

    def test_fallback_quality_cancel_translation_persistence_and_research_boundaries_remain(self) -> None:
        for marker in (
            "hasCompleteJapaneseLineCoverage(",
            "blockFallbackCanReplacePartialLines(",
            "allowsBlockCropResults: true",
            "Task.checkCancellation()",
            "catch is CancellationError",
        ):
            self.assertIn(marker, self.crop_stage + self.vision)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.crop_stage, self.selector):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("test/koharu_artifacts", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.358", "3.358"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3353-japanese-vertical-crop-risk-balance-contract.py",
            "v3.353",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, Path(__file__).read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
