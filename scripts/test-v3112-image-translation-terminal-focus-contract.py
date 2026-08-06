#!/usr/bin/env python3
"""Contract for v3.112 image OCR terminal VoiceOver focus handoff."""

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


class ImageTranslationTerminalFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_revision_scoped_terminal_focus_prefers_results_or_status(self) -> None:
        for marker in [
            'private static let imageTranslationStatusAccessibilityFocusID = "image-translation-status"',
            "@State private var pendingImageTranslationTerminalFocusRevision: Int?",
            ".onChange(of: store.imageTranslationRevision) { _, _ in",
            "pendingImageTranslationTerminalFocusRevision = store.imageTranslationRevision",
            ".onChange(of: store.imageTranslationState)",
            "state == .translated || state == .failed",
            "pendingImageTranslationTerminalFocusRevision == store.imageTranslationRevision",
            "focusImageTranslationTerminalStateIfNeeded()",
            "private func focusImageTranslationTerminalStateIfNeeded()",
            "let revision = store.imageTranslationRevision",
            "await Task.yield()",
            "revision == store.imageTranslationRevision",
            "store.imageTranslationBlocks.isEmpty",
            "Self.imageTranslationStatusAccessibilityFocusID",
            "focusReviewFilterResultIfNeeded()",
        ]:
            self.assertIn(marker, self.panel)

    def test_status_row_is_focusable_without_changing_ocr_actions(self) -> None:
        for marker in [
            'accessibilityLabel("图片翻译状态")',
            "imageStatusAccessibilityValue",
            "imageStatusAccessibilityHint",
            "Self.imageTranslationStatusAccessibilityFocusID",
            ".accessibilityFocused(",
        ]:
            self.assertIn(marker, self.panel)
        self.assertNotIn("pendingImageTranslationTerminalFocusRevision", self.store)

    def test_revision_reset_keeps_existing_filter_and_selection_cleanup(self) -> None:
        handler = braced_body(self.panel, ".onChange(of: store.imageTranslationRevision) { _, _ in")
        self.assertIn("prepareReviewFilterChange", handler)
        self.assertIn("selectedImageTranslationBlockID = nil", handler)
        self.assertIn("editingImageTranslationBlock = nil", handler)
        self.assertIn("reviewAccessibilityFocusID = nil", handler)

    def test_version_and_ci_route_follow_v3111(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 112) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.111;", self.project)
        script = "scripts/test-v3112-image-translation-terminal-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3111-manga-probe-terminal-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
