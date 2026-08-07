#!/usr/bin/env python3
"""Contract for Vision character-range geometry in Japanese line-region OCR."""

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


class JapaneseLineGeometryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(self.vision, "private static func recognizeObservations(")
        region_marker = (
            "private static func recognizedTextGeometry("
            if "private static func recognizedTextGeometry(" in self.vision
            else "private static func recognizedTextRegionRect("
        )
        self.region = braced_body(self.vision, region_marker)
        self.usability = braced_body(self.vision, "private static func isUsableTextRegion(")
        self.line = braced_body(self.vision, "private static func recognizeJapaneseVerticalLineCrops(")
        self.crop_map = braced_body(self.vision, "private static func mapRotatedCropObservation(")
        self.full_map = braced_body(self.vision, "private static func mapRotatedObservation(")

    def test_recognition_captures_vision_character_range_geometry(self) -> None:
        self.assertIn("candidate.string.startIndex..<candidate.string.endIndex", self.recognize + self.region)
        self.assertTrue(
            "recognizedTextRegionRect(" in self.recognize + self.region
            or "recognizedTextGeometry(" in self.recognize + self.region
        )
        self.assertIn("lineRegionRect:", self.recognize + self.region)
        for marker in [
            "try candidate.boundingBox(for: range)",
            "rangeObservation.boundingBox",
            "isUsableTextRegion(rangeRect, relativeTo: fallback)",
        ]:
            self.assertIn(marker, self.region)
        self.assertTrue(
            "return fallback" in self.region
            or "return (rect: fallback" in self.region
        )

    def test_line_crops_prefer_geometry_without_replacing_layout_box(self) -> None:
        for marker in [
            "let region = observation.lineRegionRect ?? observation.rect",
        ]:
            self.assertIn(marker, self.vision)
        self.assertTrue(
            "let cropRect = expandedVerticalLineCropRect(for: candidate)" in self.vision
            or "let cropRect = expandedVerticalLineCropRect(for: candidate, imageSize:" in self.vision
        )
        self.assertIn("rect: originalRect", self.crop_map)
        self.assertIn("lineRegionRect: originalLineRegionRect", self.crop_map)

    def test_geometry_is_mapped_through_both_rotation_paths(self) -> None:
        for body in (self.crop_map, self.full_map):
            for marker in [
                "observation.lineRegionRect.map",
                "mapRotated",
                "lineRegionRect: originalLineRegionRect",
            ]:
                self.assertIn(marker, body)
        self.assertIn("mapRotatedCropRegionRect(", self.crop_map)
        self.assertIn("mapRotatedRegionRect(", self.full_map)

    def test_region_fallback_and_source_boundaries_remain_safe(self) -> None:
        for marker in [
            "overlapRatio(candidate, fallback) >= 0.45",
            "areaRatio >= 0.25",
            "areaRatio <= 1.25",
        ]:
            self.assertIn(marker, self.usability)
        for marker in [
            "catch {",
            "Vision may not provide character-range geometry",
        ]:
            self.assertIn(marker, self.region)
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_fixture_version_and_ci_route_follow_v3160(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 161) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.160;", self.project)
        old = "python3 -B scripts/test-v3160-image-japanese-line-region-ocr-contract.py"
        new = "python3 -B scripts/test-v3161-image-japanese-line-geometry-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("16[1]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
