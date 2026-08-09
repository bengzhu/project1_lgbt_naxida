#!/usr/bin/env python3
"""Contract for Koharu ImageSlicer semantics in the bundled comic detector."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def braced_body(source: str, marker: str) -> str:
    start = source.index(marker)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class JapaneseComicDetectorSlicerContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = read(
            "AITRANS/Services/ComicTextBubbleDetectorService.swift"
        )
        self.detector_runtime = self.detector[
            self.detector.index("private struct ComicTextBubbleDetectorRuntime") :
        ]
        self.detect = braced_body(
            self.detector_runtime,
            "func detectTextRegions(in image: CGImage)",
        )
        self.slices = braced_body(
            self.detector_runtime,
            "private static func detectorSlices(",
        )
        self.merge = braced_body(
            self.detector_runtime,
            "private static func mergeSliceRegions(",
        )
        self.runtime = read(
            "scripts/test-v3217-image-japanese-comic-detector-slicer-runtime.sh"
        )
        self.harness = read(
            "scripts/fixtures/v3217-comic-detector-slicer-runtime-harness.swift"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_slicer_constants_and_activation_match_koharu(self) -> None:
        for marker in [
            "private static let sliceAspectRatioThreshold = 3.5",
            "private static let sliceTargetAspectRatio = 3.0",
            "private static let sliceOverlapRatio = 0.20",
            "private static let minimumLastSliceRatio = 0.70",
            "guard pageAspectRatio > sliceAspectRatioThreshold",
            "Double(imageWidth) * sliceTargetAspectRatio",
            "Double(targetHeight) * (1 - sliceOverlapRatio)",
        ]:
            self.assertIn(marker, self.detector)

    def test_short_tail_is_folded_and_final_slice_reaches_bottom(self) -> None:
        for marker in [
            "Int(ceil(Double(imageHeight) / Double(effectiveHeight)))",
            "let lastStart = (sliceCount - 1) * effectiveHeight",
            "let lastHeight = max(imageHeight - lastStart, 0)",
            "Double(lastHeight) / Double(targetHeight) <= minimumLastSliceRatio",
            "sliceCount -= 1",
            "index + 1 == sliceCount",
            "? imageHeight - startY",
        ]:
            self.assertIn(marker, self.slices)

    def test_each_slice_runs_real_model_and_maps_back_to_full_page(self) -> None:
        for marker in [
            "for slice in slices",
            "try Task.checkCancellation()",
            "image.cropping(to: cropRect)",
            "try detectPredictions(in: sliceImage)",
            "Self.mapPredictionToFullImage(",
            "slice: slice",
            "imageHeight: image.height",
        ]:
            self.assertIn(marker, self.detect)
        mapping = braced_body(
            self.detector,
            "private static func mapPredictionToFullImage(",
        )
        for marker in [
            "Double(slice.startY) + prediction.rect.y * Double(slice.height)",
            "prediction.rect.height * Double(slice.height) / fullHeight",
            ").normalizedToUnit()",
        ]:
            self.assertIn(marker, mapping)

    def test_same_label_slice_merge_matches_koharu_order_and_thresholds(self) -> None:
        for marker in [
            "guard regions[index].labelID == regions[compare].labelID",
            "containmentRelation(first, second, threshold: 0.85)",
            "if regionIoU >= 0.50",
            "let yDistanceThreshold = 0.1",
            "max(firstHeight, secondHeight) * 0.1",
            "xOverlapRatio > 0.2",
            "sizeRatio > 0.3",
            "area(mergedRect) <= 3.0 * largestArea",
            "swapRemove(at: compare, from: &regions)",
        ]:
            self.assertIn(marker, self.merge)
        self.assertIn(
            "Self.mergeTextRegions(Self.mergeSliceRegions(detections))",
            self.detect,
        )

    def test_swap_remove_is_shared_with_final_text_region_merge(self) -> None:
        text_merge = braced_body(
            self.detector,
            "private static func mergeTextRegions(",
        )
        self.assertIn("swapRemove(at: index, from: &remaining)", text_merge)
        helper = braced_body(
            self.detector,
            "private static func swapRemove(",
        )
        self.assertIn("regions.swapAt(index, lastIndex)", helper)
        self.assertIn("regions.removeLast()", helper)

    def test_real_runtime_gates_four_page_vertical_coverage(self) -> None:
        for marker in [
            "private static let sourceCopies = 4",
            "ComicTextBubbleDetectorService.shared.detectTextRegions(",
            'print("regions=\\(regions.count)")',
        ]:
            self.assertIn(marker, self.harness)
        for marker in [
            "image=1136x6400",
            "not 16 <= int(match.group(1)) <= 18",
            "for quarter in range(4)",
            "< 4",
            "height > 0.30",
            "trash \"$runtime_root\"",
        ]:
            self.assertIn(marker, self.runtime)
        self.assertNotIn("rm -rf", self.runtime)

    def test_version_and_ci_route_follow_v3216(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertEqual(len(set(versions)), 1)
        self.assertGreaterEqual(
            tuple(int(part) for part in versions[0].split(".")),
            (3, 217),
        )
        previous = (
            "python3 -B "
            "scripts/test-v3216-image-japanese-comic-text-detector-contract.py"
        )
        current = (
            "python3 -B "
            "scripts/test-v3217-image-japanese-comic-detector-slicer-contract.py"
        )
        runtime = (
            "bash "
            "scripts/test-v3217-image-japanese-comic-detector-slicer-runtime.sh"
        )
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertLess(self.workflow.index(current), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx "
            "'scripts/test-v3217-image-japanese-comic-detector-slicer-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
