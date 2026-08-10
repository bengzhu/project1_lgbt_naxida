#!/usr/bin/env python3
"""Contract for preserving full-line coverage in the Koharu quad hint."""

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


class JapaneseLineQuadCoverageContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/VisionOCRService.swift")
        self.manga = read("AITRANS/Services/MangaOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.quad = braced_body(
            self.service,
            "private static func japanesePixelDetectorCharacterQuad(",
        )

    def test_quad_aggregates_outer_edges_in_rotated_space(self) -> None:
        for marker in [
            "let rotatedCharacterQuads",
            "let allPoints = rotatedCharacterQuads.flatMap(\\.points)",
            "let minX = allPoints.map(\\.x).min()",
            "let maxX = allPoints.map(\\.x).max()",
            "let minY = allPoints.map(\\.y).min()",
            "let maxY = allPoints.map(\\.y).max()",
            "let rotatedLineQuad = ImageOCRLayoutQuad(points:",
            "let normalizedRotatedLineQuad = rotatedLineQuad.normalized()",
            "mapRotatedRegionQuad(",
        ]:
            self.assertIn(marker, self.quad)
        self.assertNotIn("median(characterQuads", self.quad)
        self.assertNotIn("median(rotatedCharacterQuads", self.quad)

    def test_full_line_geometry_keeps_strict_safety_gates(self) -> None:
        for marker in [
            "rotatedCharacterQuads.count >= 2",
            "overlapRatio(fallback, quadRect) >= 0.80",
            "overlapRatio(candidateRect, quadRect) >= 0.80",
            "detectorCoverage >= 0.55",
            "quadCoverage >= 0.80",
            "areaRatio >= 0.35",
            "areaRatio <= 1.05",
            "verticalCoverage / max(fallback.height, 0.001) >= 0.85",
            "quadRect.width < fallback.width * 0.90",
        ]:
            self.assertIn(marker, self.quad)

    def test_invalid_quad_still_falls_back_to_bbox_crop(self) -> None:
        for marker in [
            "cropQuad: region.cropQuadHint",
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            "let perspectiveCrop = request.cropQuad.flatMap",
            "guard let perspectiveCrop else { return nil }",
            "lineQuadFallbackCrop: nil",
            "CIPerspectiveCorrection",
        ]:
            self.assertIn(marker, self.service + self.manga)

    def test_version_and_ci_route_follow_v3232(self) -> None:
        previous = "python3 -B scripts/test-v3232-image-japanese-koharu-line-quad-manga-ocr-contract.py"
        current = "python3 -B scripts/test-v3233-image-japanese-line-quad-coverage-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3233-image-japanese-line-quad-coverage-contract.py'",
            self.workflow,
        )
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 233) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.232;", self.project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
