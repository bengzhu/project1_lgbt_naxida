#!/usr/bin/env python3
"""Contract for v3.122 returning VoiceOver focus after image cancellation."""

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


class ImageCancelStatusFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_running_to_idle_returns_focus_to_status(self) -> None:
        state_change = braced_body(self.panel, ".onChange(of: store.imageTranslationState)")
        self.assertIn("oldState, state", state_change)
        self.assertIn("if state == .idle", state_change)
        for state in [".loading", ".recognizing", ".translating"]:
            self.assertIn(state, state_change)
        self.assertIn("pendingImageTranslationTerminalFocusRevision = nil", state_change)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)",
            state_change,
        )

    def test_idle_focus_does_not_replace_existing_terminal_focus(self) -> None:
        state_change = braced_body(self.panel, ".onChange(of: store.imageTranslationState)")
        idle_branch = braced_body(state_change, "if state == .idle")
        self.assertIn("case .idle, .translated, .failed:", idle_branch)
        self.assertIn("break", idle_branch)
        self.assertIn("guard state == .translated || state == .failed else { return }", state_change)
        self.assertIn("focusImageTranslationTerminalStateIfNeeded()", state_change)

    def test_focus_reuses_view_generation_without_store_changes(self) -> None:
        self.assertNotIn("imageTranslationStatusAccessibilityFocusID", self.store)
        self.assertIn("moveReviewAccessibilityFocus", self.panel)
        self.assertIn("reviewAccessibilityFocusRequestID", self.panel)
        self.assertNotIn("runBubbleFirstProbe", self.panel)

    def test_version_and_ci_route_follow_v3121(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 122) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.121;", self.project)
        script = "scripts/test-v3122-image-cancel-status-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3121-image-status-retry-accessibility-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
