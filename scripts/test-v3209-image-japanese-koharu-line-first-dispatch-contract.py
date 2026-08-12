#!/usr/bin/env python3
"""Contract for line-first Japanese dispatch and uncovered fallback ownership."""

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


class JapaneseKoharuLineFirstDispatchContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.crops = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.detector = braced_body(
            self.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(",
        )
        self.pixel = braced_body(
            self.vision,
            "private static func recognizeJapanesePixelFirstVerticalCrops(",
        )
        self.tile = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalTileFallback(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_line_path_precedes_detector_tile_and_block_fallback(self) -> None:
        line_match = re.search(
            r"let lineRefined = (?:try await )?Self\.recognizeJapaneseVerticalLineCrops\(",
            self.crops,
        )
        self.assertIsNotNone(line_match)
        line_call = line_match.start()
        detector_call = self.crops.index(
            "Self.recognizeJapanesePixelFirstVerticalCrops("
        )
        tile_call = self.crops.index(
            "Self.recognizeJapaneseVerticalTileFallback("
        )
        block_loop = self.crops.index("for block in verticalBlocks")
        block_crop = self.crops.index(
            "let primary = recognizeJapaneseCropPass(", block_loop
        )
        self.assertLess(line_call, detector_call)
        self.assertLess(detector_call, tile_call)
        self.assertLess(tile_call, block_crop)
        self.assertIn("refined.append(contentsOf: lineRefined)", self.crops)

    def test_detector_and_tile_receive_line_coverage_frontier(self) -> None:
        self.assertIn("lineObservations: lineRefined", self.crops)
        self.assertIn("lineObservations: [VisionOCRObservation]", self.vision)
        self.assertIn("japaneseLinePathRegion", self.detector)
        self.assertIn("overlapRatio($0, mappedRect) >= 0.60", self.detector)
        self.assertIn("japaneseLinePathRegion", self.tile)
        self.assertIn("overlapRatio($0, tileRect) >= 0.60", self.tile)

    def test_pixel_detector_keeps_vertical_line_provenance(self) -> None:
        self.assertIn("observationRole: .verticalLine", self.pixel)
        self.assertNotIn("observationRole: .crop", self.pixel)
        self.assertIn("private enum VisionOCRObservationRole", self.vision)
        self.assertIn("case verticalLine", self.vision)

    def test_only_reliable_line_results_suppress_broader_recovery(self) -> None:
        helper = braced_body(self.vision, "private static func japaneseLinePathRegion(")
        for marker in [
            "observationRole == .verticalLine",
            "confidence >= 0.48",
            "japaneseScriptDensity(in: text) >= 0.5",
            "lineRegionRect?.normalizedToUnit()",
            "observation.rect.normalizedToUnit()",
            "isVerticalLineCandidate(region)",
        ]:
            self.assertIn(marker, helper)

    def test_scope_stays_ordinary_japanese_ocr_only(self) -> None:
        for forbidden in [
            "TranslationSessionStore",
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
            "VNCoreMLModel",
            "MLModel",
            "loadModel(",
        ]:
            self.assertNotIn(forbidden, self.vision)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)

    def test_version_and_ci_route_follow_v3208(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 209) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.208;", self.project)
        previous = "python3 -B scripts/test-v3208-image-japanese-koharu-pixel-detector-contract.py"
        current = "python3 -B scripts/test-v3209-image-japanese-koharu-line-first-dispatch-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3209-image-japanese-koharu-line-first-dispatch-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
