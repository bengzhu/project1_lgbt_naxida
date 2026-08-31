#!/usr/bin/env python3
"""Static and pure-policy contract for v3.356 compact spatial balance."""

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
class CompactCandidate:
    index: int
    y: float


def bounded_compact_candidates(
    candidates: list[CompactCandidate], limit: int
) -> list[CompactCandidate]:
    """Model the selector after the existing compact priority sort."""
    if limit <= 0 or len(candidates) <= limit:
        return candidates

    band_count = min(limit, len(candidates))
    bands: list[list[CompactCandidate]] = [[] for _ in range(band_count)]
    for candidate in candidates:
        bounded_center_y = (
            min(max(candidate.y, 0.0), 1.0)
            if math.isfinite(candidate.y)
            else 0.0
        )
        band = min(int(bounded_center_y * band_count), band_count - 1)
        bands[band].append(candidate)

    populated = [index for index, band in enumerate(bands) if band]
    if len(populated) <= 1:
        return candidates[:limit]

    selected: set[int] = set()
    cursors = [0] * band_count
    while len(selected) < limit:
        added = False
        for band_index in populated:
            if len(selected) >= limit or cursors[band_index] >= len(bands[band_index]):
                continue
            selected.add(bands[band_index][cursors[band_index]].index)
            cursors[band_index] += 1
            added = True
        if not added:
            break
    return [candidate for candidate in candidates if candidate.index in selected]


class JapaneseCompactSpatialBalanceContractTests(unittest.TestCase):
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
            + read(
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
            )
            + read("update_log.md")
        )
        cls.detector = function_body(
            cls.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(\n",
        )
        cls.selector = function_body(
            cls.vision,
            "private static func boundedJapanesePixelFirstCompactCandidates(\n",
        )
        cls.pixel_reader = function_body(
            cls.vision,
            "private static func recognizeJapanesePixelFirstVerticalCrops(\n",
        )

    def test_multi_band_compact_pool_does_not_fill_one_band(self) -> None:
        candidates = [
            CompactCandidate(0, 0.02),
            CompactCandidate(1, 0.06),
            CompactCandidate(2, 0.09),
            CompactCandidate(3, 0.12),
            CompactCandidate(4, 0.55),
            CompactCandidate(5, 0.84),
        ]
        selected = bounded_compact_candidates(candidates, limit=4)
        self.assertEqual([candidate.index for candidate in selected], [0, 1, 4, 5])
        self.assertEqual({candidate.index for candidate in selected}, {0, 1, 4, 5})

    def test_priority_order_inside_bands_and_output_is_preserved(self) -> None:
        candidates = [
            CompactCandidate(0, 0.04),
            CompactCandidate(1, 0.06),
            CompactCandidate(2, 0.54),
            CompactCandidate(3, 0.56),
            CompactCandidate(4, 0.84),
        ]
        selected = bounded_compact_candidates(candidates, limit=4)
        self.assertEqual([candidate.index for candidate in selected], [0, 1, 2, 4])

    def test_under_budget_and_single_band_keep_historical_prefix(self) -> None:
        under_budget = [CompactCandidate(index, 0.1) for index in range(4)]
        self.assertEqual(bounded_compact_candidates(under_budget, 4), under_budget)

        single_band = [CompactCandidate(index, 0.04 + index * 0.02) for index in range(6)]
        self.assertEqual(
            bounded_compact_candidates(single_band, 4),
            single_band[:4],
        )

    def test_invalid_geometry_fails_closed_into_the_first_band(self) -> None:
        candidates = [
            CompactCandidate(0, math.nan),
            CompactCandidate(1, 0.04),
            CompactCandidate(2, 0.58),
            CompactCandidate(3, 0.86),
            CompactCandidate(4, 0.90),
        ]
        selected = bounded_compact_candidates(candidates, limit=4)
        self.assertEqual([candidate.index for candidate in selected], [0, 1, 2, 3])

    def test_compact_selector_replaces_direct_prefix_after_existing_sort(self) -> None:
        for marker in (
            "let compactCandidates = unique",
            ".sorted { lhs, rhs in",
            "let reservedCompact = Self.boundedJapanesePixelFirstCompactCandidates(",
            "compactCandidates,",
            "limit: 4",
            "let regularCandidates = unique.filter { candidate in",
            "let remaining = max(0, 12 - reservedCompact.count)",
        ):
            self.assertIn(marker, self.detector)
        self.assertNotIn("let reservedCompact = Array(compactCandidates.prefix(4))", self.detector)

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

    def test_pixel_budget_and_existing_geometry_paths_remain(self) -> None:
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
            "let reservedCompact = Self.boundedJapanesePixelFirstCompactCandidates(",
        ):
            self.assertIn(marker, self.detector + self.pixel_reader)

    def test_compact_selection_does_not_change_quality_or_downstream_boundaries(self) -> None:
        for marker in (
            "meaningfulJapaneseRecoveryObservations(",
            "deduplicateJapaneseCompactRecoveryObservations(",
            "translateImageBlockWithQA(",
            "persist()",
        ):
            self.assertIn(marker, self.vision + self.store)
        for source in (self.detector, self.selector, self.pixel_reader):
            for forbidden in (
                "groundTruth",
                "KOHARU_DATA_ROOT",
                "test/koharu_artifacts",
                "TranslationSessionStore",
                "persist(",
            ):
                self.assertNotIn(forbidden, source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.380", "3.380"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3355-japanese-geometry-owner-balance-contract.py",
            "scripts/test-v3356-japanese-compact-spatial-balance-contract.py",
            "v3.356",
            "japanese-benchmark-v3.356-",
        ):
            self.assertIn(marker, combined)
        contract = Path(__file__).read_text(encoding="utf-8")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
