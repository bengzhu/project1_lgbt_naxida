#!/usr/bin/env python3
"""Contract for v3.104 report-only Koharu convergence block context."""

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


class KoharuConvergenceContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.helper = braced_body(self.view, "private func mangaProbeConvergenceContext(")
        self.action = braced_body(self.view, "private func mangaProbeBlockReportAction(")
        self.promotion = braced_body(self.view, "private func mangaProbePromotionBoundary(")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_context_consumes_existing_block_paths_and_work_item_execution_fields(self) -> None:
        for marker in [
            "report.koharuArtifactConvergenceReport",
            "convergence.blockPaths.first",
            "convergence.workItemLedger.filter",
            "path.firstBlockingArtifact",
            "path.primaryStructuralBottleneck",
            "path.needsRealArtifact",
            "path?.openWorkItems",
            "path.primaryNextAction",
            "$0.targetBlocks",
            "$0.remainingBlockers",
            "$0.canRunInCIFast",
            "$0.requiresFullProbe",
            "$0.requiresExternalArtifact",
        ]:
            self.assertIn(marker, self.helper)

    def test_convergence_context_is_shared_by_action_summary_visual_and_voiceover(self) -> None:
        for marker in [
            "let convergenceContext = mangaProbeConvergenceContext",
            "convergenceContext != nil",
            'parts.append("Koharu 收敛：\\(convergenceContext.summary)")',
            'Text("收敛：\\(convergenceContext.summary)")',
            'append("收敛动作：" + action)',
        ]:
            self.assertIn(marker, self.view)
        self.assertIn("convergence.openWorkItems", self.promotion)
        self.assertIn("reportOnly = true", self.promotion)

    def test_open_convergence_work_items_cannot_be_reported_as_success_only(self) -> None:
        self.assertIn("if convergence.diagnosticOnly || !convergence.wouldChangeMainFlow", self.promotion)
        self.assertIn("if !convergence.openWorkItems.isEmpty", self.promotion)
        self.assertIn("nextAction = nextAction ?? mangaProbeActionLabel(workItem.nextAction)", self.promotion)

    def test_context_remains_report_only_without_store_probe_or_ground_truth_ownership(self) -> None:
        for forbidden in ["TranslationSessionStore", "runMangaOverlayProbe", "groundTruth"]:
            self.assertNotIn(forbidden, self.helper)
        self.assertIn("diagnosticOnly", self.helper)
        self.assertIn("wouldChangeMainFlow", self.helper)

    def test_version_and_ci_route_follow_v3103(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 104) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.103;", self.project)
        script = "scripts/test-v3104-koharu-convergence-context-contract.py"
        old = "python3 -B scripts/test-v3103-koharu-promotion-boundary-context-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
