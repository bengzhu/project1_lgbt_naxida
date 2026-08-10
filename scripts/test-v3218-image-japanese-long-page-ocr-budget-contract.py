#!/usr/bin/env python3
"""Contract for slice-aware Manga OCR budgets on tall Japanese pages."""

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


class JapaneseLongPageOCRBudgetContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.detector = read(
            "AITRANS/Services/ComicTextBubbleDetectorService.swift"
        )
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )
        self.long_page = braced_body(
            self.vision,
            "private static func japaneseLongPageMangaOCRRegions(",
        )
        self.balance = braced_body(
            self.vision,
            "private static func verticallyBalancedJapaneseMangaOCRRegions(",
        )
        self.runtime = read(
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.harness = read(
            "scripts/fixtures/v3218-long-page-manga-ocr-runtime-harness.swift"
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_detector_exposes_the_same_slice_plan_used_for_inference(self) -> None:
        actor = braced_body(
            self.detector,
            "actor ComicTextBubbleDetectorService",
        )
        helper = braced_body(
            self.detector,
            "fileprivate static func inferenceWindowCount(",
        )
        self.assertIn("static func inferenceWindowCount(for image: CGImage)", actor)
        self.assertIn("ComicTextBubbleDetectorRuntime.inferenceWindowCount(", actor)
        self.assertIn(
            "detectorSlices(imageWidth: imageWidth, imageHeight: imageHeight).count",
            helper,
        )

    def test_standard_pages_keep_the_historical_twelve_request_boundary(self) -> None:
        for marker in [
            "let detectorSliceCount = ComicTextBubbleDetectorService.inferenceWindowCount(",
            "detectorSliceCount > 1",
            "Array(regions.prefix(12))",
            "let cropRegions = detectorSliceCount > 1 ? regions : selectedRegions",
            "let requests = selectedRegions.map",
            "among: cropRegions",
        ]:
            self.assertIn(marker, self.manga)

    def test_long_pages_scale_per_slice_with_a_responsiveness_cap(self) -> None:
        for marker in [
            "let requestsPerSlice = 12",
            "let maximumRequests = 48",
            "max(detectorSliceCount, 1) * requestsPerSlice",
            "let bandCount = min(max(detectorSliceCount, 1), requestLimit)",
        ]:
            self.assertIn(marker, self.long_page)
        self.assertNotIn("prefix(12)", self.long_page)

    def test_dedicated_regions_are_balanced_before_vision_supplements(self) -> None:
        self.assertLess(
            self.long_page.index("let primary = regions.filter"),
            self.long_page.index("let supplemental = regions.filter"),
        )
        self.assertIn("case .comicTextBubble", self.long_page)
        self.assertIn("case .vision", self.long_page)
        self.assertIn("let remaining = requestLimit - selected.count", self.long_page)

    def test_vertical_bands_receive_quota_before_confidence_overflow(self) -> None:
        for marker in [
            "region.rect.midY",
            "Int(normalizedCenter * Double(boundedBandCount))",
            "let baseQuota = limit / boundedBandCount",
            "let extraQuota = limit % boundedBandCount",
            "band.prefix(quota)",
            "band.dropFirst(quota)",
            "overflow.sort(by: isBetterJapaneseMangaOCRRegion)",
        ]:
            self.assertIn(marker, self.balance)

    def test_region_fusion_does_not_discard_long_page_candidates_early(self) -> None:
        combine = braced_body(
            self.vision,
            "private static func japaneseMangaOCRRegions(",
        )
        self.assertIn("return primary + supplemental", combine)
        self.assertNotIn("prefix(12)", combine)
        self.assertIn("Array(regions.prefix(12))", self.manga)
        self.assertIn("japaneseLongPageMangaOCRRegions(", self.manga)

    def test_version_runtime_and_ci_route_follow_v3217(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertEqual(len(set(versions)), 1)
        self.assertGreaterEqual(
            tuple(int(part) for part in versions[0].split(".")),
            (3, 218),
        )
        for marker in [
            "private static let sourceCopies = 4",
            "VisionOCRService().recognizeTextBlocks(",
            'print("blocks=\\(blocks.count)")',
        ]:
            self.assertIn(marker, self.harness)
        for marker in [
            "int(match.group(1)) < 16",
            "len(vertical_rects) < 16",
            '"direction=unknown" in text',
            "for quarter in range(4)",
            '"お願いします前は" in text',
            'sum("今度こそ" in value for value in vertical_texts) < 4',
            "trash \"$runtime_root\"",
        ]:
            self.assertIn(marker, self.runtime)
        self.assertNotIn("rm -rf", self.runtime)
        previous = (
            "bash "
            "scripts/test-v3217-image-japanese-comic-detector-slicer-runtime.sh"
        )
        contract = (
            "python3 -B "
            "scripts/test-v3218-image-japanese-long-page-ocr-budget-contract.py"
        )
        runtime = (
            "bash "
            "scripts/test-v3218-image-japanese-long-page-manga-ocr-runtime.sh"
        )
        self.assertIn(previous, self.workflow)
        self.assertIn(contract, self.workflow)
        self.assertIn(runtime, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(contract))
        self.assertLess(self.workflow.index(contract), self.workflow.index(runtime))
        self.assertIn(
            "if grep -Fx "
            "'scripts/test-v3218-image-japanese-long-page-ocr-budget-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
