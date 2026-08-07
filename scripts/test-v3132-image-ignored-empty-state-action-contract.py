#!/usr/bin/env python3
"""Contract for v3.132 actionable all-ignored image OCR empty state."""

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


class ImageIgnoredEmptyStateActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.ignored_empty = braced_body(
            self.inspector,
            "else if !store.imageTranslationIgnoredBlocks.isEmpty",
        )
        self.ignored_section = braced_body(
            self.panel,
            "if !store.imageTranslationIgnoredBlocks.isEmpty {\n                AppSectionHeader",
        )

    def test_all_ignored_empty_state_is_self_describing_and_actionable(self) -> None:
        for marker in [
            'title: "当前没有保留文字块"',
            "store.imageTranslationIgnoredBlocks.count",
            'accessibilityLabel("当前没有保留文字块")',
            'accessibilityValue(',
            'imageIgnoredBlocksEmptyAccessibilityFocusID',
            '.accessibilityAction(named: "恢复全部")',
            "requestRestoreAllIgnoredImageTranslationBlocks()",
            'action: requestRestoreAllIgnoredImageTranslationBlocks',
            ".disabled(!canModifyImageTranslation)",
            "imageModificationUnavailableDetail",
        ]:
            self.assertIn(marker, self.ignored_empty)

    def test_partial_ignore_section_keeps_one_visible_bulk_action(self) -> None:
        self.assertIn("if !store.imageTranslationBlocks.isEmpty", self.ignored_section)
        self.assertIn('title: "恢复全部 \\(store.imageTranslationIgnoredBlocks.count)"', self.ignored_section)
        self.assertIn("ForEach(store.imageTranslationIgnoredBlocks)", self.ignored_section)

    def test_last_single_ignore_moves_focus_to_actionable_empty_state(self) -> None:
        ignore = braced_body(self.panel, "private func ignoreImageTranslationBlock")
        for marker in [
            "if store.imageTranslationBlocks.isEmpty",
            "selectedImageTranslationBlockID = nil",
            "moveReviewAccessibilityFocusAfterCorrectionSheetDismissal(",
            "Self.imageIgnoredBlocksEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, ignore)

    def test_terminal_focus_preserves_empty_state_context(self) -> None:
        terminal = braced_body(
            self.panel,
            "private func focusImageTranslationTerminalStateIfNeeded",
        )
        for marker in [
            "store.imageTranslationState == .translated",
            "store.imageTranslationData != nil",
            "!store.imageTranslationIgnoredBlocks.isEmpty",
            "Self.imageIgnoredBlocksEmptyAccessibilityFocusID",
            "Self.imageTranslationStatusAccessibilityFocusID",
        ]:
            self.assertIn(marker, terminal)

    def test_focus_identity_is_view_private_and_no_store_pipeline_change(self) -> None:
        self.assertIn(
            'private static let imageIgnoredBlocksEmptyAccessibilityFocusID = "image-ignored-blocks-empty"',
            self.panel,
        )
        self.assertNotIn("imageIgnoredBlocksEmptyAccessibilityFocusID", self.store)
        self.assertNotIn("runImageTranslationPipeline", self.ignored_empty)

    def test_version_and_ci_route_follow_v3131(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 132) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.131;", self.project)
        script = "scripts/test-v3132-image-ignored-empty-state-action-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3131-image-ignored-blocks-bulk-restore-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertTrue(
            "13[0-2]" in self.workflow or "13[0-3]" in self.workflow
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
