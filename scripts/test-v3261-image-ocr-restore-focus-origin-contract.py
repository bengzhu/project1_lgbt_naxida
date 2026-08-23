#!/usr/bin/env python3
"""Contract for preserving row/preview VoiceOver context after Vision OCR restore."""

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


class ImageOCRRestoreFocusOriginContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_origin_is_view_private_and_cleared_for_new_revision_or_dialog_dismissal(self) -> None:
        self.assertIn(
            "private enum ImageTranslationRestoreFocusOrigin: Equatable",
            self.panel,
        )
        self.assertIn(
            "@State private var imageTranslationRestoreFocusOrigin:\n"
            "        ImageTranslationRestoreFocusOrigin?",
            self.panel,
        )
        self.assertNotIn("imageTranslationRestoreFocusOrigin", self.store)
        revision = braced_body(self.panel, ".onChange(of: store.imageTranslationRevision)")
        self.assertIn("imageTranslationRestoreFocusOrigin = nil", revision)
        binding = braced_body(self.panel, "private var isRestoreConfirmationPresented: Binding<Bool>")
        self.assertIn("applyPendingRestoreConfirmationDismissalFocus()", binding)
        self.assertIn("imageTranslationRestoreFocusOrigin = nil", binding)

    def test_preview_and_row_requests_record_distinct_origins(self) -> None:
        workspace = braced_body(self.panel, "private var imageWorkspace")
        inspector = braced_body(self.panel, "private var inspector")
        self.assertIn(
            "requestVisionOCRRestore(for: $0, focusOrigin: .preview)",
            workspace,
        )
        self.assertIn(
            "restoreVisionOCR: { requestVisionOCRRestore(for: block) }",
            inspector,
        )
        wrapper = braced_body(
            self.panel,
            "private func requestVisionOCRRestore(for block: ImageTranslationBlock)",
        )
        self.assertIn("requestVisionOCRRestore(for: block, focusOrigin: .row)", wrapper)

    def test_confirmation_selects_preview_or_row_focus_after_successful_restore(self) -> None:
        request = self.panel[self.panel.index("private func requestVisionOCRRestore(\n") :]
        self.assertIn("imageTranslationRestoreFocusOrigin = focusOrigin", request)
        confirmation = braced_body(
            self.panel,
            "private func confirmVisionOCRRestore(_ block: ImageTranslationBlock)",
        )
        self.assertIn("let focusID = restoreConfirmationFocusID(", confirmation)
        self.assertIn("origin: imageTranslationRestoreFocusOrigin ?? .row", confirmation)
        self.assertIn("moveReviewAccessibilityFocusAfterRestoreConfirmationDismissal(", confirmation)
        self.assertIn("to: focusID", confirmation)
        self.assertNotIn("moveReviewAccessibilityFocus(to:", confirmation)
        focus = braced_body(self.panel, "private func restoreConfirmationFocusID(")
        self.assertIn("visibleImageTranslationBlocks.contains(where: { $0.id == blockID })", focus)
        self.assertIn("selectedImageTranslationBlockID = nil", focus)
        self.assertIn("return reviewFocusIDAfterHiddenDirectionBlock()", focus)
        self.assertIn("? reviewPreviewAccessibilityFocusID(blockID)", focus)
        self.assertIn(": reviewRowAccessibilityFocusID(blockID)", focus)

    def test_existing_store_restore_remains_the_only_mutation_path(self) -> None:
        action = braced_body(self.panel, "private func restoreVisionOCR(for blockID: UUID)")
        self.assertIn("store.restoreImageTranslationBlockToVisionOCR(blockID)", action)
        self.assertIn("selectedImageTranslationBlockID = blockID", action)
        self.assertNotIn("VisionOCRService", action)
        self.assertNotIn("runImageTranslationPipeline", action)

    def test_version_and_ci_route_follow_v3260(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(versions, ["3.333", "3.333"])
        old = "scripts/test-v3260-koharu-manga-ocr-rgb-luma-contract.py"
        new = "scripts/test-v3261-image-ocr-restore-focus-origin-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        route = (
            "if grep -Fx 'scripts/test-v3261-image-ocr-restore-focus-origin-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(route, self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
