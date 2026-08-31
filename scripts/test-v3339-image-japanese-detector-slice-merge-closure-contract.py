#!/usr/bin/env python3
"""Static and pure-policy contract for v3.346 slice merge closure."""

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
Region = tuple[int, Rect, float]


def area(rect: Rect) -> float:
    return max(rect[2], 0.0) * max(rect[3], 0.0)


def intersection_area(lhs: Rect, rhs: Rect) -> float:
    width = max(
        0.0,
        min(lhs[0] + lhs[2], rhs[0] + rhs[2]) - max(lhs[0], rhs[0]),
    )
    height = max(
        0.0,
        min(lhs[1] + lhs[3], rhs[1] + rhs[3]) - max(lhs[1], rhs[1]),
    )
    return width * height


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


def containment_relation(
    first: Rect, second: Rect, threshold: float = 0.85
) -> tuple[bool, bool]:
    first_area = area(first)
    second_area = area(second)
    if first_area <= 0 or second_area <= 0:
        return False, False
    ratio = intersection_area(first, second) / min(first_area, second_area)
    if ratio < threshold:
        return False, False
    return True, first_area >= second_area


def merge_rect(first: Rect, second: Rect) -> Rect | None:
    contained, first_contains_second = containment_relation(first, second)
    if contained:
        return first if first_contains_second else second

    first_area = area(first)
    second_area = area(second)
    if iou(first, second) >= 0.50:
        return first if first_area >= second_area else second

    first_width = max(first[2], 0.000_001)
    first_height = max(first[3], 0.000_001)
    second_width = max(second[2], 0.000_001)
    second_height = max(second[3], 0.000_001)
    y_distance = min(
        abs(first[1] - (second[1] + second[3])),
        abs((first[1] + first[3]) - second[1]),
    )
    local_y_threshold = min(0.1, max(first_height, second_height) * 0.1)
    x_overlap = max(
        min(first[0] + first_width, second[0] + second_width)
        - max(first[0], second[0]),
        0.0,
    )
    x_overlap_ratio = x_overlap / min(first_width, second_width)
    largest_area = max(first_area, second_area)
    size_ratio = min(first_area, second_area) / largest_area if largest_area > 0 else 0.0
    if (
        y_distance < local_y_threshold
        and x_overlap_ratio > 0.2
        and size_ratio > 0.3
        and abs(first[0] - second[0]) < 0.5 * max(first_width, second_width)
        and abs((first[0] + first_width) - (second[0] + second_width))
        < 0.5 * max(first_width, second_width)
    ):
        merged = union(first, second)
        if area(merged) <= 3.0 * largest_area:
            return merged
    return None


def merge_slice_once(regions: list[Region]) -> list[Region]:
    """Model the pre-v3.346 scan, including swap-remove ordering."""
    remaining = list(regions)
    index = 0
    while index < len(remaining):
        compare = index + 1
        while compare < len(remaining):
            label, first, confidence = remaining[index]
            other_label, second, other_confidence = remaining[compare]
            if label != other_label:
                compare += 1
                continue
            merged = merge_rect(first, second)
            if merged is None:
                compare += 1
                continue
            remaining[index] = (
                label,
                merged,
                max(confidence, other_confidence),
            )
            remaining[compare] = remaining[-1]
            remaining.pop()
            # The old implementation continued at the post-removal compare
            # index and never revisited a candidate skipped before expansion.
            continue
        index += 1
    return remaining


def merge_slice_to_closure(regions: list[Region]) -> list[Region]:
    """Model v3.346's restart-after-merge closure."""
    remaining = list(regions)
    index = 0
    while index < len(remaining):
        compare = index + 1
        did_merge = False
        while compare < len(remaining):
            label, first, confidence = remaining[index]
            other_label, second, other_confidence = remaining[compare]
            if label != other_label:
                compare += 1
                continue
            merged = merge_rect(first, second)
            if merged is None:
                compare += 1
                continue
            remaining[index] = (
                label,
                merged,
                max(confidence, other_confidence),
            )
            remaining[compare] = remaining[-1]
            remaining.pop()
            did_merge = True
            break
        if did_merge:
            index = 0
            continue
        index += 1
    return remaining


class JapaneseDetectorSliceMergeClosureContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.detector = read(
            "AITRANS/Services/ComicTextBubbleDetectorService.swift"
        )
        cls.merge = function_body(
            cls.detector,
            "private static func mergeSliceRegions(\n",
        )
        cls.workflow = read(".github/workflows/ci-results.yml")
        cls.project = read("AITRANS.xcodeproj/project.pbxproj")
        cls.docs = (
            read("md/flow/flow.md")
            + read("md/flow/flowchart.md")
            + read("md/test/test.md")
            + read(
                "md/ultra分析/v3.279-AITRANS与Koharu-OCR翻译差距及优化路线.md"
            )
            + read("update_log.md")
        )

    def test_existing_slice_merge_thresholds_and_confidence_policy_remain(self) -> None:
        for marker in (
            "containmentRelation(first, second, threshold: 0.85)",
            "if regionIoU >= 0.50",
            "let yDistanceThreshold = 0.1",
            "max(firstHeight, secondHeight) * 0.1",
            "xOverlapRatio > 0.2",
            "sizeRatio > 0.3",
            "area(mergedRect) <= 3.0 * largestArea",
            "regions[index].confidence = max(",
            "swapRemove(at: compare, from: &regions)",
        ):
            self.assertIn(marker, self.merge)

    def test_successful_merge_restarts_complete_slice_scan(self) -> None:
        for marker in (
            "var didMerge = false",
            "didMerge = true",
            "break",
            "if didMerge",
            "index = 0",
        ):
            self.assertIn(marker, self.merge)
        self.assertLess(
            self.merge.index("didMerge = true"),
            self.merge.index("if didMerge"),
        )

    def test_adjacent_transitive_slice_chain_no_longer_leaves_duplicate_regions(self) -> None:
        first = (0.10, 0.00, 0.20, 0.10)
        skipped = (0.10, 0.22, 0.20, 0.10)
        bridge = (0.10, 0.105, 0.20, 0.10)
        regions = [
            (7, first, 0.70),
            (7, skipped, 0.80),
            (7, bridge, 0.90),
        ]
        self.assertIsNone(merge_rect(first, skipped))
        self.assertIsNotNone(merge_rect(first, bridge))
        expanded = merge_rect(first, bridge)
        assert expanded is not None
        self.assertIsNotNone(merge_rect(expanded, skipped))
        self.assertEqual(len(merge_slice_once(regions)), 2)
        closed = merge_slice_to_closure(regions)
        self.assertEqual(len(closed), 1)
        self.assertEqual(closed[0][0], 7)
        self.assertEqual(closed[0][2], 0.90)

    def test_different_labels_and_disjoint_regions_remain_separate(self) -> None:
        same_rect = (0.10, 0.10, 0.20, 0.20)
        different_labels = [(1, same_rect, 0.8), (2, same_rect, 0.9)]
        disjoint = [
            (1, (0.00, 0.00, 0.10, 0.10), 0.8),
            (1, (0.80, 0.80, 0.10, 0.10), 0.9),
        ]
        self.assertEqual(len(merge_slice_to_closure(different_labels)), 2)
        self.assertEqual(merge_slice_to_closure(disjoint), disjoint)

    def test_pipeline_and_downstream_budget_boundaries_remain(self) -> None:
        for marker in (
            "Self.mergeTextRegions(Self.mergeSliceRegions(detections))",
            "prediction.score >= Self.confidenceThreshold",
            "Self.textLabelIDs.contains(prediction.labelID)",
            "Task.checkCancellation()",
        ):
            self.assertIn(marker, self.detector)
        vision = read("AITRANS/Services/VisionOCRService.swift")
        for marker in (
            "regions.prefix(12)",
            "maximumJapaneseMangaLineOCRRequests = 8",
            "maximumJapaneseWeakBlockRecoveryRequests = 4",
        ):
            self.assertIn(marker, vision)
        self.assertNotIn("groundTruth", self.detector + vision)

    def test_contract_stays_static_only(self) -> None:
        for marker in ("sub" + "process", "Po" + "pen", "os." + "system"):
            self.assertNotIn(marker, read(
                "scripts/test-v3339-image-japanese-detector-slice-merge-closure-contract.py"
            ))

    def test_version_workflow_and_docs_are_current(self) -> None:
        self.assertEqual(
            re.findall(r"MARKETING_VERSION = ([^;]+);", self.project),
            ["3.377", "3.377"],
        )
        combined = self.workflow + self.docs
        for marker in (
            "scripts/test-v3339-image-japanese-detector-slice-merge-closure-contract.py",
            "v3.347",
            "japanese-benchmark-v3.347-",
        ):
            self.assertIn(marker, combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
