#!/usr/bin/env python3
"""Contract for tight character-envelope Japanese detector crops."""

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


class JapaneseKoharuCharacterEnvelopeContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.detector = braced_body(
            self.vision,
            "private static func detectJapanesePixelFirstVerticalRegions(",
        )
        self.envelope = braced_body(
            self.vision,
            "private static func japanesePixelDetectorCharacterEnvelope(",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_detector_requests_character_geometry_and_keeps_request_fallback(self) -> None:
        for marker in [
            "request.reportCharacterBoxes = true",
            "normalizedRect(from: detection.boundingBox)",
            "mappedRequestRect",
            "japanesePixelDetectorCharacterEnvelope(",
            "fallback: mappedRequestRect",
        ]:
            self.assertIn(marker, self.detector)

    def test_character_boxes_are_mapped_and_unioned_as_a_tight_line_proxy(self) -> None:
        for marker in [
            "detection.characterBoxes ?? []",
            "normalizedRect(from: character.boundingBox)",
            "mapRotatedRegionRect(",
            "characterRects.count >= 2",
            ".reduce(characterRects[0], { $0.union($1) })",
            ".normalizedToUnit()",
        ]:
            self.assertIn(marker, self.envelope)

    def test_envelope_is_consistency_gated_and_safely_falls_back(self) -> None:
        for marker in [
            "isJapanesePixelFirstVerticalCandidate(envelope)",
            "overlapRatio(envelope, fallback) >= 0.80",
            "areaRatio >= 0.25",
            "areaRatio <= 1.05",
            "horizontalCoverage >= 0.35",
            "verticalCoverage >= 0.60",
            "return fallback",
            "return envelope",
        ]:
            self.assertIn(marker, self.envelope)
        self.assertGreaterEqual(self.envelope.count("return fallback"), 2)

    def test_existing_vertical_budget_and_model_boundaries_remain(self) -> None:
        detector_scope = self.detector + self.vision
        for marker in [
            "isJapanesePixelFirstVerticalCandidate(mappedRect)",
            "unique.count == 12",
            "for angle in [90, 270]",
        ]:
            self.assertIn(marker, detector_scope)
        for forbidden in [
            "VNCoreMLModel",
            "MLModel",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_version_fixture_and_ci_route_follow_v3212(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, v.split("."))) >= (3, 213) for v in versions))
        self.assertNotIn("MARKETING_VERSION = 3.212;", self.project)

        previous = "python3 -B scripts/test-v3212-image-japanese-koharu-raw-crop-recognition-contract.py"
        current = "python3 -B scripts/test-v3213-image-japanese-koharu-character-envelope-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3213-image-japanese-koharu-character-envelope-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
