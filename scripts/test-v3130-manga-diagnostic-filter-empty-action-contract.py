#!/usr/bin/env python3
"""Contract for v3.130 actionable empty manga diagnostic filter state."""

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


class MangaDiagnosticFilterEmptyActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.section = braced_body(self.view, "private struct MangaProbeSection: View")
        self.empty_filter = braced_body(
            self.section,
            "else if store.mangaOverlayProbeReport != nil, filteredProbeBlocks.isEmpty",
        )

    def test_filtered_empty_state_has_visible_and_voiceover_recovery_actions(self) -> None:
        self.assertIn("VStack(spacing: AppTheme.Spacing.control)", self.empty_filter)
        self.assertIn("AppSecondaryButton", self.empty_filter)
        self.assertIn('title: "显示全部诊断"', self.empty_filter)
        self.assertIn("action: showAllDiagnosticResults", self.empty_filter)
        self.assertIn('.accessibilityAction(named: "显示全部诊断")', self.empty_filter)
        self.assertIn("Self.diagnosticFilterEmptyAccessibilityFocusID", self.empty_filter)

    def test_empty_state_preserves_historical_context_and_direct_recovery(self) -> None:
        for marker in [
            'title: "当前诊断筛选没有结果"',
            "切换到全部或其他诊断类别查看逐块报告",
            "显示全部诊断",
            "diagnosticFilterEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.empty_filter)

    def test_recovery_only_changes_view_filter_and_reuses_existing_change_path(self) -> None:
        helper = braced_body(self.section, "private func showAllDiagnosticResults")
        self.assertIn("guard diagnosticFilter != .all else { return }", helper)
        self.assertIn("diagnosticFilter = .all", helper)
        self.assertNotIn("store.", helper)
        self.assertNotIn("runMangaOverlayProbe", helper)
        self.assertNotIn("showAllDiagnosticResults", self.store)
        self.assertIn(".onChange(of: diagnosticFilter)", self.section)

    def test_probe_empty_state_and_filtered_empty_state_remain_distinct(self) -> None:
        probe_empty_index = self.section.index("store.mangaOverlayProbeBlocks.isEmpty")
        filter_empty_index = self.section.index(
            "else if store.mangaOverlayProbeReport != nil, filteredProbeBlocks.isEmpty"
        )
        rows_index = self.section.index("ForEach(filteredProbeBlocks)")
        self.assertLess(probe_empty_index, filter_empty_index)
        self.assertLess(filter_empty_index, rows_index)
        self.assertIn("本次探针未生成文字块", self.section)

    def test_version_and_ci_route_follow_v3129(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 130) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.129;", self.project)
        script = "scripts/test-v3130-manga-diagnostic-filter-empty-action-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3129-image-review-filter-empty-action-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))
        self.assertRegex(
            self.workflow,
            r"test-v3\(1\[1-9\]|\[2-7\]\[0-9\]|8\[01\]|12\[2-9\]|130\)-",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
