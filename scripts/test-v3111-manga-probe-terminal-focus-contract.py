#!/usr/bin/env python3
"""Contract for v3.111 manga probe report focus handoff."""

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


class MangaProbeTerminalFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")

    def test_report_terminal_focus_handles_blocks_and_empty_report(self) -> None:
        for marker in [
            'private static let diagnosticProbeEmptyAccessibilityFocusID = "manga-diagnostic-probe-empty"',
            ".onChange(of: store.mangaOverlayProbeReport)",
            "focusDiagnosticProbeResultIfNeeded()",
            "private func focusDiagnosticProbeResultIfNeeded()",
            "await Task.yield()",
            "diagnosticProbeEmptyAccessibilityFocusID",
            "filteredProbeBlocks.first",
            "diagnosticBlockAccessibilityFocusID(firstBlock.index)",
            "diagnosticFilterEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.section)

    def test_empty_probe_status_receives_focus_and_retry_context(self) -> None:
        for marker in [
            'accessibilityLabel("漫画探针未生成逐块诊断")',
            "emptyProbeBlocksDetail",
            "确认 test/1.png 与 Output 状态后重试",
            "Self.diagnosticProbeEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.section)

    def test_new_probe_still_clears_old_focus_before_report_focus(self) -> None:
        loading = braced_body(self.section, ".onChange(of: store.mangaOverlayProbeState)")
        self.assertIn("guard state == .loading else { return }", loading)
        self.assertIn("diagnosticFilter = .all", loading)
        self.assertIn("diagnosticAccessibilityFocusID = nil", loading)

    def test_focus_state_is_view_private(self) -> None:
        for marker in [
            "diagnosticProbeEmptyAccessibilityFocusID",
            "focusDiagnosticProbeResultIfNeeded",
            "diagnosticAccessibilityFocusID",
        ]:
            self.assertNotIn(marker, self.store)
        self.assertIn("@AccessibilityFocusState", self.section)

    def test_version_and_ci_route_follow_v3110(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 111) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.110;", self.project)
        script = "scripts/test-v3111-manga-probe-terminal-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3110-image-filter-focus-intent-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
