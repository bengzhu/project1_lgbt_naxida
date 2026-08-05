#!/usr/bin/env python3
"""Contract for v3.105 aggregate Koharu convergence overview context."""

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


class KoharuConvergenceOverviewContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.overview = braced_body(self.view, "private func mangaProbeConvergenceOverview(")
        self.triage = braced_body(self.view, "private struct MangaProbeDiagnosticTriageSummary: View")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_overview_consumes_existing_convergence_counts_and_boundaries(self) -> None:
        for marker in [
            "report.koharuArtifactConvergenceReport",
            "convergence.openWorkItems",
            "convergence.closedWorkItems",
            "convergence.stopWorkItems",
            "convergence.workItemStatusBreakdown",
            "convergence.blockPathCount",
            "convergence.workItemLedgerCount",
            "convergence.externalArtifactsRequiredForThisReport",
            "convergence.needsRealArtifactBlocks",
            "convergence.diagnosticOnly",
            "convergence.wouldChangeMainFlow",
        ]:
            self.assertIn(marker, self.overview)

    def test_overview_is_shared_by_status_copy_summary_and_voiceover(self) -> None:
        for marker in [
            "private var convergenceOverview: MangaProbeConvergenceOverview?",
            "convergenceOverview.map { \"收敛：\\($0.summary)。\" }",
            '"convergence=\\(convergenceOverview?.summary ?? "notAvailable")"',
            "private var accessibilityValue: String",
            "private var statusDetail: String",
        ]:
            self.assertIn(marker, self.triage)

    def test_open_or_blocked_convergence_cannot_be_success_toned(self) -> None:
        self.assertIn("if convergenceOverview?.isBlocked == true", self.triage)
        self.assertIn("convergenceOverview?.isReportOnly == true", self.triage)
        self.assertIn('return "Koharu 收敛待闭环"', self.triage)
        self.assertIn('return "Koharu 仅报告/预览"', self.triage)
        self.assertIn("return .warning", self.triage)

    def test_overview_is_report_only_without_store_probe_or_ground_truth_ownership(self) -> None:
        for forbidden in ["TranslationSessionStore", "runMangaOverlayProbe", "groundTruth"]:
            self.assertNotIn(forbidden, self.overview)
        self.assertIn("isReportOnly:", self.overview)

    def test_version_and_ci_route_follow_v3104(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 105) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.104;", self.project)
        script = "scripts/test-v3105-koharu-convergence-overview-contract.py"
        old = "python3 -B scripts/test-v3104-koharu-convergence-context-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
