#!/usr/bin/env python3
"""Contract for v3.123 preserving VoiceOver focus across preview retry/failure."""

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


class ImagePreviewStatusFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.preview = braced_body(self.view, "private struct ImageTranslationPreview: View")

    def test_panel_uses_stable_status_focus_and_existing_generation(self) -> None:
        self.assertIn('imagePreviewStatusAccessibilityFocusID = "image-preview-status"', self.panel)
        self.assertIn("previewStatusAccessibilityFocusID: Self.imagePreviewStatusAccessibilityFocusID", self.panel)
        self.assertIn("focusPreviewStatus: {", self.panel)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imagePreviewStatusAccessibilityFocusID)",
            self.panel,
        )

    def test_preview_status_is_a_focusable_container(self) -> None:
        for marker in [
            "let previewStatusAccessibilityFocusID: String",
            "let focusPreviewStatus: () -> Void",
            ".accessibilityFocused(\n            accessibilityFocus,\n            equals: previewStatusAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.preview)

    def test_failure_and_retry_return_focus_to_status(self) -> None:
        failure = braced_body(self.preview, "guard let preview = await ImagePreviewService.makePreview")
        self.assertIn("previewPhase = .failed(revision: revision)", failure)
        self.assertIn("focusPreviewStatus()", failure)
        retry = braced_body(self.preview, "private func retryPreview")
        self.assertIn("previewPhase = .loading(revision: store.imageTranslationRevision)", retry)
        self.assertIn("previewAttempt += 1", retry)
        self.assertIn("focusPreviewStatus()", retry)

    def test_preview_focus_remains_view_only(self) -> None:
        self.assertNotIn("previewStatusAccessibilityFocusID", self.store)
        self.assertNotIn("focusPreviewStatus", self.store)
        self.assertNotIn("runBubbleFirstProbe", self.preview)

    def test_version_and_ci_route_follow_v3122(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 123) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.122;", self.project)
        script = "scripts/test-v3123-image-preview-status-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3122-image-cancel-status-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
