#!/usr/bin/env python3
"""Contract for v3.100 report-only per-block Koharu next-action context."""

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


class KoharuBlockNextActionContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")
        self.helper = braced_body(self.view, "private func mangaProbeBlockReportAction(")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_context_consumes_existing_report_only_ledgers(self) -> None:
        for marker in [
            "report.internalStructureBottleneckReport?.blockSummaries.first",
            "report.translationModelFloorComparisonReport?.noisyBlockSummaries.first",
            "report.koharuRenderSpriteFitPlannerReport?.blockLedgers.first",
            "report.koharuArtifactDAGReport?.blockTraces.first",
            "recommendedNextAction",
            "mangaProbeActionLabel",
        ]:
            self.assertIn(marker, self.helper)

    def test_context_is_report_only_and_keeps_artifact_gate_visible(self) -> None:
        for marker in [
            'return (action, "内部结构瓶颈")',
            'return (action, "模型底线对照")',
            'return (action, "覆盖布局规划")',
            'return (action, "Koharu 工件 DAG")',
            'Koharu 工件门：\\(gateAction)',
            'case "provideRealKoharuArtifact": "提供真实 Koharu 工件"',
        ]:
            self.assertIn(marker, self.view)
        for forbidden in ["TranslationSessionStore", "runMangaOverlayProbe", "groundTruth"]:
            self.assertNotIn(forbidden, self.helper)

    def test_row_exposes_next_action_visually_and_to_voiceover(self) -> None:
        for marker in [
            'Text("建议：\\(reportAction.localizedAction)")',
            'parts.append("报告下一步：\\(reportAction.summary)")',
            'let actionHint = reportAction.map { "报告下一步：\\($0.summary)" } ?? "报告没有块级下一步"',
            '此结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图',
        ]:
            self.assertIn(marker, self.row)

    def test_version_and_ci_route_follow_v399(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 100) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.99;", self.project)
        script = "scripts/test-v3100-koharu-block-next-action-context-contract.py"
        old = "python3 -B scripts/test-v399-koharu-block-risk-context-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
