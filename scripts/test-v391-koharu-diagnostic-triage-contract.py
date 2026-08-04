#!/usr/bin/env python3
"""Contract for report-only manga probe diagnostic triage in the developer console."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class KoharuDiagnosticTriageContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_summary_routes_existing_report_signals_without_new_state(self) -> None:
        self.assertIn("MangaProbeDiagnosticTriageSummary(report: report)", self.view)
        self.assertIn("translationModelFloorComparisonReport", self.view)
        self.assertIn("noisyOCRSuspectBlocks", self.view)
        self.assertIn("noisyModelFloorBlocks", self.view)
        self.assertIn("noisyTranslationLanguageQualityBlocks", self.view)
        self.assertIn("renderCollisionUnresolvedBlocks", self.view)
        self.assertIn("renderMinFontSizeReachedBlocks", self.view)
        self.assertIn("renderTextTruncatedBlocks", self.view)
        self.assertIn("floorVerdict=", self.view)
        self.assertIn("variantPassRate=", self.view)
        self.assertIn("passRateDelta=", self.view)
        self.assertIn("diagnosticOnly=", self.view)
        self.assertIn("wouldChangeMainFlow=", self.view)
        self.assertIn("mainFlowChanged=false", self.view)
        self.assertIn("提供真实 Koharu 四件套", self.view)

    def test_summary_is_accessible_and_explicitly_report_only(self) -> None:
        self.assertIn('.accessibilityLabel("漫画探针诊断分流")', self.view)
        self.assertIn(".accessibilityValue(accessibilityValue)", self.view)
        self.assertIn("这是只读的漫画探针诊断分流", self.view)
        self.assertIn("不会修改普通图片 OCR、翻译 prompt、模型或覆盖图", self.view)
        self.assertIn("diagnosticRouteLabel", self.view)
        self.assertIn("OCR 疑似损坏", self.view)
        self.assertIn("模型输出失败", self.view)
        self.assertIn("译文质量失败", self.view)
        self.assertIn("当前分流为 \\(diagnosticRouteLabel)", self.view)

    def test_version_and_ci_route_follow_v390(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 91) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.90;", self.project)
        self.assertIn(
            "scripts/test-v391-koharu-diagnostic-triage-contract.py",
            self.workflow,
        )
        old = "python3 -B scripts/test-v390-koharu-render-failure-overlay-compaction-contract.py"
        new = "python3 -B scripts/test-v391-koharu-diagnostic-triage-contract.py"
        self.assertIn(old, self.workflow)
        self.assertIn(new, self.workflow)
        self.assertLess(self.workflow.index(old), self.workflow.index(new))


if __name__ == "__main__":
    unittest.main(verbosity=2)
