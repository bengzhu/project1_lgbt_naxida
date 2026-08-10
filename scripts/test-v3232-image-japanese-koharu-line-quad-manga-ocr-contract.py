#!/usr/bin/env python3
"""Contract for forwarding safe Koharu line geometry into Manga OCR crops."""

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


class JapaneseKoharuLineQuadMangaOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime = read("scripts/test-v3214-image-japanese-manga-ocr-runtime.sh")
        # The Koharu checkout is intentionally ignored and is not available in
        # CI. Use the tracked product line-polygon implementation as the local
        # contract oracle instead of making a clean checkout depend on it.
        self.line_warp = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.regions = braced_body(
            self.vision,
            "private static func japaneseMangaOCRRegions(",
        )
        self.quad = braced_body(
            self.vision,
            "private static func japanesePixelDetectorCharacterQuad(",
        )
        self.crop = braced_body(
            self.manga,
            "private static func perspectiveCorrectedCrop(",
        )

    def test_product_line_polygon_warp_precedes_ocr(self) -> None:
        for marker in [
            "recognizeLinePolygonWarpedText",
            "linePolygons",
            "orderedLinePolygonCorners",
            "CIPerspectiveCorrection",
            "preprocessedImage",
            "recognizeTextCandidates",
        ]:
            self.assertIn(marker, self.line_warp)

    def test_detector_quad_is_strict_and_recognition_only(self) -> None:
        self.assertIn("candidateRect: mappedRect", self.vision)
        for marker in [
            "mapRotatedRegionQuad(",
            "overlapRatio(fallback, quadRect) >= 0.80",
            "overlapRatio(candidateRect, quadRect) >= 0.80",
            "detectorCoverage >= 0.55",
            "quadCoverage >= 0.80",
            "areaRatio >= 0.35",
            "areaRatio <= 1.05",
            "quadRect.width < fallback.width * 0.90",
        ]:
            self.assertIn(marker, self.quad)
        self.assertTrue(
            "ImageOCRLayoutQuad(points: points).normalized()" in self.quad
            or "let rotatedLineQuad = ImageOCRLayoutQuad(points:" in self.quad
        )
        self.assertTrue(
            "characterQuads.count >= 2" in self.quad
            or "rotatedCharacterQuads.count >= 2" in self.quad
        )
        self.assertIn("cropQuadHint: mappedQuad", self.vision)
        self.assertIn("var cropQuadHint: ImageOCRLayoutQuad? = nil", self.vision)
        self.assertIn("textRect: region.rect", self.vision)

    def test_quad_flows_into_request_with_bbox_fallback(self) -> None:
        for marker in [
            "cropQuad: region.cropQuadHint",
            "var cropQuad: ImageOCRLayoutQuad?",
            "Self.cropImage(image, request: request)",
            "return cropImage(image, normalizedRect: request.cropRect)",
            "CIPerspectiveCorrection",
            "guard let normalizedQuad = quad.normalized()",
        ]:
            self.assertIn(marker, self.vision + self.manga)
        self.assertIn("import CoreImage", self.manga)

    def test_runtime_keeps_existing_model_and_cancellation_boundaries(self) -> None:
        for marker in [
            "MangaOCREncoderINT8",
            "ComicTextBubbleDetectorINT8",
            "MangaOCRService.swift",
        ]:
            self.assertIn(marker, self.runtime)
        self.assertIn("catch is CancellationError", self.vision)
        self.assertIn("throw CancellationError()", self.vision)
        self.assertIn("sourceLanguage == .japanese", self.vision)

    def test_ci_route_and_version_follow_v3231(self) -> None:
        previous = "python3 -B scripts/test-v3231-image-japanese-detector-tight-crop-hint-contract.py"
        current = "python3 -B scripts/test-v3232-image-japanese-koharu-line-quad-manga-ocr-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3232-image-japanese-koharu-line-quad-manga-ocr-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 232) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.231;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
