#!/usr/bin/env python3
"""Contract for returning VoiceOver focus to the source row after closing focus preview."""

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
                return source[brace : index + 1]
    raise AssertionError(f"unclosed body for {marker}")


class ImageFocusPreviewCloseFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
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

    def test_focus_close_uses_panel_focus_handoff_instead_of_dropping_focus(self) -> None:
        workspace = braced_body(self.panel, "private var imageWorkspace: some View")
        self.assertIn("clearSelection: closeImageTranslationFocusPreview", workspace)
        close = braced_body(
            self.panel,
            "private func closeImageTranslationFocusPreview()",
        )
        self.assertIn("guard let selectedImageTranslationBlockID else { return }", close)
        self.assertIn("self.selectedImageTranslationBlockID = nil", close)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: reviewRowAccessibilityFocusID(selectedImageTranslationBlockID))",
            close,
        )

    def test_focus_preview_close_remains_named_and_view_only(self) -> None:
        self.assertIn(
            'Button("关闭局部放大", systemImage: "xmark", action: close)',
            self.focus,
        )
        self.assertIn(".accessibilityFocused(", self.focus)
        self.assertIn("reviewRowAccessibilityFocusID", self.panel)
        self.assertNotIn("ImageTranslationFocusPreview", self.store)
        self.assertNotIn("VisionOCRService", self.preview)
        self.assertNotIn("VisionOCRService", self.focus)

    def test_version_and_ci_route_follow_v377(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3."), 2)
        self.assertNotIn("MARKETING_VERSION = 3.77;", self.project)
        old = "python3 -B scripts/test-v377-image-focus-preview-unavailable-voiceover-contract.py"
        new = "python3 -B scripts/test-v378-image-focus-preview-close-focus-contract.py"
        route = "grep -E '^scripts/test-v3(47|48|49|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|69|70|71|72|73|74|75|76|77|78|79|80)-.*-contract\\.py$'"
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))
        self.assertLess(self.workflow.index(route), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
