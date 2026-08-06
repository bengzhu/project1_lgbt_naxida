#!/usr/bin/env python3
"""Contract for v3.126 VoiceOver focus on image export/share failures."""

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


class ImageExportShareFailureFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_share_failure_returns_focus_to_existing_status_row(self) -> None:
        handler = braced_body(self.panel, ".onChange(of: store.imageTranslationShareState)")
        self.assertIn("guard case .failed = state, state != oldState else { return }", handler)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)",
            handler,
        )

    def test_export_failure_returns_focus_to_existing_status_row(self) -> None:
        handler = braced_body(
            self.panel,
            ".onChange(of: store.imageTranslationExportRenderState)",
        )
        self.assertIn("guard case .failed = state, state != oldState else { return }", handler)
        self.assertIn(
            "moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)",
            handler,
        )

    def test_only_terminal_failures_trigger_the_handoff(self) -> None:
        for marker in [
            ".onChange(of: store.imageTranslationShareState)",
            ".onChange(of: store.imageTranslationExportRenderState)",
        ]:
            handler = braced_body(self.panel, marker)
            self.assertLess(
                handler.index("guard case .failed = state"),
                handler.index("moveReviewAccessibilityFocus"),
            )
        self.assertIn("case .preparing", self.view)
        self.assertIn("case .rendering", self.view)

    def test_focus_remains_view_only_and_reuses_existing_state_machine(self) -> None:
        self.assertNotIn("imageTranslationStatusAccessibilityFocusID", self.store)
        self.assertIn("moveReviewAccessibilityFocus(to: Self.imageTranslationStatusAccessibilityFocusID)", self.panel)
        self.assertNotIn("runBubbleFirstProbe", self.panel)

    def test_version_and_ci_route_follow_v3125(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 126) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.125;", self.project)
        script = "scripts/test-v3126-image-export-share-failure-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3125-image-direct-failure-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-6\]\)-",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
