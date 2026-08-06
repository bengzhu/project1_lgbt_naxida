#!/usr/bin/env python3
"""Static contracts for v3.29 reversible image OCR false-positive dismissal."""

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
                return source[brace:index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageOCRFalsePositiveDismissalContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.models = read("AITRANS/Models/TranscriptModels.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )

    def test_store_keeps_ignored_blocks_and_recovery_metadata_in_memory(self) -> None:
        self.assertIn(
            "@Published private(set) var imageTranslationIgnoredBlocks: [ImageTranslationBlock] = []",
            self.store,
        )
        self.assertIn("private var imageTranslationIgnoredBlockSnapshots", self.store)
        self.assertIn("private var imageTranslationOriginalBlockOrder", self.store)
        self.assertIn("private struct ImageTranslationIgnoredBlockSnapshot", self.store)
        self.assertIn("let visionOriginalBlock: ImageTranslationBlock?", self.store)
        self.assertIn("let wasManuallyCorrected: Bool", self.store)

        persisted_snapshot = braced_body(
            self.models,
            "struct AppPersistenceSnapshot: Equatable, Codable, Sendable",
        )
        self.assertNotIn("imageTranslationIgnoredBlocks", persisted_snapshot)
        persist = braced_body(self.store, "private func persist()")
        self.assertNotIn("imageTranslationIgnoredBlocks", persist)

    def test_new_image_and_clear_reset_the_current_image_only_ignored_state(self) -> None:
        for marker in [
            "private func beginImageTranslationTask(",
            "func clearImageTranslation()",
        ]:
            body = braced_body(self.store, marker)
            self.assertIn("imageTranslationIgnoredBlocks = []", body)
            self.assertIn("imageTranslationIgnoredBlockSnapshots = [:]", body)
            self.assertIn("imageTranslationOriginalBlockOrder = [:]", body)

        pipeline = braced_body(self.store, "private func runImageTranslationPipeline(")
        self.assertIn("imageTranslationOriginalBlockOrder = Dictionary(", pipeline)
        self.assertIn("recognizedBlocks.enumerated()", pipeline)

    def test_ignore_is_translated_state_scoped_reversible_and_updates_all_current_outputs(self) -> None:
        ignore = braced_body(
            self.store,
            "func ignoreImageTranslationBlock(_ blockID: UUID) -> Bool",
        )
        for marker in [
            "imageTranslationCorrectionBlockID == nil",
            "imageTranslationState == .translated",
            "imageTranslationIgnoredBlockSnapshots[blockID] == nil",
            "imageTranslationBlocks.remove(at: blockIndex)",
            "imageTranslationVisionOriginalBlocks.removeValue(forKey: blockID)",
            "imageTranslationCorrectedBlockIDs.remove(blockID)",
            "imageTranslationReviewedBlockIDs.remove(blockID)",
            "refreshImageTranslationIgnoredBlocks()",
            "synchronizeImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
        ]:
            self.assertIn(marker, ignore)
        self.assertNotIn("translate(", ignore)
        self.assertNotIn("VisionOCRService", ignore)

    def test_restore_reinserts_in_original_order_and_rebuilds_current_state(self) -> None:
        restore = braced_body(
            self.store,
            "func restoreIgnoredImageTranslationBlock(_ blockID: UUID) -> Bool",
        )
        for marker in [
            "imageTranslationIgnoredBlockSnapshots.removeValue(forKey: blockID)",
            "imageTranslationOriginalBlockOrder[block.id]",
            "snapshot.originalOrder",
            "imageTranslationBlocks.insert(snapshot.block, at: insertionIndex)",
            "if snapshot.wasManuallyCorrected",
            "imageTranslationVisionOriginalBlocks[blockID] = visionOriginalBlock",
            "imageTranslationReviewedBlockIDs.remove(blockID)",
            "synchronizeImageTranslationTranscript(blocks: imageTranslationBlocks)",
            "invalidateImageOverlayRender()",
            "discardImageTranslationExport()",
            "rerenderImageTranslationExport()",
        ]:
            self.assertIn(marker, restore)
        self.assertNotIn("translate(", restore)
        self.assertNotIn("VisionOCRService", restore)

    def test_empty_active_block_list_can_export_the_original_image_without_a_blank_transcript(self) -> None:
        rerender = braced_body(self.store, "private func rerenderImageTranslationExport()")
        self.assertNotIn("!imageTranslationBlocks.isEmpty", rerender)
        self.assertIn("已忽略全部 OCR 文字块，正在生成原图导出", rerender)

        synchronize = braced_body(
            self.store,
            "private func synchronizeImageTranslationTranscript(blocks: [ImageTranslationBlock])",
        )
        self.assertIn("guard !blocks.isEmpty else", synchronize)
        self.assertIn("transcript.remove(at: lineIndex)", synchronize)
        self.assertIn("appendImageTranslationTranscript(blocks: blocks)", synchronize)
        self.assertIn("updateImageTranslationTranscript(blocks: blocks)", synchronize)

    def test_editor_requires_explicit_confirmation_and_explains_recovery(self) -> None:
        self.assertIn("let requestIgnore: () -> Bool", self.editor)
        self.assertIn("@State private var showIgnoreBlockConfirmation = false", self.editor)
        self.assertIn('Label("忽略此文字块", systemImage: "eye.slash")', self.editor)
        self.assertIn('"忽略此文字块？"', self.editor)
        self.assertIn("isPresented: $showIgnoreBlockConfirmation", self.editor)
        self.assertIn('Button("忽略文字块", role: .destructive, action: ignoreCurrentBlock)', self.editor)
        self.assertIn("未保存的修正不会保存；可在图片检查区恢复。", self.editor)
        ignore = braced_body(self.editor, "private func ignoreCurrentBlock()")
        self.assertIn("guard !isSaving else { return }", ignore)
        self.assertIn("guard requestIgnore() else", ignore)
        self.assertIn("dismiss()", ignore)

    def test_panel_restores_from_a_dedicated_visible_section_and_preserves_focus(self) -> None:
        self.assertIn("requestIgnore: {", self.panel)
        self.assertIn("ignoreImageTranslationBlock(block)", self.panel)
        self.assertIn('title: "已忽略的文字块"', self.panel)
        self.assertIn("ForEach(store.imageTranslationIgnoredBlocks)", self.panel)
        self.assertIn("ImageTranslationIgnoredBlockRow(", self.panel)
        self.assertIn("restoreIgnoredImageTranslationBlock(block)", self.panel)
        self.assertIn("已忽略 \\(store.imageTranslationIgnoredBlocks.count) 个 OCR 文字块", self.panel)

        ignore = braced_body(
            self.panel,
            "private func ignoreImageTranslationBlock(_ block: ImageTranslationBlock) -> Bool",
        )
        self.assertIn("store.ignoreImageTranslationBlock(block.id)", ignore)
        self.assertIn("ignoredRowAccessibilityFocusID(block.id)", ignore)

        restore = braced_body(
            self.panel,
            "private func restoreIgnoredImageTranslationBlock(_ block: ImageTranslationBlock)",
        )
        self.assertIn("store.restoreIgnoredImageTranslationBlock(block.id)", restore)
        self.assertIn("ImageOCRResultSummary.requiresReview(block)", restore)
        self.assertRegex(
            restore,
            r"prepareReviewFilterChange\(\s*to: nextFilter",
        )
        self.assertIn("revealPreview()", restore)
        self.assertIn("moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(block.id))", restore)

        row = braced_body(self.view, "private struct ImageTranslationIgnoredBlockRow: View")
        self.assertIn('Button("恢复", systemImage: "arrow.uturn.backward", action: restore)', row)
        self.assertIn("AppTheme.Layout.minimumTarget", row)
        self.assertIn("需要复查的文字块会重新回到待复查队列", row)
        self.assertIn('equals: "image-ignored-row-\\(block.id.uuidString)"', row)

    def test_ci_routes_v329_after_v328(self) -> None:
        old = "python3 -B scripts/test-v328-image-review-session-continuity-contract.py"
        new = "python3 -B scripts/test-v329-image-ocr-false-positive-dismissal-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v329-image-ocr-false-positive-dismissal-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
