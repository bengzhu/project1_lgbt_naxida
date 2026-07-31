#!/usr/bin/env python3
"""Static contracts for v3.34 focus-preview OCR correction shortcut."""

from pathlib import Path
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


class ImageFocusPreviewCorrectionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )

    def test_workspace_forwards_the_existing_correction_entry_and_same_availability_gate(self) -> None:
        workspace = braced_body(self.panel, "private var imageWorkspace: some View")
        self.assertIn("canEdit: !isRunning && !isRenderingExport", workspace)
        self.assertIn("editBlock: { beginCorrection(of: $0) }", workspace)
        self.assertIn("ImageTranslationPreview(", workspace)

    def test_selected_focus_preview_receives_the_current_block_and_existing_edit_callback(self) -> None:
        self.assertIn("let canEdit: Bool", self.preview)
        self.assertIn("let editBlock: (ImageTranslationBlock) -> Void", self.preview)
        self.assertIn("canEdit: canEdit", self.preview)
        self.assertIn("edit: { editBlock(selectedBlock) }", self.preview)
        self.assertIn(
            "store.imageTranslationBlocks.first(where: { $0.id == selectedBlockID })",
            self.preview,
        )

    def test_focus_preview_exposes_a_named_44pt_edit_command_beside_close(self) -> None:
        self.assertIn("VStack(spacing: AppTheme.Spacing.compact)", self.focus)
        self.assertIn(
            'Button("关闭局部放大", systemImage: "xmark", action: close)',
            self.focus,
        )
        self.assertIn(
            'Button("修正识别文字", systemImage: "pencil", action: edit)',
            self.focus,
        )
        self.assertIn(
            ".frame(width: AppTheme.Layout.minimumTarget, height: AppTheme.Layout.minimumTarget)",
            self.focus,
        )
        self.assertIn(".disabled(!canEdit)", self.focus)
        self.assertIn("打开当前文字块的 OCR 修正页面", self.focus)

    def test_panel_rejects_stale_or_busy_shortcut_callbacks_before_presenting_the_sheet(self) -> None:
        begin = braced_body(
            self.panel,
            "private func beginCorrection(of block: ImageTranslationBlock)",
        )
        for marker in [
            "guard !isRunning",
            "!isRenderingExport",
            "store.imageTranslationBlocks.contains(where: { $0.id == block.id })",
            "moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(",
            "editingImageTranslationBlock = block",
        ]:
            self.assertIn(marker, begin)
        self.assertLess(
            begin.index("moveReviewAccessibilityFocusAfterCorrectionSheetDismissal("),
            begin.index("editingImageTranslationBlock = block"),
        )

    def test_shortcut_reuses_the_existing_view_only_sheet_and_dismissal_handoff(self) -> None:
        self.assertNotIn("ImageTranslationFocusPreview", self.store)
        self.assertNotIn("VisionOCRService", self.focus)
        self.assertNotIn("correctImageTranslationBlock", self.focus)
        self.assertIn(
            "item: $editingImageTranslationBlock,\n"
            "            onDismiss: applyPendingCorrectionSheetDismissalFocus",
            self.panel,
        )

    def test_ci_routes_v334_after_v333(self) -> None:
        old = "python3 -B scripts/test-v333-image-ocr-correction-cancel-focus-contract.py"
        new = "python3 -B scripts/test-v334-image-focus-preview-correction-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v334-image-focus-preview-correction-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
