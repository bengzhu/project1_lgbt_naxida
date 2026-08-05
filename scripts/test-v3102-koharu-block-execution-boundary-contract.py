#!/usr/bin/env python3
"""Contract for v3.102 report-only per-block Koharu execution boundaries."""

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


class KoharuBlockExecutionBoundaryContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.helper = braced_body(self.view, "private func mangaProbeBlockExecutionBoundary(")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_boundary_consumes_existing_execution_reports(self) -> None:
        for marker in [
            "koharuPipelineResolverReport?.blockTraces",
            "trace.recommendedExecutionItemID",
            "trace.canRunInCIFast",
            "trace.requiresFullProbe",
            "trace.requiresExternalArtifact",
            "koharuWorkOrderRouterReport?.blockRoutes",
            "route.primaryWorkOrderID",
            "workOrder.remainingBlockers",
            "koharuExternalArtifactRequestPacketReport?.blockRequests",
            "request.needsTextBoxes",
            "request.needsBubbleMask",
            "request.needsSegmentMask",
            "request.forbiddenLocalActions",
            "koharuNativeAlgorithmReplayMatrixReport?.blockRoutes",
            "replay.primaryReplayCandidateID",
            "replay.shadowOnlyAllowed",
        ]:
            self.assertIn(marker, self.helper)

    def test_boundary_is_shared_by_visual_and_voiceover_report_summary(self) -> None:
        for marker in [
            'parts.append("执行边界：\\(executionBoundary)")',
            'Text("边界：\\(executionBoundary)")',
            'parts.append("报告下一步：\\(reportAction.summary)")',
        ]:
            self.assertIn(marker, self.view)
        self.assertIn("executionBoundary = mangaProbeBlockExecutionBoundary", self.view)
        self.assertIn("executionBoundary != nil", self.view)

    def test_boundary_remains_report_only_without_store_or_ground_truth_ownership(self) -> None:
        for forbidden in ["TranslationSessionStore", "runMangaOverlayProbe", "groundTruth"]:
            self.assertNotIn(forbidden, self.helper)
        self.assertIn("diagnostic", self.view)

    def test_version_and_ci_route_follow_v3101(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 102) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.101;", self.project)
        script = "scripts/test-v3102-koharu-block-execution-boundary-contract.py"
        old = "python3 -B scripts/test-v3101-koharu-block-diagnostic-evidence-context-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
