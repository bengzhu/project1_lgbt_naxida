#!/usr/bin/env python3
"""Contract for Koharu source-direction-aware Japanese crop padding."""

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


class JapaneseDirectionalKoharuPaddingContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.vision = read("AITRANS/Services/VisionOCRService.swift")
        self.padding = braced_body(
            self.vision,
            "private static func koharuVerticalCropPadding(",
        )
        self.padding_declaration = self.vision[
            self.vision.index("private static func koharuVerticalCropPadding(") :
            self.vision.index(
                "{",
                self.vision.index("private static func koharuVerticalCropPadding("),
            )
        ]
        self.block_retry = braced_body(
            self.vision,
            "private static func recognizeTextBlockDetached(",
        )
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.restore = braced_body(
            self.store,
            "func restoreImageTranslationBlockToVisionOCR(_ blockID: UUID)",
        )
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_padding_matches_koharu_source_direction(self) -> None:
        for marker in [
            "direction: ImageTextDirection = .vertical",
            "let horizontalPaddingFraction = direction == .horizontal ? 0.12 : 0.18",
            "let verticalPaddingFraction = direction == .horizontal ? 0.18 : 0.12",
            "fontSizePixels * horizontalPaddingFraction",
            "fontSizePixels * verticalPaddingFraction",
            "basePaddingPixels = max(fontSizePixels * 0.08, 2)",
        ]:
            haystack = self.padding_declaration if marker.startswith("direction:") else self.padding
            self.assertIn(marker, haystack)

    def test_scoped_retry_consumes_effective_direction(self) -> None:
        for marker in [
            "direction: block.effectiveSourceDirection ?? .vertical",
            "Self.expandedVerticalCropRect(",
            "cropRect: blockCropRect",
        ]:
            self.assertIn(marker, self.block_retry)
        self.assertIn(
            "direction: ImageTextDirection = .vertical",
            self.vision,
        )
        harness = read(
            "scripts/fixtures/v3245-directional-manga-ocr-crop-runtime-harness.swift"
        )
        runtime = read(
            "scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh"
        )
        for marker in [
            "horizontalBlock.sourceDirectionOverride = .horizontal",
            "horizontalDirection=",
            "horizontalText=",
            "horizontalConfidence=",
        ]:
            self.assertIn(marker, harness + runtime)

    def test_vertical_page_paths_keep_the_existing_default(self) -> None:
        self.assertIn(
            "expandedVerticalCropRect(block.rect, imageSize: imageSize)",
            self.vision,
        )
        self.assertIn(
            "expandedVerticalCropRect(envelope, imageSize: imageSize)",
            self.vision,
        )
        self.assertIn(
            "let padding = imageSize.flatMap { koharuVerticalCropPadding(rect, imageSize: $0) }",
            self.vision,
        )

    def test_normalized_fallback_swaps_the_same_direction_fractions(self) -> None:
        crop = braced_body(
            self.vision,
            "private static func expandedVerticalCropRect(",
        )
        for marker in [
            "let horizontalFraction = direction == .horizontal ? 0.12 : 0.18",
            "let verticalFraction = direction == .horizontal ? 0.18 : 0.12",
            "rect.width * horizontalFraction",
            "rect.height * verticalFraction",
            ".normalizedToUnit() ?? rect",
        ]:
            self.assertIn(marker, crop)

    def test_scope_keeps_ocr_fallback_and_non_japanese_paths(self) -> None:
        for marker in [
            "if sourceLanguage == .japanese",
            "MangaOCRService.shared",
            "catch is CancellationError",
            "throw CancellationError()",
            "usesLanguageCorrection: !japanese",
        ]:
            self.assertIn(marker, self.block_retry)
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "TranslationSessionStore",
            "metrics/version_history.csv",
            "output/",
        ]:
            self.assertNotIn(forbidden, self.vision)

    def test_restore_keeps_a_reviewer_direction_override(self) -> None:
        for marker in [
            "var restoredBlock = originalBlock",
            "restoredBlock.sourceDirectionOverride = imageTranslationBlocks[blockIndex].sourceDirectionOverride",
            "imageTranslationBlocks[blockIndex] = restoredBlock",
        ]:
            self.assertIn(marker, self.restore)

    def test_version_and_ci_route_follow_v3245(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 246) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.245;", self.project)
        previous = "python3 -B scripts/test-v3245-image-japanese-directional-manga-ocr-crop-contract.py"
        current = "python3 -B scripts/test-v3246-image-japanese-directional-koharu-padding-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3246-image-japanese-directional-koharu-padding-contract.py'",
            self.workflow,
        )
        self.assertIn(
            "bash scripts/test-v3245-image-japanese-directional-manga-ocr-crop-runtime.sh",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
