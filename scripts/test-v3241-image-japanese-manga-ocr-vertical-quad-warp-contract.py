#!/usr/bin/env python3
"""Contract for Koharu's bounded vertical line-quad warp in Manga OCR."""

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


class JapaneseMangaOCRVerticalQuadWarpContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.crop = braced_body(
            self.service,
            "private static func perspectiveCorrectedCrop(",
        )
        self.target = braced_body(
            self.service,
            "static func koharuVerticalQuadWarpTargetSize(",
        )

    def test_bbox_remains_primary_and_quad_remains_weak_fallback(self) -> None:
        for marker in [
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "let perspectiveCrop = request.cropQuad.flatMap",
            "cropQuadIsVertical: Bool = false",
            "primaryBoundingBoxCrop: boundingBoxCrop",
            "lineQuadFallbackCrop: perspectiveCrop",
            "chunk.map(\\.primaryBoundingBoxCrop)",
            "Self.shouldRetryLineQuad(after: primaryRecognitions[index])",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn(
            "guard let perspectiveCrop else { return nil }",
            self.service,
        )

    def test_vertical_quad_uses_koharu_axis_target_and_rotation(self) -> None:
        for marker in [
            "if applyVerticalWarp,",
            "let targetSize = koharuVerticalQuadWarpTargetSize(",
            "maximumDimension: CGFloat(maximumQuadWarpDimension)",
            "maximumPixels: maximumQuadWarpPixels",
            "let targetWidth = Int(targetSize.width.rounded())",
            "let targetHeight = Int(targetSize.height.rounded())",
            "let bounded = koharuVerticalQuadWarp(",
            "sourcePoints: localPoints",
            "let rotated = rotateImage270(bounded)",
            "return rotated",
        ]:
            self.assertIn(marker, self.crop)
        self.assertIn("applyVerticalWarp: request.cropQuadIsVertical", self.service)
        self.assertLess(
            self.crop.index("koharuVerticalQuadWarpTargetSize("),
            self.crop.index("rotateImage270(bounded)"),
        )

    def test_target_matches_quad_axis_lengths_and_is_bounded(self) -> None:
        for marker in [
            "let top = midpoint(points[0], points[1])",
            "let right = midpoint(points[1], points[2])",
            "let bottom = midpoint(points[2], points[3])",
            "let left = midpoint(points[3], points[0])",
            "let verticalLength = distance(top, bottom)",
            "let horizontalLength = distance(left, right)",
            "let textHeight = max(horizontalLength.rounded(), 1)",
            "let ratio = verticalLength / horizontalLength",
            "let rawWidth = textHeight",
            "let rawHeight = max((textHeight * ratio).rounded(), 1)",
            "maximumDimension / rawWidth",
            "maximumDimension / rawHeight",
            "sqrt(maximumPixels / (rawWidth * rawHeight))",
            "width * height <= maximumPixels + 1",
        ]:
            self.assertIn(marker, self.target)

    def test_projection_target_and_rotation_failures_keep_natural_warp(self) -> None:
        self.assertIn("guard let rendered = context.createCGImage", self.crop)
        self.assertIn("return rendered", self.crop)
        self.assertIn("let bounded = koharuVerticalQuadWarp(", self.crop)
        self.assertIn(
            "compatibility fallback",
            self.crop,
        )
        self.assertIn("private static func rotateImage270", self.service)
        self.assertIn("context.rotate(by: -.pi / 2)", self.service)

    def test_quad_path_is_strict_vertical_geometry_only(self) -> None:
        self.assertIn(
            "cropQuadHint: japaneseDetectorCropQuadHint(",
            self.vision,
        )
        self.assertIn(
            "cropQuadIsVertical: region.cropQuadHint != nil",
            self.vision,
        )
        self.assertIn(
            "isJapanesePixelFirstVerticalCandidate(envelope)",
            self.vision,
        )
        self.assertIn(
            "return quad",
            braced_body(
                self.vision,
                "private static func japanesePixelDetectorCharacterQuad(",
            ),
        )

    def test_version_and_ci_route_follow_v3240(self) -> None:
        previous = (
            "python3 -B scripts/test-v3240-image-japanese-detector-bbox-crop-contract.py"
        )
        current = (
            "python3 -B scripts/test-v3241-image-japanese-manga-ocr-vertical-quad-warp-contract.py"
        )
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3241-image-japanese-manga-ocr-vertical-quad-warp-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 241) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.240;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
