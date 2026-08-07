#!/usr/bin/env python3
"""Contract for Koharu-style perspective correction of Japanese line crops."""

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


class JapaneseLinePerspectiveOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(self.vision, "private static func recognizeObservations(")
        self.geometry = braced_body(self.vision, "private static func recognizedTextGeometry(")
        self.quad = braced_body(self.vision, "private static func normalizedQuad(")
        self.lines = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.perspective = braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )
        self.warp = braced_body(
            self.vision,
            "private static func perspectiveCorrectedLineImage(",
        )
        self.crop_map = braced_body(self.vision, "private static func mapRotatedCropObservation(")
        self.full_map = braced_body(self.vision, "private static func mapRotatedObservation(")

    def test_vision_range_geometry_keeps_quad_and_layout_box_separate(self) -> None:
        for marker in [
            "try candidate.boundingBox(for: range)",
            "rangeObservation.boundingBox",
            "normalizedQuad(from: rangeObservation)",
            "lineRegionRect: geometry.rect",
            "lineRegionQuad: geometry.quad",
        ]:
            self.assertIn(marker, self.recognize + self.geometry)
        for marker in [
            "observation.topLeft",
            "observation.topRight",
            "observation.bottomRight",
            "observation.bottomLeft",
            "quad.minimumEdgeLength",
            "quad.isConvex",
        ]:
            self.assertIn(marker, self.quad)

    def test_perspective_path_is_bounded_and_only_adds_a_line_hint(self) -> None:
        for marker in [
            "recognizeJapanesePerspectiveLineCrop(",
            "consumedPixels: &perspectiveWarpPixels",
            ".prefix(24)",
            "lineRegionQuad",
            "rect: candidate.rect",
            "lineRegionRect: candidate.lineRegionRect",
        ]:
            self.assertIn(marker, self.lines + self.perspective)
        self.assertTrue(
            "pixels <= 4_000_000" in self.perspective
            or "warpedPixels <= 4_000_000" in self.perspective
        )
        self.assertTrue(
            "consumedPixels + pixels <= 16_000_000" in self.perspective
            or "consumedPixels + preparedPixels <= 16_000_000" in self.perspective
        )
        self.assertTrue(
            "resizedImage(warped, scale: 2)" in self.perspective
            or "prepareJapaneseCropForVision(warped)" in self.perspective
        )
        for marker in [
            "minimumTextHeight: 0.002",
            "automaticallyDetectsLanguage: false",
        ]:
            self.assertIn(marker, self.perspective)

    def test_warp_uses_koharu_perspective_correction_and_safe_fallback(self) -> None:
        for marker in [
            "CIPerspectiveCorrection",
            'forKey: "inputTopLeft"',
            'forKey: "inputTopRight"',
            'forKey: "inputBottomRight"',
            'forKey: "inputBottomLeft"',
            "context.createCGImage(output, from: outputExtent)",
            "return nil",
        ]:
            self.assertIn(marker, self.warp)
        self.assertIn("guard let quad = candidate.lineRegionQuad", self.perspective)
        self.assertIn("let cropRect = expandedVerticalLineCropRect(for: candidate)", self.lines)

    def test_quad_geometry_survives_both_rotation_mapping_paths(self) -> None:
        for body in (self.crop_map, self.full_map):
            for marker in [
                "observation.lineRegionQuad.map",
                "lineRegionQuad: originalLineRegionQuad",
            ]:
                self.assertIn(marker, body)
        self.assertIn("mapRotatedCropRegionQuad(", self.crop_map)
        self.assertIn("mapRotatedRegionQuad(", self.full_map)

    def test_source_boundaries_and_fixture_remain_safe(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3161(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 162) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.161;", self.project)
        old = "python3 -B scripts/test-v3161-image-japanese-line-geometry-contract.py"
        new = "python3 -B scripts/test-v3162-image-japanese-line-perspective-ocr-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("16[2]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
