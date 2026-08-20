#!/usr/bin/env python3
"""Contract for passing effective Japanese direction to Manga OCR bbox crops."""

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


class JapaneseDirectionalMangaOCRCropContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOCRService.swift")
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.runtime = read(
            "scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh"
        )
        self.harness = read(
            "scripts/fixtures/v3245-directional-manga-ocr-crop-runtime-harness.swift"
        )
        self.crop_images = braced_body(
            self.service,
            "private static func cropImages(",
        )
        self.orientation = braced_body(
            self.service,
            "private static func orientedBoundingBoxCrop(",
        )
        self.rerecognition = braced_body(
            self.vision,
            "private static func recognizeTextBlockDetached(\n        image: CGImage,",
        )

    def test_request_has_a_safe_natural_default_and_koharu_vertical_mode(self) -> None:
        for marker in [
            "enum MangaOCRCropOrientation: Int, Sendable",
            "case natural = 0",
            "case koharuVertical270 = 270",
            "var cropOrientation: MangaOCRCropOrientation",
            "cropOrientation: MangaOCRCropOrientation = .natural",
        ]:
            self.assertIn(marker, self.service)

    def test_effective_vertical_direction_reaches_the_primary_bbox_crop(self) -> None:
        for marker in [
            "let cropOrientation: MangaOCRCropOrientation",
            "block.effectiveSourceDirection == .vertical",
            "? .koharuVertical270",
            ": .natural",
            "cropOrientation: cropOrientation",
        ]:
            self.assertIn(marker, self.rerecognition)
        self.assertNotIn("block.sourceDirection == .vertical", self.rerecognition)

    def test_scoped_retry_reuses_the_koharu_crop_envelope(self) -> None:
        for marker in [
            "let blockCropRect = sourceLanguage == .japanese",
            "Self.expandedVerticalCropRect(",
            "cropRect: blockCropRect",
            "Self.cropImageForBlock(image, normalizedRect: blockCropRect)",
        ]:
            self.assertIn(marker, self.rerecognition)

    def test_rotation_is_pixel_only_and_natural_crop_is_recoverable(self) -> None:
        for marker in [
            "let boundingBoxCrop = cropImage(image, normalizedRect: request.cropRect)",
            ".map { orientedBoundingBoxCrop($0, orientation: request.cropOrientation) }",
            "case .natural:",
            "case .koharuVertical270:",
            "guard CGFloat(crop.height) > CGFloat(crop.width) * 1.75 else",
            "return rotateImage270(crop) ?? crop",
        ]:
            self.assertIn(marker, self.service)
            self.assertIn(marker, self.crop_images if marker.startswith("let ") or marker.startswith(".map") else self.orientation)
        self.assertIn("private static func orientedBoundingBoxCrop(", self.service)

    def test_detector_ownership_and_quad_fallback_remain_separate(self) -> None:
        for marker in [
            "textRect: request.textRect",
            "primaryBoundingBoxCrop: boundingBoxCrop",
            "lineQuadFallbackCrop: perspectiveCrop",
            "applyVerticalWarp: request.cropQuadIsVertical",
            "guard let perspectiveCrop else { return nil }",
        ]:
            self.assertIn(marker, self.service)
        self.assertIn("cropOrientation", self.crop_images)

    def test_non_japanese_and_page_manga_requests_keep_natural_default(self) -> None:
        self.assertIn("if sourceLanguage == .japanese", self.rerecognition)
        self.assertIn("let japanese = sourceLanguage == .japanese", self.vision)
        self.assertIn("MangaOCRRequest(\n                textRect: region.rect", self.vision)
        self.assertIn("cropQuadIsVertical: region.cropQuadHint != nil", self.vision)
        self.assertIn("cropOrientation: MangaOCRCropOrientation = .natural", self.service)

    def test_cancellation_and_quality_fallback_are_unchanged(self) -> None:
        for marker in [
            "catch is CancellationError",
            "throw CancellationError()",
            "try Task.checkCancellation()",
            "return []",
            "Self.cleanRecognizedBlockText(result.text)",
            "result.confidence >= 0.55",
        ]:
            self.assertIn(marker, self.rerecognition if "result." in marker or "clean" in marker else self.service + self.vision)

    def test_real_runtime_exercises_vertical_override_and_fixture_gate(self) -> None:
        for marker in [
            "sourceDirectionOverride: .vertical",
            "block.effectiveSourceDirection == .vertical",
            "recognizeTextBlock(",
            "batchInference=",
            "effectiveDirection=vertical",
            "vertical Manga OCR crop did not recover the fixture text",
        ]:
            self.assertIn(marker, self.harness + self.runtime)
        self.assertIn(
            "bash scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh",
            self.workflow,
        )

    def test_version_and_ci_route_follow_v3244(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 245) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.244;", self.project)
        previous = "python3 -B scripts/test-v3244-image-japanese-direction-override-rerecognition-contract.py"
        current = "python3 -B scripts/test-v3245-image-japanese-directional-manga-ocr-crop-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3245-image-japanese-directional-manga-ocr-crop-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
