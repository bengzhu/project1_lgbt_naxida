#!/usr/bin/env python3
"""Static and pure-policy contract for v3.373 compact-aware pixel dedupe."""

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
class Rect:
    x: float
    y: float
    width: float
    height: float

    @property
    def max_x(self) -> float:
        return self.x + self.width

    @property
    def max_y(self) -> float:
        return self.y + self.height


@dataclass(frozen=True)
class Candidate:
    rect: Rect
    character_count: int


def area(rect: Rect) -> float:
    return rect.width * rect.height


def intersection_area(lhs: Rect, rhs: Rect) -> float:
    width = max(0.0, min(lhs.max_x, rhs.max_x) - max(lhs.x, rhs.x))
    height = max(0.0, min(lhs.max_y, rhs.max_y) - max(lhs.y, rhs.y))
    return width * height


def iou(lhs: Rect, rhs: Rect) -> float:
    intersection = intersection_area(lhs, rhs)
    union = area(lhs) + area(rhs) - intersection
    return intersection / union if union > 0 else 0.0


def overlap_ratio(lhs: Rect, rhs: Rect) -> float:
    minimum_area = max(min(area(lhs), area(rhs)), 0.0001)
    return intersection_area(lhs, rhs) / minimum_area


def is_compact(candidate: Candidate) -> bool:
    rect = candidate.rect
    if not 2 <= candidate.character_count <= 4:
        return False
    if not 0.012 <= rect.width <= 0.08:
        return False
    if not 0.006 <= rect.height <= 0.08:
        return False
    shortest = max(min(rect.width, rect.height), 0.001)
    longest = max(rect.width, rect.height)
    return longest / shortest <= 4.5


def is_same(lhs: Candidate, rhs: Candidate) -> bool:
    return iou(lhs.rect, rhs.rect) >= 0.45 or overlap_ratio(lhs.rect, rhs.rect) >= 0.65


def should_prefer_compact(candidate: Candidate, incumbent: Candidate) -> bool:
    if not is_compact(candidate) or is_compact(incumbent):
        return False
    candidate_area = area(candidate.rect)
    incumbent_area = area(incumbent.rect)
    if (
        not math.isfinite(candidate_area)
        or not math.isfinite(incumbent_area)
        or candidate_area <= 0
        or incumbent_area <= 0
    ):
        return False
    smaller_to_larger = min(candidate_area, incumbent_area) / max(
        candidate_area, incumbent_area
    )
    return smaller_to_larger >= 0.50 and iou(candidate.rect, incumbent.rect) >= 0.45


def deduplicate_in_order(candidates: list[Candidate]) -> list[Candidate]:
    output: list[Candidate] = []
    for candidate in candidates:
        duplicate_index = next(
            (
                index
                for index, incumbent in enumerate(output)
                if is_same(candidate, incumbent)
            ),
            None,
        )
        if duplicate_index is None:
            output.append(candidate)
        elif should_prefer_compact(candidate, output[duplicate_index]):
            output[duplicate_index] = candidate
    return output


class JapanesePixelCompactDedupeContractTests(unittest.TestCase):
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
        cls.helper = function_body(
            cls.vision,
            "private static func shouldPreferJapanesePixelFirstCompactRegion(\n",
        )

    def test_comparable_duplicate_preserves_compact_qualification(self) -> None:
        regular = Candidate(Rect(0.20, 0.20, 0.040, 0.060), 5)
        compact = Candidate(Rect(0.201, 0.201, 0.039, 0.059), 3)
        self.assertTrue(is_same(compact, regular))
        self.assertTrue(should_prefer_compact(compact, regular))
        selected = deduplicate_in_order([regular, compact])
        self.assertEqual(selected, [compact])

    def test_materially_broader_regular_region_stays(self) -> None:
        regular = Candidate(Rect(0.20, 0.20, 0.060, 0.100), 7)
        compact = Candidate(Rect(0.215, 0.210, 0.030, 0.080), 3)
        self.assertTrue(is_same(compact, regular))
        self.assertFalse(should_prefer_compact(compact, regular))
        self.assertEqual(deduplicate_in_order([regular, compact]), [regular])

    def test_noncompact_duplicate_and_existing_compact_keep_historical_first(self) -> None:
        first = Candidate(Rect(0.20, 0.20, 0.040, 0.060), 6)
        second = Candidate(Rect(0.201, 0.201, 0.039, 0.059), 7)
        self.assertEqual(deduplicate_in_order([first, second]), [first])

        compact = Candidate(Rect(0.20, 0.20, 0.040, 0.060), 3)
        regular = Candidate(Rect(0.201, 0.201, 0.039, 0.059), 6)
        self.assertEqual(deduplicate_in_order([compact, regular]), [compact])

    def test_compact_gate_and_nonfinite_area_fail_closed(self) -> None:
        self.assertTrue(is_compact(Candidate(Rect(0, 0, 0.02, 0.06), 4)))
        self.assertFalse(is_compact(Candidate(Rect(0, 0, 0.02, 0.06), 5)))
        self.assertFalse(is_compact(Candidate(Rect(0, 0, 0.01, 0.06), 3)))
        self.assertFalse(
            should_prefer_compact(
                Candidate(Rect(0, 0, math.nan, 0.06), 3),
                Candidate(Rect(0, 0, 0.04, 0.06), 6),
            )
        )

    def test_detector_dedupes_before_compact_reservation(self) -> None:
        for marker in (
            "let duplicateIndex = unique.firstIndex(where: {",
            "isSameJapanesePixelFirstRegion(candidate, as: $0)",
            "shouldPreferJapanesePixelFirstCompactRegion(",
            "unique[duplicateIndex] = candidate",
            "let compactCandidates = unique",
            "let reservedCompact = Self.boundedJapanesePixelFirstCompactCandidates(",
        ):
            self.assertIn(marker, self.detector)
        self.assertLess(
            self.detector.index("shouldPreferJapanesePixelFirstCompactRegion("),
            self.detector.index("let compactCandidates = unique"),
        )

    def test_helper_is_tight_comparable_and_no_budget_expansion(self) -> None:
        for marker in (
            "isJapanesePixelFirstCompactCandidate(",
            "candidateArea",
            "incumbentArea",
            "isFinite",
            "smallerToLarger",
            "smallerToLarger >= 0.50",
            "intersectionOverUnion(candidate.rect, incumbent.rect) >= 0.45",
        ):
            self.assertIn(marker, self.helper)
        self.assertNotIn("Task", self.helper)
        for marker in (
            "unique.count == 128",
            "for candidate in candidates.prefix(12)",
            "limit: 4",
            "let remaining = max(0, 12 - reservedCompact.count)",
            "orientationFallbacksRemaining = 4",
            "orientationFallbacksRemaining -= 1",
        ):
            self.assertIn(marker, self.detector + self.vision)

    def test_downstream_quality_translation_and_persistence_boundaries_remain(self) -> None:
        for marker in (
            "meaningfulJapaneseRecoveryObservations(",
            "deduplicateJapaneseCompactRecoveryObservations(",
            "translateImageBlockWithQA(",
            "persist()",
        ):
            self.assertIn(marker, self.vision + self.store)
        for source in (self.detector, self.helper):
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
            ["3.373", "3.373"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3360-japanese-recovery-frontier-block-skip-contract.py",
            "scripts/test-v3361-japanese-pixel-compact-dedupe-contract.py",
            "v3.373",
            "japanese-benchmark-v3.373-",
        ):
            self.assertIn(marker, combined)
        contract = Path(__file__).read_text(encoding="utf-8")
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)


if __name__ == "__main__":
    unittest.main(verbosity=2)
