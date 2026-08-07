#!/usr/bin/env python3
"""Static contracts for v3.148 gating the all-ignored empty-state action."""

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


class ImageIgnoredEmptyStateActionGateContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")
        self.empty_state = braced_body(
            self.panel,
            "private func allIgnoredBlocksEmptyStateAccessibility<Content: View>",
        )

    def test_all_ignored_empty_state_action_is_only_exposed_when_editing_is_available(self) -> None:
        empty_branch = self.inspector[
            self.inspector.index("else if !store.imageTranslationIgnoredBlocks.isEmpty"):
            self.inspector.index("} else {", self.inspector.index("else if !store.imageTranslationIgnoredBlocks.isEmpty"))
        ]
        self.assertIn("allIgnoredBlocksEmptyStateAccessibility(", empty_branch)
        self.assertIn(".accessibilityFocused(", empty_branch)
        self.assertIn("if canModifyImageTranslation", self.empty_state)
        self.assertIn('.accessibilityAction(named: "恢复全部")', self.empty_state)
        self.assertIn("requestRestoreAllIgnoredImageTranslationBlocks()", self.empty_state)
        locked_branch = self.empty_state[self.empty_state.index("else"):]
        self.assertNotIn('.accessibilityAction(named: "恢复全部")', locked_branch)

    def test_locked_empty_state_keeps_context_and_visible_button_boundary(self) -> None:
        empty_branch = self.inspector[
            self.inspector.index("else if !store.imageTranslationIgnoredBlocks.isEmpty"):
            self.inspector.index("} else {", self.inspector.index("else if !store.imageTranslationIgnoredBlocks.isEmpty"))
        ]
        for marker in [
            'accessibilityLabel("当前没有保留文字块")',
            "store.imageTranslationIgnoredBlocks.count",
            "imageModificationUnavailableDetail",
            'title: "恢复全部 \\(store.imageTranslationIgnoredBlocks.count)"',
            ".disabled(!canModifyImageTranslation)",
            "requestRestoreAllIgnoredImageTranslationBlocks",
        ]:
            self.assertIn(marker, empty_branch)

    def test_helper_is_view_only_and_keeps_confirmation_callback(self) -> None:
        for forbidden in [
            "store.",
            "imageTranslationBlocks =",
            "TranslationSessionStore(",
            "VisionOCRService",
            "persist(",
            "groundTruth",
        ]:
            self.assertNotIn(forbidden, self.empty_state)
        self.assertIn("showRestoreAllIgnoredConfirmation = true", self.panel)

    def test_version_and_ci_route_follow_v3147(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.148;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.147;", self.project)
        old = "python3 -B scripts/test-v3147-image-ocr-correction-input-accessibility-contract.py"
        new = "python3 -B scripts/test-v3148-image-ignored-empty-state-action-gate-contract.py"
        route = (
            "if grep -Fx 'scripts/test-v3148-image-ignored-empty-state-action-gate-contract.py' "
            '"$RESULT_ROOT/changed-files.txt" >/dev/null; then'
        )
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertIn(route, self.workflow)
        self.assertIn("14[8]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
