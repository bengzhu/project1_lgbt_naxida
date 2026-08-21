#!/usr/bin/env python3
"""Contract for scoped retry of failed image translation blocks."""

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


class ImageTranslationBlockRetryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.retry_gate = braced_body(
            self.store,
            "func canRetryImageTranslationBlock(",
        )
        self.retry = braced_body(
            self.store,
            "func retryImageTranslationBlock(",
        )
        self.invalidate = braced_body(
            self.store,
            "private func invalidateImageTranslationBlockRetry(",
        )
        self.row = braced_body(
            self.view,
            "private struct ImageTranslationBlockRow: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )
        self.row_hint = braced_body(
            self.row,
            "private func rowAccessibilityHint(appendingTo base: String)",
        )
        self.row_retry_modifier = braced_body(
            self.view,
            "private struct ImageReviewRowRetryAccessibilityModifier",
        )

    def test_gate_allows_only_empty_blocks_in_terminal_states(self) -> None:
        for marker in [
            "imageTranslationRetryingBlockID == nil",
            "imageTranslationState == .translated || imageTranslationState == .failed",
            "imageTranslationBlocks.first(where:",
            "!block.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty",
            "block.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty",
            "imageTranslationContentSourceLanguage != nil",
            "imageTranslationContentTargetLanguage != nil",
        ]:
            self.assertIn(marker, self.retry_gate)

    def test_retry_reuses_translation_without_running_ocr(self) -> None:
        self.assertIn("if sourceLanguage == .japanese", self.retry)
        self.assertIn("translateJapaneseImageBatch(", self.retry)
        self.assertIn("translation = try await self.translateImageBlockWithQA(", self.retry)
        for forbidden in [
            "visionOCRService",
            "recognizeTextBlocks(",
            "runImageTranslationPipeline(",
        ]:
            self.assertNotIn(forbidden, self.retry)

    def test_japanese_retry_preserves_global_numbered_batch_protocol(self) -> None:
        self.assertTrue(
            "imageTranslationOriginalBlockOrder[blockID]" in self.retry
            or "japaneseImageTranslationPrompt(for: blockID)" in self.retry
        )
        self.assertTrue(
            "startIndex: startIndex" in self.retry
            or "startIndex: prompt.startIndex" in self.retry
        )
        for marker in [
            "sourceLanguage: sourceLanguage",
            "targetLanguage: targetLanguage",
            ").first ?? \"\"",
        ]:
            self.assertIn(marker, self.retry)
        self.assertNotIn("imageTranslationBlocks =", self.retry)

    def test_stale_retry_results_cannot_mutate_new_content(self) -> None:
        for marker in [
            "let retryID = UUID()",
            "let contentTaskID = imageTranslationTaskID",
            "imageTranslationBlockRetryID = retryID",
            "self.imageTranslationBlockRetryID == retryID",
            "self.imageTranslationTaskID == contentTaskID",
            "self.imageTranslationRetryingBlockID == blockID",
            "self.imageTranslationBlocks[blockIndex].original == block.original",
        ]:
            self.assertIn(marker, self.retry)
        self.assertIn("imageTranslationBlockRetryID = UUID()", self.invalidate)
        self.assertIn("imageTranslationRetryingBlockID = nil", self.invalidate)

    def test_lifecycle_invalidates_retry_on_new_clear_and_cancel(self) -> None:
        for marker in [
            "imageTranslationBlockRetryTask?.cancel()",
            "imageTranslationBlockRetryTask = nil",
            "invalidateImageTranslationBlockRetry()",
        ]:
            self.assertGreaterEqual(self.store.count(marker), 3)

    def test_partial_failure_keeps_blocks_and_completed_translations(self) -> None:
        for marker in [
            "self.imageTranslationBlocks[blockIndex].translation = cleanTranslation",
            "let remainingCount = self.imageTranslationBlocks.count(where:",
            "self.imageTranslationState = .failed",
            "仍有 \\(remainingCount) 个文字块等待翻译",
            "self.imageTranslationMessage = \"此文字块翻译失败：\\(error.localizedDescription)\"",
        ]:
            self.assertIn(marker, self.retry)
        self.assertNotIn("self.imageTranslationBlocks =", self.retry)

    def test_all_blocks_complete_before_export_rerender(self) -> None:
        self.assertIn("if remainingCount == 0", self.retry)
        self.assertIn("self.imageTranslationState = .translated", self.retry)
        self.assertIn("self.invalidateImageOverlayRender()", self.retry)
        self.assertIn("self.discardImageTranslationExport()", self.retry)
        self.assertIn("self.rerenderImageTranslationExport()", self.retry)

    def test_result_row_exposes_retry_button_and_parent_accessibility_action(self) -> None:
        for marker in [
            "canRetryTranslation: Bool",
            "isRetryingTranslation: Bool",
            "retryTranslation: () -> Void",
            'isRetryingTranslation ? "取消此文字块翻译重试" : "重试此文字块翻译"',
            'systemImage: isRetryingTranslation ? "xmark.circle" : "arrow.clockwise"',
            '"可重试此块"',
            "ImageReviewRowRetryAccessibilityModifier(",
        ]:
            self.assertIn(marker, self.row)
        self.assertIn('actions.append("重试此文字块翻译")', self.row_hint)
        self.assertIn('.accessibilityAction(named: "重试此文字块翻译")', self.row_retry_modifier)

    def test_focus_preview_keeps_retry_action_scoped_to_empty_block(self) -> None:
        for marker in [
            "let canRetryTranslation: Bool",
            "let isRetryingTranslation: Bool",
            "let retryTranslation: () -> Void",
            "let retryUnavailableHint: String",
            "block.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty",
            '"取消只针对当前文字块的翻译重试；保留其它译文、OCR 和复查进度"',
        ]:
            self.assertIn(marker, self.focus)
        self.assertIn("retryTranslation: { retryTranslation(selectedBlock.id) }", self.view)

    def test_scope_stays_translation_ux_without_probe_or_model_claims(self) -> None:
        scoped_sources = self.retry + self.row + self.focus
        for forbidden in [
            "MangaOverlayProbeService",
            "groundTruth",
            "test/koharu_artifacts",
            "metrics/version_history.csv",
            "output/",
            "VNCoreMLModel",
            "MLModel",
        ]:
            self.assertNotIn(forbidden, scoped_sources)
        fixture = ROOT / "test/jap.jpg"
        self.assertTrue(fixture.is_file())
        self.assertGreater(fixture.stat().st_size, 100_000)

    def test_version_and_ci_route_follow_v3209(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(
            all(tuple(map(int, version.split("."))) >= (3, 210) for version in versions)
        )
        self.assertNotIn("MARKETING_VERSION = 3.209;", self.project)
        previous = "python3 -B scripts/test-v3209-image-japanese-koharu-line-first-dispatch-contract.py"
        current = "python3 -B scripts/test-v3210-image-translation-block-retry-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertIn(current, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(current))
        self.assertIn(
            "if grep -Fx 'scripts/test-v3210-image-translation-block-retry-contract.py'",
            self.workflow,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
