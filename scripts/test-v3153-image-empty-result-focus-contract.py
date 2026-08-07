#!/usr/bin/env python3
"""Static contract for v3.153 empty translated image-result focus handoff."""

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


class ImageEmptyResultFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.inspector = braced_body(self.panel, "private var inspector: some View")

    def test_empty_result_has_stable_focus_identity(self) -> None:
        for marker in [
            'imageResultEmptyAccessibilityFocusID = "image-result-empty-state"',
            "title: imageResultEmptyStateTitle",
            "detail: imageResultEmptyStateDetail",
            ".accessibilityFocused(",
            "Self.imageResultEmptyAccessibilityFocusID",
            "imageResultEmptyStateAccessibilityHint",
        ]:
            self.assertIn(marker, self.inspector if marker != 'imageResultEmptyAccessibilityFocusID = "image-result-empty-state"' else self.panel)

    def test_translated_empty_terminal_focus_prefers_actionable_empty_state(self) -> None:
        helper = braced_body(self.panel, "private func focusImageTranslationTerminalStateIfNeeded()")
        self.assertIn("store.imageTranslationBlocks.isEmpty", helper)
        self.assertIn("store.imageTranslationState == .translated", helper)
        self.assertIn("store.imageTranslationData != nil", helper)
        self.assertIn("Self.imageIgnoredBlocksEmptyAccessibilityFocusID", helper)
        self.assertIn("Self.imageResultEmptyAccessibilityFocusID", helper)
        self.assertIn("Self.imageTranslationStatusAccessibilityFocusID", helper)
        self.assertLess(
            helper.index("!store.imageTranslationIgnoredBlocks.isEmpty"),
            helper.index("Self.imageResultEmptyAccessibilityFocusID"),
        )

    def test_focus_handoff_remains_revision_scoped_and_view_only(self) -> None:
        helper = braced_body(self.panel, "private func focusImageTranslationTerminalStateIfNeeded()")
        for marker in [
            "let revision = store.imageTranslationRevision",
            "await Task.yield()",
            "revision == store.imageTranslationRevision",
        ]:
            self.assertIn(marker, helper)
        self.assertNotIn("imageResultEmptyAccessibilityFocusID", self.store)
        self.assertNotIn("imageTranslationBlocks =", helper)
        self.assertNotRegex(helper, r"(?<![=!])\bimageTranslationState\s*=\s*(?!=)")
        self.assertNotIn("runImageTranslation(", helper)

    def test_existing_rerun_action_and_visible_button_remain_gated(self) -> None:
        empty_branch = braced_body(self.inspector, "if store.imageTranslationBlocks.isEmpty")
        for marker in [
            "imageResultEmptyStateAccessibility(",
            "if store.canRerunImageRecognition",
            'title: "重新识别"',
        ]:
            self.assertIn(marker, empty_branch)
        self.assertIn('accessibilityAction(named: "重新识别")', self.panel)

    def test_version_and_ci_route_follow_v3152(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 153) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.152;", self.project)
        old = "scripts/test-v3152-image-empty-result-rerun-button-contract.py"
        new = "scripts/test-v3153-image-empty-result-focus-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(f"python3 -B {new}", self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {new}"))
        self.assertIn("15[3]", self.workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
