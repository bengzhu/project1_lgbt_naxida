#!/usr/bin/env python3
"""Contract for v3.115 image review VoiceOver focus request arbitration."""

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


class ImageFocusRequestGenerationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.panel = braced_body(self.view, "struct ImageTranslationPanel: View")

    def test_latest_focus_request_wins_within_one_revision(self) -> None:
        for marker in [
            "@State private var reviewAccessibilityFocusRequestID = 0",
            "reviewAccessibilityFocusRequestID &+= 1",
            "private func moveReviewAccessibilityFocus(to focusID: String?)",
            "let revision = store.imageTranslationRevision",
            "let requestID = reviewAccessibilityFocusRequestID",
            "await Task.yield()",
            "revision == store.imageTranslationRevision",
            "requestID == reviewAccessibilityFocusRequestID",
            "reviewAccessibilityFocusID = focusID",
        ]:
            self.assertIn(marker, self.panel)

    def test_revision_change_invalidates_pending_focus_without_store_state(self) -> None:
        revision_handler = braced_body(self.panel, ".onChange(of: store.imageTranslationRevision) { _, _ in")
        self.assertIn("reviewAccessibilityFocusRequestID &+= 1", revision_handler)
        self.assertIn("reviewAccessibilityFocusID = nil", revision_handler)
        self.assertNotIn("reviewAccessibilityFocusRequestID", self.store)
        for forbidden in [
            "focusRequestID",
            "setImageTranslationFocus",
        ]:
            self.assertNotIn(forbidden, self.store)

    def test_focus_destinations_remain_view_only(self) -> None:
        for marker in [
            "reviewRowAccessibilityFocusID",
            "reviewPreviewAccessibilityFocusID",
            "reviewFilterEmptyAccessibilityFocusID",
            "imageTranslationStatusAccessibilityFocusID",
            "focusImageTranslationTerminalStateIfNeeded()",
        ]:
            self.assertIn(marker, self.panel)

    def test_version_and_ci_route_follow_v3114(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 115) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.114;", self.project)
        script = "scripts/test-v3115-image-focus-request-generation-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3114-manga-diagnostic-expansion-state-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
