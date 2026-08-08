#!/usr/bin/env python3
"""Contract for preserving Koharu's rotate270 preference through Japanese line fusion."""

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


class JapaneseKoharuLineOrientationProvenanceContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.recognize = braced_body(
            self.vision,
            "private static func recognizeObservations(",
        )
        self.crop_pass = braced_body(
            self.vision,
            "private static func recognizeJapaneseCropPass(",
        )
        self.line_crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.perspective = braced_body(
            self.vision,
            "private static func recognizeJapanesePerspectiveLineCrop(",
        )
        self.mapping = braced_body(
            self.vision,
            "private static func mapRotatedCropObservation(",
        )
        self.score = braced_body(
            self.vision,
            "private static func isBetterObservation(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_line_role_survives_vision_and_crop_mapping(self) -> None:
        for marker in [
            "private enum VisionOCRObservationRole: Equatable, Sendable",
            "case verticalLine",
            "var observationRole: VisionOCRObservationRole = .page",
            "observationRole: VisionOCRObservationRole = .page",
            "observationRole: observationRole",
            "observationRole: observation.observationRole",
        ]:
            self.assertIn(marker, self.vision)
        self.assertIn("observationRole: VisionOCRObservationRole = .crop", self.vision)
        self.assertIn("observationRole: observationRole", self.crop_pass + self.recognize)
        self.assertIn("observationRole: observation.observationRole", self.mapping)

    def test_koharu_vertical_line_paths_mark_both_primary_and_fallback(self) -> None:
        self.assertGreaterEqual(self.line_crops.count("observationRole: .verticalLine"), 2)
        self.assertIn("observationRole: .verticalLine", self.perspective)
        self.assertIn("observationRole: .verticalLine", self.vision)
        self.assertIn("let angle = koharuPreferredJapaneseVerticalLineOrientation()", self.line_crops)
        self.assertIn("oppositeJapaneseOrientation(angle)", self.line_crops)

    def test_role_aware_score_and_tie_breaker_prefer_rotate270_only_for_lines(self) -> None:
        for marker in [
            "preferredJapaneseRotation(for: lhs)",
            "preferredJapaneseRotation(for: rhs)",
            "observation.observationRole == .verticalLine ? 270 : 90",
            "if prefersJapanese, observation.observationRole == .verticalLine",
            "rotationBonus = observation.rotationApplied == 270 ? 0.15 : 0",
        ]:
            self.assertIn(marker, self.score + self.vision)
        self.assertIn("return lhs.rotationApplied == 90", self.score)

    def test_block_and_tile_orientation_boundaries_remain_unchanged(self) -> None:
        block = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        tiles = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.assertIn("$0.rotationApplied == 270 ? 270 : 90", block)
        self.assertIn("angle: 90", tiles)
        self.assertIn("angle: 270", tiles)
        self.assertNotIn("observationRole: .verticalLine", block)
        self.assertNotIn("observationRole: .verticalLine", tiles)

    def test_scope_stays_in_ordinary_japanese_line_fusion(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3200(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 201) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.200;", self.project)
        old = "python3 -B scripts/test-v3200-image-japanese-koharu-font-anchor-contract.py"
        new = "python3 -B scripts/test-v3201-image-japanese-koharu-line-orientation-provenance-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
