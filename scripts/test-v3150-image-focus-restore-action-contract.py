#!/usr/bin/env python3
"""Contract for a gated direct Vision OCR restore action on image focus previews."""

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


class ImageFocusPreviewRestoreActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.preview = braced_body(
            self.view,
            "private struct ImageTranslationPreview: View",
        )
        self.focus = braced_body(
            self.view,
            "private struct ImageTranslationFocusPreview: View",
        )
        self.modifier = braced_body(
            self.view,
            "private struct ImageFocusPreviewRestoreAccessibilityModifier",
        )

    def test_corrected_focus_preview_exposes_restore_action(self) -> None:
        self.assertIn("let isManuallyCorrected: Bool", self.focus)
        self.assertIn("let restoreVisionOCR: () -> Void", self.focus)
        self.assertIn("if isManuallyCorrected {", self.focus)
        self.assertIn(
            'Button("恢复 Vision OCR", systemImage: "arrow.counterclockwise", action: restoreVisionOCR)',
            self.focus,
        )
        self.assertIn(".disabled(!canEdit)", self.focus)
        self.assertIn("ImageFocusPreviewRestoreAccessibilityModifier", self.focus)
        self.assertIn("isManuallyCorrected: isManuallyCorrected", self.focus)
        self.assertIn("restoreVisionOCR: restoreVisionOCR", self.focus)

    def test_restore_action_is_gated_for_unmodified_or_locked_focus(self) -> None:
        self.assertIn("if isManuallyCorrected && canEdit", self.modifier)
        self.assertIn('.accessibilityAction(named: "恢复 Vision OCR")', self.modifier)
        action = braced_body(
            self.modifier,
            '.accessibilityAction(named: "恢复 Vision OCR")',
        )
        self.assertIn("restoreVisionOCR()", action)
        locked_branch = self.modifier[self.modifier.index("} else {") :]
        self.assertNotIn('.accessibilityAction(named: "恢复 Vision OCR")', locked_branch)

    def test_preview_wires_existing_confirmation_entry_and_context(self) -> None:
        self.assertIn(
            "isManuallyCorrected: store.imageTranslationCorrectedBlockIDs.contains(selectedBlock.id)",
            self.preview,
        )
        self.assertIn(
            "restoreVisionOCR: { requestVisionOCRRestore(for: selectedBlock) }",
            self.preview,
        )
        self.assertIn('.accessibilityLabel("已定位文字块局部放大")', self.focus)
        self.assertIn('.accessibilityValue("\\(positionText)，\\(accessibilityOriginalText)")', self.focus)
        self.assertIn("focusPreviewModificationHint", self.focus)
        self.assertIn("恢复当前文字块的 Vision OCR 原文与初始译文", self.focus)
        self.assertIn("可执行“恢复 Vision OCR”", self.focus)

    def test_restore_action_is_view_only_and_does_not_duplicate_pipeline(self) -> None:
        self.assertNotIn("ImageFocusPreviewRestoreAccessibilityModifier", self.store)
        self.assertNotIn("VisionOCRService", self.focus)
        self.assertNotIn("runImageTranslationPipeline", self.focus)
        self.assertNotIn("MangaOverlayProbeService", self.focus)

    def test_version_and_ci_route_follow_v3149(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertEqual(versions, ["3.150", "3.150"])
        self.assertNotIn("MARKETING_VERSION = 3.149;", self.project)
        old = "scripts/test-v3149-image-review-completion-action-gate-contract.py"
        new = "scripts/test-v3150-image-focus-restore-action-contract.py"
        self.assertIn(f"python3 -B {old}", self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(f"python3 -B {old}"), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("14[9]", self.workflow)
        self.assertIn("15[0]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
