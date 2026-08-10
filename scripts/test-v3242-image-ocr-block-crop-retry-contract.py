#!/usr/bin/env python3
"""Contract for scoped OCR rerecognition of one image text block."""

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


class ImageOCRBlockCropRetryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.ocr = read("AITRANS/Services/VisionOCRService.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.recognize = braced_body(
            self.ocr,
            "func recognizeTextBlock(",
        )
        self.recognize_detached = braced_body(
            self.ocr,
            "private static func recognizeTextBlockDetached(",
        )
        self.gate = braced_body(
            self.store,
            "func canRerecognizeImageTranslationBlock(",
        )
        self.retry = braced_body(
            self.store,
            "func rerecognizeImageTranslationBlock(",
        )
        self.row = braced_body(
            self.view,
            "private struct ImageTranslationBlockRow: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_ocr_service_is_crop_only_and_keeps_japanese_model_fallback(self) -> None:
        for marker in [
            "let task = Task.detached(priority: .userInitiated)",
            "try await Self.recognizeTextBlockDetached(",
            "return try await task.value",
        ]:
            self.assertIn(marker, self.recognize)
        for marker in [
            "let image = try Self.makeOCRImage(from: imageData)",
            "MangaOCRRequest(",
            "MangaOCRService.shared",
            ".recognize(image: image, requests: [request])",
            "Self.cropImageForBlock(image, normalizedRect: rect)",
            "result.confidence.isFinite",
            "result.confidence >= 0.55",
            "Self.japaneseScriptDensity(in: text) >= 0.5",
            "angles = [270, 90]",
            "usesLanguageCorrection: !japanese",
            "observationRole: .crop",
        ]:
            self.assertIn(marker, self.recognize_detached)
        for forbidden in [
            "recognizeTextBlocks(",
            "ImageOCRLayoutEngine.layout(",
            "RTDETR",
            "detectJapanese",
        ]:
            self.assertNotIn(forbidden, self.recognize_detached)

    def test_gate_requires_existing_content_and_terminal_session(self) -> None:
        for marker in [
            "imageTranslationRetryingBlockID == nil",
            "imageTranslationRerecognizingBlockID == nil",
            "imageTranslationCorrectionBlockID == nil",
            "imageTranslationState == .translated || imageTranslationState == .failed",
            "imageTranslationExportRenderState != .rendering",
            "imageTranslationData != nil",
            "imageTranslationBlocks.contains(where: { $0.id == blockID })",
            "imageTranslationBlocks.first(where: { $0.id == blockID })?.boundingBox.normalizedToUnit() != nil",
            "imageTranslationContentSourceLanguage != nil",
            "imageTranslationContentTargetLanguage != nil",
        ]:
            self.assertIn(marker, self.gate)

    def test_retry_uses_request_and_content_guards_before_commit(self) -> None:
        for marker in [
            "let requestID = UUID()",
            "let contentTaskID = imageTranslationTaskID",
            "imageTranslationBlockRerecognitionID = requestID",
            "visionOCRService.recognizeTextBlock(",
            "self.imageTranslationBlockRerecognitionID == requestID",
            "self.imageTranslationTaskID == contentTaskID",
            "self.imageTranslationRerecognizingBlockID == blockID",
            "self.imageTranslationBlocks[blockIndex] == block",
            "self.imageTranslationBlocks[currentIndex] == block",
        ]:
            self.assertIn(marker, self.retry)
        self.assertNotIn("self.imageTranslationBlocks =", self.retry)

    def test_success_preserves_identity_geometry_direction_and_order(self) -> None:
        for marker in [
            "var replacement = block",
            "replacement.original = recognizedOriginal",
            "replacement.translation = cleanTranslation",
            "replacement.confidence = recognized.confidence",
            "self.imageTranslationBlocks[currentIndex] = replacement",
            "self.updateImageTranslationTranscript(blocks: self.imageTranslationBlocks)",
            "self.imageTranslationReviewedBlockIDs.remove(blockID)",
        ]:
            self.assertIn(marker, self.retry)
        for forbidden in [
            "replacement.id =",
            "replacement.boundingBox =",
            "replacement.sourceDirection =",
            "imageTranslationBlocks.remove",
            "imageTranslationBlocks.insert",
        ]:
            self.assertNotIn(forbidden, self.retry)

    def test_failure_and_cancellation_restore_prior_state_without_block_mutation(self) -> None:
        for marker in [
            "let previousState = imageTranslationState",
            "catch is CancellationError",
            "self.imageTranslationState = previousState",
            "此图片文字块重新识别已取消",
            "此图片文字块重新识别失败：\\(error.localizedDescription)",
            "self.imageTranslationRerecognizingBlockID = nil",
            "self.imageTranslationBlockRerecognitionTask = nil",
        ]:
            self.assertIn(marker, self.retry)

    def test_lifecycle_invalidates_block_rerecognition(self) -> None:
        for marker in [
            "imageTranslationBlockRerecognitionTask?.cancel()",
            "imageTranslationBlockRerecognitionTask = nil",
            "invalidateImageTranslationBlockRerecognition()",
        ]:
            self.assertGreaterEqual(self.store.count(marker), 3)
        invalidate = braced_body(
            self.store,
            "private func invalidateImageTranslationBlockRerecognition(",
        )
        self.assertIn("imageTranslationBlockRerecognitionID = UUID()", invalidate)
        self.assertIn("imageTranslationRerecognizingBlockID = nil", invalidate)

    def test_row_and_focus_preview_expose_the_same_accessibility_action(self) -> None:
        for body in [self.row, self.focus]:
            for marker in [
                "canRerecognize",
                "isRerecognizing",
                "rerecognize",
                '"重新识别此文字块"',
                'systemImage: isRerecognizing ? "hourglass" : "text.viewfinder"',
            ]:
                self.assertIn(marker, body)
        self.assertIn(
            '.accessibilityAction(named: "重新识别此文字块")',
            self.view,
        )
        self.assertIn(
            "ImageFocusPreviewRerecognitionAccessibilityModifier(",
            self.focus,
        )
        self.assertIn(
            "ImageReviewRowRerecognitionAccessibilityModifier(",
            self.row,
        )

    def test_version_and_ci_route_include_both_v3242_contracts(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 242) for version in versions)
        )
        previous = "python3 -B scripts/test-v3241-image-japanese-manga-ocr-vertical-quad-warp-contract.py"
        punctuation = "python3 -B scripts/test-v3242-image-japanese-vertical-punctuation-contract.py"
        current = "python3 -B scripts/test-v3242-image-ocr-block-crop-retry-contract.py"
        for marker in [previous, punctuation, current]:
            self.assertIn(marker, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(punctuation))
        self.assertLess(self.workflow.index(punctuation), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3242-image-ocr-block-crop-retry-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
