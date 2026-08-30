#!/usr/bin/env python3
"""Contract for the bounded pixel-first Japanese detector proxy."""

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


class JapaneseKoharuPixelDetectorContractTests(unittest.TestCase):
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
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_detector_runs_before_window_fallback_and_is_japanese_scoped(self) -> None:
        self.assertIn("recognizeJapanesePixelFirstVerticalCrops(", self.crops)
        self.assertIn("observations: ownerAnnotatedObservations", self.crops)
        owner_annotation = self.crops.index(
            "let ownerAnnotatedObservations = annotateJapaneseVerticalTextRegionOwners("
        )
        pixel_detector = self.crops.index(
            "recognizeJapanesePixelFirstVerticalCrops("
        )
        self.assertLess(owner_annotation, pixel_detector)
        self.assertLess(
            pixel_detector,
            self.crops.index("recognizeJapaneseVerticalTileFallback("),
        )

    def test_detector_uses_both_rotated_pixel_views_and_maps_geometry(self) -> None:
        for marker in [
            "for angle in [90, 270]",
            "try? rotatedImage(image, angle: angle)",
            "VNDetectTextRectanglesRequest()",
            "request.reportCharacterBoxes = true",
            "request.results ?? []",
            "normalizedRect(from: detection.boundingBox)",
            "mapRotatedRegionRect(",
            "isJapanesePixelFirstVerticalCandidate(mappedRect)",
        ]:
            self.assertIn(marker, self.detector)

    def test_detector_candidates_are_vertical_uncovered_and_bounded(self) -> None:
        detector_scope = self.detector + self.vision
        for marker in [
            "!reliableVerticalBlocks.contains(where:",
            "rect.width <= 0.30",
            "rect.height >= 0.025",
            "aspectRatio >= 1.15",
            "unique.count == 12",
            "isSameJapanesePixelFirstRegion(candidate, as: $0)",
        ]:
            self.assertIn(marker, detector_scope)
        self.assertRegex(
            detector_scope,
            r"japanesePixelDetectorRegionIsCovered\(\s*\$0\.rect,\s*by:\s*mappedRect\s*\)",
        )

    def test_detector_crop_reuses_koharu_preprocess_mapping_and_fallback_budget(self) -> None:
        for marker in [
            "for candidate in candidates.prefix(12)",
            "expandedVerticalLineCropRect(",
            "prepareJapaneseCropForVision(crop.image)",
            "recognizeJapaneseCropPass(",
            "var orientationFallbacksRemaining = 4",
            "oppositeJapaneseOrientation(",
            "cropScale: preparedCrop.scale",
            # v3.254 keeps the historical Japanese dedupe and adds a compact
            # recovery tie-break before returning the same bounded observations.
            "deduplicateJapaneseObservations(refined)",
        ]:
            self.assertIn(marker, self.pixel)
        self.assertTrue(
            "observationRole: .crop" in self.pixel
            or "observationRole: .verticalLine" in self.pixel
        )

    def test_pixel_detector_does_not_cross_model_probe_or_artifact_boundaries(self) -> None:
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

    def test_version_and_ci_route_follow_v3207(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 208) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.207;", self.project)
        previous = "python3 -B scripts/test-v3207-image-japanese-koharu-line-coverage-quality-contract.py"
        current = "python3 -B scripts/test-v3208-image-japanese-koharu-pixel-detector-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3208-image-japanese-koharu-pixel-detector-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
