#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 pixel-first spatial balance."""

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
class Region:
    offset: int
    y: float


def bounded_regular_regions(
    regions: list[Region], limit: int
) -> list[Region]:
    """Model v3.346 after the existing regular-region priority sort."""
    if limit <= 0 or len(regions) <= limit:
        return regions

    band_count = min(limit, len(regions))
    bands: list[list[Region]] = [[] for _ in range(band_count)]
    for region in regions:
        center_y = region.y
        bounded_center_y = (
            min(max(center_y, 0.0), 1.0)
            if math.isfinite(center_y)
            else 0.0
        )
        band = min(int(bounded_center_y * band_count), band_count - 1)
        bands[band].append(region)

    populated = [index for index, band in enumerate(bands) if band]
    if len(populated) <= 1:
        return regions[:limit]

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
    return [region for region in regions if region.offset in selected]


class JapanesePixelFirstSpatialBalanceContractTests(unittest.TestCase):
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
        cls.detector = function_body(
            cls.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(\n",
        )
        cls.selector = function_body(
            cls.vision,
            "private static func boundedJapanesePixelFirstRegularCandidates(\n",
        )
        cls.pixel = function_body(
            cls.vision,
            "private static func recognizeJapanesePixelFirstVerticalCrops(\n",
        )

    def test_multi_band_regular_queue_does_not_fill_all_slots_from_one_band(self) -> None:
        regions = [
            Region(0, 0.02),
            Region(1, 0.06),
            Region(2, 0.09),
            Region(3, 0.12),
            Region(4, 0.55),
            Region(5, 0.84),
        ]
        selected = bounded_regular_regions(regions, limit=4)
        self.assertEqual([region.offset for region in selected], [0, 1, 4, 5])

    def test_original_priority_order_is_preserved_inside_bands_and_output(self) -> None:
        regions = [
            Region(0, 0.04),
            Region(1, 0.06),
            Region(2, 0.54),
            Region(3, 0.56),
            Region(4, 0.84),
        ]
        selected = bounded_regular_regions(regions, limit=4)
        self.assertEqual([region.offset for region in selected], [0, 1, 2, 4])

    def test_under_budget_and_single_band_keep_the_existing_prefix(self) -> None:
        under_budget = [Region(index, 0.1) for index in range(4)]
        self.assertEqual(bounded_regular_regions(under_budget, 4), under_budget)

        single_band = [Region(index, 0.04 + index * 0.02) for index in range(6)]
        self.assertEqual(
            bounded_regular_regions(single_band, 4),
            single_band[:4],
        )

    def test_nonfinite_geometry_fails_closed_into_the_first_band(self) -> None:
        regions = [
            Region(0, math.nan),
            Region(1, 0.04),
            Region(2, 0.58),
            Region(3, 0.86),
            Region(4, 0.90),
        ]
        selected = bounded_regular_regions(regions, limit=4)
        self.assertEqual([region.offset for region in selected], [0, 1, 2, 3])

    def test_compact_reservation_and_regular_budget_partition_stay_in_place(self) -> None:
        for marker in (
            "let compactCandidates = unique",
            "let reservedCompact = Array(compactCandidates.prefix(4))",
            "let regularCandidates = unique.filter",
            "let remaining = max(0, 12 - reservedCompact.count)",
            "let selectedRegular = Self.boundedJapanesePixelFirstRegularCandidates(",
            "regularCandidates",
            "limit: remaining",
            "return reservedCompact + selectedRegular",
        ):
            self.assertIn(marker, self.detector)

    def test_selector_is_only_over_budget_and_returns_original_priority_order(self) -> None:
        for marker in (
            "guard limit > 0, candidates.count > limit else { return candidates }",
            "let bandCount = min(limit, candidates.count)",
            "let centerY = candidate.rect.y + candidate.rect.height / 2",
            "centerY.isFinite",
            "let populatedBands = bands.indices.filter { !bands[$0].isEmpty }",
            "populatedBands.count > 1",
            "var selectedOffsets = Set<Int>()",
            "while selectedOffsets.count < limit",
            "for bandIndex in populatedBands",
            "return candidates.enumerated()",
            ".filter { selectedOffsets.contains($0.offset) }",
            ".map(\\.element)",
        ):
            self.assertIn(marker, self.selector)
        self.assertNotIn("Task", self.selector)

    def test_pixel_first_recognition_cap_preprocess_and_orientation_budget_remain(self) -> None:
        for marker in (
            "for candidate in candidates.prefix(12)",
            "expandedVerticalLineCropRect(",
            "prepareJapaneseCropForVision(crop.image)",
            "recognizeJapaneseCropPass(",
            "var orientationFallbacksRemaining = 4",
            "orientationFallbacksRemaining > 0",
            "orientationFallbacksRemaining -= 1",
            "observationRole: .verticalLine",
            "meaningfulJapaneseRecoveryObservations(",
        ):
            self.assertIn(marker, self.pixel)
        self.assertEqual(self.pixel.count("orientationFallbacksRemaining -= 1"), 1)

    def test_detector_geometry_and_downstream_boundaries_are_unchanged(self) -> None:
        for marker in (
            "VNDetectTextRectanglesRequest()",
            "request.reportCharacterBoxes = true",
            "japanesePixelDetectorCharacterEnvelope(",
            "japanesePixelDetectorCharacterQuad(",
            "!overlapsLayoutBlock",
            "!existingVerticalRegions.contains(where:",
            "!reliableLineRegions.contains(where:",
        ):
            self.assertIn(marker, self.detector)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)

    def test_failure_cancel_quality_and_optional_research_boundaries_remain(self) -> None:
        for source in (self.detector, self.pixel, self.selector):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("test/koharu_artifacts", source)
        self.assertIn("async throws", self.vision)
        self.assertIn("meaningfulJapaneseRecoveryObservations", self.pixel)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.354", "3.354"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3346-japanese-pixel-first-spatial-balance-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3346-japanese-pixel-first-spatial-balance-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
