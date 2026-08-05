#!/usr/bin/env python3
"""Contract for v3.101 report-only per-block Koharu diagnosis evidence context."""

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


class KoharuBlockDiagnosticEvidenceContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")
        self.helper = braced_body(self.view, "private func mangaProbeBlockReportAction(")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_context_consumes_existing_bottleneck_and_gate_evidence(self) -> None:
        for marker in [
            "internalSummary.primaryBottleneck",
            "internalSummary.secondaryBottlenecks",
            "floorSummary.primaryBottleneckFromConvergence",
            "floorSummary.modelFloorLimited",
            "renderLedger.primaryRenderBottleneck",
            "renderLedger.fitVerdict",
            "trace.firstBlockingStage",
            "trace.firstBlockingReason",
            "mangaProbeDiagnosisSummary",
            "mangaProbeDiagnosisLabel",
        ]:
            self.assertIn(marker, self.helper)

    def test_diagnosis_remains_report_only_without_ground_truth_or_store_ownership(self) -> None:
        for marker in [
            'parts.append("依据：\\(diagnosis)")',
            'Text("依据：\\(diagnosis)")',
            'parts.append("报告下一步：\\(reportAction.summary)")',
            "Koharu 工件门：\\(gateAction)",
        ]:
            self.assertIn(marker, self.view)
        for forbidden in ["TranslationSessionStore", "runMangaOverlayProbe", "groundTruth"]:
            self.assertNotIn(forbidden, self.helper)

    def test_version_and_ci_route_follow_v3100(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 101) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.100;", self.project)
        script = "scripts/test-v3101-koharu-block-diagnostic-evidence-context-contract.py"
        old = "python3 -B scripts/test-v3100-koharu-block-next-action-context-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
