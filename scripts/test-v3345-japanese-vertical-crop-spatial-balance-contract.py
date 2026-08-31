#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 vertical crop spatial balance."""

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


def bounded_vertical_crop_blocks(
    blocks: list[Block], limit: int
) -> list[Block]:
    """Model v3.346 after the existing risk-first block ordering."""
    if limit <= 0 or len(blocks) <= limit:
        return blocks

    band_count = min(limit, len(blocks))
    bands: list[list[Block]] = [[] for _ in range(band_count)]
    for block in blocks:
        center_y = block.y
        bounded_center_y = (
            min(max(center_y, 0.0), 1.0)
            if math.isfinite(center_y)
            else 0.0
        )
        band = min(int(bounded_center_y * band_count), band_count - 1)
        bands[band].append(block)

    populated = [index for index, band in enumerate(bands) if band]
    if len(populated) <= 1:
        return blocks[:limit]

    selected: set[int] = set()
    cursors = [0] * band_count
    while len(selected) < limit:
        added = False
        for band_index in populated:
            if len(selected) >= limit or cursors[band_index] >= len(bands[band_index]):
                continue
            selected.add(bands[band_index][cursors[band_index]].offset)
            cursors[band_index] += 1
            added = True
        if not added:
            break
    return [block for block in blocks if block.offset in selected]


class JapaneseVerticalCropSpatialBalanceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.store = read("AITRANS/Services/TranslationSessionStore.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read("md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md")
            + read("update_log.md")
        )
        cls.crop_stage = function_body(
            cls.vision,
            "private static func recognizeJapaneseVerticalCrops(\n",
        )
        cls.selector = function_body(
            cls.vision,
            "private static func boundedJapaneseVerticalCropBlocks(\n",
        )

    def test_multi_band_queue_does_not_spend_all_sixteen_slots_in_one_band(self) -> None:
        blocks = [
            Block(0, 0.02),
            Block(1, 0.06),
            Block(2, 0.09),
            Block(3, 0.12),
            Block(4, 0.55),
            Block(5, 0.84),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=4)
        self.assertEqual([block.offset for block in selected], [0, 1, 4, 5])
        self.assertEqual({block.offset for block in selected}, {0, 1, 4, 5})

    def test_existing_priority_order_is_preserved_inside_bands_and_output(self) -> None:
        blocks = [
            Block(0, 0.04),
            Block(1, 0.06),
            Block(2, 0.54),
            Block(3, 0.56),
            Block(4, 0.84),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=4)
        self.assertEqual([block.offset for block in selected], [0, 1, 2, 4])

    def test_under_budget_and_single_band_queues_keep_historical_prefix(self) -> None:
        under_budget = [Block(index, 0.1) for index in range(4)]
        self.assertEqual(bounded_vertical_crop_blocks(under_budget, 4), under_budget)

        single_band = [Block(index, 0.04 + index * 0.02) for index in range(6)]
        self.assertEqual(
            bounded_vertical_crop_blocks(single_band, 4),
            single_band[:4],
        )

    def test_nonfinite_geometry_fails_closed_into_the_first_band(self) -> None:
        blocks = [
            Block(0, math.nan),
            Block(1, 0.04),
            Block(2, 0.58),
            Block(3, 0.86),
            Block(4, 0.90),
        ]
        selected = bounded_vertical_crop_blocks(blocks, limit=4)
        self.assertEqual([block.offset for block in selected], [0, 1, 2, 3])

    def test_risk_first_sort_runs_before_spatial_selector(self) -> None:
        for marker in (
            "let prioritizedVerticalBlocks = ImageOCRLayoutEngine.layout(",
            ".sorted { lhs, rhs in",
            "let lhsAtRisk = isJapaneseVerticalBlockAtRisk(lhs)",
            "let rhsAtRisk = isJapaneseVerticalBlockAtRisk(rhs)",
            "return lhsAtRisk && !rhsAtRisk",
            "validOCRConfidence(lhs.confidence) ?? -.infinity",
            "validOCRConfidence(rhs.confidence) ?? -.infinity",
            "return lhsConfidence < rhsConfidence",
            "let verticalBlocks = Self.boundedJapaneseVerticalCropBlocks(",
            "prioritizedVerticalBlocks",
            "limit: 16",
        ):
            self.assertIn(marker, self.crop_stage)

    def test_selector_is_only_over_budget_and_returns_original_priority_order(self) -> None:
        for marker in (
            "guard limit > 0, blocks.count > limit else { return blocks }",
            "let bandCount = min(limit, blocks.count)",
            "let centerY = block.rect.y + block.rect.height / 2",
            "centerY.isFinite",
            "let populatedBands = bands.indices.filter { !bands[$0].isEmpty }",
            "populatedBands.count > 1",
            "var selectedOffsets = Set<Int>()",
            "while selectedOffsets.count < limit",
            "for bandIndex in populatedBands",
            "return blocks.enumerated()",
            ".filter { selectedOffsets.contains($0.offset) }",
            ".map(\\.element)",
        ):
            self.assertIn(marker, self.selector)
        self.assertNotIn("Task", self.selector)

    def test_hard_cap_owner_assignment_and_existing_paths_remain(self) -> None:
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
        ):
            self.assertIn(marker, self.crop_stage)

    def test_block_fallback_quality_and_failure_boundaries_are_unchanged(self) -> None:
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
        self.assertIn(
            "private static func recognizeJapaneseVerticalCrops(\n"
            "        in image: CGImage,\n"
            "        observations: [VisionOCRObservation],\n"
            "        recognitionLanguages: [String]\n"
            "    ) async throws",
            self.vision,
        )

    def test_translation_persistence_and_optional_research_boundaries_remain(self) -> None:
        self.assertNotIn("ImageOCRLayoutEngine.layout", self.selector)
        self.assertNotIn("translate(", self.selector)
        self.assertNotIn("persist(", self.selector)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.crop_stage, self.selector):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("test/koharu_artifacts", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.384", "3.384"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3345-japanese-vertical-crop-spatial-balance-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3345-japanese-vertical-crop-spatial-balance-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
