#!/usr/bin/env python3
"""Contract for v3.106 dynamic filter counts in VoiceOver context."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class FilterAccessibilityContextContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.image_view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.developer_view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")

    def test_image_filter_reads_current_scope_counts_and_review_progress(self) -> None:
        self.assertIn('.pickerStyle(.segmented)\n                .accessibilityValue(reviewFilterAccessibilityValue)', self.image_view)
        self.assertIn("private var reviewFilterAccessibilityValue", self.image_view)
        for marker in [
            '"当前：\\(reviewFilter.rawValue)"',
            '"显示 \\(visibleImageTranslationBlocks.count) 个，共 \\(store.imageTranslationBlocks.count) 个文字块"',
            '"复查已完成 \\(reviewCompletedBlockCount) 个，剩余 \\(reviewRequiredBlocks.count) 个"',
        ]:
            self.assertIn(marker, self.image_view)

    def test_manga_filter_reads_selected_and_total_counts(self) -> None:
        self.assertIn('private var selectedBlockCount: Int', self.developer_view)
        self.assertIn('blocks.count(where: { selection.matches($0, report: report) })', self.developer_view)
        self.assertIn(
            '"当前：\\(selection.rawValue)，显示 \\(selectedBlockCount) 个，共 \\(blocks.count) 个文字块"',
            self.developer_view,
        )

    def test_context_remains_view_only(self) -> None:
        self.assertIn('@State private var reviewFilter: ImageOCRReviewFilter = .all', self.image_view)
        self.assertNotIn("reviewFilter", self.store)
        self.assertNotIn("selectedBlockCount", self.store)
        self.assertIn("reviewFilterAccessibilityHint", self.image_view)
        self.assertIn("只筛选下方逐块诊断结果，不修改 probe_report", self.developer_view)

    def test_version_and_ci_route_follow_v3105(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 106) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.105;", self.project)
        script = "scripts/test-v3106-filter-accessibility-context-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3105-koharu-convergence-overview-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
