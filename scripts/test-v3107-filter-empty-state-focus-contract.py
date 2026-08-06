#!/usr/bin/env python3
"""Contract for v3.107 VoiceOver focus handoff to empty filter states."""

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


class FilterEmptyStateFocusContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.image_view = read("AITRANS/Views/ImageTranslationViews.swift")
        self.developer_view = read("AITRANS/Views/DeveloperConsoleView.swift")
        self.store = read("AITRANS/Services/TranslationSessionStore.swift")
        self.project = read("AITRANS.xcodeproj/project.pbxproj")
        self.workflow = read(".github/workflows/ci-results.yml")
        self.image_panel = braced_body(self.image_view, "struct ImageTranslationPanel: View")
        self.manga_section = braced_body(self.developer_view, "private struct MangaProbeSection: View")

    def test_image_empty_filter_state_is_focusable_and_actionable(self) -> None:
        for marker in [
            'private static let reviewFilterEmptyAccessibilityFocusID = "image-review-filter-empty"',
            "focusEmptyReviewStateIfNeeded()",
            'accessibilityLabel("当前图片筛选没有结果")',
            "reviewFilterEmptyStateAccessibilityValue",
            '切换上方识别结果筛选，或回到全部查看当前图片的文字块',
            "Self.reviewFilterEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.image_panel)
        self.assertIn("visibleImageTranslationBlocks.isEmpty", self.image_panel)
        self.assertIn("reviewFilter == .needsReview && reviewCompletedBlockCount > 0", self.image_panel)

    def test_manga_empty_filter_state_is_focusable_and_actionable(self) -> None:
        for marker in [
            '@AccessibilityFocusState private var diagnosticAccessibilityFocusID: String?',
            'private static let diagnosticFilterEmptyAccessibilityFocusID = "manga-diagnostic-filter-empty"',
            'accessibilityLabel("当前漫画诊断筛选没有结果")',
            '切换到全部或其他诊断类别查看逐块报告',
            "focusEmptyDiagnosticStateIfNeeded()",
            "Self.diagnosticFilterEmptyAccessibilityFocusID",
        ]:
            self.assertIn(marker, self.manga_section)
        self.assertIn("filteredProbeBlocks.isEmpty", self.manga_section)
        self.assertIn("await Task.yield()", self.manga_section)

    def test_focus_state_is_view_private(self) -> None:
        for marker in [
            "reviewFilterEmptyAccessibilityFocusID",
            "reviewFilterEmptyStateAccessibilityValue",
            "diagnosticAccessibilityFocusID",
            "diagnosticFilterEmptyAccessibilityFocusID",
        ]:
            self.assertNotIn(marker, self.store)
        self.assertIn(".onChange(of: reviewFilter)", self.image_panel)
        self.assertIn(".onChange(of: diagnosticFilter)", self.manga_section)

    def test_version_and_ci_route_follow_v3106(self) -> None:
        versions = re.findall(r"MARKETING_VERSION = (3\.\d+);", self.project)
        self.assertEqual(len(versions), 2)
        self.assertTrue(all(tuple(map(int, version.split("."))) >= (3, 107) for version in versions))
        self.assertNotIn("MARKETING_VERSION = 3.106;", self.project)
        script = "scripts/test-v3107-filter-empty-state-focus-contract.py"
        self.assertIn(script, self.workflow)
        self.assertIn(f"python3 -B {script}", self.workflow)
        old = "scripts/test-v3106-filter-accessibility-context-contract.py"
        self.assertLess(self.workflow.index(old), self.workflow.index(f"python3 -B {script}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
