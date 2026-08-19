#!/usr/bin/env python3
"""Contract for the bounded Koharu-style Japanese crop-then-OCR refinement."""

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


class JapaneseCropOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(
            self.vision,
            "func recognizeTextBlocksWithShadowLedger(",
        )
        self.crop = braced_body(self.vision, "private static func recognizeJapaneseVerticalCrops(")

    def test_japanese_path_uses_existing_layout_to_bound_crop_rereads(self) -> None:
        for marker in [
            "let cropRefinedObservations = try await Self.recognizeJapaneseVerticalCrops(",
            "observations.append(contentsOf: cropRefinedObservations)",
            "ImageOCRLayoutEngine.layout(",
            "allowsVerticalText: true",
            ".prefix(16)",
        ]:
            self.assertIn(marker, self.recognize if marker.startswith("let ") or marker.startswith("observations") else self.crop)
        self.assertTrue(
            "existing vertical layout candidates" in self.vision
            or "crop existing vertical layout nodes" in self.vision
        )

    def test_crop_reread_uses_koharu_padding_rotation_and_box_mapping(self) -> None:
        direct_markers = [
            "expandedVerticalCropRect",
            "cropImage(image, normalizedRect:",
            "minimumTextHeight: 0.004",
            "automaticallyDetectsLanguage: false",
        ]
        crop_scope = self.crop + self.vision
        for marker in direct_markers:
            self.assertIn(marker, crop_scope)
        # Later crop refinements share the rotation/mapping helper so the
        # primary and opposite orientation passes cannot drift apart.
        self.assertTrue(
            "try? rotatedImage(crop.image, angle: angle)" in self.crop
            or "recognizeJapaneseCropPass(" in self.crop
        )
        for marker in [
            "mapRotatedCropObservation(",
            "cropRect.minX + local.x",
            "cropRect.minY + local.y",
            "rotationApplied: observation.rotationApplied",
        ]:
            self.assertIn(marker, self.vision)

    def test_crop_refinement_is_fallback_safe_and_deduped_before_final_layout(self) -> None:
        self.assertIn("guard let crop = cropImage", self.crop)
        self.assertIn("else {\n                continue\n            }", self.crop)
        self.assertIn("deduplicateObservations(observations)", self.vision)
        self.assertLess(
            self.vision.index("deduplicateObservations(observations)"),
            self.vision.index("ImageOCRLayoutEngine.layout(", self.vision.index("let layoutObservations")),
        )

    def test_crop_path_stays_out_of_probe_and_active_artifact_sources(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
        ]:
            self.assertNotIn(forbidden, self.vision)
        self.assertIn("Koharu crops each detected text node", self.vision)
        if "no bundled Manga OCR/PaddleOCR model" not in self.vision:
            manga_service = read("AITRANS/Services/MangaOCRService.swift")
            self.assertIn("await Self.recognizeJapaneseMangaOCR(", self.vision)
            self.assertNotIn("import CoreML", self.vision)
            self.assertIn("import CoreML", manga_service)
            self.assertIn("actor MangaOCRService", manga_service)

    def test_fixture_and_version_route(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 158) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.157;", self.project)
        previous = "python3 -B scripts/test-v3157-image-japanese-bidirectional-orientation-ocr-contract.py"
        current = "python3 -B scripts/test-v3158-image-japanese-crop-ocr-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn("15[8]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
