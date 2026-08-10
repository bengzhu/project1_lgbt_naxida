#!/usr/bin/env python3
"""Contract for keeping detector bboxes primary in the product OCR request path."""

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


class JapaneseDetectorBBoxCropContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.crop = braced_body(
            self.vision,
            "private static func japaneseMangaOCRCropRect(",
        )
        self.request_path = braced_body(
            self.vision,
            "private static func recognizeJapaneseMangaOCR(",
        )

    def test_detector_bbox_is_selected_before_padding(self) -> None:
        for marker in [
            "let rect = region.rect",
            "let cropBase: ImageOCRLayoutRect",
            "if case .vision = region.detector",
            "cropBase = region.cropRectHint ?? rect",
            "cropBase = rect",
            "expandedVerticalLineCropRect(\n            cropBase,",
            "guard case .vision = region.detector else {",
            "return expanded",
        ]:
            self.assertIn(marker, self.crop)
        self.assertNotIn(
            "expandedVerticalLineCropRect(\n            region.cropRectHint ?? rect,",
            self.crop,
        )
        self.assertLess(
            self.crop.index("cropBase = rect"),
            self.crop.index("expandedVerticalLineCropRect(\n            cropBase,"),
        )

    def test_vision_hint_remains_supplement_only(self) -> None:
        self.assertIn("cropBase = region.cropRectHint ?? rect", self.crop)
        self.assertLess(
            self.crop.index("if case .vision = region.detector"),
            self.crop.index("guard case .vision = region.detector else {"),
        )
        self.assertIn("cropRectHint: japaneseDetectorCropHint(", self.vision)
        self.assertIn("textRect: region.rect", self.request_path)
        self.assertIn("cropRect: japaneseMangaOCRCropRect(", self.request_path)
        self.assertIn("cropQuad: region.cropQuadHint", self.request_path)

    def test_manga_service_keeps_bbox_primary_and_quad_fallback(self) -> None:
        for marker in [
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "let perspectiveCrop = request.cropQuad.flatMap",
            "primaryBoundingBoxCrop: boundingBoxCrop",
            "lineQuadFallbackCrop: perspectiveCrop",
            "chunk.map(\\.primaryBoundingBoxCrop)",
            "Self.shouldRetryLineQuad(after: primaryRecognitions[index])",
        ]:
            self.assertIn(marker, self.manga)
        self.assertIn("CIPerspectiveCorrection", self.manga)

    def test_detector_geometry_and_ci_route_are_versioned(self) -> None:
        self.assertIn("rect: detectorRegion.rect", self.vision)
        previous = (
            "python3 -B scripts/test-v3239-image-japanese-manga-ocr-bbox-primary-contract.py"
        )
        current = (
            "python3 -B scripts/test-v3240-image-japanese-detector-bbox-crop-contract.py"
        )
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3240-image-japanese-detector-bbox-crop-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 240) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.239;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
