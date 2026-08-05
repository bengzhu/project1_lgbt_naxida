#!/usr/bin/env python3
"""Contract for v3.99 report-only per-block Koharu risk context."""

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


class KoharuBlockRiskContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.row = braced_body(self.view, "private struct MangaProbeBlockRow: View")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_rows_receive_the_current_report_without_store_ownership(self) -> None:
        self.assertIn("MangaProbeBlockRow(block: block, report: store.mangaOverlayProbeReport)", self.view)
        self.assertIn("let report: MangaOverlayProbeReport?", self.row)
        self.assertNotIn("TranslationSessionStore", self.row)
        self.assertNotIn("runMangaOverlayProbe", self.row)
        self.assertNotIn("groundTruth", self.row)

    def test_row_risk_context_reuses_all_three_report_only_sets(self) -> None:
        for marker in [
            "mangaProbeOCRRiskBlockSet(report).contains(block.index)",
            "mangaProbeTranslationRiskBlockSet(report).contains(block.index)",
            "mangaProbeRenderRiskBlockSet(report).contains(block.index)",
            'labels.append("OCR")',
            'labels.append("翻译")',
            'labels.append("布局")',
            'private var reportRiskSummary: String',
        ]:
            self.assertIn(marker, self.row)

    def test_visual_and_voiceover_context_explain_report_only_scope(self) -> None:
        for marker in [
            'Text("风险：\\(reportRiskSummary)")',
            'parts.append("报告风险：\\(reportRiskSummary)")',
            '"报告风险标签：\\(reportRiskSummary)"',
            "此结果只属于漫画探针诊断，不会改变普通图片 OCR、翻译或覆盖图",
        ]:
            self.assertIn(marker, self.row)

    def test_version_and_ci_route_follow_v398(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 99) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.98;", self.project)
        script = "scripts/test-v399-koharu-block-risk-context-contract.py"
        old = "python3 -B scripts/test-v398-koharu-diagnostic-risk-union-contract.py"
        new = f"python3 -B {script}"
        self.assertIn(script, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
