#!/usr/bin/env python3
"""Contract for exposing retained-output actions in the probe developer summary."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuRenderOutputSummaryActionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.service = read("AITRANS/Services/MangaOverlayProbeService.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_developer_summary_exposes_required_output_action_breakdown(self) -> None:
        self.assertIn(
            "let renderOutputActionBreakdown = Dictionary(",
            self.service,
        )
        self.assertIn(
            "grouping: (koharuRenderRegressionLockReport?.outputFileChecks ?? [])",
            self.service,
        )
        self.assertIn(".filter(\\.requiredInCIFast)", self.service)
        self.assertIn("by: \\.recommendedAction", self.service)
        self.assertIn('.map { "\\($0.key)=\\($0.value.count)" }', self.service)
        self.assertIn(
            'actionBreakdown=\\(renderOutputActionBreakdown.isEmpty ? "none" : renderOutputActionBreakdown)',
            self.service,
        )
        self.assertIn("outputFiles: corePresent=", self.service)
        self.assertIn("missing=\\(renderOutputMissing.isEmpty ? \"none\" : renderOutputMissing)", self.service)

    def test_version_and_ci_route_follow_v388(self) -> None:
        self.assertEqual(self.project.count("MARKETING_VERSION = 3.90;"), 2)
        self.assertNotIn("MARKETING_VERSION = 3.89;", self.project)
        old = "python3 -B scripts/test-v388-koharu-render-core-output-gate-action-contract.py"
        new = "python3 -B scripts/test-v389-koharu-render-output-summary-action-contract.py"
        route = "scripts/test-v(38(2-manga-render-newline|3-koharu-fit-budget|4-koharu-render-min-font|5-koharu-render-lock-min-font|6-koharu-render-output-ledger|7-koharu-render-output-action|8-koharu-render-core-output-gate-action|9-koharu-render-output-summary-action)|390-koharu-render-failure-overlay-compaction)-contract\\.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertIn(route, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
