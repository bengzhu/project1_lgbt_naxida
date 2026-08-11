#!/usr/bin/env python3
"""Static contracts for v3.23 confirmation before restoring image OCR."""

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


class ImageOCRRestoreConfirmationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")

    def test_restore_uses_a_view_private_optional_confirmation_target(self) -> None:
        self.assertIn(
            "@State private var restoreConfirmationBlock: ImageTranslationBlock?",
            self.view,
        )
        self.assertIn(
            '"恢复 Vision OCR？",\n            isPresented: isRestoreConfirmationPresented,',
            self.view,
        )
        self.assertIn("titleVisibility: .visible", self.view)
        self.assertNotIn("item: $restoreConfirmationBlock", self.view)

        presentation = braced_body(
            self.view,
            "private var isRestoreConfirmationPresented: Binding<Bool>",
        )
        self.assertIn("restoreConfirmationBlock != nil", presentation)
        self.assertIn("guard !isPresented else { return }", presentation)
        self.assertIn("restoreConfirmationBlock = nil", presentation)

    def test_row_requests_confirmation_instead_of_directly_restoring(self) -> None:
        inspector = braced_body(self.view, "private var inspector: some View")
        self.assertIn(
            "restoreVisionOCR: { requestVisionOCRRestore(for: block) }",
            inspector,
        )
        self.assertNotIn("restoreVisionOCR: { restoreVisionOCR(for: block.id) }", inspector)
        request = braced_body(
            self.view,
            "private func requestVisionOCRRestore(\n"
            "        for block: ImageTranslationBlock,\n"
            "        focusOrigin: ImageTranslationRestoreFocusOrigin",
        )
        self.assertIn("imageTranslationCorrectedBlockIDs.contains(block.id)", request)
        self.assertIn("canModifyImageTranslation", request)
        self.assertIn("restoreConfirmationBlock = block", request)
        self.assertNotIn("restoreImageTranslationBlockToVisionOCR", request)

    def test_only_destructive_confirmation_can_invoke_the_existing_restore_path(self) -> None:
        confirmation = braced_body(
            self.view,
            "private func confirmVisionOCRRestore(_ block: ImageTranslationBlock)",
        )
        self.assertIn(
            "guard restoreConfirmationBlock?.id == block.id,\n"
            "              restoreVisionOCR(for: block.id) else { return }",
            confirmation,
        )
        self.assertNotIn("restoreConfirmationBlock = nil", confirmation)
        self.assertIn('Button("恢复 Vision OCR", role: .destructive)', self.view)
        self.assertIn("guard let block = restoreConfirmationBlock else { return }", self.view)
        self.assertIn("confirmVisionOCRRestore(block)", self.view)
        self.assertIn('Button("取消", role: .cancel) {}', self.view)
        self.assertIn("这会移除本次人工修正，并恢复识别时的原文和初始译文。", self.view)

    def test_image_revision_clears_the_pending_confirmation(self) -> None:
        revision = braced_body(
            self.view,
            ".onChange(of: store.imageTranslationRevision)",
        )
        self.assertIn("restoreConfirmationBlock = nil", revision)

    def test_ci_runs_v323_after_v322(self) -> None:
        workflow = read(".github/workflows/ci-results.yml")
        old = "python3 -B scripts/test-v322-image-ocr-correction-restore-contract.py"
        new = "python3 -B scripts/test-v323-image-ocr-restore-confirmation-contract.py"
        self.assertIn(new, workflow)
        self.assertLess(workflow.index(old), workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
