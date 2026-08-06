#!/usr/bin/env python3
"""Contract for v3.117 MangaProbe diagnostic filter expansion reset."""

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


class MangaDiagnosticFilterExpansionResetContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")

    def test_filter_change_resets_stale_expansion_before_focus_handoff(self) -> None:
        handler = braced_body(self.section, ".onChange(of: diagnosticFilter) { _, _ in")
        reset_index = handler.index("diagnosticExpansionResetID += 1")
        focus_index = handler.index("focusDiagnosticFilterResultIfNeeded()")
        self.assertLess(reset_index, focus_index)
        for marker in [
            "diagnosticExpansionResetID += 1",
            "focusDiagnosticFilterResultIfNeeded()",
            "expansionResetID: diagnosticExpansionResetID",
        ]:
            self.assertIn(marker, self.section)

    def test_reset_still_collapses_rows_without_stealing_shared_focus(self) -> None:
        for marker in [
            "let expansionResetID: Int",
            "@State private var isExpanded = false",
            "@State private var suppressNextExpansionFocusHandoff = false",
            ".onChange(of: expansionResetID)",
            "suppressNextExpansionFocusHandoff = true",
            "isExpanded = false",
            "requestAccessibilityFocus(",
        ]:
            self.assertIn(marker, self.row)
        self.assertNotIn("accessibilityFocus.wrappedValue =", self.row)

    def test_filter_reset_is_view_only_report_context(self) -> None:
        self.assertNotIn("diagnosticExpansionResetID", self.store)
        self.assertNotIn("diagnosticFilter", self.store)
        for forbidden in [
            "runMangaOverlayProbe()",
            "groundTruth",
            "probe_report.json",
        ]:
            self.assertNotIn(forbidden, self.row)

    def test_version_and_ci_route_follow_v3116(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 117) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.116;", self.project)
        script = "scripts/test-v3117-manga-diagnostic-filter-expansion-reset-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3116-manga-diagnostic-focus-generation-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
