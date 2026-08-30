#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 detector merge closure."""

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


Rect = tuple[float, float, float, float]


def area(rect: Rect) -> float:
    return max(rect[2], 0.0) * max(rect[3], 0.0)


def intersection_area(lhs: Rect, rhs: Rect) -> float:
    x = max(0.0, min(lhs[0] + lhs[2], rhs[0] + rhs[2]) - max(lhs[0], rhs[0]))
    y = max(0.0, min(lhs[1] + lhs[3], rhs[1] + rhs[3]) - max(lhs[1], rhs[1]))
    return x * y


def union(lhs: Rect, rhs: Rect) -> Rect:
    left = min(lhs[0], rhs[0])
    top = min(lhs[1], rhs[1])
    right = max(lhs[0] + lhs[2], rhs[0] + rhs[2])
    bottom = max(lhs[1] + lhs[3], rhs[1] + rhs[3])
    return (left, top, right - left, bottom - top)


def iou(lhs: Rect, rhs: Rect) -> float:
    intersection = intersection_area(lhs, rhs)
    combined = area(lhs) + area(rhs) - intersection
    return intersection / combined if combined > 0 else 0.0


def mostly_contained(outer: Rect, inner: Rect, threshold: float = 0.30) -> bool:
    inner_area = area(inner)
    return inner_area > 0 and intersection_area(outer, inner) / inner_area >= threshold


def overlaps(lhs: Rect, rhs: Rect) -> bool:
    return (
        iou(lhs, rhs) >= 0.50
        or mostly_contained(lhs, rhs)
        or mostly_contained(rhs, lhs)
    )


def merge_once(rects: list[Rect]) -> list[Rect]:
    """Model the pre-v3.346 scan, including swap-remove ordering."""
    remaining = list(rects)
    merged: list[Rect] = []
    while remaining:
        candidate = remaining.pop()
        index = 0
        while index < len(remaining):
            other = remaining[index]
            if not overlaps(candidate, other):
                index += 1
                continue
            candidate = union(candidate, other)
            remaining[index] = remaining[-1]
            remaining.pop()
        merged.append(candidate)
    return merged


def merge_to_closure(rects: list[Rect]) -> list[Rect]:
    """Model the v3.346 scan, restarting after every envelope expansion."""
    remaining = list(rects)
    merged: list[Rect] = []
    while remaining:
        candidate = remaining.pop()
        index = 0
        while index < len(remaining):
            other = remaining[index]
            if not overlaps(candidate, other):
                index += 1
                continue
            candidate = union(candidate, other)
            remaining[index] = remaining[-1]
            remaining.pop()
            index = 0
        merged.append(candidate)
    return merged


class JapaneseDetectorMergeClosureContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detector = read(
            "AITRANS/Services/ComicTextBubbleDetectorService.swift"
        )
        cls.vision = read("AITRANS/Services/VisionOCRService.swift")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read(
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
            )
            + read("update_log.md")
        )
        cls.merge = function_body(
            cls.detector,
            "private static func mergeTextRegions(\n",
        )

    def test_overlap_and_containment_thresholds_are_preserved(self) -> None:
        for marker in (
            "intersectionOverUnion(candidate.rect, other.rect) >= 0.50",
            "threshold: 0.30",
            "candidate.rect = candidate.rect.union(other.rect)",
            "candidate.confidence = max(candidate.confidence, other.confidence)",
            "swapRemove(at: index, from: &remaining)",
        ):
            self.assertIn(marker, self.merge)

    def test_scan_restarts_after_union_to_close_earlier_candidates(self) -> None:
        removal = self.merge.index("swapRemove(at: index")
        self.assertIn("index = 0", self.merge[removal:])
        self.assertGreaterEqual(self.merge.count("index = 0"), 2)

    def test_transitive_overlap_chain_no_longer_leaves_duplicate_regions(self) -> None:
        first = (0.00, 0.00, 0.40, 1.00)
        middle = (0.25, 0.00, 0.40, 1.00)
        last = (0.60, 0.00, 0.10, 1.00)
        self.assertTrue(overlaps(first, middle))
        self.assertTrue(overlaps(middle, last))
        self.assertFalse(overlaps(first, last))
        self.assertEqual(len(merge_once([first, middle, last])), 2)
        self.assertEqual(len(merge_to_closure([first, middle, last])), 1)

    def test_disjoint_regions_remain_disjoint(self) -> None:
        regions = [(0.00, 0.00, 0.10, 0.10), (0.80, 0.80, 0.10, 0.10)]
        self.assertEqual(merge_to_closure(regions), regions[::-1])

    def test_detector_primary_path_and_quality_boundaries_remain_in_place(self) -> None:
        for marker in (
            "Self.mergeTextRegions(Self.mergeSliceRegions(detections))",
            "prediction.score >= Self.confidenceThreshold",
            "Self.textLabelIDs.contains(prediction.labelID)",
            "configuration.computeUnits = .cpuOnly",
            "Task.checkCancellation()",
        ):
            self.assertIn(marker, self.detector)
        for marker in (
            "detector: .comicTextBubble",
            "regions.prefix(12)",
            "maximumJapaneseMangaLineOCRRequests = 8",
        ):
            self.assertIn(marker, self.vision)

    def test_no_new_budget_or_external_runtime_boundary_is_introduced(self) -> None:
        self.assertNotIn("groundTruth", self.detector + self.vision)
        contract = read(
            "scripts/test-v3338-image-japanese-detector-merge-closure-contract.py"
        )
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, contract)

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.347", "3.347"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3338-image-japanese-detector-merge-closure-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
