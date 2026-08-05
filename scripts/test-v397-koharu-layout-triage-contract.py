#!/usr/bin/env python3
"""Contract for exposing report-only render fit risks in the developer console."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuLayoutTriageContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_filter_and_triage_share_existing_fit_risk_signals(self) -> None:
        self.assertIn("private func mangaProbeRenderRiskBlockSet", self.view)
        self.assertIn("mangaProbeRenderRiskBlockSet(report).contains(block.index)", self.view)
        self.assertIn("private var renderBlocks: Set<Int>", self.view)
        self.assertIn("mangaProbeRenderRiskBlockSet(report)", self.view)
        for signal in (
            "fontBudgetRiskBlocks",
            "renderMinFontSizeReachedBlocks",
            "spriteContainmentRiskBlocks",
            "siblingOverlapRiskBlocks",
            "failureOverlayRiskBlocks",
            "renderIssueBlocks",
            "renderTextTruncatedBlocks",
        ):
            self.assertIn(f"fitPlanner.{signal}", self.view) if signal in {
                "fontBudgetRiskBlocks",
                "renderMinFontSizeReachedBlocks",
                "spriteContainmentRiskBlocks",
                "siblingOverlapRiskBlocks",
                "failureOverlayRiskBlocks",
            } else self.assertIn(f"renderLock.{signal}", self.view)

    def test_layout_filter_remains_read_only_report_only(self) -> None:
        self.assertIn("private enum MangaProbeDiagnosticFilter", self.view)
        self.assertIn("case .render:", self.view)
        self.assertIn("只筛选下方逐块诊断结果，不修改 probe_report", self.view)
        helper_start = self.view.index("private func mangaProbeRenderRiskBlockSet")
        helper_end = self.view.index("private struct MangaProbeDiagnosticFilterControl", helper_start)
        helper = self.view[helper_start:helper_end]
        self.assertNotIn("TranslationSessionStore", helper)
        self.assertNotIn("runMangaOverlayProbe", helper)

    def test_version_and_ci_route(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 97) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.96;", self.project)
        route = "scripts/test-v397-koharu-layout-triage-contract.py"
        self.assertIn(route, self.workflow)
        self.assertIn(f"python3 -B {route}", self.workflow)
        previous = "python3 -B scripts/test-v396-koharu-triage-tone-contract.py"
        self.assertIn(previous, self.workflow)
        self.assertLess(self.workflow.index(previous), self.workflow.index(f"python3 -B {route}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
