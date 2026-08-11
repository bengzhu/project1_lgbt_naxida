#!/usr/bin/env python3
"""Contract for Koharu role-aware padding on Japanese Manga OCR crops."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]

# The developer-only Koharu checkout is intentionally ignored by git. Keep
# the small upstream rule excerpt inline so this CI contract remains hermetic
# while still checking the exact source-direction default and pad fractions.
KOHARU_SOURCE_DIRECTION_PADDING_RULE = """
source_direction.unwrap_or(TextDirection::Horizontal)
TextDirection::Horizontal => ((font * 0.12).max(base_pad), (font * 0.18).max(base_pad))
TextDirection::Vertical => ((font * 0.18).max(base_pad), (font * 0.12).max(base_pad))
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


class JapaneseDetectorRolePaddingContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crop = braced_body(
            self.vision,
            "private static func japaneseMangaOCRCropRect(",
        )
        self.expanded = braced_body(
            self.vision,
            "private static func expandedVerticalCropRect(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_detector_and_vision_roles_select_koharu_direction_defaults(self) -> None:
        for marker in [
            "guard case .vision = region.detector else {",
            "return rect",
            "let cropBase = region.cropRectHint ?? rect",
            "direction: .vertical",
        ]:
            self.assertIn(marker, self.crop)

    def test_role_mapping_matches_koharu_missing_direction_default(self) -> None:
        for marker in [
            "source_direction.unwrap_or(TextDirection::Horizontal)",
            "TextDirection::Horizontal => ((font * 0.12).max(base_pad), (font * 0.18).max(base_pad))",
            "TextDirection::Vertical => ((font * 0.18).max(base_pad), (font * 0.12).max(base_pad))",
        ]:
            self.assertIn(marker, KOHARU_SOURCE_DIRECTION_PADDING_RULE)
        self.assertIn("guard case .vision = region.detector else {", self.crop)
        self.assertIn("return rect", self.crop)

    def test_detector_ownership_bbox_and_vision_hint_boundaries_remain_separate(self) -> None:
        for marker in [
            "guard case .vision = region.detector else {",
            "let cropBase = region.cropRectHint ?? rect",
            "return rect",
            "guard case .vision = region.detector else",
            "let boundary = (rect.midX + neighbor.rect.midX) / 2",
            "return ImageOCRLayoutRect(\n            x: left,",
        ]:
            self.assertIn(marker, self.crop)

    def test_directional_padding_helper_keeps_pixel_and_normalized_fallbacks(self) -> None:
        self.assertIn(
            "direction: ImageTextDirection = .vertical",
            self.vision,
        )
        for marker in [
            "koharuVerticalCropPadding(rect, imageSize: $0, direction: direction)",
            "let horizontalFraction = direction == .horizontal ? 0.12 : 0.18",
            "let verticalFraction = direction == .horizontal ? 0.18 : 0.12",
            "rect.width * horizontalFraction",
            "rect.height * verticalFraction",
            ".normalizedToUnit() ?? rect",
        ]:
            self.assertIn(marker, self.expanded)

    def test_detector_role_does_not_change_provenance_or_request_budget(self) -> None:
        for marker in [
            "sourceDirectionHint: .vertical",
            "observationRole: .detectorTextRegion",
            "cropQuadIsVertical: region.cropQuadHint != nil",
            "Array(regions.prefix(12))",
            "detectorSliceCount > 1",
            "throw CancellationError()",
        ]:
            self.assertIn(marker, self.vision)

    def test_version_and_ci_route_follow_v3248(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 249) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.248;", self.project)
        previous = "python3 -B scripts/test-v3248-image-ocr-rerecognition-failure-focus-contract.py"
        current = "python3 -B scripts/test-v3249-image-japanese-detector-role-padding-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3249-image-japanese-detector-role-padding-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
