#!/usr/bin/env python3
"""Contract for v3.116 MangaProbeSection focus request arbitration."""

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


class MangaDiagnosticFocusGenerationContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")

    def test_latest_diagnostic_focus_request_wins(self) -> None:
        for marker in [
            "@State private var diagnosticAccessibilityFocusRequestID = 0",
            "private func moveDiagnosticAccessibilityFocus(to focusID: String?)",
            "diagnosticAccessibilityFocusRequestID &+= 1",
            "let requestID = diagnosticAccessibilityFocusRequestID",
            "await Task.yield()",
            "requestID == diagnosticAccessibilityFocusRequestID",
            "diagnosticAccessibilityFocusID = focusID",
        ]:
            self.assertIn(marker, self.section)

    def test_probe_reload_invalidates_old_focus_and_row_uses_shared_requester(self) -> None:
        loading_handler = braced_body(
            self.section,
            ".onChange(of: store.mangaOverlayProbeState) { _, state in",
        )
        self.assertIn("state == .loading", loading_handler)
        self.assertIn("diagnosticAccessibilityFocusRequestID &+= 1", loading_handler)
        self.assertIn("diagnosticAccessibilityFocusID = nil", loading_handler)
        self.assertIn("requestAccessibilityFocus: { focusID in", self.section)
        self.assertIn("let requestAccessibilityFocus: (String) -> Void", self.row)
        self.assertIn("requestAccessibilityFocus(", self.row)
        self.assertNotIn("accessibilityFocus.wrappedValue =", self.row)

    def test_focus_destinations_remain_view_only(self) -> None:
        for marker in [
            "diagnosticProbeEmptyAccessibilityFocusID",
            "diagnosticFilterEmptyAccessibilityFocusID",
            "diagnosticBlockAccessibilityFocusID",
            "focusDiagnosticFilterResultIfNeeded()",
            "focusDiagnosticProbeResultIfNeeded()",
        ]:
            self.assertIn(marker, self.section)
        self.assertNotIn("diagnosticAccessibilityFocusRequestID", self.store)
        self.assertNotIn("setMangaOverlayProbeFocus", self.store)

    def test_version_and_ci_route_follow_v3115(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 116) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.115;", self.project)
        script = "scripts/test-v3116-manga-diagnostic-focus-generation-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3115-image-focus-request-generation-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
