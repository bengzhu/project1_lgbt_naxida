#!/usr/bin/env python3
"""Static contracts for v3.27 OCR correction reference context."""

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


class ImageOCRCorrectionReferenceContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.editor = braced_body(
            self.view,
            "private struct ImageOCRCorrectionSheet: View",
        )
        self.reference = braced_body(
            self.view,
            "private struct ImageOCRCorrectionReferencePreview: View",
        )

    def test_sheet_receives_only_the_current_image_data_for_a_view_local_reference(self) -> None:
        panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.assertIn("ImageOCRCorrectionSheet(", panel)
        self.assertIn("imageData: store.imageTranslationData", panel)
        self.assertIn("let imageData: Data?", self.editor)
        self.assertNotIn("ImageOCRCorrectionReferencePreview", self.store)

    def test_reference_uses_existing_downsample_service_and_preserves_a_visible_bbox(self) -> None:
        self.assertIn("await ImagePreviewService.makePreview(from: imageData)", self.reference)
        self.assertIn("ImageTranslationBlockFocusCrop.make(from: sourceImage, block: block)", self.reference)
        self.assertIn("ImageTranslationBlockFocusCrop.relativeBlockRect", self.reference)
        self.assertIn(".strokeBorder(Color.appWarning, lineWidth: 4)", self.reference)
        self.assertIn('accessibilityLabel("当前文字块图片局部")', self.reference)
        self.assertIn("请对照图片局部确认 OCR 原文", self.reference)

    def test_reference_loading_and_unavailable_states_do_not_block_manual_correction(self) -> None:
        self.assertIn("case loading", self.view)
        self.assertIn("case unavailable", self.view)
        self.assertIn("正在准备图片局部", self.reference)
        self.assertIn("图片局部预览不可用，仍可编辑 OCR 原文", self.reference)
        self.assertIn("guard let imageData, !imageData.isEmpty", self.reference)
        self.assertNotIn("VisionOCRService", self.reference)
        self.assertNotIn("correctImageTranslationBlock", self.reference)

    def test_editor_explains_reference_and_shared_review_reasons(self) -> None:
        self.assertIn('Section("图片对照")', self.editor)
        self.assertIn("ImageOCRCorrectionReferencePreview(imageData: imageData, block: block)", self.editor)
        self.assertIn("局部图只使用既有本地预览，不会重新识别图片", self.editor)
        self.assertIn('Section("复查提示")', self.editor)
        self.assertTrue(
            "ImageOCRResultSummary.hasLowConfidence(block)" in self.editor
            or "ImageOCRResultSummary.hasLowConfidence(reviewBlock)" in self.editor
        )
        self.assertTrue(
            "ImageOCRResultSummary.hasUnknownDirection(block)" in self.editor
            or "ImageOCRResultSummary.hasUnknownDirection(reviewBlock)" in self.editor
        )
        self.assertIn("保存只会重新翻译当前文字块，不会重新识别整张图片", self.editor)
        self.assertTrue(
            "ImageOCRResultSummary.requiresReview(block)" in self.editor
            or "ImageOCRResultSummary.requiresReview(reviewBlock)" in self.editor
        )

    def test_existing_focus_preview_reuses_the_shared_crop_geometry(self) -> None:
        focus = braced_body(self.view, "private struct ImageTranslationFocusPreview: View")
        self.assertIn("ImageTranslationBlockFocusCrop.make(from: sourceImage, block: block)", focus)
        self.assertIn("ImageTranslationBlockFocusCrop.relativeBlockRect(for: block, in: cropRect)", focus)

    def test_ci_runs_v327_after_v325_and_routes_a_contract_only_change(self) -> None:
        old = "python3 -B scripts/test-v325-image-ocr-correction-confirmation-action-contract.py"
        new = "python3 -B scripts/test-v327-image-ocr-correction-reference-context-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v327-image-ocr-correction-reference-context-contract.py' "
            "\"$RESULT_ROOT/changed-files.txt\" >/dev/null; then"
        )
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
