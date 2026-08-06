#!/usr/bin/env python3
"""Contract for v3.125 VoiceOver focus on direct image failures without a new revision."""

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


class ImageDirectFailureFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")
        self.state_change = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationState)",
        )

    def test_direct_failed_transition_returns_focus_to_status(self) -> None:
        fallback = braced_body(self.state_change, "if state == .failed,")
        self.assertIn(
            "pendingImageTranslationTerminalFocusRevision != store.imageTranslationRevision",
            self.state_change,
        )
        self.assertIn(
            "pendingImageTranslationTerminalFocusRevision = nil",
            fallback,
        )
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)",
            fallback,
        )
        self.assertLess(
            self.state_change.index("if state == .failed,"),
            self.state_change.index(
                "guard state == .translated || state == .failed else { return }"
            ),
        )

    def test_revision_scoped_terminal_focus_remains_intact(self) -> None:
        self.assertIn(
            "guard pendingImageTranslationTerminalFocusRevision == store.imageTranslationRevision else { return }",
            self.state_change,
        )
        self.assertIn("focusImageTranslationTerminalStateIfNeeded()", self.state_change)

    def test_file_failure_is_direct_and_view_only_fallback_covers_it(self) -> None:
        file_handler = braced_body(self.store, "func handleSelectedImageFile")
        self.assertIn("imageTranslationState == .idle", file_handler)
        self.assertIn("imageTranslationData == nil", file_handler)
        self.assertIn("imageTranslationState = .failed", file_handler)
        self.assertNotIn("imageTranslationRevision += 1", file_handler)
        self.assertNotIn("imageTranslationStatusAccessibilityFocusID", self.store)

    def test_version_and_ci_route_follow_v3124(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 125) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.124;", self.project)
        script = "scripts/test-v3125-image-direct-failure-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3124-image-clear-empty-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-5\]\)-",
        )

    def test_failure_focus_remains_view_only(self) -> None:
        self.assertNotIn("runBubbleFirstProbe", self.panel)
        self.assertNotIn("imageTranslationStatusAccessibilityFocusID", self.store)


if __name__ == "__main__":
    unittest.main(verbosity=2)
