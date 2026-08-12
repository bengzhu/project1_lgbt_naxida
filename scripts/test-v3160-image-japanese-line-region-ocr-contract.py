#!/usr/bin/env python3
"""Contract for Koharu-style Japanese line-region OCR refinement."""

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


class JapaneseLineRegionOCRContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.crop = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalCrops(",
        )
        self.line = braced_body(
            self.vision,
            "private static func recognizeJapaneseVerticalLineCrops(",
        )
        self.mapping = braced_body(
            self.vision,
            "private static func mapRotatedCropObservation(",
        )
        self.padding = braced_body(
            self.vision,
            "private static func expandedVerticalLineCropRect(",
        )

    def test_vertical_blocks_feed_bounded_line_region_refinement(self) -> None:
        for marker in [
            "Koharu's extract_text_block_regions",
            "recognizeJapaneseVerticalLineCrops(",
            "let verticalBlockArray = Array(verticalBlocks)",
            "blocks: verticalBlockArray",
        ]:
            self.assertIn(marker, self.crop)
        owner_annotation = self.crop.index(
            "let ownerAnnotatedObservations = annotateJapaneseVerticalTextRegionOwners("
        )
        line_refinement = self.crop.index(
            "let lineRefined = try await Self.recognizeJapaneseVerticalLineCrops("
        )
        self.assertLess(owner_annotation, line_refinement)
        self.assertIn("blocks: verticalBlockArray", self.crop[owner_annotation:line_refinement])
        self.assertIn("overlapRatio(observation.rect, block.rect) >= 0.25", self.line)
        self.assertTrue(
            "isVerticalLineCandidate(observation.rect)" in self.line
            or (
                "let lineRegion = observation.lineRegionRect ?? observation.rect" in self.line
                and "isVerticalLineCandidate(lineRegion)" in self.line
            )
        )
        for marker in [
            ".prefix(24)",
            "expandedVerticalLineCropRect",
        ]:
            self.assertIn(marker, self.line)

    def test_line_regions_use_direction_padding_upscale_and_lower_height_gate(self) -> None:
        legacy_markers = [
            "horizontalPadding = min(max(rect.width * 0.18, 0.008), 0.06)",
            "verticalPadding = min(max(rect.height * 0.12, 0.006), 0.06)",
        ]
        adaptive_markers = [
            "private static func koharuVerticalCropPadding(",
            "let fontSizePixels = max(min(widthPixels, heightPixels), 1)",
            "let horizontalPaddingPixels = max(fontSizePixels * 0.18, basePaddingPixels)",
            "let verticalPaddingPixels = max(fontSizePixels * 0.12, basePaddingPixels)",
        ]
        directional_markers = [
            "private static func koharuVerticalCropPadding(",
            "let fontSizePixels = max(min(widthPixels, heightPixels), 1)",
            "let horizontalPaddingFraction = direction == .horizontal ? 0.12 : 0.18",
            "let verticalPaddingFraction = direction == .horizontal ? 0.18 : 0.12",
            "fontSizePixels * horizontalPaddingFraction",
            "fontSizePixels * verticalPaddingFraction",
        ]
        self.assertTrue(
            all(marker in self.padding for marker in legacy_markers)
            or all(marker in self.vision for marker in adaptive_markers)
            or all(marker in self.vision for marker in directional_markers)
        )
        line_scope = self.line + self.vision
        self.assertTrue(
            "resizedImage(crop.image, scale: 2)" in line_scope
            or "prepareJapaneseCropForVision(crop.image)" in line_scope
        )
        for marker in [
            "minimumTextHeight: 0.002",
            "automaticallyDetectsLanguage: false",
            "rotationApplied: angle",
        ]:
            self.assertIn(marker, line_scope)

    def test_upscaled_rotated_boxes_map_back_to_original_crop_space(self) -> None:
        for marker in [
            "unscaledRotatedSize",
            "scaleX",
            "scaleY",
            "$0.x / max(scaleX, safeScale)",
            "$0.y / max(scaleY, safeScale)",
            "mapPointToOriginal",
            "cropRect.minX + local.x",
            "cropRect.minY + local.y",
        ]:
            self.assertIn(marker, self.mapping)
        self.assertTrue(
            "cropScale: cropScale" in self.line
            or "cropScale: preparedCrop.scale" in self.line
        )

    def test_line_refinement_is_fallback_safe_and_finally_deduped(self) -> None:
        self.assertIn("guard let crop = cropImage", self.line)
        self.assertTrue(
            "if let resized = resizedImage(crop.image, scale: 2)" in self.line
            or "prepareJapaneseCropForVision(crop.image)" in self.line
        )
        self.assertTrue(
            "try? rotatedImage(scaledCrop, angle: angle)" in self.line
            or "recognizeJapaneseCropPass(" in self.line
        )
        self.assertIn("deduplicateObservations(observations)", self.vision)

    def test_migration_does_not_load_models_or_active_koharu_sources(self) -> None:
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "FileManager",
            "TranslationSessionStore",
        ]:
            self.assertNotIn(forbidden, self.vision)
        self.assertIn("Vision does not expose those polygons", self.vision)

    def test_fixture_version_and_ci_route(self) -> None:
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(len(fixture.read_bytes()), 100_000)
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 160) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.159;", self.project)
        old = "python3 -B scripts/test-v3159-image-japanese-ocr-status-context-contract.py"
        new = "python3 -B scripts/test-v3160-image-japanese-line-region-ocr-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn("16[0]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
