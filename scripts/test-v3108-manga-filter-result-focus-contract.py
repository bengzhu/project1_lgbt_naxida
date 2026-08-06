#!/usr/bin/env python3
"""Contract for v3.108 focus handoff to the first manga diagnostic result."""

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


class MangaFilterResultFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")

    def test_filter_change_focuses_first_visible_result(self) -> None:
        for marker in [
            "focusDiagnosticFilterResultIfNeeded()",
            "diagnosticBlockAccessibilityFocusID(filteredProbeBlocks[0].index)",
            "accessibilityFocusID: diagnosticBlockAccessibilityFocusID(block.index)",
            "await Task.yield()",
            "diagnosticAccessibilityFocusID = focusID",
        ]:
            self.assertIn(marker, self.section)
        self.assertIn(
            ".accessibilityFocused(accessibilityFocus, equals: accessibilityFocusID)",
            self.row,
        )

    def test_empty_filter_fallback_remains_intact(self) -> None:
        helper = braced_body(self.section, "private func focusDiagnosticFilterResultIfNeeded()")
        self.assertIn("filteredProbeBlocks.isEmpty", helper)
        self.assertIn("focusEmptyDiagnosticStateIfNeeded()", helper)
        self.assertIn("diagnosticFilterEmptyAccessibilityFocusID", self.section)

    def test_focus_is_view_private(self) -> None:
        for marker in [
            "diagnosticAccessibilityFocusID",
            "diagnosticBlockAccessibilityFocusID",
            "accessibilityFocusID",
        ]:
            self.assertNotIn(marker, self.store)
        self.assertIn("@AccessibilityFocusState", self.section)

    def test_version_and_ci_route_follow_v3107(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 108) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.107;", self.project)
        script = "scripts/test-v3108-manga-filter-result-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3107-filter-empty-state-focus-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
