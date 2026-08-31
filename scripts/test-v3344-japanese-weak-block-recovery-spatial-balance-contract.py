#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 weak-block recovery balance."""

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
class Candidate:
    offset: int
    y: float


def bounded_recovery_candidates(
    candidates: list[Candidate], limit: int
) -> list[Candidate]:
    """Model v3.346 after the existing weak-first sort."""
    if limit <= 0 or len(candidates) <= limit:
        return candidates

    band_count = min(limit, len(candidates))
    bands: list[list[Candidate]] = [[] for _ in range(band_count)]
    for candidate in candidates:
        center_y = candidate.y
        bounded_center_y = min(max(center_y, 0.0), 1.0) if math.isfinite(center_y) else 0.0
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
            candidate = bands[band_index][cursors[band_index]]
            cursors[band_index] += 1
            selected.add(candidate.offset)
            added = True
        if not added:
            break
    return [candidate for candidate in candidates if candidate.offset in selected]


class JapaneseWeakBlockRecoverySpatialBalanceContractTests(unittest.TestCase):
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
        cls.recovery = function_body(
            cls.vision,
            "private static func recoverWeakJapaneseBlocks(\n",
        )
        cls.selector = function_body(
            cls.vision,
            "private static func boundedJapaneseWeakBlockRecoveryCandidates(\n",
        )

    def test_spatial_round_robin_prevents_one_band_from_filling_the_budget(self) -> None:
        candidates = [
            Candidate(0, 0.03),
            Candidate(1, 0.06),
            Candidate(2, 0.09),
            Candidate(3, 0.12),
            Candidate(4, 0.55),
            Candidate(5, 0.82),
        ]
        selected = bounded_recovery_candidates(candidates, limit=4)
        self.assertEqual([candidate.offset for candidate in selected], [0, 1, 4, 5])
        self.assertEqual({candidate.offset for candidate in selected}, {0, 1, 4, 5})

    def test_selection_keeps_existing_weak_order_inside_each_band(self) -> None:
        candidates = [
            Candidate(0, 0.04),
            Candidate(1, 0.06),
            Candidate(2, 0.54),
            Candidate(3, 0.56),
            Candidate(4, 0.84),
        ]
        selected = bounded_recovery_candidates(candidates, limit=4)
        self.assertEqual([candidate.offset for candidate in selected], [0, 1, 2, 4])

    def test_under_budget_and_single_band_pages_keep_the_existing_prefix(self) -> None:
        under_budget = [Candidate(index, 0.1) for index in range(4)]
        self.assertEqual(bounded_recovery_candidates(under_budget, 4), under_budget)

        single_band = [Candidate(index, 0.04 + index * 0.02) for index in range(6)]
        self.assertEqual(
            bounded_recovery_candidates(single_band, 4),
            single_band[:4],
        )

    def test_invalid_geometry_fails_closed_into_the_first_band(self) -> None:
        candidates = [
            Candidate(0, math.nan),
            Candidate(1, 0.04),
            Candidate(2, 0.58),
            Candidate(3, 0.86),
            Candidate(4, 0.90),
        ]
        selected = bounded_recovery_candidates(candidates, limit=4)
        self.assertEqual([candidate.offset for candidate in selected], [0, 1, 2, 3])

    def test_recovery_keeps_existing_weak_sort_and_only_delegates_selection(self) -> None:
        for marker in (
            "let prioritizedCandidates = blocks.enumerated()",
            ".filter { needsJapaneseWeakBlockRecovery($0.element) }",
            ".sorted { lhs, rhs in",
            "validOCRConfidence(lhs.element.confidence)",
            "validOCRConfidence(rhs.element.confidence)",
            "return lhsConfidence < rhsConfidence",
            "return lhs.offset < rhs.offset",
            ".map { (offset: $0.offset, block: $0.element) }",
            "let candidates = Self.boundedJapaneseWeakBlockRecoveryCandidates(",
            "limit: Self.maximumJapaneseWeakBlockRecoveryRequests",
        ):
            self.assertIn(marker, self.recovery)
        self.assertNotIn(
            ".prefix(Self.maximumJapaneseWeakBlockRecoveryRequests)",
            self.recovery,
        )

    def test_selector_preserves_hard_budget_and_returns_original_order(self) -> None:
        for marker in (
            "guard limit > 0, candidates.count > limit else",
            "let bandCount = min(limit, candidates.count)",
            "let centerY = candidate.block.boundingBox.y",
            "centerY.isFinite",
            "let populatedBands = bands.indices.filter { !bands[$0].isEmpty }",
            "populatedBands.count > 1",
            "var selectedOffsets = Set<Int>()",
            "while selectedOffsets.count < limit",
            "for bandIndex in populatedBands",
            "return candidates.filter { selectedOffsets.contains($0.offset) }",
        ):
            self.assertIn(marker, self.selector)
        self.assertNotIn("Task", self.selector)

    def test_recovery_still_uses_scoped_reader_and_preserves_failure_cancel(self) -> None:
        for marker in (
            "guard !candidates.isEmpty else { return blocks }",
            "Task.checkCancellation()",
            "Self.recognizeTextBlockDetached(\n                    image: image,",
            "sourceLanguage: .japanese",
            "selectionReason: .existingLayoutFusion",
            "block: candidate.block",
            "recovered[candidate.offset] = reread",
            "catch is CancellationError",
            "throw CancellationError()",
            "catch {",
            "continue",
            "return recovered",
        ):
            self.assertIn(marker, self.recovery)

    def test_layout_translation_persistence_and_optional_research_boundaries_remain(self) -> None:
        self.assertNotIn("ImageOCRLayoutEngine.layout", self.recovery)
        self.assertNotIn("translate(", self.recovery)
        self.assertNotIn("persist(", self.recovery)
        self.assertIn("translateImageBlockWithQA(", self.store)
        self.assertIn("persist()", self.store)
        for source in (self.recovery, self.selector):
            self.assertNotIn("groundTruth", source)
            self.assertNotIn("KOHARU_DATA_ROOT", source)
            self.assertNotIn("test/koharu_artifacts", source)

    def test_version_workflow_docs_and_static_only_boundary_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.373", "3.373"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3344-japanese-weak-block-recovery-spatial-balance-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)
        contract = read(
            "scripts/test-v3344-japanese-weak-block-recovery-spatial-balance-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
