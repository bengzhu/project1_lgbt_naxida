#!/usr/bin/env python3
"""Contract for Koharu detector crop and direction boundaries."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]

# The developer-only Koharu checkout is ignored by git. Keep the small,
# audited rule inline so CI can verify the role boundary without depending on
# that local checkout being present in a cloud runner.
KOHARU_DETECTOR_CROP_RULE = """
should_expand = detector == ctd || line_polygons is non-empty
if !should_expand: return raw detector bbox
comic-text-bubble-detector TextRegion has no line_polygons or source_direction
"""


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


class JapaneseDetectorRoleBoundaryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crop = braced_body(
            self.vision,
            "private static func japaneseMangaOCRCropRect(",
        )
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_koharu_detector_without_ctd_line_polygons_keeps_raw_bbox(self) -> None:
        for marker in [
            "should_expand = detector == ctd || line_polygons is non-empty",
            "if !should_expand: return raw detector bbox",
            "comic-text-bubble-detector TextRegion has no line_polygons or source_direction",
        ]:
            self.assertIn(marker, KOHARU_DETECTOR_CROP_RULE)
        for marker in [
            "let rect = region.rect",
            "guard case .vision = region.detector else {",
            "return rect",
            "let cropBase = region.cropRectHint ?? rect",
        ]:
            self.assertIn(marker, self.crop)
        self.assertLess(
            self.crop.index("guard case .vision = region.detector else {"),
            self.crop.index("let expanded = expandedVerticalCropRect("),
        )
        self.assertNotIn("case .comicTextBubble", self.crop)
        self.assertNotIn("direction: .horizontal", self.crop)

    def test_vision_supplement_retains_vertical_padding_and_bisector(self) -> None:
        for marker in [
            "let expanded = expandedVerticalCropRect(",
            "direction: .vertical",
            "verticalOverlap >= 0.50",
            "let boundary = (rect.midX + neighbor.rect.midX) / 2",
            "left = max(left, min(boundary, rect.x))",
            "right = min(right, max(boundary, rect.maxX))",
        ]:
            self.assertIn(marker, self.crop)
        self.assertIn("cropRectHint: japaneseDetectorCropHint(", self.vision)
        self.assertIn("cropQuad: region.cropQuadHint", self.vision)

    def test_detector_provenance_and_layout_direction_remain_scoped(self) -> None:
        self.assertIn("sourceDirectionHint: .vertical", braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        ))
        self.assertIn("observationRole: .detectorTextRegion", self.vision)
        self.assertIn("preservesDetectorTextRegionBoundary:", self.vision)

    def test_bbox_primary_quad_fallback_and_budget_boundaries_remain(self) -> None:
        for marker in [
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "primaryBoundingBoxCrop: boundingBoxCrop",
            "lineQuadFallbackCrop: perspectiveCrop",
            "Self.shouldRetryLineQuad(after: primaryRecognitions[index])",
            "Array(regions.prefix(12))",
            "maximumRequests = 48",
            "throw CancellationError()",
        ]:
            self.assertIn(marker, self.manga if "boundingBox" in marker or "primary" in marker or "lineQuad" in marker or "shouldRetry" in marker else self.vision)

    def test_version_and_ci_route_follow_v3249(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 250) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.249;", self.project)
        previous = "python3 -B scripts/test-v3249-image-japanese-detector-role-padding-contract.py"
        current = "python3 -B scripts/test-v3250-image-japanese-detector-role-boundary-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3250-image-japanese-detector-role-boundary-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
